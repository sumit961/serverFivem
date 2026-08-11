local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = {}
PrisonService = L0_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPrisonerBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  return L2_2
end
L0_1.getPlayer = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPrisonerById
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  return L2_2
end
L0_1.getPlayerById = L1_1
L0_1 = PrisonService
function L1_1()
  local L0_2, L1_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_PRISONER
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = L0_2.GetPrisonersLoadedState
  return L1_2()
end
L0_1.GetPrisonersLoadedState = L1_1
L0_1 = PrisonService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L0_2 = "LOADED_DATA_INTO_CACHE"
  L1_2 = db
  L1_2 = L1_2.FetchPrisoners
  L1_2 = L1_2()
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_PRISONER
  L2_2 = L2_2(L3_2)
  L3_2 = promise
  L3_2 = L3_2.new
  L3_2 = L3_2()
  L4_2 = next
  L5_2 = L1_2
  L4_2 = L4_2(L5_2)
  if L4_2 then
    L4_2 = 1
    L5_2 = #L1_2
    L6_2 = 1
    for L7_2 = L4_2, L5_2, L6_2 do
      L8_2 = L1_2[L7_2]
      L9_2 = L8_2.data
      if L9_2 then
        L9_2 = json
        L9_2 = L9_2.decode
        L10_2 = L8_2.data
        L9_2 = L9_2(L10_2)
        if L9_2 then
          goto lbl_32
        end
      end
      L9_2 = nil
      ::lbl_32::
      if L9_2 then
        L10_2 = PrisonerModel
        L10_2 = L10_2()
        L11_2 = L8_2.prisoner_id
        L10_2.id = L11_2
        L11_2 = L8_2.owner
        L10_2.owner = L11_2
        L11_2 = L9_2.jail_time
        L10_2.jail_time = L11_2
        L11_2 = L9_2.jail_reason
        L10_2.jail_reason = L11_2
        L11_2 = L9_2.officerName
        L10_2.officerName = L11_2
        L11_2 = L9_2.prisonerName
        L10_2.prisonerName = L11_2
        L11_2 = L9_2.state
        L10_2.state = L11_2
        L11_2 = L9_2.perollDone
        L10_2.perollDone = L11_2
        L11_2 = L9_2.solitary_time
        L10_2.solitary_time = L11_2
        L11_2 = L9_2.solitary_cell
        L10_2.solitary_cell = L11_2
        L11_2 = L2_2.AddPlayer
        L12_2 = L10_2
        L11_2(L12_2)
      end
      L10_2 = #L1_2
      if L7_2 >= L10_2 then
        L11_2 = L3_2
        L10_2 = L3_2.resolve
        L12_2 = true
        L10_2(L11_2, L12_2)
      end
    end
  else
    L0_2 = "NOT_ANY_PRISONERS_IN_DB"
    L5_2 = L3_2
    L4_2 = L3_2.resolve
    L6_2 = true
    L4_2(L5_2, L6_2)
  end
  L4_2 = Citizen
  L4_2 = L4_2.Await
  L5_2 = L3_2
  L4_2(L5_2)
  if L0_2 then
    L4_2 = dbg
    L4_2 = L4_2.debug
    L5_2 = "Prisoner data into cache state: %s"
    L6_2 = L0_2
    L4_2(L5_2, L6_2)
  end
  L4_2 = Wait
  L5_2 = 0
  L4_2(L5_2)
  L4_2 = PrisonService
  L4_2.isDBReady = true
  L4_2 = L2_2.CheckOnlinePlayers
  L4_2()
end
L0_1.loadAllPrisoners = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPrisonerBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "PrisonService - Check for any sentence: Player named %s with playerId: %s has inactive sentence"
    L5_2 = GetPlayerName
    L6_2 = A0_2
    L5_2 = L5_2(L6_2)
    L6_2 = A0_2
    L3_2(L4_2, L5_2, L6_2)
    L3_2 = false
    return L3_2
  end
  L3_2 = L2_2.jail_time
  if L3_2 > 0 then
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "PrisonService - Check for any sentence: Player named %s with playerId: %s has active sentence: %s"
    L5_2 = GetPlayerName
    L6_2 = A0_2
    L5_2 = L5_2(L6_2)
    L6_2 = A0_2
    L7_2 = L2_2.jail_time
    L3_2(L4_2, L5_2, L6_2, L7_2)
    L3_2 = true
    return L3_2
  end
  L3_2 = false
  return L3_2
