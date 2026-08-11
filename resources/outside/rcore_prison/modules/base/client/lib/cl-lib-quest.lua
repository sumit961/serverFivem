local L0_1, L1_1, L2_1
L0_1 = {}
L0_1.activeCamera = nil
L0_1.appendState = false
Quest = L0_1
L0_1 = RegisterNuiCallback
L1_1 = "executeObjective"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = {}
  L3_2 = A0_2.action
  L2_2.action = L3_2
  L3_2 = A0_2.id
  L2_2.id = L3_2
  L3_2 = SH
  L3_2 = L3_2.zoneId
  L2_2.zoneId = L3_2
  L3_2 = L2_2.action
  L4_2 = Actions
  L4_2 = L4_2.PRISON_BREAK
  if L3_2 == L4_2 then
    L3_2 = HideApp
    L3_2()
  end
  L3_2 = TriggerServerEvent
  L4_2 = "rcore_prison:server:handleQuestTask"
  L5_2 = L2_2
  L3_2(L4_2, L5_2)
  L3_2 = A1_2
  L4_2 = "ok"
  L3_2(L4_2)
end
L0_1(L1_1, L2_1)
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L1_2 = GetPedBoneIndex
  L2_2 = A0_2
  L3_2 = 12844
  L1_2 = L1_2(L2_2, L3_2)
  L2_2 = GetWorldPositionOfEntityBone
  L3_2 = A0_2
  L4_2 = L1_2
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = GetEntityForwardVector
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = L3_2 * 0.5
  L4_2 = L2_2 + L4_2
  L5_2 = CreateCam
  L6_2 = "DEFAULT_SCRIPTED_CAMERA"
  L7_2 = true
  L5_2 = L5_2(L6_2, L7_2)
  L6_2 = SetCamCoord
  L7_2 = L5_2
  L8_2 = L4_2.x
  L9_2 = L4_2.y
  L10_2 = L4_2.z
  L6_2(L7_2, L8_2, L9_2, L10_2)
  L6_2 = PointCamAtCoord
  L7_2 = L5_2
  L8_2 = L2_2.x
  L9_2 = L2_2.y
  L10_2 = L2_2.z
  L6_2(L7_2, L8_2, L9_2, L10_2)
  L6_2 = SetCamActive
  L7_2 = L5_2
  L8_2 = true
  L6_2(L7_2, L8_2)
  L6_2 = RenderScriptCams
  L7_2 = true
  L8_2 = false
  L9_2 = 0
  L10_2 = true
  L11_2 = false
  L6_2(L7_2, L8_2, L9_2, L10_2, L11_2)
  return L5_2
end
PointCameraAtEntityHead = L0_1
L0_1 = {}
L1_1 = Quest
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.interaction
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    return
  end
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.interaction
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.quest
  if not L1_2 then
    L1_2 = dbg
    L1_2 = L1_2.debug
    L2_2 = "No quest found for zoneId %s"
    L3_2 = A0_2
    return L1_2(L2_2, L3_2)
  end
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.interaction
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.entity
  if not L1_2 then
    L1_2 = PlayerPedId
    L1_2 = L1_2()
  end
  if not L1_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "No interactPed found for zoneId %s"
    L4_2 = A0_2
    return L2_2(L3_2, L4_2)
  end
  L2_2 = DisplayRadar
  L3_2 = false
  L2_2(L3_2)
  L2_2 = Config
  L2_2 = L2_2.Release
  L2_2 = L2_2.AtCheckpoint
  if L2_2 then
    L2_2 = SH
    L2_2 = L2_2.data
    L2_2 = L2_2.interaction
    L2_2 = L2_2[A0_2]
    L2_2 = L2_2.releasePlayerOption
    if L2_2 then
      L2_2 = Quest
      L2_2 = L2_2.appendState
      if not L2_2 then
        L2_2 = Quest
        L2_2.appendState = true
        L2_2 = SH
        L2_2 = L2_2.data
        L2_2 = L2_2.interaction
        L2_2 = L2_2[A0_2]
        L2_2 = L2_2.quest
        L2_2 = L2_2.options
        L0_1 = L2_2
        L2_2 = L0_1
        L2_2 = #L2_2
        L3_2 = L2_2 + 1
        L2_2 = L0_1
        L4_2 = {}
        L5_2 = _U
        L6_2 = "RELEASE.LABEL"
        L5_2 = L5_2(L6_2)
        L4_2.label = L5_2
        L5_2 = Actions
        L5_2 = L5_2.RELEASE_PLAYER
        L4_2.action = L5_2
        L2_2[L3_2] = L4_2
    end
  end
  else
    L2_2 = SH
    L2_2 = L2_2.data
    L2_2 = L2_2.interaction
    L2_2 = L2_2[A0_2]
    L2_2 = L2_2.quest
    L2_2 = L2_2.options
    L0_1 = L2_2
  end
  L2_2 = Quest
  L3_2 = PointCameraAtEntityHead
  L4_2 = L1_2
  L3_2 = L3_2(L4_2)
  L2_2.activeCamera = L3_2
  L2_2 = HelpKeys
  L2_2 = L2_2.Hide
  L2_2()
  L2_2 = FrontendService
  L2_2 = L2_2.HandleFocus
  L3_2 = true
  L2_2(L3_2)
  L2_2 = FrontendService
  L2_2 = L2_2.SendReactMessage
  L3_2 = FE_EVENTS
  L3_2 = L3_2.LOAD_APP
  L4_2 = {}
  L5_2 = Screens
  L5_2 = L5_2.QUEST
  L4_2.screen = L5_2
  L4_2.visible = true
  L5_2 = SH
  L5_2 = L5_2.data
  L5_2 = L5_2.interaction
  L5_2 = L5_2[A0_2]
  L5_2 = L5_2.quest
  L4_2.quest = L5_2
  L2_2(L3_2, L4_2)
end
L1_1.RequestOpen = L2_1
