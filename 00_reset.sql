-- =====================================================================
-- 00_reset.sql  (OPTIONAL, DESTRUCTIVE)
-- Drops every object created by this project so you can start over.
-- WARNING: this deletes all data in these tables. Do NOT run it on a
-- database that already has tables with the same names that you want to keep.
-- =====================================================================

DROP VIEW IF EXISTS v_patients_without_nurse CASCADE;
DROP VIEW IF EXISTS v_nurse_workload         CASCADE;
DROP VIEW IF EXISTS v_bed_map                CASCADE;
DROP VIEW IF EXISTS v_ward_forecast          CASCADE;
DROP VIEW IF EXISTS v_open_alerts            CASCADE;
DROP VIEW IF EXISTS v_current_patients       CASCADE;
DROP VIEW IF EXISTS v_ward_occupancy         CASCADE;

DROP TABLE IF EXISTS ai_predictions    CASCADE;
DROP TABLE IF EXISTS alerts            CASCADE;
DROP TABLE IF EXISTS nurse_assignments CASCADE;
DROP TABLE IF EXISTS shifts            CASCADE;
DROP TABLE IF EXISTS admissions        CASCADE;
DROP TABLE IF EXISTS patients          CASCADE;
DROP TABLE IF EXISTS staff             CASCADE;
DROP TABLE IF EXISTS beds              CASCADE;
DROP TABLE IF EXISTS rooms             CASCADE;
DROP TABLE IF EXISTS wards             CASCADE;
DROP TABLE IF EXISTS departments       CASCADE;

DROP FUNCTION  IF EXISTS check_admission()            CASCADE;
DROP FUNCTION  IF EXISTS check_nurse_assignment()     CASCADE;
DROP FUNCTION  IF EXISTS on_admission_created()       CASCADE;
DROP FUNCTION  IF EXISTS on_admission_discharged()    CASCADE;
DROP FUNCTION  IF EXISTS admit_patient(INT, INT, INT, TEXT, TEXT);
DROP FUNCTION  IF EXISTS assign_nurse(INT, INT, TEXT, DATE);
DROP PROCEDURE IF EXISTS discharge_patient(INT);
DROP PROCEDURE IF EXISTS seed_todays_shifts();
DROP FUNCTION  IF EXISTS ward_occupancy_pct(INT);
