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
ok(!$res, 'add user with name and no email');
%res = $accounts->get_user_infos(name => $name);
ok($res{id}, 'get account infos name no email');
$id = $res{id};

%res = $accounts->get_user_payments($id);
is($res{user_id}, $id, 'get user payments returns the user id');
ok(!@{$res{payments}}, 'get user payments no payments yet');

my %paym = (user_id => $id, amount => 1250, currency => 'EUR', received_at => '2026-06-01T12:00:05');
$res = $accounts->add_user_payment(@paym{'user_id', 'amount', 'currency', 'received_at'});
is($res, '', 'add user payment');

%res = $accounts->get_user_payments($id);
is($res{user_id}, $id, 'get user payments returns the user id');
my @payments = @{$res{payments}};
is(@payments, 1, 'get user payments one payment');

$res = $accounts->add_user_payment($unknown_id, @paym{'amount', 'currency', 'received_at'});
like($res, qr/No user for id.*$unknown_id/, 'add user payment unknown id');

%res = $accounts->get_user_payments($unknown_id);
is($res{user_id},     $unknown_id, 'get user payment unknown id back');
is(@{$res{payments}}, 0,           'get user payment unknown id');

# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
