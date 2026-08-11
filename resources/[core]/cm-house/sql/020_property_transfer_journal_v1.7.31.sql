-- cm-house v1.7.31 | durable, confirmed player-to-player property transfers.
CREATE TABLE IF NOT EXISTS `cm_house_transfer_journal` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `token` VARCHAR(128) NOT NULL,
  `house_id` INT NOT NULL,
  `seller_cid` INT NOT NULL,
  `buyer_cid` INT NOT NULL,
  `mode` ENUM('gift','sale') NOT NULL,
  `price` INT NOT NULL DEFAULT 0,
  `account` VARCHAR(32) NOT NULL DEFAULT 'bank',
  `status` VARCHAR(32) NOT NULL DEFAULT 'offered',
  `last_error` VARCHAR(255) NULL,
  `expires_at` DATETIME NOT NULL,
  `paid_at` DATETIME NULL,
  `completed_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_house_transfer_token` (`token`),
  KEY `idx_house_transfer_open` (`house_id`,`status`),
  KEY `idx_house_transfer_buyer` (`buyer_cid`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
