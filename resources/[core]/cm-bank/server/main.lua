local Config = CMBank.Config

local actionCooldowns = {}
local transferCooldowns = {}
local atmReportCooldowns = {}
local lookupCooldowns = {}
local ACTIVITY_LIMIT = 4
local STATEMENT_PAGE_SIZE = 20

-- v1.5.0: per-player sliding window of recent successful transfer request
-- timestamps (GetGameTimer ms), used to enforce Config.TransferSecurity's
-- maxTransfersPerMinute server-side regardless of what the NUI allows.
local transferRateHistory = {}

local bankReady = false
local bankInitError = nil
local operationLocks = {}
local transactionSequence = 0

-- In-memory cache of discovered ATM locations, keyed by CMBank.CoordKey().
-- Loaded from bank_atm_locations at boot and kept in sync as clients report
-- new discoveries, so a report cheaply no-ops once a location is known.
-- Each entry: { id, x, y, z, ownerCharacterId, ownerName, contact, feePercent,
--               pendingEarnings, adminDisabled, forSale, verified }
-- `id` is the DB auto-increment primary key, surfaced to players/admins as
-- the ATM's serial number ("ATM No. 14") so a specific machine can be
-- referenced without needing to stand at it (admin commands accept it).
local atmLocations = {}

-- Live value for the global ATM-ownership kill-switch. Falls back to the
-- config default until cm_bank_settings has loaded; admins flip this at
-- runtime via /atmownership on|off with no restart required.
local ownershipEnabled = (Config.Ownership and Config.Ownership.enabled) ~= false

-- Admin-placed bank tellers, keyed by DB id. Unlike ATMs these are never
-- auto-discovered (there's no real world prop to scan for an NPC).
local tellers = {}

local function dbg(...)
    if Config.Debug then print('[CM-BANK]', ...) end
end

local function playerData()
    if GetResourceState('cm-playerdata') ~= 'started' then return nil end
    return exports['cm-playerdata']
end

local function isLoaded(src)
    local api = playerData()
    if not api then return false end
    local ok, loaded = pcall(function() return api:IsCharacterLoaded(src) end)
    return ok and loaded == true
end

local function getBalances(src)
    local api = playerData()
    if not api then return 0, 0 end
    local ok, cash, bank = pcall(function() return api:GetCash(src), api:GetBank(src) end)
    if not ok then return 0, 0 end
    return tonumber(cash) or 0, tonumber(bank) or 0
end

local function canAfford(src, account, amount)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:CanAfford(src, account, amount) end)
    return ok and result == true
end

local function transferOwnAccounts(src, fromAccount, toAccount, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:TransferMoney(src, fromAccount, toAccount, amount, reason) end)
    return ok and result == true
end

local function removeMoney(src, account, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:RemoveMoney(src, account, amount, reason) end)
    return ok and result == true
end

local function addMoney(src, account, amount, reason)
    local api = playerData()
    if not api then return false end
    local ok, result = pcall(function() return api:AddMoney(src, account, amount, reason) end)
    return ok and result == true
end

local function getCharId(src)
    local api = playerData()
    if not api then return nil end
    local ok, charId = pcall(function() return api:GetCharId(src) end)
    if not ok then return nil end
    return tonumber(charId)
end

local function getCharName(src)
    local api = playerData()
    if not api then return nil end
    local ok, name = pcall(function() return api:GetCharacterFullName(src) end)
    if not ok or type(name) ~= 'string' or name == '' then return nil end
    return name
end

local function getSourceByCharId(charId)
    local api = playerData()
    if not api then return nil end
    local ok, src = pcall(function() return api:GetSourceByCharId(charId) end)
    if not ok then return nil end
    return tonumber(src)
end

local function adminLog(src, action, data, targetIdentifier, targetName)
    if GetResourceState('cm-admin') ~= 'started' then return end
    local ok, err = pcall(function()
        exports['cm-admin']:AddLog(src, action, data, targetIdentifier, targetName)
    end)
    if not ok then dbg('cm-admin AddLog failed for', action, err) end
end

-- Console (src == 0) is the server operator and always allowed. In-game,
-- permission is delegated to cm-admin and fails closed if cm-admin isn't
-- running or the check itself errors.
local function isAdminAllowed(src, permission)
    if tonumber(src) == 0 then return true end
    if GetResourceState('cm-admin') ~= 'started' then return false end
    local ok, allowed = pcall(function() return exports['cm-admin']:HasPermission(src, permission) end)
    return ok and allowed == true
end

local function newTransactionId(prefix, src)
    transactionSequence = transactionSequence + 1
    if transactionSequence > 999999 then transactionSequence = 1 end
    return ('CB-%s-%d-%d-%06d'):format(
        tostring(prefix or 'TX'):upper():sub(1, 8),
        os.time(),
        tonumber(src) or 0,
        transactionSequence
    )
end

-- Non-blocking lock set. FiveM event handlers may yield while awaiting MySQL
-- or another resource export, so every money/ATM mutation must reserve its
-- character/ATM keys first. We fail busy instead of waiting, which avoids
-- deadlocks and duplicate concurrent operations.
local function runLocked(keys, fn)
    local unique, normalized = {}, {}
    for _, key in ipairs(keys or {}) do
        key = tostring(key or '')
        if key ~= '' and not unique[key] then
            unique[key] = true
            normalized[#normalized + 1] = key
        end
    end
    table.sort(normalized)

    for _, key in ipairs(normalized) do
        if operationLocks[key] then return false, 'busy' end
    end

    local token = ('%d:%d'):format(GetGameTimer(), transactionSequence + 1)
    for _, key in ipairs(normalized) do operationLocks[key] = token end

    local ok, a, b, c, d = pcall(fn)
    for _, key in ipairs(normalized) do
        if operationLocks[key] == token then operationLocks[key] = nil end
    end

    if not ok then
        print('[CM-BANK] Locked operation failed:', a)
        return false, 'error', a
    end
    return true, a, b, c, d
end

local function waitUntilBankReady(timeoutMs)
    local started = GetGameTimer()
    while not bankReady and not bankInitError and (GetGameTimer() - started) < (timeoutMs or 10000) do
        Wait(50)
    end
    return bankReady == true
end

local function beginOperation(transactionId, operation, characterId, targetCharacterId, amount, details)
    local ok, insertId = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO cm_bank_operation_journal
                (transaction_id, operation, character_id, target_character_id, amount, status, details)
            VALUES (?, ?, ?, ?, ?, 'started', ?)
        ]], {
            transactionId, operation, characterId, targetCharacterId, amount or 0,
            details and json.encode(details) or nil
        })
    end)
    if not ok or not tonumber(insertId) or tonumber(insertId) <= 0 then
        dbg('Failed to begin operation journal:', transactionId, insertId)
        return false
    end
    return true
end

local function finishOperation(transactionId, status, details)
    local ok, err = pcall(function()
        MySQL.update.await(
            'UPDATE cm_bank_operation_journal SET status = ?, details = COALESCE(?, details) WHERE transaction_id = ?',
            { tostring(status or 'unknown'), details and json.encode(details) or nil, transactionId }
        )
    end)
    if not ok then dbg('Failed to finish operation journal:', transactionId, err) end
    return ok
end

-- v1.4 initializes all database state in one ordered sequence. No banking
-- request is served until this finishes, preventing empty-cache/startup races.
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS bank_transactions (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                transaction_id VARCHAR(64) NULL,
                character_id INT NOT NULL,
                kind VARCHAR(16) NOT NULL,
                amount INT NOT NULL,
                fee_amount INT NOT NULL DEFAULT 0,
                balance_after INT NOT NULL,
                counterparty_character_id INT NULL,
                counterparty_name VARCHAR(100) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_character_created (character_id, created_at)
            )
        ]])
        for _, alterSql in ipairs({
            'ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS transaction_id VARCHAR(64) NULL AFTER id',
            'ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS fee_amount INT NOT NULL DEFAULT 0 AFTER amount',
            -- v1.5.0: statements/status. DEFAULT 'completed' means every pre-v1.5
            -- historical row reads as completed, which matches what actually happened.
            "ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'completed'",
            'ALTER TABLE bank_transactions ADD COLUMN IF NOT EXISTS description VARCHAR(120) NULL',
        }) do
            pcall(function() MySQL.query.await(alterSql) end)
        end
        for _, indexSql in ipairs({
            'ALTER TABLE bank_transactions ADD INDEX IF NOT EXISTS idx_transaction_id (transaction_id)',
            'ALTER TABLE bank_transactions ADD INDEX IF NOT EXISTS idx_counterparty (counterparty_character_id, created_at)',
            'ALTER TABLE bank_transactions ADD INDEX IF NOT EXISTS idx_kind_created (kind, created_at)',
        }) do
            pcall(function() MySQL.query.await(indexSql) end)
        end

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cm_bank_operation_journal (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                transaction_id VARCHAR(64) NOT NULL UNIQUE,
                operation VARCHAR(32) NOT NULL,
                character_id INT NULL,
                target_character_id INT NULL,
                amount INT NOT NULL DEFAULT 0,
                status VARCHAR(24) NOT NULL,
                details LONGTEXT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                INDEX idx_bank_op_character (character_id, created_at),
                INDEX idx_bank_op_status (status, created_at)
            )
        ]])

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS bank_atm_locations (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                coord_key VARCHAR(32) NOT NULL UNIQUE,
                x FLOAT NOT NULL,
                y FLOAT NOT NULL,
                z FLOAT NOT NULL,
                owner_character_id INT NULL,
                owner_name VARCHAR(100) NULL,
                contact VARCHAR(100) NULL,
                fee_percent INT NOT NULL DEFAULT 0,
                pending_earnings INT NOT NULL DEFAULT 0,
                admin_disabled TINYINT(1) NOT NULL DEFAULT 0,
                for_sale TINYINT(1) NOT NULL DEFAULT 1,
                verified TINYINT(1) NOT NULL DEFAULT 1,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])
        for _, alterSql in ipairs({
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS owner_character_id INT NULL',
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS owner_name VARCHAR(100) NULL',
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS fee_percent INT NOT NULL DEFAULT 0',
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS pending_earnings INT NOT NULL DEFAULT 0',
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS admin_disabled TINYINT(1) NOT NULL DEFAULT 0',
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS contact VARCHAR(100) NULL',
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS for_sale TINYINT(1) NOT NULL DEFAULT 1',
            -- DEFAULT 1 deliberately trusts the locations that existed before
            -- v1.4. New client discoveries are inserted explicitly as 0.
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS verified TINYINT(1) NOT NULL DEFAULT 1',
            -- v1.6.0: physical cash reserve. `cash_capacity` defaults to 0,
            -- used as a one-time "never initialized" sentinel below — real
            -- capacity is always > 0, so this can never re-trigger once set.
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS cash_reserve INT NOT NULL DEFAULT 0',
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS cash_capacity INT NOT NULL DEFAULT 0',
            'ALTER TABLE bank_atm_locations ADD COLUMN IF NOT EXISTS owner_reserve_contribution INT NOT NULL DEFAULT 0',
        }) do
            local alterOk, alterErr = pcall(function() MySQL.query.await(alterSql) end)
            if not alterOk then dbg('ATM migration skipped/failed:', alterSql, alterErr) end
        end

        -- v1.6.0: ATM-scoped business activity (owner dashboard history +
        -- analytics). Deliberately separate from bank_transactions, which is
        -- character-scoped for personal statements — an owner's business
        -- history needs to show OTHER players' withdrawals/deposits at their
        -- machine, which bank_transactions (character_id NOT NULL, one row
        -- per acting player) isn't shaped for.
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS bank_atm_activity (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                atm_id BIGINT NOT NULL,
                transaction_id VARCHAR(64) NULL,
                kind VARCHAR(24) NOT NULL,
                actor_character_id INT NULL,
                amount INT NOT NULL DEFAULT 0,
                fee_amount INT NOT NULL DEFAULT 0,
                reserve_after INT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_atm_created (atm_id, created_at)
            )
        ]])

        -- v1.7.0: saved Character ID payees. Nickname is only a personal
        -- label; the actual transfer always uses recipient_character_id.
        -- UNIQUE(owner_character_id, recipient_character_id) prevents saving
        -- the same recipient twice per owner at the database level.
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS bank_saved_payees (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                owner_character_id INT NOT NULL,
                recipient_character_id INT NOT NULL,
                nickname VARCHAR(40) NOT NULL,
                is_favourite TINYINT(1) NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                UNIQUE KEY uniq_owner_recipient (owner_character_id, recipient_character_id),
                INDEX idx_payee_owner_favourite (owner_character_id, is_favourite)
            )
        ]])

        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS cm_bank_settings (
                setting_key VARCHAR(64) PRIMARY KEY,
                setting_value TEXT NOT NULL,
                updated_by VARCHAR(64) NULL,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            )
        ]])

        -- v1.5.0: offline character-ID transfers. cm-playerdata's exported
        -- money functions all require an online `src`; there is no supported
        -- way to credit an offline character directly. Rather than bypass
        -- cm-playerdata by writing into its tables, a transfer to an offline
        -- Character ID debits the sender immediately and queues a row here,
        -- delivered idempotently the next time that character loads (see the
        -- cm-playerdata:server:characterLoaded handler below).
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS bank_pending_transfers (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                transaction_id VARCHAR(64) NOT NULL UNIQUE,
                sender_character_id INT NOT NULL,
                sender_name VARCHAR(100) NULL,
                recipient_character_id INT NOT NULL,
                amount INT NOT NULL,
                note VARCHAR(120) NULL,
                status VARCHAR(20) NOT NULL DEFAULT 'pending',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                delivered_at TIMESTAMP NULL,
                INDEX idx_pending_recipient_status (recipient_character_id, status)
            )
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS bank_tellers (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                model VARCHAR(64) NOT NULL,
                x FLOAT NOT NULL,
                y FLOAT NOT NULL,
                z FLOAT NOT NULL,
                heading FLOAT NOT NULL DEFAULT 0,
                created_by VARCHAR(64) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ]])

        local settingsRow = MySQL.single.await(
            'SELECT setting_value FROM cm_bank_settings WHERE setting_key = ?',
            { 'ownership_enabled' }
        )
        if settingsRow and settingsRow.setting_value ~= nil then
            ownershipEnabled = tostring(settingsRow.setting_value) == 'true'
        end

        local atmRows = MySQL.query.await([[
            SELECT id, coord_key, x, y, z, owner_character_id, owner_name, contact,
                   fee_percent, pending_earnings, admin_disabled, for_sale, verified,
                   cash_reserve, cash_capacity, owner_reserve_contribution
            FROM bank_atm_locations
        ]]) or {}
        for i = 1, #atmRows do
            local row = atmRows[i]
            local isOwned = row.owner_character_id ~= nil
            local capacity = tonumber(row.cash_capacity) or 0
            local reserve = tonumber(row.cash_reserve) or 0

            -- One-time backfill for rows that existed before v1.6.0: capacity
            -- is always > 0 once set, so `capacity <= 0` can only ever be
            -- true exactly once per row, making this safe to run on every boot.
            if capacity <= 0 then
                capacity = isOwned
                    and math.max(1, tonumber(Config.ATMBusiness and Config.ATMBusiness.defaultCashCapacity) or 100000)
                    or math.max(1, tonumber(Config.PublicATM and Config.PublicATM.defaultCashCapacity) or 250000)
                reserve = isOwned
                    and math.max(0, tonumber(Config.ATMBusiness and Config.ATMBusiness.startingCashReserve) or 50000)
                    or capacity -- public ATMs start full so the migration doesn't suddenly starve them
                local backfillOk, backfillAffected = pcall(function()
                    return MySQL.update.await(
                        'UPDATE bank_atm_locations SET cash_capacity = ?, cash_reserve = ? WHERE id = ? AND cash_capacity <= 0',
                        { capacity, reserve, row.id }
                    )
                end)
                if not backfillOk or tonumber(backfillAffected) ~= 1 then
                    dbg('ATM reserve backfill skipped/failed for id', row.id)
                end
            end

            atmLocations[row.coord_key] = {
                id = tonumber(row.id),
                x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                ownerCharacterId = tonumber(row.owner_character_id),
                ownerName = row.owner_name,
                contact = row.contact,
                feePercent = tonumber(row.fee_percent) or 0,
                pendingEarnings = math.max(0, tonumber(row.pending_earnings) or 0),
                adminDisabled = (tonumber(row.admin_disabled) or 0) == 1,
                forSale = (tonumber(row.for_sale) or 1) == 1,
                verified = (tonumber(row.verified) or 0) == 1,
                cashReserve = math.max(0, reserve),
                cashCapacity = math.max(1, capacity),
                ownerReserveContribution = math.max(0, tonumber(row.owner_reserve_contribution) or 0),
            }
        end

        local tellerRows = MySQL.query.await('SELECT id, name, model, x, y, z, heading FROM bank_tellers') or {}
        for i = 1, #tellerRows do
            local row = tellerRows[i]
            tellers[row.id] = {
                id = row.id, name = row.name, model = row.model,
                x = row.x, y = row.y, z = row.z, heading = row.heading or 0,
            }
        end

        -- Seed configured branch tellers after loading persisted ones.
        local existingNames = {}
        for _, t in pairs(tellers) do existingNames[t.name] = true end
        for _, loc in ipairs(Config.BankLocations or {}) do
            local branchName = tostring(loc.name or ''):gsub('^%s+', ''):gsub('%s+$', '')
            local name = branchName ~= '' and (branchName .. ' Teller') or nil
            if name and not existingNames[name] and loc.coords then
                local c = loc.coords
                local model = tostring(Config.Tellers and Config.Tellers.model or 'a_m_m_business_01')
                local insertId = MySQL.insert.await(
                    'INSERT INTO bank_tellers (name, model, x, y, z, heading, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
                    { name, model, c.x, c.y, c.z, c.w, 'seed:BankLocations' }
                )
                if insertId then
                    tellers[insertId] = { id = insertId, name = name, model = model, x = c.x, y = c.y, z = c.z, heading = c.w }
                    existingNames[name] = true
                end
            end
        end
    end)

    if not ok then
        bankInitError = tostring(err)
        print('[CM-BANK] Initialization FAILED; banking remains fail-closed:', bankInitError)
        return
    end

    bankReady = true
    dbg(('Ready: %d ATM record(s), teller cache loaded.'):format((function()
        local n = 0
        for _ in pairs(atmLocations) do n = n + 1 end
        return n
    end)()))
