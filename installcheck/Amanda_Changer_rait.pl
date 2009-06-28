# Copyright (c) 2009 Zmanda, Inc.  All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
#
# Contact information: Zmanda Inc, 465 S Mathlida Ave, Suite 300
# Sunnyvale, CA 94086, USA, or: http://www.zmanda.com

use Test::More tests => 42;
use File::Path;
use strict;

use lib "@amperldir@";
use Installcheck;
use Installcheck::Config;
use Installcheck::Changer;
use Amanda::Paths;
use Amanda::Device;
use Amanda::Debug;
use Amanda::MainLoop;
use Amanda::Config qw( :init :getconf config_dir_relative );
use Amanda::Changer;

my $tapebase = "$Installcheck::TMP/Amanda_Changer_rait_test";

sub reset_taperoot {
    for my $root (1 .. 3) {
	my $taperoot = "$tapebase/$root";
	if (-d $taperoot) {
	    rmtree($taperoot);
	}
	mkpath($taperoot);

	for my $slot (1 .. 4) {
	    mkdir("$taperoot/slot$slot")
		or die("Could not mkdir: $!");
	}
    }
}

sub label_vtape {
    my ($root, $slot, $label) = @_;
    mkpath("$tapebase/tmp");
    symlink("$tapebase/$root/slot$slot", "$tapebase/tmp/data");
    my $dev = Amanda::Device->new("file:$tapebase/tmp");
    $dev->start($Amanda::Device::ACCESS_WRITE, $label, undef)
        or die $dev->error_or_status();
    $dev->finish()
        or die $dev->error_or_status();
    rmtree("$tapebase/tmp");
}

# set up debugging so debug output doesn't interfere with test results
Amanda::Debug::dbopen("installcheck");

# and disable Debug's die() and warn() overrides
Amanda::Debug::disable_die_override();

my $testconf = Installcheck::Config->new();
$testconf->write();

my $cfg_result = config_init($CONFIG_INIT_EXPLICIT_NAME, 'TESTCONF');
if ($cfg_result != $CFGERR_OK) {
    my ($level, @errors) = Amanda::Config::config_errors();
    die(join "\n", @errors);
}

reset_taperoot();
label_vtape(1,1,"mytape");
label_vtape(2,3,"mytape");
label_vtape(3,4,"mytape");
{
    my $err = Amanda::Changer->new("chg-rait:chg-disk:$tapebase/1");
    chg_err_like($err,
	{ message => "chg-rait needs at least two child changers",
	  type => 'fatal' },
	"single child device detected and handled");

    $err = Amanda::Changer->new("chg-rait:chg-disk:{$tapebase/13,$tapebase/14}");
    chg_err_like($err,
	{ message => qr/chg-disk.*13: directory.*; chg-disk.*14: directory.*/,
	  type => 'fatal' },
	"constructor errors in child devices detected and handled");
}

