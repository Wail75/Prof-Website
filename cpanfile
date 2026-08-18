# cpanfile

requires 'Mojolicious', '9.48';

# database
requires 'Mojo::Pg';

# password secure storing
requires 'Crypt::Argon2';
# provides salt for the password secure storing
requires 'Crypt::URandom';

# Internationalization
requires 'Mojolicious::Plugin::I18N';

# Email syntax
requires 'Mail::RFC822::Address';

# Email verification
requires 'Mojo::JWT';

# to avoid error 'IO::Socket::SSL 2.009+ required for TLS support'
requires 'IO::Socket::SSL', '>=2.009';

# for Prof Quiz
requires 'Log::Any';

on "develop" => sub {
    requires 'DateTime';
    requires 'DateTime::Format::ISO8601';
};

on "test" => sub {
    requires 'DateTime';
    requires 'DateTime::Format::ISO8601';
};
