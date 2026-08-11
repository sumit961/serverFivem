local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2
  L0_2 = {}
  L1_2 = {}
  L0_2._accounts = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2._accounts
    L2_3 = A0_3.owner
    L1_3[L2_3] = A0_3
    L1_3 = true
    return L1_3
  end
  L0_2.AddPlayer = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2._accounts
    L1_3[A0_3] = nil
  end
  L0_2.deleteAccount = L1_2
  function L1_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3
    L0_3 = L0_2._accounts
    L1_3 = pairs
    L2_3 = L0_3
    L1_3, L2_3, L3_3, L4_3 = L1_3(L2_3)
    for L5_3, L6_3 in L1_3, L2_3, L3_3, L4_3 do
      L7_3 = L6_3.balance
      L8_3 = L6_3.owner
      if L6_3 then
        L9_3 = db
        L9_3 = L9_3.SavePrisonerAccount
        L10_3 = L8_3
        L11_3 = L7_3
        L12_3 = 1
        L9_3(L10_3, L11_3, L12_3)
      end
    end
  end
  L0_2.saveAllAccounts = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = L0_2.GetAccountBySource
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L2_3 = StartClient
      L3_3 = A0_3
      L4_3 = "UpdatePrisonerAccount"
      L5_3 = L1_3
      L2_3(L3_3, L4_3, L5_3)
    end
  end
  L0_2.LoadAccount = L1_2
  function L1_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3
    L0_3 = GetPlayers
    L0_3 = L0_3()
    L1_3 = promise
    L1_3 = L1_3.new
    L1_3 = L1_3()
    L2_3 = next
    L3_3 = L0_3
    L2_3 = L2_3(L3_3)
    if not L2_3 then
      return
    end
    L2_3 = 1
    L3_3 = #L0_3
    L4_3 = 1
    for L5_3 = L2_3, L3_3, L4_3 do
      L6_3 = tonumber
      L7_3 = L0_3[L5_3]
      L6_3 = L6_3(L7_3)
      L7_3 = Framework
      L7_3 = L7_3.getIdentifier
      L8_3 = L6_3
      L7_3 = L7_3(L8_3)
      L8_3 = L0_2._accounts
      L8_3 = L8_3[L7_3]
      if L8_3 then
        L8_3 = L0_2.LoadAccount
        L9_3 = L6_3
        L8_3(L9_3)
      end
      L8_3 = #L0_3
      if L5_3 >= L8_3 then
        L9_3 = L1_3
        L8_3 = L1_3.resolve
        L10_3 = true
        L8_3(L9_3, L10_3)
      end
      L8_3 = Wait
      L9_3 = 0
      L8_3(L9_3)
    end
    L2_3 = Citizen
    L2_3 = L2_3.Await
    L3_3 = L1_3
    L2_3(L3_3)
    L0_2._prisonerAccountsLoaded = true
  end
  L0_2.CheckOnlinePlayers = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = Framework
    L1_3 = L1_3.getIdentifier
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._accounts
    L2_3 = L2_3[L1_3]
    return L2_3
  end
  L0_2.GetAccountBySource = L1_2
  return L0_2
end
PrisonerAccountsStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_PRISONER_ACCOUNTS
L2_1 = PrisonerAccountsStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
