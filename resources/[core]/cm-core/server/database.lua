local dbReady = false
local migrationVersion = 0

local migrations = {
    [1] = [[CREATE TABLE IF NOT EXISTS accounts (
        id VARCHAR(50) PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL, email VARCHAR(100),
        hwid_hash VARCHAR(255), ip_address VARCHAR(45),
        banned BOOLEAN DEFAULT FALSE, ban_reason TEXT, ban_expires TIMESTAMP NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, last_login TIMESTAMP NULL
    );]],
    [2] = [[CREATE TABLE IF NOT EXISTS characters (
        id VARCHAR(50) PRIMARY KEY, account_id VARCHAR(50) NOT NULL,
        slot TINYINT NOT NULL CHECK (slot BETWEEN 1 AND 3),
        first_name VARCHAR(50) NOT NULL, last_name VARCHAR(50) NOT NULL,
        dob DATE, gender ENUM('male', 'female', 'other'), appearance_json JSON,
        current_rank_id INT DEFAULT 1, total_xp INT DEFAULT 0,
        cash INT DEFAULT 500, bank INT DEFAULT 2000,
        last_position JSON, last_dimension INT DEFAULT 0,
        is_dead BOOLEAN DEFAULT FALSE, death_time TIMESTAMP NULL,
        tutorial_step INT DEFAULT 0, tutorial_completed BOOLEAN DEFAULT FALSE,
        playtime_minutes INT DEFAULT 0, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_played TIMESTAMP NULL,
        UNIQUE(account_id, slot),
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
    );]],
    [3] = [[CREATE TABLE IF NOT EXISTS ranks (
        id INT PRIMARY KEY, name VARCHAR(50) NOT NULL, level INT NOT NULL,
        min_xp INT NOT NULL, max_xp INT NOT NULL, daily_salary INT DEFAULT 0,
        benefits_json JSON, icon VARCHAR(50)
    );]],
    [4] = [[CREATE TABLE IF NOT EXISTS player_sessions (
        id INT AUTO_INCREMENT PRIMARY KEY, account_id VARCHAR(50),
        character_id VARCHAR(50), server_id INT,
        connect_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        disconnect_time TIMESTAMP NULL, playtime_seconds INT DEFAULT 0,
        FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE SET NULL
    );]],
    [5] = [[CREATE TABLE IF NOT EXISTS server_logs (
        id INT AUTO_INCREMENT PRIMARY KEY, resource VARCHAR(50), level VARCHAR(20),
        category VARCHAR(50), message TEXT, metadata JSON,
        player_src INT, player_char_id VARCHAR(50), player_account_id VARCHAR(50),
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_resource (resource), INDEX idx_category (category),
        INDEX idx_timestamp (timestamp), INDEX idx_player (player_char_id)
    );]],
    [6] = [[CREATE TABLE IF NOT EXISTS login_attempts (
        id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50),
        ip_address VARCHAR(45), hwid_hash VARCHAR(255), success BOOLEAN,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );]],
    [7] = [[
    CREATE TABLE IF NOT EXISTS account_slots (
        social_club_id VARCHAR(100) PRIMARY KEY,
        slot_1_account_id VARCHAR(50) NULL,
        slot_2_account_id VARCHAR(50) NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (slot_1_account_id) REFERENCES accounts(id) ON DELETE RESTRICT,
        FOREIGN KEY (slot_2_account_id) REFERENCES accounts(id) ON DELETE RESTRICT
    );
    ]],
    [8] = [[
        ALTER TABLE accounts ADD COLUMN IF NOT EXISTS social_club_id VARCHAR(100) AFTER id;
    ]],
    [9] = [[
        ALTER TABLE accounts ADD COLUMN IF NOT EXISTS account_slot TINYINT NOT NULL DEFAULT 1 AFTER social_club_id;
    ]],
    [10] = [[-- handled by migrationHandlers[10] ]],
    [11] = [[CREATE TABLE IF NOT EXISTS money_ledger (
        id INT AUTO_INCREMENT PRIMARY KEY,
        character_id VARCHAR(50) NULL,
        target_character_id VARCHAR(50) NULL,
        account_type VARCHAR(20) NOT NULL,
        action VARCHAR(30) NOT NULL,
        amount INT NOT NULL,
        balance_after INT DEFAULT 0,
        reason VARCHAR(100),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_character_id (character_id),
        INDEX idx_created_at (created_at),
        INDEX idx_action (action)
    );]],
    [12] = [[
        ALTER TABLE characters ADD COLUMN IF NOT EXISTS job VARCHAR(50) DEFAULT 'unemployed';
    ]],
    [13] = [[
        ALTER TABLE characters ADD COLUMN IF NOT EXISTS job_grade INT DEFAULT 0;
    ]],
    [14] = [[
        ALTER TABLE characters ADD COLUMN IF NOT EXISTS metadata JSON NULL;
    ]],
    }

local migrationHandlers = {
    [10] = function()
        local exists = MySQL.scalar.await([[
            SELECT COUNT(1) FROM information_schema.statistics
            WHERE table_schema = DATABASE()
              AND table_name = 'accounts'
              AND index_name = 'unique_social_slot'
        ]]) or 0
        if tonumber(exists) == 0 then
            MySQL.query.await('ALTER TABLE accounts ADD UNIQUE KEY unique_social_slot (social_club_id, account_slot)')
        end
    end,
}

