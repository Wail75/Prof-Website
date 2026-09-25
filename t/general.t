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

# Add a new item to a quiz
my $add_item_page = "$author_page/add-new-item-to-quiz";

# respond to a question
my $respond_page = "/respond-question";

my $name = 'wailtest3';
my $pwd  = 'liaw12345';
my ($quiz1_name, $quiz2_name) = ('Test quiz été', 'Autumn');

my ($question1, $answer1) = ('Quèsaco?',                          'τίποτα');
my ($question2, $answer2) = ('Bonjour?',                          'Bonjour!');
my ($question3, $answer3) = ('What does it have in its pockets?', 'Birthday present');

# to be found in web page
my ($quiz1_id, $quiz2_id);
my ($item1_id, $item2_id, $item3_id);

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

  $t->get_ok($dashboard_page)->status_is(200)->text_is('h2#author a' => 'Quiz Authoring');

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
    ->attr_is('td input[name=updated_question]', 'value', $question1)
    ->attr_is('td input[name=updated_answer]',   'value', $answer1);

  $t->get_ok($logout_page)->status_is(200);
};

subtest 'Respond to a whole quiz' => sub {

  $t->post_ok($login_page => form => {csrf($login_form), name => $name, pwd => $pwd})
    ->status_is(200)
    ->text_like('b' => qr/Login successful/);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_is('div#do-quiz h3#quiz-name'          => "Quiz: $quiz1_name")
    ->text_is('div#do-quiz p#question-asked span' => $question1);

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
    ->text_like('div#single-question p#question-asked' => qr/from the quiz $quiz1_name/)
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
    ->text_like('div#single-question p#question-asked' => qr/from the quiz $quiz1_name/)
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
    ->text_like('div#single-question p#question-asked' => qr/from the quiz $quiz1_name/)
    ->text_is('div#single-question span#question' => $question2);

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
    ->text_like('div#single-question p#question-asked' => qr/from the quiz $quiz1_name/)
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

  $quiz2_id = $t->tx->res->dom->at("table#quiz-$quiz2_name input[name=quiz_id]")->attr('value');

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
    ->text_like('div#single-question p#question-asked' => qr/from the quiz $quiz2_name/)
    ->text_is('div#single-question span#question' => $question3);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_is('div#do-quiz h3#quiz-name'          => "Quiz: $quiz2_name")
    ->text_is('div#do-quiz p#question-asked span' => $question3);


  $t->get_ok($logout_page)->status_is(200);
};


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
