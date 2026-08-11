local L0_1, L1_1
L0_1 = {}
CanteenService = L0_1
L0_1 = CanteenService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L1_2 = Config
  L1_2 = L1_2.Canteen
  L1_2 = L1_2.FreeFoodPackage
  if not L1_2 then
    return
  end
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_CANTEEN
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L2_2 = L1_2.isSessionRegistered
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L2_2 = Framework
    L2_2 = L2_2.sendNotification
    L3_2 = A0_2
    L4_2 = _U
    L5_2 = "CANTEEN.FREE_FOOD_PACKAGE_RECEIVED"
    L4_2 = L4_2(L5_2)
    L5_2 = "error"
    return L2_2(L3_2, L4_2, L5_2)
  end
  L2_2 = Config
  L2_2 = L2_2.Canteen
  L2_2 = L2_2.FreeFoodPackageItems
  if L2_2 then
    L2_2 = Logs
    L2_2 = L2_2.FreePackageCanteen
    L3_2 = A0_2
    L2_2(L3_2)
    L2_2 = L1_2.registerSession
    L3_2 = A0_2
    L2_2(L3_2)
    L2_2 = pcall
    function L3_2()
      local L0_3, L1_3, L2_3
      L0_3 = Inventory
      L0_3 = L0_3.addMultipleItems
      L1_3 = A0_2
      L2_3 = Config
      L2_3 = L2_3.Canteen
      L2_3 = L2_3.FreeFoodPackageItems
      return L0_3(L1_3, L2_3)
    end
    L2_2, L3_2 = L2_2(L3_2)
    L4_2 = Framework
    L4_2 = L4_2.sendNotification
    L5_2 = A0_2
    L6_2 = _U
    L7_2 = "CANTEEN.FREE_FOOD_PACKAGE_RECEIVED_SUCCESS"
    L6_2 = L6_2(L7_2)
    L7_2 = "success"
    L4_2(L5_2, L6_2, L7_2)
  end
end
L0_1.GetFreeFoodPackage = L1_1
L0_1 = CanteenService
function L1_1(A0_2)
  local L1_2
end
L0_1.ShowOffer = L1_1
