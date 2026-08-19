use utf8;
use open qw(:std :encoding(UTF-8));

# NOTE this is a rather long test suite. Should I break it down in multiple parts? Maybe but that's
# more work and I like giving a chance for edge cases to appear if multiple operations are done on
# the same test account

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use V;

use Mojolicious::Plugin::Config;
use Profweb::Model::Emailer;

# use a test configuration file
my $configuration_test_file = './TEST-profweb.conf';

# TODO not very solid, try to use Mojolicious::Plugin::Config to read the file
my $test_config = require $configuration_test_file;
my $t           = Test::Mojo->new('Profweb', $test_config);

# use a test database, recreate it each time
$t->app->pg->migrations->migrate(0)->migrate();

$t->ua->max_redirects(3);

### Map of the site for testing

# a page containing a form to register
my $register_form = '/';

# an endpoint to register
my $register_page = '/register';

# verify an email
my $verify_email_page = '/verify-email';

# link to confirm an email address
my $verif_link_regex = qr!link http.*($verify_email_page.*jwt=.*)\.!;

# a page containing a form to login
my $login_form = '/';

# an endpoint to login
my $login_page = '/login';

# log out page
my $logout_page = '/logout';

# a page that can only be accessed once logged in
my $account_page = '/account';

# an endpoint for modifying the user account name
my $modify_user_name = '/account/name';

# an endpoint for asking for a change of the user account email
my $ask_email_change = '/account/email';

# an endpoint for modifying the user account password
my $modify_account_password = '/account/password';

# password recovery
my $recover_password = '/recover-password';
my $reset_password   = '/reset-password';
my $reset_pwd_regex  = qr!link http.*($reset_password.*jwt=.*)\.!;

# profile
my $profiles = '/profiles';

# error message shown to the user when wrong log in
my $wrong_login_err_msg   = "Wrong user name or password";
my $missing_login_err_msg = "must give a user name and a password";

my $name            = 'wailtest3';
my $invalid_pwd     = '123';
my $pwd             = 'liaw12345';
my $desc            = 'Just a user of this wonderful tool.';
my $pwd2            = 'uah45dfi*';
my $pwd_too_short   = 'l';
my $email           = 'test@test.org';
my $name2           = 'wailtest4';
my $name_too_long   = 'n' x ($V::V_MAX_NAME + 1);
my $email_too_short = 'e';
my $email_too_long  = 'e' x ($V::V_MAX_EMAIL + 1);
my $email_invalid   = 'truchahapasdearrobase';
my $email2          = 'test2@test.org';
my $email3          = 'test3@test.org';
my $unknown_email   = 'skjdfs@lskjdfd.dkj';

# this id should not work with a new test because it contains a timestamp from the past
my $unknown_id = 'c192a18f-6d7c-4cab-b880-c1c670c4699b';

# get a CSRF token from a page
sub csrf {
  return (csrf_token => $t->ua->get(shift)->res->dom->at('form input[name=csrf_token]')->val);
}
ok(csrf($login_form), 'got a CSRF token from a page');

# capture emails instead of sending them
my %last_email_args;
{
  no warnings 'redefine';

  # skip the Emailer object, keep the args
  *Profweb::Model::Emailer::send_email = sub { (undef, %last_email_args) = @_; return 1 };
}

# Register users for testing
# user without email
$t->post_ok($register_page => form => {csrf($register_form), name => $name, pwd1 => $pwd, pwd2 => $pwd})
  ->status_is(200)
  ->text_like('b#notif-ok' => qr/You are now registered./);
$t->get_ok($logout_page)->status_is(200);

# user with email only
$t->post_ok($register_page => form => {csrf($register_form), email => $email, pwd1 => $pwd, pwd2 => $pwd})
  ->status_is(200)
  ->text_like('b#notif-ok' => qr/You are now registered./);

# run the email verification link
my $email_body = $last_email_args{text};
$email_body =~ $verif_link_regex;
my $email_verify_path = $1;
$t->get_ok($email_verify_path)
  ->status_is(200)
  ->text_like('b#notif-ok' => qr/email address has been successfully verified/);
$t->get_ok($logout_page)->status_is(200);


