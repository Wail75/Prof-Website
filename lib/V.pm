package V;

# Validation for form fields
# keep it in sync with the Database

# user name
our $V_MIN_NAME = 1;
our $V_MAX_NAME = 100;

# user email
our $V_MIN_EMAIL = 3;
our $V_MAX_EMAIL = 254;

# user password
our $V_MIN_PWD = 8;
our $V_MAX_PWD = 100;

# Profile description
our $V_MAX_PROFILE = 1000;

1;
