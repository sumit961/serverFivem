local L0_1, L1_1, L2_1
L0_1 = {}
BoothService = L0_1
L0_1 = BoothService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_BOOTH
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  L2_2 = "Internal script heartbeat"
  L3_2 = GetInvokingResource
  L3_2 = L3_2()
  if L3_2 then
    L3_2 = GetInvokingResource
    L3_2 = L3_2()
    L2_2 = L3_2
  end
  L3_2 = dbg
  L3_2 = L3_2.debug
  L4_2 = "BoothStorage: Was invoked by resource named %s - checking number if its phone booth: %s"
  L5_2 = L2_2
  L6_2 = A0_2
  L3_2(L4_2, L5_2, L6_2)
  L3_2 = L1_2.getBooth
  L4_2 = A0_2
  return L3_2(L4_2)
end
L0_1.GetBooth = L1_1
L0_1 = exports
L1_1 = "GetBooth"
L2_1 = BoothService
L2_1 = L2_1.GetBooth
L0_1(L1_1, L2_1)
L0_1 = BoothService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = BoothService
  L1_2 = L1_2.GetBooth
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = "CAN_DO_CALL"
  if not L1_2 then
    L2_2 = "BOOTH_NOT_FOUND"
    L3_2 = false
    L4_2 = L2_2
    return L3_2, L4_2
  end
  L3_2 = L1_2.state
  L4_2 = CALL_ENUMS
  L4_2 = L4_2.IDLE
  if L3_2 ~= L4_2 then
    L2_2 = "BOOTH_NOT_IDLE"
    L3_2 = false
    L4_2 = L2_2
    return L3_2, L4_2
  end
  L3_2 = L1_2.callData
  if L3_2 then
    L3_2 = table
    L3_2 = L3_2.size
    L4_2 = L1_2.callData
    L3_2 = L3_2(L4_2)
    if L3_2 then
      goto lbl_31
    end
  end
  L3_2 = 0
  ::lbl_31::
  if L3_2 > 0 then
    L2_2 = "BOOTH_ACTIVE_CALL"
    L4_2 = false
    L5_2 = L2_2
    return L4_2, L5_2
  end
  L4_2 = L1_2.playerId
  if not L4_2 then
    L2_2 = "BOOTH_PLAYER_NOT_FOUND"
    L4_2 = false
    L5_2 = L2_2
    return L4_2, L5_2
  end
  L4_2 = true
  L5_2 = L2_2
  L6_2 = L1_2.playerId
  return L4_2, L5_2, L6_2
end
L0_1.CanCall = L1_1
L0_1 = exports
L1_1 = "GetBoothCallState"
L2_1 = BoothService
L2_1 = L2_1.CanCall
L0_1(L1_1, L2_1)
L0_1 = BoothService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = BoothService
  L2_2 = L2_2.GetBooth
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = "ACTIVE"
  if not L2_2 then
    L3_2 = "NOT_ACTIVE"
    L4_2 = false
    L5_2 = L3_2
    return L4_2, L5_2
  end
  L4_2 = L2_2.playerId
  if not L4_2 then
    L4_2 = false
    L5_2 = L3_2
    return L4_2, L5_2
  end
  L4_2 = L2_2.playerId
  L4_2 = not L4_2
  if L4_2 ~= A1_2 then
    L4_2 = false
    L5_2 = L3_2
    return L4_2, L5_2
  end
  L4_2 = true
  return L4_2
end
L0_1.IsOcuppied = L1_1
L0_1 = BoothService
function L1_1(A0_2, A1_2, ...)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = TriggerEvent
  L3_2 = "rcore_prison:server:booth:HeartBeat"
  L4_2 = A0_2
  L5_2 = (...)
  function L6_2(A0_3)
    local L1_3, L2_3
    L1_3 = A1_2
    L2_3 = A0_3
    L1_3(L2_3)
  end
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
L0_1.SendHeartbeat = L1_1
L0_1 = BoothService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L1_2 = Object
  L1_2 = L1_2.getStorage
  L2_2 = STORAGE_BOOTH
  L1_2 = L1_2(L2_2)
  if not L1_2 then
    return
  end
  if not A0_2 then
    return
  end
  L2_2 = pairs
  L3_2 = A0_2
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = BoothModel
    L8_2 = L8_2()
    L9_2 = L7_2.number
    L8_2.number = L9_2
    L9_2 = vec3
    L10_2 = L7_2.coords
    L10_2 = L10_2.x
    L11_2 = L7_2.coords
    L11_2 = L11_2.y
    L12_2 = L7_2.coords
    L12_2 = L12_2.z
    L9_2 = L9_2(L10_2, L11_2, L12_2)
    L8_2.coords = L9_2
    if L8_2 then
      L9_2 = L1_2.registerBooth
      L10_2 = L8_2
      L9_2(L10_2)
    end
  end
end
L0_1.Register = L1_1
