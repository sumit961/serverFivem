local L0_1, L1_1
L0_1 = {}
COMSService = L0_1
L0_1 = COMSService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_COMS
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPlayerBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  return L2_2
end
L0_1.getPlayer = L1_1
L0_1 = COMSService
function L1_1(A0_2)
  local L1_2, L2_2
  L1_2 = COMSService
  L1_2 = L1_2.getPlayer
  L2_2 = A0_2
  return L1_2(L2_2)
end
L0_1.CheckForAnySentence = L1_1
L0_1 = COMSService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_COMS
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPlayerById
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  return L2_2
end
L0_1.GetPlayerById = L1_1
L0_1 = COMSService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_COMS
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = false
    return L3_2
  end
  if A1_2 then
    L3_2 = Framework
    L3_2 = L3_2.getIdentifier
    L4_2 = A1_2
    L3_2 = L3_2(L4_2)
    L4_2 = Framework
    L4_2 = L4_2.getCharacterName
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    L5_2 = Framework
    L5_2 = L5_2.getCharacterName
    L6_2 = A1_2
    L5_2 = L5_2(L6_2)
    L6_2 = _U
    L7_2 = "LOGS_ACTIONS.LOG_CITIZEN_CITIZEN_RELEASED_BY_OFFICER_FROM_PAROLLE"
    L8_2 = L5_2
    L9_2 = L4_2
    L6_2 = L6_2(L7_2, L8_2, L9_2)
    L7_2 = LogService
    L7_2 = L7_2.RegisterTransaction
    L8_2 = "RELEASE_PLAYER"
    L9_2 = L6_2
    L10_2 = L3_2
    L11_2 = L4_2
    L12_2 = L5_2
    L7_2(L8_2, L9_2, L10_2, L11_2, L12_2)
  end
  L3_2 = COMSService
  L3_2 = L3_2.getPlayer
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  if L3_2 then
    L4_2 = L3_2.zoneIdx
    if L4_2 then
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "Found active COMS for player (%s) - clearing area with zoneId: %s!"
      L7_2 = GetPlayerName
      L8_2 = A0_2
      L7_2 = L7_2(L8_2)
      L8_2 = L4_2
      L5_2(L6_2, L7_2, L8_2)
      L5_2 = StartClient
      L6_2 = A0_2
      L7_2 = "UnregisterCOMSArea"
      L8_2 = A0_2
      L9_2 = L4_2
      L5_2(L6_2, L7_2, L8_2, L9_2)
    end
    L5_2 = StartClient
    L6_2 = A0_2
    L7_2 = "RemoveBlipByType"
    L8_2 = "COMS"
    L5_2(L6_2, L7_2, L8_2)
  end
  L4_2 = L2_2.ReleaseUser
  L5_2 = A0_2
  L4_2(L5_2)
end
L0_1.ReleaseUser = L1_1
L0_1 = COMSService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_COMS
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPlayerBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  L3_2 = L1_2.SaveUser
  L4_2 = A0_2
  L3_2(L4_2)
end
L0_1.SaveUser = L1_1
L0_1 = COMSService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_COMS
  L1_2 = L1_2(L2_2)
  L2_2 = L1_2.GetPlayerBySource
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = nil
    return L3_2
  end
  L3_2 = L1_2.loadPeroll
  L4_2 = A0_2
  L3_2(L4_2)
end
L0_1.LoadPeroll = L1_1
L0_1 = COMSService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L3_2 = Object
  L3_2 = L3_2.getStorage
  L4_2 = STORAGE_COMS
  L3_2 = L3_2(L4_2)
  L4_2 = L3_2.GetPlayerBySource
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    L5_2 = nil
    return L5_2
  end
  L5_2 = L3_2.UpdatePlayerKeyByValue
  L6_2 = A0_2
  L7_2 = A1_2
  L8_2 = A2_2
  return L5_2(L6_2, L7_2, L8_2)
end
L0_1.UpdatePlayerKeyByValue = L1_1
L0_1 = COMSService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_COMS
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = nil
    return L2_2
  end
  L2_2 = L1_2.GetAllCOMS
  L3_2 = A0_2
  return L2_2(L3_2)