end
L0_1.CheckForAnySentence = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPrisonerBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  L3_2 = L1_2.SavePrisoner
  L4_2 = A0_2
  L3_2(L4_2)
end
L0_1.SaveUser = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = nil
    return L2_2
  end
  L2_2 = L1_2.GetAllPrisoners
  L3_2 = A0_2
  return L2_2(L3_2)
end
L0_1.GetAllPrisoners = L1_1
L0_1 = PrisonService
function L1_1(A0_2, ...)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = TriggerEvent
  L2_2 = "rcore_prison:server:heartbeat"
  L3_2 = A0_2
  L4_2 = ...
  L1_2(L2_2, L3_2, L4_2)
end
L0_1.SendHeartbeat = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_PRISONER
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  L3_2 = L2_2.HandlePrisonerTeleport
  L4_2 = A0_2
  L5_2 = A1_2
  return L3_2(L4_2, L5_2)
end
L0_1.HandlePrisonerLocation = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L4_2 = A0_2
  if not L4_2 then
    L5_2 = false
    return L5_2
  end
  L5_2 = GetPlayerPed
  L6_2 = L4_2
  L5_2 = L5_2(L6_2)
  if L5_2 < 0 then
    L5_2 = false
    return L5_2
  end
  if not A1_2 then
    A1_2 = 60
  end
  if not A2_2 then
    A2_2 = "No reason provided"
  end
  L5_2 = nil
  if A3_2 then
    L5_2 = A3_2
  end
  L6_2 = PrisonService
  L6_2 = L6_2.JailCitizen
  L7_2 = L5_2
  L8_2 = L4_2
  L9_2 = A1_2
  L10_2 = A2_2
  L6_2(L7_2, L8_2, L9_2, L10_2)
end
L0_1.Jail = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  L3_2 = A0_2
  if not L3_2 then
    L4_2 = false
    return L4_2
  end
  L4_2 = GetPlayerPed
  L5_2 = L3_2
  L4_2 = L4_2(L5_2)
  if L4_2 < 0 then
    L4_2 = false
    return L4_2
  end
  if nil == A1_2 then
    A1_2 = true
  end
  if not A2_2 then
    A2_2 = false
  end
  L4_2 = PrisonService
  L4_2 = L4_2.UnjailCitizen
  L5_2 = L3_2
  L6_2 = A1_2
  L7_2 = A2_2
  L4_2(L5_2, L6_2, L7_2)
