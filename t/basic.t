#! perl

use strict;
use warnings;

use Test::More;
use Config;
use CPAN::Requirements::Dynamic;

my $dynamic = CPAN::Requirements::Dynamic->new(config => 'My::Config');

my $prereqs1 = $dynamic->parse({
	version => 1,
	expressions => [
		{ 
			condition => [ has_perl => "$]" ],
			prereqs => { Foo => "1.2" },
		},
		{
			condition => [ '!has_perl' => 5 ],
			prereqs => { Bar => "1.3" },
		},
		{
			condition => [ is_os => $^O ],
			prereqs => { Baz => "1.4" },
		},
		{
			condition => [ or => [ config_enabled => 'useperlio' ] ],
			prereqs => { Quz => "1.5" },
		},
		{
			condition => [ has_module => 'CPAN::Meta', '2' ],
			prereqs => { Wuz => "1.6" },
		},
		{
			condition => [ and => [ has_module => 'CPAN::Meta', '2' ], [ is_os => 'non-existent' ] ],
			prereqs => { Euz => "1.7" },
		},
	],
});

my $result = $prereqs1->as_string_hash;
is_deeply($result, { runtime => { requires => { Foo => '1.2', Baz => '1.4', Quz => '1.5', Wuz => '1.6' } } }) or diag explain $result;

done_testing;

sub My::Config::get {
	return $Config{$_[1]};
}
