package CPAN::Requirements::Dynamic::Describe;

use strict;
use warnings;

use Carp;

sub new {
	my ($class) = @_;
	return bless {}, $class;
}

my %relation = (
	requires => 'requirement',
	recommends => 'recommendation',
	suggests => 'suggestion',
);

sub describe {
	my ($self, $argument) = @_;
	return map { _describe_expression($_) } @{ $argument->{expressions} };
}

sub _describe_version_range {
	my ($version, $negate) = @_;
	if ($version =~ /^(?:>= )?(v?[\d.]+)$/) {
		return $negate ? " version less than $1" : " version $1";
	} else {
		my $word = $negate ? 'outside' : 'in';
		return " version $word range $version";
	}
}

sub _describe_action {
	my ($expression) = @_;

	if ($expression->{error}) {
		return "die with error: '$expression->{error}'"
	} elsif (my $prereqs = $expression->{prereqs}) {
		my @prereqs;
		my $phase = $expression->{phase} || 'runtime';
		my $relation = $expression->{relation} || 'requires';
		for my $module (sort keys %{ $expression->{prereqs} }) {
			my $tail = $expression->{prereqs}{$module} ? _describe_version_range($expression->{prereqs}{$module}) : '';
			push @prereqs, "add a $phase $relation{$relation} for $module$tail";
		}
		return join ' and ', @prereqs
	} else {
		return "no action";
	}
}

sub _describe_expression {
	my ($expression) = @_;

	my $condition = _describe_condition(!!0, 0, @{ $expression->{condition} });
	my $action = _describe_action($expression);
	return "If $condition then $action";
}

sub _describe_logical {
	my ($op, $anti_op, $negate, $level, @expressions) = @_;

	if ($negate) {
		# De Morgan's laws
		@expressions = map { [ 'not', @$_ ]} @expressions;
		return _describe_logical($anti_op, $op, !!0, $level, @expressions);
	} else {
		@expressions = map { $_->[0] eq $op ? @{$_}[1..$#$_] : $_ } @expressions;
		my @explained = map { _describe_condition(!!0, $level + 1, @$_) } @expressions;
		my $explained = join " $op ", @explained;
		return $level ? "($explained)" : $explained;
	}
}

my %conditions = (
	can_run => sub {
		my ($negate, $level, $command) = @_;
		my $word = $negate ? 'Can not' : 'Can';
		return "$word run command '$command'";
	},
	config_defined => sub {
		my ($negate, $level, $entry) = @_;
		my $word = $negate ? 'is not' : 'is';
		return "config setting '$entry' $word defined";
	},
	has_env => sub {
		my ($negate, $level, $entry) = @_;
		my $word = $negate ? 'is not' : 'is';
		return "environmental variable '$entry' $word defined";
	},
	has_perl => sub {
		my ($negate, $level, $range) = @_;
		return 'perl has' . _describe_version_range($range, $negate);
	},
	is_extended => sub {
		my ($negate, $level) = @_;
		my $word = $negate ? 'is not' : 'is';
		return "extended testing $word enabled";
	},
	is_os => sub {
		my ($negate, $level, @wanted) = @_;
		if (@wanted > 1) {
			my $word = $negate ? 'none' : 'any';
			return "operating system is $word of " . join ', ', @wanted;
		} else {
			my $word = $negate ? 'is not' : 'is';
			return "operating system $word '$wanted[0]'";
		}
	},
	is_os_type => sub {
		my ($negate, $level, $wanted) = @_;
		my $word = $negate ? 'is not' : 'is';
		return "operating system type $word '$wanted'";
	},
	is_smoker => sub {
		my ($negate, $level) = @_;
		my $word = $negate ? 'is not' : 'is';
		return "it $word a smoker";
	},
	want_xs => sub {
		my ($negate, $level) = @_;
		my ($word1, $word2, $word3) = $negate ? ('is not', 'or', 'is') : ('is', 'and', 'is not');
		return "a compiler $word1 available $word2 pure-perl $word3 asked for";
	},
	not => sub {
		my ($negate, $level, @command) = @_;
		return _describe_condition(!$negate, $level, @command);
	},
	and => sub {
		my ($negate, $level, @commands) = @_;
		return _describe_logical('and', 'or', $negate, $level, @commands);
	},
	or => sub {
		my ($negate, $level, @commands) = @_;
		return _describe_logical('or', 'and', $negate, $level, @commands);
	},
);

sub _describe_condition {
	my ($negate, $level, $command, @args) = @_;
	my $describer = $conditions{$command} or croak("No such command '$command' known");
	return $describer->($negate, $level, @args);
}

1;

# ABSTRACT: Describe dynamic prerequisites

=head1 DESCRIPTION

...

=method new

=method describe
