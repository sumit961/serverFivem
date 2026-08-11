local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1
L0_1 = "FIRST_LAYER"
L1_1 = "WALLS"
L2_1 = {}
L3_1 = {}
L3_1.phase = "BREAKING_WALLS"
L3_1.isActive = false
L3_1.isAlarmActive = false
L4_1 = {}
L3_1.initiator = L4_1
L4_1 = {}
L3_1.interactions = L4_1
L4_1 = {}
L3_1.swapSessions = L4_1
L4_1 = {}
L4_1.FIRST_LAYER = false
L4_1.SECOND_LAYER = false
L3_1.LAYERS = L4_1
L2_1.WALLS = L3_1
L3_1 = false
L4_1 = AddEventHandler
L5_1 = "rcore_prison:shared:internal:MapLoaded"
function L6_1()
  local L0_2, L1_2
  L0_2 = true
  L3_1 = L0_2
end
L4_1(L5_1, L6_1)
L4_1 = RegisterCommand
L5_1 = "prisonBreak"
function L6_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2
  if 0 == A0_2 then
    L3_2 = tprint
    L4_2 = L2_1
    L3_2(L4_2)
  end
end
L7_1 = false
L4_1(L5_1, L6_1, L7_1)
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = L2_1.WALLS
  L2_2 = L2_2.isActive
  if L2_2 then
    L2_2 = {}
    L3_2 = {}
    L3_2.phase = "BREAKING_WALLS"
    L3_2.isActive = false
    L4_2 = {}
    L3_2.initiator = L4_2
    L4_2 = {}
    L3_2.interactions = L4_2
    L4_2 = {}
    L3_2.swapSessions = L4_2
    L4_2 = {}
    L4_2.FIRST_LAYER = false
    L4_2.SECOND_LAYER = false
    L3_2.LAYERS = L4_2
    L2_2.WALLS = L3_2
    L2_1 = L2_2
    if A0_2 then
      L2_2 = dbg
      L2_2 = L2_2.debug
      L3_2 = "PRISON BREAK: Reset was done by user named %s (%s)!"
      L4_2 = GetPlayerName
      L5_2 = A0_2
      L4_2 = L4_2(L5_2)
      L5_2 = A0_2
      L2_2(L3_2, L4_2, L5_2)
    else
      L2_2 = dbg
      L2_2 = L2_2.debug
      L3_2 = "PRISON BREAK: Reset was done by system!"
      L2_2(L3_2)
    end
    L2_2 = StartClient
    L3_2 = -1
    L4_2 = "ResetPrisonBreak"
    L5_2 = A1_2
    L2_2(L3_2, L4_2, L5_2)
  elseif A0_2 then
    L2_2 = Framework
    L2_2 = L2_2.sendNotification
    L3_2 = A0_2
    L4_2 = _U
    L5_2 = "PRISON_BREAK.IS_NOT_ACTIVE"
    L4_2 = L4_2(L5_2)
    L5_2 = "error"
    L2_2(L3_2, L4_2, L5_2)
  end
end
PrisonBreakReset = L4_1
function L4_1()
  local L0_2, L1_2
end
SavePrisonBreakIntoKVP = L4_1
function L4_1()
  local L0_2, L1_2
end
LoadPrisonBreakFromKVP = L4_1
L4_1 = NetworkService
L4_1 = L4_1.EventListener
L5_1 = "heartbeat"
function L6_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = HEARTBEAT_EVENTS
  L2_2 = L2_2.PRISONER_NEW
  if A0_2 == L2_2 then
    L2_2 = A1_2.prisoner
    if not L2_2 then
      return
    end
    L3_2 = L2_2.source
    if not L3_2 then
      return
    end
    L4_2 = SyncPrisonBreak
    L5_2 = L3_2
    L6_2 = false
    L4_2(L5_2, L6_2)
  end
end
L4_1(L5_1, L6_1)
function L4_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = Config
  L1_2 = L1_2.Escape
  L1_2 = L1_2.PoliceCheck
  if L1_2 then
    L1_2 = Framework
    L1_2 = L1_2.canStartPrisonBreak
    L1_2 = L1_2()
    if not L1_2 then
      L1_2 = dbg
      L1_2 = L1_2.debug
      L2_2 = "Failed to start Prison break, not enough police officers!"
      L1_2(L2_2)
      L1_2 = Framework
      L1_2 = L1_2.sendNotification
      L2_2 = A0_2
      L3_2 = _U
      L4_2 = "PRISON_BREAK.NOT_ENOUGH_POLICE"
      L3_2 = L3_2(L4_2)
      L4_2 = "error"
      return L1_2(L2_2, L3_2, L4_2)
    end
  end
  L1_2 = Config
  L1_2 = L1_2.Escape
  L1_2 = L1_2.NeedItem
  if L1_2 then
    L1_2 = Inventory
    L1_2 = L1_2.hasItem
    L2_2 = A0_2
    L3_2 = Config
    L3_2 = L3_2.Escape
    L3_2 = L3_2.ItemName
    L4_2 = 1
    L1_2 = L1_2(L2_2, L3_2, L4_2)
    if not L1_2 then
      L1_2 = Framework
      L1_2 = L1_2.sendNotification
      L2_2 = A0_2
      L3_2 = _U
      L4_2 = "PRISON_BREAK.ITEM_REQUIRED"
      L5_2 = _U
      L6_2 = "GENERAL.WIRE_CUTTER_LABEL"
      L5_2, L6_2 = L5_2(L6_2)
      L3_2 = L3_2(L4_2, L5_2, L6_2)
      L4_2 = "error"
      return L1_2(L2_2, L3_2, L4_2)
    end
  end
  L2_2 = L1_1
  L1_2 = L2_1
  L1_2 = L1_2[L2_2]
  L1_2 = L1_2.isActive
  if L1_2 then
    L1_2 = Framework
    L1_2 = L1_2.sendNotification
    L2_2 = A0_2
    L3_2 = _U
    L4_2 = "PRISON_BREAK.ACTIVE"
    L3_2 = L3_2(L4_2)
    L4_2 = "error"
    return L1_2(L2_2, L3_2, L4_2)
  end
  L2_2 = L1_1
  L1_2 = L2_1
  L1_2 = L1_2[L2_2]
  L1_2.isActive = true
  L2_2 = L1_1
  L1_2 = L2_1
  L1_2 = L1_2[L2_2]
  L2_2 = {}
  L2_2.playerId = A0_2
  L3_2 = Framework
  L3_2 = L3_2.getIdentifier
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L2_2.charId = L3_2
  L1_2.initiator = L2_2
  L1_2 = Framework
  L1_2 = L1_2.sendNotification
  L2_2 = A0_2
  L3_2 = _U
  L4_2 = "PRISON_BREAK.ACTIVATED"
  L3_2 = L3_2(L4_2)
  L4_2 = "success"
  L1_2(L2_2, L3_2, L4_2)
  L1_2 = SetPrisonBreakLayer
  L2_2 = L1_1
  L3_2 = L0_1
  L1_2(L2_2, L3_2)
  L1_2 = StartClient
  L2_2 = A0_2
  L3_2 = "startPrisonBreakProlog"
  L1_2(L2_2, L3_2)
