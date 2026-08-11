local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = {}
SolitaryService = L0_1
L0_1 = SolitaryService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = NetworkGetEntityFromNetworkId
  L3_2 = A1_2
  L2_2 = L2_2(L3_2)
  L3_2 = GetPlayerPed
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = GetEntityCoords
  L5_2 = L2_2
  L4_2 = L4_2(L5_2)
  L5_2 = GetEntityCoords
  L6_2 = L3_2
  L5_2 = L5_2(L6_2)
  L6_2 = L4_2 - L5_2
  L6_2 = #L6_2
  L7_2 = Config
  L7_2 = L7_2.Solitary
  L7_2 = L7_2.GuardDistanceCheck
  L7_2 = L6_2 <= L7_2
  return L7_2
end
L0_1.IsPlayerCloseToGuard = L1_1
L0_1 = SolitaryService
function L1_1(A0_2)
  local L1_2, L2_2
  L1_2 = PrisonService
  L1_2 = L1_2.getPlayer
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = L1_2.solitary_time
  if L2_2 then
    L2_2 = L1_2.solitary_time
  end
  L2_2 = L2_2 > 0 or L2_2
  return L2_2
end
L0_1.HasSentence = L1_1
L0_1 = SolitaryService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = PrisonService
  L1_2 = L1_2.getPlayer
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Failed to release player from solitary, since he is not a prisoner"
    return L2_2(L3_2)
  end
  L2_2 = L1_2.solitary_cell
  if not L2_2 then
    return
  end
  L1_2.solitary_time = nil
  L1_2.solitary_cell = nil
  L1_2.solitary_startedAt = nil
  L2_2 = db
  L2_2 = L2_2.UpdateJailData
  L3_2 = L1_2
  L4_2 = L1_2.owner
  L2_2 = L2_2(L3_2, L4_2)
  if L2_2 then
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "Releasing player named %s (%s) from solitary"
    L5_2 = GetPlayerName
    L6_2 = A0_2
    L5_2 = L5_2(L6_2)
    L6_2 = A0_2
    L3_2(L4_2, L5_2, L6_2)
    L3_2 = SH
    L3_2 = L3_2.data
    L3_2 = L3_2.prisonYard
    if L3_2 then
      L3_2 = vec3
      L4_2 = SH
      L4_2 = L4_2.data
      L4_2 = L4_2.prisonYard
      L4_2 = L4_2.x
      L5_2 = SH
      L5_2 = L5_2.data
      L5_2 = L5_2.prisonYard
      L5_2 = L5_2.y
      L6_2 = SH
      L6_2 = L6_2.data
      L6_2 = L6_2.prisonYard
      L6_2 = L6_2.z
      L3_2 = L3_2(L4_2, L5_2, L6_2)
      if L3_2 then
        L4_2 = StartClient
        L5_2 = A0_2
        L6_2 = "teleportUser"
        L7_2 = L3_2
        L4_2(L5_2, L6_2, L7_2)
      end
    end
    L3_2 = SetTimeout
    L4_2 = 1000
    function L5_2()
      local L0_3, L1_3, L2_3, L3_3
      L1_2.hasTimeChange = true
      L0_3 = StartClient
      L1_3 = A0_2
      L2_3 = "prisonerHeartbeat"
      L3_3 = L1_2
      L0_3(L1_3, L2_3, L3_3)
      L1_2.hasTimeChange = false
    end
    L3_2(L4_2, L5_2)
    L3_2 = LogService
    L3_2 = L3_2.RegisterTransaction
    L4_2 = _U
    L5_2 = "SOLITARY.MDW_LOG_TITLE_RELEASED"
    L4_2 = L4_2(L5_2)
    L5_2 = _U
    L6_2 = "SOLITARY.MDW_LOG_DESC_RELEASED"
    L5_2 = L5_2(L6_2)
    L6_2 = L1_2.owner
    L7_2 = nil
    L8_2 = L1_2.prisonerName
    L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
    L3_2 = Discord
    L3_2 = L3_2.SendMessage
    L4_2 = _U
    L5_2 = "SOLITARY.DISCORD_LOG_SENT_TITLE_RELEASED"
    L4_2 = L4_2(L5_2)
    L5_2 = _U
    L6_2 = "SOLITARY.DISCORD_LOG_SENT_DESC_RELEASED"
    L5_2 = L5_2(L6_2)
    L6_2 = {}
    L7_2 = {}
    L8_2 = _U
    L9_2 = "SOLITARY.DISCORD_LOG_OOC_NAME_LABEL"
    L8_2 = L8_2(L9_2)
    L7_2.name = L8_2
    L8_2 = GetPlayerName
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    L7_2.value = L8_2
    L8_2 = {}
    L9_2 = _U
    L10_2 = "SOLITARY.DISCORD_LOG_IC_NAME_LABEL"
    L9_2 = L9_2(L10_2)
    L8_2.name = L9_2
    L9_2 = L1_2.prisonerName
    L8_2.value = L9_2
    L6_2[1] = L7_2
    L6_2[2] = L8_2
    L3_2(L4_2, L5_2, L6_2)
    L3_2 = Framework
    L3_2 = L3_2.sendNotification
    L4_2 = A0_2
    L5_2 = _U
    L6_2 = "SOLITARY.RELEASED"
    L5_2 = L5_2(L6_2)
    L6_2 = "success"
    L3_2(L4_2, L5_2, L6_2)
  end
