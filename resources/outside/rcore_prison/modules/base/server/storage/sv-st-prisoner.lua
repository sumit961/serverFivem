local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = {}
  L0_2._prisoners = L1_2
  L0_2._prisonersLoaded = false
  L1_2 = RegisterCommand
  L2_2 = "prisoners"
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    if 0 == A0_3 then
      L3_3 = next
      L4_3 = L0_2._prisoners
      L3_3 = L3_3(L4_3)
      if L3_3 then
        L3_3 = tprint
        L4_3 = L0_2._prisoners
        L3_3(L4_3)
      else
        L3_3 = dbg
        L3_3 = L3_3.debug
        L4_3 = "There are no prisoners in cache!"
        L3_3(L4_3)
      end
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2.GetPrisonerBySource
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = false
      return L2_3
    end
    L2_3 = L1_3.mugshotState
    return L2_3
  end
  L0_2.MugshotDefinedForPrisoner = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2._prisonersLoaded
    return L0_3
  end
  L0_2.GetPrisonersLoadedState = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3
    L2_3 = L0_2.GetPrisonerBySource
    L3_3 = A0_3
    L2_3 = L2_3(L3_3)
    if not L2_3 then
      L3_3 = dbg
      L3_3 = L3_3.debug
      L4_3 = "Prisoner with playerId (%s) not found!"
      L5_3 = A0_3
      return L3_3(L4_3, L5_3)
    end
    L3_3 = tostring
    L4_3 = A0_3
    L3_3 = L3_3(L4_3)
    L4_3 = IsServerIntervalRunning
    L5_3 = L3_3
    L4_3 = L4_3(L5_3)
    if not L4_3 then
      L4_3 = dbg
      L4_3 = L4_3.debug
      L5_3 = "Thread with id: %s is not running!"
      L6_3 = L3_3
      return L4_3(L5_3, L6_3)
    end
    L4_3 = ClearServerInterval
    L5_3 = L3_3
    L4_3(L5_3)
    L4_3 = L2_3.owner
    L5_3 = L2_3.jail_time
    if L5_3 and L4_3 then
      L5_3 = L2_3.solitary_time
      if L5_3 then
        L5_3 = L2_3.solitary_time
        if L5_3 <= 0 then
          L2_3.solitary_startedAt = nil
        end
      end
      L5_3 = db
      L5_3 = L5_3.UpdateJailData
      L6_3 = L2_3
      L7_3 = L4_3
      L5_3(L6_3, L7_3)
      L5_3 = Config
      L5_3 = L5_3.ReduceSentenceType
      L6_3 = SentenceTypes
      L6_3 = L6_3.OFFLINE
      if L5_3 == L6_3 then
        L5_3 = db
        L5_3 = L5_3.DefinePrisonerJailTime
        L6_3 = L2_3.id
        L7_3 = L2_3.jail_time
        L5_3(L6_3, L7_3)
      end
    end
    L5_3 = dbg
    L5_3 = L5_3.debug
    L6_3 = "Prisoner named (%s) with id: (%s) game-time %s was saved!"
    L7_3 = GetPlayerName
    L8_3 = A0_3
    L7_3 = L7_3(L8_3)
    L8_3 = L2_3.id
    L9_3 = Time
    L9_3 = L9_3.DynamicSecondsToClock
    L10_3 = L2_3.jail_time
    L9_3, L10_3 = L9_3(L10_3)
    L5_3(L6_3, L7_3, L8_3, L9_3, L10_3)
  end
  L0_2.SaveGameTime = L1_2
  L1_2 = DebugSessions
  if not L1_2 then
    L1_2 = {}
  end
  DebugSessions = L1_2
  L1_2 = RegisterCommand
  L2_2 = "times"
  function L3_2(A0_3)
    local L1_3, L2_3
    L1_3 = DebugSessions
    if L1_3 then
      L1_3 = next
      L2_3 = DebugSessions
      L1_3 = L1_3(L2_3)
      if L1_3 then
        L1_3 = tprint
        L2_3 = DebugSessions
        L1_3(L2_3)
      end
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3, L17_3
    L3_3 = L0_2.GetPrisonerBySource
    L4_3 = A0_3
    L3_3 = L3_3(L4_3)
    L4_3 = Config
    L4_3 = L4_3.ReduceSentenceType
    L5_3 = tostring
    L6_3 = A0_3
    L5_3 = L5_3(L6_3)
    if not L3_3 then
      return
    end
    L6_3 = L3_3.state
    L6_3 = not L6_3
    if "jailed" == L6_3 then
      return
    end
    L6_3 = IsServerIntervalRunning
    L7_3 = L5_3
    L6_3 = L6_3(L7_3)
    if L6_3 then
      L6_3 = dbg
      L6_3 = L6_3.debug
      L7_3 = "Thread with id: %s is already running!"
      L8_3 = L5_3
      return L6_3(L7_3, L8_3)
    end
    L6_3 = A1_3 or L6_3
    if not A1_3 then
      L6_3 = L3_3.jail_time
    end
    L7_3 = L6_3 * 1000
    L8_3 = GetGameTimer
    L8_3 = L8_3()
    L8_3 = L7_3 + L8_3
    L9_3 = nil
    L10_3 = nil
    L11_3 = nil
    L12_3 = L3_3.solitary_time
    if L12_3 then
      L9_3 = A2_3 or L9_3
      if not A2_3 then
        L9_3 = L3_3.solitary_time
      end
      L10_3 = L9_3 * 1000
      L12_3 = GetGameTimer
      L12_3 = L12_3()
      L11_3 = L10_3 + L12_3
    end
    L12_3 = GetPlayerName
    L13_3 = A0_3
    L12_3 = L12_3(L13_3)
    L13_3 = Framework
    L13_3 = L13_3.getIdentifier
    L14_3 = A0_3
    L13_3 = L13_3(L14_3)
    L14_3 = DebugSessions
    L15_3 = {}
    L15_3.identifier = L13_3
    L15_3.playerId = A0_3
    L15_3.name = L12_3
    L15_3.time = 0
    L14_3[A0_3] = L15_3
    L14_3 = dbg
    L14_3 = L14_3.debug
    L15_3 = "The game time loaded for user %s"
    L16_3 = GetPlayerName
    L17_3 = A0_3
    L16_3, L17_3 = L16_3(L17_3)
    L14_3(L15_3, L16_3, L17_3)
    L14_3 = SetServerInterval
    L15_3 = L5_3
    L16_3 = 1000
    function L17_3()
      local L0_4, L1_4, L2_4
      L0_4 = Time
      L0_4 = L0_4.GetTimeLeftFromGameTime
      L1_4 = L8_3
      L0_4 = L0_4(L1_4)
      L1_4 = L3_3.solitary_time
      if L1_4 then
        L1_4 = L11_3
        if L1_4 then
          L1_4 = Time
          L1_4 = L1_4.GetTimeLeftFromGameTime
          L2_4 = L11_3
          L1_4 = L1_4(L2_4)
          if L1_4 > 0 then
            L3_3.solitary_time = L1_4
          end
        end
      end
      L1_4 = DebugSessions
      L2_4 = A0_3
      L1_4 = L1_4[L2_4]
      if L1_4 then
        L1_4 = DebugSessions
        L2_4 = A0_3
        L1_4 = L1_4[L2_4]
        L2_4 = L3_3.jail_time
        L1_4.time = L2_4
      end
      if L0_4 > 0 then
        L3_3.jail_time = L0_4
      else
        L1_4 = ClearServerInterval
        L2_4 = L5_3
        L1_4(L2_4)
        L1_4 = L0_2.SaveGameTime
        L2_4 = A0_3
        L1_4(L2_4)
      end
    end
    L14_3(L15_3, L16_3, L17_3)
  end
  L0_2.LoadGameTime = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3
    L1_3 = L0_2._prisoners
    L2_3 = tostring
    L3_3 = A0_3
    L2_3 = L2_3(L3_3)
    L1_3 = L1_3[L2_3]
    return L1_3
  end
  L0_2.GetPrisonerById = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3
    L1_3 = L0_2.GetPrisonerBySource
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = false
      return L2_3
    end
    L2_3 = nil
    L3_3 = L1_3.state
    L4_3 = L1_3.owner
    if "jailed" == L3_3 then
      L5_3 = L0_2.GetPrisonerTimeLeft
      L6_3 = L4_3
      L5_3 = L5_3(L6_3)
      if L5_3 and L5_3 <= 10 then
        L2_3 = true
      end
    end
    return L2_3
  end
  L0_2.CanPrisonerBeReleased = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3
    L2_3 = nil
    L3_3 = Config
    L3_3 = L3_3.ReduceSentenceType
    L4_3 = db
    L4_3 = L4_3.FetchPrisonerTime
    L5_3 = A0_3
    L6_3 = L3_3
    L4_3 = L4_3(L5_3, L6_3)
    L5_3 = type
    L6_3 = L4_3
    L5_3 = L5_3(L6_3)
    if "string" == L5_3 then
      L5_3 = tonumber
      L6_3 = L4_3
      L5_3 = L5_3(L6_3)
      L2_3 = L5_3
    else
      L5_3 = type
      L6_3 = L4_3
      L5_3 = L5_3(L6_3)
      if "table" == L5_3 then
        L2_3 = L4_3.time
      else
        L5_3 = tonumber
        L6_3 = L4_3
        L5_3 = L5_3(L6_3)
        L2_3 = L5_3
      end
    end
    return L2_3
  end
  L0_2.GetPrisonerTimeLeft = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3
    L2_3 = L0_2.GetPrisonerBySource
    L3_3 = A0_3
    L2_3 = L2_3(L3_3)
    L3_3 = SH
    L3_3 = L3_3.data
    L3_3 = L3_3.YardPosPool
    L4_3 = math
    L4_3 = L4_3.random
    L5_3 = 1
    L6_3 = SH
    L6_3 = L6_3.data
    L6_3 = L6_3.YardPosPool
    L6_3 = #L6_3
    L4_3 = L4_3(L5_3, L6_3)
    L3_3 = L3_3[L4_3]
    L4_3 = SH
    L4_3 = L4_3.data
    L4_3 = L4_3.YardPosPool
    if not L4_3 then
      L4_3 = SH
      L4_3 = L4_3.data
      L3_3 = L4_3.prisonYard
    end
    L4_3 = HEARTBEAT_EVENTS
    L4_3 = L4_3.PRISONER_NEW
    if A1_3 == L4_3 then
      L4_3 = Framework
      L4_3 = L4_3.getIdentifier
      L5_3 = A0_3
      L4_3 = L4_3(L5_3)
      L5_3 = pcall
      function L6_3()
        local L0_4, L1_4, L2_4
        L0_4 = Inventory
        L0_4 = L0_4.CreatePrisonerStash
        L1_4 = A0_3
        L2_4 = L4_3
        L0_4(L1_4, L2_4)
      end
      L5_3(L6_3)
      L5_3 = pcall
      function L6_3()
        local L0_4, L1_4, L2_4
        L0_4 = Inventory
        L0_4 = L0_4.HandleOpenState
        L1_4 = A0_3
        L2_4 = true
        L0_4(L1_4, L2_4)
      end
      L5_3, L6_3 = L5_3(L6_3)
      L7_3 = Config
      L7_3 = L7_3.Prolog
      L7_3 = L7_3.Enable
      if L7_3 then
        L7_3 = dbg
        L7_3 = L7_3.debug
        L8_3 = "Starting prolog for prisoner named: %s"
        L9_3 = L2_3.prisonerName
        L7_3(L8_3, L9_3)
        L7_3 = L0_2.HandlePrisonerTeleport
        L8_3 = A0_3
        L9_3 = TELEPORT_TYPES
        L9_3 = L9_3.TO_YARD_NEW_PRISONER
        L10_3 = L3_3.pos
        L7_3(L8_3, L9_3, L10_3)
        L7_3 = callback
        L7_3 = L7_3.await
        L8_3 = "prolog"
        L9_3 = A0_3
        L10_3 = 250
        L11_3 = "a"
        L12_3 = "b"
        L7_3(L8_3, L9_3, L10_3, L11_3, L12_3)
      else
        L7_3 = L0_2.HandlePrisonerTeleport
        L8_3 = A0_3
        L9_3 = TELEPORT_TYPES
        L9_3 = L9_3.TO_YARD_NEW_PRISONER
        L10_3 = L3_3.pos
        L7_3(L8_3, L9_3, L10_3)
      end
      L7_3 = L0_2.LoadGameTime
      L8_3 = A0_3
      L9_3 = L2_3.jail_time
      L10_3 = L2_3.solitary_time
      L7_3(L8_3, L9_3, L10_3)
      L7_3 = PrisonService
      L7_3 = L7_3.SendHeartbeat
      L8_3 = HEARTBEAT_EVENTS
      L8_3 = L8_3.PRISONER_NEW
      L9_3 = {}
      L9_3.prisoner = L2_3
      L7_3(L8_3, L9_3)
    else
      L4_3 = L0_2.LoadGameTime
      L5_3 = A0_3
      L6_3 = L2_3.jail_time
      L7_3 = L2_3.solitary_time
      L4_3(L5_3, L6_3, L7_3)
      L4_3 = L0_2.HandlePrisonerTeleport
      L5_3 = A0_3
      L4_3(L5_3)
      L4_3 = PrisonService
      L4_3 = L4_3.SendHeartbeat
      L5_3 = HEARTBEAT_EVENTS
      L5_3 = L5_3.PRISONER_LOADED
      L6_3 = {}
      L6_3.prisoner = L2_3
      L4_3(L5_3, L6_3)
    end
    L4_3 = L0_2.UpdatePlayerDataByKey
    L5_3 = "source"
    L6_3 = A0_3
    L7_3 = A0_3
    L4_3(L5_3, L6_3, L7_3)
    if L2_3 then
      L4_3 = L2_3.solitary_cell
      if L4_3 then
        L4_3 = L0_2.UpdatePlayerDataByKey
        L5_3 = "solitary_startedAt"
        L6_3 = GetGameTimer
        L6_3 = L6_3()
        L7_3 = A0_3
        L4_3(L5_3, L6_3, L7_3)
      end
    end
    if L2_3 then
      L4_3 = SetTimeout
      L5_3 = 1000
      function L6_3()
        local L0_4, L1_4, L2_4, L3_4
        L0_4 = StartClient
        L1_4 = A0_3
        L2_4 = "prisonerHeartbeat"
        L3_4 = L2_3
        L0_4(L1_4, L2_4, L3_4)
      end
      L4_3(L5_3, L6_3)
    end
    if not A1_3 then
      L4_3 = L0_2.CanPrisonerBeReleased
      L5_3 = A0_3
      L4_3 = L4_3(L5_3)
      if not L4_3 then
        L4_3 = Framework
        L4_3 = L4_3.sendNotification
        L5_3 = A0_3
        L6_3 = _U
        L7_3 = "JAIL.WELCOME_BACK_TO_PRISON"
        L8_3 = Time
        L8_3 = L8_3.DynamicSecondsToClock
        L9_3 = L2_3.jail_time
        L8_3, L9_3, L10_3, L11_3, L12_3 = L8_3(L9_3)
        L6_3 = L6_3(L7_3, L8_3, L9_3, L10_3, L11_3, L12_3)
        L7_3 = "info"
        L4_3(L5_3, L6_3, L7_3)
      end
    end
    L4_3 = PlayerLoadedPool
    L4_3 = L4_3[A0_3]
    if not L4_3 then
      L4_3 = PlayerLoadedPool
      L5_3 = {}
      L5_3.playerId = A0_3
      L5_3.state = true
      L6_3 = GetPlayerName
      L7_3 = A0_3
      L6_3 = L6_3(L7_3)
      L5_3.name = L6_3
      L4_3[A0_3] = L5_3
      L4_3 = dbg
      L4_3 = L4_3.debug
      L5_3 = "Registering player %s into player loaded pool! (player-id: %s)"
      L6_3 = GetPlayerName
      L7_3 = A0_3
      L6_3 = L6_3(L7_3)
      L7_3 = A0_3
      L4_3(L5_3, L6_3, L7_3)
    end
    L4_3 = Inventory
    L4_3 = L4_3.HandleOpenState
    L5_3 = A0_3
    L6_3 = false
    L4_3(L5_3, L6_3)
    L4_3 = dbg
    L4_3 = L4_3.debug
    L5_3 = "Prisoner named (%s) with id: (%s) was loaded!"
    L6_3 = GetPlayerName
    L7_3 = A0_3
    L6_3 = L6_3(L7_3)
    L7_3 = L2_3.id
    L4_3(L5_3, L6_3, L7_3)
    L4_3 = StartClient
    L5_3 = -1
    L6_3 = "updatePrisoner"
    L7_3 = L2_3
    L4_3(L5_3, L6_3, L7_3)
    L4_3 = L0_2.CanPrisonerBeReleased
    L5_3 = A0_3
    L4_3 = L4_3(L5_3)
    if L4_3 then
      L4_3 = Config
      L4_3 = L4_3.Release
      L4_3 = L4_3.AtCheckpoint
      if L4_3 then
        L4_3 = SolitaryService
        L4_3 = L4_3.ReleasePrisoner
        L5_3 = A0_3
        L4_3(L5_3)
        L4_3 = dbg
        L4_3 = L4_3.debug
        L5_3 = "Player named %s (%s) can be released from Prison, but needs to ask Warden to release him!"
        L6_3 = GetPlayerName
        L7_3 = A0_3
        L6_3 = L6_3(L7_3)
        L7_3 = A0_3
        return L4_3(L5_3, L6_3, L7_3)
      end
      L4_3 = L0_2.ReleasePrisoner
      L5_3 = A0_3
      L6_3 = true
      L4_3(L5_3, L6_3)
      return
    end
  end
  L0_2.LoadPrisoner = L1_2
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3
    L3_3 = L0_2.HandlePrisonerLocation
    L4_3 = A0_3
    L5_3 = A1_3
    L6_3 = A2_3
    L3_3, L4_3 = L3_3(L4_3, L5_3, L6_3)
    if L4_3 then
      L5_3 = dbg
      L5_3 = L5_3.debug
      L6_3 = "Prisoner named %s (%s) pos status: %s | Result: %s"
      L7_3 = GetPlayerName
      L8_3 = A0_3
      L7_3 = L7_3(L8_3)
      L8_3 = A0_3
      L9_3 = L4_3
      if not L3_3 then
        L10_3 = "TELEPORTED BACK"
        if L10_3 then
          goto lbl_22
        end
      end
      L10_3 = "NOT_REQUIRED"
      ::lbl_22::
      L5_3(L6_3, L7_3, L8_3, L9_3, L10_3)
    end
  end
  L0_2.HandlePrisonerTeleport = L1_2
  function L1_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3
    L0_3 = GetPlayers
    L0_3 = L0_3()
    L1_3 = promise
    L1_3 = L1_3.new
    L1_3 = L1_3()
    L2_3 = next
    L3_3 = L0_3
    L2_3 = L2_3(L3_3)
    if not L2_3 then
      return
    end
    L2_3 = 1
    L3_3 = #L0_3
    L4_3 = 1
    for L5_3 = L2_3, L3_3, L4_3 do
      L6_3 = tonumber
      L7_3 = L0_3[L5_3]
      L6_3 = L6_3(L7_3)
      L7_3 = L0_2.ConvertPlayerIdToCharacterId
      L8_3 = L6_3
      L7_3 = L7_3(L8_3)
      L8_3 = L0_2._prisoners
      L8_3 = L8_3[L7_3]
      if L8_3 then
        L8_3 = L0_2.LoadPrisoner
        L9_3 = L6_3
        L10_3 = HEARTBEAT_EVENTS
        L10_3 = L10_3.PRISONER_LOADED
        L8_3(L9_3, L10_3)
      end
      L8_3 = #L0_3
      if L5_3 >= L8_3 then
        L9_3 = L1_3
        L8_3 = L1_3.resolve
        L10_3 = true
        L8_3(L9_3, L10_3)
      end
      L8_3 = Wait
      L9_3 = 0
      L8_3(L9_3)
    end
    L2_3 = Citizen
    L2_3 = L2_3.Await
    L3_3 = L1_3
    L2_3(L3_3)
    L0_2._prisonersLoaded = true
  end
  L0_2.CheckOnlinePlayers = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2.GetPrisonerBySource
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = false
      return L2_3
    end
    L2_3 = false
    return L2_3
  end
  L0_2.IsPrisonerOnEscape = L1_2
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3
    L3_3 = true
    L4_3 = "IN_PRISON_AREA"
    L5_3 = GetPlayerPed
    L6_3 = A0_3
    L5_3 = L5_3(L6_3)
    L6_3 = GetEntityCoords
    L7_3 = L5_3
    L6_3 = L6_3(L7_3)
    L7_3 = vec3
    L8_3 = SH
    L8_3 = L8_3.data
    L8_3 = L8_3.prisonYard
    L8_3 = L8_3.x
    L9_3 = SH
    L9_3 = L9_3.data
    L9_3 = L9_3.prisonYard
    L9_3 = L9_3.y
    L10_3 = SH
    L10_3 = L10_3.data
    L10_3 = L10_3.prisonYard
    L10_3 = L10_3.z
    L7_3 = L7_3(L8_3, L9_3, L10_3)
    L8_3 = IsPointInPolygon
    L9_3 = vec2
    L10_3 = L6_3.x
    L11_3 = L6_3.y
    L9_3 = L9_3(L10_3, L11_3)
    L10_3 = SH
    L10_3 = L10_3.data
    L10_3 = L10_3.prisonVertices
    L8_3 = L8_3(L9_3, L10_3)
    L9_3 = L0_2.GetPrisonerBySource
    L10_3 = A0_3
    L9_3 = L9_3(L10_3)
    if L9_3 then
      L10_3 = L9_3.solitary_time
      if L10_3 then
        L10_3 = L9_3.solitary_time
        if L10_3 > 0 then
          L10_3 = SH
          L10_3 = L10_3.data
          L10_3 = L10_3.SolitaryCells
          if not L10_3 then
            return
          end
          L10_3 = SH
          L10_3 = L10_3.data
          L10_3 = L10_3.SolitaryCells
          L11_3 = L9_3.solitary_cell
          L10_3 = L10_3[L11_3]
          if L10_3 then
            L11_3 = vec3
            L12_3 = L10_3.coords
            L12_3 = L12_3.x
            L13_3 = L10_3.coords
            L13_3 = L13_3.y
            L14_3 = L10_3.coords
            L14_3 = L14_3.z
            L11_3 = L11_3(L12_3, L13_3, L14_3)
            L11_3 = L6_3 - L11_3
            L11_3 = #L11_3
            L12_3 = Config
            L12_3 = L12_3.Solitary
            L12_3 = L12_3.DistanceCheck
            if L11_3 >= L12_3 then
              L12_3 = StartClient
              L13_3 = A0_3
              L14_3 = "teleportUser"
              L15_3 = vec4
              L16_3 = L10_3.coords
              L16_3 = L16_3.x
              L17_3 = L10_3.coords
              L17_3 = L17_3.y
              L18_3 = L10_3.coords
              L18_3 = L18_3.z
              L19_3 = 0
              L15_3 = L15_3(L16_3, L17_3, L18_3, L19_3)
              L16_3 = "SOLITARY_CELL_TELEPORT"
              L12_3(L13_3, L14_3, L15_3, L16_3)
              L4_3 = "TELEPORTED_TO_SOLITARY_CELL"
            end
          end
        end
      end
    end
    L10_3 = L0_2.IsPrisonerOnEscape
    L11_3 = A0_3
    L10_3 = L10_3(L11_3)
    if L10_3 then
      L4_3 = "SKIPPING_TELEPORT_SINCE_ACTIVE_ESCAPE"
    end
    if A2_3 then
      L10_3 = StartClient
      L11_3 = A0_3
      L12_3 = "teleportUser"
      L13_3 = A2_3
      L14_3 = A1_3
      L10_3(L11_3, L12_3, L13_3, L14_3)
    end
    if not L8_3 then
      L10_3 = StartClient
      L11_3 = A0_3
      L12_3 = "teleportUser"
      L13_3 = vec4
      L14_3 = L7_3.x
      L15_3 = L7_3.y
      L16_3 = L7_3.z
      L17_3 = 0
      L13_3 = L13_3(L14_3, L15_3, L16_3, L17_3)
      L14_3 = "NOT_IN_PRISON_AREA"
      L10_3(L11_3, L12_3, L13_3, L14_3)
      L4_3 = "NOT_IN_PRISON_AREA"
      L3_3 = false
    end
    L10_3 = L3_3
    L11_3 = L4_3
    return L10_3, L11_3
  end
  L0_2.HandlePrisonerLocation = L1_2
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3
    L3_3 = L0_2.ConvertPlayerIdToCharacterId
    L4_3 = A2_3
    L3_3 = L3_3(L4_3)
    if not L3_3 then
      L4_3 = false
      return L4_3
    end
    L4_3 = L0_2._prisoners
    L4_3 = L4_3[L3_3]
    if not L4_3 then
      L5_3 = false
      return L5_3
    end
    L4_3[A0_3] = A1_3
    L5_3 = true
    return L5_3
  end
  L0_2.UpdatePlayerDataByKey = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L1_3 = L0_2.GetPrisonerById
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = false
      return L2_3
    end
    L2_3 = pcall
    function L3_3()
      local L0_4, L1_4
      L0_4 = db
      L0_4 = L0_4.DeletePrisonerData
      L1_4 = A0_3
      L0_4(L1_4)
    end
    L2_3, L3_3 = L2_3(L3_3)
    L4_3 = PrisonService
    L4_3 = L4_3.SendHeartbeat
    L5_3 = HEARTBEAT_EVENTS
    L5_3 = L5_3.PRISONER_RELEASED
    L6_3 = {}
    L6_3.prisoner = L1_3
    L4_3(L5_3, L6_3)
    L4_3 = L0_2._prisoners
    L4_3[A0_3] = nil
    L4_3 = dbg
    L4_3 = L4_3.debug
    L5_3 = "Prisoner named (%s) with id: (%s) was released offline!"
    L6_3 = L1_3.prisonerName
    L7_3 = L1_3.id
    L4_3(L5_3, L6_3, L7_3)
    L4_3 = true
    return L4_3
  end
  L0_2.ReleasePrisonerOffline = L1_2
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3
    L3_3 = dbg
    L3_3 = L3_3.debug
    L4_3 = "Release prisoner: 1. Converting serverId to charId (%s)"
    L5_3 = GetPlayerName
    L6_3 = A0_3
    L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3 = L5_3(L6_3)
    L3_3(L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
    L3_3 = L0_2.ConvertPlayerIdToCharacterId
    L4_3 = A0_3
    L3_3 = L3_3(L4_3)
    if not L3_3 then
      L4_3 = nil
      return L4_3
    end
    L4_3 = dbg
    L4_3 = L4_3.debug
    L5_3 = "Release prisoner: 2. Checking if player is prisoner (%s)"
    L6_3 = GetPlayerName
    L7_3 = A0_3
    L6_3, L7_3, L8_3, L9_3, L10_3, L11_3 = L6_3(L7_3)
    L4_3(L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
    L4_3 = L0_2._prisoners
    L4_3 = L4_3[L3_3]
    if not L4_3 then
      L4_3 = nil
      return L4_3
    end
    L4_3 = dbg
    L4_3 = L4_3.debug
    L5_3 = "Release prisoner: 3. Loading prisoner model data (%s)"
    L6_3 = GetPlayerName
    L7_3 = A0_3
    L6_3, L7_3, L8_3, L9_3, L10_3, L11_3 = L6_3(L7_3)
    L4_3(L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
    L4_3 = L0_2.GetPrisonerBySource
    L5_3 = A0_3
    L4_3 = L4_3(L5_3)
    if L4_3 and not A2_3 then
      L5_3 = LogService
      L5_3 = L5_3.RegisterTransaction
      L6_3 = "RELEASE_PLAYER"
      L7_3 = _U
      L8_3 = "LOGS_ACTIONS.LOG_CITIZEN_CITIZEN_RELEASED_BY_OFFICER"
      L9_3 = L4_3.prisonerName
      L10_3 = L4_3.officerName
      L7_3 = L7_3(L8_3, L9_3, L10_3)
      L8_3 = L4_3.owner
      L9_3 = L4_3.officerName
      L10_3 = L4_3.prisonerName
      L5_3(L6_3, L7_3, L8_3, L9_3, L10_3)
    end
    if A2_3 then
      L4_3.escaped = true
    end
    L5_3 = PrisonService
    L5_3 = L5_3.SendHeartbeat
    L6_3 = HEARTBEAT_EVENTS
    L6_3 = L6_3.PRISONER_RELEASED
    L7_3 = {}
    L7_3.prisoner = L4_3
    L5_3(L6_3, L7_3)
    L5_3 = dbg
    L5_3 = L5_3.debug
    L6_3 = "Release prisoner: 4. Heatbeart of prisoner was sent now moving to deleting prisoner data (%s)"
    L7_3 = GetPlayerName
    L8_3 = A0_3
    L7_3, L8_3, L9_3, L10_3, L11_3 = L7_3(L8_3)
    L5_3(L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
    L5_3 = Config
    L5_3 = L5_3.Accounts
    L5_3 = L5_3.DeleteAccountWhenReleased
    if L5_3 then
      L5_3 = PrisonAccountService
      L5_3 = L5_3.DeleteAccount
      L6_3 = A0_3
      L7_3 = L3_3
      L5_3(L6_3, L7_3)
    end
    L5_3 = pcall
    L6_3 = db
    L6_3 = L6_3.DeletePrisonerData
    L7_3 = L3_3
    L5_3, L6_3 = L5_3(L6_3, L7_3)
    if not L5_3 then
      L7_3 = dbg
      L7_3 = L7_3.critical
      L8_3 = "Release prisoner: 5.5. Failed to remove prisoner data since error: %s"
      L9_3 = L6_3
      L7_3(L8_3, L9_3)
    end
    L7_3 = dbg
    L7_3 = L7_3.debug
    L8_3 = "Release prisoner: 6. Clearing player cache from storage (%s)"
    L9_3 = GetPlayerName
    L10_3 = A0_3
    L9_3, L10_3, L11_3 = L9_3(L10_3)
    L7_3(L8_3, L9_3, L10_3, L11_3)
    L7_3 = L0_2._prisoners
    L7_3[L3_3] = nil
    L7_3 = dbg
    L7_3 = L7_3.debug
    L8_3 = "Release prisoner: 7. Sending heartbeat to client, to remove data (%s)"
    L9_3 = GetPlayerName
    L10_3 = A0_3
    L9_3, L10_3, L11_3 = L9_3(L10_3)
    L7_3(L8_3, L9_3, L10_3, L11_3)
    L7_3 = StartClient
    L8_3 = A0_3
    L9_3 = "prisonerHeartbeat"
    L10_3 = nil
    L11_3 = A2_3
    L7_3(L8_3, L9_3, L10_3, L11_3)
    L7_3 = Config
    L7_3 = L7_3.Teleport
    L8_3 = "WhenReleasedTeleportPrisonerInFrontOfPrison"
    L7_3 = L7_3[L8_3]
    if L7_3 and A1_3 then
      L7_3 = dbg
      L7_3 = L7_3.debug
      L8_3 = "Release prisoner: 8. Target player named (%s) should be teleported outside of prison since release."
      L9_3 = GetPlayerName
      L10_3 = A0_3
      L9_3, L10_3, L11_3 = L9_3(L10_3)
      L7_3(L8_3, L9_3, L10_3, L11_3)
      L7_3 = StartClient
      L8_3 = A0_3
      L9_3 = "teleportUser"
      L10_3 = SH
      L10_3 = L10_3.data
      L10_3 = L10_3.releasePos
      L11_3 = TELEPORT_TYPES
      L11_3 = L11_3.TO_OUTSIDE_PRISON_RELEASED
      L7_3(L8_3, L9_3, L10_3, L11_3)
    end
    if not A2_3 then
      L7_3 = Framework
      L7_3 = L7_3.sendNotification
      L8_3 = A0_3
      L9_3 = _U
      L10_3 = "PLAYER_RELEASED"
      L9_3 = L9_3(L10_3)
      L10_3 = "info"
      L7_3(L8_3, L9_3, L10_3)
    end
    L7_3 = true
    return L7_3
  end
  L0_2.ReleasePrisoner = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    if not A0_3 then
      return
    end
    L1_3 = A0_3.owner
    if not L1_3 then
      return
    end
    L1_3 = L0_2._prisoners
    L2_3 = A0_3.owner
    L1_3[L2_3] = A0_3
    L1_3 = A0_3.owner
    return L1_3
  end
  L0_2.AddPlayer = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = tonumber
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    A0_3 = L1_3
    if not A0_3 then
      L1_3 = nil
      return L1_3
    end
    L1_3 = Framework
    L1_3 = L1_3.getIdentifier
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    return L1_3
  end
  L0_2.ConvertPlayerIdToCharacterId = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = L0_2.ConvertPlayerIdToCharacterId
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._prisoners
    L2_3 = L2_3[L1_3]
    return L2_3
  end
  L0_2.GetPrisonerBySource = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3
    L2_3 = L0_2._prisoners
    L2_3 = L2_3[A0_3]
    L3_3 = L2_3.jail_time
    L4_3 = L0_2.UpdatePlayerDataByKey
    L5_3 = "jail_time"
    L6_3 = A1_3
    L7_3 = L2_3.source
    L4_3(L5_3, L6_3, L7_3)
    L4_3 = L0_2.UpdatePlayerDataByKey
    L5_3 = "hasTimeChange"
    L6_3 = true
    L7_3 = L2_3.source
    L4_3(L5_3, L6_3, L7_3)
    L4_3 = L0_2.SaveGameTime
    L5_3 = L2_3.source
    L4_3(L5_3)
    L4_3 = Wait
    L5_3 = 1000
    L4_3(L5_3)
    L4_3 = L0_2.LoadGameTime
    L5_3 = L2_3.source
    L6_3 = A1_3
    L4_3(L5_3, L6_3)
    L2_3.jail_time = A1_3
    L4_3 = L2_3.source
    if L4_3 then
      L4_3 = StartClient
      L5_3 = L2_3.source
      L6_3 = "prisonerHeartbeat"
      L7_3 = L2_3
      L4_3(L5_3, L6_3, L7_3)
      L4_3 = L0_2.UpdatePlayerDataByKey
      L5_3 = "hasTimeChange"
      L6_3 = false
      L7_3 = L2_3.source
      L4_3(L5_3, L6_3, L7_3)
      L4_3 = dbg
      L4_3 = L4_3.debug
      L5_3 = "Prisoner named (%s) sentence was updated to %s! -> requested by %s"
      L6_3 = GetPlayerName
      L7_3 = L2_3.source
      L6_3 = L6_3(L7_3)
      L7_3 = Time
      L7_3 = L7_3.DynamicSecondsToClock
      L8_3 = A1_3
      L7_3 = L7_3(L8_3)
      L8_3 = GetInvokingResource
      L8_3 = L8_3()
      if nil == L8_3 then
        L8_3 = "INTERNAL FUNCTION"
        if L8_3 then
          goto lbl_57
        end
      end
      L8_3 = GetInvokingResource
      L8_3 = L8_3()
      ::lbl_57::
      L4_3(L5_3, L6_3, L7_3, L8_3)
    end
    L4_3 = L2_3.officerName
    if L4_3 then
      L4_3 = L2_3.jail_time
      if L4_3 and A0_3 then
        L4_3 = L2_3.prisonerName
        if L4_3 then
          L4_3 = LogService
          L4_3 = L4_3.RegisterTransaction
          L5_3 = "EDIT_SENTENCE"
          L6_3 = _U
          L7_3 = "LOGS_ACTIONS.LOG_CITIZEN_CHANGED_SENTENCE_BY_OFFICER"
          L8_3 = L2_3.officerName
          L9_3 = Time
          L9_3 = L9_3.DynamicSecondsToClock
          L10_3 = L3_3
          L9_3 = L9_3(L10_3)
          L10_3 = Time
          L10_3 = L10_3.DynamicSecondsToClock
          L11_3 = L2_3.jail_time
          L10_3, L11_3 = L10_3(L11_3)
          L6_3 = L6_3(L7_3, L8_3, L9_3, L10_3, L11_3)
          L7_3 = A0_3
          L8_3 = L2_3.prisonerName
          L9_3 = L2_3.prisonerName
          L4_3(L5_3, L6_3, L7_3, L8_3, L9_3)
        end
      end
    end
  end
  L0_2.UpdatePlayerSentence = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3
    L1_3 = L0_2.ConvertPlayerIdToCharacterId
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if not L1_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._prisoners
    L2_3 = L2_3[L1_3]
    if not L2_3 then
      L2_3 = nil
      return L2_3
    end
    L2_3 = L0_2._prisoners
    L2_3 = L2_3[L1_3]
    L3_3 = L0_2.SaveGameTime
    L4_3 = A0_3
    L3_3(L4_3)
    L2_3.source = nil
    L3_3 = ClearServerInterval
    L4_3 = tostring
    L5_3 = A0_3
    L4_3, L5_3, L6_3 = L4_3(L5_3)
    L3_3(L4_3, L5_3, L6_3)
    L3_3 = StartClient
    L4_3 = A0_3
    L5_3 = "prisonerHeartbeat"
    L3_3(L4_3, L5_3)
    L3_3 = dbg
    L3_3 = L3_3.debug
    L4_3 = "Prisoner named (%s) with id: (%s) was saved!"
    L5_3 = GetPlayerName
    L6_3 = A0_3
    L5_3 = L5_3(L6_3)
    L6_3 = L2_3.id
    L3_3(L4_3, L5_3, L6_3)
  end
  L0_2.SavePrisoner = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3
    L1_3 = {}
    L2_3 = pairs
    L3_3 = A0_3
    L2_3, L3_3, L4_3, L5_3 = L2_3(L3_3)
    for L6_3, L7_3 in L2_3, L3_3, L4_3, L5_3 do
      L8_3 = L7_3.source
      if L8_3 then
        L8_3 = L7_3.owner
        L1_3[L8_3] = L7_3
      end
    end
    return L1_3
  end
  filterBySource = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    if A0_3 then
      L1_3 = filterBySource
      L2_3 = L0_2._prisoners
      return L1_3(L2_3)
    end
    L1_3 = L0_2._prisoners
    return L1_3
  end
  L0_2.GetAllPrisoners = L1_2
  return L0_2
end
PrisonerStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_PRISONER
L2_1 = PrisonerStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
