use utf8;
use open qw(:std :encoding(UTF-8));

# NOTE this a first long test suite to test the most important features of quiz creation and play

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use V;

use Mojolicious::Plugin::Config;


# use a test configuration file
my $configuration_test_file = './TEST-profweb.conf';

# TODO not very solid, try to use Mojolicious::Plugin::Config to read the file
my $test_config = require $configuration_test_file;
my $t           = Test::Mojo->new('Profweb', $test_config);

# use a test database, recreate it each time
$t->app->pg->migrations->migrate(0)->migrate();

$t->ua->max_redirects(3);

### Map of the site for testing

# a page containing a form to register
my $register_form = '/';

# an endpoint to register
my $register_page = '/register';

# verify an email
my $verify_email_page = '/verify_email';

# link to confirm an email address
my $verif_link_regex = qr!link http.*($verify_email_page.*jwt=.*)\.!;

# a page containing a form to login
my $login_form = '/';

# an endpoint to login
my $login_page = '/login';

# log out page
my $logout_page = '/logout';

# dashboard page
my $dashboard_page = '/dashboard';

# Quiz Authoring page
my $author_page = '/author';

# Add a new quiz
my $add_quiz_page = "$author_page/add-quiz";

# Rename a quiz
my $update_quiz_name_page = "$author_page/update-quiz-name";

# Delete a quiz
my $delete_quiz_page = "$author_page/delete-quiz";

# Add a new item to a quiz
my $add_item_page = "$author_page/add-new-item-to-quiz";

# Update an item
my $update_item_page = "$author_page/update-item";

# respond to a question
my $respond_page = "/respond-question";

my $name = 'wailtest3';
my $pwd  = 'liaw12345';
my ($quiz1_name, $quiz2_name, $quiz3_name, $quiz4_name) = ('Test quiz été', 'Autumn', '0', '1');

my ($question1, $answer1) = ('Quèsaco?',                          'τίποτα');
my ($question2, $answer2) = ('Bonjour?',                          'Bonjour!');
my ($question3, $answer3) = ('What does it have in its pockets?', 'Birthday present');
my ($question4, $answer4) = ('1 - 1',                             '0');
my ($question5, $answer5) = ('1 + 1',                             '2');

# to be found in web page
my ($quiz1_id, $quiz2_id, $quiz3_id, $quiz4_id);
my ($item1_id, $item2_id, $item3_id, $item4_id);

# get a CSRF token from a page
sub csrf {
  return (csrf_token => $t->ua->get(shift)->res->dom->at('form input[name=csrf_token]')->val);
}
ok(csrf($login_form), 'got a CSRF token from a page');

# Register users for testing
# user without email
$t->post_ok($register_page => form => {csrf($register_form), name => $name, pwd1 => $pwd, pwd2 => $pwd})
  ->status_is(200)
  ->text_like('b#notif-ok' => qr/You are now registered./);
$t->get_ok($logout_page)->status_is(200);


