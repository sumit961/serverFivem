if not Config.RadioList.Enabled then
    return
end

Radio = {
    currentChannel = 0,
    restrictedJobs = Config.RadioList.RestrictedJobs,
    listVisible = false,
    toggleCooldownUntil = GetGameTimer(),
    channelLabel = "",
    users = {},
    editMode = false,
    selectedAnimation = nil,
}

function Radio.hasJobAccess(self)
    if not self.restrictedJobs then
        return true
    end
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return false
    end
    local requiredGrade = self.restrictedJobs[job.name]
    if not requiredGrade then
        return false
    end
    local grade = job.grade or 0
    return grade >= requiredGrade
end

function Radio.formatChannelLabel(self, channel)
    local channelName = Config.RadioList.ChannelNames[tostring(channel)]
    if channelName then
        return ("%s - %s"):format(channel, channelName)
    end
    return tostring(channel)
end

function Radio.mapUsers(self, users)
    local mapped = {}
    for index, user in ipairs(users) do
        mapped[index] = {
            id = user.player,
            name = user.name,
            badge = user.badge,
            isTalking = user.talking or false,
            isDead = user.isDead or false,
        }
    end
    return mapped
end

function Radio.sendUiUpdate(self)
    SendNUIMessage({
        action = "setRadioData",
        data = {
            frequency = self.channelLabel,
            users = self.users,
        },
    })
end

function Radio.setListVisible(self, visible)
    if self.listVisible == visible then
        return
    end
    self.listVisible = visible
    SendNUIMessage({ action = "setVisibleRadioList", data = visible })
end

if Config.RadioList.ToggleKey then
    lib.addKeybind({
        name = "toggle_radio_list",
        description = locale("toggle_radio_list"),
        defaultKey = Config.RadioList.ToggleKey,
        onPressed = function()
            if Radio.toggleCooldownUntil > GetGameTimer() or Radio.currentChannel == 0 then
                return
            end
            Radio.toggleCooldownUntil = GetGameTimer() + 100
            Radio:setListVisible(not Radio.listVisible)
        end,
    })
end

RegisterNetEvent("p_policejob/client_radio/connectedChannel", function(channel)
    if not Radio:hasJobAccess() then
        return
    end
    Radio.currentChannel = channel
    Radio.channelLabel = Radio:formatChannelLabel(channel)
    if channel == 0 then
        Radio.users = {}
        Radio:setListVisible(false)
    else
        Radio:setListVisible(true)
        Radio:sendUiUpdate()
    end
end)

RegisterNetEvent("p_policejob/client_radio/refreshRadioChannels", function(channel, users)
    if not Radio:hasJobAccess() then
        return
    end
    if Radio.currentChannel ~= channel then
        return
    end
    Radio.channelLabel = Radio:formatChannelLabel(channel)
    Radio.users = Radio:mapUsers(users)
    Radio:sendUiUpdate()
end)

AddStateBagChangeHandler("radioTalking", nil, function(bagName, _, value)
    if Radio.currentChannel == 0 then
        return
    end
    local serverId = tonumber(bagName:match("^player:(%d+)$"))
    if not serverId then
        return
    end
    for index = 1, #Radio.users do
        if Radio.users[index].id == serverId then
            local isTalking = value and true or false
            if Radio.users[index].isTalking ~= isTalking then
                Radio.users[index].isTalking = isTalking
                Radio:sendUiUpdate()
            end
            break
        end
    end
end)

RegisterNetEvent("p_policejob/client_radio/playerDead", function(channel, playerId, isDead)
    if not Radio:hasJobAccess() or Radio.currentChannel ~= channel then
        return
    end
    for index = 1, #Radio.users do
        if Radio.users[index].id == playerId then
            Radio.users[index].isDead = isDead
            break
        end
    end
    Radio:sendUiUpdate()
end)

CreateThread(function()
    for direction, key in pairs(Config.RadioList.ChangePageKeys) do
        lib.addKeybind({
            name = "change_radio_page_" .. direction,
            description = locale("change_radio_page"),
            defaultKey = key,
            onPressed = function()
                if Radio.toggleCooldownUntil > GetGameTimer() or Radio.currentChannel == 0 or not Radio.listVisible then
                    return
                end
                if not Radio:hasJobAccess() then
                    return
                end
                Radio.toggleCooldownUntil = GetGameTimer() + 100
                SendNUIMessage({
                    action = "changeRadioPage",
                    data = { page = direction == "left" and -1 or 1 },
                })
            end,
        })
    end
end)

