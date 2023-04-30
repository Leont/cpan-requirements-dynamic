package CPAN::Requirements::Dynamic;

use strict;
use warnings;

use Carp 'croak';

sub version_satisfies {
	my ($version, $range) = @_;
	require CPAN::Meta::Requirements::Range;
	return CPAN::Meta::Requirements::Range->with_string_requirement($range)->accepts($version);
}

my %default_commands = (
	can_xs => sub {
		my ($self) = @_;
		require ExtUtils::HasCompiler;
		return ExtUtils::HasCompiler->can_compile_extension(config => $self->{config});
	},
	has_perl => sub {
		my ($self, $range) = @_;
		return version_satisfies($], $range);
	},
	has_module => sub {
		my ($self, $module, $range) = @_;
		require Module::Metadata;
		my $data = Module::Metadata->new_from_module($module);
		return !!0 unless $data;
		return !!1 if not defined $range;
		return version_satisfies($data->version($module), $range);
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
);

sub new {
	my ($class, %args) = @_;
	return bless {
		config        => $args{config},
		prereqs       => $args{prereqs}  || do { require CPAN::Meta::Prereqs; CPAN::Meta::Prereqs->new },
		commands      => $args{commands} || \%default_commands,
		pureperl_only => $args{'pureperl-only'},
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

	my ($function, @arguments) = @{ $condition };
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
	my @results;

	for my $entry (@{ $argument->{expressions} }) {
		push @results, CPAN::Meta::Prereqs->new($entry->{prereqs}) if $self->_run_condition($entry->{condition});
	}

	if (@results) {
		return $self->{prereqs}->with_merged_prereqs(\@results);
	} else {
		return $self->{prereqs};
	}

	return @results;
}

1;

# ABSTRACT: Dynamic prerequisites in meta files
