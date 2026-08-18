package Profweb::Controller::Author;

use Mojo::Base 'Mojolicious::Controller';

sub log_context {
  my ($c, $method_name) = @_;
  return $c->app->log->context('[ControllerAuthor]', "[$method_name]");
}

sub index {
  my $c = shift;

  my $log = $c->log_context("index");
  $log->info("start.");

  my %hres  = $c->prof->get_quizzes_infos(user_id => $c->session('id'));
  my $quizs = $hres{status} ? $hres{quizzes} : [];
  $log->debug("found " . @$quizs . " quizzes for user id " . $c->session('id'));
  my $quizs_to_items = {};
  foreach my $quiz (@$quizs) {

    # if a quiz has just been created, make it the selected quiz
    if ($c->session('created_quiz_name') && $quiz->{name} eq $c->session('created_quiz_name')) {
      $c->session(selected_quiz     => $quiz->{id});
      $c->session(created_quiz_name => undef);
    }
    %hres = $c->prof->get_items($c->session('id'), quiz => $quiz->{name});
    if (!$hres{status} || !$hres{items}) {
      $quizs_to_items->{$quiz->{name}} = [];
    }
    else {
      $quizs_to_items->{$quiz->{name}} = $hres{items};
    }
  }

  %hres = $c->prof->get_items($c->session('id'));
  my $items = $hres{status} ? $hres{items} : [];

  $c->stash(user_id => $c->session('id'));

  $log->info('done.');
  $c->render(quizs => $quizs, quizs_to_items => $quizs_to_items, items => $items);
}

sub add_quiz {
  my $c = shift;
  my $err;

  my $v = $c->validation();
  $v->csrf_protect()->required('new_quiz_name', 'trim', 'not_empty');
  if ($v->has_error('csrf_token')) {
    $err = 'You can not do that.';
  }
  elsif ($v->has_error()) {
    $err = 'Quiz creation failed.';
  }
  return $c->flash(error => $err)->redirect_to('author_index') if $err;

  my $quiz_name = $c->param('new_quiz_name');

  my %hres = $c->prof->create_quiz($c->session('id'), $quiz_name);

  if ($hres{status}) {
    $c->flash(message => 'Quiz created.');

    # will be used to determine the selected_quiz
    $c->session(created_quiz_name => $quiz_name) if $quiz_name;
  }
  else {
    $c->flash(error => 'Quiz creation failed.');
  }

  $c->redirect_to('author_index');
}

sub update_quiz_name {
  my $c              = shift;
  my $quiz_to_update = $c->param('quiz_name_to_update') || '';
  my $new_quiz_name  = $c->param('new_quiz_name')       || '';
  my %hres           = $c->prof->rename_quiz($c->session('id'), $quiz_to_update, $new_quiz_name);

  if ($hres{status}) {
    $c->flash(message => 'Quiz name changed.');
  }
  else {
    $c->flash(error => 'Quiz name change failed.');
  }
  $c->redirect_to('author_index');
}

sub delete_quiz {
  my $c         = shift;
  my $quiz_name = $c->param('quiz_name_to_delete') || '';
  my %hres      = $c->prof->delete_quiz($c->session('id'), $quiz_name);

  if ($hres{status}) {
    $c->flash(message => 'Quiz deleted.');
  }
  else {
    $c->flash(error => 'Quiz deletion failed.');
  }
  $c->redirect_to('author_index');
}

sub create_item {
  my $c        = shift;
  my $question = $c->param('new_question') || '';
  my $answer   = $c->param('new_answer')   || '';
  my %hres     = $c->prof->create_item($c->session('id'), $question, $answer);

  if ($hres{status}) {
    $c->flash(message => 'Item created.');
  }
  else {
    $c->flash(error => 'Item creation failed.');
  }
  $c->redirect_to('author_index');
}

sub delete_item {
  my $c       = shift;
  my $item_id = $c->param('item_to_delete') || '';
  my %hres    = $c->prof->delete_item($c->session('id'), $item_id);

  if ($hres{status}) {
    $c->flash(message => 'Item deleted.');
  }
  else {
    $c->flash(error => 'Item deletion failed.');
  }
  $c->redirect_to('author_index');
}

