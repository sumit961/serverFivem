local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1
L0_1 = false
L1_1 = {}
WorldCOMS = L1_1
L1_1 = {}
NearWorldCOMS = L1_1
L1_1 = {}
CWZones = L1_1
L1_1 = {}
L1_1.zoneId = nil
L1_1.verticeId = nil
L1_1.owner = nil
L2_1 = false
L3_1 = glm
L3_1 = L3_1.polygon
L3_1 = L3_1.contains
L4_1 = {}
L4_1.prop_rub_binbag_06 = 2.5
L4_1.prop_rub_cardpile_06 = 2.5
L4_1.prop_rub_litter_03c = 4.0
L5_1 = {}
function L6_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2
  L1_2 = CWZones
  L2_2 = A0_2.zoneIdx
  L1_2 = L1_2[L2_2]
  if not L1_2 then
    L1_2 = CWZones
    L2_2 = A0_2.zoneIdx
    L3_2 = {}
    L1_2[L2_2] = L3_2
  end
  L1_2 = CWZones
  L2_2 = A0_2.zoneIdx
  L1_2 = L1_2[L2_2]
  L1_2 = #L1_2
  L1_2 = L1_2 + 1
  A0_2.idx = L1_2
  L1_2 = A0_2.size
  if not L1_2 then
    L1_2 = 2
  end
  A0_2.size = L1_2
  L1_2 = A0_2.zoneIdx
  A0_2.zoneIdx = L1_2
  L1_2 = {}
  A0_2.prefechPoints = L1_2
  L1_2 = pairs
  L2_2 = A0_2.points
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = A0_2.prefechPoints
    L7_2 = L7_2[L5_2]
    if not L7_2 then
      L7_2 = A0_2.prefechPoints
      L8_2 = vec3
      L9_2 = L6_2.X
      L10_2 = L6_2.Y
      L11_2 = L6_2.Z
      L8_2 = L8_2(L9_2, L10_2, L11_2)
      L7_2[L5_2] = L8_2
    end
  end
  L1_2 = A0_2.prefechPoints
  A0_2.points = L1_2
  L1_2 = glm
  L1_2 = L1_2.polygon
  L1_2 = L1_2.new
  L2_2 = A0_2.points
  L1_2 = L1_2(L2_2)
  A0_2.polygon = L1_2
  L1_2 = A0_2.polygon
  L2_2 = L1_2
  L1_2 = L1_2.centroid
  L1_2 = L1_2(L2_2)
  A0_2.coords = L1_2
  L1_2 = vec3
  L2_2 = A0_2.pos
  L2_2 = L2_2.X
  L3_2 = A0_2.pos
  L3_2 = L3_2.Y
  L4_2 = A0_2.pos
  L4_2 = L4_2.Z
  L1_2 = L1_2(L2_2, L3_2, L4_2)
  A0_2.center = L1_2
  L1_2 = contains
  A0_2.contains = L1_2
  L1_2 = CWZones
  L2_2 = A0_2.zoneIdx
  L1_2 = L1_2[L2_2]
  L2_2 = A0_2.idx
  L1_2[L2_2] = A0_2
  L1_2 = A0_2.spawnTrashEntities
  if L1_2 then
    L1_2 = CWZones
    L2_2 = A0_2.zoneIdx
    L1_2 = L1_2[L2_2]
    L2_2 = A0_2.idx
    L1_2 = L1_2[L2_2]
    L1_2 = L1_2.entities
    if not L1_2 then
      L1_2 = A0_2.modelsPreset
      L2_2 = A0_2.idx
      L1_2 = L1_2[L2_2]
      if not L1_2 then
        return
      end
      L2_2 = joaat
      L3_2 = L1_2
      L2_2 = L2_2(L3_2)
      L3_2 = IsModelValid
      L4_2 = L2_2
      L3_2 = L3_2(L4_2)
      if L3_2 then
        L3_2 = LoadModel
        L4_2 = L2_2
        L3_2(L4_2)
        L3_2 = CreateObject
        L4_2 = L2_2
        L5_2 = A0_2.center
        L5_2 = L5_2.x
        L6_2 = A0_2.center
        L6_2 = L6_2.y
        L7_2 = A0_2.center
        L7_2 = L7_2.z
        L8_2 = false
        L9_2 = false
        L10_2 = false
        L3_2 = L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2)
        L4_2 = GetEntityCoords
        L5_2 = L3_2
        L4_2 = L4_2(L5_2)
        L5_2 = GetEntityHeightAboveGround
        L6_2 = L3_2
        L5_2 = L5_2(L6_2)
        L6_2 = GetEntityArchetypeName
        L7_2 = L3_2
        L6_2 = L6_2(L7_2)
        L7_2 = SetEntityCoords
        L8_2 = L3_2
        L9_2 = L4_2.x
        L10_2 = L4_2.y
        L11_2 = L4_2.z
        L7_2(L8_2, L9_2, L10_2, L11_2)
        L7_2 = L4_1
        L7_2 = L7_2[L6_2]
        if L7_2 then
          L7_2 = L4_1
          L7_2 = L7_2[L6_2]
          A0_2.size = L7_2
        end
        L7_2 = Wait
        L8_2 = 0
        L7_2(L8_2)
        L7_2 = PlaceObjectOnGroundProperly
        L8_2 = L3_2
        L7_2(L8_2)
        L7_2 = FreezeEntityPosition
        L8_2 = L3_2
        L9_2 = true
        L7_2(L8_2, L9_2)
        L7_2 = SetEntityCollision
        L8_2 = L3_2
        L9_2 = false
        L10_2 = true
        L7_2(L8_2, L9_2, L10_2)
        L7_2 = DoesEntityExist
        L8_2 = L3_2
        L7_2 = L7_2(L8_2)
        if L7_2 then
          L7_2 = CWZones
          L8_2 = A0_2.zoneIdx
          L7_2 = L7_2[L8_2]
          L8_2 = A0_2.idx
          L7_2 = L7_2[L8_2]
          L8_2 = {}
          L8_2.entity = L3_2
          L8_2.model = L2_2
          L7_2.entities = L8_2
          L7_2 = MyServerId
          L8_2 = A0_2.owner
          if L7_2 == L8_2 then
            L7_2 = SetEntityDrawOutline
            L8_2 = L3_2
            L9_2 = true
            L7_2(L8_2, L9_2)
            L7_2 = SetEntityDrawOutlineShader
            L8_2 = 1
            L7_2(L8_2)
            L7_2 = SetEntityDrawOutlineColor
            L8_2 = Config
            L8_2 = L8_2.COMS
            L8_2 = L8_2.Outline
            L8_2 = L8_2.color
            L8_2 = L8_2.x
            L9_2 = Config
            L9_2 = L9_2.COMS
            L9_2 = L9_2.Outline
            L9_2 = L9_2.color
            L9_2 = L9_2.y
            L10_2 = Config
            L10_2 = L10_2.COMS
            L10_2 = L10_2.Outline
            L10_2 = L10_2.color
            L10_2 = L10_2.z
            L11_2 = Config
            L11_2 = L11_2.COMS
            L11_2 = L11_2.Outline
            L11_2 = L11_2.opacity
            L7_2(L8_2, L9_2, L10_2, L11_2)
          end
        end
      end
    end
  end
  L1_2 = A0_2.decals
  if L1_2 then
    L1_2 = CWZones
    L2_2 = A0_2.zoneIdx
    L1_2 = L1_2[L2_2]
    L2_2 = A0_2.idx
    L1_2 = L1_2[L2_2]
    L1_2 = L1_2.decal
    if not L1_2 then
      L1_2 = AddDecal
      L2_2 = 4421
      L3_2 = A0_2.center
      L3_2 = L3_2.x
      L4_2 = A0_2.center
      L4_2 = L4_2.y
      L5_2 = A0_2.center
      L5_2 = L5_2.z
      L6_2 = 0.0
      L7_2 = 0.0
      L8_2 = -1.0
      L9_2 = func_522
      L10_2 = 0.0
      L11_2 = 1.0
      L12_2 = 0.0
      L9_2 = L9_2(L10_2, L11_2, L12_2)
      L10_2 = 8.0
      L11_2 = 8.0
      L12_2 = 0.1
      L13_2 = 0.0
      L14_2 = 0.0
      L15_2 = 0.5
      L16_2 = -1.0
      L17_2 = 0
      L18_2 = 0
      L19_2 = 0
      L1_2 = L1_2(L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2)
      L2_2 = CWZones
      L3_2 = A0_2.zoneIdx
      L2_2 = L2_2[L3_2]
      L3_2 = A0_2.idx
      L2_2 = L2_2[L3_2]
      L2_2.decal = L1_2
    end
  end
  L1_2 = Wait
  L2_2 = 0
  L1_2(L2_2)
  return A0_2
