local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1
L0_1 = {}
L0_1.ActiveMinigame = false
L0_1.ActiveJob = false
L0_1.jobId = nil
L0_1.locationId = nil
L0_1.zoneName = nil
L0_1.inZone = false
L0_1.currentZone = nil
L1_1 = {}
L0_1.entities = L1_1
Jobs = L0_1
L0_1 = false
L1_1 = {}
L2_1 = JOBS
L2_1 = L2_1.ELECTRICIAN
L3_1 = _U
L4_1 = "JOB.ELECTRICIAN_SUBTITLES_INIT_STATE_LABEL"
L3_1 = L3_1(L4_1)
L1_1[L2_1] = L3_1
L2_1 = JOBS
L2_1 = L2_1.COOK
L3_1 = _U
L4_1 = "JOB.COOKING_SUBTITLES_INIT_STATE_LABEL"
L3_1 = L3_1(L4_1)
L1_1[L2_1] = L3_1
L2_1 = JOBS
L2_1 = L2_1.CLEAN_GROUND
L3_1 = _U
L4_1 = "JOB.CLEAN_GROUND_SUBTITLES_INIT_STATE_LABEL"
L3_1 = L3_1(L4_1)
L1_1[L2_1] = L3_1
L2_1 = JOBS
L2_1 = L2_1.JANITOR
L3_1 = _U
L4_1 = "JOB.JANITOR_SUBTITLES_INIT_STATE_LABEL"
L3_1 = L3_1(L4_1)
L1_1[L2_1] = L3_1
L2_1 = JOBS
L2_1 = L2_1.BUSH_TRIMMING
L3_1 = _U
L4_1 = "JOB.BUSHES_SUBTITLES_INIT_STATE_LABEL"
L3_1 = L3_1(L4_1)
L1_1[L2_1] = L3_1
L2_1 = JOBS
L2_1 = L2_1.GARDENER
L3_1 = _U
L4_1 = "JOB.GARDENER_SUBTITLES_INIT_STATE_LABEL"
L3_1 = L3_1(L4_1)
L1_1[L2_1] = L3_1
L2_1 = Jobs
function L3_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2
  L3_2 = dbg
  L3_2 = L3_2.debug
  L4_2 = "Job %s started! %s "
  L5_2 = A0_2
  L6_2 = A1_2
  L3_2(L4_2, L5_2, L6_2)
  L3_2 = SH
  L3_2 = L3_2.data
  L3_2 = L3_2.jobs
  L3_2 = L3_2[A0_2]
  if L3_2 then
    L4_2 = L3_2.points
    L4_2 = L4_2[A1_2]
    if not L4_2 then
      return
    end
    L5_2 = vec3
    L6_2 = L4_2.pos
    L6_2 = L6_2.x
    L7_2 = L4_2.pos
    L7_2 = L7_2.y
    L8_2 = L4_2.pos
    L8_2 = L8_2.z
    L5_2 = L5_2(L6_2, L7_2, L8_2)
    L6_2 = L4_2.pos
    L6_2 = L6_2.w
    L7_2 = L3_2.name
    L8_2 = L3_2.type
    L9_2 = Subtitles
    L9_2 = L9_2.Show
    L10_2 = L1_1
    L10_2 = L10_2[L8_2]
    L9_2(L10_2)
    L9_2 = Jobs
    L9_2.ActiveJob = true
    L9_2 = Jobs
    L9_2.jobId = A0_2
    L9_2 = Jobs
    L9_2.locationId = A1_2
    L9_2 = Jobs
    L9_2.zoneName = L7_2
    L9_2 = Jobs
    L9_2.extra = A2_2
    L9_2 = Blips
    L9_2 = L9_2.Create
    L10_2 = {}
    L11_2 = _U
    L12_2 = "JOB.TASK_BLIP_AREA_NAME"
    L11_2 = L11_2(L12_2)
    L10_2.name = L11_2
    L10_2.sprite = 164
    L10_2.color = 4
    L10_2.scale = 1.3
    L10_2.coords = L5_2
    L10_2.type = "JOB"
    L9_2(L10_2)
    L9_2 = HelpKeys
    L9_2 = L9_2.Show
    L10_2 = {}
    L11_2 = {}
    L12_2 = _U
    L13_2 = "JOB.STOP_CURRENT_JOB_LABEL"
    L12_2 = L12_2(L13_2)
    L11_2.label = L12_2
    L12_2 = Config
    L12_2 = L12_2.PrisonJobs
    L12_2 = L12_2.LeaveJobKey
    L11_2.keyName = L12_2
    L10_2[1] = L11_2
    L11_2 = "top-left"
    L9_2(L10_2, L11_2)
    if L5_2 and L6_2 then
      L9_2 = JOBS
      L9_2 = L9_2.CLEAN_GROUND
      if L8_2 == L9_2 then
        L9_2 = 0.05
        L10_2 = math
        L10_2 = L10_2.random
        L11_2 = 2
        L12_2 = 4
        L10_2 = L10_2(L11_2, L12_2)
        L11_2 = generateCirclePositions
        L12_2 = L5_2
        L13_2 = L9_2
        L14_2 = L10_2
        L11_2 = L11_2(L12_2, L13_2, L14_2)
        L12_2 = {}
        L13_2 = {}
        L13_2.name = "rcore_leafes_large"
        L14_2 = {}
        L14_2.name = "rcore_leafes_medium"
        L15_2 = {}
        L15_2.name = "rcore_leafes_small"
        L12_2[1] = L13_2
        L12_2[2] = L14_2
        L12_2[3] = L15_2
        L13_2 = ipairs
        L14_2 = L11_2
        L13_2, L14_2, L15_2, L16_2 = L13_2(L14_2)
        for L17_2, L18_2 in L13_2, L14_2, L15_2, L16_2 do
          L19_2 = math
          L19_2 = L19_2.random
          L20_2 = 1
          L21_2 = #L12_2
          L19_2 = L19_2(L20_2, L21_2)
          L19_2 = L12_2[L19_2]
          L20_2 = Entity
          L20_2 = L20_2.SpawnPropAtCoords
          L21_2 = {}
          L21_2.coords = L18_2
          L21_2.heading = L6_2
          L22_2 = L19_2.name
          L21_2.model = L22_2
          L20_2 = L20_2(L21_2)
          L21_2 = table
          L21_2 = L21_2.insert
          L22_2 = Jobs
          L22_2 = L22_2.entities
          L23_2 = L20_2
          L21_2(L22_2, L23_2)
        end
      else
        L9_2 = JOBS
        L9_2 = L9_2.BUSH_TRIMMING
        if L8_2 == L9_2 then
          L9_2 = 1
          L10_2 = math
          L10_2 = L10_2.random
          L11_2 = 2
          L12_2 = 3
          L10_2 = L10_2(L11_2, L12_2)
          L11_2 = generateCirclePositions
          L12_2 = L5_2
          L13_2 = L9_2
          L14_2 = L10_2
          L11_2 = L11_2(L12_2, L13_2, L14_2)
          L12_2 = ipairs
          L13_2 = L11_2
          L12_2, L13_2, L14_2, L15_2 = L12_2(L13_2)
          for L16_2, L17_2 in L12_2, L13_2, L14_2, L15_2 do
            L18_2 = Entity
            L18_2 = L18_2.SpawnPropAtCoords
            L19_2 = {}
            L19_2.coords = L17_2
            L19_2.heading = L6_2
            L19_2.model = "prop_veg_crop_04_leaf"
            L18_2 = L18_2(L19_2)
            L19_2 = table
            L19_2 = L19_2.insert
            L20_2 = Jobs
            L20_2 = L20_2.entities
            L21_2 = L18_2
            L19_2(L20_2, L21_2)
          end
        end
      end
      L9_2 = Interact
      L9_2 = L9_2.Type
      if "ZONE" == L9_2 then
        L9_2 = CreateCOMSZone
        L9_2 = L9_2()
        L10_2 = "%s_%s_%s"
        L11_2 = L10_2
        L10_2 = L10_2.format
        L12_2 = L7_2
        L13_2 = A1_2
        L14_2 = MyServerId
        L10_2 = L10_2(L11_2, L12_2, L13_2, L14_2)
        L11_2 = L9_2.setId
        L12_2 = L10_2
        L11_2(L12_2)
        L11_2 = L9_2.setType
        L12_2 = 1
        L11_2(L12_2)
        L11_2 = L9_2.setPosition
        L12_2 = vec3
        L13_2 = L5_2.x
        L14_2 = L5_2.y
        L15_2 = L5_2.z
        L15_2 = L15_2 - 1
        L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2 = L12_2(L13_2, L14_2, L15_2)
        L11_2(L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2)
        L11_2 = L9_2.setRenderMarker
        L12_2 = true
        L11_2(L12_2)
        L11_2 = L9_2.setInRadius
        L12_2 = Config
        L12_2 = L12_2.PrisonJobs
        L12_2 = L12_2.InRadius
        L11_2(L12_2)
        L11_2 = L9_2.setRenderDistance
        L12_2 = Config
        L12_2 = L12_2.PrisonJobs
        L12_2 = L12_2.RenderInteractZoneDistance
        L11_2(L12_2)
        L11_2 = L9_2.on
        L12_2 = "leave"
        function L13_2()
          local L0_3, L1_3, L2_3, L3_3, L4_3
          L0_3 = Jobs
          L0_3 = L0_3.inZone
          if not L0_3 then
            return
          end
          L0_3 = Jobs
          L0_3.inZone = false
          L0_3 = dbg
          L0_3 = L0_3.debug
          L1_3 = "You leave job place."
          L2_3 = L10_2
          L0_3(L1_3, L2_3)
          L0_3 = HelpKeys
          L0_3 = L0_3.Show
          L1_3 = {}
          L2_3 = {}
          L3_3 = _U
          L4_3 = "JOB.STOP_CURRENT_JOB_LABEL"
          L3_3 = L3_3(L4_3)
          L2_3.label = L3_3
          L3_3 = Config
          L3_3 = L3_3.PrisonJobs
          L3_3 = L3_3.LeaveJobKey
          L2_3.keyName = L3_3
          L1_3[1] = L2_3
          L2_3 = "top-left"
          L0_3(L1_3, L2_3)
        end
        L11_2(L12_2, L13_2)
        L11_2 = L9_2.on
        L12_2 = "enter"
        function L13_2()
          local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3
          L0_3 = Jobs
          L0_3 = L0_3.inZone
          if L0_3 then
            return
          end
          L0_3 = Jobs
          L0_3.inZone = true
          L0_3 = dbg
          L0_3 = L0_3.debug
          L1_3 = "You entered job place."
          L2_3 = L10_2
          L0_3(L1_3, L2_3)
          L0_3 = HelpKeys
          L0_3 = L0_3.Show
          L1_3 = {}
          L2_3 = {}
          L3_3 = _U
          L4_3 = "JOB.STOP_CURRENT_JOB_LABEL"
          L3_3 = L3_3(L4_3)
          L2_3.label = L3_3
          L3_3 = Config
          L3_3 = L3_3.PrisonJobs
          L3_3 = L3_3.LeaveJobKey
          L2_3.keyName = L3_3
          L3_3 = {}
          L4_3 = _U
          L5_3 = "JOB.START_TASK_LABEL"
          L4_3 = L4_3(L5_3)
          L3_3.label = L4_3
          L4_3 = Config
          L4_3 = L4_3.PrisonJobs
          L4_3 = L4_3.DoJobKey
          L3_3.keyName = L4_3
          L1_3[1] = L2_3
          L1_3[2] = L3_3
          L2_3 = "top-left"
          L0_3(L1_3, L2_3)
        end
        L11_2(L12_2, L13_2)
        L11_2 = L9_2.render
        L11_2()
        L11_2 = Jobs
        L11_2.currentZone = L9_2
      else
        L9_2 = CreateTargetZone
        L10_2 = L5_2
        L11_2 = 1
        L12_2 = 1
        L13_2 = L6_2 or L13_2
        if not L6_2 then
          L13_2 = 0
        end
        L14_2 = {}
        L15_2 = {}
        L15_2.num = 1
        L15_2.type = "client"
        L15_2.icon = ""
        L15_2.label = L7_2
        L15_2.targeticon = ""
        L15_2.distance = 5.0
        function L16_2(A0_3)
          local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3
          L1_3 = Jobs
          L1_3 = L1_3.Minigame
          L2_3 = L8_2
          L3_3 = A1_2
          L4_3 = L7_2
          L5_3 = A0_2
          L6_3 = A2_2
          L1_3(L2_3, L3_3, L4_3, L5_3, L6_3)
        end
        L15_2.onSelect = L16_2
        function L16_2(A0_3)
          local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3
          L1_3 = Jobs
          L1_3 = L1_3.Minigame
          L2_3 = L8_2
          L3_3 = A1_2
          L4_3 = L7_2
          L5_3 = A0_2
          L6_3 = A2_2
          L1_3(L2_3, L3_3, L4_3, L5_3, L6_3)
        end
        L15_2.action = L16_2
        function L16_2(A0_3, A1_3, A2_3)
          local L3_3
          L3_3 = Jobs
          L3_3 = L3_3.ActiveMinigame
          L3_3 = false == L3_3
          return L3_3
        end
        L15_2.canInteract = L16_2
        L16_2 = {}
        L17_2 = 255
        L18_2 = 255
        L19_2 = 255
        L20_2 = 255
        L16_2[1] = L17_2
        L16_2[2] = L18_2
        L16_2[3] = L19_2
        L16_2[4] = L20_2
        L15_2.drawColor = L16_2
        L16_2 = {}
        L17_2 = 30
        L18_2 = 144
        L19_2 = 255
        L20_2 = 255
        L16_2[1] = L17_2
        L16_2[2] = L18_2
        L16_2[3] = L19_2
        L16_2[4] = L20_2
        L15_2.successDrawColor = L16_2
        L15_2.eventAction = "startTask"
        L15_2.color = 255
        L14_2[1] = L15_2
        L15_2 = L7_2
        L16_2 = true
        L9_2(L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2)
      end
    end
  end
