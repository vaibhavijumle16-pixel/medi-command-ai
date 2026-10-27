-- =====================================================================
-- 06_queries.sql  -  example queries to demonstrate in the viva
-- Every block can be run on its own. Blocks that change data are wrapped
-- in BEGIN ... ROLLBACK so the demo data is left untouched.
-- If you demo on a different day, run  CALL seed_todays_shifts();  first.
-- =====================================================================

-- Q1  INNER JOIN (6 tables): who is admitted, in which ward / room / bed, under which doctor
SELECT  p.full_name  AS patient,
        w.name       AS ward,
        r.room_number,
        b.bed_number,
        s.full_name  AS doctor,
        a.diagnosis,
        a.severity
FROM    admissions a
JOIN    patients   p ON p.patient_id = a.patient_id
JOIN    beds       b ON b.bed_id     = a.bed_id
JOIN    rooms      r ON r.room_id    = b.room_id
JOIN    wards      w ON w.ward_id    = r.ward_id
JOIN    staff      s ON s.staff_id   = a.doctor_id
WHERE   a.discharged_at IS NULL
ORDER BY w.name, r.room_number, b.bed_number;

-- Q2  LEFT JOIN: every ward with its number of rooms and beds (keeps wards that have none)
SELECT  w.name AS ward,
        COUNT(DISTINCT r.room_id) AS rooms,
        COUNT(b.bed_id)           AS beds
FROM    wards w
LEFT JOIN rooms r ON r.ward_id = w.ward_id
LEFT JOIN beds  b ON b.room_id = r.room_id
GROUP BY w.name
ORDER BY beds DESC;

-- Q3  GROUP BY + HAVING (through a view): wards that are at least 75% full
SELECT  ward_name, occupied_beds, total_beds, occupancy_pct
FROM    v_ward_occupancy
WHERE   occupancy_pct >= 75;

-- Q4  Aggregate + JOIN: average length of stay (in days) per department, discharged patients only
SELECT  d.name AS department,
        COUNT(*) AS discharged_patients,
        ROUND(AVG(EXTRACT(EPOCH FROM (a.discharged_at - a.admitted_at)) / 86400)::NUMERIC, 1) AS avg_days
FROM    admissions  a
JOIN    beds        b ON b.bed_id        = a.bed_id
JOIN    rooms       r ON r.room_id       = b.room_id
JOIN    wards       w ON w.ward_id       = r.ward_id
JOIN    departments d ON d.department_id = w.department_id
WHERE   a.discharged_at IS NOT NULL
GROUP BY d.name
ORDER BY avg_days DESC;

-- Q5  Subquery with NOT EXISTS: wards that have occupied beds but NO nurse on shift today
SELECT  w.name AS ward
FROM    wards w
WHERE   EXISTS (SELECT 1
                  FROM beds  b
                  JOIN rooms r ON r.room_id = b.room_id
                 WHERE r.ward_id = w.ward_id AND b.status = 'occupied')
  AND   NOT EXISTS (SELECT 1
                      FROM shifts sh
                      JOIN staff  st ON st.staff_id = sh.staff_id
                     WHERE sh.ward_id    = w.ward_id
                       AND sh.shift_date = CURRENT_DATE
                       AND st.role       = 'Nurse');

-- Q6  Window function: rank the wards inside each department by occupancy
SELECT  department, ward_name, occupancy_pct,
        RANK() OVER (PARTITION BY department ORDER BY occupancy_pct DESC) AS rank_in_department
FROM    v_ward_occupancy
ORDER BY department, rank_in_department;

