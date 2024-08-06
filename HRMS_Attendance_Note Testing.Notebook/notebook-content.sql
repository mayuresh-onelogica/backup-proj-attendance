-- Fabric notebook source

-- METADATA ********************

-- META {
-- META   "kernel_info": {
-- META     "name": "synapse_pyspark"
-- META   },
-- META   "dependencies": {
-- META     "lakehouse": {
-- META       "default_lakehouse": "68cb26bc-36f4-42be-8c16-4172a8826b50",
-- META       "default_lakehouse_name": "HRMS_DATA_ATTNDANCE",
-- META       "default_lakehouse_workspace_id": "d1ea8773-0b8d-49c5-b0a0-f03f3cf2035e",
-- META       "known_lakehouses": [
-- META         {
-- META           "id": "68cb26bc-36f4-42be-8c16-4172a8826b50"
-- META         }
-- META       ]
-- META     }
-- META   }
-- META }

-- CELL ********************

-- TESTING

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

-- checkin data with rank
SELECT
        id,
        employee_id,
        date as date_original,
        CAST(SUBSTRING(date, 1, 10) AS DATE) AS date1,
        checkin_time as checkin_ori,
        CASE
            WHEN checkin_time IS NULL THEN '00:00:00'
            ELSE SUBSTRING(checkin_time, 12, 8)
        END AS checkin_utc,
        dense_rank() over (partition by employee_id,CAST(SUBSTRING(date, 1, 10) AS DATE) order by date, id) as rnkin
    FROM
      HRMS_DATA_ATTNDANCE.Tst_attendance
    WHERE
        status = 'checked_in'
        and extract(month from date) = 5 and employee_id = 5
    order by employee_id;

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

-- checkout data with rank
WITH 
MinCheckinTimes AS (
    SELECT
        employee_id,
        CAST(SUBSTRING(date, 1, 10) AS DATE) AS date,
        MIN(SUBSTRING(checkin_time, 12, 8)) AS min_checkin_time
    FROM
        HRMS_DATA_ATTNDANCE.Tst_attendance
    WHERE
        status = 'checked_in'
    GROUP BY
        employee_id,
        CAST(SUBSTRING(date, 1, 10) AS DATE)
),

checkout(
SELECT
    a.id,
    a.employee_id,
    a.date as date_original,
    CAST(SUBSTRING(a.date, 1, 10) AS DATE) AS date,
    a.checkout_time as checkout_ori,
    CASE
        WHEN a.checkout_time IS NULL THEN '00:00:00'
        ELSE SUBSTRING(a.checkout_time, 12, 8)
    END AS checkout_utc,
    DENSE_RANK() OVER (PARTITION BY a.employee_id, CAST(SUBSTRING(a.date, 1, 10) AS DATE) ORDER BY a.date, a.id) AS rnkout
FROM
    HRMS_DATA_ATTNDANCE.Tst_attendance a
LEFT JOIN
    MinCheckinTimes m
ON
    a.employee_id = m.employee_id
    AND CAST(SUBSTRING(a.date, 1, 10) AS DATE) = m.date
WHERE
    --a.checkout_time < m.min_checkin_time and a.status = 'checked_out'
    m.min_checkin_time < SUBSTRING(a.checkout_time, 12, 8)
   
)
select * from checkout
where  extract(month from date) = 5 and employee_id = 5
order by employee_id , date desc;

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************


