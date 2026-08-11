if (Config.Notify == 'auto' and not checkResource('ZSX_UIV2')) or (Config.Notify ~= 'auto' and Config.Notify ~= 'zsx_uiv2') then
    return
end

while not Bridge do
    Citizen.Wait(0)
end

if Config.Debug then
    lib.print.info('[Notify] Loaded: zsx_uiv2')
end

Bridge.Notify = {}

Bridge.Notify.showNotify = function(message, type)
    local icon = 'fas fa-info-circle'
    if type == 'success' then
        icon = 'fas fa-check-circle'
    elseif type == 'error' then
        icon = 'fas fa-times-circle'
    end
    
    exports['ZSX_UIV2']:Notification('Powiadomienie', message, icon, 5000)
end