end
L5_1.poly = L6_1
zones = L5_1
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = L3_1
  L3_2 = A0_2.polygon
  L4_2 = A1_2
  L5_2 = A0_2.thickness
  L5_2 = L5_2 / 4
  return L2_2(L3_2, L4_2, L5_2)
end
contains = L5_1
L5_1 = CreateThread
function L6_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L0_2 = PlayerPedId
  L1_2 = GetEntityCoords
  while true do
    L2_2 = Wait
    L3_2 = 1000
    L2_2(L3_2)
    L2_2 = false
    L0_1 = L2_2
    L2_2 = L0_2
    L2_2 = L2_2()
    L3_2 = L1_2
    L4_2 = L2_2
    L3_2 = L3_2(L4_2)
    L4_2 = pairs
    L5_2 = WorldCOMS
    L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
    for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
      L10_2 = L9_2.position
      L10_2 = L3_2 - L10_2
      L10_2 = #L10_2
      L11_2 = NearWorldCOMS
      L12_2 = L9_2.id
      L11_2 = L11_2[L12_2]
      if L11_2 then
        L11_2 = L11_2.renderDistance
      end
      if not L11_2 then
        L11_2 = Config
        L11_2 = L11_2.COMS
        L11_2 = L11_2.RenderDistance
      end
      if L10_2 < L11_2 then
        L11_2 = NearWorldCOMS
        L12_2 = L9_2.id
        L11_2[L12_2] = L9_2
        L11_2 = true
        L0_1 = L11_2
      else
        L9_2.rendering = false
        L11_2 = WorldCOMS
        L11_2[L8_2] = L9_2
        L11_2 = NearWorldCOMS
        L12_2 = L9_2.id
        L11_2[L12_2] = nil
      end
    end
  end
end
L7_1 = "cl-lib-coms code name: Phoenix"
L5_1(L6_1, L7_1)
L5_1 = CreateThread
function L6_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2
  L0_2 = PlayerPedId
  L1_2 = GetEntityCoords
  L2_2 = 0
  while true do
    L3_2 = Wait
    L4_2 = L2_2
    L3_2(L4_2)
    L3_2 = L0_1
    if not L3_2 then
      L2_2 = 250
      L3_2 = Wait
      L4_2 = 300
      L3_2(L4_2)
    end
    L3_2 = L0_2
    L3_2 = L3_2()
    L4_2 = L1_2
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    L5_2 = pairs
    L6_2 = NearWorldCOMS
    L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
    for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
      L11_2 = L10_2.position
      L11_2 = L4_2 - L11_2
      L11_2 = #L11_2
      L12_2 = L10_2.getWallState
      L12_2 = L12_2()
      if L12_2 then
        L13_2 = Config
        L13_2 = L13_2.Escape
        L13_2 = L13_2.WallLodSyncDistance
        if L11_2 < L13_2 then
          L13_2 = L10_2.syncWallState
          if not L13_2 then
            L13_2 = L10_2.getZonePlayers
            L13_2 = L13_2()
            if L13_2 then
              L14_2 = next
              L15_2 = L13_2
              L14_2 = L14_2(L15_2)
              if L14_2 then
                L14_2 = tostring
                L15_2 = MyServerId
                L14_2 = L14_2(L15_2)
                L14_2 = L13_2[L14_2]
                L15_2 = dbg
                L15_2 = L15_2.debug
                L16_2 = "[LOD - Walls] 1. Loading state cache for current user with state [%s]!"
                L17_2 = L14_2
                L15_2(L16_2, L17_2)
                if true ~= L14_2 or nil == L14_2 then
                  L15_2 = dbg
                  L15_2 = L15_2.debug
                  L16_2 = "[LOD - Walls] 2. Loading destroyed wall since player come into area!"
                  L15_2(L16_2)
                  L15_2 = CustomModelSwap
                  L16_2 = L10_2.position
                  L17_2 = WALL_STATES
                  L17_2 = L17_2.DESTROYED
                  L15_2(L16_2, L17_2)
                elseif false == L14_2 then
                  L15_2 = dbg
                  L15_2 = L15_2.debug
                  L16_2 = "[LOD - Walls] 3. Loading destroyed wall since player come into area!"
                  L15_2(L16_2)
                  L15_2 = CustomModelSwap
                  L16_2 = L10_2.position
                  L17_2 = WALL_STATES
                  L17_2 = L17_2.DESTROYED
                  L15_2(L16_2, L17_2)
                end
                L10_2.syncWallState = true
              end
            end
        end
      end
      elseif L12_2 then
        L13_2 = Config
        L13_2 = L13_2.Escape
        L13_2 = L13_2.WallLodSyncDistance
        if L11_2 > L13_2 then
          L13_2 = L10_2.syncWallState
          if L13_2 then
            L13_2 = L10_2.getZonePlayers
            L13_2 = L13_2()
            if L13_2 then
              L14_2 = next
              L15_2 = L13_2
              L14_2 = L14_2(L15_2)
              if L14_2 then
                L14_2 = tostring
                L15_2 = MyServerId
                L14_2 = L14_2(L15_2)
                L14_2 = L13_2[L14_2]
                if L14_2 or not L14_2 then
                  L15_2 = dbg
                  L15_2 = L15_2.debug
                  L16_2 = "[LOD - Walls] Unloading destroyed wall since player left area!"
                  L15_2(L16_2)
                  L15_2 = L10_2.setZonePlayerState
                  L16_2 = MyServerId
                  L17_2 = false
                  L15_2(L16_2, L17_2)
                  L15_2 = CustomModelSwap
                  L16_2 = L10_2.position
                  L17_2 = WALL_STATES
                  L17_2 = L17_2.FULL_HEALTH
                  L15_2(L16_2, L17_2)
                  L10_2.syncWallState = false
                end
            end
            else
              L14_2 = CustomModelSwap
              L15_2 = L10_2.position
              L16_2 = WALL_STATES
              L16_2 = L16_2.FULL_HEALTH
              L14_2(L15_2, L16_2)
              L10_2.syncWallState = false
            end
          end
        end
      end
    end
  end
