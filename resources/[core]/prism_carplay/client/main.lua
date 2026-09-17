

local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1, L11_1, L12_1, L13_1, L14_1, L15_1, L16_1, L17_1, L18_1, L19_1, L20_1, L21_1, L22_1, L23_1, L24_1, L25_1, L26_1, L27_1, L28_1, L29_1, L30_1, L31_1, L32_1, L33_1, L34_1, L35_1, L36_1, L37_1, L38_1, L39_1, L40_1, L41_1, L42_1, L43_1, L44_1, L45_1, L46_1, L47_1, L48_1, L49_1, L50_1, L51_1, L52_1, L53_1
windowsOpen = false
L0_1 = false
L1_1 = false
L2_1 = nil
L3_1 = true
L4_1 = false
L5_1 = false
L6_1 = {}
L7_1 = false
L8_1 = nil
L9_1 = false
L10_1 = nil
function L11_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  if not A0_2 then
    L1_2 = ""
    return L1_2
  end
  L2_2 = A0_2
  L1_2 = A0_2.gsub
  L3_2 = "%s+"
  L4_2 = ""
  return L1_2(L2_2, L3_2, L4_2)
end
function L12_1()
  local L0_2, L1_2, L2_2
  L0_2 = GetClockHours
  L0_2 = L0_2()
  L1_2 = GetClockMinutes
  L1_2 = L1_2()
  L2_2 = {}
  L2_2.hour = L0_2
  L2_2.minute = L1_2
  return L2_2
end
L13_1 = {}
L14_1 = {}
L14_1.min = 30
L14_1.max = 38
L13_1.EXTRASUNNY = L14_1
L14_1 = {}
L14_1.min = 22
L14_1.max = 28
L13_1.CLEAR = L14_1
L14_1 = {}
L14_1.min = 18
L14_1.max = 24
L13_1.CLOUDS = L14_1
L14_1 = {}
L14_1.min = 20
L14_1.max = 26
L13_1.SMOG = L14_1
L14_1 = {}
L14_1.min = 12
L14_1.max = 18
L13_1.FOGGY = L14_1
L14_1 = {}
L14_1.min = 15
L14_1.max = 20
L13_1.OVERCAST = L14_1
L14_1 = {}
L14_1.min = 14
L14_1.max = 18
L13_1.RAIN = L14_1
L14_1 = {}
L14_1.min = 12
L14_1.max = 16
L13_1.THUNDER = L14_1
L14_1 = {}
L14_1.min = 18
L14_1.max = 24
L13_1.CLEARING = L14_1
L14_1 = {}
L14_1.min = 20
L14_1.max = 25
L13_1.NEUTRAL = L14_1
L14_1 = {}
L14_1.min = -5
L14_1.max = 2
L13_1.SNOW = L14_1
L14_1 = {}
L14_1.min = -15
L14_1.max = -5
L13_1.BLIZZARD = L14_1
L14_1 = {}
L14_1.min = -2
L14_1.max = 4
L13_1.SNOWLIGHT = L14_1
L14_1 = {}
L14_1.min = -8
L14_1.max = 0
L13_1.XMAS = L14_1
function L14_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = GetPrevWeatherTypeHashName
  L0_2 = L0_2()
  L1_2 = "CLEAR"
  L2_2 = GetHashKey
  L3_2 = "EXTRASUNNY"
  L2_2 = L2_2(L3_2)
  if L0_2 == L2_2 then
    L1_2 = "EXTRASUNNY"
  else
    L2_2 = GetHashKey
    L3_2 = "CLEAR"
    L2_2 = L2_2(L3_2)
    if L0_2 == L2_2 then
      L1_2 = "CLEAR"
    else
      L2_2 = GetHashKey
      L3_2 = "CLOUDS"
      L2_2 = L2_2(L3_2)
      if L0_2 == L2_2 then
        L1_2 = "CLOUDS"
      else
        L2_2 = GetHashKey
        L3_2 = "SMOG"
        L2_2 = L2_2(L3_2)
        if L0_2 == L2_2 then
          L1_2 = "SMOG"
        else
          L2_2 = GetHashKey
          L3_2 = "FOGGY"
          L2_2 = L2_2(L3_2)
          if L0_2 == L2_2 then
            L1_2 = "FOGGY"
          else
            L2_2 = GetHashKey
            L3_2 = "OVERCAST"
            L2_2 = L2_2(L3_2)
            if L0_2 == L2_2 then
              L1_2 = "OVERCAST"
            else
              L2_2 = GetHashKey
              L3_2 = "RAIN"
              L2_2 = L2_2(L3_2)
              if L0_2 == L2_2 then
                L1_2 = "RAIN"
              else
                L2_2 = GetHashKey
                L3_2 = "THUNDER"
                L2_2 = L2_2(L3_2)
                if L0_2 == L2_2 then
                  L1_2 = "THUNDER"
                else
                  L2_2 = GetHashKey
                  L3_2 = "CLEARING"
                  L2_2 = L2_2(L3_2)
                  if L0_2 == L2_2 then
                    L1_2 = "CLEARING"
                  else
                    L2_2 = GetHashKey
                    L3_2 = "NEUTRAL"
                    L2_2 = L2_2(L3_2)
                    if L0_2 == L2_2 then
                      L1_2 = "NEUTRAL"
                    else
                      L2_2 = GetHashKey
                      L3_2 = "SNOW"
                      L2_2 = L2_2(L3_2)
                      if L0_2 == L2_2 then
                        L1_2 = "SNOW"
                      else
                        L2_2 = GetHashKey
                        L3_2 = "BLIZZARD"
                        L2_2 = L2_2(L3_2)
                        if L0_2 == L2_2 then
                          L1_2 = "BLIZZARD"
                        else
                          L2_2 = GetHashKey
                          L3_2 = "SNOWLIGHT"
                          L2_2 = L2_2(L3_2)
                          if L0_2 == L2_2 then
                            L1_2 = "SNOWLIGHT"
                          else
                            L2_2 = GetHashKey
                            L3_2 = "XMAS"
                            L2_2 = L2_2(L3_2)
                            if L0_2 == L2_2 then
                              L1_2 = "XMAS"
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  L2_2 = L13_1
  L2_2 = L2_2[L1_2]
  if not L2_2 then
    L2_2 = {}
    L2_2.min = 20
    L2_2.max = 25
  end
  L3_2 = math
  L3_2 = L3_2.random
  L4_2 = L2_2.min
  L5_2 = L2_2.max
  L3_2 = L3_2(L4_2, L5_2)
  L4_2 = {}
  L4_2.type = L1_2
  L4_2.temperature = L3_2
  return L4_2
end
function L15_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = PlayerPedId
  L0_2 = L0_2()
  L1_2 = GetEntityCoords
  L2_2 = L0_2
  L1_2 = L1_2(L2_2)
  L2_2 = GetEntityHeading
  L3_2 = L0_2
  L2_2 = L2_2(L3_2)
  L3_2 = {}
  L4_2 = L1_2.x
  L3_2.x = L4_2
  L4_2 = L1_2.y
  L3_2.y = L4_2
  L4_2 = L1_2.z
  L3_2.z = L4_2
  L3_2.heading = L2_2
  return L3_2
end
function L16_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L0_2 = IsWaypointActive
  L0_2 = L0_2()
  if not L0_2 then
    L0_2 = nil
    return L0_2
  end
  L0_2 = PlayerPedId
  L0_2 = L0_2()
  L1_2 = GetEntityCoords
  L2_2 = L0_2
  L1_2 = L1_2(L2_2)
  L2_2 = GetFirstBlipInfoId
  L3_2 = 8
  L2_2 = L2_2(L3_2)
  L3_2 = DoesBlipExist
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    L3_2 = nil
    return L3_2
  end
  L3_2 = GetBlipInfoIdCoord
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = vector2
  L5_2 = L1_2.x
  L6_2 = L1_2.y
  L4_2 = L4_2(L5_2, L6_2)
  L5_2 = vector2
  L6_2 = L3_2.x
  L7_2 = L3_2.y
  L5_2 = L5_2(L6_2, L7_2)
  L4_2 = L4_2 - L5_2
  L4_2 = #L4_2
  L5_2 = GetStreetNameAtCoord
  L6_2 = L3_2.x
  L7_2 = L3_2.y
  L8_2 = L3_2.z
  L5_2, L6_2 = L5_2(L6_2, L7_2, L8_2)
  L7_2 = GetStreetNameFromHashKey
  L8_2 = L5_2
  L7_2 = L7_2(L8_2)
  L8_2 = GetStreetNameFromHashKey
  L9_2 = L6_2
  L8_2 = L8_2(L9_2)
  L9_2 = L7_2
  if L8_2 and "" ~= L8_2 then
    L10_2 = L7_2
    L11_2 = " / "
    L12_2 = L8_2
    L10_2 = L10_2 .. L11_2 .. L12_2
    L9_2 = L10_2
  end
  L10_2 = {}
  L10_2.active = true
  L11_2 = L3_2.x
  L10_2.x = L11_2
  L11_2 = L3_2.y
  L10_2.y = L11_2
  L11_2 = L3_2.z
  L10_2.z = L11_2
  L11_2 = math
  L11_2 = L11_2.floor
  L12_2 = L4_2
  L11_2 = L11_2(L12_2)
  L10_2.distance = L11_2
  L10_2.streetName = L9_2
  return L10_2
end
L17_1 = nil
L18_1 = nil
function L19_1()
  local L0_2, L1_2
  L0_2 = L17_1
  if L0_2 then
    L0_2 = UnregisterPedheadshot
    L1_2 = L17_1
    L0_2(L1_2)
    L0_2 = nil
    L17_1 = L0_2
    L0_2 = nil
    L18_1 = L0_2
  end
end
function L20_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = PlayerId
  L2_2 = L2_2()
  L3_2 = GetPlayerName
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = nil
  L5_2 = GetVehiclePedIsIn
  L6_2 = L1_2
  L7_2 = false
  L5_2 = L5_2(L6_2, L7_2)
  if 0 ~= L5_2 then
    L6_2 = GetVehicleNumberPlateText
    L7_2 = L5_2
    L6_2 = L6_2(L7_2)
    L4_2 = L6_2
  end
  L6_2 = L17_1
  if L6_2 then
    L6_2 = IsPedheadshotValid
    L7_2 = L17_1
    L6_2 = L6_2(L7_2)
    if L6_2 then
      L6_2 = L18_1
      if L6_2 then
        L6_2 = A0_2
        L7_2 = {}
        L7_2.name = L3_2
        L8_2 = L18_1
        L7_2.mugshot = L8_2
        L7_2.vehiclePlate = L4_2
        L6_2(L7_2)
        return
      end
    end
  end
  L6_2 = L17_1
  if L6_2 then
    L6_2 = UnregisterPedheadshot
    L7_2 = L17_1
    L6_2(L7_2)
    L6_2 = nil
    L17_1 = L6_2
    L6_2 = nil
    L18_1 = L6_2
  end
  L6_2 = RegisterPedheadshot
  L7_2 = L1_2
  L6_2 = L6_2(L7_2)
  L17_1 = L6_2
  L7_2 = CreateThread
  function L8_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3
    L0_3 = 0
    while true do
      L1_3 = IsPedheadshotReady
      L2_3 = L6_2
      L1_3 = L1_3(L2_3)
      if not (not L1_3 and L0_3 < 100) then
        break
      end
      L1_3 = Wait
      L2_3 = 50
      L1_3(L2_3)
      L0_3 = L0_3 + 1
    end
    L1_3 = nil
    L2_3 = IsPedheadshotReady
    L3_3 = L6_2
    L2_3 = L2_3(L3_3)
    if L2_3 then
      L2_3 = GetPedheadshotTxdString
      L3_3 = L6_2
      L2_3 = L2_3(L3_3)
      L1_3 = L2_3
      L18_1 = L1_3
    end
    L2_3 = A0_2
    L3_3 = {}
    L4_3 = L3_2
    L3_3.name = L4_3
    L3_3.mugshot = L1_3
    L4_3 = L4_2
    L3_3.vehiclePlate = L4_3
    L2_3(L3_3)
  end
  L7_2(L8_2)
end
function L21_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L0_1 = A0_2
  L2_2 = A0_2
  if false == A1_2 then
    L2_2 = false
  end
  L3_2 = SetNuiFocus
  L4_2 = A0_2
  L5_2 = L2_2
  L3_2(L4_2, L5_2)
  L3_2 = SendNUIMessage
  L4_2 = {}
  L4_2.action = "setVisible"
  L4_2.data = A0_2
  L3_2(L4_2)
