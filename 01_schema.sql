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
