#!/usr/bin/perl
#
# Copyright © 2021 Guillem Jover <guillem@debian.org>
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

test_needs_author();
test_needs_command('shellcheck');

my @files = qw(
    hooks/debian-security-auth
);

my @shellcheck_opts = (
);

plan tests => scalar @files;

sub shell_syntax_ok
{
    my $file = shift;

    my $tags = qx(shellcheck @shellcheck_opts $file 2>&1);

    # Fixup the output:
    chomp $tags;

    my $ok = length $tags == 0;

    ok($ok, 'shellcheck');
    if (not $ok) {
        diag($tags);
    }

    return;
}

foreach my $file (@files) {
    shell_syntax_ok($file);
}