end
function L22_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = print
  L2_2 = L0_1
  L3_2 = L1_1
  L4_2 = A0_2
  L1_2(L2_2, L3_2, L4_2)
  L1_2 = L0_1
  if L1_2 then
    L1_2 = SetNuiFocus
    L2_2 = true
    L3_2 = true
    L1_2(L2_2, L3_2)
    L1_2 = SetNuiFocusKeepInput
    L2_2 = nil ~= A0_2 and true == A0_2
    L1_2(L2_2)
  end
end
function L23_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L0_2 = PlayerPedId
  L0_2 = L0_2()
  L1_2 = GetVehiclePedIsIn
  L2_2 = L0_2
  L3_2 = false
  L1_2 = L1_2(L2_2, L3_2)
  if 0 == L1_2 then
    L2_2 = Config
    L2_2 = L2_2.Notify
    L3_2 = "You must be in a vehicle to use CarPlay"
    L4_2 = "error"
    L2_2(L3_2, L4_2)
    return
  end
  L2_2 = Config
  L2_2 = L2_2.RequireCarplayItem
  if L2_2 then
    L2_2 = L5_1
    if not L2_2 then
      L2_2 = Config
      L2_2 = L2_2.Notify
      L3_2 = "This vehicle does not have CarPlay installed"
      L4_2 = "error"
      L2_2(L3_2, L4_2)
      return
    end
  end
  L2_2 = L0_1
  if not L2_2 then
    L2_2 = SendNUIMessage
    L3_2 = {}
    L3_2.action = "updatePrimaryColor"
    L4_2 = Config
    L4_2 = L4_2.PrimaryColor
    L3_2.data = L4_2
    L2_2(L3_2)
    L2_2 = SendNUIMessage
    L3_2 = {}
    L3_2.action = "setLocale"
    L4_2 = GetLocaleTable
    L4_2 = L4_2()
    L3_2.data = L4_2
    L2_2(L3_2)
    L2_2 = L15_1
    L2_2 = L2_2()
    L3_2 = SendNUIMessage
    L4_2 = {}
    L4_2.action = "updatePlayerPosition"
    L4_2.data = L2_2
    L3_2(L4_2)
    L3_2 = L12_1
    L3_2 = L3_2()
    L4_2 = SendNUIMessage
    L5_2 = {}
    L5_2.action = "updateGameTime"
    L5_2.data = L3_2
    L4_2(L5_2)
    L4_2 = L14_1
    L4_2 = L4_2()
    L5_2 = SendNUIMessage
    L6_2 = {}
    L6_2.action = "updateWeather"
    L6_2.data = L4_2
    L5_2(L6_2)
    L5_2 = L20_1
    function L6_2(A0_3)
      local L1_3, L2_3
      L1_3 = SendNUIMessage
      L2_3 = {}
      L2_3.action = "updatePlayerProfile"
      L2_3.data = A0_3
      L1_3(L2_3)
    end
    L5_2(L6_2)
    L5_2 = L16_1
    L5_2 = L5_2()
    L6_2 = SendNUIMessage
    L7_2 = {}
    L7_2.action = "updateWaypoint"
    L7_2.data = L5_2
    L6_2(L7_2)
    L6_2 = SendNUIMessage
    L7_2 = {}
    L7_2.action = "updateTunerChip"
    L8_2 = L4_1
    L7_2.data = L8_2
    L6_2(L7_2)
    L6_2 = L8_1
    if L6_2 then
      L6_2 = L10_1
      if L6_2 then
        L6_2 = SendNUIMessage
        L7_2 = {}
        L7_2.action = "musicStarted"
        L8_2 = {}
        L9_2 = L10_1
        L8_2.song = L9_2
        L7_2.data = L8_2
        L6_2(L7_2)
      end
    end
    L6_2 = L21_1
    L7_2 = true
    L6_2(L7_2)
  end
end
L24_1 = CreateThread
function L25_1()
  local L0_2, L1_2, L2_2
  while true do
    L0_2 = L0_1
    if L0_2 then
      L0_2 = L15_1
      L0_2 = L0_2()
      L1_2 = SendNUIMessage
      L2_2 = {}
      L2_2.action = "updatePlayerPosition"
      L2_2.data = L0_2
      L1_2(L2_2)
    end
    L0_2 = Wait
    L1_2 = 5000
    L0_2(L1_2)
  end
end
L24_1(L25_1)
L24_1 = CreateThread
function L25_1()
  local L0_2, L1_2, L2_2
  while true do
    L0_2 = L0_1
    if L0_2 then
      L0_2 = L12_1
      L0_2 = L0_2()
      L1_2 = SendNUIMessage
      L2_2 = {}
      L2_2.action = "updateGameTime"
      L2_2.data = L0_2
      L1_2(L2_2)
    end
    L0_2 = Wait
    L1_2 = 1000
    L0_2(L1_2)
  end
end
L24_1(L25_1)
L24_1 = CreateThread
function L25_1()
  local L0_2, L1_2, L2_2
  while true do
    L0_2 = L0_1
    if L0_2 then
      L0_2 = L14_1
      L0_2 = L0_2()
      L1_2 = SendNUIMessage
      L2_2 = {}
      L2_2.action = "updateWeather"
      L2_2.data = L0_2
      L1_2(L2_2)
    end
    L0_2 = Wait
    L1_2 = 30000
    L0_2(L1_2)
  end
end
L24_1(L25_1)
L24_1 = CreateThread
function L25_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  while true do
    L0_2 = L0_1
    if L0_2 then
      L0_2 = PlayerPedId
      L0_2 = L0_2()
      L1_2 = GetVehiclePedIsIn
      L2_2 = L0_2
      L3_2 = false
      L1_2 = L1_2(L2_2, L3_2)
      L2_2 = nil
      if 0 ~= L1_2 then
        L3_2 = GetVehicleNumberPlateText
        L4_2 = L1_2
        L3_2 = L3_2(L4_2)
        L2_2 = L3_2
      end
      L3_2 = SendNUIMessage
      L4_2 = {}
      L4_2.action = "updateVehiclePlate"
      L4_2.data = L2_2
      L3_2(L4_2)
    end
    L0_2 = Wait
    L1_2 = 5000
    L0_2(L1_2)
  end
end
L24_1(L25_1)
L24_1 = CreateThread
function L25_1()
  local L0_2, L1_2, L2_2
  while true do
    L0_2 = L0_1
    if L0_2 then
      L0_2 = L16_1
      L0_2 = L0_2()
      L1_2 = SendNUIMessage
      L2_2 = {}
      L2_2.action = "updateWaypoint"
      L2_2.data = L0_2
      L1_2(L2_2)
    end
    L0_2 = Wait
    L1_2 = 1000
    L0_2(L1_2)
  end
end
L24_1(L25_1)
function L24_1()
  local L0_2, L1_2
  L0_2 = L0_1
  if L0_2 then
    L0_2 = L21_1
    L1_2 = false
    L0_2(L1_2)
  end
end
L25_1 = RegisterCommand
L26_1 = "carplay"
function L27_1()
  local L0_2, L1_2
  L0_2 = L23_1
  L0_2()
