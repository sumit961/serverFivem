-- ============================================================
--  prism_fishing  |  client-side NUI / UI bridge  |  DEOBFUSCATED
--  Original variables renamed to descriptive identifiers.
--  All logic is preserved 1-to-1; only names and formatting
--  have changed.  Comments explain every non-trivial section.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
--  MODULE-LEVEL VARIABLES
-- ─────────────────────────────────────────────────────────────

-- Native shorthand references kept at module scope for efficiency
local rawSendNUIMessage = SendNUIMessage   -- low-level NUI message sender
local rawSetNuiFocus    = SetNuiFocus      -- native NUI focus control

-- Load the shared configuration table
local Config = require("shared/config")

-- Promise handles – only one of each should exist at a time:
--   minigamePromise  tracks the active skill-check mini-game
--   catchUIPromise   tracks the active keep/release catch screen
local minigamePromise = nil
local catchUIPromise  = nil


-- ─────────────────────────────────────────────────────────────
--  GLOBAL HELPER: toggleNuiFrame(visible)
--  Shows or hides the React NUI frame by sending a
--  "ui:setVisible" message.
-- ─────────────────────────────────────────────────────────────
function toggleNuiFrame(visible)
    SendReactMessage("ui:setVisible", visible)
end
toggleNuiFrame = toggleNuiFrame   -- expose as global


-- ─────────────────────────────────────────────────────────────
--  GLOBAL HELPER: SendReactMessage(action, data)
--  Wraps SendNUIMessage so every message has a consistent
--  { action, data } envelope that the React front-end expects.
-- ─────────────────────────────────────────────────────────────
function SendReactMessage(action, data)
    rawSendNUIMessage({
        action = action,
        data   = data,
    })
end
SendReactMessage = SendReactMessage   -- expose as global


-- ─────────────────────────────────────────────────────────────
--  GLOBAL FUNCTION: SetupUi()
--  Builds and sends the full UI initialisation payload to React.
--
--  Steps:
--    1. Wait 1 s for everything to settle after player load.
--    2. Determine the player's current fishing level.
--    3. Iterate Config.FishLevel to build a fishLevelData array,
--       annotating each entry with lock state, XP needed, etc.
--    4. Send "ui:setupUI" with shop, exchange, level, theme and
--       localisation data.
-- ─────────────────────────────────────────────────────────────
function SetupUi()
    Wait(1000)

    -- ── Locale ────────────────────────────────────────────────
    local localeCode = Config.Locale or "en"

    -- ── Player level ──────────────────────────────────────────
    -- Use PlayerFish.level if available, otherwise default to 1
    local playerLevel
    if PlayerFish and PlayerFish.level then
        playerLevel = PlayerFish.level
    else
        playerLevel = 1
    end

    -- ── Find the highest numeric level key in Config.LevelXP ──
    -- This lets us know when a fish is already at max level.
    local maxConfigLevel = 0
    for levelKey, _ in pairs(Config.LevelXP) do
        if type(levelKey) == "number" and levelKey > maxConfigLevel then
            maxConfigLevel = levelKey
        end
    end

    -- ── Build fishLevelData array ─────────────────────────────
    -- Config.FishLevel is an ordered list; each entry has at least
    -- { name, label, image, description }.
    local fishLevelData = {}

    for _, fishLevelEntry in ipairs(Config.FishLevel) do
        -- Look up the full fish definition in Config.Fish
        local fishDef = Config.Fish[fishLevelEntry.name]

        if not fishDef then
            -- Warn if a FishLevel entry references an unknown fish
            debugPrint(("Fish %s not found in Config.Fish"):format(fishLevelEntry.name))
        end

        -- Required level to unlock this fish (default 1)
        local requiredLevel = (fishDef and fishDef.requiredLevel) or 1

        -- isMaxLevel = true when this fish's required level is at or
        -- beyond the highest configured level (no further XP table entry)
        local isMaxLevel = maxConfigLevel <= requiredLevel

        -- XP needed to reach the NEXT level after requiredLevel.
        -- If the fish is already at max level there is no "next" entry,
        -- so xpNeeded stays 0.
        local xpNeeded = 0
        if not isMaxLevel then
            xpNeeded = Config.LevelXP[requiredLevel + 1] or 0
        end

        -- locked = true when the player hasn't reached the required level yet
        local isLocked = playerLevel < requiredLevel

        table.insert(fishLevelData, {
            name          = fishLevelEntry.name,
            label         = fishLevelEntry.label,
            image         = fishLevelEntry.image,
            description   = fishLevelEntry.description,
            category      = "Fish Level " .. requiredLevel,
            level         = requiredLevel,
            xpNeeded      = xpNeeded,
            isMaxLevel    = isMaxLevel,
            requiredLevel = requiredLevel,
            lockText      = locale("fishLevel_lockedText", requiredLevel),
            locked        = isLocked,
        })
    end

    -- ── Send the full setup payload to React ──────────────────
    SendReactMessage("ui:setupUI", {
        shopData         = Config.Store,
        transparency     = Config.UITransparency,
        fishExchangeData = Config.FishExchange,
        fishLevelData    = fishLevelData,
        currency         = Config.Currency,
        minigameSettings = Config.MinigameSettings,
        theme            = {
            primary = Config.ThemeUI,
        },
        setLocale        = {
            -- Pass the UI-specific locale strings for the React layer
            data = Locales[localeCode].ui,
        },
    })