end
L7_1 = "cl-lib-coms code name: Alfa"
L5_1(L6_1, L7_1)
L5_1 = CreateThread
function L6_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2
  L0_2 = PlayerPedId
  L1_2 = GetEntityCoords
  L2_2 = 0
  while true do
    L3_2 = Wait
    L4_2 = L2_2
    L3_2(L4_2)
    L3_2 = L0_1
    if not L3_2 then
      L2_2 = 700
      L3_2 = Wait
      L4_2 = 300
      L3_2(L4_2)
    end
    L3_2 = L0_2
    L3_2 = L3_2()
    L4_2 = L1_2
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    L5_2 = pairs
    L6_2 = NearWorldCOMS
    L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
    for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
      L11_2 = L10_2.position
      L11_2 = L4_2 - L11_2
      L11_2 = #L11_2
      if L11_2 and L10_2 then
        L12_2 = L10_2.renderDistance
        if not (L11_2 <= L12_2) then
        end
        L12_2 = L10_2.destroyed
        if not L12_2 then
          L12_2 = L10_2.stopRendering
          if not L12_2 then
            L10_2.rendering = true
            L12_2 = L10_2.inRadius
            if L11_2 <= L12_2 then
              L12_2 = L10_2.isIn
              if false == L12_2 then
                L12_2 = L10_2.onEnter
                if nil ~= L12_2 then
                  L12_2 = pcall
                  L13_2 = L10_2.onEnter
                  L12_2, L13_2 = L12_2(L13_2)
                end
              end
              L10_2.isIn = true
            else
              L12_2 = L10_2.isIn
              if L12_2 then
                L12_2 = L10_2.onLeave
                if nil ~= L12_2 then
                  L12_2 = pcall
                  L13_2 = L10_2.onLeave
                  L12_2, L13_2 = L12_2(L13_2)
                end
                L10_2.isIn = false
              end
            end
            L12_2 = L10_2.isIn
            if L12_2 then
              L12_2 = L10_2.id
              if L12_2 then
                L12_2 = CWZones
                L13_2 = L10_2.id
                L12_2 = L12_2[L13_2]
                if L12_2 then
                  L13_2 = pairs
                  L14_2 = L12_2
                  L13_2, L14_2, L15_2, L16_2 = L13_2(L14_2)
                  for L17_2, L18_2 in L13_2, L14_2, L15_2, L16_2 do
                    L19_2 = L3_1
                    L20_2 = L18_2.polygon
                    L21_2 = L4_2
                    L22_2 = L18_2.size
                    L22_2 = L22_2 / 2
                    L19_2 = L19_2(L20_2, L21_2, L22_2)
                    if L19_2 then
                      L20_2 = L18_2.isInsidePolygon
                      if not L20_2 then
                        L20_2 = L10_2.onEnterPolygon
                        if nil ~= L20_2 then
                          L18_2.isInsidePolygon = true
                          L10_2.verticeId = L17_2
                          L20_2 = pcall
                          L21_2 = L10_2.onEnterPolygon
                          L20_2, L21_2 = L20_2(L21_2)
                        end
                      end
                    else
                      L20_2 = L18_2.isInsidePolygon
                      if L20_2 then
                        L20_2 = L10_2.onLeavePolygon
                        if nil ~= L20_2 then
                          L18_2.isInsidePolygon = false
                          L20_2 = pcall
                          L21_2 = L10_2.onLeavePolygon
                          L20_2, L21_2 = L20_2(L21_2)
                        end
                      end
                    end
                  end
                end
              end
            end
        end
      end
      else
        L10_2.rendering = false
        L2_2 = 300
      end
      L12_2 = NearWorldCOMS
      L12_2[L9_2] = L10_2
    end
  end
end
L7_1 = "cl-lib-coms code name: Beta"
L5_1(L6_1, L7_1)
L5_1 = CreateThread
function L6_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2, L26_2, L27_2, L28_2, L29_2, L30_2, L31_2, L32_2, L33_2, L34_2, L35_2, L36_2
  L0_2 = PlayerPedId
  L1_2 = GetEntityCoords
  L2_2 = DrawMarker
  L3_2 = IsPedInAnyVehicle
  L4_2 = DrawLine
  L5_2 = 0
  while true do
    L6_2 = Wait
    L7_2 = L5_2
    L6_2(L7_2)
    L6_2 = L0_1
    if not L6_2 then
      L6_2 = Wait
      L7_2 = 1000
      L6_2(L7_2)
    end
    L6_2 = pairs
    L7_2 = NearWorldCOMS
    L6_2, L7_2, L8_2, L9_2 = L6_2(L7_2)
    for L10_2, L11_2 in L6_2, L7_2, L8_2, L9_2 do
      L12_2 = L11_2.stopRendering
      if false == L12_2 then
        L12_2 = L11_2.stopRendering
        if not L12_2 then
          L12_2 = L11_2.rendering
          if L12_2 then
            L12_2 = L11_2.destroyed
            if not L12_2 then
              L12_2 = L11_2.renderMarker
              if L12_2 then
                L12_2 = L2_2
                L13_2 = L11_2.type
                L14_2 = L11_2.position
                L14_2 = L14_2.x
                L15_2 = L11_2.position
                L15_2 = L15_2.y
                L16_2 = L11_2.position
                L16_2 = L16_2.z
                L17_2 = L11_2.dir
                L17_2 = L17_2.x
                L18_2 = L11_2.dir
                L18_2 = L18_2.y
                L19_2 = L11_2.dir
                L19_2 = L19_2.z
                L20_2 = L11_2.rot
                L20_2 = L20_2.x
                L21_2 = L11_2.rot
                L21_2 = L21_2.y
                L22_2 = L11_2.rot
                L22_2 = L22_2.z
                L23_2 = L11_2.scale
                L23_2 = L23_2.x
                L24_2 = L11_2.scale
                L24_2 = L24_2.y
                L25_2 = L11_2.scale
                L25_2 = L25_2.z
                L26_2 = L11_2.getRed
                L26_2 = L26_2()
                L27_2 = L11_2.getGreen
                L27_2 = L27_2()
                L28_2 = L11_2.getBlue
                L28_2 = L28_2()
                L29_2 = L11_2.getAlpha
                L29_2 = L29_2()
                L30_2 = false
                L31_2 = L11_2.faceCamera
                L32_2 = 2
                L33_2 = L11_2.rotation
                L34_2 = nil
                L35_2 = nil
                L36_2 = false
                L12_2(L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2, L26_2, L27_2, L28_2, L29_2, L30_2, L31_2, L32_2, L33_2, L34_2, L35_2, L36_2)
              end
            end
          end
        end
      end
    end
  end
