local L0_1, L1_1
L0_1 = {}
PrisonAccountTransactionService = L0_1
L0_1 = PrisonAccountTransactionService
function L1_1()
  local L0_2, L1_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_PRISONER_ACCOUNTS_TRANSACTIONS
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    return
  end
  L1_2 = L0_2.onInitRegister
  L1_2()
end
L0_1.RegisterIntoCache = L1_1
L0_1 = PrisonAccountTransactionService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER_ACCOUNTS_TRANSACTIONS
  L1_2 = L1_2(L2_2)
  if not A0_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Failed to get charId"
    L2_2(L3_2)
    return
  end
  L2_2 = L1_2.getTransactionsByCharId
  L3_2 = A0_2
  return L2_2(L3_2)
end
L0_1.fetchByCharId = L1_1