subtest 'Add name to registration with email only' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $email, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->get_ok($account_page)
    ->status_is(200)
    ->text_like('p#name-notif' => qr/You have not given a name for your account/)
    ->element_exists('input[name=new-name][type=text]');

  $t->post_ok($modify_user_name => form => {csrf($account_page), 'new-name' => $name2})
    ->status_is(200)
    ->text_like('b#notif-ok'     => qr/Your name has been changed/)
    ->text_like('p#account-name' => qr/Connected: $name2/);

  $t->get_ok($logout_page)->status_is(200);

  $t->post_ok($login_page => form => {csrf($login_form), name => $name2, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Login successful/);

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Change name form validation' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $name2, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Login successful/);

  $t->post_ok($modify_user_name => form => {'new-name' => $name})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You can not do that/, 'missing CSRF token');

  $t->post_ok($modify_user_name => form => {csrf($account_page)})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Name change failed/)
    ->text_like('b#error-new-name' => qr/You must give a new name/);

  $t->post_ok($modify_user_name => form => {csrf($account_page), 'new-name' => ''})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Name change failed/)
    ->text_like('b#error-new-name' => qr/You must give a new name/);

  $t->post_ok($modify_user_name => form => {csrf($account_page), 'new-name' => $name2})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Name change failed/)
    ->text_like('b#error-new-name' => qr/new name must be different from the current name/)
    ->attr_is('input[name=new-name]', 'value', $name2, 'previous input value copied');

  $t->post_ok($modify_user_name => form => {csrf($account_page), 'new-name' => $name_too_long})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Name change failed/)
    ->text_like('b#error-new-name' => qr/Name must be at maximum \d+ characters/)
    ->attr_is('input[name=new-name]', 'value', $name_too_long, 'previous input value copied');

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Ask email change form validation' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $name2, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Login successful/);

  $t->post_ok($ask_email_change => form => {'new-email' => $email})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You can not do that/, 'missing CSRF token');

  $t->post_ok($ask_email_change => form => {csrf($account_page)})
    ->status_is(200)
    ->text_like('b#notif-error'     => qr/Ask email change failed/)
    ->text_like('b#error-new-email' => qr/You must give a new email/);

  $t->post_ok($ask_email_change => form => {csrf($account_page), 'new-email' => ''})
    ->status_is(200)
    ->text_like('b#notif-error'     => qr/Ask email change failed/)
    ->text_like('b#error-new-email' => qr/You must give a new email/);

  $t->post_ok($ask_email_change => form => {csrf($account_page), 'new-email' => $email})
    ->status_is(200)
    ->text_like('b#notif-error'     => qr/Ask email change failed/)
    ->text_like('b#error-new-email' => qr/new email must be different from the current email/)
    ->attr_is('input[name=new-email]', 'value', $email, 'previous input value copied');

  $t->post_ok($ask_email_change => form => {csrf($account_page), 'new-email' => $email_too_short})
    ->status_is(200)
    ->text_like('b#notif-error'     => qr/Ask email change failed/)
    ->text_like('b#error-new-email' => qr/Email address must be at least \d+ characters/)
    ->attr_is('input[name=new-email]', 'value', $email_too_short, 'previous input value copied');

  $t->post_ok($ask_email_change => form => {csrf($account_page), 'new-email' => $email_too_long})
    ->status_is(200)
    ->text_like('b#notif-error'     => qr/Ask email change failed/)
    ->text_like('b#error-new-email' => qr/Email address must be at maximum \d+ characters/)
    ->attr_is('input[name=new-email]', 'value', $email_too_long, 'previous input value copied');

  $t->post_ok($ask_email_change => form => {csrf($account_page), 'new-email' => $email_invalid})
    ->status_is(200)
    ->text_like('b#notif-error'     => qr/Ask email change failed/)
    ->text_like('b#error-new-email' => qr/syntax of the new email is not valid/)
    ->attr_is('input[name=new-email]', 'value', $email_invalid, 'previous input value copied');

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Add an email address to a registration with name only' => sub {

  # start with an existing account with name only

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})->status_is(200);

  $t->get_ok($account_page)->status_is(200)->text_like('p#email-change', qr/You can give a new account email here/);

  $t->post_ok($ask_email_change => form => {csrf($account_page), 'new-email' => $email2})
    ->status_is(200)
    ->text_like('b'             => qr/We have sent you an email to confirm your new email address/)
    ->text_like('p#email-notif' => qr/You have not given an email address yet/);

  # logout because the email verification link should work even when not logged in
  $t->get_ok($logout_page)->status_is(200);

  # check the email verification email

  my $email_to = $last_email_args{to}->[0];
  is($email_to, $email2, 'email sent to the expected address');
  my $email_body = $last_email_args{text};
  like($email_body, qr/You have just asked to change .* email address/, 'email body email change');
  like($email_body, $verif_link_regex,                                  'email body has link with a jwt');

  # use this later to confirm the email
  $email_body =~ $verif_link_regex;
  my $email_verify_path = $1;

  # run the email verification link

  $t->get_ok($email_verify_path)
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/email address has been successfully verified/);

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})->status_is(200);

  $t->get_ok($account_page)
    ->status_is(200)
    ->text_like('p#account-name' => qr/Connected: $name/)
    ->text_unlike('p#email-notif' => qr/You have not given an email address/)
    ->text_unlike('p#email-verif' => qr/Your email address is not verified yet/)
    ->text_like('p#email-notif' => qr/Your email address is $email2/);

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Change an email address' => sub {

  # start with an existing account with name only

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})->status_is(200);

  $t->get_ok($account_page)
    ->status_is(200)
    ->text_like('p#email-notif' => qr/Your email address is $email2/)
    ->text_like('p#email-change', qr/You can give a new account email here/);

  $t->post_ok($ask_email_change => form => {csrf($account_page), 'new-email' => $email3})
    ->status_is(200)
    ->text_like('b#notif-ok'    => qr/We have sent you an email to confirm your new email address/)
    ->text_like('p#email-notif' => qr/Your email address is $email2/);

  # logout because the email verification link should work even when not logged in
  $t->get_ok($logout_page)->status_is(200);

  # check the email verification email

  my $email_to = $last_email_args{to}->[0];
  is($email_to, $email3, 'email sent to the expected address');
  my $email_body = $last_email_args{text};
  like($email_body, qr/You have just asked to change .* email address/, 'email body email change');
  like($email_body, $verif_link_regex,                                  'email body has link with a jwt');

  # use this later to confirm the email
  $email_body =~ $verif_link_regex;
  my $email_verify_path = $1;

  # run the email verification link

  $t->get_ok($email_verify_path)
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/email address has been successfully verified/);

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})->status_is(200);

  $t->get_ok($account_page)
    ->status_is(200)
    ->text_like('p#account-name' => qr/Connected: $name/)
    ->text_like('p#email-notif'  => qr/Your email address is $email3/);

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Change a password' => sub {

  # start with an existing account

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})->status_is(200);

  $t->get_ok($account_page)->status_is(200)->text_like('p#password-change label', qr/You can give a new password/);

  $t->post_ok($modify_account_password => form => {'new-pwd1' => $pwd2, 'new-pwd2' => $pwd2, 'current-pwd' => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You can not do that/)
    ->attr_is('input[name=new-pwd1]', 'value', '', 'previous password input not copied');

  $t->post_ok($modify_account_password => form =>
      {csrf($account_page), 'new-pwd1' => $pwd2, 'new-pwd2' => "x$pwd2", 'current-pwd' => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Password change failed/)
    ->text_like('b#error-new-pwd2' => qr/Password and confirmation password must be the same/);

  $t->post_ok($modify_account_password => form =>
      {csrf($account_page), 'new-pwd1' => $pwd, 'new-pwd2' => $pwd, 'current-pwd' => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Password change failed/)
    ->text_like('b#error-new-pwd1' => qr/The new password must be different/);

  $t->post_ok($modify_account_password => form => {csrf($account_page), 'new-pwd1' => $pwd2, 'new-pwd2' => $pwd2})
    ->status_is(200)
    ->text_like('b#notif-error'       => qr/Password change failed/)
    ->text_like('b#error-current-pwd' => qr/You must give the current password/);

  $t->post_ok($modify_account_password => form =>
      {csrf($account_page), 'new-pwd1' => $pwd2, 'new-pwd2' => $pwd2, 'current-pwd' => ''})
    ->status_is(200)
    ->text_like('b#notif-error'       => qr/Password change failed/)
    ->text_like('b#error-current-pwd' => qr/You must give the current password/);

  $t->post_ok($modify_account_password => form => {csrf($account_page), 'new-pwd1' => $pwd2, 'current-pwd' => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Password change failed/)
    ->text_like('b#error-new-pwd2' => qr/must repeat the new password/);

  $t->post_ok($modify_account_password => form => {csrf($account_page), 'new-pwd2' => $pwd2, 'current-pwd' => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Password change failed/)
    ->text_like('b#error-new-pwd1' => qr/You must give a new password/);

  $t->post_ok($modify_account_password => form =>
      {csrf($account_page), 'new-pwd1' => $invalid_pwd, 'new-pwd2' => $invalid_pwd, 'current-pwd' => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Password change failed/)
    ->text_like('b#error-new-pwd1' => qr/Password must be at least \d+ characters/);

  $t->post_ok($modify_account_password => form =>
      {csrf($account_page), 'new-pwd1' => $pwd2, 'new-pwd2' => $pwd2, 'current-pwd' => "x$pwd"})
    ->status_is(200)
    ->text_like('b#notif-error'       => qr/Password change failed/)
    ->text_like('b#error-current-pwd' => qr/Wrong password/);

  $t->post_ok($modify_account_password => form =>
      {csrf($account_page), 'new-pwd1' => $pwd2, 'new-pwd2' => $pwd2, 'current-pwd' => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Your password has been changed/);

  # now try to reconnect with the new password

  $t->get_ok($logout_page)->status_is(200);

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('p#login-error' => qr/$wrong_login_err_msg/);

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd2})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->post_ok($modify_account_password => form =>
      {csrf($account_page), 'new-pwd1' => $pwd, 'new-pwd2' => $pwd, 'current-pwd' => $pwd2})
    ->status_is(200)
    ->text_like('b' => qr/Your password has been changed/);

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Recover password' => sub {

  # test if access are correcly restricted
  $t->get_ok($reset_password)
    ->status_is(200)
    ->text_like('b#notif-error' => qr/password reset link is incorrect/)
    ->text_is('b#notif-ok' => undef);

  $t->post_ok($reset_password => form => {csrf($register_form), 'new-pwd1' => $pwd, 'new-pwd2' => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You can not do that/)
    ->text_is('b#notif-ok' => undef);

  $t->get_ok($recover_password)->status_is(200)->text_like('p', qr/Enter your email address .* reset your password/);

  $t->post_ok($recover_password => form => {})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You can not do that/)
    ->text_is('b#error-email' => undef);

  # make sure to reset the email
  $last_email_args{text} = '';

  my $email_body = $last_email_args{text};
  ok(!$email_body, 'no email on empty recover password form');

  $t->post_ok($recover_password => form => {csrf($recover_password), email => $unknown_email})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/you will receive an email to reset your password/);

  $email_body = $last_email_args{text};
  ok(!$email_body, 'no email on unknown address in recover password form');

  $t->post_ok($recover_password => form => {csrf($recover_password), email => $email3})
    ->status_is(200)
    ->text_like('b' => qr/you will receive an email to reset your password/);

  my $email_to = $last_email_args{to}->[0];
  is($email_to, $email3, 'reset password email sent to the expected address');

  $email_body = $last_email_args{text};
  like($email_body, qr/You have just asked to reset your.* password/, 'email body reset password');
  like($email_body, $reset_pwd_regex,                                 'reset password email body has link with a jwt');

  # use this later to confirm the email
  $email_body =~ $reset_pwd_regex;
  my $reset_pwd_path = $1;

  # run the email verification link

  $t->get_ok($reset_pwd_path)
    ->status_is(200)
    ->text_like('p#reset-password label' => qr/You can give a new password here/);

  $t->post_ok($reset_password => form => {csrf($reset_pwd_path), 'new-pwd2' => $pwd2})
    ->status_is(200)
    ->text_like('b#notif-error'    => qr/Reset password failed/)
    ->text_like('b#error-new-pwd1' => qr/You must give a new password/);

  $t->post_ok($reset_password => form => {csrf($reset_pwd_path), 'new-pwd1' => $pwd2, 'new-pwd2' => $pwd2})
    ->status_is(200)
    ->text_is('b#notif-error' => undef)
    ->text_like('b#notif-ok' => qr/Your password has been changed/);

  # check if the new password works and the old one does not then change back the password
  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('p#login-error' => qr/$wrong_login_err_msg/);
  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd2})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);
  $t->get_ok($account_page)->status_is(200)->text_like('p#account-name' => qr/Connected: $name/);
  $t->post_ok($modify_account_password => form =>
      {csrf($account_page), 'new-pwd1' => $pwd, 'new-pwd2' => $pwd, 'current-pwd' => $pwd2})
    ->status_is(200)
    ->text_like('b' => qr/Your password has been changed/);
  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Pages translated in French' => sub {
  $t->get_ok($login_form => {'Accept-Language' => 'fr'})->status_is(200)->text_like('title' => qr/Bienvenue/);

  $t->post_ok($login_page => {'Accept-Language' => 'fr'} => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Connexion réussie/);

  $t->get_ok($account_page => {'Accept-Language' => 'fr'})
    ->status_is(200)
    ->text_like('p'             => qr/Connecté : $name/)
    ->text_like('a#logout_link' => qr/Déconnexion/);

  $t->get_ok($logout_page)->status_is(200);

  $t->post_ok($register_page => {'Accept-Language' => 'fr'} => form =>
      {csrf($register_form), email => $email, pwd1 => $pwd_too_short, pwd2 => $pwd_too_short})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/L'inscription a échoué/)
    ->text_like('p#error-pwd1'  => qr/mot de passe doit faire au moins/);
};

