local L0_1, L1_1, L2_1, L3_1
L0_1 = {}
EventLimiterService = L0_1
L0_1 = {}
L1_1 = {}
L2_1 = EventLimiterService
function L3_1(A0_2, A1_2, A2_2, A3_2, ...)
  local L4_2, L5_2, L6_2
  L4_2 = RegisterNetEvent
  L5_2 = A0_2
  function L6_2(...)
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3
    L0_3 = source
    if nil ~= L0_3 then
      L0_3 = source
      if 0 ~= L0_3 then
        L0_3 = InitVariables
        L1_3 = {}
        L2_3 = A0_2
        L1_3.eventName = L2_3
        L2_3 = A2_2
        if not L2_3 then
          L2_3 = 1
        end
        L1_3.limit = L2_3
        L2_3 = A1_2
        if not L2_3 then
          L2_3 = 1000
        end
        L1_3.inTimeSpan = L2_3
        L2_3 = source
        L1_3.source = L2_3
        L0_3(L1_3)
        L1_3 = source
        L0_3 = L0_1
        L0_3 = L0_3[L1_3]
        L1_3 = A0_2
        L0_3 = L0_3[L1_3]
        L1_3 = A2_2
        if L0_3 <= L1_3 then
          L1_3 = source
          L0_3 = L1_1
          L0_3 = L0_3[L1_3]
          L1_3 = A0_2
          L0_3 = L0_3[L1_3]
          L1_3 = GetGameTimer
          L1_3 = L1_3()
          if L0_3 <= L1_3 then
            L0_3 = RegisterNetworkFlow
            L1_3 = tostring
            L2_3 = source
  [0.208s][warning][os,thread] Failed to start thread "Unknown thread" - pthread_create failed (EAGAIN) for attributes: stacksize: 1024k, guardsize: 4k, detached.
          L1_3 = L1_3(L2_3)
            L0_3 = L0_3[L1_3]
  [0.208s][warning][os,thread] Failed to start thread "Unknown thread" - pthread_create failed (EAGAIN) for attributes: stacksize: 1024k, guardsize: 4k, detached.
          if not L0_3 then
              L0_3 = RegisterNetworkFlow
              L1_3 = tostring
              L2_3 = source
              L1_3 = L1_3(L2_3)
              L2_3 = {}
              L3_3 = {}
              L2_3.session = L3_3
              L0_3[L1_3] = L2_3
              L0_3 = table
              L0_3 = L0_3.insert
              L1_3 = RegisterNetworkFlow
              L2_3 = tostring
              L3_3 = source
              L2_3 = L2_3(L3_3)
              L1_3 = L1_3[L2_3]
              L1_3 = L1_3.session
              L2_3 = {}
              L3_3 = GetPlayerName
              L4_3 = source
              L3_3 = L3_3(L4_3)
              L2_3.player_name = L3_3
              L3_3 = source
              L2_3.player_id = L3_3
              L3_3 = A0_2
              L2_3.eventName = L3_3
              L3_3 = os
              L3_3 = L3_3.time
              L3_3 = L3_3()
              L2_3.time = L3_3
              L0_3(L1_3, L2_3)
              L0_3 = RegisterNetworkFlow
              L1_3 = tostring
              L2_3 = source
              L1_3 = L1_3(L2_3)
              L0_3 = L0_3[L1_3]
              L1_3 = A0_2
              L0_3[L1_3] = true
            else
              L0_3 = table
              L0_3 = L0_3.insert
              L1_3 = RegisterNetworkFlow
              L2_3 = tostring
              L3_3 = source
              L2_3 = L2_3(L3_3)
              L1_3 = L1_3[L2_3]
              L1_3 = L1_3.session
              L2_3 = {}
              L3_3 = GetPlayerName
              L4_3 = source
              L3_3 = L3_3(L4_3)
              L2_3.player_name = L3_3
              L3_3 = source
              L2_3.player_id = L3_3
              L3_3 = A0_2
              L2_3.eventName = L3_3
              L3_3 = os
              L3_3 = L3_3.time
              L3_3 = L3_3()
              L2_3.time = L3_3
              L0_3(L1_3, L2_3)
              L0_3 = RegisterNetworkFlow
              L1_3 = tostring
              L2_3 = source
              L1_3 = L1_3(L2_3)
              L0_3 = L0_3[L1_3]
              L1_3 = A0_2
              L0_3[L1_3] = true
            end
            L0_3 = dbg
            L0_3 = L0_3.debugNetwork
            L1_3 = "Event %s has been triggered by user with playerId %s named: %s"
            L2_3 = A0_2
            L3_3 = source
            L4_3 = GetPlayerName
            L5_3 = source
            L4_3, L5_3 = L4_3(L5_3)
            L0_3(L1_3, L2_3, L3_3, L4_3, L5_3)
            L0_3 = InitVariables
            L1_3 = {}
            L2_3 = A0_2
            L1_3.eventName = L2_3
            L2_3 = A2_2
            if not L2_3 then
              L2_3 = 1
            end
            L1_3.limit = L2_3
            L2_3 = A1_2
            if not L2_3 then
              L2_3 = 1000
            end
            L1_3.inTimeSpan = L2_3
            L2_3 = source
            L1_3.source = L2_3
            L2_3 = true
            L0_3(L1_3, L2_3)
            L0_3 = A3_2
            L1_3 = source
            L2_3 = true
            L3_3, L4_3, L5_3 = ...
            L0_3(L1_3, L2_3, L3_3, L4_3, L5_3)
          else
            L0_3 = RegisterNetworkFlow
            L1_3 = tostring
            L2_3 = source
            L1_3 = L1_3(L2_3)
            L0_3 = L0_3[L1_3]
            if not L0_3 then
              L0_3 = RegisterNetworkFlow
              L1_3 = tostring
              L2_3 = source
              L1_3 = L1_3(L2_3)
              L2_3 = {}
              L3_3 = {}
              L2_3.session = L3_3
              L0_3[L1_3] = L2_3
              L0_3 = table
              L0_3 = L0_3.insert
              L1_3 = RegisterNetworkFlow
              L2_3 = tostring
              L3_3 = source
              L2_3 = L2_3(L3_3)
              L1_3 = L1_3[L2_3]
              L1_3 = L1_3.session
              L2_3 = {}
              L3_3 = GetPlayerName
              L4_3 = source
              L3_3 = L3_3(L4_3)
              L2_3.player_name = L3_3
              L3_3 = source
              L2_3.player_id = L3_3
              L3_3 = A0_2
              L2_3.eventName = L3_3
              L3_3 = os
              L3_3 = L3_3.time
              L3_3 = L3_3()
              L2_3.time = L3_3
              L0_3(L1_3, L2_3)
              L0_3 = RegisterNetworkFlow
              L1_3 = tostring
              L2_3 = source
              L1_3 = L1_3(L2_3)
              L0_3 = L0_3[L1_3]
              L1_3 = A0_2
              L0_3[L1_3] = true
            else
              L0_3 = table
              L0_3 = L0_3.insert
              L1_3 = RegisterNetworkFlow
              L2_3 = tostring
              L3_3 = source
              L2_3 = L2_3(L3_3)
              L1_3 = L1_3[L2_3]
              L1_3 = L1_3.session
              L2_3 = {}
              L3_3 = GetPlayerName
              L4_3 = source
              L3_3 = L3_3(L4_3)
              L2_3.player_name = L3_3
              L3_3 = source
              L2_3.player_id = L3_3
              L3_3 = A0_2
              L2_3.eventName = L3_3
              L3_3 = os
              L3_3 = L3_3.time
              L3_3 = L3_3()
              L2_3.time = L3_3
              L0_3(L1_3, L2_3)
              L0_3 = RegisterNetworkFlow
              L1_3 = tostring
              L2_3 = source
              L1_3 = L1_3(L2_3)
              L0_3 = L0_3[L1_3]
              L1_3 = A0_2
              L0_3[L1_3] = true
            end
            L0_3 = InitVariables
            L1_3 = {}
            L2_3 = A0_2
            L1_3.eventName = L2_3
            L2_3 = A2_2
            if not L2_3 then
              L2_3 = 1
            end
            L1_3.limit = L2_3
            L2_3 = A1_2
            if not L2_3 then
              L2_3 = 1000
            end
            L1_3.inTimeSpan = L2_3
            L2_3 = source
            L1_3.source = L2_3
            L2_3 = true
            L0_3(L1_3, L2_3)
            L0_3 = A3_2
            L1_3 = source
            L2_3 = false
            L3_3, L4_3, L5_3 = ...
            L0_3(L1_3, L2_3, L3_3, L4_3, L5_3)
          end
        end
      end
    end
  end
  L4_2(L5_2, L6_2)
