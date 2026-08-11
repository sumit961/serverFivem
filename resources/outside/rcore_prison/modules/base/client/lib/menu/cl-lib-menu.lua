local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1
L0_1 = {}
L1_1 = {}
L2_1 = {}
L3_1 = {}
L4_1 = {}
function L5_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L2_2 = dbg
    L2_2 = L2_2.menu
    L3_2 = "Menu with id "
    L4_2 = A0_2 or L4_2
    if not A0_2 then
      L4_2 = "undefined"
    end
    L5_2 = " not registered."
    L3_2 = L3_2 .. L4_2 .. L5_2
    L2_2(L3_2)
    L2_2 = false
    return L2_2
  end
  L2_2 = true
  return L2_2
end
IsMenuRegistered = L5_1
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = A0_2
  L3_2 = "_"
  L4_2 = A1_2
  L2_2 = L2_2 .. L3_2 .. L4_2
  return L2_2
end
GetCachedFunctionKey = L5_1
function L5_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = {}
  L2_2 = "top-left"
  L3_2 = "top-right"
  L4_2 = "bottom-left"
  L5_2 = "bottom-right"
  L1_2[1] = L2_2
  L1_2[2] = L3_2
  L1_2[3] = L4_2
  L1_2[4] = L5_2
  L2_2 = pairs
  L3_2 = L1_2
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    if L7_2 == A0_2 then
      return A0_2
    end
  end
  L2_2 = dbg
  L2_2 = L2_2.menu
  L3_2 = "Invalid menu position %s, defaulting to %s"
  L4_2 = A0_2
  L5_2 = L1_2[1]
  L2_2(L3_2, L4_2, L5_2)
  L2_2 = L1_2[1]
  return L2_2
end
GetValidPosition = L5_1
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L2_2 = dbg
    L2_2 = L2_2.menu
    L3_2 = "Menu with id %s already registered."
    L4_2 = A0_2
    L2_2(L3_2, L4_2)
    return
  end
  if not A0_2 then
    L2_2 = dbg
    L2_2 = L2_2.menu
    L3_2 = "Menu id not provided."
    L2_2(L3_2)
    return
  end
  L2_2 = L0_1
  L3_2 = {}
  L3_2.id = A0_2
  L4_2 = A1_2.header
  if not L4_2 then
    L4_2 = ""
  end
  L3_2.header = L4_2
  L4_2 = A1_2.headerTextColor
  if not L4_2 then
    L4_2 = "#000"
  end
  L3_2.headerTextColor = L4_2
  L4_2 = A1_2.headerImg
  if not L4_2 then
    L4_2 = nil
  end
  L3_2.headerImg = L4_2
  L4_2 = A1_2.title
  if not L4_2 then
    L4_2 = ""
  end
  L3_2.title = L4_2
  L4_2 = A1_2.accentColor
  if not L4_2 then
    L4_2 = "#f2b440"
  end
  L3_2.accentColor = L4_2
  L4_2 = A1_2.maxRowsInView
  if not L4_2 then
    L4_2 = 5
  end
  L3_2.maxRowsInView = L4_2
  L4_2 = A1_2.loadingLabel
  if not L4_2 then
    L4_2 = "Loading, please wait..."
  end
  L3_2.loadingLabel = L4_2
  L4_2 = A1_2.rows
  if not L4_2 then
    L4_2 = {}
  end
  L3_2.rows = L4_2
  L4_2 = GetValidPosition
  L5_2 = A1_2.position
  L4_2 = L4_2(L5_2)
  L3_2.position = L4_2
  L2_2[A0_2] = L3_2
  L2_2 = A1_2.goBack
  if L2_2 then
    L2_2 = L3_1
    L3_2 = A1_2.goBack
    L2_2[A0_2] = L3_2
  end
  L2_2 = pairs
  L3_2 = A1_2.rows
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = L7_2.onChange
    if L8_2 then
      L8_2 = type
      L9_2 = L7_2.onChange
      L8_2 = L8_2(L9_2)
      if "function" == L8_2 then
        L8_2 = GetCachedFunctionKey
        L9_2 = A0_2
        L10_2 = L7_2.id
        L8_2 = L8_2(L9_2, L10_2)
        L9_2 = L1_1
        L10_2 = L7_2.onChange
        L9_2[L8_2] = L10_2
        L7_2.onChange = nil
      end
    end
    L8_2 = L7_2.onClick
    if L8_2 then
      L8_2 = type
      L9_2 = L7_2.onClick
      L8_2 = L8_2(L9_2)
      if "function" == L8_2 then
        L8_2 = GetCachedFunctionKey
        L9_2 = A0_2
        L10_2 = L7_2.id
        L8_2 = L8_2(L9_2, L10_2)
        L9_2 = L2_1
        L10_2 = L7_2.onClick
        L9_2[L8_2] = L10_2
        L7_2.onClick = nil
      end
    end
    L8_2 = L7_2.onFocus
    if L8_2 then
      L8_2 = type
      L9_2 = L7_2.onFocus
      L8_2 = L8_2(L9_2)
      if "function" == L8_2 then
        L8_2 = GetCachedFunctionKey
        L9_2 = A0_2
        L10_2 = L7_2.id
        L8_2 = L8_2(L9_2, L10_2)
        L9_2 = L4_1
        L10_2 = L7_2.onFocus
        L9_2[L8_2] = L10_2
        L7_2.onFocus = nil
      end
    end
  end
  L2_2 = FrontendService
  L2_2 = L2_2.SendReactMessage
  L3_2 = "reactMenuRegister"
  L4_2 = L0_1
  L4_2 = L4_2[A0_2]
  L2_2(L3_2, L4_2)
