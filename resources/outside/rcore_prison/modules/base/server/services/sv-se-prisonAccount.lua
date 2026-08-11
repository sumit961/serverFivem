local L0_1, L1_1, L2_1
L0_1 = {}
PrisonAccountService = L0_1
L0_1 = PrisonAccountService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER_ACCOUNTS
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetAccountBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = false
    return L3_2
  end
  return L2_2
end
L0_1.getPlayer = L1_1
L0_1 = PrisonAccountService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_PRISONER_ACCOUNTS
  L2_2 = L2_2(L3_2)
  L3_2 = L2_2.GetAccountBySource
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    L4_2 = false
    return L4_2
  end
  L4_2 = L2_2.deleteAccount
  L5_2 = A1_2
  L4_2(L5_2)
end
L0_1.DeleteAccount = L1_1
L0_1 = PrisonAccountService
function L1_1()
  local L0_2, L1_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_PRISONER_ACCOUNTS
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    return
  end
  L1_2 = L0_2.saveAllAccounts
  L1_2()
end
L0_1.saveAllAccounts = L1_1
L0_1 = PrisonAccountService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  L3_2 = false
  L4_2 = Object
  L4_2 = L4_2.getStorage
  L5_2 = STORAGE_PRISONER_ACCOUNTS
  L4_2 = L4_2(L5_2)
  L5_2 = L4_2.GetAccountBySource
  L6_2 = A0_2
  L5_2 = L5_2(L6_2)
  if not L5_2 then
    L6_2 = dbg
    L6_2 = L6_2.critical
    L7_2 = "Failed to create transactions since player account not found"
    L6_2(L7_2)
    return L3_2
  end
  return L3_2
end
L0_1.CreateTransaction = L1_1
L0_1 = PrisonAccountService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L3_2 = Object
  L3_2 = L3_2.getStorage
  L4_2 = STORAGE_PRISONER_ACCOUNTS
  L3_2 = L3_2(L4_2)
  L4_2 = L3_2.GetAccountBySource
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if A1_2 <= 0 then
    return
  end
  if not A2_2 then
    A2_2 = "No reason provided"
  end
  if L4_2 then
    L5_2 = L4_2.balance
    L6_2 = L4_2.balance
    L6_2 = L6_2 + A1_2
    L4_2.balance = L6_2
    if "PRISON_JOB_REWARD" == A2_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "JOB.RECEIVED_CREDITS"
      L10_2 = A1_2
      L8_2 = L8_2(L9_2, L10_2)
      L9_2 = "success"
      L6_2(L7_2, L8_2, L9_2)
    end
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "Player named %s (%s) added [%s] credits to his account because: %s | old balance: %s | new balance: %s"
    L8_2 = GetPlayerName
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    L9_2 = A0_2
    L10_2 = A1_2
    L11_2 = A2_2
    L12_2 = L5_2
    L13_2 = L4_2.balance
    L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
    L6_2 = StartClient
    L7_2 = A0_2
    L8_2 = "UpdatePrisonerAccount"
    L9_2 = L4_2
    L6_2(L7_2, L8_2, L9_2)
  end
end
L0_1.AddCredits = L1_1
L0_1 = PrisonAccountService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_PRISONER_ACCOUNTS
  L2_2 = L2_2(L3_2)
  L3_2 = L2_2.GetAccountBySource
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  if L3_2 then
    L4_2 = L3_2.balance
    L4_2 = L4_2 - A1_2
    L3_2.balance = L4_2
    L4_2 = L3_2.balance
    if L4_2 < 0 then
      L3_2.balance = 0
    end
  end
end
L0_1.RemoveCredits = L1_1
L0_1 = PrisonAccountService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER_ACCOUNTS
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetAccountBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L3_2 = StartClient
    L4_2 = A0_2
    L5_2 = "UpdatePrisonerAccount"
    L6_2 = L2_2
    L3_2(L4_2, L5_2, L6_2)
  end
end
L0_1.LoadAccount = L1_1
L0_1 = PrisonAccountService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER_ACCOUNTS
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetAccountBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L3_2 = dbg
    L3_2 = L3_2.critical
    L4_2 = "Player already exists"
    L3_2(L4_2)
    L3_2 = nil
    return L3_2
  end
  L3_2 = Framework
  L3_2 = L3_2.getIdentifier
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = db
  L4_2 = L4_2.CreatePrisonerAccount
  L5_2 = L3_2
  L6_2 = false
  L4_2 = L4_2(L5_2, L6_2)
  if not L4_2 then
    L5_2 = dbg
    L5_2 = L5_2.critical
    L6_2 = "Failed to create player"
    L5_2(L6_2)
    L5_2 = nil
    return L5_2
  end
  L5_2 = {}
  L5_2.owner = L3_2
  L5_2.id = L4_2
  L5_2.balance = 0
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "Player named %s (%s) created a new account"
  L8_2 = GetPlayerName
  L9_2 = A0_2
  L8_2 = L8_2(L9_2)
  L9_2 = A0_2
  L6_2(L7_2, L8_2, L9_2)
  L6_2 = StartClient
  L7_2 = A0_2
  L8_2 = "UpdatePrisonerAccount"
  L9_2 = L5_2
  L6_2(L7_2, L8_2, L9_2)
  L6_2 = L1_2.AddPlayer
  L7_2 = L5_2
  return L6_2(L7_2)
end
L0_1.createAccount = L1_1
L0_1 = PrisonAccountService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L0_2 = "LOADED_DATA_INTO_CACHE"
  L1_2 = db
  L1_2 = L1_2.FetchPrisonersAccounts
  L1_2 = L1_2()
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_PRISONER_ACCOUNTS
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
        L9_2 = PrisonAccount
        L9_2 = L9_2()
        L10_2 = L8_2.owner
        L9_2.owner = L10_2
        L10_2 = L8_2.balance
        L9_2.balance = L10_2
        L10_2 = L8_2.giftstate
        L9_2.giftState = L10_2
        L10_2 = L8_2.account_id
        L9_2.id = L10_2
        L10_2 = L2_2.AddPlayer
        L11_2 = L9_2
        L10_2(L11_2)
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
    L0_2 = "NOT_ANY_PRISONERS_IN_DB"
    L5_2 = L3_2
    L4_2 = L3_2.resolve
    L6_2 = true
    L4_2(L5_2, L6_2)
  end
  L4_2 = Citizen
  L4_2 = L4_2.Await
  L5_2 = L3_2
  L4_2(L5_2)
  if L0_2 then
    L4_2 = dbg
    L4_2 = L4_2.debug
    L5_2 = "Prisoner accounts data into cache state: %s"
    L6_2 = L0_2
    L4_2(L5_2, L6_2)
  end
  L4_2 = Wait
  L5_2 = 0
  L4_2(L5_2)
  L4_2 = L2_2.CheckOnlinePlayers
  L4_2()
end
L0_1.LoadAllAccounts = L1_1
L0_1 = AddEventHandler
L1_1 = "onResourceStop"
function L2_1(A0_2)
  local L1_2
  L1_2 = GetCurrentResourceName
  L1_2 = L1_2()
  if A0_2 == L1_2 then
    L1_2 = PrisonAccountService
    L1_2 = L1_2.saveAllAccounts
    L1_2()
  end
end
L0_1(L1_1, L2_1)
