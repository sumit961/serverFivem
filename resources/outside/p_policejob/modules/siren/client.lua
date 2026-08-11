while not Config or not Config.Siren do
    Citizen.Wait(50)
end

if not Config.Siren.enabled then
    return
end

Siren = {
    menuOpen = false,
    editing = false,
    currentVehicle = nil,
    state = {
        lights = false,
        audio = false,
        muted = false,
        tone = 1,
        horn = false,
    },
}

local activeSoundId = nil
local hornActive = false
local staticSent = false

function getSirenCode(state)
    if not state.lights then
        return 0
    end
    if not state.audio then
        return 1
    end
    if state.tone > 2 then
        return 3
    end
    return 2
end

function isValidVehicle(vehicle)
    return vehicle and vehicle ~= 0
end

function isEmergencyVehicle(vehicle)
    if not vehicle or vehicle == 0 then
        return false
    end
    return Config.Siren.allowedClasses[GetVehicleClass(vehicle)] == true
end

function stopSirenSound()
    if activeSoundId then
        StopSound(activeSoundId)
        ReleaseSoundId(activeSoundId)
        activeSoundId = nil
    end
end

function playSirenSound(vehicle, soundName)
    stopSirenSound()
    if not soundName or not vehicle then
        return
    end
    if not DoesEntityExist(vehicle) then
        return
    end
    activeSoundId = GetSoundId()
    PlaySoundFromEntity(activeSoundId, soundName, vehicle, 0, false, 0)
end

function buildSirenStaticData()
    local tones = {}
    for index, tone in ipairs(Config.Siren.tones) do
        tones[index] = {
            label = tone.localeKey and locale(tone.localeKey) or tone.label,
        }
    end
    return {
        tones = tones,
        keybinds = Config.Siren.keybinds,
        locales = {
            title = locale("siren_title"),
            status_off = locale("siren_status_off"),
            status_code2 = locale("siren_status_code2"),
            status_code3 = locale("siren_status_code3"),
            label_lights = locale("siren_label_lights"),
            label_siren = locale("siren_label_siren"),
            label_mute = locale("siren_label_mute"),
            value_on = locale("siren_value_on"),
            value_off = locale("siren_value_off"),
            value_muted = locale("siren_value_muted"),
            value_audible = locale("siren_value_audible"),
            section_tones = locale("siren_section_tones"),
            section_keybinds = locale("siren_section_keybinds"),
            section_layout = locale("siren_section_layout"),
            active = locale("siren_active"),
            edit = locale("siren_edit"),
            btn_reset = locale("siren_btn_reset"),
            btn_save = locale("siren_btn_save"),
            layout_hint = locale("siren_layout_hint"),
        },
    }
end

function Siren.hasAccess(self)
    local job = Bridge.Framework.fetchPlayerJob()
    return job and Config.Jobs[job.name] ~= nil
end

function Siren.applyState(self)
    local vehicle = self.currentVehicle
    if not vehicle or not DoesEntityExist(vehicle) then
        return
    end
    if self.state.lights then
        SetVehicleSiren(vehicle, true)
        SetVehicleHasMutedSirens(vehicle, true)
    else
        SetVehicleSiren(vehicle, false)
        SetVehicleHasMutedSirens(vehicle, false)
    end
    if self.state.lights and self.state.audio and not self.state.muted then
        local tone = Config.Siren.tones[self.state.tone]
        playSirenSound(vehicle, tone and tone.sound)
    else
        stopSirenSound()
    end
end

function Siren.pushNui(self)
    if not staticSent then
        SendNUIMessage({
            action = "setSirenStatic",
            data = buildSirenStaticData(),
        })
        staticSent = true
    end
    SendNUIMessage({
        action = "setSirenData",
        data = {
            lights = self.state.lights,
            audio = self.state.audio,
            muted = self.state.muted,
            tone = self.state.tone,
            code = getSirenCode(self.state),
            horn = self.state.horn,
        },
    })
end

function Siren.openMenu(self)
    if not self:hasAccess() then
        return
    end
    if not isEmergencyVehicle(cache.vehicle) or not isValidVehicle(cache.vehicle) then
        return Bridge.Notify.showNotify(locale("siren_not_in_emergency_vehicle"), "error")
    end
    self.currentVehicle = cache.vehicle
    self.menuOpen = true
    SendNUIMessage({
        action = "setVisibleSiren",
        data = true,
    })
    self:pushNui()
    Bridge.Debug("[Siren] HUD opened")
end

function Siren.closeMenu(self)
    if not self.menuOpen then
        return
    end
    self.menuOpen = false
    if self.editing then
        self:setEditing(false)
    end
    stopHorn()
    SendNUIMessage({
        action = "setVisibleSiren",
        data = false,
    })
end

function Siren.setEditing(self, enabled)
    self.editing = enabled and true or false
    SetNuiFocus(self.editing, self.editing)
    SendNUIMessage({
        action = "setSirenEditing",
        data = self.editing,
    })
end

function Siren.toggleLights(self)
    self.state.lights = not self.state.lights
    if not self.state.lights then
        self.state.audio = false
        self.state.muted = false
    end
    self:applyState()
    self:pushNui()
end

function Siren.toggleAudio(self)
    if not self.state.lights then
        self.state.lights = true
    end
    self.state.audio = not self.state.audio
    if self.state.audio then
        self.state.muted = false
    end
    self:applyState()
    self:pushNui()
end

function Siren.toggleMute(self)
    if not self.state.audio then
        return
    end
    self.state.muted = not self.state.muted
    self:applyState()
    self:pushNui()
