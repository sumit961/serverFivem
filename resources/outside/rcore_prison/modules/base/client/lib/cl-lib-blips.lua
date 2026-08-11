local L0_1, L1_1
L0_1 = {}
L1_1 = {}
L0_1.Cache = L1_1
Blips = L0_1
L0_1 = Blips
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  if not A0_2 then
    L1_2 = dbg
    L1_2 = L1_2.debug
    L2_2 = "Invalid position for waypoint!"
    return L1_2(L2_2)
  end
  L1_2 = SetNewWaypoint
  L2_2 = A0_2.x
  L3_2 = A0_2.y
  L1_2(L2_2, L3_2)
end
L0_1.SetWaypoint = L1_1
L0_1 = Blips
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = Blips
  L1_2 = L1_2.Cache
  if L1_2 then
    L1_2 = next
    L2_2 = Blips
    L2_2 = L2_2.Cache
    L1_2 = L1_2(L2_2)
    if L1_2 then
      L1_2 = pairs
      L2_2 = Blips
      L2_2 = L2_2.Cache
      L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
      for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
        L7_2 = L6_2.type
        if L7_2 == A0_2 then
          L7_2 = RemoveBlip
          L8_2 = L5_2
          L7_2(L8_2)
          L7_2 = Blips
          L7_2 = L7_2.Cache
          L7_2[L5_2] = nil
        end
      end
    end
  end
end
L0_1.RemoveByType = L1_1
L0_1 = Blips
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = Blips
  L1_2 = L1_2.Cache
  if L1_2 then
    L1_2 = next
    L2_2 = Blips
    L2_2 = L2_2.Cache
    L1_2 = L1_2(L2_2)
    if L1_2 then
      L1_2 = pairs
      L2_2 = Blips
      L2_2 = L2_2.Cache
      L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
      for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
        L7_2 = L6_2.zoneId
        if L7_2 == A0_2 then
          L7_2 = RemoveBlip
          L8_2 = L6_2.id
          L7_2(L8_2)
          L7_2 = Blips
          L7_2 = L7_2.Cache
          L7_2[L5_2] = nil
          L7_2 = dbg
          L7_2 = L7_2.debug
          L8_2 = "Blip removed: %s %s"
          L9_2 = A0_2
          L10_2 = L6_2.id
          L7_2(L8_2, L9_2, L10_2)
        end
      end
    end
  end
end
L0_1.RemoveById = L1_1
L0_1 = Blips
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = A0_2.sprite
  if not L1_2 then
    return
  end
  L1_2 = AddBlipForCoord
  L2_2 = A0_2.coords
  L2_2 = L2_2.x
  L3_2 = A0_2.coords
  L3_2 = L3_2.y
  L1_2 = L1_2(L2_2, L3_2)
  L2_2 = Blips
  L2_2 = L2_2.Cache
  L2_2 = L2_2[L1_2]
  if not L2_2 then
    L2_2 = Blips
    L2_2 = L2_2.Cache
    L3_2 = {}
    L3_2.id = L1_2
    L4_2 = A0_2.zoneId
    L3_2.zoneId = L4_2
    L4_2 = A0_2.type
    L3_2.type = L4_2
    L2_2[L1_2] = L3_2
  end
  L2_2 = SetBlipDisplay
  L3_2 = L1_2
  L4_2 = 4
  L2_2(L3_2, L4_2)
  L2_2 = SetBlipSprite
  L3_2 = L1_2
  L4_2 = A0_2.sprite
  L2_2(L3_2, L4_2)
  L2_2 = SetBlipScale
  L3_2 = L1_2
  L4_2 = A0_2.scale
  L2_2(L3_2, L4_2)
  L2_2 = SetBlipColour
  L3_2 = L1_2
  L4_2 = A0_2.color
  L2_2(L3_2, L4_2)
  L2_2 = SetTextFont
  L3_2 = 1
  L2_2(L3_2)
  L2_2 = SetBlipAsShortRange
  L3_2 = L1_2
  L4_2 = true
  L2_2(L3_2, L4_2)
  L2_2 = BeginTextCommandSetBlipName
  L3_2 = "STRING"
  L2_2(L3_2)
  L2_2 = AddTextComponentSubstringPlayerName
  L3_2 = A0_2.name
  L2_2(L3_2)
  L2_2 = EndTextCommandSetBlipName
  L3_2 = L1_2
  L2_2(L3_2)
end
L0_1.Create = L1_1
L0_1 = Blips
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  if not A0_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Invalid position for squared area blip!"
    return L2_2(L3_2)
  end
  L2_2 = AddBlipForRadius
  L3_2 = A0_2.x
  L4_2 = A0_2.y
  L5_2 = A0_2.z
  L6_2 = 30.0
  L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
  L3_2 = ShowHeadingIndicatorOnBlip
  L4_2 = L2_2
  L5_2 = true
  L3_2(L4_2, L5_2)
  L3_2 = SetBlipSquaredRotation
  L4_2 = L2_2
  L5_2 = 90.0
  L3_2(L4_2, L5_2)
  L3_2 = SetBlipRotation
  L4_2 = L2_2
  L5_2 = math
  L5_2 = L5_2.ceil
  L6_2 = GetEntityHeading
  L7_2 = PlayerPedId
  L7_2 = L7_2()
  L6_2, L7_2 = L6_2(L7_2)
  L5_2, L6_2, L7_2 = L5_2(L6_2, L7_2)
  L3_2(L4_2, L5_2, L6_2, L7_2)
  L3_2 = SetBlipColour
  L4_2 = L2_2
  L5_2 = 0
  L3_2(L4_2, L5_2)
  L3_2 = SetBlipAlpha
  L4_2 = L2_2
  L5_2 = 80
  L3_2(L4_2, L5_2)
  L3_2 = Blips
  L3_2 = L3_2.Cache
  L3_2 = L3_2[L2_2]
  if not L3_2 then
    L3_2 = Blips
    L3_2 = L3_2.Cache
    L4_2 = {}
    L4_2.id = L2_2
    L5_2 = A1_2 or L5_2
    if not A1_2 then
      L5_2 = "COMS"
    end
    L4_2.type = L5_2
    L3_2[L2_2] = L4_2
  end
end
L0_1.CreateSquaredArea = L1_1