end
RegisterMenu = L5_1
function L5_1(A0_2)
  local L1_2, L2_2
  L1_2 = IsMenuRegistered
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.rows
  return L1_2
end
GetMenuData = L5_1
function L5_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = IsMenuRegistered
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L1_2 = dbg
  L1_2 = L1_2.menu
  L2_2 = "Destroying menu with id %s"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
  isBossMenuOpened = false
  IsMenuOpened = false
  L1_2 = SetNuiFocus
  L2_2 = false
  L3_2 = false
  L1_2(L2_2, L3_2)
  L1_2 = HideMenu
  L2_2 = A0_2
  L1_2(L2_2)
  L1_2 = L0_1
  L1_2[A0_2] = nil
  L1_2 = FrontendService
  L1_2 = L1_2.SendReactMessage
  L2_2 = "reactMenuDestroy"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
  L1_2 = ClearCachedFunctionsForMenu
  L2_2 = A0_2
  L1_2(L2_2)
end
DestroyMenu = L5_1
function L5_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L0_2 = L0_1
  if L0_2 then
    L0_2 = pairs
    L1_2 = L0_1
    L0_2, L1_2, L2_2, L3_2 = L0_2(L1_2)
    for L4_2, L5_2 in L0_2, L1_2, L2_2, L3_2 do
      L6_2 = DestroyMenu
      L7_2 = L4_2
      L6_2(L7_2)
    end
  end
end
DestroyAllMenus = L5_1
function L5_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = dbg
  L1_2 = L1_2.menu
  L2_2 = "Showing menu with id %s"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
  L1_2 = IsMenuRegistered
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L1_2 = dbg
    L1_2 = L1_2.menu
    L2_2 = "%s"
    L3_2 = A0_2
    return L1_2(L2_2, L3_2)
  end
  L1_2 = SetNuiFocus
  L2_2 = true
  L3_2 = false
  L1_2(L2_2, L3_2)
  L1_2 = FrontendService
  L1_2 = L1_2.SendReactMessage
  L2_2 = "loadApp"
  L3_2 = {}
  L4_2 = Screens
  L4_2 = L4_2.MENU
  L3_2.screen = L4_2
  L3_2.visible = true
  L1_2(L2_2, L3_2)
  L1_2 = FrontendService
  L1_2 = L1_2.SendReactMessage
  L2_2 = "reactMenuSetOpenState"
  L3_2 = {}
  L3_2.id = A0_2
  L3_2.isOpened = true
  L1_2(L2_2, L3_2)
  L1_2 = dbg
  L1_2 = L1_2.menu
  L2_2 = "Menu with ID [%s] is opened"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
  IsMenuOpened = true
  HasActiveMenu = true
