local L0_1, L1_1, L2_1
L0_1 = callback
L0_1 = L0_1.register
L1_1 = "rcore_prison:server:getAllLogs"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L2_2 = Framework
  L2_2 = L2_2.canPerformJobCommand
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L2_2 = {}
    return L2_2
  end
  L2_2 = LogService
  L2_2 = L2_2.GetLogs
  L2_2 = L2_2()
  L3_2 = table
  L3_2 = L3_2.size
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = {}
  if L2_2 then
    L5_2 = pairs
    L6_2 = L2_2
    L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
    for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
      L11_2 = table
      L11_2 = L11_2.insert
      L12_2 = L4_2
      L13_2 = L10_2
      L11_2(L12_2, L13_2)
    end
  end
  L5_2 = {}
  L6_2 = 4 == L3_2 or L6_2
  L5_2.hasMore = L6_2
  L5_2.logs = L4_2
  return L5_2
end
L0_1(L1_1, L2_1)