end
L7_1 = "cl-lib-coms code name: Bravo"
L5_1(L6_1, L7_1)
function L5_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = table
  L1_2 = L1_2.size
  L2_2 = WorldCOMS
  L1_2 = L1_2(L2_2)
  L1_2 = L1_2 + 1
  L0_2.id = L1_2
  L0_2.type = 28
  L0_2.firstUpdate = false
  L1_2 = GetCurrentResourceName
  L1_2 = L1_2()
  L0_2.resource = L1_2
  L1_2 = Config
  L1_2 = L1_2.COMS
  L1_2 = L1_2.RenderDistance
  L0_2.renderDistance = L1_2
  L1_2 = vector3
  L2_2 = 0
  L3_2 = 0
  L4_2 = 0
  L1_2 = L1_2(L2_2, L3_2, L4_2)
  L0_2.position = L1_2
  L1_2 = vector3
  L2_2 = 0
  L3_2 = 0
  L4_2 = 0
  L1_2 = L1_2(L2_2, L3_2, L4_2)
  L0_2.dir = L1_2
  L1_2 = vector3
  L2_2 = 0
  L3_2 = 0
  L4_2 = 0
  L1_2 = L1_2(L2_2, L3_2, L4_2)
  L0_2.rot = L1_2
  L1_2 = vec3
  L2_2 = 1
  L3_2 = 1
  L4_2 = 1
  L1_2 = L1_2(L2_2, L3_2, L4_2)
  L0_2.scale = L1_2
  L0_2.rotation = false
  L0_2.faceCamera = false
  L0_2.rendering = false
  L0_2.stopRendering = false
  L0_2.owner = nil
  L0_2.isBusy = false
  L0_2.onEnter = nil
  L0_2.onLeave = nil
  L0_2.onEnterPolygon = nil
  L0_2.onLeavePolygon = nil
  L0_2.isIn = false
  L0_2.onlyVehicle = nil
  L0_2.areaDebug = false
  L0_2.models = nil
  L0_2.actionState = false
  L0_2.renderMarker = false
  L0_2.reportState = false
  L1_2 = Config
  L1_2 = L1_2.COMS
  L1_2 = L1_2.InRadius
  L0_2.inRadius = L1_2
  L1_2 = {}
  L0_2.syncData = L1_2
  L1_2 = {}
  L0_2.interactHelpKeys = L1_2
  L0_2.playerJob = nil
  L0_2.breakType = nil
  L0_2.layerName = nil
  L1_2 = WALL_STATES
  L1_2 = L1_2.FULL_HEALTH
  L0_2.wallState = L1_2
  L1_2 = {}
  L1_2.r = 240
  L1_2.g = 200
  L1_2.b = 80
  L1_2.a = 160
  L0_2.color = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.onlyVehicle = A0_3
  end
  L0_2.setOnlyVehicle = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.id = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setId = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.breakType = A0_3
  end
  L0_2.setBreakType = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.breakType
    return L0_3
  end
  L0_2.getBreakType = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.id
    return L0_3
  end
  L0_2.getId = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.actionState = A0_3
  end
  L0_2.setActionState = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.actionState
    return L0_3
  end
  L0_2.getActionState = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.type = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setType = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.type
    return L0_3
  end
  L0_2.getType = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.vertices = A0_3
  end
  L0_2.setVertices = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.owner = A0_3
  end
  L0_2.setInteractOwner = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2.vertices
    L1_3 = L1_3[A0_3]
    if L1_3 then
      L1_3 = L0_2.vertices
      L1_3[A0_3] = nil
    end
  end
  L0_2.unloadVertice = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3
    if not A0_3 then
      return
    end
    L1_3 = CWZones
    L1_3 = L1_3[A0_3]
    if L1_3 then
      L2_3 = next
      L3_3 = L1_3
      L2_3 = L2_3(L3_3)
      if L2_3 then
        L2_3 = pairs
        L3_3 = L1_3
        L2_3, L3_3, L4_3, L5_3 = L2_3(L3_3)
        for L6_3, L7_3 in L2_3, L3_3, L4_3, L5_3 do
          L8_3 = L7_3.decal
          L9_3 = L7_3.entities
          if not L9_3 then
            L9_3 = L7_3.entities
            L9_3 = L9_3.entity
            if L9_3 then
              L10_3 = SetTimeout
              L11_3 = 0
              function L12_3()
                local L0_4, L1_4, L2_4, L3_4, L4_4
                L0_4 = DeleteStashOnGround
                L1_4 = A0_3
                L2_4 = L6_3
                L3_4 = L9_3
                L4_4 = true
                L0_4(L1_4, L2_4, L3_4, L4_4)
              end
              L10_3(L11_3, L12_3)
            end
            L10_3 = dbg
            L10_3 = L10_3.critical
            L11_3 = "COMS: Failed to found entities for zone with ID: %s"
            L12_3 = A0_3
            return L10_3(L11_3, L12_3)
          end
          if L8_3 then
            L9_3 = IsDecalAlive
            L10_3 = L8_3
            L9_3 = L9_3(L10_3)
            if L9_3 then
              L9_3 = RemoveDecal
              L10_3 = L8_3
              L9_3(L10_3)
            end
          end
          L9_3 = L0_2.unloadVertice
          L10_3 = L6_3
          L9_3(L10_3)
        end
      end
    end
    L2_3 = Wait
    L3_3 = 1000
    L2_3(L3_3)
    L2_3 = CWZones
    L2_3[A0_3] = nil
  end
  L0_2.unloadArea = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.models = A0_3
  end
  L0_2.setModels = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.renderMarker = A0_3
  end
  L0_2.setRenderMarker = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.wallState = A0_3
  end
  L0_2.setWallState = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.layerName = A0_3
  end
  L0_2.setLayerName = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.layerName
    return L0_3
  end
  L0_2.getLayerName = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.zonePlayers
    return L0_3
  end
  L0_2.getZonePlayers = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3
    if not A0_3 then
      return
    end
    L2_3 = L0_2.zonePlayers
    L3_3 = tostring
    L4_3 = A0_3
    L3_3 = L3_3(L4_3)
    L2_3[L3_3] = A1_3
  end
  L0_2.setZonePlayerState = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.zonePlayers = A0_3
  end
  L0_2.setZonePlayers = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.wallState
    return L0_3
  end
  L0_2.getWallState = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.reportState
    return L0_3
  end
  L0_2.getReportState = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.reportState = A0_3
  end
  L0_2.setReportState = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.playerJob = A0_3
  end
  L0_2.setPlayerCurrentJob = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.playerJob
    return L0_3
  end
  L0_2.getPlayerCurrentJob = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.zoneType = A0_3
  end
  L0_2.setZoneType = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.zoneType
    return L0_3
  end
  L0_2.getZoneType = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.interactHelpKeys = A0_3
  end
  L0_2.setInteractHelpKeys = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.interactHelpKeys
    return L0_3
  end
  L0_2.getInteractHelpKeys = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.position = A0_3
    L1_3 = L0_2.update
    L1_3()
    L1_3 = L0_2
    return L1_3
  end
  L0_2.setPosition = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.position
    return L0_3
  end
  L0_2.getPosition = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.dir = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setDir = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.dir
    return L0_3
  end
  L0_2.getDir = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.scale = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setScale = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.scale
    return L0_3
  end
  L0_2.getScale = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.color = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setColor = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.color
    return L0_3
  end
  L0_2.getColor = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2.color
    L1_3.a = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setAlpha = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.isBusy
    if L0_3 then
      L0_3 = 125
      return L0_3
    end
    L0_3 = L0_2.color
    L0_3 = L0_3.a
    return L0_3
  end
  L0_2.getAlpha = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2.color
    L1_3.r = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setRed = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.isBusy
    if L0_3 then
      L0_3 = 255
      return L0_3
    end
    L0_3 = L0_2.color
    L0_3 = L0_3.r
    return L0_3
  end
  L0_2.getRed = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2.color
    L1_3.g = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setGreen = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.isBusy
    if L0_3 then
      L0_3 = 0
      return L0_3
    end
    L0_3 = L0_2.color
    L0_3 = L0_3.g
    return L0_3
  end
  L0_2.getGreen = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2.color
    L1_3.b = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setBlue = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.isBusy
    if L0_3 then
      L0_3 = 0
      return L0_3
    end
    L0_3 = L0_2.color
    L0_3 = L0_3.b
    return L0_3
  end
  L0_2.getBlue = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.renderDistance = A0_3
    L1_3 = L0_2.update
    L1_3()
    L1_3 = L0_2
    return L1_3
  end
  L0_2.setRenderDistance = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.renderDistance
    return L0_3
  end
  L0_2.getRenderDistance = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.faceCamera = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setFaceCamera = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.faceCamera
    return L0_3
  end
  L0_2.getFaceCamera = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.rotation = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setRotation = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.rotation
    return L0_3
  end
  L0_2.getRotation = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.inRadius = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setInRadius = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.inRadius
    return L0_3
  end
  L0_2.getInRadius = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_2.stopRendering = false
    L0_2.rendering = true
    L0_2.firstUpdate = false
    L0_3 = L0_2.update
    L0_3()
    L0_3 = L0_2
    return L0_3
  end
  L0_2.render = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_2.stopRendering = true
    L0_2.rendering = false
    L0_3 = L0_2.update
    L0_3()
  end
  L0_2.stopRender = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_2.stopRendering = true
    L0_2.rendering = false
    L0_2.destroyed = true
    L0_3 = L0_2.update
    L1_3 = true
    L0_3(L1_3)
  end
  L0_2.destroy = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.isBusy = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.SetBusyStatus = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.isBusy
    return L0_3
  end
  L0_2.IsMarkerBusy = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.rendering
    return L0_3
  end
  L0_2.isRendering = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.syncData = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setSyncData = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.properties = A0_3
    L1_3 = L0_2.update
    L1_3()
  end
  L0_2.setBannerPreview = L1_2
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3
    L0_2.areaDebug = A0_3
    if A1_3 then
      L3_3 = L0_2.setType
      L4_3 = 28
      L3_3(L4_3)
    else
      L3_3 = L0_2.setType
      L4_3 = 1
      L3_3(L4_3)
    end
    if A1_3 then
      L3_3 = vector3
      L4_3 = 10
      L5_3 = 10
      L6_3 = 10
      L3_3 = L3_3(L4_3, L5_3, L6_3)
      L0_2.scale = L3_3
    elseif A2_3 then
      L3_3 = vector3
      L4_3 = A2_3
      L5_3 = A2_3
      L6_3 = A2_3
      L3_3 = L3_3(L4_3, L5_3, L6_3)
      L0_2.scale = L3_3
    else
      L3_3 = vector3
      L4_3 = Config
      L4_3 = L4_3.LOD
      L4_3 = L4_3.RENDER_DISTANCE_TOLERANCE
      L5_3 = Config
      L5_3 = L5_3.LOD
      L5_3 = L5_3.RENDER_DISTANCE_TOLERANCE
      L6_3 = Config
      L6_3 = L6_3.LOD
      L6_3 = L6_3.RENDER_DISTANCE_TOLERANCE
      L3_3 = L3_3(L4_3, L5_3, L6_3)
      L0_2.scale = L3_3
    end
    L3_3 = L0_2.update
    L3_3()
  end
  L0_2.setAreaDebug = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3, L3_3
    L2_3 = string
    L2_3 = L2_3.lower
    L3_3 = A0_3
    L2_3 = L2_3(L3_3)
    if "enter" == L2_3 then
      L0_2.onEnter = A1_3
    else
      L2_3 = string
      L2_3 = L2_3.lower
      L3_3 = A0_3
      L2_3 = L2_3(L3_3)
      if "leave" == L2_3 then
        L0_2.onLeave = A1_3
      else
        L2_3 = string
        L2_3 = L2_3.lower
        L3_3 = A0_3
        L2_3 = L2_3(L3_3)
        if "sync" == L2_3 then
          L0_2.onSync = A1_3
        elseif "enterPolygon" == A0_3 then
          L0_2.onEnterPolygon = A1_3
        elseif "leavePolygon" == A0_3 then
          L0_2.onLeavePolygon = A1_3
        end
      end
    end
    L2_3 = L0_2.update
    L2_3()
  end
  L0_2.on = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3
    L1_3 = L0_2.firstUpdate
    if L1_3 then
      return
    end
    if A0_3 then
      L1_3 = pairs
      L2_3 = NearWorldCOMS
      L1_3, L2_3, L3_3, L4_3 = L1_3(L2_3)
      for L5_3, L6_3 in L1_3, L2_3, L3_3, L4_3 do
        L7_3 = L6_3.getId
        L7_3 = L7_3()
        L8_3 = L0_2.getId
        L8_3 = L8_3()
        if L7_3 == L8_3 then
          L7_3 = NearWorldCOMS
          L7_3[L5_3] = nil
        end
      end
      L1_3 = pairs
      L2_3 = WorldCOMS
      L1_3, L2_3, L3_3, L4_3 = L1_3(L2_3)
      for L5_3, L6_3 in L1_3, L2_3, L3_3, L4_3 do
        L7_3 = L6_3.getId
        L7_3 = L7_3()
        L8_3 = L0_2.getId
        L8_3 = L8_3()
        if L7_3 == L8_3 then
          L7_3 = WorldCOMS
          L7_3[L5_3] = nil
        end
      end
    else
      L1_3 = pairs
      L2_3 = WorldCOMS
      L1_3, L2_3, L3_3, L4_3 = L1_3(L2_3)
      for L5_3, L6_3 in L1_3, L2_3, L3_3, L4_3 do
        L7_3 = L6_3.getId
        L7_3 = L7_3()
        L8_3 = L0_2.getId
        L8_3 = L8_3()
        if L7_3 == L8_3 then
          L7_3 = WorldCOMS
          L7_3[L5_3] = L6_3
        end
      end
    end
  end
  L0_2.update = L1_2
  L1_2 = table
  L1_2 = L1_2.insert
  L2_2 = WorldCOMS
  L3_2 = L0_2
  L1_2(L2_2, L3_2)
  return L0_2
