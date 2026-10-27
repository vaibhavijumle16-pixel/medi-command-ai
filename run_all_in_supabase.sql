-- ################ 01_schema.sql ################
-- =====================================================================
-- 01_schema.sql  -  DDL for the AI Hospital Command Center
-- Target: PostgreSQL 14+ (tested on 16) / Supabase
-- Design: 11 tables in Third Normal Form (see docs/NORMALIZATION.md)
-- Layout: department -> ward -> room -> bed
-- Run order: 01_schema -> 02_functions_procedures -> 03_triggers
--            -> 04_views -> 05_seed_data -> 06_queries
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. departments : organisational units of the hospital
-- ---------------------------------------------------------------------
CREATE TABLE departments (
    department_id  SERIAL       PRIMARY KEY,
    name           VARCHAR(80)  NOT NULL UNIQUE,
    floor_no       SMALLINT     NOT NULL CHECK (floor_no >= 0)
);

-- ---------------------------------------------------------------------
-- 2. wards : a department can run many wards
-- ---------------------------------------------------------------------
CREATE TABLE wards (
    ward_id        SERIAL       PRIMARY KEY,
    department_id  INT          NOT NULL
                   REFERENCES departments (department_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    name           VARCHAR(80)  NOT NULL,
    ward_type      VARCHAR(20)  NOT NULL
                   CHECK (ward_type IN ('General', 'ICU', 'Emergency', 'Maternity', 'Pediatric')),
    CONSTRAINT uq_ward_name_per_department UNIQUE (department_id, name)
);

-- ---------------------------------------------------------------------
-- 3. rooms : a ward is made of rooms
-- ---------------------------------------------------------------------
CREATE TABLE rooms (
    room_id      SERIAL       PRIMARY KEY,
    ward_id      INT          NOT NULL
                 REFERENCES wards (ward_id)
                 ON UPDATE CASCADE ON DELETE CASCADE,
    room_number  VARCHAR(10)  NOT NULL,
    room_type    VARCHAR(10)  NOT NULL DEFAULT 'Shared'
                 CHECK (room_type IN ('Private', 'Shared', 'ICU')),
    CONSTRAINT uq_room_number_per_ward UNIQUE (ward_id, room_number)
);

-- ---------------------------------------------------------------------
-- 4. beds : physical beds inside a room
--    A bed knows its room only. Its ward is found through the room, so the
--    ward is not repeated here (that would be a transitive dependency).
--    Bed counts are NOT stored either; they are derived in the views.
-- ---------------------------------------------------------------------
CREATE TABLE beds (
    bed_id      SERIAL       PRIMARY KEY,
    room_id     INT          NOT NULL
                REFERENCES rooms (room_id)
                ON UPDATE CASCADE ON DELETE CASCADE,
    bed_number  VARCHAR(10)  NOT NULL,
    status      VARCHAR(15)  NOT NULL DEFAULT 'available'
                CHECK (status IN ('available', 'occupied', 'cleaning', 'maintenance')),
    CONSTRAINT uq_bed_number_per_room UNIQUE (room_id, bed_number)
);

-- ---------------------------------------------------------------------
-- 5. staff : doctors, nurses, technicians and administrators
-- ---------------------------------------------------------------------
CREATE TABLE staff (
    staff_id       SERIAL        PRIMARY KEY,
    department_id  INT           NOT NULL
                   REFERENCES departments (department_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    full_name      VARCHAR(100)  NOT NULL,
    role           VARCHAR(20)   NOT NULL
                   CHECK (role IN ('Doctor', 'Nurse', 'Technician', 'Administrator')),
    email          VARCHAR(120)  NOT NULL UNIQUE,
    phone          VARCHAR(15)
);

-- ---------------------------------------------------------------------
-- 6. patients : age is NOT stored (it is derived from date_of_birth)
-- ---------------------------------------------------------------------
CREATE TABLE patients (
    patient_id     SERIAL        PRIMARY KEY,
    full_name      VARCHAR(100)  NOT NULL,
    date_of_birth  DATE          NOT NULL CHECK (date_of_birth > DATE '1900-01-01'),
    gender         CHAR(1)       NOT NULL CHECK (gender IN ('M', 'F', 'O')),
    blood_group    VARCHAR(3)    CHECK (blood_group IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
    phone          VARCHAR(15)
);

-- ---------------------------------------------------------------------
-- 7. admissions : a patient occupying a bed under a doctor
--    discharged_at IS NULL  <=>  the patient is currently admitted.
--    (There is deliberately no separate "status" column: it would be
--    derivable from discharged_at and would break 3NF.)
-- ---------------------------------------------------------------------
CREATE TABLE admissions (
    admission_id   SERIAL        PRIMARY KEY,
    patient_id     INT           NOT NULL
                   REFERENCES patients (patient_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    bed_id         INT           NOT NULL
                   REFERENCES beds (bed_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    doctor_id      INT           NOT NULL
                   REFERENCES staff (staff_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    admitted_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    discharged_at  TIMESTAMPTZ,
    diagnosis      VARCHAR(200)  NOT NULL,
    severity       VARCHAR(10)   NOT NULL
                   CHECK (severity IN ('Low', 'Medium', 'High', 'Critical')),
    CONSTRAINT chk_discharge_after_admit
        CHECK (discharged_at IS NULL OR discharged_at >= admitted_at)
);

-- A bed can hold only one current patient, and a patient can be in only one bed.
CREATE UNIQUE INDEX uq_active_admission_per_bed
    ON admissions (bed_id)     WHERE discharged_at IS NULL;
CREATE UNIQUE INDEX uq_active_admission_per_patient
    ON admissions (patient_id) WHERE discharged_at IS NULL;

-- ---------------------------------------------------------------------
-- 8. shifts : which staff member works in which ward on which shift
--    (resolves the many-to-many relationship staff <-> wards)
-- ---------------------------------------------------------------------
CREATE TABLE shifts (
    shift_id    SERIAL       PRIMARY KEY,
    staff_id    INT          NOT NULL
                REFERENCES staff (staff_id)
                ON UPDATE CASCADE ON DELETE CASCADE,
    ward_id     INT          NOT NULL
                REFERENCES wards (ward_id)
                ON UPDATE CASCADE ON DELETE CASCADE,
    shift_date  DATE         NOT NULL,
    shift_type  VARCHAR(10)  NOT NULL
                CHECK (shift_type IN ('Morning', 'Evening', 'Night')),
    CONSTRAINT uq_staff_one_ward_per_shift UNIQUE (staff_id, shift_date, shift_type)
);

-- ---------------------------------------------------------------------
-- 9. nurse_assignments : which nurse looks after which admitted patient
--    on which shift (resolves the many-to-many admissions <-> nurses).
--    Business rules (nurse role, nurse on shift in the patient's ward,
--    at most 6 patients per nurse per shift) are enforced by the trigger
--    trg_check_nurse_assignment in 03_triggers.sql.
-- ---------------------------------------------------------------------
CREATE TABLE nurse_assignments (
    assignment_id  SERIAL       PRIMARY KEY,
    admission_id   INT          NOT NULL
                   REFERENCES admissions (admission_id)
                   ON UPDATE CASCADE ON DELETE CASCADE,
    nurse_id       INT          NOT NULL
                   REFERENCES staff (staff_id)
                   ON UPDATE CASCADE ON DELETE RESTRICT,
    shift_date     DATE         NOT NULL,
    shift_type     VARCHAR(10)  NOT NULL
                   CHECK (shift_type IN ('Morning', 'Evening', 'Night')),
    CONSTRAINT uq_one_nurse_per_patient_shift UNIQUE (admission_id, shift_date, shift_type)
);

-- ---------------------------------------------------------------------
-- 10. alerts : critical events shown on the command-center dashboard
-- ---------------------------------------------------------------------
CREATE TABLE alerts (
    alert_id      SERIAL        PRIMARY KEY,
    ward_id       INT           NOT NULL
                  REFERENCES wards (ward_id)
                  ON UPDATE CASCADE ON DELETE CASCADE,
    admission_id  INT
                  REFERENCES admissions (admission_id)
                  ON UPDATE CASCADE ON DELETE SET NULL,
    alert_type    VARCHAR(30)   NOT NULL
                  CHECK (alert_type IN ('High Occupancy', 'Critical Patient', 'Staff Shortage', 'Equipment')),
    priority      VARCHAR(10)   NOT NULL
                  CHECK (priority IN ('Low', 'Medium', 'High', 'Critical')),
    message       VARCHAR(255)  NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    resolved_at   TIMESTAMPTZ,
    CONSTRAINT chk_alert_resolved_after_created
        CHECK (resolved_at IS NULL OR resolved_at >= created_at)
);

-- ---------------------------------------------------------------------
-- 11. ai_predictions : occupancy forecasts produced by the AI model
-- ---------------------------------------------------------------------
CREATE TABLE ai_predictions (
    prediction_id            SERIAL        PRIMARY KEY,
    ward_id                  INT           NOT NULL
                             REFERENCES wards (ward_id)
                             ON UPDATE CASCADE ON DELETE CASCADE,
    forecast_date            DATE          NOT NULL,
    predicted_occupancy_pct  NUMERIC(5,2)  NOT NULL
                             CHECK (predicted_occupancy_pct BETWEEN 0 AND 100),
    model_name               VARCHAR(50)   NOT NULL,
    created_at               TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_one_forecast_per_ward_day_model UNIQUE (ward_id, forecast_date, model_name)
);

-- ---------------------------------------------------------------------
-- Indexes on foreign keys and common dashboard filters
-- (PRIMARY KEY and UNIQUE constraints already create their own indexes.)
-- ---------------------------------------------------------------------
CREATE INDEX idx_wards_department      ON wards (department_id);
CREATE INDEX idx_rooms_ward            ON rooms (ward_id);
CREATE INDEX idx_beds_room             ON beds (room_id);
CREATE INDEX idx_staff_department      ON staff (department_id);
CREATE INDEX idx_beds_status           ON beds (status);
CREATE INDEX idx_admissions_patient    ON admissions (patient_id);
CREATE INDEX idx_admissions_doctor     ON admissions (doctor_id);
CREATE INDEX idx_shifts_ward_date      ON shifts (ward_id, shift_date);
CREATE INDEX idx_nurse_assign_nurse    ON nurse_assignments (nurse_id, shift_date, shift_type);
CREATE INDEX idx_alerts_ward           ON alerts (ward_id);
CREATE INDEX idx_alerts_open           ON alerts (priority, created_at) WHERE resolved_at IS NULL;

-- ################ 02_functions_procedures.sql ################
-- =====================================================================
-- 02_functions_procedures.sql  -  stored routines (PL/pgSQL)
--   ward_occupancy_pct(ward)   function  : percent of beds occupied
--   admit_patient(...)         function  : admits a patient, returns the new admission id
--   assign_nurse(...)          function  : assigns a nurse to a patient for a shift
--   discharge_patient(id)      procedure : discharges a patient (use CALL)
-- Business rules (bed must be free, only doctors attend, nurse must be on
-- shift in the patient's ward) are enforced by the triggers in
-- 03_triggers.sql, so every code path is protected.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Percentage of beds currently occupied in one ward (0 if the ward has no beds).
-- A bed belongs to a room and a room belongs to a ward.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ward_occupancy_pct(p_ward_id INT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
               ROUND(100.0 * COUNT(*) FILTER (WHERE b.status = 'occupied')
                           / NULLIF(COUNT(*), 0), 2),
               0)
    FROM beds  b
    JOIN rooms r ON r.room_id = b.room_id
    WHERE r.ward_id = p_ward_id;
$$;

-- ---------------------------------------------------------------------
-- Admit a patient. Returns the new admission_id.
-- Example: SELECT admit_patient(5, 12, 2, 'Chest pain', 'High');
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION admit_patient(
    p_patient_id INT,
    p_bed_id     INT,
    p_doctor_id  INT,
    p_diagnosis  TEXT,
    p_severity   TEXT
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_admission_id INT;
BEGIN
    INSERT INTO admissions (patient_id, bed_id, doctor_id, diagnosis, severity)
    VALUES (p_patient_id, p_bed_id, p_doctor_id, p_diagnosis, p_severity)
    RETURNING admission_id INTO v_admission_id;

    RETURN v_admission_id;
END;
$$;

-- ---------------------------------------------------------------------
-- Assign a nurse to an admitted patient for one shift.
-- Returns the new assignment_id.
-- Example: SELECT assign_nurse(5, 7, 'Morning');            -- today
--          SELECT assign_nurse(5, 7, 'Evening', DATE '2026-10-20');
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION assign_nurse(
    p_admission_id INT,
    p_nurse_id     INT,
    p_shift_type   TEXT,
    p_shift_date   DATE DEFAULT CURRENT_DATE
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_assignment_id INT;
BEGIN
    INSERT INTO nurse_assignments (admission_id, nurse_id, shift_date, shift_type)
    VALUES (p_admission_id, p_nurse_id, p_shift_date, p_shift_type)
    RETURNING assignment_id INTO v_assignment_id;

    RETURN v_assignment_id;
END;
$$;

-- ---------------------------------------------------------------------
-- Discharge a patient.
-- Example: CALL discharge_patient(7);
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE discharge_patient(p_admission_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE admissions
       SET discharged_at = now()
     WHERE admission_id = p_admission_id
       AND discharged_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Admission % does not exist or the patient is already discharged',
                        p_admission_id;
    END IF;
END;
$$;

-- ################ 03_triggers.sql ################
-- =====================================================================
-- 03_triggers.sql  -  automatic business rules
--
--   trg_check_admission        BEFORE INSERT / UPDATE OF doctor_id on admissions
--       - the bed must be 'available' when a patient is admitted
--       - the attending staff member must have the role 'Doctor'
--
--   trg_admission_created      AFTER INSERT on admissions
--       - marks the bed 'occupied'
--       - raises a 'Critical Patient' alert for critical cases
--       - raises a 'High Occupancy' alert when the ward reaches 90%
--
--   trg_admission_discharged   AFTER UPDATE OF discharged_at on admissions
--       - marks the bed 'cleaning'
--       - resolves the patient's alerts and the ward's occupancy alert
--
--   trg_check_nurse_assignment BEFORE INSERT / UPDATE on nurse_assignments
--       - the assigned staff member must be a 'Nurse'
--       - the patient must still be admitted
--       - the nurse must be on that shift in the patient's ward
--       - a nurse may look after at most 6 patients per shift
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Validate an admission before it is saved
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_admission()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_bed_status  VARCHAR(15);
    v_doctor_role VARCHAR(20);
BEGIN
    -- Only a new, still-active admission needs a free bed.
    IF TG_OP = 'INSERT' AND NEW.discharged_at IS NULL THEN
        SELECT status INTO v_bed_status FROM beds WHERE bed_id = NEW.bed_id;
        IF v_bed_status IS DISTINCT FROM 'available' THEN
            RAISE EXCEPTION 'Bed % is not available (current status: %)',
                            NEW.bed_id, COALESCE(v_bed_status, 'unknown');
        END IF;
    END IF;

    -- The attending staff member must be a doctor.
    SELECT role INTO v_doctor_role FROM staff WHERE staff_id = NEW.doctor_id;
    IF v_doctor_role IS DISTINCT FROM 'Doctor' THEN
        RAISE EXCEPTION 'Staff member % is not a doctor and cannot attend a patient',
                        NEW.doctor_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_admission
BEFORE INSERT OR UPDATE OF doctor_id ON admissions
FOR EACH ROW
EXECUTE FUNCTION check_admission();

-- ---------------------------------------------------------------------
-- 2. After a patient is admitted: occupy the bed and raise alerts
--    (the ward is found through bed -> room -> ward)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION on_admission_created()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ward_id INT;
    v_pct     NUMERIC;
BEGIN
    UPDATE beds
       SET status = 'occupied'
     WHERE bed_id = NEW.bed_id;

    SELECT r.ward_id INTO v_ward_id
      FROM beds  b
      JOIN rooms r ON r.room_id = b.room_id
     WHERE b.bed_id = NEW.bed_id;

    IF NEW.severity = 'Critical' THEN
        INSERT INTO alerts (ward_id, admission_id, alert_type, priority, message)
        VALUES (v_ward_id, NEW.admission_id, 'Critical Patient', 'Critical',
                'Critical patient admitted: ' || NEW.diagnosis);
    END IF;

    v_pct := ward_occupancy_pct(v_ward_id);

    IF v_pct >= 90
       AND NOT EXISTS (SELECT 1
                         FROM alerts
                        WHERE ward_id    = v_ward_id
                          AND alert_type = 'High Occupancy'
                          AND resolved_at IS NULL)
    THEN
        INSERT INTO alerts (ward_id, alert_type, priority, message)
        VALUES (v_ward_id, 'High Occupancy', 'High',
                'Ward occupancy reached ' || ROUND(v_pct) || '%');
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_admission_created
AFTER INSERT ON admissions
FOR EACH ROW
WHEN (NEW.discharged_at IS NULL)
EXECUTE FUNCTION on_admission_created();

-- ---------------------------------------------------------------------
-- 3. After a patient is discharged: free the bed and close alerts
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION on_admission_discharged()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ward_id INT;
BEGIN
    UPDATE beds
       SET status = 'cleaning'
     WHERE bed_id = NEW.bed_id;

    SELECT r.ward_id INTO v_ward_id
      FROM beds  b
      JOIN rooms r ON r.room_id = b.room_id
     WHERE b.bed_id = NEW.bed_id;

    -- Close the alerts that belonged to this patient.
    UPDATE alerts
       SET resolved_at = now()
     WHERE admission_id = NEW.admission_id
       AND resolved_at IS NULL;

    -- Close the ward's high-occupancy alert once it drops below 90%.
    IF ward_occupancy_pct(v_ward_id) < 90 THEN
        UPDATE alerts
           SET resolved_at = now()
         WHERE ward_id    = v_ward_id
           AND alert_type = 'High Occupancy'
           AND resolved_at IS NULL;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_admission_discharged
AFTER UPDATE OF discharged_at ON admissions
FOR EACH ROW
WHEN (OLD.discharged_at IS NULL AND NEW.discharged_at IS NOT NULL)
EXECUTE FUNCTION on_admission_discharged();

-- ---------------------------------------------------------------------
-- 4. Validate a nurse assignment before it is saved
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION check_nurse_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_role       VARCHAR(20);
    v_ward_id    INT;
    v_discharged TIMESTAMPTZ;
    v_patients   INT;
BEGIN
    -- 1. Only nurses can be assigned to patients.
    SELECT role INTO v_role FROM staff WHERE staff_id = NEW.nurse_id;
    IF v_role IS DISTINCT FROM 'Nurse' THEN
        RAISE EXCEPTION 'Staff member % is not a nurse and cannot be assigned to a patient',
                        NEW.nurse_id;
    END IF;

    -- 2. Find the patient's ward (bed -> room -> ward) and check the patient is still admitted.
    SELECT r.ward_id, a.discharged_at
      INTO v_ward_id, v_discharged
      FROM admissions a
      JOIN beds  b ON b.bed_id  = a.bed_id
      JOIN rooms r ON r.room_id = b.room_id
     WHERE a.admission_id = NEW.admission_id;

    IF v_ward_id IS NULL THEN
        RAISE EXCEPTION 'Admission % does not exist', NEW.admission_id;
    END IF;
    IF v_discharged IS NOT NULL THEN
        RAISE EXCEPTION 'Admission % is already discharged', NEW.admission_id;
    END IF;

    -- 3. The nurse must be rostered on this shift in the patient's ward.
    IF NOT EXISTS (SELECT 1
                     FROM shifts
                    WHERE staff_id   = NEW.nurse_id
                      AND ward_id    = v_ward_id
                      AND shift_date = NEW.shift_date
                      AND shift_type = NEW.shift_type)
    THEN
        RAISE EXCEPTION 'Nurse % is not on the % shift on % in the ward of admission %',
                        NEW.nurse_id, NEW.shift_type, NEW.shift_date, NEW.admission_id;
    END IF;

    -- 4. Workload limit: at most 6 current patients per nurse per shift.
    SELECT COUNT(*) INTO v_patients
      FROM nurse_assignments na
      JOIN admissions a ON a.admission_id = na.admission_id
     WHERE na.nurse_id      = NEW.nurse_id
       AND na.shift_date    = NEW.shift_date
       AND na.shift_type    = NEW.shift_type
       AND a.discharged_at IS NULL
       AND na.assignment_id IS DISTINCT FROM NEW.assignment_id;

    IF v_patients >= 6 THEN
        RAISE EXCEPTION 'Nurse % already has % patients on the % shift on % (maximum is 6)',
                        NEW.nurse_id, v_patients, NEW.shift_type, NEW.shift_date;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_nurse_assignment
BEFORE INSERT OR UPDATE OF nurse_id, admission_id, shift_date, shift_type ON nurse_assignments
FOR EACH ROW
EXECUTE FUNCTION check_nurse_assignment();

-- ################ 04_views.sql ################
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

-- ################ 05_seed_data.sql ################
-- =====================================================================
-- 05_seed_data.sql  -  synthetic demo data (no real patients)
-- Run AFTER 01-04 so that the triggers set bed status and raise alerts
-- automatically. Dates are relative to "now", so the data is always fresh.
--
-- Demo tip: shifts and nurse assignments are created for TODAY. If you
-- show the project on another day, run   CALL seed_todays_shifts();
-- first and the nurse queries will work for that day too.
-- =====================================================================

-- ---------- departments ----------
INSERT INTO departments (department_id, name, floor_no) VALUES
    (1, 'Emergency',        0),
    (2, 'Cardiology',       2),
    (3, 'Pediatrics',       1),
    (4, 'Intensive Care',   3),
    (5, 'General Medicine', 1);

-- ---------- wards ----------
INSERT INTO wards (ward_id, department_id, name, ward_type) VALUES
    (1, 1, 'Emergency Ward',     'Emergency'),
    (2, 2, 'Cardiac Care Unit',  'ICU'),
    (3, 3, 'Children Ward',      'Pediatric'),
    (4, 4, 'Main ICU',           'ICU'),
    (5, 5, 'General Ward A',     'General'),
    (6, 5, 'General Ward B',     'General');

-- ---------- rooms (22 rooms: ICU rooms are single, the others are shared) ----------
INSERT INTO rooms (ward_id, room_number, room_type)
SELECT v.ward_id, v.prefix || '-R' || g, v.room_type
FROM (VALUES (1, 'E', 3, 'Shared'), (2, 'C', 4, 'ICU'),    (3, 'P', 3, 'Shared'),
             (4, 'I', 5, 'ICU'),    (5, 'A', 4, 'Shared'), (6, 'B', 3, 'Shared'))
     AS v(ward_id, prefix, n_rooms, room_type)
CROSS JOIN LATERAL generate_series(1, v.n_rooms) AS g;

-- ---------- beds (35 beds: 1 per ICU room, 2 per shared room) ----------
INSERT INTO beds (room_id, bed_number)
SELECT r.room_id, v.prefix || '-' || LPAD(g::TEXT, 2, '0')
FROM (VALUES (1, 'E', 6, 2), (2, 'C', 4, 1), (3, 'P', 6, 2),
             (4, 'I', 5, 1), (5, 'A', 8, 2), (6, 'B', 6, 2))
     AS v(ward_id, prefix, n_beds, beds_per_room)
CROSS JOIN LATERAL generate_series(1, v.n_beds) AS g
JOIN rooms r
  ON r.ward_id     = v.ward_id
 AND r.room_number = v.prefix || '-R' || ((g - 1) / v.beds_per_room + 1);

-- ---------- staff ----------
INSERT INTO staff (staff_id, department_id, full_name, role, email, phone) VALUES
    ( 1, 1, 'Dr. Ramesh Kulkarni',   'Doctor',        'ramesh.kulkarni@cityhospital.example',   '9000000001'),
    ( 2, 2, 'Dr. Sunita Rao',        'Doctor',        'sunita.rao@cityhospital.example',        '9000000002'),
    ( 3, 3, 'Dr. Imran Khan',        'Doctor',        'imran.khan@cityhospital.example',        '9000000003'),
    ( 4, 4, 'Dr. Anjali Deshpande',  'Doctor',        'anjali.deshpande@cityhospital.example',  '9000000004'),
    ( 5, 5, 'Dr. Pradeep Nair',      'Doctor',        'pradeep.nair@cityhospital.example',      '9000000005'),
    ( 6, 5, 'Dr. Lakshmi Iyer',      'Doctor',        'lakshmi.iyer@cityhospital.example',      '9000000006'),
    ( 7, 1, 'Kavita Pawar',          'Nurse',         'kavita.pawar@cityhospital.example',      '9000000007'),
    ( 8, 4, 'Joseph Dsouza',         'Nurse',         'joseph.dsouza@cityhospital.example',     '9000000008'),
    ( 9, 3, 'Farah Sheikh',          'Nurse',         'farah.sheikh@cityhospital.example',      '9000000009'),
    (10, 5, 'Geeta Patil',           'Nurse',         'geeta.patil@cityhospital.example',       '9000000010'),
    (11, 4, 'Rajesh Naik',           'Technician',    'rajesh.naik@cityhospital.example',       '9000000011'),
    (12, 5, 'Smita Kamat',           'Administrator', 'smita.kamat@cityhospital.example',      '9000000012');

-- ---------- patients ----------
INSERT INTO patients (patient_id, full_name, date_of_birth, gender, blood_group, phone) VALUES
    ( 1, 'Aarav Mehta',      '1985-03-12', 'M', 'O+',  '9100000001'),
    ( 2, 'Priya Nair',       '1992-07-24', 'F', 'A+',  '9100000002'),
    ( 3, 'Rohan Deshmukh',   '1978-11-02', 'M', 'B+',  '9100000003'),
    ( 4, 'Sneha Kulkarni',   '2001-01-30', 'F', 'AB+', '9100000004'),
    ( 5, 'Vikram Singh',     '1965-09-15', 'M', 'O-',  '9100000005'),
    ( 6, 'Ananya Iyer',      '1999-05-08', 'F', 'A-',  '9100000006'),
    ( 7, 'Karan Patel',      '1958-12-19', 'M', 'B-',  '9100000007'),
    ( 8, 'Meera Joshi',      '1972-04-27', 'F', 'O+',  '9100000008'),
    ( 9, 'Arjun Reddy',      '2015-06-10', 'M', 'A+',  '9100000009'),
    (10, 'Diya Sharma',      '2018-02-14', 'F', 'B+',  '9100000010'),
    (11, 'Rahul Verma',      '1990-08-03', 'M', 'AB-', '9100000011'),
    (12, 'Pooja Gupta',      '1983-10-21', 'F', 'O+',  '9100000012'),
    (13, 'Sanjay Rao',       '1950-01-09', 'M', 'A+',  '9100000013'),
    (14, 'Neha Bhat',        '1995-03-18', 'F', 'B+',  '9100000014'),
    (15, 'Amit Chauhan',     '1969-07-07', 'M', 'O+',  '9100000015'),
    (16, 'Kavya Menon',      '1988-12-01', 'F', 'A+',  '9100000016'),
    (17, 'Suresh Pillai',    '1947-05-25', 'M', 'B+',  '9100000017'),
    (18, 'Ritu Malhotra',    '1976-09-29', 'F', 'AB+', '9100000018'),
    (19, 'Yash Thakur',      '2010-11-11', 'M', 'O+',  '9100000019'),
    (20, 'Isha Banerjee',    '1994-06-16', 'F', 'A+',  '9100000020'),
    (21, 'Manoj Kumar',      '1981-02-22', 'M', 'B-',  '9100000021'),
    (22, 'Tanvi Shah',       '2005-08-05', 'F', 'O+',  '9100000022');

-- Keep the SERIAL counters ahead of the ids inserted by hand above.
SELECT setval(pg_get_serial_sequence('departments', 'department_id'), (SELECT MAX(department_id) FROM departments));
SELECT setval(pg_get_serial_sequence('wards',       'ward_id'),       (SELECT MAX(ward_id)       FROM wards));
SELECT setval(pg_get_serial_sequence('staff',       'staff_id'),      (SELECT MAX(staff_id)      FROM staff));
SELECT setval(pg_get_serial_sequence('patients',    'patient_id'),    (SELECT MAX(patient_id)    FROM patients));

-- ---------- past admissions (already discharged; triggers ignore these) ----------
INSERT INTO admissions (patient_id, bed_id, doctor_id, admitted_at, discharged_at, diagnosis, severity)
SELECT v.patient_id, b.bed_id, v.doctor_id,
       now() - v.admitted_ago, now() - v.discharged_ago, v.diagnosis, v.severity
FROM (VALUES
    (19, 'P-03', 3, INTERVAL '5 days', INTERVAL '3 days', 'Viral fever',        'Low'),
    (20, 'A-05', 5, INTERVAL '6 days', INTERVAL '2 days', 'Food poisoning',     'Low'),
    (21, 'E-04', 1, INTERVAL '4 days', INTERVAL '3 days', 'Minor head injury',  'Medium'),
    (22, 'I-04', 4, INTERVAL '9 days', INTERVAL '5 days', 'Pneumonia',          'High')
) AS v(patient_id, bed_number, doctor_id, admitted_ago, discharged_ago, diagnosis, severity)
JOIN beds b ON b.bed_number = v.bed_number;

-- ---------- current admissions (triggers occupy the beds and raise alerts) ----------
INSERT INTO admissions (patient_id, bed_id, doctor_id, admitted_at, diagnosis, severity)
SELECT v.patient_id, b.bed_id, v.doctor_id, now() - v.admitted_ago, v.diagnosis, v.severity
FROM (VALUES
    ( 1, 'E-01', 1, INTERVAL '3 hours',  'Acute chest pain',          'High'),
    ( 2, 'E-02', 1, INTERVAL '1 hour',   'Fracture of the forearm',   'Medium'),
    ( 3, 'E-03', 1, INTERVAL '30 minutes', 'Road accident trauma',    'Critical'),
    ( 5, 'C-01', 2, INTERVAL '2 days',   'Myocardial infarction',     'Critical'),
    ( 7, 'C-02', 2, INTERVAL '1 day',    'Arrhythmia',                'High'),
    (13, 'C-03', 2, INTERVAL '3 days',   'Heart failure',             'High'),
    (17, 'C-04', 2, INTERVAL '12 hours', 'Unstable angina',           'High'),
    ( 9, 'P-01', 3, INTERVAL '1 day',    'Pneumonia',                 'Medium'),
    (10, 'P-02', 3, INTERVAL '6 hours',  'Dengue fever',              'Medium'),
    ( 8, 'I-01', 4, INTERVAL '4 days',   'Septic shock',              'Critical'),
    (15, 'I-02', 4, INTERVAL '2 days',   'Respiratory failure',       'Critical'),
    (18, 'I-03', 4, INTERVAL '1 day',    'Post-operative monitoring', 'High'),
    ( 4, 'A-01', 5, INTERVAL '2 days',   'Typhoid',                   'Low'),
    ( 6, 'A-02', 5, INTERVAL '1 day',    'Appendicitis',              'Medium'),
    (11, 'A-03', 5, INTERVAL '3 days',   'Kidney stones',             'Medium'),
    (12, 'A-04', 5, INTERVAL '5 hours',  'Gastroenteritis',           'Low'),
    (14, 'B-01', 6, INTERVAL '2 days',   'Asthma exacerbation',       'Medium'),
    (16, 'B-02', 6, INTERVAL '1 day',    'Diabetic ketoacidosis',     'High')
) AS v(patient_id, bed_number, doctor_id, admitted_ago, diagnosis, severity)
JOIN beds b ON b.bed_number = v.bed_number;

-- Two beds that are out of use for other reasons.
UPDATE beds SET status = 'cleaning'    WHERE bed_number = 'E-05';
UPDATE beds SET status = 'maintenance' WHERE bed_number = 'A-08';

-- ---------- shifts and nurse assignments for today ----------
-- (the Cardiac Care Unit has no nurse on purpose: it shows up in the
--  staff-shortage alert and in v_patients_without_nurse)
-- Safe to run again: existing rows are skipped.
CREATE OR REPLACE PROCEDURE seed_todays_shifts()
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO shifts (staff_id, ward_id, shift_date, shift_type) VALUES
        ( 1, 1, CURRENT_DATE, 'Morning'),
        ( 7, 1, CURRENT_DATE, 'Morning'),
        ( 2, 2, CURRENT_DATE, 'Morning'),
        ( 3, 3, CURRENT_DATE, 'Morning'),
        ( 9, 3, CURRENT_DATE, 'Morning'),
        ( 4, 4, CURRENT_DATE, 'Morning'),
        ( 8, 4, CURRENT_DATE, 'Morning'),
        (11, 4, CURRENT_DATE, 'Morning'),
        ( 5, 5, CURRENT_DATE, 'Morning'),
        (10, 5, CURRENT_DATE, 'Morning'),
        ( 6, 6, CURRENT_DATE, 'Morning'),
        (10, 6, CURRENT_DATE, 'Evening')
    ON CONFLICT (staff_id, shift_date, shift_type) DO NOTHING;

    -- Every current patient gets the nurse who is on shift in their ward today.
    INSERT INTO nurse_assignments (admission_id, nurse_id, shift_date, shift_type)
    SELECT a.admission_id, sh.staff_id, sh.shift_date, sh.shift_type
    FROM   admissions a
    JOIN   beds   b  ON b.bed_id    = a.bed_id
    JOIN   rooms  r  ON r.room_id   = b.room_id
    JOIN   shifts sh ON sh.ward_id  = r.ward_id
                    AND sh.shift_date = CURRENT_DATE
    JOIN   staff  st ON st.staff_id = sh.staff_id
                    AND st.role     = 'Nurse'
    WHERE  a.discharged_at IS NULL
    ON CONFLICT (admission_id, shift_date, shift_type) DO NOTHING;
END;
$$;

CALL seed_todays_shifts();

-- ---------- extra alerts (the trigger already created occupancy / critical ones) ----------
INSERT INTO alerts (ward_id, alert_type, priority, message) VALUES
    (2, 'Staff Shortage', 'High', 'No nurse is assigned to the Cardiac Care Unit for the morning shift');

INSERT INTO alerts (ward_id, alert_type, priority, message, created_at, resolved_at) VALUES
    (4, 'Equipment', 'Medium', 'Ventilator 3 sent for maintenance',
        now() - INTERVAL '2 days', now() - INTERVAL '1 day');

-- ---------- AI forecasts for the next 3 days (synthetic demo values) ----------
INSERT INTO ai_predictions (ward_id, forecast_date, predicted_occupancy_pct, model_name)
SELECT v.ward_id, CURRENT_DATE + d, LEAST(100, v.base + 2 * d), 'LSTM-demo'
FROM (VALUES (1, 55), (2, 100), (3, 40), (4, 70), (5, 58), (6, 40)) AS v(ward_id, base)
CROSS JOIN generate_series(1, 3) AS d;

