local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1
L0_1 = {}
L1_1 = "__rcore_prison_cb_%s"
L2_1 = "rcore_prison"
L3_1 = RegisterNetEvent
L5_1 = L1_1
L4_1 = L1_1.format
L6_1 = L2_1
L4_1 = L4_1(L5_1, L6_1)
function L5_1(A0_2, ...)
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
L3_1(L4_1, L5_1)
function L3_1(A0_2, A1_2, A2_2, A3_2, ...)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L4_2 = nil
  repeat
    L5_2 = "%s:%s:%s"
    L6_2 = L5_2
    L5_2 = L5_2.format
    L7_2 = A1_2
    L8_2 = math
    L8_2 = L8_2.random
    L9_2 = 0
    L10_2 = 100000
    L8_2 = L8_2(L9_2, L10_2)
    L9_2 = A2_2
    L5_2 = L5_2(L6_2, L7_2, L8_2, L9_2)
    L4_2 = L5_2
    L5_2 = L0_1
    L5_2 = L5_2[L4_2]
  until not L5_2
  L5_2 = TriggerClientEvent
  L6_2 = L1_1
  L7_2 = L6_2
  L6_2 = L6_2.format
  L8_2 = A1_2
  L6_2 = L6_2(L7_2, L8_2)
  L7_2 = A2_2
  L8_2 = L2_1
  L9_2 = L4_2
  L10_2 = ...
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
L4_1 = setmetatable
L5_1 = {}
L6_1 = {}
L6_1.__call = L3_1
L4_1 = L4_1(L5_1, L6_1)
callback = L4_1
L4_1 = callback
function L5_1(A0_2, A1_2, ...)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = L3_1
  L3_2 = _
  L4_2 = A0_2
  L5_2 = A1_2
  L6_2 = false
  L7_2 = ...
  return L2_2(L3_2, L4_2, L5_2, L6_2, L7_2)
end
L4_1.await = L5_1
L4_1 = callback
function L5_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = RegisterNetEvent
  L3_2 = L1_1
  L4_2 = L3_2
  L3_2 = L3_2.format
  L5_2 = A0_2
  L3_2 = L3_2(L4_2, L5_2)
  function L4_2(A0_3, A1_3, ...)
    local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3
    L2_3 = TriggerClientEvent
    L3_3 = L1_1
    L4_3 = L3_3
    L3_3 = L3_3.format
    L5_3 = A0_3
    L3_3 = L3_3(L4_3, L5_3)
    L4_3 = source
    L5_3 = A1_3
    L6_3 = {}
    L7_3 = A1_2
    L8_3 = source
    L9_3 = ...
    L7_3, L8_3, L9_3 = L7_3(L8_3, L9_3)
    L6_3[1] = L7_3
    L6_3[2] = L8_3
    L6_3[3] = L9_3
    L2_3(L3_3, L4_3, L5_3, L6_3)
  end
  L2_2(L3_2, L4_2)
end
L4_1.register = L5_1
