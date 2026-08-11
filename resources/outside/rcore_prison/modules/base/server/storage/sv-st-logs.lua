local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2
  L0_2 = {}
  L1_2 = {}
  L0_2.logs = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2.logs
    L2_3 = L0_2.logs
    L2_3 = #L2_3
    L2_3 = L2_3 + 1
    L1_3[L2_3] = A0_3
    L1_3 = true
    return L1_3
  end
  L0_2.addLog = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.logs
    return L0_3
  end
  L0_2.getLogs = L1_2
  return L0_2
end
LogsStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_LOGS
L2_1 = LogsStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