end
L2_1.Init = L3_1
L2_1 = Jobs
function L3_1(A0_2, A1_2, A2_2, A3_2, A4_2)
  local L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L5_2 = Jobs
  L5_2 = L5_2.ActiveMinigame
  if L5_2 then
    L5_2 = dbg
    L5_2 = L5_2.debug
    L6_2 = "Minigame is active?"
    return L5_2(L6_2)
  end
  L5_2 = Subtitles
  L5_2 = L5_2.Hide
  L5_2()
  L5_2 = Jobs
  L5_2.ActiveMinigame = true
  L5_2 = Jobs
  L5_2 = L5_2.currentZone
  if L5_2 then
    L5_2 = Jobs
    L5_2 = L5_2.currentZone
    L5_2 = L5_2.stopRender
    L5_2()
  end
  L5_2 = PlayerPedId
  L5_2 = L5_2()
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "Minigame type: %s"
  L8_2 = A0_2
  L6_2(L7_2, L8_2)
  L6_2 = Config
  L6_2 = L6_2.PrisonJobs
  L6_2 = L6_2.Minigame
  if not L6_2 then
    L6_2 = false
  end
  L7_2 = Jobs
  L7_2.MinigameType = A0_2
  L7_2 = StartDebugSession
  L8_2 = Jobs
  L8_2 = L8_2.MinigameType
  L7_2(L8_2)
  L7_2 = JOBS
  L7_2 = L7_2.ELECTRICIAN
  if A0_2 == L7_2 then
    L7_2 = TaskStartScenarioInPlace
    L8_2 = L5_2
    L9_2 = "WORLD_HUMAN_WELDING"
    L10_2 = 0
    L11_2 = true
    L7_2(L8_2, L9_2, L10_2, L11_2)
    L7_2 = Controller
    L7_2 = L7_2.LoadAndStart
    if A4_2 then
      L8_2 = A4_2.difficulty
      if L8_2 then
        goto lbl_62
      end
    end
    L8_2 = Config
    L8_2 = L8_2.Circuit
    L8_2 = L8_2.Difficulty
    ::lbl_62::
    L9_2 = Config
    L9_2 = L9_2.Circuit
    L9_2 = L9_2.Lifes
    if not L9_2 then
      L9_2 = 3
    end
    function L10_2(A0_3)
      local L1_3, L2_3, L3_3, L4_3, L5_3
      if A0_3 then
        L1_3 = Jobs
        L1_3 = L1_3.FinishedTask
        L2_3 = L5_2
        L3_3 = A1_2
        L4_3 = A2_2
        L5_3 = A3_2
        L1_3(L2_3, L3_3, L4_3, L5_3)
      else
        L1_3 = Jobs
        L1_3 = L1_3.FailedTask
        L2_3 = L5_2
        L3_3 = A1_2
        L4_3 = A2_2
        L5_3 = A3_2
        L1_3(L2_3, L3_3, L4_3, L5_3)
      end
    end
    L7_2(L8_2, L9_2, L10_2)
  else
    L7_2 = JOBS
    L7_2 = L7_2.COOK
    if A0_2 == L7_2 then
      L7_2 = Subtitles
      L7_2 = L7_2.Show
      L8_2 = _U
      L9_2 = "JOB.COOKING_SUBTITLES_ACTIVE_COOKING_LABEL"
      L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2 = L8_2(L9_2)
      L7_2(L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2)
      L7_2 = Stepper
      L7_2 = L7_2.LoadAndStart
      L8_2 = {}
      L9_2 = {}
      if L6_2 then
        L10_2 = L6_2.Cooking
        if L10_2 then
          goto lbl_93
        end
      end
      L10_2 = false
      ::lbl_93::
      L9_2.enabled = L10_2
      L8_2.minigame = L9_2
      L9_2 = _U
      L10_2 = "JOB.COOKING_HELPKEYS_TASK_LABEL"
      L9_2 = L9_2(L10_2)
      L8_2.label = L9_2
      L9_2 = {}
      L9_2.model = "prop_fish_slice_01"
      L10_2 = {}
      L11_2 = vec3
      L12_2 = 0.08
      L13_2 = 0.0
      L14_2 = -0.02
      L11_2 = L11_2(L12_2, L13_2, L14_2)
      L10_2.pos = L11_2
      L11_2 = vec3
      L12_2 = 0.0
      L13_2 = -25.0
      L14_2 = 130.0
      L11_2 = L11_2(L12_2, L13_2, L14_2)
      L10_2.rot = L11_2
      L9_2.offset = L10_2
      L8_2.prop = L9_2
      L9_2 = {}
      L10_2 = {}
      L10_2.dict = "amb@prop_human_bbq@male@enter"
      L10_2.name = "enter"
      L10_2.time = 3050
      L9_2.ENTER = L10_2
      L10_2 = {}
      L10_2.dict = "amb@prop_human_bbq@male@idle_a"
      L10_2.name = "idle_a"
      L9_2.IDLE = L10_2
      L10_2 = {}
      L10_2.dict = "amb@prop_human_bbq@male@base"
      L10_2.name = "base"
      L10_2.time = 2500
      L9_2.ACTION = L10_2
      L10_2 = {}
      L10_2.dict = "amb@prop_human_bbq@male@exit"
      L10_2.name = "exit"
      L10_2.time = 3400
      L9_2.EXIT = L10_2
      L8_2.animMap = L9_2
      L9_2 = {}
      L10_2 = {}
      L11_2 = math
      L11_2 = L11_2.random
      L12_2 = 10
      L13_2 = 20
      L11_2 = L11_2(L12_2, L13_2)
      L10_2.percentIncrease = L11_2
      L10_2.time = 4
      L9_2.action = L10_2
      L8_2.skillMap = L9_2
      function L9_2(A0_3)
        local L1_3, L2_3, L3_3, L4_3, L5_3
        if A0_3 then
          L1_3 = Jobs
          L1_3 = L1_3.FinishedTask
          L2_3 = L5_2
          L3_3 = A1_2
          L4_3 = A2_2
          L5_3 = A3_2
          L1_3(L2_3, L3_3, L4_3, L5_3)
        else
          L1_3 = Jobs
          L1_3 = L1_3.FailedTask
          L2_3 = L5_2
          L3_3 = A1_2
          L4_3 = A2_2
          L5_3 = A3_2
          L1_3(L2_3, L3_3, L4_3, L5_3)
        end
      end
      L7_2(L8_2, L9_2)
    else
      L7_2 = JOBS
      L7_2 = L7_2.BUSH_TRIMMING
      if A0_2 == L7_2 then
        L7_2 = Stepper
        L7_2 = L7_2.LoadAndStart
        L8_2 = {}
        L9_2 = {}
        if L6_2 then
          L10_2 = L6_2.BushTrimming
          if L10_2 then
            goto lbl_176
          end
        end
        L10_2 = false
        ::lbl_176::
        L9_2.enabled = L10_2
        L8_2.minigame = L9_2
        L9_2 = _U
        L10_2 = "JOB.BUSHES_DESCRIPTION"
        L9_2 = L9_2(L10_2)
        L8_2.label = L9_2
        L9_2 = {}
        L9_2.hand = 28422
        L9_2.model = "prop_hedge_trimmer_01"
        L10_2 = {}
        L11_2 = vec3
        L12_2 = 0.0
        L13_2 = 0.0
        L14_2 = 0.0
        L11_2 = L11_2(L12_2, L13_2, L14_2)
        L10_2.pos = L11_2
        L11_2 = vec3
        L12_2 = 0.0
        L13_2 = 0.0
        L14_2 = 0.0
        L11_2 = L11_2(L12_2, L13_2, L14_2)
        L10_2.rot = L11_2
        L9_2.offset = L10_2
        L8_2.prop = L9_2
        L9_2 = {}
        L9_2.dict = "scr_armenian3"
        L9_2.name = "ent_anim_leaf_blower"
        L9_2.boneId = 28422
        L10_2 = {}
        L11_2 = vec3
        L12_2 = 1.0
        L13_2 = 0.0
        L14_2 = -0.1
        L11_2 = L11_2(L12_2, L13_2, L14_2)
        L10_2.pos = L11_2
        L11_2 = vec3
        L12_2 = 0.0
        L13_2 = 0.0
        L14_2 = 0.0
        L11_2 = L11_2(L12_2, L13_2, L14_2)
        L10_2.rot = L11_2
        L9_2.offset = L10_2
        L8_2.particles = L9_2
        L9_2 = {}
        L10_2 = {}
        L10_2.dict = "amb@prop_human_bbq@male@enter"
        L10_2.name = "enter"
        L10_2.time = 3050
        L9_2.ENTER = L10_2
        L10_2 = {}
        L10_2.dict = "amb@world_human_gardener_leaf_blower@idle_a"
        L10_2.name = "idle_a"
        L9_2.IDLE = L10_2
        L10_2 = {}
        L10_2.dict = "amb@world_human_gardener_leaf_blower@base"
        L10_2.name = "base"
        L10_2.time = 3500
        L9_2.ACTION = L10_2
        L10_2 = {}
        L10_2.dict = "amb@prop_human_bbq@male@exit"
        L10_2.name = "exit"
        L10_2.time = 3400
        L9_2.EXIT = L10_2
        L8_2.animMap = L9_2
        L9_2 = {}
        L10_2 = {}
        L10_2.percentIncrease = 20
        L10_2.time = 4
        L9_2.action = L10_2
        L8_2.skillMap = L9_2
        function L9_2(A0_3)
          local L1_3, L2_3, L3_3, L4_3, L5_3
          if A0_3 then
            L1_3 = Jobs
            L1_3 = L1_3.FinishedTask
            L2_3 = L5_2
            L3_3 = A1_2
            L4_3 = A2_2
            L5_3 = A3_2
            L1_3(L2_3, L3_3, L4_3, L5_3)
          else
            L1_3 = Jobs
            L1_3 = L1_3.FailedTask
            L2_3 = L5_2
            L3_3 = A1_2
            L4_3 = A2_2
            L5_3 = A3_2
            L1_3(L2_3, L3_3, L4_3, L5_3)
          end
        end
        L7_2(L8_2, L9_2)
      else
        L7_2 = JOBS
        L7_2 = L7_2.JANITOR
        if A0_2 == L7_2 then
          L7_2 = dbg
          L7_2 = L7_2.debug
          L8_2 = "started janitor task!"
          L7_2(L8_2)
          L7_2 = Stepper
          L7_2 = L7_2.LoadAndStart
          L8_2 = {}
          L9_2 = {}
          if L6_2 then
            L10_2 = L6_2.Janitor
            if L10_2 then
              goto lbl_280
            end
          end
          L10_2 = false
          ::lbl_280::
          L9_2.enabled = L10_2
          L8_2.minigame = L9_2
          L9_2 = _U
          L10_2 = "JOB.JANITOR_TITLE"
          L9_2 = L9_2(L10_2)
          L8_2.label = L9_2
          L9_2 = {}
          L9_2.hand = 28422
          L9_2.model = "prop_tool_broom"
          L10_2 = {}
          L11_2 = vec3
          L12_2 = 0.0
          L13_2 = 0.08
          L14_2 = 0.0
          L11_2 = L11_2(L12_2, L13_2, L14_2)
          L10_2.pos = L11_2
          L11_2 = vec3
          L12_2 = 0.0
          L13_2 = 0.0
          L14_2 = 0.0
          L11_2 = L11_2(L12_2, L13_2, L14_2)
          L10_2.rot = L11_2
          L9_2.offset = L10_2
          L8_2.prop = L9_2
          L9_2 = {}
          L10_2 = {}
          L10_2.dict = "amb@prop_human_bbq@male@enter"
          L10_2.name = "enter"
          L10_2.time = 3050
          L9_2.ENTER = L10_2
          L10_2 = {}
          L10_2.dict = "anim@amb@drug_field_workers@rake@male_a@base"
          L10_2.name = "base"
          L9_2.IDLE = L10_2
          L10_2 = {}
          L10_2.dict = "anim@amb@drug_field_workers@rake@male_a@idles"
          L10_2.name = "idle_b"
          L10_2.time = 3500
          L9_2.ACTION = L10_2
          L10_2 = {}
          L10_2.dict = "amb@prop_human_bbq@male@exit"
          L10_2.name = "exit"
          L10_2.time = 3400
          L9_2.EXIT = L10_2
          L8_2.animMap = L9_2
          L9_2 = {}
          L10_2 = {}
          L11_2 = math
          L11_2 = L11_2.random
          L12_2 = 10
          L13_2 = 20
          L11_2 = L11_2(L12_2, L13_2)
          L10_2.percentIncrease = L11_2
          L10_2.time = 4
          L9_2.action = L10_2
          L8_2.skillMap = L9_2
          function L9_2(A0_3)
            local L1_3, L2_3, L3_3, L4_3, L5_3
            if A0_3 then
              L1_3 = Jobs
              L1_3 = L1_3.FinishedTask
              L2_3 = L5_2
              L3_3 = A1_2
              L4_3 = A2_2
              L5_3 = A3_2
              L1_3(L2_3, L3_3, L4_3, L5_3)
            else
              L1_3 = Jobs
              L1_3 = L1_3.FailedTask
              L2_3 = L5_2
              L3_3 = A1_2
              L4_3 = A2_2
              L5_3 = A3_2
              L1_3(L2_3, L3_3, L4_3, L5_3)
            end
          end
          L7_2(L8_2, L9_2)
        else
          L7_2 = JOBS
          L7_2 = L7_2.CLEAN_GROUND
          if A0_2 == L7_2 then
            L7_2 = Subtitles
            L7_2 = L7_2.Show
            L8_2 = _U
            L9_2 = "JOB.CLEAN_GROUND_SUBTITLES_ACTIVE_STATE_LABEL"
            L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2 = L8_2(L9_2)
            L7_2(L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2)
            L7_2 = Stepper
            L7_2 = L7_2.LoadAndStart
            L8_2 = {}
            L9_2 = {}
            if L6_2 then
              L10_2 = L6_2.CleanGround
              if L10_2 then
                goto lbl_370
              end
            end
            L10_2 = false
            ::lbl_370::
            L9_2.enabled = L10_2
            L8_2.minigame = L9_2
            L9_2 = _U
            L10_2 = "JOB.CLEAR_YARD_TITLE"
            L9_2 = L9_2(L10_2)
            L8_2.label = L9_2
            L9_2 = {}
            L9_2.hand = 57005
            L9_2.model = "prop_leaf_blower_01"
            L10_2 = {}
            L11_2 = vec3
            L12_2 = 0.0
            L13_2 = 0.0
            L14_2 = 0.0
            L11_2 = L11_2(L12_2, L13_2, L14_2)
            L10_2.pos = L11_2
            L11_2 = vec3
            L12_2 = 0.0
            L13_2 = 0.0
            L14_2 = 0.0
            L11_2 = L11_2(L12_2, L13_2, L14_2)
            L10_2.rot = L11_2
            L9_2.offset = L10_2
            L8_2.prop = L9_2
            L9_2 = {}
            L9_2.dict = "scr_armenian3"
            L9_2.name = "ent_anim_leaf_blower"
            L9_2.boneId = 28422
            L10_2 = {}
            L11_2 = vec3
            L12_2 = 1.0
            L13_2 = 0.0
            L14_2 = -0.25
            L11_2 = L11_2(L12_2, L13_2, L14_2)
            L10_2.pos = L11_2
            L11_2 = vec3
            L12_2 = 0.0
            L13_2 = 0.0
            L14_2 = 0.0
            L11_2 = L11_2(L12_2, L13_2, L14_2)
            L10_2.rot = L11_2
            L9_2.offset = L10_2
            L8_2.particles = L9_2
            L9_2 = {}
            L10_2 = {}
            L10_2.dict = "amb@prop_human_bbq@male@enter"
            L10_2.name = "enter"
            L10_2.time = 3050
            L9_2.ENTER = L10_2
            L10_2 = {}
            L10_2.dict = "amb@world_human_gardener_leaf_blower@idle_a"
            L10_2.name = "idle_a"
            L9_2.IDLE = L10_2
            L10_2 = {}
            L10_2.dict = "amb@world_human_gardener_leaf_blower@base"
            L10_2.name = "base"
            L10_2.time = 3500
            L9_2.ACTION = L10_2
            L10_2 = {}
            L10_2.dict = "amb@prop_human_bbq@male@exit"
            L10_2.name = "exit"
            L10_2.time = 3400
            L9_2.EXIT = L10_2
            L8_2.animMap = L9_2
            L9_2 = {}
            L10_2 = {}
            L11_2 = math
            L11_2 = L11_2.random
            L12_2 = 10
            L13_2 = 20
            L11_2 = L11_2(L12_2, L13_2)
            L10_2.percentIncrease = L11_2
            L10_2.time = 4
            L9_2.action = L10_2
            L8_2.skillMap = L9_2
            function L9_2(A0_3)
              local L1_3, L2_3, L3_3, L4_3, L5_3
              if A0_3 then
                L1_3 = Jobs
                L1_3 = L1_3.FinishedTask
                L2_3 = L5_2
                L3_3 = A1_2
                L4_3 = A2_2
                L5_3 = A3_2
                L1_3(L2_3, L3_3, L4_3, L5_3)
              else
                L1_3 = Jobs
                L1_3 = L1_3.FailedTask
                L2_3 = L5_2
                L3_3 = A1_2
                L4_3 = A2_2
                L5_3 = A3_2
                L1_3(L2_3, L3_3, L4_3, L5_3)
              end
            end
            L7_2(L8_2, L9_2)
          else
            L7_2 = Jobs
            L7_2.ActiveMinigame = false
            L7_2 = dbg
            L7_2 = L7_2.debug
            L8_2 = "Minigame type not found!"
            L7_2(L8_2)
          end
        end
      end
    end
  end
