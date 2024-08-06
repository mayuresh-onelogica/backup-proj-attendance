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

-- MAGIC %%sql
-- MAGIC -- checkin data with rank
-- MAGIC SELECT
-- MAGIC         id,
-- MAGIC         employee_id,
-- MAGIC         date as date_original,
-- MAGIC         CAST(SUBSTRING(date, 1, 10) AS DATE) AS date1,
-- MAGIC         checkin_time as checkin_ori,
-- MAGIC         CASE
-- MAGIC             WHEN checkin_time IS NULL THEN '00:00:00'
-- MAGIC             ELSE SUBSTRING(checkin_time, 12, 8)
-- MAGIC         END AS checkin_utc,
-- MAGIC         latitude,
-- MAGIC         longitude,
-- MAGIC         address,
-- MAGIC         dense_rank() over (partition by employee_id,CAST(SUBSTRING(date, 1, 10) AS DATE) order by date, id) as rnkin
-- MAGIC     FROM
-- MAGIC       HRMS_DATA_ATTNDANCE.Tst_attendance
-- MAGIC     WHERE
-- MAGIC         status = 'checked_in'
-- MAGIC             -- and extract(month from date) = 6 
-- MAGIC     order by employee_id;
-- MAGIC         

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

-- MAGIC %%sql
-- MAGIC -- checkout data with rank
-- MAGIC WITH 
-- MAGIC MinCheckinTimes AS (
-- MAGIC     SELECT
-- MAGIC         employee_id,
-- MAGIC         CAST(SUBSTRING(date, 1, 10) AS DATE) AS date,
-- MAGIC         MIN(SUBSTRING(checkin_time, 12, 8)) AS min_checkin_time
-- MAGIC     FROM
-- MAGIC         HRMS_DATA_ATTNDANCE.Tst_attendance
-- MAGIC     WHERE
-- MAGIC         status = 'checked_in'
-- MAGIC     GROUP BY
-- MAGIC         employee_id,
-- MAGIC         CAST(SUBSTRING(date, 1, 10) AS DATE)
-- MAGIC ),
-- MAGIC 
-- MAGIC checkout(
-- MAGIC SELECT
-- MAGIC     a.id,
-- MAGIC     a.employee_id,
-- MAGIC     a.date as date_original,
-- MAGIC     CAST(SUBSTRING(a.date, 1, 10) AS DATE) AS date,
-- MAGIC     a.checkout_time as checkout_ori,
-- MAGIC     CASE
-- MAGIC         WHEN a.checkout_time IS NULL THEN '00:00:00'
-- MAGIC         ELSE SUBSTRING(a.checkout_time, 12, 8)
-- MAGIC     END AS checkout_utc,
-- MAGIC     latitude,
-- MAGIC     longitude,
-- MAGIC     address,
-- MAGIC     DENSE_RANK() OVER (PARTITION BY a.employee_id, CAST(SUBSTRING(a.date, 1, 10) AS DATE) ORDER BY a.date, a.id) AS rnkout
-- MAGIC FROM
-- MAGIC     HRMS_DATA_ATTNDANCE.Tst_attendance a
-- MAGIC LEFT JOIN
-- MAGIC     MinCheckinTimes m
-- MAGIC ON
-- MAGIC     a.employee_id = m.employee_id
-- MAGIC     AND CAST(SUBSTRING(a.date, 1, 10) AS DATE) = m.date
-- MAGIC WHERE
-- MAGIC     --a.checkout_time < m.min_checkin_time and a.status = 'checked_out'
-- MAGIC     m.min_checkin_time < SUBSTRING(a.checkout_time, 12, 8)
-- MAGIC    
-- MAGIC )
-- MAGIC select * from checkout
-- MAGIC --   where extract(month from date) = 6
-- MAGIC order by employee_id , date desc;

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

