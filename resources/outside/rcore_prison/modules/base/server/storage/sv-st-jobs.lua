local L0_1, L1_1, L2_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = {}
  L1_2 = {}
  L0_2._sessions = L1_2
  L1_2 = RegisterCommand
  L2_2 = "prisonSessions"
  function L3_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3
    if 0 == A0_3 then
      L3_3 = tprint
      L4_3 = L0_2._sessions
      L3_3(L4_3)
    end
  end
  L4_2 = false
  L1_2(L2_2, L3_2, L4_2)
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3
    L1_3 = L0_2._sessions
    L2_3 = A0_3.name
    L1_3 = L1_3[L2_3]
    if not L1_3 then
      L1_3 = L0_2._sessions
      L2_3 = A0_3.name
      L3_3 = {}
      L4_3 = {}
      L3_3.pastJobs = L4_3
      L4_3 = {}
      L3_3.players = L4_3
      L1_3[L2_3] = L3_3
    end
    L1_3 = true
    return L1_3
  end
  L0_2.registerJob = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3
    L1_3 = Framework
    L1_3 = L1_3.getIdentifier
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L2_3 = L0_2._sessions
      if L2_3 then
        L2_3 = next
        L3_3 = L0_2._sessions
        L2_3 = L2_3(L3_3)
        if L2_3 then
          L2_3 = pairs
          L3_3 = L0_2._sessions
          L2_3, L3_3, L4_3, L5_3 = L2_3(L3_3)
          for L6_3, L7_3 in L2_3, L3_3, L4_3, L5_3 do
            L8_3 = L7_3.players
            L8_3 = L8_3[L1_3]
            if L8_3 then
              L8_3 = L7_3.players
              L8_3[L1_3] = nil
              L8_3 = dbg
              L8_3 = L8_3.debug
              L9_3 = "Unregistering player from job since left game!"
              L8_3(L9_3)
            end
          end
        end
      end
    end
  end
  L0_2.unregisterPlayer = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3
    L2_3 = 10
    while L2_3 > 0 do
      L3_3 = math
      L3_3 = L3_3.random
      L4_3 = 1
      L5_3 = A1_3.points
      L5_3 = #L5_3
      L3_3 = L3_3(L4_3, L5_3)
      L4_3 = L0_2._sessions
      L4_3 = L4_3[A0_3]
      L4_3 = L4_3.pastJobs
      L5_3 = tostring
      L6_3 = L3_3
      L5_3 = L5_3(L6_3)
      L4_3 = L4_3[L5_3]
      if not L4_3 then
        L4_3 = L0_2._sessions
        L4_3 = L4_3[A0_3]
        L4_3 = L4_3.pastJobs
        L5_3 = tostring
        L6_3 = L3_3
        L5_3 = L5_3(L6_3)
        L4_3[L5_3] = true
        return L3_3
      end
      L2_3 = L2_3 - 1
    end
    L3_3 = math
    L3_3 = L3_3.random
    L4_3 = 1
    L5_3 = A1_3.points
    L5_3 = #L5_3
    return L3_3(L4_3, L5_3)
  end
  L0_2.GetRandomPlaceIdx = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3
    L1_3 = false
    L2_3 = false
    L3_3 = pairs
    L4_3 = L0_2._sessions
    L3_3, L4_3, L5_3, L6_3 = L3_3(L4_3)
    for L7_3, L8_3 in L3_3, L4_3, L5_3, L6_3 do
      L9_3 = L8_3.players
      L9_3 = L9_3[A0_3]
      if L9_3 then
        L1_3 = true
        L9_3 = L8_3.players
        L9_3 = L9_3[A0_3]
        L2_3 = L9_3.cooldown
      end
    end
    L3_3 = L1_3
    L4_3 = L2_3
    return L3_3, L4_3
  end
  L0_2.isPlayerInJob = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3
    L2_3 = L0_2._sessions
    L2_3 = L2_3[A0_3]
    L2_3 = L2_3.players
    L2_3 = L2_3[A1_3]
    return L2_3
  end
  L0_2.getPlayerSession = L1_2
  function L1_2(A0_3)
    local L1_3
    L1_3 = L0_2._sessions
    L1_3 = L1_3[A0_3]
    L1_3 = L1_3.pastJobs
    return L1_3
  end
  L0_2.getJobPool = L1_2
  function L1_2(A0_3)
    local L1_3, L2_3
    L1_3 = Config
    L1_3 = L1_3.PrisonJobs
    L1_3 = L1_3.RequiredDelivery
    if not L1_3 then
      L1_3 = 1
    end
    L2_3 = Config
    L2_3 = L2_3.PrisonJobs
    L2_3 = L2_3.SetCustomRequiredDeliveries
    if L2_3 then
      L2_3 = Config
      L2_3 = L2_3.PrisonJobs
      L2_3 = L2_3.RequiredDeliveries
      L2_3 = L2_3[A0_3]
      if L2_3 then
        L2_3 = Config
        L2_3 = L2_3.PrisonJobs
        L2_3 = L2_3.RequiredDeliveries
        L1_3 = L2_3[A0_3]
      end
    end
    return L1_3
  end
  L0_2.getRequiredDelivery = L1_2
  function L1_2(A0_3, A1_3, A2_3, A3_3)
    local L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3
    if not A1_3 then
      return
    end
    L4_3 = SH
    L4_3 = L4_3.data
    L4_3 = L4_3.jobs
    L4_3 = L4_3[A1_3]
    if not L4_3 then
      return
    end
    L5_3 = L4_3.name
    L6_3 = L0_2._sessions
    L6_3 = L6_3[L5_3]
    if not L6_3 then
      return
    end
    L6_3 = Framework
    L6_3 = L6_3.getIdentifier
    L7_3 = A0_3
    L6_3 = L6_3(L7_3)
    L7_3 = L0_2.getPlayerSession
    L8_3 = L5_3
    L9_3 = L6_3
    L7_3 = L7_3(L8_3, L9_3)
    if L7_3 then
      L8_3 = L7_3.locationIdx
      if L8_3 ~= A2_3 then
        L8_3 = dbg
        L8_3 = L8_3.debug
        L9_3 = "Invalid location index"
        return L8_3(L9_3)
      end
      L8_3 = L0_2._sessions
      L8_3 = L8_3[L5_3]
      L8_3 = L8_3.pastJobs
      L9_3 = tostring
      L10_3 = A2_3
      L9_3 = L9_3(L10_3)
      L8_3 = L8_3[L9_3]
      if L8_3 then
        L8_3 = L0_2._sessions
        L8_3 = L8_3[L5_3]
        L8_3 = L8_3.pastJobs
        L9_3 = tostring
        L10_3 = A2_3
        L9_3 = L9_3(L10_3)
        L8_3[L9_3] = nil
      end
      L7_3.cooldown = true
      L8_3 = SetTimeout
      L9_3 = Config
      L9_3 = L9_3.PrisonJobs
      L9_3 = L9_3.PlayerJobCoolDown
      L9_3 = L9_3 * 60
      L9_3 = L9_3 * 1000
      function L10_3()
        local L0_4, L1_4, L2_4, L3_4, L4_4
        L0_4 = dbg
        L0_4 = L0_4.debug
        L1_4 = "Resetting job session for this player >> %s %s"
        L2_4 = L6_3
        L3_4 = GetPlayerName
        L4_4 = A0_3
        L3_4, L4_4 = L3_4(L4_4)
        L0_4(L1_4, L2_4, L3_4, L4_4)
        L0_4 = L0_2._sessions
        L1_4 = L5_3
        L0_4 = L0_4[L1_4]
        L0_4 = L0_4.players
        L1_4 = L6_3
        L0_4 = L0_4[L1_4]
        if L0_4 then
          L0_4 = L0_2._sessions
          L1_4 = L5_3
          L0_4 = L0_4[L1_4]
          L0_4 = L0_4.players
          L1_4 = L6_3
          L0_4[L1_4] = nil
        end
      end
      L8_3(L9_3, L10_3)
      if A3_3 then
        L8_3 = "MINIGAME_STATES.%s"
        L9_3 = L8_3
        L8_3 = L8_3.format
        L11_3 = A3_3
        L10_3 = A3_3.upper
        L10_3, L11_3, L12_3, L13_3, L14_3 = L10_3(L11_3)
        L8_3 = L8_3(L9_3, L10_3, L11_3, L12_3, L13_3, L14_3)
        L9_3 = _U
        L10_3 = L8_3
        L9_3 = L9_3(L10_3)
        L10_3 = dbg
        L10_3 = L10_3.debug
        L11_3 = "Player %s left the job session with reason: %s"
        L12_3 = GetPlayerName
        L13_3 = A0_3
        L12_3 = L12_3(L13_3)
        L13_3 = L9_3
        L10_3(L11_3, L12_3, L13_3)
        L10_3 = Framework
        L10_3 = L10_3.sendNotification
        L11_3 = A0_3
        L12_3 = _U
        L13_3 = "JOB.IN_ACTIVE_SESSION_LEFT_REASON"
        L14_3 = L9_3
        L12_3 = L12_3(L13_3, L14_3)
        L13_3 = "error"
        return L10_3(L11_3, L12_3, L13_3)
      end
      L8_3 = Framework
      L8_3 = L8_3.sendNotification
      L9_3 = A0_3
      L10_3 = _U
      L11_3 = "JOB.IN_ACTIVE_SESSION_LEFT"
      L10_3 = L10_3(L11_3)
      L11_3 = "error"
      L8_3(L9_3, L10_3, L11_3)
    end
  end
  L0_2.LeaveJobTask = L1_2
  function L1_2(A0_3, A1_3)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3
    if not A1_3 then
      return
    end
    L2_3 = SH
    L2_3 = L2_3.data
    L2_3 = L2_3.jobs
    L2_3 = L2_3[A1_3]
    if not L2_3 then
      return
    end
    L3_3 = L2_3.name
    L4_3 = L2_3.type
    L5_3 = L0_2._sessions
    L5_3 = L5_3[L3_3]
    if not L5_3 then
      return
    end
    L5_3 = Framework
    L5_3 = L5_3.getIdentifier
    L6_3 = A0_3
    L5_3 = L5_3(L6_3)
    L6_3 = L0_2.GetRandomPlaceIdx
    L7_3 = L3_3
    L8_3 = L2_3
    L6_3 = L6_3(L7_3, L8_3)
    L7_3 = L0_2._sessions
    L7_3 = L7_3[L3_3]
    L7_3 = L7_3.players
    L8_3 = {}
    L8_3.playerId = A0_3
    L8_3.jobId = A1_3
    L8_3.locationIdx = L6_3
    L8_3.delivered = 0
    L7_3[L5_3] = L8_3
    L7_3 = Config
    L7_3 = L7_3.PrisonJobs
    L7_3 = L7_3.Electrician
    L7_3 = L7_3.EachJobLevelIncreaseDifficulty
    if L7_3 then
      L7_3 = JOBS
      L7_3 = L7_3.ELECTRICIAN
      if L4_3 == L7_3 then
        L7_3 = L0_2._sessions
        L7_3 = L7_3[L3_3]
        L7_3 = L7_3.players
        L7_3 = L7_3[L5_3]
        L8_3 = {}
        L9_3 = Config
        L9_3 = L9_3.Circuit
        L9_3 = L9_3.Difficulty
        L8_3.difficulty = L9_3
        L7_3.extra = L8_3
      end
    end
    L7_3 = L2_3.points
    L7_3 = L7_3[L6_3]
    if L7_3 then
      L8_3 = L7_3.pos
      if L8_3 then
        L9_3 = StartClient
        L10_3 = A0_3
        L11_3 = "SetWaypoint"
        L12_3 = L8_3
        L9_3(L10_3, L11_3, L12_3)
      end
    end
    L8_3 = StartClient
    L9_3 = A0_3
    L10_3 = "startJob"
    L11_3 = A1_3
    L12_3 = L6_3
    L8_3(L9_3, L10_3, L11_3, L12_3)
  end
  L0_2.registerPlayerIntoJob = L1_2
  function L1_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3
    if not A1_3 then
      return
    end
    L3_3 = SH
    L3_3 = L3_3.data
    L3_3 = L3_3.jobs
    L3_3 = L3_3[A1_3]
    if not L3_3 then
      return
    end
    L4_3 = L3_3.name
    L5_3 = Framework
    L5_3 = L5_3.getIdentifier
    L6_3 = A0_3
    L5_3 = L5_3(L6_3)
    L6_3 = L0_2.getPlayerSession
    L7_3 = L4_3
    L8_3 = L5_3
    L6_3 = L6_3(L7_3, L8_3)
    L7_3 = L3_3.type
    if L6_3 then
      L8_3 = L6_3.locationIdx
      if L8_3 ~= A2_3 then
        L8_3 = dbg
        L8_3 = L8_3.debug
        L9_3 = "Invalid location index"
        return L8_3(L9_3)
      end
      L8_3 = L6_3.delivered
      L8_3 = L8_3 + 1
      L6_3.delivered = L8_3
      L8_3 = Config
      L8_3 = L8_3.PrisonJobs
      L8_3 = L8_3.Electrician
      L8_3 = L8_3.EachJobLevelIncreaseDifficulty
      if L8_3 then
        L8_3 = JOBS
        L8_3 = L8_3.ELECTRICIAN
        if L7_3 == L8_3 then
          L8_3 = L6_3.extra
          if not L8_3 then
            return
          end
          L8_3 = L6_3.extra
          L8_3 = L8_3.difficulty
          if L8_3 <= 6 then
            L8_3 = L6_3.extra
            L9_3 = L6_3.extra
            L9_3 = L9_3.difficulty
            L9_3 = L9_3 + 1
            L8_3.difficulty = L9_3
          else
            L8_3 = L6_3.extra
            L8_3.difficulty = 1
          end
        end
      end
      L8_3 = L6_3.delivered
      L9_3 = L0_2.getRequiredDelivery
      L10_3 = L7_3
      L9_3 = L9_3(L10_3)
      if L8_3 >= L9_3 then
        L8_3 = SetTimeout
        L9_3 = Config
        L9_3 = L9_3.PrisonJobs
        L9_3 = L9_3.ResetJobPoolCooldown
        L9_3 = L9_3 * 60
        L9_3 = L9_3 * 1000
        function L10_3()
          local L0_4, L1_4, L2_4, L3_4
          L0_4 = dbg
          L0_4 = L0_4.debug
          L1_4 = "Resetting job pool for this job >> %s with IDX: %s"
          L2_4 = L4_3
          L3_4 = A2_3
          L0_4(L1_4, L2_4, L3_4)
          L0_4 = L0_2._sessions
          L1_4 = L4_3
          L0_4 = L0_4[L1_4]
          L0_4 = L0_4.pastJobs
          L1_4 = tostring
          L2_4 = A2_3
          L1_4 = L1_4(L2_4)
          L0_4[L1_4] = nil
        end
        L8_3(L9_3, L10_3)
        L8_3 = SetTimeout
        L9_3 = Config
        L9_3 = L9_3.PrisonJobs
        L9_3 = L9_3.PlayerJobCoolDown
        L9_3 = L9_3 * 60
        L9_3 = L9_3 * 1000
        function L10_3()
          local L0_4, L1_4, L2_4, L3_4, L4_4
          L0_4 = dbg
          L0_4 = L0_4.debug
          L1_4 = "Resetting job session for this player >> %s %s"
          L2_4 = L5_3
          L3_4 = GetPlayerName
          L4_4 = A0_3
          L3_4, L4_4 = L3_4(L4_4)
          L0_4(L1_4, L2_4, L3_4, L4_4)
          L0_4 = L0_2._sessions
          L1_4 = L4_3
          L0_4 = L0_4[L1_4]
          L0_4 = L0_4.players
          L1_4 = L5_3
          L0_4 = L0_4[L1_4]
          if L0_4 then
            L0_4 = L0_2._sessions
            L1_4 = L4_3
            L0_4 = L0_4[L1_4]
            L0_4 = L0_4.players
            L1_4 = L5_3
            L0_4[L1_4] = nil
          end
        end
        L8_3(L9_3, L10_3)
        L6_3.cooldown = true
        L8_3 = JobService
        L8_3 = L8_3.GetReward
        L9_3 = A0_3
        L10_3 = A1_3
        L8_3(L9_3, L10_3)
      else
        L8_3 = SetTimeout
        L9_3 = Config
        L9_3 = L9_3.PrisonJobs
        L9_3 = L9_3.ResetJobPoolCooldown
        L9_3 = L9_3 * 60
        L9_3 = L9_3 * 1000
        function L10_3()
          local L0_4, L1_4, L2_4, L3_4
          L0_4 = dbg
          L0_4 = L0_4.debug
          L1_4 = "Resetting job pool for this job >> %s with IDX: %s"
          L2_4 = L4_3
          L3_4 = A2_3
          L0_4(L1_4, L2_4, L3_4)
          L0_4 = L0_2._sessions
          L1_4 = L4_3
          L0_4 = L0_4[L1_4]
          L0_4 = L0_4.pastJobs
          L1_4 = tostring
          L2_4 = A2_3
          L1_4 = L1_4(L2_4)
          L0_4[L1_4] = nil
        end
        L8_3(L9_3, L10_3)
        L8_3 = L0_2.GetRandomPlaceIdx
        L9_3 = L4_3
        L10_3 = L3_3
        L8_3 = L8_3(L9_3, L10_3)
        L6_3.locationIdx = L8_3
        L9_3 = Framework
        L9_3 = L9_3.sendNotification
        L10_3 = A0_3
        L11_3 = _U
        L12_3 = "JOB.IN_ACTIVE_SESSION_DELIVERED"
        L13_3 = L6_3.delivered
        L14_3 = L0_2.getRequiredDelivery
        L15_3 = L4_3
        L14_3, L15_3 = L14_3(L15_3)
        L11_3 = L11_3(L12_3, L13_3, L14_3, L15_3)
        L12_3 = "success"
        L9_3(L10_3, L11_3, L12_3)
        L9_3 = L3_3.points
        L9_3 = L9_3[L8_3]
        if L9_3 then
          L10_3 = L9_3.pos
          if L10_3 then
            L11_3 = StartClient
            L12_3 = A0_3
            L13_3 = "SetWaypoint"
            L14_3 = L10_3
            L11_3(L12_3, L13_3, L14_3)
          end
        end
        L10_3 = StartClient
        L11_3 = A0_3
        L12_3 = "startJob"
        L13_3 = A1_3
        L14_3 = L8_3
        L15_3 = L6_3.extra
        L10_3(L11_3, L12_3, L13_3, L14_3, L15_3)
      end
    end
  end
  L0_2.finishJobTask = L1_2
  return L0_2
end
JobStorage = L0_1
L0_1 = Object
L0_1 = L0_1.registerStorage
L1_1 = STORAGE_JOBS
L2_1 = JobStorage
L2_1 = L2_1()
L0_1(L1_1, L2_1)
