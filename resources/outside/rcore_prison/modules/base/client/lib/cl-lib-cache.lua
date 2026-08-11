local L0_1, L1_1
L0_1 = {}
Cache = L0_1
L0_1 = Cache
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = "%s_%s"
  L1_2 = L0_2
  L0_2 = L0_2.format
  L2_2 = "PRISON"
  L3_2 = "OUTFIT"
  L4_2 = GetPlayerName
  L5_2 = PlayerId
  L5_2 = L5_2()
  L4_2, L5_2 = L4_2(L5_2)
  L0_2 = L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
  L1_2 = GetResourceKvpString
  L2_2 = L0_2
  L1_2 = L1_2(L2_2)
  if L1_2 then
    L2_2 = DeleteResourceKvp
    L3_2 = L0_2
    L2_2(L3_2)
  end
end
L0_1.DeleteOutfitKVP = L1_1
L0_1 = Cache
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = "%s_%s"
  L2_2 = L1_2
  L1_2 = L1_2.format
  L3_2 = "PRISON"
  L4_2 = "OUTFIT"
  L5_2 = GetPlayerName
  L6_2 = PlayerId
  L6_2 = L6_2()
  L5_2, L6_2 = L5_2(L6_2)
  L1_2 = L1_2(L2_2, L3_2, L4_2, L5_2, L6_2)
  if not L1_2 then
    L2_2 = nil
    return L2_2
  end
  L2_2 = SetResourceKvp
  L3_2 = L1_2
  L4_2 = A0_2
  return L2_2(L3_2, L4_2)
end
L0_1.SaveOutfitKVP = L1_1
L0_1 = Cache
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = "%s_%s"
  L1_2 = L0_2
  L0_2 = L0_2.format
  L2_2 = "PRISON"
  L3_2 = "OUTFIT"
  L4_2 = GetPlayerName
  L5_2 = PlayerId
  L5_2 = L5_2()
  L4_2, L5_2 = L4_2(L5_2)
  L0_2 = L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
  if not L0_2 then
    L1_2 = nil
    return L1_2
  end
  L1_2 = GetResourceKvpString
  L2_2 = L0_2
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2 or L2_2
  if L1_2 then
    L2_2 = tonumber
    L3_2 = L1_2
    L2_2 = L2_2(L3_2)
  end
  return L2_2
end
L0_1.GetOutfitKVP = L1_1
L0_1 = Cache
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = "%s_%s"
  L1_2 = L0_2
  L0_2 = L0_2.format
  L2_2 = "PRISON"
  L3_2 = "PROLOG"
  L4_2 = GetPlayerName
  L5_2 = PlayerId
  L5_2 = L5_2()
  L4_2, L5_2 = L4_2(L5_2)
  L0_2 = L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
  L1_2 = GetResourceKvpInt
  L2_2 = L0_2
  L1_2 = L1_2(L2_2)
  if 1 == L1_2 then
    L2_2 = DeleteResourceKvp
    L3_2 = L0_2
    L2_2(L3_2)
  end
end
L0_1.DeletePrologKVP = L1_1
L0_1 = Cache
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = "%s_%s"
  L1_2 = L0_2
  L0_2 = L0_2.format
  L2_2 = "PRISON"
  L3_2 = "PROLOG"
  L4_2 = GetPlayerName
  L5_2 = PlayerId
  L5_2 = L5_2()
  L4_2, L5_2 = L4_2(L5_2)
  L0_2 = L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
  L1_2 = GetResourceKvpInt
  L2_2 = L0_2
  L1_2 = L1_2(L2_2)
  return L1_2
end
L0_1.GetPrologKVP = L1_1
L0_1 = Cache
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = "%s_%s"
  L2_2 = L1_2
  L1_2 = L1_2.format
  L3_2 = "PRISON"
  L4_2 = "PROLOG"
  L5_2 = GetPlayerName
  L6_2 = PlayerId
  L6_2 = L6_2()
  L5_2, L6_2 = L5_2(L6_2)
  L1_2 = L1_2(L2_2, L3_2, L4_2, L5_2, L6_2)
  L2_2 = SetResourceKvpInt
  L3_2 = L1_2
  L4_2 = A0_2
  return L2_2(L3_2, L4_2)
end
L0_1.SetPrologKVP = L1_1