subtest 'Create a quiz' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_is('h2#author a' => 'Quiz Authoring')
    ->text_like('p#do-quiz-select-no-quiz' => qr/no quiz yet/)
    ->text_is('p#single-question-no-quiz' => undef)
    ->text_is('p#do-quiz-no-quiz'         => undef);

  $t->get_ok($author_page)->status_is(200)->text_is('h1' => 'Authoring')->text_is('h3' => 'Create a quiz');

  $t->post_ok($add_quiz_page => form => {csrf($author_page), new_quiz_name => $quiz1_name})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Quiz created/)
    ->text_is('h4' => $quiz1_name);

  $quiz1_id = $t->tx->res->dom->at('input[name=quiz_id]')->attr('value');

  $t->post_ok(
    $add_item_page => form => {
      csrf($author_page),
      new_question => $question1,
      new_answer   => $answer1,
      quiz_id      => $quiz1_id,
      quiz_name    => $quiz1_name
    }
    )
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Item created/)
    ->attr_is('input[name=updated_question]', 'value', $question1)
    ->attr_is('input[name=updated_answer]',   'value', $answer1);

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Respond to a whole quiz' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_is('div#do-quiz h3#quiz-name' => "Quiz: $quiz1_name")
    ->text_like('p#single-question-asked span' => qr/$question1/)
    ->text_like('p#single-question-asked'      => qr/from the quiz $quiz1_name/)
    ->text_like('p#single-question-asked'      => qr/no answer yet/)
    ->text_is('div#do-quiz p#question-asked span' => $question1)
    ->text_like('div#do-quiz p#question-asked' => qr/no answer yet/)
    ->text_like('form#do-quiz-select option'   => qr/$quiz1_name \(0%\)/, '0% grade on first question no answer')
    ->text_is('p#do-quiz-no-quiz' => undef);

  # check translations
  $t->get_ok($dashboard_page => {'Accept-Language' => 'fr'})
    ->status_is(200)
    ->text_like('p#single-question-asked'      => qr/pas encore de réponse/)
    ->text_like('div#do-quiz p#question-asked' => qr/pas encore de réponse/);

  $item1_id = $t->tx->res->dom->at('div#single-question input[name=item_id]')->attr('value');

  $t->get_ok(
    $respond_page => form => {
      csrf($dashboard_page),
      page_source => 'dashboard',
      quiz_type   => 'whole-quiz',
      item_id     => $item1_id,
      response    => $answer1
    }
  )->status_is(200)->text_like('p#response-result' => qr/Good answer/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_like('p#single-question-asked'      => qr/your average score: 100%/)
    ->text_like('div#do-quiz p#question-asked' => qr/your average score: 100%/)
    ->text_like('form#do-quiz-select option'   => qr/$quiz1_name \(100%\)/, '100% grade after first good response');

  $t->get_ok(
    $respond_page => form => {
      csrf($dashboard_page),
      page_source => 'dashboard',
      quiz_type   => 'whole-quiz',
      item_id     => $item1_id,
      response    => "x$answer1"
    }
  )->status_is(200)->text_like('p#response-result' => qr/Wrong answer/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_like('p#single-question-asked'      => qr/your average score: 50%/)
    ->text_like('div#do-quiz p#question-asked' => qr/your average score: 50%/)
    ->text_is('div#single-question span#question' => $question1);

  # add another question, it should be the next Single Question
  $t->post_ok(
    $add_item_page => form => {
      csrf($author_page),
      new_question => $question2,
      new_answer   => $answer2,
      quiz_id      => $quiz1_id,
      quiz_name    => $quiz1_name
    }
  )->status_is(200)->text_like('b#notif-ok' => qr/Item created/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_like('p#single-question-asked' => qr/no answer yet/)
    ->text_is('div#single-question span#question' => $question2);

  $item2_id = $t->tx->res->dom->at('div#single-question input[name=item_id]')->attr('value');

  # answer correctly two times the new question then the Single Question will be the previous question
  $t->get_ok(
    $respond_page => form => {
      csrf($dashboard_page),
      page_source => 'dashboard',
      quiz_type   => 'single-question',
      item_id     => $item2_id,
      response    => $answer2
    }
  )->status_is(200)->text_like('p#response-result' => qr/Good answer/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_like('div#single-question p#single-question-asked' => qr/from the quiz $quiz1_name/)
    ->text_like('p#single-question-asked'                     => qr/your average score: 100%/)
    ->text_is('div#single-question span#question'          => $question2)
    ->text_is('div#do-quiz p#question-asked span#question' => $question2)
    ->text_like('div#do-quiz p#question-asked' => qr/your average score: 100%/)
    ->text_like('form#do-quiz-select option'   => qr/$quiz1_name \(67%\)/);

  $t->get_ok(
    $respond_page => form => {
      csrf($dashboard_page),
      page_source => 'dashboard',
      quiz_type   => 'single-question',
      item_id     => $item2_id,
      response    => $answer2
    }
  )->status_is(200)->text_like('p#response-result' => qr/Good answer/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_like('div#single-question p#single-question-asked' => qr/from the quiz $quiz1_name/)
    ->text_is('div#single-question span#question' => $question1);

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Adding a second quiz' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  # add a new quiz with a new item and see it appear in the dashboard
  $t->post_ok($add_quiz_page => form => {csrf($author_page), new_quiz_name => $quiz2_name})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Quiz created/)
    ->text_is('h4' => $quiz2_name);

  $quiz2_id = $t->tx->res->dom->at("div#quiz-$quiz2_name input[name=quiz_id]")->attr('value');

  $t->post_ok(
    $add_item_page => form => {
      csrf($author_page),
      new_question => $question3,
      new_answer   => $answer3,
      quiz_id      => $quiz2_id,
      quiz_name    => $quiz2_name
    }
  )->status_is(200)->text_like('b#notif-ok' => qr/Item created/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_like('div#single-question p#single-question-asked' => qr/from the quiz $quiz2_name/)
    ->text_is('div#single-question span#question' => $question3)
    ->text_like('p#single-question-asked' => qr/no answer yet/)
    ->text_is('div#do-quiz h3#quiz-name' => "Quiz: $quiz2_name", 'new quiz appears first')
    ->text_like('div#do-quiz p#question-asked' => qr/no answer yet/)
    ->text_like('form#do-quiz-select option'   => qr/$quiz2_name \(0%\)/)
    ->text_is('div#do-quiz p#question-asked span' => $question3, 'question from new quiz');


  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Questions and answers edge cases' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->post_ok(
    $add_item_page => form => {
      csrf($author_page),
      new_question => $question4,
      new_answer   => $answer4,
      quiz_id      => $quiz2_id,
      quiz_name    => $quiz2_name
    }
  )->status_is(200)->text_like('b#notif-ok' => qr/Item created/);

  # get the new item id
  $t->get_ok($author_page)
    ->status_is(200)
    ->element_exists("input[name=updated_question][value=$question4]", 'author page has the new question')
    ->element_exists("input[name=updated_answer][value=$answer4]",     'author page has the new answer');

  my $input_id = $t->tx->res->dom->at("input[name=updated_question][value=$question4]")->attr('id');
  like($input_id, qr/question-item-id-.*/, 'spotted the new item id');
  $input_id =~ /question-item-id-(.*)/;
  $item4_id = $1;
  ok($item4_id, 'got the new item id');

  $t->get_ok(
    $respond_page => form => {
      csrf($dashboard_page),
      page_source => 'dashboard',
      quiz_type   => 'whole-quiz',
      item_id     => $item4_id,
      response    => $answer4
    }
  )->status_is(200)->text_like('p#response-result' => qr/Good answer/);

  # change the question and answer and respond again
  $t->post_ok(
    $update_item_page => form => {
      csrf($author_page),
      item_to_update   => $item4_id,
      old_question     => $question4,
      old_answer       => $answer4,
      updated_question => $question5,
      updated_answer   => $answer5
    }
    )
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Item question and answer changed/)
    ->element_exists("input[name=updated_question][value=$question5]", 'author page has the updated question')
    ->element_exists("input[name=updated_answer][value=$answer5]",     'author page has the updated answer');

  $t->get_ok(
    $respond_page => form => {
      csrf($dashboard_page),
      page_source => 'dashboard',
      quiz_type   => 'whole-quiz',
      item_id     => $item4_id,
      response    => $answer5
    }
  )->status_is(200)->text_like('p#response-result' => qr/Good answer/);

  # change back to the original and answer again
  $t->post_ok(
    $update_item_page => form => {
      csrf($author_page),
      item_to_update   => $item4_id,
      old_question     => $question5,
      old_answer       => $answer5,
      updated_question => $question4,
      updated_answer   => $answer4
    }
    )
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Item question and answer changed/)
    ->element_exists("input[name=updated_question][value=$question4]", 'author page has the original question')
    ->element_exists("input[name=updated_answer][value=$answer4]",     'author page has the original answer');

  $t->get_ok(
    $respond_page => form => {
      csrf($dashboard_page),
      page_source => 'dashboard',
      quiz_type   => 'whole-quiz',
      item_id     => $item4_id,
      response    => $answer4
    }
  )->status_is(200)->text_like('p#response-result' => qr/Good answer/);

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Quiz name edge cases' => sub {
  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->post_ok($add_quiz_page => form => {csrf($author_page), new_quiz_name => $quiz3_name})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Quiz created/)
    ->text_is('h4' => $quiz3_name);

  $quiz3_id = $t->tx->res->dom->at("div#quiz-$quiz3_name input[name=quiz_id]")->attr('value');
  ok($quiz3_id, 'got the edge case quiz id');

  $t->post_ok($update_quiz_name_page => form =>
      {csrf($author_page), quiz_name_to_update => $quiz3_name, new_quiz_name => $quiz4_name})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Quiz name changed/)
    ->text_is('h4' => $quiz4_name)
    ->text_isnt('h4' => $quiz3_name);

  $t->post_ok($update_quiz_name_page => form =>
      {csrf($author_page), quiz_name_to_update => $quiz4_name, new_quiz_name => $quiz3_name})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Quiz name changed/)
    ->text_is('h4' => $quiz3_name)
    ->text_isnt('h4' => $quiz4_name);

  $t->post_ok($delete_quiz_page => form => {csrf($author_page), quiz_name_to_delete => $quiz3_name})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Quiz deleted/)
    ->text_isnt('h4' => $quiz3_name);

  $t->get_ok($logout_page)->status_is(200);
};


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
