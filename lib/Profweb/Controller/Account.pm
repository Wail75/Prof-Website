package Profweb::Controller::Account;

use Mojo::Base 'Mojolicious::Controller';
use V;
use Mojo::JWT;

my $email_topic = 'Profweb Website';

sub log_context {
  my ($c, $method_name) = @_;
  return $c->app->log->context('[ControllerAccount]', "[$method_name]");
}

# send an email to a newly registered user with a link to verify that he can read his emails
sub _send_verification_email {
  my ($c, $email_address) = @_;

  my $log = $c->log_context("_send_verification_email '$email_address'");
  $log->info("start.");

  return unless $email_address;

  my $token = $c->app->jwt->claims({user_id => $c->session('id'), email => $email_address})->encode;
  my $url   = $c->url_for('verify_email')->to_abs->query(jwt => $token);
  $c->stash(url => $url);
  my $email_text = $c->render_to_string(template => 'account/verification', format => 'email');
  my $res        = $c->app->emailer->send_email(
    to      => [$email_address],
    subject => '[' . $c->l($email_topic) . '] ' . $c->l('Verify your email address'),
    text    => $email_text
  );
  $res ? $log->info("done.") : $log->info("failed.");

  return $res;
}

# send an email to a registered user with a link to verify that he can read his emails
sub _send_verification_email_change {
  my ($c, $email_address) = @_;

  my $log = $c->log_context("_send_verification_email_change '$email_address'");
  $log->info("start.");

  return unless $email_address;

  my $token = $c->app->jwt->claims({user_id => $c->session('id'), email => $email_address})->encode;
  my $url   = $c->url_for('verify_email')->to_abs->query(jwt => $token);
  $c->stash(url => $url);
  my $email_text = $c->render_to_string(template => 'account/email_change', format => 'email');
  my $res        = $c->app->emailer->send_email(
    to      => [$email_address],
    subject => '[' . $c->l($email_topic) . '] ' . $c->l('Verify your email address'),
    text    => $email_text
  );
  $res ? $log->info("done.") : $log->info("failed.");

  return $res;
}

# register a new user with a name and/or an email and a password. Send an email for verification.
sub register {
  my $c = shift;
  my ($err, $msg) = ('', '');

  # Check params
  my $v = $c->validation();
  $v->csrf_protect;
  $v->optional('name',  'trim', 'not_empty')->min($V::V_MIN_NAME)->max($V::V_MAX_NAME);
  $v->optional('email', 'trim', 'not_empty')->min($V::V_MIN_EMAIL)->max($V::V_MAX_EMAIL)->email_syntax();
  $v->required('pwd1', 'not_empty')->min($V::V_MIN_PWD)->max($V::V_MAX_PWD)->pwd_syntax();
  $v->required('pwd2', 'not_empty')->equal_to('pwd1');

  # user must give either a name or an email
  if (!($v->is_valid('name') || $v->is_valid('email'))) {
    $v->error('name&email' => ['presence']);
  }
  return $c->redirect_to('index') if $c->validation_failed($v, 'Registration', 'name', 'email');

  my ($name, $email) = ($c->param('name') || '', $c->param('email') || '');
  my ($pwd, $pwd1) = ($c->param('pwd1'), $c->param('pwd2'));

  my $log = $c->log_context("register '$name'/'$email'");
  $log->info('start.');
  my $res = $c->accounts->add_user($name, $email, $pwd);
  if (!$res) {
    $log->info('done.');
    $msg = 'You are now registered.';
    $c->log_user_in($name || $email);
    $c->_send_verification_email($email) if $email;
  }
  else {
    $log->warn("failed '$res'.");
    if ($res =~ /Key \(name\)=\($name\) already exists/) {
      $err = 'This name is not available.';
    }
    else {
      $err = 'Registration failed.';
    }
  }

  if (!$err) {
    $c->flash(message => $msg) if $msg;
    $c->redirect_to('account');
  }
  else {
    $c->flash(error => $err);
    $c->redirect_to('index');
  }
}

