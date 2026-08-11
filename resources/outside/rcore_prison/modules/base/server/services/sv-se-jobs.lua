local L0_1, L1_1
L0_1 = {}
JobService = L0_1
L0_1 = JobService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_JOBS
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    L1_2 = dbg
    L1_2 = L1_2.error
    L2_2 = "Job storage not found"
    return L1_2(L2_2)
  end
  L1_2 = SH
  L1_2 = L1_2.data
  if not L1_2 then
    return
  end
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.jobs
  if not L1_2 then
    L1_2 = dbg
    L1_2 = L1_2.critical
    L2_2 = "Failed to load jobs on this map: %s"
    L3_2 = Config
    L3_2 = L3_2.Map
    return L1_2(L2_2, L3_2)
  end
  L1_2 = pairs
  L2_2 = SH
  L2_2 = L2_2.data
  L2_2 = L2_2.jobs
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = L0_2.registerJob
    L8_2 = L6_2
    L7_2 = L7_2(L8_2)
    if L7_2 then
      L8_2 = dbg
      L8_2 = L8_2.debug
      L9_2 = "Job with ID [%s] registered named: %s"
      L10_2 = L5_2
      L11_2 = L6_2.name
      L8_2(L9_2, L10_2, L11_2)
    end
  end
end
L0_1.RegisterInit = L1_1
L0_1 = JobService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_JOBS
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = dbg
    L2_2 = L2_2.error
    L3_2 = "Job storage not found"
    return L2_2(L3_2)
  end
  L2_2 = Framework
  L2_2 = L2_2.getIdentifier
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = L1_2.isPlayerInJob
  L4_2 = L2_2
  L3_2, L4_2 = L3_2(L4_2)
  L5_2 = L3_2
  L6_2 = L4_2
  return L5_2, L6_2
end
L0_1.isPlayerInJob = L1_1
L0_1 = JobService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_JOBS
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = dbg
    L3_2 = L3_2.error
    L4_2 = "Job storage not found"
    return L3_2(L4_2)
  end
  if not A1_2 then
    L3_2 = dbg
    L3_2 = L3_2.error
    L4_2 = "Invalid job ID [%s]"
    L5_2 = A1_2
    L3_2(L4_2, L5_2)
    return
  end
  L3_2 = SH
  L3_2 = L3_2.data
  L3_2 = L3_2.jobs
  L3_2 = L3_2[A1_2]
  if not L3_2 then
    return
  end
  L4_2 = JobService
  L4_2 = L4_2.isPlayerInJob
  L5_2 = A0_2
  L4_2, L5_2 = L4_2(L5_2)
  if L4_2 then
    if L5_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "JOB.IN_ACTIVE_SESSION_COOLDOWN"
      L8_2 = L8_2(L9_2)
      L9_2 = "error"
      return L6_2(L7_2, L8_2, L9_2)
    end
    L6_2 = Framework
    L6_2 = L6_2.sendNotification
    L7_2 = A0_2
    L8_2 = _U
    L9_2 = "JOB.IN_ACTIVE_SESSION_ACTIVE_JOB"
    L8_2 = L8_2(L9_2)
    L9_2 = "error"
    return L6_2(L7_2, L8_2, L9_2)
  end
  L6_2 = L2_2.getJobPool
  L7_2 = L3_2.name
  L6_2 = L6_2(L7_2)
  L7_2 = table
  L7_2 = L7_2.size
  L8_2 = L6_2
  L7_2 = L7_2(L8_2)
  L8_2 = L3_2.type
  L9_2 = L3_2.points
  L9_2 = #L9_2
  L10_2 = L2_2.getRequiredDelivery
  L11_2 = L8_2
  L10_2 = L10_2(L11_2)
  if not L10_2 then
    L10_2 = 0
  end
  L11_2 = L7_2 + 1
  L11_2 = L11_2 * L10_2
  L12_2 = JOBS
  L12_2 = L12_2.COOK
  if L8_2 == L12_2 then
    L12_2 = Config
    L12_2 = L12_2.Map
    if "gabz" == L12_2 then
      L11_2 = 1
    end
  end
  L12_2 = dbg
  L12_2 = L12_2.debug
  L13_2 = "Pool size: %s, Job points: %s, Required delivery: %s | %s"
  L14_2 = L7_2
  L15_2 = L9_2
  L16_2 = L10_2
  L17_2 = L11_2
  L12_2(L13_2, L14_2, L15_2, L16_2, L17_2)
  if L9_2 < L11_2 then
    L12_2 = Framework
    L12_2 = L12_2.sendNotification
    L13_2 = A0_2
    L14_2 = _U
    L15_2 = "JOB.CURRENT_JOB_NOT_FREE_SPACE"
    L14_2 = L14_2(L15_2)
    L15_2 = "error"
    return L12_2(L13_2, L14_2, L15_2)
  else
    L12_2 = L2_2.registerPlayerIntoJob
    L13_2 = A0_2
    L14_2 = A1_2
    L12_2(L13_2, L14_2)
  end
end
L0_1.RequestJob = L1_1
L0_1 = JobService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_JOBS
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    L2_2 = dbg
    L2_2 = L2_2.error
    L3_2 = "Job storage not found"
    return L2_2(L3_2)
  end
  L2_2 = L1_2.unregisterPlayer
  L3_2 = A0_2
  L2_2(L3_2)
