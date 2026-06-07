-- cm-characters/server/bridge.lua
-- This connects cm-auth login to the character selector

-- Export function that cm-auth should call after successful login
exports('OpenCharacterSelector', function(src, accountId)
    TriggerClientEvent('cm-characters:client:openSelector', src, accountId)
end)

-- Alternative: test command to manually open selector
-- Usage: /char [accountId]
-- If no accountId provided, it tries to get it from cm-core state
RegisterCommand('char', function(source, args)
    local src = source
    local accountId = args[1] and tostring(args[1]) or Player(src).state.accountId
    
    if not accountId then
        TriggerClientEvent('chat:addMessage', src, {
            color = {255, 0, 0},
            args = {'[CM-CHARACTERS]', 'No accountId. Usage: /char [accountId]'}
        })
        return
    end
    
    -- FIX: Make sure state is set before opening
    Player(src).state:set('accountId', accountId, true)
    
    print('[CM-CHARACTERS] Manual /char command for account ' .. accountId)
    TriggerClientEvent('cm-characters:client:openSelector', src, accountId)
    
    TriggerClientEvent('chat:addMessage', src, {
        color = {0, 255, 0},
        args = {'[CM-CHARACTERS]', 'Opening selector for account ' .. accountId}
    })
end, false)

-- Auto-open on first spawn (fallback if cm-auth doesn't trigger it)
-- Remove this if cm-auth handles it properly
AddEventHandler('playerSpawned', function()
    local src = source
    -- Wait a bit for cm-auth to do its thing first
    SetTimeout(3000, function()
        local accountId = Player(src).state.accountId
        local isLoggedIn = Player(src).state.isLoggedIn
        local charId = Player(src).state.charId
        
        -- Only open if logged in but no character selected yet
        if accountId and isLoggedIn and not charId then
            TriggerClientEvent('cm-characters:client:openSelector', src, accountId)
        end
    end)
end)