end
ShowMenu = L5_1
function L5_1()
  local L0_2, L1_2
  L0_2 = CreateThread
  function L1_2()
    local L0_3, L1_3, L2_3, L3_3
    while true do
      L0_3 = IsMenuOpened
      if not L0_3 then
        break
      end
      L0_3 = Wait
      L1_3 = 0
      L0_3(L1_3)
      L0_3 = HudForceWeaponWheel
      L1_3 = false
      L0_3(L1_3)
      L0_3 = HudWeaponWheelIgnoreSelection
      L0_3()
      L0_3 = DisableControlAction
      L1_3 = 0
      L2_3 = 37
      L3_3 = true
      L0_3(L1_3, L2_3, L3_3)
    end
  end
  L0_2(L1_2)
end
disableWeaponWheel = L5_1
function L5_1()
  local L0_2, L1_2
  L0_2 = CreateThread
  function L1_2()
    local L0_3, L1_3, L2_3
    while true do
      L0_3 = IsMenuOpened
      if not L0_3 then
        break
      end
      L0_3 = Wait
      L1_3 = 0
      L0_3(L1_3)
      L0_3 = DisablePlayerFiring
      L1_3 = PlayerPedId
      L1_3 = L1_3()
      L2_3 = true
      L0_3(L1_3, L2_3)
    end
  end
  L0_2(L1_2)
end
disableFiring = L5_1
function L5_1()
  local L0_2, L1_2
  L0_2 = disableFiring
  L0_2()
  L0_2 = disableWeaponWheel
  L0_2()
end
DisableCombat = L5_1
function L5_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = dbg
  L1_2 = L1_2.menu
  L2_2 = "Hiding menu with id %s"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
  L1_2 = IsMenuRegistered
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L1_2 = SetNuiFocus
  L2_2 = false
  L3_2 = false
  L1_2(L2_2, L3_2)
  L1_2 = HelpKeys
  L1_2 = L1_2.Hide
  L1_2()
  L1_2 = SH
  L1_2 = L1_2.zoneId
  if L1_2 then
    L1_2 = Config
    L1_2 = L1_2.Target
    if "NONE" == L1_2 then
      L1_2 = HelpKeys
      L1_2 = L1_2.ShowZoneInteractionKeys
      L1_2()
    end
  end
  L1_2 = FrontendService
  L1_2 = L1_2.SendReactMessage
  L2_2 = "reactMenuSetOpenState"
  L3_2 = {}
  L3_2.id = A0_2
  L3_2.isOpened = false
  L1_2(L2_2, L3_2)
  HasActiveMenu = false
end
HideMenu = L5_1
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = GetCachedFunctionKey
  L3_2 = A0_2
  L4_2 = A1_2
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = L1_1
  L2_2 = L3_2[L2_2]
  if L2_2 then
    L3_2 = L2_2
    L3_2()
  end
end
function L6_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = GetCachedFunctionKey
  L3_2 = A0_2
  L4_2 = A1_2
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = L2_1
  L2_2 = L3_2[L2_2]
  if L2_2 then
    L3_2 = L2_2
    L3_2()
  end
end
function L7_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = GetCachedFunctionKey
  L3_2 = A0_2
  L4_2 = A1_2
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = L4_1
  L2_2 = L3_2[L2_2]
  if L2_2 then
    L3_2 = L2_2
    L3_2()
  end
