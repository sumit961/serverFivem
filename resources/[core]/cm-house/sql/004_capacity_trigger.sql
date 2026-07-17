-- ============================================================
--  cm-house | Migration 004  |  Garage capacity, enforced by the database
--
--  !! RUN THIS IN HeidiSQL / phpMyAdmin / the mysql CLI -- NOT through the
--  !! FiveM server. DELIMITER is a client directive that oxmysql cannot parse.
--
--  Why it exists: the unique key already stops one car being in two garages,
--  but nothing stopped slot_index = 3 in a two-slot garage -- the row simply
--  does not know the template's capacity. Verified: without this, a 2-slot
--  garage happily accepted a 3rd car.
--
--  Spec 14.1: "A seven-car garage contains exactly seven saved vehicle
--  positions... It cannot accept an eighth assigned vehicle."
-- ============================================================

DROP TRIGGER IF EXISTS `trg_vslot_capacity_ins`;
DROP TRIGGER IF EXISTS `trg_vslot_capacity_upd`;

DELIMITER $$

CREATE TRIGGER `trg_vslot_capacity_ins`
BEFORE INSERT ON `cm_house_vehicle_slots`
FOR EACH ROW
BEGIN
    DECLARE cap INT DEFAULT 0;
    SELECT IFNULL(g.capacity, 0) INTO cap
    FROM cm_houses h
    LEFT JOIN cm_house_garage_templates g ON g.id = h.garage_template_id
    WHERE h.id = NEW.house_id;

    IF NEW.slot_index < 1 OR NEW.slot_index > cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'slot_index exceeds the garage template capacity';
    END IF;
END$$

CREATE TRIGGER `trg_vslot_capacity_upd`
BEFORE UPDATE ON `cm_house_vehicle_slots`
FOR EACH ROW
BEGIN
    DECLARE cap INT DEFAULT 0;
    SELECT IFNULL(g.capacity, 0) INTO cap
    FROM cm_houses h
    LEFT JOIN cm_house_garage_templates g ON g.id = h.garage_template_id
    WHERE h.id = NEW.house_id;

    IF NEW.slot_index < 1 OR NEW.slot_index > cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'slot_index exceeds the garage template capacity';
    END IF;
END$$

DELIMITER ;