end
StartPrisonBreak = L4_1
function L4_1(A0_2)
  local L1_2
  L1_2 = L2_1
  L1_2 = L1_2[A0_2]
  return L1_2
end
GetPrisonBreakSession = L4_1
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = L2_1
  L2_2 = L2_2[A0_2]
  L2_2 = L2_2.phase
  if L2_2 == A1_2 then
    return
  end
  L2_2 = L2_1
  L2_2 = L2_2[A0_2]
  L2_2.phase = A1_2
  L2_2 = dbg
  L2_2 = L2_2.debug
  L3_2 = "PRISON BREAK: Phase %s was set as active."
  L4_2 = A1_2
  L2_2(L3_2, L4_2)
end
SetPrisonBreakPhase = L4_1
function L4_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L3_2 = L2_1
  L3_2 = L3_2[A0_2]
  L3_2 = L3_2.interactions
  L3_2 = L3_2[A1_2]
  if L3_2 then
    L3_2 = L2_1
    L3_2 = L3_2[A0_2]
    L3_2 = L3_2.interactions
    L3_2 = L3_2[A1_2]
    L3_2 = L3_2.coords
    L4_2 = L2_1
    L4_2 = L4_2[A0_2]
    L4_2 = L4_2.interactions
    L4_2 = L4_2[A1_2]
    L4_2.state = A2_2
    if L3_2 then
      L4_2 = L2_1
      L4_2 = L4_2[A0_2]
      L4_2 = L4_2.interactions
      L4_2 = L4_2[A1_2]
      L5_2 = GatherPlayersAroundTheWall
      L6_2 = L3_2
      L5_2 = L5_2(L6_2)
      L4_2.players = L5_2
    end
  end
  L3_2 = StartClient
  L4_2 = -1
  L5_2 = "updateWall"
  L6_2 = A1_2
  L7_2 = "setWallState"
  L8_2 = A2_2
  L9_2 = L2_1
  L9_2 = L9_2[A0_2]
  L9_2 = L9_2.interactions
  L9_2 = L9_2[A1_2]
  L9_2 = L9_2.players
  L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2)
end
SetPrisonBreakWallState = L4_1
function L4_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L1_2 = GetPlayers
  L1_2 = L1_2()
  L2_2 = {}
  L3_2 = pairs
  L4_2 = L1_2
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
  for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
    L9_2 = GetPlayerPed
    L10_2 = L8_2
    L9_2 = L9_2(L10_2)
    L10_2 = GetEntityCoords
    L11_2 = L9_2
    L10_2 = L10_2(L11_2)
    L11_2 = L10_2 - A0_2
    L11_2 = #L11_2
    if L11_2 <= 100 then
      L12_2 = L2_2[L8_2]
      if not L12_2 then
        L2_2[L8_2] = true
      end
    end
  end
  return L2_2
end
GatherPlayersAroundTheWall = L4_1
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L2_2 = L2_1
  L2_2 = L2_2[A0_2]
  L2_2 = L2_2.LAYERS
  L2_2 = L2_2[A1_2]
  if L2_2 then
    return
  end
  L2_2 = L2_1
  L2_2 = L2_2[A0_2]
  L2_2 = L2_2.LAYERS
  L2_2[A1_2] = true
  L2_2 = SH
  L2_2 = L2_2.data
  L2_2 = L2_2.PrisonBreak
  L2_2 = L2_2[A0_2]
  L2_2 = L2_2[A1_2]
  if L2_2 then
    L2_2 = SH
    L2_2 = L2_2.data
    L2_2 = L2_2.PrisonBreak
    L2_2 = L2_2[A0_2]
    L2_2 = L2_2[A1_2]
    L3_2 = pairs
    L4_2 = L2_2
    L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
    for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
      L9_2 = "%s_%s_%s"
      L10_2 = L9_2
      L9_2 = L9_2.format
      L11_2 = "ESCAPE"
      L12_2 = L7_2
      L13_2 = A1_2
      L9_2 = L9_2(L10_2, L11_2, L12_2, L13_2)
      L10_2 = L2_1
      L10_2 = L10_2[A0_2]
      L10_2 = L10_2.interactions
      L10_2 = L10_2[L9_2]
      if not L10_2 then
        L10_2 = L2_1
        L10_2 = L10_2[A0_2]
        L10_2 = L10_2.interactions
        L11_2 = {}
        L12_2 = WALL_STATES
        L12_2 = L12_2.FULL_HEALTH
        L11_2.state = L12_2
        L12_2 = L8_2.interactCoords
        L11_2.coords = L12_2
        L11_2.isOccupied = false
        L12_2 = L8_2.zoneType
        L11_2.zoneType = L12_2
        L11_2.breakType = A0_2
        L11_2.layerName = A1_2
        L10_2[L9_2] = L11_2
      end
    end
  end
  L2_2 = SetTimeout
  L3_2 = 1000
  function L4_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3
    L0_3 = StartClient
    L1_3 = -1
    L2_3 = "registerEscapeRoutes"
    L4_3 = A0_2
    L3_3 = L2_1
    L3_3 = L3_3[L4_3]
    L3_3 = L3_3.interactions
    L0_3(L1_3, L2_3, L3_3)
  end
  L2_2(L3_2, L4_2)
  L2_2 = dbg
  L2_2 = L2_2.debug
  L3_2 = "PRISON BREAK: Layer %s was set as active."
  L4_2 = A1_2
  L2_2(L3_2, L4_2)
  if "SECOND_LAYER" == A1_2 then
    L2_2 = Config
    L2_2 = L2_2.Escape
    L2_2 = L2_2.EnableAutomaticReset
    if L2_2 then
      L2_2 = dbg
      L2_2 = L2_2.debug
      L3_2 = "PRISON BREAK: Activated automatic Prison break restart"
      L2_2(L3_2)
      L2_2 = SetTimeout
      L3_2 = Config
      L3_2 = L3_2.Escape
      L3_2 = L3_2.ResetTime
      L3_2 = 60000 * L3_2
      function L4_2()
        local L0_3, L1_3
        L0_3 = dbg
        L0_3 = L0_3.debug
        L1_3 = "PRISON BREAK: Automatic Prison break restart was done, time reached!"
        L0_3(L1_3)
        L0_3 = PrisonBreakReset
        L0_3()
      end
      L2_2(L3_2, L4_2)
    end
  end
