local L0_1, L1_1
L0_1 = MENU_ID_LIST
L0_1 = L0_1.COMS_MENU
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = DestroyAllMenus
  L1_2()
  L1_2 = COMSService
  L1_2 = L1_2.GetUser
  L1_2 = L1_2()
  L2_2 = {}
  L3_2 = {}
  L4_2 = _U
  L5_2 = "COMS_MENU.TITLE"
  L4_2 = L4_2(L5_2)
  L3_2.header = L4_2
  L3_2.isMenuHeader = true
  L2_2[1] = L3_2
  if L1_2 then
    L3_2 = next
    L4_2 = L1_2
    L3_2 = L3_2(L4_2)
    if L3_2 then
      L3_2 = L1_2.state
      if "RETURN" == L3_2 then
        L4_2 = #L2_2
        L4_2 = L4_2 + 1
        L5_2 = {}
        L6_2 = _U
        L7_2 = "COMS_MENU.REPORT_MISSION_TITLE"
        L6_2 = L6_2(L7_2)
        L5_2.header = L6_2
        L6_2 = _U
        L7_2 = "COMS_MENU.REPORT_MISSION_DESC"
        L6_2 = L6_2(L7_2)
        L5_2.description = L6_2
        L6_2 = #L2_2
        L6_2 = L6_2 + 1
        L5_2.order = L6_2
        L5_2.type = "button"
        L6_2 = {}
        L6_2.isServer = true
        L6_2.event = "rcore_prison:server:requestFinishPeroll"
        L5_2.params = L6_2
        L2_2[L4_2] = L5_2
      elseif "IDLE" == L3_2 then
        L4_2 = #L2_2
        L4_2 = L4_2 + 1
        L5_2 = {}
        L6_2 = _U
        L7_2 = "COMS_MENU.START_MISSION_TITLE"
        L6_2 = L6_2(L7_2)
        L5_2.header = L6_2
        L6_2 = _U
        L7_2 = "COMS_MENU.START_MISSION_DESC"
        L6_2 = L6_2(L7_2)
        L5_2.description = L6_2
        L6_2 = #L2_2
        L6_2 = L6_2 + 1
        L5_2.order = L6_2
        L5_2.type = "button"
        L6_2 = {}
        L6_2.isServer = true
        L6_2.event = "rcore_prison:server:requestComs"
        L5_2.params = L6_2
        L2_2[L4_2] = L5_2
      else
        L4_2 = dbg
        L4_2 = L4_2.menu
        L5_2 = "COMS is not in return state [%s]"
        L6_2 = L3_2
        return L4_2(L5_2, L6_2)
      end
  end
  else
    L3_2 = #L2_2
    L3_2 = L3_2 + 1
    L4_2 = {}
    L5_2 = _U
    L6_2 = "COMS_MENU.START_MISSION_TITLE"
    L5_2 = L5_2(L6_2)
    L4_2.header = L5_2
    L5_2 = _U
    L6_2 = "COMS_MENU.START_MISSION_DESC"
    L5_2 = L5_2(L6_2)
    L4_2.description = L5_2
    L5_2 = #L2_2
    L5_2 = L5_2 + 1
    L4_2.order = L5_2
    L4_2.type = "button"
    L5_2 = {}
    L5_2.isServer = true
    L5_2.event = "rcore_prison:server:requestComs"
    L4_2.params = L5_2
    L2_2[L3_2] = L4_2
  end
  L3_2 = Frontend
  L4_2 = L3_2
  L3_2 = L3_2.CreateMenu
  L5_2 = L0_1
  L6_2 = _U
  L7_2 = "COMS_MENU.TITLE"
  L6_2 = L6_2(L7_2)
  L7_2 = L2_2
  L8_2 = true
  L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
end
OpenStartCOMS = L1_1
