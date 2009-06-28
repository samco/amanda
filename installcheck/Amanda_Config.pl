# Copyright (c) 2007,2008,2009 Zmanda, Inc.  All Rights Reserved.
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

use Test::More tests => 149;
use strict;

use lib "@amperldir@";
use Installcheck::Config;
use Amanda::Paths;
use Amanda::Tests;
use Amanda::Config qw( :init :getconf );
use Amanda::Debug;

my $testconf;
my $config_overwrites;

Amanda::Debug::dbopen("installcheck");

# utility function

sub diag_config_errors {
    my ($level, @errors) = Amanda::Config::config_errors();
    for my $errmsg (@errors) {
	diag $errmsg;
    }
}

##
# Try starting with no configuration at all

is(config_init(0, ''), $CFGERR_OK,
    "Initialize with no configuration")
    or diag_config_errors();

is(config_init(0, undef), $CFGERR_OK,
    "Initialize with no configuration, passing a NULL config name")
    or diag_config_errors();

$config_overwrites = new_config_overwrites(1);
add_config_overwrite($config_overwrites, "tapedev", "null:TEST");
apply_config_overwrites($config_overwrites);

is(getconf($CNF_TAPEDEV), "null:TEST",
    "config overwrites work with null config");

##
# Check out error handling

$testconf = Installcheck::Config->new();
$testconf->add_param('rawtapedev', '"/dev/medium-rare-please"'); # a deprecated keyword -> warning
$testconf->write();

{
    is(config_init($CONFIG_INIT_EXPLICIT_NAME, "TESTCONF"), $CFGERR_WARNINGS,
	"Deprecated keyword generates a warning");
    my ($error_level, @errors) = Amanda::Config::config_errors();
    like($errors[0], qr/is deprecated/, 
	"config_get_errors returns the warning string");

    Amanda::Config::config_clear_errors();
    ($error_level, @errors) = Amanda::Config::config_errors();
    is(scalar(@errors), 0, "config_clear_errors clears error list");
}

$testconf = Installcheck::Config->new();
$testconf->add_param('invalid-param', 'random-value'); # a deprecated keyword -> warning
$testconf->write();

is(config_init($CONFIG_INIT_EXPLICIT_NAME, "NO-SUCH-CONFIGURATION"), $CFGERR_ERRORS,
    "Non-existent config generates an error");

is(config_init($CONFIG_INIT_EXPLICIT_NAME, "TESTCONF"), $CFGERR_ERRORS,
    "Invalid keyword generates an error");

##
# try a client configuration

# (note use of uppercase letters to test lower-casing of property names)
$testconf = Installcheck::Config->new();
$testconf->add_client_param('property', '"client-prop" "yep"');
$testconf->add_client_param('property', 'priority "clIent-prop1" "foo"');
$testconf->add_client_param('property', 'append "clieNt-prop" "bar"');
$testconf->write();

my $cfg_result = config_init($CONFIG_INIT_CLIENT, undef);
is($cfg_result, $CFGERR_OK,
    "Load test client configuration")
    or diag_config_errors();

is_deeply(getconf($CNF_PROPERTY), { "client-prop1" => { priority => 1,
							append   => 0,
							values => [ "foo" ]},
				    "client-prop" => { priority => 0,
						       append   => 1,
						       values => [ "yep", "bar" ] }},
    "Client PROPERTY parameter parsed correctly");

##
# Parse up a basic configuration

# invent a "large" unsigned number, and make $size_t_num 
# depend on the length of size_t
my $int64_num = '171801575472'; # 0xA000B000C000 / 1024
my $size_t_num;
if (Amanda::Tests::sizeof_size_t() > 4) {
    $size_t_num = $int64_num;
} else {
    $size_t_num = '2147483647'; # 0x7fffffff
}

