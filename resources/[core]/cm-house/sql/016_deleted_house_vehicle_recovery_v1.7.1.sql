-- cm-house v1.7.1
-- Recover vehicles that still point at a property which no longer exists.

UPDATE cm_owned_vehicles v
LEFT JOIN cm_houses h
  ON h.id = CAST(SUBSTRING_INDEX(COALESCE(NULLIF(v.garage, ''), NULLIF(v.location_ref, ''), ''), ':', -1) AS UNSIGNED)
SET v.is_stored = 0,
    v.garage = NULL,
    v.parking_id = NULL,
    v.parked_at = NULL,
    v.last_position = NULL,
    v.location_state = 'OUTSIDE',
    v.location_ref = NULL,
    v.location_slot = NULL,
    v.location_updated_at = NOW()
WHERE ((v.garage REGEXP '^house:[0-9]+$') OR v.location_state = 'HOUSE_GARAGE')
  AND h.id IS NULL;

DELETE sh
FROM cm_house_shared_vehicles sh
LEFT JOIN cm_houses h ON h.id = sh.house_id
WHERE h.id IS NULL;
