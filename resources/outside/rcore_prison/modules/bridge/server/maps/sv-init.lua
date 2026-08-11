local L0_1, L1_1, L2_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2
  L0_2 = SH
  L0_2 = L0_2.preset
  if "standalone" == L0_2 then
    L0_2 = dbg
    L0_2 = L0_2.debug
    L1_2 = "TODO: Register deployer for standalone map"
    L0_2(L1_2)
  end
end
L2_1 = "sv-init code name: Phoenix"
L0_1(L1_1, L2_1)