end
L0_1.Unjail = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  L4_2 = Object
  L4_2 = L4_2.getStorage
  L5_2 = STORAGE_PRISONER
  L4_2 = L4_2(L5_2)
  L5_2 = L4_2.GetPrisonerBySource
  L6_2 = A1_2
  L5_2 = L5_2(L6_2)
  if L5_2 then
    L6_2 = Framework
    L6_2 = L6_2.sendNotification
    L7_2 = A0_2
    L8_2 = _U
    L9_2 = "GENERAL.CITIZEN_ALREADY_JAILED"
    L8_2 = L8_2(L9_2)
    L9_2 = "error"
    L6_2(L7_2, L8_2, L9_2)
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "Player named: %s is already jailed"
    L8_2 = GetPlayerName
    L9_2 = A1_2
    L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2 = L8_2(L9_2)
    L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
    L6_2 = false
    return L6_2
  end
  L6_2 = Inventory
  L6_2 = L6_2.HandleOpenState
  L7_2 = A1_2
  L8_2 = true
  L6_2(L7_2, L8_2)
  L6_2 = Time
  L6_2 = L6_2.ConvertTimeFromSeconds
  L7_2 = A2_2
  L8_2 = Config
  L8_2 = L8_2.Time
  L6_2 = L6_2(L7_2, L8_2)
  A2_2 = L6_2
  L6_2 = PrisonerModel
  L6_2 = L6_2()
  L7_2 = Framework
  L7_2 = L7_2.getIdentifier
  L8_2 = A1_2
  L7_2 = L7_2(L8_2)
  L6_2.jail_time = A2_2
  L6_2.jail_reason = A3_2
  L6_2.state = "jailed"
  if A0_2 then
    L8_2 = Framework
    L8_2 = L8_2.getCharacterName
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    L6_2.officerName = L8_2
  else
    L6_2.officerName = "-"
  end
  L8_2 = Framework
  L8_2 = L8_2.getCharacterName
  L9_2 = A1_2
  L8_2 = L8_2(L9_2)
  L6_2.prisonerName = L8_2
  L8_2 = db
  L8_2 = L8_2.DefinePrisonerData
  L9_2 = L7_2
  L10_2 = {}
  L10_2.prisonerData = L6_2
  L8_2 = L8_2(L9_2, L10_2)
  if not L8_2 then
    L9_2 = dbg
    L9_2 = L9_2.critical
    L10_2 = "Cannot create prisoner %s %s - db insert PrisonService.JailCitizen"
    L11_2 = L6_2.charId
    L12_2 = L6_2.prisonerName
    L9_2(L10_2, L11_2, L12_2)
    return
  end
  L6_2.id = L8_2
  L6_2.source = A1_2
  L6_2.owner = L7_2
  L9_2 = db
  L9_2 = L9_2.DefinePrisonerJailTime
  L10_2 = L6_2.id
  L11_2 = L6_2.jail_time
  L9_2(L10_2, L11_2)
  L9_2 = L4_2.AddPlayer
  L10_2 = L6_2
  L9_2 = L9_2(L10_2)
  if L9_2 then
    L10_2 = LogService
    L10_2 = L10_2.RegisterTransaction
    L11_2 = "CITIZEN_JAILED"
    L12_2 = _U
    L13_2 = "LOGS_ACTIONS.LOG_CITIZEN_JAILED_BY_OFFICER"
    L14_2 = L6_2.prisonerName
    L15_2 = L6_2.officerName
    L12_2 = L12_2(L13_2, L14_2, L15_2)
    L13_2 = L7_2
    L14_2 = L6_2.prisonerName
    L15_2 = L6_2.prisonerName
    L10_2(L11_2, L12_2, L13_2, L14_2, L15_2)
    L10_2 = L4_2.LoadPrisoner
    L11_2 = A1_2
    L12_2 = HEARTBEAT_EVENTS
    L12_2 = L12_2.PRISONER_NEW
    L10_2(L11_2, L12_2)
  end
end
L0_1.JailCitizen = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  if not A0_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = Framework
  L2_2 = L2_2.getIdentifier
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if A1_2 <= 0 then
    L3_2 = Framework
    L3_2 = L3_2.sendNotification
    L4_2 = L2_2
    L5_2 = _U
    L6_2 = "GENERAl.AMOUNT_CANNOT_BE_LESS_THAN_0"
    L5_2 = L5_2(L6_2)
    L6_2 = "error"
    L3_2(L4_2, L5_2, L6_2)
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "Edit sentence service: Amount cannot be less than 0 initiated for charId (%s) by %s (%s)"
    L5_2 = L2_2
    L6_2 = GetPlayerName
    L7_2 = A0_2
    L6_2 = L6_2(L7_2)
    L7_2 = A0_2
    return L3_2(L4_2, L5_2, L6_2, L7_2)
  end
  L3_2 = Time
  L3_2 = L3_2.ConvertTimeFromSeconds
  L4_2 = A1_2
  L5_2 = Config
  L5_2 = L5_2.Time
  L3_2 = L3_2(L4_2, L5_2)
  if L3_2 then
    L4_2 = Object
    L4_2 = L4_2.getStorage
    L5_2 = STORAGE_PRISONER
    L4_2 = L4_2(L5_2)
    L5_2 = L4_2.GetPrisonerById
    L6_2 = L2_2
    L5_2 = L5_2(L6_2)
    if not L5_2 then
      return
    end
    L6_2 = L4_2.UpdatePlayerSentence
    L7_2 = L2_2
    L8_2 = L3_2
    L6_2(L7_2, L8_2)
  end