end
SetPrisonBreakLayer = L4_1
function L4_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = StartClient
  L2_2 = A0_2
  L3_2 = "setAlarm"
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
end
StopAlarmServer = L4_1
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2
  L2_2 = L2_1
  if not L2_2 then
    return
  end
  L2_2 = Wait
  L3_2 = 1000
  L2_2(L3_2)
  L2_2 = pairs
  L3_2 = L2_1
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = L7_2.isActive
    if L8_2 then
      if A1_2 then
        L8_2 = StartClient
        L9_2 = A0_2
        L10_2 = "restoreSwapSessions"
        L11_2 = L7_2.swapSessions
        L8_2(L9_2, L10_2, L11_2)
        return
      end
      L8_2 = StartClient
      L9_2 = A0_2
      L10_2 = "registerLayers"
      L11_2 = L2_1
      L11_2 = L11_2[L6_2]
      L11_2 = L11_2.interactions
      L8_2(L9_2, L10_2, L11_2)
      L8_2 = Wait
      L9_2 = 1000
      L8_2(L9_2)
      L8_2 = L2_1
      L8_2 = L8_2[L6_2]
      L8_2 = L8_2.interactions
      if L8_2 then
        L8_2 = pairs
        L9_2 = L2_1
        L9_2 = L9_2[L6_2]
        L9_2 = L9_2.interactions
        L8_2, L9_2, L10_2, L11_2 = L8_2(L9_2)
        for L12_2, L13_2 in L8_2, L9_2, L10_2, L11_2 do
          L14_2 = StartClient
          L15_2 = A0_2
          L16_2 = "updateWall"
          L17_2 = L12_2
          L18_2 = "setWallState"
          L19_2 = L13_2.state
          L20_2 = L13_2.players
          L14_2(L15_2, L16_2, L17_2, L18_2, L19_2, L20_2)
        end
      end
    end
    if A1_2 then
      return
    end
    L8_2 = L7_2.isActive
    if L8_2 then
      L8_2 = L7_2.phase
      if "ESCAPE" == L8_2 then
        L8_2 = L7_2.swapSessions
        L8_2 = #L8_2
        if L8_2 > 0 then
          L8_2 = L7_2.isAlarmActive
          if not L8_2 then
            return
          end
          L8_2 = StartClient
          L9_2 = A0_2
          L10_2 = "setAlarm"
          L11_2 = true
          L8_2(L9_2, L10_2, L11_2)
      end
    end
    else
      L8_2 = StartClient
      L9_2 = A0_2
      L10_2 = "setAlarm"
      L11_2 = false
      L8_2(L9_2, L10_2, L11_2)
    end
  end
end
SyncPrisonBreak = L4_1
L4_1 = RegisterNetEvent
L5_1 = "rcore_prison:server:prisonBreakGuardSpottedBrokenWall"
function L6_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if not A0_2 then
    return
  end
  L2_2 = source
  L3_2 = NetworkGetEntityFromNetworkId
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = GetEntityCoords
  L5_2 = L3_2
  L4_2 = L4_2(L5_2)
  L5_2 = GetPrisonBreakSession
  L6_2 = "WALLS"
  L5_2 = L5_2(L6_2)
  L6_2 = L5_2.isAlarmActive
  if L6_2 then
    return
  end
  L6_2 = L5_2.interactions
  L6_2 = L6_2[A1_2]
  if not L6_2 then
    return
  end
  if L6_2 then
    L7_2 = L6_2.state
    L8_2 = WALL_STATES
    L8_2 = L8_2.DESTROYED
    if L7_2 ~= L8_2 then
      return
    end
  end
  L7_2 = L6_2.coords
  L7_2 = L7_2 - L4_2
  L7_2 = #L7_2
  if L7_2 >= 20.0 then
    return
  end
  L8_2 = StartPrisonBreakAlarm
  L8_2()
  L8_2 = Dispatch
  L8_2 = L8_2.Breakout
  L9_2 = L2_2
  L8_2(L9_2)
  L8_2 = dbg
  L8_2 = L8_2.debug
  L9_2 = "PRISON BREAK: Guard spotted broken wall at %s %s %s"
  L10_2 = A1_2
  L11_2 = A0_2
  L12_2 = L4_2
  L8_2(L9_2, L10_2, L11_2, L12_2)
end
L4_1(L5_1, L6_1)
function L4_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = GetPrisonBreakSession
  L1_2 = "WALLS"
  L0_2 = L0_2(L1_2)
  L1_2 = L0_2.isAlarmActive
  if L1_2 then
    return
  end
  L0_2.isAlarmActive = true
  L1_2 = StartClient
  L2_2 = -1
  L3_2 = "setAlarm"
  L4_2 = true
  L1_2(L2_2, L3_2, L4_2)
  L1_2 = dbg
  L1_2 = L1_2.debug
  L2_2 = "PRISON BREAK: Alarm was activated!"
  L1_2(L2_2)
end
StartPrisonBreakAlarm = L4_1
L4_1 = EventLimiterService
L4_1 = L4_1.RegisterNetEvent
L5_1 = "rcore_prison:server:prisonBreakUserSpotted"
L6_1 = 0
L7_1 = 1
function L8_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  if A1_2 then
    if not A2_2 then
      return
    end
    L3_2 = NetworkGetEntityFromNetworkId
    L4_2 = A2_2
    L3_2 = L3_2(L4_2)
    L4_2 = GetEntityCoords
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    L5_2 = GetPlayerPed
    L6_2 = A0_2
    L5_2 = L5_2(L6_2)
    L6_2 = GetEntityCoords
    L7_2 = L5_2
    L6_2 = L6_2(L7_2)
    L7_2 = L4_2 - L6_2
    L7_2 = #L7_2
    if L7_2 >= 20.0 then
      L8_2 = dbg
      L8_2 = L8_2.debug
      L9_2 = "Player is more >= 20 meters away from initiator ped!"
      return L8_2(L9_2)
    end
    L8_2 = PrisonService
    L8_2 = L8_2.getPlayer
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    if not L8_2 then
      return
    end
    L9_2 = GetPrisonBreakSession
    L10_2 = "WALLS"
    L9_2 = L9_2(L10_2)
    L10_2 = L9_2.isAlarmActive
    if not L10_2 then
      L10_2 = StartPrisonBreakAlarm
      L10_2()
      L10_2 = Dispatch
      L10_2 = L10_2.Breakout
      L11_2 = A0_2
      L10_2(L11_2)
    end
    L10_2 = Config
    L10_2 = L10_2.Escape
    L10_2 = L10_2.AutoCatch
    if L10_2 then
      L10_2 = dbg
      L10_2 = L10_2.debug
      L11_2 = "Player was catched by guard and sent to solitary service!"
      L10_2(L11_2)
      L10_2 = Inventory
      L10_2 = L10_2.ClearPlayerInventory
      L11_2 = A0_2
      L10_2(L11_2)
      L10_2 = SolitaryService
      L10_2 = L10_2.SetPrisonerSentence
      L11_2 = A0_2
      L12_2 = Config
      L12_2 = L12_2.Escape
      L12_2 = L12_2.SolitaryTime
      L13_2 = _U
      L14_2 = "PRISON_BREAK.CAUGHT_BY_GUARD"
      L13_2, L14_2 = L13_2(L14_2)
      L10_2(L11_2, L12_2, L13_2, L14_2)
      L10_2 = Framework
      L10_2 = L10_2.sendNotification
      L11_2 = A0_2
      L12_2 = _U
      L13_2 = "PRISON_BREAK.CAUGHT_BY_GUARD"
      L12_2 = L12_2(L13_2)
      L13_2 = "error"
      L10_2(L11_2, L12_2, L13_2)
      L10_2 = PrisonBreakReset
      L11_2 = A0_2
      L12_2 = true
      L10_2(L11_2, L12_2)
    end
  end