$testconf = Installcheck::Config->new();
$testconf->add_param('reserve', '75');
$testconf->add_param('autoflush', 'yes');
$testconf->add_param('usetimestamps', '0');
$testconf->add_param('tapedev', '"/dev/foo"');
$testconf->add_param('bumpsize', $int64_num);
$testconf->add_param('bumpmult', '1.4');
$testconf->add_param('reserved_udp-port', '100,200'); # note use of '-' and '_'
$testconf->add_param('device_output_buffer_size', $size_t_num);
$testconf->add_param('taperalgo', 'last');
$testconf->add_param('device_property', '"foo" "bar"');
$testconf->add_param('device_property', '"blUE" "car" "tar"');
$testconf->add_param('displayunit', '"m"');
$testconf->add_param('debug_auth', '1');
$testconf->add_tapetype('mytapetype', [
    'comment' => '"mine"',
    'length' => '128 M',
]);
$testconf->add_dumptype('mydump-type', [    # note dash
    'comment' => '"mine"',
    'priority' => 'high',  # == 2
    'bumpsize' => $int64_num,
    'bumpmult' => 1.75,
    'starttime' => 1829,
    'holdingdisk' => 'required',
    'compress' => 'client best',
    'encrypt' => 'server',
    'strategy' => 'incronly',
    'comprate' => '0.25,0.75',
    'exclude list' => '"foo" "bar"',
    'exclude list append' => '"true" "star"',
    'exclude file' => '"foolist"',
    'include list' => '"bing" "ting"',
    'include list append' => '"string" "fling"',
    'include file optional' => '"rhyme"',
    'property' => '"prop" "erty"',
    'property' => '"DROP" "qwerty" "asdfg"',
    'estimate' => 'server calcsize client'
]);
$testconf->add_dumptype('second_dumptype', [ # note underscore
    '' => 'mydump-type',
    'comment' => '"refers to mydump-type with a dash"',
]);
$testconf->add_dumptype('third_dumptype', [
    '' => 'second_dumptype',
    'comment' => '"refers to second_dumptype with an underscore"',
]);
$testconf->add_interface('ethernet', [
    'comment' => '"mine"',
    'use' => '100',
]);
$testconf->add_interface('nic', [
    'comment' => '"empty"',
]);
$testconf->add_holdingdisk('hd1', [
    'comment' => '"mine"',
    'directory' => '"/mnt/hd1"',
    'use' => '100M',
    'chunksize' => '1024k',
]);
$testconf->add_holdingdisk('hd2', [
    'comment' => '"empty"',
]);
$testconf->add_application('my_app', [
    'comment' => '"my_app_comment"',
    'plugin' => '"amgtar"',
]);
$testconf->add_script('my_script', [
  'comment' => '"my_script_comment"',
  'plugin' => '"script-email"',
  'execute-on' => 'pre-host-backup, post-host-backup',
  'execute-where' => 'client',
  'property' => '"mailto" "amandabackup" "amanda"',
]);
$testconf->add_device('my_device', [
  'comment' => '"my device is mine, not yours"',
  'tapedev' => '"tape:/dev/nst0"',
  'device_property' => '"BLOCK_SIZE" "128k"',
]);
$testconf->add_changer('my_changer', [
  'comment' => '"my changer is mine, not yours"',
  'tpchanger' => '"chg-foo"',
  'changerdev' => '"/dev/sg0"',
  'changerfile' => '"chg.state"',
  'property' => '"testprop" "testval"',
  'device_property' => '"testdprop" "testdval"',
]);

$testconf->write();

$cfg_result = config_init($CONFIG_INIT_EXPLICIT_NAME, 'TESTCONF');
is($cfg_result, $CFGERR_OK,
    "Load test configuration")
    or diag_config_errors();

SKIP: {
    skip "error loading config", 3 unless $cfg_result == $CFGERR_OK;

    is(Amanda::Config::get_config_name(), "TESTCONF", 
	"config_name set");
    is(Amanda::Config::get_config_dir(), "$CONFIG_DIR/TESTCONF", 
	"config_dir set");
    is(Amanda::Config::get_config_filename(),
	"$CONFIG_DIR/TESTCONF/amanda.conf", 
	"config_filename set");
}

