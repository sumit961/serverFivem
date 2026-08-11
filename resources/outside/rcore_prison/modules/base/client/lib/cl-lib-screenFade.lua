local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "screenFadeIn"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Screen fade in request received!"
    L2_2(L3_2)
    L2_2 = DoScreenFadeIn
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "screenFadeOut"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Screen fade out request received!"
    L2_2(L3_2)
    L2_2 = DoScreenFadeOut
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
