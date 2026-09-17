-- =============================================================================
-- prism_fishing: SERVER-SIDE SCRIPT (Deobfuscated)
-- =============================================================================
-- Original obfuscated variable map (top-level locals):
--   L0_1  -> config           (shared config table, loaded via require)
--   L1_1  -> storeItemPrices  (map of item name -> price for the shop/basket store)
--   L2_1  -> fishSellPrices   (map of fish name -> sell price for the fish exchange)
--   L3_1  -> activeRodState   (map of source -> fishing state / reward data)
--   L4_1  -> playerDataCache  (map of source -> player fishing DB row cache)
--   L5_1  -> fishingCooldowns (map of source -> os.time() cooldown expiry)
--   L6_1  -> SendNotification (function: triggers client notification event)
--   L7_1  -> GetWeightedFish  (function: picks a fish based on level + weighted chance)
--   L8_1  -> AddXPToPlayer    (function: awards XP, handles level-up logic)
--   L9_1  -> ValidateBasket   (function: validates a basket purchase item list)
--  L10_1  -> GetPlayerLevel   (function: returns a player's current fishing level)
--  L11_1  -> WaitForIdentifier(function: waits until a valid identifier is obtained)
--  L12_1  -> (reused scratch)
--  L13_1  -> (reused scratch)
--  L14_1  -> (reused scratch/callback handler)
-- =============================================================================

-- Load the shared config file
local config = require("shared/config")

-- Lookup tables populated at runtime from config
local storeItemPrices  = {}   -- item name  -> price  (from config.Store)
local fishSellPrices   = {}   -- fish name  -> price  (from config.FishExchange)

-- Per-player state tables
local activeRodState   = {}   -- source -> { reward = fishName } | true | nil
local playerDataCache  = {}   -- source -> fishing DB row { identifier, level, xp }
local fishingCooldowns = {}   -- source -> os.time() value when cooldown expires


-- =============================================================================
-- THREAD: Create the `fishing` database table on resource start
-- =============================================================================
CreateThread(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `fishing` (
            `identifier` VARCHAR(50) NOT NULL,
            `level` INT(11) NOT NULL DEFAULT 1,
            `xp` INT(11) NOT NULL DEFAULT 0,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    ]])
    debugPrint("^2[FISHING SYSTEM]^7 Table `fishing` checked/created successfully.")
end)


-- =============================================================================
-- FUNCTION: SendNotification(source, message, notifType)
-- Triggers a client-side notification event for a specific player.
-- Parameters:
--   source     - player server id
--   message    - notification text
--   notifType  - notification style ("error", "success", etc.)
-- =============================================================================
local function SendNotification(source, message, notifType)
    TriggerClientEvent("prism_fishing:client:Notification", source, message, notifType)
end