{
    my $chg = Amanda::Changer->new("chg-rait:chg-disk:$tapebase/{1,2,3}");
    pass("Create 3-way RAIT of vtapes");
    my ($get_info, $check_info,
	$do_load_current, $got_res_current,
	$do_load_next, $got_res_next,
	$do_load_label, $got_res_label,
	$do_load_slot, $got_res_slot,
	$do_load_slot_nobraces, $got_res_slot_nobraces,
	$do_load_slot_failure, $got_res_slot_failure,
	$do_load_slot_multifailure, $got_res_slot_multifailure,
    );

    $get_info = make_cb('get_info' => sub {
        $chg->info(info_cb => $check_info, info => [ 'num_slots', 'vendor_string', 'fast_search' ]);
    });

    $check_info = make_cb('check_info' => sub {
        my ($err, %results) = @_;
        die($err) if defined($err);

        is($results{'num_slots'}, 4,
	    "info() returns the correct num_slots");
        is($results{'vendor_string'}, '{chg-disk,chg-disk,chg-disk}',
	    "info() returns the correct vendor string");
        is($results{'fast_search'}, 1,
	    "info() returns the correct fast_search");

	$do_load_current->();
    });

    $do_load_current = make_cb('do_load_current' => sub {
	$chg->load(slot => "current", res_cb => $got_res_current);
    });

    $got_res_current = make_cb('got_res_current' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error loading slot 'current'")
	    or diag($err);
	is($res->{'device'}->device_name,
	   "rait:{file:$tapebase/1/drive0,file:$tapebase/2/drive0,file:$tapebase/3/drive0}",
	    "returns correct device name");
	is($res->{'this_slot'}, '{1,1,1}',
	    "returns correct 'this_slot' name");
	is($res->{'next_slot'}, '{2,2,2}',
	    "returns correct 'next_slot' name");

	$res->release(finished_cb => $do_load_next);
    });

    $do_load_next = make_cb('do_load_next' => sub {
	my ($err) = @_;
	die $err if $err;

	$chg->load(slot => "next", res_cb => $got_res_next);
    });

    $got_res_next = make_cb('got_res_next' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error loading slot 'next'")
	    or diag($err);
	is($res->{'device'}->device_name,
	   "rait:{file:$tapebase/1/drive0,file:$tapebase/2/drive0,file:$tapebase/3/drive0}",
	    "returns correct device name");
	is($res->{'this_slot'}, '{2,2,2}',
	    "returns correct 'this_slot' name");
	is($res->{'next_slot'}, '{3,3,3}',
	    "returns correct 'next_slot' name");

	$res->release(finished_cb => $do_load_label);
    });

    $do_load_label = make_cb('do_load_label' => sub {
	my ($err) = @_;
	die $err if $err;

	$chg->load(label => "mytape", res_cb => $got_res_label);
    });

    $got_res_label = make_cb('got_res_label' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error loading slot 'label'")
	    or diag($err);
	is($res->{'device'}->device_name,
	   "rait:{file:$tapebase/1/drive0,file:$tapebase/2/drive0,file:$tapebase/3/drive0}",
	    "returns correct device name");
	is($res->{'this_slot'}, '{1,3,4}',
	    "returns correct 'this_slot' name, even with different slots");

	$res->release(finished_cb => $do_load_slot);
    });

    $do_load_slot = make_cb('do_load_slot' => sub {
	my ($err) = @_;
	die $err if $err;

	$chg->load(slot => "{1,2,3}", res_cb => $got_res_slot);
    });

    $got_res_slot = make_cb('got_res_slot' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error loading slot '{1,2,3}'")
	    or diag($err);
	is($res->{'device'}->device_name,
	   "rait:{file:$tapebase/1/drive0,file:$tapebase/2/drive0,file:$tapebase/3/drive0}",
	    "returns correct device name");
	is($res->{'this_slot'}, '{1,2,3}',
	    "returns the 'this_slot' I requested");

	$res->release(finished_cb => $do_load_slot_nobraces);
    });

    $do_load_slot_nobraces = make_cb('do_load_slot_nobraces' => sub {
	my ($err) = @_;
	die $err if $err;

	# test the shorthand "2" -> "{2,2,2}"
	$chg->load(slot => "2", res_cb => $got_res_slot_nobraces);
    });

    $got_res_slot_nobraces = make_cb('got_res_slot_nobraces' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error loading slot '2'")
	    or diag($err);
	is($res->{'device'}->device_name,
	   "rait:{file:$tapebase/1/drive0,file:$tapebase/2/drive0,file:$tapebase/3/drive0}",
	    "returns correct device name");
	is($res->{'this_slot'}, '{2,2,2}',
	    "returns an expanded 'this_slot' of {2,2,2} in response to the shorthand '2'");

	$res->release(finished_cb => $do_load_slot_failure);
    });

    $do_load_slot_failure = make_cb('do_load_slot_failure' => sub {
	my ($err) = @_;
	die $err if $err;

	$chg->load(slot => "{1,99,1}", res_cb => $got_res_slot_failure);
    });

    $got_res_slot_failure = make_cb('got_res_slot_failure' => sub {
	my ($err, $res) = @_;
	chg_err_like($err,
	    { message => qr/from chg-disk.*2: Slot 99 not found/,
	      type => 'failed',
	      reason => 'notfound' },
	    "failure of a child to load a slot is correctly propagated");

	$do_load_slot_multifailure->();
    });

    $do_load_slot_multifailure = make_cb('do_load_slot_multifailure' => sub {
	my ($err) = @_;
	die $err if $err;

	$chg->load(slot => "{99,1,99}", res_cb => $got_res_slot_multifailure);
    });

    $got_res_slot_multifailure = make_cb('got_res_slot_multifailure' => sub {
	my ($err, $res) = @_;
	chg_err_like($err,
	    { message => qr/from chg-disk.*1: Slot 99 not found; from chg-disk.*3: /,
	      type => 'failed',
	      reason => 'notfound' },
	    "failure of multiple chilren to load a slot is correctly propagated");

	Amanda::MainLoop::quit();
    });

    # start the loop
    $get_info->();
    Amanda::MainLoop::run();
}