SKIP: { # global parameters
    skip "error loading config", 12 unless $cfg_result == $CFGERR_OK;

    is(getconf($CNF_RESERVE), 75,
	"integer global confparm");
    is(getconf($CNF_BUMPSIZE), $int64_num+0,
	"int64 global confparm");
    is(getconf($CNF_TAPEDEV), "/dev/foo",
	"string global confparm");
    is(getconf($CNF_DEVICE_OUTPUT_BUFFER_SIZE), $size_t_num+0,
	"size global confparm");
    ok(getconf($CNF_AUTOFLUSH),
	"boolean global confparm");
    is(getconf($CNF_USETIMESTAMPS), 0,
	"boolean global confparm, passing an integer (0)");
    is(getconf($CNF_TAPERALGO), $Amanda::Config::ALGO_LAST,
	"taperalgo global confparam");
    is_deeply([getconf($CNF_RESERVED_UDP_PORT)], [100,200],
	"intrange global confparm");
    is(getconf($CNF_DISPLAYUNIT), "M",
	"displayunit is correctly uppercased");
    is_deeply(getconf($CNF_DEVICE_PROPERTY),
	      { "foo" => { priority => 0, append => 0, values => ["bar"]},
		"blue" => { priority => 0, append => 0,
			    values => ["car", "tar"]} },
	    "proplist global confparm");
    ok(getconf_seen($CNF_TAPEDEV),
	"'tapedev' parm was seen");
    ok(!getconf_seen($CNF_CHANGERFILE),
	"'changerfile' parm was not seen");
}

SKIP: { # derived values
    skip "error loading config", 3 unless $cfg_result == $CFGERR_OK;

    is(Amanda::Config::getconf_unit_divisor(), 1024, 
	"correct unit divisor (from displayunit -> KB)");
    ok($Amanda::Config::debug_auth, 
	"debug_auth setting reflected in global variable");
    ok(!$Amanda::Config::debug_amandad, 
	"debug_amandad defaults to false");
}

SKIP: { # tapetypes
    skip "error loading config", 6 unless $cfg_result == $CFGERR_OK;
    my $ttyp = lookup_tapetype("mytapetype");
    ok($ttyp, "found mytapetype");
    is(tapetype_getconf($ttyp, $TAPETYPE_COMMENT), 'mine', 
	"tapetype comment");
    is(tapetype_getconf($ttyp, $TAPETYPE_LENGTH), 128 * 1024, 
	"tapetype comment");

    ok(tapetype_seen($ttyp, $TAPETYPE_COMMENT),
	"tapetype comment was seen");
    ok(!tapetype_seen($ttyp, $TAPETYPE_LBL_TEMPL),
	"tapetype lbl_templ was not seen");

    is_deeply([ sort(+getconf_list("tapetype")) ],
	      [ sort("mytapetype", "TEST-TAPE") ],
	"getconf_list lists all tapetypes");
}

SKIP: { # dumptypes
    skip "error loading config", 18 unless $cfg_result == $CFGERR_OK;

    my $dtyp = lookup_dumptype("mydump-type");
    ok($dtyp, "found mydump-type");
    is(dumptype_getconf($dtyp, $DUMPTYPE_COMMENT), 'mine', 
	"dumptype string");
    is(dumptype_getconf($dtyp, $DUMPTYPE_PRIORITY), 2, 
	"dumptype priority");
    is(dumptype_getconf($dtyp, $DUMPTYPE_BUMPSIZE), $int64_num+0,
	"dumptype size");
    is(dumptype_getconf($dtyp, $DUMPTYPE_BUMPMULT), 1.75,
	"dumptype real");
    is(dumptype_getconf($dtyp, $DUMPTYPE_STARTTIME), 1829,
	"dumptype time");
    is(dumptype_getconf($dtyp, $DUMPTYPE_HOLDINGDISK), $HOLD_REQUIRED,
	"dumptype holdingdisk");
    is(dumptype_getconf($dtyp, $DUMPTYPE_COMPRESS), $COMP_BEST,
	"dumptype compress");
    is(dumptype_getconf($dtyp, $DUMPTYPE_ENCRYPT), $ENCRYPT_SERV_CUST,
	"dumptype encrypt");
    is(dumptype_getconf($dtyp, $DUMPTYPE_STRATEGY), $DS_INCRONLY,
	"dumptype strategy");
    is_deeply([dumptype_getconf($dtyp, $DUMPTYPE_COMPRATE)], [0.25, 0.75],
	"dumptype comprate");
    is_deeply(dumptype_getconf($dtyp, $DUMPTYPE_INCLUDE),
	{ 'file' => [ 'rhyme' ],
	  'list' => [ 'bing', 'ting', 'string', 'fling' ],
	  'optional' => 1 },
	"dumptype include list");
    is_deeply(dumptype_getconf($dtyp, $DUMPTYPE_EXCLUDE),
	{ 'file' => [ 'foolist' ],
	  'list' => [ 'foo', 'bar', 'true', 'star' ],
	  'optional' => 0 },
	"dumptype exclude list");
    is_deeply(dumptype_getconf($dtyp, $DUMPTYPE_ESTIMATELIST),
	      [ $ES_SERVER, $ES_CALCSIZE, $ES_CLIENT ]);
    is_deeply(dumptype_getconf($dtyp, $DUMPTYPE_PROPERTY),
	      { "prop" => { priority => 0, append => 0, values => ["erty"]},
		"drop" => { priority => 0, append => 0,
			    values => ["qwerty", "asdfg"] }},
	    "dumptype proplist");

    ok(dumptype_seen($dtyp, $DUMPTYPE_EXCLUDE),
	"'exclude' parm was seen");
    ok(!dumptype_seen($dtyp, $DUMPTYPE_RECORD),
	"'record' parm was not seen");

    is_deeply([ sort(+getconf_list("dumptype")) ],
	      [ sort(qw(
	        mydump-type second_dumptype third_dumptype 
	        NO-COMPRESS COMPRESS-FAST COMPRESS-BEST COMPRESS-CUST
		SRVCOMPRESS BSD-AUTH NO-RECORD NO-HOLD
		NO-FULL
		)) ],
	"getconf_list lists all dumptypes (including defaults)");
}

