local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = {}
L0_1.callSessionState = false
Booths = L0_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "EndCallAtBooth"
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  if A0_2 then
    L1_2 = Booths
    L1_2 = L1_2.callSessionState
    if not L1_2 then
      return
    end
    L1_2 = Booths
    L1_2.callSessionState = false
    L1_2 = pcall
    function L2_2()
      local L0_3, L1_3
      L0_3 = HandleInventoryOpenState
      L1_3 = true
      L0_3(L1_3)
    end
    L1_2, L2_2 = L1_2(L2_2)
    L3_2 = HelpKeys
    L3_2 = L3_2.Hide
    L3_2()
    L3_2 = BoothAnim
    L4_2 = L3_2
    L3_2 = L3_2.Exit
    L3_2(L4_2)
    IsAtBooth = false
  end
end
L0_1(L1_1, L2_1)
L0_1 = Booths
function L1_1()
  local L0_2, L1_2, L2_2
  IsAtBooth = true
  L0_2 = TriggerServerEvent
  L1_2 = "rcore_prison:server:requestBooth"
  L2_2 = SH
  L2_2 = L2_2.zoneId
  L0_2(L1_2, L2_2)
end
L0_1.RequestOpen = L1_1
L0_1 = Booths
function L1_1()
  local L0_2, L1_2, L2_2
  L0_2 = dbg
  L0_2 = L0_2.debug
  L1_2 = "Booths.RequestEndCall"
  L0_2(L1_2)
  L0_2 = Booths
  L0_2 = L0_2.callSessionState
  if not L0_2 then
    return
  end
  L0_2 = IsAtBooth
  if not L0_2 then
    return
  end
  L0_2 = TriggerServerEvent
  L1_2 = "rcore_prison:server:requestBoothEndCall"
  L2_2 = SH
  L2_2 = L2_2.zoneId
  L0_2(L1_2, L2_2)
end
L0_1.RequestEndCall = L1_1
L0_1 = Booths
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.interaction
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.booth
  if not L1_2 then
    return
  end
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
  L5_2 = L5_2.BOOTH
  L4_2.screen = L5_2
  L4_2.visible = true
  L5_2 = L1_2.number
  L4_2.number = L5_2
  L2_2(L3_2, L4_2)
end
L0_1.OpenUI = L1_1
L0_1 = Booths
function L1_1()
  local L0_2, L1_2
  L0_2 = Booths
  L0_2.callSessionState = false
end
L0_1.Reset = L1_1
L0_1 = Booths
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = Booths
  L1_2 = L1_2.callSessionState
  if not L1_2 then
    return
  end
  L1_2 = Booths
  L1_2.callSessionState = false
  if A0_2 then
    L1_2 = dbg
    L1_2 = L1_2.debug
    L2_2 = "Booths: Found active callId, removing from active call using %s"
    L3_2 = A0_2
    L1_2(L2_2, L3_2)
    L1_2 = exports
    L1_2 = L1_2["pma-voice"]
    L2_2 = L1_2
    L1_2 = L1_2.removePlayerFromCall
    L3_2 = A0_2
    L1_2(L2_2, L3_2)
  end
  L1_2 = pcall
  function L2_2()
    local L0_3, L1_3
    L0_3 = HandleInventoryOpenState
    L1_3 = true
    L0_3(L1_3)
  end
  L1_2, L2_2 = L1_2(L2_2)
  L3_2 = HelpKeys
  L3_2 = L3_2.Hide
  L3_2()
  L3_2 = BoothAnim
  L4_2 = L3_2
  L3_2 = L3_2.Exit
  L3_2(L4_2)
  IsAtBooth = false
  L3_2 = dbg
  L3_2 = L3_2.debug
  L4_2 = "Booths.EndCall"
  L3_2(L4_2)
end
L0_1.EndCall = L1_1
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
CreateCameraAtEntity = L0_1
L0_1 = {}
L0_1.model = "sf_prop_sf_phonebox_01b_s"
L0_1.animDict = "anim@scripted@payphone_hits@male@"
L0_1.animName = "FXFR_PTD_1_INTRO_MALE"
L0_1.sceneCamera = "FXFR_PTD_1_CAM"
L0_1.scenePhone = "FXFR_PAV_1_INTRO_PHONE"
BoothAnim = L0_1
L0_1 = BoothAnim
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = 2.0
  L2_2 = GetClosestObjectOfType
  L3_2 = A0_2.plyCoords
  L3_2 = L3_2.x
  L4_2 = A0_2.plyCoords
  L4_2 = L4_2.y
  L5_2 = A0_2.plyCoords
  L5_2 = L5_2.z
  L6_2 = L1_2
  L7_2 = joaat
  L8_2 = A0_2.model
  L7_2 = L7_2(L8_2)
  L8_2 = false
  L9_2 = false
  L10_2 = false
  return L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2)
