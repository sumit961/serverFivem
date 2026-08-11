local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1, L11_1
L0_1 = false
L1_1 = false
TASK_PROCESSING_STEPPER = false
L2_1 = nil
L3_1 = 0
L4_1 = false
L5_1 = false
L6_1 = {}
L7_1 = {}
function L8_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_1 = A1_2
  L2_2 = CreateThread
  function L3_2()
    local L0_3, L1_3
    L0_3 = StartStepper
    L1_3 = A0_2
    L0_3(L1_3)
  end
  L4_2 = "cl-lib-stepper code name: Phoenix"
  L2_2(L3_2, L4_2)
end
L7_1.LoadAndStart = L8_1
Stepper = L7_1
function L7_1()
  local L0_2, L1_2
  L0_2 = false
  L0_1 = L0_2
  L0_2 = true
  L1_1 = L0_2
  L0_2 = HelpKeys
  L0_2 = L0_2.Hide
  L0_2()
  L0_2 = ClearCycle
  L1_2 = "STEPPER"
  L0_2(L1_2)
end
StopStepper = L7_1
function L7_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2, L26_2, L27_2
  L1_2 = TASK_PROCESSING_STEPPER
  if L1_2 then
    L1_2 = error
    L2_2 = "Task is already processing"
    return L1_2(L2_2)
  end
  TASK_PROCESSING_STEPPER = true
  L1_2 = A0_2.animMap
  L2_2 = A0_2.skillMap
  L3_2 = A0_2.label
  if not L1_2 then
    TASK_PROCESSING_STEPPER = false
    L4_2 = error
    L5_2 = "Animation list is empty"
    return L4_2(L5_2)
  end
  if not L2_2 then
    TASK_PROCESSING_STEPPER = false
    L4_2 = error
    L5_2 = "Skill map is empty"
    return L4_2(L5_2)
  end
  if not L3_2 then
    TASK_PROCESSING_STEPPER = false
    L4_2 = error
    L5_2 = "Stepper label is empty"
    return L4_2(L5_2)
  end
  L4_2 = pairs
  L5_2 = L1_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = LoadAnimDict
    L11_2 = L9_2.dict
    L10_2(L11_2)
  end
  L4_2 = PlayerPedId
  L4_2 = L4_2()
  L5_2 = GetEntityCoords
  L6_2 = L4_2
  L5_2 = L5_2(L6_2)
  L6_2 = GetEntityHeading
  L7_2 = L4_2
  L6_2 = L6_2(L7_2)
  L7_2 = FreezeEntityPosition
  L8_2 = L4_2
  L9_2 = true
  L7_2(L8_2, L9_2)
  L7_2 = SetEntityHeading
  L8_2 = L4_2
  L9_2 = L6_2
  L7_2(L8_2, L9_2)
  L7_2 = nil
  L8_2 = A0_2.prop
  if L8_2 then
    L8_2 = A0_2.prop
    L8_2 = L8_2.model
    L9_2 = vec3
    L10_2 = 0
    L11_2 = 0
    L12_2 = -1.0
    L9_2 = L9_2(L10_2, L11_2, L12_2)
    L9_2 = L5_2 + L9_2
    L10_2 = L6_2
    L11_2 = RequestModel
    L12_2 = L8_2
    L11_2(L12_2)
    while true do
      L11_2 = HasModelLoaded
      L12_2 = L8_2
      L11_2 = L11_2(L12_2)
      if L11_2 then
        break
      end
      L11_2 = Wait
      L12_2 = 0
      L11_2(L12_2)
    end
    L11_2 = CreateObject
    L12_2 = L8_2
    L13_2 = L9_2.x
    L14_2 = L9_2.y
    L15_2 = L9_2.z
    L16_2 = true
    L17_2 = true
    L18_2 = true
    L11_2 = L11_2(L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
    L7_2 = L11_2
    L11_2 = SetEntityHeading
    L12_2 = L7_2
    L13_2 = L10_2
    L11_2(L12_2, L13_2)
    L11_2 = GetPedBoneIndex
    L12_2 = L4_2
    L13_2 = A0_2.prop
    L13_2 = L13_2.hand
    if not L13_2 then
      L13_2 = 57005
    end
    L11_2 = L11_2(L12_2, L13_2)
    L12_2 = AttachEntityToEntity
    L13_2 = L7_2
    L14_2 = L4_2
    L15_2 = L11_2
    L16_2 = A0_2.prop
    L16_2 = L16_2.offset
    L16_2 = L16_2.pos
    L16_2 = L16_2.x
    L17_2 = A0_2.prop
    L17_2 = L17_2.offset
    L17_2 = L17_2.pos
    L17_2 = L17_2.y
    L18_2 = A0_2.prop
    L18_2 = L18_2.offset
    L18_2 = L18_2.pos
    L18_2 = L18_2.z
    L19_2 = A0_2.prop
    L19_2 = L19_2.offset
    L19_2 = L19_2.rot
    L19_2 = L19_2.x
    L20_2 = A0_2.prop
    L20_2 = L20_2.offset
    L20_2 = L20_2.rot
    L20_2 = L20_2.y
    L21_2 = A0_2.prop
    L21_2 = L21_2.offset
    L21_2 = L21_2.rot
    L21_2 = L21_2.z
    L22_2 = true
    L23_2 = true
    L24_2 = true
    L25_2 = false
    L26_2 = 1
    L27_2 = true
    L12_2(L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2, L26_2, L27_2)
    L12_2 = SetModelAsNoLongerNeeded
    L13_2 = L7_2
    L12_2(L13_2)
  end
  L8_2 = Jobs
  L8_2.Entity = L7_2
  L8_2 = TaskPlayAnim
  L9_2 = L4_2
  L10_2 = L1_2.ENTER
  L10_2 = L10_2.dict
  L11_2 = L1_2.ENTER
  L11_2 = L11_2.name
  L12_2 = 8.0
  L13_2 = -8.0
  L14_2 = L1_2.ENTER
  L14_2 = L14_2.time
  L15_2 = 0
  L16_2 = 0
  L17_2 = 0
  L18_2 = 0
  L19_2 = 0
  L8_2(L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2)
  L8_2 = HelpKeys
  L8_2 = L8_2.Show
  L9_2 = {}
  L10_2 = {}
  L11_2 = _U
  L12_2 = "JOB.STEPPER_TASK_LABEL"
  L13_2 = L3_2
  L11_2 = L11_2(L12_2, L13_2)
  L10_2.label = L11_2
  L10_2.keyName = ""
  L11_2 = {}
  L12_2 = _U
  L13_2 = "JOB.STEPPER_PROGRESS_LABEL"
  L14_2 = L3_1
  L12_2 = L12_2(L13_2, L14_2)
  L11_2.label = L12_2
  L11_2.keyName = ""
  L12_2 = {}
  L13_2 = _U
  L14_2 = "JOB.STEPPER_DO_TASK_LABEL"
  L13_2 = L13_2(L14_2)
  L12_2.label = L13_2
  L13_2 = Config
  L13_2 = L13_2.PrisonJobs
  L13_2 = L13_2.Stepper
  L13_2 = L13_2.DoTask
  L12_2.keyName = L13_2
  L13_2 = {}
  L14_2 = _U
  L15_2 = "JOB.STEPPER_EXIT_TASK_LABEL"
  L14_2 = L14_2(L15_2)
  L13_2.label = L14_2
  L14_2 = Config
  L14_2 = L14_2.PrisonJobs
  L14_2 = L14_2.Stepper
  L14_2 = L14_2.StopTask
  L13_2.keyName = L14_2
  L9_2[1] = L10_2
  L9_2[2] = L11_2
  L9_2[3] = L12_2
  L9_2[4] = L13_2
  L10_2 = "top-left"
  L8_2(L9_2, L10_2)
  L8_2 = A0_2.minigame
  if L8_2 then
    L8_2 = L8_2.enabled
  end
  if not L8_2 then
    L8_2 = false
  end
  L9_2 = dbg
  L9_2 = L9_2.debug
  L10_2 = "Stepper started -> awaiting user input."
  L9_2(L10_2)
  L9_2 = SetCycle
  L10_2 = "STEPPER"
  L11_2 = 0
  function L12_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3
    L0_3 = L3_1
    if L0_3 > 100 then
      L0_3 = 100
      L3_1 = L0_3
    end
    L0_3 = L5_1
    if L0_3 then
      return
    end
    L0_3 = L3_1
    if L0_3 <= 99 then
      L0_3 = L4_1
      if not L0_3 then
        L0_3 = TaskPlayAnim
        L1_3 = L4_2
        L2_3 = L1_2.IDLE
        L2_3 = L2_3.dict
        L3_3 = L1_2.IDLE
        L3_3 = L3_3.name
        L4_3 = 8.0
        L5_3 = -8.0
        L6_3 = -1
        L7_3 = 0
        L8_3 = 0
        L9_3 = 0
        L10_3 = 0
        L11_3 = 0
        L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
        L0_3 = L0_1
        if L0_3 then
          L0_3 = handlePTFX
          L1_3 = true
          L2_3 = A0_2.particles
          L0_3(L1_3, L2_3)
          L0_3 = TaskPlayAnim
          L1_3 = L4_2
          L2_3 = L1_2.ACTION
          L2_3 = L2_3.dict
          L3_3 = L1_2.ACTION
          L3_3 = L3_3.name
          L4_3 = 8.0
          L5_3 = -8.0
          L6_3 = L1_2.ACTION
          L6_3 = L6_3.time
          L7_3 = L1_2.ACTION
          L7_3 = L7_3.flag
          if not L7_3 then
            L7_3 = 0
          end
          L8_3 = 0
          L9_3 = 0
          L10_3 = 0
          L11_3 = 0
          L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
          L0_3 = Wait
          L1_3 = L1_2.ACTION
          L1_3 = L1_3.time
          L0_3(L1_3)
          L0_3 = handlePTFX
          L1_3 = false
          L2_3 = A0_2.particles
          L0_3(L1_3, L2_3)
          L0_3 = HandleStepperFinish
          L1_3 = L2_2.action
          L1_3 = L1_3.percentIncrease
          L2_3 = L2_2.action
          L2_3 = L2_3.time
          L3_3 = L2_2.action
          L3_3 = L3_3.time
          L3_3 = L3_3 - 70
          L4_3 = L3_2
          L5_3 = L7_2
          L6_3 = L8_2
          L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3)
          L0_3 = L5_1
          if not L0_3 then
            L0_3 = HelpKeys
            L0_3 = L0_3.Show
            L1_3 = {}
            L2_3 = {}
            L3_3 = _U
            L4_3 = "JOB.STEPPER_TASK_LABEL"
            L5_3 = L3_2
            L3_3 = L3_3(L4_3, L5_3)
            L2_3.label = L3_3
            L2_3.keyName = ""
            L3_3 = {}
            L4_3 = _U
            L5_3 = "JOB.STEPPER_PROGRESS_LABEL"
            L6_3 = L3_1
            L4_3 = L4_3(L5_3, L6_3)
            L3_3.label = L4_3
            L3_3.keyName = ""
            L4_3 = {}
            L5_3 = _U
            L6_3 = "JOB.STEPPER_DO_TASK_LABEL"
            L5_3 = L5_3(L6_3)
            L4_3.label = L5_3
            L4_3.keyName = "SPACE"
            L5_3 = {}
            L6_3 = _U
            L7_3 = "JOB.STEPPER_EXIT_TASK_LABEL"
            L6_3 = L6_3(L7_3)
            L5_3.label = L6_3
            L5_3.keyName = "H"
            L1_3[1] = L2_3
            L1_3[2] = L3_3
            L1_3[3] = L4_3
            L1_3[4] = L5_3
            L2_3 = "top-left"
            L0_3(L1_3, L2_3)
          end
          L0_3 = false
          L0_1 = L0_3
        else
          L0_3 = L1_1
          if L0_3 then
            L0_3 = ClearCycle
            L1_3 = "STEPPER"
            L0_3(L1_3)
            L0_3 = false
            L0_1 = L0_3
            L0_3 = false
            L1_1 = L0_3
            L0_3 = handleStepperExit
            L1_3 = L1_2.EXIT
            L1_3 = L1_3.dict
            L2_3 = L1_2.EXIT
            L2_3 = L2_3.name
            L3_3 = L1_2.EXIT
            L3_3 = L3_3.time
            L4_3 = L3_2
            L5_3 = L1_2
            L6_3 = L7_2
            L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3)
          else
            L0_3 = Wait
            L1_3 = 100
            L0_3(L1_3)
          end
        end
    end
    else
      L0_3 = handleStepperExit
      L1_3 = L1_2.EXIT
      L1_3 = L1_3.dict
      L2_3 = L1_2.EXIT
      L2_3 = L2_3.name
      L3_3 = L1_2.EXIT
      L3_3 = L3_3.time
      L4_3 = L3_2
      L5_3 = L1_2
      L6_3 = L7_2
      L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3)
    end
  end
  L9_2(L10_2, L11_2, L12_2)
