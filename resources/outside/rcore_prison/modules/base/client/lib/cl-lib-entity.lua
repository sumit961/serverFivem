local L0_1, L1_1, L2_1, L3_1
L0_1 = {}
L1_1 = {}
L0_1.cache = L1_1
Entity = L0_1
L0_1 = false
L1_1 = false
L2_1 = Entity
function L3_1()
  local L0_2, L1_2
end
L2_1.RefreshArea = L3_1
L2_1 = Entity
function L3_1(A0_2)
  local L1_2
end
L2_1.SpawnNPCAtCoords = L3_1
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2
  L3_2 = {}
  L4_2 = A2_2 or L4_2
  if not A2_2 then
    L4_2 = math
    L4_2 = L4_2.random
    L5_2 = 3
    L6_2 = 6
    L4_2 = L4_2(L5_2, L6_2)
  end
  L5_2 = math
  L5_2 = L5_2.pi
  L5_2 = 2 * L5_2
  L5_2 = L5_2 / L4_2
  L6_2 = 0
  L7_2 = L4_2 - 1
  L8_2 = 1
  for L9_2 = L6_2, L7_2, L8_2 do
    L10_2 = L9_2 * L5_2
    L11_2 = math
    L11_2 = L11_2.cos
    L12_2 = L10_2
    L11_2 = L11_2(L12_2)
    L11_2 = L11_2 * A1_2
    L12_2 = math
    L12_2 = L12_2.sin
    L13_2 = L10_2
    L12_2 = L12_2(L13_2)
    L12_2 = L12_2 * A1_2
    L13_2 = table
    L13_2 = L13_2.insert
    L14_2 = L3_2
    L15_2 = {}
    L16_2 = A0_2.x
    L16_2 = L16_2 + L11_2
    L15_2.x = L16_2
    L16_2 = A0_2.y
    L16_2 = L16_2 + L12_2
    L15_2.y = L16_2
    L16_2 = A0_2.z
    L15_2.z = L16_2
    L13_2(L14_2, L15_2)
  end
  return L3_2
end
generateCirclePositions = L2_1
L2_1 = Entity
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if not A0_2 then
    return
  end
  L1_2 = IsModelInCdimage
  L2_2 = A0_2.model
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L1_2 = A0_2.model
  L2_2 = A0_2.coords
  L3_2 = A0_2.heading
  L4_2 = A0_2.invisible
  if L4_2 then
    L4_2 = false
    L0_1 = L4_2
    L4_2 = false
    L1_1 = L4_2
  end
  while true do
    L4_2 = HasModelLoaded
    L5_2 = L1_2
    L4_2 = L4_2(L5_2)
    if L4_2 then
      break
    end
    L4_2 = RequestModel
    L5_2 = L1_2
    L4_2(L5_2)
    L4_2 = Wait
    L5_2 = 100
    L4_2(L5_2)
  end
  if "sf_prop_sf_phonebox_01b_s" == L1_2 then
    L3_2 = 0
  end
  L4_2 = nil
  if "sf_prop_sf_phonebox_01b_s" == L1_2 then
    L5_2 = CreateObject
    L6_2 = L1_2
    L7_2 = L2_2.x
    L8_2 = L2_2.y
    L9_2 = L2_2.z
    L9_2 = L9_2 - 1.3
    L10_2 = L0_1
    L11_2 = L1_1
    L12_2 = true
    L5_2 = L5_2(L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
    L4_2 = L5_2
  else
    L5_2 = CreateObjectNoOffset
    L6_2 = L1_2
    L7_2 = L2_2.x
    L8_2 = L2_2.y
    L9_2 = L2_2.z
    L10_2 = L0_1
    L11_2 = L1_1
    L12_2 = true
    L5_2 = L5_2(L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
    L4_2 = L5_2
  end
  L5_2 = 0
  while true do
    L6_2 = DoesEntityExist
    L7_2 = L4_2
    L6_2 = L6_2(L7_2)
    if L6_2 then
      break
    end
    L6_2 = Wait
    L7_2 = 1
    L6_2(L7_2)
    L5_2 = L5_2 + 1
    L6_2 = 200
    if L5_2 >= L6_2 then
      L6_2 = dbg
      L6_2 = L6_2.critical
      L7_2 = "Failed to spawn entity in cl-lib-entity.lua"
      L6_2(L7_2)
      break
    end
  end
  L6_2 = Entity
  L6_2 = L6_2.cache
  L7_2 = {}
  L7_2.entity = L4_2
  L6_2[L4_2] = L7_2
  L6_2 = Wait
  L7_2 = 0
  L6_2(L7_2)
  L6_2 = SetEntityHeading
  L7_2 = L4_2
  L8_2 = L3_2 or L8_2
  if not L3_2 then
    L8_2 = 0
  end
  L6_2(L7_2, L8_2)
  L6_2 = SetEntityRotation
  L7_2 = L4_2
  L8_2 = 0
  L9_2 = 0
  L10_2 = L3_2 or L10_2
  if not L3_2 then
    L10_2 = 0
  end
  L11_2 = 2
  L12_2 = true
  L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
  L6_2 = SetEntityCanBeDamaged
  L7_2 = L4_2
  L8_2 = false
  L6_2(L7_2, L8_2)
  L6_2 = A0_2.invisible
  if L6_2 then
    L6_2 = Config
    L6_2 = L6_2.PrisonJobs
    L6_2 = L6_2.TargetHighlight
    if L6_2 then
      L6_2 = Config
      L6_2 = L6_2.PrisonJobs
      L6_2 = L6_2.TargetHiglightColor
      if not L6_2 then
        L6_2 = {}
        L7_2 = 50
        L8_2 = 149
        L9_2 = 1
        L10_2 = 255
        L6_2[1] = L7_2
        L6_2[2] = L8_2
        L6_2[3] = L9_2
        L6_2[4] = L10_2
      end
      L7_2 = SetEntityAlpha
      L8_2 = L4_2
      L9_2 = 50
      L10_2 = true
      L7_2(L8_2, L9_2, L10_2)
      L7_2 = SetEntityDrawOutline
      L8_2 = L4_2
      L9_2 = true
      L7_2(L8_2, L9_2)
      L7_2 = SetEntityDrawOutlineColor
      L8_2 = L6_2.r
      L9_2 = L6_2.g
      L10_2 = L6_2.b
      L11_2 = L6_2.a
      L7_2(L8_2, L9_2, L10_2, L11_2)
      L7_2 = SetEntityDrawOutlineShader
      L8_2 = 1
      L7_2(L8_2)
      L7_2 = SetEntityCollision
      L8_2 = L4_2
      L9_2 = false
      L10_2 = false
      L7_2(L8_2, L9_2, L10_2)
      L7_2 = SetEntityCoords
      L8_2 = L4_2
      L9_2 = L2_2.x
      L10_2 = L2_2.y
      L11_2 = L2_2.z
      L11_2 = L11_2 - 1
      L7_2(L8_2, L9_2, L10_2, L11_2)
    end
  end
  if "sf_prop_sf_phonebox_01b_s" ~= L1_2 then
    L6_2 = PlaceObjectOnGroundProperly
    L7_2 = L4_2
    L6_2(L7_2)
  end
  L6_2 = FreezeEntityPosition
  L7_2 = L4_2
  L8_2 = true
  L6_2(L7_2, L8_2)
  L6_2 = SetModelAsNoLongerNeeded
  L7_2 = L1_2
  L6_2(L7_2)
  return L4_2
end
L2_1.SpawnPropAtCoords = L3_1