{
    my $chg = Amanda::Changer->new("chg-rait:{chg-disk:$tapebase/1,chg-disk:$tapebase/2,ERROR}");
    pass("Create 3-way RAIT of vtapes, with the third errored out");
    my ($get_info, $check_info,
	$do_load_current, $got_res_current,
	$do_load_label, $got_res_label,
	$do_reset, $finished_reset,
    );

    $get_info = make_cb('get_info' => sub {
        $chg->info(info_cb => $check_info, info => [ 'num_slots', 'fast_search' ]);
    });

    $check_info = make_cb('check_info' => sub {
        my $err = shift;
        my %results = @_;
        die($err) if defined($err);

        is($results{'num_slots'}, 4, "info() returns the correct num_slots");
        is($results{'fast_search'}, 1, "info() returns the correct fast_search");

	$do_load_current->();
    });

    $do_load_current = make_cb('do_load_current' => sub {
	$chg->load(slot => "current", res_cb => $got_res_current);
    });

    $got_res_current = make_cb('got_res_current' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error loading slot 'current'")
	    or diag($err);
	is($res->{'device'}->device_name,
	   "rait:{file:$tapebase/1/drive0,file:$tapebase/2/drive0,MISSING}",
	    "returns correct device name");
	is($res->{'this_slot'}, '{1,1,ERROR}',
	    "returns correct 'this_slot' name");
	is($res->{'next_slot'}, '{2,2,ERROR}',
	    "returns correct 'next_slot' name");

	$res->release(finished_cb => $do_load_label);
    });

    $do_load_label = make_cb('do_load_label' => sub {
	my ($err) = @_;
	die $err if $err;

	$chg->load(label => "mytape", res_cb => $got_res_label);
    });

    $got_res_label = make_cb('got_res_label' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error loading slot 'label'")
	    or diag($err);
	is($res->{'device'}->device_name,
	   "rait:{file:$tapebase/1/drive0,file:$tapebase/2/drive0,MISSING}",
	    "returns correct device name");
	is($res->{'this_slot'}, '{1,3,ERROR}',
	    "returns correct 'this_slot' name, even with different slots");

	$do_reset->();
    });

    # unfortunately, reset, clean, and update are pretty boring with vtapes, so
    # it's hard to test them effectively.

    $do_reset = make_cb('do_reset' => sub {
	my ($err) = @_;
	die $err if $err;

	$chg->reset(finished_cb => $finished_reset);
    });

    $finished_reset = make_cb('finished_reset' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error resetting");

	Amanda::MainLoop::quit();
    });

    # start the loop
    $get_info->();
    Amanda::MainLoop::run();
}

##
# Test configuring the device with device_property

$testconf = Installcheck::Config->new();
$testconf->add_changer("myrait", [
    tpchanger => "\"chg-rait:chg-disk:$tapebase/{1,2,3}\"",
    device_property => '"comment" "hello, world"',
]);
$testconf->write();

config_uninit();
$cfg_result = config_init($CONFIG_INIT_EXPLICIT_NAME, 'TESTCONF');
if ($cfg_result != $CFGERR_OK) {
    my ($level, @errors) = Amanda::Config::config_errors();
    die(join "\n", @errors);
}

reset_taperoot();
label_vtape(1,1,"mytape");
label_vtape(2,2,"mytape");
label_vtape(3,3,"mytape");

{
    my $chg = Amanda::Changer->new("myrait");
    ok($chg->isa("Amanda::Changer::rait"), "Create RAIT device from a named config subsection");
    my ($do_load_1, $got_res_1, $quit);

    $do_load_1 = make_cb('do_load_1' => sub {
	$chg->load(slot => "1", res_cb => $got_res_1);
    });

    $got_res_1 = make_cb('got_res_1' => sub {
	my ($err, $res) = @_;
	ok(!$err, "no error loading slot '1'")
	    or diag($err);
	is($res->{'device'}->device_name,
	   "rait:{file:$tapebase/1/drive0,file:$tapebase/2/drive0,file:$tapebase/3/drive0}",
	    "returns correct (full) device name");
	is($res->{'this_slot'}, '{1,1,1}',
	    "returns correct 'this_slot' name");
	is($res->{'next_slot'}, '{2,2,2}',
	    "returns correct 'next_slot' name");
	is($res->{'device'}->property_get("comment"), "hello, world",
	    "property from device_property appears on RAIT device");

	$res->release(finished_cb => $quit);
    });

    $quit = make_cb('quit' => sub {
	my ($err) = @_;
	die $err if $err;

	Amanda::MainLoop::quit();
    });

    # start the loop
    $do_load_1->();
    Amanda::MainLoop::run();
}

rmtree($tapebase);
