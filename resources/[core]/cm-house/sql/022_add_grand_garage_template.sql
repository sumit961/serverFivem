-- ============================================================
-- cm-house | 022_add_grand_garage_template.sql
-- Registers Grand Garage MLO at (-463.7884, -849.8669, 9.7062)
-- as a 10-car garage template with 10 physical aligned slots.
-- Safe to run repeatedly.
-- ============================================================

INSERT INTO `cm_house_garage_templates` (
    `key_name`,
    `label`,
    `version`,
    `enabled`,
    `source_kind`,
    `source_ref`,
    `player_entry`,
    `house_door`,
    `vehicle_exit`,
    `vehicle_exits`,
    `capacity`,
    `notes`
) VALUES (
    'grand_garage',
    'Grand Garage (10 Space)',
    1,
    1,
    'world',
    'grand_garage',
    JSON_OBJECT('x', -463.7884, 'y', -849.8669, 'z', 9.7062, 'h', 90.0),
    JSON_OBJECT('x', -463.7884, 'y', -849.8669, 'z', 9.7062, 'h', 270.0),
    JSON_OBJECT('x', -463.7884, 'y', -849.8669, 'z', 9.7062, 'h', 270.0),
    JSON_ARRAY(
        JSON_OBJECT('x', -463.7884, 'y', -849.8669, 'z', 9.7062, 'h', 270.0),
        JSON_OBJECT('x', -463.7884, 'y', -846.8669, 'z', 9.7062, 'h', 270.0)
    ),
    10,
    'Grand Garage MLO 10-space world garage'
) ON DUPLICATE KEY UPDATE
    `label` = VALUES(`label`),
    `enabled` = 1,
    `source_kind` = VALUES(`source_kind`),
    `source_ref` = VALUES(`source_ref`),
    `player_entry` = VALUES(`player_entry`),
    `house_door` = VALUES(`house_door`),
    `vehicle_exit` = VALUES(`vehicle_exit`),
    `vehicle_exits` = VALUES(`vehicle_exits`),
    `capacity` = 10;

-- Ensure slots 1 to 10 exist and are aligned for grand_garage
SET @grandTplId := (SELECT id FROM cm_house_garage_templates WHERE key_name = 'grand_garage' LIMIT 1);

INSERT INTO cm_house_garage_slots (template_id, slot_index, coords)
VALUES
    (@grandTplId, 1,  JSON_OBJECT('x', -455.06, 'y', -837.14, 'z', 9.230, 'h',  90.0)),
    (@grandTplId, 2,  JSON_OBJECT('x', -455.06, 'y', -841.14, 'z', 9.230, 'h',  90.0)),
    (@grandTplId, 3,  JSON_OBJECT('x', -455.06, 'y', -845.16, 'z', 9.230, 'h',  90.0)),
    (@grandTplId, 4,  JSON_OBJECT('x', -455.06, 'y', -849.24, 'z', 9.230, 'h',  90.0)),
    (@grandTplId, 5,  JSON_OBJECT('x', -455.06, 'y', -853.24, 'z', 9.230, 'h',  90.0)),
    (@grandTplId, 6,  JSON_OBJECT('x', -450.48, 'y', -853.24, 'z', 9.230, 'h', 270.0)),
    (@grandTplId, 7,  JSON_OBJECT('x', -450.48, 'y', -849.26, 'z', 9.230, 'h', 270.0)),
    (@grandTplId, 8,  JSON_OBJECT('x', -450.48, 'y', -845.16, 'z', 9.230, 'h', 270.0)),
    (@grandTplId, 9,  JSON_OBJECT('x', -450.48, 'y', -841.14, 'z', 9.230, 'h', 270.0)),
    (@grandTplId, 10, JSON_OBJECT('x', -450.48, 'y', -837.14, 'z', 9.230, 'h', 270.0))
ON DUPLICATE KEY UPDATE
    coords = VALUES(coords);