sub update_item {
  my $c            = shift;
  my $item_id      = $c->param('item_to_update')   || '';
  my $old_question = $c->param('old_question')     || '';
  my $old_answer   = $c->param('old_answer')       || '';
  my $question     = $c->param('updated_question') || '';
  my $answer       = $c->param('updated_answer')   || '';

  my ($que_ok, $que_ko, $ans_ok, $ans_ko);
  if ($old_question ne $question) {
    my %hres = $c->prof->edit_item_question($c->session('id'), $item_id, $question);
    if ($hres{status}) {
      $que_ok = 1;
    }
    else {
      $que_ko = 1;
    }
  }

  if ($old_answer ne $answer) {
    my %hres = $c->prof->edit_item_answer($c->session('id'), $item_id, $answer);
    if ($hres{status}) {
      $ans_ok = 1;
    }
    else {
      $ans_ko = 1;
    }
  }

  my ($msg, $err);
  if ($que_ok && $ans_ok) {
    $msg = 'Item question and answer changed.';
  }
  elsif ($que_ko && $ans_ko) {
    $err = 'Item question and answer change failed.';
  }
  else {
    $msg = 'Question changed.'       if $que_ok;
    $msg = 'Answer changed.'         if $ans_ok;
    $err = 'Question change failed.' if $que_ko;
    $err = 'Answer change failed.'   if $ans_ko;
  }

  $c->flash(message => $msg) if $msg;
  $c->flash(error   => $err) if $err;

  $c->redirect_to('author_index');
}

sub add_new_item_to_quiz {
  my $c = shift;
  my $err;

  my $v = $c->validation();
  $v->csrf_protect()
    ->required('quiz_name',    'trim', 'not_empty')
    ->required('quiz_id',      'trim', 'not_empty')
    ->required('new_question', 'trim', 'not_empty')
    ->required('new_answer',   'trim', 'not_empty');
  if ($v->has_error('csrf_token')) {
    $err = 'You can not do that.';
  }
  elsif ($v->has_error()) {
    $err = 'Item creation failed.';
  }
  return $c->flash(error => $err)->redirect_to('author_index') if $err;

  my $quiz_name = $c->param('quiz_name');
  my $quiz_id   = $c->param('quiz_id');
  my $question  = $c->param('new_question');
  my $answer    = $c->param('new_answer');
  my %hres      = $c->prof->create_item($c->session('id'), $question, $answer);

  if (!$hres{status}) {
    $c->flash(error => 'Item creation failed.')->redirect_to('author_index');
  }
  my $item_id = $hres{item_id};

  %hres = $c->prof->add_item_to_quiz($c->session('id'), $quiz_name, $item_id);
  if ($hres{status}) {
    $c->flash(message => 'Item created and added to quiz.');
  }
  else {
    $c->flash(error => 'Item could not be added to quiz.');
  }

  $c->session(selected_quiz => $quiz_id) if $quiz_id;
  $c->redirect_to('author_index');
}

# change the attributes of a Quiz
# the Quiz can be identified either by quiz_id or by quiz_name
# the params to change are: name description instructions visible
sub update_quiz {
  my $c = shift;

  my $quiz_id = $c->param('quiz_id') || '';
  my $log     = $c->log_context("update_quiz '$quiz_id'");
  $log->info("start.");

  my @fields = qw(name description instructions visible);
  my %vals   = ();
  foreach my $field (@fields) {
    $vals{$field} = $c->param($field) if $c->param($field);
  }

  my %hres = $c->prof->update_quiz($c->session('id'), $quiz_id, %vals);
  if ($hres{status}) {
    $c->flash(message => 'Quiz updated.');
  }
  else {
    $log->warn("failed: '$hres{msg}'.");
    $c->flash(error => 'Quiz update failed.');
  }

  $c->session(selected_quiz => $quiz_id) if $quiz_id;
  $log->info("done.");
  $c->redirect_to('author_index');
}

1;