end
function L8_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2
  L3_2 = IsMenuRegistered
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    return
  end
  L3_2 = A2_2.valueName
  L3_2 = A1_2[L3_2]
  L4_2 = A2_2.valueName
  if "isChecked" == L4_2 then
    L4_2 = A2_2.prevValue
    L4_2 = L3_2 ~= L4_2
    return L4_2
  end
  L4_2 = A2_2.valueName
  if "value" == L4_2 then
    L4_2 = A2_2.prevValue
    L4_2 = L3_2 ~= L4_2
    return L4_2
  end
  L4_2 = A2_2.valueName
  if "selectedOption" == L4_2 then
    L4_2 = json
    L4_2 = L4_2.encode
    L5_2 = A2_2.prevValue
    L4_2 = L4_2(L5_2)
    L5_2 = json
    L5_2 = L5_2.encode
    L6_2 = L3_2
    L5_2 = L5_2(L6_2)
    L6_2 = L4_2 ~= L5_2
    return L6_2
  end
end
ShouldExecuteOnChange = L8_1
function L8_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2
  L4_2 = dbg
  L4_2 = L4_2.menu
  L5_2 = "Sending menu update for menu %s, row %s"
  L6_2 = A0_2
  L7_2 = A1_2
  L4_2(L5_2, L6_2, L7_2)
  L4_2 = IsMenuRegistered
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    return
  end
  L4_2 = FrontendService
  L4_2 = L4_2.SendReactMessage
  L5_2 = "reactMenuUpdateData"
  L6_2 = {}
  L6_2.id = A0_2
  L6_2.rowKey = A1_2
  L6_2.updatedRow = A2_2
  L4_2(L5_2, L6_2)
  L4_2 = ShouldExecuteOnChange
  L5_2 = A0_2
  L6_2 = A2_2
  L7_2 = A3_2
  L4_2 = L4_2(L5_2, L6_2, L7_2)
  if L4_2 then
    L4_2 = L5_1
    L5_2 = A0_2
    L6_2 = A1_2
    L4_2(L5_2, L6_2)
  end
end
SendMenuUpdate = L8_1
function L8_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = FrontendService
  L2_2 = L2_2.SendReactMessage
  L3_2 = "reactMenuSetLoading"
  L4_2 = {}
  L4_2.id = A0_2
  L4_2.isLoading = A1_2
  L2_2(L3_2, L4_2)
end
SetMenuLoading = L8_1
function L8_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  L3_2 = SetMenuRowValue
  L4_2 = A0_2
  L5_2 = A1_2
  L6_2 = "isLoading"
  L7_2 = A2_2
  L3_2(L4_2, L5_2, L6_2, L7_2)
end
SetRowLoading = L8_1
function L8_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = IsMenuRegistered
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  L2_2 = pairs
  L3_2 = L0_1
  L3_2 = L3_2[A0_2]
  L3_2 = L3_2.rows
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = L7_2.id
    if L8_2 == A1_2 then
      return L6_2
    end
  end
end
GetRowIndexById = L8_1
function L8_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L4_2 = dbg
  L4_2 = L4_2.menu
  L5_2 = "Setting menu row value for menu %s, row %s, value %s"
  L6_2 = A0_2
  L7_2 = A1_2
  L8_2 = A2_2
  L4_2(L5_2, L6_2, L7_2, L8_2)
  L4_2 = IsMenuRegistered
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    return
  end
  L4_2 = Wait
  L5_2 = 0
  L4_2(L5_2)
  L4_2 = L0_1
  L4_2 = L4_2[A0_2]
  if L4_2 then
    L4_2 = L4_2.rows
  end
  L5_2 = GetRowIndexById
  L6_2 = A0_2
  L7_2 = A1_2
  L5_2 = L5_2(L6_2, L7_2)
  L4_2 = L4_2[L5_2]
  if L4_2 then
    L4_2 = L4_2[A2_2]
  end
  L5_2 = L0_1
  L5_2 = L5_2[A0_2]
  L5_2 = L5_2.rows
  L6_2 = GetRowIndexById
  L7_2 = A0_2
  L8_2 = A1_2
  L6_2 = L6_2(L7_2, L8_2)
  L5_2 = L5_2[L6_2]
  L5_2[A2_2] = A3_2
  L5_2 = SendMenuUpdate
  L6_2 = A0_2
  L7_2 = A1_2
  L8_2 = GetMenuRow
  L9_2 = A0_2
  L10_2 = A1_2
  L8_2 = L8_2(L9_2, L10_2)
  L9_2 = {}
  L9_2.valueName = A2_2
  L9_2.prevValue = L4_2
  L5_2(L6_2, L7_2, L8_2, L9_2)