end
StartStepper = L7_1
function L7_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2
  if not A1_2 then
    return
  end
  if A0_2 then
    L2_2 = PlayerPedId
    L2_2 = L2_2()
    L3_2 = {}
    L3_2.R = 1.0
    L3_2.G = 1.0
    L3_2.B = 1.0
    L3_2.A = 1.0
    L4_2 = 1.0
    L5_2 = GetPedBoneIndex
    L6_2 = L2_2
    L7_2 = 28422
    L5_2 = L5_2(L6_2, L7_2)
    L6_2 = requestPTFXAsset
    L7_2 = A1_2.dict
    L6_2(L7_2)
    L6_2 = UseParticleFxAsset
    L7_2 = A1_2.dict
    L6_2(L7_2)
    L7_2 = MyServerId
    L6_2 = L6_1
    L8_2 = StartParticleFxLoopedOnEntityBone
    L9_2 = A1_2.name
    L10_2 = L2_2
    L11_2 = A1_2.offset
    L11_2 = L11_2.pos
    L11_2 = L11_2.x
    L12_2 = A1_2.offset
    L12_2 = L12_2.pos
    L12_2 = L12_2.y
    L13_2 = A1_2.offset
    L13_2 = L13_2.pos
    L13_2 = L13_2.z
    L14_2 = A1_2.offset
    L14_2 = L14_2.rot
    L14_2 = L14_2.x
    L15_2 = A1_2.offset
    L15_2 = L15_2.rot
    L15_2 = L15_2.y
    L16_2 = A1_2.offset
    L16_2 = L16_2.rot
    L16_2 = L16_2.z
    L17_2 = L5_2
    L18_2 = L4_2 + 0.0
    L19_2 = false
    L20_2 = false
    L21_2 = false
    L8_2 = L8_2(L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2)
    L6_2[L7_2] = L8_2
    if L3_2 then
      L6_2 = SetParticleFxLoopedAlpha
      L8_2 = MyServerId
      L7_2 = L6_1
      L7_2 = L7_2[L8_2]
      L8_2 = L3_2.A
      L6_2(L7_2, L8_2)
      L6_2 = SetParticleFxLoopedColour
      L8_2 = MyServerId
      L7_2 = L6_1
      L7_2 = L7_2[L8_2]
      L8_2 = L3_2.R
      L8_2 = L8_2 / 255
      L9_2 = L3_2.G
      L9_2 = L9_2 / 255
      L10_2 = L3_2.B
      L10_2 = L10_2 / 255
      L11_2 = false
      L6_2(L7_2, L8_2, L9_2, L10_2, L11_2)
    end
  else
    L2_2 = StopParticleFxLooped
    L4_2 = MyServerId
    L3_2 = L6_1
    L3_2 = L3_2[L4_2]
    L4_2 = false
    L2_2(L3_2, L4_2)
    L2_2 = RemoveNamedPtfxAsset
    L3_2 = A1_2.dict
    L2_2(L3_2)
    L3_2 = MyServerId
    L2_2 = L6_1
    L2_2[L3_2] = nil
  end
