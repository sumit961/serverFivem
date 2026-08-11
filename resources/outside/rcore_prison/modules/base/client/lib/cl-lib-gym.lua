local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1
L0_1 = {}
GYM = L0_1
L0_1 = 0
TASK_ACTIVE_EXERCISE = false
TASK_INACTIVE_STATE = false
TASK_PROCESSING = false
isExit = false
L1_1 = {}
L2_1 = EXERCISE_MAP
L2_1 = L2_1.CRANKS
L3_1 = {}
L4_1 = {}
L4_1.dict = "amb@world_human_push_ups@male@enter"
L4_1.name = "enter"
L4_1.time = 3050
L3_1.ENTER = L4_1
L4_1 = {}
L4_1.dict = "amb@world_human_push_ups@male@idle_a"
L4_1.name = "idle_c"
L3_1.IDLE = L4_1
L4_1 = {}
L4_1.dict = "amb@world_human_push_ups@male@base"
L4_1.name = "base"
L4_1.time = 1100
L3_1.ACTION = L4_1
L4_1 = {}
L4_1.dict = "amb@world_human_push_ups@male@exit"
L4_1.name = "exit"
L4_1.time = 3400
L3_1.EXIT = L4_1
L1_1[L2_1] = L3_1
L2_1 = EXERCISE_MAP
L2_1 = L2_1.SITUPS
L3_1 = {}
L4_1 = {}
L4_1.dict = "amb@world_human_sit_ups@male@enter"
L4_1.name = "enter"
L4_1.time = 4200
L3_1.ENTER = L4_1
L4_1 = {}
L4_1.dict = "amb@world_human_sit_ups@male@idle_a"
L4_1.name = "idle_a"
L3_1.IDLE = L4_1
L4_1 = {}
L4_1.dict = "amb@world_human_sit_ups@male@base"
L4_1.name = "base"
L4_1.time = 3400
L3_1.ACTION = L4_1
L4_1 = {}
L4_1.dict = "amb@world_human_sit_ups@male@exit"
L4_1.name = "exit"
L4_1.time = 3700
L3_1.EXIT = L4_1
L1_1[L2_1] = L3_1
L2_1 = EXERCISE_MAP
L2_1 = L2_1.MUSLECHIN
L3_1 = {}
L4_1 = {}
L4_1.dict = "amb@prop_human_muscle_chin_ups@male@enter"
L4_1.name = "enter"
L4_1.time = 1600
L3_1.ENTER = L4_1
L4_1 = {}
L4_1.dict = "amb@prop_human_muscle_chin_ups@male@idle_a"
L4_1.name = "idle_a"
L3_1.IDLE = L4_1
L4_1 = {}
L4_1.dict = "amb@prop_human_muscle_chin_ups@male@base"
L4_1.name = "base"
L4_1.time = 3000
L3_1.ACTION = L4_1
L4_1 = {}
L4_1.dict = "amb@prop_human_muscle_chin_ups@male@exit"
L4_1.name = "exit"
L4_1.time = 3700
L3_1.EXIT = L4_1
L1_1[L2_1] = L3_1
Exercises = L1_1
function L1_1()
  local L0_2, L1_2
  L0_2 = TASK_ACTIVE_EXERCISE
  if not L0_2 then
    L0_2 = L0_1
    if L0_2 <= 99 then
      TASK_ACTIVE_EXERCISE = false
      TASK_INACTIVE_STATE = true
      L0_2 = ClearCycle
      L1_2 = "exercise"
      L0_2(L1_2)
    end
  end
end
StopExercise = L1_1
function L1_1()
  local L0_2, L1_2
  L0_2 = TASK_PROCESSING
  if not L0_2 then
    return
  end
  L0_2 = TASK_ACTIVE_EXERCISE
  if not L0_2 then
    L0_2 = L0_1
    if L0_2 <= 99 then
      TASK_ACTIVE_EXERCISE = true
    end
  end
end
DoExercise = L1_1
L1_1 = RegisterKey
L2_1 = DoExercise
L3_1 = "A"
L4_1 = "A"
L5_1 = Config
L5_1 = L5_1.GYM
L5_1 = L5_1.DoExerciseKey
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = RegisterKey
L2_1 = StopExercise
L3_1 = "B"
L4_1 = "B"
L5_1 = Config
L5_1 = L5_1.GYM
L5_1 = L5_1.StopExerciseKey
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = 1.0
function L2_1()
  local L0_2, L1_2
  L0_2 = L1_1
  L1_2 = 1.6
  if L0_2 <= L1_2 then
    L0_2 = L1_1
    L0_2 = L0_2 + 0.1
    L1_1 = L0_2
  end