end
CreateCOMSZone = L5_1
L5_1 = AddEventHandler
L6_1 = "onResourceStop"
function L7_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = pairs
  L2_2 = WorldCOMS
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = L6_2.resource
    if L7_2 == A0_2 then
      L7_2 = L6_2.unloadArea
      L8_2 = L6_2.id
      L7_2(L8_2)
      L7_2 = L6_2.destroy
      L7_2()
    end
  end
  L1_2 = Entity
  L1_2 = L1_2.cache
  if L1_2 then
    L1_2 = next
    L2_2 = Entity
    L2_2 = L2_2.cache
    L1_2 = L1_2(L2_2)
    if L1_2 then
      L1_2 = pairs
      L2_2 = Entity
      L2_2 = L2_2.cache
      L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
      for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
        L7_2 = L6_2.entity
        L8_2 = DoesEntityExist
        L9_2 = L7_2
        L8_2 = L8_2(L9_2)
        if L8_2 then
          L8_2 = DeleteEntity
          L9_2 = L7_2
          L8_2(L9_2)
        end
      end
    end
  end
end
L5_1(L6_1, L7_1)
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = ClearAreaOfObjects
  L3_2 = A0_2.x
  L4_2 = A0_2.y
  L5_2 = A0_2.z
  L6_2 = A1_2 or L6_2
  if not A1_2 then
    L6_2 = 1
  end
  L7_2 = 0
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2)
  L2_2 = RemoveDecalsInRange
  L3_2 = A0_2.x
  L4_2 = A0_2.y
  L5_2 = A0_2.z
  L6_2 = A1_2
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
CleanZone = L5_1
function L5_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if A0_2 then
    L4_2 = table
    L4_2 = L4_2.size
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    if L4_2 < 0 then
      L4_2 = dbg
      L4_2 = L4_2.critical
      L5_2 = "Cannot register COMS zone, no data provided!!!"
      return L4_2(L5_2)
    end
  end
  if A0_2 then
    L4_2 = pairs
    L5_2 = A0_2
    L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
    for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
      L10_2 = zones
      L10_2 = L10_2.poly
      L11_2 = {}
      L12_2 = L9_2.pos
      L11_2.pos = L12_2
      L12_2 = L9_2.vertices
      L11_2.points = L12_2
      L11_2.modelsPreset = A1_2
      L11_2.spawnTrashEntities = true
      L11_2.decals = true
      L11_2.size = 4.0
      L11_2.zoneIdx = A2_2
      L11_2.owner = A3_2
      L10_2 = L10_2(L11_2)
      L11_2 = Wait
      L12_2 = 100
      L11_2(L12_2)
    end
  end
