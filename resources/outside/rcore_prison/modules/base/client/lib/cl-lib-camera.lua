local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = false
L1_1 = false
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L2_2 = {}
  L3_2 = CreateCamWithParams
  L4_2 = "DEFAULT_SCRIPTED_CAMERA"
  L5_2 = A0_2.x
  L6_2 = A0_2.y
  L7_2 = A0_2.z
  L8_2 = A1_2.x
  L9_2 = A1_2.y
  L10_2 = A1_2.z
  L11_2 = GetGameplayCamFov
  L11_2 = L11_2()
  L12_2 = false
  L13_2 = 0
  L3_2 = L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
  L2_2.cameraEntity = L3_2
  L3_2 = {}
  L2_2.activeEffects = L3_2
  L3_2 = {}
  L2_2.activeFxEffects = L3_2
  L2_2.isPointing = false
  function L3_2()
    local L0_3, L1_3, L2_3
    L0_3 = L2_2.canSkip
    L0_3 = not L0_3
    L2_2.canSkip = L0_3
    L0_3 = dbg
    L0_3 = L0_3.debug
    L1_3 = "Camera is skippable: %s"
    L2_3 = L2_2.canSkip
    L0_3(L1_3, L2_3)
    L0_3 = L2_2.canSkip
    if L0_3 then
      L0_3 = CreateThread
      function L1_3()
        local L0_4, L1_4, L2_4
        while true do
          L0_4 = L2_2.canSkip
          if not L0_4 then
            break
          end
          L0_4 = IsDisabledControlJustReleased
          L1_4 = 0
          L2_4 = 38
          L0_4 = L0_4(L1_4, L2_4)
          if L0_4 then
            L0_4 = dbg
            L0_4 = L0_4.debug
            L1_4 = "Camera has been skipped"
            L0_4(L1_4)
            L2_2.skipped = true
            L2_2.canSkip = false
            L0_4 = L2_2.StopAllFXEffects
            L0_4()
            L0_4 = Subtitles
            L0_4 = L0_4.Hide
            L0_4()
            L0_4 = HelpKeys
            L0_4 = L0_4.Hide
            L0_4()
            L0_4 = SetTimeout
            L1_4 = 1000
            function L2_4()
              local L0_5, L1_5
              L0_5 = DisplayRadar
              L1_5 = true
              L0_5(L1_5)
              L0_5 = NetworkEndTutorialSession
              L0_5()
              L0_5 = Subtitles
              L0_5 = L0_5.Hide
              L0_5()
              L0_5 = HelpKeys
              L0_5 = L0_5.Hide
              L0_5()
            end
            L0_4(L1_4, L2_4)
            L0_4 = L2_2.exitCameraSmoothly
            L1_4 = 0
            L0_4(L1_4)
            break
          end
          L0_4 = Citizen
          L0_4 = L0_4.Wait
          L1_4 = 0
          L0_4(L1_4)
        end
      end
      L2_3 = "cl-lib-camera code name: Phoenix"
      L0_3(L1_3, L2_3)
    end
  end
  L2_2.skippable = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3
    L1_3 = pairs
    L2_3 = A0_3
    L1_3, L2_3, L3_3, L4_3 = L1_3(L2_3)
    for L5_3, L6_3 in L1_3, L2_3, L3_3, L4_3 do
      L7_3 = {}
      L8_3 = L6_3.effectName
      L7_3.effectName = L8_3
      L8_3 = L6_3.intensity
      L7_3.intensity = L8_3
      L8_3 = L2_2.activeEffects
      L9_3 = L6_3.type
      L8_3[L9_3] = L7_3
      L8_3 = playEffectOnCamera
      L9_3 = L2_2.cameraEntity
      L10_3 = L6_3.type
      L11_3 = L7_3
      L8_3(L9_3, L10_3, L11_3)
    end
  end
  L2_2.playCameraEffects = L3_2
  function L3_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3
    L2_3 = pairs
    L3_3 = A0_3
    L2_3, L3_3, L4_3, L5_3 = L2_3(L3_3)
    for L6_3, L7_3 in L2_3, L3_3, L4_3, L5_3 do
      L8_3 = L2_2.activeEffects
      L9_3 = L7_3.type
      L8_3[L9_3] = L7_3
    end
    L2_3 = CreateThread
    function L3_3()
      local L0_4, L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4
      L0_4 = L2_2.getCameraCoords
      L0_4 = L0_4()
      L1_4 = L2_2.getCameraRotation
      L1_4 = L1_4()
      L2_4 = CreateCamWithParams
      L3_4 = "DEFAULT_SCRIPTED_CAMERA"
      L4_4 = L0_4.x
      L5_4 = L0_4.y
      L6_4 = L0_4.z
      L7_4 = L1_4.x
      L8_4 = L1_4.y
      L9_4 = L1_4.z
      L10_4 = L2_2.getCameraFov
      L10_4 = L10_4()
      L11_4 = false
      L12_4 = 0
      L2_4 = L2_4(L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4)
      L3_4 = SetCamActiveWithInterp
      L4_4 = L2_4
      L5_4 = L2_2.cameraEntity
      L6_4 = A1_3
      L7_4 = 1
      L8_4 = 1
      L3_4(L4_4, L5_4, L6_4, L7_4, L8_4)
      L3_4 = pairs
      L4_4 = L2_2.activeEffects
      L3_4, L4_4, L5_4, L6_4 = L3_4(L4_4)
      for L7_4, L8_4 in L3_4, L4_4, L5_4, L6_4 do
        L9_4 = playEffectOnCamera
        L10_4 = L2_4
        L11_4 = L7_4
        L12_4 = L8_4
        L9_4(L10_4, L11_4, L12_4)
      end
      L3_4 = Wait
      L4_4 = A1_3
      L3_4(L4_4)
      L3_4 = SetCamActive
      L4_4 = L2_2.cameraEntity
      L5_4 = false
      L3_4(L4_4, L5_4)
      L3_4 = DestroyCam
      L4_4 = L2_2.cameraEntity
      L3_4(L4_4)
      L2_2.cameraEntity = L2_4
      L3_4 = L2_2.startRendering
      L3_4()
    end
    L4_3 = "cl-lib-camera code name: Omega"
    L2_3(L3_3, L4_3)
  end
  L2_2.playerCameraEffectsInDuration = L3_2
  function L3_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3
    L2_3 = pairs
    L3_3 = L2_2.activeEffects
    L2_3, L3_3, L4_3, L5_3 = L2_3(L3_3)
    for L6_3, L7_3 in L2_3, L3_3, L4_3, L5_3 do
      if L6_3 == A0_3 then
        L8_3 = L2_2.activeEffects
        L8_3[L6_3] = nil
      end
    end
    L2_3 = CreateThread
    function L3_3()
      local L0_4, L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4
      L0_4 = L2_2.getCameraCoords
      L0_4 = L0_4()
      L1_4 = L2_2.getCameraRotation
      L1_4 = L1_4()
      L2_4 = CreateCamWithParams
      L3_4 = "DEFAULT_SCRIPTED_CAMERA"
      L4_4 = L0_4.x
      L5_4 = L0_4.y
      L6_4 = L0_4.z
      L7_4 = L1_4.x
      L8_4 = L1_4.y
      L9_4 = L1_4.z
      L10_4 = L2_2.getCameraFov
      L10_4 = L10_4()
      L11_4 = false
      L12_4 = 0
      L2_4 = L2_4(L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4)
      L3_4 = pairs
      L4_4 = L2_2.activeEffects
      L3_4, L4_4, L5_4, L6_4 = L3_4(L4_4)
      for L7_4, L8_4 in L3_4, L4_4, L5_4, L6_4 do
        L9_4 = playEffectOnCamera
        L10_4 = L2_4
        L11_4 = L7_4
        L12_4 = L8_4
        L9_4(L10_4, L11_4, L12_4)
      end
      L3_4 = SetCamActiveWithInterp
      L4_4 = L2_4
      L5_4 = L2_2.cameraEntity
      L6_4 = A1_3
      L7_4 = true
      L8_4 = true
      L3_4(L4_4, L5_4, L6_4, L7_4, L8_4)
      L3_4 = Wait
      L4_4 = A1_3
      L3_4(L4_4)
      L3_4 = SetCamActive
      L4_4 = L2_2.cameraEntity
      L5_4 = false
      L3_4(L4_4, L5_4)
      L3_4 = DestroyCam
      L4_4 = L2_2.cameraEntity
      L3_4(L4_4)
      L2_2.cameraEntity = L2_4
      L3_4 = L2_2.startRendering
      L3_4()
    end
    L4_3 = "cl-lib-camera code name: Beta"
    L2_3(L3_3, L4_3)
  end
  L2_2.stopCameraEffects = L3_2
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3
    L3_3 = L2_2.activeFxEffects
    L4_3 = {}
    L4_3.duration = A1_3
    L4_3.looped = A2_3
    L4_3.effectName = A0_3
    L3_3[A0_3] = L4_3
    L3_3 = IsCamActive
    L4_3 = L2_2.cameraEntity
    L3_3 = L3_3(L4_3)
    if not L3_3 then
      return
    end
    L3_3 = AnimpostfxPlay
    L4_3 = A0_3
    L5_3 = A1_3
    L6_3 = A2_3
    L3_3(L4_3, L5_3, L6_3)
  end
  L2_2.ActiveFXEffect = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3
    L1_3 = L2_2.activeFxEffects
    L1_3[A0_3] = nil
    L1_3 = AnimpostfxStop
    L2_3 = A0_3
    L1_3(L2_3)
  end
  L2_2.StopFXeffect = L3_2
  function L3_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L0_3 = pairs
    L1_3 = L2_2.activeFxEffects
    L0_3, L1_3, L2_3, L3_3 = L0_3(L1_3)
    for L4_3, L5_3 in L0_3, L1_3, L2_3, L3_3 do
      L6_3 = AnimpostfxStop
      L7_3 = L4_3
      L6_3(L7_3)
    end
    L0_3 = {}
    L2_2.activeFxEffects = L0_3
  end
  L2_2.StopAllFXEffects = L3_2
  function L3_2()
    local L0_3, L1_3
    L0_3 = L2_2.activeFxEffects
    return L0_3
  end
  L2_2.GetAllActiveFXEffects = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3
    L1_3 = L2_2.playCameraEffects
    L2_3 = {}
    L3_3 = {}
    L4_3 = CameraEffect
    L4_3 = L4_3.BLUR
    L3_3.type = L4_3
    L3_3.intensity = A0_3
    L2_3[1] = L3_3
    L1_3(L2_3)
  end
  L2_2.setMotionBlurStrength = L3_2
  function L3_2()
    local L0_3, L1_3
    L0_3 = L2_2.activeEffects
    L1_3 = CameraEffect
    L1_3 = L1_3.BLUR
    L0_3 = L0_3[L1_3]
    if L0_3 then
      L1_3 = L0_3.intensity
      return L1_3
    end
    L1_3 = 0.0
    return L1_3
  end
  L2_2.getMotionBlurStrength = L3_2
  function L3_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3
    L2_3 = L2_2.playerCameraEffectsInDuration
    L3_3 = {}
    L4_3 = {}
    L5_3 = CameraEffect
    L5_3 = L5_3.BLUR
    L4_3.type = L5_3
    L4_3.intensity = A0_3
    L3_3[1] = L4_3
    L4_3 = A1_3
    L2_3(L3_3, L4_3)
  end
  L2_2.lerpMortionBlurStrength = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L1_3 = IsCamActive
    L2_3 = L2_2.cameraEntity
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      return
    end
    if not A0_3 then
      A0_3 = 3000
    end
    L1_3 = PlayerPedId
    L1_3 = L1_3()
    L2_3 = FreezeEntityPosition
    L3_3 = L1_3
    L4_3 = true
    L2_3(L3_3, L4_3)
    L2_3 = FreezePlayerControls
    L3_3 = true
    L2_3(L3_3)
    L2_3 = Wait
    L3_3 = 200
    L2_3(L3_3)
    L2_3 = L2_2.moveCameraSmoothlyToCoords
    L3_3 = GetGameplayCamCoord
    L3_3 = L3_3()
    L4_3 = GetGameplayCamRot
    L4_3 = L4_3()
    L5_3 = A0_3
    L6_3 = {}
    L7_3 = GetGameplayCamFov
    L7_3 = L7_3()
    L6_3.fov = L7_3
    L2_3(L3_3, L4_3, L5_3, L6_3)
    L2_3 = FreezeEntityPosition
    L3_3 = L1_3
    L4_3 = false
    L2_3(L3_3, L4_3)
    L2_3 = FreezePlayerControls
    L3_3 = false
    L2_3(L3_3)
    L2_2.cameraEntity = nil
    L2_3 = L2_2.stopRendering
    L2_3()
  end
  L2_2.exitCameraSmoothly = L3_2
  function L3_2()
    local L0_3, L1_3
    L0_3 = L2_2.activeEffects
    L1_3 = CameraEffect
    L1_3 = L1_3.SHAKE_CAMERA
    L0_3 = L0_3[L1_3]
    if L0_3 then
      L1_3 = L0_3.intensity
      return L1_3
    end
    L1_3 = 0.0
    return L1_3
  end
  L2_2.getShakeCameraIntensity = L3_2
  function L3_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3
    L2_3 = L2_2.playCameraEffects
    L3_3 = {}
    L4_3 = {}
    L5_3 = CameraEffect
    L5_3 = L5_3.SHAKE_CAMERA
    L4_3.type = L5_3
    L4_3.effectName = A0_3
    L4_3.intensity = A1_3
    L3_3[1] = L4_3
    L2_3(L3_3)
  end
  L2_2.shakeCamera = L3_2
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3
    L3_3 = L2_2.playerCameraEffectsInDuration
    L4_3 = {}
    L5_3 = {}
    L6_3 = CameraEffect
    L6_3 = L6_3.SHAKE_CAMERA
    L5_3.type = L6_3
    L5_3.effectName = A0_3
    L5_3.intensity = A1_3
    L4_3[1] = L5_3
    L5_3 = A2_3
    L3_3(L4_3, L5_3)
  end
  L2_2.lerpShakeCamera = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3
    L1_3 = L2_2.stopCameraEffects
    L2_3 = CameraEffect
    L2_3 = L2_3.SHAKE_CAMERA
    L3_3 = A0_3
    L1_3(L2_3, L3_3)
  end
  L2_2.stopShakeCamera = L3_2
  function L3_2(A0_3, A1_3, A2_3, A3_3, A4_3, A5_3, A6_3, A7_3, A8_3)
    local L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3
    L9_3 = IsCamActive
    L10_3 = L2_2.cameraEntity
    L9_3 = L9_3(L10_3)
    if not L9_3 then
      return
    end
    if not A3_3 then
      L9_3 = {}
      L10_3 = L2_2.getCameraFov
      L10_3 = L10_3()
      L9_3.fov = L10_3
      L9_3.copyEffects = false
      L9_3.offsetDuration = 0
      A3_3 = L9_3
    end
    L9_3 = L2_2.skipped
    if L9_3 then
      return
    end
    L9_3 = L2_2.stopFocusing
    L9_3()
    L9_3 = CreateCamWithParams
    L10_3 = "DEFAULT_SCRIPTED_CAMERA"
    L11_3 = A0_3.x
    L12_3 = A0_3.y
    L13_3 = A0_3.z
    L14_3 = A1_3.x
    L15_3 = A1_3.y
    L16_3 = A1_3.z
    L17_3 = A3_3.fov
    if not L17_3 then
      L17_3 = L2_2.getCameraFov
      L17_3 = L17_3()
    end
    L18_3 = false
    L19_3 = 0
    L9_3 = L9_3(L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3)
    L10_3 = A3_3.copyEffects
    if L10_3 then
      L10_3 = pairs
      L11_3 = L2_2.activeEffects
      L10_3, L11_3, L12_3, L13_3 = L10_3(L11_3)
      for L14_3, L15_3 in L10_3, L11_3, L12_3, L13_3 do
        L16_3 = playEffectOnCamera
        L17_3 = L9_3
        L18_3 = L14_3
        L19_3 = L15_3
        L16_3(L17_3, L18_3, L19_3)
      end
    end
    L10_3 = SetCamActiveWithInterp
    L11_3 = L9_3
    L12_3 = L2_2.cameraEntity
    L13_3 = A2_3
    L14_3 = true
    L15_3 = true
    L10_3(L11_3, L12_3, L13_3, L14_3, L15_3)
    L10_3 = SetTimeout
    L11_3 = A5_3 or L11_3
    if not A5_3 then
      L11_3 = 0
    end
    function L12_3()
      local L0_4, L1_4
      L0_4 = A4_3
      if not L0_4 then
        return
      end
      L0_4 = Subtitles
      L0_4 = L0_4.Show
      L1_4 = A4_3
      L0_4(L1_4)
    end
    L10_3(L11_3, L12_3)
    L10_3 = L2_2.skipped
    if L10_3 then
      return
    end
    L10_3 = GetGameTimer
    L10_3 = L10_3()
    L10_3 = L10_3 + A2_3
    L11_3 = A3_3.offsetDuration
    if not L11_3 then
      L11_3 = 0
    end
    L10_3 = L10_3 - L11_3
    while true do
      L11_3 = GetGameTimer
      L11_3 = L11_3()
      if not (L10_3 > L11_3) then
        break
      end
      L11_3 = L2_2.skipped
      if L11_3 then
        L11_3 = SetCamActive
        L12_3 = L9_3
        L13_3 = false
        L11_3(L12_3, L13_3)
        L11_3 = DestroyCam
        L12_3 = L9_3
        L11_3(L12_3)
        L11_3 = DestroyCam
        L12_3 = L2_2.cameraEntity
        L11_3(L12_3)
        L2_2.cameraEntity = nil
        return
      end
      L11_3 = Wait
      L12_3 = 0
      L11_3(L12_3)
    end
    L11_3 = L2_2.skipped
    if L11_3 then
      L11_3 = SetCamActive
      L12_3 = L9_3
      L13_3 = false
      L11_3(L12_3, L13_3)
      L11_3 = DestroyCam
      L12_3 = L9_3
      L11_3(L12_3)
      L11_3 = DestroyCam
      L12_3 = L2_2.cameraEntity
      L11_3(L12_3)
      L2_2.cameraEntity = nil
      return
    end
    L11_3 = L2_2.skipped
    if L11_3 then
      return
    end
    L11_3 = SetCamActive
    L12_3 = L2_2.cameraEntity
    L13_3 = false
    L11_3(L12_3, L13_3)
    L11_3 = DestroyCam
    L12_3 = L2_2.cameraEntity
    L11_3(L12_3)
    L2_2.cameraEntity = L9_3
    L11_3 = L2_2.startRendering
    L11_3()
  end
  L2_2.moveCameraSmoothlyToCoords = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3
    L2_2.cameraSmoothPoints = A0_3
    L1_3 = pairs
    L2_3 = L2_2.cameraSmoothPoints
    L1_3, L2_3, L3_3, L4_3 = L1_3(L2_3)
    for L5_3, L6_3 in L1_3, L2_3, L3_3, L4_3 do
      L7_3 = L2_2.skipped
      if L7_3 then
        break
      end
      L7_3 = L2_2.moveCameraSmoothlyToCoords
      L8_3 = L6_3.pos
      L9_3 = L6_3.rot
      L10_3 = L6_3.duration
      L11_3 = L6_3.options
      L12_3 = L6_3.text
      L13_3 = L6_3.textTimeout
      L14_3 = L6_3.textRenderTime
      L15_3 = L6_3.model
      L16_3 = L5_3
      L7_3(L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3)
    end
    L1_3 = HelpKeys
    L1_3 = L1_3.Hide
    L1_3()
    L1_3 = Subtitles
    L1_3 = L1_3.Hide
    L1_3()
  end
  L2_2.moveCameraSmoothlyFromPoints = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = PointCamAtCoord
    L2_3 = L2_2.cameraEntity
    L3_3 = A0_3.x
    L4_3 = A0_3.y
    L5_3 = A0_3.z
    L1_3(L2_3, L3_3, L4_3, L5_3)
    L2_2.isPointing = true
  end
  L2_2.focusCameraOnCoords = L3_2
  function L3_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3
    if not A1_3 then
      L2_3 = vector3
      L3_3 = 0
      L4_3 = 0
      L5_3 = 0
      L2_3 = L2_3(L3_3, L4_3, L5_3)
      A1_3 = L2_3
    end
    L2_3 = PointCamAtEntity
    L3_3 = L2_2.cameraEntity
    L4_3 = A0_3
    L5_3 = A1_3.x
    L6_3 = A1_3.y
    L7_3 = A1_3.z
    L8_3 = 1
    L2_3(L3_3, L4_3, L5_3, L6_3, L7_3, L8_3)
    L2_2.isPointing = true
  end
  L2_2.focusCameraOnEntity = L3_2
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3
    L3_3 = PointCamAtPedBone
    L4_3 = L2_2.cameraEntity
    L5_3 = A0_3
    L6_3 = A1_3
    L7_3 = A2_3.x
    L8_3 = A2_3.y
    L9_3 = A2_3.z
    L10_3 = 1
    L3_3(L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3)
    L2_2.isPointing = true
  end
  L2_2.focusCameraOnPedBone = L3_2
  function L3_2()
    local L0_3, L1_3
    L0_3 = StopCamPointing
    L1_3 = L2_2.cameraEntity
    L0_3(L1_3)
    L2_2.isPointing = false
  end
  L2_2.stopFocusing = L3_2
  function L3_2()
    local L0_3, L1_3
    L0_3 = L2_2.isPointing
    return L0_3
  end
  L2_2.isCameraFocusing = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3
    L1_3 = SetCamRot
    L2_3 = L2_2.cameraEntity
    L3_3 = A0_3.x
    L4_3 = A0_3.y
    L5_3 = A0_3.z
    L6_3 = 2
    L1_3(L2_3, L3_3, L4_3, L5_3, L6_3)
  end
  L2_2.setCameraRotation = L3_2
  function L3_2()
    local L0_3, L1_3, L2_3
    L0_3 = GetCamRot
    L1_3 = L2_2.cameraEntity
    L2_3 = 2
    return L0_3(L1_3, L2_3)
  end
  L2_2.getCameraRotation = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = SetCamCoord
    L2_3 = L2_2.cameraEntity
    L3_3 = A0_3.x
    L4_3 = A0_3.y
    L5_3 = A0_3.z
    L1_3(L2_3, L3_3, L4_3, L5_3)
  end
  L2_2.setCameraCoords = L3_2
  function L3_2()
    local L0_3, L1_3
    L0_3 = GetCamCoord
    L1_3 = L2_2.cameraEntity
    return L0_3(L1_3)
  end
  L2_2.getCameraCoords = L3_2
  function L3_2(A0_3)
    local L1_3, L2_3, L3_3
    L1_3 = SetCamFov
    L2_3 = L2_2.cameraEntity
    L3_3 = A0_3
    L1_3(L2_3, L3_3)
  end
  L2_2.setCameraFov = L3_2
  function L3_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3
    L2_3 = L2_2.moveCameraSmoothlyToCoords
    L3_3 = L2_2.getCameraCoords
    L3_3 = L3_3()
    L4_3 = L2_2.getCameraRotation
    L4_3 = L4_3()
    L5_3 = A1_3
    L6_3 = {}
    L6_3.fov = A0_3
    L6_3.copyEffects = true
    L2_3(L3_3, L4_3, L5_3, L6_3)
  end
  L2_2.lerpCameraFov = L3_2
  function L3_2()
    local L0_3, L1_3
    L0_3 = GetCamFov
    L1_3 = L2_2.cameraEntity
    return L0_3(L1_3)
  end
  L2_2.getCameraFov = L3_2
  function L3_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3
    L0_3 = SetCamActive
    L1_3 = L2_2.cameraEntity
    L2_3 = true
    L0_3(L1_3, L2_3)
    L0_3 = RenderScriptCams
    L1_3 = true
    L2_3 = true
    L3_3 = 1
    L4_3 = true
    L5_3 = true
    L0_3(L1_3, L2_3, L3_3, L4_3, L5_3)
    L0_3 = pairs
    L1_3 = L2_2.activeFxEffects
    L0_3, L1_3, L2_3, L3_3 = L0_3(L1_3)
    for L4_3, L5_3 in L0_3, L1_3, L2_3, L3_3 do
      L6_3 = AnimpostfxStop
      L7_3 = L4_3
      L6_3(L7_3)
      L6_3 = AnimpostfxPlay
      L7_3 = L5_3.effectName
      L8_3 = L5_3.duration
      L9_3 = L5_3.looped
      L6_3(L7_3, L8_3, L9_3)
    end
  end
  L2_2.startRendering = L3_2
  function L3_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L0_3 = SetCamActive
    L1_3 = L2_2.cameraEntity
    L2_3 = false
    L0_3(L1_3, L2_3)
    L0_3 = RenderScriptCams
    L1_3 = false
    L2_3 = false
    L3_3 = 1
    L4_3 = false
    L5_3 = false
    L0_3(L1_3, L2_3, L3_3, L4_3, L5_3)
    L0_3 = pairs
    L1_3 = L2_2.activeFxEffects
    L0_3, L1_3, L2_3, L3_3 = L0_3(L1_3)
    for L4_3, L5_3 in L0_3, L1_3, L2_3, L3_3 do
      L6_3 = AnimpostfxStop
      L7_3 = L4_3
      L6_3(L7_3)
    end
  end
  L2_2.stopRendering = L3_2
  function L3_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3
    L0_3 = IsCamActive
    L1_3 = L2_2.cameraEntity
    L0_3 = L0_3(L1_3)
    if L0_3 then
      L0_3 = RenderScriptCams
      L1_3 = false
      L2_3 = false
      L3_3 = 1
      L4_3 = false
      L5_3 = false
      L0_3(L1_3, L2_3, L3_3, L4_3, L5_3)
    end
    L0_3 = SetCamActive
    L1_3 = L2_2.cameraEntity
    L2_3 = false
    L0_3(L1_3, L2_3)
    L0_3 = DestroyCam
    L1_3 = L2_2.cameraEntity
    L0_3(L1_3)
  end
  L2_2.disposeCamera = L3_2
  function L3_2()
    local L0_3, L1_3
    L0_3 = L2_2.cameraEntity
    return L0_3
  end
  L2_2.getCameraEntity = L3_2
  return L2_2
