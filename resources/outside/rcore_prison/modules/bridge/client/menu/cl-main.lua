local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = {}
L0_1.currentLabel = nil
L0_1.currentName = nil
L1_1 = Config
L1_1 = L1_1.Menus
L0_1.currentLibrary = L1_1
L1_1 = Config
L1_1 = L1_1.Menus
L0_1.useLibrary = L1_1
L1_1 = {}
L1_1.ox_lib = true
L1_1["qb-menu"] = true
L0_1.Libraries = L1_1
L1_1 = {}
L0_1.Menus = L1_1
Frontend = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L2_2 = A0_2
  L1_2 = A0_2.gsub
  L3_2 = "^%l"
  L4_2 = string
  L4_2 = L4_2.upper
  return L1_2(L2_2, L3_2, L4_2)
end
c = L0_1
L0_1 = Frontend
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2
  L3_2 = {}
  L4_2 = Config
  L4_2 = L4_2.Menus
  L5_2 = Menus
  L5_2 = L5_2.OX
  if L4_2 == L5_2 then
    L4_2 = Frontend
    L5_2 = L4_2
    L4_2 = L4_2.Ox
    L6_2 = A1_2
    L4_2 = L4_2(L5_2, L6_2)
    L3_2 = L4_2
  else
    L4_2 = Config
    L4_2 = L4_2.Menus
    L5_2 = Menus
    L5_2 = L5_2.ESX_MENU
    if L4_2 ~= L5_2 then
      L4_2 = Config
      L4_2 = L4_2.Menus
      L5_2 = Menus
      L5_2 = L5_2.ESX_CONTEXT
      if L4_2 ~= L5_2 then
        goto lbl_33
      end
    end
    L4_2 = Frontend
    L5_2 = L4_2
    L4_2 = L4_2.Esx
    L6_2 = A1_2
    L4_2 = L4_2(L5_2, L6_2)
    L3_2 = L4_2
    goto lbl_44
    ::lbl_33::
    L4_2 = Config
    L4_2 = L4_2.Menus
    L5_2 = Menus
    L5_2 = L5_2.RCORE
    if L4_2 == L5_2 then
      L4_2 = Frontend
      L5_2 = L4_2
      L4_2 = L4_2.Rcore
      L6_2 = A1_2
      L4_2 = L4_2(L5_2, L6_2)
      L3_2 = L4_2
    end
  end
  ::lbl_44::
  L4_2 = A2_2
  L5_2 = L3_2
  L4_2(L5_2)
end
L0_1.ParseData = L1_1
L0_1 = Frontend
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = Config
  L1_2 = L1_2.Menus
  L2_2 = Menus
  L2_2 = L2_2.QB
  if L1_2 == L2_2 then
    L1_2 = exports
    L1_2 = L1_2["qb-menu"]
    L2_2 = L1_2
    L1_2 = L1_2.closeMenu
    L1_2(L2_2)
    A0_2.currentName = nil
  else
    L1_2 = Config
    L1_2 = L1_2.Menus
    L2_2 = Menus
    L2_2 = L2_2.OX
    if L1_2 == L2_2 then
      L1_2 = lib
      if not L1_2 then
        L1_2 = dbg
        L1_2 = L1_2.debug
        L2_2 = "FE:CloseMenu - failed, ox_lib is not defined in fxmanifest.lua!"
        return L1_2(L2_2)
      end
      L1_2 = lib
      L1_2 = L1_2.hideContext
      L1_2()
      A0_2.currentName = nil
    else
      L1_2 = Config
      L1_2 = L1_2.Menus
      L2_2 = Menus
      L2_2 = L2_2.ESX_MENU
      if L1_2 == L2_2 then
        L1_2 = Framework
        if not L1_2 then
          L1_2 = dbg
          L1_2 = L1_2.debug
          L2_2 = "FE:CloseMenu - failed, es_extended is not detected!"
          return L1_2(L2_2)
        end
        L1_2 = Framework
        L1_2 = L1_2.UI
        L1_2 = L1_2.Menu
        L1_2 = L1_2.CloseAll
        L1_2()
      else
        L1_2 = Config
        L1_2 = L1_2.Menus
        L2_2 = Menus
        L2_2 = L2_2.ESX_CONTEXT
        if L1_2 == L2_2 then
          L1_2 = exports
          L1_2 = L1_2.esx_context
          L2_2 = L1_2
          L1_2 = L1_2.Close
          L1_2(L2_2)
          A0_2.currentName = nil
        else
          L1_2 = Config
          L1_2 = L1_2.Menus
          L2_2 = Menus
          L2_2 = L2_2.RCORE
          if L1_2 == L2_2 then
            A0_2.currentName = nil
          end
        end
      end
    end
  end
  L1_2 = TriggerLocalClientEvent
  L2_2 = "onHud"
  L3_2 = true
  L4_2 = "SHOW_HUD"
  L5_2 = "CLOSE_MENU"
  L1_2(L2_2, L3_2, L4_2, L5_2)