end
L0_1.ReleasePrisoner = L1_1
L0_1 = SolitaryService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L0_2 = SH
  L0_2 = L0_2.data
  L0_2 = L0_2.SolitaryCells
  if not L0_2 then
    return
  end
  L1_2 = math
  L1_2 = L1_2.random
  L2_2 = 1
  L3_2 = #L0_2
  L1_2 = L1_2(L2_2, L3_2)
  L2_2 = L0_2[L1_2]
  L3_2 = Config
  L3_2 = L3_2.Debug
  if L3_2 then
    L3_2 = tprint
    L4_2 = L2_2
    L3_2(L4_2)
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "Solitary: selecting random cell with ID: %s on map preset: %s"
    L5_2 = L1_2
    L6_2 = Config
    L6_2 = L6_2.Map
    L3_2(L4_2, L5_2, L6_2)
  end
  L3_2 = L1_2
  L4_2 = L2_2
  return L3_2, L4_2
end
L0_1.GetRandomCell = L1_1
L0_1 = SolitaryService
function L1_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2
  if not A0_2 then
    return
  end
  L4_2 = PrisonService
  L4_2 = L4_2.getPlayer
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    L5_2 = dbg
    L5_2 = L5_2.debug
    L6_2 = "Failed to set player for solitary, since he is not a prisoner"
    return L5_2(L6_2)
  end
  if L4_2 then
    L5_2 = L4_2.solitary_cell
    if L5_2 then
      L5_2 = Framework
      L5_2 = L5_2.sendNotification
      L6_2 = A0_2
      L7_2 = _U
      L8_2 = "SOLITARY.ALREADY_IN_SOLITARY"
      L7_2 = L7_2(L8_2)
      L8_2 = "error"
      L5_2(L6_2, L7_2, L8_2)
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "Failed to set player for solitary, since he is already in solitary"
      return L5_2(L6_2)
    end
  end
  L5_2 = Time
  L5_2 = L5_2.ConvertTimeFromSeconds
  L6_2 = A1_2
  L7_2 = Config
  L7_2 = L7_2.Time
  L5_2 = L5_2(L6_2, L7_2)
  if L5_2 then
    L6_2 = SolitaryService
    L6_2 = L6_2.GetRandomCell
    L6_2, L7_2 = L6_2()
    L4_2.solitary_cell = L6_2
    L4_2.solitary_time = L5_2
    L8_2 = db
    L8_2 = L8_2.UpdateJailData
    L9_2 = L4_2
    L10_2 = L4_2.owner
    L8_2 = L8_2(L9_2, L10_2)
    if L8_2 then
      L9_2 = db
      L9_2 = L9_2.DefinePrisonerSolitaryTime
      L10_2 = L4_2.id
      L11_2 = L5_2
      L9_2(L10_2, L11_2)
    end
    L9_2 = nil
    if A3_2 then
      L10_2 = Framework
      L10_2 = L10_2.getCharacterName
      L11_2 = A3_2
      L10_2 = L10_2(L11_2)
      L9_2 = L10_2
    end
    L10_2 = GetGameTimer
    L10_2 = L10_2()
    L4_2.solitary_startedAt = L10_2
    if L7_2 then
      L10_2 = StartClient
      L11_2 = A0_2
      L12_2 = "teleportUser"
      L13_2 = L7_2.coords
      L10_2(L11_2, L12_2, L13_2)
    end
    L10_2 = SetTimeout
    L11_2 = 1000
    function L12_2()
      local L0_3, L1_3, L2_3, L3_3
      L0_3 = StartClient
      L1_3 = A0_2
      L2_3 = "prisonerHeartbeat"
      L3_3 = L4_2
      L0_3(L1_3, L2_3, L3_3)
    end
    L10_2(L11_2, L12_2)
    L10_2 = Framework
    L10_2 = L10_2.sendNotification
    L11_2 = A0_2
    L12_2 = _U
    L13_2 = "SOLITARY.PLACED_IN_SOLITARY"
    L14_2 = Time
    L14_2 = L14_2.DynamicSecondsToClock
    L15_2 = L5_2
    L14_2, L15_2, L16_2, L17_2, L18_2, L19_2 = L14_2(L15_2)
    L12_2 = L12_2(L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2)
    L13_2 = "success"
    L10_2(L11_2, L12_2, L13_2)
    L10_2 = LogService
    L10_2 = L10_2.RegisterTransaction
    L11_2 = _U
    L12_2 = "SOLITARY.MDW_LOG_TITLE"
    L11_2 = L11_2(L12_2)
    L12_2 = _U
    L13_2 = "SOLITARY.MDW_LOG_DESC"
    L14_2 = Time
    L14_2 = L14_2.DynamicSecondsToClock
    L15_2 = L5_2
    L14_2 = L14_2(L15_2)
    L15_2 = A2_2 or L15_2
    if not A2_2 then
      L15_2 = "-"
    end
    L12_2 = L12_2(L13_2, L14_2, L15_2)
    L13_2 = L4_2.owner
    L14_2 = L9_2
    L15_2 = L4_2.prisonerName
    L10_2(L11_2, L12_2, L13_2, L14_2, L15_2)
    L10_2 = Discord
    L10_2 = L10_2.SendMessage
    L11_2 = _U
    L12_2 = "SOLITARY.DISCORD_LOG_SENT_TITLE"
    L11_2 = L11_2(L12_2)
    L12_2 = _U
    L13_2 = "SOLITARY.DISCORD_LOG_SENT_DESC"
    L12_2 = L12_2(L13_2)
    L13_2 = {}
    L14_2 = {}
    L15_2 = _U
    L16_2 = "SOLITARY.DISCORD_LOG_OOC_NAME_LABEL"
    L15_2 = L15_2(L16_2)
    L14_2.name = L15_2
    L15_2 = GetPlayerName
    L16_2 = A0_2
    L15_2 = L15_2(L16_2)
    L14_2.value = L15_2
    L15_2 = {}
    L16_2 = _U
    L17_2 = "SOLITARY.DISCORD_LOG_IC_NAME_LABEL"
    L16_2 = L16_2(L17_2)
    L15_2.name = L16_2
    L16_2 = L4_2.prisonerName
    L15_2.value = L16_2
    L16_2 = {}
    L17_2 = _U
    L18_2 = "SOLITARY.DISCORD_LOG_REASON_LABEL"
    L17_2 = L17_2(L18_2)
    L16_2.name = L17_2
    L17_2 = A2_2 or L17_2
    if not A2_2 then
      L17_2 = "-"
    end
    L16_2.value = L17_2
    L17_2 = {}
    L18_2 = _U
    L19_2 = "SOLITARY.DISCORD_LOG_TIME_LABEL"
    L18_2 = L18_2(L19_2)
    L17_2.name = L18_2
    L18_2 = Time
    L18_2 = L18_2.DynamicSecondsToClock
    L19_2 = L5_2
    L18_2 = L18_2(L19_2)
    L17_2.value = L18_2
    L13_2[1] = L14_2
    L13_2[2] = L15_2
    L13_2[3] = L16_2
    L13_2[4] = L17_2
    L10_2(L11_2, L12_2, L13_2)
    L10_2 = dbg
    L10_2 = L10_2.debug
    L11_2 = "Setting player named %s (%s) for solitary"
    L12_2 = GetPlayerName
    L13_2 = A0_2
    L12_2 = L12_2(L13_2)
    L13_2 = A0_2
    L10_2(L11_2, L12_2, L13_2)
  end
