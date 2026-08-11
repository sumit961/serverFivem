local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1
L0_1 = false
L1_1 = "prison"
L2_1 = {}
L3_1 = {}
L3_1.name = "Fresh Meat"
L3_1.desc = "Get sent to prison for the first time."
L3_1.threshold = 1
L4_1 = {}
L4_1.name = "Brooks was here"
L4_1.desc = "Get sent to prison 5 times."
L4_1.threshold = 5
L5_1 = {}
L5_1.name = "So was Red"
L5_1.desc = "Get sent to prison 10 times."
L5_1.threshold = 10
L6_1 = {}
L6_1.name = "Get busy living, or get busy dying"
L6_1.desc = "Get sent to prison 20 times."
L6_1.threshold = 20
L2_1[1] = L3_1
L2_1[2] = L4_1
L2_1[3] = L5_1
L2_1[4] = L6_1
function L3_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = L0_1
  if not L0_2 then
    L0_2 = true
    L0_1 = L0_2
    L0_2 = TriggerEvent
    L1_2 = "rcore_stats:api:ensureCategory"
    L2_2 = L1_1
    L3_2 = "Prison"
    function L4_2()
      local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3
      L0_3 = TriggerEvent
      L1_3 = "rcore_stats:api:ensureStatType"
      L2_3 = "prison_recurring_citizen"
      L3_3 = "Prison - times imprisoned"
      L4_3 = "player"
      L5_3 = nil
      L6_3 = L1_1
      L7_3 = true
      L8_3 = nil
      function L9_3()
        local L0_4, L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4, L13_4, L14_4
        L0_4 = TriggerEvent
        L1_4 = "rcore_stats:api:ensureStatType"
        L2_4 = "total_prison_recurring_citizen"
        L3_4 = "Prison - Total imprisonments"
        L4_4 = "server"
        L5_4 = nil
        L6_4 = L1_1
        L7_4 = true
        L8_4 = "prison_recurring_citizen"
        L0_4(L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4)
        L0_4 = L2_1
        if L0_4 then
          L0_4 = 1
          L1_4 = L2_1
          L1_4 = #L1_4
          L2_4 = 1
          for L3_4 = L0_4, L1_4, L2_4 do
            L4_4 = L2_1
            L4_4 = L4_4[L3_4]
            L5_4 = "prison_recurring_citizen_"
            L6_4 = L3_4
            L5_4 = L5_4 .. L6_4
            L6_4 = "prison_recurring_citizen"
            if L4_4 then
              L7_4 = TriggerEvent
              L8_4 = "rcore_stats:api:ensureAchievement"
              L9_4 = L5_4
              L10_4 = L4_4.name
              L11_4 = L4_4.desc
              L12_4 = "columns-4"
              L13_4 = L6_4
              L14_4 = L4_4.threshold
              L7_4(L8_4, L9_4, L10_4, L11_4, L12_4, L13_4, L14_4)
            end
          end
        end
      end
      L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3)
    end
    L0_2(L1_2, L2_2, L3_2, L4_2)
  end
end
L4_1 = AddEventHandler
L5_1 = "rcore_stats:api:ready"
L6_1 = L3_1
L4_1(L5_1, L6_1)
L4_1 = CreateThread
function L5_1()
  local L0_2, L1_2, L2_2
  L0_2 = isResourcePresentProvideless
  L1_2 = "rcore_stats"
  L0_2 = L0_2(L1_2)
  if L0_2 then
    while true do
      L0_2 = L0_1
      if L0_2 then
        break
      end
      L0_2 = TriggerEvent
      L1_2 = "rcore_stats:api:isReady"
      function L2_2(A0_3)
        local L1_3
        if A0_3 then
          L1_3 = L3_1
          L1_3()
        end
      end
      L0_2(L1_2, L2_2)
      L0_2 = Wait
      L1_2 = 1000
      L0_2(L1_2)
    end
  end
end
L6_1 = "sv-stats code name: Phoenix"
L4_1(L5_1, L6_1)
