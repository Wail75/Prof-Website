use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('Profweb');

ok($t->app->config->{app_secrets}->[0], 'got one app secret');
ok($t->app->config->{postgresql_host},  'got db host');
ok($t->app->config->{email_api_token},  'got email api token');

done_testing();
