local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1
L0_1 = 1
L1_1 = {}
L2_1 = {}
L3_1 = {}
L4_1 = {}
function L5_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = L0_1
  L1_2 = L1_2 + 1
  L0_1 = L1_2
  if A0_2 then
    L1_2 = "rcore_prison_target_"
    L2_2 = L0_1
    L3_2 = "_"
    L4_2 = A0_2
    L1_2 = L1_2 .. L2_2 .. L3_2 .. L4_2
    return L1_2
  end
  L1_2 = "rcore_prison_target_"
  L2_2 = L0_1
  L1_2 = L1_2 .. L2_2
  return L1_2
end
function L6_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L0_2 = L4_1
  if L0_2 then
    L0_2 = next
    L1_2 = L4_1
    L0_2 = L0_2(L1_2)
    if L0_2 then
      L0_2 = pairs
      L1_2 = L4_1
      L0_2, L1_2, L2_2, L3_2 = L0_2(L1_2)
      for L4_2, L5_2 in L0_2, L1_2, L2_2, L3_2 do
        L6_2 = DoesEntityExist
        L7_2 = L5_2
        L6_2 = L6_2(L7_2)
        if L6_2 then
          L6_2 = SetEntityAsNoLongerNeeded
          L7_2 = L5_2
          L6_2(L7_2)
          L6_2 = SetEntityDrawOutline
          L7_2 = L5_2
          L8_2 = false
          L6_2(L7_2, L8_2)
          L6_2 = DeleteEntity
          L7_2 = L5_2
          L6_2(L7_2)
          L6_2 = L4_1
          L6_2[L4_2] = nil
        end
      end
    end
  end
