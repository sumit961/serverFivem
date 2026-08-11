local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1
L0_1 = {}
L1_1 = {}
L2_1 = "__rcore_prison_cb_%s"
L3_1 = "rcore_prison"
L4_1 = RegisterNetEvent
L6_1 = L2_1
L5_1 = L2_1.format
L7_1 = L3_1
L5_1 = L5_1(L6_1, L7_1)
function L6_1(A0_2, ...)
  local L1_2, L2_2, L3_2
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  L2_2 = L1_2 or L2_2
  if L1_2 then
    L2_2 = L1_2
    L3_2 = ...
    L2_2 = L2_2(L3_2)
  end
  return L2_2
end
L4_1(L5_1, L6_1)
function L4_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  if A1_2 then
    L2_2 = type
    L3_2 = A1_2
    L2_2 = L2_2(L3_2)
    if "number" == L2_2 and A1_2 > 0 then
      L2_2 = GetGameTimer
      L2_2 = L2_2()
      L3_2 = L1_1
      L3_2 = L3_2[A0_2]
      if not L3_2 then
        L3_2 = 0
      end
      if L2_2 < L3_2 then
        L3_2 = false
        return L3_2
      end
      L3_2 = L1_1
      L4_2 = L2_2 + A1_2
      L3_2[A0_2] = L4_2
    end
  end
  L2_2 = true
  return L2_2
end
function L5_1(A0_2, A1_2, A2_2, A3_2, ...)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L4_2 = L4_1
  L5_2 = A1_2
  L6_2 = A2_2
  L4_2 = L4_2(L5_2, L6_2)
  if not L4_2 then
    return
  end
  L4_2 = nil
  repeat
    L5_2 = "%s:%s"
    L6_2 = L5_2
    L5_2 = L5_2.format
    L7_2 = A1_2
    L8_2 = math
    L8_2 = L8_2.random
    L9_2 = 0
    L10_2 = 100000
    L8_2, L9_2, L10_2 = L8_2(L9_2, L10_2)
    L5_2 = L5_2(L6_2, L7_2, L8_2, L9_2, L10_2)
    L4_2 = L5_2
    L5_2 = L0_1
    L5_2 = L5_2[L4_2]
  until not L5_2
  L5_2 = TriggerServerEvent
  L6_2 = L2_1
  L7_2 = L6_2
  L6_2 = L6_2.format
  L8_2 = A1_2
  L6_2 = L6_2(L7_2, L8_2)
  L7_2 = L3_1
  L8_2 = L4_2
  L9_2, L10_2 = ...
  L5_2(L6_2, L7_2, L8_2, L9_2, L10_2)
  L5_2 = promise
  L5_2 = L5_2.new
  L5_2 = not A3_2 and L5_2
  L6_2 = L0_1
  function L7_2(A0_3)
    local L1_3, L2_3, L3_3
    L2_3 = L4_2
    L1_3 = L0_1
    L1_3[L2_3] = nil
    L1_3 = L5_2
    if L1_3 then
      L1_3 = L5_2
      L2_3 = L1_3
      L1_3 = L1_3.resolve
      L3_3 = A0_3
      return L1_3(L2_3, L3_3)
    end
    L1_3 = A3_2
    L2_3 = table
    L2_3 = L2_3.unpack
    L3_3 = A0_3
    L2_3, L3_3 = L2_3(L3_3)
    L1_3(L2_3, L3_3)
  end
  L6_2[L4_2] = L7_2
  if L5_2 then
    L6_2 = table
    L6_2 = L6_2.unpack
    L7_2 = Citizen
    L7_2 = L7_2.Await
    L8_2 = L5_2
    L7_2, L8_2, L9_2, L10_2 = L7_2(L8_2)
    return L6_2(L7_2, L8_2, L9_2, L10_2)
  end
end
L6_1 = setmetatable
L7_1 = {}
L8_1 = {}
L8_1.__call = L5_1
L6_1 = L6_1(L7_1, L8_1)
callback = L6_1
L6_1 = callback
function L7_1(A0_2, A1_2, ...)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = L5_1
  L3_2 = _
  L4_2 = A0_2
  L5_2 = A1_2
  L6_2 = false
  L7_2 = ...
  return L2_2(L3_2, L4_2, L5_2, L6_2, L7_2)
end
L6_1.await = L7_1
L6_1 = callback
function L7_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = RegisterNetEvent
  L3_2 = L2_1
  L4_2 = L3_2
  L3_2 = L3_2.format
  L5_2 = A0_2
  L3_2 = L3_2(L4_2, L5_2)
  function L4_2(A0_3, A1_3, ...)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L2_3 = TriggerServerEvent
    L3_3 = L2_1
    L4_3 = L3_3
    L3_3 = L3_3.format
    L5_3 = A0_3
    L3_3 = L3_3(L4_3, L5_3)
    L4_3 = A1_3
    L5_3 = {}
    L6_3 = A1_2
    L7_3 = ...
    L6_3, L7_3 = L6_3(L7_3)
    L5_3[1] = L6_3
    L5_3[2] = L7_3
    L2_3(L3_3, L4_3, L5_3)
  end
  L2_2(L3_2, L4_2)
end
L6_1.register = L7_1
