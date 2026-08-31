#! perl

use strict;
use warnings;

use Test::More;
use Config;
use CPAN::Requirements::Dynamic::Describe;

my $describer = CPAN::Requirements::Dynamic::Describe->new;

my ($first) = $describer->describe({
	version => 1,
	expressions => [
		{
			condition => [ 'has_perl', '5.030'],
			prereqs => {
				'Foo' => 'v1.2.3',
				'Bar' => '>= 2',
			},
		},
	],
});

my $first_expected = 'If perl has version 5.030 then add a runtime requirement for Bar version 2 and add a runtime requirement for Foo version v1.2.3';
is($first, $first_expected, 'First is as expected');

my ($second) = $describer->describe({
	version => 1,
	expressions => [
		{
			condition => [ 'and', [ 'is_smoker' ],  ['is_extended' ] ],
			phase => 'test',
			prereqs => {
				Foo => '>= 1',
				Bar => 0,
			},
		},
	],
});

my $second_expected = 'If it is a smoker and extended testing is enabled then add a test requirement for Bar and add a test requirement for Foo version 1';
is($second, $second_expected, 'Second is as expected');

done_testing;
