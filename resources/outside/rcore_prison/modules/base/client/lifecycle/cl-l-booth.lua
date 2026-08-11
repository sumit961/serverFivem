local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "openBooth"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = Booths
    L2_2 = L2_2.OpenUI
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "startCall"
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2
  if A0_2 then
    L3_2 = Booths
    L3_2 = L3_2.StartCall
    L4_2 = A1_2
    L5_2 = A2_2
    L3_2(L4_2, L5_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "endCall"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = Booths
    L2_2 = L2_2.EndCall
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "ResetCallState"
function L2_1(A0_2)
  local L1_2
  if A0_2 then
    L1_2 = Booths
    L1_2 = L1_2.Reset
    L1_2()
  end
end
L0_1(L1_1, L2_1)
