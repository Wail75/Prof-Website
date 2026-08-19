use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use lib 'lib';

use Mojo::JWT;

my $t = Test::Mojo->new('Profweb');

my ($key, $value) = qw( email test@test.org );

my $claim = $t->app->jwt->claims({$key => $value})->encode();
ok($claim, 'JWT claim exists');

my $decoded = $t->app->jwt->decode($claim);
is($decoded->{$key}, $value, 'round trip decoding');

done_testing();
