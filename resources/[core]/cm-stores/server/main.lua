local Config = CMStores.Config
local purchaseLocks = {}

local function dprint(...)
    if not Config.Debug then return end
    print('[CM-STORES]', ...)
end

local function notify(src, msg)
    TriggerClientEvent('chat:addMessage', src, { args = { 'Store', msg } })
    TriggerClientEvent('cm-inventory:client:notify', src, msg)
end

local function callExport(resource, method, ...)
    if GetResourceState(resource) ~= 'started' then return false, nil end
    local args = { ... }

    -- Dot-style only. Colon-style export calls shift arguments in this framework
    -- and can turn src into itemName, which caused SQL/inventory errors.
    local ok, result, extra = pcall(function()
        return exports[resource][method](table.unpack(args))
    end)

    if ok then return true, result, extra end

    print(('[CM-STORES] Export failed: %s.%s | %s'):format(resource, method, tostring(result)))
    return false, result
end

local function findStore(storeId)
    for _, store in ipairs(Config.Stores) do
        if store.id == storeId then return store end
    end
    return nil
end

local function findStoreItem(store, itemName)
    for _, item in ipairs(store.items or {}) do
        if item.name == itemName then return item end
    end
    return nil
end

local function getItemDef(itemName)
    local ok, def = callExport('cm-items', 'GetItem', itemName)
    if ok and type(def) == 'table' then return def end

    return {
        name = itemName,
        label = itemName,
        image = itemName .. '.png',
        weight = 0,
        stack = true,
        usable = false,
        inventory = true,
        category = 'misc',
        itemType = 'normal',
        description = ''
    }
end

local function isVirtualBlocked(itemName)
    local blocked = {
        phone = true,
        vehicle_key = true,
        house_key = true,
        business_key = true
    }
    return blocked[tostring(itemName or '')] == true
end

local function isInventoryItem(itemName)
    itemName = tostring(itemName or '')

    -- We only hard-block virtual systems. The store UI must not mark
    -- normal shop items as unavailable just because the player has no cash,
    -- no bag space, or an older cm-items export returned false.
    if isVirtualBlocked(itemName) then return false end

    local ok, result = callExport('cm-items', 'IsInventoryItem', itemName)
    if ok and result == true then return true end

    -- Safe fallback: items listed in store config are buyable unless they are
    -- in the virtual blacklist above. The inventory AddItem/CanCarry checks
    -- still validate everything during purchase.
    return true
end

local function getCharacterId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    local ok, stateId = pcall(function()
        local state = Player(src).state
        return state.charId or state.characterId or state.character_id or state.citizenid
    end)
    if ok and stateId then return tostring(stateId) end

    ok, stateId = pcall(function()
        if GetResourceState('cm-core') == 'started' and exports['cm-core'].GetPlayer then
            local p = exports['cm-core'].GetPlayer(src)
            if type(p) == 'table' then
                return p.CharacterId or p.charId or (p.Character and p.Character.id) or (p.character and p.character.id)
            end
        end
    end)
    if ok and stateId then return tostring(stateId) end

    -- Do NOT call cm-characters export from stores. Older cm-characters exports
    -- can throw when invoked externally. Resolve the selected character from
    -- account state/database instead.
    local accountId
    pcall(function()
        local st = Player(src).state
        accountId = st.accountId or st.account_id or st.cmAccountId
    end)

    if accountId then
        local okDb, dbCharId = pcall(function()
            return MySQL.scalar.await([[
                SELECT id FROM characters
                WHERE account_id = ?
                ORDER BY last_played DESC, updated_at DESC, created_at DESC
                LIMIT 1
            ]], { tostring(accountId) })
        end)
        if okDb and dbCharId then return tostring(dbCharId) end
    end

    return nil
end

local function pushCashUpdate(src, cash)
    cash = tonumber(cash) or 0
    pcall(function() Player(src).state:set('cash', cash, true) end)
    TriggerClientEvent('cm-playerdata:client:update', src, 'cash', cash)
end

local function getCash(src)
    local ok, cash = callExport('cm-playerdata', 'GetCash', src)
    if ok and tonumber(cash) ~= nil then return tonumber(cash) end

    ok, cash = callExport('cm-playerdata', 'GetMoney', src, 'cash')
    if ok and tonumber(cash) ~= nil then return tonumber(cash) end

    local charId = getCharacterId(src)
    if not charId then return 0 end

    local dbCash = MySQL.scalar.await('SELECT cash FROM characters WHERE id = ? LIMIT 1', { charId })
    return tonumber(dbCash) or 0
end