end
RemoveTargetEntityHiglight = L6_1
function L6_1(A0_2, A1_2, A2_2, A3_2, A4_2, A5_2, A6_2, A7_2)
  local L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2
  L8_2 = Config
  L8_2 = L8_2.Interactions
  L9_2 = L5_1
  L10_2 = A5_2
  L9_2 = L9_2(L10_2)
  L10_2 = L3_1
  L10_2 = L10_2[L9_2]
  if not L10_2 then
    L10_2 = L3_1
    L10_2[L9_2] = true
  end
  L10_2 = {}
  L11_2 = Interactions
  L11_2 = L11_2.Q
  L10_2[L11_2] = true
  L11_2 = Interactions
  L11_2 = L11_2.QB
  L10_2[L11_2] = true
  L11_2 = Interactions
  L11_2 = L11_2.MV
  L10_2[L11_2] = true
  if A6_2 then
    L11_2 = Entity
    L11_2 = L11_2.SpawnPropAtCoords
    L12_2 = {}
    L12_2.coords = A0_2
    L12_2.heading = A3_2
    L12_2.model = "prop_rub_cardpile_06"
    L12_2.invisible = A6_2
    L11_2 = L11_2(L12_2)
    if L11_2 then
      L12_2 = L4_1
      L12_2 = L12_2[L9_2]
      if not L12_2 then
        L12_2 = L4_1
        L12_2[L9_2] = L11_2
      end
    end
  end
  L11_2 = Interactions
  L11_2 = L11_2.OX
  if L8_2 == L11_2 then
    L11_2 = vector3
    L12_2 = A0_2.x
    L13_2 = A0_2.y
    L14_2 = A0_2.z
    L14_2 = L14_2 - 0.5
    L11_2 = L11_2(L12_2, L13_2, L14_2)
    A0_2 = L11_2
    L11_2 = exports
    L11_2 = L11_2.ox_target
    L12_2 = L11_2
    L11_2 = L11_2.addBoxZone
    L13_2 = {}
    L13_2.name = L9_2
    L13_2.coords = A0_2
    L14_2 = vector3
    L15_2 = A2_2
    L16_2 = A1_2
    L17_2 = 2.0
    L14_2 = L14_2(L15_2, L16_2, L17_2)
    L13_2.size = L14_2
    L13_2.rotation = A3_2
    L13_2.debug = false
    L14_2 = A0_2.z
    L14_2 = L14_2 - A1_2
    L13_2.minZ = L14_2
    L14_2 = A0_2.z
    L14_2 = L14_2 + A1_2
    L13_2.maxZ = L14_2
    L13_2.options = A4_2
    L14_2 = A7_2 or L14_2
    if not A7_2 then
      L14_2 = 5.0
    end
    L13_2.distance = L14_2
    L11_2 = L11_2(L12_2, L13_2)
    L12_2 = L2_1
    L13_2 = {}
    L13_2.name = L9_2
    L12_2[L11_2] = L13_2
  else
    L11_2 = Interactions
    L11_2 = L11_2.IS
    if L8_2 == L11_2 then
      L11_2 = {}
      L12_2 = pairs
      L13_2 = A4_2
      L12_2, L13_2, L14_2, L15_2 = L12_2(L13_2)
      for L16_2, L17_2 in L12_2, L13_2, L14_2, L15_2 do
        L18_2 = table
        L18_2 = L18_2.insert
        L19_2 = L11_2
        L20_2 = {}
        L21_2 = "option_"
        L22_2 = L17_2.num
        L21_2 = L21_2 .. L22_2
        L20_2.name = L21_2
        L21_2 = L17_2.label
        L20_2.label = L21_2
        L21_2 = L17_2.icon
        L20_2.icon = L21_2
        L20_2.key = ""
        L20_2.duration = 500
        function L21_2()
          local L0_3, L1_3
          L0_3 = L17_2.type
          if "client" == L0_3 then
            L0_3 = TriggerEvent
            L1_3 = L17_2.event
            L0_3(L1_3)
          end
          L0_3 = L17_2.type
          if "server" == L0_3 then
            L0_3 = TriggerServerEvent
            L1_3 = L17_2.event
            L0_3(L1_3)
          end
        end
        L20_2.onSelect = L21_2
        L18_2(L19_2, L20_2)
      end
      L12_2 = exports
      L12_2 = L12_2.is_interaction
      L13_2 = L12_2
      L12_2 = L12_2.addInteractionCoords
      L14_2 = L9_2
      L15_2 = A0_2
      L16_2 = {}
      L16_2.hideSquare = false
      L16_2.checkVisibility = true
      L16_2.showInVehicle = false
      L17_2 = A4_2[1]
      L17_2 = L17_2.distance
      if not L17_2 then
        L17_2 = A4_2.distance
        if not L17_2 then
          L17_2 = 2
        end
      end
      L16_2.distance = L17_2
      L17_2 = A4_2[1]
      L17_2 = L17_2.distance
      if not L17_2 then
        L17_2 = A4_2.distance
        if not L17_2 then
          L17_2 = 2
        end
      end
      L17_2 = L17_2 + 2
      L16_2.distanceText = L17_2
      L17_2 = {}
      L18_2 = {}
      L18_2.x = 0.0
      L18_2.y = 0.0
      L18_2.z = 1.0
      L17_2.text = L18_2
      L18_2 = {}
      L18_2.x = 0.0
      L18_2.y = 0.0
      L18_2.z = 0.0
      L17_2.target = L18_2
      L16_2.offset = L17_2
      L16_2.options = L11_2
      L12_2(L13_2, L14_2, L15_2, L16_2)
    else
      L11_2 = Interactions
      L11_2 = L11_2.SLEEPLESS
      if L8_2 == L11_2 then
        L11_2 = exports
        L11_2 = L11_2.sleepless_interact
        L12_2 = L11_2
        L11_2 = L11_2.addCoords
        L13_2 = {}
        L13_2.id = L9_2
        L13_2.coords = A0_2
        function L14_2()
          local L0_3, L1_3
        end
        L13_2.onEnter = L14_2
        function L14_2()
          local L0_3, L1_3
        end
        L13_2.onExit = L14_2
        function L14_2()
          local L0_3, L1_3
        end
        L13_2.nearby = L14_2
        L13_2.options = A4_2
        L13_2.renderDistance = 10.0
        L14_2 = A4_2[1]
        L14_2 = L14_2.distance
        if not L14_2 then
          L14_2 = A4_2.distance
          if not L14_2 then
            L14_2 = 2
          end
        end
        L13_2.activeDistance = L14_2
        L13_2.cooldown = 1500
        L11_2(L12_2, L13_2)
      else
        L11_2 = L10_2[L8_2]
        if L11_2 then
          L11_2 = {}
          L11_2.options = A4_2
          L12_2 = A7_2 or L12_2
          if not A7_2 then
            L12_2 = 5.0
          end
          L11_2.distance = L12_2
          L11_2.heading = A3_2
          L12_2 = exports
          L12_2 = L12_2[L8_2]
          L13_2 = L12_2
          L12_2 = L12_2.AddBoxZone
          L14_2 = L9_2
          L15_2 = A0_2
          L16_2 = A1_2
          L17_2 = A2_2
          L18_2 = {}
          L18_2.name = L9_2
          L18_2.heading = A3_2
          L18_2.debugPoly = false
          L19_2 = A0_2.z
          L19_2 = L19_2 - A1_2
          L18_2.minZ = L19_2
          L19_2 = A0_2.z
          L19_2 = L19_2 + A1_2
          L18_2.maxZ = L19_2
          L19_2 = L11_2
          L12_2(L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2)
        end
      end
    end
  end
