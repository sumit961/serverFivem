-- ============================================================
-- cm-house migration 010 | Phase 1 security/economy
-- Prevents two players buying the same property at the same time.
-- Safe to run more than once.
-- ============================================================

CREATE TABLE IF NOT EXISTS `cm_house_purchase_locks` (
  `house_id`     INT          NOT NULL PRIMARY KEY,
  `buyer_cid`    INT          NOT NULL,
  `buyer_source` INT          NOT NULL,
  `token`        VARCHAR(96)  NOT NULL,
  `price`        INT          NOT NULL,
  `account`      VARCHAR(32)  NOT NULL,
  `status`       VARCHAR(24)  NOT NULL DEFAULT 'reserved',
  `expires_at`   DATETIME     NOT NULL,
  `created_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_house_purchase_token` (`token`),
  INDEX `idx_house_purchase_buyer` (`buyer_cid`, `status`),
  INDEX `idx_house_purchase_expiry` (`status`, `expires_at`),
  CONSTRAINT `fk_house_purchase_house` FOREIGN KEY (`house_id`)
    REFERENCES `cm_houses` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELETE FROM `cm_house_purchase_locks`
WHERE `status` = 'reserved' AND `expires_at` < NOW();

SELECT 'cm-house migration 010 (security/economy) complete' AS status;