-- calculate detail report and concate
CREATE TABLE IF NOT EXISTS iSAM_concate (
WITH Checkin AS (
    SELECT
        id,
        employee_id,
        CAST(SUBSTRING(date, 1, 10) AS DATE) AS date1,
        checkin_time AS checkin_ori,
        CASE
            WHEN checkin_time IS NULL THEN '00:00:00'
            ELSE SUBSTRING(checkin_time, 12, 8)
        END AS checkin_utc,
        dense_rank() OVER (PARTITION BY employee_id, CAST(SUBSTRING(date, 1, 10) AS DATE) ORDER BY date, id) AS rnkin
    FROM
        HRMS_DATA_ATTNDANCE.Tst_attendance
    WHERE
        status = 'checked_in'
),
MinCheckinTimes AS (
    SELECT
        employee_id,
        CAST(SUBSTRING(date, 1, 10) AS DATE) AS date1,
        MIN(SUBSTRING(checkin_time, 12, 8)) AS min_checkin_time
    FROM
        HRMS_DATA_ATTNDANCE.Tst_attendance
    WHERE
        status = 'checked_in'
    GROUP BY
        employee_id,
        CAST(SUBSTRING(date, 1, 10) AS DATE)
),
checkout AS (
    SELECT
        a.id,
        a.employee_id,
        CAST(SUBSTRING(a.date, 1, 10) AS DATE) AS date1,
        a.checkout_time AS checkout_ori,
        CASE
            WHEN a.checkout_time IS NULL THEN '00:00:00'
            ELSE SUBSTRING(a.checkout_time, 12, 8)
        END AS checkout_utc,
        DENSE_RANK() OVER (PARTITION BY a.employee_id, CAST(SUBSTRING(a.date, 1, 10) AS DATE) ORDER BY a.date, a.id) AS rnkout
    FROM
        HRMS_DATA_ATTNDANCE.Tst_attendance a
    LEFT JOIN
        MinCheckinTimes m
    ON
        a.employee_id = m.employee_id
        AND CAST(SUBSTRING(a.date, 1, 10) AS DATE) = m.date1
    WHERE
        m.min_checkin_time < SUBSTRING(a.checkout_time, 12, 8)
),
Total_Working AS (
    SELECT
        c.employee_id,
        c.date1 as date,
        substring(from_utc_timestamp(concat_ws(' ', c.date1, c.checkin_utc), 'Asia/Kolkata'), 12, 8) AS checkin_ist,
        COALESCE(substring(from_utc_timestamp(concat_ws(' ', co.date1, co.checkout_utc), 'Asia/Kolkata'), 12, 8), '00:00:00') AS checkout_ist,
        COALESCE(
            (
                UNIX_TIMESTAMP(concat_ws(' ', co.date1, co.checkout_utc), 'yyyy-MM-dd HH:mm:ss') -
                UNIX_TIMESTAMP(concat_ws(' ', c.date1, c.checkin_utc), 'yyyy-MM-dd HH:mm:ss')
            ), 0) AS total_working_seconds
    FROM
        Checkin c
    LEFT JOIN
        checkout co
    ON
        c.employee_id = co.employee_id
        AND c.date1 = co.date1
        AND c.rnkin = co.rnkout
),
concat_formatted AS(
SELECT 
    employee_id,
    date,
    concat_ws(' and ', collect_list(concat_ws('-', checkin_ist, checkout_ist))) AS checkin_checkout_IST,
    sum(total_working_seconds) AS total_working_seconds
FROM 
    Total_Working
GROUP BY 
    employee_id,
    date
),
att_formatted AS (
    SELECT 
       employee_id,
        date,
        checkin_checkout_IST,
        LPAD(FLOOR(total_working_seconds / 3600), 2, '0') || ':' ||
        LPAD(FLOOR((total_working_seconds % 3600) / 60), 2, '0') || ':' ||
        LPAD(total_working_seconds % 60, 2, '0') AS total_working_hours
    FROM 
        concat_formatted
)
select * from 
att_formatted
);
-- where extract(month from date) = 5 and employee_id = 5

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

