package CPAN::Requirements::Dynamic;

use strict;
use warnings;

use Carp 'croak';
use Text::ParseWords 'shellwords';

sub _version_satisfies {
	my ($version, $range) = @_;
	require CPAN::Meta::Requirements::Range;
	return CPAN::Meta::Requirements::Range->with_string_requirement($range)->accepts($version);
}

sub _is_interactive {
    return -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT)) ? 1 : 0;
}

sub _read_line {
    return undef if $ENV{PERL_MM_USE_DEFAULT} || !_is_interactive && eof STDIN;;

    my $answer = <STDIN>;
    chomp $answer if defined $answer;
    return $answer;
}

my %default_commands = (
	can_xs => sub {
		my ($self) = @_;
		require ExtUtils::HasCompiler;
		return ExtUtils::HasCompiler->can_compile_extension(config => $self->{config});
	},
	has_perl => sub {
		my ($self, $range) = @_;
		return _version_satisfies($], $range);
	},
	has_module => sub {
		my ($self, $module, $range) = @_;
		require Module::Metadata;
		my $data = Module::Metadata->new_from_module($module);
		return !!0 unless $data;
		return !!1 if not defined $range;
		return _version_satisfies($data->version($module), $range);
	},
	can_run => sub {
		my ($self, $command) = @_;
		require IPC::Cmd;
		return IPC::Cmd::can_run($command);
	},
	config_enabled => sub {
		my ($self, $entry) = @_;
		return $self->{config}->get($entry);
	},
	has_env => sub {
		my ($self, $entry) = @_;
		return $ENV{$entry};
	},
	is_os => sub {
		my ($self, $wanted) = @_;
		return $wanted eq $^O;
	},
	is_os_type => sub {
		my ($self, $wanted) = @_;
		require Perl::OSType;
		return Perl::OSType::is_os_type($wanted);
	},
	want_pureperl => sub {
		my ($self) = @_;
		return $self->{pureperl_only};
	},
	want_compiled => sub {
		my ($self) = @_;
		return defined $self->{pureperl_only} && $self->{pureperl_only} == 0;
	},
	y_n => sub {
		my ($mess, $default) = @_;

		die "y_n() called without a prompt message" unless $mess;
		die "Invalid default value: y_n() default must be 'y' or 'n'" if $default && $default !~ /^[yn]/i;

		while (1) {
			local $|=1;
			print "$mess [$default]";

			my $answer = _read_line;

			$answer = $default if !defined $answer or !length $answer;

			return 1 if $answer =~ /^y/i;
			return 0 if $answer =~ /^n/i;
			print "Please answer 'y' or 'n'.\n";
		}
	},
);

sub new {
	my ($class, %args) = @_;
	return bless {
		config        => $args{config}   || do { require ExtUtils::Config; ExtUtils::Config->new },
		prereqs       => $args{prereqs}  || do { require CPAN::Meta::Prereqs; CPAN::Meta::Prereqs->new },
		commands      => $args{commands} || \%default_commands,
		pureperl_only => $args{pureperl_only},
	}, $class;
}

sub _get_command {
	my ($self, $name) = @_;
	if ($name eq 'or') {
		return sub {
			my ($self, @each) = @_;
			for my $elem (@each) {
				return !!1 if $self->_run_condition($elem);
			}
			return !!0;
		};
	} elsif ($name eq 'and') {
		return sub {
			my ($self, @each) = @_;
			for my $elem (@each) {
				return !!0 if not $self->_run_condition($elem);
			}
			return !!1;
		};
	} else {
		return $self->{commands}{$name} || croak "No such command $name";
	}
}

sub _run_condition {
	my ($self, $condition) = @_;

	my ($function, @arguments) = shellwords($condition);
	if (my ($name) = $function =~ / ^ ! (\w+) $ /xms) {
		my $method = $self->_get_command($name);
		return not $self->$method(@arguments);
	} elsif (($name) = $function =~ / ^ (\w+) $ /xms) {
		my $method = $self->_get_command($name);
		return $self->$method(@arguments);
	} else {
		croak "Can\'t parse dynamic prerequisite '$function'";
	}
}

