use Mojo::Base -strict;

use Test::More;
use Test::Mojo;

use lib 'lib';
use Profweb::Model::Emailer;

my $emailer = Profweb::Model::Emailer->new();

my $t = Test::Mojo->new('Profweb');
ok($t->app->emailer,       'Emailer object exists');
ok($t->app->emailer->ping, 'ping to the Email API');

done_testing();
