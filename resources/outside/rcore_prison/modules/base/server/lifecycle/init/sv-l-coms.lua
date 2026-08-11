local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1
L0_1 = {}
COMS = L0_1
L0_1 = {}
L1_1 = {}
L2_1 = Config
L2_1 = L2_1.COMS
L2_1 = L2_1.Models
L3_1 = COMS
function L4_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L0_2 = json
  L0_2 = L0_2.decode
  L1_2 = LoadResourceFile
  L2_2 = GetCurrentResourceName
  L2_2 = L2_2()
  L3_2 = RESOURCE_FILES
  L3_2 = L3_2.ZONES
  L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2 = L1_2(L2_2, L3_2)
  L0_2 = L0_2(L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
  L1_2 = {}
  L2_2 = {}
  L1_2.vertGroups = L2_2
  L2_2 = promise
  L2_2 = L2_2.new
  L2_2 = L2_2()
  if not L0_2 then
    L3_2 = nil
    return L3_2
  end
  L3_2 = 0
  L4_2 = pairs
  L5_2 = L0_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L3_2 = L3_2 + 1
    L10_2 = L1_2.vertGroups
    L10_2 = L10_2[L8_2]
    if not L10_2 then
      L10_2 = L1_2.vertGroups
      L10_2[L8_2] = L9_2
    end
    L10_2 = #L0_2
    if L3_2 >= L10_2 then
      L11_2 = L2_2
      L10_2 = L2_2.resolve
      L12_2 = true
      L10_2(L11_2, L12_2)
    end
  end
  L4_2 = Citizen
  L4_2 = L4_2.Await
  L5_2 = L2_2
  L4_2(L5_2)
  L4_2 = L1_2.vertGroups
  return L4_2
end
L3_1.GetZoneData = L4_1
L3_1 = {}
L4_1 = {}
L3_1.models = L4_1
L4_1 = COMS
L4_1 = L4_1.GetZoneData
L4_1 = L4_1()
L3_1.vertGroups = L4_1
L4_1 = COMS
function L5_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L0_2 = promise
  L0_2 = L0_2.new
  L0_2 = L0_2()
  L1_2 = 5
  L2_2 = nil
  L3_2 = 1
  L4_2 = L1_2
  L5_2 = 1
  for L6_2 = L3_2, L4_2, L5_2 do
    L7_2 = math
    L7_2 = L7_2.random
    L8_2 = 1
    L9_2 = L3_1.vertGroups
    L9_2 = #L9_2
    L7_2 = L7_2(L8_2, L9_2)
    L8_2 = L1_1
    L8_2 = L8_2[L7_2]
    if not L8_2 then
      L2_2 = L7_2
    end
    if L6_2 == L1_2 then
      L9_2 = L0_2
      L8_2 = L0_2.resolve
      L10_2 = true
      L8_2(L9_2, L10_2)
    end
  end
  L3_2 = Citizen
  L3_2 = L3_2.Await
  L4_2 = L0_2
  L3_2(L4_2)
  return L2_2
end
L4_1.GenerateRandomArea = L5_1
function L4_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = 10
  while L1_2 > 0 do
    L2_2 = math
    L2_2 = L2_2.random
    L3_2 = 1
    L4_2 = L2_1
    L4_2 = #L4_2
    L2_2 = L2_2(L3_2, L4_2)
    L3_2 = L2_1
    L2_2 = L3_2[L2_2]
    L3_2 = A0_2[L2_2]
    if not L3_2 then
      return L2_2
    end
    L1_2 = L1_2 - 1
  end
  L2_2 = math
  L2_2 = L2_2.random
  L3_2 = 1
  L4_2 = L2_1
  L4_2 = #L4_2
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = L2_1
  L2_2 = L3_2[L2_2]
  return L2_2
end
GetRandomModel = L4_1
function L4_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = promise
  L1_2 = L1_2.new
  L1_2 = L1_2()
  L2_2 = 1
  L3_2 = L3_1.vertGroups
  L3_2 = L3_2[A0_2]
  L3_2 = #L3_2
  L4_2 = 1
  for L5_2 = L2_2, L3_2, L4_2 do
    L6_2 = GetRandomModel
    L7_2 = L0_1
    L6_2 = L6_2(L7_2)
    L7_2 = L3_1.models
    L7_2 = L7_2[L5_2]
    if not L7_2 then
      L7_2 = L3_1.models
      L7_2[L5_2] = L6_2
    end
    L7_2 = L3_1.vertGroups
    L7_2 = L7_2[A0_2]
    L7_2 = #L7_2
    if L5_2 == L7_2 then
      L8_2 = L1_2
      L7_2 = L1_2.resolve
      L9_2 = true
      L7_2(L8_2, L9_2)
    end
  end
  L2_2 = Citizen
  L2_2 = L2_2.Await
  L3_2 = L1_2
  L2_2(L3_2)
  L2_2 = true
  return L2_2
end
GenerateRandomModelPreset = L4_1
L4_1 = EventLimiterService
L4_1 = L4_1.RegisterNetEvent
L5_1 = "rcore_prison:server:requestPerollRelease"
L6_1 = 0
L7_1 = 1
function L8_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  if A1_2 then
    L2_2 = COMSService
    L2_2 = L2_2.getPlayer
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if L2_2 then
      L3_2 = next
      L4_2 = L2_2
      L3_2 = L3_2(L4_2)
      if not L3_2 then
        L3_2 = Framework
        L3_2 = L3_2.sendNotification
        L4_2 = A0_2
        L5_2 = _U
        L6_2 = "CS.NOT_CS_USER"
        L5_2 = L5_2(L6_2)
        L6_2 = "error"
        L3_2(L4_2, L5_2, L6_2)
        L3_2 = dbg
        L3_2 = L3_2.critical
        L4_2 = "Player [%s] tried to finish peroll, when not on CS."
        L5_2 = GetPlayerName
        L6_2 = A0_2
        L5_2, L6_2 = L5_2(L6_2)
        return L3_2(L4_2, L5_2, L6_2)
      end
    end
    L3_2 = COMSService
    L3_2 = L3_2.ReleaseUser
    L4_2 = A0_2
    L3_2(L4_2)
  end
end
L4_1(L5_1, L6_1, L7_1, L8_1)
L4_1 = EventLimiterService
L4_1 = L4_1.RegisterNetEvent
L5_1 = "rcore_prison:server:requestFinishPeroll"
L6_1 = 0
L7_1 = 1
function L8_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  if A1_2 then
    L2_2 = COMSService
    L2_2 = L2_2.getPlayer
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if L2_2 then
      L3_2 = next
      L4_2 = L2_2
      L3_2 = L3_2(L4_2)
      if not L3_2 then
        L3_2 = Framework
        L3_2 = L3_2.sendNotification
        L4_2 = A0_2
        L5_2 = _U
        L6_2 = "CS.NOT_CS_USER"
        L5_2 = L5_2(L6_2)
        L6_2 = "error"
        L3_2(L4_2, L5_2, L6_2)
        L3_2 = dbg
        L3_2 = L3_2.critical
        L4_2 = "Player [%s] tried to finish peroll, when not on CS."
        L5_2 = GetPlayerName
        L6_2 = A0_2
        L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
        return L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
      end
    end
    L3_2 = L2_2.zoneIdx
    L4_2 = L2_2.state
    L5_2 = COMS_STATES
    L5_2 = L5_2.RETURN
    if L4_2 ~= L5_2 then
      L4_2 = Framework
      L4_2 = L4_2.sendNotification
      L5_2 = A0_2
      L6_2 = _U
      L7_2 = "CS.NOT_IN_RETURN_STATE"
      L6_2 = L6_2(L7_2)
      L7_2 = "error"
      L4_2(L5_2, L6_2, L7_2)
      return
    end
    L4_2 = COMSessionsService
    L4_2 = L4_2.GetZoneData
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    L5_2 = L4_2.verticesDone
    L6_2 = L4_2.verticesTarget
    if L5_2 >= L6_2 then
      L5_2 = L2_2.perollAmount
      L5_2 = L5_2 + 1
      L2_2.perollAmount = L5_2
      L5_2 = db
      L5_2 = L5_2.DeleteCOMSZone
      L6_2 = L2_2.charId
      L7_2 = L3_2
      L5_2(L6_2, L7_2)
      L5_2 = db
      L5_2 = L5_2.UpdatePlayerComsPerollAmount
      L6_2 = L2_2.charId
      L7_2 = L2_2.perollAmount
      L5_2(L6_2, L7_2)
      L5_2 = COMSService
      L5_2 = L5_2.UpdatePlayerKeyByValue
      L6_2 = A0_2
      L7_2 = "zoneIdx"
      L8_2 = nil
      L5_2(L6_2, L7_2, L8_2)
      L5_2 = COMSService
      L5_2 = L5_2.UpdatePlayerKeyByValue
      L6_2 = A0_2
      L7_2 = "state"
      L8_2 = COMS_STATES
      L8_2 = L8_2.IDLE
      L5_2(L6_2, L7_2, L8_2)
      L5_2 = COMSService
      L5_2 = L5_2.UpdatePlayerKeyByValue
      L6_2 = A0_2
      L7_2 = "perollAmount"
      L8_2 = L2_2.perollAmount
      L5_2(L6_2, L7_2, L8_2)
      L5_2 = StartClient
      L6_2 = A0_2
      L7_2 = "comsHeartbeat"
      L8_2 = L2_2
      L5_2(L6_2, L7_2, L8_2)
      L5_2 = Framework
      L5_2 = L5_2.sendNotification
      L6_2 = A0_2
      L7_2 = _U
      L8_2 = "CS.PEROLL_FINISHED"
      L7_2 = L7_2(L8_2)
      L8_2 = "success"
      L5_2(L6_2, L7_2, L8_2)
    end
  end
end
L4_1(L5_1, L6_1, L7_1, L8_1)
L4_1 = EventLimiterService
L4_1 = L4_1.RegisterNetEvent
L5_1 = "rcore_prison:server:requestComs"
L6_1 = 0
L7_1 = 1
function L8_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  if A1_2 then
    L2_2 = COMSService
    L2_2 = L2_2.getPlayer
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if not L2_2 then
      L3_2 = Framework
      L3_2 = L3_2.sendNotification
      L4_2 = A0_2
      L5_2 = _U
      L6_2 = "CS.NOT_CS_USER"
      L5_2 = L5_2(L6_2)
      L6_2 = "error"
      L3_2(L4_2, L5_2, L6_2)
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "Player [%s] tried to request peroll while not being on CS."
      L5_2 = GetPlayerName
      L6_2 = A0_2
      L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2 = L5_2(L6_2)
      return L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
    end
    L3_2 = L2_2.state
    L4_2 = COMS_STATES
    L4_2 = L4_2.IDLE
    if L3_2 ~= L4_2 then
      L3_2 = Framework
      L3_2 = L3_2.sendNotification
      L4_2 = A0_2
      L5_2 = _U
      L6_2 = "CS.NOT_IN_RETURN_STATE"
      L5_2 = L5_2(L6_2)
      L6_2 = "error"
      L3_2(L4_2, L5_2, L6_2)
      return
    end
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "Player [%s] requested peroll."
    L5_2 = GetPlayerName
    L6_2 = A0_2
    L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2 = L5_2(L6_2)
    L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
    L3_2 = COMS
    L3_2 = L3_2.GenerateRandomArea
    L3_2 = L3_2()
    L4_2 = L1_1
    L4_2 = L4_2[L3_2]
    if L4_2 then
      return
    end
    L4_2 = db
    L4_2 = L4_2.DoesIdExistInPool
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    if L4_2 then
      L5_2 = Framework
      L5_2 = L5_2.sendNotification
      L6_2 = A0_2
      L7_2 = _U
      L8_2 = "CS.CANNOT_GENERATE_ZONE_ALREADY_ACTIVE"
      L7_2 = L7_2(L8_2)
      L8_2 = "error"
      L5_2(L6_2, L7_2, L8_2)
      return
    end
    L5_2 = L1_1
    L5_2[L3_2] = true
    L5_2 = GenerateRandomModelPreset
    L6_2 = L3_2
    L5_2 = L5_2(L6_2)
    if L5_2 then
      L6_2 = dbg
      L6_2 = L6_2.debug
      L7_2 = "Loading community service for [%s] | ZONE [%s]"
      L8_2 = GetPlayerName
      L9_2 = A0_2
      L8_2 = L8_2(L9_2)
      L9_2 = L3_2
      L6_2(L7_2, L8_2, L9_2)
      L6_2 = L3_1.vertGroups
      L6_2 = L6_2[L3_2]
      L7_2 = L6_2[1]
      L7_2 = L7_2.pos
      L8_2 = vec3
      L9_2 = L7_2.X
      L10_2 = L7_2.Y
      L11_2 = L7_2.Z
      L8_2 = L8_2(L9_2, L10_2, L11_2)
      L9_2 = COMSessionsService
      L9_2 = L9_2.RegisterZone
      L10_2 = L3_2
      L11_2 = #L6_2
      L12_2 = 0
      L9_2 = L9_2(L10_2, L11_2, L12_2)
      if L9_2 then
        L10_2 = dbg
        L10_2 = L10_2.debug
        L11_2 = "Registering zone [%s] | [%s] for player named (%s)"
        L12_2 = L3_2
        L13_2 = #L6_2
        L14_2 = GetPlayerName
        L15_2 = A0_2
        L14_2, L15_2 = L14_2(L15_2)
        L10_2(L11_2, L12_2, L13_2, L14_2, L15_2)
        L10_2 = db
        L10_2 = L10_2.RegisterCOMSZone
        L11_2 = L3_2
        L12_2 = #L6_2
        L13_2 = 0
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = db
        L10_2 = L10_2.UpdatePlayerComsZoneId
        L11_2 = L3_2
        L12_2 = L2_2.charId
        L10_2(L11_2, L12_2)
        L10_2 = COMSService
        L10_2 = L10_2.UpdatePlayerKeyByValue
        L11_2 = A0_2
        L12_2 = "zoneIdx"
        L13_2 = L3_2
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = COMSService
        L10_2 = L10_2.UpdatePlayerKeyByValue
        L11_2 = A0_2
        L12_2 = "state"
        L13_2 = COMS_STATES
        L13_2 = L13_2.SWEEPING
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = StartClient
        L11_2 = A0_2
        L12_2 = "comsHeartbeat"
        L13_2 = L2_2
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = SetTimeout
        L11_2 = 1000
        function L12_2()
          local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3
          L0_3 = StartClient
          L1_3 = -1
          L2_3 = "registerZone"
          L3_3 = {}
          L4_3 = L3_1.models
          L3_3.models = L4_3
          L4_3 = L8_2
          L3_3.zonePos = L4_3
          L4_3 = L3_1.vertGroups
          L5_3 = L3_2
          L4_3 = L4_3[L5_3]
          L3_3.vertices = L4_3
          L4_3 = L3_2
          L3_3.idx = L4_3
          L4_3 = A0_2
          L3_3.owner = L4_3
          L0_3(L1_3, L2_3, L3_3)
        end
        L10_2(L11_2, L12_2)
        L10_2 = StartClient
        L11_2 = A0_2
        L12_2 = "SetWaypoint"
        L13_2 = L8_2
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = StartClient
        L11_2 = A0_2
        L12_2 = "createSquaredArea"
        L13_2 = L8_2
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = Framework
        L10_2 = L10_2.sendNotification
        L11_2 = A0_2
        L12_2 = _U
        L13_2 = "CS.STARTED_PEROLL"
        L12_2 = L12_2(L13_2)
        L13_2 = "success"
        L10_2(L11_2, L12_2, L13_2)
      end
    end
  end
end
L4_1(L5_1, L6_1, L7_1, L8_1)
function L4_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L3_2 = GetPlayerPed
  L4_2 = A2_2
  L3_2 = L3_2(L4_2)
  L4_2 = GetEntityCoords
  L5_2 = L3_2
  L4_2 = L4_2(L5_2)
  L5_2 = L3_1.vertGroups
  L5_2 = L5_2[A0_2]
  L5_2 = L5_2[A1_2]
  if not L5_2 then
    L6_2 = false
    return L6_2
  end
  L6_2 = vec3
  L7_2 = L5_2.pos
  L7_2 = L7_2.X
  L8_2 = L5_2.pos
  L8_2 = L8_2.Y
  L9_2 = L5_2.pos
  L9_2 = L9_2.Z
  L6_2 = L6_2(L7_2, L8_2, L9_2)
  L6_2 = L4_2 - L6_2
  L6_2 = #L6_2
  L7_2 = 1.5
  if L6_2 <= L7_2 then
    L7_2 = true
    return L7_2
  end
  L7_2 = false
  return L7_2
end
IsPlayerAtVertice = L4_1
L4_1 = RegisterNetEvent
L5_1 = "rcore_prison:server:requestRemoveVertice"
function L6_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L1_2 = source
  L2_2 = COMSService
  L2_2 = L2_2.getPlayer
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = Framework
    L3_2 = L3_2.sendNotification
    L4_2 = L1_2
    L5_2 = _U
    L6_2 = "CS.NOT_CS_USER"
    L5_2 = L5_2(L6_2)
    L6_2 = "error"
    L3_2(L4_2, L5_2, L6_2)
    return
  end
  L3_2 = L2_2.zoneIdx
  L4_2 = A0_2.zoneId
  L5_2 = A0_2.owner
  L6_2 = A0_2.verticeId
  if L3_2 ~= L4_2 then
    L7_2 = Framework
    L7_2 = L7_2.sendNotification
    L8_2 = L1_2
    L9_2 = _U
    L10_2 = "CS.NOT_IN_OWN_ZONE"
    L9_2 = L9_2(L10_2)
    L10_2 = "error"
    L7_2(L8_2, L9_2, L10_2)
    return
  end
  if L5_2 ~= L1_2 then
    L7_2 = Framework
    L7_2 = L7_2.sendNotification
    L8_2 = L1_2
    L9_2 = _U
    L10_2 = "CS.NOT_OWNER_OF_ZONE"
    L9_2 = L9_2(L10_2)
    L10_2 = "error"
    L7_2(L8_2, L9_2, L10_2)
    return
  end
  L7_2 = IsPlayerAtVertice
  L8_2 = L3_2
  L9_2 = L6_2
  L10_2 = L1_2
  L7_2 = L7_2(L8_2, L9_2, L10_2)
  if not L7_2 then
    L8_2 = Framework
    L8_2 = L8_2.sendNotification
    L9_2 = L1_2
    L10_2 = _U
    L11_2 = "CS.NOT_IN_SWEEPING_RANGE"
    L10_2 = L10_2(L11_2)
    L11_2 = "error"
    L8_2(L9_2, L10_2, L11_2)
    return
  end
  L8_2 = L2_2.state
  L9_2 = COMS_STATES
  L9_2 = L9_2.SWEEPING
  if L8_2 ~= L9_2 then
    L8_2 = Framework
    L8_2 = L8_2.sendNotification
    L9_2 = L1_2
    L10_2 = _U
    L11_2 = "CS.NOT_IN_SWEEPING_STATE"
    L10_2 = L10_2(L11_2)
    L11_2 = "error"
    L8_2(L9_2, L10_2, L11_2)
    return
  end
  L8_2 = COMSessionsService
  L8_2 = L8_2.GetZoneData
  L9_2 = L3_2
  L8_2 = L8_2(L9_2)
  L9_2 = L8_2.verticesDone
  L9_2 = L9_2 + 1
  L8_2.verticesDone = L9_2
  L9_2 = COMSessionsService
  L9_2 = L9_2.UpdateDataByKey
  L10_2 = L3_2
  L11_2 = "verticesDone"
  L12_2 = L8_2.verticesDone
  L9_2(L10_2, L11_2, L12_2)
  L9_2 = L8_2.verticesDone
  L10_2 = L8_2.verticesTarget
  if L9_2 >= L10_2 then
    L9_2 = COMSService
    L9_2 = L9_2.UpdatePlayerKeyByValue
    L10_2 = L1_2
    L11_2 = "state"
    L12_2 = COMS_STATES
    L12_2 = L12_2.RETURN
    L9_2(L10_2, L11_2, L12_2)
    L9_2 = Config
    L9_2 = L9_2.COMS
    L9_2 = L9_2.StartLocations
    if L9_2 then
      L10_2 = L9_2.coords
      if L10_2 then
        L11_2 = StartClient
        L12_2 = L1_2
        L13_2 = "SetWaypoint"
        L14_2 = L10_2
        L11_2(L12_2, L13_2, L14_2)
      end
    end
    L10_2 = StartClient
    L11_2 = L1_2
    L12_2 = "comsHeartbeat"
    L13_2 = L2_2
    L10_2(L11_2, L12_2, L13_2)
    L10_2 = StartClient
    L11_2 = L1_2
    L12_2 = "RemoveBlipByType"
    L13_2 = "COMS"
    L10_2(L11_2, L12_2, L13_2)
    L10_2 = Framework
    L10_2 = L10_2.sendNotification
    L11_2 = L1_2
    L12_2 = _U
    L13_2 = "CS.AREA_CLEANED_RETURN"
    L12_2 = L12_2(L13_2)
    L13_2 = "success"
    L10_2(L11_2, L12_2, L13_2)
  end
  L9_2 = StartClient
  L10_2 = -1
  L11_2 = "removeVertice"
  L12_2 = A0_2
  L9_2(L10_2, L11_2, L12_2)
end
L4_1(L5_1, L6_1)
L4_1 = callback
L4_1 = L4_1.register
L5_1 = "rcore_prison:server:getAllComs"
function L6_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L2_2 = Framework
  L2_2 = L2_2.canPerformJobCommand
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L2_2 = {}
    return L2_2
  end
  L2_2 = COMSService
  L2_2 = L2_2.GetAllCOMS
  L2_2 = L2_2()
  L3_2 = table
  L3_2 = L3_2.size
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = {}
  L5_2 = pairs
  L6_2 = L2_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = table
    L11_2 = L11_2.insert
    L12_2 = L4_2
    L13_2 = L10_2
    L11_2(L12_2, L13_2)
  end
  L5_2 = {}
  L6_2 = 4 == L3_2 or L6_2
  L5_2.hasMore = L6_2
  L5_2.coms = L4_2
  return L5_2
end
L4_1(L5_1, L6_1)