end)

-- v1.6.0: server-only automatic top-up for public/unowned ATMs (never
-- triggered by any client event). Player-owned ATMs are never touched here.
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutes
        if bankReady then
            local cfg = Config.PublicATM or {}
            if cfg.useCashReserve ~= false and cfg.infiniteCash ~= true and cfg.automaticRestock ~= false then
                local threshold = tonumber(cfg.restockThreshold) or 50000
                local target = tonumber(cfg.restockTarget) or 250000
                for key, atm in pairs(atmLocations) do
                    if atm.verified == true and not atm.ownerCharacterId and (tonumber(atm.cashReserve) or 0) < threshold then
                        -- This loop only ever handles unowned/public ATMs, so
                        -- the public capacity default is the correct fallback
                        -- (defaultCapacityForAtm is defined later in the file
                        -- and isn't in scope for this earlier local function).
                        local capacity = tonumber(atm.cashCapacity) or math.max(1, tonumber(cfg.defaultCashCapacity) or 250000)
                        local newReserve = math.min(capacity, target)
                        local ok, affected = pcall(function()
                            return MySQL.update.await(
                                'UPDATE bank_atm_locations SET cash_reserve = ? WHERE coord_key = ? AND owner_character_id IS NULL AND verified = 1',
                                { newReserve, key }
                            )
                        end)
                        if ok and tonumber(affected) == 1 then
                            atm.cashReserve = newReserve
                        end
                    end
                end
            end
        end
    end
end)

local function recordTransaction(charId, kind, amount, balanceAfter, counterpartyCharId, counterpartyName, transactionId, feeAmount, status, description)
    if not charId then return false end
    local ok, err = pcall(function()
        MySQL.query.await(
            'INSERT INTO bank_transactions (transaction_id, character_id, kind, amount, fee_amount, balance_after, counterparty_character_id, counterparty_name, status, description) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            { transactionId, charId, kind, amount, math.max(0, tonumber(feeAmount) or 0), balanceAfter, counterpartyCharId, counterpartyName, tostring(status or 'completed'), description }
        )
    end)
    if not ok then dbg('Failed to record bank transaction:', transactionId, err) end
    return ok
end

-- v1.8.0: technical numeric safety, not a gameplay limit (transaction
-- amounts are intentionally uncapped — see CHANGELOG_v1.8.0.md). Lua's
-- tonumber() will happily parse "nan"/"inf"/"infinity" into non-finite
-- floats, and math.floor() on those stays non-finite; every amount that
-- reaches SQL must be a finite, non-negative integer that fits in the
-- database's INT column (MySQL INT max is 2147483647) so it can never be
-- silently truncated or corrupt a downstream comparison. Anything invalid
-- resolves to 0, which every existing minAmount floor already rejects.
local SAFE_MAX_AMOUNT = 2000000000
local function sanitizeAmount(raw)
    local n = tonumber(raw)
    if type(n) ~= 'number' or n ~= n or n == math.huge or n == -math.huge then return 0 end
    n = math.floor(n)
    if n < 0 then return 0 end
    if n > SAFE_MAX_AMOUNT then return SAFE_MAX_AMOUNT end
    return n
end

-- v1.8.0: the one player-facing string every recovery_required outcome
-- returns. Deliberately generic — it never names which internal step failed
-- (that detail only goes to adminLog/cm-admin) so a player can't learn
-- anything about server internals from a failure message, but the reference
-- is real and support staff can trace it straight back through
-- cm_bank_operation_journal.
local function recoveryRequiredMessage(txId)
    return ('The banking operation could not be completed safely. Reference: %s.'):format(txId)
end

-- Strips control characters (including newlines) and clamps length so a
-- transfer note can never break log/DB formatting or carry hidden bytes.
-- The NUI only ever assigns this to textContent, never innerHTML, so no
-- HTML-escaping is required here — this is a plain-text sanitizer.
local function sanitizeNote(note)
    note = tostring(note or ''):gsub('[%c]', ' ')
    note = note:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s%s+', ' ')
    if #note > 120 then note = note:sub(1, 120) end
    return note ~= '' and note or nil
end

-- v1.7.0: a payee nickname is a purely cosmetic personal label — strips
-- control characters exactly like sanitizeNote, capped at
-- Config.Payees.nicknameMaxLength. The NUI only ever assigns it via
-- textContent, never innerHTML, so no HTML-escaping is required here either.
local function sanitizeNickname(nickname)
    local maxLength = math.max(1, tonumber(Config.Payees and Config.Payees.nicknameMaxLength) or 40)
    nickname = tostring(nickname or ''):gsub('[%c]', ' ')
    nickname = nickname:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s%s+', ' ')
    if #nickname > maxLength then nickname = nickname:sub(1, maxLength) end
    return nickname ~= '' and nickname or nil
end

-- Resolves whether a Character ID exists and its display name, whether that
-- character is currently online or not. Never trust a name supplied by NUI —
-- this is the single source of truth used both for the pre-transfer
-- confirmation lookup and for the transfer itself.
local function resolveCharacterIdentity(charId)
    local onlineSrc = getSourceByCharId(charId)
    if onlineSrc and isLoaded(onlineSrc) and getCharId(onlineSrc) == charId then
        local name = getCharName(onlineSrc)
        if name then return true, name, onlineSrc end
    end
    local offlineName = getCharacterNameByIdOffline(charId)
    if offlineName then return true, offlineName, nil end
    return false, nil, nil
end

-- One efficient aggregate query per panel-open instead of scanning full
-- history client-side. Excludes rolled-back/failed rows so numbers reflect
-- money that actually moved.
-- v1.7.0: shared by the Today and This Month dashboard tiles. Only rows that
-- actually completed count — failed/rolled-back/recovery_required operations
-- never moved real money (or their outcome is still unresolved), so they're
-- excluded everywhere a "how much money moved" total is shown.
local function fetchPeriodSummary(charId, sinceSql)
    if not charId then return { moneyIn = 0, moneyOut = 0, feesPaid = 0 } end
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT
                COALESCE(SUM(CASE WHEN kind IN ('deposit','transfer_in','atm_earnings','atm_sale') THEN amount ELSE 0 END), 0) AS money_in,
                COALESCE(SUM(CASE WHEN kind IN ('withdraw','transfer_out','atm_purchase','atm_restock') THEN amount ELSE 0 END), 0) AS money_out,
                COALESCE(SUM(fee_amount), 0) AS fees_paid
            FROM bank_transactions
            WHERE character_id = ? AND created_at >= ]] .. sinceSql .. [[ AND status NOT IN ('rolled_back', 'failed', 'recovery_required')
        ]], { charId })
    end)
    if not ok or not row then return { moneyIn = 0, moneyOut = 0, feesPaid = 0 } end
    return {
        moneyIn = tonumber(row.money_in) or 0,
        moneyOut = tonumber(row.money_out) or 0,
        feesPaid = tonumber(row.fees_paid) or 0,
    }
end

local function fetchTodaySummary(charId)
    return fetchPeriodSummary(charId, 'CURDATE()')
end

local function fetchMonthSummary(charId)
    return fetchPeriodSummary(charId, "DATE_FORMAT(NOW(), '%Y-%m-01')")
end

-- Transfers only (sent/received count + amount) for the current calendar
-- month — the "Transfers This Month" dashboard tile.
local function fetchMonthlyTransferSummary(charId)
    if not charId then return { sentCount = 0, receivedCount = 0, moneySent = 0, moneyReceived = 0 } end
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT
                COALESCE(SUM(CASE WHEN kind = 'transfer_out' THEN 1 ELSE 0 END), 0) AS sent_count,
                COALESCE(SUM(CASE WHEN kind = 'transfer_in' THEN 1 ELSE 0 END), 0) AS received_count,
                COALESCE(SUM(CASE WHEN kind = 'transfer_out' THEN amount ELSE 0 END), 0) AS money_sent,
                COALESCE(SUM(CASE WHEN kind = 'transfer_in' THEN amount ELSE 0 END), 0) AS money_received
            FROM bank_transactions
            WHERE character_id = ? AND kind IN ('transfer_out', 'transfer_in')
              AND created_at >= DATE_FORMAT(NOW(), '%Y-%m-01') AND status NOT IN ('rolled_back', 'failed', 'recovery_required')
        ]], { charId })
    end)
    if not ok or not row then return { sentCount = 0, receivedCount = 0, moneySent = 0, moneyReceived = 0 } end
    return {
        sentCount = tonumber(row.sent_count) or 0,
        receivedCount = tonumber(row.received_count) or 0,
        moneySent = tonumber(row.money_sent) or 0,
        moneyReceived = tonumber(row.money_received) or 0,
    }
end

local function fetchSavedPayees(charId)
    if not charId then return {} end
    local ok, rows = pcall(function()
        return MySQL.query.await(
            'SELECT id, recipient_character_id, nickname, is_favourite FROM bank_saved_payees WHERE owner_character_id = ? ORDER BY is_favourite DESC, nickname ASC',
            { charId }
        )
    end)
    if not ok or type(rows) ~= 'table' then return {} end
    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        out[#out + 1] = {
            id = tonumber(row.id),
            recipientCharacterId = tonumber(row.recipient_character_id),
            nickname = row.nickname,
            isFavourite = (tonumber(row.is_favourite) or 0) == 1,
        }
    end
    return out
end

-- v1.8.0: up to 5 most-recently-transferred-to Character IDs, for the
-- "Recent" quick-fill list on the Transfer tab. Uses the existing
-- (character_id, created_at) / (counterparty_character_id, created_at)
-- indexes via a portable "latest row per group" self-join (no window
-- functions, so this works on older MySQL/MariaDB too) instead of a new
-- table. Selecting one only pre-fills the Character ID — never transfers.
local function fetchRecentPayees(charId)
    if not charId then return {} end
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT bt.counterparty_character_id, bt.counterparty_name, bt.amount, bt.created_at
            FROM bank_transactions bt
            INNER JOIN (
                SELECT counterparty_character_id, MAX(created_at) AS max_created
                FROM bank_transactions
                WHERE character_id = ? AND kind = 'transfer_out' AND counterparty_character_id IS NOT NULL
                GROUP BY counterparty_character_id
            ) latest ON bt.counterparty_character_id = latest.counterparty_character_id AND bt.created_at = latest.max_created
            WHERE bt.character_id = ? AND bt.kind = 'transfer_out'
            ORDER BY bt.created_at DESC
            LIMIT 5
        ]], { charId, charId })
    end)
    if not ok or type(rows) ~= 'table' then return {} end
    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        out[#out + 1] = {
            characterId = tonumber(row.counterparty_character_id),
            name = row.counterparty_name,
            lastAmount = tonumber(row.amount) or 0,
            time = row.created_at and tostring(row.created_at) or nil,
        }
    end
    return out
end

local function fetchRecentTransactions(charId)
    if not charId then return {} end
    local ok, rows = pcall(function()
        return MySQL.query.await(
            'SELECT transaction_id, kind, amount, fee_amount, balance_after, counterparty_name, status, created_at FROM bank_transactions WHERE character_id = ? ORDER BY created_at DESC LIMIT ?',
            { charId, ACTIVITY_LIMIT }
        )
    end)
    if not ok or type(rows) ~= 'table' then return {} end
    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        out[#out + 1] = {
            transactionId = row.transaction_id,
            kind = row.kind,
            amount = tonumber(row.amount) or 0,
            feeAmount = tonumber(row.fee_amount) or 0,
            counterpartyName = row.counterparty_name,
            status = row.status or 'completed',
            time = row.created_at and tostring(row.created_at) or nil,
        }
    end
    return out
end

local function underCooldown(tbl, key, cooldownMs)
    local now = GetGameTimer()
    if now - (tbl[key] or 0) < cooldownMs then return true end
    tbl[key] = now
    return false
end

local function sendResult(src, action, ok, message, extra)
    local result = type(extra) == 'table' and extra or {}
    result.ok = ok == true
    result.message = tostring(message or '')
    result.cash, result.bank = getBalances(src)
    TriggerClientEvent('cm-bank:client:actionResult', src, action, result)
end

-- v1.6.0 ATM cash-reserve business system ----------------------------------

local function defaultCapacityForAtm(atm)
    if atm and atm.ownerCharacterId then
        return math.max(1, tonumber(Config.ATMBusiness and Config.ATMBusiness.defaultCashCapacity) or 100000)
    end
    return math.max(1, tonumber(Config.PublicATM and Config.PublicATM.defaultCashCapacity) or 250000)
end

-- Public/unowned ATMs can opt out of the reserve system entirely (either via
-- an explicit infinite-cash override or by disabling reserve tracking).
-- Player-owned ATMs are never allowed to take this path.
local function publicAtmIsUnlimited()
    local cfg = Config.PublicATM or {}
    return cfg.useCashReserve == false or cfg.infiniteCash == true
end

local function atmReserveIsLimited(accessType, atm)
    if accessType ~= 'atm' or not atm then return false end
    if atm.ownerCharacterId then return true end
    return not publicAtmIsUnlimited()
end

local function atmReserveStatus(atm)
    if not atm then return 'operational' end
    if atm.adminDisabled then return 'disabled' end
    if not atm.verified then return 'pending_verification' end
    if not atm.ownerCharacterId and publicAtmIsUnlimited() then return 'operational' end

    local capacity = math.max(1, tonumber(atm.cashCapacity) or defaultCapacityForAtm(atm))
    local reserve = math.max(0, tonumber(atm.cashReserve) or 0)
    if reserve <= 0 then return 'out_of_cash' end

    local thresholds = (Config.ATMBusiness and Config.ATMBusiness.reserveStatus) or {}
    local criticalPct = tonumber(thresholds.criticalPercent) or 10
    local lowPct = tonumber(thresholds.lowPercent) or 25
    local pct = reserve / capacity * 100
    if pct <= criticalPct then return 'critical' end
    if pct <= lowPct then return 'low' end
    return 'operational'
end

local RESERVE_STATUS_SEVERITY = { operational = 0, low = 1, critical = 2, out_of_cash = 3 }