end
HandlingTask = L2_1
L2_1 = RegisterKey
L3_1 = HandlingTask
L4_1 = "A"
L5_1 = "A"
L6_1 = "E"
L2_1(L3_1, L4_1, L5_1, L6_1)
function L2_1()
  local L0_2, L1_2, L2_2, L3_2
  L0_2 = TASK_PROCESSING
  if L0_2 then
    return
  end
  L0_2 = ClearPedTasksImmediately
  L1_2 = PlayerPedId
  L1_2, L2_2, L3_2 = L1_2()
  L0_2(L1_2, L2_2, L3_2)
  L0_2 = TriggerEvent
  L1_2 = "rcore_prison:gymStartExercise"
  L2_2 = MyServerId
  L3_2 = SH
  L3_2 = L3_2.zoneId
  L0_2(L1_2, L2_2, L3_2)
end
startExercise = L2_1
L2_1 = RegisterNetEvent
L3_1 = "rcore_prison:gymStartExercise"
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2
  L2_2 = MyServerId
  L2_2 = not L2_2
  if L2_2 == A0_2 then
    return
  end
  TASK_PROCESSING = true
  L2_2 = PlayerPedId
  L2_2 = L2_2()
  L3_2 = SH
  L3_2 = L3_2.data
  L3_2 = L3_2.interaction
  L3_2 = L3_2[A1_2]
  if not L3_2 then
    return L3_2
  end
  L4_2 = L3_2
  L5_2 = L4_2.exercise
  L6_2 = Exercises
  L6_2 = L6_2[L5_2]
  L7_2 = L4_2.coords
  L8_2 = Config
  L8_2 = L8_2.GYM
  L8_2 = L8_2.SkillMap
  L8_2 = L8_2[L5_2]
  L9_2 = pairs
  L10_2 = L6_2
  L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
  for L13_2, L14_2 in L9_2, L10_2, L11_2, L12_2 do
    L15_2 = LoadAnimDict
    L16_2 = L14_2.dict
    L15_2(L16_2)
  end
  L9_2 = nil
  L10_2 = nil
  L11_2 = L4_2.place
  if L11_2 then
    L11_2 = L4_2.place
    L11_2 = L11_2.model
    if L11_2 then
      L11_2 = L4_2.place
      L9_2 = L11_2.model
    end
  end
  if L9_2 then
    L11_2 = GetClosestObjectOfType
    L12_2 = L7_2.x
    L13_2 = L7_2.y
    L14_2 = L7_2.z
    L15_2 = 1.0
    L16_2 = L9_2
    L17_2 = false
    L18_2 = false
    L19_2 = false
    L11_2 = L11_2(L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2)
    L10_2 = L11_2
  end
  L11_2 = 0
  if L10_2 then
    L12_2 = GetEntityHeading
    L13_2 = L10_2
    L12_2 = L12_2(L13_2)
    L11_2 = L12_2
    L12_2 = GetEntityCoords
    L13_2 = L10_2
    L12_2 = L12_2(L13_2)
    L7_2 = L12_2
  end
  L12_2 = FreezeEntityPosition
  L13_2 = L2_2
  L14_2 = true
  L12_2(L13_2, L14_2)
  L12_2 = SetEntityCoords
  L13_2 = L2_2
  L14_2 = L7_2
  L12_2(L13_2, L14_2)
  L12_2 = SetEntityHeading
  L13_2 = L2_2
  L14_2 = L11_2
  L12_2(L13_2, L14_2)
  L12_2 = TaskPlayAnim
  L13_2 = L2_2
  L14_2 = L6_2.ENTER
  L14_2 = L14_2.dict
  L15_2 = L6_2.ENTER
  L15_2 = L15_2.name
  L16_2 = 8.0
  L17_2 = -8.0
  L18_2 = L6_2.ENTER
  L18_2 = L18_2.time
  L19_2 = 0
  L20_2 = 0
  L21_2 = 0
  L22_2 = 0
  L23_2 = 0
  L12_2(L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2)
  L12_2 = HelpKeys
  L12_2 = L12_2.Show
  L13_2 = {}
  L14_2 = {}
  L15_2 = _U
  L16_2 = "GYM.HELPKEY_EXERCISE_LABEL"
  L17_2 = L5_2
  L15_2 = L15_2(L16_2, L17_2)
  L14_2.label = L15_2
  L14_2.keyName = ""
  L15_2 = {}
  L16_2 = _U
  L17_2 = "GYM.HELPKEY_EXERCISE_PROGRESS_LABEL"
  L18_2 = L0_1
  L16_2 = L16_2(L17_2, L18_2)
  L17_2 = "%"
  L16_2 = L16_2 .. L17_2
  L15_2.label = L16_2
  L15_2.keyName = ""
  L16_2 = {}
  L17_2 = _U
  L18_2 = "GYM.HELPKEY_EXERCISE_DO_LABEL"
  L17_2 = L17_2(L18_2)
  L16_2.label = L17_2
  L16_2.keyName = "SPACE"
  L17_2 = {}
  L18_2 = _U
  L19_2 = "GYM.HELPKEY_EXERCISE_EXIT"
  L18_2 = L18_2(L19_2)
  L17_2.label = L18_2
  L17_2.keyName = "H"
  L13_2[1] = L14_2
  L13_2[2] = L15_2
  L13_2[3] = L16_2
  L13_2[4] = L17_2
  L14_2 = "top-left"
  L12_2(L13_2, L14_2)
  L12_2 = SetCycle
  L13_2 = "exercise"
  L14_2 = 0
  function L15_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3
    L0_3 = L0_1
    if L0_3 > 100 then
      L0_3 = 100
      L0_1 = L0_3
    end
    L0_3 = L0_1
    if L0_3 <= 99 then
      L0_3 = isExit
      if not L0_3 then
        L0_3 = TaskPlayAnim
        L1_3 = L2_2
        L2_3 = L6_2.IDLE
        L2_3 = L2_3.dict
        L3_3 = L6_2.IDLE
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
        L0_3 = TASK_ACTIVE_EXERCISE
        if L0_3 then
          L0_3 = TaskPlayAnim
          L1_3 = L2_2
          L2_3 = L6_2.ACTION
          L2_3 = L2_3.dict
          L3_3 = L6_2.ACTION
          L3_3 = L3_3.name
          L4_3 = 8.0
          L5_3 = -8.0
          L6_3 = L6_2.ACTION
          L6_3 = L6_3.time
          L7_3 = 0
          L8_3 = 0
          L9_3 = 0
          L10_3 = 0
          L11_3 = 0
          L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
          L0_3 = IncreaseStats
          L1_3 = L8_2.action
          L1_3 = L1_3.percentIncrease
          L2_3 = L8_2.action
          L2_3 = L2_3.time
          L3_3 = L6_2.ACTION
          L3_3 = L3_3.time
          L3_3 = L3_3 - 70
          L4_3 = L5_2
          L0_3(L1_3, L2_3, L3_3, L4_3)
          L0_3 = HelpKeys
          L0_3 = L0_3.Show
          L1_3 = {}
          L2_3 = {}
          L3_3 = _U
          L4_3 = "GYM.HELPKEY_EXERCISE_LABEL"
          L5_3 = L5_2
          L3_3 = L3_3(L4_3, L5_3)
          L2_3.label = L3_3
          L2_3.keyName = ""
          L3_3 = {}
          L4_3 = _U
          L5_3 = "GYM.HELPKEY_EXERCISE_PROGRESS_LABEL"
          L6_3 = L0_1
          L4_3 = L4_3(L5_3, L6_3)
          L5_3 = "%"
          L4_3 = L4_3 .. L5_3
          L3_3.label = L4_3
          L3_3.keyName = ""
          L4_3 = {}
          L5_3 = _U
          L6_3 = "GYM.HELPKEY_EXERCISE_DO_LABEL"
          L5_3 = L5_3(L6_3)
          L4_3.label = L5_3
          L4_3.keyName = "SPACE"
          L5_3 = {}
          L6_3 = _U
          L7_3 = "GYM.HELPKEY_EXERCISE_EXIT"
          L6_3 = L6_3(L7_3)
          L5_3.label = L6_3
          L5_3.keyName = "H"
          L1_3[1] = L2_3
          L1_3[2] = L3_3
          L1_3[3] = L4_3
          L1_3[4] = L5_3
          L2_3 = "top-left"
          L0_3(L1_3, L2_3)
          TASK_ACTIVE_EXERCISE = false
        else
          L0_3 = TASK_INACTIVE_STATE
          if L0_3 then
            L0_3 = ClearCycle
            L1_3 = "exercise"
            L0_3(L1_3)
            TASK_ACTIVE_EXERCISE = false
            TASK_INACTIVE_STATE = false
            L0_3 = StopTraining
            L1_3 = L6_2.EXIT
            L1_3 = L1_3.dict
            L2_3 = L6_2.EXIT
            L2_3 = L2_3.name
            L3_3 = L6_2.EXIT
            L3_3 = L3_3.time
            L4_3 = L5_2
            L0_3(L1_3, L2_3, L3_3, L4_3)
          else
            L0_3 = Wait
            L1_3 = 100
            L0_3(L1_3)
          end
        end
    end
    else
      L0_3 = StopTraining
      L1_3 = L6_2.EXIT
      L1_3 = L1_3.dict
      L2_3 = L6_2.EXIT
      L2_3 = L2_3.name
      L3_3 = L6_2.EXIT
      L3_3 = L3_3.time
      L4_3 = L5_2
      L0_3(L1_3, L2_3, L3_3, L4_3)
    end
  end
  L12_2(L13_2, L14_2, L15_2)
