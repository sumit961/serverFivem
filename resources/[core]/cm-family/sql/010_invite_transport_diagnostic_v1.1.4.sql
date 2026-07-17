-- cm-family v1.1.4 optional diagnostic. No destructive migration is required.
SELECT COLUMN_NAME, COLUMN_TYPE, COLUMN_KEY, COLUMN_DEFAULT, IS_NULLABLE, EXTRA
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'cm_family_invites'
ORDER BY ORDINAL_POSITION;

SELECT id, family_id, character_id, invited_by, rank_id, expires_at, NOW() AS database_now, created_at
FROM cm_family_invites
ORDER BY created_at DESC
LIMIT 20;
