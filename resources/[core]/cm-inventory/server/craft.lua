-- cm-inventory/craft.lua
-- Atomic single-character item transformation ("craft settlement") for cm-crafting.
-- Loaded by the server/main.lua bootloader AFTER external.lua (needs sendInventorySmart) and BEFORE drops.lua/events.lua,
-- inside the same chunk so it reuses the real inventory internals (getItemDef, rowCanStackWithMetadata,
-- decorateNewItemMetadata, getBagLevelFromItem, canPlaceInSlot ...). Everything is wrapped in a do-block so it adds no
-- permanent top-level locals (the combined chunk is near Lua's 200-local limit).
--
-- Public server exports (trusted resource only, see CraftTrusted): ValidateCraftTransaction, ExecuteCraftTransaction,
-- GetCraftTransactionStatus. Contract: cm-crafting/docs/README.md.
--
-- Scope: ONE character's items -> that character's items. Not a two-party exchange (that is cm-trade, still pending).
-- Item policy (V1, deliberate):
--   * inputs   : stackable, plain (no durability default), matched ONLY against rows whose stack-metadata signature equals that
--                of a metadata-free item; consumed across stacks, largest first (same order as RemoveItem). Carry slots only
--                (quickaccess/pocket/backpack), never equipment slots. Metadata-matched inputs are NOT supported.
--   * outputs  : stackable, non-clothing, non-weapon/armor only. Unique/serial/clothing outputs are rejected (invalid_item)
--                because serial creation cannot join this transaction safely. Metadata comes from the trusted recipe, is
--                validated with cm-items:ValidateMetadata and decorated with the normal inventory rules.
--   * tools    : required-and-kept; optional durabilityUse is applied to the tool's metadata.durability in the SAME transaction.
--                A durability tool must sit in a single-quantity row (a stack of N tools cannot be partially worn).
do
    local Cfg = {
        trusted = { ['cm-crafting'] = true },                 -- craft transactions (inputs + tools -> outputs)
        sinkTrusted = { ['cm-commercial-ownership'] = true }, -- consume-only item sink (destination owner credits its own balance)
        -- output-only paid-goods grant (the caller has already taken payment; see ExecuteItemGrant). Per-caller policy:
        --   clothing = true  : may grant clothing_* items (clothing/bag garments with appearance metadata); never weapons/armor/unique
        --   limits           : per-caller overrides of line/metadata/payload limits (clothing carts carry large metadata)
        grantTrusted = {
            ['cm-gasstations'] = {},
            ['cm-store'] = { limits = { maxOutputLines = 24 } },
            ['nv_cloth'] = { clothing = true, limits = { maxOutputLines = 24, maxMetadataBytes = 8192, maxMetadataNodes = 256, maxMetadataDepth = 6, maxPayload = 60000 } },
        },
        exchangeTrusted = { ['cm-trade'] = true },            -- two-character item exchange (server/exchange.lua); cm-trade orchestrates, never touches rows
        exchangeMaxLines = 8, exchangeMaxQuantity = 1000,
        maxInputLines = 8, maxOutputLines = 8, maxToolLines = 4,
        maxAmount = 10000, maxTotalAmount = 50000,
        maxDurabilityUse = 100,
        maxMetadataBytes = 1024, maxMetadataDepth = 4, maxMetadataNodes = 64,
        maxRowQuantity = 2000000000,
        lockTimeoutMs = 5000, lockStaleMs = 40000,
    }
    local TX_TYPE, SINK_TYPE, GRANT_TYPE = 'craft', 'item_sink', 'item_grant'
    local TYPE_OF = { craft = TX_TYPE, sink = SINK_TYPE, grant = GRANT_TYPE }
    local ledgerReady = false

    ------------------------------------------------------------------ utilities
    local function failpointNoop() end
    local failpoint = failpointNoop
    -- Test hook: only exists in a development runtime with QA enabled; never exported to other resources.
    if GetConvar('cm_environment', '') == 'development' and GetConvar('cm_qa_enabled', '0') == '1' then
        CMInventory.SetCraftFailpoint = function(fn) failpoint = type(fn) == 'function' and fn or failpointNoop end
        CMInventory.CraftConfig = Cfg
    end

    local function fnv1a(str)
        local h = -3750763034362895579 -- FNV-1a 64-bit offset basis (two's complement)
        for i = 1, #str do
            h = (h ~ str:byte(i)) * 1099511628211
        end
        return ('%016x'):format(h)
    end

    local function isInt(n, lo, hi)
        return type(n) == 'number' and n == n and n % 1 == 0 and n >= lo and n <= hi
    end

    local function plainMetadata(value, depth, state, L)
        L = L or Cfg
        local t = type(value)
        if t == 'string' or t == 'boolean' then return true end
        if t == 'number' then return value == value and value ~= math.huge and value ~= -math.huge end
        if t ~= 'table' then return false end
        if depth > L.maxMetadataDepth then return false end
        for k, v in pairs(value) do
            state.nodes = state.nodes + 1
            if state.nodes > L.maxMetadataNodes then return false end
            if type(k) ~= 'string' and type(k) ~= 'number' then return false end
            if not plainMetadata(v, depth + 1, state, L) then return false end
        end
        return true
    end

    local function deepCopy(value)
        if type(value) ~= 'table' then return value end
        local out = {}
        for k, v in pairs(value) do out[k] = deepCopy(v) end
        return out
    end

    local function onlyKeys(tbl, allowed)
        for k in pairs(tbl) do if not allowed[k] then return false end end
        return true
    end

    local function validReference(ref)
        return type(ref) == 'string' and #ref >= 8 and #ref <= 64 and ref:match('^[%w_%-]+$') ~= nil
    end

    local function validCharacterId(cid)
        if type(cid) == 'number' then cid = tostring(cid) end
        return type(cid) == 'string' and #cid >= 1 and #cid <= 20 and cid:match('^%d+$') ~= nil and cid or nil
    end

    local function isEquipSlot(slot) return isEquipmentSlot(slot) end

    -- Effective limits for a call: defaults, overridden per trusted grant caller.
    local function limitsFor(policy)
        local L = { maxOutputLines = Cfg.maxOutputLines, maxMetadataBytes = Cfg.maxMetadataBytes, maxMetadataNodes = Cfg.maxMetadataNodes,
            maxMetadataDepth = Cfg.maxMetadataDepth, maxPayload = 8000 }
        for k, v in pairs(policy and policy.limits or {}) do L[k] = v end
        return L
    end

    local function itemRulesOk(itemName, def, role, policy)
        local lower = itemName:lower()
        if role == 'output' and policy then
            -- paid-goods grant: mirror what AddItem accepts for a plain purchase (non-stackable goods are one row, like AddItem), minus the
            -- items that need serials or are managed elsewhere.
            if def.unique == true then return false end
            if lower:find('weapon_', 1, true) == 1 or lower:find('armor', 1, true) ~= nil then return false end
            if isClothingItemName(lower) or isBagItemName(lower) then return policy.clothing == true end
            return true
        end
        if def.stack == false or def.unique == true then return false end
        if isClothingItemName(lower) or isBagItemName(lower) then return false end
        if lower:find('weapon_', 1, true) == 1 or lower:find('armor', 1, true) ~= nil then return false end
        if role == 'input' and def.durability ~= nil then return false end
        return true
    end

    ------------------------------------------------------------------ normalization
    -- Returns a normalized, canonical transaction or nil, reason. No database access.
    local function normalizeTx(tx, mode, L)
        L = L or limitsFor(nil)
        local allowed = mode == 'sink' and { inputs = true } or mode == 'grant' and { outputs = true } or { inputs = true, outputs = true, tools = true }
        if type(tx) ~= 'table' or not onlyKeys(tx, allowed) then
            return nil, 'invalid_transaction'
        end
        local norm = { inputs = {}, outputs = {}, tools = {} }
        local total, seen = 0, {}

        local function lines(key, max, fields, build)
            local list = tx[key]
            if list == nil then return true end
            if type(list) ~= 'table' or #list > max then return nil, 'invalid_transaction' end
            local count = 0
            for k in pairs(list) do
                if type(k) ~= 'number' then return nil, 'invalid_transaction' end
                count = count + 1
            end
            if count ~= #list then return nil, 'invalid_transaction' end
            for _, line in ipairs(list) do
                if type(line) ~= 'table' or not onlyKeys(line, fields) then return nil, 'invalid_transaction' end
                local entry, why = build(line)
                if not entry then return nil, why end
                norm[key][#norm[key] + 1] = entry
            end
            return true
        end

        local function itemOf(line)
            local name = line.item
            if type(name) ~= 'string' or #name < 1 or #name > 100 or not name:match('^[a-z0-9_]+$') then return nil, 'invalid_item' end
            return name
        end

        local ok, why = lines('inputs', Cfg.maxInputLines, { item = true, amount = true }, function(line)
            local name, e = itemOf(line); if not name then return nil, e end
            if not isInt(line.amount, 1, Cfg.maxAmount) then return nil, 'invalid_transaction' end
            if seen['i:' .. name] then return nil, 'invalid_transaction' end
            seen['i:' .. name] = true
            total = total + line.amount
            return { item = name, amount = line.amount }
        end)
        if not ok then return nil, why end

        ok, why = lines('tools', Cfg.maxToolLines, { item = true, durabilityUse = true }, function(line)
            local name, e = itemOf(line); if not name then return nil, e end
            if line.durabilityUse ~= nil and not isInt(line.durabilityUse, 1, Cfg.maxDurabilityUse) then return nil, 'invalid_transaction' end
            if seen['t:' .. name] or seen['i:' .. name] then return nil, 'invalid_transaction' end
            seen['t:' .. name] = true
            return { item = name, durabilityUse = line.durabilityUse }
        end)
        if not ok then return nil, why end

        ok, why = lines('outputs', L.maxOutputLines, { item = true, amount = true, metadata = true }, function(line)
            local name, e = itemOf(line); if not name then return nil, e end
            if not isInt(line.amount, 1, Cfg.maxAmount) then return nil, 'invalid_transaction' end
            local meta = line.metadata
            if meta == nil then meta = {} end
            if type(meta) ~= 'table' or not plainMetadata(meta, 1, { nodes = 0 }, L) then return nil, 'invalid_metadata' end
            local encoded = stableEncode(meta)
            if #encoded > L.maxMetadataBytes then return nil, 'invalid_metadata' end
            if seen['t:' .. name] then return nil, 'invalid_transaction' end
            total = total + line.amount
            return { item = name, amount = line.amount, metadata = deepCopy(meta) }
        end)
        if not ok then return nil, why end

        if total > Cfg.maxTotalAmount then return nil, 'invalid_transaction' end
        if mode == 'sink' then
            -- consume-only: at least one input, nothing is ever created or worn
            if #norm.inputs == 0 then return nil, 'invalid_transaction' end
            return norm
        end
        if mode == 'grant' then
            -- output-only, but only for a trusted caller that settles payment itself under the same reference
            if #norm.outputs == 0 then return nil, 'invalid_transaction' end
            return norm
        end
        if #norm.inputs == 0 and #norm.outputs == 0 then return nil, 'invalid_transaction' end
        if #norm.inputs == 0 and #norm.tools == 0 and #norm.outputs > 0 then
            -- outputs from nothing would be an item mint; crafting must consume something or at least require a tool.
            return nil, 'invalid_transaction'
        end
        return norm
    end

    -- Item definition checks (cm-items authority). Returns true or false, reason; 'unavailable' when cm-items cannot answer.
    local function checkItems(norm, policy)
        if GetResourceState('cm-items') ~= 'started' then return false, 'unavailable' end
        local function known(name)
            local allowed = isInventoryItem(name)
            if not allowed then return nil end
            return getItemDef(name)
        end
        for _, l in ipairs(norm.inputs) do
            local def = known(l.item)
            if not def or not itemRulesOk(l.item, def, 'input') then return false, 'invalid_item' end
        end
        for _, l in ipairs(norm.tools) do
            if not known(l.item) then return false, 'invalid_item' end
        end
        for _, l in ipairs(norm.outputs) do
            local def = known(l.item)
            if not def or not itemRulesOk(l.item, def, 'output', policy) then return false, 'invalid_item' end
            if def.singleton == true and l.amount ~= 1 then return false, 'invalid_item' end
            local valid = safeItemCall('ValidateMetadata', l.item, l.metadata)
            if valid == nil then return false, 'unavailable' end
            if valid ~= true then return false, 'invalid_metadata' end
        end
        return true
    end

    local function canonicalPayload(cid, norm, txType)
        return stableEncode({ character = tostring(cid), type = txType or TX_TYPE, tx = norm })
    end

    ------------------------------------------------------------------ planning (pure over rows; no database access)
    local function rowDurability(row, def)
        local d = tonumber(row.meta.durability)
        if d == nil then d = tonumber(def and def.durability) end
        return d
    end

    local function bagInfoFromRows(rows)
        local bagRow
        for _, r in ipairs(rows) do if r.slot == 'bag' then bagRow = r break end end
        local level = getBagLevelFromItem(bagRow and { item_name = bagRow.item_name, metadata = bagRow.metadata })
        local cfg = Config.BagLevels and Config.BagLevels[level] or (Config.BagLevels and Config.BagLevels[0]) or {}
        return {
            backpackSlots = tonumber(cfg.backpackSlots or cfg.slots) or 0,
            maxWeight = tonumber(cfg.maxWeight or cfg.weight) or (Config.Weight and Config.Weight.max) or 25000,
        }
    end

    local function slotRank(slot)
        local prefix = tostring(slot):match('^([^%-]+)') or ''
        if prefix == 'pocket' then return 1 elseif prefix == 'backpack' then return 2 elseif prefix == 'quickaccess' then return 3 end
        return 4
    end

    local function byStackOrder(a, b)
        local ra, rb = slotRank(a.slot), slotRank(b.slot)
        if ra ~= rb then return ra < rb end
        if a.slot ~= b.slot then return a.slot < b.slot end
        return a.id < b.id
    end

    -- rawRows are inventory_items rows. Returns plan or nil, reason.
    local function planCraft(rawRows, norm)
        local rows = {}
        for _, r in ipairs(rawRows) do
            rows[#rows + 1] = {
                id = tonumber(r.id), slot = tostring(r.slot), item_name = tostring(r.item_name):lower(),
                qty = tonumber(r.quantity) or 0, orig = tonumber(r.quantity) or 0,
                metadata = r.metadata, raw = r.metadata, meta = decode(r.metadata),
            }
        end
        local bag = bagInfoFromRows(rows)
        local plan = { toolUpdates = {}, updates = {}, deletes = {}, inserts = {}, outputs = {} }

        -- tools (kept; optional durability use)
        for _, tool in ipairs(norm.tools) do
            local def = getItemDef(tool.item)
            local cands = {}
            for _, r in ipairs(rows) do
                if r.item_name == tool.item and r.qty >= 1 and not isEquipSlot(r.slot) then cands[#cands + 1] = r end
            end
            if #cands == 0 then return nil, 'tool_missing' end
            if not tool.durabilityUse then
                local usable
                for _, r in ipairs(cands) do
                    local d = rowDurability(r, def)
                    if d == nil or d > 0 then usable = true break end
                end
                if not usable then return nil, 'tool_durability' end
            else
                local single = {}
                for _, r in ipairs(cands) do if r.qty == 1 then single[#single + 1] = r end end
                if #single == 0 then return nil, 'tool_missing' end
                local best
                for _, r in ipairs(single) do
                    local d = rowDurability(r, def)
                    if d ~= nil and d >= tool.durabilityUse then
                        if not best or d < rowDurability(best, def) or (d == rowDurability(best, def) and r.id < best.id) then best = r end
                    end
                end
                if not best then return nil, 'tool_durability' end
                local newMeta = deepCopy(best.meta)
                newMeta.durability = math.floor(rowDurability(best, def) - tool.durabilityUse)
                plan.toolUpdates[#plan.toolUpdates + 1] = {
                    id = best.id, oldRaw = best.raw, metadata = encode(newMeta), item = tool.item, slot = best.slot,
                    used = tool.durabilityUse, after = newMeta.durability,
                }
            end
        end

        -- inputs (generic same-name, metadata-free stacks only)
        for _, input in ipairs(norm.inputs) do
            local plain = stackMetadataSignature(input.item, {})
            local cands = {}
            for _, r in ipairs(rows) do
                if r.item_name == input.item and r.qty > 0 and not isEquipSlot(r.slot)
                    and stackMetadataSignature(input.item, r.meta) == plain then
                    cands[#cands + 1] = r
                end
            end
            table.sort(cands, function(a, b)
                if a.qty ~= b.qty then return a.qty > b.qty end
                if a.slot ~= b.slot then return a.slot < b.slot end
                return a.id < b.id
            end)
            local have = 0
            for _, r in ipairs(cands) do have = have + r.qty end
            if have < input.amount then return nil, 'insufficient_input' end
            local remaining = input.amount
            for _, r in ipairs(cands) do
                if remaining <= 0 then break end
                local take = math.min(r.qty, remaining)
                r.qty = r.qty - take
                remaining = remaining - take
            end
        end

        -- outputs on the post-input state
        local occupied = {}
        for _, r in ipairs(rows) do if r.qty > 0 then occupied[r.slot] = true end end
        for _, out in ipairs(norm.outputs) do
            local def = getItemDef(out.item)
            if not def then return nil, 'invalid_item' end
            if def.singleton == true then
                for _, r in ipairs(rows) do
                    if r.item_name == out.item and r.qty > 0 then return nil, 'no_capacity' end
                end
            end
            local meta = decorateNewItemMetadata(out.item, deepCopy(out.metadata), def, next(out.metadata) ~= nil)
            local cands = {}
            for _, r in ipairs(rows) do
                if r.item_name == out.item and r.qty > 0 and not isEquipSlot(r.slot)
                    and rowCanStackWithMetadata({ item_name = r.item_name, slot = r.slot, metadata = r.metadata or encode(r.meta) }, out.item, meta) then
                    cands[#cands + 1] = r
                end
            end
            table.sort(cands, byStackOrder)
            local target = cands[1]
            if target then
                if target.qty + out.amount > Cfg.maxRowQuantity then return nil, 'no_capacity' end
                target.qty = target.qty + out.amount
            else
                local slot
                for i = 1, Config.Slots.pockets.count do
                    local s = Config.Slots.pockets.prefix .. i
                    if not occupied[s] then slot = s break end
                end
                if not slot then
                    for i = 1, math.min(Config.Slots.backpack.count, bag.backpackSlots or 0) do
                        local s = Config.Slots.backpack.prefix .. i
                        if not occupied[s] then slot = s break end
                    end
                end
                if not slot then return nil, 'no_capacity' end
                if not canPlaceInSlot(out.item, slot) then return nil, 'no_capacity' end
                occupied[slot] = true
                rows[#rows + 1] = {
                    id = nil, new = true, slot = slot, item_name = out.item, qty = out.amount, orig = 0,
                    meta = meta, metadata = encode(meta),
                }
            end
            plan.outputs[#plan.outputs + 1] = { item = out.item, amount = out.amount }
        end

        -- final weight against the POST-transaction state
        local weight = 0
        for _, r in ipairs(rows) do
            if r.qty > 0 then
                local def = getItemDef(r.item_name)
                weight = weight + ((def and tonumber(def.weight) or 0) * r.qty)
            end
        end
        if weight > bag.maxWeight then return nil, 'no_capacity' end

        for _, r in ipairs(rows) do
            if r.new then
                plan.inserts[#plan.inserts + 1] = { slot = r.slot, item = r.item_name, qty = r.qty, metadata = r.metadata }
            elseif r.qty ~= r.orig then
                if r.qty <= 0 then
                    plan.deletes[#plan.deletes + 1] = { id = r.id, qty = r.orig, item = r.item_name, slot = r.slot }
                else
                    plan.updates[#plan.updates + 1] = { id = r.id, qty = r.qty, old = r.orig, item = r.item_name, slot = r.slot }
                end
            end
        end
        return plan
    end

    ------------------------------------------------------------------ per-character mutation lock (re-entrant per coroutine)
    local CharLocks = {}
    local function lockKey(ownerType, ownerId) return tostring(ownerType) .. ':' .. tostring(ownerId) end

    local function acquire(key, timeoutMs)
        local co = coroutine.running()
        local held = CharLocks[key]
        if held and held.co == co then held.depth = held.depth + 1 return true end
        local waited = 0
        while CharLocks[key] do
            if (os.clock() - CharLocks[key].since) * 1000 > Cfg.lockStaleMs then CharLocks[key] = nil break end -- holder died
            if waited >= (timeoutMs or Cfg.lockTimeoutMs) then return false end
            Wait(10)
            waited = waited + 10
        end
        CharLocks[key] = { co = co, depth = 1, since = os.clock() }
        return true
    end

    local function release(key)
        local held = CharLocks[key]
        if not held then return end
        held.depth = held.depth - 1
        if held.depth <= 0 then CharLocks[key] = nil end
    end

    -- Serialize the legacy item mutators with craft settlement so two operations can never spend the same stack concurrently.
    local function withOwnerLock(fn)
        return function(src, ...)
            local ownerType, ownerId = getOwner(src)
            if not ownerId then return fn(src, ...) end
            local key = lockKey(ownerType, ownerId)
            if not acquire(key) then return false, 'Inventory is busy. Try again.' end
            local res = table.pack(pcall(fn, src, ...))
            release(key)
            if not res[1] then error(res[2], 0) end
            return table.unpack(res, 2, res.n)
        end
    end
    AddItemInternal = withOwnerLock(AddItemInternal)
    RemoveItemInternal = withOwnerLock(RemoveItemInternal)
    MoveItemInternal = withOwnerLock(MoveItemInternal)
    SplitItemInternal = withOwnerLock(SplitItemInternal)
    DropItemInternal = withOwnerLock(DropItemInternal)
    ConsumeSlotItemInternal = withOwnerLock(ConsumeSlotItemInternal)

    ------------------------------------------------------------------ ledger
    local function ensureLedger()
        if ledgerReady then return true end
        local ok = pcall(function()
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS cm_inventory_transactions (
                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                    reference VARCHAR(64) NOT NULL,
                    tx_type VARCHAR(32) NOT NULL,
                    character_id VARCHAR(100) NOT NULL,
                    payload_hash CHAR(16) NOT NULL,
                    payload TEXT NOT NULL,
                    status VARCHAR(16) NOT NULL DEFAULT 'committed',
                    result_json TEXT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    committed_at TIMESTAMP NULL DEFAULT NULL,
                    UNIQUE KEY uq_cm_inventory_tx_reference (reference),
                    INDEX idx_cm_inventory_tx_character (character_id, id)
                )
            ]])
        end)
        ledgerReady = ok
        return ok
    end

    CreateThread(function() ensureLedger() end)

    local function ledgerLookup(reference)
        local ok, row = pcall(function()
            return MySQL.single.await(
                'SELECT reference, character_id, payload_hash, payload, status, result_json, tx_type FROM cm_inventory_transactions WHERE reference = ? LIMIT 1',
                { reference })
        end)
        if not ok then return nil, true end
        return row or false
    end

    local function replayOf(row, cid, payload)
        if tostring(row.character_id) ~= tostring(cid) then return false, 'reference_conflict' end
        local result = decode(row.result_json)
        -- a cancelled grant reference is a permanent DEFINITE "never delivered" (see CancelItemGrant)
        if row.status == 'cancelled' or result.cancelled == true then return false, 'cancelled' end
        if row.payload ~= payload then return false, 'reference_conflict' end
        return true, { replayed = true, outputs = result.outputs or {} }
    end

    ------------------------------------------------------------------ exports
    local function stripSelf(...)
        local args = table.pack(...)
        if type(args[1]) == 'table' and args.n >= 2 then return table.unpack(args, 2, args.n) end
        return table.unpack(args, 1, args.n)
    end

    local function trusted(mode)
        local invoker = GetInvokingResource()
        if mode == 'grant' then return invoker ~= nil and Cfg.grantTrusted[invoker] ~= nil end
        local list = mode == 'sink' and Cfg.sinkTrusted or Cfg.trusted
        return invoker ~= nil and list[invoker] == true
    end

    local function characterExists(cid)
        local ok, found = pcall(function() return MySQL.scalar.await('SELECT id FROM characters WHERE id = ? LIMIT 1', { cid }) end)
        if not ok then return nil end
        return found ~= nil and found ~= false
    end

    local function refreshOnline(cid)
        pcall(function()
            if GetResourceState('cm-playerdata') ~= 'started' then return end
            local src = exports['cm-playerdata']:GetSourceByCharId(tonumber(cid) or cid)
            if src then sendInventorySmart(tonumber(src)) end
        end)
    end

    -- ValidateCraftTransaction(characterId, tx) -> true | false, reason       (read-only, advisory)
    local function validateImpl(mode, ...)
        if not trusted(mode) then return false, 'forbidden' end
        local policy = mode == 'grant' and Cfg.grantTrusted[GetInvokingResource()] or nil
        local characterId, tx = stripSelf(...)
        local cid = validCharacterId(characterId)
        if not cid then return false, 'invalid_transaction' end
        local norm, why = normalizeTx(tx, mode, limitsFor(policy))
        if not norm then return false, why end
        local okItems, whyItems = checkItems(norm, policy)
        if not okItems then return false, whyItems end
        local exists = characterExists(cid)
        if exists == nil then return false, 'unavailable' end
        if not exists then return false, 'invalid_transaction' end
        local okRows, rows = pcall(function()
            return MySQL.query.await('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY id', { Config.OwnerType or 'character', cid })
        end)
        if not okRows or type(rows) ~= 'table' then return false, 'unavailable' end
        local plan, reason = planCraft(rows, norm)
        if not plan then return false, reason end
        return true
    end

    -- GetCraftTransactionStatus(reference) -> 'committed' | 'not_applied' | 'unknown'   (authoritative ledger lookup)
    local function statusImpl(mode, ...)
        if not trusted(mode) then return false, 'forbidden' end
        local reference = stripSelf(...)
        if not validReference(reference) then return false, 'invalid_reference' end
        if not ensureLedger() then return 'unknown' end
        local row, err = ledgerLookup(reference)
        if err then return 'unknown' end
        if row and row.tx_type ~= TYPE_OF[mode] then return false, 'reference_conflict' end   -- the reference belongs to a different transaction kind
        if row and row.status == 'committed' then return 'committed' end
        if row and row.status == 'cancelled' then return 'cancelled' end
        return 'not_applied'
    end

    -- ExecuteCraftTransaction(reference, characterId, tx)
    --   -> true, { replayed = bool, outputs = {...} }        committed (now, or earlier under this reference)
    --   |  false, reason                                      DEFINITE failure: nothing applied
    --   |  false, 'unavailable'                               outcome unknown: reconcile via GetCraftTransactionStatus
    local function executeImpl(mode, ...)
        if not trusted(mode) then return false, 'forbidden' end
        local policy = mode == 'grant' and Cfg.grantTrusted[GetInvokingResource()] or nil  -- read before any yield
        local L = limitsFor(policy)
        local reference, characterId, tx = stripSelf(...)
        if not validReference(reference) then return false, 'invalid_transaction' end
        local cid = validCharacterId(characterId)
        if not cid then return false, 'invalid_transaction' end
        local norm, why = normalizeTx(tx, mode, L)
        if not norm then return false, why end
        local payload = canonicalPayload(cid, norm, TYPE_OF[mode])
        if #payload > L.maxPayload then return false, 'invalid_transaction' end
        local okItems, whyItems = checkItems(norm, policy)
        if not okItems then
            -- A previously committed reference stays committed even if item definitions changed later.
            local prior = ledgerLookup(reference)
            if prior then return replayOf(prior, cid, payload) end
            return false, whyItems
        end
        if not ensureLedger() then return false, 'unavailable' end

        local ownerType = Config.OwnerType or 'character'
        local key = lockKey(ownerType, cid)
        if not acquire(key) then return false, 'unavailable' end

        local result
        local okRun, errRun = pcall(function()
            local prior, lookupErr = ledgerLookup(reference)
            if lookupErr then result = { false, 'unavailable' } return end
            if prior then result = { replayOf(prior, cid, payload) } return end

            local outcome = {}
            local committed = MySQL.startTransaction(function(query)
                local okBody, bodyErr = pcall(function()
                    local function q(sql, params)
                        local r = query(sql, params)
                        if r == nil then error('query_failed') end
                        return r
                    end
                    failpoint('begin')

                    -- Lock order matters: the character's inventory rows are the serialization point. Locking a not-yet-existing
                    -- ledger row first would take a gap lock on the UNIQUE index and deadlock two different references (verified
                    -- against MySQL in tests/craft_mysql_smoke.py). The ledger is read AFTER the row locks (so it sees any commit
                    -- we waited for); the UNIQUE reference insert is the final arbiter.
                    local rows = q('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY id FOR UPDATE', { ownerType, cid })

                    local led = q('SELECT reference, character_id, payload, result_json FROM cm_inventory_transactions WHERE reference = ?', { reference })
                    if led[1] then
                        outcome.replay = led[1]
                        return
                    end

                    local chars = q('SELECT id FROM characters WHERE id = ? LIMIT 1', { cid })
                    if not chars[1] then outcome.fail = 'invalid_transaction' return end

                    local plan, reason = planCraft(rows, norm)
                    if not plan then outcome.fail = reason return end
                    failpoint('after_validation')

                    local function affected(sql, params)
                        -- inside MySQL.startTransaction oxmysql returns the raw ResultSetHeader ({ affectedRows = n }), not a number
                        local r = q(sql, params)
                        local n = type(r) == 'table' and r.affectedRows or r
                        if tonumber(n) ~= 1 then error('guard_failed') end
                    end
                    local function auditRow(action, item, qty, fromSlot, toSlot)
                        q([[INSERT INTO inventory_audit (character_id, action, item_name, quantity, from_slot, to_slot, reason)
                            VALUES (?, ?, ?, ?, ?, ?, ?)]], { cid, action, item, qty, fromSlot, toSlot, reference })
                    end

                    for _, t in ipairs(plan.toolUpdates) do
                        affected('UPDATE inventory_items SET metadata = ? WHERE id = ? AND metadata <=> ?', { t.metadata, t.id, t.oldRaw })
                        auditRow('craft_tool', t.item, t.used, t.slot, nil)
                    end
                    for _, u in ipairs(plan.updates) do
                        affected('UPDATE inventory_items SET quantity = ? WHERE id = ? AND quantity = ?', { u.qty, u.id, u.old })
                        auditRow('craft_update', u.item, u.qty - u.old, u.slot, nil)
                    end
                    for _, d in ipairs(plan.deletes) do
                        affected('DELETE FROM inventory_items WHERE id = ? AND quantity = ?', { d.id, d.qty })
                        auditRow('craft_consume', d.item, -d.qty, d.slot, nil)
                    end
                    failpoint('after_inputs')
                    failpoint('before_outputs')
                    for _, i in ipairs(plan.inserts) do
                        q('INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata) VALUES (?, ?, ?, ?, ?, ?)',
                            { ownerType, cid, i.slot, i.item, i.qty, i.metadata })
                        auditRow('craft_add', i.item, i.qty, nil, i.slot)
                    end
                    failpoint('before_ledger')
                    q([[INSERT INTO cm_inventory_transactions
                        (reference, tx_type, character_id, payload_hash, payload, status, result_json, committed_at)
                        VALUES (?, ?, ?, ?, ?, 'committed', ?, NOW())]],
                        { reference, TYPE_OF[mode], cid, fnv1a(payload), payload, encode({ outputs = plan.outputs }) })
                    failpoint('after_ledger')
                    outcome.ok = true
                    outcome.outputs = plan.outputs
                end)
                if not okBody then
                    outcome.error = tostring(bodyErr)
                    outcome.ok = nil
                    return false
                end
                if not outcome.ok then return false end -- definite refusal / replay: nothing to commit
                return true
            end)

            if outcome.ok and committed == true then
                result = { true, { replayed = false, outputs = outcome.outputs } }
            elseif outcome.replay then
                result = { replayOf(outcome.replay, cid, payload) }
            elseif outcome.fail then
                result = { false, outcome.fail }
            else
                -- Unknown: the transaction errored or the connection failed. The ledger is authoritative.
                local row, lookupErr = ledgerLookup(reference)
                if lookupErr then result = { false, 'unavailable' }
                elseif row then result = { replayOf(row, cid, payload) }
                else result = { false, 'unavailable' } end
            end
        end)
        release(key)
        if not okRun then
            print(('^1[CM-INVENTORY]^7 craft settlement error reference=%s error=%s'):format(tostring(reference), tostring(errRun)))
            -- The failure may have happened after commit; the ledger decides.
            local row = ledgerLookup(reference)
            if row then return replayOf(row, cid, payload) end
            return false, 'unavailable'
        end
        if result[1] == true and result[2] and result[2].replayed == false then refreshOnline(cid) end
        return result[1], result[2]
    end

    exports('ValidateCraftTransaction', function(...) return validateImpl('craft', ...) end)
    exports('GetCraftTransactionStatus', function(...) return statusImpl('craft', ...) end)
    exports('ExecuteCraftTransaction', function(...) return executeImpl('craft', ...) end)

    -- Consume-only item sink (v2): the SAME atomic engine (row locks, guarded writes, UNIQUE-reference ledger, replay) with no outputs and no tools.
    -- Trusted caller: Cfg.sinkTrusted (cm-commercial-ownership). `items` = { { item, amount } ... }. The destination owner credits its own balance and
    -- must treat a committed sink as irreversible (no refund path): retry its credit until it settles.
    --   ValidateItemSinkTransaction(characterId, items)             -> true | false, reason   (read-only)
    --   ExecuteItemSinkTransaction(reference, characterId, items)   -> true, { replayed } | false, reason (nothing applied) | false, 'unavailable'
    --   GetItemSinkTransactionStatus(reference)                     -> 'committed' | 'not_applied' | 'unknown'
    exports('ValidateItemSinkTransaction', function(...)
        local a, b = stripSelf(...)
        return validateImpl('sink', a, { inputs = b })
    end)
    exports('GetItemSinkTransactionStatus', function(...) return statusImpl('sink', ...) end)
    exports('ExecuteItemSinkTransaction', function(...)
        local reference, characterId, items = stripSelf(...)
        return executeImpl('sink', reference, characterId, { inputs = items })
    end)

    -- Paid-goods grant (v3): the SAME atomic engine with outputs only, for a trusted caller that has already taken payment and must deliver
    -- the goods exactly once (cm-gasstations). Items must satisfy the craft output policy (stackable, non-clothing, non-weapon).
    --   ExecuteItemGrant(reference, characterId, items)  items = { { item, amount [, metadata] } ... }, all-or-nothing
    --        -> true, { replayed = bool }   delivered (now, or earlier under this reference)
    --        |  false, 'cancelled'           the reference was fenced by CancelItemGrant: DEFINITELY never delivered
    --        |  false, reason                DEFINITE failure: nothing applied (no_capacity, invalid_item, ...)
    --        |  false, 'unavailable'         outcome unknown: reconcile via GetItemGrantStatus (never assume "not delivered")
    --   GetItemGrantStatus(reference)  -> 'committed' | 'not_applied' | 'cancelled' | 'unknown'
    --   CancelItemGrant(reference, characterId)
    --        -> true, 'cancelled'          reference permanently fenced: a later ExecuteItemGrant can never deliver
    --        |  false, 'already_committed' the goods WERE delivered (the caller must treat the purchase as delivered)
    --        |  false, 'unavailable'       unknown; retry
    exports('ExecuteItemGrant', function(...)
        local reference, characterId, items = stripSelf(...)
        return executeImpl('grant', reference, characterId, { outputs = items })
    end)
    exports('GetItemGrantStatus', function(...) return statusImpl('grant', ...) end)
    exports('CancelItemGrant', function(...)
        if not trusted('grant') then return false, 'forbidden' end
        local reference, characterId = stripSelf(...)
        if not validReference(reference) then return false, 'invalid_reference' end
        local cid = validCharacterId(characterId)
        if not cid then return false, 'invalid_transaction' end
        if not ensureLedger() then return false, 'unavailable' end
        local key = lockKey(Config.OwnerType or 'character', cid) -- same serialization point as ExecuteItemGrant
        if not acquire(key) then return false, 'unavailable' end
        local okRun, verdict, detail = pcall(function()
            local row, err = ledgerLookup(reference)
            if err then return false, 'unavailable' end
            if not row then
                -- UNIQUE(reference) is the arbiter; a concurrent insert simply makes the lookup below see the winner.
                pcall(function()
                    MySQL.query.await([[INSERT INTO cm_inventory_transactions
                        (reference, tx_type, character_id, payload_hash, payload, status, result_json, committed_at)
                        VALUES (?, ?, ?, ?, ?, 'cancelled', ?, NOW())]],
                        { reference, GRANT_TYPE, cid, fnv1a('cancelled'), 'cancelled', encode({ cancelled = true }) })
                end)
                row, err = ledgerLookup(reference)
                if err or not row then return false, 'unavailable' end
            end
            if row.tx_type ~= GRANT_TYPE or tostring(row.character_id) ~= tostring(cid) then return false, 'reference_conflict' end
            if row.status == 'cancelled' then return true, 'cancelled' end
            if row.status == 'committed' then return false, 'already_committed' end
            return false, 'unavailable'
        end)
        release(key)
        if not okRun then return false, 'unavailable' end
        return verdict, detail
    end)

    -- Shared engine internals for server/exchange.lua (resource-local global; NOT an export, not reachable from other resources).
    CMInventory.Tx = {
        Cfg = Cfg, acquire = acquire, release = release, lockKey = lockKey, ensureLedger = ensureLedger, ledgerLookup = ledgerLookup, fnv1a = fnv1a,
        stripSelf = stripSelf, refreshOnline = refreshOnline, characterExists = characterExists, failpoint = function(name) failpoint(name) end,
        validReference = validReference, validCharacterId = validCharacterId, deepCopy = deepCopy, isInt = isInt, slotRank = slotRank,
        byStackOrder = byStackOrder, bagInfoFromRows = bagInfoFromRows, isEquipSlot = isEquipSlot, trusted = function(list) local i = GetInvokingResource(); return i ~= nil and list[i] == true end,
    }

end