end
L28_1 = false
L25_1(L26_1, L27_1, L28_1)
L25_1 = RegisterKeyMapping
L26_1 = "carplay"
L27_1 = "Open CarPlay"
L28_1 = "keyboard"
L29_1 = Config
L29_1 = L29_1.Keybind
L25_1(L26_1, L27_1, L28_1, L29_1)
L25_1 = RegisterNUICallback
L26_1 = "closeMenu"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = L24_1
  L2_2()
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "setWaypoint"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = A0_2.x
  if L2_2 then
    L2_2 = A0_2.y
    if L2_2 then
      L2_2 = SetNewWaypoint
      L3_2 = A0_2.x
      L4_2 = A0_2.y
      L2_2(L3_2, L4_2)
    end
  end
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "toggleDoors"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.open
    if L4_2 then
      L4_2 = 0
      L5_2 = 3
      L6_2 = 1
      for L7_2 = L4_2, L5_2, L6_2 do
        L8_2 = SetVehicleDoorOpen
        L9_2 = L3_2
        L10_2 = L7_2
        L11_2 = false
        L12_2 = false
        L8_2(L9_2, L10_2, L11_2, L12_2)
      end
    else
      L4_2 = SetVehicleDoorsShut
      L5_2 = L3_2
      L6_2 = false
      L4_2(L5_2, L6_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "toggleTrunk"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = GetNumberOfVehicleDoors
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    L5_2 = L4_2 - 1
    L6_2 = A0_2.open
    if L6_2 then
      L6_2 = SetVehicleDoorOpen
      L7_2 = L3_2
      L8_2 = L5_2
      L9_2 = false
      L10_2 = false
      L6_2(L7_2, L8_2, L9_2, L10_2)
    else
      L6_2 = SetVehicleDoorShut
      L7_2 = L3_2
      L8_2 = L5_2
      L9_2 = false
      L6_2(L7_2, L8_2, L9_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "toggleSeatbelt"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = Config
  L2_2 = L2_2.ToggleSeatbelt
  L3_2 = A0_2.on
  L2_2(L3_2)
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "toggleWindows"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.down
    if L4_2 then
      L4_2 = RollDownWindows
      L5_2 = L3_2
      L4_2(L5_2)
      windowsOpen = true
    else
      L4_2 = RollUpWindow
      L5_2 = L3_2
      L6_2 = 0
      L4_2(L5_2, L6_2)
      L4_2 = RollUpWindow
      L5_2 = L3_2
      L6_2 = 1
      L4_2(L5_2, L6_2)
      L4_2 = RollUpWindow
      L5_2 = L3_2
      L6_2 = 2
      L4_2(L5_2, L6_2)
      L4_2 = RollUpWindow
      L5_2 = L3_2
      L6_2 = 3
      L4_2(L5_2, L6_2)
      windowsOpen = false
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "toggleLock"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.locked
    if L4_2 then
      L4_2 = SetVehicleDoorsLocked
      L5_2 = L3_2
      L6_2 = 2
      L4_2(L5_2, L6_2)
    else
      L4_2 = SetVehicleDoorsLocked
      L5_2 = L3_2
      L6_2 = 1
      L4_2(L5_2, L6_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "toggleEngine"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.on
    if L4_2 then
      L4_2 = SetVehicleEngineOn
      L5_2 = L3_2
      L6_2 = true
      L7_2 = false
      L8_2 = true
      L4_2(L5_2, L6_2, L7_2, L8_2)
    else
      L4_2 = SetVehicleEngineOn
      L5_2 = L3_2
      L6_2 = false
      L7_2 = false
      L8_2 = true
      L4_2(L5_2, L6_2, L7_2, L8_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "toggleLights"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.on
    if L4_2 then
      L4_2 = SetVehicleLights
      L5_2 = L3_2
      L6_2 = 2
      L4_2(L5_2, L6_2)
    else
      L4_2 = SetVehicleLights
      L5_2 = L3_2
      L6_2 = 1
      L4_2(L5_2, L6_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "toggleDoor"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.door
    L5_2 = A0_2.open
    if L5_2 then
      L5_2 = SetVehicleDoorOpen
      L6_2 = L3_2
      L7_2 = L4_2
      L8_2 = false
      L9_2 = false
      L5_2(L6_2, L7_2, L8_2, L9_2)
    else
      L5_2 = SetVehicleDoorShut
      L6_2 = L3_2
      L7_2 = L4_2
      L8_2 = false
      L5_2(L6_2, L7_2, L8_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "selectSeat"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.seat
    L5_2 = L4_2 - 1
    L6_2 = IsVehicleSeatFree
    L7_2 = L3_2
    L8_2 = L5_2
    L6_2 = L6_2(L7_2, L8_2)
    if L6_2 then
      L6_2 = SetPedIntoVehicle
      L7_2 = L2_2
      L8_2 = L3_2
      L9_2 = L5_2
      L6_2(L7_2, L8_2, L9_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L25_1(L26_1, L27_1)
L25_1 = RegisterNUICallback
L26_1 = "getVehicleInfo"
function L27_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = GetVehicleHandlingFloat
    L5_2 = L3_2
    L6_2 = "CHandlingData"
    L7_2 = "fDriveBiasFront"
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    L5_2 = "AWD"
    L6_2 = 0.6
    if L4_2 >= L6_2 then
      L5_2 = "FWD"
    else
      L6_2 = 0.4
      if L4_2 <= L6_2 then
        L5_2 = "RWD"
      end
    end
    L6_2 = GetVehicleFuelLevel
    L7_2 = L3_2
    L6_2 = L6_2(L7_2)
    L7_2 = math
    L7_2 = L7_2.floor
    L8_2 = GetVehicleEngineHealth
    L9_2 = L3_2
    L8_2 = L8_2(L9_2)
    L8_2 = L8_2 / 10
    L7_2 = L7_2(L8_2)
    if L7_2 < 0 then
      L7_2 = 0
    end
    if L7_2 > 100 then
      L7_2 = 100
    end
    L8_2 = math
    L8_2 = L8_2.floor
    L9_2 = GetVehicleBodyHealth
    L10_2 = L3_2
    L9_2 = L9_2(L10_2)
    L9_2 = L9_2 / 10
    L8_2 = L8_2(L9_2)
    if L8_2 < 0 then
      L8_2 = 0
    end
    if L8_2 > 100 then
      L8_2 = 100
    end
    L9_2 = GetVehicleNumberOfWheels
    L10_2 = L3_2
    L9_2 = L9_2(L10_2)
    L10_2 = 0
    L11_2 = 0
    L12_2 = L9_2 - 1
    L13_2 = 1
    for L14_2 = L11_2, L12_2, L13_2 do
      L15_2 = GetVehicleWheelHealth
      L16_2 = L3_2
      L17_2 = L14_2
      L15_2 = L15_2(L16_2, L17_2)
      L10_2 = L10_2 + L15_2
    end
    L11_2 = math
    L11_2 = L11_2.floor
    L12_2 = L10_2 / L9_2
    L12_2 = L12_2 / 10
    L11_2 = L11_2(L12_2)
    if L11_2 < 0 then
      L11_2 = 0
    end
    if L11_2 > 100 then
      L11_2 = 100
    end
    L12_2 = 70
    L13_2 = GetIsVehicleEngineRunning
    L14_2 = L3_2
    L13_2 = L13_2(L14_2)
    if not L13_2 then
      L12_2 = 25
    else
      L13_2 = math
      L13_2 = L13_2.floor
      L14_2 = 100
      L14_2 = L14_2 - L7_2
      L14_2 = L14_2 * 0.5
      L13_2 = L13_2(L14_2)
      L12_2 = 70 + L13_2
    end
    L13_2 = A1_2
    L14_2 = {}
    L14_2.drivetrain = L5_2
    L14_2.driveBias = L4_2
    L14_2.fuelLevel = L6_2
    L14_2.engineHealth = L7_2
    L14_2.bodyHealth = L8_2
    L14_2.tireHealth = L11_2
    L14_2.engineTemp = L12_2
    L13_2(L14_2)
  else
    L4_2 = A1_2
    L5_2 = {}
    L5_2.drivetrain = "N/A"
    L5_2.driveBias = 0
    L5_2.fuelLevel = 0
    L5_2.engineHealth = 0
    L5_2.bodyHealth = 0
    L5_2.tireHealth = 0
    L5_2.engineTemp = 0
    L4_2(L5_2)
  end
end
L25_1(L26_1, L27_1)
L25_1 = {}
function L26_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = L25_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = L25_1
    L2_2 = {}
    L3_2 = GetVehicleHandlingFloat
    L4_2 = A0_2
    L5_2 = "CHandlingData"
    L6_2 = "fInitialDriveMaxFlatVel"
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    L2_2.topSpeed = L3_2
    L3_2 = GetVehicleHandlingFloat
    L4_2 = A0_2
    L5_2 = "CHandlingData"
    L6_2 = "fClutchChangeRateScaleUpShift"
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    L2_2.gearChange = L3_2
    L3_2 = GetVehicleHandlingFloat
    L4_2 = A0_2
    L5_2 = "CHandlingData"
    L6_2 = "fInitialDragCoeff"
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    L2_2.dragCoeff = L3_2
    L3_2 = GetVehicleHandlingFloat
    L4_2 = A0_2
    L5_2 = "CHandlingData"
    L6_2 = "fBrakeForce"
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    L2_2.brakeForce = L3_2
    L1_2[A0_2] = L2_2
  end
  L1_2 = L25_1
  L1_2 = L1_2[A0_2]
  return L1_2
end
L27_1 = {}
L28_1 = {}
function L29_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if not A0_2 or 0 == A0_2 or not A1_2 then
    return
  end
  L2_2 = L26_1
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = A1_2.boostPower
  if L3_2 then
    L3_2 = A1_2.boostPower
    if L3_2 > 0 then
      L3_2 = Config
      L3_2 = L3_2.TunerChip
      L3_2 = L3_2.BoostPower
      L3_2 = L3_2.maxPercent
      L4_2 = L2_2.topSpeed
      L5_2 = A1_2.boostPower
      L5_2 = L5_2 / 100
      L4_2 = L4_2 * L5_2
      L5_2 = L3_2 / 100
      L4_2 = L4_2 * L5_2
      L5_2 = L2_2.topSpeed
      L5_2 = L5_2 + L4_2
      L6_2 = SetVehicleHandlingFloat
      L7_2 = A0_2
      L8_2 = "CHandlingData"
      L9_2 = "fInitialDriveMaxFlatVel"
      L10_2 = L5_2 + 0.0
      L6_2(L7_2, L8_2, L9_2, L10_2)
      L6_2 = ModifyVehicleTopSpeed
      L7_2 = A0_2
      L8_2 = 1.0
      L6_2(L7_2, L8_2)
    end
  end
  L3_2 = A1_2.gearChange
  if L3_2 then
    L3_2 = A1_2.gearChange
    if L3_2 > 0 then
      L3_2 = Config
      L3_2 = L3_2.TunerChip
      L3_2 = L3_2.GearChange
      L3_2 = L3_2.maxPercent
      L4_2 = L2_2.gearChange
      L5_2 = A1_2.gearChange
      L5_2 = L5_2 / 100
      L4_2 = L4_2 * L5_2
      L5_2 = L3_2 / 100
      L4_2 = L4_2 * L5_2
      L5_2 = L2_2.gearChange
      L5_2 = L5_2 + L4_2
      L6_2 = SetVehicleHandlingFloat
      L7_2 = A0_2
      L8_2 = "CHandlingData"
      L9_2 = "fClutchChangeRateScaleUpShift"
      L10_2 = L5_2 + 0.0
      L6_2(L7_2, L8_2, L9_2, L10_2)
    end
  end
  L3_2 = A1_2.acceleration
  if L3_2 then
    L3_2 = A1_2.acceleration
    if L3_2 > 0 then
      L3_2 = Config
      L3_2 = L3_2.TunerChip
      L3_2 = L3_2.Acceleration
      L3_2 = L3_2.maxPercent
      L4_2 = L2_2.dragCoeff
      L5_2 = A1_2.acceleration
      L5_2 = L5_2 / 100
      L4_2 = L4_2 * L5_2
      L5_2 = L3_2 / 100
      L4_2 = L4_2 * L5_2
      L5_2 = L2_2.dragCoeff
      L5_2 = L5_2 - L4_2
      L6_2 = SetVehicleHandlingFloat
      L7_2 = A0_2
      L8_2 = "CHandlingData"
      L9_2 = "fInitialDragCoeff"
      L10_2 = L5_2 + 0.0
      L6_2(L7_2, L8_2, L9_2, L10_2)
    end
  end
  L3_2 = A1_2.brakes
  if L3_2 then
    L3_2 = A1_2.brakes
    if L3_2 > 0 then
      L3_2 = Config
      L3_2 = L3_2.TunerChip
      L3_2 = L3_2.Brakes
      L3_2 = L3_2.maxPercent
      L4_2 = L2_2.brakeForce
      L5_2 = A1_2.brakes
      L5_2 = L5_2 / 100
      L4_2 = L4_2 * L5_2
      L5_2 = L3_2 / 100
      L4_2 = L4_2 * L5_2
      L5_2 = L2_2.brakeForce
      L5_2 = L5_2 + L4_2
      L6_2 = SetVehicleHandlingFloat
      L7_2 = A0_2
      L8_2 = "CHandlingData"
      L9_2 = "fBrakeForce"
      L10_2 = L5_2 + 0.0
      L6_2(L7_2, L8_2, L9_2, L10_2)
    end
  end
end
L30_1 = RegisterNetEvent
L31_1 = "prism-carplay:client:receiveTunerChipData"
function L32_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = L27_1
  L2_2[A0_2] = A1_2
  L2_2 = L28_1
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L2_2 = L28_1
    L2_2 = L2_2[A0_2]
    L3_2 = L28_1
    L3_2[A0_2] = nil
    if A1_2 then
      L3_2 = L2_2
      L4_2 = {}
      L5_2 = A1_2.boostPower
      if not L5_2 then
        L5_2 = 0
      end
      L4_2.boostPower = L5_2
      L5_2 = A1_2.gearChange
      if not L5_2 then
        L5_2 = 0
      end
      L4_2.gearChange = L5_2
      L5_2 = A1_2.acceleration
      if not L5_2 then
        L5_2 = 0
      end
      L4_2.acceleration = L5_2
      L5_2 = A1_2.brakes
      if not L5_2 then
        L5_2 = 0
      end
      L4_2.brakes = L5_2
      L3_2(L4_2)
    else
      L3_2 = L2_2
      L4_2 = {}
      L4_2.boostPower = 0
      L4_2.gearChange = 0
      L4_2.acceleration = 0
      L4_2.brakes = 0
      L3_2(L4_2)
    end
  end
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    if L4_2 == A0_2 then
      if A1_2 then
        L5_2 = A1_2.installed
        if L5_2 then
          goto lbl_67
        end
      end
      L5_2 = false
      ::lbl_67::
      L4_1 = L5_2
      L5_2 = SendNUIMessage
      L6_2 = {}
      L6_2.action = "updateTunerChip"
      L7_2 = L4_1
      L6_2.data = L7_2
      L5_2(L6_2)
      if A1_2 then
        L5_2 = L29_1
        L6_2 = L3_2
        L7_2 = A1_2
        L5_2(L6_2, L7_2)
      end
    end
  end
end
L30_1(L31_1, L32_1)
L30_1 = RegisterNetEvent
L31_1 = "prism-carplay:client:tunerChipDataUpdated"
function L32_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = L27_1
  L2_2[A0_2] = A1_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2)
    if L4_2 == A0_2 then
      L5_2 = L4_1
      if A1_2 then
        L6_2 = A1_2.installed
        if L6_2 then
          goto lbl_25
        end
      end
      L6_2 = false
      ::lbl_25::
      L4_1 = L6_2
      L6_2 = SendNUIMessage
      L7_2 = {}
      L7_2.action = "updateTunerChip"
      L8_2 = L4_1
      L7_2.data = L8_2
      L6_2(L7_2)
      if L5_2 then
        L6_2 = L4_1
        if not L6_2 then
          L6_2 = SendNUIMessage
          L7_2 = {}
          L7_2.action = "navigateHome"
          L6_2(L7_2)
        end
      end
      if A1_2 then
        L6_2 = L29_1
        L7_2 = L3_2
        L8_2 = A1_2
        L6_2(L7_2, L8_2)
      end
    end
  end
end
L30_1(L31_1, L32_1)
function L30_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  if not A0_2 or 0 == A0_2 then
    return
  end
  L1_2 = L26_1
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if L1_2 then
    L2_2 = SetVehicleHandlingFloat
    L3_2 = A0_2
    L4_2 = "CHandlingData"
    L5_2 = "fInitialDriveMaxFlatVel"
    L6_2 = L1_2.topSpeed
    L6_2 = L6_2 + 0.0
    L2_2(L3_2, L4_2, L5_2, L6_2)
    L2_2 = ModifyVehicleTopSpeed
    L3_2 = A0_2
    L4_2 = 1.0
    L2_2(L3_2, L4_2)
    L2_2 = SetVehicleHandlingFloat
    L3_2 = A0_2
    L4_2 = "CHandlingData"
    L5_2 = "fClutchChangeRateScaleUpShift"
    L6_2 = L1_2.gearChange
    L6_2 = L6_2 + 0.0
    L2_2(L3_2, L4_2, L5_2, L6_2)
    L2_2 = SetVehicleHandlingFloat
    L3_2 = A0_2
    L4_2 = "CHandlingData"
    L5_2 = "fInitialDragCoeff"
    L6_2 = L1_2.dragCoeff
    L6_2 = L6_2 + 0.0
    L2_2(L3_2, L4_2, L5_2, L6_2)
    L2_2 = SetVehicleHandlingFloat
    L3_2 = A0_2
    L4_2 = "CHandlingData"
    L5_2 = "fBrakeForce"
    L6_2 = L1_2.brakeForce
    L6_2 = L6_2 + 0.0
    L2_2(L3_2, L4_2, L5_2, L6_2)
  end
end
L31_1 = RegisterNetEvent
L32_1 = "prism-carplay:client:useCarplayItem"
function L33_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L0_2 = PlayerPedId
  L0_2 = L0_2()
  L1_2 = GetVehiclePedIsIn
  L2_2 = L0_2
  L3_2 = false
  L1_2 = L1_2(L2_2, L3_2)
  if 0 == L1_2 then
    L2_2 = Config
    L2_2 = L2_2.Notify
    L3_2 = "You must be in a vehicle to install CarPlay"
    L4_2 = "error"
    L2_2(L3_2, L4_2)
    return
  end
  L2_2 = L11_1
  L3_2 = GetVehicleNumberPlateText
  L4_2 = L1_2
  L3_2, L4_2, L5_2, L6_2, L7_2, L8_2 = L3_2(L4_2)
  L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2)
  L3_2 = L6_1
  L3_2 = L3_2[L2_2]
  if not L3_2 then
    L3_2 = false
  end
  L4_2 = not L3_2
  L5_2 = L6_1
  L5_2[L2_2] = L4_2
  L5_1 = L4_2
  L5_2 = TriggerServerEvent
  L6_2 = "prism-carplay:server:saveCarplayInstalled"
  L7_2 = L2_2
  L8_2 = L4_2
  L5_2(L6_2, L7_2, L8_2)
  if L4_2 then
    L5_2 = Config
    L5_2 = L5_2.Notify
    L6_2 = "CarPlay installed in this vehicle"
    L7_2 = "success"
    L5_2(L6_2, L7_2)
  else
    L5_2 = Config
    L5_2 = L5_2.Notify
    L6_2 = "CarPlay removed from this vehicle"
    L7_2 = "info"
    L5_2(L6_2, L7_2)
    L5_2 = L0_1
    if L5_2 then
      L5_2 = SetNuiFocus
      L6_2 = false
      L7_2 = false
      L5_2(L6_2, L7_2)
      L5_2 = SendNUIMessage
      L6_2 = {}
      L6_2.action = "setVisible"
      L6_2.data = false
      L5_2(L6_2)
      L5_2 = false
      L0_1 = L5_2
    end
  end
end
L31_1(L32_1, L33_1)
L31_1 = RegisterNetEvent
L32_1 = "prism-carplay:client:receiveCarplayInstalled"
function L33_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = L6_1
  L3_2 = true == A1_2
  L2_2[A0_2] = L3_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2)
    if L4_2 == A0_2 then
      L5_2 = true == A1_2
      L5_1 = L5_2
    end
  end
end
L31_1(L32_1, L33_1)
L31_1 = RegisterNetEvent
L32_1 = "prism-carplay:client:carplayInstalledUpdated"
function L33_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = L6_1
  L3_2 = true == A1_2
  L2_2[A0_2] = L3_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2)
    if L4_2 == A0_2 then
      L5_2 = true == A1_2
      L5_1 = L5_2
    end
  end
end
L31_1(L32_1, L33_1)
L31_1 = RegisterNetEvent
L32_1 = "prism-carplay:client:useTunerChip"
function L33_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L0_2 = PlayerPedId
  L0_2 = L0_2()
  L1_2 = GetVehiclePedIsIn
  L2_2 = L0_2
  L3_2 = false
  L1_2 = L1_2(L2_2, L3_2)
  if 0 == L1_2 then
    L2_2 = Config
    L2_2 = L2_2.Notify
    L3_2 = "You must be in a vehicle to install a tuner chip"
    L4_2 = "error"
    L2_2(L3_2, L4_2)
    return
  end
  L2_2 = L11_1
  L3_2 = GetVehicleNumberPlateText
  L4_2 = L1_2
  L3_2, L4_2, L5_2, L6_2, L7_2 = L3_2(L4_2)
  L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2, L7_2)
  L3_2 = L27_1
  L3_2 = L3_2[L2_2]
  if not L3_2 then
    L3_2 = {}
  end
  L4_2 = L3_2.installed
  L4_2 = not L4_2
  L3_2.installed = L4_2
  L4_2 = L3_2.installed
  if not L4_2 then
    L3_2.boostPower = 0
    L3_2.gearChange = 0
    L3_2.acceleration = 0
    L3_2.brakes = 0
    L4_2 = L30_1
    L5_2 = L1_2
    L4_2(L5_2)
  end
  L4_2 = L27_1
  L4_2[L2_2] = L3_2
  L4_2 = TriggerServerEvent
  L5_2 = "prism-carplay:server:saveTunerChipData"
  L6_2 = L2_2
  L7_2 = L3_2
  L4_2(L5_2, L6_2, L7_2)
  L4_2 = L3_2.installed
  L4_1 = L4_2
  L4_2 = SendNUIMessage
  L5_2 = {}
  L5_2.action = "updateTunerChip"
  L6_2 = L4_1
  L5_2.data = L6_2
  L4_2(L5_2)
  L4_2 = L4_1
  if L4_2 then
    L4_2 = Config
    L4_2 = L4_2.Notify
    L5_2 = "Tuner Chip Installed - Statistics and Modifications unlocked"
    L6_2 = "success"
    L4_2(L5_2, L6_2)
  else
    L4_2 = SendNUIMessage
    L5_2 = {}
    L5_2.action = "navigateHome"
    L4_2(L5_2)
    L4_2 = Config
    L4_2 = L4_2.Notify
    L5_2 = "Tuner Chip Removed - Statistics and Modifications locked"
    L6_2 = "error"
    L4_2(L5_2, L6_2)
  end
end
L31_1(L32_1, L33_1)
L31_1 = RegisterNUICallback
L32_1 = "removeTunerChip"
function L33_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 == L3_2 then
    L4_2 = A1_2
    L5_2 = {}
    L5_2.success = false
    L4_2(L5_2)
    return
  end
  L4_2 = L11_1
  L5_2 = GetVehicleNumberPlateText
  L6_2 = L3_2
  L5_2, L6_2, L7_2, L8_2, L9_2 = L5_2(L6_2)
  L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2)
  L5_2 = {}
  L5_2.installed = false
  L5_2.boostPower = 0
  L5_2.gearChange = 0
  L5_2.acceleration = 0
  L5_2.brakes = 0
  L6_2 = L27_1
  L6_2[L4_2] = L5_2
  L6_2 = TriggerServerEvent
  L7_2 = "prism-carplay:server:saveTunerChipData"
  L8_2 = L4_2
  L9_2 = L5_2
  L6_2(L7_2, L8_2, L9_2)
  L6_2 = L30_1
  L7_2 = L3_2
  L6_2(L7_2)
  L6_2 = false
  L4_1 = L6_2
  L6_2 = SendNUIMessage
  L7_2 = {}
  L7_2.action = "updateTunerChip"
  L7_2.data = false
  L6_2(L7_2)
  L6_2 = SendNUIMessage
  L7_2 = {}
  L7_2.action = "navigateHome"
  L6_2(L7_2)
  L6_2 = A1_2
  L7_2 = {}
  L7_2.success = true
  L6_2(L7_2)
end
L31_1(L32_1, L33_1)
L31_1 = RegisterNUICallback
L32_1 = "getTunerChipValues"
function L33_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L26_1
    L5_2 = L3_2
    L4_2(L5_2)
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2)
    L5_2 = L27_1
    L5_2 = L5_2[L4_2]
    if L5_2 then
      L5_2 = L27_1
      L5_2 = L5_2[L4_2]
      L6_2 = A1_2
      L7_2 = {}
      L8_2 = L5_2.boostPower
      if not L8_2 then
        L8_2 = 0
      end
      L7_2.boostPower = L8_2
      L8_2 = L5_2.gearChange
      if not L8_2 then
        L8_2 = 0
      end
      L7_2.gearChange = L8_2
      L8_2 = L5_2.acceleration
      if not L8_2 then
        L8_2 = 0
      end
      L7_2.acceleration = L8_2
      L8_2 = L5_2.brakes
      if not L8_2 then
        L8_2 = 0
      end
      L7_2.brakes = L8_2
      L6_2(L7_2)
    else
      L5_2 = L28_1
      L5_2[L4_2] = A1_2
      L5_2 = TriggerServerEvent
      L6_2 = "prism-carplay:server:getTunerChipData"
      L7_2 = L4_2
      L5_2(L6_2, L7_2)
    end
  else
    L4_2 = A1_2
    L5_2 = {}
    L5_2.boostPower = 0
    L5_2.gearChange = 0
    L5_2.acceleration = 0
    L5_2.brakes = 0
    L4_2(L5_2)
  end