# a registered user comes back with a verification link, verify his email address
sub verify_email {
  my $c = shift;

  my $log = $c->log_context("verify_email");
  $log->info("start.");

  my $jwt = $c->param('jwt') || '';
  if (!$jwt) {
    $log->warn("no jwt param '" . $c->req->url . "'.");
    return $c->flash(error => 'The email verification link is incorrect.')->redirect_to('index');
  }
  my ($user_id, $email_address);
  eval {
    my $claims = $c->app->jwt->decode($jwt);
    $user_id       = $claims->{user_id};
    $email_address = $claims->{email};
  } or do {
    $log->warn("jwt decode failed '" . $c->req->url . "': '$@'.");
    return $c->flash(error => 'The email verification link is incorrect.')->redirect_to('index');
  };

  my $res = $c->accounts->modify_user_email($user_id, $email_address);
  if ($res) {
    $log->warn("'$email_address' failed '$res'.");
    $c->flash(message => 'Your email address could not be verified.');
  }
  else {
    $log->info("'$email_address' done.");
    $c->flash(message => 'Your email address has been successfully verified.');
  }
  $c->redirect_to('index');
}

# make so that the user is considered logged in
sub log_user_in {
  my ($c, $name) = @_;
  $c->session(name => $name);

  my %res = $c->accounts->get_user_infos(name => $name);
  if ($res{error}) {
    $c->log->warn("log_user_in('$name') error '$res{error}'.");
  }
  else {
    $c->session(id    => $res{id});
    $c->session(email => $res{email});
  }
}

# returns true if the user is logged in, false otherwise
sub logged_in {
  my $c = shift;
  if (!$c->session('id')) {
    return $c->flash(error => 'You need to log in first.')->redirect_to('index');
  }
  return 1;
}

sub login {
  my $c = shift;

  my $res;
  my ($err, $msg) = ('', '');
  my $failed_login_err = 'Login failed.';

  if ($c->session('name')) {
    return $c->flash(message => 'You are already logged in.')->redirect_to('dashboard');
  }

  my $v = $c->validation();
  $v->csrf_protect()->required('name', 'not_empty')->required('pwd', 'not_empty');
  if ($c->validation_failed($v, 'Login')) {

    # param-level validation model does not fit very well this case so use another variable
    # also, it's ok if a failed CSRF token shows that error message
    $err = 'You must give a user name and a password in order to connect.';
    return $c->flash(login_error => $err)->redirect_to('index');
  }

  my ($name, $pwd) = ($c->param('name'), $c->param('pwd'));

  my $log = $c->log_context("login '$name'");
  if ($res = $c->accounts->check_login($name, '', $pwd)) {
    $err = 'Wrong user name or password.';
    $log->warn("failed '$res'.");
    return $c->flash(error => $failed_login_err, login_error => $err)->redirect_to('index');
  }
  else {
    $c->log_user_in($name);
    $msg = 'Login successful.';
  }

  $log->info("done.");
  $c->flash(message => $msg) if $msg;
  return $c->redirect_to('dashboard');
}

sub logout {
  my $c = shift;
  $c->session(expires => 1);
  $c->flash(error => 'You are now logged out.');
  $c->redirect_to('index');
}

sub account {
  my $c       = shift;
  my $user_id = $c->session('id') || '';
  if (!$user_id) {
    $c->flash(error => 'You need to log in first.');
    return $c->redirect_to('index');
  }
  my %data = $c->accounts->get_user_infos(id => $user_id);
  $c->stash('id',             $user_id);
  $c->stash('name',           $data{name});
  $c->stash('email',          $data{email});
  $c->stash('email_verified', $data{email_verified});

  # do your thing here

  return $c->render();
}

