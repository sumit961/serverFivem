local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1
L0_1 = {}
Chairs = L0_1
CurrentPoint = nil
L0_1 = nil
L1_1 = {}
L2_1 = {}
L3_1 = {}
L4_1 = -1760759129
L3_1[L4_1] = 180.0
L4_1 = 1953006958
L3_1[L4_1] = 0.0
L4_1 = -382290129
L3_1[L4_1] = 180.0
L4_1 = -628719744
L3_1[L4_1] = 180.0
L4_1 = 493125771
L3_1[L4_1] = -220.0
L4_1 = 2056257134
L3_1[L4_1] = 180
L4_1 = -931009034
L3_1[L4_1] = -220.0
ENTITY_HEADING_MAP = L3_1
L3_1 = math
L3_1 = L3_1.pi
L3_1 = L3_1 / 180.0
DEG2RAD = L3_1
L3_1 = math
L3_1 = L3_1.pi
L4_1 = 180.0
L3_1 = L4_1 / L3_1
RAD2DEG = L3_1
function L3_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2
  L4_2 = L2_1
  L4_2 = L4_2[A0_2]
  if not L4_2 and A1_2 then
    L4_2 = L2_1
    L4_2[A0_2] = A1_2
    L4_2 = CreateThread
    function L5_2()
      local L0_3, L1_3, L2_3
      repeat
        L1_3 = A0_2
        L0_3 = L2_1
        L0_3 = L0_3[L1_3]
        L1_3 = Wait
        L2_3 = L0_3
        L1_3(L2_3)
        L1_3 = A2_2
        L2_3 = L0_3
        L1_3(L2_3)
      until -1 == L0_3
      L1_3 = A3_2
      if L1_3 then
        L1_3 = A3_2
        L1_3 = L1_3()
        if not L1_3 then
        end
      end
      L1_3 = A0_2
      L0_3 = L2_1
      L0_3[L1_3] = nil
    end
    L6_2 = "cl-lib-chairs code name: Phoenix"
    L4_2(L5_2, L6_2)
  elseif A1_2 then
    L4_2 = L2_1
    L4_2[A0_2] = A1_2
  end
end
SetCycle = L3_1
function L3_1(A0_2)
  local L1_2
  L1_2 = L2_1
  L1_2 = L1_2[A0_2]
  if L1_2 then
    L1_2 = L2_1
    L1_2[A0_2] = -1
  end
end
ClearCycle = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = {}
  L2_2 = math
  L2_2 = L2_2.pi
  L2_2 = L2_2 / 180
  L3_2 = A0_2.x
  L2_2 = L2_2 * L3_2
  L1_2.x = L2_2
  L2_2 = math
  L2_2 = L2_2.pi
  L2_2 = L2_2 / 180
  L3_2 = A0_2.y
  L2_2 = L2_2 * L3_2
  L1_2.y = L2_2
  L2_2 = math
  L2_2 = L2_2.pi
  L2_2 = L2_2 / 180
  L3_2 = A0_2.z
  L2_2 = L2_2 * L3_2
  L1_2.z = L2_2
  L2_2 = {}
  L3_2 = math
  L3_2 = L3_2.sin
  L4_2 = L1_2.z
  L3_2 = L3_2(L4_2)
  L3_2 = -L3_2
  L4_2 = math
  L4_2 = L4_2.abs
  L5_2 = math
  L5_2 = L5_2.cos
  L6_2 = L1_2.x
  L5_2, L6_2 = L5_2(L6_2)
  L4_2 = L4_2(L5_2, L6_2)
  L3_2 = L3_2 * L4_2
  L2_2.x = L3_2
  L3_2 = math
  L3_2 = L3_2.cos
  L4_2 = L1_2.z
  L3_2 = L3_2(L4_2)
  L4_2 = math
  L4_2 = L4_2.abs
  L5_2 = math
  L5_2 = L5_2.cos
  L6_2 = L1_2.x
  L5_2, L6_2 = L5_2(L6_2)
  L4_2 = L4_2(L5_2, L6_2)
  L3_2 = L3_2 * L4_2
  L2_2.y = L3_2
  L3_2 = math
  L3_2 = L3_2.sin
  L4_2 = L1_2.x
  L3_2 = L3_2(L4_2)
  L2_2.z = L3_2
  return L2_2
