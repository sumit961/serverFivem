local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:executeMDWQuickAction"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  if A1_2 then
    L3_2 = Framework
    L3_2 = L3_2.canPerformJobCommand
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "Player named %s tried to execute a MDW quick action without permission"
      L5_2 = GetPlayerName
      L6_2 = A0_2
      L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2 = L5_2(L6_2)
      L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
      return
    end
    L3_2 = A2_2.action
    L4_2 = A2_2.data
    if L4_2 then
      L4_2 = L4_2.charId
    end
    L5_2 = A2_2.data
    if L5_2 then
      L5_2 = L5_2.characterId
    end
    L6_2 = tonumber
    L7_2 = A2_2.data
    if L7_2 then
      L7_2 = L7_2.amount
    end
    L6_2 = L6_2(L7_2)
    L7_2 = false
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "Player named %s is executing a MDW quick action: %s"
    L10_2 = GetPlayerName
    L11_2 = A0_2
    L10_2 = L10_2(L11_2)
    L11_2 = L3_2
    L8_2(L9_2, L10_2, L11_2)
    if "RELEASE_PLAYER" == L3_2 and L4_2 then
      L8_2 = PrisonService
      L8_2 = L8_2.getPlayerById
      L9_2 = L4_2
      L8_2 = L8_2(L9_2)
      if not L8_2 then
        L9_2 = dbg
        L9_2 = L9_2.debug
        L10_2 = "Player with charId: %s is not found!"
        L11_2 = L4_2
        return L9_2(L10_2, L11_2)
      end
      L9_2 = L8_2.source
      if not L9_2 then
        L10_2 = dbg
        L10_2 = L10_2.debug
        L11_2 = "Player named %s is not online, doing offline unjail!"
        L12_2 = L8_2.prisonerName
        L10_2(L11_2, L12_2)
        L10_2 = PrisonService
        L10_2 = L10_2.UnjailOfflineCitizen
        L11_2 = L4_2
        L10_2 = L10_2(L11_2)
        A1_2 = L10_2
      else
        L10_2 = A2_2.data
        if L10_2 then
          L10_2 = L10_2.TELEPORT_PLAYER
        end
        L11_2 = dbg
        L11_2 = L11_2.debug
        L12_2 = "Player named %s is releasing player named %s with state: %s"
        L13_2 = GetPlayerName
        L14_2 = L9_2
        L13_2 = L13_2(L14_2)
        L14_2 = L8_2.name
        L15_2 = L10_2
        L11_2(L12_2, L13_2, L14_2, L15_2)
        L11_2 = PrisonService
        L11_2 = L11_2.UnjailCitizen
        L12_2 = L9_2
        L13_2 = L10_2
        L11_2(L12_2, L13_2)
        L7_2 = true
        L11_2 = Framework
        L11_2 = L11_2.sendNotification
        L12_2 = L9_2
        L13_2 = _U
        L14_2 = "GENERAL.TARGET_PLAYER_HAS_BEEN_RELEASED"
        L13_2 = L13_2(L14_2)
        L14_2 = "success"
        L11_2(L12_2, L13_2, L14_2)
      end
      L10_2 = StartClient
      L11_2 = -1
      L12_2 = "updatePrisoner"
      L13_2 = L8_2
      L10_2(L11_2, L12_2, L13_2)
    elseif "RELEASE_PLAYER" == L3_2 and L5_2 then
      L8_2 = GetPlayerByCharacterId
      L9_2 = L5_2
      L8_2 = L8_2(L9_2)
      if not L8_2 then
        L9_2 = dbg
        L9_2 = L9_2.debug
        L10_2 = "Player with charId: %s is not found!"
        L11_2 = L5_2
        return L9_2(L10_2, L11_2)
      end
      L9_2 = COMSService
      L9_2 = L9_2.ReleaseUser
      L10_2 = L8_2
      L9_2(L10_2)
      L7_2 = true
      L9_2 = Framework
      L9_2 = L9_2.sendNotification
      L10_2 = A0_2
      L11_2 = _U
      L12_2 = "GENERAL.TARGET_PLAYER_HAS_BEEN_RELEASED"
      L11_2 = L11_2(L12_2)
      L12_2 = "success"
      L9_2(L10_2, L11_2, L12_2)
    elseif "EDIT_SENTENCE" == L3_2 then
      L8_2 = PrisonService
      L8_2 = L8_2.EditSentence
      L9_2 = L4_2
      L10_2 = L6_2
      L11_2 = A0_2
      L8_2(L9_2, L10_2, L11_2)
      L7_2 = true
      L8_2 = PrisonService
      L8_2 = L8_2.getPlayerById
      L9_2 = L4_2
      L8_2 = L8_2(L9_2)
      L9_2 = StartClient
      L10_2 = -1
      L11_2 = "updatePrisoner"
      L12_2 = L8_2
      L9_2(L10_2, L11_2, L12_2)
    end
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "Player named %s is executing a MDW quick action: %s was done with state: %s"
    L10_2 = GetPlayerName
    L11_2 = A0_2
    L10_2 = L10_2(L11_2)
    L11_2 = L3_2
    L12_2 = L7_2
    L8_2(L9_2, L10_2, L11_2, L12_2)
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:requestAddSentence"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if A1_2 then
    L3_2 = Framework
    L3_2 = L3_2.canPerformJobCommand
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      return
    end
    L3_2 = A0_2
    L4_2 = tonumber
    L5_2 = A2_2.playerId
    L4_2 = L4_2(L5_2)
    if L4_2 then
      L5_2 = GetPlayerPed
      L6_2 = L4_2
      L5_2 = L5_2(L6_2)
      if L5_2 <= 0 then
        L5_2 = dbg
        L5_2 = L5_2.debug
        L6_2 = "Player is not online"
        L7_2 = GetPlayerName
        L8_2 = L4_2
        L7_2, L8_2, L9_2, L10_2 = L7_2(L8_2)
        L5_2(L6_2, L7_2, L8_2, L9_2, L10_2)
        L5_2 = Framework
        L5_2 = L5_2.sendNotification
        L6_2 = L3_2
        L7_2 = _U
        L8_2 = "GENERAL.TARGET_PLAYER_NOT_FOUND"
        L7_2 = L7_2(L8_2)
        L8_2 = "error"
        L5_2(L6_2, L7_2, L8_2)
        L5_2 = false
        return L5_2
      end
    end
    L5_2 = A2_2.type
    if L4_2 == L3_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = L3_2
      L8_2 = _U
      L9_2 = "GENERAL.CANNOT_EXECUTE_ACTION_ON_YOURSELF"
      L8_2 = L8_2(L9_2)
      L9_2 = "error"
      L6_2(L7_2, L8_2, L9_2)
      L6_2 = dbg
      L6_2 = L6_2.debug
      L7_2 = "Player named %s tried to execute a MDW quick action on himself"
      L8_2 = GetPlayerName
      L9_2 = L3_2
      L8_2, L9_2, L10_2 = L8_2(L9_2)
      return L6_2(L7_2, L8_2, L9_2, L10_2)
    end
    if "COMS" == L5_2 then
      L6_2 = COMSService
      L6_2 = L6_2.StartPerollForCitizen
      L7_2 = L3_2
      L8_2 = L4_2
      L9_2 = A2_2.sentenceAmount
      L10_2 = A2_2.sentenceReason
      L6_2(L7_2, L8_2, L9_2, L10_2)
    elseif "JAIL" == L5_2 then
      L6_2 = PrisonService
      L6_2 = L6_2.JailCitizen
      L7_2 = L3_2
      L8_2 = L4_2
      L9_2 = A2_2.sentenceAmount
      L10_2 = A2_2.sentenceReason
      L6_2(L7_2, L8_2, L9_2, L10_2)
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
