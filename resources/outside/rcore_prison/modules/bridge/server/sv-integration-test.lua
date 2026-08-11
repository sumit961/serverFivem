local L0_1, L1_1, L2_1, L3_1
L0_1 = RegisterCommand
L1_1 = "rcore_prison_test_dispatch"
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2
  if 0 == A0_2 then
    L3_2 = dbg
    L3_2 = L3_2.info
    L4_2 = "Testing dispatch for prison - sending message via: %s"
    L5_2 = Config
    L5_2 = L5_2.Dispatches
    L3_2(L4_2, L5_2)
    L3_2 = Dispatch
    L3_2 = L3_2.Breakout
    L4_2 = -1
    L3_2(L4_2)
    L3_2 = StartPrisonBreakAlarm
    L3_2()
  else
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "This command can be executed only from server console!"
    L3_2(L4_2)
  end
end
L3_1 = false
L0_1(L1_1, L2_1, L3_1)
