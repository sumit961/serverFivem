-- Fixture: client-side FiveM script for cm-fivem-map tests.
-- Covers: single/double quotes, a multiline call, a commented-out
-- registration, a dynamic (computed) event name, a client -> server
-- trigger, and an ox_lib callback await.

RegisterNetEvent('fixture:clientReady')
AddEventHandler('fixture:clientReady', function()
    print('client ready')
end)

RegisterNetEvent(
    "fixture:multilineEvent",
    function(data)
        print(data)
    end
)

-- RegisterNetEvent('fixture:commentedOut') -- must never appear as a contract

local function pickEventName()
    return 'fixture:computed'
end
RegisterNetEvent(pickEventName())

TriggerServerEvent('fixture:doThing', 1, 2)

local answer = lib.callback.await('fixture:askServer', false, 42)
