package Profweb::Model::Prof;

use v5.14;
use warnings;
use Carp;
use utf8;
use open qw(:encoding(UTF-8) :std);

use Mojo::Base -base;
has 'pg';

use DateTime;
use Log::Any qw($log);
use Unicode::Normalize;

=pod

=encoding UTF-8

=head1 NAME

Quiz - A Quiz engine

=head1 VERSION

Version 0.01-TRIAL

=head1 SYNOPSIS

Most basic interface

  my $quiz = create_quiz('Quiz1', 'question1' => 'answer1', 'question2' => 'answer2');

  my %item = next_question('Quiz1');

  print $item{question} . "\n";

  my %res = respond_question($item{item_id}, 'response');

  print ($res{grade} ? 'Correct answer.' : 'Wrong!');

See statistics on your responses

  get_average_grade();
  get_average_grade(item_id => $item_id);
  get_average_grade(quiz => 'quiz');

See all quizzes

  my @quizzes = get_quizzes();

See all quizzes containing the word 'Lesson'

  my @quizzes = get_quizzes('Lesson');

See all quizzes infos, e.g. visibility, description, instructions

  my @quizzes_infos = get_quizzes_infos();

Rename a Quiz

  rename_quiz($old_name, $new_name);

Delete a Quiz

  delete_quiz($quiz_name);

See all items in a quiz

  my @items = get_items(quiz => 'Name');

See all items

  my @items = get_items();

See all items whose question contains the word 'language'

  my @items = get_item(question => 'language');

See all items whose answer contains the word 'Perl'

  my @items = get_item(answer => 'Perl');

Remove an item from the quiz

  remove_item_from_quiz('Quiz name', $item_id);

Modify an item

  edit_item_question($item_id, 'new question');
  edit_item_answer($item_id, 'new answer');

Delete an item

  delete_item($item_id);

Run a quiz session to be asked all questions

  my $session = session_start_quiz("Quiz1");
  while (my $question =  session_next_question($session)) {
      my $answer = <STDIN>;
      my $item = session_respond_question($answer, $session);
  }
  print session_results($session);

List existing sessions

  get_sessions();

List existing sessions for a quiz

  get_sessions('Quiz name');

Get the session creation time

  session_creation_time($session_id)

Create an item (without association to a quiz)

  my $item_id = create_item('question', 'answer');

Reuse a question in a quiz

  add_item_to_quiz($quiz, $item_id);

Order the items in a quiz

  set_quiz_items_rank($quiz, $first_item_id, $second_item_id, $third_item_id);

Delete results for an item

  delete_item_results()

Reset all results

  delete_all_results()

Clean up old results

  cleanup_old_results();

Clean up old sessions

  cleanup_old_sessions();

=head1 DESCRIPTION

This library allows you to setup a quiz, as a list of questions and answers and then run the quizes.

=head1 INSTALLATION

Use Carton or find the list of modules to install in the file cpanfile.
Install sqlite3.
The default database will be in the file ./dbquiz.sqlite

=head1 CAVEAT

This library is not made for handling a large dataset. If you handle a great number of quizzes, use
subroutines that operate only on a single quiz (which is not expected to be very big).

There is not account system, any call can modify any data. Build your own account system on top if
needed.

This library has not been designed for thread safety.

=cut


my $MAX_GRADE = 100;

# return a formatted error message for DB failures
sub _db_error_str {
  my ($self, $error, $query, @params) = @_;
  return "DB error: '$query' " . join(', ', map { $_ || '' } @params) . " => '$error'";
}

# perform a DB query that should change only a single row, shortcut method for simple actions
# Parameters:
# - query: a string, a DB query
# - binds: an array, bind values
# Returns the number of affected rows or -1 if not sure
sub _db_do_single {
  my ($self, $query, @params) = @_;

  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { return $self->_db_error_str($@, $query, @params) };
  return $res->rv;
}

# Paramters:
# - a hash with keys pg, log and argon2_params()
sub new {
  my ($class, %params) = @_;
  my %obj = ();
  $obj{pg} = $params{pg};

  bless \%obj, $class;
}


