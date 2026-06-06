CM = CM or {}

CreateThread(function()
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end
    print("[CM-CORE] Client ready. Character: " .. tostring(LocalPlayer.state.charId))
end)