end
L0_1.CloseMenu = L1_1
L0_1 = {}
L1_1 = MENU_ID_LIST
L1_1 = L1_1.JOB_MENU
L2_1 = {}
L3_1 = GetImageByName
L4_1 = "yard"
L3_1 = L3_1(L4_1)
L2_1.headerImage = L3_1
L3_1 = _U
L4_1 = "MENU.JOB_TITLE"
L3_1 = L3_1(L4_1)
L2_1.title = L3_1
L0_1[L1_1] = L2_1
L1_1 = MENU_ID_LIST
L1_1 = L1_1.LOBBY_MENU
L2_1 = {}
L3_1 = GetImageByName
L4_1 = "gate"
L3_1 = L3_1(L4_1)
L2_1.headerImage = L3_1
L3_1 = _U
L4_1 = "MENU.LOBBY_TITLE"
L3_1 = L3_1(L4_1)
L2_1.title = L3_1
L0_1[L1_1] = L2_1
L1_1 = MENU_ID_LIST
L1_1 = L1_1.COMS_MENU
L2_1 = {}
L3_1 = GetImageByName
L4_1 = "coms"
L3_1 = L3_1(L4_1)
L2_1.headerImage = L3_1
L3_1 = _U
L4_1 = "COMS_MENU.TITLE"
L3_1 = L3_1(L4_1)
L2_1.title = L3_1
L0_1[L1_1] = L2_1
L1_1 = Frontend
function L2_1(A0_2, A1_2)
  local L2_2
  L2_2 = L0_1
  L2_2 = L2_2[A1_2]
  if not L2_2 then
    L2_2 = nil
  end
  return L2_2
