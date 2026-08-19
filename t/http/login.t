use utf8;
use open qw(:std :encoding(UTF-8));

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

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
my $protected_page = '/account';

# error message shown to the user when wrong log in
my $login_failed_err_msg  = "Login failed";
my $wrong_login_err_msg   = "Wrong user name or password";
my $missing_login_err_msg = "must give a user name and a password";

my $name  = 'wailtest3';
my $pwd   = 'liaw12345';
my $email = 'test@test.org';
my $name2 = 'wailtest4';
my $pwd2  = 'uah45dfi*';

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

$t->get_ok($login_form)
  ->status_is(200)
  ->element_exists('form input[name="name"]')
  ->element_exists('form input[name="pwd"]')
  ->element_exists('form input[name="csrf_token"]')
  ->element_exists('form input[type="submit"]');

subtest 'Failed login workflow' => sub {

  # logout from not being logged in
  $t->get_ok($logout_page)->status_is(200);

  $t->get_ok($login_form)
    ->status_is(200)
    ->element_exists('form input[name="name"]')
    ->element_exists('form input[name="pwd"]')
    ->element_exists('form input[name="csrf_token"]')
    ->element_exists('form input[type="submit"]');

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/$login_failed_err_msg/)
    ->text_like('p#login-error' => qr/$wrong_login_err_msg/, 'no user');

  $t->post_ok($login_page => form => {name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You can not do that/, 'no user, missing csrf token');
};

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


subtest 'Login/logout workflow' => sub {
  $t->get_ok($login_form)
    ->status_is(200)
    ->element_exists('form input[name="name"]')
    ->element_exists('form input[name="pwd"]')
    ->element_exists('form input[type="submit"]');

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => "x$pwd"})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/$login_failed_err_msg/)
    ->text_like('p#login-error' => qr/$wrong_login_err_msg/, 'wrong password');

  $t->post_ok($login_page => form => {csrf($login_form), name => $name})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/$login_failed_err_msg/)
    ->text_like('p#login-error' => qr/$missing_login_err_msg/, 'no password');

  $t->post_ok($login_page => form => {csrf($login_form), pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/$login_failed_err_msg/)
    ->text_like('p#login-error' => qr/$missing_login_err_msg/, 'no name');

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Login successful/, 'login successful');

  $t->get_ok($protected_page)
    ->status_is(200)
    ->text_like('p#account-name' => qr/Connected: $name/, 'connected')
    ->text_like('a#logout_link'  => qr/Logout/);

  $t->get_ok($logout_page)
    ->status_is(200)
    ->element_exists('form input[name="name"]')
    ->element_exists('form input[name="pwd"]')
    ->element_exists('form input[type="submit"]');
};

subtest 'Login error' => sub {

  $t->post_ok($login_page => form => {name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/You can not do that./, 'missing csrf token');

  $t->post_ok($login_page => form => {csrf($login_form), pwd => $pwd})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/$login_failed_err_msg/)
    ->text_like('p#login-error' => qr/$missing_login_err_msg/, 'no name');

  $t->post_ok($login_page => form => {csrf($login_form), name => $name})
    ->status_is(200)
    ->text_like('b#notif-error' => qr/$login_failed_err_msg/)
    ->text_like('p#login-error' => qr/$missing_login_err_msg/, 'no password');

};


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
