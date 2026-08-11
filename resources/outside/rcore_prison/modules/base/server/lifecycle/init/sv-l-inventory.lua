local L0_1, L1_1
L0_1 = Inventory
L1_1 = {}
L0_1.KeepSessionItems = L1_1
L0_1 = Inventory
L1_1 = {}
L0_1.KeepSessionItemsWithName = L1_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L0_2 = Config
  L0_2 = L0_2.Stash
  L0_2 = L0_2.KeepItems
  if not L0_2 then
    L0_2 = Config
    L0_2 = L0_2.Stash
    L0_2 = L0_2.KeepItemsState
    if L0_2 then
      L0_2 = Config
      L0_2 = L0_2.Stash
      L0_2.KeepItemsState = false
    end
    return
  end
  L0_2 = Config
  L0_2 = L0_2.Stash
  L0_2 = L0_2.KeepItems
  if not L0_2 then
    L1_2 = Config
    L1_2 = L1_2.Stash
    L1_2 = L1_2.KeepItemsState
    if L1_2 then
      L1_2 = Config
      L1_2 = L1_2.Stash
      L1_2.KeepItemsState = false
    end
    return
  end
  L1_2 = pairs
  L2_2 = L0_2
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = Config
    L7_2 = L7_2.Inventories
    L8_2 = Inventories
    L8_2 = L8_2.ESX
    if L7_2 == L8_2 then
      L7_2 = Inventory
      L7_2 = L7_2.KeepSessionItems
      L7_2[L5_2] = true
    else
      L7_2 = Inventory
      L7_2 = L7_2.KeepSessionItemsWithName
      L7_2[L5_2] = L6_2
      L7_2 = Config
      L7_2 = L7_2.Inventories
      L8_2 = Inventories
      L8_2 = L8_2.OX
      if L7_2 == L8_2 and false == L6_2 then
        return
      end
      L7_2 = table
      L7_2 = L7_2.insert
      L8_2 = Inventory
      L8_2 = L8_2.KeepSessionItems
      L9_2 = L5_2
      L7_2(L8_2, L9_2)
    end
  end
end
L0_1(L1_1)