end
L4_1(L5_1, L6_1, L7_1, L8_1)
L4_1 = EventLimiterService
L4_1 = L4_1.RegisterNetEvent
L5_1 = "rcore_prison:server:requestRepairWall"
L6_1 = 0
L7_1 = 1
function L8_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if A1_2 then
    if not A2_2 then
      return
    end
    L3_2 = PrisonService
    L3_2 = L3_2.getPlayer
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if L3_2 then
      return
    end
    L4_2 = A2_2.zoneId
    L5_2 = A2_2.breakType
    L6_2 = GetPrisonBreakSession
    L7_2 = L5_2
    L6_2 = L6_2(L7_2)
    L7_2 = L6_2.interactions
    L7_2 = L7_2[L4_2]
    L8_2 = Framework
    L8_2 = L8_2.canPerformJobCommand
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    if not L8_2 then
      L8_2 = Framework
      L8_2 = L8_2.sendNotification
      L9_2 = A0_2
      L10_2 = _U
      L11_2 = "PRISON_BREAK.NOT_IN_JOB"
      L10_2 = L10_2(L11_2)
      L11_2 = "error"
      return L8_2(L9_2, L10_2, L11_2)
    end
    if L7_2 then
      L8_2 = L7_2.state
      L9_2 = WALL_STATES
      L9_2 = L9_2.DESTROYED
      if L8_2 ~= L9_2 then
        return
      end
    end
    if L7_2 then
      L8_2 = L7_2.isOccupied
      if L8_2 then
        L8_2 = Framework
        L8_2 = L8_2.sendNotification
        L9_2 = A0_2
        L10_2 = _U
        L11_2 = "PRISON_BREAK.INTERACT_ALREADY_DONE"
        L10_2 = L10_2(L11_2)
        L11_2 = "error"
        return L8_2(L9_2, L10_2, L11_2)
      end
    end
    L8_2 = IsPlayerAtInteractPoint
    L9_2 = A0_2
    L10_2 = L7_2.coords
    L8_2 = L8_2(L9_2, L10_2)
    if not L8_2 then
      L8_2 = Framework
      L8_2 = L8_2.sendNotification
      L9_2 = A0_2
      L10_2 = _U
      L11_2 = "PRISON_BREAK.NOT_AT_INTERACTION"
      L10_2 = L10_2(L11_2)
      L11_2 = "error"
      return L8_2(L9_2, L10_2, L11_2)
    end
    L7_2.isOccupied = true
    L8_2 = Framework
    L8_2 = L8_2.getIdentifier
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    L7_2.charId = L8_2
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "PRISON BREAK: Interaction repair wall %s was registered by %s (%s)"
    L10_2 = L4_2
    L11_2 = GetPlayerName
    L12_2 = A0_2
    L11_2 = L11_2(L12_2)
    L12_2 = A0_2
    L8_2(L9_2, L10_2, L11_2, L12_2)
    L8_2 = StartClient
    L9_2 = A0_2
    L10_2 = "startInteractTask"
    L11_2 = L4_2
    L12_2 = "REPAIR_WALL"
    L8_2(L9_2, L10_2, L11_2, L12_2)
    L8_2 = SetTimeout
    L9_2 = Config
    L9_2 = L9_2.Escape
    L9_2 = L9_2.RepairWallTime
    L9_2 = L9_2 * 1000
    function L10_2()
      local L0_3, L1_3, L2_3, L3_3
      L0_3 = SetPrisonBreakWallState
      L1_3 = L5_2
      L2_3 = L4_2
      L3_3 = WALL_STATES
      L3_3 = L3_3.FULL_HEALTH
      L0_3(L1_3, L2_3, L3_3)
      L0_3 = StartClient
      L1_3 = -1
      L2_3 = "syncRepairWall"
      L3_3 = L7_2.coords
      L0_3(L1_3, L2_3, L3_3)
      L7_2.isOccupied = false
      L7_2.charId = nil
    end
    L8_2(L9_2, L10_2)
  end