end
L1_1.ObtainSettingForRcore = L2_1
L1_1 = Frontend
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L2_2 = Frontend
  L3_2 = L2_2
  L2_2 = L2_2.RemoveHeaderFromArray
  L4_2 = A1_2
  L2_2(L3_2, L4_2)
  L2_2 = promise
  L2_2 = L2_2.new
  L2_2 = L2_2()
  L3_2 = #A1_2
  L4_2 = {}
  L5_2 = {}
  L4_2.options = L5_2
  L5_2 = ipairs
  L6_2 = A1_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = {}
    L12_2 = L10_2.header
    L11_2.label = L12_2
    L12_2 = L10_2.header
    if L12_2 then
      L12_2 = L10_2.txt
      if L12_2 then
        L12_2 = L10_2.header
        L13_2 = L10_2.txt
        if L12_2 ~= L13_2 then
          L12_2 = L10_2.header
          L13_2 = " - "
          L14_2 = L10_2.txt
          L12_2 = L12_2 .. L13_2 .. L14_2
          L11_2.label = L12_2
      end
    end
    else
      L12_2 = L10_2.header
      L11_2.label = L12_2
    end
    L12_2 = L10_2.header
    if L12_2 then
      L12_2 = L10_2.txt
      if L12_2 then
        L12_2 = L10_2.header
        L13_2 = L10_2.txt
        if L12_2 ~= L13_2 then
          L12_2 = L10_2.header
          L13_2 = " - "
          L14_2 = L10_2.txt
          L12_2 = L12_2 .. L13_2 .. L14_2
          L11_2.title = L12_2
      end
    end
    else
      L12_2 = L10_2.header
      L11_2.title = L12_2
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      L12_2 = L12_2.event
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.isServer
        if not L12_2 then
          L12_2 = L10_2.params
          L12_2 = L12_2.event
          L11_2.event = L12_2
        end
      end
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      L12_2 = L12_2.isServer
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.event
        if L12_2 then
          L12_2 = L10_2.params
          L12_2 = L12_2.event
          L11_2.serverEvent = L12_2
          L12_2 = L10_2.params
          L12_2 = L12_2.args
          L11_2.args = L12_2
        end
      end
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.args
      end
      L11_2.args = L12_2
    end
    L12_2 = L10_2.disabled
    if L12_2 then
      L11_2.disabled = true
    end
    L12_2 = L10_2.params
    L12_2 = L12_2.isClient
    if L12_2 then
      function L12_2()
        local L0_3, L1_3, L2_3
        L0_3 = DestroyAllMenus
        L0_3()
        L0_3 = TriggerEvent
        L1_3 = L11_2.event
        L2_3 = L11_2.args
        L0_3(L1_3, L2_3)
      end
      L11_2.onClick = L12_2
    end
    L12_2 = L10_2.params
    L12_2 = L12_2.isServer
    if L12_2 then
      function L12_2()
        local L0_3, L1_3, L2_3
        L0_3 = DestroyAllMenus
        L0_3()
        L0_3 = TriggerServerEvent
        L1_3 = L11_2.serverEvent
        L2_3 = L11_2.args
        L0_3(L1_3, L2_3)
      end
      L11_2.onClick = L12_2
    end
    L12_2 = L4_2.options
    L12_2 = #L12_2
    L12_2 = L12_2 + 1
    L11_2.id = L12_2
    L11_2.type = "button"
    L12_2 = L10_2.description
    L11_2.description = L12_2
    L12_2 = L4_2.options
    L13_2 = L4_2.options
    L13_2 = #L13_2
    L13_2 = L13_2 + 1
    L12_2 = L12_2[L13_2]
    if not L12_2 then
      L12_2 = L4_2.options
      L13_2 = L4_2.options
      L13_2 = #L13_2
      L13_2 = L13_2 + 1
      L12_2[L13_2] = L11_2
    end
    L12_2 = L4_2.options
    L12_2 = #L12_2
    if L3_2 == L12_2 then
      L13_2 = L2_2
      L12_2 = L2_2.resolve
      L14_2 = true
      L12_2(L13_2, L14_2)
    end
  end
  L5_2 = Citizen
  L5_2 = L5_2.Await
  L6_2 = L2_2
  L5_2(L6_2)
  L5_2 = A0_2.currentName
  L6_2 = CreateThread
  function L7_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3
    L0_3 = IsMenuRegistered
    L1_3 = L5_2
    L0_3 = L0_3(L1_3)
    if not L0_3 then
      L0_3 = Frontend
      L1_3 = L0_3
      L0_3 = L0_3.ObtainSettingForRcore
      L2_3 = L5_2
      L0_3 = L0_3(L1_3, L2_3)
      L1_3 = {}
      L2_3 = L5_2
      L1_3.id = L2_3
      L1_3.header = ""
      L1_3.headerTextColor = "#fff"
      L2_3 = L0_3.headerImage
      if not L2_3 then
        L2_3 = nil
      end
      L1_3.headerImg = L2_3
      L2_3 = L0_3.title
      if not L2_3 then
        L2_3 = "Unk title"
      end
      L1_3.title = L2_3
      L1_3.accentColor = "#7ea5cc"
      L1_3.maxRowsInView = 6
      L2_3 = L0_3.title
      if not L2_3 then
        L2_3 = "Unk title"
      end
      L1_3.loadingLabel = L2_3
      L2_3 = Config
      L2_3 = L2_3.Menu
      L2_3 = L2_3.Position
      L1_3.position = L2_3
      function L2_3()
        local L0_4, L1_4, L2_4
        L0_4 = IsMenuRegistered
        L1_4 = L5_2
        L0_4 = L0_4(L1_4)
        if not L0_4 then
          return
        end
        L0_4 = dbg
        L0_4 = L0_4.menu
        L1_4 = "Closed menu with ID [%s]"
        L2_4 = L5_2
        L0_4(L1_4, L2_4)
      end
      L1_3.goBack = L2_3
      L2_3 = L4_2.options
      L1_3.rows = L2_3
      L2_3 = RegisterMenu
      L3_3 = L5_2
      L4_3 = L1_3
      L2_3(L3_3, L4_3)
    end
    L0_3 = HelpKeys
    L0_3 = L0_3.ShowNavigationKeysInMenu
    L0_3()
    L0_3 = ShowMenu
    L1_3 = L5_2
    L0_3(L1_3)
  end
  L8_2 = "cl-main code name: Alfa"
  L6_2(L7_2, L8_2)
