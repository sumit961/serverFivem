local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.EventListener
L1_1 = "heartbeat"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = next
  L3_2 = A1_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  L2_2 = Config
  L2_2 = L2_2.Cloth
  L3_2 = Cloth
  L3_2 = L3_2.FAPPEARANCE
  if L2_2 ~= L3_2 then
    return
  end
  L2_2 = A1_2.prisoner
  if not L2_2 then
    return
  end
  L3_2 = HEARTBEAT_EVENTS
  L3_2 = L3_2.PRISONER_LOADED
  if A0_2 == L3_2 then
    L3_2 = L2_2.source
    L4_2 = L2_2.owner
    if L3_2 then
      L5_2 = GetCachedOutfit
      L6_2 = L4_2
      L5_2 = L5_2(L6_2)
      if L5_2 then
        L6_2 = next
        L7_2 = L5_2
        L6_2 = L6_2(L7_2)
        if L6_2 then
          L6_2 = StartClient
          L7_2 = L3_2
          L8_2 = "StoredOutfit"
          L9_2 = L5_2
          L6_2(L7_2, L8_2, L9_2)
        end
      end
    end
  else
    L3_2 = HEARTBEAT_EVENTS
    L3_2 = L3_2.PRISONER_RELEASED
    if A0_2 == L3_2 then
      L3_2 = L2_2.source
      L4_2 = L2_2.owner
      if L3_2 then
        L5_2 = GetCachedOutfit
        L6_2 = L4_2
        L5_2 = L5_2(L6_2)
        if L5_2 then
          L6_2 = next
          L7_2 = L5_2
          L6_2 = L6_2(L7_2)
          if L6_2 then
            L6_2 = StartClient
            L7_2 = L3_2
            L8_2 = "StoredOutfit"
            L9_2 = L5_2
            L6_2(L7_2, L8_2, L9_2)
          end
        end
      end
    end
  end
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNetEvent
L1_1 = "rcore_prison:request:saveOutfitIntoCache"
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = source
  L2_2 = PrisonService
  L2_2 = L2_2.CheckForAnySentence
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  L2_2 = Config
  L2_2 = L2_2.Cloth
  L3_2 = Cloth
  L3_2 = L3_2.FAPPEARANCE
  if L2_2 ~= L3_2 then
    return
  end
  L2_2 = Framework
  L2_2 = L2_2.getIdentifier
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  L3_2 = type
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  if "table" ~= L3_2 then
    return
  end
  L3_2 = CacheCurrentOutfit
  L4_2 = L2_2
  L5_2 = A0_2
  L3_2(L4_2, L5_2)
end
L0_1(L1_1, L2_1)
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = "%s_%s"
  L2_2 = L1_2
  L1_2 = L1_2.format
  L3_2 = GetCurrentResourceName
  L3_2 = L3_2()
  L4_2 = A0_2
  L1_2 = L1_2(L2_2, L3_2, L4_2)
  if L1_2 then
    L2_2 = DeleteResourceKvp
    L3_2 = L1_2
    L2_2(L3_2)
  end
end
DeleteCachedOutfit = L0_1
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = "%s_%s"
  L3_2 = L2_2
  L2_2 = L2_2.format
  L4_2 = GetCurrentResourceName
  L4_2 = L4_2()
  L5_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  if L2_2 then
    L3_2 = SetResourceKvp
    L4_2 = L2_2
    L5_2 = json
    L5_2 = L5_2.encode
    L6_2 = A1_2
    L5_2, L6_2 = L5_2(L6_2)
    L3_2(L4_2, L5_2, L6_2)
  end
end
CacheCurrentOutfit = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = "%s_%s"
  L2_2 = L1_2
  L1_2 = L1_2.format
  L3_2 = GetCurrentResourceName
  L3_2 = L3_2()
  L4_2 = A0_2
  L1_2 = L1_2(L2_2, L3_2, L4_2)
  L2_2 = GetResourceKvpString
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L3_2 = json
    L3_2 = L3_2.decode
    L4_2 = L2_2
    return L3_2(L4_2)
  end
end
GetCachedOutfit = L0_1
