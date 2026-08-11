local L0_1, L1_1
L0_1 = {}
SolitaryService = L0_1
L0_1 = SolitaryService
function L1_1()
  local L0_2, L1_2
  L0_2 = dbg
  L0_2 = L0_2.debug
  L1_2 = "Releasing prisoner from solitary"
  L0_2(L1_2)
  L0_2 = TriggerServerEvent
  L1_2 = "rcore_prison:server:requestSolitaryRelease"
  L0_2(L1_2)
end
L0_1.ReleasePrisoner = L1_1
