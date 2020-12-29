#!/usr/bin/perl
#
# Copyright © 2016-2017, 2019 Guillem Jover <guillem@debian.org>
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

use Test::More;
use Test::Dupload qw(:needs);

my @files = Test::Dupload::all_perl_files();

plan tests => scalar @files;

my $PERL = $ENV{PERL} // $^X // 'perl';

# Detect compilation warnings that are not found with just «use warnings»,
# such as redefinition of symbols from multiple imports. We cannot use
# Test::Strict::syntax_ok because it does not pass -w to perl, and does not
# check for other issues whenever perl states the syntax is ok.
sub syntax_ok {
    my $file = shift;

    my $eval = qx($PERL -cw \"$file\" 2>&1);
    my $ok = ($eval =~ s{^\Q$file\E syntax OK\n$}{}ms) && length $eval == 0;

    ok($ok, "Compilation check $file");
    if (not $ok) {
        diag($eval);
    }

    return;
}

for my $file (@files) {
    syntax_ok($file);
}