end
SetupUi = SetupUi   -- expose as global


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:onLoadUI
--  Fired by the React app once it has mounted.
--  Simply acknowledges and prints a debug message.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:onLoadUI", function(data, cb)
    cb(true)
    debugPrint("NUI UI Loaded")
end)


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:buyBasket
--  Player clicked "Buy Basket" in the fishing store UI.
--  Forwards the request to the server callback and passes the
--  result straight back to the NUI.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:buyBasket", function(data, cb)
    local result = lib.callback.await("prism_fishing:server:BuyBasket", false, data)
    cb(result)
end)


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:sellItem
--  Player clicked "Sell" on a fish/item in the store UI.
--  Forwards to the server and returns the result to the NUI.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:sellItem", function(data, cb)
    local result = lib.callback.await("prism_fishing:server:SellItem", false, data)
    cb(result)
end)


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:minigameSuccess
--  The React mini-game component reports success.
--  Resolves minigamePromise with the result data, closes the
--  NUI frame, and acknowledges the callback.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:minigameSuccess", function(data, cb)
    -- Resolve the waiting promise with whatever the mini-game returned
    minigamePromise:resolve(data)
    minigamePromise = nil

    -- Release NUI focus and hide the frame
    rawSetNuiFocus(false, false)
    toggleNuiFrame(false)
    SendReactMessage("ui:openMinigame", false)

    cb(true)
end)


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:hideFrame
--  Generic "close the UI" signal from React (e.g. player presses
--  Escape inside the store).  Removes NUI focus and resets state.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:hideFrame", function(data, cb)
    rawSetNuiFocus(false, false)
    toggleNuiFrame(false)
    SendReactMessage("ui:resetData")
    cb(true)
end)


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:loadUI
--  Simple ready-acknowledgement from the React app.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:loadUI", function(data, cb)
    cb(true)
end)


-- ─────────────────────────────────────────────────────────────
--  GLOBAL FUNCTION: StartMinigame(difficulty)
--  Opens the skill-check mini-game UI and BLOCKS until the
--  player either succeeds or the mini-game resolves.
--
--  Returns whatever the mini-game resolves with (typically a
--  boolean or result table).
--
--  Guards against being called a second time while already open
--  by returning early if minigamePromise is not nil.
-- ─────────────────────────────────────────────────────────────
function StartMinigame(difficulty)
    -- Already running – do not open a second instance
    if minigamePromise then return end

    -- Create a new promise; we will await it below
    minigamePromise = promise.new()

    -- Show the NUI frame and grant cursor/keyboard focus
    toggleNuiFrame(true)
    rawSetNuiFocus(true, true)

    -- Tell React to open the mini-game panel with the given difficulty
    SendReactMessage("ui:openMinigame", {
        open       = true,
        difficulty = difficulty,
    })

    -- Block this Lua thread until nui:minigameSuccess resolves the promise
    return Citizen.Await(minigamePromise)
end
StartMinigame = StartMinigame   -- expose as global


