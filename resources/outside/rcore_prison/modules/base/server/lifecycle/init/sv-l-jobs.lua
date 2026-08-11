local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = AddEventHandler
L1_1 = "rcore_prison:shared:internal:MapLoaded"
function L2_1()
  local L0_2, L1_2
  L0_2 = JobService
  L0_2 = L0_2.RegisterInit
  L0_2()
end
L0_1(L1_1, L2_1)
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:requestJob"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2
  if A1_2 then
    L3_2 = JobService
    L3_2 = L3_2.RequestJob
    L4_2 = A0_2
    L5_2 = A2_2
    L3_2(L4_2, L5_2)
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:requestOpenJobMenu"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  if A1_2 then
    L2_2 = PrisonService
    L2_2 = L2_2.getPlayer
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if not L2_2 then
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "Request job menu - player named %s is not prisoner."
      L5_2 = GetPlayerName
      L6_2 = A0_2
      L5_2, L6_2, L7_2 = L5_2(L6_2)
      L3_2(L4_2, L5_2, L6_2, L7_2)
      L3_2 = Framework
      L3_2 = L3_2.sendNotification
      L4_2 = A0_2
      L5_2 = _U
      L6_2 = "GENERAL.YOUT_ARE_NOT_PRISONER"
      L5_2 = L5_2(L6_2)
      L6_2 = "error"
      return L3_2(L4_2, L5_2, L6_2)
    end
    L3_2 = PrisonAccountService
    L3_2 = L3_2.getPlayer
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if L3_2 then
      L4_2 = dbg
      L4_2 = L4_2.debug
      L5_2 = "Request job menu - player named %s is opening job menu."
      L6_2 = GetPlayerName
      L7_2 = A0_2
      L6_2, L7_2 = L6_2(L7_2)
      L4_2(L5_2, L6_2, L7_2)
      L4_2 = StartClient
      L5_2 = A0_2
      L6_2 = "openJobMenu"
      L4_2(L5_2, L6_2)
    else
      L4_2 = dbg
      L4_2 = L4_2.debug
      L5_2 = "Request job menu - player named %s is not having prison account."
      L6_2 = GetPlayerName
      L7_2 = A0_2
      L6_2, L7_2 = L6_2(L7_2)
      L4_2(L5_2, L6_2, L7_2)
      L4_2 = Framework
      L4_2 = L4_2.sendNotification
      L5_2 = A0_2
      L6_2 = _U
      L7_2 = "GENERAL.YOU_DONT_HAVE_PRISONER_ACCOUNT"
      L6_2 = L6_2(L7_2)
      L7_2 = "error"
      L4_2(L5_2, L6_2, L7_2)
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:finishJobTask"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2
  if A1_2 then
    L4_2 = JobService
    L4_2 = L4_2.FinishJobTask
    L5_2 = A0_2
    L6_2 = A2_2
    L7_2 = A3_2
    L4_2(L5_2, L6_2, L7_2)
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:leaveJobTask"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2, A3_2, A4_2)
  local L5_2, L6_2, L7_2, L8_2, L9_2
  if A1_2 then
    L5_2 = JobService
    L5_2 = L5_2.LeaveJobTask
    L6_2 = A0_2
    L7_2 = A2_2
    L8_2 = A3_2
    L9_2 = A4_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