end
CreateCameraLib = L2_1
function L2_1(A0_2)
  local L1_2
  L0_1 = A0_2
end
FreezePlayerControls = L2_1
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2
  L3_2 = CameraEffect
  L3_2 = L3_2.SHAKE_CAMERA
  if A1_2 == L3_2 then
    L3_2 = ShakeCam
    L4_2 = A0_2
    L5_2 = A2_2.effectName
    L6_2 = A2_2.intensity
    L3_2(L4_2, L5_2, L6_2)
  end
  L3_2 = CameraEffect
  L3_2 = L3_2.BLUR
  if A1_2 == L3_2 then
    L3_2 = SetCamMotionBlurStrength
    L4_2 = A0_2
    L5_2 = A2_2.intensity
    L3_2(L4_2, L5_2)
  end
end
playEffectOnCamera = L2_1
L2_1 = CreateThread
function L3_1()
  local L0_2, L1_2
  while true do
    L0_2 = Wait
    L1_2 = 0
    L0_2(L1_2)
    L0_2 = L0_1
    if not L0_2 then
      L0_2 = Wait
      L1_2 = 100
      L0_2(L1_2)
    else
      L0_2 = DisableAllControlActions
      L1_2 = 0
      L0_2(L1_2)
      L0_2 = DisableAllControlActions
      L1_2 = 1
      L0_2(L1_2)
      L0_2 = DisableAllControlActions
      L1_2 = 2
      L0_2(L1_2)
    end
  end
end
L4_1 = "cl-lib-camera code name: Bravo"
L2_1(L3_1, L4_1)
function L2_1()
  local L0_2, L1_2
  L0_2 = L0_1
  if L0_2 then
    L0_2 = true
    L1_1 = L0_2
    L0_2 = dbg
    L0_2 = L0_2.critical
    L1_2 = "Prolog was skipped"
    L0_2(L1_2)
  end
end
SkipProlog = L2_1
