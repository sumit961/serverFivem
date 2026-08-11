local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2
  L0_2 = {}
  L1_2 = {}
  L0_2._prisoner = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2._prisoner = A0_3
    L1_3 = true
    return L1_3
  end
  L0_2.RegisterPrisoner = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3
    L2_3 = L0_2.IsPrisoner
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
    L2_3 = L0_2._prisoner
    L2_3[A0_3] = A1_3
  end
  L0_2.UpdatePrisonerDataByKeyValue = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_2._prisoner = nil
    L0_3 = true
    return L0_3
  end
  L0_2.UnregisterPrisoner = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2._prisoner
    if L0_3 then
      L0_3 = next
      L1_3 = L0_2._prisoner
      L0_3 = L0_3(L1_3)
      L0_3 = nil ~= L0_3
    end
    return L0_3
  end
  L0_2.IsPrisoner = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.IsPrisoner
    L0_3 = L0_3()
    if not L0_3 then
      L0_3 = nil
      return L0_3
    end
    L0_3 = L0_2._prisoner
    return L0_3
  end
  L0_2.GetPrisonerData = L1_2
  return L0_2
end
PrisonerStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_PRISONER
L2_1 = PrisonerStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