# creates a quiz with a name and a hash of questions/answers
sub create_quiz {
  my ($self, $user_id, $name, @q_and_a) = @_;

  my $query_quiz = 'INSERT INTO quizs (user_id, name) VALUES ($1, $2)';
  my $query_qid  = 'SELECT id FROM quizs WHERE user_id = $1 AND name = $2';
  my $query_item = 'INSERT INTO items (user_id, question, answer) VALUES ($1, $2, $3)';
  my $query_iid  = 'SELECT id FROM items WHERE user_id = $1 AND question = $2 AND answer = $3';
  my $query_link = 'INSERT INTO quiz_item_links (user_id, quiz_id, item_id) VALUES ($1, $2, $3)';

  my $cnt = @q_and_a;
  return (status => 0, msg => 'Error: there should be as many answers as questions.') if $cnt % 2;
  $cnt = $cnt / 2;

  my $query  = $query_quiz;
  my @params = ($user_id, $name);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  $query  = $query_qid;
  @params = ($user_id, $name);
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  die 'quiz not found after creation' unless $res->rv > 0;
  my $quiz_id = $res->array->[0];

  for (my $i = 0; $i < $cnt; $i++) {
    my $question = $q_and_a[$i * 2];
    my $answer   = $q_and_a[$i * 2 + 1];
    $query  = $query_item;
    @params = ($user_id, $question, $answer);
    eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

    # $log->debug("Created item id $item_id question '$question' answer '$answer'.");

    $query  = $query_iid;
    @params = ($user_id, $question, $answer);
    eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
    die 'item not found after creation' unless $res->rv > 0;
    my $item_id = $res->array->[0];

    $query  = $query_link;
    @params = ($user_id, $quiz_id, $item_id);
    eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

    # $log->debug("Created link id $link_id for quiz id $quiz_id and item id $item_id.");
  }

  return (status => 1, msg => "Created quiz named '$name'.");
}

# get the next question from a quiz
# If a quiz is private, this method will return the next question only if the user id is the owner
# of the quiz
# Parameters:
# - user_id: may be undef for a public quiz, should match the item owner if the quiz is private
# - quiz_id: the id of the quiz
# returns a hash, if error the hash has only one key 'error' with value an error message
# if success, the hash has one question key, with the text of the question and one item_id key to
# use with the next respond_question method
sub next_question {
  my ($self, $user_id, $quiz_id) = @_;

  # ok with an undef user_id, the method will return the next question if the quiz is public
  # return (status => 0, msg => 'Parameter missing: user_id') unless $user_id;
  return (status => 0, msg => 'Parameter missing: quiz_id') unless $quiz_id;

  # get the first question with the least results
  # we take advantage of the bare colum 'results.item_id' to sort first items that don't have any
  # result (the NULL value in results.item_id makes it sort first)
  my $query = <<"EOS";
SELECT items.id, items.question
FROM items
    JOIN quiz_item_links ON items.id = quiz_item_links.item_id
    JOIN quizs ON quiz_item_links.quiz_id = quizs.id
    LEFT JOIN results ON items.id = results.item_id
WHERE quiz_item_links.quiz_id = \$1 AND (quizs.visible = 'public' OR quizs.user_id = \$2)
GROUP BY items.id, results.item_id, quiz_item_links.rank
-- multiply by 10 so that there is distinction even at a low count of results
-- NULLS FIRST because if no result, the expression value is NULL
ORDER BY (10 * COUNT(*) + 20 * AVG(results.grade) / ${MAX_GRADE}::REAL * COUNT(*)) ASC NULLS FIRST,
    results.item_id ASC NULLS FIRST, quiz_item_links.rank, items.id ASC
LIMIT 1
EOS

  # undef because an empty string would cause an error
  my @params = ($quiz_id, ($user_id || undef));
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 }
    or do { return (status => 0, msg => $self->_db_error_str($@, $query, @params)) };
  if ($res->rv < 1) {
    return (status => 0, msg => "Could not find an item for quiz id '$quiz_id'.");
  }
  my ($item_id, $question) = @{$res->array};
  if (!$item_id) {
    return (status => 0, msg => "Could not find an item for quiz id '$quiz_id'.");
  }

  return (status => 1, item_id => $item_id, question => $question);
}

