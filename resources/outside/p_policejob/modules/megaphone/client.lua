if not Config.Megaphone.enabled then
    return
end

Megaphone = {
    isActive = false,
    props = {},
    filter = nil,
}

local submixParams = {
    [-455129387] = 1,
    [-773893275] = 300.0,
    [2006643436] = 5000.0,
    [-688973352] = 0.0,
    [-1383405282] = 0.2,
    [1634608902] = 0.0,
    [1556538169] = 550.0,
    [-1555401541] = 0.0,
}

exports("isMegaphoneActive", function()
    return Megaphone.isActive
end)

exports("useMegaphone", function()
    Megaphone:use()
end)

CreateThread(function()
    if not Config.Megaphone.enableSubmix then
        return
    end
    Megaphone.filter = CreateAudioSubmix("Megaphone")
    SetAudioSubmixEffectRadioFx(Megaphone.filter, 0)
    for paramHash in pairs(submixParams) do
        SetAudioSubmixEffectParamInt(Megaphone.filter, 0, paramHash, 1)
    end
    AddAudioSubmixOutput(Megaphone.filter, 0)
end)

function Megaphone.playAnim(self)
    local animDict = lib.requestAnimDict("molly@megaphone")
    TaskPlayAnim(cache.ped, animDict, "megaphone_clip", -8.0, 8.0, -1, 49, 1, false, false, false)
    RemoveAnimDict(animDict)
end

function Megaphone.attachProp(self, ped, serverId)
    local model = lib.requestModel("prop_megaphone_01")
    local prop = CreateObject(model, GetEntityCoords(ped), false, false, false)
    local boneIndex = GetPedBoneIndex(ped, 57005)
    AttachEntityToEntity(
        prop, ped, boneIndex,
        0.1, 0.05, 0.0,
        -75.62, -19.44, -30.24,
        true, false, false, false, 0, true
    )
    SetModelAsNoLongerNeeded(model)
    self.props[serverId] = prop
end

function Megaphone.removeProp(self, serverId)
    local prop = self.props[serverId]
    if prop and DoesEntityExist(prop) then
        DeleteEntity(prop)
        self.props[serverId] = nil
    end
end

function Megaphone.enableVoice(self)
    if GetResourceState("pma-voice") == "started" then
        exports["pma-voice"]:overrideProximityRange(Config.Megaphone.forceRange or 30.0, true)
    elseif GetResourceState("yaca-voice") == "started" then
        exports["yaca-voice"]:setCanUseMegaphone(true)
        exports["yaca-voice"]:useMegaphone(true)
    end
end

function Megaphone.disableVoice(self)
    if GetResourceState("pma-voice") == "started" then
        exports["pma-voice"]:clearProximityOverride()
    elseif GetResourceState("yaca-voice") == "started" then
        exports["yaca-voice"]:useMegaphone(false)
    end
end

function Megaphone.startLocalLoop(self)
    self:playAnim()
    Config.Megaphone.onStart()
    CreateThread(function()
        while self.isActive do
            Wait(1000)
            if self.isActive and not IsEntityPlayingAnim(cache.ped, "molly@megaphone", "megaphone_clip", 3) then
                self:playAnim()
            end
        end
    end)
    lib.showTextUI(locale("megaphone_radius"))
    CreateThread(function()
        while self.isActive do
            Wait(1)
            if IsControlPressed(0, 47) then
                local coords = GetEntityCoords(cache.ped)
                local radius = Config.Megaphone.forceRange * 2.25
                DrawMarker(
                    28, coords.x, coords.y, coords.z,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    radius, radius, radius,
                    255, 42, 24, 100,
                    false, false, 0, true, false, false, false
                )
            end
        end
        lib.hideTextUI()
    end)
end

AddStateBagChangeHandler("usingMegaphone", nil, function(bagName, _, value, _, replicated)
    if replicated then
        return
    end
    local playerId = GetPlayerFromStateBagName(bagName)
    if playerId == 0 then
        return
    end
    local ped = GetPlayerPed(playerId)
    local serverId = GetPlayerServerId(playerId)
    local isLocalPlayer = cache.serverId == serverId
    if not value then
        if isLocalPlayer then
            ClearPedTasks(ped)
            Megaphone:disableVoice()
            Config.Megaphone.onStop()
        end
        MumbleSetSubmixForServerId(serverId, -1)
        MumbleSetVolumeOverrideByServerId(serverId, -1.0)
        MumbleClearVoiceTargetPlayers(serverId)
        Megaphone:removeProp(serverId)
        return
    end
    Wait(1)
    Megaphone:attachProp(ped, serverId)
    MumbleSetVolumeOverrideByServerId(serverId, 0.99)
    if Megaphone.filter then
        MumbleSetSubmixForServerId(serverId, Megaphone.filter)
    end
    if isLocalPlayer then
        Megaphone:enableVoice()
        Megaphone:startLocalLoop()
    end
end)

function Megaphone.use(self)
    if not self.isActive then
        local job = Bridge.Framework.fetchPlayerJob()
        if not Config.Jobs[job.name] then
            return Bridge.Notify.showNotify(locale("extras_no_access"), "error")
        end
    end
    self.isActive = not self.isActive
    LocalPlayer.state:set("usingMegaphone", self.isActive, true)
end

RegisterNetEvent("p_policejob/client/megaphone/use", function()
    Megaphone:use()
end)