end
L2_1.Minigame = L3_1
L2_1 = Jobs
function L3_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L4_2 = Jobs
  L4_2.ActiveJob = false
  L4_2 = Jobs
  L4_2.ActiveMinigame = false
  L4_2 = Jobs
  L4_2.inZone = false
  L4_2 = Jobs
  L4_2 = L4_2.entities
  if L4_2 then
    L4_2 = next
    L5_2 = Jobs
    L5_2 = L5_2.entities
    L4_2 = L4_2(L5_2)
    if L4_2 then
      L4_2 = pairs
      L5_2 = Jobs
      L5_2 = L5_2.entities
      L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
      for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
        L10_2 = DoesEntityExist
        L11_2 = L9_2
        L10_2 = L10_2(L11_2)
        if L10_2 then
          L10_2 = DeleteEntity
          L11_2 = L9_2
          L10_2(L11_2)
          L10_2 = SetEntityDrawOutline
          L11_2 = L9_2
          L12_2 = false
          L10_2(L11_2, L12_2)
        end
      end
      L4_2 = Jobs
      L5_2 = {}
      L4_2.entities = L5_2
    end
  end
  L4_2 = DebugRecordStep
  L5_2 = Jobs
  L5_2 = L5_2.MinigameType
  L6_2 = "Finished job in total"
  L4_2(L5_2, L6_2)
  L4_2 = Jobs
  L4_2.MinigameType = nil
  L4_2 = ClearPedTasks
  L5_2 = A0_2
  L4_2(L5_2)
  L4_2 = RemoveTargetZone
  L5_2 = A2_2
  L6_2 = A3_2
  L4_2(L5_2, L6_2)
  L4_2 = RemoveTargetEntityHiglight
  L4_2()
  L4_2 = Subtitles
  L4_2 = L4_2.Hide
  L4_2()
  L4_2 = HelpKeys
  L4_2 = L4_2.Hide
  L4_2()
  L4_2 = Blips
  L4_2 = L4_2.RemoveByType
  L5_2 = "JOB"
  L4_2(L5_2)
  L4_2 = FreezePlayer
  L5_2 = PlayerId
  L5_2 = L5_2()
  L6_2 = false
  L4_2(L5_2, L6_2)
  L4_2 = FreezeEntityPosition
  L5_2 = A0_2
  L6_2 = false
  L4_2(L5_2, L6_2)
  L4_2 = dbg
  L4_2 = L4_2.debug
  L5_2 = "Job %s finished! %s"
  L6_2 = A3_2
  L7_2 = A1_2
  L4_2(L5_2, L6_2, L7_2)
  L4_2 = DestoryDebugSession
  L5_2 = Jobs
  L5_2 = L5_2.MinigameType
  L4_2(L5_2)
  L4_2 = TriggerServerEvent
  L5_2 = "rcore_prison:server:finishJobTask"
  L6_2 = A3_2
  L7_2 = A1_2
  L4_2(L5_2, L6_2, L7_2)