end
L31_1(L32_1, L33_1)
L31_1 = RegisterNUICallback
L32_1 = "setTunerChipValue"
function L33_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.type
    if L4_2 then
      L4_2 = A0_2.value
      if L4_2 then
        L4_2 = A0_2.value
        L5_2 = L26_1
        L6_2 = L3_2
        L5_2 = L5_2(L6_2)
        L6_2 = L11_1
        L7_2 = GetVehicleNumberPlateText
        L8_2 = L3_2
        L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2 = L7_2(L8_2)
        L6_2 = L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
        L7_2 = L27_1
        L7_2 = L7_2[L6_2]
        if not L7_2 then
          L7_2 = {}
          L7_2.boostPower = 0
          L7_2.gearChange = 0
          L7_2.acceleration = 0
          L7_2.brakes = 0
          L7_2.installed = true
        end
        L8_2 = A0_2.type
        if "boostPower" == L8_2 then
          L8_2 = Config
          L8_2 = L8_2.TunerChip
          L8_2 = L8_2.BoostPower
          L8_2 = L8_2.maxPercent
          L9_2 = L5_2.topSpeed
          L10_2 = L4_2 / 100
          L9_2 = L9_2 * L10_2
          L10_2 = L8_2 / 100
          L9_2 = L9_2 * L10_2
          L10_2 = L5_2.topSpeed
          L10_2 = L10_2 + L9_2
          L11_2 = SetVehicleHandlingFloat
          L12_2 = L3_2
          L13_2 = "CHandlingData"
          L14_2 = "fInitialDriveMaxFlatVel"
          L15_2 = L10_2 + 0.0
          L11_2(L12_2, L13_2, L14_2, L15_2)
          L11_2 = ModifyVehicleTopSpeed
          L12_2 = L3_2
          L13_2 = 1.0
          L11_2(L12_2, L13_2)
          L7_2.boostPower = L4_2
        else
          L8_2 = A0_2.type
          if "gearChange" == L8_2 then
            L8_2 = Config
            L8_2 = L8_2.TunerChip
            L8_2 = L8_2.GearChange
            L8_2 = L8_2.maxPercent
            L9_2 = L5_2.gearChange
            L10_2 = L4_2 / 100
            L9_2 = L9_2 * L10_2
            L10_2 = L8_2 / 100
            L9_2 = L9_2 * L10_2
            L10_2 = L5_2.gearChange
            L10_2 = L10_2 + L9_2
            L11_2 = SetVehicleHandlingFloat
            L12_2 = L3_2
            L13_2 = "CHandlingData"
            L14_2 = "fClutchChangeRateScaleUpShift"
            L15_2 = L10_2 + 0.0
            L11_2(L12_2, L13_2, L14_2, L15_2)
            L7_2.gearChange = L4_2
          else
            L8_2 = A0_2.type
            if "acceleration" == L8_2 then
              L8_2 = Config
              L8_2 = L8_2.TunerChip
              L8_2 = L8_2.Acceleration
              L8_2 = L8_2.maxPercent
              L9_2 = L5_2.dragCoeff
              L10_2 = L4_2 / 100
              L9_2 = L9_2 * L10_2
              L10_2 = L8_2 / 100
              L9_2 = L9_2 * L10_2
              L10_2 = L5_2.dragCoeff
              L10_2 = L10_2 - L9_2
              L11_2 = SetVehicleHandlingFloat
              L12_2 = L3_2
              L13_2 = "CHandlingData"
              L14_2 = "fInitialDragCoeff"
              L15_2 = L10_2 + 0.0
              L11_2(L12_2, L13_2, L14_2, L15_2)
              L7_2.acceleration = L4_2
            else
              L8_2 = A0_2.type
              if "brakes" == L8_2 then
                L8_2 = Config
                L8_2 = L8_2.TunerChip
                L8_2 = L8_2.Brakes
                L8_2 = L8_2.maxPercent
                L9_2 = L5_2.brakeForce
                L10_2 = L4_2 / 100
                L9_2 = L9_2 * L10_2
                L10_2 = L8_2 / 100
                L9_2 = L9_2 * L10_2
                L10_2 = L5_2.brakeForce
                L10_2 = L10_2 + L9_2
                L11_2 = SetVehicleHandlingFloat
                L12_2 = L3_2
                L13_2 = "CHandlingData"
                L14_2 = "fBrakeForce"
                L15_2 = L10_2 + 0.0
                L11_2(L12_2, L13_2, L14_2, L15_2)
                L7_2.brakes = L4_2
              end
            end
          end
        end
        L7_2.installed = true
        L8_2 = L27_1
        L8_2[L6_2] = L7_2
        L8_2 = TriggerServerEvent
        L9_2 = "prism-carplay:server:saveTunerChipData"
        L10_2 = L6_2
        L11_2 = L7_2
        L8_2(L9_2, L10_2, L11_2)
      end
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L31_1(L32_1, L33_1)
L31_1 = {}
L32_1 = {}
L33_1 = {}
L34_1 = {}
L35_1 = 0
L36_1 = "solid"
L37_1 = nil
L38_1 = {}
L39_1 = "fInitialDriveMaxFlatVel"
L40_1 = "fInitialDragCoeff"
L41_1 = "fBrakeForce"
L42_1 = "fTractionCurveMax"
L43_1 = "fTractionCurveMin"
L44_1 = "fSuspensionForce"
L45_1 = "fDriveInertia"
L46_1 = "fSteeringLock"
L47_1 = "fTractionCurveLateral"
L48_1 = "fLowSpeedTractionLossMult"
L38_1[1] = L39_1
L38_1[2] = L40_1
L38_1[3] = L41_1
L38_1[4] = L42_1
L38_1[5] = L43_1
L38_1[6] = L44_1
L38_1[7] = L45_1
L38_1[8] = L46_1
L38_1[9] = L47_1
L38_1[10] = L48_1
function L39_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L1_2 = L33_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = L33_1
    L2_2 = {}
    L1_2[A0_2] = L2_2
    L1_2 = ipairs
    L2_2 = L38_1
    L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
    for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
      L7_2 = L33_1
      L7_2 = L7_2[A0_2]
      L8_2 = GetVehicleHandlingFloat
      L9_2 = A0_2
      L10_2 = "CHandlingData"
      L11_2 = L6_2
      L8_2 = L8_2(L9_2, L10_2, L11_2)
      L7_2[L6_2] = L8_2
    end
  end
  L1_2 = L33_1
  L1_2 = L1_2[A0_2]
  return L1_2
