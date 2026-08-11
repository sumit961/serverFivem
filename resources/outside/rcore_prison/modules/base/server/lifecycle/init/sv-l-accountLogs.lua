local L0_1, L1_1, L2_1
L0_1 = callback
L0_1 = L0_1.register
L1_1 = "rcore_prison:server:getPrisonerAccountLogs"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L2_2 = Framework
  L2_2 = L2_2.getIdentifier
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = {}
    return L3_2
  end
  L3_2 = AccountLogService
  L3_2 = L3_2.GetLogsByCharId
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    L4_2 = {}
    return L4_2
  end
  L4_2 = table
  L4_2 = L4_2.size
  L5_2 = L3_2
  L4_2 = L4_2(L5_2)
  L5_2 = {}
  if L3_2 then
    L6_2 = pairs
    L7_2 = L3_2
    L6_2, L7_2, L8_2, L9_2 = L6_2(L7_2)
    for L10_2, L11_2 in L6_2, L7_2, L8_2, L9_2 do
      L12_2 = table
      L12_2 = L12_2.insert
      L13_2 = L5_2
      L14_2 = L11_2
      L12_2(L13_2, L14_2)
    end
  end
  L6_2 = {}
  L7_2 = 4 == L4_2 or L7_2
  L6_2.hasMore = L7_2
  L6_2.logs = L5_2
  return L6_2
end
L0_1(L1_1, L2_1)
