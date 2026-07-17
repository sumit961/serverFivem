-- cm-house v1.7.4 | durable recovery for failed weapon-storage transfers.
--
-- When a deposit removes a weapon from the player but the locker insert fails
-- AND returning the item to the player also fails, the item would otherwise be
-- lost. We instead write a durable row here so an admin can restore it.

CREATE TABLE IF NOT EXISTS `cm_house_weapon_recovery` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `house_id`    INT UNSIGNED NULL,
  `point_index` INT NULL,
  `character_id` VARCHAR(64) NULL,
  `src_player`  INT NULL,
  `item_name`   VARCHAR(128) NOT NULL,
  `amount`      INT NOT NULL DEFAULT 1,
  `metadata`    LONGTEXT NULL,
  `reason`      VARCHAR(255) NULL,
  `resolved`    TINYINT(1) NOT NULL DEFAULT 0,
  `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_recovery_char` (`character_id`),
  KEY `idx_recovery_open` (`resolved`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