end
L4_1(L5_1, L6_1, L7_1, L8_1)
L4_1 = EventLimiterService
L4_1 = L4_1.RegisterNetEvent
L5_1 = "rcore_prison:server:requestEscapeInteract"
L6_1 = 0
L7_1 = 1
function L8_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if A1_2 then
    if not A2_2 then
      return
    end
    L3_2 = A2_2.zoneId
    L4_2 = A2_2.breakType
    L5_2 = GetPrisonBreakSession
    L6_2 = L4_2
    L5_2 = L5_2(L6_2)
    L6_2 = L5_2.interactions
    L6_2 = L6_2[L3_2]
    if L6_2 then
      L7_2 = L6_2.state
      L8_2 = WALL_STATES
      L8_2 = L8_2.DESTROYED
      if L7_2 == L8_2 then
        L7_2 = dbg
        L7_2 = L7_2.debug
        L8_2 = "PRISON BREAK: Interaction %s is already destroyed."
        L9_2 = L3_2
        return L7_2(L8_2, L9_2)
      end
    end
    if L6_2 then
      L7_2 = L6_2.isOccupied
      if L7_2 then
        L7_2 = dbg
        L7_2 = L7_2.debug
        L8_2 = "PRISON BREAK: Interaction %s is already occupied."
        L9_2 = L3_2
        L7_2(L8_2, L9_2)
        L7_2 = Framework
        L7_2 = L7_2.sendNotification
        L8_2 = A0_2
        L9_2 = _U
        L10_2 = "PRISON_BREAK.INTERACT_ALREADY_DONE"
        L9_2 = L9_2(L10_2)
        L10_2 = "error"
        return L7_2(L8_2, L9_2, L10_2)
      end
    end
    L7_2 = IsPlayerAtInteractPoint
    L8_2 = A0_2
    L9_2 = L6_2.coords
    L7_2 = L7_2(L8_2, L9_2)
    if not L7_2 then
      L7_2 = dbg
      L7_2 = L7_2.debug
      L8_2 = "PRISON BREAK: Player %s is not at interaction point."
      L9_2 = GetPlayerName
      L10_2 = A0_2
      L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
      L7_2(L8_2, L9_2, L10_2, L11_2, L12_2)
      L7_2 = Framework
      L7_2 = L7_2.sendNotification
      L8_2 = A0_2
      L9_2 = _U
      L10_2 = "PRISON_BREAK.NOT_AT_INTERACTION"
      L9_2 = L9_2(L10_2)
      L10_2 = "error"
      return L7_2(L8_2, L9_2, L10_2)
    end
    if "WALLS" == L4_2 then
      L7_2 = Config
      L7_2 = L7_2.Escape
      L7_2 = L7_2.NeedItem
      if L7_2 then
        L7_2 = Inventory
        L7_2 = L7_2.hasItem
        L8_2 = A0_2
        L9_2 = Config
        L9_2 = L9_2.Escape
        L9_2 = L9_2.ItemName
        L10_2 = 1
        L7_2 = L7_2(L8_2, L9_2, L10_2)
        if not L7_2 then
          L7_2 = dbg
          L7_2 = L7_2.debug
          L8_2 = "PRISON BREAK: Player %s does not have required item."
          L9_2 = GetPlayerName
          L10_2 = A0_2
          L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
          L7_2(L8_2, L9_2, L10_2, L11_2, L12_2)
          L7_2 = Framework
          L7_2 = L7_2.sendNotification
          L8_2 = A0_2
          L9_2 = _U
          L10_2 = "PRISON_BREAK.NO_ITEM"
          L9_2 = L9_2(L10_2)
          L10_2 = "error"
          return L7_2(L8_2, L9_2, L10_2)
        end
      end
    end
    L7_2 = L5_2.swapSessions
    L7_2 = #L7_2
    L7_2 = L7_2 + 1
    L6_2.isOccupied = true
    L8_2 = Framework
    L8_2 = L8_2.getIdentifier
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    L6_2.charId = L8_2
    L6_2.sessionId = L7_2
    if "WALLS" == L4_2 then
      L8_2 = L5_2.swapSessions
      L9_2 = {}
      L10_2 = L6_2.coords
      L9_2.pos = L10_2
      L8_2[L7_2] = L9_2
    end
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "PRISON BREAK: Interaction %s was registered by %s (%s)"
    L10_2 = L3_2
    L11_2 = GetPlayerName
    L12_2 = A0_2
    L11_2 = L11_2(L12_2)
    L12_2 = A0_2
    L8_2(L9_2, L10_2, L11_2, L12_2)
    L8_2 = StartClient
    L9_2 = A0_2
    L10_2 = "startInteractTask"
    L11_2 = L3_2
    L12_2 = L4_2
    L8_2(L9_2, L10_2, L11_2, L12_2)
  end
end
L4_1(L5_1, L6_1, L7_1, L8_1)
L4_1 = EventLimiterService
L4_1 = L4_1.RegisterNetEvent
L5_1 = "rcore_prison:server:registerEscapeExitZone"
L6_1 = 0
L7_1 = 1
function L8_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2
  if A1_2 then
    if not A2_2 then
      return
    end
    L3_2 = PrisonService
    L3_2 = L3_2.getPlayer
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      return
    end
    L4_2 = A2_2.zoneId
    L5_2 = A2_2.breakType
    L6_2 = GetPrisonBreakSession
    L7_2 = L5_2
    L6_2 = L6_2(L7_2)
    if not L6_2 then
      return
    end
    L7_2 = L6_2.phase
    if "ESCAPE" ~= L7_2 then
      return
    end
    L7_2 = L6_2.interactions
    L7_2 = L7_2[L4_2]
    if not L7_2 then
      return
    end
    if L7_2 then
      L8_2 = L7_2.state
      L9_2 = WALL_STATES
      L9_2 = L9_2.DESTROYED
      if L8_2 ~= L9_2 then
        return
      end
    end
    L8_2 = IsPlayerAtInteractPoint
    L9_2 = A0_2
    L10_2 = L7_2.coords
    L8_2 = L8_2(L9_2, L10_2)
    if not L8_2 then
      L8_2 = Framework
      L8_2 = L8_2.sendNotification
      L9_2 = A0_2
      L10_2 = _U
      L11_2 = "PRISON_BREAK.NOT_AT_INTERACTION"
      L10_2 = L10_2(L11_2)
      L11_2 = "error"
      return L8_2(L9_2, L10_2, L11_2)
    end
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "PRISON BREAK: Prisoner %s (%s) has escaped from prison!"
    L10_2 = GetPlayerName
    L11_2 = A0_2
    L10_2 = L10_2(L11_2)
    L11_2 = A0_2
    L8_2(L9_2, L10_2, L11_2)
    L8_2 = LogService
    L8_2 = L8_2.RegisterTransaction
    L9_2 = "PRISON_BREAK"
    L10_2 = _U
    L11_2 = "LOGS_ACTIONS.LOG_CITIZEN_ESCAPED_PRISON"
    L12_2 = L3_2.prisonerName
    L10_2 = L10_2(L11_2, L12_2)
    L11_2 = L3_2.owner
    L12_2 = "-"
    L13_2 = L3_2.prisonerName
    L8_2(L9_2, L10_2, L11_2, L12_2, L13_2)
    L8_2 = PrisonService
    L8_2 = L8_2.UnjailCitizen
    L9_2 = A0_2
    L10_2 = false
    L11_2 = true
    L8_2(L9_2, L10_2, L11_2)
    L8_2 = Logs
    L8_2 = L8_2.Sent
    L9_2 = "PRISON_BREAK"
    L10_2 = _U
    L11_2 = "PRISON_BREAK.DISCORD_PRISONER_HAS_ESCAPED_FROM_PRISON_LABEL"
    L10_2 = L10_2(L11_2)
    L11_2 = {}
    L12_2 = {}
    L13_2 = _U
    L14_2 = "PRISON_BREAK.DISCORD_OOC_LABEL"
    L13_2 = L13_2(L14_2)
    L12_2.name = L13_2
    L13_2 = GetPlayerName
    L14_2 = A0_2
    L13_2 = L13_2(L14_2)
    L12_2.value = L13_2
    L13_2 = {}
    L14_2 = _U
    L15_2 = "PRISON_BREAK.DISCORD_PLAYER_ID_LABEL"
    L14_2 = L14_2(L15_2)
    L13_2.name = L14_2
    L13_2.value = A0_2
    L14_2 = {}
    L15_2 = _U
    L16_2 = "PRISON_BREAK.DISCORD_CHAR_ID_LABEL"
    L15_2 = L15_2(L16_2)
    L14_2.name = L15_2
    L15_2 = Framework
    L15_2 = L15_2.getIdentifier
    L16_2 = A0_2
    L15_2 = L15_2(L16_2)
    L14_2.value = L15_2
    L15_2 = {}
    L16_2 = _U
    L17_2 = "PRISON_BREAK.DISCORD_BREAK_TYPE_LABEL"
    L16_2 = L16_2(L17_2)
    L15_2.name = L16_2
    L15_2.value = L5_2
    L11_2[1] = L12_2
    L11_2[2] = L13_2
    L11_2[3] = L14_2
    L11_2[4] = L15_2
    L8_2(L9_2, L10_2, L11_2)
    L8_2 = PrisonService
    L8_2 = L8_2.SendHeartbeat
    L9_2 = HEARTBEAT_EVENTS
    L9_2 = L9_2.PLAYER_ESCAPE_FROM_PRISON
    L10_2 = {}
    L10_2.prisoner = L3_2
    L8_2(L9_2, L10_2)
    L8_2 = Framework
    L8_2 = L8_2.sendNotification
    L9_2 = A0_2
    L10_2 = _U
    L11_2 = "PRISON_BREAK.PRISONER_ESCAPED_RELEASE_MESSAGE"
    L10_2 = L10_2(L11_2)
    L11_2 = "success"
    L8_2(L9_2, L10_2, L11_2)
    L8_2 = Framework
    L8_2 = L8_2.getIdentifier
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    L9_2 = Config
    L9_2 = L9_2.Escape
    L9_2 = L9_2.WhenEscapeRemoveInmateStash
    if L9_2 then
      L9_2 = db
      L9_2 = L9_2.RemoveStashItems
      L10_2 = L8_2
      L9_2(L10_2)
    end
  end
