local L0_1, L1_1, L2_1, L3_1
L0_1 = 0
L1_1 = AddEventHandler
L2_1 = "rcore_prison:shared:internal:MapLoaded"
function L3_1()
  local L0_2, L1_2
  L0_2 = HandlePool
  L0_2()
end
L1_1(L2_1, L3_1)
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L0_2 = {}
  L1_2 = "PRISONER"
  L2_2 = "COP"
  L0_2[1] = L1_2
  L0_2[2] = L2_2
  L1_2 = 1
  L2_2 = #L0_2
  L3_2 = 1
  for L4_2 = L1_2, L2_2, L3_2 do
    L5_2 = SetRelationshipBetweenGroups
    L6_2 = 1
    L7_2 = L0_2[L4_2]
    L8_2 = 1862763509
    L5_2(L6_2, L7_2, L8_2)
  end
  L1_2 = SH
  L1_2 = L1_2.data
  if not L1_2 then
    return
  end
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.interaction
  if not L1_2 then
    return
  end
  L1_2 = vec3
  L2_2 = SH
  L2_2 = L2_2.data
  L2_2 = L2_2.prisonYard
  L2_2 = L2_2.x
  L3_2 = SH
  L3_2 = L3_2.data
  L3_2 = L3_2.prisonYard
  L3_2 = L3_2.y
  L4_2 = SH
  L4_2 = L4_2.data
  L4_2 = L4_2.prisonYard
  L4_2 = L4_2.z
  L1_2 = L1_2(L2_2, L3_2, L4_2)
  L2_2 = 300
  L3_2 = 300
  L4_2 = Config
  L4_2 = L4_2.EnableSpawnNPCInsidePrison
  if not L4_2 then
    L4_2 = dbg
    L4_2 = L4_2.debug
    L5_2 = "Disabling NPC spawning inside prison."
    L4_2(L5_2)
    L4_2 = SetAllVehicleGeneratorsActiveInArea
    L5_2 = L1_2.x
    L5_2 = L5_2 - L2_2
    L6_2 = L1_2.y
    L6_2 = L6_2 - L2_2
    L7_2 = L1_2.z
    L7_2 = L7_2 - L3_2
    L8_2 = L1_2.x
    L8_2 = L8_2 + L2_2
    L9_2 = L1_2.y
    L9_2 = L9_2 + L2_2
    L10_2 = L1_2.z
    L10_2 = L10_2 + L3_2
    L11_2 = false
    L12_2 = false
    L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
    L4_2 = SetPedNonCreationArea
    L5_2 = L1_2.x
    L5_2 = L5_2 - L2_2
    L6_2 = L1_2.y
    L6_2 = L6_2 - L2_2
    L7_2 = L1_2.z
    L7_2 = L7_2 - L3_2
    L8_2 = L1_2.x
    L8_2 = L8_2 + L2_2
    L9_2 = L1_2.y
    L9_2 = L9_2 + L2_2
    L10_2 = L1_2.z
    L10_2 = L10_2 + L3_2
    L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2)
    L4_2 = AddScenarioBlockingArea
    L5_2 = L1_2.x
    L5_2 = L5_2 - L2_2
    L6_2 = L1_2.y
    L6_2 = L6_2 - L2_2
    L7_2 = L1_2.z
    L7_2 = L7_2 - L3_2
    L8_2 = L1_2.x
    L8_2 = L8_2 + L2_2
    L9_2 = L1_2.y
    L9_2 = L9_2 + L2_2
    L10_2 = L1_2.z
    L10_2 = L10_2 + L3_2
    L11_2 = false
    L12_2 = true
    L13_2 = true
    L14_2 = true
    L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2)
    L0_1 = L4_2
    L4_2 = {}
    L5_2 = "s_m_y_prisoner_01"
    L6_2 = "s_m_y_primuscl_01,"
    L4_2[1] = L5_2
    L4_2[2] = L6_2
    L5_2 = 1
    L6_2 = #L4_2
    L7_2 = 1
    for L8_2 = L5_2, L6_2, L7_2 do
      L9_2 = L4_2[L8_2]
      L10_2 = IsModelAPed
      L11_2 = L9_2
      L10_2 = L10_2(L11_2)
      if L10_2 then
        L10_2 = SetPedModelIsSuppressed
        L11_2 = L9_2
        L12_2 = true
        L10_2(L11_2, L12_2)
      end
    end
  else
    L4_2 = SetAllVehicleGeneratorsActiveInArea
    L5_2 = L1_2.x
    L5_2 = L5_2 - L2_2
    L6_2 = L1_2.y
    L6_2 = L6_2 - L2_2
    L7_2 = L1_2.z
    L7_2 = L7_2 - L3_2
    L8_2 = L1_2.x
    L8_2 = L8_2 + L2_2
    L9_2 = L1_2.y
    L9_2 = L9_2 + L2_2
    L10_2 = L1_2.z
    L10_2 = L10_2 + L3_2
    L11_2 = true
    L12_2 = true
    L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
    L4_2 = RemoveScenarioBlockingArea
    L5_2 = L0_1
    L6_2 = true
    L4_2(L5_2, L6_2)
    L4_2 = dbg
    L4_2 = L4_2.debug
    L5_2 = "Enabling NPC spawning inside prison."
    L4_2(L5_2)
  end
end
HandlePool = L1_1
