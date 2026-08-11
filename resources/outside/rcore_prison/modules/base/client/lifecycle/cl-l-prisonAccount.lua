local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1
L0_1 = {}
L1_1 = false
L2_1 = promise
L2_1 = L2_1.new
L2_1 = L2_1()
L3_1 = NetworkService
L3_1 = L3_1.RegisterNetEvent
L4_1 = "UpdatePrisonerAccount"
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = FrontendService
  L2_2 = L2_2.AwaitFrontend
  L2_2()
  if A0_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Prisoner account data received: %s"
    L4_2 = json
    L4_2 = L4_2.encode
    L5_2 = A1_2
    L4_2, L5_2 = L4_2(L5_2)
    L2_2(L3_2, L4_2, L5_2)
    L2_2 = L1_1
    if L2_2 then
      L0_1 = A1_2
      L2_2 = L2_1
      L3_2 = L2_2
      L2_2 = L2_2.resolve
      L4_2 = true
      L2_2(L3_2, L4_2)
    end
    L2_2 = FrontendService
    L2_2 = L2_2.SendReactMessage
    L3_2 = "syncPrisonerAccount"
    L4_2 = A1_2
    L2_2(L3_2, L4_2)
  end
end
L3_1(L4_1, L5_1)
L3_1 = NetworkService
L3_1 = L3_1.EventListener
L4_1 = "heartbeat"
function L5_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = A0_2
  L3_2 = HEARTBEAT_EVENTS
  L3_2 = L3_2.PRISONER_RELEASED
  if L2_2 ~= L3_2 then
    return
  end
  L3_2 = Config
  L3_2 = L3_2.Accounts
  L3_2 = L3_2.DeleteAccountWhenReleased
  if L3_2 then
    L3_2 = PrisonerAccountService
    L3_2 = L3_2.Reset
    L3_2()
  end
end
L3_1(L4_1, L5_1)
L3_1 = RegisterNuiCallback
L4_1 = NUI_CALLBACKS
L4_1 = L4_1.REGISTER_PRISONER_ACCOUNT
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = true
  L1_1 = L2_2
  if A0_2 then
    L2_2 = TriggerServerEvent
    L3_2 = "rcore_prison:server:registerPrisonerAccount"
    L4_2 = SH
    L4_2 = L4_2.zoneId
    L2_2(L3_2, L4_2)
  end
  L2_2 = Citizen
  L2_2 = L2_2.Await
  L3_2 = L2_1
  L2_2(L3_2)
  L2_2 = SetTimeout
  L3_2 = 250
  function L4_2()
    local L0_3, L1_3, L2_3
    L0_3 = L1_1
    if L0_3 then
      L0_3 = false
      L1_1 = L0_3
      L0_3 = {}
      L0_1 = L0_3
      L0_3 = FrontendService
      L0_3 = L0_3.HandleFocus
      L1_3 = true
      L0_3(L1_3)
      L0_3 = FrontendService
      L0_3 = L0_3.SendReactMessage
      L1_3 = FE_EVENTS
      L1_3 = L1_3.LOAD_APP
      L2_3 = {}
      L2_3.screen = "ACCOUNT"
      L2_3.visible = true
      L0_3(L1_3, L2_3)
    end
  end
  L2_2(L3_2, L4_2)
  L2_2 = A1_2
  L3_2 = L0_1
  L2_2(L3_2)
end
L3_1(L4_1, L5_1)
L3_1 = RegisterNuiCallback
L4_1 = NUI_CALLBACKS
L4_1 = L4_1.EXECUTE_PRISONER_ACCOUNT
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  if A0_2 then
    L2_2 = TriggerServerEvent
    L3_2 = "rcore_prison:server:executePrisonerAccountTask"
    L4_2 = SH
    L4_2 = L4_2.zoneId
    L5_2 = A0_2
    L2_2(L3_2, L4_2, L5_2)
  end
  L2_2 = A1_2
  L3_2 = "OK"
  L2_2(L3_2)
end
L3_1(L4_1, L5_1)
L3_1 = RegisterNuiCallback
L4_1 = NUI_CALLBACKS
L4_1 = L4_1.GET_PRISON_LOGS
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = callback
  L2_2 = L2_2.await
  L3_2 = "rcore_prison:server:getAllTransactions"
  L4_2 = false
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = A1_2
  L4_2 = L2_2
  L3_2(L4_2)
end
L3_1(L4_1, L5_1)
L3_1 = RegisterNuiCallback
L4_1 = NUI_CALLBACKS
L4_1 = L4_1.GET_PRISONER_ACCOUNT_LOGS
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = callback
  L2_2 = L2_2.await
  L3_2 = "rcore_prison:server:getPrisonerAccountLogs"
  L4_2 = false
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = A1_2
  L4_2 = L2_2
  L3_2(L4_2)
end
L3_1(L4_1, L5_1)
