-- cm-inventory/server/tier2.lua
-- Tier 2 features, concatenated into the same server chunk as the other split
-- files (see server/main.lua bootloader), so it shares scope with all the local
-- internals (getOwner, getItemAt, AddItemInternal, ConsumeSlotItemInternal,
-- MoveItemInternal, canCarry, sendInventorySmart, audit, notify, decode, etc.).
--
-- Features:
--   #4  Give: show nearby player name(s); if several, a list -> confirmation,
--       then give the FULL stack to the chosen target (re-validated server-side).
--   #6  Unequip gun: its ammo follows into the inventory if there is space.
--   #7  Death: equipped gun + ammo drop to the ground for others to pick up.
--
-- Every player-facing action is validated server-side. Client only ever picks a
-- target/slot; the server re-checks ownership, distance, carry limits, and rolls
-- back on failure. Nothing here trusts a client-supplied amount or target blindly.

-- ============================================================================
-- Shared helpers
-- ============================================================================

local function tier2Owner(src)
    return getOwner(src)
end

-- Resolve a friendly display name for a player via cm-playerdata, with fallbacks.
local function playerDisplayName(playerSrc)
    playerSrc = tonumber(playerSrc)
    if not playerSrc then return 'Unknown' end
    if GetResourceState('cm-playerdata') == 'started' then
        local ok, name = pcall(function()
            return exports['cm-playerdata']:GetCharacterFullName(playerSrc)
        end)
        if ok and name and name ~= '' then return tostring(name) end
    end
    local gpn = GetPlayerName(playerSrc)
    return (gpn and gpn ~= '') and gpn or ('Player ' .. tostring(playerSrc))
end

-- All players within range (list, not just the closest). Returns an array of
-- { serverId, name, distance } sorted nearest-first.
local function nearbyPlayers(src, maxDistance)
    maxDistance = tonumber(maxDistance) or 3.0
    local srcPed = GetPlayerPed(src)
    if not srcPed or srcPed == 0 then return {} end
    local srcCoords = GetEntityCoords(srcPed)

    local list = {}
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and target ~= tonumber(src) then
            local targetPed = GetPlayerPed(target)
            if targetPed and targetPed ~= 0 then
                local tc = GetEntityCoords(targetPed)
                local dist = #(srcCoords - tc)
                if dist <= maxDistance then
                    -- Only list players who actually have a loaded character.
                    local _, targetOwnerId = tier2Owner(target)
                    if targetOwnerId then
                        list[#list + 1] = {
                            serverId = target,
                            name = playerDisplayName(target),
                            distance = math.floor(dist * 10) / 10,
                        }
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end

-- ============================================================================
-- #4  GIVE with name / list / confirmation
-- ============================================================================

-- Pending give offers, keyed by giver src, so confirm can't be spoofed to give
-- a different slot/amount than what was offered. Short TTL.
local pendingGive = {}
local GIVE_OFFER_TTL_MS = 20000

local function giveRange()
    return (Config.Give and Config.Give.distance) or 3.0
end

-- Step 1: player asks to give a slot. Server figures out who's nearby and either
-- returns the single name (client shows a confirm) or the list (client shows a
-- picker). No item moves yet.
RegisterNetEvent('cm-inventory:server:requestGive', function(data)
    local src = source
    if isPlayerDeadState(src) then return end
    data = type(data) == 'table' and data or {}
    local slot = tostring(data.slot or '')

    if Config.Give and Config.Give.enabled == false then
        notify(src, 'Giving items is disabled.', 'error')
        return
    end

    local ownerType, ownerId = tier2Owner(src)
    if not ownerId then notify(src, 'No character owner found.', 'error') return end
    if not isValidSlot(slot) then notify(src, 'Invalid slot.', 'error') return end

    local row = getItemAt(ownerType, ownerId, slot)
    if not row then notify(src, 'Slot is empty.', 'error') return end

    local players = nearbyPlayers(src, giveRange())
    if #players == 0 then
        notify(src, 'No nearby player found.', 'error')
        return
    end

    -- Give the FULL stack (Tier 1 decision: no amount prompt).
    local amount = tonumber(row.quantity) or 1

    -- Record the offer so confirm is bound to this exact slot/amount.
    pendingGive[src] = {
        slot = slot,
        amount = amount,
        itemName = row.item_name,
        expiresAt = GetGameTimer() + GIVE_OFFER_TTL_MS,
        candidates = {},
    }
    for _, p in ipairs(players) do pendingGive[src].candidates[p.serverId] = true end

    -- Tell the client what to show: single -> confirm, multiple -> list.
    TriggerClientEvent('cm-inventory:client:giveTargets', src, {
        slot = slot,
        itemLabel = row.item_name,
        amount = amount,
        players = players,   -- array of { serverId, name, distance }
    })
end)