end
L0_1.EditSentenceBySource = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  if A1_2 <= 0 then
    L3_2 = Framework
    L3_2 = L3_2.sendNotification
    L4_2 = A0_2
    L5_2 = _U
    L6_2 = "GENERAl.AMOUNT_CANNOT_BE_LESS_THAN_0"
    L5_2 = L5_2(L6_2)
    L6_2 = "error"
    L3_2(L4_2, L5_2, L6_2)
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "Edit sentence service: Amount cannot be less than 0 initiated for charId (%s) by %s (%s)"
    L5_2 = A0_2
    L6_2 = GetPlayerName
    L7_2 = A2_2
    L6_2 = L6_2(L7_2)
    L7_2 = A2_2
    return L3_2(L4_2, L5_2, L6_2, L7_2)
  end
  L3_2 = A1_2
  if L3_2 then
    L4_2 = Object
    L4_2 = L4_2.getStorage
    L5_2 = STORAGE_PRISONER
    L4_2 = L4_2(L5_2)
    L5_2 = L4_2.GetPrisonerById
    L6_2 = A0_2
    L5_2 = L5_2(L6_2)
    if not L5_2 then
      return
    end
    L6_2 = L4_2.UpdatePlayerSentence
    L7_2 = A0_2
    L8_2 = L3_2
    L6_2(L7_2, L8_2)
  end
end
L0_1.EditSentenceWithConvertedTime = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  if A1_2 <= 0 then
    L3_2 = Framework
    L3_2 = L3_2.sendNotification
    L4_2 = A0_2
    L5_2 = _U
    L6_2 = "GENERAl.AMOUNT_CANNOT_BE_LESS_THAN_0"
    L5_2 = L5_2(L6_2)
    L6_2 = "error"
    L3_2(L4_2, L5_2, L6_2)
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "Edit sentence service: Amount cannot be less than 0 initiated for charId (%s) by %s (%s)"
    L5_2 = A0_2
    L6_2 = GetPlayerName
    L7_2 = A2_2
    L6_2 = L6_2(L7_2)
    L7_2 = A2_2
    return L3_2(L4_2, L5_2, L6_2, L7_2)
  end
  L3_2 = Time
  L3_2 = L3_2.ConvertTimeFromSeconds
  L4_2 = A1_2
  L5_2 = Config
  L5_2 = L5_2.Time
  L3_2 = L3_2(L4_2, L5_2)
  if L3_2 then
    L4_2 = Object
    L4_2 = L4_2.getStorage
    L5_2 = STORAGE_PRISONER
    L4_2 = L4_2(L5_2)
    L5_2 = L4_2.GetPrisonerById
    L6_2 = A0_2
    L5_2 = L5_2(L6_2)
    if not L5_2 then
      return
    end
    L6_2 = L4_2.UpdatePlayerSentence
    L7_2 = A0_2
    L8_2 = L3_2
    L6_2(L7_2, L8_2)
  end
end
L0_1.EditSentence = L1_1
L0_1 = PrisonService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L3_2 = Object
  L3_2 = L3_2.getStorage
  L4_2 = STORAGE_PRISONER
  L3_2 = L3_2(L4_2)
  L4_2 = L3_2.GetPrisonerBySource
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    L5_2 = dbg
    L5_2 = L5_2.debug
    L6_2 = "Player named: %s is not jailed!"
    L7_2 = GetPlayerName
    L8_2 = A0_2
    L7_2, L8_2 = L7_2(L8_2)
    L5_2(L6_2, L7_2, L8_2)
    L5_2 = false
    return L5_2
  end
  L5_2 = L3_2.ReleasePrisoner
  L6_2 = A0_2
  L7_2 = A1_2
  L8_2 = A2_2
  L5_2(L6_2, L7_2, L8_2)
