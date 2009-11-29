# Copyright (c) Zmanda, Inc.  All Rights Reserved.
#
# This library is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License version 2.1 as
# published by the Free Software Foundation.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this library; if not, write to the Free Software Foundation,
# Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA.
#
# Contact information: Zmanda Inc., 465 S. Mathilda Ave., Suite 300
# Sunnyvale, CA 94086, USA, or: http://www.zmanda.com

package Amanda::Changer::robot;

use strict;
use warnings;
use Carp;
use vars qw( @ISA );
@ISA = qw( Amanda::Changer );

use Data::Dumper;
use File::Path;
use Amanda::Paths;
use Amanda::MainLoop qw( :GIOCondition );
use Amanda::Config qw( :getconf );
use Amanda::Debug qw( debug warning );
use Amanda::Device qw( :constants );
use Amanda::Changer;
use Amanda::Constants;
use Amanda::MainLoop;

=head1 NAME

Amanda::Changer::robot -- control a physical tape changer

=head1 DESCRIPTION

This package controls a physical tape changer via 'mtx'.

See the amanda-changers(7) manpage for usage information.

=cut

# NOTES
#
# This is one of the more sophisticated changers.  Here are some notes that may
# help while reading the source code.

# STATE
#
# The device state is shared between all changers accessing the same library.
# It is a hash with keys:
#   slots - see below
#   drives - see below
#   drive_lru - recently used drives, least recent first
#   bc2lb - hash mapping known barcodes to known labels
#   current_slot - the current slot
#   last_operation_time - time the last operation finished
#   last_operation_delay - required delay for that operation
#   last_status - last time a 'status' command finished
#
# The 'slots' key is a hash, with slot numbers as keys and hashes
# as values.  Each slot's hash has keys
#   state - one of the SLOT_ constants, below
#   label - volume label, if known
#   barcode - volume barcode, if available
#   loaded_in - drive this volume is loaded in
#   ie - 1 if this is an import/export slot
# note that this state pretends that a tape physically located
# in a tape drive is still located in its original slot.
#
# The 'drives' key is also a hash by drive numbere, the values of
# which are hashes with keys
#   state - one of the SLOT_ constants, below
#   label - volume label
#   barcode - volume barcode
#   orig_slot - slot from which this tape was loaded

# LOCKING
#
# This package uses Amanda::Changer's with_locked_state to lock a statefile and
# load its contents.  Every time the state is locked, the package also
# considers running 'status' to update the state; the status_interval protects
# against running status too often.
#
# Each changer method has an "_unlocked" version that does the actual work, and
# is called with an additional 'state' parameter containing the locked state.
# This is particularly useful when the load method calls the eject method to
# empty a drive that it wants to use.

# RESERVATIONS
#
# Reservations are currently represented by a PID in the state file.  If that
# pid is no longer running, then the reservation is considered stale and is
# discarded (with a warning).
#
# Reservation objects defer most of the interesting operations back to the
# changer itself, since the operations require locked access to the state.

# INTERFACE
#
# All of the operating-system-specific functionality is abstracted into the
# Interface class.  This is written in such a way that it could be replaced
# by a direct SCSI interface.

# constants for the states that slots may be in; note that these states still
# apply even if the tape is actually loaded in a drive

# slot is known to contain no volume
use constant SLOT_EMPTY => 0;

# slot contains a volume, but who knows what
use constant SLOT_UNKNOWN => 1;

# slot contains an unlabled volume
use constant SLOT_UNLABELED => 2;

# slot contains a volume with a known label
use constant SLOT_LABELED => 3;

sub new {
    my $class = shift;
    my ($config, $tpchanger) = @_;
    my ($device_name) = ($tpchanger =~ /chg-robot:(.*)/);

    unless (-e $device_name) {
	return Amanda::Changer->make_error("fatal", undef,
	    message => "'$device_name' not found");
    }

    my $self = {
        interface => undef,
	device_name => $device_name,
        config => $config,

        # set below from properties
        statefile => undef,
        drive2device => {}, # { drive => device name }
	driveorder => [], # order of tape-device properties
	drive_choice => 'lru',
	eject_before_unload => 0,
	fast_search => 1,
	use_slots => undef,
	status_interval => 2, # in seconds
	load_poll => [0, 2, 120], # delay, poll, until
	eject_delay => 0, # in seconds
	unload_delay => 0, # in seconds
    };
    bless ($self, $class);

    # handle some config and properties
    my $properties = $config->{'properties'};

    if (defined $config->{'changerdev'} and $config->{'changerdev'} ne '') {
	return Amanda::Changer->make_error("fatal", undef,
	    message => "'changerdev' is not allowed with chg-robot");
    }

    if ($config->{'changerfile'}) {
        $self->{'statefile'} = Amanda::Config::config_dir_relative($config->{'changerfile'});
    } else {
        my $safe_filename = "chg-robot:$device_name";
        $safe_filename =~ tr/a-zA-Z0-9/-/cs;
        $safe_filename =~ s/^-*//;
        $self->{'statefile'} = "$libexecdir/lib/amanda/$safe_filename";
    }
    $self->_debug("using statefile '$self->{statefile}'");

    # figure out the drive number to device name mapping
    if (exists $config->{'tapedev'}
	    and $config->{'tapedev'} ne ''
	    and !exists $properties->{'tape-device'}) {
	# if the tapedev points to us (the changer), then give an error
	if ($config->{'tapedev'} =~ /^chg-robot:/) {
            return Amanda::Changer->make_error("fatal", undef,
                message => "must specify a tape-device property");
        }
        $self->{'drive2device'} = { '0' => $config->{'tapedev'} };
	push @{$self->{'driveorder'}}, '0';
    } else {
        if (!exists $properties->{'tape-device'}) {
            return Amanda::Changer->make_error("fatal", undef,
                message => "no 'tape-device' property specified");
        }
        for my $pval (@{$properties->{'tape-device'}->{'values'}}) {
            my ($drive, $device);
            unless (($drive, $device) = ($pval =~ /(\d+)=(.*)/)) {
                return Amanda::Changer->make_error("fatal", undef,
                    message => "invalid 'tape-device' property '$pval'");
            }
	    if (exists $self->{'drive2device'}->{$drive}) {
                return Amanda::Changer->make_error("fatal", undef,
                    message => "tape-device drive $drive defined more than once");
	    }
            $self->{'drive2device'}->{$drive} = $device;
	    push @{$self->{'driveorder'}}, $drive;
        }
    }

    # eject-before-unload
    my $ebu = $self->get_boolean_property($self->{'config'},
					    "eject-before-unload", 0);
    if (!defined $ebu) {
	return Amanda::Changer->make_error("fatal", undef,
	    message => "invalid 'eject-before-unload' value");
    }
    $self->{'eject_before_unload'} = $ebu;

    # fast-search
    my $fast_search = $self->get_boolean_property($self->{'config'},
						"fast-search", 1);
    if (!defined $fast_search) {
	return Amanda::Changer->make_error("fatal", undef,
	    message => "invalid 'fast-search' value");
    }
    $self->{'fast_search'} = $fast_search;

    # use-slots
    if (exists $properties->{'use-slots'}) {
	$self->{'use_slots'} = join ",", @{$properties->{'use-slots'}->{'values'}};
	if ($self->{'use_slots'} !~ /\d+(-\d+)?(,\d+(-\d+)?)*/) {
	    return Amanda::Changer->make_error("fatal", undef,
		message => "invalid 'use-slots' value '$self->{use_slots}'");
	}
    }

    # drive-choice
    if (exists $properties->{'drive-choice'}) {
	my $pval = $properties->{'drive-choice'}->{'values'}->[0];
	if (!grep { lc($_) eq $pval } ('lru', 'firstavail')) {
	    return Amanda::Changer->make_error("fatal", undef,
		message => "invalid 'drive-choice' value '$pval'");
	}
	$self->{'drive_choice'} = $pval;
    }

    # load-poll
    {
	next unless exists $config->{'properties'}->{'load-poll'};
	if (@{$config->{'properties'}->{'load-poll'}->{'values'}} > 1) {
	    return Amanda::Changer->make_error("fatal", undef,
		message => "only one value allowed for 'load-poll'");
	}
	my $propval = $config->{'properties'}->{'load-poll'}->{'values'}->[0];
	my ($delay, $delayu, $poll, $pollu, $until, $untilu) = ($propval =~ /^
		(\d+)([ms]?)
		(?:
		  \s+poll\s+
		  (\d+)([ms]?)
		  (?:
		    \s+until\s+
		    (\d+)([ms]?)
		  )?
		)?
		$/ix);

	if (!defined $delay) {
	    return Amanda::Changer->make_error("fatal", undef,
		message => "invalid delay value '$propval' for 'load-poll'");
	}

	$delay *= 60 if (defined $delayu and $delayu =~ /m/i);

	$poll = 0 unless defined $poll;
	$poll *= 60 if (defined $pollu and $pollu =~ /m/i);

	$until = 0 unless defined $until;
	$until *= 60 if (defined $untilu and $untilu =~ /m/i);

	$self->{'load_poll'} = [ $delay, $poll, $until ];
    }

    # status-interval, eject-delay, unload-delay
    for my $propname qw(status-interval eject-delay unload-delay) {
	next unless exists $config->{'properties'}->{$propname};
	if (@{$config->{'properties'}->{$propname}->{'values'}} > 1) {
	    return Amanda::Changer->make_error("fatal", undef,
		message => "only one value allowed for $propname");
	}
	my $propval = $config->{'properties'}->{$propname}->{'values'}->[0];
	my ($time, $timeu) = ($propval =~ /^(\d+)([ms]?)/ix);

	if (!defined $time) {
	    return Amanda::Changer->make_error("fatal", undef,
		message => "invalid time value '$propval' for '$propname'");
	}

	$time *= 60 if (defined $timeu and $timeu =~ /m/i);

	my $key = $propname;
	$key =~ s/-/_/;
	$self->{$key} = $time;
    }

    # mt and mtx
    my ($mt, $mtx);
    if (exists $config->{'properties'}->{'mt'}) {
	if (@{$config->{'properties'}->{'mt'}->{'values'}} > 1) {
	    return Amanda::Changer->make_error("fatal", undef,
		message => "only one value allowed for 'mt'");
	}
	$mt = $config->{'properties'}->{'mt'}->{'values'}->[0];
    } else {
	$mt = $Amanda::Constants::MT;
    }

    if (exists $config->{'properties'}->{'mtx'}) {
	if (@{$config->{'properties'}->{'mtx'}->{'values'}} > 1) {
	    return Amanda::Changer->make_error("fatal", undef,
		message => "only one value allowed for 'mtx'");
	}
	$mtx = $config->{'properties'}->{'mtx'}->{'values'}->[0];
    } else {
	$mtx = $Amanda::Constants::MTX;
    }

    if (!$mtx) {
	return Amanda::Changer->make_error("fatal", undef,
	    message => "no default value for property MTX");
    }

    if (!$mt and $ebu) {
	# mt is only needed for eject-before-unload
	return Amanda::Changer->make_error("fatal", undef,
	    message => "no default value for property MT");
    }

    my $ignore_barcodes = $self->get_boolean_property($self->{'config'},
					    "ignore-barcodes", 0);
    if (!defined $ignore_barcodes) {
	return Amanda::Changer->make_error("fatal", undef,
	    message => "invalid 'ignore-barcodes' value");
    }

    # construct the interface object
    $self->{'interface'} = Amanda::Changer::robot::Interface->new(
	    $device_name, $mt, $mtx, $ignore_barcodes),

    return $self;
}

