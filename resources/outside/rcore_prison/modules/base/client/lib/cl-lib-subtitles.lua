local L0_1, L1_1
L0_1 = {}
Subtitles = L0_1
L0_1 = Subtitles
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = FrontendService
  L1_2 = L1_2.SendReactMessage
  L2_2 = FE_EVENTS
  L2_2 = L2_2.SUBTITLES
  L3_2 = {}
  L3_2.visible = true
  L3_2.text = A0_2
  L4_2 = Config
  L4_2 = L4_2.Subtitles
  L4_2 = L4_2.Position
  if not L4_2 then
    L4_2 = "bottom-center"
  end
  L3_2.position = L4_2
  L1_2(L2_2, L3_2)
end
L0_1.Show = L1_1
L0_1 = Subtitles
function L1_1()
  local L0_2, L1_2, L2_2
  L0_2 = FrontendService
  L0_2 = L0_2.SendReactMessage
  L1_2 = FE_EVENTS
  L1_2 = L1_2.SUBTITLES
  L2_2 = {}
  L2_2.visible = false
  L0_2(L1_2, L2_2)
end
L0_1.Hide = L1_1
