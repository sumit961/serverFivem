local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "startSit"
function L2_1(A0_2, A1_2, A2_2, A3_2, A4_2)
  local L5_2, L6_2, L7_2, L8_2, L9_2
  if A0_2 then
    L5_2 = HandleInteraction
    L6_2 = A1_2
    L7_2 = A2_2
    L8_2 = A3_2
    L9_2 = A4_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "startExit"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    L2_2 = ExitFunc
    L3_2 = A1_2
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "resetSit"
function L2_1(A0_2, A1_2, A2_2, A3_2, A4_2)
  local L5_2, L6_2, L7_2, L8_2, L9_2
  if A0_2 then
    L5_2 = HandleInteraction
    L6_2 = A1_2
    L7_2 = A2_2
    L8_2 = A3_2
    L9_2 = A4_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "healPlayer"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if A0_2 then
    L2_2 = PlayerPedId
    L2_2 = L2_2()
    L3_2 = GetEntityHealth
    L4_2 = L2_2
    L3_2 = L3_2(L4_2)
    L4_2 = GetEntityArchetypeName
    L5_2 = L2_2
    L4_2 = L4_2(L5_2)
    L5_2 = "mp_m_freemode_01" == L4_2
    L6_2 = "mp_f_freemode_01" == L4_2
    if L5_2 then
      L7_2 = 200
      if L3_2 <= L7_2 then
        L7_2 = SetEntityHealth
        L8_2 = L2_2
        L9_2 = L3_2 + A1_2
        L7_2(L8_2, L9_2)
    end
    elseif L6_2 and L3_2 <= 100 then
      L7_2 = SetEntityHealth
      L8_2 = L2_2
      L9_2 = L3_2 + A1_2
      L7_2(L8_2, L9_2)
    end
    L7_2 = dbg
    L7_2 = L7_2.debug
    L8_2 = "Healing player since laying on bed to amount: from / %s | to / %s"
    L9_2 = A1_2
    L10_2 = L3_2 + A1_2
    L7_2(L8_2, L9_2, L10_2)
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.EventListener
L1_1 = "heartbeat"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if "PRISONER_LOADED" == A0_2 then
    L2_2 = Config
    L2_2 = L2_2.Chairs
    L2_2 = L2_2.Enable
    if not L2_2 then
      return
    end
    L2_2 = HandleRaycastInterval
    L3_2 = "init"
    L2_2(L3_2)
  elseif "PRISONER_RELEASED" == A0_2 then
    L2_2 = HandleRaycastInterval
    L3_2 = "exit"
    L2_2(L3_2)
  end
end
L0_1(L1_1, L2_1)
