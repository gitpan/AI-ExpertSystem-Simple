package AI::ExpertSystem::Simple;

use strict;
use warnings;

use XML::Twig;

use AI::ExpertSystem::Simple::Rule;
use AI::ExpertSystem::Simple::Knowledge;
use AI::ExpertSystem::Simple::Goal;

our $VERSION = '1.0';

sub new {
	my ($class) = @_;

	die "Simple->new() takes no arguments" if scalar(@_) != 1;

	my $self = {};

	$self->{_rules} = ();
	$self->{_knowledge} = ();
	$self->{_goal} = undef;
	$self->{_filename} = undef;

	$self->{_ask_about} = undef;
	$self->{_told_about} = undef;

	return bless $self, $class;
}

sub load {
	my ($self, $filename) = @_;

	die "Simple->load() takes 1 argument" if scalar(@_) != 2;
	die "Simple->load() argument 1 (FILENAME) is undefined" if !defined($filename);

	if(-f $filename and -r $filename) {
		my $twig = XML::Twig->new(
			twig_handlers => { goal => sub { $self->_goal(@_) },
					   rule => sub { $self->_rule(@_) },
					   question => sub { $self->_question(@_) } }
		);

		$twig->safe_parsefile($filename);

		die "Simple->load() XML parse failed: $@" if $@;

		$self->{_filename} = $filename;

		return 1;
	} else {
		die "Simple->load() unable to use file";
	}
}

sub _goal {
	my ($self, $t, $node) = @_;

	my $attribute = undef;
	my $text = undef;

	my $x = ($node->children('attribute'))[0];
	$attribute = $x->text();

	$x = ($node->children('text'))[0];
	$text = $x->text();

	$self->{_goal} = AI::ExpertSystem::Simple::Goal->new($attribute, $text);

	eval { $t->purge(); }
}

sub _rule {
	my ($self, $t, $node) = @_;

	my $name = undef;

	my $x = ($node->children('name'))[0];
	$name = $x->text();

	if(!defined($self->{_rules}->{$name})) {
		$self->{_rules}->{$name} = AI::ExpertSystem::Simple::Rule->new($name);
	}

	foreach $x ($node->get_xpath('//condition')) {
		my $attribute = undef;
		my $value = undef;

		my $y = ($x->children('attribute'))[0];
		$attribute = $y->text();

		$y = ($x->children('value'))[0];
		$value = $y->text();

		$self->{_rules}->{$name}->add_condition($attribute, $value);

		if(!defined($self->{_knowledge}->{$attribute})) {
			$self->{_knowledge}->{$attribute} = AI::ExpertSystem::Simple::Knowledge->new($attribute);
		}
	}

	foreach $x ($node->get_xpath('//action')) {
		my $attribute = undef;
		my $value = undef;

		my $y = ($x->children('attribute'))[0];
		$attribute = $y->text();

		$y = ($x->children('value'))[0];
		$value = $y->text();

		$self->{_rules}->{$name}->add_action($attribute, $value);

		if(!defined($self->{_knowledge}->{$attribute})) {
			$self->{_knowledge}->{$attribute} = AI::ExpertSystem::Simple::Knowledge->new($attribute);
		}
	}

	eval { $t->purge(); }
}

sub _question {
	my ($self, $t, $node) = @_;

	my $attribute = undef;
	my $text = undef;
	my @responses = ();

	my $x = ($node->children('attribute'))[0];
	$attribute = $x->text();

	$x = ($node->children('text'))[0];
	$text = $x->text();

	foreach $x ($node->children('response')) {
		push(@responses, $x->text());
	}

	if(!defined($self->{_knowledge}->{$attribute})) {
		$self->{_knowledge}->{$attribute} = AI::ExpertSystem::Simple::Knowledge->new($attribute);
	}
	$self->{_knowledge}->{$attribute}->set_question($text, @responses);

	eval { $t->purge(); }
}

sub process {
	my ($self) = @_;

	die "Simple->process() takes no arguments" if scalar(@_) != 1;

	my $n = $self->{_goal}->name();

	if($self->{_knowledge}->{$n}->is_value_set()) {
		return 'finished';
	}

	if($self->{_ask_about}) {
		my %answers = ();

		$answers{$self->{_ask_about}} = $self->{_told_about};

		$self->{_ask_about} = undef;
		$self->{_told_about} = undef;

		while(%answers) {
			my %old_answers = %answers;
			%answers = ();

			foreach my $answer (keys(%old_answers)) {
				my $n = $answer;
				my $v = $old_answers{$answer};

				$self->{_knowledge}->{$n}->set_value($v);

				foreach my $key (keys(%{$self->{_rules}})) {
					if($self->{_rules}->{$key}->state() eq 'active') {
						if($self->{_rules}->{$key}->given($n, $v) eq 'completed') {
							my %y = $self->{_rules}->{$key}->actions();
							foreach my $k (keys(%y)) {
								$answers{$k} = $y{$k};
							}
						}
					}
				}
			}
		}

		return 'continue';
	} else {
		my %scoreboard = ();

		foreach my $rule (keys(%{$self->{_rules}})) {
			if($self->{_rules}->{$rule}->state() eq 'active') {
				my @listofquestions = $self->{_rules}->{$rule}->unresolved();
				my $ok = 1;
				my @questionstoask = ();
				foreach my $name (@listofquestions) {
					if($self->{_knowledge}->{$name}->has_question()) {
						push(@questionstoask, $name);
					} else {
						$ok = 0;
					}
				}

				if($ok == 1) {
					foreach my $name (@questionstoask) {
						$scoreboard{$name}++;
					}
				}
			}
		}

		my $max_value = 0;

		foreach my $name (keys(%scoreboard)) {
			if($scoreboard{$name} > $max_value) {
				$max_value = $scoreboard{$name};
				$self->{_ask_about} = $name;
			}
		}

		return $self->{_ask_about} ? 'question' : 'failed';
	}
}

