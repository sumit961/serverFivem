[0.146s][warning][os,thread] Failed to start thread "Unknown thread" - pthread_create failed (EAGAIN) for attributes: stacksize: 1024k, guardsize: 4k, detached.
local L0_1, L1_1
L0_1 = {}
NetworkService = L0_1
L0_1 = NetworkService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = "%s:%s:%s"
  L3_2 = L2_2
  L2_2 = L2_2.format
  L4_2 = GetCurrentResourceName
  L4_2 = L4_2()
  L5_2 = "server"
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