end
L0_1.SetPrisonerSentence = L1_1
L0_1 = SolitaryService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = false
  L2_2 = PrisonService
  L2_2 = L2_2.getPlayer
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return L1_2
  end
  L3_2 = L2_2.solitary_time
  if not L3_2 then
    return L1_2
  end
  L3_2 = L2_2.solitary_startedAt
  L4_2 = L2_2.solitary_time
  L4_2 = L4_2 * 1000
  if not L3_2 then
    return L1_2
  end
  L5_2 = L3_2 + L4_2
  L6_2 = GetGameTimer
  L6_2 = L6_2()
  if L5_2 <= L6_2 then
    L1_2 = true
  end
  L7_2 = dbg
  L7_2 = L7_2.debug
  L8_2 = "Solitary player named %s release state: %s"
  L9_2 = GetPlayerName
  L10_2 = A0_2
  L9_2 = L9_2(L10_2)
  L10_2 = L1_2
  L7_2(L8_2, L9_2, L10_2)
  return L1_2
end
L0_1.CanBeAutoReleased = L1_1
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:requestSolitaryRelease"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2)
  local L2_2, L3_2
  if A1_2 then
    L2_2 = SolitaryService
    L2_2 = L2_2.CanBeAutoReleased
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if L2_2 then
      L2_2 = SolitaryService
      L2_2 = L2_2.ReleasePrisoner
      L3_2 = A0_2
      L2_2(L3_2)
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
L0_1 = RegisterNetEvent
L1_1 = "rcore_prison:server:guardWasAttackedByPrisoner"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L2_2 = source
  if not A0_2 then
    return
  end
  if L2_2 ~= A1_2 then
    return
  end
  L3_2 = GetPatrollingGuards
  L3_2 = L3_2()
  L4_2 = L3_2[A0_2]
  if not L4_2 then
    return
  end
  L4_2 = SolitaryService
  L4_2 = L4_2.IsPlayerCloseToGuard
  L5_2 = L2_2
  L6_2 = A0_2
  L4_2 = L4_2(L5_2, L6_2)
  if not L4_2 then
    return
  end
  L4_2 = PrisonService
  L4_2 = L4_2.getPlayer
  L5_2 = L2_2
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    L5_2 = CitizenAttackedGuard
    L6_2 = A1_2
    L5_2(L6_2)
    return
  end
  L5_2 = Config
  L5_2 = L5_2.Solitary
  L5_2 = L5_2.Time
  L6_2 = Framework
  L6_2 = L6_2.sendNotification
  L7_2 = L2_2
  L8_2 = _U
  L9_2 = "SOLITARY.PRISONER_ATTACKED_GUARD"
  L10_2 = Time
  L10_2 = L10_2.DynamicSecondsToClock
  L11_2 = L5_2
  L10_2, L11_2 = L10_2(L11_2)
  L8_2 = L8_2(L9_2, L10_2, L11_2)
  L9_2 = "success"
  L6_2(L7_2, L8_2, L9_2)
  L6_2 = SolitaryService
  L6_2 = L6_2.SetPrisonerSentence
  L7_2 = L2_2
  L8_2 = L5_2
  L9_2 = _U
  L10_2 = "SOLITARY.DISCORD_LOG_REASON_PRISONER_ATTACKED_GUARD"
  L9_2, L10_2, L11_2 = L9_2(L10_2)
  L6_2(L7_2, L8_2, L9_2, L10_2, L11_2)
end
L0_1(L1_1, L2_1)