# compares two strings but before using eq, this subroutine does the following:
# - remove trailing whitespaces, unless the first string finishes by whitespace
# - remove starting whitespaces, unless the first string starts by whitespace
# - applies NFC on both strings
sub basic_answer_compare {
  my ($answer, $response) = @_;
  if ($answer =~ /^\S/) { $answer =~ s/^\s+//; $response =~ s/^\s+// }
  if ($answer =~ /\S$/) { $answer =~ s/\s+$//; $response =~ s/\s+$// }
  return NFC($answer) eq NFC($response);
}

# respond to a question. The user response and the item answer are normalized with NFC and spaces
# before and after are removed from the response if the item answer does not start or finish with
# spaces.
# NOTE the user_id is not used for access to the item. Control access at a higher level if need be.
# Parameters:
# - user_id: may be undef. If present, create a result for that user.
# - item_id: the item for the response
# - response: the text of the response, will be compared to the answer for the item
# returns a hash, if error the hash has only one key 'error' with value an error message
# if success, the hash has one grade key, with a grade, between 0 and $MAX_GRADE
sub respond_question {
  my ($self, $user_id, $item_id, $response) = @_;

  return (status => 0, msg => 'Parameter missing: item_id')  unless $item_id;
  return (status => 0, msg => 'Parameter missing: response') unless $response;

  my $query_answer = 'SELECT answer FROM items WHERE id = $1';
  my $query_result = <<'EOS';
INSERT INTO results (user_id, item_id, response, grade) VALUES ($1, $2, $3, $4)
EOS

  my $query  = $query_answer;
  my @params = ($item_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  return (status => 0, msg => "Item id '$item_id' not found.") unless $res->rv > 0;
  my $answer = $res->array->[0];

  # don't check if $answer is empty, it might be voluntary. Check the database result instead.

  my $grade = basic_answer_compare($answer, $response) ? $MAX_GRADE : 0;

  if ($user_id) {
    $query  = $query_result;
    @params = ($user_id, $item_id, $response, $grade);
    eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
    $log->warn("Failed to save result for item id '$item_id'.") unless $res->rv > 0;
  }

  return (status => 1, grade => $grade);
}

# returns an average score over:
# - without argument (other than self and user_id), all items
# - with an argument item_id, over a particular item
# - with an argument quiz, over items of a quiz
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error message, present only if failure
# - average_prct: an integer, the average grade (over $MAX_GRADE) undef if there are no results
sub get_average_grade {
  my ($self, $user_id, @params) = @_;

  my ($joins, $suppl_where_clauses) = ('', '');
  my ($arg,   $id)                  = ('', '');
  if (@params) {
    if (scalar(@params) != 2) {
      return (status => 0, msg => "get_average_grade argument must be key => val or nothing.");
    }
    ($arg, $id) = @params;
    if ($arg eq 'item_id') {
      $suppl_where_clauses = ' AND results.item_id = $2';
    }
    elsif ($arg eq 'quiz') {
      $joins = <<'EOS';
 JOIN quiz_item_links ON results.item_id = quiz_item_links.item_id
JOIN quizs ON quiz_item_links.quiz_id = quizs.id
EOS
      $suppl_where_clauses = ' AND quizs.name = $2';
    }
    else {
      return (status => 0, msg => "get_average_grade wrong argument: '$arg'.");
    }
  }
  my $query = 'SELECT CEIL(AVG(grade)) FROM results' . $joins . ' WHERE results.user_id = $1' . $suppl_where_clauses;
  @params = ($user_id, ($id ? ($id) : ()));
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  die 'results not found' unless $res->rv > 0;
  my $average = $res->array->[0];

  return (status => 1, average_prct => $average);
}

# get a list of the names of all quizzes
# Argument:
# - word, optional: the names must contain this word
sub get_quizzes {
  my ($self, $user_id, $word) = @_;

  my $query  = 'SELECT name FROM quizs WHERE user_id = $1' . ($word ? ' AND name LIKE $2' : '');
  my @params = ($user_id, ($word ? "%$word%" : ()));
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  return (status => 0, msg => 'get_quizzes Unknown database error.') unless $res;

  return (status => 1, quizzes => [map { $_->[0] } @{$res->arrays->to_array}]);
}

# get a list of hashes, one for each quiz, with all fields (e.g. id, name etc)
# Arguments are key/values:
# - user_id => id, see only quizes owned by this user
# - name => string, see only quizes with this name, use it with user_id
# - id => id, see only the quiz with this id
# - visible => 'public'/'private', see all quiz with this visibility
sub get_quizzes_infos {
  my ($self, @parameters) = @_;
  return (status => 0, msg => 'Parameters not key/value pairs') if @parameters % 2;
  my %pars = @parameters;
  foreach my $key (keys %pars) {
    next if grep { $_ eq $key } qw(user_id id name visible);
    return (status => 0, msg => "Parameter incorrect: $key");
  }

  my $query  = 'SELECT id, name, description, instructions, visible FROM quizs';
  my @params = ();
  if (%pars) {
    my @conditions = map {"$_ = ?"} keys %pars;
    $query .= ' WHERE ' . join(' AND ', @conditions);
    @params = values %pars;
  }
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 }
    or do { return (status => 0, msg => $self->_db_error_str($@, $query, @params)) };

  return (status => 0, msg => 'get_quizzes_infos Unknown database error.') if $res->rv < 0;

  return (status => 1, quizzes => $res->hashes->to_array);
}

# update the attributes of a Quiz
# Arguments:
# - user_id: the id of the user who owns the quiz
# - quiz_id: the id of the quiz to update
# - a list of key/value pairs, representing the fields to update and the new value, the fields must
#       be name, description, instruction or visible
sub update_quiz {
  my ($self, $user_id, $quiz_id, @parameters) = @_;

  my $err = '';
  $err = 'Parameters not key/value pairs' if @parameters % 2;
  $err = 'Parameter missing: quiz_id' unless $quiz_id;
  $err = 'Parameter missing: user_id' unless $user_id;
  return (status => 0, msg => $err) if $err;

  my %pars = @parameters;
  foreach my $key (keys %pars) {
    next if grep { $_ eq $key } qw(name description instructions visible);
    return (status => 0, msg => "Parameter incorrect: $key");
  }
  return (status => 0, 'Nothing to change.') unless %pars;

  my @fields     = map {"$_ = ?"} keys %pars;
  my $set_clause = join(', ', @fields);
  my $query      = "UPDATE quizs SET $set_clause WHERE user_id = ? AND id = ?";
  my @params     = (values %pars, $user_id, $quiz_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if the Quiz id '$quiz_id' has been updated.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "No Quiz id '$quiz_id' found?");
  }
  return (status => 1, msg => "Quiz id '$quiz_id' updated.");
}

# rename a Quiz
# Arguments:
# - old name
# - new name
sub rename_quiz {
  my ($self, $user_id, $old_name, $new_name) = @_;

  my $query  = 'UPDATE quizs SET name = $2 WHERE user_id = $1 AND name = $3';
  my @params = ($user_id, $new_name, $old_name);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if the Quiz '$old_name' has been renamed.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "No Quiz named '$old_name' found?");
  }
  return (status => 1, msg => "Quiz '$old_name' renamed to '$new_name'.");
}

