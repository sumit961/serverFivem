local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = {}
  L0_2._sessions = L1_2
  L1_2 = RegisterCommand
  L2_2 = "sessions"
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    if 0 == A0_3 then
      L3_3 = tprint
      L4_3 = L0_2._sessions
      L3_3(L4_3)
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2._sessions
    return L0_3
  end
  L0_2.getAllSessions = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2._sessions
    L1_3 = L1_3[A0_3]
    return L1_3
  end
  L0_2.getSession = L1_2
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    L3_3 = L0_2._sessions
    L3_3 = L3_3[A0_3]
    if not L3_3 then
      L4_3 = false
      return L4_3
    end
    L3_3[A1_3] = A2_3
    L4_3 = true
    return L4_3
  end
  L0_2.updateSessionByKeyValue = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2._sessions
    L2_3 = A0_3.zoneId
    L1_3[L2_3] = A0_3
    L1_3 = true
    return L1_3
  end
  L0_2.registerSession = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2._sessions
    L2_3 = A0_3.zoneId
    L1_3[L2_3] = nil
  end
  L0_2.unregisterSession = L1_2
  return L0_2
end
COMSSessionStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_COMS_SESSIONS
L2_1 = COMSSessionStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
