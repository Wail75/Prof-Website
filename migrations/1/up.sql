-- set the time zone to UTC to facilitate comparisons
SET TIME ZONE +0;

CREATE TABLE users (

    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(200) UNIQUE,
    email        VARCHAR(300) UNIQUE,
    -- passwords are not stored in clear-text but in a secure form (Argon2id)
    secpwd       VARCHAR(200) NOT NULL,
    -- 1 email unverified, 2 email verified
    status       INTEGER DEFAULT '1',
    -- synchronize the character limit with the Perl code (Blank::Model::Account)
    description  VARCHAR(1000),
    -- a code for the user subscription status: 1 unsubscribed user
    subscription INTEGER DEFAULT '1',

    created_at  TIMESTAMP NOT NULL DEFAULT now(),
    archived_at TIMESTAMP,

    CHECK (name IS NOT NULL OR email IS NOT NULL)
);

CREATE TABLE accounts (

    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL,
    name        VARCHAR(200) NOT NULL,
    bckg_color  VARCHAR(6),

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE user_payments (

    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID,
    -- in cents
    amount      INTEGER,
    received_at TIMESTAMP,
    -- you may use the ISO 4217 three letters curency codes
    currency    VARCHAR(10),

    FOREIGN KEY (user_id) REFERENCES users(id)
);