sub load {
    my $self = shift;
    my %params = @_;
    $self->validate_params('load', \%params);

    return if $self->check_error($params{'res_cb'});

    $self->_with_updated_state(\%params, 'res_cb', sub { $self->load_unlocked(@_) });
}

sub load_unlocked {
    my $self = shift;
    my %params = @_;
    my %subs;
    my ($slot, $drive, $need_unload);

    my $state = $params{'state'};

    $subs{'calculate_slot'} = make_cb(calculate_slot => sub {
	# make sure the slot is numeric
	if (exists $params{'slot'}) {
	    if ($params{'slot'} =~ /^\d+$/) {
		$params{'slot'} = $params{'slot'}+0;
	    } else {
		return $self->make_error("failed", $params{'res_cb'},
			reason => "invalid",
			message => "invalid slot '$params{slot}'");
	    }
	}

        if (exists $params{'relative_slot'}) {
            if ($params{'relative_slot'} eq "next") {
		if (exists $params{'slot'}) {
		    $slot = $self->_get_next_slot($state, $params{'slot'});
		    $self->_debug("loading next relative to $params{slot}: $slot");
		} else {
		    $slot = $self->_get_next_slot($state, $state->{'current_slot'});
		    $self->_debug("loading next relative to current slot: $slot");
		}
		if ($slot == -1) {
		    return $self->make_error("failed", $params{'res_cb'},
			    reason => "invalid",
			    message => "could not find next slot");
		}
            } elsif ($params{'relative_slot'} eq "current") {
                $slot = $state->{'current_slot'};
		if ($slot == -1) {
		    # seek to the first slot
		    $slot = $self->_get_next_slot($state, $state->{'current_slot'});
		}
		if ($slot == -1) {
		    return $self->make_error("failed", $params{'res_cb'},
			    reason => "invalid",
			    message => "no current slot");
		}
	    } else {
		return $self->make_error("failed", $params{'res_cb'},
			reason => "invalid",
			message => "invalid relative_slot '$params{relative_slot}'");
	    }

        } elsif (exists $params{'slot'}) {
            $slot = $params{'slot'};
	    $self->_debug("loading slot '$params{slot}'");

            if (!defined $slot or !exists $state->{'slots'}->{$slot}) {
                return $self->make_error("failed", $params{'res_cb'},
                        reason => "invalid",
                        message => "invalid slot '$slot'");
            }

        } elsif (exists $params{'label'}) {
	    $self->_debug("loading label '$params{label}'");
            while (my ($sl, $info) = each(%{$state->{'slots'}})) {
                if (defined $info->{'label'} and $info->{'label'} eq $params{'label'}) {
                    $slot = $sl;
                    last;
                }
            }

            if (!defined $slot) {
                return $self->make_error("failed", $params{'res_cb'},
                        reason => "notfound",
                        message => "label '$params{label}' not recognized or not found");
            }

        } else {
            return $self->make_error("failed", $params{'res_cb'},
                    reason => "invalid",
                    message => "no 'slot' or 'label' specified to load()");
        }

	if (!$self->_is_slot_allowed($slot)) {
	    if (exists $params{'label'}) {
		return $self->make_error("failed", $params{'res_cb'},
			reason => "invalid",
			message => "label '$params{label}' is in slot $slot, which is " .
				   "not in use-slots ($self->{use_slots})");
	    } else {
		return $self->make_error("failed", $params{'res_cb'},
			reason => "invalid",
			message => "slot $slot not in use-slots ($self->{use_slots})");
	    }
	}

	if (exists $params{'except_slots'} and exists $params{'except_slots'}->{$slot}) {
	    return $self->make_error("failed", $params{'res_cb'},
		reason => "notfound",
		message => "all slots have been loaded");
	}

	my $slot_state = $state->{'slots'}->{$slot}->{'state'};
	if ($slot_state == SLOT_EMPTY) {
	    return $self->make_error("failed", $params{'res_cb'},
		    reason => "notfound",
		    message => "slot $slot is empty");
	}

	return $subs{'calculate_drive'}->();
    });

    $subs{'calculate_drive'} = make_cb(calculate_drive => sub {
        # $slot is set
	$need_unload = 0;

	# see if the tape is already in a drive
	$drive = $state->{'slots'}->{$slot}->{'loaded_in'};
	if (defined $drive) {
	    $self->_debug("requested volume is already in drive $drive");
	    my $info = $state->{'drives'}->{$drive};

	    # if it's reserved, it can't be used
	    if ($info->{'res_info'} and $self->_res_info_verify($info->{'res_info'})) {
		return $self->make_error("failed", $params{'res_cb'},
			reason => "inuse",
			slot => $slot,
			message => "the requested volume is in use (drive $drive)");
	    }

	    # if it's not reserved, but not in our list of drives, well, it still
	    # can't be used
	    if (!exists $self->{'drive2device'}->{$drive}) {
		return $self->make_error("failed", $params{'res_cb'},
			# not 'inuse' because we can't expect the tape to be magically
			# unloaded any time soon -- it's not actually in use, just inaccessible
			reason => "invalid",
			message => "the requested volume is in drive $drive, which this " .
				   "changer instance cannot access");
	    }

	    # otherwise, we can jump all the way to the end of this process
	    return $subs{'check_device'}->();
	}

	# here is where we implement each of the drive-selection algorithms
	my @check_order;
	if ($self->{'drive_choice'} eq 'lru') {
            my %lru = map { $_, 1 } @{$state->{'drive_lru'}};
            my @unused = grep { ! exists $lru{$_} } @{$self->{'driveorder'}};

	    # search through unused drives, then the LRU list
	    @check_order = (@unused, @{$state->{'drive_lru'}});
	} elsif ($self->{'drive_choice'} eq 'firstavail') {
	    # just the drive order, so we tend to prefer the first drive in
	    # this order
	    @check_order = (@{$self->{'driveorder'}});
	} else {
	    # the constructor should detect this circumstance
	    die "invalid drive_choice";
	}

	my %checked;
	for my $dr (@check_order) {
	    my $info = $state->{'drives'}->{$dr};
	    next unless defined $info;
	    next if exists $checked{$dr}; # don't check drives repeatedly
	    $checked{$dr} = 1;

	    # skip drives we don't have rights to use
	    next unless exists $self->{'drive2device'}->{$dr};

	    # skip reserved drives
	    if ($info->{'res_info'}) {
		if ($self->_res_info_verify($info->{'res_info'})) {
		    # this is a valid reservation -> skip this drive
		    $self->_debug("skipping drive $dr - already reserved");
		    next;
		} else {
		    warning("invalidating stale reservation on drive $dr");
		    $info->{'res_info'} = undef;
		}
	    }

	    # otherwise, the drive is available, so use it (whether it contains
	    # a volume or not)
	    $drive = $dr;
	    if ($info->{'state'} != SLOT_EMPTY) {
		$need_unload = 1;
	    }
	    last;
	}

        if (!defined $drive) {
            return $self->make_error("failed", $params{'res_cb'},
                    reason => "inuse",
                    message => "no drives available");
        }

	# remove this drive from the lru and put it at the end
	$state->{'drive_lru'} = [ grep { $_ ne $drive } @{$state->{'drive_lru'}} ];
	push @{$state->{'drive_lru'}}, $drive;

	$self->_debug("using drive $drive");

	$subs{'wait_to_start'}->();
    });

    $subs{'wait_to_start'} = make_cb(wait_to_start => sub {
	$self->_after_delay($state, $subs{'start_operation'});
    });

    $subs{'start_operation'} = make_cb(start_operation => sub {
	# $need_unload is set in $subs{calculate_drive}
	if ($need_unload) {
	    $subs{'start_eject'}->();
	} else {
	    $subs{'start_load'}->();
	}
    });

    $subs{'start_eject'} = make_cb(start_eject => sub {
	# we use the 'eject' method to unload here -- it ejects the volume
	# if the configuration calls for it, then puts the volume away in its
	# original slot.
	$self->eject_unlocked(
		finished_cb => $subs{'eject_finished'},
		drive => $drive,
		state => $state);
    });

    $subs{'eject_finished'} = make_cb(eject_finished => sub {
        my ($err) = @_;

        if ($err) {
	   return $params{'res_cb'}->($err);
        }

	$subs{'wait_to_load'}->();
    });

    $subs{'wait_to_load'} = make_cb(wait_to_load => sub {
	$self->_after_delay($state, $subs{'start_load'});
    });

    $subs{'start_load'} = make_cb(start_load => sub {
        # $slot and $drive are set
	$self->{'interface'}->load($slot, $drive, $subs{'load_finished'});
    });

    $subs{'load_finished'} = make_cb(load_finished => sub {
        # $slot and $drive are set
        my ($err) = @_;

        if ($err) {
            return $self->make_error("failed", $params{'res_cb'},
                    reason => "unknown",
                    message => $err);
        }

	$subs{'start_polling'}->();
    });

    my ($next_poll, $last_poll);
    $subs{'start_polling'} = make_cb(start_polling => sub {
	my ($delay, $poll, $until) = @{ $self->{'load_poll'} };
	my $now = time;
	$next_poll = $now + $delay;
	$last_poll = $now + $until;

	return Amanda::MainLoop::call_after(1000 * ($next_poll - $now), $subs{'check_device'});
    });

    $subs{'check_device'} = make_cb(check_device => sub {
	my $device_name = $self->{'drive2device'}->{$drive};
	die "drive $drive not found in drive2device" unless $device_name; # shouldn't happen

	$self->_debug("polling '$device_name' to see if it's ready");

	my $device = Amanda::Device->new($device_name);
	if ($device->status != $DEVICE_STATUS_SUCCESS) {
	    return $self->make_error("failed", $params{'res_cb'},
		    reason => "device",
		    message => "opening '$device_name': " . $device->error_or_status());
	}

	if (my $err = $self->{'config'}->configure_device($device)) {
	    return $self->make_error("failed", $params{'res_cb'},
		    reason => "device",
		    message => $err);
	}

	my $label;
	$device->read_label();

	# see if the device thinks it's possible it's busy or empty
	if ($device->status & $DEVICE_STATUS_VOLUME_MISSING
	    or $device->status & $DEVICE_STATUS_DEVICE_BUSY) {
	    # device is not ready -- set up for the next polling step
	    my ($delay, $poll, $until) = @{ $self->{'load_poll'} };
	    my $now = time;
	    $next_poll += $poll;
	    $next_poll = $now + 1 if ($next_poll < $now);
	    if ($poll != 0 and $next_poll < $last_poll) {
		return Amanda::MainLoop::call_after(
			1000 * ($next_poll - $now), $subs{'check_device'});
	    }

	    # (fall through if we're done polling)
	}

	if ($device->status == $DEVICE_STATUS_SUCCESS) {
	    $label = $device->volume_label;
	} elsif ($device->status & $DEVICE_STATUS_VOLUME_UNLABELED) {
	    $label = undef;
	} else {
	    return $self->make_error("failed", $params{'res_cb'},
		    reason => "device",
		    message => "while waiting for '$device_name' to become ready: "
			. $device->error_or_status());
	}

	# success!
	$subs{'make_res'}->($device, $label);
    });

    $subs{'make_res'} = make_cb(make_res => sub {
	my ($device, $label) = @_;

	# check the label against the desired label, in case this isn't the
	# desired volume
	if ($label and $params{'label'} and $label ne $params{'label'}) {
	    $self->_debug("Expected label '$params{label}', but got '$label'");

	    # update metadata with this new information
	    $state->{'slots'}->{$slot}->{'label'} = $label;
	    if ($state->{'slots'}->{$slot}->{'barcode'}) {
		$state->{'bc2lb'}->{$state->{'slots'}->{$slot}->{'barcode'}} = $label;
	    }

	    return $self->make_error("failed", $params{'res_cb'},
		    reason => "notfound",
		    message => "Found unexpected tape '$label' while looking " .
			       "for '$params{label}'");
	}

	if (!$label and $params{'label'}) {
	    $self->_debug("Expected label '$params{label}', but got an unlabeled tape");

	    # update metadata with this new information
	    $state->{'slots'}->{$slot}->{'label'} = undef;
	    $state->{'slots'}->{$slot}->{'state'} = SLOT_UNLABELED;
	    if ($state->{'slots'}->{$slot}->{'barcode'}) {
		delete $state->{'bc2lb'}->{$state->{'slots'}->{$slot}->{'barcode'}};
	    }

	    return $self->make_error("failed", $params{'res_cb'},
		    reason => "notfound",
		    message => "Found unlabeled tape while looking for '$params{label}'");
	}

	my $slot_state = $label? SLOT_LABELED : SLOT_UNLABELED;
        my $res = Amanda::Changer::robot::Reservation->new($self, $slot, $drive,
                                $device, $state->{'slots'}->{$slot}->{'barcode'});

	# mark this as reserved
	$state->{'drives'}->{$drive}->{'res_info'} = $self->_res_info_new();

	# update our state before returning
	$state->{'slots'}->{$slot}->{'loaded_in'} = $drive;
	$state->{'drives'}->{$drive}->{'orig_slot'} = $slot;
	$state->{'slots'}->{$slot}->{'label'} = $label;
	$state->{'drives'}->{$drive}->{'label'} = $label;
	$state->{'slots'}->{$slot}->{'state'} = $slot_state;
	$state->{'drives'}->{$drive}->{'state'} = $slot_state;
	$state->{'drives'}->{$drive}->{'barcode'} = $state->{'slots'}->{$slot}->{'barcode'};
	if ($label and $state->{'slots'}->{$slot}->{'barcode'}) {
	    $state->{'bc2lb'}->{$state->{'slots'}->{$slot}->{'barcode'}} = $label;
	}
	if ($params{'set_current'}) {
		$self->_debug("setting current slot to $slot");
	    $state->{'current_slot'} = $slot;
	}

        return $params{'res_cb'}->(undef, $res);
    });

    $subs{'calculate_slot'}->();
}