end
L0_1.GetClosest = L1_1
L0_1 = BoothAnim
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  A0_2.ped = L1_2
  L1_2 = GetEntityCoords
  L2_2 = A0_2.ped
  L1_2 = L1_2(L2_2)
  A0_2.plyCoords = L1_2
  L2_2 = A0_2
  L1_2 = A0_2.GetClosest
  L1_2 = L1_2(L2_2)
  A0_2.entity = L1_2
  L1_2 = RequestScriptAudioBank
  L2_2 = "payphone"
  L3_2 = false
  L4_2 = -1
  L1_2(L2_2, L3_2, L4_2)
  L1_2 = DoesEntityExist
  L2_2 = A0_2.entity
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L1_2 = SetFacialIdleAnimOverride
  L2_2 = A0_2.ped
  L3_2 = A0_2.animDict
  L4_2 = "fxfr_phl_1_intro_male_facial"
  L1_2(L2_2, L3_2, L4_2)
  L1_2 = BoothAnim
  L2_2 = L1_2
  L1_2 = L1_2.SetEntityAsNetworked
  L1_2, L2_2 = L1_2(L2_2)
  if not L1_2 then
    L3_2 = dbg
    L3_2 = L3_2.critical
    L4_2 = "Failed to set entity as networked"
    return L3_2(L4_2)
  end
  L3_2 = GetEntityRotation
  L4_2 = A0_2.entity
  L3_2 = L3_2(L4_2)
  A0_2.heading = L3_2
  L3_2 = GetOffsetFromEntityInWorldCoords
  L4_2 = A0_2.entity
  L5_2 = vec3
  L6_2 = 0
  L7_2 = 0
  L8_2 = 0
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2, L7_2, L8_2)
  L3_2 = L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
  A0_2.coords = L3_2
  L3_2 = true
  return L3_2
end
L0_1.Prepare = L1_1
L0_1 = BoothAnim
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L1_2 = NetworkGetEntityIsNetworked
  L2_2 = A0_2.entity
  L1_2 = L1_2(L2_2)
  if L1_2 then
    L1_2 = NetworkGetNetworkIdFromEntity
    L2_2 = A0_2.entity
    L1_2 = L1_2(L2_2)
  end
  if not L1_2 then
    L2_2 = GetEntityCoords
    L3_2 = A0_2.entity
    L2_2 = L2_2(L3_2)
    L3_2 = GetClosestObjectOfType
    L4_2 = L2_2.x
    L5_2 = L2_2.y
    L6_2 = L2_2.z
    L7_2 = 0.1
    L8_2 = GetEntityModel
    L9_2 = A0_2.entity
    L8_2 = L8_2(L9_2)
    L9_2 = true
    L10_2 = true
    L11_2 = true
    L3_2 = L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2)
    A0_2.entity = L3_2
    L3_2 = A0_2.entity
    L3_2 = NetworkGetNetworkIdFromEntity
    L4_2 = A0_2.entity
    L3_2 = L3_2(L4_2)
    L1_2 = 0 ~= L3_2 and L1_2
  end
  if L1_2 then
    L2_2 = true
    L3_2 = L1_2
    return L2_2, L3_2
  end
end
L0_1.SetEntityAsNetworked = L1_1
L0_1 = BoothAnim
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L1_2 = NetworkCreateSynchronisedScene
  L2_2 = A0_2.coords
  L2_2 = L2_2.x
  L3_2 = A0_2.coords
  L3_2 = L3_2.y
  L4_2 = A0_2.coords
  L4_2 = L4_2.z
  L5_2 = A0_2.heading
  L5_2 = L5_2.x
  L6_2 = A0_2.heading
  L6_2 = L6_2.y
  L7_2 = A0_2.heading
  L7_2 = L7_2.z
  L8_2 = 2
  L9_2 = true
  L10_2 = false
  L11_2 = 1065353216
  L12_2 = 0
  L13_2 = 1065353216
  L1_2 = L1_2(L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
  L2_2 = NetworkAddEntityToSynchronisedScene
  L3_2 = A0_2.entity
  L4_2 = L1_2
  L5_2 = A0_2.animDict
  L6_2 = A0_2.scenePhone
  L7_2 = 4.0
  L8_2 = -8.0
  L9_2 = 1
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2)
  L2_2 = NetworkAddPedToSynchronisedScene
  L3_2 = A0_2.ped
  L4_2 = L1_2
  L5_2 = A0_2.animDict
  L6_2 = A0_2.animName
  L7_2 = 4.0
  L8_2 = -4.0
  L9_2 = 1033
  L10_2 = 0
  L11_2 = 1000.0
  L12_2 = 0
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
  L2_2 = NetworkStartSynchronisedScene
  L3_2 = L1_2
  L2_2(L3_2)
