use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use Mojolicious::Plugin::Config;

# use a test configuration file
my $configuration_test_file = './TEST-profweb.conf';

# TODO not very solid, try to use Mojolicious::Plugin::Config to read the file
my $test_config = require $configuration_test_file;
my $t           = Test::Mojo->new('Profweb', $test_config);

# use a test database, recreate it each time
$t->app->pg->migrations->migrate(0)->migrate();

my $accounts = $t->app->accounts;

subtest 'Secure password storage' => sub {
  my $password = 'password';
  my $secpwd   = $accounts->secure_password('password');
  ok($secpwd, 'password hashing');
  ok($accounts->_verify_password($secpwd,  $password),    'check password');
  ok(!$accounts->_verify_password($secpwd, " $password"), 'check wrong password');
};

my ($res, %res);
my $name = 'wailtest';
my ($id, $id2, $id3);    # to be found after creating the user
my $unknown_id = '628b453f-567e-4a88-8c00-7853dfa69c34';
my $short_pwd  = '123';
my $pwd        = 'liaw12345';
my $pwd2       = 'dls;f466\[';
my $name2      = 'wailtest2';
my $email      = 'wail@test.org';
my $email2     = 'wail2@test.org';
my $email3     = 'wail3@test.org';
my $email4     = 'wail4@test.org';
my $name3      = 'wailtest3';
my $desc       = 'Hello, it is me.';

$res = $accounts->add_user($name, '', $short_pwd);
ok($res, 'add user with password too short');
like($res, qr/Parameter incorrect: password/, 'add user with password too short error message');
$res = $accounts->add_user($name, '', $pwd);
is($res, '', 'add user with name and no email');
%res = $accounts->get_user_infos(name => $name);
ok($res{id}, 'get account infos name no email');
$id  = $res{id};
$res = $accounts->add_user($name, '', $pwd);
like($res, qr/DB error.*duplicate.*users_name/, 'add user with existing name');

$res = $accounts->check_login($name, '', $pwd);
is($res, '', 'check login on name no email');
$res = $accounts->check_login($name2, '', $pwd);
ok($res, 'check login bad name fail');
like($res, qr/no user for.*'$name2'/, 'check login bad name error message');
$res = $accounts->check_login($name, '', "x$pwd");
ok($res, 'check login bad password fail');
like($res, qr/password does not match/, 'check login bad password error message');

$res = $accounts->add_user('', $email, $pwd);
is($res, '', 'add user with email and no name');
%res = $accounts->get_user_infos(name => $email);
ok($res{id}, 'get account infos email no name');
$id2 = $res{id};
$res = $accounts->add_user('', $email, $pwd);

# name is duplicated because the email address is used as a name if no name is given
like($res, qr/DB error.*duplicate.*users_name/, 'add user with existing email');
$res = $accounts->check_login($email, '', $pwd);
is($res, '', 'check login on email no name');

$res = $accounts->add_user($name2, $email2, $pwd);
is($res, '', 'add user with name and email');
%res = $accounts->get_user_infos(name => $name2);
ok($res{id}, 'get account infos name and email');
$id3 = $res{id};
$res = $accounts->add_user($name2, $email2, $pwd);
like($res, qr/DB error.*duplicate.*users_/, 'add user with existing name and email');
$res = $accounts->check_login($name2, '', $pwd);
is($res, '', 'check login on name and email');

%res = $accounts->get_user_infos();
ok(%res, 'get account infos no param');
like($res{error}, qr/Parameter missing.*field/, 'get account infos no param error message');
%res = $accounts->get_user_infos('name');
ok(%res, 'get account infos no value');
like($res{error}, qr/Parameter missing.*value/, 'get account infos no value error message');
%res = $accounts->get_user_infos(age => 15);
ok(%res, 'get account infos field incorrect');
like($res{error}, qr/Parameter incorrect.*field/, 'get account infos field incorrect error message');
%res = $accounts->get_user_infos(name => "x$name");
ok(%res, 'get account infos no user');
like($res{error}, qr/No account found/, 'get account infos no user error message');

%res = $accounts->get_user_infos(name => $name);
is($res{name},           $name, 'get account infos name no email name correct');
is($res{email},          undef, 'get account infos name no email email correct');
is($res{email_verified}, 'no',  'get account infos email no name email verification status correct');

%res = $accounts->get_user_infos(name => $email);
is($res{name},           $email, 'get account infos email no name name correct');
is($res{email},          $email, 'get account infos email no name email correct');
is($res{email_verified}, 'no',   'get account infos email no name email verification status correct');

%res = $accounts->get_user_infos(email => $email);
ok(%res, 'get account infos by email email no name');
is($res{name},  $email, 'get account infos by email email no name name correct');
is($res{email}, $email, 'get account infos by email email no name email correct');

$res = $accounts->modify_user_name($id3, $name);
ok($res, 'modify user name already used name');
like($res, qr/DB error.*duplicate.*users_name/, 'add user name already used name error message');

$res = $accounts->modify_user_name($id3, $name3);
is($res, '', 'modify user name');

%res = $accounts->get_user_infos(name => $name3);
ok(%res, 'get account infos new name on email');
is($res{email}, $email2, 'get account infos new name on email email correct');

%res = $accounts->get_user_infos(email => $email2);
ok(%res, 'get account infos by email after new name');
is($res{name},  $name3,  'get account infos by email after new name name correct');
is($res{email}, $email2, 'get account infos by email after new name email correct');

$res = $accounts->modify_user_email($id3, $email);
ok($res, 'modify user email already used email');
like($res, qr/DB error.*duplicate.*users_email/, 'add user email already used email error message');

$res = $accounts->modify_user_email($unknown_id, $email3);
ok($res, 'modify user email bad user id');
like($res, qr/No user for id '$unknown_id'/, 'modify user name bad user id error msg');

$res = $accounts->modify_user_email($id3, $email3);
is($res, '', 'modify user email');

%res = $accounts->get_user_infos(id => $id3);
ok(%res, 'get account infos after change email');
is($res{email}, $email3, 'get account infos after change email email correct');

%res = $accounts->get_user_infos(email => $email);
ok(%res, 'get account infos by email');
is($res{name},           $email, 'get account infos by email name correct');
is($res{email},          $email, 'get account infos by email email correct');
is($res{email_verified}, 'no',   'get account infos by email email verification status correct');

$res = $accounts->modify_user_password($id, $pwd2);
is($res, '', 'modify user password');
$res = $accounts->check_login($name, '', $pwd);
ok($res, 'check login bad password fail after change');
like($res, qr/password does not match/, 'check login bad password after change error message');
$res = $accounts->check_login($name, '', $pwd2);
is($res, '', 'check login after change');

$res = $accounts->modify_user_email($id2, $email4);
is($res, '', 'modify user name and email');

%res = $accounts->get_user_infos(email => $email);
ok($res{error}, 'get account infos after modify user name and email old email unknown');

%res = $accounts->get_user_infos(email => $email4);
ok(%res, 'get account infos after modify user name and email');
is($res{name},  $email4, 'get account infos after modify user name and email email correct');
is($res{email}, $email4, 'get account infos after modify user name and email email correct');

%res = $accounts->get_user_description($id);
is($res{error},       undef, 'get user description no error');
is($res{description}, undef, 'get user description no description yet');
is($res{name},        $name, 'get user description correct name');

$res = $accounts->modify_user_description($id, $desc);
is($res, '', 'modify user description no error');

%res = $accounts->get_user_description($id);
is($res{error},       undef, 'get user description after modif no error');
is($res{description}, $desc, 'get user description after modif description correct');

# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
