use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use Mojolicious::Plugin::Config;

use DateTime::Format::ISO8601;

use utf8;
use open qw(:std :encoding(UTF8));

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
my @quizzes;

# create a user to run tests with him
my $name = 'wailtest';
my $user_id;    # to be found after creating the user
my $pwd = 'liaw12345';
$res = $accounts->add_user($name, '', $pwd);
is($res, '', 'add user with name and no email');
%hres = $accounts->get_user_infos(name => $name);
ok($hres{id}, 'get account infos name no email');
$user_id = $hres{id};

my $quiz_name     = 'Premier Quiz';
my $quiz_name_bis = '1er Quiz';
my $description   = 'Le premier quiz de la série.';
my $instructions  = 'Répondez au quiz naturellement.';
my $quiz_id;    # to be found after creating the quiz
my $question1 = '2 + 20';
my $answer1   = "22";
my $question2 = '1 + 10';
my $answer2   = '11';
%hres = $prof->create_quiz($user_id, $quiz_name, $question1, $answer1, $question2, $answer2);
ok($hres{status}, 'first quiz created');

%hres = $prof->get_quizzes_infos();
ok($hres{status}, 'got quizzes infos');
is($hres{quizzes}[0]{name}, $quiz_name, 'get_quizzes_infos correct quiz name');
$quiz_id = $hres{quizzes}[0]{id};
ok($quiz_id, 'get_quizzes_infos got a quiz id');
is($hres{quizzes}[0]{visible}, 'private', 'get_quizzes_infos correct visible');

%hres = $prof->next_question($user_id, $quiz_id);
my $item_id       = $hres{item_id};
my $first_item_id = $item_id;         # save it for later
%hres    = $prof->respond_question($user_id, $item_id, $answer1);
%hres    = $prof->next_question($user_id, $quiz_id);
$item_id = $hres{item_id};
my $second_item_id = $item_id;        # save it for later

%hres = $prof->get_quizzes_infos(user_id => $user_id);
ok($hres{status}, 'got quizzes infos by user_id');
is($hres{quizzes}[0]{id}, $quiz_id, 'get_quizzes_infos by user_id correct quiz id');

%hres = $prof->update_quiz($user_id, $quiz_id, name => $quiz_name_bis);
ok($hres{status}, 'update_quiz updated name ok');

%hres = $prof->get_quizzes_infos(user_id => $user_id);
ok($hres{status}, 'got quizzes infos after name changed');
is($hres{quizzes}[0]{name}, $quiz_name_bis, 'get_quizzes_infos after name changed name correct');

%hres = $prof->update_quiz(
  $user_id, $quiz_id,
  name         => $quiz_name,
  description  => $description,
  instructions => $instructions,
  visible      => 'public'
);
ok($hres{status}, 'update_quiz updated all ok');

%hres = $prof->get_quizzes_infos(user_id => $user_id);
ok($hres{status}, 'got quizzes infos after all changed');
is($hres{quizzes}[0]{name},         $quiz_name,    'get_quizzes_infos name correct');
is($hres{quizzes}[0]{description},  $description,  'get_quizzes_infos description correct');
is($hres{quizzes}[0]{instructions}, $instructions, 'get_quizzes_infos instructions correct');
is($hres{quizzes}[0]{visible},      'public',      'get_quizzes_infos visible correct');


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
