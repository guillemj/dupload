#!/usr/bin/perl
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
test_needs_module('Test::Perl::Critic');

my @policies = qw(
    BuiltinFunctions::ProhibitBooleanGrep
    BuiltinFunctions::ProhibitLvalueSubstr
    BuiltinFunctions::ProhibitReverseSortBlock
    BuiltinFunctions::ProhibitSleepViaSelect
    BuiltinFunctions::ProhibitStringySplit
    BuiltinFunctions::ProhibitUniversalCan
    BuiltinFunctions::ProhibitUniversalIsa
    BuiltinFunctions::ProhibitUselessTopic
    BuiltinFunctions::ProhibitVoidGrep
    BuiltinFunctions::ProhibitVoidMap
    BuiltinFunctions::RequireBlockGrep
    BuiltinFunctions::RequireBlockMap
    BuiltinFunctions::RequireGlobFunction
    BuiltinFunctions::RequireSimpleSortBlock
    ClassHierarchies::ProhibitAutoloading
    ClassHierarchies::ProhibitExplicitISA
    ClassHierarchies::ProhibitOneArgBless
    CodeLayout::ProhibitHardTabs
    CodeLayout::ProhibitParensWithBuiltins
    CodeLayout::ProhibitQuotedWordLists
    CodeLayout::ProhibitTrailingWhitespace
    CodeLayout::RequireConsistentNewlines
    ControlStructures::ProhibitCStyleForLoops
    ControlStructures::ProhibitLabelsWithSpecialBlockNames
    ControlStructures::ProhibitMutatingListFunctions
    ControlStructures::ProhibitNegativeExpressionsInUnlessAndUntilConditions
    ControlStructures::ProhibitUntilBlocks
    ControlStructures::ProhibitYadaOperator
    Documentation::RequirePackageMatchesPodName
    Documentation::RequirePodSections
    ErrorHandling::RequireCheckingReturnValueOfEval
    InputOutput::ProhibitBarewordFileHandles
    InputOutput::ProhibitInteractiveTest
    InputOutput::ProhibitJoinedReadline
    InputOutput::ProhibitOneArgSelect
    InputOutput::ProhibitReadlineInForLoop
    InputOutput::ProhibitTwoArgOpen
    InputOutput::RequireBracedFileHandleWithPrint
    InputOutput::RequireEncodingWithUTF8Layer
    Miscellanea::ProhibitFormats
    Miscellanea::ProhibitTies
    Miscellanea::ProhibitUnrestrictedNoCritic
    Miscellanea::ProhibitUselessNoCritic
    Modules::ProhibitAutomaticExportation
    Modules::ProhibitConditionalUseStatements
    Modules::ProhibitEvilModules
    Modules::ProhibitMultiplePackages
    Modules::RequireBarewordIncludes
    Modules::RequireEndWithOne
    Modules::RequireExplicitPackage
    Modules::RequireNoMatchVarsWithUseEnglish
    Objects::ProhibitIndirectSyntax
    References::ProhibitDoubleSigils
    RegularExpressions::ProhibitCaptureWithoutTest
    RegularExpressions::ProhibitComplexRegexes
    RegularExpressions::ProhibitFixedStringMatches
    RegularExpressions::ProhibitSingleCharAlternation
    RegularExpressions::ProhibitUnusedCapture
    RegularExpressions::ProhibitUnusualDelimiters
    RegularExpressions::ProhibitUselessTopic
    RegularExpressions::RequireBracesForMultiline
    RegularExpressions::RequireExtendedFormatting
    Subroutines::ProhibitAmpersandSigils
    Subroutines::ProhibitBuiltinHomonyms
    Subroutines::ProhibitExplicitReturnUndef
    Subroutines::ProhibitNestedSubs
    Subroutines::ProhibitReturnSort
    Subroutines::ProhibitUnusedPrivateSubroutines
    Subroutines::ProtectPrivateSubs
    TestingAndDebugging::ProhibitNoStrict
    TestingAndDebugging::ProhibitNoWarnings
    TestingAndDebugging::ProhibitProlongedStrictureOverride
    TestingAndDebugging::RequireTestLabels
    TestingAndDebugging::RequireUseStrict
    TestingAndDebugging::RequireUseWarnings
    ValuesAndExpressions::ProhibitCommaSeparatedStatements
    ValuesAndExpressions::ProhibitComplexVersion
    ValuesAndExpressions::ProhibitInterpolationOfLiterals
    ValuesAndExpressions::ProhibitLongChainsOfMethodCalls
    ValuesAndExpressions::ProhibitMismatchedOperators
    ValuesAndExpressions::ProhibitMixedBooleanOperators
    ValuesAndExpressions::ProhibitQuotesAsQuotelikeOperatorDelimiters
    ValuesAndExpressions::ProhibitSpecialLiteralHeredocTerminator
    ValuesAndExpressions::ProhibitVersionStrings
    ValuesAndExpressions::RequireConstantVersion
    ValuesAndExpressions::RequireInterpolationOfMetachars
    ValuesAndExpressions::RequireQuotedHeredocTerminator
    ValuesAndExpressions::RequireUpperCaseHeredocTerminator
    Variables::ProhibitAugmentedAssignmentInDeclaration
    Variables::ProhibitConditionalDeclarations
    Variables::ProhibitLocalVars
    Variables::ProhibitPerl4PackageNames
    Variables::ProhibitUnusedVariables
    Variables::ProtectPrivateVars
    Variables::RequireLexicalLoopIterators
    Variables::RequireNegativeIndices
);

Test::Perl::Critic->import(
    -profile => 't/critic/perlcriticrc',
    -verbose => 8,
    -include => \@policies,
    -only => 1,
);

my @files = Test::Dupload::all_perl_files();

plan tests => scalar @files;

for my $file (@files) {
    critic_ok($file);
}
