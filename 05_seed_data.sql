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
