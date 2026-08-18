package Profweb::Model::Emailer;

use v5.14;
use strict;
use warnings;
use utf8;
use open qw(:encoding(UTF-8) :std);
use Data::Dumper;

use Mojo::UserAgent;

=head1 NAME

Emailer - a module for sending emails through an API.

=head1 SYNOPSIS

  use Profweb::Model::Emailer;

  my $emailer = Profweb::Model::Emailer->new('https://email.provider', 'token-DKJ65FAL');

  $emailer->send_email(to => 'foo@bar.com', text => 'Test');

=head1 DESCRIPTION

This module is for sending emails through a service provider's API. You may have to rewrite the
code to adapt it to your provider, in particular the headers for the tokens, the endpoint names.

=cut

# Parameters: use key/value
sub new {
  my ($class, %params) = @_;

  my %obj = (ua => Mojo::UserAgent->new());
  $obj{$_} = defined $params{$_} ? $params{$_} : '' foreach qw(api_host api_header api_token from);

  bless \%obj, $class;
}

# the arguments must match those from the API provider for sending emails. Blocking.
# By default, the 'from' address is taken from the object
# returns true if success, false otherwise
sub send_email {
  my ($self, %email_args) = @_;
  $email_args{from} = $self->{from} unless $email_args{from};

  my $endpoint = $self->{api_host} . '/send';

  my %headers = ('Content-Type' => 'application/json', 'Accept' => 'application/json');
  $headers{$self->{api_header}} = $self->{api_token} if $self->{api_header};

  my $res      = $self->{ua}->post($self->{api_host} . '/send', \%headers, json => \%email_args)->result;
  my $res_json = $res->json;

  if ($res_json && $res_json->{status} && $res_json->{status} eq 'pending') {
    return 1;
  }
  else {
    say "Profweb::Model::Emailer::send_mail failed, JSON result: '"
      . Dumper($res_json)
      . "', email args: "
      . Dumper(\%email_args);
    return 0;
  }
}

# test the access to the API
# returns true if success, false otherwise
sub ping {
  my ($self) = @_;

  my $endpoint = $self->{api_host} . '/ping';

  my %headers = ();
  $headers{$self->{api_header}} = $self->{api_token} if $self->{api_header};

  my $res = $self->{ua}->get($endpoint, \%headers)->result;

  if ($res->code == 200) {
    return 1;
  }
  else {
    say 'Profweb::Model::Emailer  send_email: status is not pending';
    return 0;
  }
}

1;
