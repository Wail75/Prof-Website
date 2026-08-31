package Profweb;

use Mojo::Base 'Mojolicious', -signatures;

use utf8;
use open qw(:std :encoding(UTF-8));

use Mojolicious::Plugin::Config;
use Mojo::Pg;
use Mojo::JWT;
use Mail::RFC822::Address;

use Profweb::Model::Emailer;
use Profweb::Model::Accounts;
use Profweb::Model::Prof;

our $VERSION = '0.93';


=encoding utf8

=head1 NAME

Profweb - a website for creating and doing quizzes to help you learn

=head1 DESCRIPTION

Profweb is a website that allows you to:

=over 4

=item *

create quizzes with questions and answer

=item *

do your quizzes and save the results

=back

The website asks you more often questions on which you erred more

=head1 FEATURES

The user can create quizs. A quiz has a list of items, i.e. a question and an answer. The user can
then do a quiz, responding to questions and the website tells him if his answers are correct or not.

The user's answers are saved and when a user starts a quiz, the first questions to be asked will be
those that the user hasn't answered yet or those with the most errors. There is a simple formula
that tries to balance these two conditions. At first, questions without user result are favored,
then it is a mix of low result count and low correct answers count, then, in the long run, questions
with more user mistakes are favored.

The user can do quizs from his dashboard page, where he can select which quiz to do. There is also
a direct link for each quiz so that the user can do one quiz in particular.

In a quiz page, the answer text input field takes the focus, so that you can directly type in your
response to the next question when the page reloads. Similarly, after entering a new item in the
quiz, the focus goes to the new item question text input field. Thus you should be able to enter
quiz items and answer questions with your keyboard only.

When editing a quiz item, the answer field does not remember your input to avoid unnecessary clutter.
Same thing with previous answers when doing a quiz.

The last used quiz (created, edited, added questions to or selected to do a quiz) is kept in the
session so that it is preselected. For example, after adding an item to quiz, if you go to the page
for doing quizzes, the quiz is already selected.

A user may choose to make his quiz public. Other users can then do this quiz, with their own results.
If a non logged in user tries to do a quiz, he may answer one question but he will then be asked to
create an account and log in.

=head1 DEPLOYMENT

See the DEPLOY file for help.

=head1 Sources

=head2 Favicons

The favicon comes from https://findicons.com/icon/227244/package_edutainment
Icon Pack: Nuvola
Designer: David Vignoni
License: GNU/GPL

=cut


# a general error message for a form with an absent/invalid CSRF token
my $csrf_failure_error_msg = 'You can not do that.';


sub make_pg_connec_string_from_conf {
  my $config = shift;
  return
      'postgresql://'
    . ($config->{postgresql_user}     || '') . ':'
    . ($config->{postgresql_password} || '') . '@'
    . ($config->{postgresql_host}     || '') . '/'
    . ($config->{postgresql_dbname}   || '')
    . ';port='
    . ($config->{postgresql_port} || '');
}

