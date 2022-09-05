#!/usr/bin/perl
#
# Copyright © 2022 Guillem Jover <guillem@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;
use warnings;

use Cwd qw(getcwd);
use File::Spec::Functions qw(rel2abs);
use File::Path qw(make_path remove_tree);
use File::Copy;
use File::Compare;

use Test::More;
use Test::Dupload qw(:paths);

my $srcdir = rel2abs($ENV{srcdir} || '.');
my $datadir = test_get_data_path();
my $tmpdir = test_get_temp_path();

my $mta = "$srcdir/t/bin/sendmail";

my @extra_files = qw(
    pkg-src.announce
    pkg-src_1.0-1.announce
    pkg-src_1.0-2.announce
    pkg-src_1.0.announce
    pkg-src_2.0.announce
    pkg-src_2.0-1.announce
);

my @upload_files = qw(
    pkg-bin_1.0-1_amd64.deb
    pkg-src_1.0-1.debian.tar
    pkg-src_1.0-1.dsc
    pkg-src_1.0-1_amd64.buildinfo
    pkg-src_1.0.orig.tar
);

my @tests = qw(
    bad-no-nickname
    bad-size-fields
    bad-size-disk
    bad-md5sums
    bad-sha1sums
    bad-sha256sums
    mail-announce
    mail-announce-obsolete-mailto
    mail-announce-visible
    mail-announce-no-archive
    mail-announce-extra
    mail-no-announce-no-extra
    method-copy-direct
    method-copy-queue
);

plan tests =>
    scalar @tests * 5 +
    scalar @tests * (scalar @upload_files + 1)
;

sub test_neutralize_variance
{
    my ($filename, $basedir) = @_;
    my $filenamenew = "$filename.new";

    return unless -e $filename;

    open my $fhnew, '>', $filenamenew
        or die "cannot open new $filenamenew: $!\n";
    open my $fh, '<', $filename
        or die "cannot open old $filename: $!\n";
    while (<$fh>) {
        s{\Q$basedir\E}{<<<BASEDIR>>>}g;
        s{X-dupload: .*}{X-dupload: <<<DUPLOAD_VERSION>>>}g;
        print { $fhnew } $_;
    }
    close $fh or die "cannot close $filename\n";
    close $fhnew or die "cannot close $filenamenew\n";

    rename $filenamenew, $filename
        or die "cannot rename $filenamenew to $filename\n";

    return;
}

sub test_file
{
    my ($ref, $gen) = @_;

    my $res;

    if ($ref eq '/dev/null' && ! -e $gen) {
        $res = 0;
    } else {
        $res = compare($ref, $gen);
    }
    if ($res) {
        system "diff -u '$ref' '$gen' >&2";
    }

    ok($res == 0, "generated file matches expected one ($ref)");

    return;
}

sub test_dupload
{
    my (%opts) = @_;

    my $datadir = $opts{datadir};
    my $testdir = rel2abs($opts{testdir});
    my $workdir = rel2abs($opts{workdir});
    my $remote = $opts{remote};
    my $changes = "$workdir/$opts{upload}.changes";
    my $logfile = "$workdir/$opts{upload}.upload";

    $opts{ref_rc} //= 0;
    $opts{ref_upload} //= "$datadir/ref.$remote.upload";
    $opts{ref_stdout} //= "$datadir/ref.$remote.stdout";
    $opts{cmd_stdout} //= "$workdir/cmd.$remote.stdout";
    $opts{ref_stderr} //= '/dev/null';
    $opts{cmd_stderr} //= "$workdir/cmd.$remote.stderr";
    $opts{ref_mtaout} //= "$datadir/ref.$remote.mta";
    $opts{cmd_mtaout} //= "$workdir/cmd.$remote.mta";

    my $dupload = $ENV{DUPLOAD_PROG} || './dupload';

    local $ENV{DUPLOAD_LOG_TIMESTAMP} = 'Wed Feb  2 00:00:00 2022';
    local $ENV{DUPLOAD_MTA_SPOOL} = $opts{cmd_mtaout};
    local $ENV{DUPLOAD_TEST_DIR} = $testdir;

    my @cmd = ($dupload);
    push @cmd, '--configfile', $opts{config};
    push @cmd, '--mta', $opts{mta} // $mta;
    push @cmd, '--to', $remote;
    push @cmd, @{$opts{args}} if exists $opts{args};
    push @cmd, $changes;

    my $ret = system "@cmd >$opts{cmd_stdout} 2>$opts{cmd_stderr}";
    # XXX: Currently the exit value is unreliable as we use die(), once
    # we switch to an explicit exit code, we can use the exact value.
    my $rc = !!($ret >> 8);
    ok($rc == $opts{ref_rc}, "dupload to remote $remote exit $rc == $opts{ref_rc}");

    test_neutralize_variance($opts{cmd_stdout}, $testdir);
    test_neutralize_variance($opts{cmd_mtaout}, $testdir);

    test_file($opts{ref_upload}, $logfile);
    test_file($opts{ref_stdout}, $opts{cmd_stdout});
    test_file($opts{ref_stderr}, $opts{cmd_stderr});
    test_file($opts{ref_mtaout}, $opts{cmd_mtaout});

    return;
}

my $config = rel2abs("$datadir/dupload.conf");

$ENV{PATH} = "$srcdir/t/bin:$ENV{PATH}";
$ENV{DUPLOAD_USER} = 'thisuser';
$ENV{DUPLOAD_HOST} = 'thishost';

remove_tree($tmpdir);

foreach my $test (@tests) {
    my $testdir = "$tmpdir/$test";
    my $workdir = "$testdir/work";

    make_path($workdir);
    make_path("$testdir/incoming");
    make_path("$testdir/queue");

    my $upload;
    if ($test =~ m/^bad-/) {
        $upload = 'pkg-src_1.0-1_' . $test;
    } else {
        $upload = 'pkg-src_1.0-1_amd64';
    }
    my $changes = "$upload.changes";

    my @copy_files = @upload_files;
    push @copy_files, $changes;
    if ($test =~ m/extra/) {
        push @copy_files, @extra_files;
    }

    foreach my $file (@copy_files) {
        copy("$datadir/$file", "$workdir/$file");
    }

    my %opts;
    if ($test !~ m/^mail/ or $test =~ m/^mail-no/) {
        $opts{ref_mtaout} = '/dev/null';
    }
    if ($test =~ m/^bad-/) {
        $opts{ref_rc} = 1;
        $opts{ref_stderr} //= "$datadir/ref.$test.stderr";
        $opts{ref_upload} //= '/dev/null';
    }

    test_dupload(
        datadir => $datadir,
        testdir => $testdir,
        workdir => $workdir,
        config => $config,
        remote => $test,
        upload => $upload,
        %opts,
    );

    foreach my $file ((@upload_files, $changes)) {
        my $destdir;

        if ($test =~ m/queue/) {
            $destdir = "$testdir/queue";
        } else {
            $destdir = "$testdir/incoming";
        }

        if ($test =~ m/^bad-/) {
            ok(! -e "$destdir/$file", "file $file not uploaded to $destdir");
        } else {
            ok(-e "$destdir/$file", "file $file correctly uploaded to $destdir");
        }
    }
}

1;
