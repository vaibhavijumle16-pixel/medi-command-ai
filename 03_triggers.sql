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
