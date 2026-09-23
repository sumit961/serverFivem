-- ============================================================
-- cm-house | 021_align_g10_garage_slots.sql
-- Aligns the 10-car garage template slots with exact equal 3.90m
-- spacing and grid-aligned 90.0 / 270.0 headings.
-- ============================================================

UPDATE cm_house_garage_slots s
JOIN cm_house_garage_templates t ON t.id = s.template_id
SET s.coords = CASE s.slot_index
    WHEN 1  THEN JSON_OBJECT('x', 233.40, 'y', -1000.40, 'z', -99.605, 'h', 90.0)
    WHEN 2  THEN JSON_OBJECT('x', 233.40, 'y',  -996.50, 'z', -99.605, 'h', 90.0)
    WHEN 3  THEN JSON_OBJECT('x', 233.40, 'y',  -992.60, 'z', -99.605, 'h', 90.0)
    WHEN 4  THEN JSON_OBJECT('x', 233.40, 'y',  -988.70, 'z', -99.605, 'h', 90.0)
    WHEN 5  THEN JSON_OBJECT('x', 233.40, 'y',  -984.80, 'z', -99.605, 'h', 90.0)
    WHEN 6  THEN JSON_OBJECT('x', 223.60, 'y',  -996.50, 'z', -99.605, 'h', 270.0)
    WHEN 7  THEN JSON_OBJECT('x', 223.60, 'y',  -992.60, 'z', -99.605, 'h', 270.0)
    WHEN 8  THEN JSON_OBJECT('x', 223.60, 'y',  -988.70, 'z', -99.605, 'h', 270.0)
    WHEN 9  THEN JSON_OBJECT('x', 223.60, 'y',  -984.80, 'z', -99.605, 'h', 270.0)
    WHEN 10 THEN JSON_OBJECT('x', 223.60, 'y',  -980.90, 'z', -99.605, 'h', 270.0)
END
WHERE t.key_name = 'g10_10_space' AND s.slot_index BETWEEN 1 AND 10;

-- Fixed 2 exit points at the 2 physical garage doors
UPDATE cm_house_garage_templates
SET vehicle_exit = JSON_OBJECT('x', 225.00, 'y', -1006.40, 'z', -99.00, 'h', 180.0),
    vehicle_exits = JSON_ARRAY(
        JSON_OBJECT('x', 225.00, 'y', -1006.40, 'z', -99.00, 'h', 180.0),
        JSON_OBJECT('x', 232.00, 'y', -1006.40, 'z', -99.00, 'h', 180.0)
    )
WHERE key_name = 'g10_10_space';

