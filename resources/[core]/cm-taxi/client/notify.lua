local Config = CMTaxi.Config
CMTaxi.Client = CMTaxi.Client or {}

local function notify(message, kind)
    message = tostring(message or '')
    if message == '' then return end
    kind = kind or 'info'

    local hud = Config.NotifyResource or 'cm-hud'
    if GetResourceState(hud) == 'started' then
        TriggerEvent(hud .. ':client:notify', message, kind)
        return
    end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterNetEvent('cm-taxi:client:notify', notify)

CMTaxi.Client.Notify = notify
