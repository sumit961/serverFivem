local L0_1, L1_1, L2_1
L0_1 = {}
Canteen = L0_1
L0_1 = Canteen
function L1_1()
  local L0_2, L1_2, L2_2
  L0_2 = FrontendService
  L0_2 = L0_2.HandleFocus
  L1_2 = true
  L0_2(L1_2)
  L0_2 = FrontendService
  L0_2 = L0_2.SendReactMessage
  L1_2 = FE_EVENTS
  L1_2 = L1_2.LOAD_APP
  L2_2 = {}
  L2_2.screen = "Canteen"
  L2_2.visible = true
  L0_2(L1_2, L2_2)
end
L0_1.RequestOpen = L1_1
L0_1 = RegisterNuiCallback
L1_1 = "proceedCanteenTransaction"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = A1_2
  L3_2 = "OK"
  L2_2(L3_2)
  L2_2 = TriggerServerEvent
  L3_2 = "rcore_prison:server:requestCanteenTransaction"
  L4_2 = A0_2
  L2_2(L3_2, L4_2)
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNuiCallback
L1_1 = "getCanteen"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = dbg
  L2_2 = L2_2.debug
  L3_2 = "Fetching canteen data to FE!"
  L2_2(L3_2)
  L2_2 = A1_2
  L3_2 = {}
  L4_2 = Config
  L4_2 = L4_2.Canteen
  L4_2 = L4_2.FreeFoodPackageItems
  L3_2.free = L4_2
  L4_2 = Config
  L4_2 = L4_2.Canteen
  L4_2 = L4_2.CreditItems
  L3_2.paid = L4_2
  L2_2(L3_2)
end
L0_1(L1_1, L2_1)