sub get_question {
	my ($self) = @_;

	die "Simple->get_question() takes no arguments" if scalar(@_) != 1;

	return $self->{_knowledge}->{$self->{_ask_about}}->get_question();
}

sub answer {
	my ($self, $value) = @_;

	die "Simple->answer() takes 1 argument" if scalar(@_) != 2;
	die "Simple->answer() argument 1 (VALUE) is undefined" if ! defined($value);

	$self->{_told_about} = $value;
}

sub get_answer {
	my ($self) = @_;

	die "Simple->get_answer() takes no arguments" if scalar(@_) != 1;

	my $n = $self->{_goal}->name();

	return $self->{_goal}->answer($self->{_knowledge}->{$n}->get_value());
}

1;

=head1 NAME

AI::ExpertSystem::Simple - A simple expert system shell

=head1 VERSION

This document refers to verion 1.00 of AI::ExpertSystem::Simple, released April 25, 2003

=head1 SYNOPSIS

This class implements a simple expert system shell that reads the rules from an XML 
knowledge base and questions the user as it attempts to arrive at a conclusion.

=head1 DESCRIPTION

=head2 Overview

This class is where all the work is being done and the other three classes are only 
there for support. At present there is little you can do with it other than run it. Future 
version will make subclassing of this class feasable and features like logging will be introduced.

To see how to use this class there is a simple shell in the bin directory which allows you 
to consult the example knowledge bases and more extensive documemtation in the docs directory.

There is a Ruby version that reads the same XML knowledge bases, if you are interested.

=head2 Constructors and initialisation

=over 4

=item new( )

The constructor takes no arguments and just initialises a few basic variables.

=back

=head2 Public methods

=over 4

=item load( FILENAME )

This method takes the FILENAME of an XML knowledgebase and attempts to parse it to set up the data structures 
required for a consoltation.

=item process( )

Once the knowledgebase is loaded the consultation is run by repeatedly calling this method.

It returns four results:

=over 4

=item "question"

The system has a question to ask of the user.

The question and list of valid responses is available from the get_question( ) method and the users response should be returned via the answer( ) method. 

Then simply call the process( ) method again.

=item "continue"

The system has calculated some data but has nothing to ask the user but has still not finished.

This response will be removed in future versions.

Simply call the process( ) method again.

=item "finished"

The consoltation has finished and the system has an answer for the user which is available from the answer( ) method.

=item "failed"

The consoltation has finished and the system has failed to find an answer for the user. It happens.

=back

=item get_question( )

If the process( ) method has returned "question" then this method will return the question to ask the user 
and a list of valid responses.

=item answer( VALUE )

The user has been presented with the question from the get_question( ) method along with a set of 
valid responses and the users selection is returned by this method.

=item get_answer( )

If the process( ) method has returned "finished" then the answer to the users query will be 
returned by this method.

=back

=head2 Private methods

=over 4

=item _goal

A private method to get the goal data from the knowledgebase.

=item _rule

A private method to get the rule data from the knowledgebase.

=item _question

A private method to get the question data from the knowledgebase.

=back

=head1 ENVIRONMENT

None

=head1 DIAGNOSTICS

=over 4

=item Simple->new() takes no arguments

When the constructor is initialised it requires no arguments. This message is given if 
some arguments were supplied.

=item Simple->load() takes 1 argument

When the method is called it requires one argument. This message is given if more or 
less arguments were supplied.

=item Simple->load() argument 1 (FILENAME) is undefined

The corrct number of arguments were supplied with the method call, however the first 
argument, FILENAME, was undefined.

=item Simple->load() XML parse failed

XML Twig encountered some errors when trying to parse the XML knowledgebase.

=item Simple->load() unable to use file

The file supplied to the load( ) method could not be used as it was either not a file 
or not readable.

=item Simple->process() takes no arguments

When the method is called it requires no arguments. This message is given if 
some arguments were supplied.

=item Simple->get_question() takes no arguments

When the method is called it requires no arguments. This message is given if 
some arguments were supplied.

=item Simple->answer() takes 1 argument

When the method is called it requires one argument. This message is given if more or 
less arguments were supplied.

=item Simple->answer() argument 1 (VALUE) is undefined

The corrct number of arguments were supplied with the method call, however the first 
argument, VALUE, was undefined.

=item Simple->get_answer() takes no arguments

When the method is called it requires no arguments. This message is given if 
some arguments were supplied.

=back

=head1 BUGS

None

=head1 FILES

See the Simple.t file in the test directory and simpleshell in the bin directory.

=head1 SEE ALSO

AI::ExpertSystem::Simple::Goal - A utility class

AI::ExpertSystem::Simple::Knowledge - A utility class

AI::ExpertSystem::Simple::Rule - A utility class

=head1 AUTHORS

Peter Hickman (peterhi@ntlworld.com)

=head1 COPYRIGHT

Copyright (c) 2003, Peter Hickman. All rights reserved.

This module is free software. It may be used, redistributed and/or 
modified under the same terms as Perl itself.
