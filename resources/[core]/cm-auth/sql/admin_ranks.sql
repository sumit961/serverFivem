CREATE TABLE IF NOT EXISTS admin_ranks (
    `level` TINYINT UNSIGNED NOT NULL,
    `name` VARCHAR(64) NOT NULL,
    `permissions` JSON NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`level`)
);

INSERT INTO admin_ranks (`level`, `name`, `permissions`) VALUES
(1, 'Helper', JSON_ARRAY('auth.lookup')),
(2, 'Trial Moderator', JSON_ARRAY('auth.lookup', 'auth.reset.ip')),
(3, 'Moderator', JSON_ARRAY('auth.lookup', 'auth.reset.ip', 'auth.reset.hwid')),
(4, 'Senior Moderator', JSON_ARRAY('auth.lookup', 'auth.reset.ip', 'auth.reset.hwid')),
(5, 'Administrator', JSON_ARRAY('auth.lookup', 'auth.reset.ip', 'auth.reset.hwid', 'auth.reset.socialclub')),
(6, 'Senior Admin', JSON_ARRAY('auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload')),
(7, 'Head Admin', JSON_ARRAY('auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload')),
(8, 'Community Manager', JSON_ARRAY('auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload')),
(9, 'Developer', JSON_ARRAY('auth.lookup', 'auth.reset.identifiers', 'auth.ranks.reload')),
(10, 'Owner', JSON_ARRAY('*'))
ON DUPLICATE KEY UPDATE
    `name` = VALUES(`name`),
    `permissions` = VALUES(`permissions`);
