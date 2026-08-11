local L0_1, L1_1, L2_1, L3_1
L0_1 = false
L1_1 = AddEventHandler
L2_1 = "rcore_prison:shared:internal:MapLoaded"
function L3_1()
  local L0_2, L1_2
  L0_2 = true
  L0_1 = L0_2
end
L1_1(L2_1, L3_1)
L1_1 = CreateThread
function L2_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2
  L0_2 = Config
  L0_2 = L0_2.RestrictZones
  if not L0_2 then
    return
  end
  L0_2 = Config
  L0_2 = L0_2.RestrictZones
  L0_2 = L0_2.Enable
  if not L0_2 then
    L0_2 = dbg
    L0_2 = L0_2.debug
    L1_2 = "Restrict zones are not enabled, not loading them"
    return L0_2(L1_2)
  end
  L0_2 = 0
  repeat
    L1_2 = Wait
    L2_2 = 250
    L1_2(L2_2)
    L0_2 = L0_2 + 1
    if L0_2 >= 50 then
      L1_2 = dbg
      L1_2 = L1_2.critical
      L2_2 = "Failed to load prison map in cl-l-restrictZones.lua"
      L1_2(L2_2)
      break
    end
    L1_2 = L0_1
  until L1_2
  L1_2 = SH
  L1_2 = L1_2.data
  if not L1_2 then
    return
  end
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.RestrictCommandZones
  if not L1_2 then
    L1_2 = dbg
    L1_2 = L1_2.critical
    L2_2 = "Failed to find any RestrictCommandZones for map: %s"
    L3_2 = Config
    L3_2 = L3_2.Map
    return L1_2(L2_2, L3_2)
  end
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.RestrictCommandZones
  if not L1_2 then
    return
  end
  L2_2 = {}
  while true do
    L3_2 = Wait
    L4_2 = 250
    L3_2(L4_2)
    L3_2 = PlayerPedId
    L3_2 = L3_2()
    L4_2 = GetEntityCoords
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    L5_2 = vec2
    L6_2 = L4_2.x
    L7_2 = L4_2.y
    L5_2 = L5_2(L6_2, L7_2)
    L6_2 = pairs
    L7_2 = L1_2
    L6_2, L7_2, L8_2, L9_2 = L6_2(L7_2)
    for L10_2, L11_2 in L6_2, L7_2, L8_2, L9_2 do
      L12_2 = L11_2.vertices
      if L12_2 then
        L12_2 = math
        L12_2 = L12_2.huge
        L13_2 = nil
        L14_2 = nil
        L15_2 = nil
        L16_2 = ipairs
        L17_2 = L11_2.vertices
        L16_2, L17_2, L18_2, L19_2 = L16_2(L17_2)
        for L20_2, L21_2 in L16_2, L17_2, L18_2, L19_2 do
          L22_2 = vec2
          L23_2 = L21_2.x
          L24_2 = L21_2.y
          L22_2 = L22_2(L23_2, L24_2)
          L22_2 = L22_2 - L5_2
          L22_2 = #L22_2
          if L12_2 >= L22_2 then
            L12_2 = L22_2
            L13_2 = L21_2
            L14_2 = L11_2.name
            L15_2 = L11_2.access
          end
        end
        L16_2 = {}
        L16_2.closestVertex = L13_2
        L16_2.distance = L12_2
        L16_2.name = L14_2
        L16_2.access = L15_2
        if L16_2 then
          L17_2 = L16_2.distance
          L18_2 = Config
          L18_2 = L18_2.RestrictZones
          if L18_2 then
            L18_2 = Config
            L18_2 = L18_2.RestrictZones
            L18_2 = L18_2.CheckDist
            if L18_2 then
              goto lbl_118
            end
          end
          L18_2 = 10
          ::lbl_118::
          if L17_2 < L18_2 then
            L17_2 = IsPointInPolygon
            L18_2 = L5_2
            L19_2 = L11_2.vertices
            L17_2 = L17_2(L18_2, L19_2)
            if L17_2 then
              L18_2 = next
              L19_2 = RestrictZone
              L18_2 = L18_2(L19_2)
              if not L18_2 then
                L18_2 = {}
                L18_2.id = L10_2
                L19_2 = L16_2.name
                L18_2.name = L19_2
                L19_2 = L16_2.access
                L18_2.access = L19_2
                RestrictZone = L18_2
                L18_2 = TriggerServerEvent
                L19_2 = "rcore_prison:server:currentRestrictZone"
                L20_2 = RestrictZone
                L18_2(L19_2, L20_2)
            end
            elseif not L17_2 then
              L18_2 = RestrictZone
              if L18_2 then
                L18_2 = next
                L19_2 = RestrictZone
                L18_2 = L18_2(L19_2)
                if L18_2 then
                  L18_2 = {}
                  RestrictZone = L18_2
                  L18_2 = {}
                  L16_2 = L18_2
                  L18_2 = TriggerServerEvent
                  L19_2 = "rcore_prison:server:clearCurrentRestrictZone"
                  L18_2(L19_2)
                end
              end
            end
          end
        end
      end
    end
  end
end
L1_1(L2_1)