end
L1_1.Rcore = L2_1
L1_1 = Frontend
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L2_2 = Frontend
  L3_2 = L2_2
  L2_2 = L2_2.RemoveHeaderFromArray
  L4_2 = A1_2
  L2_2(L3_2, L4_2)
  L2_2 = {}
  L3_2 = {}
  L2_2.options = L3_2
  L3_2 = promise
  L3_2 = L3_2.new
  L3_2 = L3_2()
  L4_2 = #A1_2
  L5_2 = ipairs
  L6_2 = A1_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = {}
    L12_2 = L10_2.header
    L11_2.label = L12_2
    L12_2 = L10_2.header
    if L12_2 then
      L12_2 = L10_2.txt
      if L12_2 then
        L12_2 = L10_2.header
        L13_2 = L10_2.txt
        if L12_2 ~= L13_2 then
          L12_2 = L10_2.header
          L13_2 = " - "
          L14_2 = L10_2.txt
          L12_2 = L12_2 .. L13_2 .. L14_2
          L11_2.label = L12_2
      end
    end
    else
      L12_2 = L10_2.header
      L11_2.label = L12_2
    end
    L12_2 = L10_2.header
    if L12_2 then
      L12_2 = L10_2.txt
      if L12_2 then
        L12_2 = L10_2.header
        L13_2 = L10_2.txt
        if L12_2 ~= L13_2 then
          L12_2 = L10_2.header
          L13_2 = " - "
          L14_2 = L10_2.txt
          L12_2 = L12_2 .. L13_2 .. L14_2
          L11_2.title = L12_2
      end
    end
    else
      L12_2 = L10_2.header
      L11_2.title = L12_2
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      L12_2 = L12_2.event
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.isServer
        if not L12_2 then
          L12_2 = L10_2.params
          L12_2 = L12_2.event
          L11_2.event = L12_2
        end
      end
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      L12_2 = L12_2.isServer
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.event
        if L12_2 then
          L12_2 = L10_2.params
          L12_2 = L12_2.event
          L11_2.serverEvent = L12_2
          L12_2 = L10_2.params
          L12_2 = L12_2.args
          L11_2.args = L12_2
        end
      end
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.args
      end
      L11_2.args = L12_2
    end
    L12_2 = L10_2.disabled
    if L12_2 then
      L11_2.disabled = true
    end
    L12_2 = L2_2.options
    L13_2 = L2_2.options
    L13_2 = #L13_2
    L13_2 = L13_2 + 1
    L12_2 = L12_2[L13_2]
    if not L12_2 then
      L12_2 = L2_2.options
      L13_2 = L2_2.options
      L13_2 = #L13_2
      L13_2 = L13_2 + 1
      L12_2[L13_2] = L11_2
    end
    L12_2 = L2_2.options
    L12_2 = #L12_2
    if L4_2 == L12_2 then
      L13_2 = L3_2
      L12_2 = L3_2.resolve
      L14_2 = true
      L12_2(L13_2, L14_2)
    end
  end
  L5_2 = Citizen
  L5_2 = L5_2.Await
  L6_2 = L3_2
  L5_2(L6_2)
  L5_2 = Config
  L5_2 = L5_2.Menus
  L6_2 = Menus
  L6_2 = L6_2.ESX_MENU
  if L5_2 == L6_2 then
    L5_2 = RenderESXMenu
    L6_2 = L2_2
    L7_2 = A0_2.currentName
    L8_2 = A0_2.currentLabel
    L5_2(L6_2, L7_2, L8_2)
  else
    L5_2 = Config
    L5_2 = L5_2.Menus
    L6_2 = Menus
    L6_2 = L6_2.ESX_CONTEXT
    if L5_2 == L6_2 then
      L5_2 = RenderESXContext
      L6_2 = L2_2
      L7_2 = A0_2.currentName
      L8_2 = A0_2.currentLabel
      L5_2(L6_2, L7_2, L8_2)
    end
  end