end
RotationToDirection = L3_1
function L3_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2
  L4_2 = GetGameplayCamRot
  L4_2 = L4_2()
  L5_2 = GetGameplayCamCoord
  L5_2 = L5_2()
  L6_2 = PlayerPedId
  L6_2 = L6_2()
  L7_2 = RotationToDirection
  L8_2 = L4_2
  L7_2 = L7_2(L8_2)
  L8_2 = {}
  L9_2 = L5_2.x
  L10_2 = L7_2.x
  L10_2 = L10_2 * A3_2
  L9_2 = L9_2 + L10_2
  L8_2.x = L9_2
  L9_2 = L5_2.y
  L10_2 = L7_2.y
  L10_2 = L10_2 * A3_2
  L9_2 = L9_2 + L10_2
  L8_2.y = L9_2
  L9_2 = L5_2.z
  L10_2 = L7_2.z
  L10_2 = L10_2 * A3_2
  L9_2 = L9_2 + L10_2
  L8_2.z = L9_2
  L9_2 = StartShapeTestRay
  L10_2 = L5_2.x
  L11_2 = L5_2.y
  L12_2 = L5_2.z
  L13_2 = L8_2.x
  L14_2 = L8_2.y
  L15_2 = L8_2.z
  L16_2 = A0_2 or L16_2
  if not A0_2 then
    L16_2 = -1
  end
  L17_2 = A1_2 or L17_2
  if not A1_2 then
    L17_2 = 0
  end
  L18_2 = A2_2 or L18_2
  if not A2_2 then
    L18_2 = 4
  end
  L9_2 = L9_2(L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
  L10_2 = GetShapeTestResult
  L11_2 = L9_2
  L10_2, L11_2, L12_2, L13_2, L14_2 = L10_2(L11_2)
  L15_2 = L11_2
  L16_2 = L14_2
  L17_2 = L12_2
  return L15_2, L16_2, L17_2
end
RayCastGamePlayCamera = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = GetEntityCoords
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2
  L3_2 = math
  L3_2 = L3_2.atan2
  L4_2 = L2_2.x
  L4_2 = -L4_2
  L5_2 = L2_2.y
  L3_2 = L3_2(L4_2, L5_2)
  L4_2 = RAD2DEG
  L4_2 = L3_2 * L4_2
  return L4_2
end
GetHeadingFromDirection = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = GetEntityHeading
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = DEG2RAD
  L1_2 = L1_2 * L2_2
  L2_2 = math
  L2_2 = L2_2.cos
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  L3_2 = math
  L3_2 = L3_2.sin
  L4_2 = L1_2
  L3_2 = L3_2(L4_2)
  L3_2 = -L3_2
  L4_2 = math
  L4_2 = L4_2.atan2
  L5_2 = L3_2
  L6_2 = L2_2
  L4_2 = L4_2(L5_2, L6_2)
  L5_2 = RAD2DEG
  L5_2 = L4_2 * L5_2
  return L5_2
end
GetHeadDirection = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = GetEntityCoords
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = GetEntityCoords
  L4_2 = A1_2
  L3_2 = L3_2(L4_2)
  L4_2 = L3_2 - L2_2
  L5_2 = math
  L5_2 = L5_2.atan2
  L6_2 = L4_2.x
  L6_2 = -L6_2
  L7_2 = L4_2.y
  L5_2 = L5_2(L6_2, L7_2)
  L6_2 = RAD2DEG
  L6_2 = L5_2 * L6_2
  return L6_2
end
GetEntityHeadingFromEntity = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = GetEntityCoords
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = GetEntityCoords
  L4_2 = A1_2
  L3_2 = L3_2(L4_2)
  L4_2 = L3_2 - L2_2
  L5_2 = math
  L5_2 = L5_2.atan2
  L6_2 = L4_2.x
  L6_2 = -L6_2
  L7_2 = L4_2.y
  L5_2 = L5_2(L6_2, L7_2)
  L6_2 = SetEntityHeading
  L7_2 = A0_2
  L8_2 = RAD2DEG
  L8_2 = L5_2 * L8_2
  L6_2(L7_2, L8_2)
end
SetEntityHeadingLookAt = L3_1
function L3_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L4_2 = World3dToScreen2d
  L5_2 = A0_2
  L6_2 = A1_2
  L7_2 = A2_2
  L4_2, L5_2, L6_2 = L4_2(L5_2, L6_2, L7_2)
  if L4_2 then
    L7_2 = SetTextScale
    L8_2 = 0.6
    L9_2 = 0.6
    L7_2(L8_2, L9_2)
    L7_2 = SetTextFont
    L8_2 = 0
    L7_2(L8_2)
    L7_2 = SetTextColour
    L8_2 = 255
    L9_2 = 255
    L10_2 = 255
    L11_2 = 255
    L7_2(L8_2, L9_2, L10_2, L11_2)
    L7_2 = SetTextDropshadow
    L8_2 = 0
    L9_2 = 0
    L10_2 = 0
    L11_2 = 0
    L12_2 = 255
    L7_2(L8_2, L9_2, L10_2, L11_2, L12_2)
    L7_2 = SetTextDropShadow
    L7_2()
    L7_2 = SetTextOutline
    L7_2()
    L7_2 = SetTextEntry
    L8_2 = "STRING"
    L7_2(L8_2)
    L7_2 = SetTextCentre
    L8_2 = 1
    L7_2(L8_2)
    L7_2 = AddTextComponentString
    L8_2 = A3_2
    L7_2(L8_2)
    L7_2 = DrawText
    L8_2 = L5_2
    L9_2 = L6_2
    L7_2(L8_2, L9_2)
  end
end
Draw3DText = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = nil
  L4_2 = false
  if "sit" == A0_2 or "lay" == A0_2 then
    if "bed" == A1_2 then
      L4_2 = true
      L5_2 = GetEntityVector
      L6_2 = L2_2
      L7_2 = "front"
      L5_2 = L5_2(L6_2, L7_2)
      L3_2 = L5_2
    elseif "noback" == A1_2 then
      L4_2 = true
      L5_2 = GetEntityVector
      L6_2 = L2_2
      L7_2 = "front"
      L5_2 = L5_2(L6_2, L7_2)
      L3_2 = L5_2
    else
      L5_2 = GetEntityVector
      L6_2 = L2_2
      L7_2 = "back"
      L5_2 = L5_2(L6_2, L7_2)
      L3_2 = L5_2
    end
  elseif "back" == A0_2 then
    if not A1_2 then
      L4_2 = true
    end
    L5_2 = GetEntityVector
    L6_2 = L2_2
    L7_2 = "front"
    L5_2 = L5_2(L6_2, L7_2)
    L3_2 = L5_2
  end
  L5_2 = "Generating correct exit point for [%s] | [%s] -> [%s]"
  L6_2 = L5_2
  L5_2 = L5_2.format
  L7_2 = A0_2
  L8_2 = A1_2
  L9_2 = L3_2
  L5_2 = L5_2(L6_2, L7_2, L8_2, L9_2)
  if L5_2 then
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "%s"
    L8_2 = L5_2
    L6_2(L7_2, L8_2)
  end
  L6_2 = L3_2
  L7_2 = L4_2
  return L6_2, L7_2
end
GetExitCoordsFromEntity = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = nil
  L3_2 = DoesEntityExist
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  if L3_2 then
    L3_2 = GetEntityCoords
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    L4_2 = GetEntityForwardVector
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    L5_2 = nil
    if "front" == A1_2 then
      L6_2 = L4_2 / 2.3
      L5_2 = L3_2 + L6_2
    else
      L6_2 = L4_2 / 2.3
      L5_2 = L3_2 - L6_2
    end
    L2_2 = L5_2
  end
  return L2_2
end
GetEntityVector = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = false
  L3_2 = SH
  L3_2 = L3_2.data
  L3_2 = L3_2.Chairs
  L4_2 = joaat
  L5_2 = A0_2.model
  L4_2 = L4_2(L5_2)
  L3_2 = L3_2[L4_2]
  if not L3_2 then
    return
  end
  L4_2 = GetExitCoordsFromEntity
  L5_2 = A0_2.seatType
  L6_2 = L3_2.type
  L4_2, L5_2 = L4_2(L5_2, L6_2)
  L6_2 = L3_2.type
  if "bed" == L6_2 then
    L6_2 = ClearPedTasksImmediately
    L7_2 = L1_2
    L6_2(L7_2)
  end
  L6_2 = {}
  L1_1 = L6_2
  L6_2 = ClearCycle
  L7_2 = "chairs_exit"
  L6_2(L7_2)
  hintState = false
  validEntity = false
  L6_2 = ClearAllHelpMessages
  L6_2()
  L6_2 = FreezeEntityPosition
  L7_2 = L1_2
  L8_2 = false
  L6_2(L7_2, L8_2)
  if L4_2 then
    L6_2 = SetEntityCoords
    L7_2 = L1_2
    L8_2 = L4_2
    L6_2(L7_2, L8_2)
  end
  L6_2 = SetEntityCollision
  L7_2 = L1_2
  L8_2 = true
  L9_2 = true
  L6_2(L7_2, L8_2, L9_2)
  L6_2 = ENUMS
  L6_2 = L6_2.ANIMS
  L6_2 = L6_2.EXIT
  L7_2 = 0.0
  L8_2 = IsModelInCdimage
  L9_2 = "ch_prop_casino_door_01b"
  L8_2 = L8_2(L9_2)
  if L8_2 then
    L8_2 = LoadAnim
    L9_2 = L6_2.animDict
    L8_2(L9_2)
  else
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "CHAIRS: Failed to detect anim dict [%s] using fallback"
    L10_2 = L6_2.animDict
    L8_2(L9_2, L10_2)
  end
  if L4_2 and not L5_2 then
    L8_2 = TaskPlayAnimAdvanced
    L9_2 = L1_2
    L10_2 = L6_2.animDict
    L11_2 = L6_2.animName
    L12_2 = L4_2.x
    L13_2 = L4_2.y
    L14_2 = L4_2.z
    L15_2 = 0
    L16_2 = 0.0
    L17_2 = L7_2
    L18_2 = 8.0
    L19_2 = 1.0
    L20_2 = -1
    L21_2 = 2
    L22_2 = 0.0
    L23_2 = 0.0
    L24_2 = 0.0
    L8_2(L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2)
    L8_2 = Wait
    L9_2 = 2500
    L8_2(L9_2)
  else
    L8_2 = Wait
    L9_2 = 1500
    L8_2(L9_2)
  end
  L8_2 = ClearPedTasksImmediately
  L9_2 = L1_2
  L8_2(L9_2)
  L8_2 = Wait
  L9_2 = 500
  L8_2(L9_2)
  L8_2 = dbg
  L8_2 = L8_2.debug
  L9_2 = "CHAIRS: ExitFunc - activating raycast? 1."
  L8_2(L9_2)
  L8_2 = HandleRaycastInterval
  L9_2 = "init"
  L8_2(L9_2)
end
ExitFunc = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = GetOffsetFromEntityInWorldCoords
  L3_2 = A0_2
  L4_2 = A1_2
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 then
    L2_2 = nil
  end
  return L2_2
end
GetPointByOffset = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = GetEntityCoords
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = nil
  L5_2 = nil
  L6_2 = 1
  L7_2 = #A1_2
  L8_2 = 1
  for L9_2 = L6_2, L7_2, L8_2 do
    L10_2 = A1_2[L9_2]
    L10_2 = L10_2.offset
    L11_2 = GetPointByOffset
    L12_2 = A0_2
    L13_2 = L10_2
    L11_2 = L11_2(L12_2, L13_2)
    L12_2 = Config
    L12_2 = L12_2.Chairs
    L12_2 = L12_2.DebugSeatPos
    if L12_2 then
      L12_2 = DrawBox
      L13_2 = L11_2
      L14_2 = L11_2 + 0.1
      L15_2 = 200
      L16_2 = 255
      L17_2 = 250
      L18_2 = 255
      L12_2(L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
    end
    L12_2 = L11_2 - L3_2
    L12_2 = #L12_2
    L13_2 = Config
    L13_2 = L13_2.Chairs
    L13_2 = L13_2.SeatDistCheck
    if L12_2 <= L13_2 then
      L4_2 = L9_2
      L5_2 = L11_2
      break
    end
  end
  L6_2 = L4_2
  L7_2 = L5_2
  return L6_2, L7_2
end
GetClosestPoint = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = dbg
  L2_2 = L2_2.debug
  L3_2 = "CHAIRS: Getting anim type by action [%s] | [%s]"
  L4_2 = A0_2
  L5_2 = A1_2
  L2_2(L3_2, L4_2, L5_2)
  L2_2 = nil
  if A1_2 then
    if "sit" ~= A0_2 then
      if "back" ~= A0_2 then
        goto lbl_29
      end
      L3_2 = A1_2.anim
      L3_2 = L3_2.sit
      if not L3_2 then
        L3_2 = A1_2.anim
        L3_2 = L3_2.scenario
        if not L3_2 then
          goto lbl_29
        end
      end
    end
    L3_2 = A1_2.anim
    L3_2 = L3_2.sit
    L2_2 = L3_2 or L2_2
    if not L3_2 then
      L3_2 = A1_2.anim
      L2_2 = L3_2.scenario
      goto lbl_43
      ::lbl_29::
      if "lay" == A0_2 then
        L3_2 = A1_2.anim
        L3_2 = L3_2.lay
        if L3_2 then
          L3_2 = A1_2.anim
          L2_2 = L3_2.lay
        end
      end
    end
  else
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "CHAIRS: No data found for anim type [%s]"
    L5_2 = A0_2
    L3_2(L4_2, L5_2)
  end
  ::lbl_43::
  L3_2 = dbg
  L3_2 = L3_2.debug
  L4_2 = "CHAIRS: Anim type found [%s]"
  L5_2 = L2_2
  L3_2(L4_2, L5_2)
  return L2_2
end
GetAnimTypeByAction = L3_1
function L3_1(A0_2)
  local L1_2, L2_2
  L1_2 = RequestAnimDict
  L2_2 = A0_2.dict
  L1_2(L2_2)
  while true do
    L1_2 = HasAnimDictLoaded
    L2_2 = A0_2.dict
    L1_2 = L1_2(L2_2)
    if L1_2 then
      break
    end
    L1_2 = RequestAnimDict
    L2_2 = A0_2.dict
    L1_2(L2_2)
    L1_2 = Wait
    L2_2 = 0
    L1_2(L2_2)
  end
end
LoadAnimDict = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = SetEntityHeadingLookAt
  L3_2 = A0_2
  L4_2 = A1_2
  L2_2(L3_2, L4_2)
  L2_2 = TaskTurnPedToFaceEntity
  L3_2 = A0_2
  L4_2 = A1_2
  L5_2 = -1
  L2_2(L3_2, L4_2, L5_2)
end
MakePlayerFaceEntity = L3_1
function L3_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2
  L4_2 = dbg
  L4_2 = L4_2.debug
  L5_2 = "CHAIRS: Starting sitting interaction at [%s] | [%s] | [%s] | [%s]"
  L6_2 = A0_2
  L7_2 = A1_2
  L8_2 = A2_2
  L9_2 = A3_2
  L4_2(L5_2, L6_2, L7_2, L8_2, L9_2)
  if A2_2 then
    L4_2 = A2_2.model
    if L4_2 then
      goto lbl_15
    end
  end
  L4_2 = nil
  ::lbl_15::
  if not L4_2 then
    L5_2 = dbg
    L5_2 = L5_2.critical
    L6_2 = "CHAIRS: No model found for entity [%s]"
    L7_2 = A1_2
    return L5_2(L6_2, L7_2)
  end
  L5_2 = dbg
  L5_2 = L5_2.debug
  L6_2 = "CHAIRS: Model found [%s]"
  L7_2 = L4_2
  L5_2(L6_2, L7_2)
  L5_2 = GetAnimTypeByAction
  L6_2 = A0_2
  L7_2 = A2_2
  L5_2 = L5_2(L6_2, L7_2)
  L6_2 = L5_2.dict
  if L6_2 then
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "CHAIRS: Loading anim dict [%s]"
    L8_2 = L5_2.dict
    L6_2(L7_2, L8_2)
    L6_2 = DoesAnimDictExist
    L7_2 = L5_2.dict
    L6_2 = L6_2(L7_2)
    if not L6_2 then
      L6_2 = dbg
      L6_2 = L6_2.error
      L7_2 = "CHAIRS: Anim dict [%s] does not exist"
      L8_2 = L5_2.dict
      return L6_2(L7_2, L8_2)
    end
    L6_2 = RequestAnimDict
    L7_2 = L5_2.dict
    L6_2(L7_2)
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "CHAIRS: Loaded anim dict [%s]"
    L8_2 = L5_2.dict
    L6_2(L7_2, L8_2)
  end
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "CHAIRS: Anim data [%s] | [%s]"
  L8_2 = L5_2.dict
  L9_2 = L5_2.name
  L6_2(L7_2, L8_2, L9_2)
  EXIT_MODE = true
  L6_2 = CurrentPoint
  L7_2 = PlayerPedId
  L7_2 = L7_2()
  L8_2 = MakePlayerFaceEntity
  L9_2 = L7_2
  L10_2 = A1_2
  L8_2(L9_2, L10_2)
  L8_2 = SetPedResetFlag
  L9_2 = L7_2
  L10_2 = 322
  L11_2 = true
  L8_2(L9_2, L10_2, L11_2)
  L8_2 = Wait
  L9_2 = 250
  L8_2(L9_2)
  L8_2 = GetEntityHeadingFromEntity
  L9_2 = L7_2
  L10_2 = A1_2
  L8_2 = L8_2(L9_2, L10_2)
  if "back" == A0_2 then
    L9_2 = GetEntityHeadingFromEntity
    L10_2 = L7_2
    L11_2 = A1_2
    L9_2 = L9_2(L10_2, L11_2)
    L8_2 = L9_2 - 180
  else
    L9_2 = IsEntityHavingBrokenOffset
    L10_2 = A2_2.model
    L9_2 = L9_2(L10_2)
    if L9_2 then
      L10_2 = GetEntityHeadingFromEntity
      L11_2 = L7_2
      L12_2 = A1_2
      L10_2 = L10_2(L11_2, L12_2)
      L8_2 = L10_2 - L9_2
    else
      L10_2 = GetEntityHeadingFromEntity
      L11_2 = L7_2
      L12_2 = A1_2
      L10_2 = L10_2(L11_2, L12_2)
      L8_2 = L10_2
    end
  end
  L9_2 = dbg
  L9_2 = L9_2.debug
  L10_2 = "CHAIRS: Heading for entity [%s] | [%s]"
  L11_2 = A1_2
  L12_2 = L8_2
  L9_2(L10_2, L11_2, L12_2)
  L9_2 = L5_2.dict
  if L9_2 then
    L9_2 = TaskPlayAnimAdvanced
    L10_2 = L7_2
    L11_2 = L5_2.dict
    L12_2 = L5_2.name
    L13_2 = L6_2.x
    L14_2 = L6_2.y
    L15_2 = L6_2.z
    L16_2 = 0
    L17_2 = 0.0
    L18_2 = L8_2
    L19_2 = 8.0
    L20_2 = 1.0
    L21_2 = -1
    L22_2 = 2
    L23_2 = 0.0
    L24_2 = 0
    L25_2 = 0
    L9_2(L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2)
  else
    L9_2 = TaskStartScenarioAtPosition
    L10_2 = L7_2
    L11_2 = L5_2.name
    L12_2 = L6_2.x
    L13_2 = L6_2.y
    L14_2 = L6_2.z
    L15_2 = L8_2
    L16_2 = 0
    L17_2 = true
    L18_2 = true
    L9_2(L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
  end
  L9_2 = HandleRaycastInterval
  L10_2 = "exit"
  L9_2(L10_2)
  L9_2 = Wait
  L10_2 = 1000
  L9_2(L10_2)
  L9_2 = dbg
  L9_2 = L9_2.debug
  L10_2 = "CHAIRS: Player should be sitting loading and exit interval"
  L9_2(L10_2)
  L9_2 = HelpKeys
  L9_2 = L9_2.Show
  L10_2 = {}
  L11_2 = {}
  L12_2 = _U
  L13_2 = "CHAIRS.EXIT"
  L12_2 = L12_2(L13_2)
  L11_2.label = L12_2
  L11_2.keyName = "E"
  L10_2[1] = L11_2
  L11_2 = "top-left"
  L9_2(L10_2, L11_2)
  L9_2 = SetCycle
  L10_2 = "chairs_exit"
  L11_2 = 0
  function L12_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3
    L0_3 = IsControlJustPressed
    L1_3 = 0
    L2_3 = 38
    L0_3 = L0_3(L1_3, L2_3)
    if not L0_3 then
      L0_3 = IsDisabledControlJustPressed
      L1_3 = 0
      L2_3 = 38
      L0_3 = L0_3(L1_3, L2_3)
    end
    if L0_3 then
      L1_3 = HelpKeys
      L1_3 = L1_3.Hide
      L1_3()
      L1_3 = SetTimeout
      L2_3 = 1500
      function L3_3()
        local L0_4, L1_4
        EXIT_MODE = false
        L0_4 = nil
        L0_1 = L0_4
      end
      L1_3(L2_3, L3_3)
      L1_3 = TriggerServerEvent
      L2_3 = "rcore_prison:server:unregisterSeat"
      L3_3 = A3_2
      L4_3 = L4_2
      L1_3(L2_3, L3_3, L4_3)
    end
  end
  L9_2(L10_2, L11_2, L12_2)
end
HandleInteraction = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = pcall
  L2_2 = GetEntityLodDist
  L3_2 = A0_2
  L1_2, L2_2 = L1_2(L2_2, L3_2)
  L3_2 = L1_2 or L3_2
  if L1_2 then
    L3_2 = L2_2
  end
  L4_2 = L3_2 or L4_2
  L4_2 = L3_2 and L3_2 > 0
  return L4_2
end
IsEntityAModel = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  if "init" == A0_2 then
    L1_2 = SetCycle
    L2_2 = "raycast_check"
    L3_2 = 0
    function L4_2()
      local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3, L17_3
      L0_3 = PlayerPedId
      L0_3 = L0_3()
      L1_3 = GetEntityCoords
      L2_3 = L0_3
      L1_3 = L1_3(L2_3)
      L2_3 = RaycastFromCamera
      L3_3 = 511
      L2_3, L3_3, L4_3 = L2_3(L3_3)
      L5_3 = L4_3 - L1_3
      L5_3 = #L5_3
      if L2_3 and L5_3 < 2 then
        L6_3 = L0_1
        if L3_3 ~= L6_3 and 0 ~= L3_3 then
          L6_3 = IsEntityAModel
          L7_3 = L3_3
          L6_3 = L6_3(L7_3)
          if L6_3 then
            L6_3 = IsPointInPolygon
            L7_3 = vec2
            L8_3 = L1_3.x
            L9_3 = L1_3.y
            L7_3 = L7_3(L8_3, L9_3)
            L8_3 = SH
            L8_3 = L8_3.data
            L8_3 = L8_3.prisonVertices
            L6_3 = L6_3(L7_3, L8_3)
            L7_3 = GetEntityModel
            L8_3 = L3_3
            L7_3 = L7_3(L8_3)
            if not L6_3 then
              return
            end
            L8_3 = GetEntityCoords
            L9_3 = L3_3
            L8_3 = L8_3(L9_3)
            L9_3 = L4_3 - L8_3
            L9_3 = #L9_3
            if L9_3 >= 6.0 then
              return
            end
            L10_3 = GetSeatDataFromEntityModel
            L11_3 = L7_3
            L10_3 = L10_3(L11_3)
            if L10_3 then
              L11_3 = L10_3.type
              L12_3 = {}
              if "noback" == L11_3 then
                L13_3 = table
                L13_3 = L13_3.insert
                L14_3 = L12_3
                L15_3 = {}
                L16_3 = _U
                L17_3 = "CHAIRS.SIT_BACK"
                L16_3 = L16_3(L17_3)
                L15_3.label = L16_3
                L15_3.keyName = "E"
                L13_3(L14_3, L15_3)
              elseif "bed" == L11_3 then
                L13_3 = table
                L13_3 = L13_3.insert
                L14_3 = L12_3
                L15_3 = {}
                L16_3 = _U
                L17_3 = "CHAIRS.LAY"
                L16_3 = L16_3(L17_3)
                L15_3.label = L16_3
                L15_3.keyName = "H"
                L13_3(L14_3, L15_3)
              elseif "nobed" == L11_3 then
                L13_3 = #L12_3
                L13_3 = L13_3 + 1
                L14_3 = {}
                L15_3 = _U
                L16_3 = "CHAIRS.SIT_FRONT"
                L15_3 = L15_3(L16_3)
                L14_3.label = L15_3
                L14_3.keyName = "E"
                L12_3[L13_3] = L14_3
                L13_3 = #L12_3
                L13_3 = L13_3 + 1
                L14_3 = {}
                L15_3 = _U
                L16_3 = "CHAIRS.SIT_BACK"
                L15_3 = L15_3(L16_3)
                L14_3.label = L15_3
                L14_3.keyName = "G"
                L12_3[L13_3] = L14_3
              elseif "back" == L11_3 then
                L13_3 = #L12_3
                L13_3 = L13_3 + 1
                L14_3 = {}
                L15_3 = _U
                L16_3 = "CHAIRS.SIT_FRONT"
                L15_3 = L15_3(L16_3)
                L14_3.label = L15_3
                L14_3.keyName = "E"
                L12_3[L13_3] = L14_3
                L13_3 = #L12_3
                L13_3 = L13_3 + 1
                L14_3 = {}
                L15_3 = _U
                L16_3 = "CHAIRS.LAY"
                L15_3 = L15_3(L16_3)
                L14_3.label = L15_3
                L14_3.keyName = "H"
                L12_3[L13_3] = L14_3
                L13_3 = #L12_3
                L13_3 = L13_3 + 1
                L14_3 = {}
                L15_3 = _U
                L16_3 = "CHAIRS.SIT_BACK"
                L15_3 = L15_3(L16_3)
                L14_3.label = L15_3
                L14_3.keyName = "G"
                L12_3[L13_3] = L14_3
              end
              L13_3 = HelpKeys
              L13_3 = L13_3.Show
              L14_3 = L12_3
              L15_3 = "top-left"
              L13_3(L14_3, L15_3)
              L13_3 = HandleSeatOptions
              L14_3 = L10_3
              L15_3 = L3_3
              L13_3 = L13_3(L14_3, L15_3)
              L1_1 = L13_3
            end
          else
            L6_3 = SH
            L6_3 = L6_3.zoneId
            if not L6_3 then
              L6_3 = HelpKeys
              L6_3 = L6_3.Hide
              L6_3()
            end
          end
        end
      end
      L6_3 = L1_1
      if L6_3 then
        L6_3 = L1_1.entity
        L7_3 = L0_1
        if L6_3 ~= L7_3 then
          L3_3 = 0
        end
      end
      L0_1 = L3_3
      L3_3 = 0
      L6_3 = SH
      L6_3 = L6_3.zoneId
      if not L6_3 and L5_3 > 4 then
        L6_3 = HelpKeys
        L6_3 = L6_3.Hide
        L6_3()
      end
      L6_3 = Wait
      L7_3 = 0
      L6_3(L7_3)
    end
    L1_2(L2_2, L3_2, L4_2)
  else
    L1_2 = ClearCycle
    L2_2 = "raycast_check"
    L1_2(L2_2)
  end
end
HandleRaycastInterval = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = GetPlayerPed
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = GetVehiclePedIsIn
  L3_2 = L1_2
  L4_2 = false
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = L2_2 or L3_2
  if 0 == L2_2 or not L2_2 then
    L3_2 = L1_2
  end
  return L3_2
end
GetPlayerPedOrVehicle = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.Chairs
  L2_2 = joaat
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L1_2 = L1_2[L2_2]
  if not L1_2 then
    L1_2 = nil
  end
  return L1_2
end
GetSeatDataFromEntityModel = L3_1
function L3_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = ENTITY_HEADING_MAP
  L2_2 = joaat
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L1_2 = L1_2[L2_2]
  if not L1_2 then
    L1_2 = nil
  end
  return L1_2
end
IsEntityHavingBrokenOffset = L3_1
function L3_1(A0_2)
  local L1_2, L2_2
  L1_2 = HasAnimDictLoaded
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L1_2 = RequestAnimDict
    L2_2 = A0_2
    L1_2(L2_2)
    while true do
      L1_2 = HasAnimDictLoaded
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
end
LoadAnim = L3_1
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = nil
  L3_2 = nil
  L4_2 = nil
  if A0_2 then
    L2_2 = A0_2.positions
    L5_2 = GetClosestPoint
    L6_2 = A1_2
    L7_2 = L2_2
    L5_2, L6_2 = L5_2(L6_2, L7_2)
    L4_2 = L6_2
    L3_2 = L5_2
  end
  L5_2 = 0.1
  if L3_2 then
    L6_2 = {}
    L6_2.idx = L3_2
    L6_2.point = L4_2
    L6_2.data = A0_2
    L6_2.entity = A1_2
    return L6_2
  end
end
HandleSeatOptions = L3_1
function L3_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = EXIT_MODE
  if L0_2 then
    return
  end
  L0_2 = L1_1
  if L0_2 then
    L0_2 = next
    L1_2 = L1_1
    L0_2 = L0_2(L1_2)
    if L0_2 then
      L0_2 = L1_1.point
      CurrentPoint = L0_2
      L0_2 = TriggerServerEvent
      L1_2 = "rcore_prison:server:registerSeat"
      L2_2 = L1_1.entity
      L3_2 = "sit"
      L4_2 = L1_1.idx
      L5_2 = L1_1.data
      L5_2 = L5_2.model
      L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
    end
  end
end
START_SIT_E = L3_1
function L3_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = EXIT_MODE
  if L0_2 then
    return
  end
  L0_2 = L1_1
  if L0_2 then
    L0_2 = next
    L1_2 = L1_1
    L0_2 = L0_2(L1_2)
    if L0_2 then
      L0_2 = L1_1.point
      CurrentPoint = L0_2
      L0_2 = TriggerServerEvent
      L1_2 = "rcore_prison:server:registerSeat"
      L2_2 = L1_1.entity
      L3_2 = "back"
      L4_2 = L1_1.idx
      L5_2 = L1_1.data
      L5_2 = L5_2.model
      L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
    end
  end
end
START_SIT_BACK = L3_1
function L3_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = EXIT_MODE
  if L0_2 then
    return
  end
  L0_2 = L1_1
  if L0_2 then
    L0_2 = next
    L1_2 = L1_1
    L0_2 = L0_2(L1_2)
    if L0_2 then
      L0_2 = L1_1.point
      CurrentPoint = L0_2
      L0_2 = TriggerServerEvent
      L1_2 = "rcore_prison:server:registerSeat"
      L2_2 = L1_1.entity
      L3_2 = "lay"
      L4_2 = L1_1.idx
      L5_2 = L1_1.data
      L5_2 = L5_2.model
      L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
    end
  end
end
START_LAY = L3_1
L3_1 = RegisterKey
L4_1 = START_LAY
L5_1 = "STAND_LAY"
L6_1 = "Stand lay"
L7_1 = "H"
L3_1(L4_1, L5_1, L6_1, L7_1)
L3_1 = RegisterKey
L4_1 = START_SIT_BACK
L5_1 = "STAND_BACK"
L6_1 = "Stand sit back"
L7_1 = "G"
L3_1(L4_1, L5_1, L6_1, L7_1)
L3_1 = RegisterKey
L4_1 = START_SIT_E
L5_1 = "STAND_FRONT"
L6_1 = "Start sit front"
L7_1 = "E"
L3_1(L4_1, L5_1, L6_1, L7_1)
