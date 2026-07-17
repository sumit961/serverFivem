-- ============================================================
-- cm-family v1.0.5 | legacy rank grade compatibility
--
-- No destructive schema or data rewrite is required. Runtime v1.0.5 detects
-- an existing `grade` column and writes every new rank to both `tier` and
-- `grade`, satisfying legacy `uq_rank_grade (family_id, grade)` indexes.
--
-- Run this diagnostic after installing v1.0.5 if desired. A result of 1 means
-- the legacy column exists and runtime dual-write compatibility will be used.
-- ============================================================
SELECT EXISTS (
    SELECT 1
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'cm_family_ranks'
      AND COLUMN_NAME = 'grade'
) AS legacy_grade_detected;
