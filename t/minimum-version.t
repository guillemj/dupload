#!/usr/bin/perl
#
# Copyright © 2016-2017 Guillem Jover <guillem@debian.org>
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
test_needs_module('Test::MinimumVersion');

my @files = Test::Dupload::all_perl_files();

plan tests => scalar @files;

for my $file (@files) {
    minimum_version_ok($file, '5.14.2');
}
