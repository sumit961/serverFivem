-- ============================================================
--  cm-family | sv_schema.lua | v1.1.6
--  Legacy-safe, idempotent database bootstrap and validation.
--
--  Important compatibility rule:
--  Older cm_families tables may use a signed INT, BIGINT, a different engine,
--  or another otherwise valid legacy definition for `id`. MySQL requires an
--  FK child column to match the parent exactly and both tables to use a
--  compatible engine. A strict CREATE TABLE ... FOREIGN KEY therefore makes
--  startup fail with errno 150 even though the family data itself is usable.
--
--  cm-family v1.0.5 creates/repairs child tables without hard FK constraints
--  and performs family deletion through one explicit DB transaction instead.
--  Existing valid foreign keys are left untouched.
-- ============================================================

CMFamilyDatabaseReady = false
CMFamilyDatabaseError = 'initializing'

-- Some older cm-family schemas store rank JSON in `perms` rather than
-- `permissions`. When both columns exist, rank writes must keep both valid or
-- MariaDB's automatic JSON CHECK on `perms` rejects the entire insert.
CMFamilyUsesLegacyPermsColumn = false
CMFamilyLegacyPermsFormat = 'object'
CMFamilyUsesLegacyGradeColumn = false

-- Legacy member tables may contain an `id` primary key that is NOT
-- AUTO_INCREMENT. Omitting it makes MariaDB insert the column default (often
-- an empty string), so the second member fails with `Duplicate entry '' for
-- key PRIMARY`. The detected layout is used by CMFamilyInsertMember below.
CMFamilyMemberIdMode = { present = false, autoIncrement = false, numeric = false, maxLength = nil }
CMFamilyInviteIdMode = { present = false, autoIncrement = false, numeric = false, maxLength = nil }
CMFamilyMemberLayout = { columns = {}, ordered = {}, requiredLegacy = {} }

-- Return the effective authority tier for a rank row. Older schemas called
-- this column `grade`; when that column exists it remains authoritative so
-- pre-existing ranks do not all collapse onto the additive tier default.
function CMFamilyRankTier(row)
    if type(row) ~= 'table' then return nil end
    if CMFamilyUsesLegacyGradeColumn and row.grade ~= nil then
        return tonumber(row.grade)
    end
    return tonumber(row.tier)
end

function CMFamilyIsDatabaseReady()
    return CMFamilyDatabaseReady == true, CMFamilyDatabaseError
end

exports('IsDatabaseReady', function()
    return CMFamilyIsDatabaseReady()
end)