sub parse {
	my ($self, $argument) = @_;
	my $version = $argument->{version};
	my @prereqs;

	for my $entry (@{ $argument->{expressions} }) {
		if ($self->_run_condition($entry->{condition})) {
			if ($entry->{error}) {
				die "$entry->{error}\n";
			} elsif (my $prereqs = $entry->{prereqs}) {
				my $phase = $entry->{phase} || 'runtime';
				my $relation = $entry->{relation} || 'requires';
				my $prereqs = { $phase => { $relation => $entry->{prereqs} } };
				push @prereqs, CPAN::Meta::Prereqs->new($prereqs);
			}
		}
	}

	return $self->{prereqs}->with_merged_prereqs(\@prereqs);
}

1;

# ABSTRACT: Dynamic prerequisites in meta files

=head1 SYNOPSIS

 my $result = $dynamic->parse({
   expressions => [
     {
       condition => 'has_perl v5.20.0',
       prereqs => { Bar => "1.3" },
     },
     {
       condition => 'is_os linux',
       prereqs => { Baz => "1.4" },
     },
     {
       condition => 'config_enabled usethreads',
       prereqs => { Quz => "1.5" },
     },
     {
       condition => 'has_module CPAN::Meta 2' ],
       prereqs => { Wuz => "1.6" },
     },
     {
       condition => 'and "is_os openbsd" "config_enabled usethreads"',
       prereqs => { Euz => "1.7" },
     },
     {
       condition => '!is_os_type Unix',
       error => 'OS unsupported',
     }
   ],
 });

=head1 DESCRIPTION

This module implements

=method new(%options)

This constructor takes two (optional but recommended) named arguments

=over 4

=item * config

This is an L<ExtUtils::Config|ExtUtils::Config> (compatible) object for reading configuration.

=item * pureperl_only

This should be the value of the C<pureperl-only> flag.

=back

=method parse(%options)

This takes the following named arguments:

=over 4

=item * condition

The condition of the dynamic requirement. This is a shell-like string with a command name and zero or more arguments following it. The semantics are described below under L</Conditions>.

=item * prereqs

The prereqs is a hash with modules for keys and the required version as values (e.g. C<< { Foo => '1.234' } >>).

=item * phase

The phase of the requirements. This defaults to C<'runtime'>. Other valid values include C<'build'> and C<'test'>.

=item * relation

The relation of the requirements

=item * error

It will die with this error if set. The two messages C<"No support for OS"> and C<"OS unsupported"> have special meaning to CPAN Testers and are generally encouraged for situations that indicate not a failed build but an impossibility to build.

=back

C<condition> and one of C<prereqs> or C<error> are mandatory.

=head2 Conditions

=head3 can_xs

This returns true if a compiler appears to be available.

=head3 has_perl($version)

Returns true if the perl version satisfies C<$version>. C<$version> is interpreted exactly as in the CPAN::Meta spec (e.g. C<1.2> equals C<< '>= 1.2' >>).

=head3 has_module($module, $version = 0)

Returns true if a module is installed on the system. If a C<$version> is given, it will also check if that version is provided. C<$version> is interpreted exactly as in the CPAN::Meta spec.

=head3 is_os($os)

Returns true if the OS name equals C<$os>.

=head3 is_os_type($type)

Returns true if the OS type equals C<$type>. Typical values of C<$type> are C<'Unix'> or C<'Windows'>.

=head3 can_run($command)

Returns true if a C<$command> can be run.

=head3 config_enabled($variable)

This returns true if a specific configuration variable is true

=head3 has_env

This returns true if the given environmental variable is true.

=head3 want_pureperl

This returns true if the user has indicated they want a pure-perl build.

=head3 want_compiled

This returns true if the user has explicitly indicated they do not want a pure-perl build.

=head3 y_n($question, $default)

This will ask a question to the user, or use the default if no answer is given.

=head3 or

This takes an array or arrayrefs, each containing a condition expression. If at least one of the conditions is true this will also return true.

=head3 and

This takes an array or arrayrefs, each containing a condition expression. If all of the conditions are true this will also return true.
