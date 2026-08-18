package Profweb::Model::Accounts;

use v5.14;
use strict;
use warnings;
use utf8;
use open qw(:encoding(UTF-8) :std);

use Mojo::Base -base;
has 'pg';

use Crypt::Argon2  qw( argon2id_pass argon2id_verify );
use Crypt::URandom qw( urandom );
use Mail::RFC822::Address;
use V;

=head1 NAME

Accounts - a module for managing a user account.

=head1 SYNOPSIS

This module needs a Mojo::Pg object to use the database.

A user can give either a name or an email or both. An email address is not required, for privacy and
ease of use reasons. Hence, a user can use his account even if he has not confirmed his email
address.

Registering a new user with a name, email and password. Email addresses are checked for syntax and
reply to a verification email. Passwords are not stored in clear but after secure derivation.
The user can give either a name or an email address. If no name is given, the email address is also
copied as a name. The user is later prompted to give the missing name or email address.

Checking the name/email and password to authenticate a user and log in.

Providing a session token for accessing private resources.

Logging out.

Changing the name, email or password of the user account.
The user can ask for an email addresse change. The new email address is registered only when the user
verifies his address.
The password can be changed when logged in, the user must give his old password again.

Asking for an email with a link to change the password, in case of a forgotten password.

Removing a user account. The account is kept as archived for some time and then deleted by a robot.

=cut

# matches users table, column status
my $STATUS_EMAIL_UNVERIFIED = 1;
my $STATUS_EMAIL_VERIFIED   = 2;

# matches users table, column subscription
my $STATUS_NO_SUBSCRIPTION = 1;
my $STATUS_SUBSCRIBED      = 2;
my %subscriptions          = ($STATUS_NO_SUBSCRIPTION => 'no subscription', $STATUS_SUBSCRIBED => 'subscribed');
sub STATUS_NO_SUBSCRIPTION { $subscriptions{$STATUS_NO_SUBSCRIPTION} }
sub STATUS_SUBSCRIBED      { $subscriptions{$STATUS_SUBSCRIBED} }

# matches users table, description varchar size
# NOTE I have not checked if the length measurement is the same for Perl and Postgresql
my $DESCRIPTION_MAX_CHARS = 1000;

# parameters used for Argon2 secure password storage, should be read from configuration
sub argon2_params {
  qw( argon2_saltsize argon2_t_cost argon2_m_factor argon2_parallelism argon2_tag_size );
}

# Paramters:
# - a hash with keys pg, log and argon2_params()
sub new {
  my ($class, %params) = @_;
  my %obj = ();
  $obj{pg} = $params{pg};
  $obj{$_} = defined $params{$_} ? $params{$_} : '' foreach argon2_params();

  bless \%obj, $class;
}

# use Argon2id to create a secure form of the password to be stored instead of the clear-text
# Parameters
# - clear_password: a string, the new clear-text password given by the user
# - args: a hash, the parameters for Argon2id, i.e. salt, t_cost, m_factor, parallelism and tag_size
sub secure_password {
  my ($self, $clear_password) = @_;
  my $salt = urandom($self->{argon2_saltsize});
  return argon2id_pass(
    $clear_password, $salt,
    $self->{argon2_t_cost},
    $self->{argon2_m_factor},
    $self->{argon2_parallelism},
    $self->{argon2_tag_size}
  );
}

# providing a stored "hashed" password and a user input password, check if they match
sub _verify_password {
  my ($self, $encoded, $password) = @_;
  argon2id_verify($encoded, $password);
}

# return true if the email is valid, false otherwise
sub _validate_email {
  my ($self, $email) = @_;
  return Mail::RFC822::Address::valid($email);
}

# return true if the password is valid, false otherwise
sub validate_password {
  my ($self, $password) = @_;
  return 0 unless $password =~ /\p{Letter}/;
  return 0 unless $password =~ /\d/;
  my $length = length($password);
  return $length >= $V::V_MIN_PWD && $length <= $V::V_MAX_PWD;
}

# return a formatted error message for DB failures
sub _db_error_str {
  my ($self, $error, $query, @params) = @_;
  return "DB error: '$query' " . join(', ', map { $_ || '' } @params) . " => '$error'";
}

# returns an empty string if success, an error message otherwise
sub add_user {
  my ($self, $name, $email, $password) = @_;

  return 'Parameter missing: name or email' unless $name || $email;
  return 'Parameter missing: password'      unless $password;
  return 'Parameter incorrect: email '      unless !$email || $self->_validate_email($email);
  return 'Parameter incorrect: password'    unless $self->validate_password($password);

  # NOTE if no name is given, the email address is copied as a name
  $name = $email unless $name;

  my $secpwd = $self->secure_password($password) or return 'secure password failed';

  my $query  = 'INSERT INTO users (name, email, secpwd) VALUES ($1, $2, $3)';
  my @params = ($name || undef, $email || undef, $secpwd);

  # turn empty strings into NULL for name and email or they won't be UNIQUE
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return '';
}

