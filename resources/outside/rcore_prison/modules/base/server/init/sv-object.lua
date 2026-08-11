local L0_1, L1_1, L2_1
L0_1 = {}
Object = L0_1
L0_1 = Object
L1_1 = {}
L0_1.services = L1_1
L0_1 = Object
L1_1 = {}
L0_1.storages = L1_1
L0_1 = Object
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = Object
  L2_2 = L2_2.services
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Service with name "
    L4_2 = A0_2
    L5_2 = " registered!"
    L3_2 = L3_2 .. L4_2 .. L5_2
    L2_2(L3_2)
  else
    L2_2 = dbg
    L2_2 = L2_2.error
    L3_2 = "Service with name "
    L4_2 = A0_2
    L5_2 = " already exists - rewrting!"
    L3_2 = L3_2 .. L4_2 .. L5_2
    L2_2(L3_2)
  end
  L2_2 = Object
  L2_2 = L2_2.services
  L2_2[A0_2] = A1_2
  L2_2 = pcall
  L3_2 = A1_2.init
  L2_2(L3_2)
  L2_2 = TriggerEvent
  L3_2 = "rcore_prison:server:registeredService"
  L4_2 = A0_2
  L2_2(L3_2, L4_2)
end
L0_1.registerService = L1_1
L0_1 = Object
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = Object
  L2_2 = L2_2.storages
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = dbg
    L2_2 = L2_2.debug
    L3_2 = "Storage with name "
    L4_2 = A0_2
    L5_2 = " registered!"
    L3_2 = L3_2 .. L4_2 .. L5_2
    L2_2(L3_2)
  else
    L2_2 = dbg
    L2_2 = L2_2.error
    L3_2 = "Storage with name "
    L4_2 = A0_2
    L5_2 = " already exists - rewriting!"
    L3_2 = L3_2 .. L4_2 .. L5_2
    L2_2(L3_2)
  end
  L2_2 = Object
  L2_2 = L2_2.storages
  L2_2[A0_2] = A1_2
  L2_2 = pcall
  L3_2 = A1_2.init
  L2_2(L3_2)
  L2_2 = TriggerEvent
  L3_2 = "rcore_prison:server:registeredStorage"
  L4_2 = A0_2
  L2_2(L3_2, L4_2)
end
L0_1.registerStorage = L1_1
L0_1 = Object
function L1_1(A0_2)
  local L1_2
  L1_2 = Object
  L1_2 = L1_2.services
  L1_2 = L1_2[A0_2]
  return L1_2
end
L0_1.getService = L1_1
L0_1 = Object
function L1_1(A0_2)
  local L1_2
  L1_2 = Object
  L1_2 = L1_2.storages
  L1_2 = L1_2[A0_2]
  return L1_2
end
L0_1.getStorage = L1_1
L0_1 = exports
L1_1 = "getObject"
function L2_1()
  local L0_2, L1_2
  L0_2 = Object
  return L0_2
end
L0_1(L1_1, L2_1)