# delete a quiz, does not delete associated objects like items
# Argument:
# -name: the name of the quiz to delete
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
sub delete_quiz {
  my ($self, $user_id, $name) = @_;

  my $query  = 'DELETE FROM quizs WHERE user_id = $1 AND name = $2';
  my @params = ($user_id, $name);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if the Quiz '$name' has been deleted.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "No Quiz named '$name' found?");
  }
  return (status => 1, msg => "Quiz '$name' deleted.");
}

# get a list of items, without argument, all items, or using a filter. If a quiz parameter is given,
# then the items are in order for the quiz (creation order by default or user defined order).
# Argument:
# - quiz: a Quiz name, get items linked to that quiz
# - question: a string, get items whose question contains that string
# - answer: a string, get items whose answer contains that string
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error message, present only if failure
# - items: a list of hashes representing the items. present only if success
#     - id: an integer, the id of the item
#     - question: a string, the question
#     - answer: a string, the answer
#     - rank: undef or an integer, the rank of the item in the quiz (only if quiz parameter)
sub get_items {
  my ($self, $user_id, @params) = @_;

  my ($arg, $word) = ('', '');
  my ($extra_columns, $joins, $suppl_where_clause, $order) = ('', '', '', '');
  if (@params) {
    if (scalar(@params) != 2) {
      return (status => 0, msg => "get_items argument must be key => value or nothing.");
    }
    ($arg, $word) = @params;
    if ($arg eq 'question') {
      $suppl_where_clause = ' AND items.question LIKE $2';
    }
    elsif ($arg eq 'answer') {
      $suppl_where_clause = ' AND items.answer LIKE $2';
    }
    elsif ($arg eq 'quiz') {
      $extra_columns .= ', quiz_item_links.rank';
      $joins = <<'EOS';
 JOIN quiz_item_links ON items.id = quiz_item_links.item_id
JOIN quizs ON quiz_item_links.quiz_id = quizs.id
EOS
      $suppl_where_clause = ' AND  quizs.name = $2';
      $order              = ' ORDER BY quiz_item_links.rank, quizs.id ASC';
    }
    else {
      return (status => 0, msg => "get_items wrong argument: '$arg'.");
    }
  }
  my $query = <<EOS;
SELECT items.id, items.question, items.answer$extra_columns
FROM items$joins
WHERE items.user_id = \$1$suppl_where_clause$order
EOS

  # exceptionnaly using dbh because of the slice argument
  my $dbh = $self->pg->db->dbh;
  my $arr_ref;
  my @common_params = ({Slice => {}}, $user_id);
  if ($arg eq 'quiz') {
    $arr_ref = $dbh->selectall_arrayref($query, @common_params, $word) or die $DBI::errstr;
  }
  elsif (grep { $_ eq $arg } qw(question answer)) {
    $arr_ref = $dbh->selectall_arrayref($query, @common_params, "%$word%") or die $DBI::errstr;
  }
  else {
    $arr_ref = $dbh->selectall_arrayref($query, @common_params) or die $DBI::errstr;
  }
  return (status => 0, msg => 'get_items Database error: ' . $dbh->err) if $dbh->err;

  return (status => 1, items => $arr_ref);
}

