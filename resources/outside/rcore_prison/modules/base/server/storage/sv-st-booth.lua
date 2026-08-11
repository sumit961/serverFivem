local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = {}
  L0_2.Booths = L1_2
  L1_2 = RegisterCommand
  L2_2 = "booths"
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    if 0 == A0_3 then
      L3_3 = L0_2.Booths
      if L3_3 then
        L3_3 = next
        L4_3 = L0_2.Booths
        L3_3 = L3_3(L4_3)
        if L3_3 then
          L3_3 = tprint
          L4_3 = L0_2.Booths
          L3_3(L4_3)
      end
      else
        L3_3 = print
        L4_3 = "No booths found."
        L3_3(L4_3)
      end
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2.Booths
    L1_3 = L1_3[A0_3]
    return L1_3
  end
  L0_2.getBooth = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2.Booths
    L2_3 = A0_3.number
    L1_3[L2_3] = A0_3
  end
  L0_2.registerBooth = L1_2
  return L0_2
end
BoothStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_BOOTH
L2_1 = BoothStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
