local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = {}
  L0_2._prisonBreakSessions = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2._prisonBreakSessions
    L0_3 = L0_3.state
    return L0_3
  end
  L0_2.GetState = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = {}
    L1_3.state = true
    L0_2._prisonBreakSessions = L1_3
    L1_3 = true
    return L1_3
  end
  L0_2.RegisterSession = L1_2
  L1_2 = RegisterCommand
  L2_2 = "prison_break"
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    if 0 == A0_3 then
      L3_3 = next
      L4_3 = L0_2._prisonBreakSessions
      L3_3 = L3_3(L4_3)
      if L3_3 then
        L3_3 = tprint
        L4_3 = L0_2._prisonBreakSessions
        L3_3(L4_3)
      else
        L3_3 = dbg
        L3_3 = L3_3.debug
        L4_3 = "There is no active prison break sessions!"
        L3_3(L4_3)
      end
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  return L0_2
end
PrisonBreakStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_PRISON_BREAK
L2_1 = PrisonBreakStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
