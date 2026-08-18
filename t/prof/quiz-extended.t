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

my $quiz_name        = 'Premier Quiz';
my $question1        = '2 + 20';
my $answer1_fragment = '2';
my $answer1          = "${answer1_fragment}2";
my $question2        = '1 + 10';
my $answer2          = '11';
my $bad_answer2      = '6';
my ($quiz_id, $quiz2_id);    # to be found after creating the quiz

%hres = $prof->create_quiz($user_id, $quiz_name, $question1, $answer1, $question2, $answer2);
%hres = $prof->get_quizzes_infos(name => $quiz_name);
ok($hres{status}, 'got quizzes infos');
$quiz_id = $hres{quizzes}[0]{id};
%hres    = $prof->next_question($user_id, $quiz_id);
my $item_id       = $hres{item_id};
my $first_item_id = $item_id;         # save it for later
%hres    = $prof->respond_question($user_id, $item_id, $answer1);
%hres    = $prof->next_question($user_id, $quiz_id);
$item_id = $hres{item_id};
my $second_item_id = $item_id;        # save it for later
%hres = $prof->respond_question($user_id, $item_id, $bad_answer2);

my $search_term = 'tition';
my $quiz2_name  = "Répé${search_term}s";
my $question3   = 'Été';
my $answer3     = 'صَيْف';
%hres     = $prof->create_quiz($user_id, $quiz2_name, $question3, $answer3);
%hres     = $prof->get_quizzes_infos(name => $quiz2_name);
$quiz2_id = $hres{quizzes}[0]{id};
%hres     = $prof->next_question($user_id, $quiz2_id);
my $item3_id = $hres{item_id};
%hres = $prof->respond_question($user_id, $item3_id, $answer3);

%hres = $prof->get_average_grade($user_id);
ok($hres{status}, 'got all stats');
is($hres{average_prct}, 67, 'all stats average');

%hres = $prof->get_average_grade($user_id, quiz => $quiz2_name);
ok($hres{status}, 'got quiz stats');
is($hres{average_prct}, 100, 'quiz stats average');

%hres = $prof->get_average_grade($user_id, item_id => $item_id);
ok($hres{status}, 'got item stats');
is($hres{average_prct}, 0, 'item stats average');

%hres = $prof->get_quizzes($user_id);
ok($hres{status}, 'get quizzes');
@quizzes = @{$hres{quizzes}};
is(scalar(@quizzes), 2, 'get quizzes correct count');
ok((grep { $_ eq $quiz2_name } @quizzes), 'get quizzes one expected quiz');

%hres = $prof->get_quizzes($user_id, $search_term);
ok($hres{status}, 'get quizzes word');
@quizzes = @{$hres{quizzes}};
is(scalar(@quizzes), 1, 'get quizzes word count correct');
ok((grep { $_ eq $quiz2_name } @quizzes), 'get quizzes word one expected quiz');

%hres = $prof->rename_quiz($user_id, 'lsdkjfsdlkf;s\2389', 'Bob');
ok(!$hres{status}, 'failed to rename a quiz that does not exist');
like($hres{msg}, qr/No Quiz named/, 'failed to rename a quiz that does not exist message');

my $new_name = 'Quiz 1';
%hres = $prof->rename_quiz($user_id, $quiz2_name, $new_name);
ok($hres{status}, 'rename a quiz');
%hres    = $prof->get_quizzes($user_id);
@quizzes = @{$hres{quizzes}};
ok((grep { $_ eq $new_name } @quizzes), 'renamed quiz found');

%hres = $prof->delete_quiz($user_id, $new_name);
ok($hres{status}, 'deleted a quiz');
%hres    = $prof->get_quizzes($user_id);
@quizzes = @{$hres{quizzes}};
ok(!(grep { $_ eq $new_name } @quizzes), 'deleted quiz not found');

%hres = $prof->get_items($user_id);
ok($hres{status}, 'got all items');
is(scalar(@{$hres{items}}), 3, 'got items correct count');