end
L2_1.FinishedTask = L3_1
L2_1 = Jobs
function L3_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2
  L4_2 = Jobs
  L4_2 = L4_2.ActiveJob
  if not L4_2 then
    return
  end
  L4_2 = Jobs
  L4_2 = L4_2.currentZone
  if L4_2 then
    L4_2 = SetTimeout
    L5_2 = 100
    function L6_2()
      local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3
      L0_3 = HelpKeys
      L0_3 = L0_3.Show
      L1_3 = {}
      L2_3 = {}
      L3_3 = _U
      L4_3 = "JOB.STOP_CURRENT_JOB_LABEL"
      L3_3 = L3_3(L4_3)
      L2_3.label = L3_3
      L3_3 = Config
      L3_3 = L3_3.PrisonJobs
      L3_3 = L3_3.LeaveJobKey
      L2_3.keyName = L3_3
      L3_3 = {}
      L4_3 = _U
      L5_3 = "JOB.START_TASK_LABEL"
      L4_3 = L4_3(L5_3)
      L3_3.label = L4_3
      L4_3 = Config
      L4_3 = L4_3.PrisonJobs
      L4_3 = L4_3.DoJobKey
      L3_3.keyName = L4_3
      L1_3[1] = L2_3
      L1_3[2] = L3_3
      L2_3 = "top-left"
      L0_3(L1_3, L2_3)
    end
    L4_2(L5_2, L6_2)
    L4_2 = Jobs
    L4_2 = L4_2.currentZone
    L4_2 = L4_2.render
    L4_2()
    L4_2 = ClearPedTasksImmediately
    L5_2 = A0_2
    L4_2(L5_2)
  end
  L4_2 = ClearPedTasksImmediately
  L5_2 = A0_2
  L4_2(L5_2)
  L4_2 = RemoveTargetEntityHiglight
  L4_2()
  L4_2 = Subtitles
  L4_2 = L4_2.Hide
  L4_2()
  L4_2 = DebugRecordStep
  L5_2 = Jobs
  L5_2 = L5_2.MinigameType
  L6_2 = "Exit task"
  L4_2(L5_2, L6_2)
  L4_2 = Jobs
  L4_2.ActiveMinigame = false
  L4_2 = FreezePlayer
  L5_2 = PlayerId
  L5_2 = L5_2()
  L6_2 = false
  L4_2(L5_2, L6_2)
  L4_2 = FreezeEntityPosition
  L5_2 = A0_2
  L6_2 = false
  L4_2(L5_2, L6_2)
  L4_2 = dbg
  L4_2 = L4_2.debug
  L5_2 = "Job %s failed! %s "
  L6_2 = A3_2
  L7_2 = A1_2
  L4_2(L5_2, L6_2, L7_2)