end
L1_1.Esx = L2_1
L1_1 = Frontend
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  if not A1_2 then
    return
  end
  L2_2 = type
  L3_2 = A1_2
  L2_2 = L2_2(L3_2)
  if "table" == L2_2 then
    L2_2 = table
    L2_2 = L2_2.remove
    L3_2 = A1_2
    L4_2 = 1
    L2_2(L3_2, L4_2)
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Frontend - removed isMenuHeader from array."
    L2_2(L3_2)
  end
end
L1_1.RemoveHeaderFromArray = L2_1
L1_1 = Frontend
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L2_2 = Frontend
  L3_2 = L2_2
  L2_2 = L2_2.RemoveHeaderFromArray
  L4_2 = A1_2
  L2_2(L3_2, L4_2)
  L2_2 = {}
  L3_2 = A0_2.currentName
  L2_2.id = L3_2
  L3_2 = c
  L4_2 = A0_2.currentLabel
  L3_2 = L3_2(L4_2)
  L2_2.title = L3_2
  L3_2 = {}
  L2_2.options = L3_2
  L3_2 = promise
  L3_2 = L3_2.new
  L3_2 = L3_2()
  L4_2 = #A1_2
  L5_2 = ipairs
  L6_2 = A1_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = {}
    L12_2 = L10_2.header
    if L12_2 then
      L12_2 = L10_2.header
      L11_2.title = L12_2
    end
    L12_2 = L10_2.txt
    if L12_2 then
      L12_2 = L10_2.params
      if L12_2 then
        L12_2 = L10_2.txt
        L11_2.description = L12_2
      end
    end
    L12_2 = L10_2.txt
    if L12_2 then
      L12_2 = L10_2.txt
      L11_2.description = L12_2
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      L12_2 = L12_2.event
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.isServer
        if not L12_2 then
          L12_2 = L10_2.params
          L12_2 = L12_2.event
          L11_2.event = L12_2
        end
      end
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      L12_2 = L12_2.isServer
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.event
        if L12_2 then
          L12_2 = L10_2.params
          L12_2 = L12_2.event
          L11_2.serverEvent = L12_2
          L12_2 = L10_2.params
          L12_2 = L12_2.args
          L11_2.args = L12_2
        end
      end
    end
    L12_2 = L10_2.params
    if L12_2 then
      L12_2 = L10_2.params
      if L12_2 then
        L12_2 = L10_2.params
        L12_2 = L12_2.args
      end
      L11_2.args = L12_2
    end
    L12_2 = L10_2.disabled
    if L12_2 then
      L11_2.disabled = true
    end
    L12_2 = L2_2.options
    L13_2 = L2_2.options
    L13_2 = #L13_2
    L13_2 = L13_2 + 1
    L12_2 = L12_2[L13_2]
    if not L12_2 then
      L12_2 = L2_2.options
      L13_2 = L2_2.options
      L13_2 = #L13_2
      L13_2 = L13_2 + 1
      L12_2[L13_2] = L11_2
    end
    L12_2 = L2_2.options
    L12_2 = #L12_2
    if L4_2 == L12_2 then
      L13_2 = L3_2
      L12_2 = L3_2.resolve
      L14_2 = true
      L12_2(L13_2, L14_2)
    end
  end
  L5_2 = Citizen
  L5_2 = L5_2.Await
  L6_2 = L3_2
  L5_2(L6_2)
  L5_2 = lib
  L5_2 = L5_2.registerContext
  L6_2 = L2_2
  L5_2(L6_2)
  L5_2 = Wait
  L6_2 = 0
  L5_2(L6_2)
  L5_2 = true
  return L5_2