%hres = $prof->get_items($user_id, quiz => $quiz_name);
ok($hres{status}, 'got items for a quiz');
my @items = @{$hres{items}};
is(scalar(@items), 2, 'got items for a quiz correct count');
ok(grep({ $_->{question} eq $question1 } @items), 'got items one expected question');
ok(exists $items[0]->{rank},                      'got items item has rank key');
ok(!defined $items[0]->{rank},                    'got items item rank not defined by default');

%hres = $prof->get_items($user_id, question => $question1);
ok($hres{status}, 'got items for a question');
is(scalar(@{$hres{items}}), 1, 'got items for a question correct count');
my $item1 = $hres{items}->[0];

%hres = $prof->get_items($user_id, answer => $answer1_fragment);
ok($hres{status}, 'got items for an answer');
is(scalar(@{$hres{items}}), 1, 'got items for an answer correct count');

%hres = $prof->remove_item_from_quiz($user_id, $quiz_name, $item1->{id});
ok($hres{status}, 'removed item from quiz');

%hres = $prof->remove_item_from_quiz($user_id, $quiz_name, $item1->{id});
ok(!$hres{status}, 'failed to remove item from quiz again');

%hres = $prof->get_items($user_id, question => $question1);
is(scalar(@{$hres{items}}), 1, 'after remove item from quiz, it still exists');

%hres  = $prof->get_items($user_id, quiz => $quiz_name);
@items = @{$hres{items}};
is(scalar(@items), 1, 'after remove item from quiz, correct item count in quiz');
ok(grep({ $_->{question} eq $question2 } @items), 'after remove item, expected item left in quiz');

my $question1_edited = '20 + 2';
%hres = $prof->edit_item_question($user_id, $item1->{id}, $question1_edited);
ok($hres{status}, 'edited item question');

%hres = $prof->get_items($user_id, question => $question1);
is(scalar(@{$hres{items}}), 0, 'edited question has disappeared');

my $answer1_edited = 'twenty-two';
%hres = $prof->edit_item_answer($user_id, $item1->{id}, $answer1_edited);
ok($hres{status}, 'edited item answer');

%hres = $prof->get_items($user_id, answer => $answer1);
is(scalar(@{$hres{items}}), 0, 'edited answer has disappeared');

my $old_items_cnt = scalar(@items);
%hres = $prof->delete_item($user_id, $item3_id);
ok($hres{status}, 'deleted an item');
%hres  = $prof->get_items($user_id);
@items = @{$hres{items}};
ok(!(grep { $_ eq $new_name } @quizzes), 'deleted quiz not found');

%hres = $prof->delete_item($user_id, $item3_id);
ok(!$hres{status}, 'failed to delete an item again');

my $question4 = 'Atomic Number of carbon?';
my $answer4   = '6';
%hres = $prof->create_item($user_id, $question4, $answer4);
ok($hres{status}, 'created item');
$item_id = $hres{item_id};
my $third_item_id = $item_id;    # save it for later
ok($item_id, 'created item with an id');

%hres = $prof->add_item_to_quiz($user_id, $quiz_name, $item_id);
ok($hres{status}, 'added item to quiz');
%hres  = $prof->get_items($user_id, quiz => $quiz_name);
@items = @{$hres{items}};
ok(grep({ $_->{id} eq $item_id } @items), 'added item appears in the quiz');

%hres = $prof->add_item_to_quiz($user_id, $quiz_name, $first_item_id);
is($items[0]->{id}, $second_item_id, 'the first item id is as expected before reordering');
%hres = $prof->set_quiz_items_rank($user_id, $quiz_name, $third_item_id, $second_item_id, $first_item_id);
ok($hres{status}, 'reordered items in quiz');
%hres  = $prof->get_items($user_id, quiz => $quiz_name);
@items = @{$hres{items}};
is($items[0]->{id}, $third_item_id, 'the third item id is as expected for reordering');
ok(defined $items[0]->{rank}, 'after reordering, get items has rank');

