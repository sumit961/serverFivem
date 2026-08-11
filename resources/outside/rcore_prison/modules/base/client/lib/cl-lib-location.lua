local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "teleportUser"
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  if A0_2 then
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "Teleport session: Preparing teleport to area! 1/2 - reason: %s"
    L5_2 = A2_2
    L3_2(L4_2, L5_2)
    L3_2 = PlayerPedId
    L3_2 = L3_2()
    L4_2 = GetGameTimer
    L4_2 = L4_2()
    L5_2 = FreezeEntityPosition
    L6_2 = L3_2
    L7_2 = true
    L5_2(L6_2, L7_2)
    while true do
      L5_2 = HasCollisionLoadedAroundEntity
      L6_2 = L3_2
      L5_2 = L5_2(L6_2)
      if L5_2 then
        break
      end
      L5_2 = GetGameTimer
      L5_2 = L5_2()
      L5_2 = L5_2 - L4_2
      L6_2 = 5000
      if not (L5_2 < L6_2) then
        break
      end
      L5_2 = Wait
      L6_2 = 0
      L5_2(L6_2)
    end
    L5_2 = SetEntityCoords
    L6_2 = L3_2
    L7_2 = A1_2.x
    L8_2 = A1_2.y
    L9_2 = A1_2.z
    L10_2 = false
    L11_2 = false
    L12_2 = false
    L13_2 = false
    L5_2(L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
    L5_2 = SetEntityHeading
    L6_2 = L3_2
    L7_2 = A1_2.w
    if not L7_2 then
      L7_2 = 0
    end
    L5_2(L6_2, L7_2)
    L5_2 = TELEPORT_TYPES
    L5_2 = L5_2.TO_YARD_NEW_PRISONER
    if A2_2 == L5_2 then
      L5_2 = dbg
      L5_2 = L5_2.debug
      L6_2 = "Teleport session: Looks like teleport to yard new prisoner, loading some transition!"
      L7_2 = A2_2
      L5_2(L6_2, L7_2)
    end
    L5_2 = dbg
    L5_2 = L5_2.debug
    L6_2 = "Teleport session: User was succesfully teleported to target area! 2/2 - reason: %s"
    L7_2 = A2_2
    L5_2(L6_2, L7_2)
    L5_2 = FreezeEntityPosition
    L6_2 = L3_2
    L7_2 = false
    L5_2(L6_2, L7_2)
    L5_2 = SetTimeout
    L6_2 = 1000
    function L7_2()
      local L0_3, L1_3, L2_3
      L0_3 = FreezeEntityPosition
      L1_3 = L3_2
      L2_3 = false
      L0_3(L1_3, L2_3)
    end
    L5_2(L6_2, L7_2)
  end
end
L0_1(L1_1, L2_1)
