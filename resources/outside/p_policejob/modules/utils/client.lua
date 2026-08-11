Utils = {}

function Utils.fadeOutScreen(self, duration)
    if not duration then
        duration = 1000
    end
    DoScreenFadeOut(duration)
    while not IsScreenFadedOut() do
        Wait(0)
    end
end

function Utils.fadeInScreen(self, duration)
    if not duration then
        duration = 1000
    end
    DoScreenFadeIn(duration)
    while not IsScreenFadedIn() do
        Wait(0)
    end
end

RegisterNUICallback("getLocales", function(_, cb)
    cb(lib.getLocales())
end)
