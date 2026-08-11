local L0_1, L1_1
L0_1 = {}
NetworkService = L0_1
L0_1 = NetworkService
function L1_1(A0_2, A1_2, ...)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = "%s:%s:%s"
  L3_2 = L2_2
  L2_2 = L2_2.format
  L4_2 = GetCurrentResourceName
  L4_2 = L4_2()
  L5_2 = "client"
  L6_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
  L3_2 = dbg
  L3_2 = L3_2.debugNetwork
  L4_2 = "Registering protected event named: %s"
  L5_2 = A0_2
  L3_2(L4_2, L5_2)
  L3_2 = RegisterNetEvent
  L4_2 = L2_2
  function L5_2(...)
    local L0_3, L1_3, L2_3
    L0_3 = source
    if "" == L0_3 then
      return
    end
    L0_3 = A1_2
    L1_3 = true
    L2_3 = ...
    L0_3(L1_3, L2_3)
  end
  L3_2(L4_2, L5_2)
end
L0_1.RegisterNetEvent = L1_1
L0_1 = NetworkService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = "%s:%s:%s"
  L3_2 = L2_2
  L2_2 = L2_2.format
  L4_2 = GetCurrentResourceName
  L4_2 = L4_2()
  L5_2 = "client"
  L6_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
  L3_2 = AddEventHandler
  L4_2 = L2_2
  function L5_2(...)
    local L0_3, L1_3
    L0_3 = A1_2
    L1_3 = ...
    L0_3(L1_3)
  end
  L3_2(L4_2, L5_2)
end
L0_1.EventListener = L1_1
