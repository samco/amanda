# Copyright (c) 2006 Zmanda Inc.  All Rights Reserved.
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
# Contact information: Zmanda Inc, 505 N Mathlida Ave, Suite 120
# Sunnyvale, CA 94085, USA, or: http://www.zmanda.com

use Test::More tests => 11;

use lib "@amperldir@";
use Installcheck::Config;
use Installcheck::Run qw(run run_get run_err);
use Amanda::Paths;

my $testconf;

##
# First, try amgetconf out without a config

ok(!run('amdevcheck'),
    "'amdevcheck' with no arguments returns an error exit status");
like($Installcheck::Run::stdout, qr(\AUsage: )i, 
    ".. and gives usage message on stdout");

like(run_err('amdevcheck', 'this-probably-doesnt-exist'), qr(could not open conf file)i, 
    "if the configuration doesn't exist, fail with the correct message");

##
# Next, work against a basically empty config

# this is re-created for each test
$testconf = Installcheck::Config->new();
$testconf->add_param("tapedev", '"/dev/null"');
$testconf->write();

# test some defaults
ok(run('amdevcheck', 'TESTCONF'), "run succeeds with a real configuration");
is_deeply([ sort split "\n", $Installcheck::Run::stdout ],
	  [ sort "DEVICE_MISSING", "DEVICE_ERROR" ],
    "A bad tapedev described as DEVICE_MISSING, DEVICE_ERROR");
like($Installcheck::Run::stderr, qr{File /dev/null is not a tape device},
    "App uses tapedev by default");

##
# Now use a config with a vtape

# this is re-created for each test
$testconf = Installcheck::Run::setup();
$testconf->add_param('label_new_tapes', '"TESTCONF%%"');
$testconf->write();

is_deeply([ sort split "\n", run_get('amdevcheck', 'TESTCONF') ],
	  [ sort "VOLUME_UNLABELED", "VOLUME_ERROR", "DEVICE_ERROR" ],
    "empty vtape described as VOLUME_UNLABELED, VOLUME_ERROR, DEVICE_ERROR");

ok(run('amdevcheck', 'TESTCONF', "/dev/null"),
    "can override device on the command line");
like($Installcheck::Run::stderr, qr{File /dev/null is not a tape device},
    ".. and produce a corresponding error message");

ok(my $dumpok = run('amdump', 'TESTCONF'), "a dump runs successfully");

SKIP: {
    skip "Dump failed", 1 unless $dumpok;
    is_deeply([ sort split "\n", run_get('amdevcheck', 'TESTCONF') ],
	      [ sort "SUCCESS" ],
	"used vtape described as SUCCESS");
}

Installcheck::Run::cleanup();