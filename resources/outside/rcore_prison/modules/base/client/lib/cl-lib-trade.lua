local L0_1, L1_1, L2_1
L0_1 = {}
Trade = L0_1
L0_1 = Trade
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = HelpKeys
  L1_2 = L1_2.Hide
  L1_2()
  L1_2 = FrontendService
  L1_2 = L1_2.HandleFocus
  L2_2 = true
  L1_2(L2_2)
  L1_2 = FrontendService
  L1_2 = L1_2.SendReactMessage
  L2_2 = FE_EVENTS
  L2_2 = L2_2.LOAD_APP
  L3_2 = {}
  L4_2 = Screens
  L4_2 = L4_2.TRADING
  L3_2.screen = L4_2
  L3_2.visible = true
  L1_2(L2_2, L3_2)
end
L0_1.Open = L1_1
L0_1 = RegisterNuiCallback
L1_1 = "buyItem"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = TriggerServerEvent
  L3_2 = "rcore_prison:server:requestBuyDealerItem"
  L4_2 = A0_2
  L5_2 = SH
  L5_2 = L5_2.zoneId
  L2_2(L3_2, L4_2, L5_2)
  L2_2 = A1_2
  L3_2 = true
  L2_2(L3_2)
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNuiCallback
L1_1 = "getTradeItems"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = SH
  L2_2 = L2_2.zoneId
  if not L2_2 then
    return
  end
  L2_2 = SH
  L2_2 = L2_2.data
  L2_2 = L2_2.interaction
  L3_2 = SH
  L3_2 = L3_2.zoneId
  L2_2 = L2_2[L3_2]
  if not L2_2 then
    return
  end
  L3_2 = L2_2.items
  L4_2 = A1_2
  L5_2 = L3_2
  L4_2(L5_2)
end
L0_1(L1_1, L2_1)
