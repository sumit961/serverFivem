local L0_1, L1_1, L2_1, L3_1
L0_1 = RegisterCommand
L1_1 = "rcore_prison_player_loaded"
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2
  if 0 == A0_2 then
    L3_2 = PlayerLoadedPool
    if L3_2 then
      L3_2 = next
      L4_2 = PlayerLoadedPool
      L3_2 = L3_2(L4_2)
      if L3_2 then
        L3_2 = tprint
        L4_2 = PlayerLoadedPool
        L3_2(L4_2)
    end
    else
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "Debug player loaded: Failed to find any registered players!"
      L3_2(L4_2)
    end
  end
end
L3_1 = false
L0_1(L1_1, L2_1, L3_1)
L0_1 = AddEventHandler
L1_1 = "rcore_prison:server:playerLoaded"
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = ChatService
  L1_2 = L1_2.RegisterAllSuggestions
  L2_2 = A0_2
  L1_2(L2_2)
  L1_2 = Framework
  L1_2 = L1_2.getIdentifier
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = PlayerLoadedPool
  L3_2 = {}
  L3_2.playerId = A0_2
  L3_2.state = true
  L3_2.identifier = L1_2
  L4_2 = Framework
  L4_2 = L4_2.getCharacterName
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  L3_2.name = L4_2
  L2_2[A0_2] = L3_2
  L2_2 = GlobalState
  L3_2 = PlayerLoadedPool
  L2_2.rcore_prison_servers_players = L3_2
  L2_2 = PrisonService
  L2_2 = L2_2.CheckForAnySentence
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Player load: Has sentence player %s with serverId %s with identifier: %s"
    L4_2 = GetPlayerName
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    L5_2 = A0_2
    L6_2 = L1_2
    L2_2(L3_2, L4_2, L5_2, L6_2)
    L2_2 = PrisonService
    L2_2 = L2_2.LoadPrisoner
    L3_2 = A0_2
    L2_2(L3_2)
  else
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Player load: Failed to find any sentence for player %s with serverId %s with identifier: %s"
    L4_2 = GetPlayerName
    L5_2 = A0_2
    L4_2 = L4_2(L5_2)
    L5_2 = A0_2
    L6_2 = L1_2
    L2_2(L3_2, L4_2, L5_2, L6_2)
    L2_2 = Config
    L2_2 = L2_2.Debug
    if L2_2 then
      L2_2 = PrisonService
      L2_2 = L2_2.GetAllPrisoners
      L3_2 = false
      L2_2 = L2_2(L3_2)
      if L2_2 then
        L3_2 = next
        L4_2 = L2_2
        L3_2 = L3_2(L4_2)
        if L3_2 then
          L3_2 = tprint
          L4_2 = L2_2
          L3_2(L4_2)
        end
      end
    end
  end
  L2_2 = COMSService
  L2_2 = L2_2.CheckForAnySentence
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L2_2 = SetTimeout
    L3_2 = 1000
    function L4_2()
      local L0_3, L1_3
      L0_3 = COMSService
      L0_3 = L0_3.LoadPeroll
      L1_3 = A0_2
      L0_3(L1_3)
    end
    L2_2(L3_2, L4_2)
  end
  L2_2 = PrisonAccountService
  L2_2 = L2_2.LoadAccount
  L3_2 = A0_2
  L2_2(L3_2)
  L2_2 = SyncPrisonBreak
  L3_2 = A0_2
  L4_2 = false
  L2_2(L3_2, L4_2)
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.EventListener
L1_1 = "heartbeat"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = HEARTBEAT_EVENTS
  L2_2 = L2_2.PRISONER_NEW
  if A0_2 ~= L2_2 then
    return
  end
  L2_2 = next
  L3_2 = A1_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  L2_2 = A1_2.prisoner
  if not L2_2 then
    return
  end
  L3_2 = Config
  L3_2 = L3_2.Accounts
  L3_2 = L3_2.Enable
  if not L3_2 then
    return
  end
  L3_2 = PrisonAccountService
  L3_2 = L3_2.LoadAccount
  L4_2 = L2_2.source
  L3_2(L4_2)
