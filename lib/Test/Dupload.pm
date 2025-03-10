# Copyright © 2015-2017, 2022 Guillem Jover <guillem@debian.org>
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

package Test::Dupload;

use strict;
use warnings;

our $VERSION = '0.00';

our @EXPORT_OK = qw(
    all_perl_files
    test_get_data_path
    test_get_temp_path
    test_needs_author
    test_needs_module
    test_needs_command
);
our %EXPORT_TAGS = (
    needs => [ qw(
        test_needs_author
        test_needs_module
        test_needs_command
    ) ],
    paths => [ qw(
        all_perl_files
        test_get_data_path
        test_get_temp_path
     ) ],
);

use Exporter qw(import);
use Cwd;
use File::Find;
use File::Basename;
use File::Path qw(make_path);
use IPC::Cmd qw(can_run);
use Test::More;

sub _test_get_caller_dir
{
    my (undef, $path, undef) = caller 1;

    $path =~ s{\.t$}{};
    $path =~ s{^\./}{};

    return $path;
}

sub test_get_data_path
{
    my $path = shift;

    if (defined $path) {
        my $srcdir = $ENV{srcdir} || '.';
        return "$srcdir/$path";
    } else {
        return _test_get_caller_dir();
    }
}

sub test_get_temp_path
{
    my $path = shift // _test_get_caller_dir();
    $path = 't.tmp/' . fileparse($path);

    make_path($path);
    return $path;
}

sub test_get_perl_dirs
{
    return qw(t lib);
}

sub test_get_perl_files
{
    return qw(
        dupload
        dupload.conf
        hooks/debian-next-dinstall
        hooks/debian-source-only
        hooks/debian-transition
        hooks/openpgp-check
    );
}

sub all_perl_files
{
    my $filter = shift // qr/\.(?:pl|pm|t)$/;
    my @files = test_get_perl_files();
    my $scan_perl_files = sub {
        push @files, $File::Find::name if m/$filter/;
    };

    find($scan_perl_files, test_get_perl_dirs());

    return @files;
}

sub test_needs_author
{
    if (not $ENV{AUTHOR_TESTING}) {
        plan skip_all => 'developer test';
    }

    return;
}

sub test_needs_module
{
    my ($module, @imports) = @_;
    my ($package) = caller;

    require version;
    my $version = '';
    if (@imports >= 1 and version::is_lax($imports[0])) {
        $version = shift @imports;
    }

    eval qq{
        package $package;
        use $module $version \@imports;
        1;
    } or do {
        plan skip_all => "requires module $module $version";
    };

    return;
}

sub test_needs_command
{
    my $command = shift;

    if (not can_run($command)) {
        plan skip_all => "requires command $command";
    }

    return;
}

1;
