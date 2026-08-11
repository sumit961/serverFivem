local L0_1, L1_1
L0_1 = {}
LogService = L0_1
L0_1 = LogService
function L1_1(A0_2, A1_2, A2_2, A3_2, A4_2)
  local L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L5_2 = Object
  L5_2 = L5_2.getStorage
  L6_2 = STORAGE_LOGS
  L5_2 = L5_2(L6_2)
  if not L5_2 then
    L6_2 = nil
    return L6_2
  end
  if not A3_2 then
    A3_2 = "-"
  end
  if not A4_2 then
    A4_2 = "-"
  end
  L6_2 = {}
  L6_2.action = A0_2
  L6_2.desc = A1_2
  L6_2.charId = A2_2
  L6_2.officer_name = A3_2
  L6_2.citizen_name = A4_2
  L7_2 = os
  L7_2 = L7_2.date
  L8_2 = "%Y-%m-%d %H:%M:%S"
  L7_2 = L7_2(L8_2)
  L6_2.created_at = L7_2
  L7_2 = L5_2.addLog
  L8_2 = L6_2
  L7_2(L8_2)
  L7_2 = db
  L7_2 = L7_2.RegisterTransaction
  L8_2 = A0_2
  L9_2 = A1_2
  L10_2 = A2_2
  L11_2 = A3_2
  L12_2 = A4_2
  L7_2 = L7_2(L8_2, L9_2, L10_2, L11_2, L12_2)
  if L7_2 then
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "Log registered successfully"
    L8_2(L9_2)
  end
end
L0_1.RegisterTransaction = L1_1
L0_1 = LogService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L0_2 = "LOADED_DATA_INTO_CACHE"
  L1_2 = db
  L1_2 = L1_2.FetchPrisonLogs
  L1_2 = L1_2()
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_LOGS
  L2_2 = L2_2(L3_2)
  L3_2 = promise
  L3_2 = L3_2.new
  L3_2 = L3_2()
  L4_2 = next
  L5_2 = L1_2
  L4_2 = L4_2(L5_2)
  if L4_2 then
    L4_2 = 1
    L5_2 = #L1_2
    L6_2 = 1
    for L7_2 = L4_2, L5_2, L6_2 do
      L8_2 = L1_2[L7_2]
      if L8_2 then
        L9_2 = L2_2.addLog
        L10_2 = L8_2
        L9_2(L10_2)
      end
      L9_2 = #L1_2
      if L7_2 >= L9_2 then
        L10_2 = L3_2
        L9_2 = L3_2.resolve
        L11_2 = true
        L9_2(L10_2, L11_2)
      end
      L9_2 = Wait
      L10_2 = 0
      L9_2(L10_2)
    end
  else
    L0_2 = "NOT_ANY_LOGS_IN_DB"
    L5_2 = L3_2
    L4_2 = L3_2.resolve
    L6_2 = true
    L4_2(L5_2, L6_2)
  end
  L4_2 = Citizen
  L4_2 = L4_2.Await
  L5_2 = L3_2
  L4_2(L5_2)
  L4_2 = dbg
  L4_2 = L4_2.debug
  L5_2 = "Logs data into cache state: %s"
  L6_2 = L0_2
  L4_2(L5_2, L6_2)
end
L0_1.LoadAllLogs = L1_1
L0_1 = LogService
function L1_1()
  local L0_2, L1_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_LOGS
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    L1_2 = nil
    return L1_2
  end
  L1_2 = L0_2.getLogs
  return L1_2()
end
L0_1.GetLogs = L1_1