sub info_key {
    my $self = shift;
    my ($key, %params) = @_;

    if ($key eq 'fast_search') {
	$self->info_key_fast_search(%params);
    } elsif ($key eq 'vendor_string') {
	$self->info_key_vendor_string(%params);
    } elsif ($key eq 'num_slots') {
	$self->info_key_num_slots(%params);
    }
}

sub info_key_fast_search {
    my $self = shift;
    my %params = @_;

    $params{'info_cb'}->(undef,
	fast_search => $self->{'fast_search'},
    );
}

sub info_key_vendor_string {
    my $self = shift;
    my %params = @_;

    $self->{'interface'}->inquiry(make_cb(inquiry_cb => sub {
	my ($err, $info) = @_;
	return $params{'info_cb'}->($err) if $err;

	my $vendor_string = sprintf "%s %s",
	    ($info->{'vendor id'} or "<unknown>"),
	    ($info->{'product id'} or "<unknown>");

	$params{'info_cb'}->(undef,
	    vendor_string => $vendor_string,
	);
    }));
}

sub info_key_num_slots {
    my $self = shift;
    my %params = @_;

    $self->_with_updated_state(\%params, 'info_cb',
	sub { $self->info_key_num_slots_unlocked(@_) });
}

sub info_key_num_slots_unlocked {
    my $self = shift;
    my %params = @_;
    my %subs;
    my $state = $params{'state'};

    my @allowed_slots = grep { $self->_is_slot_allowed($_) }
			keys %{$state->{'slots'}};

    $params{'info_cb'}->(undef, num_slots => scalar @allowed_slots);
}

