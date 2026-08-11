local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "openMDW"
function L2_1(A0_2)
  local L1_2
  if A0_2 then
    L1_2 = FrontendService
    L1_2 = L1_2.OpenMDW
    L1_2()
  end
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNuiCallback
L1_1 = "ADD_SENTENCE"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = TriggerServerEvent
  L3_2 = "rcore_prison:server:requestAddSentence"
  L4_2 = A0_2
  L2_2(L3_2, L4_2)
  L2_2 = A1_2
  L3_2 = "OK"
  L2_2(L3_2)
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNUICallback
L1_1 = "call"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = FrontendService
  L2_2 = L2_2.HandleShowState
  L3_2 = false
  L2_2(L3_2)
  L2_2 = TriggerServerEvent
  L3_2 = "rcore_prison:server:requestBoothCall"
  L4_2 = SH
  L4_2 = L4_2.zoneId
  L5_2 = A0_2
  L2_2(L3_2, L4_2, L5_2)
  L2_2 = A1_2
  L3_2 = "OK"
  L2_2(L3_2)
end
L0_1(L1_1, L2_1)
