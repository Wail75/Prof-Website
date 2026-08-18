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
my $prof     = $t->app->prof;

my ($res, %hres);

# create a user to run tests with him
my $name = 'wailtest';
my $user_id;    # to be found after creating the user
my $pwd = 'liaw12345';
$res = $accounts->add_user($name, '', $pwd);
is($res, '', 'add user with name and no email');
%hres = $accounts->get_user_infos(name => $name);
ok($hres{id}, 'get account infos name no email');
$user_id = $hres{id};

my $quiz_name        = 'Premier Quiz';
my $question1        = '2 + 20';
my $answer1_fragment = '2';
my $answer1          = "${answer1_fragment}2";
my $question2        = '1 + 10';
my $answer2          = '11';
%hres = $prof->create_quiz($user_id, $quiz_name, $question1, $answer1, $question2, $answer2);

my $quiz2_name = "Répétitions";
my $question3  = 'Été';
my $answer3    = 'صَيْف';
%hres = $prof->create_quiz($user_id, $quiz2_name, $question3, $answer3);

%hres = $prof->get_items($user_id, question => $question3);
my @items = @{$hres{items}};
my $item3 = $items[0];

%hres = $prof->session_start_quiz($user_id, $quiz_name);
ok($hres{status}, 'session started');
my $session_id = $hres{session_id};

%hres = $prof->session_next_question($user_id, $session_id);
ok($hres{status}, 'got session next question');
is($hres{question}, $question1, 'got the expected question');
my $item_id = $hres{item_id};
is($item_id, 1, 'got the expected item id');

%hres = $prof->session_start_quiz($user_id, $quiz2_name);
ok($hres{status}, 'second session started');
my $session2_id = $hres{session_id};

%hres = $prof->session_next_question($user_id, $session2_id);
ok($hres{status}, 'got second session next question');
is($hres{question}, $question3, 'got the expected question for the second session');
my $item3_id = $hres{item_id};
is($item3_id, 3, 'got the expected item id for the second session');

%hres = $prof->session_respond_question($user_id, $session_id, $answer1);
ok($hres{status}, 'got response to question');
is($hres{grade}, 100, 'got the expected grade');

%hres = $prof->session_respond_question($user_id, 4546546, $answer1);
ok(!$hres{status}, 'responding to a non existent session did not work');
like($hres{msg}, qr/Could not find the answer/, 'expected error message to non existent session');

%hres = $prof->session_next_question($user_id, $session_id);
ok($hres{status}, 'got session next second question');
is($hres{question}, $question2, 'got the expected second question');

%hres = $prof->session_respond_question($user_id, $session_id, "no$answer2");
ok($hres{status}, 'got response to second question');
is($hres{grade}, 0, 'got the expected grade');

%hres = $prof->session_next_question($user_id, $session_id);
ok(!$hres{status}, 'no more question on finished quiz session');
like($hres{msg}, qr/No more question/, 'expected error message on finished quiz');

%hres = $prof->session_results($user_id, $session_id);
ok($hres{status}, 'got session results');
is($hres{average_prct}, 50, 'session results average percentage as expected');

%hres = $prof->get_sessions($user_id);
ok($hres{status}, 'got all session');
my @sessions = @{$hres{sessions}};
is(scalar(@sessions), 2, 'got correct count of sessions');
my $dt = DateTime::Format::ISO8601->parse_datetime($sessions[0]->{creation_time});
ok($dt, 'correct ISO8601 date time on get session');

%hres = $prof->get_sessions($user_id, 'non existing name');
ok($hres{status}, 'got sessions for non existing name');
@sessions = @{$hres{sessions}};
is(scalar(@sessions), 0, 'got correct count of sessions for non existing quiz');

%hres = $prof->get_sessions($user_id, $quiz_name);
ok($hres{status}, 'got sessions for the first quiz');
@sessions = @{$hres{sessions}};
is(scalar(@sessions), 1, 'got correct count of sessions for the first quiz');
ok((grep { $_->{quiz_name} eq $quiz_name } @sessions), 'got the expected session for the quiz');

%hres = $prof->session_creation_time($user_id, $session_id);
ok($hres{status}, 'got session creation time');
$dt = DateTime::Format::ISO8601->parse_datetime($hres{creation_time});
ok(DateTime->now()->epoch() - $dt->epoch() < 10, 'session created recently');


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