SKIP: { # interfaces
    skip "error loading config", 8 unless $cfg_result == $CFGERR_OK;
    my $iface = lookup_interface("ethernet");
    ok($iface, "found ethernet");
    is(interface_name($iface), "ethernet",
	"interface knows its name");
    is(interface_getconf($iface, $INTER_COMMENT), 'mine', 
	"interface comment");
    is(interface_getconf($iface, $INTER_MAXUSAGE), 100, 
	"interface maxusage");

    $iface = lookup_interface("nic");
    ok($iface, "found nic");
    ok(interface_seen($iface, $INTER_COMMENT),
	"seen set for parameters that appeared");
    ok(!interface_seen($iface, $INTER_MAXUSAGE),
	"seen not set for parameters that did not appear");

    is_deeply([ sort(+getconf_list("interface")) ],
	      [ sort('ethernet', 'nic', 'default') ],
	"getconf_list lists all interfaces (in any order)");
}

SKIP: { # holdingdisks
    skip "error loading config", 13 unless $cfg_result == $CFGERR_OK;
    my $hdisk = lookup_holdingdisk("hd1");
    ok($hdisk, "found hd1");
    is(holdingdisk_name($hdisk), "hd1",
	"hd1 knows its name");
    is(holdingdisk_getconf($hdisk, $HOLDING_COMMENT), 'mine', 
	"holdingdisk comment");
    is(holdingdisk_getconf($hdisk, $HOLDING_DISKDIR), '/mnt/hd1',
	"holdingdisk diskdir (directory)");
    is(holdingdisk_getconf($hdisk, $HOLDING_DISKSIZE), 100*1024, 
	"holdingdisk disksize (use)");
    is(holdingdisk_getconf($hdisk, $HOLDING_CHUNKSIZE), 1024, 
	"holdingdisk chunksize");

    $hdisk = lookup_holdingdisk("hd2");
    ok($hdisk, "found hd2");
    ok(holdingdisk_seen($hdisk, $HOLDING_COMMENT),
	"seen set for parameters that appeared");
    ok(!holdingdisk_seen($hdisk, $HOLDING_CHUNKSIZE),
	"seen not set for parameters that did not appear");

    # only holdingdisks have this linked-list structure
    # exposed
    my $hdisklist = getconf($CNF_HOLDINGDISK);
    my $first_disk = @$hdisklist[0];
    $hdisk = lookup_holdingdisk($first_disk);
    like(holdingdisk_name($hdisk), qr/hd[12]/,
	"one disk is first in list of holdingdisks");
    $hdisk = lookup_holdingdisk(@$hdisklist[1]);
    like(holdingdisk_name($hdisk), qr/hd[12]/,
	"another is second in list of holdingdisks");
    ok($#$hdisklist == 1,
	"no third holding disk");

    is_deeply([ sort(+getconf_list("holdingdisk")) ],
	      [ sort('hd1', 'hd2') ],
	"getconf_list lists all holdingdisks (in any order)");
}

