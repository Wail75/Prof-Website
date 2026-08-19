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
my ($res, %res);
my $name = 'wailtest';
my $pwd  = 'liaw12345';
my $id;    # to be found after creating the user
my $unknown_id = '628b453f-567e-4a88-8c00-7853dfa69c34';

$res = $accounts->add_user($name, '', $pwd);
is($res, '', 'add user with name and no email');
%res = $accounts->get_user_infos(name => $name);
ok($res{id}, 'get account infos name no email');
$id = $res{id};

is($res{subscription}, $accounts->STATUS_NO_SUBSCRIPTION, 'get account infos subscription status');

$res = $accounts->subscribe_user($id);
is($res, '', 'subscribe user');

$res = $accounts->subscribe_user($id);
is($res, '', 'subscribe user');
%res = $accounts->get_user_infos(id => $id);
ok($res{id}, 'get account infos after subscription');
is($res{subscription}, $accounts->STATUS_SUBSCRIBED, 'get account infos after subscription status');

$res = $accounts->unsubscribe_user($id);
is($res, '', 'unsubscribe user');
%res = $accounts->get_user_infos(id => $id);
ok($res{id}, 'get account infos after unsubscription');
is($res{subscription}, $accounts->STATUS_NO_SUBSCRIPTION, 'get account infos unsubscription status');

$res = $accounts->subscribe_user($unknown_id);
like($res, qr/No user for id.*$unknown_id/, 'subscribe user unknown id');

$res = $accounts->unsubscribe_user($unknown_id);
like($res, qr/No user for id.*$unknown_id/, 'subscribe user unknown id');

# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