end
L2_1.FailedTask = L3_1
L2_1 = NetworkService
L2_1 = L2_1.EventListener
L3_1 = "heartbeat"
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L2_2 = A0_2
  L3_2 = HEARTBEAT_EVENTS
  L3_2 = L3_2.PRISONER_RELEASED
  if L2_2 ~= L3_2 then
    return
  end
  L3_2 = StopStepper
  L3_2()
  L3_2 = Jobs
  L3_2 = L3_2.ExitJob
  L3_2()
  L3_2 = Jobs
  L3_2 = L3_2.entities
  if L3_2 then
    L3_2 = next
    L4_2 = Jobs
    L4_2 = L4_2.entities
    L3_2 = L3_2(L4_2)
    if L3_2 then
      L3_2 = pairs
      L4_2 = Jobs
      L4_2 = L4_2.entities
      L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
      for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
        L9_2 = DoesEntityExist
        L10_2 = L8_2
        L9_2 = L9_2(L10_2)
        if L9_2 then
          L9_2 = DeleteEntity
          L10_2 = L8_2
          L9_2(L10_2)
          L9_2 = SetEntityDrawOutline
          L10_2 = L8_2
          L11_2 = false
          L9_2(L10_2, L11_2)
        end
      end
      L3_2 = Jobs
      L4_2 = {}
      L3_2.entities = L4_2
    end
  end
  L3_2 = Jobs
  L3_2 = L3_2.Entity
  if L3_2 then
    L3_2 = DoesEntityExist
    L4_2 = Jobs
    L4_2 = L4_2.Entity
    L3_2 = L3_2(L4_2)
    if L3_2 then
      L3_2 = DeleteEntity
      L4_2 = Jobs
      L4_2 = L4_2.Entity
      L3_2(L4_2)
      L3_2 = DetachEntity
      L4_2 = Jobs
      L4_2 = L4_2.Entity
      L5_2 = false
      L6_2 = false
      L3_2(L4_2, L5_2, L6_2)
      L3_2 = Jobs
      L3_2.Entity = nil
      L3_2 = ClearPedTasksImmediately
      L4_2 = PlayerPedId
      L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2 = L4_2()
      L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2)
    end
  end
  L3_2 = dbg
  L3_2 = L3_2.debug
  L4_2 = "Found active job on citizen, stopping and clearing props."
  L3_2(L4_2)
