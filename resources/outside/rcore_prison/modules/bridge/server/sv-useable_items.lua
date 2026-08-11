local L0_1, L1_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2
  L0_2 = Config
  L0_2 = L0_2.Inventories
  L1_2 = Inventories
  L1_2 = L1_2.NONE
  if L0_2 ~= L1_2 then
    L0_2 = Inventory
    L0_2 = L0_2.registerUsableItem
    L1_2 = Config
    L1_2 = L1_2.UseableItems
    if L1_2 then
      L1_2 = Config
      L1_2 = L1_2.UseableItems
      L1_2 = L1_2.Tablet
      if L1_2 then
        goto lbl_19
      end
    end
    L1_2 = "prison_tablet"
    ::lbl_19::
    function L2_2(A0_3)
      local L1_3, L2_3, L3_3, L4_3
      L1_3 = Framework
      L1_3 = L1_3.canPerformJobCommand
      L2_3 = A0_3
      L3_3 = Config
      L3_3 = L3_3.Commands
      L3_3 = L3_3.JailCP
      L1_3 = L1_3(L2_3, L3_3)
      if not L1_3 then
        L1_3 = Framework
        L1_3 = L1_3.sendNotification
        L2_3 = A0_3
        L3_3 = _U
        L4_3 = "GENERAL.YOU_NEED_TO_BE_IN_JOB"
        L3_3 = L3_3(L4_3)
        L4_3 = "error"
        L1_3(L2_3, L3_3, L4_3)
        L1_3 = dbg
        L1_3 = L1_3.info
        L2_3 = "Cannot perform this command - you are not job member!"
        L3_3 = A0_3
        L1_3(L2_3, L3_3)
        return
      end
      L1_3 = TriggerClientEvent
      L2_3 = "rcore_prison:client:openDashboard"
      L3_3 = A0_3
      L1_3(L2_3, L3_3)
    end
    L0_2(L1_2, L2_2)
  end
end
L0_1(L1_1)
