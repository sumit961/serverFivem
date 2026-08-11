local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = {}
  L0_2._cigarProductionStorage = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2._cigarProductionStorage
    L0_3 = #L0_3
    L0_3 = L0_3 + 1
    return L0_3
  end
  L0_2.GetIdForSession = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3
    L1_3 = promise
    L1_3 = L1_3.new
    L1_3 = L1_3()
    L2_3 = nil
    L3_3 = 1
    L4_3 = L0_2._cigarProductionStorage
    L4_3 = #L4_3
    L5_3 = 1
    for L6_3 = L3_3, L4_3, L5_3 do
      L7_3 = L0_2._cigarProductionStorage
      L7_3 = L7_3[L6_3]
      L7_3 = L7_3.playerId
      if L7_3 == A0_3 then
        L2_3 = L6_3
      end
      L7_3 = L0_2._cigarProductionStorage
      L7_3 = #L7_3
      if L6_3 >= L7_3 then
        L8_3 = L1_3
        L7_3 = L1_3.resolve
        L9_3 = L2_3
        L7_3(L8_3, L9_3)
      end
    end
    L3_3 = Citizen
    L3_3 = L3_3.Await
    L4_3 = L1_3
    return L3_3(L4_3)
  end
  L0_2.GetSessionBySource = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2.GetSessionBySource
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L2_3 = L0_2._cigarProductionStorage
      L2_3[L1_3] = nil
      L2_3 = true
      return L2_3
    else
      L2_3 = false
      return L2_3
    end
  end
  L0_2.UnregisterSession = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    if not A0_3 then
      return
    end
    L1_3 = L0_2._cigarProductionStorage
    L2_3 = A0_3.id
    L1_3[L2_3] = A0_3
    L1_3 = A0_3.id
    return L1_3
  end
  L0_2.RegisterSession = L1_2
  L1_2 = RegisterCommand
  L2_2 = "prison_cigar_production"
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    if 0 == A0_3 then
      L3_3 = next
      L4_3 = L0_2._cigarProductionStorage
      L3_3 = L3_3(L4_3)
      if L3_3 then
        L3_3 = tprint
        L4_3 = L0_2._cigarProductionStorage
        L3_3(L4_3)
      else
        L3_3 = dbg
        L3_3 = L3_3.debug
        L4_3 = "There is no active cigar production sessions!"
        L3_3(L4_3)
      end
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  return L0_2
end
CigarProductionStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_CIGAR_PRODUCTION
L2_1 = CigarProductionStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
