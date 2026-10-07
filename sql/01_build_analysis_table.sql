/*
Build the analysis table used in the original university project.

This public copy keeps the original SQL logic and table structure. I only cleaned
formatting, added statement terminators where needed, and removed source-specific
identifiers / expected output values from the diagnostic comments.
*/

/* 1. Create unique_sessions and define the implied conversion variable from events */
DROP TABLE IF EXISTS unique_sessions;

CREATE TEMP TABLE unique_sessions AS
SELECT
    internet_session_id,
    customer_id,
    session_duration,
    MODE() WITHIN GROUP (
        ORDER BY device_category_desc, session_duration DESC
    ) AS device_used,
    action_type_desc,
    MAX(CASE WHEN action_type_desc = 'purchase' THEN 1 ELSE 0 END) AS conversion,
    DATE_TRUNC('day', internet_session_dtime) AS session_date
FROM events
GROUP BY
    internet_session_id,
    customer_id,
    session_duration,
    action_type_desc,
    internet_session_dtime;

/* Check the number of distinct sessions */
SELECT COUNT(DISTINCT internet_session_id)
FROM unique_sessions;


/* 2. Join unique_sessions with customer information */
DROP TABLE IF EXISTS final_table;

CREATE TEMP TABLE final_table AS
SELECT
    us.internet_session_id,
    us.customer_id,
    us.session_duration,
    us.device_used,
    us.conversion,
    us.action_type_desc,
    us.session_date,

    CASE
        WHEN EXTRACT(MONTH FROM us.session_date) IN (3, 4, 5) THEN 1
        WHEN EXTRACT(MONTH FROM us.session_date) IN (6, 7, 8) THEN 2
        WHEN EXTRACT(MONTH FROM us.session_date) IN (9, 10, 11) THEN 3
        ELSE 4
    END AS season,

    c.gender_code,
    c.geom_urbanisation,
    c.geom_household_age,
    c.geom_household_income
FROM unique_sessions us
LEFT JOIN customers c
    ON us.customer_id = c.customer_id;

/* Check row and session counts after the join */
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT internet_session_id) AS sessions
FROM final_table;

/* Check conversion totals overall and by year */
SELECT
    SUM(conversion) AS sum_conversion,
    COUNT(DISTINCT internet_session_id) AS n_sessions,
    CAST(
        100.0 * SUM(conversion) / COUNT(DISTINCT internet_session_id)
        AS DEC(5, 2)
    ) AS cr_overall,

    SUM(
        CASE WHEN EXTRACT(YEAR FROM session_date) = 2021 THEN conversion ELSE 0 END
    ) AS sum_conversion_2021,
    COUNT(
        DISTINCT CASE
            WHEN EXTRACT(YEAR FROM session_date) = 2021 THEN internet_session_id
        END
    ) AS n_sessions_2021,
    CAST(
        100.0 * SUM(
            CASE WHEN EXTRACT(YEAR FROM session_date) = 2021 THEN conversion ELSE 0 END
        ) / NULLIF(
            COUNT(
                DISTINCT CASE
                    WHEN EXTRACT(YEAR FROM session_date) = 2021 THEN internet_session_id
                END
            ),
            0
        )
        AS DEC(5, 2)
    ) AS cr_2021,

    SUM(
        CASE WHEN EXTRACT(YEAR FROM session_date) = 2022 THEN conversion ELSE 0 END
    ) AS sum_conversion_2022,
    COUNT(
        DISTINCT CASE
            WHEN EXTRACT(YEAR FROM session_date) = 2022 THEN internet_session_id
        END
    ) AS n_sessions_2022,
    CAST(
        100.0 * SUM(
            CASE WHEN EXTRACT(YEAR FROM session_date) = 2022 THEN conversion ELSE 0 END
        ) / NULLIF(
            COUNT(
                DISTINCT CASE
                    WHEN EXTRACT(YEAR FROM session_date) = 2022 THEN internet_session_id
                END
            ),
            0
        )
        AS DEC(5, 2)
    ) AS cr_2022
FROM final_table;


/*
During the project we found sessions linked to more than one customer ID. In many
cases one record contained customer information while another contained missing
values. The next steps reproduce the original process used to inspect and resolve
that issue.
*/

/* 3. Find sessions with more than one customer ID */
DROP TABLE IF EXISTS sessions;

CREATE TEMP TABLE sessions AS
SELECT
    internet_session_id,
    COUNT(internet_session_id) AS rows_in_session
FROM final_table
GROUP BY internet_session_id
HAVING COUNT(DISTINCT customer_id) > 1;

SELECT COUNT(*) AS number_rows
FROM sessions;

/* Inspect affected sessions */
SELECT
    internet_session_id,
    customer_id,
    geom_household_income,
    geom_urbanisation,
    geom_household_age
FROM final_table
WHERE internet_session_id IN (
    SELECT internet_session_id
    FROM final_table
    GROUP BY internet_session_id
    HAVING COUNT(DISTINCT customer_id) > 1
)
ORDER BY internet_session_id
LIMIT 10000;


/* 4. First attempt: fill missing customer information within a session */
DROP TABLE IF EXISTS final_table_fixed;