end
L2_1(L3_1, L4_1)
L2_1 = Jobs
function L3_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = Dialog
  L1_2 = L1_2.Hide
  L1_2()
  L1_2 = Jobs
  L1_2 = L1_2.currentZone
  if L1_2 then
    L1_2 = Jobs
    L1_2 = L1_2.currentZone
    L1_2 = L1_2.stopRender
    L1_2()
  end
  L1_2 = RemoveTargetZone
  L2_2 = Jobs
  L2_2 = L2_2.zoneName
  L3_2 = Jobs
  L3_2 = L3_2.locationId
  L1_2(L2_2, L3_2)
  L1_2 = RemoveTargetEntityHiglight
  L1_2()
  L1_2 = TriggerServerEvent
  L2_2 = "rcore_prison:server:leaveJobTask"
  L3_2 = Jobs
  L3_2 = L3_2.jobId
  L4_2 = Jobs
  L4_2 = L4_2.locationId
  L5_2 = A0_2
  L1_2(L2_2, L3_2, L4_2, L5_2)
  L1_2 = DestoryDebugSession
  L2_2 = Jobs
  L2_2 = L2_2.MinigameType
  L1_2(L2_2)
  L1_2 = Jobs
  L1_2.MinigameType = nil
  L1_2 = Jobs
  L1_2.ActiveJob = false
  L1_2 = Jobs
  L1_2.ActiveMinigame = false
  L1_2 = Jobs
  L1_2.jobId = nil
  L1_2 = Jobs
  L1_2.locationId = nil
  L1_2 = Jobs
  L1_2.inZone = false
  L1_2 = Jobs
  L1_2.extra = nil
  L1_2 = Jobs
  L1_2.currentZone = nil
  L1_2 = Blips
  L1_2 = L1_2.RemoveByType
  L2_2 = "JOB"
  L1_2(L2_2)
  L1_2 = Subtitles
  L1_2 = L1_2.Hide
  L1_2()
  L1_2 = HelpKeys
  L1_2 = L1_2.Hide
  L1_2()
  L1_2 = FreezePlayer
  L2_2 = PlayerId
  L2_2 = L2_2()
  L3_2 = false
  L1_2(L2_2, L3_2)
  L1_2 = SetTimeout
  L2_2 = 1000
  function L3_2()
    local L0_3, L1_3
    L0_3 = HelpKeys
    L0_3 = L0_3.Hide
    L0_3()
  end
  L1_2(L2_2, L3_2)
  L1_2 = Wait
  L2_2 = 1000
  L1_2(L2_2)