end
L1_1.Ox = L2_1
L1_1 = Frontend
function L2_1(A0_2, A1_2, A2_2, A3_2, A4_2)
  local L5_2, L6_2, L7_2, L8_2, L9_2
  if not A4_2 then
    A4_2 = false
  end
  if not A1_2 then
    L5_2 = error
    L6_2 = "Frontend - failed to create menu, undefined name."
    return L5_2(L6_2)
  end
  if not A3_2 then
    L5_2 = error
    L6_2 = "Frontend - failed to create menu, undefined menu data."
    return L5_2(L6_2)
  end
  if not A2_2 then
    L5_2 = error
    L6_2 = "Frontend - failed to create menu, undefined menu menuLabel."
    return L5_2(L6_2)
  end
  L5_2 = Config
  L5_2 = L5_2.Menus
  if not L5_2 then
    L6_2 = error
    L7_2 = "Undefined library."
    return L6_2(L7_2)
  end
  L6_2 = Frontend
  L6_2 = L6_2.Menus
  L6_2 = L6_2[A1_2]
  if not L6_2 then
    L6_2 = Frontend
    L6_2 = L6_2.Menus
    L7_2 = {}
    L7_2.data = A3_2
    L6_2[A1_2] = L7_2
    A0_2.currentName = A1_2
  else
    A0_2.currentName = A1_2
  end
  L6_2 = A0_2.currentName
  if not L6_2 then
    L6_2 = dbg
    L6_2 = L6_2.critical
    L7_2 = "Failed to get currentName [%s]"
    L8_2 = A0_2.currentName
    return L6_2(L7_2, L8_2)
  end
  A0_2.currentLabel = A2_2
  L6_2 = Menus
  L6_2 = L6_2.NONE
  if L5_2 == L6_2 then
    L6_2 = Menus
    L5_2 = L6_2.RCORE
    L6_2 = Config
    L6_2.Menus = L5_2
  end
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "Using frontend library -> [%s]"
  L8_2 = L5_2
  L6_2(L7_2, L8_2)
  L6_2 = Menus
  L6_2 = L6_2.QB
  if L5_2 == L6_2 then
    L6_2 = exports
    L6_2 = L6_2["qb-menu"]
    L7_2 = L6_2
    L6_2 = L6_2.openMenu
    L8_2 = A3_2
    L6_2(L7_2, L8_2)
  else
    L6_2 = Menus
    L6_2 = L6_2.OX
    if L5_2 == L6_2 then
      L6_2 = lib
      if not L6_2 then
        L6_2 = error
        L7_2 = [[
Frontend - failed to create menu, ox_lib not hooked with prison resource. 
Please add ox_lib into rcore_prison/fxmanifest.lua
]]
        L8_2 = message
        L7_2 = L7_2 .. L8_2
        return L6_2(L7_2)
      end
      if A4_2 then
        L6_2 = Frontend
        L7_2 = L6_2
        L6_2 = L6_2.ParseData
        L8_2 = A3_2
        function L9_2(A0_3)
          local L1_3, L2_3, L3_3
          if A0_3 then
            L1_3 = dbg
            L1_3 = L1_3.debug
            L2_3 = "Opened menu named [%s]"
            L3_3 = A0_2.currentName
            L1_3(L2_3, L3_3)
            L1_3 = lib
            L1_3 = L1_3.showContext
            L2_3 = A0_2.currentName
            L1_3(L2_3)
          end
        end
        L6_2(L7_2, L8_2, L9_2)
      end
    else
      if "es_extended" ~= L5_2 and "esx_context" ~= L5_2 then
        L6_2 = Menus
        L6_2 = L6_2.RCORE
        if L5_2 ~= L6_2 then
          goto lbl_120
        end
      end
      L6_2 = Framework
      if not L6_2 then
        L6_2 = error
        L7_2 = "Frontend - failed to create menu, esx_menu_list or esx_context not hooked with prison resource - unk framework."
        return L6_2(L7_2)
      end
      if A4_2 then
        L6_2 = Frontend
        L7_2 = L6_2
        L6_2 = L6_2.ParseData
        L8_2 = A3_2
        function L9_2(A0_3)
          local L1_3, L2_3, L3_3
          if A0_3 then
            L1_3 = dbg
            L1_3 = L1_3.info
            L2_3 = "Opened menu named [%s]"
            L3_3 = A0_2.currentName
            L1_3(L2_3, L3_3)
          end
        end
        L6_2(L7_2, L8_2, L9_2)
      end
    end
  end
  ::lbl_120::
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "Menu finished return state."
  L6_2(L7_2)
end
L1_1.CreateMenu = L2_1