sub _set_label {
    my $self = shift;
    my %params = @_;

    return if $self->check_error($params{'finished_cb'});

    $self->_with_updated_state(\%params, 'finished_cb',
	sub { $self->_set_label_unlocked(@_); });
}

sub _set_label_unlocked {
    my $self = shift;
    my %params = @_;
    my $state = $params{'state'};

    # update all of the various pieces of cached information
    my $drive = $params{'drive'};
    my $slot = $state->{'drives'}->{$drive}->{'orig_slot'};
    my $label = $params{'label'};
    my $barcode = $state->{'drives'}->{$drive}->{'barcode'};

    $state->{'drives'}->{$drive}->{'label'} = $label;
    $state->{'drives'}->{$drive}->{'state'} = SLOT_LABELED;
    if (defined $slot) {
	$state->{'slots'}->{$slot}->{'label'} = $label;
	$state->{'slots'}->{$slot}->{'state'} = SLOT_LABELED;
    }
    if (defined $barcode) {
	$state->{'bc2lb'}->{$barcode} = $label;
    }

    $params{'finished_cb'}->(undef);
}

sub _release {
    my $self = shift;
    my %params = @_;

    return if $self->check_error($params{'finished_cb'});

    $self->_with_updated_state(\%params, 'finished_cb',
	sub { $self->_release_unlocked(@_); });
}

sub _release_unlocked {
    my $self = shift;
    my %params = @_;
    my $state = $params{'state'};
    my $drive = $params{'drive'};

    # delete the reservation and save the statefile
    if (!$self->_res_info_is_mine($state->{'drives'}->{$drive}->{'res_info'})) {
	# this should *never* happen
	return $self->make_error("fatal", $params{'finished_cb'},
		message => "reservation belongs to another instance");
    }
    $state->{'drives'}->{$drive}->{'res_info'} = undef;

    # bounce off to eject if the user has requested it, using the xx_unlocked
    # variant since we've already got the statefile open
    if ($params{'eject'}) {
	$self->eject_unlocked(
	    drive => $drive,
	    finished_cb => $params{'finished_cb'},
	    state => $state,
	);
    } else {
	$params{'finished_cb'}->();
    }
}

sub reset {
    my $self = shift;
    my %params = @_;

    return if $self->check_error($params{'finished_cb'});

    $self->_with_updated_state(\%params, 'finished_cb',
	sub { $self->reset_unlocked(@_); });
}

sub reset_unlocked {
    my $self = shift;
    my %params = @_;
    my $state = $params{'state'};

    $state->{'current_slot'} = $self->_get_next_slot($state, -1);

    $params{'finished_cb'}->();
}

sub eject {
    my $self = shift;
    my %params = @_;

    debug("$self->eject()");
    return if $self->check_error($params{'finished_cb'});

    $self->_with_updated_state(\%params, 'finished_cb',
	sub { $self->eject_unlocked(@_); });
}

sub eject_unlocked {
    my $self = shift;
    my %params = @_;
    my %subs;
    my $state = $params{'state'};
    my ($drive, $drive_info);

    return if $self->check_error($params{'finished_cb'});

    # note that this changer treats "eject" as "unload", which may also require an eject
    # operation if the eject_before_unload property is set

    $subs{'start'} = make_cb(start => sub {
	# if drive isn't specified, see if we only have one
	if (!exists $params{'drive'}) {
	    if ((keys %{$self->{'drive2device'}}) == 1) {
		$params{'drive'} = (keys %{$self->{'drive2device'}})[0];
	    } else {
		return $self->make_error("failed", $params{'finished_cb'},
			reason => "invalid",
			message => "no drive specified");
	    }
	}
	$drive = $params{'drive'};

	$self->_debug("unloading drive $drive");
	$drive_info = $state->{'drives'}->{$drive};
	if (!$drive_info) {
	    return $self->make_error("failed", $params{'finished_cb'},
		    reason => "invalid",
		    message => "invalid drive '$drive'");
	}

	# check for a reservation
	if ($drive_info->{'res_info'}
		    and $self->_res_info_verify($drive_info->{'res_info'})) {
	    return $self->make_error("failed", $params{'finished_cb'},
		    reason => "inuse",
		    message => "tape in drive '$drive' is in use");
	}

	if ($self->{'eject_before_unload'}) {
	    $subs{'wait_to_eject'}->();
	} else {
	    $subs{'wait_to_unload'}->();
	}
    });

    $subs{'wait_to_eject'} = make_cb(wait_to_eject => sub {
	$self->_after_delay($state, $subs{'eject'});
    });

    $subs{'eject'} = make_cb(eject => sub {
	my $drive_name = $self->{'drive2device'}->{$drive};
	$self->_debug("ejecting $drive_name before unload");
	$self->{'interface'}->eject($drive_name, $subs{'eject_finished'});
    });

    $subs{'eject_finished'} = make_cb(eject_finished => sub {
	my ($err) = @_;

	# errors while ejecting are noted in the debug file but ignored
        if ($err) {
	    warning("while ejecting: $err (ignored)");
        }

	$self->_set_delay($state, $self->{'eject_delay'});

	$subs{'wait_to_unload'}->();
    });

    $subs{'wait_to_unload'} = make_cb(wait_to_unload => sub {
	$self->_after_delay($state, $subs{'unload'});
    });

    $subs{'unload'} = make_cb(unload => sub {
	# find target slot and unload it - note that the target slot may not be
	# in the USE-SLOTS list, as it may belong to another config
	my $orig_slot = $drive_info->{'orig_slot'};
	$self->{'interface'}->unload($drive, $orig_slot, $subs{'unload_finished'});
    });

    $subs{'unload_finished'} = make_cb(unload_finished => sub {
	my ($err) = @_;

        if ($err) {
            return $self->make_error("failed", $params{'finished_cb'},
                    reason => "unknown",
                    message => $err);
        }

	$self->_debug("unload complete");
	my $orig_slot = $state->{'drives'}->{$drive}->{'orig_slot'};
	$state->{'slots'}->{$orig_slot}->{'state'} = $state->{'drives'}->{$drive}->{'state'};
	$state->{'slots'}->{$orig_slot}->{'label'} = $state->{'drives'}->{$drive}->{'label'};
	$state->{'slots'}->{$orig_slot}->{'barcode'} = $state->{'drives'}->{$drive}->{'barcode'};
	$state->{'slots'}->{$orig_slot}->{'loaded_in'} = undef;
	$state->{'drives'}->{$drive}->{'state'} = SLOT_EMPTY;
	$state->{'drives'}->{$drive}->{'label'} = undef;
	$state->{'drives'}->{$drive}->{'barcode'} = undef;
	$state->{'drives'}->{$drive}->{'orig_slot'} = undef;

	$self->_set_delay($state, $self->{'unload_delay'});
	$params{'finished_cb'}->();
    });

    $subs{'start'}->();
}