CREATE TEMP TABLE final_table_fixed AS
SELECT
    internet_session_id,

    COALESCE(
        NULLIF(customer_id, ''),
        FIRST_VALUE(customer_id) OVER (
            PARTITION BY internet_session_id
            ORDER BY
                geom_household_income DESC NULLS LAST,
                geom_household_age DESC NULLS LAST,
                gender_code DESC NULLS LAST
        )
    ) AS customer_id_fixed,

    COALESCE(
        geom_household_income,
        FIRST_VALUE(geom_household_income) OVER (
            PARTITION BY internet_session_id
            ORDER BY geom_household_income DESC NULLS LAST
        )
    ) AS geom_household_income,

    COALESCE(
        geom_household_age,
        FIRST_VALUE(geom_household_age) OVER (
            PARTITION BY internet_session_id
            ORDER BY geom_household_age DESC NULLS LAST
        )
    ) AS geom_household_age,

    COALESCE(
        gender_code,
        FIRST_VALUE(gender_code) OVER (
            PARTITION BY internet_session_id
            ORDER BY gender_code DESC NULLS LAST
        )
    ) AS gender_code,

    COALESCE(
        geom_urbanisation,
        FIRST_VALUE(geom_urbanisation) OVER (
            PARTITION BY internet_session_id
            ORDER BY geom_urbanisation DESC NULLS LAST
        )
    ) AS geom_urbanisation,

    session_duration,
    device_used,
    conversion,
    session_date,
    season
FROM final_table;

/* Check whether multiple customer IDs still remain */
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT internet_session_id) AS sessions
FROM final_table_fixed;

DROP TABLE IF EXISTS customers_fixed;

CREATE TEMP TABLE customers_fixed AS
SELECT
    internet_session_id,
    COUNT(DISTINCT customer_id_fixed) AS unique_customers
FROM final_table_fixed
GROUP BY internet_session_id
HAVING COUNT(DISTINCT customer_id_fixed) > 1;

SELECT *
FROM customers_fixed
LIMIT 1000;


/* 5. Final table: rank customer IDs and keep the most complete customer information */
DROP TABLE IF EXISTS final_table_fixed2;

CREATE TEMP TABLE final_table_fixed2 AS
WITH ranked_customers AS (
    SELECT
        internet_session_id,
        customer_id,

        RANK() OVER (
            PARTITION BY internet_session_id
            ORDER BY
                geom_household_income DESC NULLS LAST,
                geom_household_age DESC NULLS LAST,
                gender_code DESC NULLS LAST
        ) AS rank,

        session_date,
        geom_household_income,
        geom_household_age,
        gender_code,
        geom_urbanisation,
        session_duration,
        device_used,
        conversion,
        season
    FROM final_table
)
SELECT
    rc.internet_session_id,

    FIRST_VALUE(customer_id) OVER (
        PARTITION BY internet_session_id
        ORDER BY rank
    ) AS customer_id,

    FIRST_VALUE(geom_household_income) OVER (
        PARTITION BY internet_session_id
        ORDER BY rank
    ) AS geom_household_income,

    FIRST_VALUE(geom_household_age) OVER (
        PARTITION BY internet_session_id
        ORDER BY rank
    ) AS geom_household_age,

    FIRST_VALUE(gender_code) OVER (
        PARTITION BY internet_session_id
        ORDER BY rank
    ) AS gender_code,

    FIRST_VALUE(geom_urbanisation) OVER (
        PARTITION BY internet_session_id
        ORDER BY rank
    ) AS geom_urbanisation,

    session_duration,
    device_used,
    conversion,
    session_date,
    season
FROM ranked_customers rc;

/* Confirm that no session is associated with more than one selected customer ID */
SELECT
    internet_session_id,
    customer_id,
    geom_household_income,
    geom_urbanisation,
    geom_household_age
FROM final_table_fixed2
WHERE internet_session_id IN (
    SELECT internet_session_id
    FROM final_table_fixed2
    GROUP BY internet_session_id
    HAVING COUNT(DISTINCT customer_id) > 1
)
ORDER BY internet_session_id
LIMIT 10000;

/* Final row/session count */
SELECT
    COUNT(*) AS rows,
    COUNT(DISTINCT internet_session_id) AS sessions
FROM final_table_fixed2;

/* Final conversion check */
SELECT
    SUM(conversion) AS sum_conversion,
    COUNT(DISTINCT internet_session_id) AS n_sessions,
    CAST(
        100.0 * SUM(conversion) / COUNT(DISTINCT internet_session_id)
        AS DEC(5, 2)
    ) AS cr_overall,

    SUM(
        CASE WHEN EXTRACT(YEAR FROM session_date) = 2021 THEN conversion ELSE 0 END
    ) AS sum_conversion_2021,
    COUNT(
        DISTINCT CASE
            WHEN EXTRACT(YEAR FROM session_date) = 2021 THEN internet_session_id
        END
    ) AS n_sessions_2021,
    CAST(
        100.0 * SUM(
            CASE WHEN EXTRACT(YEAR FROM session_date) = 2021 THEN conversion ELSE 0 END
        ) / NULLIF(
            COUNT(
                DISTINCT CASE
                    WHEN EXTRACT(YEAR FROM session_date) = 2021 THEN internet_session_id
                END
            ),
            0
        )
        AS DEC(5, 2)
    ) AS cr_2021,

    SUM(
        CASE WHEN EXTRACT(YEAR FROM session_date) = 2022 THEN conversion ELSE 0 END
    ) AS sum_conversion_2022,
    COUNT(
        DISTINCT CASE
            WHEN EXTRACT(YEAR FROM session_date) = 2022 THEN internet_session_id
        END
    ) AS n_sessions_2022,
    CAST(
        100.0 * SUM(
            CASE WHEN EXTRACT(YEAR FROM session_date) = 2022 THEN conversion ELSE 0 END
        ) / NULLIF(
            COUNT(
                DISTINCT CASE
                    WHEN EXTRACT(YEAR FROM session_date) = 2022 THEN internet_session_id
                END
            ),
            0
        )
        AS DEC(5, 2)
    ) AS cr_2022
FROM final_table_fixed2;

/* Export this table for the R analysis */
SELECT *
FROM final_table_fixed2;