end
handlePTFX = L7_1
function L7_1(A0_2)
  local L1_2, L2_2
  L1_2 = RequestNamedPtfxAsset
  L2_2 = A0_2
  L1_2(L2_2)
  while true do
    L1_2 = HasNamedPtfxAssetLoaded
    L2_2 = A0_2
    L1_2 = L1_2(L2_2)
    if L1_2 then
      break
    end
    L1_2 = Wait
    L2_2 = 0
    L1_2(L2_2)
  end
  L1_2 = true
  return L1_2
end
requestPTFXAsset = L7_1
function L7_1(A0_2, A1_2, A2_2, A3_2, A4_2, A5_2)
  local L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2
  L6_2 = L4_1
  if L6_2 then
    return
  end
  L6_2 = L5_1
  if L6_2 then
    return
  end
  L6_2 = ClearCycle
  L7_2 = "STEPPER"
  L6_2(L7_2)
  L6_2 = true
  L4_1 = L6_2
  L6_2 = PlayerPedId
  L6_2 = L6_2()
  L7_2 = GetEntityCoords
  L8_2 = L6_2
  L7_2 = L7_2(L8_2)
  L8_2 = GetGroundZFor_3dCoord
  L9_2 = L7_2.x
  L10_2 = L7_2.y
  L11_2 = L7_2.z
  L12_2 = true
  L8_2, L9_2 = L8_2(L9_2, L10_2, L11_2, L12_2)
  L10_2 = vec3
  L11_2 = L7_2.x
  L12_2 = L7_2.y
  L13_2 = L9_2
  L10_2 = L10_2(L11_2, L12_2, L13_2)
  L11_2 = GetEntityForwardVector
  L12_2 = L6_2
  L11_2 = L11_2(L12_2)
  L12_2 = L11_2 / 0.8
  L12_2 = L10_2 - L12_2
  L13_2 = false
  L14_2 = EXERCISE_MAP
  L14_2 = L14_2.SITUPS
  if A3_2 == L14_2 then
    L14_2 = SetEntityCoords
    L15_2 = L6_2
    L16_2 = L12_2
    L14_2(L15_2, L16_2)
  else
    L13_2 = true
  end
  L14_2 = DeleteEntity
  L15_2 = A5_2
  L14_2(L15_2)
  L14_2 = HelpKeys
  L14_2 = L14_2.Hide
  L14_2()
  L14_2 = TaskPlayAnim
  L15_2 = L6_2
  L16_2 = A0_2
  L17_2 = A1_2
  L18_2 = 8.0
  L19_2 = -8.0
  L20_2 = A2_2
  L21_2 = 0
  L22_2 = 0.0
  L23_2 = 0
  L24_2 = 0
  L25_2 = 0
  L14_2(L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2)
  if not L13_2 then
    L14_2 = Wait
    L15_2 = A2_2
    L14_2(L15_2)
  end
  L14_2 = false
  L0_1 = L14_2
  L14_2 = FreezeEntityPosition
  L15_2 = L6_2
  L16_2 = false
  L14_2(L15_2, L16_2)
  L14_2 = ClearPedTasksImmediately
  L15_2 = L6_2
  L14_2(L15_2)
  L14_2 = A4_2
  L15_2 = pairs
  L16_2 = L14_2
  L15_2, L16_2, L17_2, L18_2 = L15_2(L16_2)
  for L19_2, L20_2 in L15_2, L16_2, L17_2, L18_2 do
    L21_2 = RemoveAnimDict
    L22_2 = L20_2.dict
    L21_2(L22_2)
  end
  TASK_PROCESSING_STEPPER = false
  L15_2 = FreezeEntityPosition
  L16_2 = L6_2
  L17_2 = false
  L15_2(L16_2, L17_2)
  L15_2 = ClearPedTasksImmediately
  L16_2 = L6_2
  L15_2(L16_2)
  L15_2 = false
  L4_1 = L15_2
  ActionState = false
  L15_2 = L5_1
  if not L15_2 then
    L15_2 = L2_1
    L16_2 = false
    L17_2 = A5_2
    L15_2(L16_2, L17_2)
  end
  L15_2 = DebugRecordStep
  L16_2 = Jobs
  L16_2 = L16_2.MinigameType
  L17_2 = "Exit task"
  L15_2(L16_2, L17_2)
  L15_2 = HelpKeys
  L15_2 = L15_2.Show
  L16_2 = {}
  L17_2 = {}
  L18_2 = _U
  L19_2 = "JOB.STOP_CURRENT_JOB_LABEL"
  L18_2 = L18_2(L19_2)
  L17_2.label = L18_2
  L18_2 = Config
  L18_2 = L18_2.PrisonJobs
  L18_2 = L18_2.LeaveJobKey
  L17_2.keyName = L18_2
  L16_2[1] = L17_2
  L17_2 = "top-left"
  L15_2(L16_2, L17_2)