end

function Siren.cycleTone(self)
    local toneCount = #Config.Siren.tones
    if toneCount == 0 then
        return
    end
    self.state.tone = (self.state.tone % toneCount) + 1
    self:applyState()
    self:pushNui()
end

function Siren.setTone(self, toneIndex)
    if not Config.Siren.tones[toneIndex] then
        return
    end
    self.state.tone = toneIndex
    self:applyState()
    self:pushNui()
end

function Siren.reset(self)
    self.state.lights = false
    self.state.audio = false
    self.state.muted = false
    self.state.horn = false
    self.state.tone = 1
    stopSirenSound()
    if self.currentVehicle and DoesEntityExist(self.currentVehicle) then
        SetVehicleSiren(self.currentVehicle, false)
        SetVehicleHasMutedSirens(self.currentVehicle, false)
    end
end

function startHorn()
    if not isEmergencyVehicle(cache.vehicle) or not isValidVehicle(cache.vehicle) then
        return
    end
    if hornActive then
        return
    end
    hornActive = true
    Siren.state.horn = true
    if Siren.menuOpen then
        Siren:pushNui()
    end
    CreateThread(function()
        while hornActive do
            if not cache.vehicle or cache.vehicle == 0 then
                break
            end
            Wait(0)
            SoundVehicleHornThisFrame(cache.vehicle)
        end
        hornActive = false
    end)
end

function stopHorn()
    if not hornActive and not Siren.state.horn then
        return
    end
    hornActive = false
    Siren.state.horn = false
    if Siren.menuOpen then
        Siren:pushNui()
    end
end

lib.addKeybind({
    name = "p_policejob_siren_menu",
    description = locale("siren_kb_toggle_menu"),
    defaultKey = Config.Siren.keybinds.toggleMenu.key,
    onPressed = function()
        if Siren.menuOpen then
            Siren:closeMenu()
        else
            Siren:openMenu()
        end
    end,
})

lib.addKeybind({
    name = "p_policejob_siren_lights",
    description = locale("siren_kb_toggle_lights"),
    defaultKey = Config.Siren.keybinds.toggleLights.key,
    onPressed = function()
        if not Siren:hasAccess() then
            return
        end
        if not isEmergencyVehicle(cache.vehicle) or not isValidVehicle(cache.vehicle) then
            return
        end
        Siren.currentVehicle = cache.vehicle
        Siren:toggleLights()
    end,
})

lib.addKeybind({
    name = "p_policejob_siren_cycle",
    description = locale("siren_kb_cycle_siren"),
    defaultKey = Config.Siren.keybinds.cycleSiren.key,
    onPressed = function()
        if not Siren:hasAccess() then
            return
        end
        if not isEmergencyVehicle(cache.vehicle) or not isValidVehicle(cache.vehicle) then
            return
        end
        Siren.currentVehicle = cache.vehicle
        if not Siren.state.audio then
            Siren:toggleAudio()
        else
            Siren:cycleTone()
        end
    end,
})

lib.addKeybind({
    name = "p_policejob_siren_mute",
    description = locale("siren_kb_mute_toggle"),
    defaultKey = Config.Siren.keybinds.muteToggle.key,
    onPressed = function()
        if not isEmergencyVehicle(cache.vehicle) or not isValidVehicle(cache.vehicle) then
            return
        end
        Siren.currentVehicle = cache.vehicle
        Siren:toggleMute()
    end,
})

lib.addKeybind({
    name = "p_policejob_siren_horn",
    description = locale("siren_kb_manual_horn"),
    defaultKey = Config.Siren.keybinds.manualHorn.key,
    onPressed = startHorn,
    onReleased = stopHorn,
})

CreateThread(function()
    while true do
        Wait(500)
        if Siren.currentVehicle then
            local sameVehicle = cache.vehicle == Siren.currentVehicle
            local vehicleValid = isValidVehicle(Siren.currentVehicle)
            if not sameVehicle or not vehicleValid then
                Siren:reset()
                Siren.currentVehicle = nil
                if Siren.menuOpen then
                    Siren:closeMenu()
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(250)
        local vehicle = Siren.currentVehicle
        local shouldPlay = false
        if vehicle and DoesEntityExist(vehicle) then
            if Siren.state.lights and Siren.state.audio and not Siren.state.muted then
                shouldPlay = true
            end
        end
        if shouldPlay then
            if activeSoundId and HasSoundFinished(activeSoundId) then
                local tone = Config.Siren.tones[Siren.state.tone]
                playSirenSound(vehicle, tone and tone.sound)
            end
        elseif activeSoundId then
            stopSirenSound()
        end
    end
end)

RegisterNUICallback("siren/closeEdit", function(_, cb)
    Siren:setEditing(false)
    cb(1)
end)

RegisterNUICallback("hideFrame", function(data, cb)
    local frameName = data and data.name
    if frameName == "setVisibleSiren" and Siren.editing then
        Siren:setEditing(false)
    end
    cb("ok")
end)

RegisterCommand("sirenconfig", function()
    if not Siren.menuOpen then
        Siren:openMenu()
    end
    if not Siren.menuOpen then
        return
    end
    Siren:setEditing(not Siren.editing)
end, false)

TriggerEvent("chat:addSuggestion", "/sirenconfig", locale("siren_command_suggestion"))

exports("isSirenMenuOpen", function()
    return Siren.menuOpen
end)

exports("openSirenMenu", function()
    Siren:openMenu()
end)