SKIP: { # application
    skip "error loading config", 5 unless $cfg_result == $CFGERR_OK;
    my $app = lookup_application("my_app");
    ok($app, "found my_app");
    is(application_name($app), "my_app",
	"my_app knows its name");
    is(application_getconf($app, $APPLICATION_COMMENT), 'my_app_comment', 
	"application comment");
    is(application_getconf($app, $APPLICATION_PLUGIN), 'amgtar',
	"application plugin (amgtar)");

    is_deeply([ sort(+getconf_list("application-tool")) ],
	      [ sort("my_app") ],
	"getconf_list lists all application-tool");
}

SKIP: { # script
    skip "error loading config", 7 unless $cfg_result == $CFGERR_OK;
    my $sc = lookup_pp_script("my_script");
    ok($sc, "found my_script");
    is(pp_script_name($sc), "my_script",
	"my_script knows its name");
    is(pp_script_getconf($sc, $PP_SCRIPT_COMMENT), 'my_script_comment', 
	"script comment");
    is(pp_script_getconf($sc, $PP_SCRIPT_PLUGIN), 'script-email',
	"script plugin (script-email)");
    is(pp_script_getconf($sc, $PP_SCRIPT_EXECUTE_WHERE), $ES_CLIENT,
	"script execute_where (client)");
    is(pp_script_getconf($sc, $PP_SCRIPT_EXECUTE_ON),
	$EXECUTE_ON_PRE_HOST_BACKUP|$EXECUTE_ON_POST_HOST_BACKUP,
	"script execute_on");

    is_deeply([ sort(+getconf_list("script-tool")) ],
	      [ sort("my_script") ],
	"getconf_list lists all script-tool");
}

SKIP: { # device
    skip "error loading config", 6 unless $cfg_result == $CFGERR_OK;
    my $dc = lookup_device_config("my_device");
    ok($dc, "found my_device");
    is(device_config_name($dc), "my_device",
	"my_device knows its name");
    is(device_config_getconf($dc, $DEVICE_CONFIG_COMMENT), 'my device is mine, not yours',
	"device comment");
    is(device_config_getconf($dc, $DEVICE_CONFIG_TAPEDEV), 'tape:/dev/nst0',
	"device tapedev");
    # TODO do we really need all of this equipment for device properties?
    is_deeply(device_config_getconf($dc, $DEVICE_CONFIG_DEVICE_PROPERTY),
          { "block_size" => { 'priority' => 0, 'values' => ["128k"], 'append' => 0 }, },
        "device config proplist");

    is_deeply([ sort(+getconf_list("device")) ],
	      [ sort("my_device") ],
	"getconf_list lists all devices");
}

SKIP: { # changer
    skip "error loading config", 7 unless $cfg_result == $CFGERR_OK;
    my $dc = lookup_changer_config("my_changer");
    ok($dc, "found my_changer");
    is(changer_config_name($dc), "my_changer",
	"my_changer knows its name");
    is(changer_config_getconf($dc, $CHANGER_CONFIG_COMMENT), 'my changer is mine, not yours',
	"changer comment");
    is(changer_config_getconf($dc, $CHANGER_CONFIG_CHANGERDEV), '/dev/sg0',
	"changer tapedev");
    is_deeply(changer_config_getconf($dc, $CHANGER_CONFIG_PROPERTY),
	{ 'testprop' => {
		'priority' => 0,
		'values' => [ 'testval' ],
		'append' => 0,
	    }
        }, "changer properties represented correctly");

    is_deeply(changer_config_getconf($dc, $CHANGER_CONFIG_DEVICE_PROPERTY),
	{ 'testdprop' => {
		'priority' => 0,
		'values' => [ 'testdval' ],
		'append' => 0,
	    }
        }, "changer device properties represented correctly");

    is_deeply([ sort(+getconf_list("changer")) ],
	      [ sort("my_changer") ],
	"getconf_list lists all changers");
}