end
SetMenuRowValue = L8_1
function L8_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = IsMenuRegistered
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  L2_2 = GetRowIndexById
  L3_2 = A0_2
  L4_2 = A1_2
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = L0_1
  L3_2 = L3_2[A0_2]
  if L3_2 then
    L3_2 = L3_2.rows
  end
  if L3_2 then
    L3_2 = L3_2[L2_2]
  end
  return L3_2
end
GetMenuRow = L8_1
function L8_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2
  L3_2 = IsMenuRegistered
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    return
  end
  L3_2 = GetMenuRow
  L4_2 = A0_2
  L5_2 = A1_2
  L3_2 = L3_2(L4_2, L5_2)
  if L3_2 then
    L3_2 = L3_2[A2_2]
  end
  return L3_2
end
GetMenuRowValue = L8_1
function L8_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = pairs
  L2_2 = L1_1
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = string
    L7_2 = L7_2.find
    L8_2 = L5_2
    L9_2 = A0_2
    L7_2 = L7_2(L8_2, L9_2)
    if L7_2 then
      L7_2 = L1_1
      L7_2[L5_2] = nil
    end
  end
  L1_2 = pairs
  L2_2 = L2_1
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = string
    L7_2 = L7_2.find
    L8_2 = L5_2
    L9_2 = A0_2
    L7_2 = L7_2(L8_2, L9_2)
    if L7_2 then
      L7_2 = L2_1
      L7_2[L5_2] = nil
    end
  end
  L1_2 = pairs
  L2_2 = L3_1
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = string
    L7_2 = L7_2.find
    L8_2 = L5_2
    L9_2 = A0_2
    L7_2 = L7_2(L8_2, L9_2)
    if L7_2 then
      L7_2 = L3_1
      L7_2[L5_2] = nil
    end
  end
  L1_2 = pairs
  L2_2 = L4_1
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = string
    L7_2 = L7_2.find
    L8_2 = L5_2
    L9_2 = A0_2
    L7_2 = L7_2(L8_2, L9_2)
    if L7_2 then
      L7_2 = L4_1
      L7_2[L5_2] = nil
    end
  end
end
ClearCachedFunctionsForMenu = L8_1
function L8_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L4_2 = dbg
  L4_2 = L4_2.menu
  L5_2 = "Updating menu data for menu %s, row %s, value %s, type %s"
  L6_2 = A0_2
  L7_2 = A1_2
  L8_2 = A2_2
  L9_2 = A3_2
  L4_2(L5_2, L6_2, L7_2, L8_2, L9_2)
  L4_2 = IsMenuRegistered
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    return
  end
  L4_2 = false
  if "checkbox" == A3_2 then
    L5_2 = SetMenuRowValue
    L6_2 = A0_2
    L7_2 = A1_2
    L8_2 = "isChecked"
    L9_2 = A2_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
    L4_2 = true
  elseif "select" == A3_2 then
    L5_2 = SetMenuRowValue
    L6_2 = A0_2
    L7_2 = A1_2
    L8_2 = "selectedOption"
    L9_2 = A2_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
    L4_2 = true
  elseif "input" == A3_2 then
    L5_2 = SetMenuRowValue
    L6_2 = A0_2
    L7_2 = A1_2
    L8_2 = "value"
    L9_2 = A2_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
    L4_2 = true
  end
  if not L4_2 then
    L5_2 = dbg
    L5_2 = L5_2.menu
    L6_2 = "error"
    L7_2 = "Menu data not updated, invalid type %s"
    L8_2 = A3_2
    L5_2(L6_2, L7_2, L8_2)
  end
