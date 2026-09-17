-- Shared "Press [key]" interaction prompt. Passive, no NUI focus change --
-- safe to call every frame from a proximity loop in any resource.
--
-- exports['cm-ui']:ShowInteract({ key = 'E', label = 'INTERACTION', name = 'Officer Reyes', role = 'CM POLICE' })
-- exports['cm-ui']:HideInteract()

local function ShowInteract(options)
    options = type(options) == 'table' and options or {}
    SendNUIMessage({
        action = 'cmInteract:show',
        key = tostring(options.key or 'E'),
        label = tostring(options.label or 'INTERACTION'),
        name = options.name and tostring(options.name) or nil,
        role = options.role and tostring(options.role) or nil,
    })
end

local function HideInteract()
    SendNUIMessage({ action = 'cmInteract:hide' })
end

exports('ShowInteract', ShowInteract)
exports('HideInteract', HideInteract)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then HideInteract() end
end)