sub modify_user_name {
  my $c = shift;
  my ($err, $msg) = ('', '');

  my $user_id = $c->session('id') || '';
  return $c->flash(error => 'You need to log in first.')->redirect_to('index') unless $user_id;
  my $user_name = $c->session('name') || '';

  my $v = $c->validation();
  $v->csrf_protect();
  $v->required('new-name', 'trim', 'not_empty')->min($V::V_MIN_NAME)->max($V::V_MAX_NAME);
  if ($v->is_valid('new-name') && $user_name eq $c->param('new-name')) {
    $v->error('new-name' => ['original']);
  }
  return $c->redirect_to('account') if $c->validation_failed($v, 'Name change', 'new-name');

  my $new_name = $c->param('new-name');

  my $log = $c->log_context("modify_user_name '$user_id'/'$new_name'");
  $log->info("start.");
  my $res = $c->accounts->modify_user_name($user_id, $new_name);
  if (!$res) {
    $msg = 'Your name has been changed.';
    $c->session('name' => $new_name);
    $log->info("done.");
  }
  else {
    $err = 'Name change failed.';
    $log->warn("failed '$res'.");
  }

  $c->flash(error   => $err) if $err;
  $c->flash(message => $msg) if $msg;
  $c->redirect_to('account');
}

# check a potential new email address and send a confirmation email
sub ask_email_change {
  my $c = shift;
  my ($err, $msg) = ('', '');

  my $user_id = $c->session('id') || '';
  return $c->flash(error => 'You need to log in first.')->redirect_to('index') unless $user_id;

  my $v = $c->validation();
  $v->csrf_protect();
  $v->required('new-email', 'trim', 'not_empty')->min($V::V_MIN_EMAIL)->max($V::V_MAX_EMAIL)->email_syntax();
  return $c->redirect_to('account') if $c->validation_failed($v, 'Ask email change', 'new-email');

  my $new_email = $c->param('new-email');

  my $log = $c->log_context("change_user_email '$user_id'/'$new_email'");
  $log->info("start.");
  my %res = $c->accounts->get_user_infos(id => $user_id);
  if (!%res || !exists $res{email}) {
    $err = 'This action can not be done for the moment. Please retry later.';
    $log->warn("failed no result from get_user_infos(id => $user_id).");
    return $c->flash(error => $err)->redirect_to('account');
  }

  if ($res{email} && $res{email} eq $new_email) {
    $log->warn("failed current email is the same as new email.");
    $v->error('new-email' => ['original']);
    $c->validation_failed($v, 'Ask email change', 'new-email');
    return $c->redirect_to('account');
  }

  my $res = $c->_send_verification_email_change($new_email);
  if ($res) {
    $msg = 'We have sent you an email to confirm your new email address.';
    $log->info("done.");
  }
  else {
    $err = 'This action can not be done for the moment. Please retry later.';
    $log->warn("failed no result from get_user_infos(id => $user_id).");
  }

  $c->flash(error   => $err) if $err;
  $c->flash(message => $msg) if $msg;
  $c->redirect_to('account');
}

sub modify_user_password {
  my $c = shift;
  my ($err, $msg) = ('', '');

  my $user_id = $c->session('id') || '';
  return $c->flash(error => 'You need to log in first.')->redirect_to('index') unless $user_id;
  my $user_name = $c->session('name') || '';

  my $v = $c->validation();
  $v->csrf_protect;
  $v->required('current-pwd', 'not_empty');
  $v->required('new-pwd1',    'not_empty')->min($V::V_MIN_PWD)->max($V::V_MAX_PWD)->pwd_syntax();
  $v->required('new-pwd2',    'not_empty');
  if ($v->is_valid('current-pwd')) {
    $v->topic('new-pwd1')->diff_than('current-pwd');
    if ($c->accounts->check_login($user_name, '', $c->param('current-pwd'))) {
      $v->error('current-pwd' => ['correct']);
    }
    $v->topic('new-pwd2')->equal_to('new-pwd1') if $v->is_valid('new-pwd1');
  }
  return $c->redirect_to('account') if $c->validation_failed($v, 'Password change');

  my $current_pwd = $c->param('current-pwd');
  my $new_pwd1    = $c->param('new-pwd1');
  my $new_pwd2    = $c->param('new-pwd2');

  my $log = $c->log_context("modify_user_password '$user_id'");
  $log->info("start.");
  my $res = $c->accounts->modify_user_password($user_id, $new_pwd1);
  if (!$res) {
    $msg = 'Your password has been changed.';
    $log->info("done.");
  }
  else {
    $err = 'Password change failed.';
    $log->warn("failed '$res'.");
  }

  $c->flash(error   => $err) if $err;
  $c->flash(message => $msg) if $msg;
  $c->redirect_to('account');
}