end
UpdateMenuData = L8_1
function L8_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = IsMenuRegistered
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L1_2 = L3_1
  L1_2 = L1_2[A0_2]
  if L1_2 then
    L2_2 = type
    L3_2 = L1_2
    L2_2 = L2_2(L3_2)
    if "function" == L2_2 then
      L2_2 = L1_2
      L2_2()
      L2_2 = true
      return L2_2
    end
  end
  L2_2 = false
  return L2_2
end
GoBackInMenu = L8_1
L8_1 = RegisterNuiCallback
L9_1 = "handleMenuCheckboxChange"
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = A1_2
  L3_2 = {}
  L2_2(L3_2)
  L2_2 = UpdateMenuData
  L3_2 = A0_2.menuId
  L4_2 = A0_2.key
  L5_2 = A0_2.value
  L6_2 = "checkbox"
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
L8_1(L9_1, L10_1)
L8_1 = RegisterNuiCallback
L9_1 = "handleMenuSelectChange"
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = A1_2
  L3_2 = {}
  L2_2(L3_2)
  L2_2 = UpdateMenuData
  L3_2 = A0_2.menuId
  L4_2 = A0_2.key
  L5_2 = A0_2.value
  L6_2 = "select"
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
L8_1(L9_1, L10_1)
L8_1 = RegisterNuiCallback
L9_1 = "handleMenuInputChange"
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = A1_2
  L3_2 = {}
  L2_2(L3_2)
  L2_2 = UpdateMenuData
  L3_2 = A0_2.menuId
  L4_2 = A0_2.key
  L5_2 = A0_2.value
  L6_2 = "input"
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
L8_1(L9_1, L10_1)
L8_1 = RegisterNuiCallback
L9_1 = "handleMenuButtonClick"
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = A1_2
  L3_2 = {}
  L2_2(L3_2)
  L2_2 = L6_1
  L3_2 = A0_2.menuId
  L4_2 = A0_2.key
  L2_2(L3_2, L4_2)
end
L8_1(L9_1, L10_1)
L8_1 = RegisterNuiCallback
L9_1 = "handleCloseMenu"
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = A1_2
  L3_2 = {}
  L2_2(L3_2)
  L2_2 = HideMenu
  L3_2 = A0_2.menuId
  L2_2(L3_2)
  L2_2 = TriggerLocalClientEvent
  L3_2 = "onHud"
  L4_2 = true
  L5_2 = "SHOW_HUD"
  L6_2 = "CLOSE_MENU_MENU"
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
L8_1(L9_1, L10_1)
L8_1 = RegisterNuiCallback
L9_1 = "handleMenuRowFocus"
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = A1_2
  L3_2 = {}
  L2_2(L3_2)
  L2_2 = SH
  L2_2 = L2_2.screen
  L3_2 = Screens
  L3_2 = L3_2.MENU
  if L2_2 ~= L3_2 then
    return
  end
  L2_2 = dbg
  L2_2 = L2_2.menu
  L3_2 = "Menu row focus for menu %s, row %s"
  L4_2 = A0_2.menuId
  L5_2 = A0_2.key
  L2_2(L3_2, L4_2, L5_2)
  L2_2 = L7_1
  L3_2 = A0_2.menuId
  L4_2 = A0_2.key
  L2_2(L3_2, L4_2)
end
L8_1(L9_1, L10_1)
L8_1 = RegisterNuiCallback
L9_1 = "handleMenuGoBack"
function L10_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = A1_2
  L3_2 = {}
  L2_2(L3_2)
  L2_2 = GoBackInMenu
  L3_2 = A0_2.menuId
  L2_2(L3_2)
end
L8_1(L9_1, L10_1)