end
RegisterZoneCOMS = L5_1
function L5_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L3_2 = nil
  L4_2 = math
  L4_2 = L4_2.sqrt
  L5_2 = A0_2 * A0_2
  L6_2 = A1_2 * A1_2
  L5_2 = L5_2 + L6_2
  L6_2 = A2_2 * A2_2
  L5_2 = L5_2 + L6_2
  L4_2 = L4_2(L5_2)
  L5_2 = nil
  if 0.0 ~= L4_2 then
    L6_2 = 1.0
    L3_2 = L6_2 / L4_2
    L6_2 = vector3
    L7_2 = A0_2
    L8_2 = A1_2
    L9_2 = A2_2
    L6_2 = L6_2(L7_2, L8_2, L9_2)
    L7_2 = vector3
    L8_2 = L3_2
    L9_2 = L3_2
    L10_2 = L3_2
    L7_2 = L7_2(L8_2, L9_2, L10_2)
    L5_2 = L6_2 * L7_2
  end
  L6_2 = L5_2 or L6_2
  if not L5_2 then
    L6_2 = vector3
    L7_2 = 0.0
    L8_2 = 0.0
    L9_2 = 0.0
    L6_2 = L6_2(L7_2, L8_2, L9_2)
  end
  return L6_2
end
func_522 = L5_1
function L5_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L0_2 = PlayerPedId
  L0_2 = L0_2()
  L1_2 = GetEntityCoords
  L2_2 = L0_2
  L1_2 = L1_2(L2_2)
  L2_2 = nil
  L3_2 = L1_1.zoneId
  if not L3_2 then
    return L2_2
  end
  L3_2 = CWZones
  L4_2 = L1_1.zoneId
  L3_2 = L3_2[L4_2]
  L4_2 = pairs
  L5_2 = L3_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = L9_2.coords
    L10_2 = L10_2 - L1_2
    L10_2 = #L10_2
    L11_2 = L9_2.state
    if not L11_2 then
      L11_2 = 1.5
      if L10_2 <= L11_2 then
        L2_2 = L8_2
        break
      end
    end
  end
  return L2_2