%hres = $prof->set_quiz_items_rank($user_id, $quiz_name, $first_item_id, $second_item_id, $third_item_id);
ok($hres{status}, 'reordered items again in quiz');
%hres  = $prof->get_items($user_id, quiz => $quiz_name);
@items = @{$hres{items}};
is($items[0]->{id}, $first_item_id, 'the third item id is as expected for reordering');

%hres = $prof->set_quiz_items_rank($user_id, $quiz_name, $first_item_id, $second_item_id, $third_item_id);
ok($hres{status}, 'reordered items no change in quiz');
%hres  = $prof->get_items($user_id, quiz => $quiz_name);
@items = @{$hres{items}};
is($items[0]->{id}, $first_item_id, 'the first item id is as expected for reordering');

%hres = $prof->get_average_grade($user_id, item_id => $first_item_id);
is($hres{average_prct}, 100, 'got average grade for item before deletion');
%hres = $prof->delete_item_results($user_id, $first_item_id);
ok($hres{status}, 'deleted item results');
%hres = $prof->get_average_grade($user_id, item_id => $first_item_id);
ok(!defined($hres{average_prct}), 'average grade undef after deletion');

%hres = $prof->get_average_grade($user_id);
is($hres{average_prct}, 0, 'got all average grade before deletion');
%hres = $prof->delete_all_results($user_id);
ok($hres{status}, 'deleted all results');
%hres = $prof->get_average_grade($user_id);
ok(!defined($hres{average_prct}), 'all average grade undef after deletion');

%hres = $prof->delete_all_results($user_id);
ok($hres{status}, 'deleted all results on no result');
is($hres{deletions_cnt}, 0, 'no deletion on no result');

%hres = $prof->cleanup_old_results();
ok($hres{status}, 'cleaned up results on no result');
is($hres{deletions_cnt}, 0, 'clean up results no deletion on no result');

foreach my $i (1 .. 3) {
  $prof->respond_question($user_id, $first_item_id, $answer1);
}
%hres = $prof->cleanup_old_results();
ok($hres{status}, 'cleaned up results on few results');
is($hres{deletions_cnt}, 0, 'clean up results no deletion on few results');

# 8 out of these 10 new responses will be cleaned up
foreach my $i (1 .. 10) {
  $prof->respond_question($user_id, $first_item_id, $answer1);
}

# none of these new responses will be cleaned up
foreach my $i (1 .. 5) {
  $prof->respond_question($user_id, $second_item_id, $answer2);
}
%hres = $prof->cleanup_old_results();
ok($hres{status}, 'cleaned up results on many results');
is($hres{deletions_cnt}, 8, 'clean up results deletions on many results');

Profweb::Model::Prof::set_results_keep_days(0);
%hres = $prof->cleanup_old_results();
ok($hres{status}, 'cleaned up results on a shorter date');
is($hres{deletions_cnt}, 10, 'clean up results deletions on a shorter date');

%hres = $prof->cleanup_old_sessions();
ok($hres{status}, 'cleaned up sessions on no sessions');
is($hres{deletions_cnt}, 0, 'clean up sessions no deletion on no session');

$prof->session_start_quiz($user_id, $quiz_name);
%hres = $prof->cleanup_old_sessions();
ok($hres{status}, 'cleaned up sessions on a single session');
is($hres{deletions_cnt}, 0, 'clean up sessions no deletion on a single session');

$prof->session_start_quiz($user_id, $quiz_name);
%hres = $prof->cleanup_old_sessions();
ok($hres{status}, 'cleaned up sessions on two sessions');
is($hres{deletions_cnt}, 1, 'clean up sessions deletion on two sessions');

Profweb::Model::Prof::set_sessions_keep_days(0);
%hres = $prof->cleanup_old_sessions();
ok($hres{status}, 'cleaned up sessions on short date');
is($hres{deletions_cnt}, 1, 'clean up sessions deletion on short date');


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