sub update {
    my $self = shift;
    my %params = @_;

    return if $self->check_error($params{'finished_cb'});

    $self->_with_updated_state(\%params, 'finished_cb',
	sub { $self->update_unlocked(@_); });
}

sub update_unlocked {
    my $self = shift;
    my %params = @_;
    my %subs;
    my @slots_to_check;
    my $state = $params{'state'};

    return if $self->check_error($params{'finished_cb'});

    my $user_msg_fn = $params{'user_msg_fn'};
    $user_msg_fn ||= sub { Amanda::Debug::info("chg-robot: " . $_[0]); };

    $subs{'handle_assignment'} = make_cb(handle_assignment => sub {
	# check for the SL=LABEL format, and handle it here
	if (exists $params{'changed'} and $params{'changed'} =~ /^\d+=\S+$/) {
	    my ($slot, $label) = ($params{'changed'} =~ /^(\d+)=(\S+)$/);

	    # let's list the reasons we *can't* do what the user has asked
	    my $whynot;
	    if (!exists $state->{'slots'}) {
		$whynot = "slot $slot does not exist";
	    } elsif (!$self->_is_slot_allowed($slot)) {
		$whynot = "slot $slot is not used by this changer";
	    } elsif ($state->{'slots'}->{$slot}->{'state'} == SLOT_EMPTY) {
		$whynot = "slot $slot is empty";
	    } elsif (defined $state->{'slots'}->{$slot}->{'loaded_in'}) {
		$whynot = "slot $slot is currently loaded";
	    }

	    if ($whynot) {
		return $self->make_error("failed", $params{'finished_cb'},
			reason => "unknown", message => $whynot);
	    }

	    $user_msg_fn->("recoding volume '$label' in slot $slot");
	    # ok, now erase all knowledge of that label
	    while (my ($bc, $lb) = each %{$state->{'bc2lb'}}) {
		if ($lb eq $label) {
		    delete $state->{'bc2lb'}->{$bc};
		    last;
		}
	    }
	    while (my ($sl, $inf) = each %{$state->{'slots'}}) {
		if ($inf->{'label'} and $inf->{'label'} eq $label) {
		    $inf->{'label'} = undef;
		    $inf->{'state'} = SLOT_UNKNOWN;
		}
	    }

	    # and add knowledge of the label to the given slot
	    $state->{'slots'}->{$slot}->{'label'} = $label;
	    $state->{'slots'}->{$slot}->{'state'} = SLOT_LABELED;
	    if ($state->{'slots'}->{$slot}->{'barcode'}) {
		my $bc = $state->{'slots'}->{$slot}->{'barcode'};
		$state->{'bc2lb'}->{$bc} = $label;
	    }

	    # that's it -- no changer motion required
	    return $params{'finished_cb'}->(undef);
	} else {
	    $subs{'calculate_slots'}->();
	}
    });
    $subs{'calculate_slots'} = make_cb(calculate_slots => sub {
	if (exists $params{'changed'}) {
	    # parse the string just like use-slots, using a hash for uniqueness
	    my %changed;
	    for my $range (split ',', $params{'changed'}) {
		my ($first, $last) = ($range =~ /(\d+)(?:-(\d+))?/);
		$last = $first unless defined($last);
		for ($first .. $last) {
		    $changed{$_} = undef;
		}
	    }

	    @slots_to_check = keys %changed;
	    @slots_to_check = grep { exists $state->{'slots'}->{$_} } @slots_to_check;
	} else {
	    @slots_to_check = keys %{ $state->{'slots'} };
	}

	# limit the update to allowed slots, and sort them so we don't confuse
	# the user with a "random" order
	@slots_to_check = grep { $self->_is_slot_allowed($_) } @slots_to_check;
	@slots_to_check = grep { $state->{'slots'}->{$_}->{'state'} != SLOT_EMPTY } @slots_to_check;
	@slots_to_check = sort @slots_to_check;

	$subs{'update_slot'}->();
    });

    # TODO: parallelize this if multiple drives are available

    $subs{'update_slot'} = make_cb(update_slot => sub {
	return $subs{'done'}->() if (!@slots_to_check);

	my $slot = shift @slots_to_check;
	$user_msg_fn->("scanning slot $slot");

	$self->load_unlocked(
		slot => $slot,
		res_cb => $subs{'slot_loaded'},
		state => $state);
    });

    $subs{'slot_loaded'} = make_cb(slot_loaded => sub {
	my ($err, $res) = @_;
	if ($err) {
	    return $params{'finished_cb'}->($err);
	}

	# load() already fixed up the metadata, so just release; but we have to
	# be careful to do an unlocked release.
	$res->release(
	    finished_cb => $subs{'released'},
	    unlocked => 1,
	    state => $state);
    });

    $subs{'released'} = make_cb(released => sub {
	my ($err) = @_;
	if ($err) {
	    return $params{'finished_cb'}->($err);
	}

	$subs{'update_slot'}->();
    });

    $subs{'done'} = make_cb(done => sub {
	$params{'finished_cb'}->(undef);
    });

    $subs{'handle_assignment'}->();
}

sub inventory {
    my $self = shift;
    my %params = @_;

    return if $self->check_error($params{'inventory_cb'});

    $self->_with_updated_state(\%params, 'inventory_cb',
	sub { $self->inventory_unlocked(@_); });
}

sub inventory_unlocked {
    my $self = shift;
    my %params = @_;
    my $state = $params{'state'};

    my @slot_names = sort { $a <=> $b } keys %{ $state->{'slots'} };
    my @inv;
    for my $slot_name (@slot_names) {
	my $i = {};
	next unless $self->_is_slot_allowed($slot_name);
	my $slot = $state->{'slots'}->{$slot_name};

	$i->{'slot'} = $slot_name;
	$i->{'empty'} = 1
	    if ($slot->{'state'} == SLOT_EMPTY);
	$i->{'label'} = ($slot->{'state'} == SLOT_UNLABELED)?
	    '' : $slot->{'label'};
	$i->{'barcode'} = $slot->{'barcode'}
	    if ($slot->{'barcode'});
	if (defined $slot->{'loaded_in'}) {
	    $i->{'loaded_in'} = $slot->{'loaded_in'};
	    my $drive = $state->{'drives'}->{$slot->{'loaded_in'}};
	    if ($drive->{'res_info'} and $self->_res_info_verify($drive->{'res_info'})) {
		$i->{'reserved'} = 1;
	    }
	}
	$i->{'ie'} = 1
	    if $slot->{'ie'};

	push @inv, $i;
    }

    $params{'inventory_cb'}->(undef, \@inv);
}

sub move {
    my $self = shift;
    my %params = @_;

    return if $self->check_error($params{'finished_cb'});

    $self->_with_updated_state(\%params, 'finished_cb',
	sub { $self->move_unlocked(@_); });
}