# remove an item for a quiz
# Parameters:
# - quiz: a string, the name of the quiz
# - item_id: an integer, the id of the item to add
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
sub remove_item_from_quiz {
  my ($self, $user_id, $quiz, $item_id) = @_;

  my $query = <<'EOS';
DELETE FROM quiz_item_links
WHERE user_id = $1 AND quiz_item_links.id IN (
    SELECT quiz_item_links.id
    FROM quiz_item_links
    JOIN quizs ON quiz_item_links.quiz_id = quizs.id
    WHERE quizs.user_id = $1 AND quizs.name = $2 AND quiz_item_links.id = $3
)
EOS
  my @params = ($user_id, $quiz, $item_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if item id '$item_id' has been removed from Quiz '$quiz'.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "Failed to remove item id '$item_id' from Quiz '$quiz'.");
  }
  return (status => 1, msg => "Removed item id '$item_id' from Quiz '$quiz'.");
}

# private method, edit an item
sub _edit_item {
  my ($self, $user_id, $item_id, %args) = @_;

  my @defined_keys = grep { defined $args{$_} } qw(question answer);
  my $set_clauses  = join(', ', map {"$_ = ?"} @defined_keys);
  my $query        = "UPDATE items SET $set_clauses WHERE user_id = ? AND id = ?";
  my @binds        = map { $args{$_} } @defined_keys;

  my @params = (@binds, $user_id, $item_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if item id '$item_id' has been edited.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "Failed to edit item id '$item_id'.");
  }
  return (status => 1, msg => "Edited item id '$item_id'.");
}

# edit the question of an item
# Parameters:
# - item_id: an integer, the id of the item to edit
# - new_question: a string, the new value for the question
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
sub edit_item_question {
  my ($self, $user_id, $item_id, $new_question) = @_;
  return $self->_edit_item($user_id, $item_id, question => $new_question);
}

# edit the answer of an item
# Parameters:
# - item_id: an integer, the id of the item to edit
# - new_answer: a string, the new value for the answer
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
sub edit_item_answer {
  my ($self, $user_id, $item_id, $new_answer) = @_;
  return $self->_edit_item($user_id, $item_id, answer => $new_answer);
}

# delete an item
# Parameter:
# - item_id: an integer, the id of the item to delete
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
sub delete_item {
  my ($self, $user_id, $item_id) = @_;

  my $query  = 'DELETE FROM items WHERE user_id = $1 AND items.id = $2';
  my @params = ($user_id, $item_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if the item id '$item_id' has been deleted.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "No item id '$item_id' found?");
  }
  return (status => 1, msg => "Item id '$item_id' deleted.");
}

# create a quiz item (without automatically associating it to a quiz)
# Parameters:
# - question: a string, the question
# - answer: a string, the answer
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - item_id: an integer, the id of the item if success
sub create_item {
  my ($self, $user_id, $question, $answer) = @_;

  my $query  = 'INSERT INTO items (user_id, question, answer) VALUES ($1, $2, $3)';
  my @params = ($user_id, $question, $answer);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv > 1) {
    $log->warn("More than one row affected by create_item ('$query', " . join(' ', @params) . ")");
  }

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if item for question '$question' has been created.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "Failed to create item for question '$question'.");
  }

  $query  = 'SELECT id FROM items WHERE user_id = $1 AND question = $2 AND answer = $3';
  @params = ($user_id, $question, $answer);
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  die 'item not found after creation' unless $res->rv > 0;
  my $item_id = $res->array->[0];

  # $log->debug("Created item id $item_id for question '$question'.");

  return (status => 1, item_id => $item_id);
}

# add an item to a quiz
# Parameters:
# - quiz: a string, a quiz name
# - item_id: an integer, an item id
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
sub add_item_to_quiz {
  my ($self, $user_id, $quiz, $item_id) = @_;

  my $query = <<'EOS';
INSERT INTO quiz_item_links (user_id, quiz_id, item_id)
    SELECT quizs.user_id, quizs.id, $3
    FROM quizs
    WHERE quizs.user_id = $1 AND quizs.name = $2
EOS
  my @params = ($user_id, $quiz, $item_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if the item id '$item_id' added to quiz '$quiz'.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "Failed to add item id '$item_id' added to quiz '$quiz'.");
  }

  return (status => 1, msg => "Item id '$item_id' added to quiz '$quiz'.");
}

