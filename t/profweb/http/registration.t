use utf8;
use open qw(:std :encoding(UTF-8));

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use Mojolicious::Plugin::Config;
use Profweb::Model::Emailer;
use V;

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
my $protected_page = '/account';

my $name               = 'wailtest3';
my $name_too_long      = 'n' x ($V::V_MAX_NAME + 1);
my $invalid_pwd        = '123';
my $pwd                = 'liaw12345';
my $pwd_too_short      = 'l';
my $pwd2_too_short     = 'o';
my $pwd_too_long       = 'a' x ($V::V_MAX_PWD + 1);
my $pwd_invalid_digit  = 'jfoiwejpfLKFJ:DLDKFJ';
my $pwd_invalid_letter = '4+6464+456464=';
my $pwd2               = 'uah45dfi*';
my $email              = 'test@test.org';
my $email_too_short    = 'e';
my $email_too_long     = 'e' x ($V::V_MAX_EMAIL + 1);
my $email_invalid      = 'truchahapasdearrobase';
my $name2              = 'wailtest4';
my $email4             = 'test4@test.org';

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

$t->get_ok($register_form)
  ->status_is(200)
  ->element_exists('form input[name="name"]')
  ->element_exists('form input[name="pwd1"]')
  ->element_exists('form input[type="submit"]');


subtest 'Registration with errors' => sub {

  $t->get_ok($register_form)->status_is(200);

  $t->post_ok($register_page => form => {name => $name, pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You can not do that./);

  $t->post_ok($register_page => form => {csrf($register_form), pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error'      => qr/Registration failed./)
    ->text_like('p#error-name&email' => qr/You must give a user name or an email or both/);

  $t->post_ok($register_page => form => {csrf($register_form), name => '', pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error'      => qr/Registration failed./)
    ->text_like('p#error-name&email' => qr/You must give a user name or an email or both/);

  $t->post_ok($register_page => form => {csrf($register_form), email => '', pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error'      => qr/Registration failed./)
    ->text_like('p#error-name&email' => qr/You must give a user name or an email or both/);

  $t->post_ok($register_page => form => {csrf($register_form), name => $name_too_long, pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-name'  => qr/Name must be at maximum \d+ characters/);

  $t->post_ok($register_page => form => {csrf($register_form), email => $email_too_short, pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-email' => qr/Email address must be at least \d+ characters/)
    ->attr_is('input[name=email]', 'value', $email_too_short, 'previous input value forwarded');

  $t->post_ok($register_page => form => {csrf($register_form), email => $email_too_long, pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-email' => qr/Email address must be at maximum \d+ characters/);

  $t->post_ok($register_page => form => {csrf($register_form), email => $email_invalid, pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-email' => qr/The syntax of the email is not valid/)
    ->attr_is('input[name=email]', 'value', $email_invalid, 'previous input value copied');

  $t->post_ok($register_page => form => {csrf($register_form), email => $email, pwd1 => '', pwd2 => ''})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd1'  => qr/You must give a password./);

  $t->post_ok($register_page => form => {csrf($register_form), email => $email, pwd1 => $pwd, pwd2 => ''})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd2'  => qr/You must give a confirmation password./);

  # check if the user receives error messages on the password validation before the confirmation
  # don't tell the user that the conf. password is not the same while the password is invalid
  $t->post_ok($register_page => form => {csrf($register_form), email => $email, pwd1 => $pwd_too_short, pwd2 => ''})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd1'  => qr/Password must be at least \d+ characters/);

  $t->post_ok(
    $register_page => form => {csrf($register_form), email => $email, pwd1 => $pwd_too_short, pwd2 => $pwd2_too_short})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd1'  => qr/Password must be at least \d+ characters/);

  $t->post_ok(
    $register_page => form => {csrf($register_form), email => $email, pwd1 => $pwd_too_short, pwd2 => $pwd_too_short})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd1'  => qr/Password must be at least \d+ characters/);

  $t->post_ok($register_page => form =>
      {csrf($register_form), email => $email, pwd1 => $pwd_invalid_letter, pwd2 => $pwd_invalid_letter})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd1'  => qr/respect the given password syntax/);

  $t->post_ok($register_page => form =>
      {csrf($register_form), email => $email, pwd1 => $pwd_invalid_digit, pwd2 => $pwd_invalid_digit})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd1'  => qr/respect the given password syntax/);

  $t->post_ok($register_page => form => {csrf($register_form), email => $email, pwd1 => $pwd_too_long, pwd2 => ''})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd1'  => qr/Password must be at maximum \d+ characters/);

  $t->post_ok($register_page => form => {csrf($register_form), email => $email, pwd1 => $pwd, pwd2 => "a$pwd"})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/Registration failed./)
    ->text_like('p#error-pwd2'  => qr/Password and confirmation password must be the same/);

};

subtest 'Registration workflow with name only' => sub {

  $t->get_ok($register_form)->status_is(200);

  $t->post_ok($register_page => form => {csrf($register_form), name => $name, pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/You are now registered./);

  $t->get_ok($protected_page)
    ->status_is(200)
    ->text_like('p#account-name' => qr/Connected: $name/)
    ->text_like('p#email-notif'  => qr/You have not given an email address/)
    ->text_unlike('p#email-verif' => qr/Your email address is not verified yet/)
    ->text_unlike('p#name-notif'  => qr/You have not given a name for your account/)
    ->text_like('a#logout_link' => qr/Logout/);

  $t->get_ok($logout_page)
    ->status_is(200)
    ->element_exists('form input[name="name"]')
    ->element_exists('form input[name="pwd1"]')
    ->element_exists('form input[type="submit"]');

  $t->post_ok($register_page => form => {csrf($register_form), name => $name, pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/This name is not available./);
};

subtest 'Registration workflow with email only' => sub {

  $t->get_ok($register_form)->status_is(200);

  $t->post_ok($register_page => form => {csrf($register_form), email => $email, pwd1 => $pwd, pwd2 => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/You are now registered./);

  $t->get_ok($protected_page)
    ->status_is(200)
    ->text_like('p#account-name' => qr/Connected: $email/)
    ->text_like('p#email-verif'  => qr/Your email address is not verified yet/)
    ->text_like('a#logout_link'  => qr/Logout/);

  # check the email verification email

  my $email_to = $last_email_args{to}->[0];
  is($email_to, $email, 'email sent to the expected address');
  my $email_body = $last_email_args{text};
  like($email_body, qr/You have just registered an account/, 'email body says registered');
  like($email_body, $verif_link_regex,                       'email body has link with a jwt');

  # use this later to confirm the email
  $email_body =~ $verif_link_regex;
  my $email_verify_path = $1;

  # logout because the email verification link should work even when not logged in
  $t->get_ok($logout_page)->status_is(200);

  # run the email verification link

  $t->get_ok($email_verify_path)
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/email address has been successfully verified/);

  $t->post_ok($login_page => form => {csrf($login_form), name => $email, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->get_ok($protected_page)
    ->status_is(200)
    ->text_like('p#account-name' => qr/Connected: $email/)
    ->text_like('p#email-notif'  => qr/Your email address is $email/);

  $t->get_ok($logout_page)->status_is(200);
};


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