end
L0_1.UnjailCitizen = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = L1_2.ReleasePrisonerOffline
  L3_2 = A0_2
  return L2_2(L3_2)
end
L0_1.UnjailOfflineCitizen = L1_1
L0_1 = PrisonService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_PRISONER
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPrisonerBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  L3_2 = L1_2.LoadPrisoner
  L4_2 = A0_2
  L3_2(L4_2)
end
L0_1.LoadPrisoner = L1_1
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:requestRelease"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if A1_2 then
    L2_2 = Object
    L2_2 = L2_2.getStorage
    L3_2 = STORAGE_PRISONER
    L2_2 = L2_2(L3_2)
    L3_2 = L2_2.GetPrisonerBySource
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      L4_2 = false
      L5_2 = "PRISONER_NOT_FOUND"
      return L4_2, L5_2
    end
    L4_2 = tonumber
    L5_2 = L3_2.jail_time
    L4_2 = L4_2(L5_2)
    L5_2 = dbg
    L5_2 = L5_2.debug
    L6_2 = "Release player: Checking player %s with jailTime: %s to be released out."
    L7_2 = GetPlayerName
    L8_2 = A0_2
    L7_2 = L7_2(L8_2)
    L8_2 = L4_2
    L5_2(L6_2, L7_2, L8_2)
    if L4_2 > 10 then
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "Failed to release player %s with jailTime: %s"
      L7_2 = GetPlayerName
      L8_2 = A0_2
      L7_2 = L7_2(L8_2)
      L8_2 = L4_2
      L5_2(L6_2, L7_2, L8_2)
      L5_2 = Framework
      L5_2 = L5_2.sendNotification
      L6_2 = A0_2
      L7_2 = _U
      L8_2 = "CANNOT_BE_RELEASED"
      L9_2 = Time
      L9_2 = L9_2.DynamicSecondsToClock
      L10_2 = L3_2.jail_time
      L9_2, L10_2 = L9_2(L10_2)
      L7_2 = L7_2(L8_2, L9_2, L10_2)
      L8_2 = "error"
      return L5_2(L6_2, L7_2, L8_2)
    end
    L5_2 = Config
    L5_2 = L5_2.CanPrisonerBeReleasedWhenOnSolitary
    if not L5_2 then
      L5_2 = L3_2.solitary_cell
      if L5_2 then
        L5_2 = SolitaryService
        L5_2 = L5_2.CanBeAutoReleased
        L6_2 = A0_2
        L5_2 = L5_2(L6_2)
        if not L5_2 then
          L5_2 = dbg
          L5_2 = L5_2.debug
          L6_2 = "Failed to release player %s with jailTime: %s since being in solitary cell!"
          L7_2 = GetPlayerName
          L8_2 = A0_2
          L7_2 = L7_2(L8_2)
          L8_2 = L4_2
          L5_2(L6_2, L7_2, L8_2)
          L5_2 = Framework
          L5_2 = L5_2.sendNotification
          L6_2 = A0_2
          L7_2 = _U
          L8_2 = "CANNOT_BE_RELEASED_SINCE_HAVING_SOLITARY"
          L7_2 = L7_2(L8_2)
          L8_2 = "error"
          return L5_2(L6_2, L7_2, L8_2)
        end
      end
    end
    L5_2 = dbg
    L5_2 = L5_2.debug
    L6_2 = "Player named: %s was automatically released his time is up"
    L7_2 = GetPlayerName
    L8_2 = A0_2
    L7_2, L8_2, L9_2, L10_2 = L7_2(L8_2)
    L5_2(L6_2, L7_2, L8_2, L9_2, L10_2)
    L5_2 = L2_2.ReleasePrisoner
    L6_2 = A0_2
    L7_2 = true
    L5_2(L6_2, L7_2)
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
L0_1 = Object
L0_1 = L0_1.registerService
L1_1 = SERVICE_PRISONER
L2_1 = PrisonService
L0_1(L1_1, L2_1)