-- Q7  CTE: patients per nurse in each ward today (NULL when no nurse is on shift)
WITH patients_in_ward AS (
    SELECT r.ward_id, COUNT(*) AS patients
    FROM   admissions a
    JOIN   beds  b ON b.bed_id  = a.bed_id
    JOIN   rooms r ON r.room_id = b.room_id
    WHERE  a.discharged_at IS NULL
    GROUP BY r.ward_id
),
nurses_in_ward AS (
    SELECT sh.ward_id, COUNT(DISTINCT sh.staff_id) AS nurses
    FROM   shifts sh
    JOIN   staff  st ON st.staff_id = sh.staff_id
    WHERE  sh.shift_date = CURRENT_DATE AND st.role = 'Nurse'
    GROUP BY sh.ward_id
)
SELECT  w.name AS ward,
        COALESCE(pw.patients, 0) AS patients,
        COALESCE(nw.nurses, 0)   AS nurses,
        ROUND(pw.patients::NUMERIC / NULLIF(nw.nurses, 0), 1) AS patients_per_nurse
FROM    wards w
LEFT JOIN patients_in_ward pw ON pw.ward_id = w.ward_id
LEFT JOIN nurses_in_ward   nw ON nw.ward_id = w.ward_id
ORDER BY patients_per_nurse DESC NULLS FIRST;

-- Q8  Views: dashboard feeds
SELECT * FROM v_ward_occupancy ORDER BY occupancy_pct DESC;
SELECT * FROM v_open_alerts;
SELECT * FROM v_ward_forecast WHERE predicted_occupancy_pct >= 80 ORDER BY forecast_date, ward_name;

-- Q9  Set operation: staff who are not scheduled on any shift today
SELECT staff_id, full_name, role FROM staff
EXCEPT
SELECT st.staff_id, st.full_name, st.role
FROM   shifts sh JOIN staff st ON st.staff_id = sh.staff_id
WHERE  sh.shift_date = CURRENT_DATE
ORDER BY role, full_name;

-- =====================================================================
-- Rooms and nurse assignments
-- =====================================================================

-- Q13  Bed map: ward -> room -> bed, with the patient in each bed (NULL = empty)
SELECT ward_name, room_number, room_type, bed_number, bed_status, patient_name
FROM   v_bed_map
WHERE  ward_name IN ('Emergency Ward', 'Cardiac Care Unit')
ORDER BY ward_id, room_number, bed_number;

-- Q14  Which nurse looks after which patient today (JOIN of 7 tables)
SELECT  na.shift_type,
        st.full_name AS nurse,
        w.name       AS ward,
        r.room_number,
        b.bed_number,
        p.full_name  AS patient,
        a.severity
FROM    nurse_assignments na
JOIN    staff      st ON st.staff_id    = na.nurse_id
JOIN    admissions a  ON a.admission_id = na.admission_id
JOIN    patients   p  ON p.patient_id   = a.patient_id
JOIN    beds       b  ON b.bed_id       = a.bed_id
JOIN    rooms      r  ON r.room_id      = b.room_id
JOIN    wards      w  ON w.ward_id      = r.ward_id
WHERE   na.shift_date = CURRENT_DATE
ORDER BY w.name, na.shift_type, r.room_number, b.bed_number;

-- Q15  Nurse workload today, and the patients who have no nurse at all
SELECT * FROM v_nurse_workload WHERE shift_date = CURRENT_DATE ORDER BY patients DESC;
SELECT * FROM v_patients_without_nurse ORDER BY severity, ward_name;

-- =====================================================================
-- DML demonstrations (rolled back so the data stays unchanged)
-- =====================================================================

-- Q10  INSERT through the function: admit a patient, then discharge with the procedure.
--      The triggers occupy the bed, then mark it for cleaning.
BEGIN;
    INSERT INTO patients (full_name, date_of_birth, gender, blood_group)
    VALUES ('Demo Patient', '1990-01-01', 'M', 'O+');

    SELECT admit_patient(
               (SELECT MAX(patient_id) FROM patients),
               (SELECT bed_id FROM beds WHERE bed_number = 'E-06'),
               1, 'Observation', 'Low') AS new_admission_id;

    SELECT bed_number, status FROM beds WHERE bed_number = 'E-06';   -- occupied

    DO $$
    DECLARE v_id INT;
    BEGIN
        SELECT MAX(admission_id) INTO v_id FROM admissions;
        CALL discharge_patient(v_id);
    END
    $$;

    SELECT bed_number, status FROM beds WHERE bed_number = 'E-06';   -- cleaning
