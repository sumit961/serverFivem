local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:requestBuyDealerItem"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  if A1_2 then
    L4_2 = PrisonService
    L4_2 = L4_2.getPlayer
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    if not L4_2 then
      L4_2 = Framework
      L4_2 = L4_2.sendNotification
      L5_2 = A0_2
      L6_2 = _U
      L7_2 = "GENERAL.YOU_ARE_NOT_PRISONER"
      L6_2 = L6_2(L7_2)
      L7_2 = "error"
      L4_2(L5_2, L6_2, L7_2)
      L4_2 = dbg
      L4_2 = L4_2.debug
      L5_2 = "Trade: Requested transaction failed, since player: %s (%s) is not prisoner."
      L6_2 = A0_2
      L7_2 = GetPlayerName
      L8_2 = A0_2
      L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2 = L7_2(L8_2)
      return L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
    end
    L4_2 = A2_2.id
    L5_2 = A2_2.amount
    if L5_2 <= 0 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "GENERAL.INVALID_ITEM_AMOUNT"
      L8_2 = L8_2(L9_2)
      L9_2 = "error"
      L6_2(L7_2, L8_2, L9_2)
      L6_2 = dbg
      L6_2 = L6_2.debug
      L7_2 = "Trade: Requested transaction failed, since player: %s (%s) has invalid item amount."
      L8_2 = A0_2
      L9_2 = GetPlayerName
      L10_2 = A0_2
      L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2 = L9_2(L10_2)
      return L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
    end
    L6_2 = SH
    L6_2 = L6_2.data
    L6_2 = L6_2.interaction
    L6_2 = L6_2[A3_2]
    L6_2 = L6_2.items
    L6_2 = L6_2[L4_2]
    if not L6_2 then
      return
    end
    if L6_2 then
      L7_2 = L6_2.name
      if L7_2 then
        L7_2 = Inventory
        L7_2 = L7_2.DoesItemExist
        L8_2 = L6_2.name
        L9_2 = A0_2
        L7_2 = L7_2(L8_2, L9_2)
        if not L7_2 then
          L7_2 = Framework
          L7_2 = L7_2.sendNotification
          L8_2 = A0_2
          L9_2 = _U
          L10_2 = "DEALER.NO_ECONOMY_ITEM"
          L9_2 = L9_2(L10_2)
          L10_2 = "error"
          L7_2(L8_2, L9_2, L10_2)
          L7_2 = dbg
          L7_2 = L7_2.debug
          L8_2 = "Trade: Requested transaction failed, for player named %s (%s) | this item is not defined: [%s]!"
          L9_2 = A0_2
          L10_2 = GetPlayerName
          L11_2 = A0_2
          L10_2 = L10_2(L11_2)
          L11_2 = L6_2.name
          return L7_2(L8_2, L9_2, L10_2, L11_2)
        end
      end
    end
    L7_2 = L6_2.price
    L7_2 = L7_2 * L5_2
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "Trade: Checking if player has %s amount of %s in his inventory | %s %s"
    L10_2 = L7_2
    L11_2 = Config
    L11_2 = L11_2.EconomyItem
    L12_2 = A0_2
    L13_2 = GetPlayerName
    L14_2 = A0_2
    L13_2, L14_2, L15_2 = L13_2(L14_2)
    L8_2(L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
    L8_2 = Inventory
    L8_2 = L8_2.hasItem
    L9_2 = A0_2
    L10_2 = Config
    L10_2 = L10_2.EconomyItem
    L11_2 = L7_2
    L8_2 = L8_2(L9_2, L10_2, L11_2)
    if L8_2 then
      L8_2 = dbg
      L8_2 = L8_2.debug
      L9_2 = "Trade: Requested transaction proceed since player has %s amount of %s in his inventory | %s %s"
      L10_2 = L7_2
      L11_2 = Config
      L11_2 = L11_2.EconomyItem
      L12_2 = A0_2
      L13_2 = GetPlayerName
      L14_2 = A0_2
      L13_2, L14_2, L15_2 = L13_2(L14_2)
      L8_2(L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
      L8_2 = Inventory
      L8_2 = L8_2.removeItem
      L9_2 = A0_2
      L10_2 = Config
      L10_2 = L10_2.EconomyItem
      L11_2 = L7_2
      L8_2(L9_2, L10_2, L11_2)
      L8_2 = Inventory
      L8_2 = L8_2.addItem
      L9_2 = A0_2
      L10_2 = L6_2.name
      L11_2 = L5_2
      L8_2(L9_2, L10_2, L11_2)
      L8_2 = Framework
      L8_2 = L8_2.sendNotification
      L9_2 = A0_2
      L10_2 = _U
      L11_2 = "DEALER.BOUGHT_ITEM"
      L12_2 = L6_2.label
      if not L12_2 then
        L12_2 = L6_2.name
      end
      L13_2 = L5_2
      L14_2 = L7_2
      L15_2 = Config
      L15_2 = L15_2.EconomyItem
      L10_2 = L10_2(L11_2, L12_2, L13_2, L14_2, L15_2)
      L11_2 = "success"
      L8_2(L9_2, L10_2, L11_2)
    else
      L8_2 = Framework
      L8_2 = L8_2.sendNotification
      L9_2 = A0_2
      L10_2 = _U
      L11_2 = "DEALER.NOT_ENOUGH_ITEM"
      L12_2 = L7_2
      L13_2 = Config
      L13_2 = L13_2.EconomyItem
      L10_2 = L10_2(L11_2, L12_2, L13_2)
      L11_2 = "error"
      L8_2(L9_2, L10_2, L11_2)
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
