-- =====================================================================
-- 04_views.sql  -  read-only views that feed the dashboard
--   v_ward_occupancy         bed counts and occupancy % per ward
--   v_current_patients       every patient who is admitted right now
--   v_open_alerts            unresolved alerts, most urgent first
--   v_ward_forecast          AI forecast next to the current occupancy
--   v_bed_map                ward -> room -> bed with the patient in it
--   v_nurse_workload         patients per nurse per shift
--   v_patients_without_nurse admitted patients with no nurse today
-- =====================================================================

CREATE OR REPLACE VIEW v_ward_occupancy AS
SELECT  w.ward_id,
        w.name                                              AS ward_name,
        w.ward_type,
        d.name                                              AS department,
        COUNT(b.bed_id)                                     AS total_beds,
        COUNT(*) FILTER (WHERE b.status = 'occupied')       AS occupied_beds,
        COUNT(*) FILTER (WHERE b.status = 'available')      AS available_beds,
        COALESCE(ROUND(100.0 * COUNT(*) FILTER (WHERE b.status = 'occupied')
                       / NULLIF(COUNT(b.bed_id), 0), 2), 0) AS occupancy_pct
FROM    wards       w
JOIN    departments d ON d.department_id = w.department_id
LEFT JOIN rooms     r ON r.ward_id       = w.ward_id
LEFT JOIN beds      b ON b.room_id       = r.room_id
GROUP BY w.ward_id, w.name, w.ward_type, d.name;

CREATE OR REPLACE VIEW v_current_patients AS
SELECT  a.admission_id,
        p.patient_id,
        p.full_name                                        AS patient_name,
        EXTRACT(YEAR FROM age(CURRENT_DATE, p.date_of_birth))::INT AS age,
        p.gender,
        w.name                                             AS ward_name,
        r.room_number,
        b.bed_number,
        s.full_name                                        AS doctor_name,
        a.diagnosis,
        a.severity,
        a.admitted_at,
        ROUND(EXTRACT(EPOCH FROM (now() - a.admitted_at)) / 86400, 1) AS days_admitted
FROM    admissions a
JOIN    patients   p ON p.patient_id = a.patient_id
JOIN    beds       b ON b.bed_id     = a.bed_id
JOIN    rooms      r ON r.room_id    = b.room_id
JOIN    wards      w ON w.ward_id    = r.ward_id
JOIN    staff      s ON s.staff_id   = a.doctor_id
WHERE   a.discharged_at IS NULL;

CREATE OR REPLACE VIEW v_open_alerts AS
SELECT  al.alert_id,
        w.name       AS ward_name,
        al.alert_type,
        al.priority,
        al.message,
        al.created_at
FROM    alerts al
JOIN    wards  w ON w.ward_id = al.ward_id
WHERE   al.resolved_at IS NULL
ORDER BY CASE al.priority
             WHEN 'Critical' THEN 1
             WHEN 'High'     THEN 2
             WHEN 'Medium'   THEN 3
             ELSE 4
         END,
         al.created_at DESC;

CREATE OR REPLACE VIEW v_ward_forecast AS
SELECT  w.ward_id,
        w.name                      AS ward_name,
        ap.forecast_date,
        ap.predicted_occupancy_pct,
        ap.model_name,
        wo.occupancy_pct            AS current_occupancy_pct,
        ap.predicted_occupancy_pct - wo.occupancy_pct AS expected_change
FROM    ai_predictions  ap
JOIN    wards           w  ON w.ward_id  = ap.ward_id
JOIN    v_ward_occupancy wo ON wo.ward_id = w.ward_id
WHERE   ap.forecast_date >= CURRENT_DATE;

-- Every bed with its room and ward, and the patient in it (NULL when empty).
CREATE OR REPLACE VIEW v_bed_map AS
SELECT  w.ward_id,
        w.name          AS ward_name,
        r.room_number,
        r.room_type,
        b.bed_id,
        b.bed_number,
        b.status        AS bed_status,
        p.full_name     AS patient_name,
        a.severity
FROM    wards  w
JOIN    rooms  r ON r.ward_id = w.ward_id
JOIN    beds   b ON b.room_id = r.room_id
LEFT JOIN admissions a ON a.bed_id = b.bed_id AND a.discharged_at IS NULL
LEFT JOIN patients   p ON p.patient_id = a.patient_id
ORDER BY w.ward_id, r.room_number, b.bed_number;

-- How many current patients each nurse looks after, per shift.
CREATE OR REPLACE VIEW v_nurse_workload AS
SELECT  na.shift_date,
        na.shift_type,
        st.staff_id     AS nurse_id,
        st.full_name    AS nurse_name,
        w.name          AS ward_name,
        COUNT(*)        AS patients
FROM    nurse_assignments na
JOIN    staff      st ON st.staff_id     = na.nurse_id
JOIN    admissions a  ON a.admission_id  = na.admission_id AND a.discharged_at IS NULL
JOIN    beds       b  ON b.bed_id        = a.bed_id
JOIN    rooms      r  ON r.room_id       = b.room_id
JOIN    wards      w  ON w.ward_id       = r.ward_id
GROUP BY na.shift_date, na.shift_type, st.staff_id, st.full_name, w.name;

-- Admitted patients who have no nurse assigned for today.
CREATE OR REPLACE VIEW v_patients_without_nurse AS
SELECT  cp.admission_id,
        cp.patient_name,
        cp.ward_name,
        cp.room_number,
        cp.bed_number,
        cp.severity
FROM    v_current_patients cp
WHERE   NOT EXISTS (SELECT 1
                      FROM nurse_assignments na
                     WHERE na.admission_id = cp.admission_id
                       AND na.shift_date   = CURRENT_DATE);
