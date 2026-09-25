package Profweb::Controller::Profweb;

use Mojo::Base 'Mojolicious::Controller';

# if returning from an endpoint that may be called from different pages
my $DEFAULT_RETURN_PAGE = 'dashboard';

sub log_context {
  my ($c, $method_name) = @_;
  return $c->app->log->context('[ControllerProfweb]', "[$method_name]");
}

sub index {
  my $c = shift;

  my $log = $c->log_context("index");
  $log->info("start.");
  $log->info("done.");

  return $c->render();
}

sub dashboard {
  my $c = shift;

  my $user_id = $c->session('id') || '';
  my $log     = $c->log_context("dashboard '$user_id'");
  $log->info("start.");

  my %hres  = $c->prof->get_quizzes_infos(user_id => $user_id);
  my $quizs = $hres{status} ? $hres{quizzes} : [];
  $log->debug("found " . @$quizs . " quizzes for user id $user_id");

  # a newly selected quiz replaces the previously selected quiz
  my $v = $c->validation();
  $v->csrf_protect()->optional('selected_quiz');

  # stay silent on CSRF token errors
  if (!$v->has_error()) {
    $c->session(selected_quiz => $c->param('selected_quiz'));
  }

  ## Single Question
  my ($single_question_quiz, $single_item_id, $single_question, $single_quiz_name);
  %hres = $c->prof->single_question($user_id);
  if (!$hres{status} || !$hres{item_id}) {
    $log->warn("failed to get single question '$hres{msg}'.");
  }
  else {
    ($single_item_id, $single_question, $single_quiz_name) = @hres{qw(item_id question quiz_name)};
  }

  ## Do Quiz
  my ($selected_quiz_name, $item_id, $question);
  if (@$quizs) {

    # there is no particular reason for taking the first quiz, it's like a random default quiz
    my $random_quiz_id = $quizs->[0]{id};
    $c->session(selected_quiz => $random_quiz_id) unless $c->session('selected_quiz');

    # find the selected quiz name in the list
    my @qs   = grep { $_->{id} == $c->session('selected_quiz') } @$quizs;
    my $quiz = shift @qs;
    $selected_quiz_name = $quiz->{name};

    %hres = $c->prof->next_question($user_id, $c->session('selected_quiz'));
    if (!$hres{status} || !$hres{item_id}) {
      $log->warn("failed to get next question for quiz id '$quiz->{id}': '$hres{msg}'.");
    }
    else {
      ($item_id, $question) = @hres{qw(item_id question)};
    }
  }
  $log->info("done.");

  return $c->render(
    page_source             => $c->url_for,
    last_response_quiz_type => $c->session('last_response_quiz_type') || '',
    selected_quiz_name      => $selected_quiz_name,
    item_id                 => $item_id,
    question                => $question,
    quizs                   => $quizs,
    single_item_id          => $single_item_id,
    single_question         => $single_question,
    single_quiz_name        => $single_quiz_name
  );
}

sub do_quizs {
  my $c = shift;

  my $user_id = $c->session('id') || '';
  my $log     = $c->log_context("do_quizs '$user_id'");
  $log->info("start.");

  my $author  = $c->stash('author');
  my $quiz_id = $c->stash('quiz');

  my %hres = $c->prof->get_quizzes_infos(id => $quiz_id);
  return $c->flash(error => 'Quiz not found.')->redirect_to('do_quizs') unless $hres{status};

  my $selected_quiz_name = $hres{quizzes}[0]{name};

  my ($item_id, $question);
  %hres = $c->prof->next_question($user_id, $quiz_id);
  if (!$hres{status} || !$hres{item_id}) {
    $log->warn("failed to get next question for quiz id '$quiz_id': '$hres{msg}'.");
  }
  else {
    ($item_id, $question) = @hres{qw(item_id question)};
    $log->info("done.");
  }

  return $c->render(
    page_source             => $c->url_for,
    last_response_quiz_type => $c->session('last_response_quiz_type') || '',
    selected_quiz_name      => $selected_quiz_name,
    item_id                 => $item_id,
    question                => $question,
    quiz_id                 => $quiz_id
  );
}

sub respond_question {
  my $c = shift;
  my $err;

  my $v = $c->validation();

  # the param 'response' might be any string (empty, with leading spaces etc)
  $v->csrf_protect()
    ->required('page_source', 'trim', 'not_empty')
    ->required('quiz_type',   'trim', 'not_empty')
    ->required('item_id',     'trim', 'not_empty')
    ->required('response');

  if ($v->has_error('csrf_token')) {
    $err = 'You can not do that.';
  }
  elsif ($v->has_error()) {
    $err = 'Your answer has not been saved.';
  }
  my $page_source = $c->param('page_source');
  return $c->flash(error => $err)->redirect_to($page_source || $DEFAULT_RETURN_PAGE) if $err;

  my $user_id   = $c->session('id') || '';
  my $quiz_type = $c->param('quiz_type');
  my $item_id   = $c->param('item_id');
  my $response  = $c->param('response');

  # store the quiz_type so that the template knows which type of quiz is being answered
  $c->session('last_response_quiz_type' => $quiz_type);

  my $log = $c->log_context("respond_question '$user_id'/'$item_id'");
  $log->info("start.");

  my %hres = $c->prof->respond_question($user_id, $item_id, $response);

  if ($hres{status}) {
    if ($user_id) {
      $c->flash(message => 'Your answer has been saved.');
    }
    else {
      $c->flash(error => 'To get more questions, please create an account and log in.');
    }
    $c->flash(response_msg => ($hres{grade} ? "\x{2611}Good answer" : "\x{274C}Wrong answer"));
    $log->info("done.");
  }
  else {
    $c->flash(error => 'Your answer has not been saved.');
    $log->warn("failed '$hres{msg}'.");
  }
  $log->info("done.");

  $c->redirect_to($page_source);
}

1;
