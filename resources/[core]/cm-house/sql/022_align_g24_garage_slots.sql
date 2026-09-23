-- ============================================================
-- cm-house | 022_align_g24_garage_slots.sql
-- Removes temporary 10-space grand_garage and aligns all 24 slots
-- in g24_24_space with equal 4.20m spacing and cardinal headings.
-- Result: exactly 2 garage templates (g10_10_space and g24_24_space).
-- Safe to run repeatedly.
-- ============================================================

-- Remove the temporary 10-space grand_garage template if present
DELETE FROM `cm_house_garage_templates` WHERE `key_name` = 'grand_garage';

-- Ensure g24_24_space has capacity 24 and is enabled
UPDATE `cm_house_garage_templates`
SET `capacity` = 24, `enabled` = 1
WHERE `key_name` = 'g24_24_space';

-- Align all 24 slots with equal 4.20m spacing and aligned headings
UPDATE cm_house_garage_slots s
JOIN cm_house_garage_templates t ON t.id = s.template_id
SET s.coords = CASE s.slot_index
    -- Row 2 (facing 90.0°)
    WHEN 1  THEN JSON_OBJECT('x', -458.70, 'y', -822.50, 'z', 8.693, 'h', 90.0)
    WHEN 2  THEN JSON_OBJECT('x', -458.70, 'y', -826.70, 'z', 8.693, 'h', 90.0)
    WHEN 3  THEN JSON_OBJECT('x', -458.70, 'y', -830.90, 'z', 8.693, 'h', 90.0)
    WHEN 4  THEN JSON_OBJECT('x', -458.70, 'y', -835.10, 'z', 8.693, 'h', 90.0)
    WHEN 5  THEN JSON_OBJECT('x', -458.70, 'y', -839.30, 'z', 8.693, 'h', 90.0)
    WHEN 12 THEN JSON_OBJECT('x', -458.70, 'y', -843.50, 'z', 8.693, 'h', 90.0)
    -- Row 3 (facing 270.0°)
    WHEN 6  THEN JSON_OBJECT('x', -446.50, 'y', -822.50, 'z', 8.693, 'h', 270.0)
    WHEN 7  THEN JSON_OBJECT('x', -446.50, 'y', -826.70, 'z', 8.693, 'h', 270.0)
    WHEN 8  THEN JSON_OBJECT('x', -446.50, 'y', -830.90, 'z', 8.693, 'h', 270.0)
    WHEN 9  THEN JSON_OBJECT('x', -446.50, 'y', -835.10, 'z', 8.693, 'h', 270.0)
    WHEN 10 THEN JSON_OBJECT('x', -446.50, 'y', -839.30, 'z', 8.693, 'h', 270.0)
    WHEN 11 THEN JSON_OBJECT('x', -446.50, 'y', -843.50, 'z', 8.693, 'h', 270.0)
    -- Row 1 (facing 270.0°)
    WHEN 13 THEN JSON_OBJECT('x', -471.40, 'y', -822.50, 'z', 8.693, 'h', 270.0)
    WHEN 14 THEN JSON_OBJECT('x', -471.40, 'y', -826.70, 'z', 8.693, 'h', 270.0)
    WHEN 15 THEN JSON_OBJECT('x', -471.40, 'y', -830.90, 'z', 8.693, 'h', 270.0)
    WHEN 16 THEN JSON_OBJECT('x', -471.40, 'y', -835.10, 'z', 8.693, 'h', 270.0)
    WHEN 17 THEN JSON_OBJECT('x', -471.40, 'y', -839.30, 'z', 8.693, 'h', 270.0)
    WHEN 18 THEN JSON_OBJECT('x', -471.40, 'y', -843.50, 'z', 8.693, 'h', 270.0)
    -- Row 4 (facing 90.0°)
    WHEN 24 THEN JSON_OBJECT('x', -434.70, 'y', -822.50, 'z', 8.693, 'h', 90.0)
    WHEN 23 THEN JSON_OBJECT('x', -434.70, 'y', -826.70, 'z', 8.693, 'h', 90.0)
    WHEN 22 THEN JSON_OBJECT('x', -434.70, 'y', -830.90, 'z', 8.693, 'h', 90.0)
    WHEN 21 THEN JSON_OBJECT('x', -434.70, 'y', -835.10, 'z', 8.693, 'h', 90.0)
    WHEN 20 THEN JSON_OBJECT('x', -434.70, 'y', -839.30, 'z', 8.693, 'h', 90.0)
    WHEN 19 THEN JSON_OBJECT('x', -434.70, 'y', -843.50, 'z', 8.693, 'h', 90.0)
END
WHERE t.key_name = 'g24_24_space' AND s.slot_index BETWEEN 1 AND 24;