-- FINAL DETAILS REPORT INCLUDE LEAVE TIMESHEET & EMPLOYEE_DETAILS
WITH concate_att AS (
SELECT * 
FROM HRMS_DATA_ATTNDANCE.isam_concate
),
-- Create the CTE for leave
leave AS (
    SELECT
        employee_id,
        start_date,
        end_date,
        status,
        reason,
        CASE
            WHEN status = 'Approved' AND reason != 'WFH' THEN 1
            ELSE 0
        END AS leave_status
    FROM
        HRMS_DATA_ATTNDANCE.Tst_leave
),
-- Expand leave dates to individual days
expanded_leave AS (
    SELECT
        employee_id,
        date,
        leave_status
    FROM (
        SELECT
            employee_id,
            date,
            leave_status,
            ROW_NUMBER() OVER (PARTITION BY employee_id, date, leave_status ORDER BY employee_id) AS row_num
        FROM
            leave
        LATERAL VIEW EXPLODE(sequence(start_date, end_date, INTERVAL 1 DAY)) AS date
        WHERE
            leave_status = 1
    ) temp
    WHERE
        row_num = 1 -- Select only the first occurrence of each date per employee with leave_status = 1
),
dailyworks AS (
    SELECT
        employee_id,
        date,
        total_working_hours AS standard_working_hours,
        hours_worked,
        overtime_hours,
        remaining_hours
    FROM HRMS_DATA_ATTNDANCE.Tst_dailyworks
),
employee_details AS (
SELECT
    id AS employee_id,
    first_name,
    last_name,
    CONCAT(first_name, ' ', last_name) AS name
FROM HRMS_DATA_ATTNDANCE.TsT_employee
),
combine AS (
    SELECT
        e.name,
        COALESCE(t.checkin_checkout_IST,0) AS checkin_checkout_IST,
        COALESCE(t.employee_id, el.employee_id) AS employee_id,
        COALESCE(t.date, el.date) AS date,
        CASE
            WHEN el.leave_status = 1 THEN 1  -- Directly use el.leave_status when available
            ELSE COALESCE(t.total_working_hours, 0)
        END AS total_working_hours,
        COALESCE(el.leave_status, 0) AS leave_status, -- Use el.leave_status directly
        COALESCE(d.standard_working_hours, 0) AS standard_working_hours,
        COALESCE(d.hours_worked, 0) AS hours_worked,
        COALESCE(d.overtime_hours, 0) AS overtime_hours,
        COALESCE(d.remaining_hours, 0) AS remaining_hours
    FROM concate_att AS t
    FULL JOIN expanded_leave AS el
        ON t.employee_id = el.employee_id AND t.date = el.date
    LEFT JOIN dailyworks AS d
        ON t.employee_id = d.employee_id AND t.date = d.date
    LEFT JOIN employee_details AS e
        ON COALESCE(t.employee_id, el.employee_id) = e.employee_id  -- Adjusted join condition


-- combine AS (
--     SELECT
--         e.name,
--         CASE
--          WHEN t.checkin_checkout_IST IS NULL THEN 0
--          ELSE t.checkin_checkout_IST 
--          END AS checkin_checkout_IST ,
--         COALESCE(t.employee_id, el.employee_id) AS employee_id, -- Include all dates from both tables
--         COALESCE(t.date, el.date) AS date, -- Include all dates from both tables
--         CASE
--             WHEN el.leave_status = 1 AND t.total_working_hours IS NULL THEN 0
--             ELSE COALESCE(t.total_working_hours, 0)
--         END AS total_working_hours, -- Ensure 0 if no working hours recorded and leave status is 1
--         COALESCE(el.leave_status, 0) AS leave_status, -- Include leave status
--         d.standard_working_hours,
--         d.hours_worked,
--         d.overtime_hours,
--         d.remaining_hours
--     FROM concate_att
--          AS t
--     FULL JOIN -- FULL OUTER JOIN to include all dates
--         expanded_leave AS el ON t.employee_id = el.employee_id AND t.date = el.date
--     LEFT JOIN 
--         dailyworks AS d ON t.employee_id = d.employee_id AND t.date = d.date
--     LEFT JOIN 
--         employee_details AS e ON t.employee_id = e.employee_id

)
select 
Distinct
employee_id,
name AS Name,
date,
checkin_checkout_IST,
total_working_hours,
leave_status,
standard_working_hours,
hours_worked,
overtime_hours,
remaining_hours
from combine
where extract(month from date) = 5;

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

SELECT * FROM HRMS_DATA_ATTNDANCE.Tst_attendance
where employee_id = 14 and extract(month from date)= 7


-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

SELECT * FROM HRMS_DATA_ATTNDANCE.Tst_dailyworks
where employee_id = 5 and extract(month from date)=6 


-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************


-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }
