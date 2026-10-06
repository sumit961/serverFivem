-- cm-phone schema. Additive and repeatable: CREATE TABLE IF NOT EXISTS only; never drops or
-- truncates. character_id columns match characters.id (VARCHAR(50), utf8mb4_general_ci).
local S = CMPhone.Server

local TABLE_OPTS = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci'

S.Schema = {
    ([[CREATE TABLE IF NOT EXISTS cm_phone_numbers (
        character_id VARCHAR(50) NOT NULL,
        phone_number VARCHAR(12) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (character_id),
        UNIQUE KEY uq_phone_number (phone_number)
    ) %s]]):format(TABLE_OPTS),

    ([[CREATE TABLE IF NOT EXISTS cm_phone_contacts (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        owner_character_id VARCHAR(50) NOT NULL,
        contact_number VARCHAR(12) NOT NULL,
        display_name VARCHAR(64) NOT NULL,
        favourite TINYINT(1) NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_contact_owner_number (owner_character_id, contact_number),
        KEY idx_contact_owner (owner_character_id)
    ) %s]]):format(TABLE_OPTS),

    ([[CREATE TABLE IF NOT EXISTS cm_phone_conversations (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        kind ENUM('direct','group') NOT NULL DEFAULT 'direct',
        direct_key VARCHAR(110) NULL,
        name VARCHAR(64) NULL,
        creator_character_id VARCHAR(50) NULL,
        last_message_id BIGINT UNSIGNED NULL,
        last_message_at TIMESTAMP NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        UNIQUE KEY uq_direct_key (direct_key)
    ) %s]]):format(TABLE_OPTS),

    ([[CREATE TABLE IF NOT EXISTS cm_phone_conversation_members (
        conversation_id BIGINT UNSIGNED NOT NULL,
        character_id VARCHAR(50) NOT NULL,
        last_read_message_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
        joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (conversation_id, character_id),
        KEY idx_member_character (character_id)
    ) %s]]):format(TABLE_OPTS),

    ([[CREATE TABLE IF NOT EXISTS cm_phone_messages (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        conversation_id BIGINT UNSIGNED NOT NULL,
        sender_character_id VARCHAR(50) NULL,
        sender_number VARCHAR(12) NOT NULL,
        kind ENUM('text','location','system') NOT NULL DEFAULT 'text',
        body VARCHAR(2000) NOT NULL DEFAULT '',
        payload TEXT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_message_conversation (conversation_id, id)
    ) %s]]):format(TABLE_OPTS),

    ([[CREATE TABLE IF NOT EXISTS cm_phone_calls (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        caller_character_id VARCHAR(50) NOT NULL,
        caller_number VARCHAR(12) NOT NULL,
        callee_character_id VARCHAR(50) NOT NULL,
        callee_number VARCHAR(12) NOT NULL,
        outcome ENUM('answered','missed','declined','timeout','busy','unavailable','ended') NOT NULL,
        started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        answered_at TIMESTAMP NULL,
        ended_at TIMESTAMP NULL,
        duration_seconds INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        KEY idx_call_caller (caller_character_id, id),
        KEY idx_call_callee (callee_character_id, id)
    ) %s]]):format(TABLE_OPTS),

    ([[CREATE TABLE IF NOT EXISTS cm_phone_blocks (
        owner_character_id VARCHAR(50) NOT NULL,
        blocked_number VARCHAR(12) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (owner_character_id, blocked_number)
    ) %s]]):format(TABLE_OPTS),

    ([[CREATE TABLE IF NOT EXISTS cm_phone_adverts (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        author_character_id VARCHAR(50) NOT NULL,
        author_number VARCHAR(12) NOT NULL,
        body VARCHAR(400) NOT NULL,
        fee_paid INT UNSIGNED NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_advert_expires (expires_at),
        KEY idx_advert_author (author_character_id, id)
    ) %s]]):format(TABLE_OPTS),
}

S.SchemaReady = false
S.SchemaError = nil

function S.AwaitSchema()
    local waited = 0
    while not S.SchemaReady and not S.SchemaError and waited < 15000 do
        Wait(100)
        waited = waited + 100
    end
    return S.SchemaReady
end

CreateThread(function()
    if not MySQL then S.SchemaError = 'oxmysql unavailable' return end
    for index, statement in ipairs(S.Schema) do
        local ok, err = pcall(function() return MySQL.query.await(statement) end)
        if not ok then
            S.SchemaError = ('schema statement %d failed: %s'):format(index, tostring(err))
            print('[cm-phone] ' .. S.SchemaError)
            return
        end
    end
    S.SchemaReady = true
    print(('[cm-phone] schema ready (%d tables)'):format(#S.Schema))
end)