# returns an empty string if the name/email and password match, an error message otherwise
sub check_login {
  my ($self, $name, $email, $password) = @_;

  return 'Parameter missing: name or email' unless $name || $email;
  return 'Parameter missing: password'      unless $password;
  return 'Parameter incorrect: email '      unless !$email || $self->_validate_email($email);

  # password should be validated only when the user is created

  my $column = $name ? 'name' : 'email';
  my $query  = "SELECT secpwd FROM users WHERE $column = \$1";
  my @params = ($name || $email);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return "no user for '$column' = '$name'" if $res->rv < 1;
  my $secpwd = $res->array->[0] or return "no password for '$column' = '$name'";

  return $self->_verify_password($secpwd, $password) ? '' : 'password does not match';
}

# returns some infos on the account for display, using the parameters field (id, name or email) and
# a value
# returns a hash, if error the hash has only one key 'error' with value an error message
sub get_user_infos {
  my ($self, $field, $value) = @_;
  return (error => "Parameter missing: field")   unless $field;
  return (error => "Parameter missing: value")   unless $value;
  return (error => "Parameter incorrect: field") unless grep { $_ eq $field } qw(id name email);

  my $query = <<"EOS";
SELECT id, name, email, status, subscription, archived_at
FROM users
WHERE $field = \$1
EOS
  my @params = ($value);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 }
    or do { return (error => $self->_db_error_str($@, $query, @params)) };

  # NOTE don't forget that the array method is iterative
  $res = $res->array;
  if ($res && @{$res}) {
    return (
      id             => $res->[0],
      name           => $res->[1],
      email          => $res->[2],
      email_verified => ($res->[3] == 1 ? 'no' : 'yes'),
      subscription   => $subscriptions{$res->[4]},
      archived_at    => $res->[5]
    );
  }
  else {
    return (error => "No account found for $field '$value'.");
  }
}

# modify a user name (create or modify)
# returns an empty string if success, an error string otherwise
sub modify_user_name {
  my ($self, $user_id, $new_name) = @_;
  return 'Parameter missing: user id.'       unless $user_id;
  return 'Parameter missing: new user name.' unless $new_name;

  my $query  = 'UPDATE users SET name = $2 WHERE id = $1';
  my @params = ($user_id, $new_name);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return "No user for name '$user_id'." if $res->rv < 1;
  return '';
}

# modify the user email address and change a user status to email verified
# this method works for both post registration email validation and email address change
# returns an empty string if success, an error string otherwise
sub modify_user_email {
  my ($self, $user_id, $new_email) = @_;
  return 'Parameter missing: user id.'         unless $user_id;
  return 'Parameter missing: new user email.'  unless $new_email;
  return 'Parameter incorrect: new user email' unless $self->_validate_email($new_email);

  # this command is for users whose name is the same as the email address
  my $query = <<'EOS';
UPDATE users
SET name = $2, email = $2, status = $3
WHERE id = $1 AND email IS NOT NULL AND name = email
EOS
  my @params = ($user_id, $new_email, $STATUS_EMAIL_VERIFIED);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return '' if $res && $res->rv >= 1;

  $query  = "UPDATE users SET email = \$2, status = \$3 WHERE id = \$1 ; ";
  @params = ($user_id, $new_email, $STATUS_EMAIL_VERIFIED);
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return "No user for id '$user_id'." if $res->rv < 1;
  return '';
}

# modify the user password
# returns an empty string if success, an error string otherwise
sub modify_user_password {
  my ($self, $user_id, $new_password) = @_;
  return 'Parameter missing: user id.'            unless $user_id;
  return 'Parameter missing: new user password.'  unless $new_password;
  return 'Parameter incorrect: new user password' unless $self->validate_password($new_password);

  my $secpwd = $self->secure_password($new_password) or return 'secure password failed';

  my $query  = 'UPDATE users SET secpwd = $2 WHERE id = $1';
  my @params = ($user_id, $secpwd);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return "No user for id '$user_id'." if $res->rv < 1;
  return '';
}

# get the description field from user
# returns a hash, if error the hash has only one key 'error' with value an error message
sub get_user_description {
  my ($self, $user_id) = @_;
  return 'Parameter missing: user_id.' unless $user_id;

  my $query  = 'SELECT name, description FROM users WHERE id = $1';
  my @params = ($user_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 }
    or do { return (error => $self->_db_error_str($@, $query, @params)) };

  # NOTE don't forget that the array method is iterative
  $res = $res->array;
  if ($res && @{$res}) {
    return (name => $res->[0], description => $res->[1]);
  }
  else {
    return (error => "No account found for user id '$user_id'.");
  }
}

