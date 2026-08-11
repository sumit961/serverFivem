local L0_1, L1_1, L2_1
L0_1 = {}
PrisonService = L0_1
L0_1 = RegisterCommand
L1_1 = "rcore_prison_debug_release"
function L2_1()
  local L0_2, L1_2, L2_2
  L0_2 = {}
  L1_2 = SH
  L1_2 = L1_2.timeLeft
  L0_2.jail_time = L1_2
  L1_2 = SH
  L1_2 = L1_2.solitaryLeft
  if L1_2 then
    L1_2 = SH
    L1_2 = L1_2.solitaryLeft
    if L1_2 <= 0 then
      L1_2 = "not_in_solitary"
      if L1_2 then
        goto lbl_19
      end
    end
  end
  L1_2 = SH
  L1_2 = L1_2.solitaryLeft
  ::lbl_19::
  L0_2.solitary_time = L1_2
  L1_2 = SH
  L1_2 = L1_2.isRenderingTime
  L0_2.render_state = L1_2
  if L0_2 then
    L1_2 = type
    L2_2 = L0_2
    L1_2 = L1_2(L2_2)
    if "table" == L1_2 then
      L1_2 = next
      L2_2 = L0_2
      L1_2 = L1_2(L2_2)
      if L1_2 then
        L1_2 = tprint
        L2_2 = L0_2
        L1_2(L2_2)
      end
    end
  end
end
L0_1(L1_1, L2_1)
L0_1 = PrisonService
function L1_1(A0_2, ...)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = TriggerEvent
  L2_2 = "rcore_prison:client:heartbeat"
  L3_2 = A0_2
  L4_2 = ...
  L1_2(L2_2, L3_2, L4_2)
end
L0_1.SendHeartbeat = L1_1
L0_1 = PrisonService
function L1_1()
  local L0_2, L1_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_PRISONER
  L0_2 = L0_2(L1_2)
  L1_2 = L0_2.IsPrisoner
  return L1_2()
end
L0_1.IsPrisoner = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = PrisonerModel
  L1_2 = L1_2()
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_PRISONER
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  L3_2 = A0_2.prisoner_id
  L1_2.id = L3_2
  L3_2 = A0_2.owner
  L1_2.charId = L3_2
  L3_2 = A0_2.jail_time
  L1_2.jail_time = L3_2
  L3_2 = A0_2.jail_reason
  L1_2.jail_reason = L3_2
  L3_2 = A0_2.officerName
  L1_2.officerName = L3_2
  L3_2 = A0_2.state
  L1_2.state = L3_2
  L3_2 = A0_2.perollDone
  L1_2.perollDone = L3_2
  L3_2 = L2_2.RegisterPrisoner
  L4_2 = L1_2
  L3_2 = L3_2(L4_2)
  L4_2 = PrisonService
  L4_2 = L4_2.SendHeartbeat
  L5_2 = HEARTBEAT_EVENTS
  L5_2 = L5_2.PRISONER_LOADED
  L6_2 = {}
  L6_2.prisoner = A0_2
  L4_2(L5_2, L6_2)