# define an order for the items in a quiz
# Parameters:
# - quiz: a string, a quiz name
# - first_item_id ..., a list of integer, the item ids in the desired order
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
sub set_quiz_items_rank {
  my ($self, $user_id, $quiz, @item_ids) = @_;

  my $query = <<'EOS';
UPDATE quiz_item_links
SET rank = $4
FROM (
    SELECT quiz_item_links.id
    FROM quiz_item_links JOIN quizs ON quizs.id = quiz_item_links.quiz_id
    WHERE quizs.user_id = $1 AND quizs.name = $2 AND quiz_item_links.item_id = $3
) AS qil
WHERE quiz_item_links.user_id = $1 AND quiz_item_links.id = qil.id
EOS

  my $sth = $self->pg->db->dbh->prepare($query) or die $DBI::errstr;

  my $i = 1;
  foreach my $item_id (@item_ids) {
    my @binds = ($user_id, $quiz, $item_id, $i + 1);
    my $rows  = $sth->execute(@binds);
    die $DBI::errstr unless defined $rows;

    if ($rows > 1) {
      $log->warn("More than one row affected by set rank '$query', " . join(' ', @binds) . ").");
    }

    if ($rows == -1) {
      return (status => 0, msg => "Not sure if set rank for quiz '$quiz' has been done.");
    }
    elsif ($rows == 0) {
      return (status => 0, msg => "Failed to set rank for quiz '$quiz'.");
    }
    $i++;
  }

  return (status => 1, msg => "Items reordered in quiz '$quiz'.");
}

# deletes all results for an item
# Parameter:
# - item_id: an integer, the id of an item for which to delete results
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
sub delete_item_results {
  my ($self, $user_id, $item_id) = @_;

  my $query  = 'DELETE FROM results WHERE user_id = $1 AND item_id = $2';
  my @params = ($user_id, $item_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if the results for item id '$item_id' were deleted.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "Failed to delete results for item id '$item_id'.");
  }

  return (status => 1, msg => "Results deleted for item id '$item_id'.");
}

# deletes all results
# Parameter:
# None
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - deletion_cnt: number of deletions done, if any
sub delete_all_results {
  my ($self, $user_id) = @_;

  my $query  = 'DELETE FROM results WHERE user_id = $1';
  my @params = ($user_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  return (status => 0, msg => "Not sure if all results were deleted.") if $res->rv == -1;

  return (status => 1, deletions_cnt => ($res->rv > 0 ? $res->rv : 0));
}

# private subroutine, delete all results created at or before the parameter date and any result
# except the keep_cnt parameter last results
# Returns the number of results cleaned up or -1 if unknown
sub _cleanup_results_for {
  my ($self, $keep_cnt, $keep_days) = @_;

  my $query = <<'EOS';
DELETE FROM results
WHERE id NOT IN (
    SELECT r.id
    FROM results AS r
    WHERE r.item_id = results.item_id
    ORDER BY r.creation_time DESC
    LIMIT $1
)
OR creation_time::DATE <= CURRENT_DATE - make_interval(days => $2)
EOS
  my @params = ($keep_cnt, $keep_days);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  return $res->rv;
}

my $RESULTS_KEEP_CNT = 5;
sub set_results_keep_cnt { $RESULTS_KEEP_CNT = shift if @_; }

my $RESULTS_KEEP_DAYS = 60;
sub set_results_keep_days { $RESULTS_KEEP_DAYS = shift if @_; }

# clean up old results, that is any result beyond the last 10 results for an item and any result more
# than 60 days old
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - deletions_cnt: the number of results cleaned up, might be 0
sub cleanup_old_results {
  my $self          = shift;
  my $deletions_cnt = $self->_cleanup_results_for($RESULTS_KEEP_CNT, $RESULTS_KEEP_DAYS);

  return (status => 0, msg => "Not sure if old results were cleaned up.") if $deletions_cnt == -1;

  return (status => 1, deletions_cnt => ($deletions_cnt > 0 ? $deletions_cnt : 0));
}

# start a quiz session, questions are ordered as defined by the user or, by default, by id in
# database
# Parameter:
# - quiz: a string, the name of the quiz
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - session_id: an integer, a session id to reuse later
sub session_start_quiz {
  my ($self, $user_id, $name) = @_;

  my $query = <<'EOS';
INSERT INTO sessions (user_id, quiz_id, next_item_id)
    -- start the session at the first quiz in id order
    SELECT quizs.user_id, quizs.id, items.id
    FROM items
        JOIN quiz_item_links ON quiz_item_links.item_id = items.id
        JOIN quizs ON quiz_item_links.quiz_id = quizs.id
    WHERE quizs.user_id = $1 AND quizs.name = $2
    ORDER BY quiz_item_links.rank, items.id ASC
    LIMIT 1
EOS
  my @params = ($user_id, $name);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if the session for Quiz '$name' has been started.");
  }
  elsif ($res->rv < 1) {
    return (status => 0, msg => "Session for Quiz '$name' not started.");
  }

  $query = <<'EOS';
SELECT sessions.id
FROM sessions JOIN quizs ON sessions.quiz_id = quizs.id
WHERE sessions.user_id = $1 AND quizs.name = $2
EOS
  @params = ($user_id, $name);
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  die 'session not found after creation' unless $res->rv > 0;
  my $session_id = $res->array->[0];

  return (status => 1, session_id => $session_id, msg => "Session for quiz '$name' started.");
}