-- Atomically claims `amount` of physical cash out of an ATM's reserve via a
-- compare-and-set UPDATE, so two concurrent withdrawals can never both
-- succeed against the same last dollars. Updates the in-memory cache only on
-- confirmed success.
local function claimAtmReserve(atmKey, atm, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local ok, affected = pcall(function()
        return MySQL.update.await(
            'UPDATE bank_atm_locations SET cash_reserve = cash_reserve - ? WHERE coord_key = ? AND cash_reserve >= ? AND verified = 1',
            { amount, atmKey, amount }
        )
    end)
    if not ok or tonumber(affected) ~= 1 then return false end
    atm.cashReserve = math.max(0, (tonumber(atm.cashReserve) or 0) - amount)
    return true
end

-- Best-effort refund of a previously-claimed amount (rollback path). Never
-- exceeds capacity. Returns whether the refund persisted.
local function refundAtmReserve(atmKey, atm, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local ok, affected = pcall(function()
        return MySQL.update.await(
            'UPDATE bank_atm_locations SET cash_reserve = LEAST(cash_capacity, cash_reserve + ?) WHERE coord_key = ?',
            { amount, atmKey }
        )
    end)
    if not ok or tonumber(affected) ~= 1 then
        dbg('Failed to refund ATM reserve claim:', atmKey, amount)
        return false
    end
    local capacity = tonumber(atm.cashCapacity) or defaultCapacityForAtm(atm)
    atm.cashReserve = math.min(capacity, (tonumber(atm.cashReserve) or 0) + amount)
    return true
end

-- Adds cash into an ATM's reserve, capped at capacity, returning the amount
-- actually absorbed (may be less than requested, or 0 if already full).
-- Used by both deposit contribution and owner restock. Never overflows.
local function contributeAtmReserve(atmKey, atm, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or not atm then return 0 end
    local capacity = math.max(0, tonumber(atm.cashCapacity) or defaultCapacityForAtm(atm))
    local current = math.max(0, tonumber(atm.cashReserve) or 0)
    local room = math.max(0, capacity - current)
    local contribution = math.min(amount, room)
    if contribution <= 0 then return 0 end

    local ok, affected = pcall(function()
        return MySQL.update.await(
            'UPDATE bank_atm_locations SET cash_reserve = LEAST(cash_capacity, cash_reserve + ?) WHERE coord_key = ? AND verified = 1',
            { contribution, atmKey }
        )
    end)
    if not ok or tonumber(affected) ~= 1 then return 0 end
    atm.cashReserve = math.min(capacity, current + contribution)
    return contribution
end

-- Records one ATM-scoped business event (owner dashboard history/analytics).
-- Deliberately owner-gated: public/unowned ATMs have no owner to view this,
-- so nothing is recorded for them (keeps the table bounded and useful).
local function recordAtmActivity(atm, kind, actorCharId, amount, feeAmount, transactionId)
    if not atm or not atm.ownerCharacterId or not atm.id then return false end
    local ok, err = pcall(function()
        MySQL.query.await(
            'INSERT INTO bank_atm_activity (atm_id, transaction_id, kind, actor_character_id, amount, fee_amount, reserve_after) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { atm.id, transactionId, kind, actorCharId, math.floor(tonumber(amount) or 0),
              math.max(0, tonumber(feeAmount) or 0), math.max(0, tonumber(atm.cashReserve) or 0) }
        )
    end)
    if not ok then dbg('Failed to record ATM business activity:', atm.id, kind, err) end
    return ok
end

-- Notifies an online owner only when reserve status just got worse than it
-- was before this operation (never spams on every withdrawal, never builds
-- an offline notification queue — the dashboard is enough for offline owners).
local function notifyOwnerIfReserveWorsened(atm, statusBefore)
    if not atm or not atm.ownerCharacterId then return end
    local statusAfter = atmReserveStatus(atm)
    if (RESERVE_STATUS_SEVERITY[statusAfter] or 0) <= (RESERVE_STATUS_SEVERITY[statusBefore] or 0) then return end

    local ownerSrc = getSourceByCharId(atm.ownerCharacterId)
    if not ownerSrc then return end

    local capacity = math.max(1, tonumber(atm.cashCapacity) or defaultCapacityForAtm(atm))
    local reserve = math.max(0, tonumber(atm.cashReserve) or 0)
    local label = statusAfter == 'out_of_cash' and 'is out of cash' or ('is running ' .. statusAfter:gsub('_', ' '))
    TriggerClientEvent('cm-bank:client:atmNotice', ownerSrc, ('ATM #%d %s. Reserve: $%d / $%d'):format(atm.id or 0, label, reserve, capacity), 'error')
end

-- v1.8.0: mirror of notifyOwnerIfReserveWorsened for the opposite direction —
-- fires exactly once, only on the transition back to fully 'operational'
-- (e.g. after a restock), never on every restock regardless of outcome.
local function notifyOwnerIfReserveRecovered(atm, statusBefore)
    if not atm or not atm.ownerCharacterId then return end
    if statusBefore == 'operational' then return end
    local statusAfter = atmReserveStatus(atm)
    if statusAfter ~= 'operational' then return end

    local ownerSrc = getSourceByCharId(atm.ownerCharacterId)
    if not ownerSrc then return end

    TriggerClientEvent('cm-bank:client:atmNotice', ownerSrc, ('ATM #%d is operational again.'):format(atm.id or 0), 'success')
end

local function buildAtmView(atmKey, atm, charId)
    if not atm then
        return {
            key = atmKey, id = nil, owned = false, isOwner = false, ownerName = nil, contact = nil,
            feePercent = 0, disabled = false, forSale = true, pendingEarnings = 0,
            cashReserve = 0, cashCapacity = 0, reserveStatus = 'operational', reserveUnlimited = true,
            ownerReserveContribution = 0,
        }
    end
    local isOwner = atm.ownerCharacterId ~= nil and atm.ownerCharacterId == charId
    local unlimited = not atm.ownerCharacterId and publicAtmIsUnlimited()
    return {
        key = atmKey,
        id = atm.id,
        owned = atm.ownerCharacterId ~= nil,
        isOwner = isOwner,
        ownerName = atm.ownerName,
        -- The owner chose to publish this, so it's fine to show any viewer.
        contact = atm.contact,
        feePercent = atm.feePercent or 0,
        disabled = atm.adminDisabled == true,
        forSale = atm.forSale ~= false,
        -- Only ever reveal the business balance to the owner standing at it.
        pendingEarnings = isOwner and (atm.pendingEarnings or 0) or 0,
        -- Reserve/capacity/status are operational info every visitor needs to
        -- judge "will my withdrawal work" — not private owner finances.
        cashReserve = math.max(0, tonumber(atm.cashReserve) or 0),
        cashCapacity = math.max(1, tonumber(atm.cashCapacity) or defaultCapacityForAtm(atm)),
        reserveStatus = atmReserveStatus(atm),
        reserveUnlimited = unlimited,
        -- Owner-only business accounting, never shown to other players.
        ownerReserveContribution = isOwner and (atm.ownerReserveContribution or 0) or 0,
    }
end

-- Withdrawal fee charged at an ATM. Deposits and character-ID transfers are
-- not charged an ATM-owner fee in v1.4. Tellers are always free.
-- - No owner: flat unownedFeePercent service fee (burned).
-- - Owner using their own ATM: free.
-- - Anyone else at an owned ATM: the owner's chosen 1/2/3/4% fee.
local function effectiveWithdrawalFeePercent(atm, actingCharId)
    if not atm then return 0 end
    if not atm.ownerCharacterId then
        return math.max(0, tonumber(Config.Ownership and Config.Ownership.unownedFeePercent) or 0)
    end
    if atm.ownerCharacterId == actingCharId then return 0 end
    local fee = tonumber(atm.feePercent) or 0
    return fee < 0 and 0 or fee
end

local function defaultFeePercent()
    local choices = (Config.Ownership and Config.Ownership.feeChoices) or {}
    return tonumber(choices[1]) or 0
end

local function isValidFeeChoice(feePercent)
    local choices = (Config.Ownership and Config.Ownership.feeChoices) or {}
    for _, c in ipairs(choices) do
        if tonumber(c) == feePercent then return true end
    end
    return false
end

local function accrueAtmEarnings(atmKey, atm, amount)
    amount = math.floor(tonumber(amount) or 0)
    if not atmKey or not atm or amount <= 0 or not atm.ownerCharacterId then return false end

    local ok, affected = pcall(function()
        return MySQL.update.await(
            'UPDATE bank_atm_locations SET pending_earnings = pending_earnings + ? WHERE coord_key = ? AND verified = 1 AND owner_character_id = ?',
            { amount, atmKey, atm.ownerCharacterId }
        )
    end)
    if not ok or tonumber(affected) ~= 1 then
        dbg('Failed to persist ATM earnings accrual:', atmKey, affected)
        return false
    end

    atm.pendingEarnings = (atm.pendingEarnings or 0) + amount
    return true
end

local function findNearestAtmKey(coords, maxDist, verifiedOnly)
    local bestKey, bestDist = nil, maxDist
    for key, atm in pairs(atmLocations) do
        if not verifiedOnly or atm.verified == true then
            local dist = #(coords - vector3(atm.x, atm.y, atm.z))
            if dist < bestDist then
                bestDist = dist
                bestKey = key
            end
        end
    end
    return bestKey
end

-- Is this player physically near a bank teller? Checked before any ATM
-- match so a branch's own street ATM (very common for Fleeca-style
-- buildings) never leaks its fee/ownership onto the teller — tellers are
-- always free with no owner, regardless of what's nearby.
local function currentTellerForPlayer(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    local maxDist = (tonumber(Config.Tellers and Config.Tellers.interactDistance) or 1.8) + 2.5
    local bestDist, closest = maxDist, nil
    for _, t in pairs(tellers) do
        local dist = #(coords - vector3(t.x, t.y, t.z))
        if dist < bestDist then
            bestDist = dist
            closest = t
        end
    end
    return closest
end

-- Server-authoritative "which ATM is this player physically at" — never
-- trust a client-supplied ATM identifier for fee/ownership/disable checks.
-- Radius is generous enough to cover normal lag/position-tick slack around
-- interactDistance without letting a player claim an ATM across the map.
local function currentAtmForPlayer(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil, nil end
    if currentTellerForPlayer(src) then return nil, nil end
    local key = findNearestAtmKey(GetEntityCoords(ped), (tonumber(Config.interactDistance) or 1.6) + 2.5, true)
    return key, key and atmLocations[key] or nil
end

local function findOwnedAtmByChar(charId)
    if not charId then return nil, nil end
    for key, atm in pairs(atmLocations) do
        if atm.ownerCharacterId == charId then return key, atm end
    end
    return nil, nil
end

local function countOwnedAtmsByChar(charId)
    if not charId then return 0 end
    local count = 0
    for _, atm in pairs(atmLocations) do
        if atm.ownerCharacterId == charId then count = count + 1 end
    end
    return count
end

local function resolveBankAccess(src)
    local teller = currentTellerForPlayer(src)
    if teller then return 'teller', nil, nil, teller end

    local atmKey, atm = currentAtmForPlayer(src)
    if atm then return 'atm', atmKey, atm, nil end
    return nil, nil, nil, nil
end

-- Admin targeting: an explicit ATM number (its DB id) takes priority so
-- staff can manage a machine without traveling to it; otherwise falls back
-- to proximity, matching the existing /atmdisable convention.
local function resolveAtmTarget(src, numberArg)
    local num = tonumber(numberArg)
    if num then
        for key, atm in pairs(atmLocations) do
            if atm.id == num then return key, atm end
        end
        return nil, nil
    end
    local coords = GetEntityCoords(GetPlayerPed(src))
    local key = findNearestAtmKey(coords, 5.0)
    return key, key and atmLocations[key] or nil
end

-- Resolves a character's display name even when they're offline, for admin
-- ownership assignment. cm-characters owns the `characters` table; this is a
-- read-only cross-resource query, the same pattern cm-admin's own offline
-- character search already uses.
local function getCharacterNameByIdOffline(charId)
    local ok, row = pcall(function()
        return MySQL.single.await('SELECT first_name, last_name FROM characters WHERE id = ? LIMIT 1', { charId })
    end)
    if not ok or not row then return nil end
    local full = (tostring(row.first_name or '') .. ' ' .. tostring(row.last_name or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return full ~= '' and full or nil
end

local function persistOwnershipToggle(src, enabled)
    ownershipEnabled = enabled == true
    local ok, err = pcall(function()
        MySQL.query.await(
            'INSERT INTO cm_bank_settings (setting_key, setting_value, updated_by) VALUES (?, ?, ?) ' ..
            'ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)',
            { 'ownership_enabled', ownershipEnabled and 'true' or 'false', tostring(getCharId(src) or ('src:' .. tostring(src))) }
        )
    end)
    if not ok then dbg('Failed to persist ownership_enabled setting:', err) end

    adminLog(src, 'bank_atm_ownership_toggle', { category = 'players', enabled = ownershipEnabled }, nil, nil)
    TriggerClientEvent('cm-bank:client:ownershipToggled', -1, ownershipEnabled)
end

local function persistAtmDisabled(src, atmKey, atm, disabled)
    local newDisabled = disabled == true
    local ok, affected = pcall(function()
        return MySQL.update.await(
            'UPDATE bank_atm_locations SET admin_disabled = ? WHERE coord_key = ?',
            { newDisabled and 1 or 0, atmKey }
        )
    end)
    if not ok or tonumber(affected) ~= 1 then
        dbg('Failed to persist ATM disable state:', atmKey, affected)
        return false
    end

    atm.adminDisabled = newDisabled
    adminLog(src, 'bank_atm_admin_disable', { category = 'players', atmKey = atmKey, disabled = atm.adminDisabled }, 'atm:' .. atmKey, atm.ownerName)
    return true
end

RegisterNetEvent('cm-bank:server:requestAtmSync', function()
    local src = source
    if not waitUntilBankReady(10000) then return end

    local list = {}
    for _, atm in pairs(atmLocations) do
        if atm.verified == true then
            list[#list + 1] = { x = atm.x, y = atm.y, z = atm.z }
        end
    end
    TriggerClientEvent('cm-bank:client:syncAtmBlips', src, list)
end)

RegisterNetEvent('cm-bank:server:requestTellerSync', function()
    local src = source
    if not waitUntilBankReady(10000) then return end

    local list = {}
    for _, t in pairs(tellers) do list[#list + 1] = t end
    TriggerClientEvent('cm-bank:client:syncTellers', src, list)
end)

-- Client discovery is advisory only in v1.4. Static world ATM props are not
-- server-authoritative entities, so a client can suggest a coordinate but it
-- cannot create a usable/ownable ATM. New reports are persisted as unverified
-- and fail closed until an admin approves the location with /atmverify.
RegisterNetEvent('cm-bank:server:reportAtm', function(coords)
    local src = source
    if not bankReady or not isLoaded(src) then return end
    if underCooldown(atmReportCooldowns, src, tonumber(Config.Security.atmReportCooldownMs) or 2000) then return end
    if type(coords) ~= 'table' then return end

    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end
    if math.abs(x) > 8000 or math.abs(y) > 8000 or z < -500 or z > 1500 then return end

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local playerCoords = GetEntityCoords(ped)
    local reportDistance = #(playerCoords - vector3(x, y, z))
    local maxReportDistance = tonumber(Config.Security.atmReportMaxPlayerDistance)
        or ((tonumber(Config.detectDistance) or 20.0) + 3.0)
    if reportDistance > maxReportDistance then return end

    local key = CMBank.CoordKey(x, y, z)
    if atmLocations[key] then return end

    local entry = {
        x = x, y = y, z = z,
        feePercent = 0, pendingEarnings = 0,
        adminDisabled = false, forSale = false, verified = false,
    }

    local ok, insertId = pcall(function()
        return MySQL.insert.await([[
            INSERT IGNORE INTO bank_atm_locations
                (coord_key, x, y, z, fee_percent, pending_earnings, admin_disabled, for_sale, verified)
            VALUES (?, ?, ?, ?, 0, 0, 0, 0, 0)
        ]], { key, x, y, z })
    end)
    if not ok then
        dbg('Failed to persist unverified ATM discovery:', insertId)
        return
    end

    if not insertId or tonumber(insertId) == 0 then
        local row = MySQL.single.await(
            'SELECT id, verified, for_sale FROM bank_atm_locations WHERE coord_key = ? LIMIT 1',
            { key }
        )
        if not row then return end
        entry.id = tonumber(row.id)
        entry.verified = (tonumber(row.verified) or 0) == 1
        entry.forSale = (tonumber(row.for_sale) or 0) == 1
    else
        entry.id = tonumber(insertId)
    end

    atmLocations[key] = entry
    dbg(('ATM discovery pending verification: No. %d @ %.2f %.2f %.2f'):format(entry.id or 0, x, y, z))
end)

RegisterNetEvent('cm-bank:server:requestOpen', function()
    local src = source
    if not bankReady then
        TriggerClientEvent('cm-bank:client:openDenied', src, 'Banking is still starting. Please try again.')
        return
    end
    if not isLoaded(src) then
        TriggerClientEvent('cm-bank:client:openDenied', src, 'You are not fully logged in yet.')
        return
    end

    local accessType, atmKey, atm, teller = resolveBankAccess(src)
    if not accessType then
        TriggerClientEvent('cm-bank:client:openDenied', src, 'You need to be at a verified ATM or bank teller.')
        return
    end
    if atm and atm.adminDisabled then
        TriggerClientEvent('cm-bank:client:openDenied', src, 'This ATM is out of service.')
        return
    end

    local charId = getCharId(src)
    if not charId then
        TriggerClientEvent('cm-bank:client:openDenied', src, 'Your character could not be identified.')
        return
    end

    local cash, bank = getBalances(src)
    local _, ownedAtm = findOwnedAtmByChar(charId)

    TriggerClientEvent('cm-bank:client:openMenu', src, {
        source = accessType,
        tellerName = teller and teller.name or nil,
        cash = cash,
        bank = bank,
        limits = Config.Limits,
        transferLimits = Config.TransferLimits,
        transferSecurity = {
            largeTransferWarning = tonumber(Config.TransferSecurity and Config.TransferSecurity.largeTransferWarning) or 0,
        },
        today = fetchTodaySummary(charId),
        thisMonth = fetchMonthSummary(charId),
        monthlyTransfers = fetchMonthlyTransferSummary(charId),
        transactions = fetchRecentTransactions(charId),
        payees = fetchSavedPayees(charId),
        recentPayees = fetchRecentPayees(charId),
        payeeLimits = {
            maxPayees = tonumber(Config.Payees and Config.Payees.maxPayees) or 30,
            maxFavourites = tonumber(Config.Payees and Config.Payees.maxFavourites) or 6,
            nicknameMaxLength = tonumber(Config.Payees and Config.Payees.nicknameMaxLength) or 40,
        },
        atm = buildAtmView(atmKey, atm, charId),
        ownership = {
            enabled = ownershipEnabled,
            purchasePrice = tonumber(Config.Ownership and Config.Ownership.purchasePrice) or 0,
            unownedFeePercent = tonumber(Config.Ownership and Config.Ownership.unownedFeePercent) or 0,
            feeChoices = (Config.Ownership and Config.Ownership.feeChoices) or { 1, 2, 3, 4 },
            governmentSellPercent = tonumber(Config.Ownership and Config.Ownership.governmentSellPercent) or 80,
            ownedAtmId = ownedAtm and ownedAtm.id or nil,
            defaultCashCapacity = tonumber(Config.ATMBusiness and Config.ATMBusiness.defaultCashCapacity) or 100000,
            purchaseStartingReserve = tonumber(Config.ATMBusiness and Config.ATMBusiness.purchaseStartingReserve) or 25000,
        },
    })
end)

RegisterNetEvent('cm-bank:server:closeSession', function()
    -- v1.4 has no client-trusted session state; position is revalidated for
    -- every operation, so closing the NUI has nothing authoritative to release.
end)

RegisterNetEvent('cm-bank:server:deposit', function(amount)
    local src = source
    amount = sanitizeAmount(amount)

    if not bankReady then return sendResult(src, 'deposit', false, 'Banking is not ready yet.') end
    if not isLoaded(src) then return sendResult(src, 'deposit', false, 'You are not fully logged in.') end
    if underCooldown(actionCooldowns, src, tonumber(Config.Security.actionCooldownMs) or 900) then
        return sendResult(src, 'deposit', false, 'Please wait a moment and try again.')
    end

    local charId = getCharId(src)
    if not charId then return sendResult(src, 'deposit', false, 'Your character could not be identified.') end

    local preAccess, preAtmKey, preAtm = resolveBankAccess(src)
    if not preAccess then return sendResult(src, 'deposit', false, 'You need to be at a verified ATM or bank teller.') end
    if preAtm and preAtm.adminDisabled then return sendResult(src, 'deposit', false, 'This ATM is out of service.') end

    local lockKeys = { 'money:' .. charId }
    if preAtm and preAtm.id then lockKeys[#lockKeys + 1] = 'atm:' .. tostring(preAtm.id) end

    local ran, opOk, message, extra = runLocked(lockKeys, function()
        local accessType, atmKey, atm = resolveBankAccess(src)
        if not accessType then return false, 'You need to be at a verified ATM or bank teller.' end
        if preAtmKey and atmKey ~= preAtmKey then return false, 'Your ATM position changed. Try again.' end
        if atm and atm.adminDisabled then return false, 'This ATM is out of service.' end
        if not isLoaded(src) then return false, 'You are not fully logged in.' end

        -- v1.7.0: no gameplay maximum. The only real constraints are a
        -- positive-integer floor and whether the player actually has the cash.
        local minAmount = tonumber((Config.Limits or {}).minAmount) or 1
        if amount < minAmount then return false, 'Enter a valid amount.' end
        if not canAfford(src, 'cash', amount) then return false, 'You do not have that much cash.' end

        local txId = newTransactionId('DEP', src)
        if not beginOperation(txId, 'deposit', charId, nil, amount, { access = accessType }) then
            return false, 'The bank audit service is unavailable. Try again.'
        end

        if not transferOwnAccounts(src, 'cash', 'bank', amount, 'bank_deposit:' .. txId) then
            finishOperation(txId, 'rolled_back', { reason = 'playerdata_transfer_failed' })
            return false, 'The deposit could not be completed.'
        end

        -- ATM reserve contribution never gates or reverses a deposit that has
        -- already succeeded — it is a best-effort side effect, capped at
        -- capacity. Overflow beyond capacity simply does not increase reserve.
        local reserveContribution = 0
        if accessType == 'atm' and atm and atmReserveIsLimited(accessType, atm) then
            reserveContribution = contributeAtmReserve(atmKey, atm, amount)
        end

        local _, newBank = getBalances(src)
        recordTransaction(charId, 'deposit', amount, newBank, nil, nil, txId, 0)
        finishOperation(txId, 'committed', { balanceAfter = newBank, atmReserveContribution = reserveContribution })
        if reserveContribution > 0 then
            recordAtmActivity(atm, 'deposit', charId, amount, 0, txId)
        end
        adminLog(src, 'bank_deposit', {
            category = 'players', transactionId = txId, amount = amount, fee = 0, bank = newBank,
            atmReserveContribution = reserveContribution,
        }, 'character:' .. tostring(charId), getCharName(src))

        return true, ('Deposited $%d.'):format(amount), {
            amount = amount, transactionId = txId, atmReserveContribution = reserveContribution,
            atm = (accessType == 'atm' and atm) and buildAtmView(atmKey, atm, charId) or nil,
        }
    end)

    if not ran then
        return sendResult(src, 'deposit', false, opOk == 'busy' and 'Another money operation is already processing.' or 'The deposit could not be completed.')
    end
    sendResult(src, 'deposit', opOk, message, extra)
end)

RegisterNetEvent('cm-bank:server:withdraw', function(amount)
    local src = source
    amount = sanitizeAmount(amount)

    if not bankReady then return sendResult(src, 'withdraw', false, 'Banking is not ready yet.') end
    if not isLoaded(src) then return sendResult(src, 'withdraw', false, 'You are not fully logged in.') end
    if underCooldown(actionCooldowns, src, tonumber(Config.Security.actionCooldownMs) or 900) then
        return sendResult(src, 'withdraw', false, 'Please wait a moment and try again.')
    end

    local charId = getCharId(src)
    if not charId then return sendResult(src, 'withdraw', false, 'Your character could not be identified.') end

    local preAccess, preAtmKey, preAtm = resolveBankAccess(src)
    if not preAccess then return sendResult(src, 'withdraw', false, 'You need to be at a verified ATM or bank teller.') end
    if preAtm and preAtm.adminDisabled then return sendResult(src, 'withdraw', false, 'This ATM is out of service.') end

    local lockKeys = { 'money:' .. charId }
    if preAtm and preAtm.id then lockKeys[#lockKeys + 1] = 'atm:' .. tostring(preAtm.id) end

    local ran, opOk, message, extra = runLocked(lockKeys, function()
        local accessType, atmKey, atm = resolveBankAccess(src)
        if not accessType then return false, 'You need to be at a verified ATM or bank teller.' end
        if preAtmKey and atmKey ~= preAtmKey then return false, 'Your ATM position changed. Try again.' end
        if atm and atm.adminDisabled then return false, 'This ATM is out of service.' end
        if not isLoaded(src) then return false, 'You are not fully logged in.' end

        -- v1.7.0: no gameplay maximum. Bank balance and (for ATMs) physical
        -- cash reserve are the only real constraints on how much comes out.
        local minAmount = tonumber((Config.Limits or {}).minAmount) or 1
        if amount < minAmount then return false, 'Enter a valid amount.' end
        if not canAfford(src, 'bank', amount) then return false, 'You do not have that much in the bank.' end

        local feePercent = accessType == 'atm' and effectiveWithdrawalFeePercent(atm, charId) or 0
        feePercent = math.max(0, math.min(100, tonumber(feePercent) or 0))
        local fee = math.floor(amount * feePercent / 100)
        local credited = amount - fee
        if credited <= 0 then return false, 'The withdrawal amount is too small after fees.' end

        -- v1.6.0: the ATM's physical cash reserve is a separate pool from the
        -- withdrawal fee. Only the dispensed `amount` consumes it; the fee
        -- still flows to pending_earnings exactly as before. Teller
        -- withdrawals and unlimited public ATMs never touch a reserve.
        local reserveLimited = atmReserveIsLimited(accessType, atm)
        local statusBeforeWithdraw = reserveLimited and atmReserveStatus(atm) or nil
        if reserveLimited then
            local availableReserve = math.max(0, tonumber(atm.cashReserve) or 0)
            if availableReserve < amount then
                return false, ('This ATM does not have enough cash for that withdrawal. Available ATM cash: $%d'):format(availableReserve)
            end
        end

        local txId = newTransactionId('WDR', src)
        if not beginOperation(txId, 'withdraw', charId, nil, amount, {
            access = accessType, atmId = atm and atm.id or nil, fee = fee, reserveLimited = reserveLimited,
        }) then
            return false, 'The bank audit service is unavailable. Try again.'
        end

        -- Claim the physical cash FIRST, before touching any player money.
        -- This is the contended resource across concurrent withdrawers at
        -- the same machine; claiming it via compare-and-set up front means a
        -- claim failure never requires unwinding any player-money changes.
        local reserveClaimed = false
        if reserveLimited then
            if not claimAtmReserve(atmKey, atm, amount) then
                finishOperation(txId, 'rolled_back', { reason = 'reserve_claim_failed' })
                return false, 'This ATM no longer has enough cash.'
            end
            reserveClaimed = true
        end

        local recoveryRequired = false
        if fee > 0 then
            if not removeMoney(src, 'bank', amount, 'bank_withdraw:' .. txId) then
                if reserveClaimed then refundAtmReserve(atmKey, atm, amount) end
                finishOperation(txId, 'rolled_back', { reason = 'remove_bank_failed' })
                return false, 'The withdrawal could not be completed.'
            end
            if not addMoney(src, 'cash', credited, 'bank_withdraw:' .. txId) then
                local refunded = addMoney(src, 'bank', amount, 'bank_withdraw_refund:' .. txId)
                if refunded and reserveClaimed then refundAtmReserve(atmKey, atm, amount) end
                finishOperation(txId, refunded and 'rolled_back' or 'recovery_required', {
                    reason = 'add_cash_failed', refundSucceeded = refunded == true, reserveClaimed = reserveClaimed,
                })
                if not refunded then
                    adminLog(src, 'bank_recovery_required', {
                        category = 'players', transactionId = txId, operation = 'withdraw', amount = amount,
                    }, 'character:' .. tostring(charId), getCharName(src))
                end
                return false, refunded and 'The withdrawal could not be completed and was refunded.' or recoveryRequiredMessage(txId)
            end

            if atm and atm.ownerCharacterId and not accrueAtmEarnings(atmKey, atm, fee) then
                -- Never silently burn an owner fee if its business balance
                -- cannot be persisted. Give it back to the withdrawing player.
                if addMoney(src, 'cash', fee, 'atm_fee_refund:' .. txId) then
                    credited = amount
                    fee = 0
                else
                    recoveryRequired = true
                    finishOperation(txId, 'recovery_required', { reason = 'atm_fee_accrual_and_refund_failed', fee = fee })
                    adminLog(src, 'bank_recovery_required', {
                        category = 'players', transactionId = txId, operation = 'atm_fee', fee = fee, atmId = atm.id,
                    }, 'character:' .. tostring(charId), getCharName(src))
                end
            end
        else
            if not transferOwnAccounts(src, 'bank', 'cash', amount, 'bank_withdraw:' .. txId) then
                if reserveClaimed then refundAtmReserve(atmKey, atm, amount) end
                finishOperation(txId, 'rolled_back', { reason = 'playerdata_transfer_failed' })
                return false, 'The withdrawal could not be completed.'
            end
        end

        local _, newBank = getBalances(src)
        recordTransaction(charId, 'withdraw', amount, newBank, nil, nil, txId, fee)
        if not recoveryRequired then
            finishOperation(txId, 'committed', { balanceAfter = newBank, fee = fee, cashReceived = credited })
        end
        if atm and atm.ownerCharacterId then
            recordAtmActivity(atm, 'withdrawal', charId, amount, fee, txId)
            if statusBeforeWithdraw then notifyOwnerIfReserveWorsened(atm, statusBeforeWithdraw) end
        end
        adminLog(src, 'bank_withdraw', {
            category = 'players', transactionId = txId, amount = amount, fee = fee, bank = newBank,
            atmId = atm and atm.id or nil,
        }, 'character:' .. tostring(charId), getCharName(src))

        local msg = fee > 0
            and ('Withdrew $%d (-$%d withdrawal fee).'):format(credited, fee)
            or ('Withdrew $%d.'):format(credited)
        if recoveryRequired then
            msg = msg .. (' ATM fee recovery is required; reference %s.'):format(txId)
        end
        return true, msg, {
            amount = amount, received = credited, fee = fee, transactionId = txId,
            recoveryRequired = recoveryRequired,
            atm = (accessType == 'atm' and atm) and buildAtmView(atmKey, atm, charId) or nil,
        }
    end)

    if not ran then
        return sendResult(src, 'withdraw', false, opOk == 'busy' and 'This account or ATM is already processing another operation.' or 'The withdrawal could not be completed.')
    end
    sendResult(src, 'withdraw', opOk, message, extra)
end)

RegisterNetEvent('cm-bank:server:transfer', function(targetCharId, amount, note)
    local src = source
    targetCharId = sanitizeAmount(targetCharId)
    amount = sanitizeAmount(amount)
    note = sanitizeNote(note)

    if not bankReady then return sendResult(src, 'transfer', false, 'Banking is still starting.') end
    if not isLoaded(src) then return sendResult(src, 'transfer', false, 'You are not fully logged in.') end
    if underCooldown(actionCooldowns, src, tonumber(Config.Security.actionCooldownMs) or 900) then
        return sendResult(src, 'transfer', false, 'Please wait a moment and try again.')
    end
    local transferSecurity = Config.TransferSecurity or {}
    local transferCooldownMs = tonumber(transferSecurity.cooldownMs) or tonumber(Config.Security.transferCooldownMs) or 3000
    if underCooldown(transferCooldowns, src, transferCooldownMs) then
        return sendResult(src, 'transfer', false, 'Please wait before sending another transfer.')
    end

    local senderCharId = getCharId(src)
    if not senderCharId then return sendResult(src, 'transfer', false, 'Your character could not be identified.') end
    if targetCharId <= 0 then return sendResult(src, 'transfer', false, 'Character ID not found.') end
    if targetCharId == senderCharId then return sendResult(src, 'transfer', false, 'You cannot transfer to yourself.') end

    -- Server-authoritative per-minute transfer rate limit. Independent of any
    -- client-side button disabling; a modified client cannot bypass this.
    local now = GetGameTimer()
    local recentSends = {}
    for _, t in ipairs(transferRateHistory[src] or {}) do
        if now - t < 60000 then recentSends[#recentSends + 1] = t end
    end
    transferRateHistory[src] = recentSends
    local maxPerMinute = math.max(1, math.floor(tonumber(transferSecurity.maxTransfersPerMinute) or 10))
    if #recentSends >= maxPerMinute then
        return sendResult(src, 'transfer', false, 'Transfer limit exceeded. Please slow down.')
    end

    local recipientExists, recipientKnownName = resolveCharacterIdentity(targetCharId)
    if not recipientExists then return sendResult(src, 'transfer', false, 'Character ID not found.') end

    local ran, opOk, message, extra = runLocked({
        'money:' .. tostring(senderCharId),
        'money:' .. tostring(targetCharId),
    }, function()
        local accessType, _, atm = resolveBankAccess(src)
        if not accessType then return false, 'You need to be at a verified ATM or bank teller.' end
        if atm and atm.adminDisabled then return false, 'This ATM is out of service.' end
        if not isLoaded(src) then return false, 'You are not fully logged in.' end

        -- v1.7.0: no per-transfer maximum and no daily cap. A transfer is
        -- allowed at any size as long as the sender actually has the money —
        -- rate limiting above (cooldown + per-minute cap) is spam protection,
        -- not a gameplay amount restriction, and stays in place unchanged.
        local minAmount = tonumber((Config.TransferLimits or {}).minimum) or 1
        if amount < minAmount then return false, 'Enter a valid amount.' end
        if not canAfford(src, 'bank', amount) then return false, 'You do not have that much in the bank.' end

        local transferFeePercent = math.max(0, math.min(100, tonumber((Config.Limits or {}).transferFeePercent) or 0))
        local transferFee = math.floor(amount * transferFeePercent / 100)
        local received = amount - transferFee
        if received <= 0 then return false, 'The transfer amount is too small after fees.' end

        -- Re-resolve online/offline status inside the lock (fresh, not the
        -- pre-lock snapshot) so a login/logout race can't be exploited.
        local targetSrc = getSourceByCharId(targetCharId)
        local isOnline = targetSrc ~= nil and isLoaded(targetSrc) and getCharId(targetSrc) == targetCharId

        local txId = newTransactionId('XFR', src)
        if not beginOperation(txId, 'character_transfer', senderCharId, targetCharId, amount, {
            access = accessType, transferFee = transferFee, offline = not isOnline,
        }) then
            return false, 'The bank audit service is unavailable. Try again.'
        end

        if not removeMoney(src, 'bank', amount, 'bank_transfer_out:' .. txId) then
            finishOperation(txId, 'rolled_back', { reason = 'sender_debit_failed' })
            return false, 'The transfer could not be completed.'
        end

        local senderName = getCharName(src) or GetPlayerName(src) or ('Character %d'):format(senderCharId)

        if isOnline then
            if not addMoney(targetSrc, 'bank', received, 'bank_transfer_in:' .. txId) then
                local refunded = addMoney(src, 'bank', amount, 'bank_transfer_refund:' .. txId)
                finishOperation(txId, refunded and 'rolled_back' or 'recovery_required', {
                    reason = 'recipient_credit_failed', refundSucceeded = refunded == true,
                })
                if not refunded then
                    adminLog(src, 'bank_recovery_required', {
                        category = 'players', transactionId = txId, operation = 'character_transfer',
                        amount = amount, targetCharacterId = targetCharId,
                    }, 'character:' .. tostring(targetCharId), recipientKnownName)
                end
                return false, refunded
                    and 'The transfer could not be completed and was refunded.'
                    or recoveryRequiredMessage(txId)
            end

            local targetName = getCharName(targetSrc) or GetPlayerName(targetSrc) or ('Character %d'):format(targetCharId)
            local _, senderBank = getBalances(src)
            local targetCash, targetBank = getBalances(targetSrc)

            recordTransaction(senderCharId, 'transfer_out', amount, senderBank, targetCharId, targetName, txId, transferFee, 'completed', note)
            recordTransaction(targetCharId, 'transfer_in', received, targetBank, senderCharId, senderName, txId, 0, 'completed', note)
            finishOperation(txId, 'committed', {
                senderBalanceAfter = senderBank, recipientBalanceAfter = targetBank, received = received,
            })

            adminLog(src, 'bank_transfer', {
                category = 'players', transactionId = txId, amount = amount,
                transferFee = transferFee, received = received, targetCharacterId = targetCharId,
            }, 'character:' .. tostring(targetCharId), targetName)

            TriggerClientEvent('cm-bank:client:actionResult', targetSrc, 'transferReceived', {
                ok = true,
                message = ('You received $%d from %s.'):format(received, senderName),
                amount = received,
                senderName = senderName,
                transactionId = txId,
                cash = targetCash,
                bank = targetBank,
            })

            transferRateHistory[src] = transferRateHistory[src] or {}
            table.insert(transferRateHistory[src], now)

            return true, ('Sent $%d to %s (Character #%d).'):format(received, targetName, targetCharId), {
                amount = amount, received = received, targetName = targetName,
                targetCharacterId = targetCharId, transferFee = transferFee, transactionId = txId,
            }
        end

        -- Recipient is offline. cm-playerdata's exported money functions all
        -- require an online src, so there is no supported way to credit them
        -- directly right now. Queue delivery instead of bypassing
        -- cm-playerdata by writing into its tables; the pending row is
        -- delivered idempotently the moment that character next loads (see
        -- the cm-playerdata:server:characterLoaded handler below).
        local pendingOk = pcall(function()
            MySQL.insert.await(
                'INSERT INTO bank_pending_transfers (transaction_id, sender_character_id, sender_name, recipient_character_id, amount, note, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
                { txId, senderCharId, senderName, targetCharId, received, note, 'pending' }
            )
        end)
        if not pendingOk then
            local refunded = addMoney(src, 'bank', amount, 'bank_transfer_refund:' .. txId)
            finishOperation(txId, refunded and 'rolled_back' or 'recovery_required', {
                reason = 'pending_insert_failed', refundSucceeded = refunded == true,
            })
            if not refunded then
                adminLog(src, 'bank_recovery_required', {
                    category = 'players', transactionId = txId, operation = 'character_transfer_offline',
                    amount = amount, targetCharacterId = targetCharId,
                }, 'character:' .. tostring(targetCharId), recipientKnownName)
            end
            return false, refunded
                and 'The transfer could not be completed and was refunded.'
                or ('Transfer could not be completed with reference %s.'):format(txId)
        end

        local _, senderBank = getBalances(src)
        recordTransaction(senderCharId, 'transfer_out', amount, senderBank, targetCharId, recipientKnownName, txId, transferFee, 'pending', note)
        finishOperation(txId, 'committed', { senderBalanceAfter = senderBank, offlineDelivery = true })
        adminLog(src, 'bank_transfer_offline_pending', {
            category = 'players', transactionId = txId, amount = amount, targetCharacterId = targetCharId,
        }, 'character:' .. tostring(targetCharId), recipientKnownName)

        transferRateHistory[src] = transferRateHistory[src] or {}
        table.insert(transferRateHistory[src], now)

        return true, ('Sent $%d to %s (Character #%d). They will receive it the next time they log in.'):format(received, recipientKnownName, targetCharId), {
            amount = amount, received = received, targetName = recipientKnownName,
            targetCharacterId = targetCharId, transferFee = transferFee, transactionId = txId,
            offlineDelivery = true,
        }
    end)

    if not ran then
        return sendResult(src, 'transfer', false, opOk == 'busy' and 'One of these accounts is already processing another money operation.' or 'The transfer could not be completed.')
    end
    sendResult(src, 'transfer', opOk, message, extra)
end)

-- Idempotent delivery for one queued offline transfer. The status column is
-- the only source of truth: `pending -> delivering` is a compare-and-set
-- claim, so two concurrent delivery attempts (e.g. a duplicate event fire)
-- can never both succeed. Money is only ever credited once a claim is won,
-- and a claim that can't be finalized is reverted to `pending` for retry
-- rather than left in a state that could be re-credited.
local function deliverPendingTransfer(targetSrc, charId, row)
    runLocked({ 'money:' .. tostring(charId), 'pending-xfr:' .. tostring(row.id) }, function()
        local claimOk, claimed = pcall(function()
            return MySQL.update.await(
                "UPDATE bank_pending_transfers SET status = 'delivering' WHERE id = ? AND status = 'pending'",
                { row.id }
            )
        end)
        if not claimOk or tonumber(claimed) ~= 1 then return false end

        if not isLoaded(targetSrc) or getCharId(targetSrc) ~= charId then
            pcall(function() MySQL.update.await("UPDATE bank_pending_transfers SET status = 'pending' WHERE id = ?", { row.id }) end)
            return false
        end

        local amount = math.max(0, math.floor(tonumber(row.amount) or 0))
        if amount <= 0 then
            pcall(function() MySQL.update.await("UPDATE bank_pending_transfers SET status = 'delivered', delivered_at = CURRENT_TIMESTAMP WHERE id = ?", { row.id }) end)
            return true
        end

        if not addMoney(targetSrc, 'bank', amount, 'bank_transfer_in_pending:' .. row.transaction_id) then
            -- Never mark delivered without a successful credit. Release the
            -- claim so the next character load retries delivery.
            pcall(function() MySQL.update.await("UPDATE bank_pending_transfers SET status = 'pending' WHERE id = ?", { row.id }) end)
            dbg('Pending transfer credit failed, will retry on next load:', row.transaction_id)
            return false
        end

        local finalizeOk, finalized = pcall(function()
            return MySQL.update.await(
                "UPDATE bank_pending_transfers SET status = 'delivered', delivered_at = CURRENT_TIMESTAMP WHERE id = ? AND status = 'delivering'",
                { row.id }
            )
        end)
        if not finalizeOk or tonumber(finalized) ~= 1 then
            -- Credit already happened; do NOT retry it (would double-pay).
            -- Flag for admin follow-up instead of silently leaving it unclear.
            pcall(function() MySQL.update.await("UPDATE bank_pending_transfers SET status = 'recovery_required' WHERE id = ?", { row.id }) end)
            adminLog(targetSrc, 'bank_recovery_required', {
                category = 'players', transactionId = row.transaction_id, operation = 'pending_transfer_delivery_status', amount = amount,
            }, 'character:' .. tostring(charId), getCharName(targetSrc))
        end

        local _, newBank = getBalances(targetSrc)
        recordTransaction(charId, 'transfer_in', amount, newBank, tonumber(row.sender_character_id), row.sender_name, row.transaction_id, 0, 'completed', row.note)
        pcall(function()
            MySQL.update.await(
                "UPDATE bank_transactions SET status = 'completed' WHERE transaction_id = ? AND kind = 'transfer_out'",
                { row.transaction_id }
            )
        end)

        adminLog(targetSrc, 'bank_pending_transfer_delivered', {
            category = 'players', transactionId = row.transaction_id, amount = amount, senderCharacterId = row.sender_character_id,
        }, 'character:' .. tostring(row.sender_character_id), row.sender_name)

        local targetCash = getBalances(targetSrc)
        TriggerClientEvent('cm-bank:client:actionResult', targetSrc, 'transferReceived', {
            ok = true,
            message = ('You received $%d from %s.'):format(amount, row.sender_name or ('Character %d'):format(tonumber(row.sender_character_id) or 0)),
            amount = amount,
            senderName = row.sender_name,
            transactionId = row.transaction_id,
            cash = targetCash,
            bank = newBank,
        })
        return true
    end)
end

-- Read-only subscription to cm-playerdata's real character-load event (never
-- modifies cm-playerdata). Fires once per character load; delivers any
-- pending transfers waiting for that Character ID.
AddEventHandler('cm-playerdata:server:characterLoaded', function(loadedSrc, safeData)
    if not bankReady then return end
    local charId = tonumber(safeData and safeData.charId)
    if not charId then return end

    local ok, rows = pcall(function()
        return MySQL.query.await(
            "SELECT id, transaction_id, sender_character_id, sender_name, amount, note FROM bank_pending_transfers WHERE recipient_character_id = ? AND status = 'pending'",
            { charId }
        )
    end)
    if not ok or type(rows) ~= 'table' then return end
    for i = 1, #rows do
        deliverPendingTransfer(loadedSrc, charId, rows[i])
    end
end)

RegisterNetEvent('cm-bank:server:lookupRecipient', function(targetCharId)
    local src = source
    targetCharId = sanitizeAmount(targetCharId)
    if not bankReady or not isLoaded(src) then return end
    if underCooldown(lookupCooldowns, src, 500) then return end

    local senderCharId = getCharId(src)
    if not senderCharId or targetCharId <= 0 then
        TriggerClientEvent('cm-bank:client:recipientLookupResult', src, { ok = false, targetCharacterId = targetCharId, message = 'Character ID not found.' })
        return
    end
    if targetCharId == senderCharId then
        TriggerClientEvent('cm-bank:client:recipientLookupResult', src, { ok = false, targetCharacterId = targetCharId, message = 'You cannot transfer to yourself.' })
        return
    end

    local exists, name = resolveCharacterIdentity(targetCharId)
    if not exists then
        TriggerClientEvent('cm-bank:client:recipientLookupResult', src, { ok = false, targetCharacterId = targetCharId, message = 'Character ID not found.' })
        return
    end
    TriggerClientEvent('cm-bank:client:recipientLookupResult', src, { ok = true, targetCharacterId = targetCharId, name = name })
end)

-- v1.7.0: saved Character ID payees. All four mutations respond with the
-- owner's refreshed full payee list so the NUI never has to guess local
-- state — it just re-renders from what the server actually persisted.
local function sendPayeesResult(src, ok, message, charId)
    TriggerClientEvent('cm-bank:client:payeesResult', src, {
        ok = ok, message = message or '', payees = charId and fetchSavedPayees(charId) or nil,
    })
end

RegisterNetEvent('cm-bank:server:fetchPayees', function()
    local src = source
    if not bankReady or not isLoaded(src) then return end
    local charId = getCharId(src)
    if not charId then return end
    sendPayeesResult(src, true, nil, charId)
end)

RegisterNetEvent('cm-bank:server:addPayee', function(recipientCharId, nickname)
    local src = source
    recipientCharId = sanitizeAmount(recipientCharId)
    nickname = sanitizeNickname(nickname)

    if not bankReady then return sendPayeesResult(src, false, 'Banking is still starting.') end
    if not isLoaded(src) then return sendPayeesResult(src, false, 'You are not fully logged in.') end
    if underCooldown(lookupCooldowns, src, 400) then return end

    local charId = getCharId(src)
    if not charId then return sendPayeesResult(src, false, 'Your character could not be identified.') end
    if recipientCharId <= 0 then return sendPayeesResult(src, false, 'Character ID not found.', charId) end
    if recipientCharId == charId then return sendPayeesResult(src, false, 'You cannot save your own Character ID.', charId) end
    if not nickname then return sendPayeesResult(src, false, 'Enter a nickname for this payee.', charId) end

    local exists = resolveCharacterIdentity(recipientCharId)
    if not exists then return sendPayeesResult(src, false, 'Character ID not found.', charId) end

    local maxPayees = math.max(1, tonumber(Config.Payees and Config.Payees.maxPayees) or 30)
    local countRow = MySQL.single.await('SELECT COUNT(*) AS total FROM bank_saved_payees WHERE owner_character_id = ?', { charId })
    if countRow and (tonumber(countRow.total) or 0) >= maxPayees then
        return sendPayeesResult(src, false, ('You can save at most %d payees.'):format(maxPayees), charId)
    end

    local ok, insertId = pcall(function()
        return MySQL.insert.await(
            'INSERT INTO bank_saved_payees (owner_character_id, recipient_character_id, nickname, is_favourite) VALUES (?, ?, ?, 0)',
            { charId, recipientCharId, nickname }
        )
    end)
    if not ok or not insertId then
        -- The UNIQUE(owner, recipient) constraint is what actually stops a
        -- duplicate save; a failed insert here is almost always that.
        return sendPayeesResult(src, false, 'You already have a saved payee for that Character ID.', charId)
    end

    adminLog(src, 'bank_payee_add', { category = 'players', recipientCharacterId = recipientCharId }, 'character:' .. tostring(recipientCharId), nickname)
    sendPayeesResult(src, true, 'Payee saved.', charId)
end)

RegisterNetEvent('cm-bank:server:renamePayee', function(payeeId, nickname)
    local src = source
    payeeId = sanitizeAmount(payeeId)
    nickname = sanitizeNickname(nickname)

    if not bankReady or not isLoaded(src) then return sendPayeesResult(src, false, 'Banking is still starting.') end
    local charId = getCharId(src)
    if not charId or payeeId <= 0 then return sendPayeesResult(src, false, 'Your character could not be identified.', charId) end
    if not nickname then return sendPayeesResult(src, false, 'Enter a nickname for this payee.', charId) end

    local ok, affected = pcall(function()
        return MySQL.update.await(
            'UPDATE bank_saved_payees SET nickname = ? WHERE id = ? AND owner_character_id = ?',
            { nickname, payeeId, charId }
        )
    end)
    if not ok or tonumber(affected) ~= 1 then return sendPayeesResult(src, false, 'That payee could not be found.', charId) end
    sendPayeesResult(src, true, 'Payee renamed.', charId)
end)

RegisterNetEvent('cm-bank:server:setPayeeFavourite', function(payeeId, favourite)
    local src = source
    payeeId = sanitizeAmount(payeeId)
    favourite = favourite == true

    if not bankReady or not isLoaded(src) then return sendPayeesResult(src, false, 'Banking is still starting.') end
    local charId = getCharId(src)
    if not charId or payeeId <= 0 then return sendPayeesResult(src, false, 'Your character could not be identified.', charId) end

    if favourite then
        local maxFavourites = math.max(1, tonumber(Config.Payees and Config.Payees.maxFavourites) or 6)
        local countRow = MySQL.single.await(
            'SELECT COUNT(*) AS total FROM bank_saved_payees WHERE owner_character_id = ? AND is_favourite = 1',
            { charId }
        )
        if countRow and (tonumber(countRow.total) or 0) >= maxFavourites then
            return sendPayeesResult(src, false, ('You can have at most %d favourite payees.'):format(maxFavourites), charId)
        end
    end

    local ok, affected = pcall(function()
        return MySQL.update.await(
            'UPDATE bank_saved_payees SET is_favourite = ? WHERE id = ? AND owner_character_id = ?',
            { favourite and 1 or 0, payeeId, charId }
        )
    end)
    if not ok or tonumber(affected) ~= 1 then return sendPayeesResult(src, false, 'That payee could not be found.', charId) end
    sendPayeesResult(src, true, favourite and 'Added to favourites.' or 'Removed from favourites.', charId)
end)

RegisterNetEvent('cm-bank:server:deletePayee', function(payeeId)
    local src = source
    payeeId = sanitizeAmount(payeeId)

    if not bankReady or not isLoaded(src) then return sendPayeesResult(src, false, 'Banking is still starting.') end
    local charId = getCharId(src)
    if not charId or payeeId <= 0 then return sendPayeesResult(src, false, 'Your character could not be identified.', charId) end

    local ok, affected = pcall(function()
        return MySQL.update.await('DELETE FROM bank_saved_payees WHERE id = ? AND owner_character_id = ?', { payeeId, charId })
    end)
    if not ok or tonumber(affected) ~= 1 then return sendPayeesResult(src, false, 'That payee could not be found.', charId) end
    sendPayeesResult(src, true, 'Payee deleted.', charId)
end)

local STATEMENT_FILTER_KIND = {
    deposit = 'deposit', withdraw = 'withdraw', withdrawal = 'withdraw',
    transfer_sent = 'transfer_out', transfer_out = 'transfer_out',
    transfer_received = 'transfer_in', transfer_in = 'transfer_in',
    atm_earnings = 'atm_earnings', atm_purchase = 'atm_purchase', atm_sale = 'atm_sale',
}

-- v1.7.0: statement date filter. Values are fixed literal SQL fragments
-- selected only from this map (never interpolated from user input directly),
-- so this stays just as parameterized-safe as the rest of the query.
local STATEMENT_DATE_RANGE_SQL = {
    today = 'created_at >= CURDATE()',
    week = 'created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)',
    month30 = 'created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)',
    this_month = "created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')",
}

RegisterNetEvent('cm-bank:server:fetchStatements', function(opts)
    local src = source
    opts = type(opts) == 'table' and opts or {}
    if not bankReady or not isLoaded(src) then
        TriggerClientEvent('cm-bank:client:statementsResult', src, { ok = false, message = 'Banking is still starting.' })
        return
    end
    if underCooldown(lookupCooldowns, src, 250) then return end

    local charId = getCharId(src)
    if not charId then return end

    local page = math.max(1, math.floor(tonumber(opts.page) or 1))
    local filterKind = STATEMENT_FILTER_KIND[tostring(opts.filter or 'all')]
    local dateRangeSql = STATEMENT_DATE_RANGE_SQL[tostring(opts.dateRange or 'all')]
    local search = tostring(opts.search or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #search > 64 then search = search:sub(1, 64) end

    local where = { 'character_id = ?' }
    local params = { charId }
    if filterKind then
        where[#where + 1] = 'kind = ?'
        params[#params + 1] = filterKind
    end
    if dateRangeSql then
        where[#where + 1] = dateRangeSql
    end
    if search ~= '' then
        local like = '%' .. search .. '%'
        local searchCharId = tonumber(search)
        if searchCharId then
            where[#where + 1] = '(transaction_id LIKE ? OR counterparty_character_id = ? OR description LIKE ?)'
            params[#params + 1] = like
            params[#params + 1] = math.floor(searchCharId)
            params[#params + 1] = like
        else
            where[#where + 1] = '(transaction_id LIKE ? OR description LIKE ?)'
            params[#params + 1] = like
            params[#params + 1] = like
        end
    end
    local whereSql = table.concat(where, ' AND ')

    local countOk, countRow = pcall(function()
        return MySQL.single.await('SELECT COUNT(*) AS total FROM bank_transactions WHERE ' .. whereSql, params)
    end)
    local totalCount = (countOk and countRow and tonumber(countRow.total)) or 0
    local totalPages = math.max(1, math.ceil(totalCount / STATEMENT_PAGE_SIZE))
    if page > totalPages then page = totalPages end
    local offset = (page - 1) * STATEMENT_PAGE_SIZE

    local rowParams = {}
    for _, p in ipairs(params) do rowParams[#rowParams + 1] = p end
    rowParams[#rowParams + 1] = STATEMENT_PAGE_SIZE
    rowParams[#rowParams + 1] = offset

    local rowsOk, rows = pcall(function()
        return MySQL.query.await(
            'SELECT transaction_id, kind, amount, fee_amount, balance_after, counterparty_character_id, counterparty_name, description, status, created_at ' ..
            'FROM bank_transactions WHERE ' .. whereSql .. ' ORDER BY created_at DESC LIMIT ? OFFSET ?',
            rowParams
        )
    end)
    if not rowsOk or type(rows) ~= 'table' then rows = {} end

    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        out[#out + 1] = {
            transactionId = row.transaction_id,
            kind = row.kind,
            amount = tonumber(row.amount) or 0,
            feeAmount = tonumber(row.fee_amount) or 0,
            balanceAfter = tonumber(row.balance_after) or 0,
            counterpartyCharacterId = tonumber(row.counterparty_character_id),
            counterpartyName = row.counterparty_name,
            description = row.description,
            status = row.status or 'completed',
            time = row.created_at and tostring(row.created_at) or nil,
        }
    end

    TriggerClientEvent('cm-bank:client:statementsResult', src, {
        ok = true, page = page, totalPages = totalPages, totalCount = totalCount, rows = out,
    })
end)

RegisterNetEvent('cm-bank:server:buyAtm', function()
    local src = source
    if not bankReady then return sendResult(src, 'buyAtm', false, 'Banking is not ready yet.') end
    if not isLoaded(src) then return sendResult(src, 'buyAtm', false, 'You are not fully logged in.') end
    if not ownershipEnabled then return sendResult(src, 'buyAtm', false, 'ATM ownership is currently disabled.') end

    local charId = getCharId(src)
    local preKey, preAtm = currentAtmForPlayer(src)
    if not charId then return sendResult(src, 'buyAtm', false, 'Your character could not be identified.') end
    if not preAtm or preAtm.verified ~= true then return sendResult(src, 'buyAtm', false, 'You need to be at a verified ATM to buy it.') end

    local ran, opOk, message, extra = runLocked({
        'money:' .. tostring(charId),
        'atm-owner:' .. tostring(charId),
        'atm:' .. tostring(preAtm.id or preKey),
    }, function()
        local atmKey, atm = currentAtmForPlayer(src)
        if not atm or atmKey ~= preKey then return false, 'You need to remain at the ATM while buying it.' end
        if atm.verified ~= true then return false, 'This ATM is not verified.' end
        if atm.adminDisabled then return false, 'This ATM is out of service.' end
        if atm.ownerCharacterId then return false, 'This ATM is already owned.' end
        if atm.forSale == false then return false, 'This ATM is not for sale.' end
        if not ownershipEnabled then return false, 'ATM ownership is currently disabled.' end

        local maxOwned = math.max(1, math.floor(tonumber(Config.Ownership and Config.Ownership.maxOwnedPerCharacter) or 1))
        if countOwnedAtmsByChar(charId) >= maxOwned then
            local _, existing = findOwnedAtmByChar(charId)
            return false, existing
                and ('You already own ATM No. %d. Sell it before buying another.'):format(existing.id or 0)
                or ('You already own the maximum of %d ATM(s).'):format(maxOwned)
        end

        local price = math.max(0, math.floor(tonumber(Config.Ownership and Config.Ownership.purchasePrice) or 0))
        if not canAfford(src, 'bank', price) then return false, 'You do not have enough in your bank account.' end

        local name = getCharName(src) or GetPlayerName(src) or ('Character %d'):format(charId)
        local startingFee = defaultFeePercent()
        local txId = newTransactionId('BUYATM', src)
        if not beginOperation(txId, 'atm_purchase', charId, nil, price, { atmId = atm.id, atmKey = atmKey }) then
            return false, 'The bank audit service is unavailable. Try again.'
        end

        -- v1.6.0: a purchased ATM resets to a fixed, government-provided
        -- starting reserve rather than inheriting whatever cash a public
        -- machine happened to be holding — otherwise a player could stuff a
        -- public ATM with deposits and immediately buy it to convert that
        -- public liquidity into a private, owner-recoverable asset. The
        -- previous reserve is remembered only to restore it if the purchase
        -- itself has to roll back below.
        local previousReserve = math.max(0, tonumber(atm.cashReserve) or 0)
        local capacityForAtm = math.max(1, tonumber(atm.cashCapacity) or defaultCapacityForAtm(atm))
        local startingReserve = math.min(capacityForAtm, math.max(0, tonumber(Config.ATMBusiness and Config.ATMBusiness.purchaseStartingReserve) or 25000))

        -- Claim the machine in SQL before taking money. The conditional update
        -- means a simultaneous buyer cannot claim the same ATM.
        local claimOk, affected = pcall(function()
            return MySQL.update.await([[
                UPDATE bank_atm_locations
                SET owner_character_id = ?, owner_name = ?, fee_percent = ?, cash_reserve = ?, owner_reserve_contribution = 0
                WHERE coord_key = ? AND verified = 1 AND owner_character_id IS NULL
                  AND for_sale = 1 AND admin_disabled = 0
            ]], { charId, name, startingFee, startingReserve, atmKey })
        end)
        if not claimOk or tonumber(affected) ~= 1 then
            finishOperation(txId, 'rolled_back', { reason = 'atm_claim_failed' })
            return false, 'This ATM could not be claimed. It may have just been bought by someone else.'
        end
        atm.cashReserve = startingReserve
        atm.ownerReserveContribution = 0

        if price > 0 and not removeMoney(src, 'bank', price, 'atm_purchase:' .. txId) then
            local rollbackOk, rolledBack = pcall(function()
                return MySQL.update.await([[
                    UPDATE bank_atm_locations
                    SET owner_character_id = NULL, owner_name = NULL, fee_percent = 0, cash_reserve = ?, owner_reserve_contribution = 0
                    WHERE coord_key = ? AND owner_character_id = ?
                ]], { previousReserve, atmKey, charId })
            end)
            local restored = rollbackOk and tonumber(rolledBack) == 1
            finishOperation(txId, restored and 'rolled_back' or 'recovery_required', {
                reason = 'purchase_debit_failed', ownershipRollback = restored,
            })
            if not restored then
                atm.ownerCharacterId, atm.ownerName, atm.feePercent = charId, name, startingFee
                adminLog(src, 'bank_recovery_required', {
                    category = 'players', transactionId = txId, operation = 'atm_purchase', atmId = atm.id,
                }, 'character:' .. tostring(charId), name)
                return false, ('Purchase recovery required. Reference %s.'):format(txId)
            end
            atm.cashReserve = previousReserve
            atm.ownerReserveContribution = 0
            return false, 'The purchase could not be completed.'
        end

        atm.ownerCharacterId = charId
        atm.ownerName = name
        atm.feePercent = startingFee

        local _, newBank = getBalances(src)
        recordTransaction(charId, 'atm_purchase', price, newBank, nil, nil, txId, 0)
        finishOperation(txId, 'committed', { atmId = atm.id, balanceAfter = newBank })
        recordAtmActivity(atm, 'purchase', charId, price, 0, txId)
        adminLog(src, 'bank_atm_purchase', {
            category = 'players', transactionId = txId, atmKey = atmKey, atmId = atm.id, price = price,
        }, 'character:' .. tostring(charId), name)

        return true, ('You now own ATM No. %d.'):format(atm.id or 0), {
            transactionId = txId, atm = buildAtmView(atmKey, atm, charId),
        }
    end)

    if not ran then
        return sendResult(src, 'buyAtm', false, opOk == 'busy' and 'This ATM or account is already processing another operation.' or 'The purchase could not be completed.')
    end
    sendResult(src, 'buyAtm', opOk, message, extra)
end)

RegisterNetEvent('cm-bank:server:setAtmFee', function(feePercent)
    local src = source
    feePercent = math.floor(tonumber(feePercent) or -1)

    if not bankReady then return sendResult(src, 'setAtmFee', false, 'Banking is not ready yet.') end
    if not isLoaded(src) then return sendResult(src, 'setAtmFee', false, 'You are not fully logged in.') end
    if not isValidFeeChoice(feePercent) then
        return sendResult(src, 'setAtmFee', false, 'Withdrawal fee must be 1%, 2%, 3%, or 4%.')
    end

    local charId = getCharId(src)
    local preKey, preAtm = currentAtmForPlayer(src)
    if not charId or not preAtm then return sendResult(src, 'setAtmFee', false, 'You need to be at the ATM to manage it.') end

    local ran, opOk, message, extra = runLocked({ 'atm:' .. tostring(preAtm.id or preKey) }, function()
        local atmKey, atm = currentAtmForPlayer(src)
        if not atm or atmKey ~= preKey then return false, 'You need to remain at the ATM to manage it.' end
        if atm.ownerCharacterId ~= charId then return false, 'You do not own this ATM.' end

        local ok, affected = pcall(function()
            return MySQL.update.await(
                'UPDATE bank_atm_locations SET fee_percent = ? WHERE coord_key = ? AND owner_character_id = ? AND verified = 1',
                { feePercent, atmKey, charId }
            )
        end)
        if not ok or tonumber(affected) ~= 1 then return false, 'The withdrawal fee could not be updated.' end

        atm.feePercent = feePercent
        return true, ('Withdrawal fee set to %d%%.'):format(feePercent), { atm = buildAtmView(atmKey, atm, charId) }
    end)

    if not ran then return sendResult(src, 'setAtmFee', false, opOk == 'busy' and 'This ATM is busy. Try again.' or 'The fee could not be updated.') end
    sendResult(src, 'setAtmFee', opOk, message, extra)
end)

-- v1.6.0: owner-funded restock. Uses the owner's actual CASH (never bank
-- money), mirrors the setAtmFee/withdrawAtmEarnings proximity+ownership+lock
-- pattern exactly, and tracks the contributed amount separately in
-- owner_reserve_contribution so it can be recovered (but never inflated by
-- player deposits or public liquidity) on a later sale.
RegisterNetEvent('cm-bank:server:restockAtm', function(amount)
    local src = source
    amount = sanitizeAmount(amount)

    if not bankReady then return sendResult(src, 'restockAtm', false, 'Banking is not ready yet.') end
    if not isLoaded(src) then return sendResult(src, 'restockAtm', false, 'You are not fully logged in.') end
    if amount <= 0 then return sendResult(src, 'restockAtm', false, 'Enter a valid amount.') end

    local charId = getCharId(src)
    local preKey, preAtm = currentAtmForPlayer(src)
    if not charId or not preAtm then return sendResult(src, 'restockAtm', false, 'You need to be at the ATM to restock it.') end
    if preAtm.ownerCharacterId ~= charId then return sendResult(src, 'restockAtm', false, 'You do not own this ATM.') end
    if preAtm.adminDisabled then return sendResult(src, 'restockAtm', false, 'This ATM is out of service.') end

    local ran, opOk, message, extra = runLocked({ 'money:' .. tostring(charId), 'atm:' .. tostring(preAtm.id or preKey) }, function()
        local atmKey, atm = currentAtmForPlayer(src)
        if not atm or atmKey ~= preKey then return false, 'You need to remain at the ATM to restock it.' end
        if atm.ownerCharacterId ~= charId then return false, 'You do not own this ATM.' end
        if atm.adminDisabled then return false, 'This ATM is out of service.' end
        if not isLoaded(src) then return false, 'You are not fully logged in.' end
        if not canAfford(src, 'cash', amount) then return false, 'You do not have that much cash.' end

        local capacity = math.max(1, tonumber(atm.cashCapacity) or defaultCapacityForAtm(atm))
        local remaining = math.max(0, capacity - (tonumber(atm.cashReserve) or 0))
        if amount > remaining then
            return false, ('ATM only has space for $%d more.'):format(remaining)
        end

        local statusBeforeRestock = atmReserveStatus(atm)

        local txId = newTransactionId('ATMRESTOCK', src)
        if not beginOperation(txId, 'atm_restock', charId, nil, amount, { atmId = atm.id }) then
            return false, 'The bank audit service is unavailable. Try again.'
        end

        if not removeMoney(src, 'cash', amount, 'atm_restock:' .. txId) then
            finishOperation(txId, 'rolled_back', { reason = 'owner_cash_debit_failed' })
            return false, 'The restock could not be completed.'
        end

        local contributed = contributeAtmReserve(atmKey, atm, amount)
        if contributed < amount then
            -- Reserve write failed or capacity shrank concurrently. Refund
            -- whatever wasn't actually absorbed rather than losing it.
            local shortfall = amount - contributed
            local refunded = addMoney(src, 'cash', shortfall, 'atm_restock_refund:' .. txId)
            if not refunded then
                finishOperation(txId, 'recovery_required', { reason = 'restock_shortfall_refund_failed', contributed = contributed })
                adminLog(src, 'bank_recovery_required', {
                    category = 'players', transactionId = txId, operation = 'atm_restock', amount = shortfall, atmId = atm.id,
                }, 'character:' .. tostring(charId), getCharName(src))
                return false, recoveryRequiredMessage(txId)
            end
        end
        if contributed <= 0 then
            finishOperation(txId, 'rolled_back', { reason = 'no_capacity' })
            return false, 'This ATM has no space for a restock right now.'
        end

        local ok, affected = pcall(function()
            return MySQL.update.await(
                'UPDATE bank_atm_locations SET owner_reserve_contribution = owner_reserve_contribution + ? WHERE coord_key = ? AND owner_character_id = ?',
                { contributed, atmKey, charId }
            )
        end)
        if ok and tonumber(affected) == 1 then
            atm.ownerReserveContribution = (atm.ownerReserveContribution or 0) + contributed
        else
            dbg('Failed to persist owner_reserve_contribution:', atmKey, affected)
        end

        local _, newBank = getBalances(src)
        recordTransaction(charId, 'atm_restock', contributed, newBank, nil, nil, txId, 0)
        finishOperation(txId, 'committed', { atmId = atm.id, contributed = contributed })
        recordAtmActivity(atm, 'restock', charId, contributed, 0, txId)
        notifyOwnerIfReserveRecovered(atm, statusBeforeRestock)
        adminLog(src, 'bank_atm_restock', {
            category = 'players', transactionId = txId, atmId = atm.id, amount = contributed,
        }, 'character:' .. tostring(charId), getCharName(src))

        return true, ('Restocked ATM No. %d with $%d.'):format(atm.id or 0, contributed), {
            amount = contributed, transactionId = txId, atm = buildAtmView(atmKey, atm, charId),
        }
    end)

    if not ran then return sendResult(src, 'restockAtm', false, opOk == 'busy' and 'This ATM is busy. Try again.' or 'The restock could not be completed.') end
    sendResult(src, 'restockAtm', opOk, message, extra)
end)

-- v1.6.0: owner analytics + business history. Read-only, but still gated on
-- proximity + ownership (resolved fresh via currentAtmForPlayer, matching
-- every other owner-only ATM action) so a remote player cannot scrape
-- another owner's business figures. Queried on demand when the owner opens
-- the dashboard/history view, never on a timer and never for every visitor.
local ATM_ANALYTICS_RANGE_SQL = {
    today = 'created_at >= CURDATE()',
    week = 'created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)',
    all = '1 = 1',
}

RegisterNetEvent('cm-bank:server:fetchAtmAnalytics', function(range)
    local src = source
    range = ATM_ANALYTICS_RANGE_SQL[tostring(range or 'today')] and tostring(range) or 'today'
    if not bankReady or not isLoaded(src) then return end
    if underCooldown(lookupCooldowns, src, 250) then return end

    local charId = getCharId(src)
    local _, atm = currentAtmForPlayer(src)
    if not charId or not atm or atm.ownerCharacterId ~= charId then
        TriggerClientEvent('cm-bank:client:atmAnalyticsResult', src, { ok = false, message = 'You need to be at your ATM to view its analytics.' })
        return
    end

    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT
                COUNT(*) AS transactions,
                SUM(CASE WHEN kind = 'withdrawal' THEN 1 ELSE 0 END) AS withdrawal_count,
                SUM(CASE WHEN kind = 'deposit' THEN 1 ELSE 0 END) AS deposit_count,
                SUM(CASE WHEN kind = 'withdrawal' THEN amount ELSE 0 END) AS cash_withdrawn,
                SUM(CASE WHEN kind = 'deposit' THEN amount ELSE 0 END) AS cash_deposited,
                SUM(CASE WHEN kind = 'withdrawal' THEN fee_amount ELSE 0 END) AS fee_revenue
            FROM bank_atm_activity
            WHERE atm_id = ? AND ]] .. ATM_ANALYTICS_RANGE_SQL[range], { atm.id })
    end)
    if not ok or not row then
        TriggerClientEvent('cm-bank:client:atmAnalyticsResult', src, { ok = false, message = 'Analytics are unavailable right now.' })
        return
    end

    local withdrawalCount = tonumber(row.withdrawal_count) or 0
    local cashWithdrawn = tonumber(row.cash_withdrawn) or 0
    local capacity = math.max(1, tonumber(atm.cashCapacity) or defaultCapacityForAtm(atm))
    local reserve = math.max(0, tonumber(atm.cashReserve) or 0)
    TriggerClientEvent('cm-bank:client:atmAnalyticsResult', src, {
        ok = true,
        range = range,
        transactions = tonumber(row.transactions) or 0,
        withdrawalCount = withdrawalCount,
        depositCount = tonumber(row.deposit_count) or 0,
        cashWithdrawn = cashWithdrawn,
        cashDeposited = tonumber(row.cash_deposited) or 0,
        feeRevenue = tonumber(row.fee_revenue) or 0,
        averageWithdrawal = withdrawalCount > 0 and math.floor(cashWithdrawn / withdrawalCount) or 0,
        currentReserve = reserve,
        cashCapacity = capacity,
        reserveUtilisationPercent = math.floor(reserve / capacity * 100),
    })
end)

local ATM_HISTORY_PAGE_SIZE = 20

RegisterNetEvent('cm-bank:server:fetchAtmHistory', function(opts)
    local src = source
    opts = type(opts) == 'table' and opts or {}
    if not bankReady or not isLoaded(src) then return end
    if underCooldown(lookupCooldowns, src, 250) then return end

    local charId = getCharId(src)
    local _, atm = currentAtmForPlayer(src)
    if not charId or not atm or atm.ownerCharacterId ~= charId then
        TriggerClientEvent('cm-bank:client:atmHistoryResult', src, { ok = false, message = 'You need to be at your ATM to view its history.' })
        return
    end

    local page = math.max(1, math.floor(tonumber(opts.page) or 1))

    local countOk, countRow = pcall(function()
        return MySQL.single.await('SELECT COUNT(*) AS total FROM bank_atm_activity WHERE atm_id = ?', { atm.id })
    end)
    local totalCount = (countOk and countRow and tonumber(countRow.total)) or 0
    local totalPages = math.max(1, math.ceil(totalCount / ATM_HISTORY_PAGE_SIZE))
    if page > totalPages then page = totalPages end
    local offset = (page - 1) * ATM_HISTORY_PAGE_SIZE

    local rowsOk, rows = pcall(function()
        return MySQL.query.await(
            'SELECT transaction_id, kind, actor_character_id, amount, fee_amount, reserve_after, created_at ' ..
            'FROM bank_atm_activity WHERE atm_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?',
            { atm.id, ATM_HISTORY_PAGE_SIZE, offset }
        )
    end)
    if not rowsOk or type(rows) ~= 'table' then rows = {} end

    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        -- Character ID only, deliberately never a name here — this history
        -- can include players other than the owner, and Character ID is
        -- sufficient per the business-history identity rule.
        out[#out + 1] = {
            transactionId = row.transaction_id,
            kind = row.kind,
            actorCharacterId = tonumber(row.actor_character_id),
            amount = tonumber(row.amount) or 0,
            feeAmount = tonumber(row.fee_amount) or 0,
            reserveAfter = tonumber(row.reserve_after),
            time = row.created_at and tostring(row.created_at) or nil,
        }
    end

    TriggerClientEvent('cm-bank:client:atmHistoryResult', src, {
        ok = true, page = page, totalPages = totalPages, totalCount = totalCount, rows = out,
    })
end)

RegisterNetEvent('cm-bank:server:withdrawAtmEarnings', function()
    local src = source
    if not bankReady then return sendResult(src, 'withdrawAtmEarnings', false, 'Banking is not ready yet.') end
    if not isLoaded(src) then return sendResult(src, 'withdrawAtmEarnings', false, 'You are not fully logged in.') end

    local charId = getCharId(src)
    local preKey, preAtm = currentAtmForPlayer(src)
    if not charId or not preAtm then return sendResult(src, 'withdrawAtmEarnings', false, 'You need to be at the ATM to withdraw its earnings.') end

    local ran, opOk, message, extra = runLocked({
        'money:' .. tostring(charId),
        'atm:' .. tostring(preAtm.id or preKey),
    }, function()
        local atmKey, atm = currentAtmForPlayer(src)
        if not atm or atmKey ~= preKey then return false, 'You need to remain at the ATM.' end
        if atm.ownerCharacterId ~= charId then return false, 'You do not own this ATM.' end

        local row = MySQL.single.await(
            'SELECT pending_earnings FROM bank_atm_locations WHERE coord_key = ? AND owner_character_id = ? AND verified = 1 LIMIT 1',
            { atmKey, charId }
        )
        local amount = row and math.max(0, math.floor(tonumber(row.pending_earnings) or 0)) or 0
        if amount <= 0 then
            atm.pendingEarnings = 0
            return false, 'This ATM has no business earnings to withdraw.'
        end

        local txId = newTransactionId('ATMEARN', src)
        if not beginOperation(txId, 'atm_earnings_withdraw', charId, nil, amount, { atmId = atm.id }) then
            return false, 'The bank audit service is unavailable. Try again.'
        end

        -- Clear first with the exact amount as a compare-and-set. That prevents
        -- double-withdrawal if two requests arrive together or the DB is slow.
        local clearOk, affected = pcall(function()
            return MySQL.update.await([[
                UPDATE bank_atm_locations SET pending_earnings = 0
                WHERE coord_key = ? AND owner_character_id = ? AND pending_earnings = ? AND verified = 1
            ]], { atmKey, charId, amount })
        end)
        if not clearOk or tonumber(affected) ~= 1 then
            finishOperation(txId, 'rolled_back', { reason = 'earnings_compare_and_set_failed' })
            return false, 'The ATM earnings changed. Please try again.'
        end

        if not addMoney(src, 'bank', amount, 'atm_business_withdraw:' .. txId) then
            local restoreOk, restored = pcall(function()
                return MySQL.update.await([[
                    UPDATE bank_atm_locations SET pending_earnings = pending_earnings + ?
                    WHERE coord_key = ? AND owner_character_id = ? AND verified = 1
                ]], { amount, atmKey, charId })
            end)
            local recovered = restoreOk and tonumber(restored) == 1
            finishOperation(txId, recovered and 'rolled_back' or 'recovery_required', {
                reason = 'owner_credit_failed', earningsRestored = recovered,
            })
            if not recovered then
                adminLog(src, 'bank_recovery_required', {
                    category = 'players', transactionId = txId, operation = 'atm_earnings_withdraw',
                    atmId = atm.id, amount = amount,
                }, 'character:' .. tostring(charId), getCharName(src))
                return false, recoveryRequiredMessage(txId)
            end
            return false, 'The withdrawal could not be completed.'
        end

        atm.pendingEarnings = 0
        local _, newBank = getBalances(src)
        recordTransaction(charId, 'atm_earnings', amount, newBank, nil, nil, txId, 0)
        finishOperation(txId, 'committed', { atmId = atm.id, balanceAfter = newBank })
        recordAtmActivity(atm, 'earnings_withdrawal', charId, amount, 0, txId)
        adminLog(src, 'bank_atm_earnings_withdraw', {
            category = 'players', transactionId = txId, atmKey = atmKey, atmId = atm.id, amount = amount,
        }, 'character:' .. tostring(charId), getCharName(src))

        return true, ('Withdrew $%d in business earnings.'):format(amount), {
            amount = amount, transactionId = txId, atm = buildAtmView(atmKey, atm, charId),
        }
    end)

    if not ran then return sendResult(src, 'withdrawAtmEarnings', false, opOk == 'busy' and 'This ATM or account is already processing another operation.' or 'The withdrawal could not be completed.') end
    sendResult(src, 'withdrawAtmEarnings', opOk, message, extra)
end)

RegisterNetEvent('cm-bank:server:sellAtm', function()
    local src = source
    if not bankReady then return sendResult(src, 'sellAtm', false, 'Banking is not ready yet.') end
    if not isLoaded(src) then return sendResult(src, 'sellAtm', false, 'You are not fully logged in.') end

    local charId = getCharId(src)
    local preKey, preAtm = currentAtmForPlayer(src)
    if not charId or not preAtm then return sendResult(src, 'sellAtm', false, 'You need to be at the ATM to sell it.') end

    local ran, opOk, message, extra = runLocked({
        'money:' .. tostring(charId),
        'atm-owner:' .. tostring(charId),
        'atm:' .. tostring(preAtm.id or preKey),
    }, function()
        local atmKey, atm = currentAtmForPlayer(src)
        if not atm or atmKey ~= preKey then return false, 'You need to remain at the ATM while selling it.' end
        if atm.ownerCharacterId ~= charId then return false, 'You do not own this ATM.' end

        local row = MySQL.single.await([[
            SELECT owner_name, contact, fee_percent, pending_earnings, cash_reserve, owner_reserve_contribution
            FROM bank_atm_locations
            WHERE coord_key = ? AND owner_character_id = ? AND verified = 1
            LIMIT 1
        ]], { atmKey, charId })
        if not row then return false, 'ATM ownership could not be verified.' end

        local pending = math.max(0, math.floor(tonumber(row.pending_earnings) or 0))
        local reserveBefore = math.max(0, math.floor(tonumber(row.cash_reserve) or 0))
        local contribution = math.max(0, math.floor(tonumber(row.owner_reserve_contribution) or 0))
        -- Sale formula (documented in CHANGELOG_v1.6.0.md): the owner is paid
        -- the government base value, their unclaimed fee earnings, and only
        -- the portion of their OWN restocked cash that is still physically in
        -- the machine — never more than they personally contributed, and
        -- never any of the government starting reserve or player-deposited
        -- liquidity, both of which stay behind with the machine.
        local recoverableContribution = math.min(contribution, reserveBefore)
        local price = math.max(0, math.floor(tonumber(Config.Ownership and Config.Ownership.purchasePrice) or 0))
        local sellPercent = math.max(0, math.min(100, tonumber(Config.Ownership and Config.Ownership.governmentSellPercent) or 80))
        local governmentValue = math.floor(price * sellPercent / 100)
        local payout = governmentValue + pending + recoverableContribution
        local reserveAfter = reserveBefore - recoverableContribution
        local previousName = row.owner_name or atm.ownerName
        local previousContact = row.contact
        local previousFee = tonumber(row.fee_percent) or atm.feePercent or defaultFeePercent()
        local atmNumber = atm.id or 0

        local txId = newTransactionId('SELLATM', src)
        if not beginOperation(txId, 'atm_sale', charId, nil, payout, {
            atmId = atmNumber, governmentValue = governmentValue, pendingEarnings = pending,
            recoverableContribution = recoverableContribution, reserveBefore = reserveBefore, reserveAfter = reserveAfter,
        }) then
            return false, 'The bank audit service is unavailable. Try again.'
        end

        -- Remove ownership/earnings before paying. If the payout fails, restore
        -- the exact previous owner state instead of leaving a reusable payout.
        local clearOk, affected = pcall(function()
            return MySQL.update.await([[
                UPDATE bank_atm_locations
                SET owner_character_id = NULL, owner_name = NULL, fee_percent = 0,
                    pending_earnings = 0, contact = NULL, cash_reserve = ?, owner_reserve_contribution = 0
                WHERE coord_key = ? AND owner_character_id = ? AND verified = 1
            ]], { reserveAfter, atmKey, charId })
        end)
        if not clearOk or tonumber(affected) ~= 1 then
            finishOperation(txId, 'rolled_back', { reason = 'ownership_clear_failed' })
            return false, 'The ATM sale could not be started.'
        end

        if payout > 0 and not addMoney(src, 'bank', payout, 'atm_sell_government:' .. txId) then
            local restoreOk, restored = pcall(function()
                return MySQL.update.await([[
                    UPDATE bank_atm_locations
                    SET owner_character_id = ?, owner_name = ?, fee_percent = ?, pending_earnings = ?, contact = ?,
                        cash_reserve = ?, owner_reserve_contribution = ?
                    WHERE coord_key = ? AND owner_character_id IS NULL AND verified = 1
                ]], { charId, previousName, previousFee, pending, previousContact, reserveBefore, contribution, atmKey })
            end)
            local recovered = restoreOk and tonumber(restored) == 1
            finishOperation(txId, recovered and 'rolled_back' or 'recovery_required', {
                reason = 'sale_payout_failed', ownershipRestored = recovered,
            })
            if recovered then
                atm.ownerCharacterId, atm.ownerName, atm.feePercent = charId, previousName, previousFee
                atm.pendingEarnings, atm.contact = pending, previousContact
                atm.cashReserve, atm.ownerReserveContribution = reserveBefore, contribution
                return false, 'The sale could not be completed.'
            end

            adminLog(src, 'bank_recovery_required', {
                category = 'players', transactionId = txId, operation = 'atm_sale', atmId = atmNumber, payout = payout,
            }, 'character:' .. tostring(charId), previousName)
            return false, recoveryRequiredMessage(txId)
        end

        recordAtmActivity(atm, 'sale', charId, payout, 0, txId)

        atm.ownerCharacterId = nil
        atm.ownerName = nil
        atm.feePercent = 0
        atm.pendingEarnings = 0
        atm.contact = nil
        atm.cashReserve = reserveAfter
        atm.ownerReserveContribution = 0

        local _, newBank = getBalances(src)
        recordTransaction(charId, 'atm_sale', payout, newBank, nil, nil, txId, 0)
        finishOperation(txId, 'committed', { atmId = atmNumber, payout = payout, balanceAfter = newBank })
        adminLog(src, 'bank_atm_sell', {
            category = 'players', transactionId = txId, atmKey = atmKey, atmNumber = atmNumber, payout = payout,
            governmentValue = governmentValue, pendingEarnings = pending, recoverableContribution = recoverableContribution,
        }, 'character:' .. tostring(charId), previousName)

        return true, ('Sold ATM No. %d to the government for $%d.'):format(atmNumber, payout), {
            amount = payout, transactionId = txId, atm = buildAtmView(atmKey, atm, charId),
        }
    end)

    if not ran then return sendResult(src, 'sellAtm', false, opOk == 'busy' and 'This ATM or account is already processing another operation.' or 'The sale could not be completed.') end
    sendResult(src, 'sellAtm', opOk, message, extra)
end)

RegisterNetEvent('cm-bank:server:setAtmContact', function(contact)
    local src = source
    if not bankReady then return sendResult(src, 'setAtmContact', false, 'Banking is not ready yet.') end
    if not isLoaded(src) then return sendResult(src, 'setAtmContact', false, 'You are not fully logged in.') end

    local charId = getCharId(src)
    local preKey, preAtm = currentAtmForPlayer(src)
    if not charId or not preAtm then return sendResult(src, 'setAtmContact', false, 'You need to be at the ATM to manage it.') end

    contact = tostring(contact or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #contact > 100 then contact = contact:sub(1, 100) end
    local newContact = contact ~= '' and contact or nil

    local ran, opOk, message, extra = runLocked({ 'atm:' .. tostring(preAtm.id or preKey) }, function()
        local atmKey, atm = currentAtmForPlayer(src)
        if not atm or atmKey ~= preKey then return false, 'You need to remain at the ATM to manage it.' end
        if atm.ownerCharacterId ~= charId then return false, 'You do not own this ATM.' end

        local ok, affected = pcall(function()
            return MySQL.update.await(
                'UPDATE bank_atm_locations SET contact = ? WHERE coord_key = ? AND owner_character_id = ? AND verified = 1',
                { newContact, atmKey, charId }
            )
        end)
        if not ok or tonumber(affected) ~= 1 then return false, 'Contact info could not be updated.' end

        atm.contact = newContact
        return true, atm.contact and 'Contact info updated.' or 'Contact info cleared.', {
            atm = buildAtmView(atmKey, atm, charId),
        }
    end)

    if not ran then return sendResult(src, 'setAtmContact', false, opOk == 'busy' and 'This ATM is busy. Try again.' or 'Contact info could not be updated.') end
    sendResult(src, 'setAtmContact', opOk, message, extra)
end)

-- Shared reply helper for the admin commands below: chat message in-game,
-- console print from the server console.
local function adminReply(src, msg)
    if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', msg } })
    else print('[CM-BANK] ' .. msg) end
end

RegisterCommand('atmpending', function(src)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        return adminReply(src, 'You do not have permission to do that.')
    end
    if not bankReady then return adminReply(src, 'Banking is still starting.') end

    local pending = {}
    for _, atm in pairs(atmLocations) do
        if atm.verified ~= true then pending[#pending + 1] = atm end
    end
    table.sort(pending, function(a, b) return (a.id or 0) < (b.id or 0) end)

    if #pending == 0 then return adminReply(src, 'No ATM discoveries are waiting for verification.') end
    adminReply(src, ('%d ATM discovery/discoveries are waiting for verification:'):format(#pending))
    for i = 1, math.min(#pending, 15) do
        local atm = pending[i]
        adminReply(src, ('ATM No. %d @ %.2f, %.2f, %.2f'):format(atm.id or 0, atm.x or 0, atm.y or 0, atm.z or 0))
    end
    if #pending > 15 then adminReply(src, ('...and %d more.'):format(#pending - 15)) end
end, false)

RegisterCommand('atmverify', function(src, args)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        return adminReply(src, 'You do not have permission to do that.')
    end
    if not bankReady then return adminReply(src, 'Banking is still starting.') end
    if src == 0 and not args[1] then
        return adminReply(src, 'Usage from console: atmverify <atmNumber>')
    end

    local key, atm = resolveAtmTarget(src, args[1])
    if not atm then return adminReply(src, 'No matching ATM found. Stand beside it or pass its number.') end
    if atm.verified == true then return adminReply(src, ('ATM No. %d is already verified.'):format(atm.id or 0)) end

    local ran, result, message = runLocked({ 'atm:' .. tostring(atm.id or key) }, function()
        local ok, affected = pcall(function()
            return MySQL.update.await(
                'UPDATE bank_atm_locations SET verified = 1, for_sale = 1 WHERE coord_key = ? AND verified = 0',
                { key }
            )
        end)
        if not ok or tonumber(affected) ~= 1 then return false, 'The ATM could not be verified.' end

        atm.verified = true
        atm.forSale = true
        adminLog(src, 'bank_atm_verify', {
            category = 'players', atmKey = key, atmNumber = atm.id,
            x = atm.x, y = atm.y, z = atm.z,
        }, 'atm:' .. key, nil)
        TriggerClientEvent('cm-bank:client:addAtmBlip', -1, { x = atm.x, y = atm.y, z = atm.z })
        return true, ('ATM No. %d verified and enabled for banking/ownership.'):format(atm.id or 0)
    end)

    if not ran then return adminReply(src, result == 'busy' and 'That ATM is busy. Try again.' or 'The ATM could not be verified.') end
    adminReply(src, message or (result and 'ATM verified.' or 'The ATM could not be verified.'))
end, false)

RegisterCommand('atmreject', function(src, args)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        return adminReply(src, 'You do not have permission to do that.')
    end
    if not bankReady then return adminReply(src, 'Banking is still starting.') end
    if src == 0 and not args[1] then
        return adminReply(src, 'Usage from console: atmreject <atmNumber>')
    end

    local key, atm = resolveAtmTarget(src, args[1])
    if not atm then return adminReply(src, 'No matching ATM found. Stand beside it or pass its number.') end
    if atm.verified == true then return adminReply(src, 'Verified ATMs cannot be rejected. Disable them instead if needed.') end
    if atm.ownerCharacterId then return adminReply(src, 'An owned ATM cannot be rejected.') end

    local atmNumber = atm.id or 0
    local ran, result, message = runLocked({ 'atm:' .. tostring(atm.id or key) }, function()
        local ok, affected = pcall(function()
            return MySQL.update.await('DELETE FROM bank_atm_locations WHERE coord_key = ? AND verified = 0', { key })
        end)
        if not ok or tonumber(affected) ~= 1 then return false, 'The pending ATM could not be removed.' end
        atmLocations[key] = nil
        adminLog(src, 'bank_atm_reject', { category = 'players', atmKey = key, atmNumber = atmNumber }, 'atm:' .. key, nil)
        return true, ('Rejected pending ATM No. %d.'):format(atmNumber)
    end)

    if not ran then return adminReply(src, result == 'busy' and 'That ATM is busy. Try again.' or 'The pending ATM could not be removed.') end
    adminReply(src, message or (result and 'Pending ATM removed.' or 'The pending ATM could not be removed.'))
end, false)

RegisterCommand('atmdisable', function(src, args)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        return adminReply(src, 'You do not have permission to do that.')
    end
    if not bankReady then return adminReply(src, 'Banking is still starting.') end
    if src == 0 and not args[1] then
        return adminReply(src, 'Usage from console: atmdisable <atmNumber>')
    end

    local key, atm = resolveAtmTarget(src, args[1])
    if not atm then return adminReply(src, 'No matching ATM found. Walk right up to it, or pass its number.') end

    local ran, changed = runLocked({ 'atm:' .. tostring(atm.id or key) }, function()
        return persistAtmDisabled(src, key, atm, not (atm.adminDisabled == true))
    end)
    if not ran then return adminReply(src, changed == 'busy' and 'That ATM is busy. Try again.' or 'ATM state could not be changed.') end
    if changed ~= true then return adminReply(src, 'ATM state could not be changed.') end
    adminReply(src, ('ATM No. %d is now %s.'):format(atm.id or 0, atm.adminDisabled and 'disabled' or 'enabled'))
end, false)

RegisterCommand('atmforsale', function(src, args)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        return adminReply(src, 'You do not have permission to do that.')
    end
    if not bankReady then return adminReply(src, 'Banking is still starting.') end
    if src == 0 and not args[1] then
        return adminReply(src, 'Usage from console: atmforsale <atmNumber>')
    end

    local key, atm = resolveAtmTarget(src, args[1])
    if not atm then return adminReply(src, 'No matching ATM found. Walk right up to it, or pass its number.') end
    if atm.verified ~= true then return adminReply(src, ('ATM No. %d is pending verification.'):format(atm.id or 0)) end

    local ran, changed = runLocked({ 'atm:' .. tostring(atm.id or key) }, function()
        local newForSale = not (atm.forSale ~= false)
        local ok, affected = pcall(function()
            return MySQL.update.await(
                'UPDATE bank_atm_locations SET for_sale = ? WHERE coord_key = ? AND verified = 1',
                { newForSale and 1 or 0, key }
            )
        end)
        if not ok or tonumber(affected) ~= 1 then return false end
        atm.forSale = newForSale
        adminLog(src, 'bank_atm_for_sale_toggle', { category = 'players', atmKey = key, forSale = atm.forSale }, 'atm:' .. key, atm.ownerName)
        return true
    end)
    if not ran then return adminReply(src, changed == 'busy' and 'That ATM is busy. Try again.' or 'ATM sale state could not be changed.') end
    if changed ~= true then return adminReply(src, 'ATM sale state could not be changed.') end
    adminReply(src, ('ATM No. %d is now %s.'):format(atm.id or 0, atm.forSale and 'for sale' or 'not for sale'))
end, false)

RegisterCommand('atmsetowner', function(src, args)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        return adminReply(src, 'You do not have permission to do that.')
    end
    if not bankReady then return adminReply(src, 'Banking is still starting.') end

    local targetCharId = tonumber(args[1])
    if not targetCharId then return adminReply(src, 'Usage: atmsetowner <characterId> [atmNumber]') end
    if src == 0 and not args[2] then return adminReply(src, 'Usage from console: atmsetowner <characterId> <atmNumber>') end

    local key, atm = resolveAtmTarget(src, args[2])
    if not atm then return adminReply(src, 'No matching ATM found. Walk right up to it, or pass its number.') end
    if atm.verified ~= true then return adminReply(src, ('ATM No. %d is pending verification. Run /atmverify first.'):format(atm.id or 0)) end

    local onlineSrc = getSourceByCharId(targetCharId)
    local name = (onlineSrc and getCharName(onlineSrc)) or getCharacterNameByIdOffline(targetCharId)
        or ('Character %d'):format(targetCharId)

    local ran, changed = runLocked({ 'atm:' .. tostring(atm.id or key), 'atm-owner:' .. tostring(targetCharId) }, function()
        local fee = isValidFeeChoice(atm.feePercent) and atm.feePercent or defaultFeePercent()
        local ok, affected = pcall(function()
            return MySQL.update.await(
                'UPDATE bank_atm_locations SET owner_character_id = ?, owner_name = ?, fee_percent = ? WHERE coord_key = ? AND verified = 1',
                { targetCharId, name, fee, key }
            )
        end)
        if not ok or tonumber(affected) ~= 1 then return false end
        atm.ownerCharacterId = targetCharId
        atm.ownerName = name
        atm.feePercent = fee
        adminLog(src, 'bank_atm_admin_set_owner', { category = 'players', atmKey = key, atmNumber = atm.id, targetCharacterId = targetCharId },
            'character:' .. tostring(targetCharId), name)
        return true
    end)
    if not ran then return adminReply(src, changed == 'busy' and 'That ATM or owner is busy. Try again.' or 'ATM ownership could not be changed.') end
    if changed ~= true then return adminReply(src, 'ATM ownership could not be changed.') end
    adminReply(src, ('ATM No. %d ownership set to %s.'):format(atm.id or 0, name))
end, false)

RegisterCommand('atmclearowner', function(src, args)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        return adminReply(src, 'You do not have permission to do that.')
    end
    if not bankReady then return adminReply(src, 'Banking is still starting.') end
    if src == 0 and not args[1] then return adminReply(src, 'Usage from console: atmclearowner <atmNumber>') end

    local key, atm = resolveAtmTarget(src, args[1])
    if not atm then return adminReply(src, 'No matching ATM found. Walk right up to it, or pass its number.') end
    if not atm.ownerCharacterId then return adminReply(src, ('ATM No. %d is already unowned.'):format(atm.id or 0)) end

    local previousOwnerId, previousName = atm.ownerCharacterId, atm.ownerName
    local ran, changed = runLocked({ 'atm:' .. tostring(atm.id or key), 'atm-owner:' .. tostring(previousOwnerId) }, function()
        local ok, affected = pcall(function()
            return MySQL.update.await([[
                UPDATE bank_atm_locations
                SET owner_character_id = NULL, owner_name = NULL, fee_percent = 0,
                    pending_earnings = 0, contact = NULL
                WHERE coord_key = ? AND owner_character_id = ?
            ]], { key, previousOwnerId })
        end)
        if not ok or tonumber(affected) ~= 1 then return false end
        atm.ownerCharacterId = nil
        atm.ownerName = nil
        atm.feePercent = 0
        atm.pendingEarnings = 0
        atm.contact = nil
        adminLog(src, 'bank_atm_admin_clear_owner', { category = 'players', atmKey = key, atmNumber = atm.id }, 'atm:' .. key, previousName)
        return true
    end)
    if not ran then return adminReply(src, changed == 'busy' and 'That ATM is busy. Try again.' or 'ATM ownership could not be cleared.') end
    if changed ~= true then return adminReply(src, 'ATM ownership could not be cleared.') end
    adminReply(src, ('ATM No. %d ownership cleared (was %s). Any unclaimed business balance was forfeited.'):format(atm.id or 0, previousName or 'unknown'))
end, false)

RegisterCommand('atmownership', function(src, args)
    if not isAdminAllowed(src, 'atm.admin.kill_switch') then
        if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', 'You do not have permission to do that.' } })
        else print('[CM-BANK] Permission denied.') end
        return
    end

    local arg = tostring(args[1] or ''):lower()
    if arg ~= 'on' and arg ~= 'off' then
        local msg = 'Usage: /atmownership on|off'
        if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', msg } })
        else print('[CM-BANK] ' .. msg) end
        return
    end

    persistOwnershipToggle(src, arg == 'on')
    local msg = ownershipEnabled and 'ATM ownership enabled.' or 'ATM ownership disabled.'
    if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', msg } })
    else print('[CM-BANK] ' .. msg) end
end, false)

RegisterCommand('addbankteller', function(src, args)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', 'You do not have permission to do that.' } })
        else print('[CM-BANK] Permission denied.') end
        return
    end
    if src == 0 then
        print('[CM-BANK] /addbankteller must be run in-game, standing where the NPC should appear.')
        return
    end

    local name = table.concat(args, ' ')
    if name == '' then
        TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', 'Usage: /addbankteller <name>' } })
        return
    end

    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local model = tostring(Config.Tellers and Config.Tellers.model or 'csb_bankman')
    local charId = getCharId(src)

    local ok, insertId = pcall(function()
        return MySQL.insert.await(
            'INSERT INTO bank_tellers (name, model, x, y, z, heading, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { name, model, coords.x, coords.y, coords.z, heading, tostring(charId or ('src:' .. tostring(src))) }
        )
    end)
    if not ok or not insertId then
        TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', 'Could not save that teller.' } })
        dbg('Failed to insert bank teller:', insertId)
        return
    end

    local teller = { id = insertId, name = name, model = model, x = coords.x, y = coords.y, z = coords.z, heading = heading }
    tellers[insertId] = teller

    adminLog(src, 'bank_teller_add', { category = 'players', name = name, tellerId = insertId }, nil, name)
    TriggerClientEvent('cm-bank:client:addTeller', -1, teller)
    TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', ('Placed bank teller "%s".'):format(name) } })
end, false)

RegisterCommand('removebankteller', function(src)
    if not isAdminAllowed(src, 'atm.admin.manage') then
        if src ~= 0 then TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', 'You do not have permission to do that.' } })
        else print('[CM-BANK] Permission denied.') end
        return
    end
    if src == 0 then
        print('[CM-BANK] /removebankteller must be run in-game, standing next to the NPC.')
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(src))
    local nearestId, nearestDist = nil, 5.0
    for id, t in pairs(tellers) do
        local dist = #(coords - vector3(t.x, t.y, t.z))
        if dist < nearestDist then
            nearestDist = dist
            nearestId = id
        end
    end
    if not nearestId then
        TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', 'No bank teller nearby. Stand right next to it first.' } })
        return
    end

    local name = tellers[nearestId].name
    tellers[nearestId] = nil
    local ok, err = pcall(function()
        MySQL.query.await('DELETE FROM bank_tellers WHERE id = ?', { nearestId })
    end)
    if not ok then dbg('Failed to delete bank teller:', err) end

    adminLog(src, 'bank_teller_remove', { category = 'players', name = name, tellerId = nearestId }, nil, name)
    TriggerClientEvent('cm-bank:client:removeTeller', -1, nearestId)
    TriggerClientEvent('chat:addMessage', src, { args = { '[CM-BANK]', ('Removed bank teller "%s".'):format(name) } })
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    actionCooldowns[src] = nil
    transferCooldowns[src] = nil
    atmReportCooldowns[src] = nil
    lookupCooldowns[src] = nil
    transferRateHistory[src] = nil
end)