end
L0_1.RegisterPrisoner = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L2_2 = L1_2.UnregisterPrisoner
  L2_2()
  L2_2 = SH
  L2_2.isRenderingTime = false
  L2_2 = SH
  L2_2.isRenderingPrisonMap = false
  L2_2 = Booths
  L2_2.callSessionState = false
  L2_2 = SH
  L2_2.isSolitaryDone = false
  L2_2 = SH
  L2_2.screen = nil
  L2_2 = SH
  L2_2.zoneId = nil
  L2_2 = HideApp
  L2_2()
  L2_2 = HelpKeys
  L2_2 = L2_2.Hide
  L2_2()
  L2_2 = Text
  L2_2 = L2_2.Hide
  L2_2()
  L2_2 = Subtitles
  L2_2 = L2_2.Hide
  L2_2()
  L2_2 = FrontendService
  L2_2 = L2_2.SendReactMessage
  L3_2 = FE_EVENTS
  L3_2 = L3_2.LOAD_APP
  L4_2 = {}
  L4_2.visible = false
  L4_2.screen = nil
  L2_2(L3_2, L4_2)
  L2_2 = Blips
  L2_2 = L2_2.RemoveByType
  L3_2 = "RELEASE"
  L2_2(L3_2)
  L2_2 = DestroyAllMenus
  L2_2()
  L2_2 = TextService
  L2_2 = L2_2.Hide
  L2_2()
  L2_2 = ClearAllHelpMessages
  L2_2()
  L2_2 = BusyspinnerOff
  L2_2()
  if A0_2 then
    L2_2 = PlayerEscaped
    L2_2()
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Prisoner data were cleared, but the outfit was kept since Prison Break!"
    return L2_2(L3_2)
  end
  L2_2 = SetTimeout
  L3_2 = 1000
  function L4_2()
    local L0_3, L1_3
    L0_3 = dbg
    L0_3 = L0_3.debug
    L1_3 = "Removing loaded UI as fallback!"
    L0_3(L1_3)
    L0_3 = SH
    L0_3.isRenderingTime = false
    L0_3 = TextService
    L0_3 = L0_3.Hide
    L0_3()
    L0_3 = HelpKeys
    L0_3 = L0_3.Hide
    L0_3()
    L0_3 = Text
    L0_3 = L0_3.Hide
    L0_3()
    L0_3 = Subtitles
    L0_3 = L0_3.Hide
    L0_3()
  end
  L2_2(L3_2, L4_2)
  L2_2 = PrisonService
  L2_2 = L2_2.SendHeartbeat
  L3_2 = HEARTBEAT_EVENTS
  L3_2 = L3_2.PRISONER_RELEASED
  L2_2(L3_2)
end
L0_1.ClearPrisonerData = L1_1
L0_1 = PrisonService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = Config
  L0_2 = L0_2.DisplayPrisonMap
  if not L0_2 then
    return
  end
  L0_2 = SH
  L0_2.isRenderingPrisonMap = true
  L0_2 = SetRadarAsInteriorThisFrame
  _SetRadarAsInteriorThisFrame = L0_2
  L0_2 = SetRadarAsExteriorThisFrame
  _SetRadarAsExteriorThisFrame = L0_2
  while true do
    L0_2 = SH
    L0_2 = L0_2.isRenderingPrisonMap
    if not L0_2 then
      break
    end
    L0_2 = Wait
    L1_2 = 0
    L0_2(L1_2)
    L0_2 = _SetRadarAsInteriorThisFrame
    L1_2 = "V_FakePrison"
    L2_2 = 1700.0
    L3_2 = 2580.0
    L4_2 = 0.0
    L5_2 = 0
    L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
    L0_2 = _SetRadarAsExteriorThisFrame
    L0_2()
  end
