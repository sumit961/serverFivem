local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1
L0_1 = {}
L0_1.DEPOSIT = true
L0_1.WITHDRAW = true
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:registerPrisonerAccount"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  if A1_2 then
    L3_2 = PrisonService
    L3_2 = L3_2.getPlayer
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      L4_2 = Framework
      L4_2 = L4_2.sendNotification
      L5_2 = A0_2
      L6_2 = "You are not a prisoner"
      L7_2 = "error"
      return L4_2(L5_2, L6_2, L7_2)
    end
    L4_2 = PrisonAccountService
    L4_2 = L4_2.getPlayer
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    if not L4_2 then
      L5_2 = PrisonAccountService
      L5_2 = L5_2.createAccount
      L6_2 = A0_2
      L5_2(L6_2)
    else
      L5_2 = PrisonAccountService
      L5_2 = L5_2.LoadAccount
      L6_2 = A0_2
      L5_2(L6_2)
    end
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:executePrisonerAccountTask"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if A1_2 then
    L4_2 = PrisonService
    L4_2 = L4_2.getPlayer
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    if not L4_2 then
      L5_2 = Framework
      L5_2 = L5_2.sendNotification
      L6_2 = A0_2
      L7_2 = "You are not a prisoner"
      L8_2 = "error"
      return L5_2(L6_2, L7_2, L8_2)
    end
    if not A2_2 then
      return
    end
    L5_2 = PrisonAccountService
    L5_2 = L5_2.getPlayer
    L6_2 = A0_2
    L5_2 = L5_2(L6_2)
    if L5_2 then
      L6_2 = false
      L7_2 = A3_2.action
      L8_2 = A3_2.amount
      if L8_2 then
        L8_2 = tonumber
        L9_2 = A3_2.amount
        L8_2 = L8_2(L9_2)
      end
      L9_2 = L0_1
      L9_2 = L9_2[L7_2]
      if L9_2 and L8_2 then
        L9_2 = PrisonAccountService
        L9_2 = L9_2.CreateTransaction
        L10_2 = A0_2
        L11_2 = L7_2
        L12_2 = L8_2
        L9_2 = L9_2(L10_2, L11_2, L12_2)
        L6_2 = L9_2
      end
      if L6_2 then
        L9_2 = StartClient
        L10_2 = A0_2
        L11_2 = "UpdatePrisonerAccount"
        L12_2 = L5_2
        L9_2(L10_2, L11_2, L12_2)
      end
    end
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