end
L2_1.ExitJob = L3_1
L2_1 = Jobs
function L3_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L0_2 = dbg
  L0_2 = L0_2.debug
  L1_2 = "Job keypress state: %s %s"
  L2_2 = Jobs
  L2_2 = L2_2.inZone
  L3_2 = Jobs
  L3_2 = L3_2.ActiveJob
  L0_2(L1_2, L2_2, L3_2)
  L0_2 = Jobs
  L0_2 = L0_2.inZone
  if L0_2 then
    L0_2 = Jobs
    L0_2 = L0_2.ActiveJob
    if L0_2 then
      L0_2 = SH
      L0_2 = L0_2.data
      L0_2 = L0_2.jobs
      L1_2 = Jobs
      L1_2 = L1_2.jobId
      L0_2 = L0_2[L1_2]
      if not L0_2 then
        L1_2 = dbg
        L1_2 = L1_2.debug
        L2_2 = "Not job found"
        return L1_2(L2_2)
      end
      L1_2 = dbg
      L1_2 = L1_2.debug
      L2_2 = "Starting job minigame!"
      L1_2(L2_2)
      L1_2 = Jobs
      L1_2 = L1_2.Minigame
      L2_2 = L0_2.type
      L3_2 = Jobs
      L3_2 = L3_2.locationId
      L4_2 = Jobs
      L4_2 = L4_2.zoneName
      L5_2 = Jobs
      L5_2 = L5_2.jobId
      L6_2 = Jobs
      L6_2 = L6_2.extra
      L1_2(L2_2, L3_2, L4_2, L5_2, L6_2)
    end
  end
  L0_2 = Wait
  L1_2 = 1000
  L0_2(L1_2)
