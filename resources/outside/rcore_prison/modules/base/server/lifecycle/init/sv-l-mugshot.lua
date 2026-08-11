local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:syncMugshot"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  if A1_2 then
    L3_2 = Config
    L3_2 = L3_2.Mugshot
    if not L3_2 then
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "Mugshot is disabled when syncing mugshot for user: %s -> returning!"
      L5_2 = GetPlayerName
      L6_2 = A0_2
      L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
      return L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
    end
    L3_2 = PrisonService
    L3_2 = L3_2.getPlayer
    L4_2 = A0_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      L4_2 = dbg
      L4_2 = L4_2.debug
      L5_2 = "syncMugshot Prisoner not found when syncing mugshot for user: %s"
      L6_2 = GetPlayerName
      L7_2 = A0_2
      L6_2, L7_2, L8_2 = L6_2(L7_2)
      return L4_2(L5_2, L6_2, L7_2, L8_2)
    end
    L4_2 = Object
    L4_2 = L4_2.getStorage
    L5_2 = STORAGE_PRISONER
    L4_2 = L4_2(L5_2)
    if not L4_2 then
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "syncMugshot Prisoner storage not found when syncing mugshot for user: %s"
      L7_2 = GetPlayerName
      L8_2 = A0_2
      L7_2, L8_2 = L7_2(L8_2)
      return L5_2(L6_2, L7_2, L8_2)
    end
    L5_2 = L4_2.MugshotDefinedForPrisoner
    L6_2 = A0_2
    L5_2 = L5_2(L6_2)
    if L5_2 then
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "syncMugshot Prisoner mugshot is defined when syncing mugshot for user: %s"
      L7_2 = GetPlayerName
      L8_2 = A0_2
      L7_2, L8_2 = L7_2(L8_2)
      return L5_2(L6_2, L7_2, L8_2)
    end
    if not A2_2 then
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "syncMugshot Prisoner mugshot data are missing for user named: %s"
      L7_2 = GetPlayerName
      L8_2 = A0_2
      L7_2, L8_2 = L7_2(L8_2)
      return L5_2(L6_2, L7_2, L8_2)
    end
    L5_2 = A2_2.id
    if L5_2 ~= A0_2 then
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "syncMugshot Prisoner playerId is not matching the mugshot source which was sent for user: %s"
      L7_2 = GetPlayerName
      L8_2 = A0_2
      L7_2, L8_2 = L7_2(L8_2)
      return L5_2(L6_2, L7_2, L8_2)
    end
    L5_2 = L3_2.mugshot
    if L5_2 then
      L5_2 = L4_2.UpdatePlayerDataByKey
      L6_2 = "mugshotState"
      L7_2 = true
      L8_2 = A0_2
      L5_2(L6_2, L7_2, L8_2)
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