##
# Test config overwrites (using the config from above)

$config_overwrites = new_config_overwrites(1); # note estimate is too small
add_config_overwrite($config_overwrites, "tapedev", "null:TEST");
add_config_overwrite($config_overwrites, "tpchanger", "chg-test");
add_config_overwrite_opt($config_overwrites, "org=KAOS");
apply_config_overwrites($config_overwrites);

is(getconf($CNF_TAPEDEV), "null:TEST",
    "config overwrites work with real config");
is(getconf($CNF_ORG), "KAOS",
    "add_config_overwrite_opt parsed correctly");

# introduce an error
$config_overwrites = new_config_overwrites(1);
add_config_overwrite($config_overwrites, "bogusparam", "foo");
apply_config_overwrites($config_overwrites);

my ($error_level, @errors) = Amanda::Config::config_errors();
is($error_level, $CFGERR_ERRORS, "bogus config overwrite flagged as an error");

##
# Test configuration dumping

# (uses the config from the previous section)

# fork a child and capture its stdout
my $pid = open(my $kid, "-|");
die "Can't fork: $!" unless defined($pid);
if (!$pid) {
    Amanda::Config::dump_configuration();
    exit 1;
}
my $dump_first_line = <$kid>;
my $dump = join'', $dump_first_line, <$kid>;
close $kid;
waitpid $pid, 0;

my $fn = Amanda::Config::get_config_filename();
my $dump_filename = $dump_first_line;
chomp $dump_filename;
$dump_filename =~ s/^# AMANDA CONFIGURATION FROM FILE "//g;
$dump_filename =~ s/":$//g;
is($dump_filename, $fn, 
    "config filename is included correctly");

like($dump, qr/DEVICE_PROPERTY\s+"foo" "bar"\n/i,
    "DEVICE_PROPERTY appears in dump output");

like($dump, qr/AMRECOVER_CHECK_LABEL\s+(yes|no)/i,
    "AMRECOVER_CHECK_LABEL has a trailing space");

like($dump, qr/AMRECOVER_CHECK_LABEL\s+(yes|no)/i,
    "AMRECOVER_CHECK_LABEL has a trailing space");

like($dump, qr/EXCLUDE\s+LIST "foo" "bar" "true" "star"/i,
    "EXCLUDE LIST is in the dump");
like($dump, qr/EXCLUDE\s+FILE "foolist"/i,
    "EXCLUDE FILE is in the dump");
like($dump, qr/INCLUDE\s+LIST OPTIONAL "bing" "ting" "string" "fling"/i,
    "INCLUDE LIST is in the dump");
like($dump, qr/INCLUDE\s+FILE OPTIONAL "rhyme"/i,
    "INCLUDE FILE is in the dump");

##
# Test nested definitions inside a dumptype

$testconf = Installcheck::Config->new();
$testconf->add_dumptype('nested_stuff', [
    'comment' => '"contains a nested application, pp_script"',
    'application' => '{
	comment "my app"
	plugin "amfun"
}',
    'script' => '{
	comment "my script"
	plugin "ppfun"
}',
]);

$testconf->write();

$cfg_result = config_init($CONFIG_INIT_EXPLICIT_NAME, "TESTCONF");
is($cfg_result, $CFGERR_OK, 
    "parsing nested config loaded")
    or diag_config_errors();