end
function L40_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  if not A0_2 or 0 == A0_2 then
    return
  end
  L2_2 = Config
  L2_2 = L2_2.DriveModes
  L2_2 = L2_2[A1_2]
  if not L2_2 then
    L3_2 = Config
    L3_2 = L3_2.DriveModes
    L2_2 = L3_2.normal
    A1_2 = "normal"
  end
  L3_2 = L33_1
  L3_2 = L3_2[A0_2]
  if not L3_2 then
    L4_2 = L39_1
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    L3_2 = L4_2
  end
  L4_2 = pairs
  L5_2 = L3_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = SetVehicleHandlingFloat
    L11_2 = A0_2
    L12_2 = "CHandlingData"
    L13_2 = L8_2
    L14_2 = L9_2 + 0.0
    L10_2(L11_2, L12_2, L13_2, L14_2)
  end
  L4_2 = ModifyVehicleTopSpeed
  L5_2 = A0_2
  L6_2 = 1.0
  L4_2(L5_2, L6_2)
  L4_2 = L2_2.type
  if "reset" == L4_2 or "normal" == A1_2 then
    L4_2 = L34_1
    L4_2[A0_2] = "normal"
    return
  end
  L4_2 = L34_1
  L4_2[A0_2] = A1_2
  L4_2 = L2_2.type
  if "multiplier" == L4_2 then
    L4_2 = pairs
    L5_2 = L2_2
    L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
    for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
      if "type" ~= L8_2 then
        L10_2 = L3_2[L8_2]
        if L10_2 then
          L10_2 = L3_2[L8_2]
          L10_2 = L10_2 * L9_2
          if "fInitialDragCoeff" == L8_2 then
            L11_2 = 0.1
            if L10_2 < L11_2 then
              L10_2 = 0.1
            end
          end
          L11_2 = SetVehicleHandlingFloat
          L12_2 = A0_2
          L13_2 = "CHandlingData"
          L14_2 = L8_2
          L15_2 = L10_2 + 0.0
          L11_2(L12_2, L13_2, L14_2, L15_2)
        end
      end
    end
  else
    L4_2 = L2_2.type
    if "additive" == L4_2 then
      L4_2 = pairs
      L5_2 = L2_2
      L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
      for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
        if "type" ~= L8_2 then
          L10_2 = L3_2[L8_2]
          if L10_2 then
            L10_2 = L3_2[L8_2]
            L10_2 = L10_2 + L9_2
            if "fInitialDragCoeff" == L8_2 then
              L11_2 = 0.1
              if L10_2 < L11_2 then
                L10_2 = 0.1
              end
            end
            L11_2 = SetVehicleHandlingFloat
            L12_2 = A0_2
            L13_2 = "CHandlingData"
            L14_2 = L8_2
            L15_2 = L10_2 + 0.0
            L11_2(L12_2, L13_2, L14_2, L15_2)
          end
        end
      end
    end
  end
  L4_2 = ModifyVehicleTopSpeed
  L5_2 = A0_2
  L6_2 = 1.0
  L4_2(L5_2, L6_2)
  L4_2 = L11_1
  L5_2 = GetVehicleNumberPlateText
  L6_2 = A0_2
  L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2 = L5_2(L6_2)
  L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
  L5_2 = L27_1
  L5_2 = L5_2[L4_2]
  if L5_2 then
    L6_2 = L5_2.installed
    if L6_2 then
      L6_2 = L29_1
      L7_2 = A0_2
      L8_2 = L5_2
      L6_2(L7_2, L8_2)
    end
  end
end
function L41_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2
  L3_2 = A0_2 / 360
  L4_2 = A1_2 / 100
  L5_2 = A2_2 / 100
  L6_2 = nil
  L7_2 = nil
  L8_2 = nil
  L9_2 = math
  L9_2 = L9_2.floor
  L10_2 = L3_2 * 6
  L9_2 = L9_2(L10_2)
  L10_2 = L3_2 * 6
  L10_2 = L10_2 - L9_2
  L11_2 = 1
  L11_2 = L11_2 - L4_2
  L11_2 = L5_2 * L11_2
  L12_2 = L10_2 * L4_2
  L13_2 = 1
  L12_2 = L13_2 - L12_2
  L12_2 = L5_2 * L12_2
  L13_2 = 1
  L13_2 = L13_2 - L10_2
  L13_2 = L13_2 * L4_2
  L14_2 = 1
  L13_2 = L14_2 - L13_2
  L13_2 = L5_2 * L13_2
  L9_2 = L9_2 % 6
  if 0 == L9_2 then
    L14_2 = L5_2
    L15_2 = L13_2
    L8_2 = L11_2
    L7_2 = L15_2
    L6_2 = L14_2
  elseif 1 == L9_2 then
    L14_2 = L12_2
    L15_2 = L5_2
    L8_2 = L11_2
    L7_2 = L15_2
    L6_2 = L14_2
  elseif 2 == L9_2 then
    L14_2 = L11_2
    L15_2 = L5_2
    L8_2 = L13_2
    L7_2 = L15_2
    L6_2 = L14_2
  elseif 3 == L9_2 then
    L14_2 = L11_2
    L15_2 = L12_2
    L8_2 = L5_2
    L7_2 = L15_2
    L6_2 = L14_2
  elseif 4 == L9_2 then
    L14_2 = L13_2
    L15_2 = L11_2
    L8_2 = L5_2
    L7_2 = L15_2
    L6_2 = L14_2
  elseif 5 == L9_2 then
    L14_2 = L5_2
    L15_2 = L11_2
    L8_2 = L12_2
    L7_2 = L15_2
    L6_2 = L14_2
  end
  L14_2 = math
  L14_2 = L14_2.floor
  L15_2 = L6_2 * 255
  L14_2 = L14_2(L15_2)
  L15_2 = math
  L15_2 = L15_2.floor
  L16_2 = L7_2 * 255
  L15_2 = L15_2(L16_2)
  L16_2 = math
  L16_2 = L16_2.floor
  L17_2 = L8_2 * 255
  L16_2, L17_2 = L16_2(L17_2)
  return L14_2, L15_2, L16_2, L17_2
end
function L42_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2
  if not A0_2 or 0 == A0_2 or not A1_2 then
    return
  end
  L2_2 = A1_2.neonHue
  if not L2_2 then
    L2_2 = 120
  end
  L3_2 = A1_2.neonSaturation
  if not L3_2 then
    L3_2 = 100
  end
  L4_2 = A1_2.neonBrightness
  if not L4_2 then
    L4_2 = 50
  end
  L5_2 = L41_1
  L6_2 = L2_2
  L7_2 = L3_2
  L8_2 = L4_2
  L5_2, L6_2, L7_2 = L5_2(L6_2, L7_2, L8_2)
  L8_2 = SetVehicleNeonLightsColour
  L9_2 = A0_2
  L10_2 = L5_2
  L11_2 = L6_2
  L12_2 = L7_2
  L8_2(L9_2, L10_2, L11_2, L12_2)
  L8_2 = A1_2.neonLocations
  if not L8_2 then
    L8_2 = {}
  end
  L9_2 = ipairs
  L10_2 = Config
  L10_2 = L10_2.NeonLocations
  L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
  for L13_2, L14_2 in L9_2, L10_2, L11_2, L12_2 do
    L15_2 = false
    L16_2 = ipairs
    L17_2 = L8_2
    L16_2, L17_2, L18_2, L19_2 = L16_2(L17_2)
    for L20_2, L21_2 in L16_2, L17_2, L18_2, L19_2 do
      L22_2 = L21_2.id
      L23_2 = L14_2.id
      if L22_2 == L23_2 then
        L22_2 = L21_2.enabled
        if L22_2 then
          L15_2 = true
          break
        end
      end
    end
    L16_2 = SetVehicleNeonLightEnabled
    L17_2 = A0_2
    L18_2 = L14_2.index
    L19_2 = L15_2
    L16_2(L17_2, L18_2, L19_2)
  end
end
function L43_1()
  local L0_2, L1_2
  L0_2 = L35_1
  L0_2 = L0_2 + 1
  L35_1 = L0_2
  L0_2 = nil
  L36_1 = L0_2