sub move_unlocked {
    my $self = shift;
    my %params = @_;
    my $state = $params{'state'};

    my $from_slot = $params{'from_slot'};
    my $to_slot = $params{'to_slot'};

    # make sure this is OK
    for ($from_slot, $to_slot) {
	if (!$self->_is_slot_allowed($_)) {
	    return $self->make_error("failed", $params{'finished_cb'},
		    reason => "invalid",
		    message => "invalid slot $_");
	}
    }

    my $from_state = $state->{'slots'}->{$from_slot}->{'state'};
    my $to_state = $state->{'slots'}->{$to_slot}->{'state'};

    if ($from_state == SLOT_EMPTY) {
	return $self->make_error("failed", $params{'finished_cb'},
		reason => "invalid",
		message => "slot $from_slot is empty");
    }

    if (defined $state->{'slots'}->{$from_slot}->{'loaded_in'}) {
	return $self->make_error("failed", $params{'finished_cb'},
		reason => "invalid",
		message => "slot $from_slot is currently loaded");
    }

    if ($to_state != SLOT_EMPTY) {
	return $self->make_error("failed", $params{'finished_cb'},
		reason => "invalid",
		message => "slot $to_slot is not empty");
    }

    # if the destination slot is loaded, then we could do an "exchange", but
    # should we?

    my $transfer_complete = make_cb(transfer_complete => sub {
	my ($err) = @_;
	return $params{'finished_cb'}->($err) if $err;

	# update metadata
	$state->{'slots'}->{$to_slot} = { %{ $state->{'slots'}->{$from_slot} } };
	$state->{'slots'}->{$from_slot}->{'state'} = SLOT_EMPTY;
	$state->{'slots'}->{$from_slot}->{'label'} = undef;
	$state->{'slots'}->{$from_slot}->{'barcode'} = undef;

	$params{'finished_cb'}->();
    });
    $self->{'interface'}->transfer($from_slot, $to_slot, $transfer_complete);
}

##
# Utilities

# calculate the next highest non-empty slot after $slot (assuming that
# the changer status has been updated)
sub _get_next_slot {
    my $self = shift;
    my ($state, $slot) = @_;

    my @nonempty = sort grep {
	$state->{'slots'}->{$_}->{'state'} != SLOT_EMPTY
	and $self->_is_slot_allowed($_)
    } keys(%{$state->{'slots'}});

    my @higher = grep { $_ > $slot } @nonempty;

    # return the next higher slot, or the first nonempty slot (to loop around)
    return $higher[0] if (@higher);
    return $nonempty[0];
}

# is $slot in the slots specified by the use-slots property?
sub _is_slot_allowed {
    my $self = shift;
    my ($slot) = @_;

    # if use-slots is not specified, all slots are available
    return 1 unless ($self->{'use_slots'});

    for my $range (split ',', $self->{'use_slots'}) {
	my ($first, $last) = ($range =~ /(\d+)(?:-(\d+))?/);
	$last = $first unless defined($last);
	return 1 if ($slot >= $first and $slot <= $last);
    }

    return 0;
}

# add a prefix and call Amanda::Debug::debug
sub _debug {
    my $self = shift;
    my ($msg) = @_;
    my $pfx = "chg-robot:$self->{device_name}";
    debug("$pfx: $msg");
}

##
# Timing management

# Wait until the delay from the last operation has expired, and call the
# given callback with the given arguments
sub _after_delay {
    my $self = shift;
    my ($state, $cb, @args) = @_;

    confess("undefined \$cb") unless (defined $cb);

    # if the current time is before $start, then we'll perform the action anyway; this
    # saves us from long delays when clocks fall out of sync or run backward, but delays
    # are short.
    my ($start, $end, $now);
    $start = $state->{'last_operation_time'};
    if (!defined $start) {
	return $cb->(@args);
    }

    $end = $start + $state->{'last_operation_delay'};
    $now = time;

    if ($now >= $start and $now < $end) {
	Amanda::MainLoop::call_after(1000 * ($end - $now), $cb, @args);
    } else {
	return $cb->(@args);
    }
}

# set the delay parameters in the statefile
sub _set_delay {
    my $self = shift;
    my ($state, $delay) = @_;

    $state->{'last_operation_time'} = time;
    $state->{'last_operation_delay'} = $delay;
}

##
# Statefile management

# wrapper around Amanda::Changer's with_locked_state to lock the statefile and
# then update the state with the results of the 'status' command.
#
# Like with_locked_state, this method assumes the keyword-based parameter
# style, and adds a 'state' parameter with the new state.  Also like
# with_locked_state, it replaces the $cbname key with a wrapped version of that
# callback.  It then calls $sub.
sub _with_updated_state {
    my $self = shift;
    my ($paramsref, $cbname, $sub) = @_;
    my %params = %$paramsref;
    my $state;
    my %subs;

    $subs{'start'} = make_cb(start => sub {
	$self->with_locked_state($self->{'statefile'},
	    $params{$cbname}, $subs{'got_lock'});
    });

    $subs{'got_lock'} = make_cb(got_lock => sub {
	($state, my $new_cb) = @_;

	# set up params for calling through to $sub later
	$params{'state'} = $state;
	$params{$cbname} = $new_cb;

	if (!keys %$state) {
	    $state->{'slots'} = {};
	    $state->{'drives'} = {};
	    $state->{'drive_lru'} = [];
	    $state->{'bc2lb'} = {};
	    $state->{'current_slot'} = -1;
	}

	# this is for testing ONLY!
	$self->{'__last_state'} = $state;

	# if it's not time for another run of the status command yet, then just skip to
	# the end.
	if (defined $state->{'last_status'}
	    and time < $state->{'last_status'} + $self->{'status_interval'}) {
	    $self->_debug("too early for another 'status' invocation");
	    $subs{'done'}->();
	} else {
	    $subs{'wait'}->();
	}
    });

    $subs{'wait'} = make_cb(wait => sub {
	$self->_after_delay($state, $subs{'call_status'});
    });

    $subs{'call_status'} = make_cb(call_status => sub {
	$self->{'interface'}->status($subs{'status_cb'});
    });

    $subs{'status_cb'} = make_cb(status_cb => sub {
	my ($err, $status) = @_;
	if ($err) {
	    return $self->make_error("fatal", $params{$cbname},
		message => $err);
	}

	$state->{'last_status'} = time;
	$self->_debug("updating state");

	# process the results; $status can update our slot->label
	# mapping, but the barcode->label mapping stays the same.

	my $new_slots = {};
	my ($drv, $slot, $info);

	# note that loaded_in is always undef; it will be set correctly
	# when the drives are scanned
	while (($slot, $info) = each %{$status->{'slots'}}) {
            if ($info->{'empty'}) {
                # empty slot
                $new_slots->{$slot} = {
                    state => SLOT_EMPTY,
                    label => undef,
                    barcode => undef,
                    loaded_in => undef,
		    ie => $info->{'ie'},
                };
                next;
            }

	    if (defined $info->{'barcode'}) {
                my $slot_state = SLOT_UNKNOWN;

                my $label = $state->{'bc2lb'}->{$info->{'barcode'}};
                if (defined $label and $label ne '') {
                    $slot_state = SLOT_LABELED;
                }

		$new_slots->{$slot} = {
                    state => $slot_state,
		    label => $label,
		    barcode => $info->{'barcode'},
                    loaded_in => undef,
		    ie => $info->{'ie'},
		};
	    } else {
		# assume the status of this slot has not changed since the last
                # time we looked at it, although mark it as not loaded in a slot
		if (exists $state->{'slots'}->{$slot}) {
		    $new_slots->{$slot} = $state->{'slots'}->{$slot};
		    $new_slots->{$slot}->{'loaded_in'} = undef;
		} else {
		    $new_slots->{$slot} = {
			state => SLOT_UNKNOWN,
			label => undef,
			barcode => undef,
			loaded_in => undef,
			ie => $info->{'ie'},
		    };
		}
	    }
	}
	$state->{'slots'} = $new_slots;

	# now handle the drives
	my $new_drives = {};
	while (($drv, $info) = each %{$status->{'drives'}}) {
	    my $old_drive = $state->{'drives'}->{$drv};

	    # if this drive still has a valid reservation, don't change it
	    if (defined $old_drive->{'res_info'}
			and $self->_res_info_verify($old_drive->{'res_info'})) {
		$new_drives->{$drv} = $old_drive;
		next;
	    }

	    # if the drive is empty, this is pretty easy
	    if (!defined $info) {
		$new_drives->{$drv} = {
                    state => SLOT_EMPTY,
                    label => undef,
                    barcode => undef,
                    orig_slot => undef,
                };
		next;
	    }

	    # trust our own orig_slot over that from the changer, if possible,
	    # as some changers do not report this information accurately
	    my ($orig_slot, $label);
	    if (defined $old_drive->{'orig_slot'}) {
		$orig_slot = $old_drive->{'orig_slot'};
                $label = $old_drive->{'label'};
	    }

	    # but don't trust it if the barcode has changed
	    if (defined $info->{'barcode'}
		    and defined $old_drive->{'barcode'}
		    and $info->{'barcode'} ne $old_drive->{'barcode'}) {
		$orig_slot = undef;
                $label = undef;
	    }

	    # get the robot's notion of the original slot if we don't know ourselves
	    if (!defined $orig_slot) {
		$orig_slot = $info->{'orig_slot'};
	    }

	    # but if there's a tape in that slot, then we've got a problem
	    if (defined $orig_slot
		    and $state->{'slots'}->{$orig_slot}->{'state'} != SLOT_EMPTY) {
		warning("mtx indicates tape in drive $drv should go to slot $orig_slot, " .
		        "but that slot is not empty.");
		$orig_slot = undef;
		for my $slot (keys %{ $state->{'slots'} }) {
		    if ($state->{'slots'}->{$slot}->{'state'} == SLOT_EMPTY) {
			$orig_slot = $slot;
			last;
		    }
		}
		if (!defined $orig_slot) {
		    warning("cannot find an empty slot for the tape in drive $drv");
		}
	    }

	    # and look up the label by barcode if possible
	    if (!defined $label && defined $info->{'barcode'}) {
		$label = $state->{'bc2lb'}->{$info->{'barcode'}};
	    }

	    $new_drives->{$drv} = {
                state => $label? SLOT_LABELED : SLOT_UNKNOWN,
                label => $label,
                barcode => $info->{'barcode'},
                orig_slot => $orig_slot,
            };
	}
	$state->{'drives'} = $new_drives;

	# update the loaded_in info for the relevant slots
	while (($drv, $info) = each %$new_drives) {
	    # also update the slots with the relevant 'loaded_in' info
	    if (defined $info->{'orig_slot'}) {
		$state->{'slots'}->{$info->{'orig_slot'}} = {
                    state => defined $info->{'label'}? SLOT_LABELED : SLOT_UNLABELED,
		    label => $info->{'label'},
                    barcode => $info->{'barcode'},
		    loaded_in => $drv,
		};
	    }
	}

	# sanity check that we don't have tape-device info for nonexistent drives
	for my $dr (@{$self->{'driveorder'}}) {
	    if (!exists $state->{'drives'}->{$dr}) {
		warning("tape-device property specified for drive $dr, but no such " .
			"drive exists in the library");
	    }
	}

	$subs{'done'}->();
    });

    $subs{'done'} = make_cb(done => sub {
	# finally, call through to the user's method; $params{$cbname} has been
	# properly patched to release the state lock when this method is done.
	$sub->(%params);
    });

    $subs{'start'}->();
}

