--========================================================
-- nvCloth – cm-core server helpers
--========================================================

-- Replicate FiveM's native empty-head opt-in to every capturing client. This is
-- equivalent to entering `allowEmptyHeadDrawable true` in F8, but does not require
-- each clothing admin to set it manually before a batch.
SetConvarReplicated('allowEmptyHeadDrawable', 'true')

function getAccountMoney(src, account)
  -- cm-core only exposes RemoveMoney for payment in this setup.
  -- Return a high value so old balance-check code cannot block; sv_cloth.lua uses RemoveMoney directly.
  return 999999999
end

function removeAccountMoney(src, account, amount)
  amount = tonumber(amount) or 0
  if amount <= 0 then return true end
  return exports['cm-core']:RemoveMoney(src, account or 'bank', amount) == true
end

function sendNotification(src, msg, msgType)
  TriggerClientEvent('cm-hud:client:notify', src, tostring(msg or ''), msgType or 'info')
end

function getPlayerIdentifier(src)
  local state = Player(src).state
  return tostring(state.charId or state.characterId or state.character_id or state.citizenid or src)
end

RegisterServerEvent('nvCloth:save')
AddEventHandler('nvCloth:save', function(_skin)
  -- Clothing purchases no longer save appearance directly.
  -- Appearance is saved only when a clothing inventory item is used.
end)
