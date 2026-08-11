local L0_1, L1_1, L2_1
L0_1 = MENU_ID_LIST
L0_1 = L0_1.JOB_MENU
L1_1 = {}
function L2_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L0_2 = {}
  L1_2 = {}
  L2_2 = _U
  L3_2 = "MENU.JOB_TITLE"
  L2_2 = L2_2(L3_2)
  L1_2.header = L2_2
  L1_2.isMenuHeader = true
  L0_2[1] = L1_2
  L1_1 = L0_2
  L0_2 = 1
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.jobs
  L1_2 = #L1_2
  L2_2 = 1
  for L3_2 = L0_2, L1_2, L2_2 do
    L4_2 = L1_1
    L4_2 = #L4_2
    L5_2 = L4_2 + 1
    L4_2 = L1_1
    L6_2 = {}
    L7_2 = SH
    L7_2 = L7_2.data
    L7_2 = L7_2.jobs
    L7_2 = L7_2[L3_2]
    L7_2 = L7_2.name
    L6_2.header = L7_2
    L7_2 = SH
    L7_2 = L7_2.data
    L7_2 = L7_2.jobs
    L7_2 = L7_2[L3_2]
    L7_2 = L7_2.description
    if not L7_2 then
      L7_2 = "No description"
    end
    L6_2.description = L7_2
    L6_2.order = L3_2
    L7_2 = {}
    L7_2.isServer = true
    L7_2.event = "rcore_prison:server:requestJob"
    L7_2.args = L3_2
    L6_2.params = L7_2
    L4_2[L5_2] = L6_2
  end
  L0_2 = Frontend
  L1_2 = L0_2
  L0_2 = L0_2.CreateMenu
  L2_2 = L0_1
  L3_2 = _U
  L4_2 = "MENU.JOB_TITLE"
  L3_2 = L3_2(L4_2)
  L4_2 = L1_1
  L5_2 = true
  L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
end
OpenJobMenu = L2_1
