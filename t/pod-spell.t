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
test_needs_module('Test::Spelling');
test_needs_command('aspell');

if (qx(aspell dicts) !~ m/en_US/) {
    plan skip_all => 'aspell en_US dictionary required for spell checking POD';
}

my @files = Test::Dupload::all_perl_files();

plan tests => scalar @files;

set_spell_cmd('aspell list --encoding UTF-8 -l en_US -p /dev/null');
add_stopwords(<DATA>);

for my $file (@files) {
    pod_file_spelling_ok($file);
}

__DATA__