end
L0_1.StartIntro = L1_1
L0_1 = BoothAnim
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L1_2 = NetworkCreateSynchronisedScene
  L2_2 = A0_2.coords
  L2_2 = L2_2.x
  L3_2 = A0_2.coords
  L3_2 = L3_2.y
  L4_2 = A0_2.coords
  L4_2 = L4_2.z
  L5_2 = A0_2.heading
  L5_2 = L5_2.x
  L6_2 = A0_2.heading
  L6_2 = L6_2.y
  L7_2 = A0_2.heading
  L7_2 = L7_2.z
  L8_2 = 2
  L9_2 = true
  L10_2 = false
  L11_2 = 1065353216
  L12_2 = 0
  L13_2 = 1065353216
  L1_2 = L1_2(L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
  L2_2 = NetworkAddEntityToSynchronisedScene
  L3_2 = A0_2.entity
  L4_2 = L1_2
  L5_2 = A0_2.animDict
  L6_2 = "wtf_exit_phone"
  L7_2 = 4.0
  L8_2 = -8.0
  L9_2 = 1
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2)
  L2_2 = NetworkAddPedToSynchronisedScene
  L3_2 = A0_2.ped
  L4_2 = L1_2
  L5_2 = A0_2.animDict
  L6_2 = "wtf_exit_male"
  L7_2 = 4.0
  L8_2 = -4.0
  L9_2 = 1033
  L10_2 = 0
  L11_2 = 1000.0
  L12_2 = 0
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
  L2_2 = NetworkStartSynchronisedScene
  L3_2 = L1_2
  L2_2(L3_2)
  L2_2 = GetAnimDuration
  L3_2 = A0_2.animDict
  L4_2 = "wtf_exit_phone"
  L2_2 = L2_2(L3_2, L4_2)
  L2_2 = L2_2 * 1000
  L3_2 = Wait
  L4_2 = L2_2
  L3_2(L4_2)
  L3_2 = NetworkStopSynchronisedScene
  L4_2 = L1_2
  L3_2(L4_2)
  L3_2 = RemoveAnimDict
  L4_2 = A0_2.animDict
  L3_2(L4_2)
end
L0_1.Exit = L1_1
L0_1 = RegisterNetEvent
L1_1 = "phone:phone:endCall"
function L2_1()
  local L0_2, L1_2
  L0_2 = Booths
  L0_2 = L0_2.callSessionState
  if L0_2 then
    L0_2 = Booths
    L0_2 = L0_2.RequestEndCall
    L0_2()
  end
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNetEvent
L1_1 = "phone:phone:connectCall"
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L1_2 = Booths
  L1_2 = L1_2.callSessionState
  if not L1_2 then
    return
  end
  L1_2 = GetGameTimer
  L1_2 = L1_2()
  L2_2 = BoothAnim
  L3_2 = L2_2
  L2_2 = L2_2.Prepare
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L3_2 = BoothAnim
    L4_2 = L3_2
    L3_2 = L3_2.StartIntro
    L3_2(L4_2)
  end
  L3_2 = pcall
  function L4_2()
    local L0_3, L1_3
    L0_3 = HandleInventoryOpenState
    L1_3 = true
    L0_3(L1_3)
  end
  L3_2, L4_2 = L3_2(L4_2)
  L5_2 = CreateThread
  function L6_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    while true do
      L0_3 = Booths
      L0_3 = L0_3.callSessionState
      if not L0_3 then
        break
      end
      L0_3 = Wait
      L1_3 = 1000
      L0_3(L1_3)
      L0_3 = Booths
      L0_3 = L0_3.callSessionState
      if not L0_3 then
        L0_3 = HelpKeys
        L0_3 = L0_3.Hide
        L0_3()
        break
      end
      L0_3 = tonumber
      L1_3 = math
      L1_3 = L1_3.floor
      L2_3 = GetGameTimer
      L2_3 = L2_3()
      L3_3 = L1_2
      L2_3 = L2_3 - L3_3
      L2_3 = L2_3 / 1000
      L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3 = L1_3(L2_3)
      L0_3 = L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3)
      L1_3 = HelpKeys
      L1_3 = L1_3.Show
      L2_3 = {}
      L3_3 = {}
      L4_3 = _U
      L5_3 = "BOOTHS.HANGUP_LABEL"
      L4_3 = L4_3(L5_3)
      L3_3.label = L4_3
      L3_3.keyName = "BACKSPACE"
      L4_3 = {}
      L5_3 = _U
      L6_3 = "BOOTHS.DURATION_LABEL"
      L7_3 = L0_3
      L5_3 = L5_3(L6_3, L7_3)
      L4_3.label = L5_3
      L4_3.keyName = ""
      L2_3[1] = L3_3
      L2_3[2] = L4_3
      L3_3 = "top-left"
      L1_3(L2_3, L3_3)
    end
  end
  L7_2 = "cl-lib-booth code name: Phoenix"
  L5_2(L6_2, L7_2)
