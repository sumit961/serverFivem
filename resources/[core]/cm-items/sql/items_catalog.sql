-- Generic item catalog: the single source of truth for dynamically-created items
-- (armor vests, custom weapons, event items, future types). Clothing keeps its own
-- richer clothing_catalog table; this is for everything else and for items that other
-- resources (cm-gunstore, events) create at runtime.
CREATE TABLE IF NOT EXISTS cm_items_catalog (
    name         VARCHAR(80)  NOT NULL PRIMARY KEY,
    label        VARCHAR(120) NOT NULL,
    category     VARCHAR(60)  NOT NULL DEFAULT 'misc',
    item_type    VARCHAR(40)  NOT NULL DEFAULT 'normal',  -- normal | unique | rare
    image        VARCHAR(255) NULL,                        -- full nui:// path or filename in cm-items
    weight       INT          NOT NULL DEFAULT 0,
    stack        TINYINT(1)   NOT NULL DEFAULT 1,
    usable       TINYINT(1)   NOT NULL DEFAULT 1,
    equipment_slot VARCHAR(40) NULL,                       -- e.g. bodyarmor, weapon
    armor_value  INT          NULL,                        -- for armor/vests
    description  TEXT         NULL,
    metadata     LONGTEXT     NULL,                        -- JSON: type-specific fields
    enabled      TINYINT(1)   NOT NULL DEFAULT 1,
    created_by   VARCHAR(100) NULL,
    updated_by   VARCHAR(100) NULL,
    created_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_enabled (enabled)
);