end
handleStepperExit = L7_1
function L7_1(A0_2, A1_2, A2_2, A3_2, A4_2, A5_2)
  local L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2
  L6_2 = false
  if A5_2 then
    L7_2 = HandleStepperMinigame
    L7_2 = L7_2()
    L6_2 = L7_2
  end
  if L6_2 or not A5_2 then
    L7_2 = 1
    L8_2 = A1_2
    L9_2 = 1
    for L10_2 = L7_2, L8_2, L9_2 do
      L11_2 = Wait
      L12_2 = A2_2 / A1_2
      L11_2(L12_2)
      L11_2 = L3_1
      L11_2 = L11_2 + A0_2
      L3_1 = L11_2
    end
    L7_2 = next
    L8_2 = Jobs
    L8_2 = L8_2.entities
    L7_2 = L7_2(L8_2)
    if L7_2 then
      L7_2 = pairs
      L8_2 = Jobs
      L8_2 = L8_2.entities
      L7_2, L8_2, L9_2, L10_2 = L7_2(L8_2)
      for L11_2, L12_2 in L7_2, L8_2, L9_2, L10_2 do
        L13_2 = DoesEntityExist
        L14_2 = L12_2
        L13_2 = L13_2(L14_2)
        if L13_2 then
          L13_2 = nil
          L14_2 = math
          L14_2 = L14_2.floor
          L15_2 = L3_1
          L15_2 = L15_2 / 100
          L15_2 = 255 * L15_2
          L14_2 = L14_2(L15_2)
          L15_2 = 255
          L13_2 = L15_2 - L14_2
          L14_2 = SetEntityAlpha
          L15_2 = L12_2
          L16_2 = L13_2
          L14_2(L15_2, L16_2)
        end
      end
    end
  end
  L7_2 = L3_1
  if L7_2 >= 99 then
    L7_2 = ClearCycle
    L8_2 = "STEPPER"
    L7_2(L8_2)
    L7_2 = L2_1
    L8_2 = true
    L9_2 = A4_2
    L7_2(L8_2, L9_2)
    L7_2 = true
    L5_1 = L7_2
    L7_2 = 0
    L3_1 = L7_2
    TASK_PROCESSING_STEPPER = false
    L7_2 = DetachEntity
    L8_2 = A4_2
    L9_2 = true
    L10_2 = true
    L7_2(L8_2, L9_2, L10_2)
    L7_2 = DeleteEntity
    L8_2 = A4_2
    L7_2(L8_2)
    L7_2 = FreezeEntityPosition
    L8_2 = PlayerPedId
    L8_2 = L8_2()
    L9_2 = false
    L7_2(L8_2, L9_2)
    L7_2 = ClearPedTasksImmediately
    L8_2 = PlayerPedId
    L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2 = L8_2()
    L7_2(L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2)
    L7_2 = HelpKeys
    L7_2 = L7_2.Hide
    L7_2()
    L7_2 = DebugRecordStep
    L8_2 = Jobs
    L8_2 = L8_2.MinigameType
    L9_2 = "Finished task"
    L7_2(L8_2, L9_2)
    L7_2 = SetTimeout
    L8_2 = 2000
    function L9_2()
      local L0_3, L1_3
      L0_3 = false
      L5_1 = L0_3
    end
    L7_2(L8_2, L9_2)
  end
