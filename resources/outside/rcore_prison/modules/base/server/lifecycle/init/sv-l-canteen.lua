local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:requestCanteenTransaction"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2
  if A1_2 then
    L3_2 = PrisonService
    L3_2 = L3_2.getPlayer
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      L3_2 = Framework
      L3_2 = L3_2.sendNotification
      L4_2 = A0_2
      L5_2 = _U
      L6_2 = "GENERAL.YOU_ARE_NOT_PRISONER"
      L5_2 = L5_2(L6_2)
      L6_2 = "error"
      L3_2(L4_2, L5_2, L6_2)
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "Canteen: Requested transaction failed, since player: %s (%s) is not prisoner."
      L5_2 = A0_2
      L6_2 = GetPlayerName
      L7_2 = A0_2
      L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2 = L6_2(L7_2)
      return L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2)
    end
    L3_2 = A2_2.shopType
    L4_2 = A2_2.items
    if "free" == L3_2 then
      L5_2 = CanteenService
      L5_2 = L5_2.GetFreeFoodPackage
      L6_2 = A0_2
      L5_2(L6_2)
    elseif "paid" == L3_2 then
      L5_2 = PrisonAccountService
      L5_2 = L5_2.getPlayer
      L6_2 = A0_2
      L5_2 = L5_2(L6_2)
      if not L5_2 then
        L6_2 = Framework
        L6_2 = L6_2.sendNotification
        L7_2 = A0_2
        L8_2 = _U
        L9_2 = "GENERAL.YOU_DONT_HAVE_PRISONER_ACCOUNT"
        L8_2 = L8_2(L9_2)
        L9_2 = "error"
        L6_2(L7_2, L8_2, L9_2)
        L6_2 = dbg
        L6_2 = L6_2.debug
        L7_2 = "Canteen: Requested transaction failed, since player: %s (%s) does not have a prison account."
        L8_2 = A0_2
        L9_2 = GetPlayerName
        L10_2 = A0_2
        L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2 = L9_2(L10_2)
        return L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2)
      end
      L6_2 = L4_2.id
      L7_2 = L4_2.amount
      if L7_2 <= 0 then
        L8_2 = Framework
        L8_2 = L8_2.sendNotification
        L9_2 = A0_2
        L10_2 = _U
        L11_2 = "GENERAL.INVALID_ITEM_AMOUNT"
        L10_2 = L10_2(L11_2)
        L11_2 = "error"
        L8_2(L9_2, L10_2, L11_2)
        L8_2 = dbg
        L8_2 = L8_2.debug
        L9_2 = "Canteen: Requested transaction failed, since player: %s (%s) has invalid item amount."
        L10_2 = A0_2
        L11_2 = GetPlayerName
        L12_2 = A0_2
        L11_2, L12_2, L13_2, L14_2, L15_2, L16_2 = L11_2(L12_2)
        return L8_2(L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2)
      end
      L8_2 = Config
      L8_2 = L8_2.Canteen
      L8_2 = L8_2.CreditItems
      L8_2 = L8_2[L6_2]
      L9_2 = L8_2.price
      L9_2 = L9_2 * L7_2
      L10_2 = Inventory
      L10_2 = L10_2.DoesItemExist
      L11_2 = L8_2.name
      L12_2 = A0_2
      L10_2 = L10_2(L11_2, L12_2)
      if not L10_2 then
        L10_2 = Framework
        L10_2 = L10_2.sendNotification
        L11_2 = A0_2
        L12_2 = _U
        L13_2 = "GENERAL.ITEM_NOT_FOUND"
        L14_2 = L8_2.name
        L12_2 = L12_2(L13_2, L14_2)
        L13_2 = "error"
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = dbg
        L10_2 = L10_2.debug
        L11_2 = "Canteen: Requested transaction failed, since player requested: %s (%s) item doesnt exist %s."
        L12_2 = A0_2
        L13_2 = GetPlayerName
        L14_2 = A0_2
        L13_2 = L13_2(L14_2)
        L14_2 = L8_2.name
        return L10_2(L11_2, L12_2, L13_2, L14_2)
      end
      L10_2 = L5_2.balance
      if L9_2 <= L10_2 then
        L10_2 = L5_2.balance
        L10_2 = L10_2 - L9_2
        L5_2.balance = L10_2
        L10_2 = Inventory
        L10_2 = L10_2.addItem
        L11_2 = A0_2
        L12_2 = L8_2.name
        L13_2 = L7_2
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = Logs
        L10_2 = L10_2.BuyItemCanteen
        L11_2 = A0_2
        L12_2 = L8_2
        L13_2 = L7_2
        L14_2 = L9_2
        L10_2(L11_2, L12_2, L13_2, L14_2)
        L10_2 = dbg
        L10_2 = L10_2.debug
        L11_2 = "Canteen: Requested transaction for player: %s (%s) with item: %s, amount: %s, price: %s."
        L12_2 = A0_2
        L13_2 = GetPlayerName
        L14_2 = A0_2
        L13_2 = L13_2(L14_2)
        L14_2 = L8_2.name
        L15_2 = L7_2
        L16_2 = L9_2
        L10_2(L11_2, L12_2, L13_2, L14_2, L15_2, L16_2)
        L10_2 = Framework
        L10_2 = L10_2.sendNotification
        L11_2 = A0_2
        L12_2 = _U
        L13_2 = "CANTEEN.BOUGHT_ITEM"
        L14_2 = L8_2.name
        L15_2 = L9_2
        L12_2 = L12_2(L13_2, L14_2, L15_2)
        L13_2 = "success"
        L10_2(L11_2, L12_2, L13_2)
        L10_2 = AccountLogService
        L10_2 = L10_2.RegisterTransaction
        L11_2 = _U
        L12_2 = "CANTEEN.TITLE"
        L11_2 = L11_2(L12_2)
        L12_2 = _U
        L13_2 = "CANTEEN.BOUGHT_ITEM"
        L14_2 = L8_2.name
        L15_2 = L9_2
        L12_2 = L12_2(L13_2, L14_2, L15_2)
        L13_2 = Framework
        L13_2 = L13_2.getIdentifier
        L14_2 = A0_2
        L13_2 = L13_2(L14_2)
        L14_2 = -L9_2
        L10_2(L11_2, L12_2, L13_2, L14_2)
        L10_2 = StartClient
        L11_2 = A0_2
        L12_2 = "UpdatePrisonerAccount"
        L13_2 = L5_2
        L10_2(L11_2, L12_2, L13_2)
      else
        L10_2 = Framework
        L10_2 = L10_2.sendNotification
        L11_2 = A0_2
        L12_2 = _U
        L13_2 = "CANTEEN.NOT_ENOUGH_CREDITS"
        L14_2 = L8_2.price
        L12_2 = L12_2(L13_2, L14_2)
        L13_2 = "error"
        L10_2(L11_2, L12_2, L13_2)
      end
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