end
GetClosestPolygon = L5_1
function L5_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2
  L0_2 = L1_1
  if L0_2 then
    L0_2 = next
    L1_2 = L1_1
    L0_2 = L0_2(L1_2)
    if L0_2 then
      L0_2 = L1_1.owner
      if L0_2 then
        L0_2 = L1_1.owner
        L1_2 = MyServerId
        if L0_2 ~= L1_2 then
          L0_2 = dbg
          L0_2 = L0_2.debug
          L1_2 = "Cannot start interaction, not owner"
          return L0_2(L1_2)
        end
      end
      L0_2 = IsInVehicle
      L0_2 = L0_2()
      if L0_2 then
        L0_2 = dbg
        L0_2 = L0_2.debug
        L1_2 = "Cannot start interaction while in vehicle"
        return L0_2(L1_2)
      end
      L0_2 = L2_1
      if L0_2 then
        L0_2 = dbg
        L0_2 = L0_2.debug
        L1_2 = "Cannot start interaction, already sweeping"
        return L0_2(L1_2)
      end
      L0_2 = HelpKeys
      L0_2 = L0_2.Hide
      L0_2()
      L0_2 = GetClosestPolygon
      L0_2 = L0_2()
      L1_2 = L1_1.verticeId
      if L0_2 ~= L1_2 then
        L1_1.verticeId = L0_2
      end
      L1_2 = L1_1.verticeId
      if not L1_2 then
        return
      end
      if not L0_2 then
        L1_2 = false
        L2_1 = L1_2
        L1_2 = Framework
        L1_2 = L1_2.sendNotification
        L2_2 = "You are not near any trash"
        L3_2 = "error"
        return L1_2(L2_2, L3_2)
      end
      L1_2 = true
      L2_1 = L1_2
      L1_2 = "prop_tool_broom"
      L2_2 = PlayerPedId
      L2_2 = L2_2()
      L3_2 = vec3
      L4_2 = 0.0
      L5_2 = 0.0
      L6_2 = -5.0
      L3_2 = L3_2(L4_2, L5_2, L6_2)
      L4_2 = Config
      L4_2 = L4_2.COMS
      L4_2 = L4_2.DisableGameControls
      if L4_2 then
        L4_2 = FreezePlayer
        L5_2 = PlayerId
        L5_2 = L5_2()
        L6_2 = true
        L4_2(L5_2, L6_2)
      end
      L4_2 = FreezeEntityPosition
      L5_2 = L2_2
      L6_2 = true
      L4_2(L5_2, L6_2)
      L4_2 = GetOffsetFromEntityInWorldCoords
      L5_2 = L2_2
      L6_2 = L3_2.x
      L7_2 = L3_2.y
      L8_2 = L3_2.z
      L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2)
      L5_2 = CreateObject
      L6_2 = joaat
      L7_2 = L1_2
      L6_2 = L6_2(L7_2)
      L7_2 = L4_2.x
      L8_2 = L4_2.y
      L9_2 = L4_2.z
      L10_2 = true
      L11_2 = false
      L12_2 = false
      L5_2 = L5_2(L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
      L6_2 = LoadAnim
      L7_2 = "amb@world_human_janitor@male@idle_a"
      L6_2(L7_2)
      L6_2 = TaskPlayAnim
      L7_2 = L2_2
      L8_2 = "amb@world_human_janitor@male@idle_a"
      L9_2 = "idle_a"
      L10_2 = 8.0
      L11_2 = -8.0
      L12_2 = -1
      L13_2 = 0
      L14_2 = 0
      L15_2 = false
      L16_2 = false
      L17_2 = false
      L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2)
      L6_2 = AttachEntityToEntity
      L7_2 = L5_2
      L8_2 = L2_2
      L9_2 = GetPedBoneIndex
      L10_2 = L2_2
      L11_2 = 28422
      L9_2 = L9_2(L10_2, L11_2)
      L10_2 = -0.005
      L11_2 = 0.0
      L12_2 = 0.0
      L13_2 = 360.0
      L14_2 = 360.0
      L15_2 = 0.0
      L16_2 = true
      L17_2 = true
      L18_2 = false
      L19_2 = true
      L20_2 = false
      L21_2 = true
      L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2)
      L6_2 = SetTimeout
      L7_2 = Config
      L7_2 = L7_2.COMS
      L7_2 = L7_2.CleaningAnimTime
      function L8_2()
        local L0_3, L1_3, L2_3, L3_3
        L0_3 = Config
        L0_3 = L0_3.COMS
        L0_3 = L0_3.DisableGameControls
        if L0_3 then
          L0_3 = FreezePlayer
          L1_3 = PlayerId
          L1_3 = L1_3()
          L2_3 = false
          L0_3(L1_3, L2_3)
        end
        L0_3 = FreezeEntityPosition
        L1_3 = L2_2
        L2_3 = false
        L0_3(L1_3, L2_3)
        L0_3 = DetachEntity
        L1_3 = L5_2
        L2_3 = true
        L3_3 = true
        L0_3(L1_3, L2_3, L3_3)
        L0_3 = DeleteEntity
        L1_3 = L5_2
        L0_3(L1_3)
        L0_3 = ClearPedTasks
        L1_3 = L2_2
        L0_3(L1_3)
        L0_3 = false
        L2_1 = L0_3
        L0_3 = TriggerServerEvent
        L1_3 = "rcore_prison:server:requestRemoveVertice"
        L2_3 = L1_1
        L0_3(L1_3, L2_3)
      end
      L6_2(L7_2, L8_2)
    end
  end
end
StartInteract = L5_1
function L5_1()
  local L0_2, L1_2, L2_2
  L0_2 = PlayerPedId
  L0_2 = L0_2()
  L1_2 = GetVehiclePedIsIn
  L2_2 = L0_2
  L1_2 = L1_2(L2_2)
  if L1_2 > 0 then
    L1_2 = true
    if L1_2 then
      goto lbl_12
    end
  end
  L1_2 = false
  ::lbl_12::
  return L1_2
end
IsInVehicle = L5_1
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = SetPlayerControl
  L3_2 = A0_2
  L4_2 = not A1_2
  L5_2 = false
  L2_2(L3_2, L4_2, L5_2)
