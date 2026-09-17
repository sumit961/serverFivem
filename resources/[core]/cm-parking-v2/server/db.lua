local function ensure()
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_parking_spaces (id BIGINT AUTO_INCREMENT PRIMARY KEY, character_id VARCHAR(100) NOT NULL, parking_id VARCHAR(64) NOT NULL, spot_index INT NOT NULL, vehicle_id BIGINT NULL, price_paid INT NOT NULL DEFAULT 0, expires_at DATETIME NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE KEY uq_parking_spot (parking_id,spot_index), UNIQUE KEY uq_parking_vehicle (vehicle_id), KEY idx_character (character_id))]])
 local exists=MySQL.scalar.await("SHOW COLUMNS FROM cm_parking_spaces LIKE 'vehicle_id'")
 if not exists then MySQL.query.await('ALTER TABLE cm_parking_spaces ADD COLUMN vehicle_id BIGINT NULL AFTER spot_index') end
 local index=MySQL.scalar.await("SHOW INDEX FROM cm_parking_spaces WHERE Key_name='uq_parking_vehicle'")
 if not index then MySQL.query.await('ALTER TABLE cm_parking_spaces ADD UNIQUE KEY uq_parking_vehicle (vehicle_id)') end
 local characterIndex=MySQL.scalar.await("SHOW INDEX FROM cm_parking_spaces WHERE Key_name='uq_character'")
 if not characterIndex then
  MySQL.query.await([[DELETE p1 FROM cm_parking_spaces p1 INNER JOIN cm_parking_spaces p2 ON p1.character_id=p2.character_id AND p1.id<p2.id]])
  MySQL.query.await('ALTER TABLE cm_parking_spaces ADD UNIQUE KEY uq_character (character_id)')
 end
 local price=MySQL.scalar.await("SHOW COLUMNS FROM cm_parking_spaces LIKE 'price_paid'")
 if not price then MySQL.query.await('ALTER TABLE cm_parking_spaces ADD COLUMN price_paid INT NOT NULL DEFAULT 0 AFTER vehicle_id') end
 local expires=MySQL.scalar.await("SHOW COLUMNS FROM cm_parking_spaces LIKE 'expires_at'")
 if not expires then MySQL.query.await('ALTER TABLE cm_parking_spaces ADD COLUMN expires_at DATETIME NULL AFTER price_paid') end

 -- Parking lot business ownership table
 MySQL.query.await([[
  CREATE TABLE IF NOT EXISTS cm_parking_lots (
    parking_id VARCHAR(64) PRIMARY KEY,
    owner_character_id VARCHAR(100) NULL,
    owner_name VARCHAR(120) NULL,
    price_tier VARCHAR(20) NOT NULL DEFAULT 'normal',
    price_per_spot INT NOT NULL DEFAULT 2500,
    business_balance INT NOT NULL DEFAULT 0,
    daily_income INT NOT NULL DEFAULT 0,
    weekly_income INT NOT NULL DEFAULT 0,
    purchased_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY idx_owner (owner_character_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
 ]])

 for _, g in ipairs(Config.Parking or {}) do
  if g.id then
   MySQL.query.await([[
    INSERT INTO cm_parking_lots (parking_id, price_tier, price_per_spot)
    VALUES (?, 'normal', 2500)
    ON DUPLICATE KEY UPDATE parking_id = parking_id
   ]], { g.id })
  end
 end
end
CreateThread(ensure)