##
# reservation records

# A reservation record is recorded in the statefile, and is distinct from an
# Amanda::Changer::robot:Reservation object in that it is seen by all users of
# the tape device, whether in this process or another.
#
# This is abstracted out to enable support for a more robust mechanism than
# caching a pid.

sub _res_info_new {
    my $self = shift;
    return { pid => $$, };
}

sub _res_info_verify {
    my $self = shift;
    my ($res_info) = @_;

    # true if this is our reservation
    return 1 if ($res_info->{'pid'} == $$);

    # or if the process is dead
    return kill 0, $res_info->{'pid'};
}

sub _res_info_is_mine {
    my $self = shift;
    my ($res_info) = @_;

    return 1 if ($res_info and $res_info->{'pid'} == $$);
}

package Amanda::Changer::robot::Reservation;
use vars qw( @ISA );
use Amanda::Debug qw( debug warning );
@ISA = qw( Amanda::Changer::Reservation );

sub new {
    my $class = shift;
    my ($chg, $slot, $drive, $device, $barcode) = @_;
    my $self = Amanda::Changer::Reservation::new($class);

    $self->{'chg'} = $chg;

    $self->{'drive'} = $drive;
    $self->{'device'} = $device;
    $self->{'this_slot'} = $slot;
    $self->{'barcode'} = $barcode;

    return $self;
}

sub do_release {
    my $self = shift;
    my %params = @_;

    # if we're in global cleanup and the changer is already dead,
    # then never mind
    return unless $self->{'chg'};

    # unref the device, for good measure
    $self->{'device'} = undef;

    # punt this method off to the changer itself, optionally calling
    # the unlocked version if we have the 'state' parameter
    if (exists $params{'unlocked'} and exists $params{'state'}) {
	$self->{'chg'}->_release_unlocked(drive => $self->{'drive'}, %params);
    } else {
	$self->{'chg'}->_release(drive => $self->{'drive'}, %params);
    }
}

sub set_label {
    my $self = shift;
    my %params = @_;

    return unless $self->{'chg'};
    $self->{'chg'}->_set_label(drive => $self->{'drive'}, %params);
}

package Amanda::Changer::robot::Interface;
use Amanda::Paths;
use Amanda::MainLoop qw( :GIOCondition );
use Amanda::Config qw( :getconf );
use Amanda::Debug qw( debug warning );
use Amanda::MainLoop qw( synchronized make_cb );

# the physical interface to the changer is abstracted out in hopes of eventually
# supporting SCSI access (via some C glue, presumably).

# This object uses a big lock to block *all* operations, not just mtx
# invocations.  This allows us to add delays to certain operations, while still
# holding the lock.

sub new {
    my $class = shift;
    my ($device_name, $mt, $mtx, $ignore_barcodes) = @_;

    return bless {
	lock => [],
	device_name => $device_name,
	mt => $mt,
	mtx => $mtx,
	ignore_barcodes => $ignore_barcodes,
    }, $class;
}

# Inquire as to the relevant information about the changer.  The result is a
# hash table of lowercased key names and values, $info.  The inquiry_cb is
# called as $inquiry_cb->($errmsg, $info).  The resulting strings have quotes
# and whitespace stripped
sub inquiry {
    my $self = shift;
    my ($inquiry_cb) = @_;

    synchronized($self->{'lock'}, $inquiry_cb, sub {
	my ($inquiry_cb) = @_;
	my $sys_cb = make_cb(sys_cb => sub {
	    my ($exitstatus, $output) = @_;
	    if ($exitstatus != 0) {
		return $inquiry_cb->("error from mtx: " . $output, {});
	    } else {
		my %info;
		for my $line (split '\n', $output) {
		    if (my ($k, $v) = ($line =~ /^(.*):\s*(.*)$/)) {
			$v =~ s/^'(.*)'$/$1/;
			$v =~ s/\s*$//;
			$info{lc $k} = $v;
		    }
		}
		return $inquiry_cb->(undef, \%info);
	    }

	});
	$self->_run_system_command($sys_cb,
	    $self->{'mtx'}, "-f", $self->{'device_name'}, 'inquiry');
    });
}

