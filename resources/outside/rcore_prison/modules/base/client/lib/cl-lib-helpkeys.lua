local L0_1, L1_1
L0_1 = {}
HelpKeys = L0_1
L0_1 = HelpKeys
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = FrontendService
  L2_2 = L2_2.SendReactMessage
  L3_2 = "loadApp"
  L4_2 = {}
  L4_2.visible = true
  L5_2 = Screens
  L5_2 = L5_2.HELPKEYS
  L4_2.screen = L5_2
  L5_2 = {}
  L5_2.visible = true
  L5_2.helpKeys = A0_2
  L6_2 = A1_2 or L6_2
  if not A1_2 then
    L6_2 = "top-left"
  end
  L5_2.position = L6_2
  L5_2.marginVertical = "30px"
  L5_2.marginHorizontal = "30px"
  L5_2.asColumn = true
  L4_2.help = L5_2
  L2_2(L3_2, L4_2)
end
L0_1.Show = L1_1
L0_1 = HelpKeys
function L1_1()
  local L0_2, L1_2, L2_2, L3_2
  L0_2 = FrontendService
  L0_2 = L0_2.SendReactMessage
  L1_2 = "loadApp"
  L2_2 = {}
  L2_2.visible = false
  L3_2 = {}
  L3_2.visible = false
  L2_2.help = L3_2
  L3_2 = false
  L0_2(L1_2, L2_2, L3_2)
end
L0_1.Hide = L1_1
L0_1 = HelpKeys
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = HelpKeys
  L0_2 = L0_2.Show
  L1_2 = {}
  L2_2 = {}
  L3_2 = _U
  L4_2 = "HELPKEYS_LABELS.CONFIRM"
  L3_2 = L3_2(L4_2)
  L2_2.label = L3_2
  L2_2.keyName = "Enter"
  L3_2 = {}
  L4_2 = _U
  L5_2 = "HELPKEYS_LABELS.EXIT_MENU"
  L4_2 = L4_2(L5_2)
  L3_2.label = L4_2
  L3_2.keyName = "BACKSPACE"
  L1_2[1] = L2_2
  L1_2[2] = L3_2
  L2_2 = "top-left"
  L0_2(L1_2, L2_2)
end
L0_1.ShowNavigationKeysInMenu = L1_1
L0_1 = HelpKeys
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = HelpKeys
  L0_2 = L0_2.Show
  L1_2 = {}
  L2_2 = {}
  L3_2 = _U
  L4_2 = "HELPKEYS_LABELS.INTERACT"
  L3_2 = L3_2(L4_2)
  L2_2.label = L3_2
  L3_2 = Config
  L3_2 = L3_2.Zone
  L3_2 = L3_2.HelpkeysInteractKeyName
  if not L3_2 then
    L3_2 = "E"
  end
  L2_2.keyName = L3_2
  L1_2[1] = L2_2
  L2_2 = Config
  L2_2 = L2_2.Helpkeys
  L2_2 = L2_2.Position
  L0_2(L1_2, L2_2)
end
L0_1.ShowZoneInteractionKeys = L1_1
