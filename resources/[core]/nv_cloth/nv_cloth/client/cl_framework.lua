--========================================================
-- nvCloth – cm-core client helpers
--========================================================

loaded = true

function showNotification(msg, msgType)
  TriggerEvent('cm-hud:client:notify', tostring(msg or ''), msgType or 'info')
end

function showHelpNotification(msg)
  BeginTextCommandDisplayHelp('STRING')
  AddTextComponentSubstringPlayerName(tostring(msg or ''))
  EndTextCommandDisplayHelp(0, false, true, -1)
end

function getPedAppearance()
  local ped = PlayerPedId()

  if Config.AppearanceRessource == 'illenium-appearance' then
    return exports['illenium-appearance']:getPedAppearance(ped)
  elseif Config.AppearanceRessource == 'fivem-appearance' then
    return exports['fivem-appearance']:getPedAppearance(ped)
  elseif Config.AppearanceRessource == 'skinchanger' then
    local p = promise.new()
    TriggerEvent('skinchanger:getSkin', function(skin)
      p:resolve(skin)
    end)
    return Citizen.Await(p)
  end

  return nil
end

function savePedAppearance(appearance)
  local ped = PlayerPedId()

  if Config.AppearanceRessource == 'illenium-appearance' then
    exports['illenium-appearance']:setPedAppearance(ped, appearance)
  elseif Config.AppearanceRessource == 'fivem-appearance' then
    exports['fivem-appearance']:setPedAppearance(ped, appearance)
  elseif Config.AppearanceRessource == 'skinchanger' then
    TriggerEvent('skinchanger:loadSkin', appearance)
  end
end

RegisterNUICallback('getGender', function(_, cb)
  local ped = PlayerPedId()
  local model = GetEntityModel(ped)
  cb({ gender = (model == GetHashKey('mp_m_freemode_01')) and 'male' or 'female' })
end)

RegisterNetEvent('nvCloth:showNotification', function(_icon, msgType, message)
  showNotification(message or msgType or _icon, msgType or 'info')
end)
