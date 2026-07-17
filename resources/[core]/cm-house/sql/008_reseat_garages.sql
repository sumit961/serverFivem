-- ============================================================
--  cm-house | Migration 008  |  Repair the garage seating chart
--
--  THE DRIFT.
--    cm-vehicles says a car is parked here:  garage = 'house:6', is_stored = 1
--    cm-house says which space it sits in:   cm_house_vehicle_slots.vehicle_id
--
--  When those disagree the car is REAL but INVISIBLE. GarageState builds its
--  spawn list from a JOIN on the seating chart, so a car with no seat has
--  slot_index = NULL and is silently dropped -- while a car that DOES have a
--  seat is respawned on every refresh.
--
--  That is why one car appeared over and over while the others never showed:
--  only that one still had a seat.
--
--  Safe to run repeatedly.
-- ============================================================

-- ---------- 1. Clear only invalid/conflicting reservations ----------
-- is_stored = 0 is VALID: it means the assigned vehicle is currently outside
-- and may later be recalled into this same space.
UPDATE `cm_house_vehicle_slots` s
LEFT JOIN `cm_owned_vehicles` v ON v.id = s.vehicle_id
SET s.vehicle_id = NULL, s.assigned_by = NULL, s.assigned_at = NULL
WHERE s.vehicle_id IS NOT NULL
  AND (
        v.id IS NULL                                   -- the car no longer exists
     OR (v.is_stored = 1
         AND v.garage LIKE 'house:%'
         AND v.garage <> CONCAT('house:', s.house_id)) -- conflicting house claim
  );

-- ---------- 2. Seat the cars that are here but homeless ----------
DROP PROCEDURE IF EXISTS `cm_house_reseat_garages`;

DELIMITER $$
CREATE PROCEDURE `cm_house_reseat_garages`()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_id INT;
    DECLARE v_house INT;
    DECLARE v_slot INT;

    DECLARE cur CURSOR FOR
        SELECT v.id, CAST(SUBSTRING(v.garage, 7) AS UNSIGNED) AS house_id
        FROM cm_owned_vehicles v
        WHERE v.is_stored = 1
          AND v.garage LIKE 'house:%'
          AND NOT EXISTS (
              SELECT 1 FROM cm_house_vehicle_slots s WHERE s.vehicle_id = v.id
          );

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_id, v_house;
        IF done THEN LEAVE read_loop; END IF;

        SET v_slot = (
            SELECT MIN(s.slot_index) FROM cm_house_vehicle_slots s
            WHERE s.house_id = v_house AND s.vehicle_id IS NULL
        );

        IF v_slot IS NOT NULL THEN
            UPDATE cm_house_vehicle_slots
            SET vehicle_id = v_id, owner_class = 'personal', assigned_at = NOW()
            WHERE house_id = v_house AND slot_index = v_slot AND vehicle_id IS NULL;
        ELSE
            -- Garage full. Release the car rather than strand it somewhere it
            -- can never be retrieved from. It stays owned.
            UPDATE cm_owned_vehicles SET is_stored = 0, garage = NULL, parking_id = NULL, parked_at = NULL WHERE id = v_id;
        END IF;
    END LOOP;
    CLOSE cur;
END$$
DELIMITER ;

CALL `cm_house_reseat_garages`();
DROP PROCEDURE `cm_house_reseat_garages`;

SELECT
    (SELECT COUNT(*) FROM cm_owned_vehicles
      WHERE is_stored = 1 AND garage LIKE 'house:%')          AS cars_in_garages,
    (SELECT COUNT(*) FROM cm_house_vehicle_slots
      WHERE vehicle_id IS NOT NULL)                            AS seats_taken,
    (SELECT COUNT(*) FROM cm_owned_vehicles v
      WHERE v.is_stored = 1 AND v.garage LIKE 'house:%'
        AND NOT EXISTS (SELECT 1 FROM cm_house_vehicle_slots s
                        WHERE s.vehicle_id = v.id))            AS still_homeless;

SELECT 'cm-house migration 008 (reseat garages) complete' AS status;
