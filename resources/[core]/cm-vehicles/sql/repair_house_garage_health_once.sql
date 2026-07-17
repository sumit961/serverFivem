-- ============================================================
-- cm-vehicles v3.3.0 | LEGACY CONDITION DIAGNOSTIC ONLY
-- ============================================================
-- IMPORTANT:
-- Numeric 0 is now a valid destroyed vehicle component. This file performs
-- NO automatic UPDATE and must not convert 0/1 values to 1000.
--
-- Safe entity creation uses temporary bootstrap health in memory, then applies
-- the real saved database condition after the network vehicle is initialized.

-- Review damaged house vehicles. Zero is valid and should remain zero unless an
-- administrator intentionally repairs that specific vehicle.
SELECT id, plate, model, garage,
       engine_health, body_health, tank_health, condition_state
FROM cm_owned_vehicles
WHERE is_stored = 1
  AND garage LIKE 'house:%'
  AND (engine_health <= 150 OR body_health <= 150 OR tank_health <= 150)
ORDER BY garage, id;

-- Review truly invalid out-of-range values. The runtime clamps these safely,
-- but operators may decide how to repair the source data after inspection.
SELECT id, plate, model, garage,
       engine_health, body_health, tank_health
FROM cm_owned_vehicles
WHERE engine_health < 0 OR engine_health > 1000
   OR body_health < 0 OR body_health > 1000
   OR tank_health < 0 OR tank_health > 1000
ORDER BY id;

-- Example of an EXPLICIT, vehicle-specific administrator repair:
-- UPDATE cm_owned_vehicles
-- SET engine_health = 1000, body_health = 1000, tank_health = 1000,
--     condition_state = JSON_OBJECT()
-- WHERE id = 12345;
