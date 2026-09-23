-- CM-LAW shared BOLO board, dispatch CCTV cameras, and booking fines.
-- Additive and repeatable. The resource also creates/alters these at boot
-- (server/bolo.lua, server/dispatch_cameras.lua, server/booking.lua);
-- production operators may apply this migration explicitly ahead of time.
CREATE TABLE IF NOT EXISTS cm_legal_bolos (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  plate VARCHAR(16) NOT NULL,
  description VARCHAR(200) NOT NULL,
  organization_id VARCHAR(32) NOT NULL,
  author_cid VARCHAR(64) NOT NULL,
  status ENUM('active','cleared') NOT NULL DEFAULT 'active',
  cleared_by VARCHAR(64) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  cleared_at TIMESTAMP NULL,
  PRIMARY KEY(id),
  KEY idx_cm_legal_bolos_plate (plate, status),
  KEY idx_cm_legal_bolos_status (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cm_legal_dispatch_cameras (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organization_id VARCHAR(32) NOT NULL,
  label VARCHAR(64) NOT NULL,
  x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading FLOAT NOT NULL DEFAULT 0,
  created_by VARCHAR(64) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY(id),
  KEY idx_cm_legal_dispatch_cameras_org (organization_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE cm_legal_bookings ADD COLUMN IF NOT EXISTS fine_amount INT UNSIGNED NOT NULL DEFAULT 0;
