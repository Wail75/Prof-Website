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
my ($quiz_id, $quiz2_id);    # to be found after creating the quiz
%hres = $prof->create_quiz($user_id, $quiz_name, $question1, $answer1, $question2, $answer2);
ok($hres{status}, 'quiz creation');

%hres = $prof->get_quizzes_infos(name => $quiz_name);
ok($hres{status}, 'got quizzes infos');
$quiz_id = $hres{quizzes}[0]{id};

%hres = $prof->next_question($user_id, $quiz_id);
ok($hres{status}, 'first question');
is($hres{question}, $question1, 'first question in order of creation');

my $item_id = $hres{item_id};
%hres = $prof->respond_question($user_id, $item_id, $answer1);
ok($hres{status}, 'first response registered');
ok($hres{grade},  'first response correct');

%hres = $prof->next_question($user_id, $quiz_id);
ok($hres{status}, 'second question');
is($hres{question}, $question2, 'second question in order of creation');

$item_id = $hres{item_id};
%hres    = $prof->respond_question($user_id, $item_id, '6');
ok($hres{status}, 'second response registered');
ok(!$hres{grade}, 'second response wrong');

my $search_term = 'tition';
my $quiz2_name  = "Répé${search_term}s";
my $question3   = 'Été';
my $answer3     = 'صَيْف';
%hres = $prof->create_quiz($user_id, $quiz2_name, $question3, $answer3);
ok($hres{status}, 'Non ASCII quiz creation');
%hres     = $prof->get_quizzes_infos(name => $quiz2_name);
$quiz2_id = $hres{quizzes}[0]{id};

%hres = $prof->next_question($user_id, $quiz2_id);
ok($hres{status}, 'non ASCII question');
is($hres{question}, $question3, 'non ASCII question read');

my $item3_id = $hres{item_id};
%hres = $prof->respond_question($user_id, $item3_id, $answer3);
ok($hres{status}, 'non ASCII response registered');
ok($hres{grade},  'non ASCII response correct');


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