end
L2_1.HandleKeypress = L3_1
L2_1 = Jobs
function L3_1()
  local L0_2, L1_2, L2_2, L3_2
  L0_2 = Jobs
  L0_2 = L0_2.ActiveJob
  if L0_2 then
    L0_2 = TASK_PROCESSING_STEPPER
    if not L0_2 then
      L0_2 = Jobs
      L0_2 = L0_2.ActiveMinigame
      if L0_2 then
        return
      end
      L0_2 = L0_1
      if L0_2 then
        L0_2 = false
        L0_1 = L0_2
        L0_2 = Jobs
        L0_2 = L0_2.ExitJob
        L0_2()
      else
        L0_2 = Dialog
        L0_2 = L0_2.Show
        L1_2 = _U
        L2_2 = "JOB.LEAVE_JOB_DIALOG"
        L1_2 = L1_2(L2_2)
        L2_2 = _U
        L3_2 = "JOB.LEAVE_JOB_DIALOG_DESC"
        L2_2 = L2_2(L3_2)
        function L3_2(A0_3)
          local L1_3
          if A0_3 then
            L1_3 = Jobs
            L1_3 = L1_3.ExitJob
            L1_3()
          else
            L1_3 = Dialog
            L1_3 = L1_3.Hide
            L1_3()
          end
        end
        L0_2(L1_2, L2_2, L3_2)
      end
    end
  end
end
L2_1.LeaveCurrentJob = L3_1
L2_1 = RegisterKey
L3_1 = Jobs
L3_1 = L3_1.LeaveCurrentJob
L4_1 = "PRISON_JOBS_LEAVE"
L5_1 = _U
L6_1 = "KEYS.JOB_LEAVE_DSC"
L5_1 = L5_1(L6_1)
L6_1 = Config
L6_1 = L6_1.PrisonJobs
L6_1 = L6_1.LeaveJobKey
L2_1(L3_1, L4_1, L5_1, L6_1)
L2_1 = RegisterKey
L3_1 = Jobs
L3_1 = L3_1.HandleKeypress
L4_1 = "PRISON_START_TASK"
L5_1 = _U
L6_1 = "KEYS.JOB_LEAVE_DSC"
L5_1 = L5_1(L6_1)
L6_1 = Config
L6_1 = L6_1.PrisonJobs
L6_1 = L6_1.DoJobKey
L2_1(L3_1, L4_1, L5_1, L6_1)