end
L2_1(L3_1, L4_1)
function L2_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2
  L4_2 = isExit
  if L4_2 then
    return
  end
  isExit = true
  L4_2 = PlayerPedId
  L4_2 = L4_2()
  L5_2 = GetEntityCoords
  L6_2 = L4_2
  L5_2 = L5_2(L6_2)
  L6_2 = GetGroundZFor_3dCoord
  L7_2 = L5_2.x
  L8_2 = L5_2.y
  L9_2 = L5_2.z
  L10_2 = true
  L6_2, L7_2 = L6_2(L7_2, L8_2, L9_2, L10_2)
  L8_2 = vec3
  L9_2 = L5_2.x
  L10_2 = L5_2.y
  L11_2 = L7_2
  L8_2 = L8_2(L9_2, L10_2, L11_2)
  L9_2 = GetEntityForwardVector
  L10_2 = L4_2
  L9_2 = L9_2(L10_2)
  L10_2 = L9_2 / 0.8
  L10_2 = L8_2 - L10_2
  L11_2 = false
  L12_2 = EXERCISE_MAP
  L12_2 = L12_2.SITUPS
  if A3_2 == L12_2 then
    L12_2 = SetEntityCoords
    L13_2 = L4_2
    L14_2 = L10_2
    L12_2(L13_2, L14_2)
  else
    L11_2 = true
  end
  L12_2 = HelpKeys
  L12_2 = L12_2.Hide
  L12_2()
  L12_2 = ClearCycle
  L13_2 = "exercise"
  L12_2(L13_2)
  L12_2 = TaskPlayAnim
  L13_2 = L4_2
  L14_2 = A0_2
  L15_2 = A1_2
  L16_2 = 8.0
  L17_2 = -8.0
  L18_2 = A2_2
  L19_2 = 0
  L20_2 = 0.0
  L21_2 = 0
  L22_2 = 0
  L23_2 = 0
  L12_2(L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2)
  L12_2 = 0
  L0_1 = L12_2
  if not L11_2 then
    L12_2 = Wait
    L13_2 = A2_2
    L12_2(L13_2)
  end
  TASK_ACTIVE_EXERCISE = false
  L12_2 = FreezeEntityPosition
  L13_2 = L4_2
  L14_2 = false
  L12_2(L13_2, L14_2)
  L12_2 = ClearPedTasksImmediately
  L13_2 = L4_2
  L12_2(L13_2)
  L12_2 = Exercises
  L12_2 = L12_2[A3_2]
  L13_2 = pairs
  L14_2 = L12_2
  L13_2, L14_2, L15_2, L16_2 = L13_2(L14_2)
  for L17_2, L18_2 in L13_2, L14_2, L15_2, L16_2 do
    L19_2 = RemoveAnimDict
    L20_2 = L18_2.dict
    L19_2(L20_2)
  end
  TASK_PROCESSING = false
  L13_2 = SetTimeout
  L14_2 = 1500
  function L15_2()
    local L0_3, L1_3, L2_3
    L0_3 = FreezeEntityPosition
    L1_3 = L4_2
    L2_3 = false
    L0_3(L1_3, L2_3)
    L0_3 = ClearPedTasksImmediately
    L1_3 = L4_2
    L0_3(L1_3)
    isExit = false
    ActionState = false
    L0_3 = TriggerServerEvent
    L1_3 = "rcore_prison:unregisterGymPlace"
    L2_3 = SH
    L2_3 = L2_3.zoneId
    L0_3(L1_3, L2_3)
    L0_3 = SH
    L0_3.zoneId = nil
  end
  L13_2(L14_2, L15_2)
end
StopTraining = L2_1
function L2_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L4_2 = 1
  L5_2 = A1_2
  L6_2 = 1
  for L7_2 = L4_2, L5_2, L6_2 do
    L8_2 = Wait
    L9_2 = A2_2 / A1_2
    L8_2(L9_2)
    L8_2 = L0_1
    L8_2 = L8_2 + A0_2
    L0_1 = L8_2
  end
  L4_2 = L0_1
  if L4_2 >= 99 then
    L4_2 = ReceiveExerciseStats
    L5_2 = A3_2
    L4_2(L5_2)
  end
end
IncreaseStats = L2_1
function L2_1(A0_2)
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
LoadAnimDict = L2_1