-- ─────────────────────────────────────────────────────────────
--  GLOBAL FUNCTION: OpenStorePage()
--  Opens the fishing store page in the NUI.
--  Populates the player's live data (including calculated xpMax)
--  before showing the page so the HUD reflects current progress.
-- ─────────────────────────────────────────────────────────────
function OpenStorePage()
    toggleNuiFrame(true)
    rawSetNuiFocus(true, true)

    -- Ensure we have a valid PlayerFish table even if not yet loaded
    local fishData = PlayerFish or { level = 0, xp = 0 }

    -- Calculate the XP required to reach the NEXT level
    local nextLevel = (fishData.level or 0) + 1
    fishData.xpMax  = Config.LevelXP[nextLevel] or 0

    -- Push the player's stats to React then open the store page
    SendReactMessage("ui:setPlayerData", fishData)
    SendReactMessage("ui:openStorePage", true)
end
OpenStorePage = OpenStorePage   -- expose as global


-- ─────────────────────────────────────────────────────────────
--  GLOBAL FUNCTION: OpenBoatShop()
--  Opens the boat shop page inside the NUI.
--  Mirrors OpenStorePage but sends "ui:openBoatShop" instead.
-- ─────────────────────────────────────────────────────────────
function OpenBoatShop()
    toggleNuiFrame(true)
    rawSetNuiFocus(true, true)

    -- Ensure we have a valid PlayerFish table
    local fishData = PlayerFish or { level = 0, xp = 0 }

    -- Calculate xpMax for the HUD display
    local nextLevel = (fishData.level or 0) + 1
    fishData.xpMax  = Config.LevelXP[nextLevel] or 0

    -- Push the player's stats then open the boat shop page
    SendReactMessage("ui:setPlayerData", fishData)
    SendReactMessage("ui:openBoatShop", true)
end
OpenBoatShop = OpenBoatShop   -- expose as global


-- ─────────────────────────────────────────────────────────────
--  NET EVENT: prism_fishing:client:OpenBoatShop
--  Server-triggered shortcut to open the boat shop on this client.
-- ─────────────────────────────────────────────────────────────
RegisterNetEvent("prism_fishing:client:OpenBoatShop")
AddEventHandler("prism_fishing:client:OpenBoatShop", function()
    OpenBoatShop()
end)


-- ─────────────────────────────────────────────────────────────
--  GLOBAL FUNCTION: StartCatchUI(catchData)
--  Opens the "Keep / Release" catch notification panel and
--  BLOCKS until the player makes a decision or the timer expires.
--
--  catchData (table) – fish info passed straight to React:
--    { name, label, rarity, change }
--
--  Returns the string resolved by the NUI (e.g. "keep",
--  "release", or false on timeout).
-- ─────────────────────────────────────────────────────────────
function StartCatchUI(catchData)
    -- Guard: do not open if already showing a catch panel
    if catchUIPromise then return end

    catchUIPromise = promise.new()

    toggleNuiFrame(true)
    rawSetNuiFocus(true, true)

    -- Tell React to open the catch notification overlay
    SendReactMessage("ui:openCatchNotification", true)

    -- Send the actual fish data to populate the card
    SendReactMessage("ui:catchFish", catchData)

    -- Block until nui:takeFish or nui:fishTimeout resolves the promise
    return Citizen.Await(catchUIPromise)
end
StartCatchUI = StartCatchUI   -- expose as global


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:takeFish
--  Fired when the player clicks "Keep" (or equivalent) on the
--  catch card.  Resolves catchUIPromise with the action string
--  from the NUI, then closes the catch overlay.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:takeFish", function(data, cb)
    -- data contains the player's choice (e.g. "keep" or "release")
    catchUIPromise:resolve(data)
    catchUIPromise = nil

    -- Close the catch notification overlay and clear the fish card
    SendReactMessage("ui:openCatchNotification", false)
    SendReactMessage("ui:catchFish", nil)

    cb(true)
end)


-- ─────────────────────────────────────────────────────────────
--  NUI CALLBACK: nui:fishTimeout
--  Fired when the catch-decision timer runs out before the player
--  acts.  Resolves catchUIPromise with false (fish got away),
--  notifies the player, and closes the catch overlay.
-- ─────────────────────────────────────────────────────────────
RegisterNUICallback("nui:fishTimeout", function(data, cb)
    -- Nothing to resolve if the promise was already cleaned up
    if not catchUIPromise then return end

    -- Resolve with false → fish escaped
    catchUIPromise:resolve(false)
    catchUIPromise = nil

    -- Inform the player
    Notify(locale("got_away_fish"), "error")

    -- Close the catch overlay
    SendReactMessage("ui:openCatchNotification", false)
    SendReactMessage("ui:catchFish", nil)

    cb(true)
end)