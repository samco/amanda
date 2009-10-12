# Copyright (c) 2008 Zmanda, Inc.  All Rights Reserved.
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
# Contact information: Zmanda Inc., 465 S Mathlida Ave, Suite 300
# Sunnyvale, CA 94085, USA, or: http://www.zmanda.com

use Test::More tests => 15;
use strict;
use warnings;

use File::Path;
use Data::Dumper;

use lib "@amperldir@";

use Installcheck;
use Amanda::Report;

my %LogfileContents;
my %LogfileData;
my $logCount = 0;
my $log_filename = "$Installcheck::TMP/Amanda_Report_test.log";

# copy/pasted from installcheck/Amanda_Logfile.pl .  Maybe move this
# to a module?
sub write_logfile
{
    my ($contents) = @_;

    open my $logfile, ">", $log_filename
      or die("Could not create temporary log file '$log_filename': $!");
    print $logfile $contents;
    close $logfile;

    return $log_filename;
}

$LogfileContents{planner} = <<EOF;
START planner date 20090728160530
INFO planner planner pid 12346
DISK planner localhost /root
DISK planner localhost /etc
DISK planner localhost /var/log
EOF

$LogfileData{planner} = {
    programs => {
        planner => { start => "20090728160530", },
    },
    disklist => {
        localhost => {
            "/root" => {
                estimate => undef,
                tries    => [],
            },
            "/etc" => {
                estimate => undef,
                tries    => [],
            },
            "/var/log" => {
                estimate => undef,
                tries    => [],
            },
        },
    },
};

#
# NOTE: this test is not reflective of real amanda log output.
#
$LogfileContents{driver} = <<EOF;
START planner date 20090728122430
INFO planner planner pid 12346
INFO driver driver pid 12347
DISK planner localhost /root
DISK planner localhost /etc
DISK planner localhost /home
START driver date 20090728122430
STATS driver hostname localhost
STATS driver startup time 0.034
STATS driver estimate localhost /root 20090728122430 0 [sec 0 nkb 42 ckb 64 kps 1024]
STATS driver estimate localhost /etc 20090728122430 0 [sec 2 nkb 2048 ckb 64 kps 1024]
STATS driver estimate localhost /home 20090728122430 0 [sec 4 nkb 5012 ckb 64 kps 1024]
FINISH driver date 20090728122445 time 14.46
EOF

