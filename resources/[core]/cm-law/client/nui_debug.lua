-- Development-only NUI visibility diagnostic (see AGENTS.md "police NPC
-- proximity" hotfix). Dumps window.cmLawNuiSnapshot() from html/index.html
-- to this client's own F8 console so a full-screen paint regression can be
-- pinpointed without browser dev tools. Reports only local UI DOM state
-- (visibility/background/class of NUI elements) -- no player, server or
-- permission data. Not registered as an ACE-restricted command because it
-- exposes nothing beyond this client's own screen state.

RegisterNUICallback('cmLawNuiDebugDump', function(data, cb)
    print('[cm-law nui debug] ' .. json.encode(data or {}, { indent = true }))
    cb({ ok = true })
end)

RegisterCommand('cmnuidebug', function()
    SendNUIMessage({ action = 'cmNuiDebugDump' })
end, false)
