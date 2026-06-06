print([[
  ____ _   _    _    ____   ____ 
 / ___| | | |  / \  |  _ \ / ___|
| |   | |_| | / _ \ | |_) | |    
| |___|  _  |/ ___ \|  _ <| |___ 
 \____|_| |_/_/   \_\_| \_\\____|
                                 
[CM-CORE] Kernel initialized
]])

CreateThread(function()
    while true do
        Wait(60000)
        local online = exports['cm-core']:GetOnlineCount()
        TriggerEvent('cm-core:heartbeat', online)
    end
end)