$LogfileData{driver} = {
    programs => {
        planner => { start => "20090728122430", },
        driver  => {
            start      => "20090728122430",
            start_time => "0.034",
            time       => "14.46",
        },
    },
    disklist => {
        localhost => {
            "/root" => {
                estimate => {
                    level => "0",
                    sec   => "0",
                    nkb   => "42",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [],
            },
            "/etc" => {
                estimate => {
                    level => "0",
                    sec   => "2",
                    nkb   => "2048",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [],
            },
            "/home" => {
                estimate => {
                    level => "0",
                    sec   => "4",
                    nkb   => "5012",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [],
            },
        },
    },
};



$LogfileContents{dumper} = <<EOF;
START planner date 20090728122430
INFO driver driver pid 12345
INFO planner planner pid 12346
DISK planner localhost /root
DISK planner localhost /etc
DISK planner localhost /home
START driver date 20090728122430
STATS driver hostname localhost
STATS driver startup time 0.034
SUCCESS dumper localhost /root 20090728122430 0 [sec 0.02 kb 42 kps 2100 orig-kb 42]
STATS driver estimate localhost /root 20090728122430 0 [sec 0 nkb 42 ckb 64 kps 1024]
SUCCESS dumper localhost /etc 20090728122430 0 [sec 0.87 kb 2048 kps 2354 orig-kb 2048]
STATS driver estimate localhost /etc 20090728122430 0 [sec 2 nkb 2048 ckb 64 kps 1024]
SUCCESS dumper localhost /home 20090728122430 0 [sec 1.68421 kb 4096 kps 2354 orig-kb 4096]
STATS driver estimate localhost /home 20090728122430 0 [sec 4 nkb 4096 ckb 64 kps 1024]
FINISH driver date 20090728122445 time 14.46
EOF

$LogfileData{dumper} = {
    programs => {
        planner => { start => "20090728122430", },
        driver  => {
            start      => "20090728122430",
            start_time => "0.034",
            time       => "14.46",
        },
        dumper => {},
    },
    disklist => {
        localhost => {
            "/root" => {
                estimate => {
                    level => "0",
                    sec   => "0",
                    nkb   => "42",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [
                    {
                        dumper => {
                            date      => "20090728122430",
                            status    => "success",
                            level     => "0",
                            sec       => "0.02",
                            kb        => "42",
                            kps       => "2100",
                            "orig-kb" => "42",
                        },
                    },
                ],
            },
            "/etc" => {
                estimate => {
                    level => "0",
                    sec   => "2",
                    nkb   => "2048",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [
                    {
                        dumper => {
                            date      => "20090728122430",
                            status    => "success",
                            level     => "0",
                            sec       => "0.87",
                            kb        => "2048",
                            kps       => "2354",
                            "orig-kb" => "2048",
                        },
                    },
                ],
            },
            "/home" => {
                estimate => {
                    level => "0",
                    sec   => "4",
                    nkb   => "4096",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [
                    {
                        dumper => {
                            date      => "20090728122430",
                            status    => "success",
                            level     => "0",
                            sec       => "1.68421",
                            kb        => "4096",
                            kps       => "2354",
                            "orig-kb" => "4096",
                        },
                    },
                ],
            },
        },
    },
};


$LogfileContents{chunker} = <<EOF;
START planner date 20090728122430
INFO driver driver pid 12345
INFO planner planner pid 12346
DISK planner localhost /root
DISK planner localhost /etc
DISK planner localhost /home
START driver date 20090728122430
STATS driver hostname localhost
STATS driver startup time 0.034
SUCCESS dumper localhost /root 20090728122430 0 [sec 0.02 kb 42 kps 2100 orig-kb 42]
INFO chunker chunker pid 12348
SUCCESS chunker localhost /root 20090728122430 0 [sec 0.02 kb 42 kps 2100]
STATS driver estimate localhost /root 20090728122430 0 [sec 0 nkb 42 ckb 64 kps 1024]
SUCCESS dumper localhost /etc 20090728122430 0 [sec 0.87 kb 2048 kps 2354 orig-kb 2048]
INFO chunker chunker pid 12349
SUCCESS chunker localhost /etc 20090728122430 0 [sec 0.79 kb 2048 kps 2592.40506]
STATS driver estimate localhost /etc 20090728122430 0 [sec 2 nkb 2048 ckb 64 kps 1024]
SUCCESS dumper localhost /home 20090728122430 0 [sec 1.68421 kb 4096 kps 2354 orig-kb 4096]
INFO chunker chunker pid 12350
PARTIAL chunker localhost /home 20090728122430 0 [sec 0.82 kb 2532 kps 3087.80488]
STATS driver estimate localhost /home 20090728122430 0 [sec 4 nkb 4096 ckb 64 kps 1024]
FINISH driver date 20090728122445 time 14.46
EOF

$LogfileData{chunker} = {
    programs => {
        planner => { start => "20090728122430", },
        driver => {
            start      => "20090728122430",
            start_time => "0.034",
            time       => "14.46",
        },
        dumper  => {},
        chunker => {}
    },
    disklist => {
        localhost => {
            "/root" => {
                estimate => {
                    level => "0",
                    sec   => "0",
                    nkb   => "42",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [
                    {
                        dumper => {
                            date      => "20090728122430",
                            status    => "success",
                            level     => "0",
                            sec       => "0.02",
                            kb        => "42",
                            kps       => "2100",
                            "orig-kb" => "42",
                        },
                        chunker => {
                            status => "success",
                            level  => "0",
                            date   => "20090728122430",
                            sec    => "0.02",
                            kb     => "42",
                            kps    => "2100",
                        },
                    },
                ],
            },
            "/etc" => {
                estimate => {
                    level => "0",
                    sec   => "2",
                    nkb   => "2048",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [
                    {
                        dumper => {
                            date      => "20090728122430",
                            status    => "success",
                            level     => "0",
                            sec       => "0.87",
                            kb        => "2048",
                            kps       => "2354",
                            "orig-kb" => "2048",
                        },
                        chunker => {
                            status => "success",
                            level  => "0",
                            date   => "20090728122430",
                            sec    => "0.79",
                            kb     => "2048",
                            kps    => "2592.40506",
                        },
                    },
                ],
            },
            "/home" => {
                estimate => {
                    level => "0",
                    sec   => "4",
                    nkb   => "4096",
                    ckb   => "64",
                    kps   => "1024",
                },
                tries => [
                    {
                        dumper => {
                            date      => "20090728122430",
                            status    => "success",
                            level     => "0",
                            sec       => "1.68421",
                            kb        => "4096",
                            kps       => "2354",
                            "orig-kb" => "4096",
                        },
                        chunker => {
                            status => "partial",
                            level  => "0",
                            date   => "20090728122430",
                            sec    => "0.82",
                            kb     => "2532",
                            kps    => "3087.80488"
                        },
                    },
                ],
            },
        },
    },
};


$LogfileContents{taper} = <<EOF;
DISK planner somebox /lib
START planner date 20080111
START driver date 20080111
STATS driver hostname somebox
STATS driver startup time 0.051
FINISH planner date 20080111 time 82.721
SUCCESS dumper somebox /lib 20080111 0 [sec 0.209 kb 1970 kps 9382.2 orig-kb 1970]
SUCCESS chunker somebox /lib 20080111 0 [sec 0.305 kb 420 kps 1478.7]
STATS driver estimate somebox /lib 20080111 0 [sec 1 nkb 2002 ckb 480 kps 385]
INFO taper taper pid 28023
INFO taper Will write new label `TESTCONF01' to new tape
START taper datestamp 20080111 label TESTCONF01 tape 1
PART taper TESTCONF01 1 somebox /lib 20080111 1/-1 0 [sec 0.004722 kb 640 kps 135535.789920]
PART taper TESTCONF01 2 somebox /lib 20080111 2/-1 0 [sec 0.003438 kb 640 kps 186154.741129]
PART taper TESTCONF01 3 somebox /lib 20080111 3/-1 0 [sec 0.002931 kb 640 kps 218355.510065]
PART taper TESTCONF01 4 somebox /lib 20080111 4/-1 0 [sec 0.000578 kb 96 kps 166089.965398]
PARTIAL taper somebox /lib 20080111 4 0 [sec 0.011669 kb 2016 kps 172765.446911]
INFO taper tape TESTCONF01 kb 2016 fm 4 [OK]
INFO taper pid-done 28023
FINISH driver date 20080111 time 2167.581
EOF

$LogfileData{taper} = {
    programs => {
        planner => {
            start => "20080111",
            time  => "82.721",
        },
        driver => {
            start      => "20080111",
            start_time => "0.051",
            time       => "2167.581",
        },
        dumper  => {},
        chunker => {},
        taper   => {
            notes => [ "Will write new label `TESTCONF01' to new tape", ],
            tapes => {
                TESTCONF01 => {
                    date  => "20080111",
                    kb    => "2016",
                    files => "4",
                },
            },
        },
    },
   disklist => {
        somebox => {
            "/lib" => {
                estimate => {
                    level => "0",
                    sec   => "1",
                    nkb   => "2002",
                    ckb   => "480",
                    kps   => "385",
                },
                tries => [
                    {
                        dumper => {
                            status    => "success",
                            date      => "20080111",
                            level     => "0",
                            sec       => "0.209",
                            kb        => "1970",
                            kps       => "9382.2",
                            "orig-kb" => "1970",
                        },
                        chunker => {
                            status => "success",
                            date   => "20080111",
                            level  => "0",
                            sec    => "0.305",
                            kb     => "420",
                            kps    => "1478.7",
                        },
                        taper => {
                            status => "partial",
                            parts   => "4",
                            level  => "0",
                            sec    => "0.011669",
                            kb     => "2016",
                            kps    => "172765.446911",
                        },
                    },
                ],
                chunks => [
                    {
                        label => "TESTCONF01",
                        date  => "20080111",
                        file  => "1",
                        part  => "1",
                        sec   => "0.004722",
                        kb    => "640",
                        kps   => "135535.789920",
                    },
                    {
                        label => "TESTCONF01",
                        date  => "20080111",
                        file  => "2",
                        part  => "2",
                        sec   => "0.003438",
                        kb    => "640",
                        kps   => "186154.741129",
                    },
                    {
                        label => "TESTCONF01",
                        date  => "20080111",
                        file  => "3",
                        part  => "3",
                        sec   => "0.002931",
                        kb    => "640",
                        kps   => "218355.510065",
                    },
                    {
                        label => "TESTCONF01",
                        date  => "20080111",
                        file  => "4",
                        part  => "4",
                        sec   => "0.000578",
                        kb    => "96",
                        kps   => "166089.965398",
                    },
                ],
            },
        },
    },
};


$LogfileContents{simple} = <<EOF;
DISK planner somebox /lib
START planner date 20080111
START driver date 20080111
STATS driver hostname somebox
STATS driver startup time 0.051
FINISH planner date 20080111 time 82.721
START taper datestamp 20080111 label Conf-001 tape 1
SUCCESS dumper somebox /lib 20080111 0 [sec 0.209 kb 1970 kps 9382.2 orig-kb 1970]
SUCCESS chunker somebox /lib 20080111 0 [sec 0.305 kb 420 kps 1478.7]
STATS driver estimate somebox /lib 20080111 0 [sec 1 nkb 2002 ckb 480 kps 385]
PART taper Conf-001 1 somebox /lib 20080111 1/1 0 [sec 4.813543 kb 419 kps 87.133307]
DONE taper somebox /lib 20080111 1 0 [sec 4.813543 kb 419 kps 87.133307]
FINISH driver date 20080111 time 2167.581
EOF

$LogfileData{simple} = {
    programs => {
        planner => {
            start => "20080111",
            time  => "82.721",
        },
        driver => {
            start      => "20080111",
            start_time => "0.051",
            time       => "2167.581",
        },
        taper   => {
            tapes => {
                "Conf-001" => {
                    date => "20080111",
                },
            },
        },
        dumper  => {},
        chunker => {},
    },
    disklist => {
        somebox => {
            "/lib" => {
                estimate => {
                    nkb   => "2002",
                    kps   => "385",
                    ckb   => "480",
                    level => "0",
                    sec   => "1"
                },
                tries => [
                    {
                        dumper => {
                            status    => "success",
                            date      => "20080111",
                            level     => "0",
                            sec       => "0.209",
                            kb        => "1970",
                            kps       => "9382.2",
                            "orig-kb" => "1970",
                        },
                        taper => {
                            status => "done",
                            parts  => "1",
                            level  => "0",
                            sec    => "4.813543",
                            kb     => "419",
                            kps    => "87.133307",
                        },
                        chunker => {
                            status => "success",
                            date   => "20080111",
                            level  => "0",
                            sec    => "0.305",
                            kb     => "420",
                            kps    => "1478.7",
                        },
                    },
                ],
                chunks => [
                    {
                        label => "Conf-001",
                        date  => "20080111",
                        file  => "1",
                        part  => "1",
                        sec   => "4.813543",
                        kb    => "419",
                        kps   => "87.133307",
                    },
                ],
            },
        },
    },
};

$LogfileContents{fullExample} = <<EOF;
INFO amdump amdump pid 9291
INFO driver driver pid 9313
INFO planner planner pid 9312
DISK planner hostname.example.org /
DISK planner hostname.example.org /somedir2
DISK planner hostname.example.org /moreapps
DISK planner hostname.example.org /apps
DISK planner hostname.example.org /somedir
START planner date 20081002040002
START driver date 20081002040002
STATS driver hostname hostname.example.org
STATS driver startup time 0.043
INFO dumper dumper pid 9316
INFO dumper dumper pid 9315
INFO dumper dumper pid 9318
INFO dumper dumper pid 9317
INFO taper taper pid 9314
FINISH planner date 20081002040002 time 32.689
INFO planner pid-done 9312
INFO chunker chunker pid 11110
INFO dumper gzip pid 11129
SUCCESS dumper hostname.example.org /somedir 20081002040002 1 [sec 0.039 kb 10 kps 250.4 orig-kb 10]
SUCCESS chunker hostname.example.org /somedir 20081002040002 1 [sec 5.070 kb 10 kps 8.3]
INFO chunker pid-done 11110
STATS driver estimate hostname.example.org /somedir 20081002040002 1 [sec 0 nkb 42 ckb 64 kps 1024]
INFO dumper pid-done 11129
START taper datestamp 20081002040002 label FullBackup-14 tape 1
PART taper FullBackup-14 1 hostname.example.org /somedir 20081002040002 1/1 1 [sec 0.002776 kb 10 kps 3602.305476]
DONE taper hostname.example.org /somedir 20081002040002 1 1 [sec 0.002776 kb 10 kps 3602.305476]
INFO chunker chunker pid 11157
INFO dumper gzip pid 11232
SUCCESS dumper hostname.example.org /moreapps 20081002040002 1 [sec 0.039 kb 10 kps 250.8 orig-kb 10]
INFO dumper pid-done 11232
SUCCESS chunker hostname.example.org /moreapps 20081002040002 1 [sec 5.058 kb 10 kps 8.3]
INFO chunker pid-done 11157
STATS driver estimate hostname.example.org /moreapps 20081002040002 1 [sec 0 nkb 42 ckb 64 kps 149050]
PART taper FullBackup-14 2 hostname.example.org /moreapps 20081002040002 1/1 1 [sec 0.002656 kb 10 kps 3765.060241]
DONE taper hostname.example.org /moreapps 20081002040002 1 1 [sec 0.002656 kb 10 kps 3765.060241]
INFO chunker chunker pid 11700
INFO dumper gzip pid 11723
SUCCESS dumper hostname.example.org /apps 20081002040002 1 [sec 0.414 kb 6630 kps 16013.4 orig-kb 6630]
SUCCESS chunker hostname.example.org /apps 20081002040002 1 [sec 5.432 kb 6630 kps 1226.3]
INFO chunker pid-done 11700
INFO dumper pid-done 11723
STATS driver estimate hostname.example.org /apps 20081002040002 1 [sec 6 nkb 6662 ckb 6688 kps 1024]
PART taper FullBackup-14 3 hostname.example.org /apps 20081002040002 1/1 1 [sec 0.071808 kb 6630 kps 92329.545455]
DONE taper hostname.example.org /apps 20081002040002 1 1 [sec 0.071808 kb 6630 kps 92329.545455]
INFO chunker chunker pid 11792
INFO dumper gzip pid 11816
SUCCESS dumper hostname.example.org / 20081002040002 1 [sec 3.028 kb 8393 kps 2771.1 orig-kb 82380]
SUCCESS chunker hostname.example.org / 20081002040002 1 [sec 8.047 kb 8393 kps 1047.0]
INFO chunker pid-done 11792
STATS driver estimate hostname.example.org / 20081002040002 1 [sec 39 nkb 80542 ckb 40288 kps 1024]
INFO dumper pid-done 11816
PART taper FullBackup-14 4 hostname.example.org / 20081002040002 1/1 1 [sec 0.088934 kb 8392 kps 94368.875374]
DONE taper hostname.example.org / 20081002040002 1 1 [sec 0.088934 kb 8392 kps 94368.875374]
INFO dumper gzip pid 11861
SUCCESS dumper hostname.example.org /somedir2 20081002040002 0 [sec 372.700 kb 28776940 kps 77212.0 orig-kb 28776940]
PART taper FullBackup-14 5 hostname.example.org /somedir2 20081002040002 1/1 0 [sec 370.382399 kb 28776940 kps 77695.214669]
DONE taper hostname.example.org /somedir2 20081002040002 1 0 [sec 370.382399 kb 28776940 kps 77695.214669]
INFO dumper pid-done 11861
STATS driver estimate hostname.example.org /somedir2 20081002040002 0 [sec 28776940 nkb 28776972 ckb 28776992 kps 1]
INFO dumper pid-done 9315
INFO dumper pid-done 9317
INFO dumper pid-done 9316
INFO dumper pid-done 9318
INFO taper pid-done 9314
FINISH driver date 20081002040002 time 663.574
INFO driver pid-done 9313

EOF

$LogfileData{fullExample} = {
    programs => {
        amdump => {},
        dumper => {},
        driver => {
            time       => "663.574",
            start      => "20081002040002",
            start_time => "0.043",
        },
        planner => {
            time  => "32.689",
            start => "20081002040002",
        },
        chunker => {},
        taper =>
          { tapes => { "FullBackup-14" => { date => "20081002040002", }, }, },
    },
    disklist => {
        "hostname.example.org" => {
            "/" => {
                estimate => {
                    level => "1",
                    sec   => "39",
                    nkb => "80542",
                    kps   => "1024",
                    ckb   => "40288",
                },
                tries => [
                    {
                        chunker => {
                            status => "success",
                            date   => "20081002040002",
                            kps    => "1047.0",
                            level  => "1",
                            sec    => "8.047",
                            kb     => "8393"
                        },
                        taper => {
                            kps    => '94368.875374',
                            level  => '1',
                            sec    => '0.088934',
                            status => 'done',
                            parts  => '1',
                            kb     => '8392'
                        },
                        dumper => {
                            kps       => "2771.1",
                            level     => "1",
                            sec       => "3.028",
                            status    => "success",
                            date      => "20081002040002",
                            kb        => "8393",
                            "orig-kb" => "82380"
                        },
                    },
                ],
                chunks => [
                    {
                        kps   => "94368.875374",
                        sec   => "0.088934",
                        date  => "20081002040002",
                        part  => "1",
                        file  => "4",
                        kb    => "8392",
                        label => "FullBackup-14"
                    },
                ],
            },
            "/somedir2" => {
                estimate => {
                    nkb   => "28776972",
                    kps   => "1",
                    ckb   => "28776992",
                    level => "0",
                    sec   => "28776940"
                },
                tries => [
                    {
                        dumper => {
                            kps       => "77212.0",
                            level     => "0",
                            sec       => "372.700",
                            status    => "success",
                            date      => "20081002040002",
                            kb        => "28776940",
                            "orig-kb" => "28776940",
                        },
                        taper => {
                            kps    => "77695.214669",
                            level  => "0",
                            sec    => "370.382399",
                            status => "done",
                            parts  => "1",
                            kb     => "28776940",
                        },
                    },
                ],
                chunks => [
                    {
                        label => 'FullBackup-14',
                        date  => '20081002040002',
                        kps   => '77695.214669',
                        sec   => '370.382399',
                        part  => '1',
                        file  => '5',
                        kb    => '28776940',
                    }
                ],
            },
            "/moreapps" => {
                estimate => {
                    nkb   => "42",
                    kps   => "149050",
                    ckb   => "64",
                    level => "1",
                    sec   => "0"
                },
                'tries' => [
                    {
                        'chunker' => {
                            'kps'    => '8.3',
                            'level'  => '1',
                            'sec'    => '5.058',
                            'status' => 'success',
                            'date'   => '20081002040002',
                            'kb'     => '10'
                        },
                        'taper' => {
                            'kps'    => '3765.060241',
                            'level'  => '1',
                            'sec'    => '0.002656',
                            'status' => 'done',
                            'parts'  => '1',
                            'kb'     => '10'
                        },
                        'dumper' => {
                            'kps'     => '250.8',
                            'level'   => '1',
                            'sec'     => '0.039',
                            'status'  => 'success',
                            'date'    => '20081002040002',
                            'kb'      => '10',
                            'orig-kb' => '10'
                        }
                    }
                ],
                chunks => [
                    {
                        kps   => "3765.060241",
                        sec   => "0.002656",
                        date  => "20081002040002",
                        part  => "1",
                        file  => "2",
                        kb    => "10",
                        label => "FullBackup-14"
                    },
                ],
            },
            "/apps" => {
                estimate => {
                    nkb   => "6662",
                    kps   => "1024",
                    ckb   => "6688",
                    level => "1",
                    sec   => "6"
                },
                tries    => [
                    {
                        chunker => {
                            kps    => "1226.3",
                            level  => "1",
                            sec    => "5.432",
                            status => "success",
                            date   => "20081002040002",
                            kb     => "6630"
                        },
                        taper => {
                            kps    => "92329.545455",
                            level  => "1",
                            sec    => "0.071808",
                            status => "done",
                            parts  => "1",
                            kb     => "6630"
                        },
                        dumper => {
                            kps       => "16013.4",
                            level     => "1",
                            sec       => "0.414",
                            status    => "success",
                            date      => "20081002040002",
                            kb        => "6630",
                            "orig-kb" => "6630"
                        },
                    },
                ],
                chunks => [
                    {
                        kps   => "92329.545455",
                        sec   => "0.071808",
                        date  => "20081002040002",
                        part  => "1",
                        file  => "3",
                        kb    => "6630",
                        label => "FullBackup-14"
                    },
                ],
            },
            "/somedir" => {
                estimate => {
                    nkb   => "42",
                    kps   => "1024",
                    ckb   => "64",
                    level => "1",
                    sec   => "0"
                },
                tries => [
                    {
                        chunker => {
                            kps    => "8.3",
                            level  => "1",
                            sec    => "5.070",
                            status => "success",
                            date   => "20081002040002",
                            kb     => "10",
                        },
                        taper => {
                            kps    => "3602.305476",
                            level  => "1",
                            sec    => "0.002776",
                            status => "done",
                            parts  => "1",
                            kb     => "10",
                        },
                        dumper => {
                            kps       => "250.4",
                            level     => "1",
                            sec       => "0.039",
                            status    => "success",
                            date      => "20081002040002",
                            kb        => "10",
                            "orig-kb" => "10",
                        },
                    },
                ],
                chunks => [
                    {
                        kps   => "3602.305476",
                        sec   => "0.002776",
                        date  => "20081002040002",
                        part  => "1",
                        file  => "1",
                        kb    => "10",
                        label => "FullBackup-14",
                    },
                ],
            },
        },
    },
};

$LogfileContents{amflushExample} = <<EOF;
INFO amflush amflush pid 26036
DISK amflush localhost /backups/oracle
DISK amflush localhost /backups/mysql
DISK amflush localhost /usr/local/bin
DISK amflush localhost /etc
DISK amflush localhost /home
START amflush date 20090622075550
INFO driver driver pid 26076
START driver date 20090622075550
STATS driver hostname localhost
STATS driver startup time 0.011
INFO taper taper pid 26077
START taper datestamp 20090622075550 label DailyTapeDataSet-017 tape 1
PART taper DailyTapeDataSet-017 1 localhost /etc 20090620020002 1/1 1 [sec 2.504314 kb 36980 kps 14766.518895]
DONE taper localhost /etc 20090620020002 1 1 [sec 2.504314 kb 36980 kps 14766.518895]
PART taper DailyTapeDataSet-017 2 localhost /usr/local/bin 20090620020002 1/1 1 [sec 1.675693 kb 309 kps 184.632684]
DONE taper localhost /usr/local/bin 20090620020002 1 1 [sec 1.675693 kb 309 kps 184.632684]
INFO taper pid-done 26077
FINISH driver date 20090622075550 time 177.708
INFO driver pid-done 26076
INFO amflush pid-done 26075
EOF

$LogfileData{amflushExample} = {
    'programs' => {
        'taper' => {
            'tapes' => {
                'DailyTapeDataSet-017' => {
                    'date' => '20090622075550'
                },
            },
        },
        'amflush' => { 'start' => '20090622075550' },
        'driver'  => {
            'time'       => '177.708',
            'start_time' => '0.011',
            'start'      => '20090622075550'
        },
    },
    'disklist' => {
        'localhost' => {
            '/etc' => {
                'tries' => [
                    {
                        'taper' => {
                            'kps'    => '14766.518895',
                            'level'  => '1',
                            'sec'    => '2.504314',
                            'status' => 'done',
                            'parts'  => '1',
                            'kb'     => '36980'
                        },
                    },
                ],
                'chunks' => [
                    {
                        'kps'   => '14766.518895',
                        'sec'   => '2.504314',
                        'date'  => '20090620020002',
                        'part'  => '1',
                        'file'  => '1',
                        'kb'    => '36980',
                        'label' => 'DailyTapeDataSet-017'
                    },
                ],
                'estimate' => undef
            },
            '/backups/oracle' => {
                'tries'    => [],
                'estimate' => undef
            },
            '/usr/local/bin' => {
                'tries' => [
                    {
                        'taper' => {
                            'kps'    => '184.632684',
                            'level'  => '1',
                            'sec'    => '1.675693',
                            'status' => 'done',
                            'parts'  => '1',
                            'kb'     => '309'
                        },
                    },
                ],
                'chunks' => [
                    {
                        'kps'   => '184.632684',
                        'sec'   => '1.675693',
                        'date'  => '20090620020002',
                        'part'  => '1',
                        'file'  => '2',
                        'kb'    => '309',
                        'label' => 'DailyTapeDataSet-017'
                    },
                ],
                'estimate' => undef
            },
            '/home' => {
                'tries'    => [],
                'estimate' => undef
            },
            '/backups/mysql' => {
                'tries'    => [],
                'estimate' => undef
            },
        },
    },
};


foreach my $test ( keys %LogfileContents ) {

    unless ( exists $LogfileData{$test} ) {
        die "error: $test present in \%LogfileContents but not \%LogfileData\n";
    }

    my $report = Amanda::Report->new(write_logfile($LogfileContents{$test}));
    is_deeply( $report->{data}, $LogfileData{$test}, "data check: $test" );
}

#
# Test the report API
#
my $report =
  Amanda::Report->new( write_logfile( $LogfileContents{fullExample} ) );

is_deeply( [ $report->get_hosts() ],
    ['hostname.example.org'], 'check: Amanda::Report::get_hosts()' );

is_deeply(
    [ sort { $a cmp $b } $report->get_disks('hostname.example.org') ],
    [ '/', '/apps', '/moreapps', '/somedir', '/somedir2' ],
    'check: Amanda::Report::get_disks($hostname)'
);

is_deeply(
    [ sort { $a->[1] cmp $b->[1] } $report->get_dles() ],
    [
        [ 'hostname.example.org', '/' ],
        [ 'hostname.example.org', '/apps' ],
        [ 'hostname.example.org', '/moreapps' ],
        [ 'hostname.example.org', '/somedir' ],
        [ 'hostname.example.org', '/somedir2' ],
    ],
    'check: Amanda::Report::get_dles()'
);

is_deeply(
    $report->get_dle_info( "hostname.example.org", "/apps" ),
    {
        estimate => {
            nkb   => "6662",
            kps   => "1024",
            ckb   => "6688",
            level => "1",
            sec   => "6"
        },
        tries => [
            {
                chunker => {
                    kps    => "1226.3",
                    level  => "1",
                    sec    => "5.432",
                    status => "success",
                    date   => "20081002040002",
                    kb     => "6630"
                },
                taper => {
                    kps    => "92329.545455",
                    level  => "1",
                    sec    => "0.071808",
                    status => "done",
                    parts  => "1",
                    kb     => "6630"
                },
                dumper => {
                    kps       => "16013.4",
                    level     => "1",
                    sec       => "0.414",
                    status    => "success",
                    date      => "20081002040002",
                    kb        => "6630",
                    "orig-kb" => "6630"
                },
            },
        ],
        chunks => [
            {
                kps   => "92329.545455",
                sec   => "0.071808",
                date  => "20081002040002",
                part  => "1",
                file  => "3",
                kb    => "6630",
                label => "FullBackup-14"
            },
        ],
    },
    'check: Amanda::Report::get_dle_info($hostname, $disk)'
);

is_deeply(
    $report->get_dle_info( 'hostname.example.org', '/', 'estimate' ),
    {
        level => "1",
        sec   => "39",
        nkb   => "80542",
        kps   => "1024",
        ckb   => "40288",
    },
    'check: Amanda::Report::get_dle_info($hostname, $disk, $field)'
);

is_deeply(
    $report->get_program_info('planner'),
    {
        time  => "32.689",
        start => "20081002040002",
    },
    'check: Amanda::Report::get_program_info($program)'
);

is( $report->get_program_info( 'driver', 'start' ),
    "20081002040002",
    'check: Amanda::Report::get_program_info($program, $field)' );

# clean up
unlink($log_filename) if -f $log_filename;