end
FreezePlayer = L5_1
function L5_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2
  L4_2 = CWZones
  L4_2 = L4_2[A0_2]
  if L4_2 then
    L4_2 = CWZones
    L4_2 = L4_2[A0_2]
    L4_2 = L4_2[A1_2]
    if L4_2 then
      L4_2 = CWZones
      L4_2 = L4_2[A0_2]
      L4_2[A1_2] = nil
    end
  end
  if A3_2 then
    L4_2 = SetEntityDrawOutline
    L5_2 = A2_2
    L6_2 = false
    L4_2(L5_2, L6_2)
    L4_2 = DeleteEntity
    L5_2 = A2_2
    L4_2(L5_2)
    return
  end
  L4_2 = 255
  while L4_2 >= 0 do
    L5_2 = Wait
    L6_2 = 10
    L5_2(L6_2)
    L5_2 = SetEntityAlpha
    L6_2 = A2_2
    L7_2 = L4_2
    L8_2 = false
    L5_2(L6_2, L7_2, L8_2)
    L4_2 = L4_2 - 12
  end
  L5_2 = Wait
  L6_2 = 5000
  L5_2(L6_2)
  L5_2 = SetEntityDrawOutline
  L6_2 = A2_2
  L7_2 = false
  L5_2(L6_2, L7_2)
  L5_2 = DeleteEntity
  L6_2 = A2_2
  L5_2(L6_2)
end
DeleteStashOnGround = L5_1
function L5_1(A0_2)
  local L1_2, L2_2
  L1_2 = RequestModel
  L2_2 = A0_2
  L1_2(L2_2)
  while true do
    L1_2 = HasModelLoaded
    L2_2 = A0_2
    L1_2 = L1_2(L2_2)
    if L1_2 then
      break
    end
    L1_2 = Wait
    L2_2 = 0
    L1_2(L2_2)
  end
end
LoadModel = L5_1
L5_1 = RegisterCommand
L6_1 = "rcore_prison_coms_debug"
function L7_1()
  local L0_2, L1_2, L2_2, L3_2
  L0_2 = L1_1
  if L0_2 then
    L0_2 = next
    L1_2 = L1_1
    L0_2 = L0_2(L1_2)
    if L0_2 then
      L0_2 = PlayerPedId
      L0_2 = L0_2()
      L1_2 = GetEntityCoords
      L2_2 = L0_2
      L1_2 = L1_2(L2_2)
      L1_1.Coords = L1_2
      L2_2 = tprint
      L3_2 = L1_1
      L2_2(L3_2)
  end
  else
    L0_2 = dbg
    L0_2 = L0_2.debug
    L1_2 = "COMS: Failed to find any active player current session!"
    L0_2(L1_2)
  end
end
L5_1(L6_1, L7_1)
function L5_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = A0_2.idx
  L2_2 = CreateCOMSZone
  L2_2 = L2_2()
  L3_2 = A0_2.zonePos
  L4_2 = L2_2.setPosition
  L5_2 = L3_2
  L4_2(L5_2)
  L4_2 = L2_2.setModels
  L5_2 = A0_2.models
  L4_2(L5_2)
  L4_2 = L2_2.setVertices
  L5_2 = A0_2.vertices
  L4_2(L5_2)
  L4_2 = L2_2.setId
  L5_2 = L1_2
  L4_2(L5_2)
  L4_2 = L2_2.setInteractOwner
  L5_2 = A0_2.owner
  L4_2(L5_2)
  L4_2 = A0_2.owner
  L5_2 = MyServerId
  if L4_2 == L5_2 then
    L4_2 = A0_2.owner
    L1_1.owner = L4_2
  end
  L4_2 = L2_2.render
  L4_2()
  L4_2 = L2_2.on
  L5_2 = "enterPolygon"
  function L6_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3
    L0_3 = L2_2.owner
    L1_3 = MyServerId
    if L0_3 == L1_3 then
      L0_3 = HelpKeys
      L0_3 = L0_3.Show
      L1_3 = {}
      L2_3 = {}
      L2_3.keyName = "E"
      L3_3 = _U
      L4_3 = "START_CLEANING_LABEL"
      L3_3 = L3_3(L4_3)
      L2_3.label = L3_3
      L1_3[1] = L2_3
      L0_3(L1_3)
      L0_3 = L2_2.verticeId
      L1_1.verticeId = L0_3
    end
  end
  L4_2(L5_2, L6_2)
  L4_2 = L2_2.on
  L5_2 = "leavePolygon"
  function L6_2()
    local L0_3, L1_3
    L0_3 = L2_2.owner
    L1_3 = MyServerId
    if L0_3 == L1_3 then
      L0_3 = HelpKeys
      L0_3 = L0_3.Hide
      L0_3()
      L1_1.verticeId = nil
    end
  end
  L4_2(L5_2, L6_2)
  L4_2 = L2_2.on
  L5_2 = "leave"
  function L6_2()
    local L0_3, L1_3, L2_3
    L0_3 = L2_2.owner
    L1_3 = MyServerId
    if L0_3 == L1_3 then
      L1_1.zoneId = nil
    end
    L0_3 = dbg
    L0_3 = L0_3.debug
    L1_3 = "You left COMS active area, unloading."
    L2_3 = L1_2
    L0_3(L1_3, L2_3)
    L0_3 = Config
    L0_3 = L0_3.COMS
    L0_3 = L0_3.Area
    if L0_3 then
      L0_3 = Config
      L0_3 = L0_3.COMS
      L0_3 = L0_3.Area
      L0_3 = L0_3.EnableDynamicUnload
      if L0_3 then
        L0_3 = L2_2.unloadArea
        L1_3 = L1_2
        L0_3(L1_3)
      end
    end
  end
  L4_2(L5_2, L6_2)
  L4_2 = L2_2.on
  L5_2 = "enter"
  function L6_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3
    L0_3 = L2_2.owner
    L1_3 = MyServerId
    if L0_3 == L1_3 then
      L0_3 = L1_2
      L1_1.zoneId = L0_3
    end
    L0_3 = dbg
    L0_3 = L0_3.debug
    L1_3 = "Entered active COMS area with zoneId: %s %s %s"
    L2_3 = L1_2
    L3_3 = L2_2.owner
    L4_3 = MyServerId
    L0_3(L1_3, L2_3, L3_3, L4_3)
    L0_3 = RegisterZoneCOMS
    L1_3 = L2_2.vertices
    L2_3 = L2_2.models
    L3_3 = L1_2
    L4_3 = L2_2.owner
    L0_3(L1_3, L2_3, L3_3, L4_3)
  end
  L4_2(L5_2, L6_2)
end
RegisterCOMSArea = L5_1
L5_1 = RegisterKey
L6_1 = StartInteract
L7_1 = "START_INTERACT_COMS"
L8_1 = "Interact COMS"
L9_1 = Config
L9_1 = L9_1.COMS
L9_1 = L9_1.InteractKey
L5_1(L6_1, L7_1, L8_1, L9_1)