local CREATE_PARENT_TABLE = [[
    CREATE TABLE IF NOT EXISTS `cm_families` (
      `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `name`          VARCHAR(64) NOT NULL,
      `tag`           VARCHAR(8) NULL,
      `color`         VARCHAR(9) NOT NULL DEFAULT '#00f0ff',
      `symbol`        VARCHAR(16) NOT NULL DEFAULT 'shield',
      `tag_visible`   TINYINT(1) NOT NULL DEFAULT 1,
      `founder_cid`   VARCHAR(64) NOT NULL,
      `house_id`      INT UNSIGNED NULL,
      `bank_balance`  BIGINT NOT NULL DEFAULT 0,
      `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      UNIQUE KEY `uniq_family_name` (`name`),
      KEY `idx_family_founder` (`founder_cid`),
      KEY `idx_family_house` (`house_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
]]

-- No FOREIGN KEY clauses here. See the compatibility note above. All tables
-- still have indexed family_id columns, and CMFamilyDeleteFamilyRows performs
-- atomic child-first cleanup.
local CREATE_CHILD_TABLES = {
    [[
        CREATE TABLE IF NOT EXISTS `cm_family_ranks` (
          `id`               INT UNSIGNED NOT NULL AUTO_INCREMENT,
          `family_id`        BIGINT UNSIGNED NOT NULL,
          `tier`             TINYINT UNSIGNED NOT NULL,
          `name`             VARCHAR(48) NOT NULL,
          `overhead_symbol`  VARCHAR(16) NOT NULL DEFAULT 'shield',
          `overhead_color`   VARCHAR(9) NULL,
          `permissions`      JSON NOT NULL,
          `is_founder`       TINYINT(1) NOT NULL DEFAULT 0,
          `bank_daily_limit` BIGINT NOT NULL DEFAULT 0,
          `created_at`       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uniq_family_tier` (`family_id`, `tier`),
          KEY `idx_rank_family` (`family_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `cm_family_members` (
          `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
          `family_id`    BIGINT UNSIGNED NOT NULL,
          `character_id` VARCHAR(64) NOT NULL,
          `rank_id`      BIGINT UNSIGNED NOT NULL,
          `custom_title` VARCHAR(24) NULL,
          `tag_hidden`   TINYINT(1) NOT NULL DEFAULT 0,
          `joined_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uniq_member_character` (`character_id`),
          KEY `idx_member_family` (`family_id`),
          KEY `idx_member_rank` (`rank_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `cm_family_invites` (
          `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
          `family_id`    BIGINT UNSIGNED NOT NULL,
          `character_id` VARCHAR(64) NOT NULL,
          `invited_by`   VARCHAR(64) NOT NULL,
          `rank_id`      BIGINT UNSIGNED NULL,
          `expires_at`   TIMESTAMP NULL,
          `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uniq_invite` (`family_id`, `character_id`),
          KEY `idx_invite_character` (`character_id`),
          KEY `idx_invite_family` (`family_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `cm_family_vehicle_access` (
          `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
          `family_id`   BIGINT UNSIGNED NOT NULL,
          `vehicle_id`  BIGINT UNSIGNED NOT NULL,
          `level`       TINYINT UNSIGNED NOT NULL DEFAULT 1,
          `updated_by`  VARCHAR(64) NULL,
          `updated_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uniq_family_vehicle` (`family_id`, `vehicle_id`),
          KEY `idx_vaccess_family` (`family_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `cm_family_bank_log` (
          `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
          `family_id`     BIGINT UNSIGNED NOT NULL,
          `character_id`  VARCHAR(64) NULL,
          `direction`     ENUM('deposit','withdraw') NOT NULL,
          `amount`        BIGINT NOT NULL,
          `balance_after` BIGINT NOT NULL,
          `reason`        VARCHAR(128) NULL,
          `created_at`    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_banklog_family` (`family_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `cm_family_log` (
          `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
          `family_id`    BIGINT UNSIGNED NOT NULL,
          `actor_cid`    VARCHAR(64) NULL,
          `action`       VARCHAR(48) NOT NULL,
          `detail`       JSON NULL,
          `created_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_log_family` (`family_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
    [[
        CREATE TABLE IF NOT EXISTS `cm_family_activity_log` (
          `id`              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `event_uid`       VARCHAR(96) NOT NULL,
          `family_id`       BIGINT UNSIGNED NOT NULL,
          `category`        VARCHAR(32) NOT NULL DEFAULT 'family',
          `action`          VARCHAR(64) NOT NULL,
          `severity`        VARCHAR(16) NOT NULL DEFAULT 'info',
          `high_risk`       TINYINT(1) NOT NULL DEFAULT 0,
          `status`          VARCHAR(16) NOT NULL DEFAULT 'success',
          `actor_cid`       VARCHAR(64) NULL,
          `actor_name`      VARCHAR(128) NULL,
          `target_cid`      VARCHAR(64) NULL,
          `target_name`     VARCHAR(128) NULL,
          `source_resource` VARCHAR(64) NOT NULL DEFAULT 'cm-family',
          `entity_type`     VARCHAR(32) NULL,
          `entity_id`       VARCHAR(96) NULL,
          `house_id`        BIGINT UNSIGNED NULL,
          `vehicle_id`      BIGINT UNSIGNED NULL,
          `amount`          BIGINT NULL,
          `detail`          JSON NULL,
          `created_at`      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uniq_family_activity_uid` (`event_uid`),
          KEY `idx_family_activity_family_time` (`family_id`, `created_at`),
          KEY `idx_family_activity_high_time` (`high_risk`, `created_at`),
          KEY `idx_family_activity_action` (`action`),
          KEY `idx_family_activity_actor` (`actor_cid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]],
}

-- Additive repairs are ordered so AFTER references always exist. Nullable or
-- defaulted definitions are used for legacy tables that may already hold rows.
local ADDITIVE_COLUMNS = {
    cm_families = {
        { name = 'tag',          ddl = "`tag` VARCHAR(8) NULL AFTER `name`" },
        { name = 'color',        ddl = "`color` VARCHAR(9) NOT NULL DEFAULT '#00f0ff' AFTER `tag`" },
        { name = 'symbol',       ddl = "`symbol` VARCHAR(16) NOT NULL DEFAULT 'shield' AFTER `color`" },
        { name = 'tag_visible',  ddl = "`tag_visible` TINYINT(1) NOT NULL DEFAULT 1 AFTER `symbol`" },
        { name = 'founder_cid',  ddl = "`founder_cid` VARCHAR(64) NOT NULL DEFAULT '' AFTER `tag_visible`" },
        { name = 'house_id',     ddl = "`house_id` INT UNSIGNED NULL AFTER `founder_cid`" },
        { name = 'bank_balance', ddl = "`bank_balance` BIGINT NOT NULL DEFAULT 0 AFTER `house_id`" },
        { name = 'created_at',   ddl = "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP" },
    },
    cm_family_ranks = {
        { name = 'family_id',        ddl = "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`" },
        { name = 'tier',             ddl = "`tier` TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER `family_id`" },
        { name = 'name',             ddl = "`name` VARCHAR(48) NOT NULL DEFAULT 'Rank' AFTER `tier`" },
        { name = 'overhead_symbol',  ddl = "`overhead_symbol` VARCHAR(16) NOT NULL DEFAULT 'shield' AFTER `name`" },
        { name = 'overhead_color',   ddl = "`overhead_color` VARCHAR(9) NULL AFTER `overhead_symbol`" },
        { name = 'permissions',      ddl = "`permissions` JSON NULL AFTER `overhead_color`" },
        { name = 'is_founder',       ddl = "`is_founder` TINYINT(1) NOT NULL DEFAULT 0 AFTER `permissions`" },
        { name = 'bank_daily_limit', ddl = "`bank_daily_limit` BIGINT NOT NULL DEFAULT 0 AFTER `is_founder`" },
        { name = 'created_at',       ddl = "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP" },
    },
    cm_family_members = {
        { name = 'family_id',    ddl = "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0" },
        { name = 'character_id', ddl = "`character_id` VARCHAR(64) NOT NULL DEFAULT '' AFTER `family_id`" },
        { name = 'rank_id',      ddl = "`rank_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `character_id`" },
        { name = 'custom_title', ddl = "`custom_title` VARCHAR(24) NULL AFTER `rank_id`" },
        { name = 'tag_hidden',   ddl = "`tag_hidden` TINYINT(1) NOT NULL DEFAULT 0 AFTER `custom_title`" },
        { name = 'joined_at',    ddl = "`joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP" },
    },
    cm_family_invites = {
        { name = 'family_id',    ddl = "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`" },
        { name = 'character_id', ddl = "`character_id` VARCHAR(64) NOT NULL DEFAULT '' AFTER `family_id`" },
        { name = 'invited_by',   ddl = "`invited_by` VARCHAR(64) NOT NULL DEFAULT '' AFTER `character_id`" },
        { name = 'rank_id',      ddl = "`rank_id` BIGINT UNSIGNED NULL AFTER `invited_by`" },
        { name = 'expires_at',   ddl = "`expires_at` TIMESTAMP NULL AFTER `rank_id`" },
        { name = 'created_at',   ddl = "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP" },
    },
    cm_family_vehicle_access = {
        { name = 'family_id',  ddl = "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`" },
        { name = 'vehicle_id', ddl = "`vehicle_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `family_id`" },
        { name = 'level',      ddl = "`level` TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER `vehicle_id`" },
        { name = 'updated_by', ddl = "`updated_by` VARCHAR(64) NULL AFTER `level`" },
        { name = 'updated_at', ddl = "`updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP" },
    },
    cm_family_bank_log = {
        { name = 'family_id',     ddl = "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`" },
        { name = 'character_id',  ddl = "`character_id` VARCHAR(64) NULL AFTER `family_id`" },
        { name = 'direction',     ddl = "`direction` ENUM('deposit','withdraw') NOT NULL DEFAULT 'deposit' AFTER `character_id`" },
        { name = 'amount',        ddl = "`amount` BIGINT NOT NULL DEFAULT 0 AFTER `direction`" },
        { name = 'balance_after', ddl = "`balance_after` BIGINT NOT NULL DEFAULT 0 AFTER `amount`" },
        { name = 'reason',        ddl = "`reason` VARCHAR(128) NULL AFTER `balance_after`" },
        { name = 'created_at',    ddl = "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP" },
    },
    cm_family_log = {
        { name = 'family_id',  ddl = "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `id`" },
        { name = 'actor_cid',  ddl = "`actor_cid` VARCHAR(64) NULL AFTER `family_id`" },
        { name = 'action',     ddl = "`action` VARCHAR(48) NOT NULL DEFAULT 'legacy' AFTER `actor_cid`" },
        { name = 'detail',     ddl = "`detail` JSON NULL AFTER `action`" },
        { name = 'created_at', ddl = "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP" },
    },
    cm_family_activity_log = {
        { name = 'event_uid',       ddl = "`event_uid` VARCHAR(96) NOT NULL DEFAULT '' AFTER `id`" },
        { name = 'family_id',       ddl = "`family_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER `event_uid`" },
        { name = 'category',        ddl = "`category` VARCHAR(32) NOT NULL DEFAULT 'family' AFTER `family_id`" },
        { name = 'action',          ddl = "`action` VARCHAR(64) NOT NULL DEFAULT 'legacy' AFTER `category`" },
        { name = 'severity',        ddl = "`severity` VARCHAR(16) NOT NULL DEFAULT 'info' AFTER `action`" },
        { name = 'high_risk',       ddl = "`high_risk` TINYINT(1) NOT NULL DEFAULT 0 AFTER `severity`" },
        { name = 'status',          ddl = "`status` VARCHAR(16) NOT NULL DEFAULT 'success' AFTER `high_risk`" },
        { name = 'actor_cid',       ddl = "`actor_cid` VARCHAR(64) NULL AFTER `status`" },
        { name = 'actor_name',      ddl = "`actor_name` VARCHAR(128) NULL AFTER `actor_cid`" },
        { name = 'target_cid',      ddl = "`target_cid` VARCHAR(64) NULL AFTER `actor_name`" },
        { name = 'target_name',     ddl = "`target_name` VARCHAR(128) NULL AFTER `target_cid`" },
        { name = 'source_resource', ddl = "`source_resource` VARCHAR(64) NOT NULL DEFAULT 'cm-family' AFTER `target_name`" },
        { name = 'entity_type',     ddl = "`entity_type` VARCHAR(32) NULL AFTER `source_resource`" },
        { name = 'entity_id',       ddl = "`entity_id` VARCHAR(96) NULL AFTER `entity_type`" },
        { name = 'house_id',        ddl = "`house_id` BIGINT UNSIGNED NULL AFTER `entity_id`" },
        { name = 'vehicle_id',      ddl = "`vehicle_id` BIGINT UNSIGNED NULL AFTER `house_id`" },
        { name = 'amount',          ddl = "`amount` BIGINT NULL AFTER `vehicle_id`" },
        { name = 'detail',          ddl = "`detail` JSON NULL AFTER `amount`" },
        { name = 'created_at',      ddl = "`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP" },
    },
}

local REQUIRED_COLUMNS = {
    cm_families = { 'id', 'name', 'tag', 'color', 'symbol', 'tag_visible', 'founder_cid', 'house_id', 'bank_balance', 'created_at' },
    cm_family_ranks = { 'id', 'family_id', 'tier', 'name', 'overhead_symbol', 'overhead_color', 'permissions', 'is_founder', 'bank_daily_limit', 'created_at' },
    -- Legacy cm_family_members tables often use character_id as the primary key
    -- and intentionally have no numeric id. No runtime query uses members.id.
    cm_family_members = { 'family_id', 'character_id', 'rank_id', 'custom_title', 'tag_hidden', 'joined_at' },
    cm_family_invites = { 'id', 'family_id', 'character_id', 'invited_by', 'rank_id', 'expires_at', 'created_at' },
    cm_family_vehicle_access = { 'id', 'family_id', 'vehicle_id', 'level', 'updated_by', 'updated_at' },
    cm_family_bank_log = { 'id', 'family_id', 'character_id', 'direction', 'amount', 'balance_after', 'reason', 'created_at' },
    cm_family_log = { 'id', 'family_id', 'actor_cid', 'action', 'detail', 'created_at' },
    cm_family_activity_log = { 'id', 'event_uid', 'family_id', 'category', 'action', 'severity', 'high_risk', 'status', 'actor_cid', 'actor_name', 'target_cid', 'target_name', 'source_resource', 'entity_type', 'entity_id', 'house_id', 'vehicle_id', 'amount', 'detail', 'created_at' },
}

local REQUIRED_INDEXES = {
    cm_families = {
        { name = 'uniq_family_name', ddl = 'UNIQUE KEY `uniq_family_name` (`name`)' },
        { name = 'idx_family_founder', ddl = 'KEY `idx_family_founder` (`founder_cid`)' },
        { name = 'idx_family_house', ddl = 'KEY `idx_family_house` (`house_id`)' },
    },
    cm_family_ranks = {
        { name = 'uniq_family_tier', ddl = 'UNIQUE KEY `uniq_family_tier` (`family_id`, `tier`)' },
        { name = 'idx_rank_family', ddl = 'KEY `idx_rank_family` (`family_id`)' },
    },
    cm_family_members = {
        { name = 'uniq_member_character', ddl = 'UNIQUE KEY `uniq_member_character` (`character_id`)' },
        { name = 'idx_member_family', ddl = 'KEY `idx_member_family` (`family_id`)' },
        { name = 'idx_member_rank', ddl = 'KEY `idx_member_rank` (`rank_id`)' },
    },
    cm_family_invites = {
        { name = 'uniq_invite', ddl = 'UNIQUE KEY `uniq_invite` (`family_id`, `character_id`)' },
        { name = 'idx_invite_character', ddl = 'KEY `idx_invite_character` (`character_id`)' },
        { name = 'idx_invite_family', ddl = 'KEY `idx_invite_family` (`family_id`)' },
    },
    cm_family_vehicle_access = {
        { name = 'uniq_family_vehicle', ddl = 'UNIQUE KEY `uniq_family_vehicle` (`family_id`, `vehicle_id`)' },
        { name = 'idx_vaccess_family', ddl = 'KEY `idx_vaccess_family` (`family_id`)' },
    },
    cm_family_bank_log = {
        { name = 'idx_banklog_family', ddl = 'KEY `idx_banklog_family` (`family_id`)' },
    },
    cm_family_log = {
        { name = 'idx_log_family', ddl = 'KEY `idx_log_family` (`family_id`)' },
    },
    cm_family_activity_log = {
        { name = 'uniq_family_activity_uid', ddl = 'UNIQUE KEY `uniq_family_activity_uid` (`event_uid`)' },
        { name = 'idx_family_activity_family_time', ddl = 'KEY `idx_family_activity_family_time` (`family_id`, `created_at`)' },
        { name = 'idx_family_activity_high_time', ddl = 'KEY `idx_family_activity_high_time` (`high_risk`, `created_at`)' },
        { name = 'idx_family_activity_action', ddl = 'KEY `idx_family_activity_action` (`action`)' },
        { name = 'idx_family_activity_actor', ddl = 'KEY `idx_family_activity_actor` (`actor_cid`)' },
    },
}

local function readColumns(tableName)
    local rows = MySQL.query.await([[
        SELECT COLUMN_NAME
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
    ]], { tableName }) or {}

    local columns = {}
    for _, row in ipairs(rows) do
        local name = row.COLUMN_NAME or row.column_name
        if name then columns[tostring(name)] = true end
    end
    return columns
end

local function readIndexes(tableName)
    local rows = MySQL.query.await([[
        SELECT DISTINCT INDEX_NAME
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
    ]], { tableName }) or {}

    local indexes = {}
    for _, row in ipairs(rows) do
        local name = row.INDEX_NAME or row.index_name
        if name then indexes[tostring(name)] = true end
    end
    return indexes
end


local function detectLegacyRankColumns()
    local columns = readColumns('cm_family_ranks')
    CMFamilyUsesLegacyPermsColumn = columns.perms == true
    CMFamilyUsesLegacyGradeColumn = columns.grade == true
    CMFamilyLegacyPermsFormat = 'object'

    if CMFamilyUsesLegacyGradeColumn then
        print('[cm-family] legacy cm_family_ranks.grade detected; enabling tier/grade dual-write compatibility')
    end

    if not CMFamilyUsesLegacyPermsColumn then return end

    -- Most old schemas only use JSON_VALID(perms), which accepts either shape.
    -- A few add JSON_TYPE checks; detect those so dual-writes satisfy the exact
    -- installed constraint rather than guessing.
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT cc.CHECK_CLAUSE
            FROM information_schema.TABLE_CONSTRAINTS tc
            JOIN information_schema.CHECK_CONSTRAINTS cc
              ON cc.CONSTRAINT_SCHEMA = tc.CONSTRAINT_SCHEMA
             AND cc.CONSTRAINT_NAME = tc.CONSTRAINT_NAME
            WHERE tc.TABLE_SCHEMA = DATABASE()
              AND tc.TABLE_NAME = 'cm_family_ranks'
              AND tc.CONSTRAINT_TYPE = 'CHECK'
        ]]) or {}
    end)

    if ok then
        for _, row in ipairs(rows) do
            local clause = tostring(row.CHECK_CLAUSE or row.check_clause or ''):lower()
            if clause:find('perms', 1, true) and clause:find('json_type', 1, true) then
                if clause:find('array', 1, true) then
                    CMFamilyLegacyPermsFormat = 'array'
                elseif clause:find('object', 1, true) then
                    CMFamilyLegacyPermsFormat = 'object'
                end
            end
        end
    end

    print(('[cm-family] legacy cm_family_ranks.perms detected; enabling safe dual-read/dual-write compatibility (%s JSON)')
        :format(CMFamilyLegacyPermsFormat))
end

local function detectLegacyIdColumn(tableName)
    local rows = MySQL.query.await([[
        SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, COLUMN_KEY, COLUMN_DEFAULT,
               IS_NULLABLE, EXTRA, CHARACTER_MAXIMUM_LENGTH
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = ?
    ]], { tableName }) or {}

    local mode = { present = false, autoIncrement = false, numeric = false, maxLength = nil }
    for _, row in ipairs(rows) do
        local name = tostring(row.COLUMN_NAME or row.column_name or ''):lower()
        if name == 'id' then
            local dataType = tostring(row.DATA_TYPE or row.data_type or ''):lower()
            local extra = tostring(row.EXTRA or row.extra or ''):lower()
            mode.present = true
            mode.autoIncrement = extra:find('auto_increment', 1, true) ~= nil
            mode.numeric = dataType == 'tinyint' or dataType == 'smallint' or dataType == 'mediumint'
                or dataType == 'int' or dataType == 'integer' or dataType == 'bigint'
                or dataType == 'decimal' or dataType == 'numeric'
            mode.maxLength = tonumber(row.CHARACTER_MAXIMUM_LENGTH or row.character_maximum_length)
            break
        end
    end
    return mode
end

local function detectLegacyMemberIdColumn()
    local rows = MySQL.query.await([[
        SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, COLUMN_KEY, COLUMN_DEFAULT,
               IS_NULLABLE, EXTRA, CHARACTER_MAXIMUM_LENGTH,
               COALESCE(GENERATION_EXPRESSION, '') AS GENERATION_EXPRESSION,
               ORDINAL_POSITION
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'cm_family_members'
        ORDER BY ORDINAL_POSITION
    ]]) or {}

    local mode = { present = false, autoIncrement = false, numeric = false, maxLength = nil }
    local layout = { columns = {}, ordered = {}, requiredLegacy = {} }
    local canonical = {
        id = true, family_id = true, character_id = true, rank_id = true,
        custom_title = true, tag_hidden = true, joined_at = true,
    }

    for _, row in ipairs(rows) do
        local name = tostring(row.COLUMN_NAME or row.column_name or '')
        local lower = name:lower()
        local dataType = tostring(row.DATA_TYPE or row.data_type or ''):lower()
        local extra = tostring(row.EXTRA or row.extra or ''):lower()
        local nullable = tostring(row.IS_NULLABLE or row.is_nullable or 'YES'):upper() == 'YES'
        local generated = tostring(row.GENERATION_EXPRESSION or row.generation_expression or '') ~= ''
            or extra:find('generated', 1, true) ~= nil
        local column = {
            name = name,
            lower = lower,
            dataType = dataType,
            columnType = tostring(row.COLUMN_TYPE or row.column_type or ''),
            key = tostring(row.COLUMN_KEY or row.column_key or ''):upper(),
            default = row.COLUMN_DEFAULT ~= nil and row.COLUMN_DEFAULT or row.column_default,
            nullable = nullable,
            extra = extra,
            maxLength = tonumber(row.CHARACTER_MAXIMUM_LENGTH or row.character_maximum_length),
            generated = generated,
        }
        layout.columns[lower] = column
        layout.ordered[#layout.ordered + 1] = column

        if lower == 'id' then
            mode.present = true
            mode.autoIncrement = extra:find('auto_increment', 1, true) ~= nil
            mode.numeric = dataType == 'tinyint' or dataType == 'smallint' or dataType == 'mediumint'
                or dataType == 'int' or dataType == 'integer' or dataType == 'bigint'
                or dataType == 'decimal' or dataType == 'numeric'
            mode.maxLength = column.maxLength
        end

        local hasDefault = column.default ~= nil
        if not canonical[lower] and not nullable and not hasDefault
            and not generated and extra:find('auto_increment', 1, true) == nil then
            layout.requiredLegacy[#layout.requiredLegacy + 1] = name
        end
    end

    CMFamilyMemberIdMode = mode
    CMFamilyMemberLayout = layout

    if mode.present and not mode.autoIncrement then
        print(('[cm-family] legacy cm_family_members.id is not AUTO_INCREMENT; enabling explicit member-id compatibility (%s)')
            :format(mode.numeric and 'numeric' or 'text'))
    end
    if #layout.requiredLegacy > 0 then
        print(('[cm-family] cm_family_members requires legacy insert columns: %s')
            :format(table.concat(layout.requiredLegacy, ', ')))
    end
end

local function detectLegacyInviteIdColumn()
    local mode = detectLegacyIdColumn('cm_family_invites')
    CMFamilyInviteIdMode = mode
    if mode.present and not mode.autoIncrement then
        print(('[cm-family] legacy cm_family_invites.id is not AUTO_INCREMENT; enabling explicit invite-id compatibility (%s)')
            :format(mode.numeric and 'numeric' or 'text'))
    end
end

-- Insert one membership row across both current and legacy schemas. Returns
-- (true) only after exactly one row is committed. For old text primary keys we
-- use a deterministic character-based id. For old numeric primary keys we use
-- MAX(id)+1 and retry on a concurrent duplicate.
function CMFamilyInsertMember(familyId, characterId, rankId)
    familyId = tonumber(familyId)
    rankId = tonumber(rankId)
    characterId = characterId ~= nil and tostring(characterId) or nil
    if not familyId or not rankId or not characterId or characterId == '' then
        return false, 'invalid_membership_values'
    end

    -- The in-memory cache intentionally ignores rows whose family no longer
    -- exists. Those stale rows can still block the unique character index, so
    -- reconcile the database before attempting a new membership insert.
    local existing = MySQL.single.await([[
        SELECT family_id, rank_id
        FROM cm_family_members
        WHERE character_id = ?
        LIMIT 1
    ]], { characterId })
    if existing then
        local existingFamilyId = tonumber(existing.family_id) or existing.family_id
        local familyStillExists = MySQL.scalar.await(
            'SELECT id FROM cm_families WHERE id = ? LIMIT 1', { existingFamilyId })
        if familyStillExists then
            if tonumber(existingFamilyId) == familyId then
                local changed = tonumber(MySQL.update.await([[
                    UPDATE cm_family_members
                    SET rank_id = ?
                    WHERE family_id = ? AND character_id = ?
                ]], { rankId, familyId, characterId })) or 0
                -- An unchanged rank reports zero affected rows; the row is still
                -- the requested membership and is therefore an idempotent success.
                return true
            end
            return false, ('character_already_in_family_%s'):format(tostring(existingFamilyId))
        end

        local removed = tonumber(MySQL.update.await(
            'DELETE FROM cm_family_members WHERE character_id = ?', { characterId })) or 0
        print(('[cm-family] removed %d orphan membership row(s) for cid %s before invite acceptance')
            :format(removed, characterId))
    end

    local mode = CMFamilyMemberIdMode or {}
    local layout = CMFamilyMemberLayout or { columns = {}, ordered = {} }
    local columnsByName = layout.columns or {}

    local rankRow = MySQL.single.await('SELECT * FROM cm_family_ranks WHERE id = ? LIMIT 1', { rankId }) or {}
    local rankTier = (CMFamilyRankTier and CMFamilyRankTier(rankRow)) or tonumber(rankRow.tier) or rankId
    local rankName = tostring(rankRow.name or 'Member')
    local familyRow = (Families and Families[familyId]) or MySQL.single.await(
        'SELECT id, name, founder_cid FROM cm_families WHERE id = ? LIMIT 1', { familyId }) or {}
    local familyName = tostring(familyRow.name or 'Family')
    local isFounder = tostring(familyRow.founder_cid or '') == characterId
    local playerName = ('Character #%s'):format(characterId)
    if CMFamilyBridge and type(CMFamilyBridge.GetCharName) == 'function' then
        local ok, resolved = pcall(CMFamilyBridge.GetCharName, characterId)
        if ok and resolved and tostring(resolved) ~= '' then playerName = tostring(resolved) end
    end

    local insertColumns, insertValues, parameters, assigned = {}, {}, {}, {}
    local function quoteIdentifier(name)
        return ('`%s`'):format(tostring(name):gsub('`', '``'))
    end
    local function addValue(column, value)
        if not column or assigned[column.lower] then return nil end
        insertColumns[#insertColumns + 1] = quoteIdentifier(column.name)
        insertValues[#insertValues + 1] = '?'
        parameters[#parameters + 1] = value
        assigned[column.lower] = true
        return #parameters
    end
    local function addExpression(column, expression)
        if not column or assigned[column.lower] then return end
        insertColumns[#insertColumns + 1] = quoteIdentifier(column.name)
        insertValues[#insertValues + 1] = expression
        assigned[column.lower] = true
    end

    addValue(columnsByName.family_id, familyId)
    addValue(columnsByName.character_id, characterId)
    addValue(columnsByName.rank_id, rankId)
    addValue(columnsByName.tag_hidden, 0)

    -- Generate the legacy primary id only when the installed schema requires it.
    local memberIdParameterIndex
    local function textMemberId(attempt)
        local numericCid = tonumber(characterId)
        local candidates = {
            characterId,
            ('%s:%s'):format(familyId, characterId),
            ('m%s_%s'):format(familyId, characterId),
            tostring(((familyId * 100000) + (numericCid or 0) + (attempt or 1)) % 2147483647),
        }
        local raw = candidates[math.min(math.max(tonumber(attempt) or 1, 1), #candidates)]
        local maxLength = tonumber(mode.maxLength)
        if maxLength and maxLength > 0 then
            if #raw > maxLength then
                -- Preserve the changing tail for very short legacy ids instead
                -- of truncating every value to the same leading character.
                raw = raw:sub(-maxLength)
            end
        end
        return raw
    end
    if mode.present and not mode.autoIncrement then
        local idColumn = columnsByName.id
        if mode.numeric then
            local nextId = tonumber(MySQL.scalar.await(
                'SELECT COALESCE(MAX(CAST(`id` AS UNSIGNED)), 0) + 1 FROM cm_family_members')) or 1
            memberIdParameterIndex = addValue(idColumn, nextId)
        else
            memberIdParameterIndex = addValue(idColumn, textMemberId(1))
        end
    end

    local characterAliases = {
        cid = true, citizenid = true, citizen_id = true, char_id = true,
        charid = true, member_cid = true, player_cid = true, owner_cid = true,
    }
    local familyAliases = { family = true, familyid = true, group_id = true, gang_id = true }
    local rankIdAliases = { role_id = true, family_rank_id = true }
    local rankTierAliases = { grade = true, rank_grade = true, rank_tier = true, level = true }
    local rankNameAliases = { role = true, rank_name = true, grade_name = true }
    local playerNameAliases = { player_name = true, character_name = true, member_name = true }
    local ownerAliases = { is_owner = true, is_founder = true, is_boss = true, boss = true }

    local function firstEnumValue(columnType)
        local value = tostring(columnType or ''):match("^enum%('([^']*)'")
        return value or ''
    end
    local function legacyFallback(column)
        local lower, dataType = column.lower, column.dataType
        if characterAliases[lower] then return 'value', characterId end
        if familyAliases[lower] then return 'value', familyId end
        if rankIdAliases[lower] then return 'value', rankId end
        if rankTierAliases[lower] then return 'value', rankTier end
        if rankNameAliases[lower] then return 'value', rankName end
        if playerNameAliases[lower] or lower == 'name' then return 'value', playerName end
        if lower == 'family_name' then return 'value', familyName end
        if ownerAliases[lower] then return 'value', isFounder and 1 or 0 end
        if lower == 'status' or lower == 'state' then return 'value', 'active' end
        if lower == 'permissions' or lower == 'perms' or lower == 'metadata' or lower == 'data' then
            return 'value', '{}'
        end
        if lower == 'created_at' or lower == 'updated_at' or lower == 'joined_at'
            or lower == 'date_joined' or lower == 'joined' then
            return 'expression', 'NOW()'
        end
        if dataType == 'timestamp' or dataType == 'datetime' then return 'expression', 'NOW()' end
        if dataType == 'date' then return 'expression', 'CURRENT_DATE()' end
        if dataType == 'time' then return 'value', '00:00:00' end
        if dataType == 'year' then return 'expression', 'YEAR(CURRENT_DATE())' end
        if dataType == 'json' then return 'value', '{}' end
        if dataType == 'enum' then return 'value', firstEnumValue(column.columnType) end
        if dataType == 'tinyint' or dataType == 'smallint' or dataType == 'mediumint'
            or dataType == 'int' or dataType == 'integer' or dataType == 'bigint'
            or dataType == 'decimal' or dataType == 'numeric' or dataType == 'float'
            or dataType == 'double' or dataType == 'bit' or dataType == 'boolean' then
            return 'value', 0
        end
        if column.key == 'PRI' or column.key == 'UNI' then
            local unique = ('%s_%s_%s'):format(familyId, characterId, lower)
            if column.maxLength and column.maxLength > 0 then unique = unique:sub(1, column.maxLength) end
            return 'value', unique
        end
        return 'value', ''
    end

    -- Populate every extra NOT NULL/no-default legacy column. This is what makes
    -- invitation acceptance compatible with member tables created by older or
    -- third-party family resources without weakening their constraints globally.
    for _, column in ipairs(layout.ordered or {}) do
        local hasDefault = column.default ~= nil
        local requiresValue = not column.nullable and not hasDefault and not column.generated
            and column.extra:find('auto_increment', 1, true) == nil
        if requiresValue and not assigned[column.lower] then
            local kind, value = legacyFallback(column)
            if kind == 'expression' then addExpression(column, value) else addValue(column, value) end
        end
    end

    if #insertColumns == 0 then return false, 'member_schema_has_no_insertable_columns' end
    local sql = ('INSERT INTO cm_family_members (%s) VALUES (%s)')
        :format(table.concat(insertColumns, ', '), table.concat(insertValues, ', '))

    local lastError
    for attempt = 1, 4 do
        local ok, result = pcall(function() return MySQL.update.await(sql, parameters) end)
        if ok and tonumber(result) == 1 then return true end
        lastError = tostring(result)

        -- Legacy ids can collide under concurrent joins or because an old text
        -- id is extremely short. Change only that id and retry.
        if mode.present and not mode.autoIncrement and memberIdParameterIndex
            and lastError:lower():find('duplicate', 1, true) then
            if mode.numeric then
                parameters[memberIdParameterIndex] = tonumber(MySQL.scalar.await(
                    'SELECT COALESCE(MAX(CAST(`id` AS UNSIGNED)), 0) + 1 FROM cm_family_members')) or (attempt + 1)
            else
                parameters[memberIdParameterIndex] = textMemberId(attempt + 1)
            end
        else
            break
        end
    end

    print(('[cm-family] membership insert failed family=%s cid=%s rank=%s columns=[%s] error=%s')
        :format(tostring(familyId), characterId, tostring(rankId), table.concat(insertColumns, ', '), tostring(lastError)))
    return false, lastError or 'membership_insert_failed'
end

local function repairColumns()
    for tableName, definitions in pairs(ADDITIVE_COLUMNS) do
        local columns = readColumns(tableName)
        for _, definition in ipairs(definitions) do
            if not columns[definition.name] then
                print(('[cm-family] adding missing column %s.%s'):format(tableName, definition.name))
                MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tableName, definition.ddl))
                columns[definition.name] = true
            end
        end
    end
end

local function repairIndexes()
    for tableName, definitions in pairs(REQUIRED_INDEXES) do
        local indexes = readIndexes(tableName)
        for _, definition in ipairs(definitions) do
            if not indexes[definition.name] then
                print(('[cm-family] adding missing index %s.%s'):format(tableName, definition.name))
                MySQL.query.await(('ALTER TABLE `%s` ADD %s'):format(tableName, definition.ddl))
                indexes[definition.name] = true
            end
        end
    end
end

local function validateSchema()
    local missing = {}
    for tableName, required in pairs(REQUIRED_COLUMNS) do
        local columns = readColumns(tableName)
        for _, columnName in ipairs(required) do
            if not columns[columnName] then
                missing[#missing + 1] = ('%s.%s'):format(tableName, columnName)
            end
        end
    end

    if #missing > 0 then
        error(('database schema is incomplete; missing: %s'):format(table.concat(missing, ', ')))
    end
end

local function ensureSchema()
    if Config.Database and Config.Database.autoInstall == false then
        print('[cm-family] automatic schema installation is disabled; validating existing tables')
        detectLegacyRankColumns()
        detectLegacyMemberIdColumn()
        detectLegacyInviteIdColumn()
        validateSchema()
        return
    end

    -- Parent first, then its additive columns, then children. Child tables do
    -- not declare FKs, so an older parent type/engine cannot block startup.
    MySQL.query.await(CREATE_PARENT_TABLE)

    for _, query in ipairs(CREATE_CHILD_TABLES) do
        MySQL.query.await(query)
    end

    repairColumns()
    detectLegacyRankColumns()
    detectLegacyMemberIdColumn()
    detectLegacyInviteIdColumn()
    repairIndexes()
    validateSchema()
end

-- Delete a family and every cm-family-owned child row atomically. This is the
-- application-level replacement for ON DELETE CASCADE and works regardless of
-- whether the installed schema has FKs, has none, or is a legacy mix.
function CMFamilyDeleteFamilyRows(familyId)
    familyId = tonumber(familyId)
    if not familyId then return false, 'invalid_family_id' end

    local statements = {
        { query = 'DELETE FROM cm_family_log WHERE family_id = ?', values = { familyId } },
        { query = 'DELETE FROM cm_family_bank_log WHERE family_id = ?', values = { familyId } },
        { query = 'DELETE FROM cm_family_vehicle_access WHERE family_id = ?', values = { familyId } },
        { query = 'DELETE FROM cm_family_invites WHERE family_id = ?', values = { familyId } },
        { query = 'DELETE FROM cm_family_members WHERE family_id = ?', values = { familyId } },
        { query = 'DELETE FROM cm_family_ranks WHERE family_id = ?', values = { familyId } },
        { query = 'DELETE FROM cm_families WHERE id = ?', values = { familyId } },
    }

    local ok, result = pcall(function()
        return MySQL.transaction.await(statements)
    end)
    if not ok then return false, tostring(result) end
    if result ~= true then return false, 'delete_transaction_rejected' end
    return true
end

MySQL.ready(function()
    -- Run in a separate thread so an already-ready oxmysql connection cannot
    -- execute bootstrap before the remaining cm-family server files are loaded.
    CreateThread(function()
        local ok, err = xpcall(ensureSchema, debug.traceback)
        if not ok then
            CMFamilyDatabaseReady = false
            CMFamilyDatabaseError = tostring(err)
            print('^1[cm-family] DATABASE NOT READY^7')
            print(('[cm-family] %s'):format(CMFamilyDatabaseError))
            print('[cm-family] Run sql/013_family_activity_audit_v1.4.0.sql manually if automatic ALTER is unavailable; also review sql/011_member_insert_compat_v1.1.5.sql for legacy member layouts, or grant the DB user CREATE/ALTER permission, then restart cm-family.')
            return
        end

        local waited = 0
        while (type(LoadFamilies) ~= 'function'
            or type(CMFamilyUpgradeStockRecruitPermissions) ~= 'function') and waited < 5000 do
            Wait(50)
            waited = waited + 50
        end
        if type(LoadFamilies) ~= 'function'
            or type(CMFamilyUpgradeStockRecruitPermissions) ~= 'function' then
            CMFamilyDatabaseReady = false
            CMFamilyDatabaseError = 'family state/rank helpers were not registered'
            print('^1[cm-family] startup failed: family state/rank helpers were not registered^7')
            return
        end

        local loaded, loadErr = xpcall(LoadFamilies, debug.traceback)
        if not loaded then
            CMFamilyDatabaseReady = false
            CMFamilyDatabaseError = tostring(loadErr)
            print(('^1[cm-family] failed to load family state:^7 %s'):format(CMFamilyDatabaseError))
            return
        end

        CMFamilyDatabaseError = nil
        CMFamilyDatabaseReady = true
        print('^2[cm-family] database schema ready (durable family activity audit + rank symbols + legacy compatibility)^7')
    end)
end)