local function removeCash(src, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end

    local ok, result = callExport('cm-playerdata', 'RemoveCash', src, amount, reason or 'store_purchase')
    if ok and result == true then return true end

    ok, result = callExport('cm-playerdata', 'RemoveMoney', src, 'cash', amount, reason or 'store_purchase')
    if ok and result == true then return true end

    local charId = getCharacterId(src)
    if not charId then return false end

    local changed = MySQL.update.await('UPDATE characters SET cash = cash - ? WHERE id = ? AND cash >= ?', { amount, charId, amount })
    if tonumber(changed) and tonumber(changed) > 0 then
        local newCash = MySQL.scalar.await('SELECT cash FROM characters WHERE id = ? LIMIT 1', { charId }) or 0
        pushCashUpdate(src, newCash)
        return true
    end

    return false
end

local function addCash(src, amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return true end

    local ok, result = callExport('cm-playerdata', 'AddCash', src, amount, reason or 'store_refund')
    if ok and result == true then return true end

    ok, result = callExport('cm-playerdata', 'AddMoney', src, 'cash', amount, reason or 'store_refund')
    if ok and result == true then return true end

    local charId = getCharacterId(src)
    if not charId then return false end

    local changed = MySQL.update.await('UPDATE characters SET cash = cash + ? WHERE id = ?', { amount, charId })
    if tonumber(changed) and tonumber(changed) > 0 then
        local newCash = MySQL.scalar.await('SELECT cash FROM characters WHERE id = ? LIMIT 1', { charId }) or 0
        pushCashUpdate(src, newCash)
        return true
    end

    return false
end

local function canCarry(src, itemName, amount, metadata)
    local ok, result, reason = callExport('cm-inventory', 'CanCarryItem', src, itemName, amount, metadata or {})
    if ok and result ~= nil then return result == true, reason end
    return true, nil
end

local function addItem(src, itemName, amount, metadata, reason)
    local ok, result, failReason = callExport('cm-inventory', 'AddItem', src, itemName, amount, metadata or {}, reason or 'store_purchase')
    if ok and result ~= nil then return result == true, failReason end
    return false, 'Inventory AddItem export failed.'
end

local function audit(src, action, data)
    data = data or {}
    data.player_src = src
    pcall(function()
        MySQL.insert.await([[INSERT INTO store_audit (player_src, action, data)
            VALUES (?, ?, ?)]], { src, action, json.encode(data) })
    end)
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS store_audit (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        player_src INT NULL,
        action VARCHAR(80) NOT NULL,
        data LONGTEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_action (action)
    )]])
    print('[CM-STORES] Started v1.3-integrationfix')
end)

RegisterNetEvent('cm-stores:server:requestStore', function(storeId)
    local src = source
    local store = findStore(storeId)
    if not store then return end

    local balance = getCash(src) or 0
    local items = {}

    for _, shopItem in ipairs(store.items or {}) do
        local itemName = shopItem.name
        local def = getItemDef(itemName)
        items[#items + 1] = {
            name = itemName,
            label = def.label or itemName,
            image = def.image or (itemName .. '.png'),
            weight = tonumber(def.weight) or 0,
            stack = def.stack ~= false,
            usable = def.usable == true,
            category = def.category or 'misc',
            itemType = def.itemType or def.rarity or 'normal',
            description = def.description or '',
            price = tonumber(shopItem.price) or 0,
            max = tonumber(shopItem.max) or 99,
            inventory = true,
            buyable = not isVirtualBlocked(itemName)
        }
    end

    TriggerClientEvent('cm-stores:client:storeData', src, {
        id = store.id,
        name = store.name,
        npcName = store.npcName or 'Store Clerk',
        balance = balance,
        currency = Config.Currency,
        items = items
    })
end)

RegisterNetEvent('cm-stores:server:buyItem', function(requestId, storeId, itemName, amount)
    local src = source
    requestId = tonumber(requestId) or 0
    itemName = tostring(itemName or '')
    amount = math.floor(tonumber(amount) or 0)

    if purchaseLocks[src] then
        TriggerClientEvent('cm-stores:client:buyResult', src, requestId, false, 'Purchase already processing.')
        return
    end

    purchaseLocks[src] = true

    local function finish(ok, message, extra)
        purchaseLocks[src] = nil
        TriggerClientEvent('cm-stores:client:buyResult', src, requestId, ok, message, extra or {})
    end

    if amount <= 0 or amount > 99 then
        finish(false, 'Invalid quantity.')
        return
    end

    local store = findStore(storeId)
    if not store then
        finish(false, 'Invalid store.')
        return
    end

    local shopItem = findStoreItem(store, itemName)
    if not shopItem then
        finish(false, 'Item is not sold here.')
        return
    end

    if amount > (tonumber(shopItem.max) or 99) then
        finish(false, ('Maximum quantity is %s.'):format(shopItem.max))
        return
    end

    -- Only virtual/system items are blocked here (phone/keys/etc.).
    -- Normal shop items must be visible and buyable; inventory validates slot/weight when adding.
    if isVirtualBlocked(itemName) then
        finish(false, 'This item is handled by another system, not inventory.')
        return
    end

    local price = tonumber(shopItem.price) or 0
    local total = price * amount

    -- Validate only when player confirms Buy. Do not hide items in UI.
    local cash = getCash(src)
    if cash ~= nil and cash < total then
        finish(false, ('Not enough funds. Need $%s, you have $%s.'):format(total, cash))
        return
    end

    local carryOk, carryReason = canCarry(src, itemName, amount, {})
    if not carryOk then
        finish(false, carryReason or 'No space in backpack / weight limit reached.')
        return
    end

    if total > 0 then
        local paid = removeCash(src, total, 'store_purchase_' .. itemName)
        if not paid then
            finish(false, 'Could not remove cash.')
            return
        end
    end

    local added, addReason = addItem(src, itemName, amount, {}, 'store_purchase')
    if not added then
        if total > 0 then addCash(src, total, 'store_purchase_refund') end
        finish(false, tostring(addReason or 'No space in backpack / weight limit reached.'))
        return
    end

    audit(src, 'purchase', {
        store = storeId,
        item = itemName,
        amount = amount,
        total = total
    })

    local newBalance = getCash(src) or 0
    finish(true, ('Purchased %sx %s for $%s.'):format(amount, itemName, total), {
        balance = newBalance
    })
end)