end
L0_1.DisplayPrisonMap = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L3_2 = A0_2 * 1000
  if A2_2 then
    L4_2 = A2_2 * 1000
    if L4_2 then
      goto lbl_10
    end
  end
  L4_2 = 0
  ::lbl_10::
  L5_2 = GetGameTimer
  L5_2 = L5_2()
  L5_2 = L3_2 + L5_2
  L6_2 = GetGameTimer
  L6_2 = L6_2()
  L6_2 = L4_2 + L6_2
  L7_2 = promise
  L7_2 = L7_2.new
  L7_2 = L7_2()
  L8_2 = Config
  L8_2 = L8_2.RenderJailTime
  if not L8_2 then
    L8_2 = dbg
    L8_2 = L8_2.bridge
    L9_2 = "Jail time is disabled in the config!"
    L8_2(L9_2)
  end
  if A2_2 and not A1_2 then
    A1_2 = true
  end
  if A1_2 then
    L8_2 = SH
    L8_2.isRenderingTime = false
    L8_2 = Text
    L8_2 = L8_2.Hide
    L8_2()
    L8_2 = Wait
    L9_2 = 1000
    L8_2(L9_2)
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "RequestRelease: Jail time has been updated, stopping the current time and starting a new one!"
    L8_2(L9_2)
  end
  L8_2 = SH
  L8_2 = L8_2.isRenderingTime
  if L8_2 then
    L8_2 = dbg
    L8_2 = L8_2.bridge
    L9_2 = "Jail time is already running!"
    L8_2(L9_2)
    return
  end
  L8_2 = SH
  L8_2 = L8_2.isSolitaryDone
  if L8_2 then
    L8_2 = SH
    L8_2.isSolitaryDone = false
  end
  L8_2 = SH
  L8_2.isRenderingTime = true
  L8_2 = SH
  L8_2.solitaryLeft = nil
  L8_2 = SH
  L8_2.timeLeft = nil
  L8_2 = CreateThread
  function L9_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    while true do
      L0_3 = SH
      L0_3 = L0_3.isRenderingTime
      if not L0_3 then
        break
      end
      L0_3 = Wait
      L1_3 = 0
      L0_3(L1_3)
      L0_3 = Time
      L0_3 = L0_3.GetTimeLeftFromGameTime
      L1_3 = L5_2
      L0_3 = L0_3(L1_3)
      L1_3 = Time
      L1_3 = L1_3.GetTimeLeftFromGameTime
      L2_3 = L6_2
      L1_3 = L1_3(L2_3)
      if L1_3 <= 0 then
        L2_3 = SH
        L2_3 = L2_3.isSolitaryDone
        if not L2_3 then
          L2_3 = SH
          L2_3.isSolitaryDone = true
          L2_3 = SH
          L2_3.solitaryLeft = nil
          L2_3 = SolitaryService
          L2_3 = L2_3.ReleasePrisoner
          L2_3()
        end
      end
      L2_3 = Config
      L2_3 = L2_3.RenderJailTime
      if not L2_3 and L0_3 <= 0 then
        L2_3 = SH
        L2_3 = L2_3.solitaryLeft
        if nil == L2_3 then
          L2_3 = SH
          L2_3.isRenderingTime = false
        end
        L2_3 = Text
        L2_3 = L2_3.Hide
        L2_3()
        L2_3 = L7_2
        L3_3 = L2_3
        L2_3 = L2_3.resolve
        L4_3 = true
        L2_3(L3_3, L4_3)
      end
      if L0_3 > 0 then
        L2_3 = Config
        L2_3 = L2_3.RenderJailTime
        if not L2_3 then
        else
          if L1_3 > 0 then
            L2_3 = PrisonService
            L2_3 = L2_3.DisplayTime
            L3_3 = _U
            L4_3 = "DISPLAY_SOLITARY_TIME_WITH_JAIL"
            L5_3 = Time
            L5_3 = L5_3.DynamicSecondsToClock
            L6_3 = L0_3
            L5_3 = L5_3(L6_3)
            L6_3 = Time
            L6_3 = L6_3.DynamicSecondsToClock
            L7_3 = L1_3
            L6_3, L7_3 = L6_3(L7_3)
            L3_3, L4_3, L5_3, L6_3, L7_3 = L3_3(L4_3, L5_3, L6_3, L7_3)
            L2_3(L3_3, L4_3, L5_3, L6_3, L7_3)
          else
            L2_3 = PrisonService
            L2_3 = L2_3.DisplayTime
            L3_3 = _U
            L4_3 = "DISPLAY_JAIL_TIME"
            L5_3 = Time
            L5_3 = L5_3.DynamicSecondsToClock
            L6_3 = L0_3
            L5_3, L6_3, L7_3 = L5_3(L6_3)
            L3_3, L4_3, L5_3, L6_3, L7_3 = L3_3(L4_3, L5_3, L6_3, L7_3)
            L2_3(L3_3, L4_3, L5_3, L6_3, L7_3)
          end
          elseif L0_3 <= 0 then
            L2_3 = SH
            L2_3 = L2_3.solitaryLeft
            if nil == L2_3 then
              L2_3 = SH
              L2_3.isRenderingTime = false
            end
            L2_3 = Text
            L2_3 = L2_3.Hide
            L2_3()
            L2_3 = L7_2
            L3_3 = L2_3
            L2_3 = L2_3.resolve
            L4_3 = true
            L2_3(L3_3, L4_3)
          end
          if L0_3 <= 0 and L1_3 > 0 then
            L2_3 = PrisonService
            L2_3 = L2_3.DisplayTime
            L3_3 = _U
            L4_3 = "DISPLAY_SOLITARY_TIME_WITH_JAIL"
            L5_3 = Time
            L5_3 = L5_3.DynamicSecondsToClock
            L6_3 = L0_3
            L5_3 = L5_3(L6_3)
            L6_3 = Time
            L6_3 = L6_3.DynamicSecondsToClock
            L7_3 = L1_3
            L6_3, L7_3 = L6_3(L7_3)
            L3_3, L4_3, L5_3, L6_3, L7_3 = L3_3(L4_3, L5_3, L6_3, L7_3)
            L2_3(L3_3, L4_3, L5_3, L6_3, L7_3)
          end
          L2_3 = SH
          L2_3.solitaryLeft = L1_3
          L2_3 = SH
          L2_3.timeLeft = L0_3
        end
      L2_3 = Wait
      L3_3 = 1000
      L2_3(L3_3)
    end
  end
  L10_2 = "cl-se-prisoner code name: Phoenix"
  L8_2(L9_2, L10_2)
  L8_2 = dbg
  L8_2 = L8_2.debug
  L9_2 = "RequestRelease: Jail time has started 1/2"
  L8_2(L9_2)
  L8_2 = Citizen
  L8_2 = L8_2.Await
  L9_2 = L7_2
  L8_2(L9_2)
  L8_2 = dbg
  L8_2 = L8_2.debug
  L9_2 = "RequestRelease: Jail time has finished - continue."
  L8_2(L9_2)
  L8_2 = PrisonService
  L8_2 = L8_2.HandleEnforceRelease
  L8_2()
