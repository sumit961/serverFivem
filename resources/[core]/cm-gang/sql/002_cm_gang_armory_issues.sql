CREATE TABLE IF NOT EXISTS `cm_gang_armory_issues` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `issue_uid` VARCHAR(64) NOT NULL,
  `gang_id` VARCHAR(16) NOT NULL,
  `character_id` VARCHAR(64) NOT NULL,
  `item_id` VARCHAR(96) NOT NULL,
  `item_type` ENUM('weapon','ammo') NOT NULL,
  `quantity` INT UNSIGNED NOT NULL,
  `status` ENUM('issued','void') NOT NULL DEFAULT 'issued',
  `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_cm_gang_armory_issue_uid` (`issue_uid`),
  KEY `idx_cm_gang_armory_issue_limit` (`gang_id`,`character_id`,`item_id`,`status`),
  CONSTRAINT `fk_cm_gang_armory_issue_gang` FOREIGN KEY (`gang_id`) REFERENCES `cm_gangs` (`gang_id`),
  CONSTRAINT `chk_cm_gang_armory_issue_quantity` CHECK (`quantity` BETWEEN 1 AND 1000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO `cm_gang_migrations` (`migration_id`) VALUES ('002_cm_gang_armory_issues');
