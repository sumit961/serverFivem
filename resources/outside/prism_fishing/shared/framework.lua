Framework = {}
Core = nil
if GetResourceState('es_extended') == 'started' then
    Framework.IsESX = true
    Core = exports['es_extended']:getSharedObject()
elseif GetResourceState('qb-core') == 'started' or GetResourceState('qbx_core') == 'started' then
    Framework.IsQB = true
    Core = exports['qb-core']:GetCoreObject()
else
    Framework.IsESX = false
    Framework.IsQB = false
end

local Framework = (Framework.IsESX and 'ESX') or (Framework.IsQB and 'QB') or 'Standalone'
debugPrint('Framework Loaded ' .. Framework)