end
CreateTargetZone = L6_1
function L6_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = tonumber
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L2_2 = GetHashKey
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    A0_2 = L2_2
  end
  L2_2 = L1_1
  L2_2[A0_2] = true
  L2_2 = Config
  L2_2 = L2_2.Interactions
  L3_2 = L5_1
  L3_2 = L3_2()
  L4_2 = {}
  L5_2 = Interactions
  L5_2 = L5_2.Q
  L4_2[L5_2] = true
  L5_2 = Interactions
  L5_2 = L5_2.QB
  L4_2[L5_2] = true
  L5_2 = Interactions
  L5_2 = L5_2.MV
  L4_2[L5_2] = true
  L5_2 = Interactions
  L5_2 = L5_2.OX
  if L2_2 == L5_2 then
    L5_2 = exports
    L5_2 = L5_2.ox_target
    L6_2 = L5_2
    L5_2 = L5_2.addModel
    L7_2 = A0_2
    L8_2 = A1_2
    L5_2(L6_2, L7_2, L8_2)
  else
    L5_2 = L4_2[L2_2]
    if L5_2 then
      L5_2 = {}
      L5_2.options = A1_2
      L6_2 = A1_2.distance
      if not L6_2 then
        L6_2 = 5.0
      end
      L5_2.distance = L6_2
      L6_2 = exports
      L6_2 = L6_2[L2_2]
      L7_2 = L6_2
      L6_2 = L6_2.AddTargetModel
      L8_2 = A0_2
      L9_2 = L5_2
      L6_2(L7_2, L8_2, L9_2)
    end
  end
end
CreateTargetModel = L6_1
function L6_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L0_2 = Config
  L0_2 = L0_2.Interactions
  L1_2 = L5_1
  L1_2 = L1_2()
  L2_2 = {}
  L3_2 = Interactions
  L3_2 = L3_2.Q
  L2_2[L3_2] = true
  L3_2 = Interactions
  L3_2 = L3_2.QB
  L2_2[L3_2] = true
  L3_2 = Interactions
  L3_2 = L3_2.MV
  L2_2[L3_2] = true
  L3_2 = Interactions
  L3_2 = L3_2.OX
  if L0_2 == L3_2 then
    L3_2 = pairs
    L4_2 = L1_1
    L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
    for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
      L9_2 = exports
      L9_2 = L9_2.ox_target
      L10_2 = L9_2
      L9_2 = L9_2.removeModel
      L11_2 = L7_2
      L9_2(L10_2, L11_2)
    end
    L3_2 = pairs
    L4_2 = L2_1
    L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
    for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
      L9_2 = exports
      L9_2 = L9_2.ox_target
      L10_2 = L9_2
      L9_2 = L9_2.removeZone
      L11_2 = L7_2
      L9_2(L10_2, L11_2)
    end
  else
    L3_2 = L2_2[L0_2]
    if L3_2 then
      L3_2 = next
      L4_2 = L3_1
      L3_2 = L3_2(L4_2)
      if L3_2 then
        L3_2 = 1
        L4_2 = L3_1
        L5_2 = 1
        for L6_2 = L3_2, L4_2, L5_2 do
          L7_2 = exports
          L7_2 = L7_2[L0_2]
          L8_2 = L7_2
          L7_2 = L7_2.RemoveZone
          L9_2 = L3_1
          L9_2 = L9_2[L6_2]
          L7_2(L8_2, L9_2)
        end
      end
    end
  end
  L3_2 = {}
  L1_1 = L3_2
  L3_2 = {}
  L2_1 = L3_2