end
L4_1(L5_1, L6_1, L7_1, L8_1)
L4_1 = EventLimiterService
L4_1 = L4_1.RegisterNetEvent
L5_1 = "rcore_prison:server:EscapeInteractFinishTask"
L6_1 = 0
L7_1 = 1
function L8_1(A0_2, A1_2, A2_2, A3_2, A4_2)
  local L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2
  if A1_2 then
    if not A3_2 then
      return
    end
    L5_2 = GetPrisonBreakSession
    L6_2 = A2_2
    L5_2 = L5_2(L6_2)
    L6_2 = L5_2.interactions
    L6_2 = L6_2[A3_2]
    if not L6_2 then
      return
    end
    L7_2 = IsPlayerAtInteractPoint
    L8_2 = A0_2
    L9_2 = L6_2.coords
    L7_2 = L7_2(L8_2, L9_2)
    if not L7_2 then
      L7_2 = Framework
      L7_2 = L7_2.sendNotification
      L8_2 = A0_2
      L9_2 = _U
      L10_2 = "PRISON_BREAK.NOT_AT_INTERACTION"
      L9_2 = L9_2(L10_2)
      L10_2 = "error"
      return L7_2(L8_2, L9_2, L10_2)
    end
    L7_2 = L6_2.charId
    L8_2 = Framework
    L8_2 = L8_2.getIdentifier
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    if L7_2 ~= L8_2 then
      return
    end
    L7_2 = PrisonService
    L7_2 = L7_2.getPlayer
    L8_2 = A0_2
    L7_2 = L7_2(L8_2)
    L8_2 = PrisonService
    L8_2 = L8_2.SendHeartbeat
    L9_2 = HEARTBEAT_EVENTS
    L9_2 = L9_2.PLAYER_DESTROYED_WALL
    L10_2 = {}
    L10_2.prisoner = L7_2
    L8_2(L9_2, L10_2)
    L8_2 = L6_2.zoneType
    L9_2 = L6_2.layerName
    if "WALLS" == A2_2 then
      L10_2 = StartClient
      L11_2 = -1
      L12_2 = "destroyWall"
      L13_2 = A3_2
      L14_2 = A2_2
      L15_2 = L9_2
      L10_2(L11_2, L12_2, L13_2, L14_2, L15_2)
    end
    L10_2 = Logs
    L10_2 = L10_2.Sent
    L11_2 = "PRISON_BREAK"
    L12_2 = _U
    L13_2 = "PRISON_BREAK.DISCORD_PRISONER_HAS_FINISHED_TASK_LABEL"
    L12_2 = L12_2(L13_2)
    L13_2 = {}
    L14_2 = {}
    L15_2 = _U
    L16_2 = "PRISON_BREAK.DISCORD_OOC_LABEL"
    L15_2 = L15_2(L16_2)
    L14_2.name = L15_2
    L15_2 = GetPlayerName
    L16_2 = A0_2
    L15_2 = L15_2(L16_2)
    L14_2.value = L15_2
    L15_2 = {}
    L16_2 = _U
    L17_2 = "PRISON_BREAK.DISCORD_PLAYER_ID_LABEL"
    L16_2 = L16_2(L17_2)
    L15_2.name = L16_2
    L15_2.value = A0_2
    L16_2 = {}
    L17_2 = _U
    L18_2 = "PRISON_BREAK.DISCORD_BREAK_TYPE_LABEL"
    L17_2 = L17_2(L18_2)
    L16_2.name = L17_2
    L16_2.value = A2_2
    L17_2 = {}
    L18_2 = _U
    L19_2 = "PRISON_BREAK.DISCORD_PATH_LAYER_LABEL"
    L18_2 = L18_2(L19_2)
    L17_2.name = L18_2
    L17_2.value = L9_2
    L18_2 = {}
    L19_2 = _U
    L20_2 = "PRISON_BREAK.DISCORD_ZONE_ID_LABEL"
    L19_2 = L19_2(L20_2)
    L18_2.name = L19_2
    L18_2.value = A3_2
    L13_2[1] = L14_2
    L13_2[2] = L15_2
    L13_2[3] = L16_2
    L13_2[4] = L17_2
    L13_2[5] = L18_2
    L10_2(L11_2, L12_2, L13_2)
    L10_2 = SetPrisonBreakWallState
    L11_2 = A2_2
    L12_2 = A3_2
    L13_2 = WALL_STATES
    L13_2 = L13_2.DESTROYED
    L10_2(L11_2, L12_2, L13_2)
    L6_2.isOccupied = false
    L6_2.charId = nil
    if "SECOND_LAYER" ~= L9_2 then
      L10_2 = Framework
      L10_2 = L10_2.sendNotification
      L11_2 = A0_2
      L12_2 = _U
      L13_2 = "PRISON_BREAK.INTERACT_DONE"
      L12_2 = L12_2(L13_2)
      L13_2 = "success"
      L10_2(L11_2, L12_2, L13_2)
    end
    if "INNER" == L8_2 then
      L10_2 = SetPrisonBreakLayer
      L11_2 = A2_2
      L12_2 = "SECOND_LAYER"
      L10_2(L11_2, L12_2)
    elseif "INNER" ~= L8_2 then
      L10_2 = L5_2.phase
      if "BREAKING_WALLS" == L10_2 then
        L10_2 = SetPrisonBreakPhase
        L11_2 = A2_2
        L12_2 = "ESCAPE"
        L10_2(L11_2, L12_2)
      end
    end
  end
