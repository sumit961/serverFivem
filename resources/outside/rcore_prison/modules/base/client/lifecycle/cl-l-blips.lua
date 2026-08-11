local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "createSquaredArea"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = Blips
    L2_2 = L2_2.CreateSquaredArea
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "RemoveBlipByType"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = Blips
    L2_2 = L2_2.RemoveByType
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "SetWaypoint"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = Blips
    L2_2 = L2_2.SetWaypoint
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
