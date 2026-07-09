print([[
   ____ __  __        ____ ___  ____  _____
  / ___|  \/  |      / ___/ _ \|  _ \| ____|
 | |   | |\/| |_____| |  | | | | |_) |  _|
 | |___| |  | |_____| |__| |_| |  _ <| |___
  \____|_|  |_|      \____\___/|_| \_\_____|

[CM-CORE] Foundation initialized
]])

CreateThread(function()
    while true do
        Wait(60000)
        local online = exports['cm-core']:GetOnlineCount()
        TriggerEvent('cm-core:heartbeat', online)
    end
end)
