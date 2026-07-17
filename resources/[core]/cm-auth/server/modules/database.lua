-- cm-auth/server/modules/database.lua
-- Schema bootstrap (idempotent) and all account-row lookups in one place.

local Util = _G.CMAuthUtil
local DB = {}

-- ---- Account lookups --------------------------------------------------------

function DB.getAccountBySocialClub(socialClubId)
    return Util.single('SELECT * FROM accounts WHERE social_club_id = ? LIMIT 1', { socialClubId })
end

function DB.getAccountByEmail(email)
    return Util.single('SELECT * FROM accounts WHERE LOWER(email) = LOWER(?) LIMIT 1', { email })
end

function DB.getAccountByToken(token)
    return Util.single('SELECT * FROM accounts WHERE auth_token = ? LIMIT 1', { token })
end

function DB.getAccountByIdOrEmail(target)
    target = Util.sanitize(target)
    if target == '' then return nil end
    return Util.single('SELECT * FROM accounts WHERE id = ? OR LOWER(email) = LOWER(?) LIMIT 1', { target, target })
end

function DB.emailExists(email)
    return (tonumber(Util.scalar('SELECT COUNT(*) FROM accounts WHERE LOWER(email) = LOWER(?)', { email }) or 0) or 0) > 0
end

-- ---- Schema bootstrap -------------------------------------------------------

local function indexExists(tableName, indexName)
    local rows = Util.query(('SHOW INDEX FROM %s WHERE Key_name = ?'):format(tableName), { indexName })
    return rows and rows[1] ~= nil
end

local function columnMissing(tableName, columnName)
    local col = Util.query(('SHOW COLUMNS FROM %s LIKE ?'):format(tableName), { columnName })
    return not col or not col[1]
end

function DB.ensureSchema()
    Util.query([[CREATE TABLE IF NOT EXISTS login_attempts (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(100) NOT NULL,
        ip_address VARCHAR(64) NULL,
        hwid_hash VARCHAR(255) NULL,
        success TINYINT(1) NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])

    Util.query([[CREATE TABLE IF NOT EXISTS auth_lockouts (
        lock_key VARCHAR(160) NOT NULL PRIMARY KEY,
        locked_until DATETIME NOT NULL,
        reason VARCHAR(255) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    )]])

    Util.query([[CREATE TABLE IF NOT EXISTS register_attempts (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        ip_address VARCHAR(64) NULL,
        hwid_hash VARCHAR(255) NULL,
        email VARCHAR(100) NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_register_lookup (ip_address, hwid_hash, created_at)
    )]])

    -- Additive columns on the pre-existing accounts table (safe if already present).
    if columnMissing('login_attempts', 'created_at') then
        Util.query('ALTER TABLE login_attempts ADD COLUMN created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP')
    end
    if columnMissing('accounts', 'auth_token') then
        Util.query('ALTER TABLE accounts ADD COLUMN auth_token VARCHAR(128) NULL')
    end
    if columnMissing('accounts', 'auth_token_created_at') then
        Util.query('ALTER TABLE accounts ADD COLUMN auth_token_created_at DATETIME NULL')
    end

    -- Unique indexes to stop duplicate-account races at the DB level.
    if not indexExists('accounts', 'uniq_accounts_email') then
        if Util.query('ALTER TABLE accounts ADD UNIQUE INDEX uniq_accounts_email (email)') == nil then
            print('[CM-AUTH] NOTE: could not add UNIQUE index on accounts.email (likely existing duplicates). Clean them, then restart.')
        end
    end
    if not indexExists('accounts', 'uniq_accounts_social') then
        if Util.query('ALTER TABLE accounts ADD UNIQUE INDEX uniq_accounts_social (social_club_id)') == nil then
            print('[CM-AUTH] NOTE: could not add UNIQUE index on accounts.social_club_id (likely existing duplicates). Clean them, then restart.')
        end
    end
    if not indexExists('login_attempts', 'idx_attempts_lookup') then
        Util.query('ALTER TABLE login_attempts ADD INDEX idx_attempts_lookup (username, ip_address, created_at)')
    end
end

_G.CMAuthDB = DB
return DB