sub startup {
  my ($self) = shift;

  # security headers
  $self->hook(
    before_dispatch => sub ($c) {
      $c->res->headers->header('X-Frame-Options'           => 'DENY');
      $c->res->headers->header('X-Content-Type-Options'    => 'nosniff');
      $c->res->headers->header('Strict-Transport-Security' => 'max-age=3600');
      $c->res->headers->header(
        'Content-Security-Policy' => "default-src 'self'; frame-ancestors 'self'; form-action 'self';");
    }
  );

  # more detailed form validation
  $self->validator->add_check(min => sub ($v, $name, $value, $min) { length($value) < $min });
  $self->validator->add_check(max => sub ($v, $name, $value, $max) { length($value) > $max });
  $self->validator->add_check(
    diff_than => sub ($v, $name, $value, $than) {
      return 1 unless defined(my $other = $v->input->{$than});
      return $value eq $other;
    }
  );

  $self->helper(validate_email => sub ($c, $email) { Mail::RFC822::Address::valid($email) });
  $self->validator->add_check(
    email_syntax => sub ($v, $name, $value) {
      return !$self->validate_email($value);
    }
  );


  $self->helper(
    reports => sub ($c, $v) {
      return {map { $_ => $v->error($_) } @{$v->failed()}};
    }
  );

  # returns true if validation errors, creates stash values for general error message and previous
  # values to carry after a redirect
  # $prev_names is a reference to an array with the param values to report to the form again
  # $operation is a unique name to create an error message and a variable with the errors
  $self->helper(
    validation_failed => sub ($c, $v, $operation, @prev_names) {
      return 0 unless $v->has_error();

      if ($v->has_error('csrf_token')) {
        $c->flash(error => $csrf_failure_error_msg);
      }
      else {
        my $operation_var = (lc($operation) =~ s/ /_/gr);
        my %prevs         = ();
        foreach (@prev_names) { $prevs{"prev_${operation_var}_$_"} = $c->param($_) || '' }

        # save validation errors and report them through the redirect
        my $reports         = {map { $_ => $v->error($_) } @{$v->failed()}};
        my $errors_variable = "${operation_var}_errors";
        $c->flash(error => "$operation failed.", $errors_variable => $reports, %prevs);
      }
      return 1;
    }
  );

  # Configuration file
  my $config = $self->plugin('Config');

  $self->secrets($self->app->config->{app_secrets});

  # keep the default session expiration duration

  # remove the default Mojolicious favicon
  delete $self->static->extra->{'favicon.ico'};

  # Internationalization
  $self->plugin('I18N', default => 'en', support_url_langs => [qw(en fr)]);

  # database
  my $pg_conec_str = make_pg_connec_string_from_conf($config);
  $self->helper(pg => sub { state $pg = Mojo::Pg->new($pg_conec_str) });
  $self->pg->migrations->from_dir('migrations');
  $self->app->log->error('Mojo::Pg not started') unless $self->pg;
  $self->app->log->debug($self->pg->db->query('SELECT VERSION() AS version')->hash->{version});

  # account management
  my %account_params = map { $_ => $config->{$_} } Profweb::Model::Accounts::argon2_params();
  $self->helper(
    accounts => sub {
      state $accounts = Profweb::Model::Accounts->new(pg => $self->pg, %account_params);
    }
  );

  # NOTE this check needs the account
  $self->validator->add_check(
    pwd_syntax => sub ($v, $name, $value) {
      return !$self->accounts->validate_password($value);
    }
  );

  # email sending
  my %emailer_params = map { $_ => $config->{"email_$_"} } qw(api_host api_header api_token from);
  $self->helper(
    emailer => sub {
      state $emailer = Profweb::Model::Emailer->new(%emailer_params);
    }
  );

  # JWT for email verification
  my $jwt_obj = Mojo::JWT->new(secret => $config->{jwt_email_verify_secret});
  if ($jwt_obj) {

    $self->helper(jwt => sub { state $jwt = $jwt_obj });

  }
  else {
    $self->log->error("Mojo::JWT new failed.");
  }

  # Prof, the main Model, for running the quizzes
  $self->helper(
    prof => sub {
      state $prof = Profweb::Model::Prof->new(pg => $self->pg);
    }
  );

  #
  # Routing
  #

  my $r = $self->routes;
  $r->add_type(uuid => qr/[-0-9a-fA-F]+/);

  $r->any('/')->to('profweb#index')->name('index');

  ## User Account
  # registration
  $r->post('/register')->to('account#register')->name('register');
  $r->get('/verify-email')->to('account#verify_email')->name('verify_email');

  # log in and out
  $r->post('/login')->to('account#login')->name('login');
  $r->get('/logout')->to('account#logout')->name('logout');

  # recover password
  $r->get('/recover-password')->to('account#recover_password_form')->name('recover_password_form');
  $r->post('/recover-password')->to('account#recover_password')->name('recover_password');

  # with the JWT link from the password reset email
  $r->get('/reset-password')->to('account#reset_password_form')->name('reset_password_form');
  $r->post('/reset-password')->to('account#reset_password')->name('reset_password');

  # public profile
  $r->get('/profiles/<user-id:uuid>')->to('account#get_profile')->name('get_profile');

  # public quizzes
  $r->any([qw(GET POST)] => '/quizs/<author:uuid>/<quiz:num>')->to('profweb#do_quizs')->name('do_quizs');
  $r->get('/respond-question')->to('profweb#respond_question')->name('respond_question');

  ## logged in routes
  my $logged_in = $r->under('/')->to('account#logged_in');

  # dashboard
  $logged_in->any(['GET', 'POST'] => '/dashboard')->to('profweb#dashboard');

  ## User account
  my $account = $logged_in->any('/account')->to(controller => 'account');
  $account->any([qw(GET POST)] => '/')->to(action => 'account')->name('account');

  # routes without account id for the default account
  $account->post('/name')->to(action => 'modify_user_name')->name('modify_user_name');

  # ask to change the user email, it does not immediately change but it sends a confirmation email
  $account->post('/email')->to(action => 'ask_email_change')->name('ask_email_change');
  $account->post('/password')->to(action => 'modify_user_password')->name('modify_user_password');

  # public profiles
  $logged_in->post('/profiles')->to('account#modify_profile')->name('modify_profile');

  ## Author
  my $author = $logged_in->any('/author')->to(controller => 'author');
  $author->any([qw(GET POST)] => '/')->to(action => 'index')->name('author_index');
  $author->post('/add-quiz')->to(action => 'add_quiz')->name('add_quiz');
  $author->post('/update-quiz')->to(action => 'update_quiz')->name('update_quiz');
  $author->post('/update-quiz-name')->to(action => 'update_quiz_name')->name('update_quiz_name');
  $author->post('/delete-quiz')->to(action => 'delete_quiz')->name('delete_quiz');
  $author->post('/add-item')->to(action => 'create_item')->name('create_item');
  $author->post('/delete-item')->to(action => 'delete_item')->name('delete_item');
  $author->post('/update-item')->to(action => 'update_item')->name('update_item');
  $author->post('/add-new-item-to-quiz')->to(action => 'add_new_item_to_quiz')->name('add_new_item_to_quiz');

}

1;