end
L4_1(L5_1, L6_1, L7_1, L8_1)
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  if not A0_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = GetPlayerPed
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = GetEntityCoords
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = L3_2 - A1_2
  L4_2 = #L4_2
  L5_2 = L4_2 <= 8.0
  return L5_2
end
IsPlayerAtInteractPoint = L4_1
L4_1 = {}
L5_1 = {}
function L6_1()
  local L0_2, L1_2
  L0_2 = L4_1
  return L0_2
end
GetPatrollingGuards = L6_1
function L6_1(A0_2)
  local L1_2
  L1_2 = L5_1
  L1_2 = L1_2[A0_2]
  if L1_2 then
    L1_2 = L5_1
    L1_2[A0_2] = nil
  end
end
RemoveNearPlayers = L6_1
L6_1 = CreateThread
function L7_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2
  L0_2 = 0
  repeat
    L1_2 = Wait
    L2_2 = 250
    L1_2(L2_2)
    L0_2 = L0_2 + 1
    if L0_2 >= 50 then
      L1_2 = dbg
      L1_2 = L1_2.critical
      L2_2 = "Failed to load prison map in sv-l-prisonbreak."
      L1_2(L2_2)
      break
    end
    L1_2 = L3_1
  until L1_2
  L1_2 = SH
  L1_2 = L1_2.data
  if not L1_2 then
    return
  end
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.interaction
  if not L1_2 then
    return
  end
  L1_2 = Config
  L1_2 = L1_2.Escape
  L1_2 = L1_2.DisablePatrollingGuards
  if L1_2 then
    return
  end
  while true do
    L1_2 = Wait
    L2_2 = 1500
    L1_2(L2_2)
    L1_2 = GetPlayers
    L1_2 = L1_2()
    L2_2 = vec3
    L3_2 = SH
    L3_2 = L3_2.data
    L3_2 = L3_2.prisonYard
    L3_2 = L3_2.x
    L4_2 = SH
    L4_2 = L4_2.data
    L4_2 = L4_2.prisonYard
    L4_2 = L4_2.y
    L5_2 = SH
    L5_2 = L5_2.data
    L5_2 = L5_2.prisonYard
    L5_2 = L5_2.z
    L2_2 = L2_2(L3_2, L4_2, L5_2)
    L3_2 = pairs
    L4_2 = L1_2
    L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
    for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
      L9_2 = GetPlayerPed
      L10_2 = L8_2
      L9_2 = L9_2(L10_2)
      L10_2 = GetEntityCoords
      L11_2 = L9_2
      L10_2 = L10_2(L11_2)
      L11_2 = L10_2 - L2_2
      L11_2 = #L11_2
      L12_2 = 400
      if L11_2 <= L12_2 then
        L12_2 = L5_1
        L12_2[L8_2] = true
      else
        L12_2 = L5_1
        L12_2[L8_2] = nil
      end
    end
    L3_2 = table
    L3_2 = L3_2.len
    L4_2 = L5_1
    L3_2 = L3_2(L4_2)
    if 0 == L3_2 then
      L3_2 = next
      L4_2 = L4_1
      L3_2 = L3_2(L4_2)
      if L3_2 then
        L3_2 = dbg
        L3_2 = L3_2.debug
        L4_2 = "Despawning all guards"
        L3_2(L4_2)
        L3_2 = deleteGuards
        L4_2 = L4_1
        L3_2(L4_2)
        L3_2 = {}
        L4_1 = L3_2
    end
    else
      L3_2 = next
      L4_2 = L5_1
      L3_2 = L3_2(L4_2)
      if L3_2 then
        L3_2 = next
        L4_2 = L4_1
        L3_2 = L3_2(L4_2)
        if nil == L3_2 then
          L3_2 = SH
          L3_2 = L3_2.data
          L3_2 = L3_2.guards
          if L3_2 then
            L3_2 = spawnGuards
            L4_2 = SH
            L4_2 = L4_2.data
            L4_2 = L4_2.guards
            L3_2 = L3_2(L4_2)
            L4_1 = L3_2
            L3_2 = dbg
            L3_2 = L3_2.debug
            L4_2 = "Spawning guards"
            L3_2(L4_2)
            L3_2 = Wait
            L4_2 = 1000
            L3_2(L4_2)
            L3_2 = StartClient
            L4_2 = -1
            L5_2 = "guards"
            L6_2 = L4_1
            L3_2(L4_2, L5_2, L6_2)
        end
      end
      else
        L3_2 = next
        L4_2 = L5_1
        L3_2 = L3_2(L4_2)
        if L3_2 then
          L3_2 = pairs
          L4_2 = L4_1
          L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
          for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
            L9_2 = NetworkGetEntityFromNetworkId
            L10_2 = L8_2.netId
            L9_2 = L9_2(L10_2)
            L10_2 = GetEntityHealth
            L11_2 = L9_2
            L10_2 = L10_2(L11_2)
            if L10_2 <= 0 then
              L10_2 = L8_2.isDead
              if not L10_2 then
                L8_2.isDead = true
                L10_2 = L8_2
                L11_2 = DeleteEntity
                L12_2 = L9_2
                L11_2(L12_2)
                L11_2 = dbg
                L11_2 = L11_2.debug
                L12_2 = "Guard %s is dead, setting respawn timer"
                L13_2 = L8_2.netId
                L11_2(L12_2, L13_2)
                L11_2 = Wait
                L12_2 = 500
                L11_2(L12_2)
                if L10_2 then
                  L11_2 = SH
                  L11_2 = L11_2.data
                  L11_2 = L11_2.guards
                  L12_2 = L10_2.idx
                  L11_2 = L11_2[L12_2]
                  L12_2 = STRUCT_POS
                  L12_2 = L11_2[L12_2]
                  if not L12_2 then
                    return
                  end
                  L12_2 = table
                  L12_2 = L12_2.unpack
                  L13_2 = STRUCT_POS
                  L13_2 = L11_2[L13_2]
                  L12_2, L13_2, L14_2 = L12_2(L13_2)
                  L15_2 = CreatePed
                  L16_2 = 1
                  L17_2 = STRUCT_MODEL
                  L17_2 = L11_2[L17_2]
                  L18_2 = L12_2
                  L19_2 = L13_2
                  L20_2 = L14_2
                  L21_2 = STRUCT_HEADING
                  L21_2 = L11_2[L21_2]
                  L22_2 = true
                  L23_2 = false
                  L15_2 = L15_2(L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2)
                  L16_2 = 0
                  while true do
                    L17_2 = DoesEntityExist
                    L18_2 = L15_2
                    L17_2 = L17_2(L18_2)
                    if L17_2 then
                      break
                    end
                    L17_2 = Wait
                    L18_2 = 1
                    L17_2(L18_2)
                    L16_2 = L16_2 + 1
                    if L16_2 >= 50 then
                      L17_2 = dbg
                      L17_2 = L17_2.critical
                      L18_2 = "Failed to spawn ped for guards in prison (sv-l-prisonbreak.lua)"
                      L17_2(L18_2)
                      break
                    end
                  end
                  L17_2 = STRUCT_WEAPON
                  L17_2 = L11_2[L17_2]
                  if nil ~= L17_2 then
                    L17_2 = GiveWeaponToPed
                    L18_2 = L15_2
                    L19_2 = STRUCT_WEAPON
                    L19_2 = L11_2[L19_2]
                    L20_2 = 60
                    L21_2 = false
                    L22_2 = true
                    L17_2(L18_2, L19_2, L20_2, L21_2, L22_2)
                  end
                  L17_2 = NetworkGetNetworkIdFromEntity
                  L18_2 = L15_2
                  L17_2 = L17_2(L18_2)
                  L18_2 = L4_1
                  L18_2 = L18_2[L17_2]
                  if L18_2 then
                    L18_2 = L4_1
                    L18_2 = L18_2[L17_2]
                    L18_2.ped = L15_2
                    L18_2 = L4_1
                    L18_2 = L18_2[L17_2]
                    L18_2.isDead = false
                    L18_2 = L4_1
                    L18_2 = L18_2[L17_2]
                    L18_2.netId = L17_2
                  end
                  L18_2 = Wait
                  L19_2 = 1000
                  L18_2(L19_2)
                  L18_2 = StartClient
                  L19_2 = -1
                  L20_2 = "respawnGuard"
                  L21_2 = L4_1
                  L21_2 = L21_2[L17_2]
                  L18_2(L19_2, L20_2, L21_2)
                end
              end
            end
          end
        end
      end
    end
  end
