use utf8;
use open qw(:std :encoding(UTF-8));

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

my $dashboard_page = '/dashboard';

# error message shown to the user when wrong log in
my $wrong_login_err_msg   = "Wrong user name or password";
my $missing_login_err_msg = "must give a user name and a password";

my $name            = 'wailtest3';
my $invalid_pwd     = '123';
my $pwd             = 'liaw12345';
my $email           = 'test@test.org';
my $name2           = 'wailtest4';

# this id should not work with a new test because it contains a timestamp from the past
my $unknown_id = 'c192a18f-6d7c-4cab-b880-c1c670c4699b';

# get a CSRF token from a page
sub csrf {
  return (csrf_token => $t->ua->get(shift)->res->dom->at('form input[name=csrf_token]')->val);
}
ok(csrf($login_form), 'got a CSRF token from a page');

# Register users for testing
# user without email
$t->post_ok($register_page => form => {csrf($register_form), name => $name, pwd1 => $pwd, pwd2 => $pwd})
  ->status_is(200)
  ->text_like('b#notif-ok' => qr/You are now registered./);
$t->get_ok($logout_page)->status_is(200);


subtest 'Basic dashboard features' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_like('h1' => qr/Dashboard/)
    ->text_like('h2#author a' => qr/Quiz Authoring/)
    ->attr_is('a#author', 'href', '/author', 'link to the authoring page')
    ->text_like('div#small-quiz p', qr/no quiz yet/, 'help for no quiz yet');

  $t->get_ok($logout_page)->status_is(200);
};


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
