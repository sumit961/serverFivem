local L0_1, L1_1
L0_1 = {}
L0_1.isDBReady = false
AccountLogService = L0_1
L0_1 = AccountLogService
function L1_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L4_2 = Object
  L4_2 = L4_2.getStorage
  L5_2 = STORAGE_ACCOUNT_LOGS
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    L5_2 = nil
    return L5_2
  end
  L5_2 = {}
  L5_2.action = A0_2
  L5_2.desc = A1_2
  L5_2.charId = A2_2
  L5_2.amount = A3_2
  L6_2 = os
  L6_2 = L6_2.date
  L7_2 = "%Y-%m-%d %H:%M:%S"
  L6_2 = L6_2(L7_2)
  L5_2.created_at = L6_2
  L6_2 = L4_2.addLog
  L7_2 = L5_2
  L6_2(L7_2)
  L6_2 = db
  L6_2 = L6_2.RegisterAccountTransaction
  L7_2 = A0_2
  L8_2 = A1_2
  L9_2 = A2_2
  L10_2 = A3_2
  L6_2 = L6_2(L7_2, L8_2, L9_2, L10_2)
  if L6_2 then
    L7_2 = dbg
    L7_2 = L7_2.debug
    L8_2 = "Account log registered successfully"
    L7_2(L8_2)
  end
end
L0_1.RegisterTransaction = L1_1
L0_1 = AccountLogService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_ACCOUNT_LOGS
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = nil
    return L2_2
  end
  L2_2 = L1_2.getLogs
  L2_2 = L2_2()
  L3_2 = {}
  L4_2 = ipairs
  L5_2 = L2_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = L9_2.charId
    if L10_2 == A0_2 then
      L10_2 = table
      L10_2 = L10_2.insert
      L11_2 = L3_2
      L12_2 = L9_2
      L10_2(L11_2, L12_2)
    end
  end
  return L3_2
end
L0_1.GetLogsByCharId = L1_1
L0_1 = AccountLogService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L0_2 = "LOADED_DATA_INTO_CACHE"
  L1_2 = db
  L1_2 = L1_2.FetchAccountLogs
  L1_2 = L1_2()
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_ACCOUNT_LOGS
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
    L0_2 = "NOT_ANY_ACCOUNT_LOGS_IN_DB"
    L5_2 = L3_2
    L4_2 = L3_2.resolve
    L6_2 = true
    L4_2(L5_2, L6_2)
  end
  L4_2 = AccountLogService
  L4_2.isDBReady = true
end
L0_1.LoadAllLogs = L1_1
L0_1 = AccountLogService
function L1_1()
  local L0_2, L1_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_ACCOUNT_LOGS
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    L1_2 = nil
    return L1_2
  end
  L1_2 = L0_2.getLogs
  return L1_2()
end
L0_1.GetLogs = L1_1