# write the description field from user
# returns an empty string if success, an error string otherwise
sub modify_user_description {
  my ($self, $user_id, $description) = @_;
  return 'Parameter missing: user_id.' unless $user_id;

  # description might be empty so that you can erase it
  if (length($description) > $DESCRIPTION_MAX_CHARS) {
    return 'Parameter incorrect: description is too long.';
  }

  my $query  = 'UPDATE users SET description = $2 WHERE id = $1';
  my @params = ($user_id, $description);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return "No user for id '$user_id'." if $res->rv < 1;
  return '';
}

# modifies the user subscription status
# returns an empty string if success, an error string otherwise
sub _modify_user_subscription {
  my ($self, $user_id, $subscription) = @_;
  return 'Parameter missing: user_id.'        unless $user_id;
  return 'Parameter missing: subscription.'   unless $subscription;
  return 'Parameter incorrect: subscription.' unless exists $subscriptions{$subscription};

  my $query  = 'UPDATE users SET subscription = $2 WHERE id = $1';
  my @params = ($user_id, $subscription);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return "No user for id '$user_id'." if $res->rv < 1;
  return '';
}

# set the subscription status to subscribed
# returns an empty string if success, an error string otherwise
sub subscribe_user {
  my ($self, $user_id) = @_;
  return 'Parameter missing: user_id.' unless $user_id;
  return $self->_modify_user_subscription($user_id, $STATUS_SUBSCRIBED);
}

# set the subscription status to no subscription
# returns an empty string if success, an error string otherwise
sub unsubscribe_user {
  my ($self, $user_id) = @_;
  return 'Parameter missing: user_id.' unless $user_id;
  return $self->_modify_user_subscription($user_id, $STATUS_NO_SUBSCRIPTION);
}

# sets the archived_at field to now
# returns an empty string if success, an error string otherwise
sub archive_user {
  my ($self, $user_id) = @_;
  return 'Parameter missing: user_id.' unless $user_id;

  my $query  = 'UPDATE users SET archived_at = now() WHERE id = $1';
  my @params = ($user_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return "No user for id '$user_id'." if $res->rv < 1;
  return '';
}

# sets the archived_at field to NULL
# returns an empty string if success, an error string otherwise
sub unarchive_user {
  my ($self, $user_id) = @_;
  return 'Parameter missing: user_id.' unless $user_id;

  my $query  = 'UPDATE users SET archived_at = NULL WHERE id = $1';
  my @params = ($user_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  return "No user for id '$user_id'." if $res->rv < 1;
  return '';
}

# add a payment made by the user, possibly to subscribe to the website
# Paramters:
# - amount in cents (to avoid dealing with floats)
sub add_user_payment {
  my ($self, $user_id, $amount, $currency, $received_at) = @_;

  return 'Parameter missing: user_id.'     unless $user_id;
  return 'Parameter missing: amount.'      unless $amount;
  return 'Parameter missing: currency.'    unless $currency;
  return 'Parameter missing: received_at.' unless $received_at;

  my $query = <<'EOS';
INSERT INTO user_payments (user_id, amount, received_at, currency)
VALUES ($1, $2, $3, $4)
EOS
  my @params = ($user_id, $amount, $received_at, $currency);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do {
    my $err_str = $self->_db_error_str($@, $query, @params);
    if ($err_str =~ /Key \(user_id\)=\($user_id\) is not present in table "users"/) {
      $err_str = "No user for id '$user_id'.";
    }
    return error => $err_str;
  };

  return '';
}

# get payments for a user
# returns a hash, if error the hash has only one key 'error' with value an error message
# if success, the hash has one user_id key and one payments key with value an array ref with one
# hash ref for each payment
sub get_user_payments {
  my ($self, $user_id) = @_;

  return 'Parameter missing: user_id.' unless $user_id;

  my $query  = 'SELECT id, amount, currency, received_at FROM user_payments WHERE user_id = $1';
  my @params = ($user_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };

  if ($res && $res->rv == 0) {
    return (user_id => $user_id, payments => []);
  }
  elsif ($res && $res->rv > 0) {

    # turn each array into a hash with field names
    my @payments = map { {id => $_->[0], amount => $_->[1], currency => $_->[2], received_at => $_->[3]} }
      @{$res->arrays->to_array};
    return (user_id => $user_id, payments => \@payments);
  }
  else {
    return (error => "No payment found for user id '$user_id'.");
  }

  return '';
}

1;