end
function L44_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2
  if not A0_2 or 0 == A0_2 or not A2_2 then
    return
  end
  L37_1 = A2_2
  L3_2 = A1_2
  L4_2 = type
  L5_2 = A1_2
  L4_2 = L4_2(L5_2)
  if "string" == L4_2 then
    if "solid" == A1_2 then
      L3_2 = 1
    elseif "pulse" == A1_2 then
      L3_2 = 2
    elseif "flash" == A1_2 then
      L3_2 = 3
    elseif "fade" == A1_2 then
      L3_2 = 4
    end
  end
  L4_2 = L36_1
  L5_2 = type
  L6_2 = L36_1
  L5_2 = L5_2(L6_2)
  if "string" == L5_2 then
    L5_2 = L36_1
    if "solid" == L5_2 then
      L4_2 = 1
    else
      L5_2 = L36_1
      if "pulse" == L5_2 then
        L4_2 = 2
      else
        L5_2 = L36_1
        if "flash" == L5_2 then
          L4_2 = 3
        else
          L5_2 = L36_1
          if "fade" == L5_2 then
            L4_2 = 4
          end
        end
      end
    end
  end
  if L3_2 == L4_2 then
    if 3 ~= L3_2 then
      L5_2 = A2_2.neonLocations
      if not L5_2 then
        L5_2 = {}
      end
      L6_2 = ipairs
      L7_2 = Config
      L7_2 = L7_2.NeonLocations
      L6_2, L7_2, L8_2, L9_2 = L6_2(L7_2)
      for L10_2, L11_2 in L6_2, L7_2, L8_2, L9_2 do
        L12_2 = false
        L13_2 = ipairs
        L14_2 = L5_2
        L13_2, L14_2, L15_2, L16_2 = L13_2(L14_2)
        for L17_2, L18_2 in L13_2, L14_2, L15_2, L16_2 do
          L19_2 = L18_2.id
          L20_2 = L11_2.id
          if L19_2 == L20_2 then
            L19_2 = L18_2.enabled
            if L19_2 then
              L12_2 = true
              break
            end
          end
        end
        L13_2 = SetVehicleNeonLightEnabled
        L14_2 = A0_2
        L15_2 = L11_2.index
        L16_2 = L12_2
        L13_2(L14_2, L15_2, L16_2)
      end
    end
    if 1 == L3_2 then
      L5_2 = A2_2.neonHue
      if not L5_2 then
        L5_2 = 120
      end
      L6_2 = A2_2.neonSaturation
      if not L6_2 then
        L6_2 = 100
      end
      L7_2 = A2_2.neonBrightness
      if not L7_2 then
        L7_2 = 50
      end
      L8_2 = L41_1
      L9_2 = L5_2
      L10_2 = L6_2
      L11_2 = L7_2
      L8_2, L9_2, L10_2 = L8_2(L9_2, L10_2, L11_2)
      L11_2 = SetVehicleNeonLightsColour
      L12_2 = A0_2
      L13_2 = L8_2
      L14_2 = L9_2
      L15_2 = L10_2
      L11_2(L12_2, L13_2, L14_2, L15_2)
    end
    return
  end
  L5_2 = L43_1
  L5_2()
  L36_1 = A1_2
  if 1 == L3_2 then
    L5_2 = L42_1
    L6_2 = A0_2
    L7_2 = A2_2
    L5_2(L6_2, L7_2)
    return
  end
  if 2 == L3_2 or 4 == L3_2 then
    L5_2 = A2_2.neonLocations
    if not L5_2 then
      L5_2 = {}
    end
    L6_2 = ipairs
    L7_2 = Config
    L7_2 = L7_2.NeonLocations
    L6_2, L7_2, L8_2, L9_2 = L6_2(L7_2)
    for L10_2, L11_2 in L6_2, L7_2, L8_2, L9_2 do
      L12_2 = false
      L13_2 = ipairs
      L14_2 = L5_2
      L13_2, L14_2, L15_2, L16_2 = L13_2(L14_2)
      for L17_2, L18_2 in L13_2, L14_2, L15_2, L16_2 do
        L19_2 = L18_2.id
        L20_2 = L11_2.id
        if L19_2 == L20_2 then
          L19_2 = L18_2.enabled
          if L19_2 then
            L12_2 = true
            break
          end
        end
      end
      L13_2 = SetVehicleNeonLightEnabled
      L14_2 = A0_2
      L15_2 = L11_2.index
      L16_2 = L12_2
      L13_2(L14_2, L15_2, L16_2)
    end
  end
  L5_2 = L35_1
  L5_2 = L5_2 + 1
  L35_1 = L5_2
  L5_2 = L35_1
  L6_2 = CreateThread
  function L7_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3, L20_3, L21_3, L22_3
    L0_3 = 0
    while true do
      L1_3 = L5_2
      L2_3 = L35_1
      if L1_3 ~= L2_3 then
        break
      end
      L1_3 = PlayerPedId
      L1_3 = L1_3()
      L2_3 = GetVehiclePedIsIn
      L3_3 = L1_3
      L4_3 = false
      L2_3 = L2_3(L3_3, L4_3)
      L3_3 = A0_2
      if L2_3 ~= L3_3 then
        return
      end
      L3_3 = L37_1
      if not L3_3 then
        L3_3 = A2_2
      end
      L4_3 = L3_3.neonHue
      if not L4_3 then
        L4_3 = 120
      end
      L5_3 = L3_3.neonSaturation
      if not L5_3 then
        L5_3 = 100
      end
      L6_3 = L3_3.neonBrightness
      if not L6_3 then
        L6_3 = 50
      end
      L7_3 = L3_2
      if 2 == L7_3 then
        L7_3 = math
        L7_3 = L7_3.abs
        L8_3 = math
        L8_3 = L8_3.sin
        L9_3 = L0_3
        L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3, L20_3, L21_3, L22_3 = L8_3(L9_3)
        L7_3 = L7_3(L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3, L20_3, L21_3, L22_3)
        L7_3 = 0.7 * L7_3
        L7_3 = 0.3 + L7_3
        L7_3 = L6_3 * L7_3
        L8_3 = L41_1
        L9_3 = L4_3
        L10_3 = L5_3
        L11_3 = L7_3
        L8_3, L9_3, L10_3 = L8_3(L9_3, L10_3, L11_3)
        L11_3 = SetVehicleNeonLightsColour
        L12_3 = A0_2
        L13_3 = L8_3
        L14_3 = L9_3
        L15_3 = L10_3
        L11_3(L12_3, L13_3, L14_3, L15_3)
        L0_3 = L0_3 + 0.05
      else
        L7_3 = L3_2
        if 3 == L7_3 then
          L7_3 = math
          L7_3 = L7_3.floor
          L8_3 = L0_3
          L7_3 = L7_3(L8_3)
          L7_3 = L7_3 % 2
          L7_3 = 0 == L7_3
          L8_3 = ipairs
          L9_3 = Config
          L9_3 = L9_3.NeonLocations
          L8_3, L9_3, L10_3, L11_3 = L8_3(L9_3)
          for L12_3, L13_3 in L8_3, L9_3, L10_3, L11_3 do
            L14_3 = false
            L15_3 = ipairs
            L16_3 = L3_3.neonLocations
            if not L16_3 then
              L16_3 = {}
            end
            L15_3, L16_3, L17_3, L18_3 = L15_3(L16_3)
            for L19_3, L20_3 in L15_3, L16_3, L17_3, L18_3 do
              L21_3 = L20_3.id
              L22_3 = L13_3.id
              if L21_3 == L22_3 then
                L21_3 = L20_3.enabled
                if L21_3 then
                  L14_3 = true
                  break
                end
              end
            end
            L15_3 = SetVehicleNeonLightEnabled
            L16_3 = A0_2
            L17_3 = L13_3.index
            L18_3 = L14_3 or L18_3
            if L14_3 then
              L18_3 = L7_3
            end
            L15_3(L16_3, L17_3, L18_3)
          end
          L0_3 = L0_3 + 0.15
        else
          L7_3 = L3_2
          if 4 == L7_3 then
            L7_3 = L0_3 * 50
            L7_3 = L4_3 + L7_3
            L7_3 = L7_3 % 360
            L8_3 = L41_1
            L9_3 = L7_3
            L10_3 = L5_3
            L11_3 = L6_3
            L8_3, L9_3, L10_3 = L8_3(L9_3, L10_3, L11_3)
            L11_3 = SetVehicleNeonLightsColour
            L12_3 = A0_2
            L13_3 = L8_3
            L14_3 = L9_3
            L15_3 = L10_3
            L11_3(L12_3, L13_3, L14_3, L15_3)
            L0_3 = L0_3 + 0.02
          end
        end
      end
      L7_3 = Wait
      L8_3 = 50
      L7_3(L8_3)
    end
  end
  L6_2(L7_2)
end
function L45_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  if not A0_2 or 0 == A0_2 or not A1_2 then
    return
  end
  L2_2 = A1_2.driveMode
  if L2_2 then
    L2_2 = L40_1
    L3_2 = A0_2
    L4_2 = A1_2.driveMode
    L2_2(L3_2, L4_2)
  end
  L2_2 = 1
  L3_2 = ipairs
  L4_2 = A1_2.neonPatterns
  if not L4_2 then
    L4_2 = {}
  end
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
  for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
    L9_2 = L8_2.enabled
    if L9_2 then
      L2_2 = L8_2.id
      break
    end
  end
  L3_2 = L44_1
  L4_2 = A0_2
  L5_2 = L2_2
  L6_2 = A1_2
  L3_2(L4_2, L5_2, L6_2)
end
L46_1 = RegisterNetEvent
L47_1 = "prism-carplay:client:receiveModificationsData"
function L48_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = L31_1
  L2_2[A0_2] = A1_2
  L2_2 = L32_1
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L2_2 = L32_1
    L2_2 = L2_2[A0_2]
    L3_2 = L32_1
    L3_2[A0_2] = nil
    L3_2 = L2_2
    L4_2 = A1_2 or L4_2
    if not A1_2 then
      L4_2 = {}
    end
    L3_2(L4_2)
  end
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    if L4_2 == A0_2 and A1_2 then
      L5_2 = L45_1
      L6_2 = L3_2
      L7_2 = A1_2
      L5_2(L6_2, L7_2)
    end
  end
end
L46_1(L47_1, L48_1)
L46_1 = RegisterNetEvent
L47_1 = "prism-carplay:client:modificationsDataUpdated"
function L48_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = L31_1
  L2_2[A0_2] = A1_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    if L4_2 == A0_2 and A1_2 then
      L5_2 = L45_1
      L6_2 = L3_2
      L7_2 = A1_2
      L5_2(L6_2, L7_2)
    end
  end
end
L46_1(L47_1, L48_1)
L46_1 = RegisterNUICallback
L47_1 = "getModificationsData"
function L48_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    L5_2 = L31_1
    L5_2 = L5_2[L4_2]
    if L5_2 then
      L5_2 = A1_2
      L6_2 = L31_1
      L6_2 = L6_2[L4_2]
      L5_2(L6_2)
    else
      L5_2 = L32_1
      L5_2[L4_2] = A1_2
      L5_2 = TriggerServerEvent
      L6_2 = "prism-carplay:server:getModificationsData"
      L7_2 = L4_2
      L5_2(L6_2, L7_2)
    end
  else
    L4_2 = A1_2
    L5_2 = {}
    L4_2(L5_2)
  end
