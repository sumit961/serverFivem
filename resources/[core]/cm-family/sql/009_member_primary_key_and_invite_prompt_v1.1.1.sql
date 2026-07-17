-- cm-family v1.1.1
-- Legacy cm_family_members primary-key compatibility diagnostic.
-- The Lua resource now supports non-AUTO_INCREMENT text/numeric `id` columns
-- without destructive table changes. This SQL is optional and only reports the
-- installed member-table layout.

SELECT COLUMN_NAME, COLUMN_TYPE, COLUMN_KEY, COLUMN_DEFAULT, IS_NULLABLE, EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'cm_family_members'
ORDER BY ORDINAL_POSITION;