function Radio.setEditMode(self, enabled)
    self.editMode = enabled
    if enabled then
        SetNuiFocus(true, true)
        SendNUIMessage({ action = "setVisibleRadioList", data = true })
        if self.currentChannel == 0 then
            SendNUIMessage({
                action = "setRadioData",
                data = {
                    frequency = self:formatChannelLabel(1),
                    users = {
                        { id = 1, name = "John Smith", badge = "1247", isTalking = true, isDead = false },
                        { id = 2, name = "Jane Doe", badge = "3892", isTalking = false, isDead = false },
                        { id = 3, name = "Mike Johnson", isTalking = false, isDead = true },
                    },
                },
            })
        else
            self:sendUiUpdate()
        end
        SendNUIMessage({ action = "setRadioListEdit", data = true })
    else
        SendNUIMessage({ action = "setRadioListEdit", data = false })
        SetNuiFocus(false, false)
        if self.currentChannel ~= 0 and self.listVisible then
            self:sendUiUpdate()
        else
            SendNUIMessage({ action = "setVisibleRadioList", data = false })
        end
    end
end

if Config.RadioList.MoveCommand then
    RegisterCommand(Config.RadioList.MoveCommand, function()
        Radio:setEditMode(not Radio.editMode)
    end, false)
end

RegisterNUICallback("hideFrame", function(data, cb)
    if data and data.name == "setVisibleRadioList" and Radio.editMode then
        Radio:setEditMode(false)
    end
    cb("ok")
end)

function Radio.playTalkingAnimation(self, active)
    CreateThread(function()
        local animation = self.selectedAnimation
        if not animation then
            return
        end
        if active then
            local animDict = lib.requestAnimDict(animation.animDict)
            TaskPlayAnim(cache.ped, animDict, animation.animClip, 2.0, -2.0, -1, animation.animFlag, 1)
            if animation.prop then
                local propConfig = animation.prop
                local model = lib.requestModel(propConfig.model)
                local prop = CreateObject(model, GetEntityCoords(cache.ped), true, true, true)
                self.selectedAnimation.createdProp = prop
                local boneIndex = GetPedBoneIndex(cache.ped, propConfig.bone)
                AttachEntityToEntity(
                    prop, cache.ped, boneIndex,
                    vector3(propConfig.coords.x, propConfig.coords.y, propConfig.coords.z),
                    vector3(propConfig.rotation.x, propConfig.rotation.y, propConfig.rotation.z),
                    true, true, false, false, 1, true
                )
                SetEntityAsMissionEntity(prop, true, true)
            end
        else
            if animation.createdProp then
                DeleteEntity(animation.createdProp)
                animation.createdProp = nil
            end
            StopAnimTask(cache.ped, animation.animDict, animation.animClip, -2.0)
        end
    end)
end

AddEventHandler("pma-voice:radioActive", function(active)
    LocalPlayer.state:set("radioTalking", active and true or false, true)
    Radio:playTalkingAnimation(active)
end)

CreateThread(function()
    Wait(1000)
    local savedAnimation = GetResourceKvpString("radio_anim")
    if savedAnimation then
        Radio.selectedAnimation = json.decode(savedAnimation)
    else
        for _, animation in pairs(Config.RadioAnimations) do
            if animation.isDefault then
                Radio.selectedAnimation = animation
                break
            end
        end
    end
end)

function Radio.openAnimMenu()
    local options = {}
    for _, animation in pairs(Config.RadioAnimations) do
        options[#options + 1] = {
            title = animation.label,
            description = locale("set_radio_anim", animation.label),
            arrow = true,
            onSelect = function()
                Radio.selectedAnimation = animation
                Bridge.Notify.showNotify(locale("radio_anim_selected", animation.label), "success")
                SetResourceKvp("radio_anim", json.encode(animation))
            end,
        }
    end
    lib.registerContext({
        id = "radio_anim_menu",
        title = locale("radio_anim_menu"),
        options = options,
    })
    lib.showContext("radio_anim_menu")
end

RegisterCommand("radioanim", Radio.openAnimMenu)
AddEventHandler("p_policejob/client/radio/openAnimMenu", Radio.openAnimMenu)
exports("OpenRadioAnimMenu", Radio.openAnimMenu)