end
L0_1.UnregisterPlayer = L1_1
L0_1 = JobService
function L1_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  L3_2 = Object
  L3_2 = L3_2.getStorage
  L4_2 = STORAGE_JOBS
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    L4_2 = dbg
    L4_2 = L4_2.error
    L5_2 = "Job storage not found"
    return L4_2(L5_2)
  end
  if not A1_2 then
    return
  end
  L4_2 = L3_2.finishJobTask
  L5_2 = A0_2
  L6_2 = A1_2
  L7_2 = A2_2
  L4_2(L5_2, L6_2, L7_2)
end
L0_1.FinishJobTask = L1_1
L0_1 = JobService
function L1_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L4_2 = Object
  L4_2 = L4_2.getStorage
  L5_2 = STORAGE_JOBS
  L4_2 = L4_2(L5_2)
  if not L4_2 then
    L5_2 = dbg
    L5_2 = L5_2.error
    L6_2 = "Job storage not found"
    return L5_2(L6_2)
  end
  if not A1_2 then
    return
  end
  L5_2 = L4_2.LeaveJobTask
  L6_2 = A0_2
  L7_2 = A1_2
  L8_2 = A2_2
  L9_2 = A3_2
  L5_2(L6_2, L7_2, L8_2, L9_2)
end
L0_1.LeaveJobTask = L1_1
L0_1 = JobService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L2_2 = Framework
  L2_2 = L2_2.sendNotification
  L3_2 = A0_2
  L4_2 = _U
  L5_2 = "JOB.IN_ACTIVE_SESSION_FINISHED"
  L4_2 = L4_2(L5_2)
  L5_2 = "success"
  L2_2(L3_2, L4_2, L5_2)
  L2_2 = dbg
  L2_2 = L2_2.debug
  L3_2 = "Prison Jobs: Player named %s (%s) finished job get him reward [%s]"
  L4_2 = GetPlayerName
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  L5_2 = A0_2
  L6_2 = A1_2
  L2_2(L3_2, L4_2, L5_2, L6_2)
  L2_2 = Framework
  L2_2 = L2_2.getIdentifier
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = pairs
  L4_2 = Config
  L4_2 = L4_2.PrisonJobs
  L4_2 = L4_2.Rewards
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
  for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
    L9_2 = L8_2.type
    if "ITEM" == L9_2 then
      L9_2 = pcall
      function L10_2()
        local L0_3, L1_3, L2_3
        L0_3 = Inventory
        L0_3 = L0_3.addMultipleItems
        L1_3 = A0_2
        L2_3 = L8_2.list
        return L0_3(L1_3, L2_3)
      end
      L9_2, L10_2 = L9_2(L10_2)
    end
    L9_2 = L8_2.type
    if "CREDITS" == L9_2 then
      L9_2 = math
      L9_2 = L9_2.random
      L10_2 = L8_2.min
      L11_2 = L8_2.max
      L9_2 = L9_2(L10_2, L11_2)
      L10_2 = AccountLogService
      L10_2 = L10_2.RegisterTransaction
      L11_2 = _U
      L12_2 = "JOB.REWARD_LOG_TITLE"
      L11_2 = L11_2(L12_2)
      L12_2 = _U
      L13_2 = "JOB.REWARD_LOG_DESC"
      L14_2 = L9_2
      L12_2 = L12_2(L13_2, L14_2)
      L13_2 = L2_2
      L14_2 = L9_2
      L10_2(L11_2, L12_2, L13_2, L14_2)
      L10_2 = PrisonAccountService
      L10_2 = L10_2.AddCredits
      L11_2 = A0_2
      L12_2 = L9_2
      L13_2 = "PRISON_JOB_REWARD"
      L10_2(L11_2, L12_2, L13_2)
    end
    L9_2 = L8_2.type
    if "REDUCE_SENTENCE" == L9_2 then
      L9_2 = L8_2.value
      if not L9_2 then
        L8_2.value = 5
      end
      L9_2 = JobService
      L9_2 = L9_2.ReduceSentenceTime
      L10_2 = A0_2
      L11_2 = L8_2.value
      L9_2(L10_2, L11_2)
    end
  end
end
L0_1.GetReward = L1_1
L0_1 = JobService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L2_2 = PrisonService
  L2_2 = L2_2.getPlayer
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  if not A1_2 then
    A1_2 = 5
  end
  L3_2 = Framework
  L3_2 = L3_2.getIdentifier
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = L2_2.jail_time
  L5_2 = Time
  L5_2 = L5_2.ConvertTimeFromSeconds
  L6_2 = A1_2
  L7_2 = Config
  L7_2 = L7_2.Time
  L5_2 = L5_2(L6_2, L7_2)
  L6_2 = L4_2 - L5_2
  if L6_2 < 0 then
    L6_2 = 1
  end
  L7_2 = PrisonService
  L7_2 = L7_2.EditSentenceWithConvertedTime
  L8_2 = L3_2
  L9_2 = L6_2
  L10_2 = A0_2
  L7_2(L8_2, L9_2, L10_2)
end
L0_1.ReduceSentenceTime = L1_1