SKIP: {
    skip "error loading config", 8 unless $cfg_result == $CFGERR_OK;

    my $dtyp = lookup_dumptype("nested_stuff");
    ok($dtyp, "found nested_stuff");

    my $appname = dumptype_getconf($dtyp, $DUMPTYPE_APPLICATION);
    like($appname, qr/^custom\(/,
	"DUMPTYPE_APPLICATION is the generated name of an application subsection");

    my $app = lookup_application($appname);
    ok($app, ".. and that name leads to an application object");
    is(application_getconf($app, $APPLICATION_COMMENT), "my app",
	".. that has the right comment");

    my $sc = dumptype_getconf($dtyp, $DUMPTYPE_SCRIPTLIST);
    ok(ref($sc) eq 'ARRAY' && @$sc == 1, "DUMPTYPE_SCRIPTLIST returns a 1-element list");
    like($sc->[0], qr/^custom\(/,
	".. and the first element is the generated name of a script subsection");

    $sc = lookup_pp_script($sc->[0]);
    ok($sc, ".. and that name leads to a pp_script object");
    is(pp_script_getconf($sc, $PP_SCRIPT_COMMENT), "my script",
	".. that has the right comment");
}

##
# Explore a quirk of exinclude parsing.  Only the last
# exclude (or include) directive affects the 'optional' flag.
# We may want to change this, but we should do so intentionally.
# This is also tested by the 'amgetconf' installcheck.

$testconf = Installcheck::Config->new();
$testconf->add_dumptype('mydump-type', [
    'exclude list' => '"foo" "bar"',
    'exclude list optional append' => '"true" "star"',
    'exclude list append' => '"true" "star"',
]);
$testconf->write();

$cfg_result = config_init($CONFIG_INIT_EXPLICIT_NAME, "TESTCONF");
is($cfg_result, $CFGERR_OK, 
    "first exinclude parsing config loaded")
    or diag_config_errors();
SKIP: {
    skip "error loading config", 2 unless $cfg_result == $CFGERR_OK;

    my $dtyp = lookup_dumptype("mydump-type");
    ok($dtyp, "found mydump-type");
    is(dumptype_getconf($dtyp, $DUMPTYPE_EXCLUDE)->{'optional'}, 0,
	"'optional' has no effect when not on the last occurrence");
}

##
# Check out where quoting is and is not required.

$testconf = Installcheck::Config->new();

# make sure an unquoted tapetype is OK
$testconf->add_param('tapetype', 'TEST-TAPE'); # unquoted (Installcheck::Config uses quoted)

# strings can optionally be quoted
$testconf->add_param('dumporder', '"STSTST"');

# enumerations (e.g., taperalgo) must not be quoted; implicitly tested above

# definitions
$testconf->add_dumptype('"parent"', [ # note quotes
    'bumpsize' => '10240',
]);
$testconf->add_dumptype('child', [
    '' => '"parent"', # note quotes
]);
$testconf->add_dumptype('child2', [
    '' => 'parent',
]);
$testconf->write();

$cfg_result = config_init($CONFIG_INIT_EXPLICIT_NAME, "TESTCONF");
is($cfg_result, $CFGERR_OK,
    "parsed config to test strings vs. identifiers")
    or diag_config_errors();
SKIP: {
    skip "error loading config", 3 unless $cfg_result == $CFGERR_OK;

    my $dtyp = lookup_dumptype("parent");
    ok($dtyp, "found parent");
    $dtyp = lookup_dumptype("child");
    ok($dtyp, "found child");
    is(dumptype_getconf($dtyp, $DUMPTYPE_BUMPSIZE), 10240,
	"child dumptype correctly inherited bumpsize");
}

##
# Explore a quirk of read_int_or_str parsing.

$testconf = Installcheck::Config->new();
$testconf->add_dumptype('mydump-type1', [
    'client_port' => '12345',
]);
$testconf->add_dumptype('mydump-type2', [
    'client_port' => '"newamanda"',
]);
$testconf->add_dumptype('mydump-type3', [
    'client_port' => '"67890"',
]);
$testconf->write();

$cfg_result = config_init($CONFIG_INIT_EXPLICIT_NAME, "TESTCONF");
is($cfg_result, $CFGERR_OK, 
    "read_int_or_str parsing config loaded")
    or diag_config_errors();
SKIP: {
    skip "error loading config", 6 unless $cfg_result == $CFGERR_OK;

    my $dtyp = lookup_dumptype("mydump-type1");
    ok($dtyp, "found mydump-type1");
    is(dumptype_getconf($dtyp, $DUMPTYPE_CLIENT_PORT), "12345",
	"client_port set to 12345");

    $dtyp = lookup_dumptype("mydump-type2");
    ok($dtyp, "found mydump-type1");
    is(dumptype_getconf($dtyp, $DUMPTYPE_CLIENT_PORT), "newamanda",
	"client_port set to \"newamanda\"");

    $dtyp = lookup_dumptype("mydump-type3");
    ok($dtyp, "found mydump-type1");
    is(dumptype_getconf($dtyp, $DUMPTYPE_CLIENT_PORT), "67890",
	"client_port set to \"67890\"");
}

##
# Check property inheritance

$testconf = Installcheck::Config->new();
$testconf->add_application('app1', [
    'property' => '"prop1" "val1"'
]);
$testconf->add_application('app2', [
    'property' => 'append "prop2" "val2"'
]);
$testconf->add_application('app3', [
    'property' => '"prop3" "val3"'
]);
$testconf->add_application('app1a', [
    'property' => '"prop4" "val4"',
    'property' => '"prop1" "val1a"',
    'app1' => undef
]);
$testconf->add_application('app2a', [
    'property' => '"prop5" "val5"',
    'property' => '"prop2" "val2a"',
    'app2' => undef
]);
$testconf->add_application('app3a', [
    'property' => '"prop6" "val6"',
    'app3' => undef,
    'property' => '"prop7" "val7"'
]);
$testconf->add_application('app1b', [
    'property' => '"prop4" "val4"',
    'property' => '"prop1" "val1a"',
    'app1' => undef,
    'property' => '"prop1" "val1b"',
]);
$testconf->add_application('app2b', [
    'property' => '"prop5" "val5"',
    'property' => '"prop2" "val2a"',
    'app2' => undef,
    'property' => 'append "prop2" "val2b"',
]);
$testconf->write();

$cfg_result = config_init($CONFIG_INIT_EXPLICIT_NAME, "TESTCONF");
is($cfg_result, $CFGERR_OK, 
    "application properties inheritance")
    or diag_config_errors();
SKIP: {
    skip "error loading config", 15 unless $cfg_result == $CFGERR_OK;

    my $app = lookup_application("app1a");
    ok($app, "found app1a");
    is(application_name($app), "app1a",
	"app1a knows its name");
    my $prop = application_getconf($app, $APPLICATION_PROPERTY);
    is_deeply($prop, { "prop4" => { priority => 0,
				    append   => 0,
				    values => [ "val4" ]},
		       "prop1" => { priority => 0,
				    append   => 0,
				    values => [ "val1" ] }},
    "PROPERTY parameter of app1a parsed correctly");

    $app = lookup_application("app2a");
    ok($app, "found app2a");
    is(application_name($app), "app2a",
	"app2a knows its name");
    $prop = application_getconf($app, $APPLICATION_PROPERTY);
    is_deeply($prop, { "prop5" => { priority => 0,
				    append   => 0,
				    values => [ "val5" ]},
		       "prop2" => { priority => 0,
				    append   => 0,
				    values => [ "val2a", "val2" ] }},
    "PROPERTY parameter of app2a parsed correctly");

    $app = lookup_application("app3a");
    ok($app, "found app3a");
    is(application_name($app), "app3a",
	"app3a knows its name");
    $prop = application_getconf($app, $APPLICATION_PROPERTY);
    is_deeply($prop, { "prop3" => { priority => 0,
				    append   => 0,
				    values => [ "val3" ]},
		       "prop6" => { priority => 0,
				    append   => 0,
				    values => [ "val6" ] },
		       "prop7" => { priority => 0,
				    append   => 0,
				    values => [ "val7" ] }},
    "PROPERTY parameter of app3a parsed correctly");

    $app = lookup_application("app1b");
    ok($app, "found app1b");
    is(application_name($app), "app1b",
	"app1b knows its name");
    $prop = application_getconf($app, $APPLICATION_PROPERTY);
    is_deeply($prop, { "prop4" => { priority => 0,
				    append   => 0,
				    values => [ "val4" ]},
		       "prop1" => { priority => 0,
				    append   => 0,
				    values => [ "val1b" ] }},
    "PROPERTY parameter of app1b parsed correctly");

    $app = lookup_application("app2b");
    ok($app, "found app2b");
    is(application_name($app), "app2b",
	"app2b knows its name");
    $prop = application_getconf($app, $APPLICATION_PROPERTY);
    is_deeply($prop, { "prop5" => { priority => 0,
				    append   => 0,
				    values => [ "val5" ]},
		       "prop2" => { priority => 0,
				    append   => 1,
				    values => [ "val2a", "val2", "val2b" ] }},
    "PROPERTY parameter of app2b parsed correctly");
}