-- Details Report including Leave
 --CREATE TABLE IF NOT EXISTS iSAM_Details_Report AS(
WITH Checkin AS (
    SELECT
        id,
        employee_id,
        date AS date_original,
        CAST(SUBSTRING(date, 1, 10) AS DATE) AS date1,
        checkin_time AS checkin_ori,
        CASE
            WHEN checkin_time IS NULL THEN '00:00:00'
            ELSE SUBSTRING(checkin_time, 12, 8)
        END AS checkin_utc,
        latitude,
        longitude,
        address,
        DENSE_RANK() OVER (PARTITION BY employee_id, CAST(SUBSTRING(date, 1, 10) AS DATE) ORDER BY date, id) AS rnkin
    FROM
        HRMS_DATA_ATTNDANCE.Tst_attendance
    WHERE
        status = 'checked_in'
),
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
checkout AS (
    SELECT
        a.id,
        a.employee_id,
        a.date AS date_original,
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
        AND CAST(SUBSTRING(a.date, 1, 10) AS DATE) = m.date
    WHERE
        m.min_checkin_time < SUBSTRING(a.checkout_time, 12, 8)
),
Total_Working AS (
    SELECT
        c.employee_id,
        c.date1 AS date,
        c.checkin_utc AS checkin,
        co.checkout_utc AS checkout,
        (
            UNIX_TIMESTAMP(co.date1 || ' ' || co.checkout_utc, 'yyyy-MM-dd HH:mm:ss') -
            UNIX_TIMESTAMP(c.date1 || ' ' || c.checkin_utc, 'yyyy-MM-dd HH:mm:ss')
        ) AS total_working_seconds,
        c.latitude,
        c.longitude,
        c.address
    FROM
        Checkin c
    LEFT JOIN
        checkout co
    ON
        c.employee_id = co.employee_id
        AND c.date1 = co.date1
        AND c.rnkin = co.rnkout
),
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
        row_num = 1
),
chkin_chkout AS (
    SELECT
        COALESCE(t.checkin,0) AS checkin,
        COALESCE(t.checkout,0) AS checkout,
        COALESCE(t.employee_id, el.employee_id) AS employee_id,
        COALESCE(t.date, el.date) AS date,
        CASE
            WHEN el.leave_status = 1 AND t.total_working_seconds IS NULL THEN 0
            ELSE COALESCE(t.total_working_seconds, 0)
        END AS total_working_seconds,
        COALESCE(el.leave_status, 0) AS leave_status,
        latitude,
        longitude,
        address
    FROM
        Total_Working AS t
    FULL JOIN
        expanded_leave AS el ON t.employee_id = el.employee_id AND t.date = el.date
),
employee_details AS (
    SELECT
        id AS employee_id,
        email,
        first_name,
        last_name,
        CONCAT(first_name, ' ', last_name) AS name
    FROM HRMS_DATA_ATTNDANCE.TsT_employee
),
final_formatted AS (
    SELECT DISTINCT
        cc.employee_id,
        e.name,
        e.email,
        cc.date,
        cc.checkin,
        cc.checkout,
        LPAD(FLOOR(cc.total_working_seconds / 3600), 2, '0') || ':' ||
        LPAD(FLOOR((cc.total_working_seconds % 3600) / 60), 2, '0') || ':' ||
        LPAD(cc.total_working_seconds % 60, 2, '0') AS total_working_hours,
        cc.leave_status,
        cc.latitude,
        cc.longitude,
        cc.address
    FROM
        chkin_chkout cc
    LEFT JOIN 
        employee_details AS e ON cc.employee_id = e.employee_id
)
SELECT * 
FROM final_formatted
where extract(month from date) = 7 and employee_id = 1
ORDER BY
    employee_id,
    date DESC 


-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

-- calculate MERGE(checkin & checkout) report and concate
--CREATE TABLE IF NOT EXISTS iSAM_concate (
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
        latitude,
        longitude,
        address,
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
            ), 0) AS total_working_seconds,
        c.latitude,
        c.longitude,
        c.address
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
    sum(total_working_seconds) AS total_working_seconds,
    latitude,
    longitude,
    address
FROM 
    Total_Working
GROUP BY 
    employee_id,
    date,
    latitude,
    longitude,
    address
),
att_formatted AS (
    SELECT 
       employee_id,
        date,
        checkin_checkout_IST,
        LPAD(FLOOR(total_working_seconds / 3600), 2, '0') || ':' ||
        LPAD(FLOOR((total_working_seconds % 3600) / 60), 2, '0') || ':' ||
        LPAD(total_working_seconds % 60, 2, '0') AS total_working_hours,
        latitude,
        longitude,
        address
    FROM 
        concat_formatted
)
select * from 
att_formatted 
where extract(month from date) = 7 and employee_id = 14

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

