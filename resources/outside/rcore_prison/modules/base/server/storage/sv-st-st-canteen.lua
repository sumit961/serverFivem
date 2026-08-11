local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2
  L0_2 = {}
  L1_2 = {}
  L0_2.storageSessions = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2.storageSessions
    L1_3 = L1_3[A0_3]
    L1_3 = nil ~= L1_3
    return L1_3
  end
  L0_2.isSessionRegistered = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3
    L1_3 = L0_2.storageSessions
    L1_3[A0_3] = true
    L1_3 = SetTimeout
    L2_3 = Config
    L2_3 = L2_3.Canteen
    L2_3 = L2_3.FreeFoodPackageCooldown
    L2_3 = L2_3 * 60
    L2_3 = L2_3 * 1000
    function L3_3()
      local L0_4, L1_4
      L0_4 = L0_2.storageSessions
      L1_4 = A0_3
      L0_4[L1_4] = nil
    end
    L1_3(L2_3, L3_3)
  end
  L0_2.registerSession = L1_2
  return L0_2
end
CanteenStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_CANTEEN
L2_1 = CanteenStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
