local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1
L0_1 = {}
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:requestCigarProduction"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if A1_2 then
    L3_2 = SH
    L3_2 = L3_2.data
    L3_2 = L3_2.interaction
    L3_2 = L3_2[A2_2]
    if not L3_2 then
      return
    end
    L4_2 = L3_2.zone
    L4_2 = L4_2.access
    if not L4_2 then
      L4_2 = INTERACT_ACCESS_TYPES
      L4_2 = L4_2.PRISONER_ONLY
    end
    L5_2 = INTERACT_ACCESS_TYPES
    L5_2 = L5_2.PRISONER_ONLY
    if L4_2 == L5_2 then
      L5_2 = PrisonService
      L5_2 = L5_2.CheckForAnySentence
      L6_2 = A0_2
      L5_2 = L5_2(L6_2)
      if not L5_2 then
        L5_2 = Framework
        L5_2 = L5_2.sendNotification
        L6_2 = A0_2
        L7_2 = _U
        L8_2 = "GENERAL.YOUT_ARE_NOT_PRISONER"
        L7_2 = L7_2(L8_2)
        L8_2 = "error"
        return L5_2(L6_2, L7_2, L8_2)
      end
    end
    L5_2 = Object
    L5_2 = L5_2.getStorage
    L6_2 = STORAGE_CIGAR_PRODUCTION
    L5_2 = L5_2(L6_2)
    if not L5_2 then
      return
    end
    L6_2 = Inventory
    L6_2 = L6_2.DoesItemExist
    L7_2 = Config
    L7_2 = L7_2.CigarProduction
    L7_2 = L7_2.RewardItem
    L8_2 = A0_2
    L6_2 = L6_2(L7_2, L8_2)
    if not L6_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "CIGAR_PRODUCTION.REQUIRED_ITEM_NOT_FOUND"
      L10_2 = Config
      L10_2 = L10_2.CigarProduction
      L10_2 = L10_2.RewardItem
      L8_2 = L8_2(L9_2, L10_2)
      L9_2 = "error"
      L6_2(L7_2, L8_2, L9_2)
      L6_2 = dbg
      L6_2 = L6_2.critical
      L7_2 = "Cigar production: Cannot start since required item is not defined on your server for user %s (%s)"
      L8_2 = Config
      L8_2 = L8_2.CigarProduction
      L8_2 = L8_2.RewardItem
      L9_2 = GetPlayerName
      L10_2 = A0_2
      L9_2 = L9_2(L10_2)
      L10_2 = A0_2
      return L6_2(L7_2, L8_2, L9_2, L10_2)
    end
    L6_2 = L0_1
    L6_2 = L6_2[A0_2]
    if L6_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "CIGAR_PRODUCTION.COOLDOWN"
      L8_2 = L8_2(L9_2)
      L9_2 = "error"
      L6_2(L7_2, L8_2, L9_2)
      return
    end
    L6_2 = L0_1
    L6_2[A0_2] = true
    L6_2 = StartClient
    L7_2 = A0_2
    L8_2 = "startCigarProduction"
    L9_2 = A2_2
    L6_2(L7_2, L8_2, L9_2)
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:requestCigarProductionFailed"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if A1_2 then
    L3_2 = SH
    L3_2 = L3_2.data
    L3_2 = L3_2.interaction
    L3_2 = L3_2[A2_2]
    if not L3_2 then
      return
    end
    L4_2 = L3_2.zone
    L4_2 = L4_2.access
    if not L4_2 then
      L4_2 = INTERACT_ACCESS_TYPES
      L4_2 = L4_2.PRISONER_ONLY
    end
    L5_2 = INTERACT_ACCESS_TYPES
    L5_2 = L5_2.PRISONER_ONLY
    if L4_2 == L5_2 then
      L5_2 = PrisonService
      L5_2 = L5_2.CheckForAnySentence
      L6_2 = A0_2
      L5_2 = L5_2(L6_2)
      if not L5_2 then
        L5_2 = Framework
        L5_2 = L5_2.sendNotification
        L6_2 = A0_2
        L7_2 = _U
        L8_2 = "GENERAL.YOUT_ARE_NOT_PRISONER"
        L7_2 = L7_2(L8_2)
        L8_2 = "error"
        return L5_2(L6_2, L7_2, L8_2)
      end
    end
    L5_2 = Object
    L5_2 = L5_2.getStorage
    L6_2 = STORAGE_CIGAR_PRODUCTION
    L5_2 = L5_2(L6_2)
    if not L5_2 then
      return
    end
    L6_2 = Inventory
    L6_2 = L6_2.DoesItemExist
    L7_2 = Config
    L7_2 = L7_2.CigarProduction
    L7_2 = L7_2.RewardItem
    L8_2 = A0_2
    L6_2 = L6_2(L7_2, L8_2)
    if not L6_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "CIGAR_PRODUCTION.REQUIRED_ITEM_NOT_FOUND"
      L10_2 = Config
      L10_2 = L10_2.CigarProduction
      L10_2 = L10_2.RewardItem
      L8_2 = L8_2(L9_2, L10_2)
      L9_2 = "error"
      L6_2(L7_2, L8_2, L9_2)
      L6_2 = dbg
      L6_2 = L6_2.critical
      L7_2 = "Cigar production: Cannot start since required item is not defined on your server for user %s (%s)"
      L8_2 = Config
      L8_2 = L8_2.CigarProduction
      L8_2 = L8_2.RewardItem
      L9_2 = GetPlayerName
      L10_2 = A0_2
      L9_2 = L9_2(L10_2)
      L10_2 = A0_2
      return L6_2(L7_2, L8_2, L9_2, L10_2)
    end
    L6_2 = L0_1
    L6_2 = L6_2[A0_2]
    if L6_2 then
      L6_2 = Config
      L6_2 = L6_2.CigarProduction
      L6_2 = L6_2.RewardCooldown
      if L6_2 <= 0 then
        L6_2 = dbg
        L6_2 = L6_2.debug
        L7_2 = "No cooldown: Cigar production: Cooldown ended for player named: %s (%s)"
        L8_2 = GetPlayerName
        L9_2 = A0_2
        L8_2 = L8_2(L9_2)
        L9_2 = A0_2
        L6_2(L7_2, L8_2, L9_2)
        L6_2 = L0_1
        L6_2[A0_2] = nil
      else
        L6_2 = dbg
        L6_2 = L6_2.debug
        L7_2 = "Cooldown: Cigar production: Cooldown started for player named: %s (%s)"
        L8_2 = GetPlayerName
        L9_2 = A0_2
        L8_2 = L8_2(L9_2)
        L9_2 = A0_2
        L6_2(L7_2, L8_2, L9_2)
        L6_2 = SetTimeout
        L7_2 = Config
        L7_2 = L7_2.CigarProduction
        L7_2 = L7_2.RewardCooldown
        L7_2 = L7_2 * 60
        L7_2 = L7_2 * 1000
        function L8_2()
          local L0_3, L1_3, L2_3, L3_3
          L0_3 = dbg
          L0_3 = L0_3.debug
          L1_3 = "Cooldown: Cigar production: Cooldown ended for player named: %s (%s)"
          L2_3 = GetPlayerName
          L3_3 = A0_2
          L2_3 = L2_3(L3_3)
          L3_3 = A0_2
          L0_3(L1_3, L2_3, L3_3)
          L1_3 = A0_2
          L0_3 = L0_1
          L0_3[L1_3] = nil
        end
        L6_2(L7_2, L8_2)
      end
    end
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:requestCigarProductionReward"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if A1_2 then
    L3_2 = SH
    L3_2 = L3_2.data
    L3_2 = L3_2.interaction
    L3_2 = L3_2[A2_2]
    if not L3_2 then
      return
    end
    L4_2 = L3_2.zone
    L4_2 = L4_2.access
    if not L4_2 then
      L4_2 = INTERACT_ACCESS_TYPES
      L4_2 = L4_2.PRISONER_ONLY
    end
    L5_2 = INTERACT_ACCESS_TYPES
    L5_2 = L5_2.PRISONER_ONLY
    if L4_2 == L5_2 then
      L5_2 = PrisonService
      L5_2 = L5_2.CheckForAnySentence
      L6_2 = A0_2
      L5_2 = L5_2(L6_2)
      if not L5_2 then
        L5_2 = Framework
        L5_2 = L5_2.sendNotification
        L6_2 = A0_2
        L7_2 = _U
        L8_2 = "GENERAL.YOUT_ARE_NOT_PRISONER"
        L7_2 = L7_2(L8_2)
        L8_2 = "error"
        return L5_2(L6_2, L7_2, L8_2)
      end
    end
    L5_2 = Object
    L5_2 = L5_2.getStorage
    L6_2 = STORAGE_CIGAR_PRODUCTION
    L5_2 = L5_2(L6_2)
    if not L5_2 then
      return
    end
    L6_2 = Inventory
    L6_2 = L6_2.DoesItemExist
    L7_2 = Config
    L7_2 = L7_2.CigarProduction
    L7_2 = L7_2.RewardItem
    L8_2 = A0_2
    L6_2 = L6_2(L7_2, L8_2)
    if not L6_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "CIGAR_PRODUCTION.REQUIRED_ITEM_NOT_FOUND"
      L10_2 = Config
      L10_2 = L10_2.CigarProduction
      L10_2 = L10_2.RewardItem
      L8_2 = L8_2(L9_2, L10_2)
      L9_2 = "error"
      L6_2(L7_2, L8_2, L9_2)
      L6_2 = dbg
      L6_2 = L6_2.critical
      L7_2 = "Cigar production: Cannot start since required item is not defined on your server for user %s (%s)"
      L8_2 = Config
      L8_2 = L8_2.CigarProduction
      L8_2 = L8_2.RewardItem
      L9_2 = GetPlayerName
      L10_2 = A0_2
      L9_2 = L9_2(L10_2)
      L10_2 = A0_2
      return L6_2(L7_2, L8_2, L9_2, L10_2)
    end
    L6_2 = dbg
    L6_2 = L6_2.debug
    L7_2 = "Cigar production: Requesting reward for player named: %s (%s)"
    L8_2 = GetPlayerName
    L9_2 = A0_2
    L8_2 = L8_2(L9_2)
    L9_2 = A0_2
    L6_2(L7_2, L8_2, L9_2)
    L6_2 = L0_1
    L6_2 = L6_2[A0_2]
    if L6_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = _U
      L9_2 = "CIGAR_PRODUCTION.YOU_RECEIVED_REWARD"
      L8_2 = L8_2(L9_2)
      L9_2 = "success"
      L6_2(L7_2, L8_2, L9_2)
      L6_2 = 1
      L7_2 = Config
      L7_2 = L7_2.CigarProduction
      L7_2 = L7_2.RewardMin
      if L7_2 then
        L7_2 = Config
        L7_2 = L7_2.CigarProduction
        L7_2 = L7_2.RewardMax
        if L7_2 then
          L7_2 = math
          L7_2 = L7_2.random
          L8_2 = Config
          L8_2 = L8_2.CigarProduction
          L8_2 = L8_2.RewardMin
          L9_2 = Config
          L9_2 = L9_2.CigarProduction
          L9_2 = L9_2.RewardMax
          L7_2 = L7_2(L8_2, L9_2)
          L6_2 = L7_2
        end
      end
      L7_2 = Inventory
      L7_2 = L7_2.addItem
      L8_2 = A0_2
      L9_2 = Config
      L9_2 = L9_2.CigarProduction
      L9_2 = L9_2.RewardItem
      L10_2 = L6_2
      L7_2(L8_2, L9_2, L10_2)
      L7_2 = Config
      L7_2 = L7_2.CigarProduction
      L7_2 = L7_2.RewardCooldown
      if L7_2 <= 0 then
        L7_2 = dbg
        L7_2 = L7_2.debug
        L8_2 = "No cooldown: Cigar production: Cooldown ended for player named: %s (%s)"
        L9_2 = GetPlayerName
        L10_2 = A0_2
        L9_2 = L9_2(L10_2)
        L10_2 = A0_2
        L7_2(L8_2, L9_2, L10_2)
        L7_2 = L0_1
        L7_2[A0_2] = nil
      else
        L7_2 = dbg
        L7_2 = L7_2.debug
        L8_2 = "Cooldown: Cigar production: Cooldown started for player named: %s (%s)"
        L9_2 = GetPlayerName
        L10_2 = A0_2
        L9_2 = L9_2(L10_2)
        L10_2 = A0_2
        L7_2(L8_2, L9_2, L10_2)
        L7_2 = SetTimeout
        L8_2 = Config
        L8_2 = L8_2.CigarProduction
        L8_2 = L8_2.RewardCooldown
        L8_2 = L8_2 * 60
        L8_2 = L8_2 * 1000
        function L9_2()
          local L0_3, L1_3, L2_3, L3_3
          L0_3 = dbg
          L0_3 = L0_3.debug
          L1_3 = "Cooldown: Cigar production: Cooldown ended for player named: %s (%s)"
          L2_3 = GetPlayerName
          L3_3 = A0_2
          L2_3 = L2_3(L3_3)
          L3_3 = A0_2
          L0_3(L1_3, L2_3, L3_3)
          L1_3 = A0_2
          L0_3 = L0_1
          L0_3[L1_3] = nil
        end
        L7_2(L8_2, L9_2)
      end
    end
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