end
L0_1(L1_1, L2_1)
L0_1 = AddEventHandler
L1_1 = "rcore_prison:server:playerUnloaded"
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = dbg
  L1_2 = L1_2.debug
  L2_2 = "UNLOAD-PLAYER: Player with ID (%s) named %s saving his time, unloading."
  L3_2 = A0_2
  L4_2 = GetPlayerName
  L5_2 = A0_2
  L4_2, L5_2 = L4_2(L5_2)
  L1_2(L2_2, L3_2, L4_2, L5_2)
  L1_2 = JobService
  L1_2 = L1_2.isPlayerInJob
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if L1_2 then
    L2_2 = JobService
    L2_2 = L2_2.UnregisterPlayer
    L3_2 = A0_2
    L2_2(L3_2)
  end
  L2_2 = PrisonService
  L2_2 = L2_2.SaveUser
  L3_2 = A0_2
  L2_2(L3_2)
  L2_2 = COMSService
  L2_2 = L2_2.SaveUser
  L3_2 = A0_2
  L2_2(L3_2)
  L2_2 = StopAlarmServer
  L3_2 = A0_2
  L2_2(L3_2)
  L2_2 = RemoveNearPlayers
  L3_2 = A0_2
  L2_2(L3_2)
  L2_2 = PlayerLoadedPool
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L2_2 = PlayerLoadedPool
    L2_2[A0_2] = nil
  end
  L2_2 = RegisterNetworkFlow
  L3_2 = tostring
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L2_2 = L2_2[L3_2]
  if L2_2 then
    L2_2 = RegisterNetworkFlow
    L3_2 = tostring
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    L2_2[L3_2] = nil
  end
  L2_2 = GlobalState
  L3_2 = PlayerLoadedPool
  L2_2.rcore_prison_servers_players = L3_2
end
L0_1(L1_1, L2_1)
L0_1 = AddEventHandler
L1_1 = "onResourceStop"
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = GetCurrentResourceName
  L1_2 = L1_2()
  if A0_2 == L1_2 then
    L1_2 = pairs
    L2_2 = GetPlayers
    L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2 = L2_2()
    L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2)
    for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
      L7_2 = L6_2
      if L7_2 then
        L8_2 = PrisonService
        L8_2 = L8_2.SaveUser
        L9_2 = L7_2
        L8_2(L9_2)
      end
    end
  end
end
L0_1(L1_1, L2_1)
L0_1 = AddEventHandler
L1_1 = "txAdmin:events:scheduledRestart"
function L2_1(A0_2)
  local L1_2, L2_2
  L1_2 = A0_2.secondsRemaining
  if 60 == L1_2 then
    L1_2 = CreateThread
    function L2_2()
      local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3
      L0_3 = Wait
      L1_3 = 45000
      L0_3(L1_3)
      L0_3 = pairs
      L1_3 = GetPlayers
      L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3 = L1_3()
      L0_3, L1_3, L2_3, L3_3 = L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3)
      for L4_3, L5_3 in L0_3, L1_3, L2_3, L3_3 do
        L6_3 = L5_3
        if L6_3 then
          L7_3 = PrisonService
          L7_3 = L7_3.SaveUser
          L8_3 = L6_3
          L7_3(L8_3)
        end
      end
      L0_3 = PrisonAccountService
      L0_3 = L0_3.saveAllAccounts
      L0_3()
    end
    L1_2(L2_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = callback
L0_1 = L0_1.register
L1_1 = "rcore_prison:server:getAllPrisoners"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L2_2 = Framework
  L2_2 = L2_2.canPerformJobCommand
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L2_2 = {}
    return L2_2
  end
  L2_2 = PrisonService
  L2_2 = L2_2.GetAllPrisoners
  L3_2 = false
  L2_2 = L2_2(L3_2)
  L3_2 = table
  L3_2 = L3_2.size
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = {}
  L5_2 = pairs
  L6_2 = L2_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = table
    L11_2 = L11_2.insert
    L12_2 = L4_2
    L13_2 = L10_2
    L11_2(L12_2, L13_2)
  end
  L5_2 = {}
  L6_2 = 4 == L3_2 or L6_2
  L5_2.hasMore = L6_2
  L5_2.prisoners = L4_2
  return L5_2
end
L0_1(L1_1, L2_1)
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L0_2 = Config
  L0_2 = L0_2.Escape
  L0_2 = L0_2.DisableBugEscape
  if not L0_2 then
    return
  end
  while true do
    L0_2 = Wait
    L1_2 = 0
    L0_2(L1_2)
    L0_2 = PrisonService
    L0_2 = L0_2.GetAllPrisoners
    L1_2 = true
    L0_2 = L0_2(L1_2)
    L1_2 = next
    L2_2 = L0_2
    L1_2 = L1_2(L2_2)
    if not L1_2 then
    else
      L1_2 = pairs
      L2_2 = L0_2
      L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
      for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
        L7_2 = L6_2.source
        if L7_2 then
          L8_2 = PrisonService
          L8_2 = L8_2.HandlePrisonerLocation
          L9_2 = L7_2
          L8_2(L9_2)
        end
      end
    end
    L1_2 = Wait
    L2_2 = Config
    L2_2 = L2_2.Escape
    L2_2 = L2_2.BugEscapeCycleTime
    L2_2 = L2_2 * 60
    L2_2 = L2_2 * 1000
    L1_2(L2_2)
  end
end
L0_1(L1_1)
