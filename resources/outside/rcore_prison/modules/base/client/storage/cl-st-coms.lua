local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = {}
  L0_2._comsData = L1_2
  L1_2 = RegisterCommand
  L2_2 = "client_data"
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    L3_3 = next
    L4_3 = L0_2._comsData
    L3_3 = L3_3(L4_3)
    if L3_3 then
      L3_3 = tprint
      L4_3 = L0_2._comsData
      L3_3(L4_3)
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  function L1_2(A0_3)
    local L1_3
    L0_2._comsData = A0_3
    L1_3 = true
    return L1_3
  end
  L0_2.RegisterActiveCOMS = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3
    L2_3 = L0_2.IsActiveCOMS
    L2_3 = L2_3()
    if not L2_3 then
      L2_3 = false
      return L2_3
    end
    if not A0_3 then
      L2_3 = false
      return L2_3
    end
    if not A1_3 then
      L2_3 = false
      return L2_3
    end
    L2_3 = L0_2._comsData
    L2_3[A0_3] = A1_3
  end
  L0_2.UpdateCOMSDataByKeyValue = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = {}
    L0_2._comsData = L0_3
    L0_3 = true
    return L0_3
  end
  L0_2.UnregisterActiveCOMS = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2._comsData
    if L0_3 then
      L0_3 = next
      L1_3 = L0_2._comsData
      L0_3 = L0_3(L1_3)
      L0_3 = nil ~= L0_3
    end
    return L0_3
  end
  L0_2.IsUserOnCOMS = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2._comsData
    return L0_3
  end
  L0_2.GetCOMS = L1_2
  return L0_2
end
COMStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_COMS
L2_1 = COMStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
