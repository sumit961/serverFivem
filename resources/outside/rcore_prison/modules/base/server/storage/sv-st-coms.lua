local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = {}
  L0_2._COMS = L1_2
  L1_2 = RegisterCommand
  L2_2 = "coms"
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    if 0 == A0_3 then
      L3_3 = tprint
      L4_3 = L0_2._COMS
      L3_3(L4_3)
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    if not A0_3 then
      L3_3 = nil
      return L3_3
    end
    L3_3 = Framework
    L3_3 = L3_3.getIdentifier
    L4_3 = A0_3
    L3_3 = L3_3(L4_3)
    if not L3_3 then
      L4_3 = nil
      return L4_3
    end
    L4_3 = L0_2._COMS
    L4_3 = L4_3[L3_3]
    L4_3[A1_3] = A2_3
    L4_3 = true
    return L4_3
  end
  L0_2.UpdatePlayerKeyByValue = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2._COMS
    return L0_3
  end
  L0_2.GetAllCOMS = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3
    L1_3 = L0_2._COMS
    L2_3 = tostring
    L3_3 = A0_3
    L2_3 = L2_3(L3_3)
    L1_3 = L1_3[L2_3]
    return L1_3
  end
  L0_2.GetPlayerById = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    if not A0_3 then
      L1_3 = nil
      return L1_3
    end
    L1_3 = Framework
    L1_3 = L1_3.getIdentifier
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._COMS
    L2_3 = L2_3[L1_3]
    return L2_3
  end
  L0_2.GetPlayerBySource = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    if not A0_3 then
      L1_3 = nil
      return L1_3
    end
    L1_3 = Framework
    L1_3 = L1_3.getIdentifier
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._COMS
    L2_3 = L2_3[L1_3]
    if not L2_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._COMS
    L2_3[L1_3] = nil
    L2_3 = db
    L2_3 = L2_3.DeletePlayerCOMS
    L3_3 = L1_3
    L2_3(L3_3)
    L2_3 = dbg
    L2_3 = L2_3.debug
    L3_3 = "Citizen named (%s) was released from peroll"
    L4_3 = GetPlayerName
    L5_3 = A0_3
    L4_3, L5_3 = L4_3(L5_3)
    L2_3(L3_3, L4_3, L5_3)
    L2_3 = Framework
    L2_3 = L2_3.sendNotification
    L3_3 = A0_3
    L4_3 = _U
    L5_3 = "RELEASE_COMS_MESSAGE"
    L4_3 = L4_3(L5_3)
    L5_3 = "success"
    L2_3(L3_3, L4_3, L5_3)
    L2_3 = StartClient
    L3_3 = A0_3
    L4_3 = "comsHeartbeat"
    L2_3(L3_3, L4_3)
  end
  L0_2.ReleaseUser = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    if not A0_3 then
      L1_3 = nil
      return L1_3
    end
    L1_3 = Framework
    L1_3 = L1_3.getIdentifier
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._COMS
    L2_3 = L2_3[L1_3]
    if not L2_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._COMS
    L2_3 = L2_3[L1_3]
    L2_3 = L2_3.zoneId
    L3_3 = GetPlayerName
    L4_3 = A0_3
    L3_3 = L3_3(L4_3)
    if L2_3 then
      L4_3 = dbg
      L4_3 = L4_3.debug
      L5_3 = "Removing current zone with ID (%s) since player disconnect (%s)"
      L6_3 = L2_3
      L7_3 = L3_3
      L4_3(L5_3, L6_3, L7_3)
      L4_3 = db
      L4_3 = L4_3.DeleteCOMSZone
      L5_3 = L1_3
      L6_3 = L2_3
      L4_3(L5_3, L6_3)
      L4_3 = db
      L4_3 = L4_3.DeleteCOMSSessionZone
      L5_3 = L2_3
      L4_3(L5_3)
    end
    L4_3 = StartClient
    L5_3 = A0_3
    L6_3 = "comsHeartbeat"
    L4_3(L5_3, L6_3)
  end
  L0_2.SaveUser = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    if not A0_3 then
      L1_3 = nil
      return L1_3
    end
    L1_3 = Framework
    L1_3 = L1_3.getIdentifier
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = dbg
    L2_3 = L2_3.debug
    L3_3 = "Loading community service for charId -> [%s]"
    L4_3 = GetPlayerName
    L5_3 = A0_3
    L4_3, L5_3, L6_3, L7_3 = L4_3(L5_3)
    L2_3(L3_3, L4_3, L5_3, L6_3, L7_3)
    L2_3 = Config
    L2_3 = L2_3.COMS
    L2_3 = L2_3.StartLocations
    if L2_3 then
      L3_3 = L2_3.coords
      if L3_3 then
        L4_3 = StartClient
        L5_3 = A0_3
        L6_3 = "SetWaypoint"
        L7_3 = L3_3
        L4_3(L5_3, L6_3, L7_3)
      end
    end
    L3_3 = L0_2._COMS
    L3_3 = L3_3[L1_3]
    L4_3 = L3_3.state
    L5_3 = COMS_STATES
    L5_3 = L5_3.SWEEPING
    if L4_3 == L5_3 then
      L4_3 = COMS_STATES
      L4_3 = L4_3.IDLE
      L3_3.state = L4_3
    end
    L4_3 = SetTimeout
    L5_3 = 1000
    function L6_3()
      local L0_4, L1_4, L2_4, L3_4, L4_4
      L0_4 = StartClient
      L1_4 = A0_3
      L2_4 = "StartComsIntro"
      L3_4 = {}
      L4_4 = L3_3.name
      L3_4.name = L4_4
      L4_4 = L3_3.perollTarget
      L3_4.perollTarget = L4_4
      L4_4 = L3_3.perollAmount
      L3_4.perollAmount = L4_4
      L0_4(L1_4, L2_4, L3_4)
    end
    L4_3(L5_3, L6_3)
    L4_3 = StartClient
    L5_3 = A0_3
    L6_3 = "comsHeartbeat"
    L7_3 = L0_2._COMS
    L7_3 = L7_3[L1_3]
    L4_3(L5_3, L6_3, L7_3)
  end
  L0_2.loadPeroll = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    if not A0_3 then
      L1_3 = nil
      return L1_3
    end
    L1_3 = A0_3.charId
    if not L1_3 then
      L1_3 = nil
      return L1_3
    end
    L1_3 = L0_2._COMS
    L2_3 = A0_3.charId
    L1_3[L2_3] = A0_3
    L1_3 = A0_3.charId
    return L1_3
  end
  L0_2.addPlayer = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2._COMS
    L2_3 = A0_3.charId
    L1_3[L2_3] = nil
  end
  L0_2.removePlayer = L1_2
  return L0_2
end
COMStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_COMS
L2_1 = COMStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