end
L0_1.HandleJailTime = L1_1
L0_1 = PrisonService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L0_2 = Config
  L0_2 = L0_2.Release
  L0_2 = L0_2.AtCheckpoint
  if L0_2 then
    L0_2 = SH
    L0_2 = L0_2.solitaryLeft
    if L0_2 then
      L0_2 = SH
      L0_2 = L0_2.solitaryLeft
      if L0_2 > 0 then
        L0_2 = dbg
        L0_2 = L0_2.debug
        L1_2 = "RequestRelease: Release at checkpoint is enabled, but the solitary time is not finished yet!"
        return L0_2(L1_2)
      end
    end
    L0_2 = TextService
    L0_2 = L0_2.Render
    L1_2 = _U
    L2_2 = "RELEASE.RELEASE_READY_TEXT"
    L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2 = L1_2(L2_2)
    L0_2(L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2)
    L0_2 = SH
    L0_2 = L0_2.data
    L0_2 = L0_2.interaction
    if L0_2 then
      L0_2 = Subtitles
      L0_2 = L0_2.Show
      L1_2 = _U
      L2_2 = "RELEASE.RELEASE_READY_SUBTITLE"
      L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2 = L1_2(L2_2)
      L0_2(L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2)
      L0_2 = pairs
      L1_2 = SH
      L1_2 = L1_2.data
      L1_2 = L1_2.interaction
      L0_2, L1_2, L2_2, L3_2 = L0_2(L1_2)
      for L4_2, L5_2 in L0_2, L1_2, L2_2, L3_2 do
        L6_2 = L5_2.releasePlayerOption
        if L6_2 then
          L6_2 = SetNewWaypoint
          L7_2 = L5_2.coords
          L7_2 = L7_2.x
          L8_2 = L5_2.coords
          L8_2 = L8_2.y
          L6_2(L7_2, L8_2)
          L6_2 = Blips
          L6_2 = L6_2.CreateSquaredArea
          L7_2 = L5_2.coords
          L8_2 = "RELEASE"
          L6_2(L7_2, L8_2)
        end
      end
    end
    L0_2 = dbg
    L0_2 = L0_2.debug
    L1_2 = "RequestRelease: Release at checkpoint is enabled, you need to get to the checkpoint!"
    return L0_2(L1_2)
  end
  L0_2 = TriggerServerEvent
  L1_2 = "rcore_prison:server:requestRelease"
  L0_2(L1_2)
end
L0_1.HandleEnforceRelease = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2
  L1_2 = TextService
  L1_2 = L1_2.Render
  L2_2 = A0_2
  L1_2(L2_2)
end
L0_1.DisplayTime = L1_1
L0_1 = Object
L0_1 = L0_1.registerService
L1_1 = SERVICE_PRISONER
L2_1 = PrisonService
L0_1(L1_1, L2_1)
