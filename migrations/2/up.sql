-- set the time zone to UTC to facilitate comparisons
SET TIME ZONE +0;

-- using BIGINT instead of UUID to have a predictable sequence of ids, used as default rank

CREATE TYPE visibility AS ENUM ('public', 'private');

CREATE TABLE quizs (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(200) NOT NULL,
    -- access to a quiz questions is controlled by the quizs.user_id and quizs.visible
    user_id       UUID NOT NULL,
    description   VARCHAR(1000),
    instructions  VARCHAR(1000),
    visible       visibility DEFAULT 'private',

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE (user_id, name)
);

CREATE TABLE items (
    id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    question VARCHAR(500) NOT NULL,
    answer   VARCHAR(1000) NOT NULL,
    user_id  UUID NOT NULL,

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE (user_id, question, answer)
);

CREATE TABLE quiz_item_links (
    id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quiz_id BIGINT NOT NULL,
    item_id BIGINT NOT NULL,
    rank    INTEGER,
    user_id UUID NOT NULL,

    FOREIGN KEY (quiz_id) REFERENCES quizs(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE (user_id, quiz_id, item_id)
);

CREATE TABLE results (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    creation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    item_id       BIGINT NOT NULL,
    response      VARCHAR(1200),
    grade         INTEGER NOT NULL,
    user_id       UUID NOT NULL,

    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE sessions (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    creation_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    quiz_id       BIGINT NOT NULL,
    -- next_item_id is NULL when the last item has been reached
    next_item_id  BIGINT,
    responses_cnt INTEGER DEFAULT 0 NOT NULL,
    total_grade   INTEGER DEFAULT 0 NOT NULL,
    user_id       UUID NOT NULL,

    FOREIGN KEY (quiz_id) REFERENCES quizs(id) ON DELETE CASCADE,
    -- no need for cascade, but you have to check if the next item is available
    FOREIGN KEY (next_item_id) REFERENCES items(id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