# get the next question to answer in the session
# Parameter:
# - session_id: an integer, the session id
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - question: a string, the text of the question
# - item_id: an integer, an item_id to reuse later to respond to the question
sub session_next_question {
  my ($self, $user_id, $session_id) = @_;

  my $query = <<'EOS';
SELECT items.id, items.question
FROM items JOIN sessions ON sessions.next_item_id = items.id
WHERE sessions.user_id = $1 AND sessions.id = $2
EOS
  my @params = ($user_id, $session_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv == 0) {
    return (status => 0, msg => "No more question for session id '$session_id'");
  }

  my $items_ref = $res->array;
  die 'item not found after creation' unless $items_ref;
  my $item_id  = $items_ref->[0];
  my $question = $items_ref->[1];

  return (status => 1, question => $question, item_id => $item_id);
}

# answer the next question in the session
# Parameters:
# - session_id: an integer, the session id
# - response: a string, the response to the previous question from session_next_question()
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - grade: an integer between 0 and $MAX_GRADE, $MAX_GRADE if the response is the expected answer,
#       0 otherwise
sub session_respond_question {
  my ($self, $user_id, $session_id, $response) = @_;

  # use the user_id to keep some access control
  my $query_answer = <<'EOS';
SELECT items.answer, sessions.next_item_id, sessions.quiz_id
FROM items JOIN sessions ON sessions.next_item_id = items.id
WHERE sessions.user_id = $1 AND sessions.id = $2
EOS
  my $query_result = <<'EOS';
INSERT INTO results (user_id, item_id, response, grade) VALUES ($1, $2, $3, $4)
EOS
  my $query_next = <<'EOS';
SELECT item_id
FROM quiz_item_links
WHERE quiz_id = $1 AND item_id > $2
ORDER BY rank, item_id ASC
LIMIT 1
EOS
  my $query_session = <<'EOS';
UPDATE sessions
SET total_grade = total_grade + $3, responses_cnt = responses_cnt + 1, next_item_id = $4
WHERE user_id = $1 AND id = $2
EOS

  my $query  = $query_answer;
  my @params = ($user_id, $session_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  if ($res->rv < 1) {
    return (status => 0, msg => "Could not find the answer for session id '$session_id'.");
  }
  my ($answer, $item_id, $quiz_id) = @{$res->array};

  if (!$answer) {
    return (status => 0, msg => "Could not find the answer for session id '$session_id'.");
  }
  my $grade = $answer eq $response ? $MAX_GRADE : 0;

  $query  = $query_result;
  @params = ($user_id, $item_id, $response, $grade);
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  $log->warn("Failed to save result for item id '$item_id'.") unless $res->rv > 0;

  $query  = $query_next;
  @params = ($quiz_id, $item_id);
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  my $next_item_id = $res->rv > 0 ? $res->array->[0] : undef;

  $query  = $query_session;
  @params = ($user_id, $session_id, $grade, $next_item_id);
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };
  $log->warn("Failed to update the session id '$session_id' after response.") unless $res->rv > 0;
  if ($res->rv == -1) {
    return (status => 0, msg => "Not sure if response registered in session id '$session_id'.");
  }
  elsif ($res->rv == 0) {
    return (status => 0, msg => "Response not registered in session id '$session_id'.");
  }

  return (status => 1, grade => $grade);
}

