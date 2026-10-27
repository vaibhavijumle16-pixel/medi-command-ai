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
