local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:handleQuestTask"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if A1_2 then
    L3_2 = PrisonService
    L3_2 = L3_2.getPlayer
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      L4_2 = Framework
      L4_2 = L4_2.sendNotification
      L5_2 = A0_2
      L6_2 = _U
      L7_2 = "GENERAL.YOU_ARE_NOT_PRISONER"
      L6_2 = L6_2(L7_2)
      L7_2 = "error"
      return L4_2(L5_2, L6_2, L7_2)
    end
    L4_2 = type
    L5_2 = A2_2
    L4_2 = L4_2(L5_2)
    L4_2 = not L4_2
    if "table" == L4_2 then
      return
    end
    L4_2 = A2_2.zoneId
    L5_2 = IsAtZone
    L6_2 = L4_2
    L7_2 = A0_2
    L5_2 = L5_2(L6_2, L7_2)
    if not L5_2 then
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "Handle quest task: Player named %s is not in zone with ID: %s"
      L7_2 = GetPlayerName
      L8_2 = A0_2
      L7_2 = L7_2(L8_2)
      L8_2 = L4_2
      L5_2(L6_2, L7_2, L8_2)
      L5_2 = Framework
      L5_2 = L5_2.sendNotification
      L6_2 = A0_2
      L7_2 = _U
      L8_2 = "GENERAL.YOU_ARE_FAR_AWAY"
      L7_2 = L7_2(L8_2)
      L8_2 = "error"
      return L5_2(L6_2, L7_2, L8_2)
    end
    L5_2 = A2_2.action
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "Handle quest task: Executing action: %s"
    L8_2 = L5_2
    L6_2(L7_2, L8_2)
    L6_2 = Actions
    L6_2 = L6_2.SHOW_JAIL_TIME
    if L5_2 == L6_2 then
      L6_2 = dbg
      L6_2 = L6_2.debug
      L7_2 = "Handle quest task: Started action - show jail time!"
      L6_2(L7_2)
      L6_2 = tonumber
      L7_2 = L3_2.jail_time
      L6_2 = L6_2(L7_2)
      if not L6_2 then
        return
      end
      L7_2 = Framework
      L7_2 = L7_2.sendNotification
      L8_2 = A0_2
      L9_2 = _U
      L10_2 = "GENERAL.REMAINING_JAIL_TIME"
      L11_2 = Time
      L11_2 = L11_2.DynamicSecondsToClock
      L12_2 = L6_2
      L11_2, L12_2 = L11_2(L12_2)
      L9_2 = L9_2(L10_2, L11_2, L12_2)
      L10_2 = "info"
      L7_2(L8_2, L9_2, L10_2)
    else
      L6_2 = Actions
      L6_2 = L6_2.GET_FREE_FOOD_PACKAGE
      if L5_2 == L6_2 then
        L6_2 = CanteenService
        L6_2 = L6_2.GetFreeFoodPackage
        L7_2 = A0_2
        L6_2(L7_2)
      else
        L6_2 = Actions
        L6_2 = L6_2.SHOW_CANTEEN
        if L5_2 == L6_2 then
          L6_2 = CanteenService
          L6_2 = L6_2.ShowOffer
          L7_2 = A0_2
          L6_2(L7_2)
        else
          L6_2 = Actions
          L6_2 = L6_2.PRISON_BREAK
          if L5_2 == L6_2 then
            L6_2 = StartPrisonBreak
            L7_2 = A0_2
            L6_2(L7_2)
          else
            L6_2 = Actions
            L6_2 = L6_2.RELEASE_PLAYER
            if L5_2 == L6_2 then
              L6_2 = tonumber
              L7_2 = L3_2.jail_time
              L6_2 = L6_2(L7_2)
              if L6_2 and L6_2 > 2 then
                L7_2 = Framework
                L7_2 = L7_2.sendNotification
                L8_2 = A0_2
                L9_2 = _U
                L10_2 = "CANNOT_BE_RELEASED"
                L11_2 = Time
                L11_2 = L11_2.DynamicSecondsToClock
                L12_2 = L6_2
                L11_2, L12_2 = L11_2(L12_2)
                L9_2 = L9_2(L10_2, L11_2, L12_2)
                L10_2 = "error"
                return L7_2(L8_2, L9_2, L10_2)
              end
              L7_2 = PrisonService
              L7_2 = L7_2.UnjailCitizen
              L8_2 = A0_2
              L9_2 = true
              L7_2(L8_2, L9_2)
            end
          end
        end
      end
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
