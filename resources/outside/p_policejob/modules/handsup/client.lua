if not Config.Handsup.Enabled then return end

local handsUp = false
local cfg = Config.Handsup

local function exportHandler(exportName, func)
    AddEventHandler(('__cfx_export_qb-smallresources_%s'):format(exportName), function(setCB)
        setCB(func)
    end)
end

exports('isHandsUp', function()
    return handsUp
end)

-- compatible with qb-smallresources
exportHandler('getHandsup', function()
    return handsUp
end)

RegisterCommand(cfg.Command, function()
    local state = LocalPlayer.state
    if state.isDead or state.isCuffed or state.PhoneOpen then return end
    if Interactions and Interactions.isInCuffProcess then return end

    if handsUp then
        ClearPedSecondaryTask(cache.ped)
        handsUp = false
        return
    end

    local anim = cfg.Animation
    local dict = lib.requestAnimDict(anim.dict)
    TaskPlayAnim(cache.ped, dict, anim.clip, 2.0, 2.0, -1, 49, true)
    RemoveAnimDict(dict)
    handsUp = true

    local controls = cfg.DisableControls
    CreateThread(function()
        while handsUp do
            Wait(1)
            for i = 1, #controls do
                DisableControlAction(controls[i][1], controls[i][2], true)
            end
            if not IsEntityPlayingAnim(cache.ped, anim.dict, anim.clip, 3) then
                handsUp = false
            end
        end
    end)
end, false)

RegisterKeyMapping(cfg.Command, locale('hands_up'), 'keyboard', cfg.Key)
