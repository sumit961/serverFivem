-- CM License System -- constraint correction for installations created by v1.
-- Review duplicate character/type rows before applying to a populated database.

ALTER TABLE cm_character_licenses
    DROP INDEX IF EXISTS unique_character_active_license,
    ADD UNIQUE INDEX IF NOT EXISTS unique_character_license (character_id, license_type_id);

ALTER TABLE cm_license_active_tests
    DROP INDEX IF EXISTS unique_active_test;