end
HandleStepperFinish = L7_1
function L7_1(A0_2)
  local L1_2, L2_2
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
LoadAnimDict = L7_1
function L7_1()
  local L0_2, L1_2
  L0_2 = L0_1
  if not L0_2 then
    L0_2 = L3_1
    if L0_2 <= 99 then
      L0_2 = false
      L0_1 = L0_2
      L0_2 = true
      L1_1 = L0_2
      L0_2 = ClearCycle
      L1_2 = "STEPPER"
      L0_2(L1_2)
    end
  end
end
StopStepper = L7_1
function L7_1()
  local L0_2, L1_2
  L0_2 = TASK_PROCESSING_STEPPER
  if not L0_2 then
    return
  end
  L0_2 = L0_1
  if not L0_2 then
    L0_2 = L3_1
    if L0_2 <= 99 then
      L0_2 = true
      L0_1 = L0_2
    end
  end
end
DoStepper = L7_1
L7_1 = RegisterKey
L8_1 = DoStepper
L9_1 = "START_STEPPER"
L10_1 = "Start stepper"
L11_1 = Config
L11_1 = L11_1.PrisonJobs
L11_1 = L11_1.Stepper
L11_1 = L11_1.DoTask
L7_1(L8_1, L9_1, L10_1, L11_1)
L7_1 = RegisterKey
L8_1 = StopStepper
L9_1 = "STOP_STEPPER"
L10_1 = "Stop stepper"
L11_1 = Config
L11_1 = L11_1.PrisonJobs
L11_1 = L11_1.Stepper
L11_1 = L11_1.StopTask
L7_1(L8_1, L9_1, L10_1, L11_1)