end
RemoveAllTargetZones = L6_1
function L6_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L2_2 = Config
  L2_2 = L2_2.Interactions
  L3_2 = {}
  L4_2 = Interactions
  L4_2 = L4_2.Q
  L3_2[L4_2] = true
  L4_2 = Interactions
  L4_2 = L4_2.QB
  L3_2[L4_2] = true
  if not A0_2 then
    return
  end
  L4_2 = Interactions
  L4_2 = L4_2.OX
  if L2_2 == L4_2 then
    L4_2 = pairs
    L5_2 = L1_1
    L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
    for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
      L10_2 = exports
      L10_2 = L10_2.ox_target
      L11_2 = L10_2
      L10_2 = L10_2.removeModel
      L12_2 = L8_2
      L10_2(L11_2, L12_2)
    end
    L4_2 = pairs
    L5_2 = L2_1
    L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
    for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
      L10_2 = L9_2.name
      if L10_2 ~= A0_2 then
        L11_2 = string
        L11_2 = L11_2.match
        L12_2 = L10_2
        L13_2 = A0_2
        L11_2 = L11_2(L12_2, L13_2)
        if not L11_2 then
          goto lbl_49
        end
      end
      L11_2 = exports
      L11_2 = L11_2.ox_target
      L12_2 = L11_2
      L11_2 = L11_2.removeZone
      L13_2 = L8_2
      L11_2(L12_2, L13_2)
      ::lbl_49::
    end
  else
    L4_2 = L3_2[L2_2]
    if L4_2 then
      L4_2 = 1
      L5_2 = L0_1
      L6_2 = 1
      for L7_2 = L4_2, L5_2, L6_2 do
        L8_2 = exports
        L8_2 = L8_2[L2_2]
        L9_2 = L8_2
        L8_2 = L8_2.RemoveZone
        L10_2 = "rcore_prison_target_"
        L11_2 = L0_1
        L12_2 = "_"
        L13_2 = A0_2
        L10_2 = L10_2 .. L11_2 .. L12_2 .. L13_2
        L8_2(L9_2, L10_2)
      end
    else
      L4_2 = Interactions
      L4_2 = L4_2.SLEEPLESS
      if L2_2 == L4_2 then
        L4_2 = pairs
        L5_2 = L2_1
        L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
        for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
          L10_2 = L9_2.name
          if L10_2 ~= A0_2 then
            L11_2 = string
            L11_2 = L11_2.match
            L12_2 = L10_2
            L13_2 = A0_2
            L11_2 = L11_2(L12_2, L13_2)
            if not L11_2 then
              goto lbl_94
            end
          end
          L11_2 = exports
          L11_2 = L11_2.sleepless_interact
          L12_2 = L11_2
          L11_2 = L11_2.removeById
          L13_2 = L8_2
          L11_2(L12_2, L13_2)
          ::lbl_94::
        end
      else
        L4_2 = Interactions
        L4_2 = L4_2.IS
        if L2_2 == L4_2 then
          L4_2 = exports
          L4_2 = L4_2.is_interaction
          L5_2 = L4_2
          L4_2 = L4_2.removeResource
          L4_2(L5_2)
        end
      end
    end
  end
  L4_2 = {}
  L1_1 = L4_2
  L4_2 = {}
  L2_1 = L4_2
end
RemoveTargetZone = L6_1
