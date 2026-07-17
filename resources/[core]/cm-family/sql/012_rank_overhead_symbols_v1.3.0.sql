-- cm-family v1.3.0
-- Rank-controlled symbol-only overhead identity. Non-destructive.

ALTER TABLE `cm_family_ranks`
  ADD COLUMN IF NOT EXISTS `overhead_symbol` VARCHAR(16) NOT NULL DEFAULT 'shield' AFTER `name`,
  ADD COLUMN IF NOT EXISTS `overhead_color` VARCHAR(9) NULL AFTER `overhead_symbol`;

-- Assign polished defaults only to rows that have never been configured.
UPDATE `cm_family_ranks`
SET `overhead_symbol` = CASE
      WHEN `is_founder` = 1 THEN 'crown'
      WHEN COALESCE(`tier`, 1) >= 10 THEN 'shield'
      WHEN COALESCE(`tier`, 1) >= 5 THEN 'star'
      ELSE 'flower'
    END,
    `overhead_color` = CASE
      WHEN `is_founder` = 1 THEN '#ffd76a'
      WHEN COALESCE(`tier`, 1) >= 10 THEN '#00f0ff'
      WHEN COALESCE(`tier`, 1) >= 5 THEN '#75e6ff'
      ELSE '#9be7ff'
    END
WHERE `overhead_color` IS NULL OR `overhead_color` = '';