end
L6_1(L7_1)
function L6_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = pairs
  L2_2 = A0_2
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = L6_2.ped
    L8_2 = DoesEntityExist
    L9_2 = L7_2
    L8_2 = L8_2(L9_2)
    if L8_2 then
      L8_2 = DeleteEntity
      L9_2 = L7_2
      L8_2(L9_2)
    end
  end
end
deleteGuards = L6_1
function L6_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2
  L1_2 = {}
  L2_2 = pairs
  L3_2 = A0_2
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = table
    L8_2 = L8_2.unpack
    L9_2 = STRUCT_POS
    L9_2 = L7_2[L9_2]
    L8_2, L9_2, L10_2 = L8_2(L9_2)
    L11_2 = CreatePed
    L12_2 = 1
    L13_2 = STRUCT_MODEL
    L13_2 = L7_2[L13_2]
    L14_2 = L8_2
    L15_2 = L9_2
    L16_2 = L10_2
    L17_2 = STRUCT_HEADING
    L17_2 = L7_2[L17_2]
    L18_2 = true
    L19_2 = true
    L11_2 = L11_2(L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2)
    L12_2 = 0
    while true do
      L13_2 = DoesEntityExist
      L14_2 = L11_2
      L13_2 = L13_2(L14_2)
      if L13_2 then
        break
      end
      L13_2 = Wait
      L14_2 = 1
      L13_2(L14_2)
      L12_2 = L12_2 + 1
      if L12_2 >= 50 then
        L13_2 = dbg
        L13_2 = L13_2.critical
        L14_2 = "Failed to spawn ped (spawnGuards) for guards in prison (sv-l-prisonbreak.lua)"
        L13_2(L14_2)
        break
      end
    end
    L13_2 = STRUCT_WEAPON
    L13_2 = L7_2[L13_2]
    if nil ~= L13_2 then
      L13_2 = GiveWeaponToPed
      L14_2 = L11_2
      L15_2 = STRUCT_WEAPON
      L15_2 = L7_2[L15_2]
      L16_2 = 60
      L17_2 = false
      L18_2 = true
      L13_2(L14_2, L15_2, L16_2, L17_2, L18_2)
    end
    L13_2 = DoesEntityExist
    L14_2 = L11_2
    L13_2 = L13_2(L14_2)
    if not L13_2 then
      L13_2 = dbg
      L13_2 = L13_2.critical
      L14_2 = "Cannot create guard %s"
      L15_2 = L6_2
      L13_2(L14_2, L15_2)
    end
    L13_2 = NetworkGetNetworkIdFromEntity
    L14_2 = L11_2
    L13_2 = L13_2(L14_2)
    L14_2 = L1_2[L13_2]
    if not L14_2 then
      L14_2 = {}
      L14_2.ped = L11_2
      L14_2.netId = L13_2
      L15_2 = STRUCT_ROUTE
      L15_2 = L7_2[L15_2]
      L14_2.route = L15_2
      L14_2.isDead = false
      L14_2.idx = L6_2
      L1_2[L13_2] = L14_2
    end
  end
  return L1_2
end
spawnGuards = L6_1
L6_1 = AddEventHandler
L7_1 = "onResourceStop"
function L8_1(A0_2)
  local L1_2, L2_2
  L1_2 = GetCurrentResourceName
  L1_2 = L1_2()
  if A0_2 == L1_2 then
    L1_2 = deleteGuards
    L2_2 = L4_1
    L1_2(L2_2)
  end
end
L6_1(L7_1, L8_1)
