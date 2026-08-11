local L0_1, L1_1, L2_1
PrisonService = nil
ChatService = nil
L0_1 = {}
Inventory = L0_1
L0_1 = {}
Dispatch = L0_1
L0_1 = {}
PlayerLoadedPool = L0_1
L0_1 = {}
RestrictZone = L0_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2
  L0_2 = Object
  L0_2 = L0_2.getService
  L1_2 = SERVICE_PRISONER
  L0_2 = L0_2(L1_2)
  PrisonService = L0_2
  L0_2 = PrisonService
  if not L0_2 then
    L0_2 = dbg
    L0_2 = L0_2.critical
    L1_2 = "Cannot find prison service - sv-init.lua"
    L0_2(L1_2)
    return
  end
  L0_2 = Object
  L0_2 = L0_2.getService
  L1_2 = SERVICE_CHAT
  L0_2 = L0_2(L1_2)
  ChatService = L0_2
  L0_2 = ChatService
  if not L0_2 then
    L0_2 = dbg
    L0_2 = L0_2.critical
    L1_2 = "Cannot find chat service - sv-init.lua"
    L0_2(L1_2)
    return
  end
end
L2_1 = "sv-init code name: Phoenix"
L0_1(L1_1, L2_1)
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  if not A0_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = GetPlayerPed
  L3_2 = A1_2
  L2_2 = L2_2(L3_2)
  L3_2 = GetEntityCoords
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = true
  L5_2 = SH
  L5_2 = L5_2.data
  L5_2 = L5_2.interaction
  L5_2 = L5_2[A0_2]
  if not L5_2 then
    L6_2 = false
    return L6_2
  end
  L6_2 = L5_2.coords
  L6_2 = L3_2 - L6_2
  L6_2 = #L6_2
  if L5_2 then
    L7_2 = L5_2.zone
    if L7_2 then
      L7_2 = L5_2.zone
      L7_2 = L7_2.distance
      if L7_2 then
        goto lbl_36
      end
    end
  end
  L7_2 = Config
  L7_2 = L7_2.Zone
  L7_2 = L7_2.CheckDist
  ::lbl_36::
  if L5_2 then
    L8_2 = L5_2.zone
    if L8_2 then
      L8_2 = L5_2.zone
      L8_2 = L8_2.distance
      if L8_2 then
        L4_2 = false
      end
    end
  end
  L8_2 = dbg
  L8_2 = L8_2.debug
  L9_2 = "Checking zone distance for user %s: distance %s with check distance is <= %s | Config.Zone.CheckDist = %s"
  L10_2 = GetPlayerName
  L11_2 = A1_2
  L10_2 = L10_2(L11_2)
  L11_2 = L6_2
  L12_2 = L7_2
  L13_2 = L4_2
  L8_2(L9_2, L10_2, L11_2, L12_2, L13_2)
  if L6_2 <= L7_2 then
    L8_2 = true
    return L8_2
  end
  L8_2 = false
  return L8_2
end
IsAtZone = L0_1