--Summarize report include leave and detalis
--CREATE TABLE IF NOT EXISTS iSAM_summarize_Report AS(
WITH concate_att AS (
    SELECT * 
    FROM HRMS_DATA_ATTNDANCE.isam_concate
),
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
        row_num = 1
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
        email,
        first_name,
        last_name,
        CONCAT(first_name, ' ', last_name) AS name
    FROM HRMS_DATA_ATTNDANCE.TsT_employee
),
combine AS (
    SELECT
        COALESCE(t.employee_id, el.employee_id) AS employee_id,
        COALESCE(t.date, el.date) AS date,
        COALESCE(t.latitude, '') AS latitude,
        COALESCE(t.longitude,'') AS longitude,
        COALESCE(t.address,'') AS address,
        COALESCE(e.name, '') AS name,
        COALESCE(e.email, '') AS email,
        COALESCE(t.checkin_checkout_IST, 0) AS checkin_checkout_IST,
        COALESCE(t.total_working_hours,0) AS total_working_hours,
        COALESCE(el.leave_status, 0) AS leave_status,
        COALESCE(d.standard_working_hours, 0) AS standard_working_hours,
        COALESCE(d.hours_worked, 0) AS hours_worked,
        COALESCE(d.overtime_hours, 0) AS overtime_hours,
        COALESCE(d.remaining_hours, 0) AS remaining_hours
    FROM concate_att AS t
    FULL JOIN expanded_leave AS el
        ON t.employee_id = el.employee_id AND t.date = el.date
    LEFT JOIN dailyworks AS d
        ON COALESCE(t.employee_id, el.employee_id) = d.employee_id AND COALESCE(t.date, el.date) = d.date
    LEFT JOIN employee_details AS e
        ON COALESCE(t.employee_id, el.employee_id) = e.employee_id
)
SELECT DISTINCT
    employee_id,
    name AS Name,
    email AS Email,
    latitude,
    longitude,
    address,
    date,
    checkin_checkout_IST,
    total_working_hours,
    leave_status,
    standard_working_hours,
    hours_worked,
    overtime_hours,
    remaining_hours
FROM combine
where extract(month from date) = 7 and employee_id = 14
ORDER BY employee_id, date

-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

-- --CREATING DATE TABLE
-- -- Step 1: Create a Common Table Expression (CTE) to filter out weekends
-- CREATE TABLE IF NOT EXISTS working_day AS(
-- WITH WeekdaysOnly AS (
--     SELECT
--         date
--     FROM
--         HRMS_DATA_ATTNDANCE.date_table
--     WHERE
--         IsWeekday = 'Weekday' -- Assuming 'Yes' indicates a weekday
-- ),
-- holiday AS(
--     SELECT 
--     CONCAT(LPAD(day, 2, '0'), '-', LPAD(month, 2, '0'), '-', year) AS holiday_date
--     FROM 
--     HRMS_DATA_ATTNDANCE.Holiday
-- ),
-- -- Step 2: Create another CTE to exclude holidays
--  ExcludeHolidays AS (
--     SELECT
--         WeekdaysOnly.date
--     FROM
--         WeekdaysOnly
--     LEFT JOIN
--         holiday  ON WeekdaysOnly.date = holiday.holiday_date
--     WHERE
--         holiday.holiday_date IS NULL
-- )

-- -- Step 3: Select the final working dates from the CTE
-- SELECT
--     date
-- FROM
--     ExcludeHolidays
-- ORDER BY
--     date
-- );


-- METADATA ********************

-- META {
-- META   "language": "sparksql",
-- META   "language_group": "synapse_pyspark"
-- META }

-- CELL ********************

-- CREATE TABLE IF NOT EXISTS working_day AS(
WITH DateCTE AS (
    SELECT Date,
           IsWeekday
    FROM date_table
),
HolidayCTE AS (
    SELECT 
        make_date(Year, Month, Day) AS holiday_date
    FROM holiday
)

SELECT d.Date
FROM DateCTE d
LEFT JOIN HolidayCTE h ON d.Date = h.holiday_date
WHERE d.IsWeekday = 'Weekday'
  AND h.holiday_date IS NULL
  AND SUBSTRING(d.Date, 4, 2) = '06'
;

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