function SeedRanks()
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM ranks')
    if count == 0 then
        for _, rank in ipairs(CM.Ranks) do
            MySQL.query.await([[
                INSERT INTO ranks (id, name, level, min_xp, max_xp, daily_salary, benefits_json, icon)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ]], {rank.id, rank.name, rank.level, rank.min_xp, rank.max_xp, rank.daily_salary, json.encode(rank.benefits), rank.icon})
        end
        print("[CM-CORE] Seeded " .. #CM.Ranks .. " ranks")
    end
end

local function RunMigrations()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS schema_migrations (
        version INT PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )]])
    
    local currentVersion = MySQL.scalar.await('SELECT MAX(version) FROM schema_migrations') or 0
    migrationVersion = currentVersion
    
    for version = currentVersion + 1, #migrations do
        local query = migrations[version]
        if query then
            local ok, err = pcall(function()
                if migrationHandlers[version] then
                    migrationHandlers[version]()
                elseif type(query) == 'string' and query:match('%S') and not query:match('^%s*%-%-') then
                    MySQL.query.await(query)
                end
                MySQL.query.await('INSERT INTO schema_migrations (version) VALUES (?)', {version})
            end)
            if ok then
                print("[CM-CORE] Migration " .. version .. " applied")
                migrationVersion = version
            else
                print("[CM-CORE] Migration " .. version .. " FAILED: " .. tostring(err))
                break
            end
        end
    end
    
    dbReady = true
    print("[CM-CORE] Database ready. Version: " .. migrationVersion)
    SeedRanks()
end

CreateThread(function()
    -- FiveM starts resources in order, but other resources can still call cm-core exports
    -- before cm-core has completed its async database migrations. Wait for oxmysql,
    -- then initialize as early as possible. Query exports below also wait for dbReady.
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(100)
    end

    local ok, err = pcall(RunMigrations)
    if not ok then
        dbReady = false
        print('[CM-CORE] Database initialization FAILED: ' .. tostring(err))
    end
end)

local lastDbNotReadyWarning = 0

local function WaitForDBReady(timeoutMs)
    if dbReady then return true end

    timeoutMs = timeoutMs or 15000
    local startedAt = GetGameTimer()

    while not dbReady and (GetGameTimer() - startedAt) < timeoutMs do
        Wait(50)
    end

    if dbReady then return true end

    local now = GetGameTimer()
    if now - lastDbNotReadyWarning > 5000 then
        lastDbNotReadyWarning = now
        print(('[CM-CORE] DB not ready after %dms wait'):format(timeoutMs))
    end

    return false
end

local function NormalizeQueryArgs(a, b, c)
    -- Supports every common CFX export call shape:
    -- exports['cm-core'].Query(sql, params)
    -- exports['cm-core']:Query(sql, params)
    -- exports['cm-core'][name](sql, params)
    -- accidental packed args table: { sql, params }

    if type(a) == 'string' then
        return a, b or {}
    end

    if type(a) == 'table' then
        -- Colon-style call where the export object/self is argument 1
        if type(b) == 'string' then
            return b, c or {}
        end

        -- Packed arguments table: { sql, params }
        if type(a[1]) == 'string' then
            return a[1], a[2] or {}
        end

        -- Named table form, useful for future safety
        if type(a.sql) == 'string' then
            return a.sql, a.params or b or {}
        end

        if type(a.query) == 'string' then
            return a.query, a.params or b or {}
        end
    end

    return a, b or {}
end

exports('Query', function(a, b, c)
    if not WaitForDBReady() then return nil end
    local query, params = NormalizeQueryArgs(a, b, c)
    if type(query) ~= 'string' then
        print(('[CM-CORE] Query expected string, got %s'):format(type(query)))
        return nil
    end
    local start = GetGameTimer()
    local result = MySQL.query.await(query, params)
    local elapsed = GetGameTimer() - start
    if elapsed > (exports['cm-core']:GetConfig('Database', 'slowQueryThreshold') or 150) then
        print(("[CM-CORE] SLOW QUERY (%dms): %s"):format(elapsed, query:sub(1, 100)))
    end
    return result
end)

exports('Scalar', function(a, b, c)
    if not WaitForDBReady() then return nil end
    local query, params = NormalizeQueryArgs(a, b, c)
    if type(query) ~= 'string' then
        print(('[CM-CORE] Scalar expected string, got %s'):format(type(query)))
        return nil
    end
    return MySQL.scalar.await(query, params)
end)

exports('Single', function(a, b, c)
    if not WaitForDBReady() then return nil end
    local query, params = NormalizeQueryArgs(a, b, c)
    if type(query) ~= 'string' then
        print(('[CM-CORE] Single expected string, got %s'):format(type(query)))
        return nil
    end
    return MySQL.single.await(query, params)
end)

exports('Update', function(a, b, c)
    if not WaitForDBReady() then return nil end
    local query, params = NormalizeQueryArgs(a, b, c)
    if type(query) ~= 'string' then
        print(('[CM-CORE] Update expected string, got %s'):format(type(query)))
        return nil
    end
    return MySQL.update.await(query, params)
end)

exports('Insert', function(a, b, c)
    if not WaitForDBReady() then return nil end
    local query, params = NormalizeQueryArgs(a, b, c)
    if type(query) ~= 'string' then
        print(('[CM-CORE] Insert expected string, got %s'):format(type(query)))
        return nil
    end
    return MySQL.insert.await(query, params)
end)

exports('Transaction', function(a, b)
    if not WaitForDBReady() then return false end
    local queries = type(a) == 'table' and type(b) == 'table' and b or a
    return MySQL.transaction.await(queries)
end)

exports('IsDBReady', function() return dbReady end)