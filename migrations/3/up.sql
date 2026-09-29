CREATE MATERIALIZED VIEW stats_items AS
    -- fortunately, if there are no results, the average_grade is NULL (no 'divide by 0' crash)
    SELECT items.user_id AS user_id, items.id AS item_id, round(AVG(results.grade)) AS average_grade
    FROM items
        LEFT JOIN results ON items.id = results.item_id
    GROUP BY items.user_id, items.id
;

CREATE MATERIALIZED VIEW stats_quizs AS
    -- fortunately, if there are no results, the average_grade is NULL (no 'divide by 0' crash)
    SELECT quizs.user_id AS user_id, quizs.id AS quiz_id, round(AVG(results.grade)) AS average_grade
    FROM quizs
        LEFT JOIN quiz_item_links ON quizs.id = quiz_item_links.quiz_id
        JOIN results ON quiz_item_links.item_id = results.item_id
    GROUP BY quizs.user_id, quizs.id
;