ROLLBACK;

-- Q11  UPDATE and DELETE examples
BEGIN;
    UPDATE beds SET status = 'available' WHERE status = 'cleaning';
    DELETE FROM alerts WHERE resolved_at IS NOT NULL;
ROLLBACK;

-- Q16  Assign a nurse with the function, and see her workload change.
--      Kavita Pawar (staff 7) is on the Emergency Ward morning shift today.
BEGIN;
    INSERT INTO patients (full_name, date_of_birth, gender, blood_group)
    VALUES ('Demo Patient Two', '1991-02-02', 'F', 'A+');

    SELECT admit_patient(
               (SELECT MAX(patient_id) FROM patients),
               (SELECT bed_id FROM beds WHERE bed_number = 'E-06'),
               1, 'Observation', 'Low') AS new_admission_id;

    SELECT assign_nurse((SELECT MAX(admission_id) FROM admissions), 7, 'Morning') AS new_assignment_id;

    SELECT nurse_name, ward_name, patients
    FROM   v_nurse_workload
    WHERE  nurse_id = 7 AND shift_date = CURRENT_DATE AND shift_type = 'Morning';
ROLLBACK;

-- Q12  Show that the constraints and triggers protect the data.
--      Each statement fails on purpose; the DO block prints the error message.
DO $$
DECLARE
    v_adm_emergency INT;
    v_adm_cardiac   INT;
BEGIN
    -- (a) bed already occupied -> trigger trg_check_admission rejects it
    BEGIN
        PERFORM admit_patient(20, (SELECT bed_id FROM beds WHERE bed_number = 'E-01'), 1, 'Test', 'Low');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '(a) Rejected: %', SQLERRM;
    END;

    -- (b) a nurse cannot attend a patient -> trigger rejects it
    BEGIN
        PERFORM admit_patient(20, (SELECT bed_id FROM beds WHERE bed_number = 'P-04'), 7, 'Test', 'Low');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '(b) Rejected: %', SQLERRM;
    END;

    -- (c) CHECK constraint on priority
    BEGIN
        INSERT INTO alerts (ward_id, alert_type, priority, message)
        VALUES (1, 'Equipment', 'Urgent', 'invalid priority');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '(c) Rejected: %', SQLERRM;
    END;

    -- (d) FOREIGN KEY (ON DELETE RESTRICT): a department that still has wards cannot be deleted
    BEGIN
        DELETE FROM departments WHERE department_id = 1;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '(d) Rejected: %', SQLERRM;
    END;

    SELECT a.admission_id INTO v_adm_emergency
      FROM admissions a JOIN beds b USING (bed_id)
     WHERE b.bed_number = 'E-01' AND a.discharged_at IS NULL;
    SELECT a.admission_id INTO v_adm_cardiac
      FROM admissions a JOIN beds b USING (bed_id)
     WHERE b.bed_number = 'C-01' AND a.discharged_at IS NULL;

    -- (e) a doctor cannot be assigned as the nurse -> trigger trg_check_nurse_assignment rejects it
    BEGIN
        PERFORM assign_nurse(v_adm_emergency, 1, 'Evening');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '(e) Rejected: %', SQLERRM;
    END;

    -- (f) a nurse who works in another ward cannot be assigned (Cardiac Care Unit patient, Emergency nurse)
    BEGIN
        PERFORM assign_nurse(v_adm_cardiac, 7, 'Morning');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '(f) Rejected: %', SQLERRM;
    END;

    -- (g) the same patient cannot get a second nurse for the same shift (UNIQUE constraint)
    BEGIN
        PERFORM assign_nurse(v_adm_emergency, 7, 'Morning');
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '(g) Rejected: %', SQLERRM;
    END;
END
$$;
