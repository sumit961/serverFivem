local L0_1, L1_1
L0_1 = {}
COMSessionsService = L0_1
L0_1 = COMSessionsService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2
  L3_2 = Object
  L3_2 = L3_2.getStorage
  L4_2 = STORAGE_COMS_SESSIONS
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    L4_2 = dbg
    L4_2 = L4_2.critical
    L5_2 = "Storage not found"
    L4_2(L5_2)
    L4_2 = nil
    return L4_2
  end
  L4_2 = L3_2.getSession
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if L4_2 then
    L4_2 = dbg
    L4_2 = L4_2.critical
    L5_2 = "Zone already registered"
    L4_2(L5_2)
    L4_2 = nil
    return L4_2
  end
  L4_2 = COMSSessionsModel
  L4_2 = L4_2()
  L4_2.zoneId = A0_2
  L4_2.verticesTarget = A1_2
  L4_2.verticesDone = A2_2
  L5_2 = L3_2.registerSession
  L6_2 = L4_2
  L5_2 = L5_2(L6_2)
  return L5_2
end
L0_1.RegisterZone = L1_1
L0_1 = COMSessionsService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_COMS_SESSIONS
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = dbg
    L2_2 = L2_2.critical
    L3_2 = "Storage not found"
    L2_2(L3_2)
    L2_2 = nil
    return L2_2
  end
  L2_2 = L1_2.getSession
  L3_2 = A0_2
  return L2_2(L3_2)
end
L0_1.GetZoneData = L1_1
L0_1 = COMSessionsService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  L3_2 = Object
  L3_2 = L3_2.getStorage
  L4_2 = STORAGE_COMS_SESSIONS
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    L4_2 = dbg
    L4_2 = L4_2.critical
    L5_2 = "Storage not found"
    L4_2(L5_2)
    L4_2 = false
    L5_2 = nil
    return L4_2, L5_2
  end
  L4_2 = L3_2.updateSessionByKeyValue
  L5_2 = A0_2
  L6_2 = A1_2
  L7_2 = A2_2
  return L4_2(L5_2, L6_2, L7_2)
end
L0_1.UpdateDataByKey = L1_1
