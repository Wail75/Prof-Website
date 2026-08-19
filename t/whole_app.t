use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

my $t = Test::Mojo->new('Profweb');

ok($t->app->accounts, 'Accounts helper initialized');
ok($t->app->pg,       'Postgres helper initialized');
ok($t->app->config,   'Config plugin initialized');
ok($t->app->emailer,  'Emailer helper initialized');

done_testing();
