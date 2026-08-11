local L0_1, L1_1
L0_1 = {}
PrisonerAccountService = L0_1
L0_1 = PrisonerAccountService
function L1_1()
  local L0_2, L1_2, L2_2
  L0_2 = dbg
  L0_2 = L0_2.debug
  L1_2 = "Resetting prisoner account"
  L0_2(L1_2)
  L0_2 = FrontendService
  L0_2 = L0_2.SendReactMessage
  L1_2 = "syncPrisonerAccount"
  L2_2 = {}
  L0_2(L1_2, L2_2)
end
L0_1.Reset = L1_1