end
L46_1(L47_1, L48_1)
L46_1 = RegisterNUICallback
L47_1 = "saveModificationsData"
function L48_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 and A0_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2)
    L5_2 = L31_1
    L5_2[L4_2] = A0_2
    L5_2 = L45_1
    L6_2 = L3_2
    L7_2 = A0_2
    L5_2(L6_2, L7_2)
    L5_2 = TriggerServerEvent
    L6_2 = "prism-carplay:server:saveModificationsData"
    L7_2 = L4_2
    L8_2 = A0_2
    L5_2(L6_2, L7_2, L8_2)
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L46_1(L47_1, L48_1)
L46_1 = RegisterNUICallback
L47_1 = "setDriveMode"
function L48_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = A0_2.mode
    if L4_2 then
      L4_2 = L11_1
      L5_2 = GetVehicleNumberPlateText
      L6_2 = L3_2
      L5_2, L6_2, L7_2, L8_2, L9_2 = L5_2(L6_2)
      L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2)
      L5_2 = L31_1
      L5_2 = L5_2[L4_2]
      if not L5_2 then
        L5_2 = {}
      end
      L6_2 = A0_2.mode
      L5_2.driveMode = L6_2
      L6_2 = L31_1
      L6_2[L4_2] = L5_2
      L6_2 = L40_1
      L7_2 = L3_2
      L8_2 = A0_2.mode
      L6_2(L7_2, L8_2)
      L6_2 = TriggerServerEvent
      L7_2 = "prism-carplay:server:saveModificationsData"
      L8_2 = L4_2
      L9_2 = L5_2
      L6_2(L7_2, L8_2, L9_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L46_1(L47_1, L48_1)
function L46_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L1_2 = L2_1
  if not L1_2 then
    return
  end
  L1_2 = L3_1
  if L1_2 then
    L1_2 = GetEntityBoneIndexByName
    L2_2 = A0_2
    L3_2 = "bonnet"
    L1_2 = L1_2(L2_2, L3_2)
    if -1 == L1_2 then
      L2_2 = GetEntityBoneIndexByName
      L3_2 = A0_2
      L4_2 = "boot"
      L2_2 = L2_2(L3_2, L4_2)
      L1_2 = L2_2
    end
    L2_2 = AttachCamToVehicleBone
    L3_2 = L2_1
    L4_2 = A0_2
    L5_2 = L1_2
    L6_2 = true
    L7_2 = -5.0
    L8_2 = 0.0
    L9_2 = 0.0
    L10_2 = 0.0
    L11_2 = 0.5
    L12_2 = 0.3
    L13_2 = true
    L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
  else
    L1_2 = GetEntityBoneIndexByName
    L2_2 = A0_2
    L3_2 = "boot"
    L1_2 = L1_2(L2_2, L3_2)
    if -1 == L1_2 then
      L2_2 = GetEntityBoneIndexByName
      L3_2 = A0_2
      L4_2 = "bonnet"
      L2_2 = L2_2(L3_2, L4_2)
      L1_2 = L2_2
    end
    L2_2 = AttachCamToVehicleBone
    L3_2 = L2_1
    L4_2 = A0_2
    L5_2 = L1_2
    L6_2 = true
    L7_2 = -5.0
    L8_2 = 0.0
    L9_2 = 180.0
    L10_2 = 0.0
    L11_2 = -0.5
    L12_2 = 0.3
    L13_2 = true
    L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
  end
end
L47_1 = false
function L48_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = GetVehiclePedIsIn
  L3_2 = L1_2
  L4_2 = false
  L2_2 = L2_2(L3_2, L4_2)
  if 0 == L2_2 then
    L3_2 = false
    return L3_2
  end
  L3_2 = false ~= A0_2
  L3_1 = L3_2
  L3_2 = CreateCam
  L4_2 = "DEFAULT_SCRIPTED_CAMERA"
  L5_2 = true
  L3_2 = L3_2(L4_2, L5_2)
  L2_1 = L3_2
  L3_2 = SetCamFov
  L4_2 = L2_1
  L5_2 = 70.0
  L3_2(L4_2, L5_2)
  L3_2 = L46_1
  L4_2 = L2_2
  L3_2(L4_2)
  L3_2 = SetTimecycleModifier
  L4_2 = "CAMERA_secuirity"
  L3_2(L4_2)
  L3_2 = SetTimecycleModifierStrength
  L4_2 = 1.0
  L3_2(L4_2)
  L3_2 = RenderScriptCams
  L4_2 = true
  L5_2 = true
  L6_2 = 500
  L7_2 = true
  L8_2 = false
  L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
  L3_2 = true
  L47_1 = L3_2
  L3_2 = true
  L1_1 = L3_2
  L3_2 = L22_1
  L4_2 = true
  L3_2(L4_2)
  L3_2 = true
  return L3_2
end
function L49_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = L2_1
  if L0_2 then
    L0_2 = DestroyCam
    L1_2 = L2_1
    L2_2 = false
    L0_2(L1_2, L2_2)
    L0_2 = nil
    L2_1 = L0_2
  end
  L0_2 = RenderScriptCams
  L1_2 = false
  L2_2 = true
  L3_2 = 500
  L4_2 = true
  L5_2 = false
  L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
  L0_2 = ClearTimecycleModifier
  L0_2()
  L0_2 = false
  L47_1 = L0_2
  L0_2 = SetTimeout
  L1_2 = 3000
  function L2_2()
    local L0_3, L1_3
    L0_3 = L47_1
    if not L0_3 then
      L0_3 = false
      L1_1 = L0_3
    end
  end
  L0_2(L1_2, L2_2)
  L0_2 = L22_1
  L1_2 = false
  L0_2(L1_2)
end
L50_1 = RegisterNUICallback
L51_1 = "startDashcam"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = A0_2.front
  L2_2 = false ~= L2_2
  L3_2 = L48_1
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = A1_2
  L5_2 = {}
  L5_2.success = L3_2
  L4_2(L5_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNUICallback
L51_1 = "stopDashcam"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = L49_1
  L2_2()
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNUICallback
L51_1 = "rotateDashcam"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L2_1
    if L4_2 then
      L4_2 = A0_2.front
      L4_2 = false ~= L4_2
      L3_1 = L4_2
      L4_2 = L46_1
      L5_2 = L3_2
      L4_2(L5_2)
    end
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNUICallback
L51_1 = "startRecording"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = L7_1
  if L2_2 then
    L2_2 = A1_2
    L3_2 = {}
    L3_2.success = false
    L3_2.error = "Already recording"
    L2_2(L3_2)
    return
  end
  L2_2 = true
  L7_1 = L2_2
  L2_2 = A0_2.duration
  if not L2_2 then
    L2_2 = 60
  end
  L3_2 = TriggerServerEvent
  L4_2 = "prism-carplay:server:startRecording"
  L5_2 = L2_2
  L3_2(L4_2, L5_2)
  L3_2 = A1_2
  L4_2 = {}
  L4_2.success = true
  L3_2(L4_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNUICallback
L51_1 = "stopRecording"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = L7_1
  if not L2_2 then
    L2_2 = A1_2
    L3_2 = {}
    L3_2.success = false
    L3_2.error = "Not recording"
    L2_2(L3_2)
    return
  end
  L2_2 = A0_2.recordingTime
  if not L2_2 then
    L2_2 = 0
  end
  L3_2 = TriggerServerEvent
  L4_2 = "prism-carplay:server:stopRecording"
  L5_2 = L2_2
  L3_2(L4_2, L5_2)
  L3_2 = false
  L7_1 = L3_2
  L3_2 = A1_2
  L4_2 = {}
  L4_2.success = true
  L3_2(L4_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNUICallback
L51_1 = "getRecordings"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = TriggerServerEvent
  L3_2 = "prism-carplay:server:getRecordings"
  L2_2(L3_2)
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNUICallback
L51_1 = "deleteRecording"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = A0_2.id
  if L2_2 then
    L2_2 = TriggerServerEvent
    L3_2 = "prism-carplay:server:deleteRecording"
    L4_2 = A0_2.id
    L2_2(L3_2, L4_2)
  end
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNUICallback
L51_1 = "clearAllRecordings"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = TriggerServerEvent
  L3_2 = "prism-carplay:server:clearAllRecordings"
  L2_2(L3_2)
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNUICallback
L51_1 = "uploadRecording"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = A0_2.id
  if L2_2 then
    L2_2 = TriggerServerEvent
    L3_2 = "prism-carplay:server:uploadRecording"
    L4_2 = A0_2.id
    L2_2(L3_2, L4_2)
  end
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNetEvent
L51_1 = "prism-carplay:client:uploadComplete"
function L52_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.action = "uploadComplete"
  L4_2 = {}
  L4_2.id = A0_2
  L4_2.url = A1_2
  L3_2.data = L4_2
  L2_2(L3_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNetEvent
L51_1 = "prism-carplay:client:uploadFailed"
function L52_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.action = "uploadFailed"
  L3_2 = {}
  L3_2.id = A0_2
  L2_2.data = L3_2
  L1_2(L2_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNetEvent
L51_1 = "prism-carplay:client:receiveRecordings"
function L52_1(A0_2)
  local L1_2, L2_2
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.action = "receiveRecordings"
  L2_2.data = A0_2
  L1_2(L2_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNetEvent
L51_1 = "prism-carplay:client:recordingSaved"
function L52_1(A0_2)
  local L1_2, L2_2
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.action = "recordingSaved"
  L2_2.data = A0_2
  L1_2(L2_2)
end
L50_1(L51_1, L52_1)
L50_1 = RegisterNetEvent
L51_1 = "ts-medialib:stopRecording"
function L52_1()
  local L0_2, L1_2
  L0_2 = false
  L7_1 = L0_2
end
L50_1(L51_1, L52_1)
L50_1 = CreateThread
function L51_1()
  local L0_2, L1_2, L2_2, L3_2
  while true do
    L0_2 = L1_1
    if L0_2 then
      L0_2 = IsPauseMenuActive
      L0_2 = L0_2()
      if L0_2 then
        L0_2 = SetPauseMenuActive
        L1_2 = false
        L0_2(L1_2)
      end
      L0_2 = DisableAllControlActions
      L1_2 = 0
      L0_2(L1_2)
      L0_2 = DisableAllControlActions
      L1_2 = 2
      L0_2(L1_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 71
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 72
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 63
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 64
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 59
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 60
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 75
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 76
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 81
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 82
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 80
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 73
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 172
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 173
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 174
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 175
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 1
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 2
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 24
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 0
      L2_2 = 25
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 2
      L2_2 = 1
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 2
      L2_2 = 2
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 2
      L2_2 = 24
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = EnableControlAction
      L1_2 = 2
      L2_2 = 25
      L3_2 = true
      L0_2(L1_2, L2_2, L3_2)
      L0_2 = PlayerPedId
      L0_2 = L0_2()
      L1_2 = GetVehiclePedIsIn
      L2_2 = L0_2
      L3_2 = false
      L1_2 = L1_2(L2_2, L3_2)
      if 0 == L1_2 then
        L2_2 = L49_1
        L2_2()
        L2_2 = SendNUIMessage
        L3_2 = {}
        L3_2.action = "dashcamStopped"
        L3_2.data = true
        L2_2(L3_2)
      end
    end
    L0_2 = Wait
    L1_2 = 0
    L0_2(L1_2)
  end
end
L50_1(L51_1)
function L50_1()
  local L0_2, L1_2
  L0_2 = L1_1
  if L0_2 then
    L0_2 = L49_1
    L0_2()
  end
  L0_2 = L0_1
  if L0_2 then
    L0_2 = L21_1
    L1_2 = false
    L0_2(L1_2)
  end
end
L24_1 = L50_1
L50_1 = 0
L51_1 = CreateThread
function L52_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  while true do
    L0_2 = PlayerPedId
    L0_2 = L0_2()
    L1_2 = GetVehiclePedIsIn
    L2_2 = L0_2
    L3_2 = false
    L1_2 = L1_2(L2_2, L3_2)
    if 0 ~= L1_2 then
      L2_2 = L50_1
      if L1_2 ~= L2_2 then
        L50_1 = L1_2
        L2_2 = L11_1
        L3_2 = GetVehicleNumberPlateText
        L4_2 = L1_2
        L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
        L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
        L3_2 = L33_1
        L3_2[L1_2] = nil
        L3_2 = L25_1
        L3_2[L1_2] = nil
        L3_2 = L39_1
        L4_2 = L1_2
        L3_2(L4_2)
        L3_2 = L26_1
        L4_2 = L1_2
        L3_2(L4_2)
        L3_2 = Config
        L3_2 = L3_2.RequireCarplayItem
        if L3_2 then
          L3_2 = L6_1
          L3_2 = L3_2[L2_2]
          if nil ~= L3_2 then
            L3_2 = L6_1
            L3_2 = L3_2[L2_2]
            L5_1 = L3_2
          else
            L3_2 = false
            L5_1 = L3_2
            L3_2 = TriggerServerEvent
            L4_2 = "prism-carplay:server:getCarplayInstalled"
            L5_2 = L2_2
            L3_2(L4_2, L5_2)
          end
        else
          L3_2 = true
          L5_1 = L3_2
        end
        L3_2 = L27_1
        L3_2 = L3_2[L2_2]
        if L3_2 then
          L3_2 = L27_1
          L3_2 = L3_2[L2_2]
          L4_2 = L3_2.installed
          if not L4_2 then
            L4_2 = false
          end
          L4_1 = L4_2
          L4_2 = SendNUIMessage
          L5_2 = {}
          L5_2.action = "updateTunerChip"
          L6_2 = L4_1
          L5_2.data = L6_2
          L4_2(L5_2)
          L4_2 = L29_1
          L5_2 = L1_2
          L6_2 = L3_2
          L4_2(L5_2, L6_2)
        else
          L3_2 = false
          L4_1 = L3_2
          L3_2 = SendNUIMessage
          L4_2 = {}
          L4_2.action = "updateTunerChip"
          L4_2.data = false
          L3_2(L4_2)
          L3_2 = TriggerServerEvent
          L4_2 = "prism-carplay:server:getTunerChipData"
          L5_2 = L2_2
          L3_2(L4_2, L5_2)
        end
        L3_2 = L31_1
        L3_2 = L3_2[L2_2]
        if L3_2 then
          L3_2 = L45_1
          L4_2 = L1_2
          L5_2 = L31_1
          L5_2 = L5_2[L2_2]
          L3_2(L4_2, L5_2)
        else
          L3_2 = TriggerServerEvent
          L4_2 = "prism-carplay:server:getModificationsData"
          L5_2 = L2_2
          L3_2(L4_2, L5_2)
        end
        L3_2 = TriggerServerEvent
        L4_2 = "prism-carplay:server:getMusicState"
        L5_2 = L2_2
        L3_2(L4_2, L5_2)
    end
    elseif 0 == L1_2 then
      L2_2 = 0
      L50_1 = L2_2
      L2_2 = false
      L5_1 = L2_2
      L2_2 = L43_1
      L2_2()
    end
    L2_2 = Wait
    L3_2 = 500
    L2_2(L3_2)
  end
end
L51_1(L52_1)
L51_1 = AddEventHandler
L52_1 = "onResourceStart"
function L53_1(A0_2)
  local L1_2, L2_2
  L1_2 = GetCurrentResourceName
  L1_2 = L1_2()
  if L1_2 ~= A0_2 then
    return
  end
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.action = "setVisible"
  L2_2.data = false
  L1_2(L2_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "getMusicLibrary"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = A1_2
  L3_2 = Config
  L3_2 = L3_2.MusicLibrary
  if not L3_2 then
    L3_2 = {}
  end
  L2_2(L3_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "fetchYouTubeData"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = A0_2.url
  if not L2_2 then
    L2_2 = A1_2
    L3_2 = {}
    L3_2.success = false
    L3_2.error = "No URL provided"
    L2_2(L3_2)
    return
  end
  L2_2 = FetchData
  L3_2 = A0_2.url
  function L4_2(A0_3)
    local L1_3, L2_3, L3_3
    if A0_3 then
      L1_3 = A0_3.status
      if "success" == L1_3 then
        L1_3 = A1_2
        L2_3 = {}
        L2_3.success = true
        L3_3 = A0_3.title
        if not L3_3 then
          L3_3 = "YouTube Video"
        end
        L2_3.title = L3_3
        L3_3 = A0_3.duration
        if not L3_3 then
          L3_3 = 0
        end
        L2_3.duration = L3_3
        L1_3(L2_3)
    end
    else
      L1_3 = A1_2
      L2_3 = {}
      L2_3.success = false
      L2_3.error = "Failed to fetch video data"
      L1_3(L2_3)
    end
  end
  L2_2(L3_2, L4_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "playMusic"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 == L3_2 then
    L4_2 = A1_2
    L5_2 = {}
    L5_2.success = false
    L5_2.error = "Not in vehicle"
    L4_2(L5_2)
    return
  end
  L4_2 = L11_1
  L5_2 = GetVehicleNumberPlateText
  L6_2 = L3_2
  L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2 = L5_2(L6_2)
  L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2)
  L5_2 = A0_2.song
  L6_2 = NetworkGetNetworkIdFromEntity
  L7_2 = L3_2
  L6_2 = L6_2(L7_2)
  L7_2 = L5_2.filePath
  if L7_2 then
    L7_2 = L5_2.isYouTube
    if not L7_2 then
      L7_2 = string
      L7_2 = L7_2.match
      L8_2 = L5_2.filePath
      L9_2 = "^https?://"
      L7_2 = L7_2(L8_2, L9_2)
      if not L7_2 then
        L7_2 = "https://cfx-nui-"
        L8_2 = GetCurrentResourceName
        L8_2 = L8_2()
        L9_2 = "/web/dist/sounds/"
        L10_2 = L5_2.filePath
        L7_2 = L7_2 .. L8_2 .. L9_2 .. L10_2
        L5_2.url = L7_2
      end
    end
  end
  L7_2 = L5_2.isYouTube
  if L7_2 then
    L7_2 = L5_2.url
    if L7_2 then
      L7_2 = FetchData
      L8_2 = L5_2.url
      function L9_2(A0_3)
        local L1_3, L2_3, L3_3, L4_3, L5_3
        if A0_3 then
          L1_3 = A0_3.status
          if "success" == L1_3 then
            L1_3 = A0_3.title
            if L1_3 then
              L1_3 = A0_3.title
              if "" ~= L1_3 then
                L1_3 = A0_3.title
                L5_2.title = L1_3
              end
            end
            L1_3 = A0_3.duration
            if L1_3 then
              L1_3 = A0_3.duration
              if L1_3 > 0 then
                L1_3 = A0_3.duration
                L5_2.duration = L1_3
              end
            end
          end
        end
        L1_3 = TriggerServerEvent
        L2_3 = "prism-carplay:server:playMusic"
        L3_3 = L4_2
        L4_3 = L5_2
        L5_3 = L6_2
        L1_3(L2_3, L3_3, L4_3, L5_3)
        L1_3 = L4_2
        L8_1 = L1_3
        L1_3 = L5_2
        L10_1 = L1_3
      end
      L7_2(L8_2, L9_2)
      L7_2 = A1_2
      L8_2 = {}
      L8_2.success = true
      L7_2(L8_2)
      return
    end
  end
  L7_2 = TriggerServerEvent
  L8_2 = "prism-carplay:server:playMusic"
  L9_2 = L4_2
  L10_2 = L5_2
  L11_2 = L6_2
  L7_2(L8_2, L9_2, L10_2, L11_2)
  L8_1 = L4_2
  L10_1 = L5_2
  L7_2 = A1_2
  L8_2 = {}
  L8_2.success = true
  L7_2(L8_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "getMusicTime"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = L8_1
  if L2_2 then
    L2_2 = L8_1
    L3_2 = "carplay"
    L2_2 = L2_2 .. L3_2
    L3_2 = GetCurrentTime
    L4_2 = L2_2
    L3_2 = L3_2(L4_2)
    L4_2 = A1_2
    L5_2 = {}
    L6_2 = L3_2 or L6_2
    if not L3_2 then
      L6_2 = 0
    end
    L5_2.currentTime = L6_2
    L4_2(L5_2)
  else
    L2_2 = A1_2
    L3_2 = {}
    L3_2.currentTime = 0
    L2_2(L3_2)
  end
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "toggleMusic"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = L8_1
  if not L2_2 then
    L2_2 = A1_2
    L3_2 = "ok"
    L2_2(L3_2)
    return
  end
  L2_2 = TriggerServerEvent
  L3_2 = "prism-carplay:server:toggleMusic"
  L4_2 = L8_1
  L2_2(L3_2, L4_2)
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "stopMusic"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = L8_1
  if L2_2 then
    L2_2 = TriggerServerEvent
    L3_2 = "prism-carplay:server:stopMusic"
    L4_2 = L8_1
    L2_2(L3_2, L4_2)
    L2_2 = nil
    L8_1 = L2_2
    L2_2 = nil
    L10_1 = L2_2
    L2_2 = false
    L9_1 = L2_2
  end
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "seekMusic"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = L8_1
  if L2_2 then
    L2_2 = A0_2.time
    if L2_2 then
      L2_2 = TriggerServerEvent
      L3_2 = "prism-carplay:server:seekMusic"
      L4_2 = L8_1
      L5_2 = A0_2.time
      L2_2(L3_2, L4_2, L5_2)
    end
  end
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "setMusicVolume"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = L8_1
  if L2_2 then
    L2_2 = A0_2.volume
    if L2_2 then
      L2_2 = TriggerServerEvent
      L3_2 = "prism-carplay:server:setMusicVolume"
      L4_2 = L8_1
      L5_2 = A0_2.volume
      L5_2 = L5_2 * 100
      L2_2(L3_2, L4_2, L5_2)
    end
  end
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNUICallback
L52_1 = "getMusicState"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = L8_1
  if L2_2 then
    L2_2 = L10_1
    if L2_2 then
      L2_2 = L8_1
      L3_2 = "carplay"
      L2_2 = L2_2 .. L3_2
      L3_2 = GetCurrentTime
      L4_2 = L2_2
      L3_2 = L3_2(L4_2)
      L4_2 = SendNUIMessage
      L5_2 = {}
      L5_2.action = "syncMusicState"
      L6_2 = {}
      L7_2 = L10_1
      L6_2.song = L7_2
      L7_2 = L9_1
      L6_2.isPlaying = L7_2
      L7_2 = L3_2 or L7_2
      if not L3_2 then
        L7_2 = 0
      end
      L6_2.currentTime = L7_2
      L6_2.audioSourceId = L2_2
      L5_2.data = L6_2
      L4_2(L5_2)
    end
  end
  L2_2 = A1_2
  L3_2 = "ok"
  L2_2(L3_2)
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNetEvent
L52_1 = "prism-carplay:client:musicStarted"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2, L8_2, L9_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2)
    if L4_2 == A0_2 then
      L8_1 = A0_2
      L10_1 = A1_2
      L5_2 = true
      L9_1 = L5_2
      L5_2 = SendNUIMessage
      L6_2 = {}
      L6_2.action = "musicStarted"
      L7_2 = {}
      L7_2.song = A1_2
      L8_2 = A0_2
      L9_2 = "carplay"
      L8_2 = L8_2 .. L9_2
      L7_2.audioSourceId = L8_2
      L6_2.data = L7_2
      L5_2(L6_2)
    end
  end
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNetEvent
L52_1 = "prism-carplay:client:playbackStatus"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    if L4_2 == A0_2 then
      L9_1 = A1_2
      L5_2 = SendNUIMessage
      L6_2 = {}
      L6_2.action = "updatePlaybackStatus"
      L7_2 = {}
      L7_2.isPlaying = A1_2
      L6_2.data = L7_2
      L5_2(L6_2)
    end
  end
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNetEvent
L52_1 = "prism-carplay:client:musicStopped"
function L53_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = GetVehiclePedIsIn
  L3_2 = L1_2
  L4_2 = false
  L2_2 = L2_2(L3_2, L4_2)
  if 0 ~= L2_2 then
    L3_2 = L11_1
    L4_2 = GetVehicleNumberPlateText
    L5_2 = L2_2
    L4_2, L5_2 = L4_2(L5_2)
    L3_2 = L3_2(L4_2, L5_2)
    if L3_2 ~= A0_2 then
      L4_2 = L8_1
      if L4_2 ~= A0_2 then
        goto lbl_31
      end
    end
    L4_2 = SendNUIMessage
    L5_2 = {}
    L5_2.action = "musicStopped"
    L5_2.data = true
    L4_2(L5_2)
    L4_2 = nil
    L8_1 = L4_2
    L4_2 = nil
    L10_1 = L4_2
    L4_2 = false
    L9_1 = L4_2
  end
  ::lbl_31::
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNetEvent
L52_1 = "prism-carplay:client:trackEnded"
function L53_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = GetVehiclePedIsIn
  L3_2 = L1_2
  L4_2 = false
  L2_2 = L2_2(L3_2, L4_2)
  if 0 ~= L2_2 then
    L3_2 = L11_1
    L4_2 = GetVehicleNumberPlateText
    L5_2 = L2_2
    L4_2, L5_2 = L4_2(L5_2)
    L3_2 = L3_2(L4_2, L5_2)
    if L3_2 ~= A0_2 then
      L4_2 = L8_1
      if L4_2 ~= A0_2 then
        goto lbl_31
      end
    end
    L4_2 = SendNUIMessage
    L5_2 = {}
    L5_2.action = "trackEnded"
    L5_2.data = true
    L4_2(L5_2)
    L4_2 = nil
    L8_1 = L4_2
    L4_2 = nil
    L10_1 = L4_2
    L4_2 = false
    L9_1 = L4_2
  end
  ::lbl_31::
end
L51_1(L52_1, L53_1)
L51_1 = RegisterNetEvent
L52_1 = "prism-carplay:client:syncMusicState"
function L53_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetVehiclePedIsIn
  L4_2 = L2_2
  L5_2 = false
  L3_2 = L3_2(L4_2, L5_2)
  if 0 ~= L3_2 then
    L4_2 = L11_1
    L5_2 = GetVehicleNumberPlateText
    L6_2 = L3_2
    L5_2, L6_2, L7_2, L8_2, L9_2, L10_2 = L5_2(L6_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2)
    if L4_2 == A0_2 then
      L5_2 = A1_2.currentSong
      if L5_2 then
        L8_1 = A0_2
        L5_2 = A1_2.currentSong
        L10_1 = L5_2
        L5_2 = A1_2.isPlaying
        L9_1 = L5_2
        L5_2 = A0_2
        L6_2 = "carplay"
        L5_2 = L5_2 .. L6_2
        L6_2 = GetCurrentTime
        L7_2 = L5_2
        L6_2 = L6_2(L7_2)
        L7_2 = SendNUIMessage
        L8_2 = {}
        L8_2.action = "syncMusicState"
        L9_2 = {}
        L10_2 = A1_2.currentSong
        L9_2.song = L10_2
        L10_2 = A1_2.isPlaying
        L9_2.isPlaying = L10_2
        L10_2 = A1_2.volume
        L9_2.volume = L10_2
        L10_2 = L6_2 or L10_2
        if not L6_2 then
          L10_2 = 0
        end
        L9_2.currentTime = L10_2
        L9_2.audioSourceId = L5_2
        L8_2.data = L9_2
        L7_2(L8_2)
      end
    end
  end
end
L51_1(L52_1, L53_1)