-- =============================================================================
-- FUNCTION: GetWeightedFish(fishList, playerLevel)
-- Picks a fish name from fishList using weighted random selection.
-- Only considers fish whose requiredLevel <= playerLevel.
-- Falls back to fishList[1] if no eligible fish found.
-- Parameters:
--   fishList    - array of fish keys (strings referencing config.Fish)
--   playerLevel - the player's current fishing level (integer)
-- Returns:
--   fishName (string)
-- =============================================================================
local function GetWeightedFish(fishList, playerLevel)
    local eligibleFish = {}
    local totalWeight  = 0

    -- Build a list of fish the player is high enough level to catch
    for _, fishName in ipairs(fishList) do
        local fishData = config.Fish[fishName]
        if playerLevel >= fishData.requiredLevel then
            table.insert(eligibleFish, fishName)
            totalWeight = totalWeight + fishData.chance
        end
    end

    -- Fallback: if no eligible fish, return the first in the list
    if #eligibleFish == 0 then
        return fishList[1]
    end

    -- Weighted random pick
    local roll        = math.random(totalWeight)
    local accumulated = 0

    for _, fishName in ipairs(eligibleFish) do
        accumulated = accumulated + config.Fish[fishName].chance
        if roll <= accumulated then
            return fishName
        end
    end

    -- Safety fallback: return last eligible fish
    return eligibleFish[#eligibleFish]
end


-- =============================================================================
-- FUNCTION: AddXPToPlayer(source, xpAmount)
-- Awards xpAmount XP to a player, handles levelling up, and persists to DB.
-- Also syncs new xp/level back to the client via lib.callback.await.
-- Parameters:
--   source   - player server id
--   xpAmount - amount of XP to award
-- =============================================================================
local function AddXPToPlayer(source, xpAmount)
    -- Validate player exists
    local player = GetPlayer(source)
    if not player then return end

    -- Fetch current XP and level from DB
    local row = MySQL.single.await(
        "SELECT xp, level FROM fishing WHERE identifier = ? LIMIT 1",
        { GetIdentifier(source) }
    )
    if not row then return end

    local currentXP    = row.xp
    local currentLevel = row.level
    local newXP        = currentXP + xpAmount
    local newLevel     = currentLevel

    -- Level-up loop: keep levelling up while XP threshold is met
    while true do
        local xpNeeded = config.LevelXP[newLevel + 1]
        if xpNeeded and newXP >= xpNeeded then
            newXP   = newXP - xpNeeded
            newLevel = newLevel + 1
        else
            break
        end
    end

    -- Persist new level and XP to database
    MySQL.update.await(
        "UPDATE fishing SET level = ?, xp = ? WHERE identifier = ?",
        { newLevel, newXP, GetIdentifier(source) }
    )

    -- Sync updated XP to client
    lib.callback.await("prism_fishing:client:UpdatePlayerFishData", source, "xp", newXP)

    -- If the player levelled up, update cache and sync level to client
    if newLevel ~= currentLevel then
        playerDataCache[source].level = newLevel
        lib.callback.await("prism_fishing:client:UpdatePlayerFishData", source, "level", newLevel)
    end
end


-- =============================================================================
-- FUNCTION: ValidateBasket(items)
-- Validates a list of items for a basket purchase.
-- Checks that each item exists in storeItemPrices and has a valid quantity.
-- Parameters:
--   items - array of { name = string, qty = number/string }
-- Returns (on success):
--   true, validatedItems, totalPrice
-- Returns (on failure):
--   false, errorCode
-- =============================================================================
local function ValidateBasket(items)
    local totalPrice      = 0
    local validatedItems  = {}

    for _, item in ipairs(items) do
        -- Check item exists in the store price list
        local unitPrice = storeItemPrices[item.name]
        if not unitPrice then
            return false, "invalid_item"
        end

        -- Validate quantity is a positive integer
        local qty = tonumber(item.qty)
        if not qty or qty < 1 then
            return false, "invalid_qty"
        end

        totalPrice = totalPrice + (unitPrice * qty)

        table.insert(validatedItems, {
            name  = item.name,
            qty   = qty,
            price = unitPrice,
        })
    end

    return true, validatedItems, totalPrice
end


-- =============================================================================
-- FUNCTION: GetPlayerLevel(source)
-- Returns the cached fishing level for a player, defaulting to 1.
-- Parameters:
--   source - player server id
-- Returns:
--   level (integer, minimum 1)
-- =============================================================================
local function GetPlayerLevel(source)
    local cachedData = playerDataCache[source]
    if cachedData then
        local level = cachedData.level
        if level then
            return level
        end
    end
    return 1
end


-- =============================================================================
-- FUNCTION: WaitForIdentifier(source)
-- Polls GetIdentifier() in a loop until a non-empty identifier is returned.
-- Used to safely retrieve the identifier even if it isn't immediately available.
-- Parameters:
--   source - player server id
-- Returns:
--   identifier (string)
-- =============================================================================
local function WaitForIdentifier(source)
    local identifier = GetIdentifier(source)
    while not identifier or identifier == "" do
        Wait(100)
        identifier = GetIdentifier(source)
    end
    return identifier
end


-- =============================================================================
-- CALLBACK: prism_fishing:server:GetDataPlayer
-- Fetches (or creates) a player's fishing data row from the DB.
-- Caches the result in playerDataCache[source].
-- Returns the full DB row to the client.
-- =============================================================================
lib.callback.register("prism_fishing:server:GetDataPlayer", function(source)
    local identifier = WaitForIdentifier(source)

    -- Try to load existing row
    local row = MySQL.single.await(
        "SELECT * FROM fishing WHERE identifier = ? LIMIT 1",
        { identifier }
    )

    -- If no row exists, insert a default one and re-fetch it
    if not row then
        MySQL.insert.await(
            "INSERT INTO fishing (identifier, level, xp) VALUES (?, ?, ?)",
            { identifier, 0, 0 }
        )
        row = MySQL.single.await(
            "SELECT * FROM fishing WHERE identifier = ? LIMIT 1",
            { identifier }
        )
    end

    -- Cache and return the row
    playerDataCache[source] = row
    return row
end)


-- =============================================================================
-- CALLBACK: prism_fishing:server:BuyBasket
-- Handles a player purchasing a basket of items from the fishing store.
-- Validates items, checks funds, removes money, and grants items.
-- Parameters (from client):
--   data.items         - array of { name, qty }
--   data.paymentMethod - "cash" / "bank" / etc.
-- Returns:
--   true on success, false on failure
-- =============================================================================
lib.callback.register("prism_fishing:server:BuyBasket", function(source, data)
    -- Basic input validation
    if not data or not data.items then
        return false
    end

    -- Validate the basket contents (prices, quantities)
    local isValid, validatedItems, totalPrice = ValidateBasket(data.items)

    if not isValid then
        -- Cheat attempt: invalid item data submitted
        DropPlayer(source, "Cheat attempt from " .. source .. " (invalid basket)")
        return false
    end

    -- Check player has enough money
    local playerMoney = GetPlayerMoney(source, data.paymentMethod)

    if totalPrice <= playerMoney then
        -- Deduct payment
        RemoveMoney(source, data.paymentMethod, totalPrice)

        -- Grant each item to the player
        for _, item in ipairs(validatedItems) do
            AddItem(source, item.name, item.qty)
        end

        return true
    else
        -- Not enough money: notify player
        SendNotification(source, locale("not_enough_money"), "error")
        return false
    end
end)


-- =============================================================================
-- CALLBACK: prism_fishing:server:SellItem
-- Handles a player selling a fish item at the exchange.
-- Supports selling one ("one") or all ("all") of a given fish.
-- Parameters (from client):
--   data.method   - "one" or "all"
--   data.itemName - the fish item name to sell
-- Returns:
--   true on success, false on failure
-- =============================================================================
lib.callback.register("prism_fishing:server:SellItem", function(source, data)
    local method = data.method

    if method == "one" then
        -- Sell exactly 1 fish
        local fishName  = data.itemName
        local sellPrice = fishSellPrices[fishName]

        if not sellPrice then return end

        -- Attempt to remove 1 of the item
        local removed = RemoveItem(source, data.itemName, 1)

        if removed then
            AddMoney(source, "cash", sellPrice)
            return true
        else
            SendNotification(source, locale("not_enough_fish"), "error")
            return false
        end
    else
        -- Sell ALL of this fish the player owns
        local count     = GetCountItems(source, data.itemName)
        local fishName  = data.itemName
        local sellPrice = fishSellPrices[fishName]

        if not sellPrice then return end

        if count > 0 then
            local removed = RemoveItem(source, data.itemName, count)

            if removed then
                AddMoney(source, "cash", sellPrice * count)
                return true
            else
                SendNotification(source, locale("not_enough_fish"), "error")
                return false
            end
        else
            SendNotification(source, locale("not_enough_fish"), "error")
            return false
        end
    end
end)


-- =============================================================================
-- CALLBACK: prism_fishing:server:CheckPlayerMoney
-- Checks if the player has enough money and deducts it if so.
-- Parameters (from client):
--   paymentMethod - "cash" / "bank" / etc.
--   amount        - the price to check/deduct
-- Returns:
--   true if successful, false if insufficient funds
-- =============================================================================
lib.callback.register("prism_fishing:server:CheckPlayerMoney", function(source, paymentMethod, amount)
    local balance = GetPlayerMoney(source, paymentMethod)

    if amount <= balance then
        RemoveMoney(source, paymentMethod, amount)
        return true
    end

    return false
end)


-- =============================================================================
-- THREAD: Populate storeItemPrices and fishSellPrices from config at startup
-- =============================================================================
CreateThread(function()
    -- Build the item-price map from the store config
    for _, storeEntry in ipairs(config.Store) do
        storeItemPrices[storeEntry.name] = storeEntry.price
    end

    -- Build the fish-sell-price map from the fish exchange config
    for _, exchangeEntry in ipairs(config.FishExchange) do
        fishSellPrices[exchangeEntry.name] = exchangeEntry.price
    end
end)


-- =============================================================================
-- THREAD: Register useable items for every fishing rod defined in config
-- For each rod key in config.FishingRod, a useable item is registered.
-- Using the rod triggers the full fishing flow:
--   cooldown check -> zone check -> bait check -> fish selection -> client event
-- =============================================================================
CreateThread(function()
    for rodItemName, rodData in pairs(config.FishingRod) do

        -- Register this rod as a useable item
        CreateUseableItem(rodItemName, function(source)

            -- ----------------------------------------------------------------
            -- 1. COOLDOWN CHECK
            --    If the player used a rod recently, block and notify them.
            -- ----------------------------------------------------------------
            local cooldownExpiry = fishingCooldowns[source]
            if cooldownExpiry then
                if cooldownExpiry > os.time() then
                    SendNotification(source, locale("cooldown_fishing"), "error")
                    return
                end
            end

            -- ----------------------------------------------------------------
            -- 2. ROD POSSESSION CHECK
            --    Verify the player actually has this rod in their inventory.
            -- ----------------------------------------------------------------
            local rodCount = GetCountItems(source, rodItemName)
            if rodCount < 1 then
                SendNotification(source, locale("no_fishing_rod"), "error")
                activeRodState[source] = nil
                return
            end

            -- Mark the player as actively using a rod
            activeRodState[source] = true

            -- ----------------------------------------------------------------
            -- 3. ZONE CHECK
            --    Ask the client whether the player is in a fishing zone.
            --    Returns: isNearWater (bool), zoneData (table or nil)
            -- ----------------------------------------------------------------
            local isNearWater, zoneData = lib.callback.await(
                "prism_fishing:client:GetCurrentZone",
                source
            )

            if not isNearWater then
                SendNotification(source, locale("no_water_nearby"), "error")
                activeRodState[source] = nil
                return
            end

            -- If no specific zone, check if outside fishing is enabled
            if not zoneData then
                if not config.outside.enable then
                    SendNotification(source, locale("fishing_only_in_zone"), "error")
                    activeRodState[source] = nil
                    return
                end
            end

            -- ----------------------------------------------------------------
            -- 4. BAIT CHECK
            --    Find all bait types the player currently has in their inventory.
            -- ----------------------------------------------------------------
            local availableBaits = {}

            for _, baitData in pairs(config.Bait) do
                local baitCount = GetCountItems(source, baitData.name)
                if baitCount > 0 then
                    availableBaits[#availableBaits + 1] = baitData
                end
            end

            if #availableBaits == 0 then
                SendNotification(source, locale("no_bait"), "error")
                activeRodState[source] = nil
                return
            end

            -- ----------------------------------------------------------------
            -- 5. DISTANCE CHECK (only when inside a named fishing zone)
            --    Make sure the player is within the zone's allowed radius.
            -- ----------------------------------------------------------------
            if zoneData then
                local areaConfig   = config.FishingArea[zoneData.index]
                local locationCoord = areaConfig.locations[zoneData.locationIndex]

                -- Get player's current world coordinates via the ped entity
                local ped         = GetPlayerPed(source)
                local playerCoord = GetEntityCoords(ped)

                -- Vector distance from player to the zone location
                local distance = #(playerCoord - locationCoord)

                if distance > areaConfig.radius then
                    SendNotification(source, locale("out_of_fishing_zone"), "error")
                    activeRodState[source] = nil
                    return
                end
            end

            -- ----------------------------------------------------------------
            -- 6. BAIT SELECTION
            --    Send available baits to the client for the player to choose.
            --    Returns the chosen baitData table, or nil if cancelled.
            -- ----------------------------------------------------------------
            local chosenBait = lib.callback.await(
                "prism_fishing:client:SelectBait",
                source,
                availableBaits
            )

            if not chosenBait then
                activeRodState[source] = nil
                return
            end

            -- ----------------------------------------------------------------
            -- 7. FISH SELECTION
            --    Determine which fish list to use (zone-specific or outside),
            --    then pick a fish via weighted random based on player level.
            -- ----------------------------------------------------------------
            local fishList

            if zoneData then
                local areaConfig = config.FishingArea[zoneData.index]
                fishList = areaConfig.fishList
            end

            -- Fall back to outside fish list if no zone-specific list
            if not fishList then
                fishList = config.outside.fishList
            end

            local playerLevel  = GetPlayerLevel(source)
            local selectedFish = GetWeightedFish(fishList, playerLevel)

            -- ----------------------------------------------------------------
            -- 8. CARRY SPACE CHECK
            --    Ensure the player has room to carry 1 more fish item.
            -- ----------------------------------------------------------------
            local canCarry = CanCarryItem(source, selectedFish, 1)
            if not canCarry then
                SendNotification(source, locale("no_carry_space"), "error")
                activeRodState[source] = nil
                return
            end

            -- ----------------------------------------------------------------
            -- 9. COMMIT STATE & CONSUME BAIT, THEN TRIGGER CLIENT FISHING ANIM
            -- ----------------------------------------------------------------
            -- Store the pending reward in the active state
            activeRodState[source] = { reward = selectedFish }

            -- Consume 1 bait item
            RemoveItem(source, chosenBait.name, 1)

            -- Tell the client to start the fishing animation / minigame
            TriggerClientEvent(
                "prism_fishing:client:UseFishingRod",
                source,
                chosenBait,
                selectedFish,
                rodItemName
            )
        end)

    end
end)


-- =============================================================================
-- NET EVENT: prism_fishing:client:FinishFishing
-- Fired by the client when the fishing minigame is successfully completed.
-- Awards the pending fish item and its XP reward to the player.
-- =============================================================================
RegisterNetEvent("prism_fishing:client:FinishFishing", function()
    local source    = source
    local rodState  = activeRodState[source]

    -- Anti-cheat: if there's no active state for this player, log and bail
    if not rodState then
        debugPrint("Something Cheater")
        return
    end

    -- Grant the fish item (1x) to the player
    AddItem(source, rodState.reward, 1)

    -- Award XP based on the fish's xpReward value in config
    local xpReward = config.Fish[rodState.reward].xpReward
    AddXPToPlayer(source, xpReward)

    -- Clear the active rod state for this player
    activeRodState[source] = nil

    -- Apply a 1-second cooldown before they can fish again
    fishingCooldowns[source] = os.time() + 1
end)


-- =============================================================================
-- NET EVENT: prism_fishing:client:ClearFishing
-- Fired by the client when fishing ends without success (cancelled, escaped, etc.).
-- Handles rod break chance and resets player fishing state.
-- Parameters:
--   rodItemName - the rod item name that was in use (passed from client)
-- =============================================================================
RegisterNetEvent("prism_fishing:client:ClearFishing", function(rodItemName)
    local source  = source
    local rodData = config.FishingRod[rodItemName]

    -- Roll for rod break: random 0-100 against the rod's breakChange percentage
    local breakRoll   = math.random(0, 100)
    local breakChance = rodData.breakChange

    if breakRoll <= breakChance then
        -- Rod broke: remove it and notify the player
        RemoveItem(source, rodItemName, 1)
        SendNotification(source, locale("rod_broke"), "error")
    end

    -- Clear the active rod state for this player
    activeRodState[source] = nil

    -- Apply a 1-second cooldown before they can fish again
    fishingCooldowns[source] = os.time() + 1
end)