end
L2_1.RegisterNetEvent = L3_1
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L3_2 = A0_2.source
  L2_2 = L0_1
  L2_2 = L2_2[L3_2]
  if not L2_2 or A1_2 then
    L3_2 = A0_2.source
    L2_2 = L0_1
    L4_2 = {}
    L2_2[L3_2] = L4_2
    L3_2 = A0_2.source
    L2_2 = L1_1
    L4_2 = {}
    L2_2[L3_2] = L4_2
  end
  L3_2 = A0_2.source
  L2_2 = L0_1
  L2_2 = L2_2[L3_2]
  L3_2 = A0_2.eventName
  L2_2 = L2_2[L3_2]
  if not L2_2 or A1_2 then
    L3_2 = A0_2.source
    L2_2 = L0_1
    L2_2 = L2_2[L3_2]
    L3_2 = A0_2.eventName
    L2_2[L3_2] = 0
    L3_2 = A0_2.source
    L2_2 = L1_1
    L2_2 = L2_2[L3_2]
    L3_2 = A0_2.eventName
    L4_2 = GetGameTimer
    L4_2 = L4_2()
    L5_2 = A0_2.inTimeSpan
    L4_2 = L4_2 + L5_2
    L2_2[L3_2] = L4_2
  end
end
InitVariables = L2_1
