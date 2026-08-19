use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use Mojolicious::Plugin::Config;

use DateTime::Format::ISO8601;

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
my $archived_dt;

$res = $accounts->add_user($name, '', $pwd);
is($res, '', 'add user with name and no email');
%res = $accounts->get_user_infos(name => $name);
ok($res{id}, 'get account infos name no email');
$id = $res{id};

is($res{archived_at}, undef, 'get account infos archived at');

$res = $accounts->archive_user($id);
is($res, '', 'archive user');
%res = $accounts->get_user_infos(id => $id);
ok($res{id}, 'get account infos after archive');
$res{archived_at} = $res{archived_at};
ok($res{archived_at}, 'get account infos after archive');
$res{archived_at} =~ s/ /T/;
$archived_dt = DateTime::Format::ISO8601->parse_datetime($res{archived_at});

# "By default, the returned object will be in the UTC time zone." from DateTime doc now()
ok(DateTime->now()->epoch() - $archived_dt->epoch() < 10, 'archived at recently');

$res = $accounts->unarchive_user($id);
is($res, '', 'unarchive user');
%res = $accounts->get_user_infos(id => $id);
ok($res{id}, 'get account infos after unarchive');
is($res{archived_at}, undef, 'get account infos unarchive done');

$res = $accounts->archive_user($unknown_id);
like($res, qr/No user for id.*$unknown_id/, 'subscribe user unknown id');

$res = $accounts->unarchive_user($unknown_id);
like($res, qr/No user for id.*$unknown_id/, 'subscribe user unknown id');

# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