-- Step 2: player confirmed a specific target. Re-validate EVERYTHING server-side
-- (offer exists, target was in the offered set, still in range, can carry), then
-- perform the give with rollback.
RegisterNetEvent('cm-inventory:server:confirmGive', function(data)
    local src = source
    if isPlayerDeadState(src) then
        pendingGive[src] = nil
        return
    end
    data = type(data) == 'table' and data or {}
    local targetSrc = tonumber(data.targetServerId)

    local offer = pendingGive[src]
    pendingGive[src] = nil  -- single-use, whatever happens

    if not offer then notify(src, 'Give offer expired. Try again.', 'error') return end
    if GetGameTimer() > offer.expiresAt then notify(src, 'Give offer expired. Try again.', 'error') return end
    if not targetSrc or not offer.candidates[targetSrc] then
        notify(src, 'That player is no longer available.', 'error')
        return
    end

    -- Re-check the target is still nearby right now (they can't have walked off).
    local stillNear = false
    for _, p in ipairs(nearbyPlayers(src, giveRange())) do
        if p.serverId == targetSrc then stillNear = true break end
    end
    if not stillNear then
        notify(src, 'That player moved away.', 'error')
        sendInventorySmart(src)
        return
    end

    -- Re-fetch the source row; it must still match the offered item (no swap).
    local ownerType, ownerId = tier2Owner(src)
    if not ownerId then notify(src, 'No character owner found.', 'error') return end
    local row = getItemAt(ownerType, ownerId, offer.slot)
    if not row or tostring(row.item_name) ~= tostring(offer.itemName) then
        notify(src, 'The item is no longer in that slot.', 'error')
        sendInventorySmart(src)
        return
    end

    local amount = math.min(tonumber(offer.amount) or 1, tonumber(row.quantity) or 1)
    if amount < 1 then notify(src, 'Nothing to give.', 'error') return end

    local targetOwnerType, targetOwnerId = tier2Owner(targetSrc)
    if not targetOwnerId then notify(src, 'That player has no active character.', 'error') return end

    local carryOk, carryReason = canCarry(targetOwnerType, targetOwnerId, row.item_name, amount)
    if not carryOk then
        notify(src, 'They cannot carry that: ' .. tostring(carryReason), 'error')
        return
    end

    local metadata = decode(row.metadata)
    local consumed, consumeErr = ConsumeSlotItemInternal(src, offer.slot, amount, 'give_item')
    if not consumed then notify(src, consumeErr or 'Could not remove item.', 'error') return end

    local added, addReason = AddItemInternal(targetSrc, row.item_name, amount, metadata, 'received_from_player')
    if not added then
        AddItemInternal(src, row.item_name, amount, metadata, 'give_rollback')  -- rollback
        notify(src, addReason or 'Could not give item.', 'error')
        sendInventorySmart(src)
        return
    end

    audit(ownerId, 'give_item', row.item_name, amount, offer.slot, nil, ('to_player_%s'):format(targetSrc), metadata)
    audit(targetOwnerId, 'receive_item', row.item_name, amount, nil, nil, ('from_player_%s'):format(src), metadata)

    local targetName = playerDisplayName(targetSrc)
    local giverName = playerDisplayName(src)
    notify(src, ('Gave %sx %s to %s.'):format(amount, row.item_name, targetName), 'success')
    notify(targetSrc, ('%s gave you %sx %s.'):format(giverName, amount, row.item_name), 'success')
    sendInventorySmart(src)
    sendInventorySmart(targetSrc)
end)

AddEventHandler('playerDropped', function()
    pendingGive[source] = nil
end)

-- ============================================================================
-- #6  Unequip gun -> ammo follows into inventory if there is space
-- ============================================================================
-- When the weapon slot is emptied into the inventory, move the matching ammo out
-- of the ammo slot too (only if the inventory has room). This wraps the existing
-- MoveItemInternal without altering it.

local function ammoSlotName()
    return (Config.Ammo and Config.Ammo.slot) or 'ammo'
end

-- Public export other code / events can call after moving a weapon out of the
-- weapon slot. Safe: does nothing if there's no ammo or no free inventory space.
-- Global (not local) so the moveItem handler in drops.lua — which is earlier in
-- the concatenated chunk — can reach it at runtime.
function followAmmoToInventory(src, weaponRowBeforeMove)
    local ownerType, ownerId = tier2Owner(src)
    if not ownerId then return false end

    local aSlot = ammoSlotName()
    local ammoRow = getItemAt(ownerType, ownerId, aSlot)
    if not ammoRow then return false end  -- no ammo equipped, nothing to follow

    local qty = tonumber(ammoRow.quantity) or 0
    if qty < 1 then return false end

    -- Only move if there is inventory room for this ammo (respect carry limits).
    local carryOk = canCarry(ownerType, ownerId, ammoRow.item_name, qty)
    if not carryOk then
        notify(src, 'Ammo stayed in the ammo slot (no inventory space).', 'info')
        return false
    end

    -- Find a free normal slot and move the ammo there via the existing mover.
    local destSlot = nil
    for _, slot in ipairs(allSlots()) do
        if slot ~= 'weapon' and slot ~= aSlot and not isEquipmentSlot(slot) then
            if not getItemAt(ownerType, ownerId, slot) and isSlotUnlocked(ownerType, ownerId, slot) then
                destSlot = slot
                break
            end
        end
    end
    if not destSlot then
        notify(src, 'Ammo stayed in the ammo slot (no free pocket).', 'info')
        return false
    end

    local moved = MoveItemInternal(src, aSlot, destSlot)
    if moved then
        audit(ownerId, 'ammo_follow_unequip', ammoRow.item_name, qty, aSlot, destSlot, 'gun_unequipped')
        sendInventorySmart(src)
        return true
    end
    return false
end

-- Expose as an export so the equipment move path can call it directly.
exports('FollowAmmoToInventory', function(src)
    return followAmmoToInventory(src, nil)
end)

-- ============================================================================
-- #7  Death -> drop equipped gun + ammo to the ground (pickup-able)
-- ============================================================================
-- Inventory had no death handling. We listen for cm-playerdata's death signal,
-- then move the equipped weapon and ammo from their slots into a world drop that
-- any nearby player can pick up (using the existing drop system).

-- Drop a full slot to the ground using the existing world-drop system.
-- DropItemInternal already: removes from the slot, calls createWorldDrop (a
-- pickup any nearby player can loot), audits, and broadcasts the drop.
local function dropSlotToGround(src, ownerType, ownerId, slot)
    local row = getItemAt(ownerType, ownerId, slot)
    if not row then return false end
    local qty = tonumber(row.quantity) or 0
    if qty < 1 then return false end
    local ok = DropItemInternal(src, slot, qty)
    return ok == true
end

local activeDeathDrops = {}

local function dropEquippedWeaponsOnDeath(src)
    src = tonumber(src)
    if not src or src <= 0 or activeDeathDrops[src] then return end

    -- Only an authoritative replicated unconscious state may drop equipment.
    if not isPlayerDeadState(src) then return end

    -- Default ON; set Config.Death.dropWeapons = false to disable.
    if Config.Death and Config.Death.dropWeapons == false then return end

    local ownerType, ownerId = tier2Owner(src)
    if not ownerId then return end
    activeDeathDrops[src] = true

    local aSlot = ammoSlotName()
    local droppedAny = false

    -- Weapon first, then its ammo, each becoming its own normal world pickup.
    if dropSlotToGround(src, ownerType, ownerId, 'weapon') then droppedAny = true end
    if dropSlotToGround(src, ownerType, ownerId, aSlot) then droppedAny = true end

    if droppedAny then
        -- Remove the weapon from the ped immediately and refresh authoritative
        -- equipment/inventory state even though the death screen keeps UI closed.
        syncAllEquipment(src)
        sendInventorySmart(src)
    end
end

RegisterNetEvent('cm-inventory:server:playerDied', function()
    -- Resource-restart fallback only. Client cannot force a drop unless
    -- cm-playerdata already replicated isDead=true for this player.
    dropEquippedWeaponsOnDeath(source)
end)

AddEventHandler('playerDropped', function()
    activeDeathDrops[source] = nil
end)

-- Preferred explicit hook: if cm-playerdata (or a medical resource) calls this
-- export at the exact moment of death, that is the most reliable trigger.
exports('DropEquippedWeaponsOnDeath', function(playerSrc)
    local s = tonumber(playerSrc)
    if s then dropEquippedWeaponsOnDeath(s) end
end)

exports('ResetDeathDropState', function(playerSrc)
    local s = tonumber(playerSrc)
    if s then activeDeathDrops[s] = nil end
end)
