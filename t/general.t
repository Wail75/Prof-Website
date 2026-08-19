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

my $name      = 'wailtest3';
my $pwd       = 'liaw12345';
my $quiz_name = 'Test quiz été';

# to be found in web page
my $quiz_id;
my $question1 = 'Quèsaco?';
my $answer1   = 'τίποτα';

# to be found in web page
my $item1_id;

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

  $t->get_ok($dashboard_page)->status_is(200)->text_is('h1#author a' => 'Quiz Authoring');

  $t->get_ok($author_page)->status_is(200)->text_is('h1' => 'Authoring')->text_is('h3' => 'Create a quiz');

  $t->post_ok($add_quiz_page => form => {csrf($author_page), new_quiz_name => $quiz_name})
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Quiz created/)
    ->text_is('h4' => $quiz_name);

  $quiz_id = $t->tx->res->dom->at('input[name=quiz_id]')->attr('value');

  $t->post_ok(
    $add_item_page => form => {
      csrf($author_page),
      new_question => $question1,
      new_answer   => $answer1,
      quiz_id      => $quiz_id,
      quiz_name    => $quiz_name
    }
    )
    ->status_is(200)
    ->text_like('b#notif-ok' => qr/Item created/)
    ->attr_is('td input[name=updated_question]', 'value', $question1)
    ->attr_is('td input[name=updated_answer]',   'value', $answer1);

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_is('h1#quiz-name'       => "Quiz: $quiz_name")
    ->text_is('p#question-asked b' => $question1);

  $item1_id = $t->tx->res->dom->at('input[name=item_id]')->attr('value');

  $t->get_ok($dashboard_page)
    ->status_is(200)
    ->text_is('h1#quiz-name'       => "Quiz: $quiz_name")
    ->text_is('p#question-asked b' => $question1);

  $t->get_ok($respond_page => form => {csrf($dashboard_page), item_id => $quiz_id, response => $answer1})
    ->status_is(200)
    ->text_like('p#response-result' => qr/Good answer/);

  $t->get_ok($respond_page => form => {csrf($dashboard_page), item_id => $quiz_id, response => "x$answer1"})
    ->status_is(200)
    ->text_like('p#response-result' => qr/Wrong answer/);

  $t->get_ok($logout_page)->status_is(200);

};


# delete the temporary test schema
$t->app->pg->migrations->migrate(0);

done_testing();