# Get the READ ELEMENT STATUS output for the changer.  The status_cb is called
# as $status_cb->($errmsg, $status).  $status is a hash with keys 'drives' and
# 'slots', each of which is a hash indexed by the element address (note that drive
# element addresses can and usually do overlap with slots.  The values of the slots
# hash are hashes with keys
#  - 'empty' (1 if the slot is empty)
#  - 'barcode' (which may be undef if the changer does not support barcodes)
#  - 'ie' (a boolean indicating whether this is an import/export slot).
# The values of the drives are undef for empty drive, or hashes with keys
#  - 'barcode' (which may be undef if the changer does not support barcodes)
#  - 'orig_slot' (slot from which this volume was taken, if known)
sub status {
    my $self = shift;
    my ($status_cb) = @_;

    synchronized($self->{'lock'}, $status_cb, sub {
	my ($status_cb) = @_;

	my $sys_cb = make_cb(sys_cb => sub {
	    my ($exitstatus, $output) = @_;
	    if ($exitstatus != 0) {
		my $err = $output;
		# if it's a regular SCSI error, just show the sense key
		my ($sensekey) = ($err =~ /mtx: Request Sense: Sense Key=(.*)\n/);
		$err = "SCSI error; Sense Key=$sensekey" if $sensekey;
		return $status_cb->("error from mtx: " . $err, {});
	    } else {
		my %status;
		for my $line (split '\n', $output) {
		    my ($slot, $ie, $slinfo);

		    # drives (data transfer elements)
		    if (($slot, $slinfo) = ($line =~
				/^Data Transfer Element\s*(\d+)?\s*:\s*(.*)/i)) {
			# assume 0 when not given a drive #
			$slot = 0 unless defined $slot;
			if ($slinfo =~ /^Empty/i) {
			    $status{'drives'}->{$slot} = undef;
			} elsif ($slinfo =~ /^Full/i) {
			    my ($barcode, $orig_slot);
			    ($barcode) = ($slinfo =~ /:VolumeTag\s*=\s*(\S+)/i);
			    ($orig_slot) = ($slinfo =~ /\(Storage Element (\d+) Loaded\)/i);
			    $status{'drives'}->{$slot} = {
				barcode => $barcode,
				orig_slot => $orig_slot,
			    };
			}

		    # slots (storage elements)
		    } elsif (($slot, $ie, $slinfo) = ($line =~
				/^\s*Storage Element\s*(\d+)\s*(IMPORT\/EXPORT)?\s*:\s*(.*)/i)) {
			$ie = $ie? 1 : 0;
			if ($slinfo =~ /^Empty/i) {
			    $status{'slots'}->{$slot} = {
				empty => 1,
				ie => $ie,
			    };
			} elsif ($slinfo =~ /^Full/i) {
			    my $barcode;
			    ($barcode) = ($slinfo =~ /:VolumeTag\s*=\s*(\S+)/i)
				unless ($self->{'ignore_barcodes'});
			    $status{'slots'}->{$slot} = {
				barcode => $barcode,
				ie => $ie,
			    };
			}
		    }
		}

		return $status_cb->(undef, \%status);
	    }

	});
	my @nobarcode = ('nobarcode') if $self->{'ignore_barcodes'};
	$self->_run_system_command($sys_cb,
	    $self->{'mtx'}, "-f", $self->{'device_name'}, @nobarcode, 'status');
    });
}

# Load $slot into $drive.  The finished_cb gets a single argument, $error,
# which is only defined if an error occurred.  Note that this does not
# necessarily wait until the load operation is complete (most drives give
# no such indication) (this method also implements unload, if $un=1)
sub load {
    my $self = shift;
    my ($slot, $drive, $finished_cb, $un) = @_;

    synchronized($self->{'lock'}, $finished_cb, sub {
	my ($finished_cb) = @_;

	my $sys_cb = make_cb(sys_cb => sub {
	    my ($exitstatus, $output) = @_;
	    if ($exitstatus != 0) {
		return $finished_cb->("error from mtx: " . $output);
	    } else {
		return $finished_cb->(undef);
	    }

	});

	$self->_run_system_command($sys_cb,
	    $self->{'mtx'}, "-f", $self->{'device_name'},
			    $un? 'unload':'load', $slot, $drive);
    });
}

# Unload $drive into $slot.  Finished_cb is just as for load().
sub unload {
    my $self = shift;
    my ($drive, $slot, $finished_cb) = @_;
    return $self->load($slot, $drive, $finished_cb, 1);
}

# eject $drive (named /dev/whatever, not the drive number), and call finished_cb.
# This will strip any "tape:" prefix beforehand.
sub eject {
    my $self = shift;
    my ($drive_name, $finished_cb) = @_;
    $drive_name =~ s/^tape://;

    synchronized($self->{'lock'}, $finished_cb, sub {
	my ($finished_cb) = @_;

	my $sys_cb = make_cb(sys_cb => sub {
	    my ($exitstatus, $output) = @_;
	    if ($exitstatus != 0) {
		return $finished_cb->("error from mt: " . $output);
	    } else {
		return $finished_cb->(undef);
	    }
	});

	$self->_run_system_command($sys_cb,
	    $self->{'mt'}, "-f", $drive_name, 'eject');
    });
}

# Move the tape in $src_slot into $dst_slot.  The finished_cb gets a single
# argument, $error, which is only defined if an error occurred.  Note that this
# does not necessarily wait until the load operation is complete.
sub transfer {
    my $self = shift;
    my ($src_slot, $dst_slot, $finished_cb) = @_;

    synchronized($self->{'lock'}, $finished_cb, sub {
	my ($finished_cb) = @_;

	my $sys_cb = make_cb(sys_cb => sub {
	    my ($exitstatus, $output) = @_;
	    if ($exitstatus != 0) {
		return $finished_cb->("error from mtx: " . $output);
	    } else {
		return $finished_cb->(undef);
	    }

	});

	$self->_run_system_command($sys_cb,
	    $self->{'mtx'}, "-f", $self->{'device_name'},
			    'transfer', $src_slot, $dst_slot);
    });
}

# Run 'mtx' or 'mt' and capture the output.  Standard output and error
# are lumped together.
#
# @param $sys_cb: called with ($exitstatus, $output)
# @param @args: args to pass to exec()
sub _run_system_command {
    my ($self, $sys_cb, @args) = @_;

    debug("invoking " . join(" ", @args));

    my ($readfd, $writefd) = POSIX::pipe();
    if (!defined($writefd)) {
	die("Error creating pipe: $!");
    }

    my $pid = fork();
    if (!defined($pid) or $pid < 0) {
        die("Can't fork to run changer script: $!");
    }

    if (!$pid) {
        ## child

	# get our file-handle house in order
	POSIX::close($readfd);
	POSIX::dup2($writefd, 1);
	POSIX::dup2($writefd, 2);
	POSIX::close($writefd);

        %ENV = Amanda::Util::safe_env();

        { exec { $args[0] } @args; } # braces protect against warning
        exit 127;
    }

    ## parent

    # clean up file descriptors from the fork
    POSIX::close($writefd);

    # the callbacks that follow share these lexical variables
    my $child_eof = 0;
    my $child_output = '';
    my $child_dead = 0;
    my $child_exit_status = 0;
    my ($fdsrc, $cwsrc);
    my %subs;

    $subs{'maybe_finished'} = sub {
	return unless $child_eof;
	return unless $child_dead;

	# everything is finished -- process the results and invoke the callback
	chomp $child_output;

	# let the callback take care of any further interpretation
	my $exitval = POSIX::WEXITSTATUS($child_exit_status);
	$sys_cb->($exitval, $child_output);
    };

    $subs{'fd_source_cb'} = sub {
	my ($fdsrc) = @_;
	my ($len, $bytes);
	$len = POSIX::read($readfd, $bytes, 1024);

	# if we got an EOF, shut things down.
	if ($len == 0) {
	    $child_eof = 1;
	    POSIX::close($readfd);
	    $fdsrc->remove();
	    $fdsrc = undef; # break a reference loop
	    $subs{'maybe_finished'}->();
	} else {
	    # otherwise, just keep the bytes
	    $child_output .= $bytes;
	}
    };

    $subs{'child_watch_source_cb'} = sub {
	my ($cwsrc, $got_pid, $got_status) = @_;
	$cwsrc->remove();
	$cwsrc = undef; # break a reference loop
	$child_dead = 1;
	$child_exit_status = $got_status;

	$subs{'maybe_finished'}->();
    };

    Amanda::MainLoop::fd_source($readfd, $G_IO_IN | $G_IO_ERR | $G_IO_HUP)
	->set_callback($subs{'fd_source_cb'});
    Amanda::MainLoop::child_watch_source($pid)
	->set_callback($subs{'child_watch_source_cb'});
}

1;
