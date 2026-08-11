local L0_1, L1_1
L0_1 = {}
Text = L0_1
L0_1 = Text
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = FrontendService
  L2_2 = L2_2.SendReactMessage
  L3_2 = FE_EVENTS
  L3_2 = L3_2.TEXT_UI
  L4_2 = {}
  L5_2 = {}
  L5_2.visible = true
  L6_2 = {}
  L7_2 = {}
  L7_2.label = A0_2
  L6_2[1] = L7_2
  L5_2.text = L6_2
  L6_2 = A1_2 or L6_2
  if not A1_2 then
    L6_2 = "bottom-right"
  end
  L5_2.position = L6_2
  L5_2.marginVertical = "30px"
  L5_2.marginHorizontal = "30px"
  L5_2.asColumn = true
  L4_2.text = L5_2
  L2_2(L3_2, L4_2)
end
L0_1.Show = L1_1
L0_1 = Text
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = FrontendService
  L0_2 = L0_2.SendReactMessage
  L1_2 = FE_EVENTS
  L1_2 = L1_2.TEXT_UI
  L2_2 = {}
  L3_2 = {}
  L3_2.visible = false
  L4_2 = {}
  L3_2.text = L4_2
  L2_2.text = L3_2
  L3_2 = false
  L0_2(L1_2, L2_2, L3_2)
end
L0_1.Hide = L1_1