sub recover_password {
  my $c = shift;
  my ($err, $msg) = ('', '');

  my $v = $c->validation();
  $v->csrf_protect;
  $v->required('email', 'trim', 'not_empty')->email_syntax();
  return $c->redirect_to('recover_password_form') if $c->validation_failed($v, 'Recover password');

  my $email = $c->param('email');

  my $log = $c->log_context("recover_password '$email'");
  $log->info("start.");

  my %res    = $c->accounts->get_user_infos(email => $email);
  my $ok_msg = 'If the email address is correct, you will receive an email to reset your password.';
  if (!%res || !exists $res{id}) {

    # don't let people know if an email is registered or not
    $msg = $ok_msg;
    $log->warn("failed no result from get_user_infos(email => '$email').");
  }
  else {
    my $res = $c->_send_reset_password_email($res{id}, $email);
    if ($res) {
      $msg = $ok_msg;
      $log->info("done.");
    }
    else {
      $err = 'This action can not be done for the moment. Please retry later.';
      $log->warn("failed no result from get_user_infos(email => '$email').");
    }
  }

  $c->flash(error   => $err) if $err;
  $c->flash(message => $msg) if $msg;
  $c->redirect_to('index');
}

# send an email to a user with a link to reset his password
# returns true if the sending has been well received by the emailer, false otherwise
sub _send_reset_password_email {
  my ($c, $user_id, $email_address) = @_;

  my $log = $c->log_context("_send_reset_password_email '$user_id/$email_address'");
  $log->info("start.");

  return unless $user_id && $email_address;

  my $token = $c->app->jwt->claims({user_id => $user_id})->encode;
  my $url   = $c->url_for('reset_password_form')->to_abs->query(jwt => $token);
  $c->stash(url => $url);
  my $email_text = $c->render_to_string(template => 'account/reset_password', format => 'email');
  my $res        = $c->app->emailer->send_email(
    to      => [$email_address],
    subject => '[' . $c->l($email_topic) . '] ' . $c->l('Reset your password'),
    text    => $email_text
  );
  $res ? $log->info("done.") : $log->info("failed.");

  return $res;
}

# the user comes with a link to reset his password, set a session variable and show him a form for
# resetting his password
sub reset_password_form {
  my $c = shift;
  my ($err, $msg) = ('', '');

  my $log = $c->log_context("reset_password_form");
  $log->info("start.");

  my $reset_user_id;

  # get the reset_user_id either from the JWT token in the email link OR from the session when
  # returning to the form because of a user input error
  if ($c->session('reset_password') && $c->session('reset_user_id')) {
    $reset_user_id = $c->session('reset_user_id');
  }
  else {
    my $jwt = $c->param('jwt') || '';
    if (!$jwt) {
      $log->warn("no jwt param '" . $c->req->url . "'.");
      return $c->flash(error => 'The password reset link is incorrect.')->redirect_to('index');
    }
    eval {
      my $claims = $c->app->jwt->decode($jwt);
      $reset_user_id = $claims->{user_id};
    } or do {
      $log->warn("jwt decode failed '" . $c->req->url . "': '$@'.");
      return $c->flash(error => 'The password reset link is incorrect.')->redirect_to('index');
    };
  }

  my %res = $c->accounts->get_user_infos(id => $reset_user_id);
  if (!%res) {
    $log->warn("failed no result from get_user_infos(id => '$reset_user_id').");
    return $c->flash(error => 'The password reset link is incorrect.')->redirect_to('index');
  }

  # don't use the same session variable as the one to check logged in users
  $c->session(reset_user_id  => $reset_user_id);
  $c->session(reset_password => 1);
}

