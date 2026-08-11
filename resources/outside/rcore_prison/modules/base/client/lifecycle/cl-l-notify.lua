local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "Notify"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = Framework
    L2_2 = L2_2.sendNotification
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