end
L0_1.GetAllCOMS = L1_1
L0_1 = COMSService
function L1_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2
  L4_2 = Object
  L4_2 = L4_2.getStorage
  L5_2 = STORAGE_COMS
  L4_2 = L4_2(L5_2)
  L5_2 = L4_2.GetPlayerBySource
  L6_2 = A1_2
  L5_2 = L5_2(L6_2)
  if L5_2 then
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "Player already has a peroll"
    L8_2 = GetPlayerName
    L9_2 = A1_2
    L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2 = L8_2(L9_2)
    L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
    if A0_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "GENERAL.ACTIVE_PAROLLE"
      L8_2 = L8_2(L9_2)
      L9_2 = "error"
      L6_2(L7_2, L8_2, L9_2)
    end
    L6_2 = false
    return L6_2
  end
  L6_2 = GetPlayerPed
  L7_2 = A1_2
  L6_2 = L6_2(L7_2)
  if L6_2 <= 0 then
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "Player is not online"
    L8_2 = GetPlayerName
    L9_2 = A1_2
    L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2 = L8_2(L9_2)
    L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
    if A0_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "GENERAL.TARGET_PLAYER_NOT_FOUND"
      L8_2 = L8_2(L9_2)
      L9_2 = "error"
      L6_2(L7_2, L8_2, L9_2)
    end
    L6_2 = false
    return L6_2
  end
  L6_2 = COMSPlayerModel
  L6_2 = L6_2()
  L7_2 = Framework
  L7_2 = L7_2.getIdentifier
  L8_2 = A1_2
  L7_2 = L7_2(L8_2)
  L6_2.charId = L7_2
  L6_2.perollAmount = 0
  L6_2.perollTarget = A2_2
  L6_2.reason = A3_2
  L7_2 = Framework
  L7_2 = L7_2.getCharacterName
  L8_2 = A1_2
  L7_2 = L7_2(L8_2)
  L6_2.name = L7_2
  L7_2 = db
  L7_2 = L7_2.CreateCitizenPeroll
  L8_2 = L6_2.charId
  L9_2 = L6_2.state
  L10_2 = L6_2.perollTarget
  L11_2 = L6_2.name
  L7_2 = L7_2(L8_2, L9_2, L10_2, L11_2)
  if not L7_2 then
    L8_2 = dbg
    L8_2 = L8_2.critical
    L9_2 = "Cannot create peroll %s %s - db insert COMSService.StartPerollForCitizen"
    L10_2 = L6_2.charId
    L11_2 = L6_2.prisonerName
    L8_2(L9_2, L10_2, L11_2)
    return
  end
  L8_2 = "-"
  if A0_2 then
    L9_2 = Framework
    L9_2 = L9_2.getCharacterName
    L10_2 = A0_2
    L9_2 = L9_2(L10_2)
    L8_2 = L9_2
  end
  L9_2 = Framework
  L9_2 = L9_2.getIdentifier
  L10_2 = A1_2
  L9_2 = L9_2(L10_2)
  L10_2 = Framework
  L10_2 = L10_2.getCharacterName
  L11_2 = A1_2
  L10_2 = L10_2(L11_2)
  L11_2 = _U
  L12_2 = "LOGS_ACTIONS.LOG_CITIZEN_PAROLLED_BY_OFFICER"
  L13_2 = L10_2
  L14_2 = L8_2
  L15_2 = A2_2
  L11_2 = L11_2(L12_2, L13_2, L14_2, L15_2)
  L12_2 = LogService
  L12_2 = L12_2.RegisterTransaction
  L13_2 = "CITIZEN_PAROLLED"
  L14_2 = L11_2
  L15_2 = L9_2
  L16_2 = L8_2
  L17_2 = L10_2
  L12_2(L13_2, L14_2, L15_2, L16_2, L17_2)
  L6_2.id = L7_2
  L12_2 = L6_2.id
  if L12_2 then
    L12_2 = L4_2.addPlayer
    L13_2 = L6_2
    L12_2 = L12_2(L13_2)
    L13_2 = Config
    L13_2 = L13_2.COMS
    L13_2 = L13_2.StartLocations
    if L13_2 then
      L14_2 = L13_2.coords
      if L14_2 then
        L15_2 = StartClient
        L16_2 = A1_2
        L17_2 = "SetWaypoint"
        L18_2 = L14_2
        L15_2(L16_2, L17_2, L18_2)
      end
    end
    if L12_2 then
      L14_2 = L4_2.loadPeroll
      L15_2 = A1_2
      L14_2(L15_2)
      if A0_2 then
        L14_2 = Framework
        L14_2 = L14_2.sendNotification
        L15_2 = A1_2
        L16_2 = _U
        L17_2 = "GENERAL.YOU_HAVE_BEEN_SENT_TO_COMS_BY"
        L18_2 = L8_2
        L16_2, L17_2, L18_2 = L16_2(L17_2, L18_2)
        L14_2(L15_2, L16_2, L17_2, L18_2)
      end
    end
  end
  return L6_2
end
L0_1.StartPerollForCitizen = L1_1
L0_1 = COMSService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L0_2 = "LOADED_DATA_INTO_CACHE"
  L1_2 = db
  L1_2 = L1_2.FetchCOMSUsers
  L1_2 = L1_2()
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_COMS
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
      if L8_2 then
        L9_2 = COMSPlayerModel
        L9_2 = L9_2()
        L10_2 = L8_2.id
        L9_2.id = L10_2
        L10_2 = L8_2.owner
        L9_2.charId = L10_2
        L10_2 = L8_2.perollAmount
        L9_2.perollAmount = L10_2
        L10_2 = L8_2.perollTarget
        L9_2.perollTarget = L10_2
        L10_2 = L8_2.reason
        L9_2.reason = L10_2
        L10_2 = L8_2.state
        L9_2.state = L10_2
        L10_2 = L8_2.zoneId
        if not L10_2 then
          L10_2 = "NONE"
        end
        L9_2.zoneId = L10_2
        L10_2 = L8_2.name
        L9_2.name = L10_2
        L10_2 = L2_2.addPlayer
        L11_2 = L9_2
        L10_2(L11_2)
      end
      L9_2 = #L1_2
      if L7_2 >= L9_2 then
        L10_2 = L3_2
        L9_2 = L3_2.resolve
        L11_2 = true
        L9_2(L10_2, L11_2)
      end
      L9_2 = Wait
      L10_2 = 0
      L9_2(L10_2)
    end
  else
    L0_2 = "NOT_ANY_COMS_USERS_IN_DB"
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
    L5_2 = "COMS data into cache state: %s"
    L6_2 = L0_2
    L4_2(L5_2, L6_2)
  end
end
L0_1.loadAllUsers = L1_1