end
L0_1(L1_1, L2_1)
L0_1 = Booths
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = Booths
  L2_2 = L2_2.callSessionState
  if L2_2 then
    return
  end
  L2_2 = Booths
  L2_2.callSessionState = true
  L2_2 = isResourceLoaded
  L3_2 = Phones
  L3_2 = L3_2.LB
  L2_2 = L2_2(L3_2)
  if L2_2 then
    return
  end
  L2_2 = GetGameTimer
  L2_2 = L2_2()
  L3_2 = BoothAnim
  L4_2 = L3_2
  L3_2 = L3_2.Prepare
  L3_2 = L3_2(L4_2)
  L4_2 = pcall
  function L5_2()
    local L0_3, L1_3
    L0_3 = HandleInventoryOpenState
    L1_3 = false
    L0_3(L1_3)
  end
  L4_2, L5_2 = L4_2(L5_2)
  if L3_2 then
    L6_2 = BoothAnim
    L7_2 = L6_2
    L6_2 = L6_2.StartIntro
    L6_2(L7_2)
  end
  if A1_2 then
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "Booths: Found active callId, adding to active call with id (%s)"
    L8_2 = A1_2
    L6_2(L7_2, L8_2)
    L6_2 = exports
    L6_2 = L6_2["pma-voice"]
    L7_2 = L6_2
    L6_2 = L6_2.addPlayerToCall
    L8_2 = A1_2
    L6_2(L7_2, L8_2)
  end
  L6_2 = CreateThread
  function L7_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    while true do
      L0_3 = Booths
      L0_3 = L0_3.callSessionState
      if not L0_3 then
        break
      end
      L0_3 = dbg
      L0_3 = L0_3.debug
      L1_3 = "Booths: Call session state active."
      L0_3(L1_3)
      L0_3 = Wait
      L1_3 = 1000
      L0_3(L1_3)
      L0_3 = Booths
      L0_3 = L0_3.callSessionState
      if not L0_3 then
        L0_3 = HelpKeys
        L0_3 = L0_3.Hide
        L0_3()
        break
      end
      L0_3 = tonumber
      L1_3 = math
      L1_3 = L1_3.floor
      L2_3 = GetGameTimer
      L2_3 = L2_3()
      L3_3 = L2_2
      L2_3 = L2_3 - L3_3
      L2_3 = L2_3 / 1000
      L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3 = L1_3(L2_3)
      L0_3 = L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3)
      L1_3 = HelpKeys
      L1_3 = L1_3.Show
      L2_3 = {}
      L3_3 = {}
      L4_3 = _U
      L5_3 = "BOOTHS.HANGUP_LABEL"
      L4_3 = L4_3(L5_3)
      L3_3.label = L4_3
      L3_3.keyName = "BACKSPACE"
      L4_3 = {}
      L5_3 = _U
      L6_3 = "BOOTHS.DURATION_LABEL"
      L7_3 = L0_3
      L5_3 = L5_3(L6_3, L7_3)
      L4_3.label = L5_3
      L4_3.keyName = ""
      L2_3[1] = L3_3
      L2_3[2] = L4_3
      L3_3 = "top-left"
      L1_3(L2_3, L3_3)
    end
  end
  L8_2 = "cl-lib-booth code name: Omega"
  L6_2(L7_2, L8_2)
end
L0_1.StartCall = L1_1
L0_1 = RegisterKey
L1_1 = Booths
L1_1 = L1_1.RequestEndCall
L2_1 = "TEST_A"
L3_1 = "TEST_B"
L4_1 = "BACK"
L0_1(L1_1, L2_1, L3_1, L4_1)
