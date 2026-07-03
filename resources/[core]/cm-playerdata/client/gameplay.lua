-- cm-playerdata/client/gameplay.lua
-- v1.6: movement/comfort rules.
--   * Infinite stamina (never tired, no exhausted breathing, no stamina damage)
--   * Low health never affects movement (no hurt/injured limp)
--   * Other players can never shove/ragdoll you by running into you
--   * Optional: full no-collision between player peds (zero push at all)

local Config = CMPlayerData.Config
local Gameplay = Config.Gameplay or {}

local nearbyPeds = {}

local function IsLoadedAndAlive()
    if not LocalPlayer or not LocalPlayer.state then return false end
    if LocalPlayer.state.playerDataLoaded ~= true then return false end
    if LocalPlayer.state.isInCharacterSelector == true then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Infinite stamina. RestorePlayerStamina keeps the bar full, which also
-- prevents exhausted breathing audio and stamina health drain while swimming.
-- ---------------------------------------------------------------------------
if Gameplay.InfiniteStamina ~= false then
    CreateThread(function()
        while true do
            Wait(150)
            if IsLoadedAndAlive() then
                RestorePlayerStamina(PlayerId(), 1.0)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Per-ped flags. The ped handle changes on respawn/model change, so these are
-- re-applied on a slow loop instead of only once at spawn.
-- ---------------------------------------------------------------------------
CreateThread(function()
    local lastPed = 0
    while true do
        Wait(1500)
        local ped = PlayerPedId()
        if ped ~= 0 and ped ~= lastPed then
            lastPed = ped

            if Gameplay.BlockShoveRagdoll ~= false then
                -- Never ragdoll/stumble because another player ran into us.
                SetPedCanRagdollFromPlayerImpact(ped, false)
            end

            if Gameplay.DisableHurtMovement ~= false then
                -- Never enter "hurt"/injured combat movement at low health.
                SetPedSuffersCriticalHits(ped, true) -- headshots stay normal; only movement is protected below
            end
        end

        -- Injured movement clipset can still be pushed by the game at low HP;
        -- clear it whenever it appears so movement always stays normal.
        if Gameplay.DisableHurtMovement ~= false and ped ~= 0 then
            local health = GetEntityHealth(ped)
            if health > 0 and health < 175 then
                ResetPedMovementClipset(ped, 0.0)
                SetPedMoveRateOverride(ped, 1.0)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Never let the idle/AFK cinematic camera take over while standing still.
-- ---------------------------------------------------------------------------
if Gameplay.DisableIdleCamera ~= false then
    CreateThread(function()
        while true do
            Wait(5000)
            InvalidateIdleCam()
            InvalidateVehicleIdleCam()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- No player push. Maintains a small list of very close player peds (cheap,
-- every 500ms) and disables ped-to-ped collision with them each frame.
-- Result: players walk through each other; nobody can be pushed or body-blocked.
-- ---------------------------------------------------------------------------
if Gameplay.NoPlayerCollision == true then
    CreateThread(function()
        local limit = Gameplay.NoCollisionDistance or 8.0
        while true do
            Wait(500)
            local list = {}
            if IsLoadedAndAlive() then
                local myPed = PlayerPedId()
                local myCoords = GetEntityCoords(myPed)
                for _, playerIndex in ipairs(GetActivePlayers()) do
                    if playerIndex ~= PlayerId() then
                        local ped = GetPlayerPed(playerIndex)
                        if ped ~= 0 and DoesEntityExist(ped) then
                            if #(myCoords - GetEntityCoords(ped)) <= limit then
                                list[#list + 1] = ped
                            end
                        end
                    end
                end
            end
            nearbyPeds = list
        end
    end)

    CreateThread(function()
        while true do
            if #nearbyPeds > 0 then
                local myPed = PlayerPedId()
                for _, ped in ipairs(nearbyPeds) do
                    if DoesEntityExist(ped) then
                        SetEntityNoCollisionEntity(ped, myPed, true)
                        SetEntityNoCollisionEntity(myPed, ped, true)
                    end
                end
                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end