# get the results of the session
# Parameter:
# - session_id, integer, the session id
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - average_prct: the average grade over the responses for this session
# - responses_cnt: the number of responses registered for this session
sub session_results {
  my ($self, $user_id, $session_id) = @_;

  # use the user_id to keep some access control
  my $query  = 'SELECT responses_cnt, total_grade FROM sessions WHERE user_id = $1 AND id = $2';
  my @params = ($user_id, $session_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  if ($res->rv < 1) {
    return (status => 0, msg => "Failed to get session results for session id '$session_id'");
  }

  my ($responses_cnt, $total_grade) = @{$res->array};
  my $average = sprintf("%.0f", $total_grade / $responses_cnt);
  return (status => 1, average_prct => $average,);
}

# SQLite does not really produce an ISO8601 compliant date time
sub _correct_datetime {
  return shift =~ s/ /T/r;
}

# return the creation time (UTC) of the session
# Parameter:
# - session_id: an integer, the id of the session
# Returns a hash:
# - status: 0 if failure, 1 if success
# - creation_time: a string, the creation time (UTC) in ISO8601
sub session_creation_time {
  my ($self, $user_id, $session_id) = @_;

  # use the user_id to keep some access control
  my $query  = 'SELECT creation_time FROM sessions WHERE user_id = $1 AND id = $2';
  my @params = ($user_id, $session_id);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  return (status => 0, msg => "No session for session id $session_id") unless $res->rv > 0;
  my $creation_time = $res->array->[0];

  $creation_time = _correct_datetime($creation_time);
  return (status => 1, creation_time => $creation_time);
}

# return all existing sessions
# Parameter:
# - name: optional, a string, get the sessions associated to this Quiz
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - sessions, a hash:
#   - session_id: an integer, the session id
#   - creation_time: a string, the creation time (UTC) in ISO 8601
#   - quiz_name: a string, the name of the associated quiz
#   - responses_cnt: an integer, the number of responses already made
#   - total_grade: an integer, the total of the grades for the responses
sub get_sessions {
  my ($self, $user_id, $name) = @_;

  my $query = <<'EOS';
SELECT sessions.id AS session_id, creation_time, quizs.name AS quiz_name, responses_cnt, total_grade
FROM sessions JOIN quizs ON quizs.id = sessions.quiz_id
WHERE sessions.user_id = $1
EOS
  $query .= ' AND quizs.name = $2' if $name;

  # exceptionnaly using dbh because of the slice argument
  my $dbh = $self->pg->db->dbh;
  my $arr_ref;
  if ($name) {
    $arr_ref = $dbh->selectall_arrayref($query, {Slice => {}}, $user_id, $name) or die $DBI::errstr;
  }
  else {
    $arr_ref = $dbh->selectall_arrayref($query, {Slice => {}}, $user_id) or die $DBI::errstr;
  }
  return (status => 0, msg => 'get_items Database error: ' . $dbh->err) if $dbh->err;

  my @sessions = @$arr_ref;
  $_->{creation_time} = _correct_datetime($_->{creation_time}) foreach @sessions;
  return (status => 1, sessions => \@sessions);
}

# private subroutine, delete all sessions created at or before the parameter date and any session
# except the keep_cnt parameter last sessions
# Returns the number of sessions cleaned up or -1 if unknown
sub _cleanup_sessions_for {
  my ($self, $keep_cnt, $keep_days) = @_;

  my $query = <<'EOS';
DELETE FROM sessions
WHERE id NOT IN (
    SELECT s.id
    FROM sessions AS s
    WHERE s.quiz_id = sessions.quiz_id
    ORDER BY s.creation_time DESC
    LIMIT $1
)
OR creation_time::DATE <= CURRENT_DATE - make_interval(days => $2)
EOS

  my @params = ($keep_cnt, $keep_days);
  my $res;
  eval { $res = $self->pg->db->query($query, @params); 1 } or do { die $self->_db_error_str($@, $query, @params) };

  return $res->rv;
}

my $SESSIONS_KEEP_CNT = 1;
sub set_sessions_keep_cnt { $SESSIONS_KEEP_CNT = shift if @_; }

my $SESSIONS_KEEP_DAYS = 10;
sub set_sessions_keep_days { $SESSIONS_KEEP_DAYS = shift if @_; }

# clean up old sessions, that is any session beyond the last session for a quiz or amy session older
# than 10 days old
# Returns a hash:
# - status: 0 if failure, 1 if success
# - msg: an error/info message
# - deletions_cnt: the number of sessions cleaned up, might be 0
sub cleanup_old_sessions {
  my $self          = shift;
  my $deletions_cnt = $self->_cleanup_sessions_for($SESSIONS_KEEP_CNT, $SESSIONS_KEEP_DAYS);

  return (status => 0, msg => "Not sure if old sessions were cleaned up.") if $deletions_cnt == -1;

  return (status => 1, deletions_cnt => ($deletions_cnt > 0 ? $deletions_cnt : 0));
}


1;
