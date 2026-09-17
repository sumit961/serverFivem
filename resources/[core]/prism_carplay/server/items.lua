

local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1
L0_1 = nil
L1_1 = nil
L2_1 = nil
function L3_1()
  local L0_2, L1_2, L2_2
  L0_2 = GetResourceState
  L1_2 = "es_extended"
  L0_2 = L0_2(L1_2)
  if "started" == L0_2 then
    L0_2 = "esx"
    L2_1 = L0_2
    L0_2 = exports
    L0_2 = L0_2.es_extended
    L1_2 = L0_2
    L0_2 = L0_2.getSharedObject
    L0_2 = L0_2(L1_2)
    L0_1 = L0_2
  else
    L0_2 = GetResourceState
    L1_2 = "qb-core"
    L0_2 = L0_2(L1_2)
    if "started" ~= L0_2 then
      L0_2 = GetResourceState
      L1_2 = "qbx_core"
      L0_2 = L0_2(L1_2)
      if "started" ~= L0_2 then
        goto lbl_32
      end
    end
    L0_2 = "qbcore"
    L2_1 = L0_2
    L0_2 = exports
    L0_2 = L0_2["qb-core"]
    L1_2 = L0_2
    L0_2 = L0_2.GetCoreObject
    L0_2 = L0_2(L1_2)
    L1_1 = L0_2
    goto lbl_34
    ::lbl_32::
    L0_2 = "standalone"
    L2_1 = L0_2
  end
  ::lbl_34::
  L0_2 = print
  L1_2 = "^2[Prism-CarPlay]^7 Framework detected: "
  L2_2 = L2_1
  L1_2 = L1_2 .. L2_2
  L0_2(L1_2)
end
function L4_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = TriggerClientEvent
  L2_2 = "prism-carplay:client:useCarplayItem"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
end
UseCarplayItem = L4_1
function L4_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = TriggerClientEvent
  L2_2 = "prism-carplay:client:useTunerChip"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
end
UseTunerChip = L4_1
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = L2_1
  if "esx" == L2_2 then
    L2_2 = L0_1.GetPlayerFromId
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if L2_2 then
      L3_2 = L2_2.addInventoryItem
      L4_2 = "carplay"
      L5_2 = 1
      L3_2(L4_2, L5_2)
    end
  else
    L2_2 = L2_1
    if "qbcore" == L2_2 then
      L2_2 = L1_1.Functions
      L2_2 = L2_2.GetPlayer
      L3_2 = A0_2
      L2_2 = L2_2(L3_2)
      if L2_2 then
        L3_2 = L2_2.Functions
        L3_2 = L3_2.AddItem
        L4_2 = "carplay"
        L5_2 = 1
        L3_2(L4_2, L5_2)
      end
    end
  end
end
RemoveCarplayItem = L4_1
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = L2_1
  if "esx" == L2_2 then
    L2_2 = L0_1.GetPlayerFromId
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if L2_2 then
      L3_2 = L2_2.addInventoryItem
      L4_2 = "tunerchip"
      L5_2 = 1
      L3_2(L4_2, L5_2)
    end
  else
    L2_2 = L2_1
    if "qbcore" == L2_2 then
      L2_2 = L1_1.Functions
      L2_2 = L2_2.GetPlayer
      L3_2 = A0_2
      L2_2 = L2_2(L3_2)
      if L2_2 then
        L3_2 = L2_2.Functions
        L3_2 = L3_2.AddItem
        L4_2 = "tunerchip"
        L5_2 = 1
        L3_2(L4_2, L5_2)
      end
    end
  end
end
RemoveTunerChip = L4_1
L4_1 = CreateThread
function L5_1()
  local L0_2, L1_2, L2_2
  L0_2 = Wait
  L1_2 = 1000
  L0_2(L1_2)
  L0_2 = L3_1
  L0_2()
  L0_2 = L2_1
  if "esx" == L0_2 then
    L0_2 = L0_1.RegisterUsableItem
    L1_2 = "carplay"
    function L2_2(A0_3)
      local L1_3, L2_3, L3_3, L4_3
      L1_3 = L0_1.GetPlayerFromId
      L2_3 = A0_3
      L1_3 = L1_3(L2_3)
      if not L1_3 then
        return
      end
      L2_3 = UseCarplayItem
      L3_3 = A0_3
      L2_3(L3_3)
      L2_3 = L1_3.removeInventoryItem
      L3_3 = "carplay"
      L4_3 = 1
      L2_3(L3_3, L4_3)
    end
    L0_2(L1_2, L2_2)
    L0_2 = L0_1.RegisterUsableItem
    L1_2 = "tunerchip"
    function L2_2(A0_3)
      local L1_3, L2_3, L3_3, L4_3
      L1_3 = L0_1.GetPlayerFromId
      L2_3 = A0_3
      L1_3 = L1_3(L2_3)
      if not L1_3 then
        return
      end
      L2_3 = UseTunerChip
      L3_3 = A0_3
      L2_3(L3_3)
      L2_3 = L1_3.removeInventoryItem
      L3_3 = "tunerchip"
      L4_3 = 1
      L2_3(L3_3, L4_3)
    end
    L0_2(L1_2, L2_2)
  else
    L0_2 = L2_1
    if "qbcore" == L0_2 then
      L0_2 = L1_1.Functions
      L0_2 = L0_2.CreateUseableItem
      L1_2 = "carplay"
      function L2_2(A0_3)
        local L1_3, L2_3, L3_3, L4_3
        L1_3 = L1_1.Functions
        L1_3 = L1_3.GetPlayer
        L2_3 = A0_3
        L1_3 = L1_3(L2_3)
        if not L1_3 then
          return
        end
        L2_3 = UseCarplayItem
        L3_3 = A0_3
        L2_3(L3_3)
        L2_3 = L1_3.Functions
        L2_3 = L2_3.RemoveItem
        L3_3 = "carplay"
        L4_3 = 1
        L2_3(L3_3, L4_3)
      end
      L0_2(L1_2, L2_2)
      L0_2 = L1_1.Functions
      L0_2 = L0_2.CreateUseableItem
      L1_2 = "tunerchip"
      function L2_2(A0_3)
        local L1_3, L2_3, L3_3, L4_3
        L1_3 = L1_1.Functions
        L1_3 = L1_3.GetPlayer
        L2_3 = A0_3
        L1_3 = L1_3(L2_3)
        if not L1_3 then
          return
        end
        L2_3 = UseTunerChip
        L3_3 = A0_3
        L2_3(L3_3)
        L2_3 = L1_3.Functions
        L2_3 = L2_3.RemoveItem
        L3_3 = "tunerchip"
        L4_3 = 1
        L2_3(L3_3, L4_3)
      end
      L0_2(L1_2, L2_2)
    end
  end
end
L4_1(L5_1)

