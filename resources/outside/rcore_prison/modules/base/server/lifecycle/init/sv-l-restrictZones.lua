local L0_1, L1_1, L2_1
L0_1 = RegisterNetEvent
L1_1 = "rcore_prison:server:currentRestrictZone"
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = source
  L2_2 = SH
  L2_2 = L2_2.data
  if not L2_2 then
    return
  end
  if not A0_2 then
    return
  end
  L2_2 = A0_2.id
  L3_2 = SH
  L3_2 = L3_2.data
  L3_2 = L3_2.RestrictCommandZones
  L4_2 = L3_2[L2_2]
  if L4_2 then
    L5_2 = next
    L6_2 = L4_2
    L5_2 = L5_2(L6_2)
    if L5_2 then
      L5_2 = GetPlayerPed
      L6_2 = L1_2
      L5_2 = L5_2(L6_2)
      L6_2 = GetEntityCoords
      L7_2 = L5_2
      L6_2 = L6_2(L7_2)
      L7_2 = IsPointInPolygon
      L8_2 = L6_2
      L9_2 = L4_2.vertices
      L7_2 = L7_2(L8_2, L9_2)
      if not L7_2 then
        return
      end
      RestrictZone = A0_2
    end
  end
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNetEvent
L1_1 = "rcore_prison:server:clearCurrentRestrictZone"
function L2_1()
  local L0_2, L1_2
  L0_2 = RestrictZone
  if L0_2 then
    L0_2 = next
    L1_2 = RestrictZone
    L0_2 = L0_2(L1_2)
    if L0_2 then
      L0_2 = {}
      RestrictZone = L0_2
    end
  end
end
L0_1(L1_1, L2_1)