sub reset_password {
  my $c = shift;
  my ($err, $msg) = ('', '');

  if (!($c->session('reset_password') && $c->session('reset_user_id'))) {
    return $c->flash(error => 'You can not do that.')->redirect_to('index');
  }
  my $reset_user_id = $c->session('reset_user_id');

  my $v = $c->validation();
  $v->csrf_protect;
  $v->required('new-pwd1', 'not_empty')->min($V::V_MIN_PWD)->max($V::V_MAX_PWD)->pwd_syntax();
  $v->required('new-pwd2', 'not_empty')->equal_to('new-pwd1') if $v->is_valid('new-pwd1');
  return $c->redirect_to('reset_password_form') if $c->validation_failed($v, 'Reset password');

  my $new_pwd1 = $c->param('new-pwd1');
  my $new_pwd2 = $c->param('new-pwd2');

  my $log = $c->log_context("reset_password '$reset_user_id'");
  $log->info("start.");

  $log->info("will reset password.");

  # the new password is valid, now burn the right to reset a password
  $c->session(reset_password => undef);
  $c->session(reset_user_id  => undef);

  my $res = $c->accounts->modify_user_password($reset_user_id, $new_pwd1);
  if (!$res) {
    $msg = 'Your password has been changed.';
    $log->info("done.");
  }
  else {
    $err = 'Password change failed.';
    $log->warn("failed '$res'.");
  }

  $c->flash(error   => $err) if $err;
  $c->flash(message => $msg) if $msg;
  $c->redirect_to('index');
}

sub get_profile {
  my $c = shift;
  my ($err, $msg) = ('', '');

  my $profile_id = $c->param('user-id') || '';
  $c->redirect_to('index') unless $profile_id;

  my $log = $c->log_context("show_profile '$profile_id'");
  $log->info("start.");

  my %res = $c->accounts->get_user_description($profile_id);

  # if a user has not entered a description. don't show his page (anonymity by default)
  if ($res{error}) {
    $err = 'This profile is not available.';
    $c->log->warn("can't get user description '$res{error}'.");
  }
  elsif ((!$c->session('id') || $c->session('id') ne $profile_id) && !$res{description}) {
    $err = 'This profile is not available.';
    $c->log->info('not the profile owner, done.');
  }
  else {
    $c->log->info('done.');
  }
  $c->stash(profile_id => $profile_id, profile_name => $res{name} || '', profile_desc => $res{description} || '');

  $c->stash(error   => $err) if $err;
  $c->stash(message => $msg) if $msg;
}

sub modify_profile {
  my $c = shift;
  my ($err, $msg) = ('', '');

  my $user_id = $c->session('id') || '';
  return $c->flash(error => 'You need to log in first.')->redirect_to('index') unless $user_id;

  my $v = $c->validation();
  $v->csrf_protect;

  # allow an empty description to clear the description field
  $v->required('description')->max($V::V_MAX_PROFILE);
  if ($c->validation_failed($v, 'Profile change')) {
    return $c->redirect_to('get_profile', 'user-id' => $c->session('id'));
  }

  # description might be empty so that you can erase it
  my $description = $c->param('description') || '';

  my $log = $c->log_context("modify_profile '$user_id/" . substr($description, 0, 20) . "'");
  $log->info("start.");
  my $res = $c->accounts->modify_user_description($user_id, $description);
  if (!$res) {
    $msg = 'Your profile has been changed.';
    $log->info("done.");
  }
  else {
    $err = 'Profile change failed.';
    $log->warn("failed '$res'.");
  }

  $c->flash(error   => $err) if $err;
  $c->flash(message => $msg) if $msg;
  $c->redirect_to('get_profile', 'user-id' => $c->session('id'));

}

1;