subtest 'Authorization checks' => sub {
  $t->post_ok($modify_user_name => form => {'new-name' => "x$name2"})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You need to log in first/)
    ->text_is('b#notif-ok' => undef);

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->get_ok($logout_page)->status_is(200);

  $t->post_ok($modify_account_password => form =>
      {csrf($login_form), 'current-pwd' => $pwd, 'new-pwd1' => "x$pwd", 'new-pwd2' => "x$pwd"})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You need to log in first/)
    ->text_is('b#notif-ok' => undef);
};

subtest 'Profile management' => sub {

  # get the id for the user being tested
  my %res = $t->app->accounts->get_user_infos(name => $name);
  my $id  = $res{id};

  $t->get_ok("$profiles/x$id")->status_is(404, 'bad syntax uuid leads to a not found page');

  $t->get_ok("$profiles/$unknown_id")
    ->status_is(200)
    ->text_like('b#notif-error' => qr/This profile is not available/, 'unregistered id')
    ->text_like('h1'            => qr//);

  $t->get_ok("$profiles/$id")
    ->status_is(200)
    ->text_like('b#notif-error' => qr/This profile is not available/, 'not allowed to see this')
    ->text_like('h1'            => qr//)
    ->element_exists_not('p#description')
    ->element_exists_not('textarea#modify-description');

  $t->post_ok($login_page => form => {csrf($login_form), name => $name2, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Login successful/);

  $t->get_ok("$profiles/$id")->status_is(200)->text_like(
    'b#notif-error' => qr/This profile is not available/,

    # REMINDER profiles are not public by default
    'even logged in user can not see another user profile'
  )->text_like('h1' => qr//)->element_exists_not('p#description')->element_exists_not('textarea#modify-description');

  $t->get_ok($logout_page)->status_is(200);

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Login successful/);

  $t->get_ok($account_page)
    ->status_is(200)
    ->text_like('a#my-profile-link' => qr/My Profile/, 'link to my own profile')
    ->attr_like('a#my-profile-link', 'href', qr/$profiles.+$id/);

  $t->get_ok("$profiles/$id")
    ->status_is(200)
    ->text_is('b#notif-error' => undef)
    ->text_like('h1' => qr/Profile: $name/, 'I can see my own profile')
    ->text_is('textarea#modify-description' => '', 'I can modify my own profile description');

  $t->post_ok("$profiles" => form => {csrf("$profiles/$id"), 'description' => $desc})
    ->status_is(200)
    ->text_like('b#notif-ok', qr/Your profile has been changed/);

  $t->get_ok("$profiles/$id")
    ->status_is(200)
    ->text_is('b#notif-error' => undef)
    ->text_like('h1' => qr/Profile: $name/)
    ->text_is('textarea#modify-description' => $desc);

  $t->get_ok($logout_page)->status_is(200);

  $t->get_ok("$profiles/$id")
    ->status_is(200)
    ->text_is('b#notif-error' => undef)
    ->text_like('h1' => qr/Profile: $name/)
    ->text_is('p#description', $desc)
    ->element_exists_not('textarea#modify-description');

  $t->post_ok($login_page => form => {csrf($login_form), name => $name2, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Login successful/);

  $t->get_ok("$profiles/$id")
    ->status_is(200)
    ->text_is('b#notif-error' => undef)
    ->text_like('h1' => qr/Profile: $name/)
    ->text_is('p#description', $desc)
    ->element_exists_not('textarea#modify-description');

  $t->get_ok($logout_page)->status_is(200);

};


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
