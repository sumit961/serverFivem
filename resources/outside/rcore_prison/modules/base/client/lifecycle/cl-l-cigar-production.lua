local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "startCigarProduction"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  if A0_2 then
    L2_2 = StartMinigame
    L3_2 = A1_2
    L4_2 = MINIGAME_PLACE_TYPE
    L4_2 = L4_2.CIGAR
    L2_2(L3_2, L4_2)
  end
end
L0_1(L1_1, L2_1)
