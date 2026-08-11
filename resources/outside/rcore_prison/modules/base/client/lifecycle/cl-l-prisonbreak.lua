local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "destroyWall"
function L2_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2
  if A0_2 then
    L4_2 = DestroyWall
    L5_2 = A1_2
    L6_2 = A2_2
    L7_2 = A3_2
    L4_2(L5_2, L6_2, L7_2)
  end
end
L0_1(L1_1, L2_1)
