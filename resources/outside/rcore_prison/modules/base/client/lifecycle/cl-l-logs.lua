local L0_1, L1_1, L2_1
L0_1 = RegisterNuiCallback
L1_1 = "getLogs"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = callback
  L2_2 = L2_2.await
  L3_2 = "rcore_prison:server:getAllLogs"
  L4_2 = false
  L5_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L3_2 = A1_2
  L4_2 = L2_2
  L3_2(L4_2)
end
L0_1(L1_1, L2_1)
