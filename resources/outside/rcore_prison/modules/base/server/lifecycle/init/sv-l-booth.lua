local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1
L0_1 = false
L1_1 = AddEventHandler
L2_1 = "rcore_prison:shared:internal:MapLoaded"
function L3_1()
  local L0_2, L1_2
  L0_2 = true
  L0_1 = L0_2
end
L1_1(L2_1, L3_1)
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:requestBooth"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  if A1_2 then
    L3_2 = SH
    L3_2 = L3_2.data
    L3_2 = L3_2.interaction
    L3_2 = L3_2[A2_2]
    if not L3_2 then
      L4_2 = Framework
      L4_2 = L4_2.sendNotification
      L5_2 = A0_2
      L6_2 = "Zone is not defined."
      L7_2 = "error"
      return L4_2(L5_2, L6_2, L7_2)
    end
    L4_2 = L3_2.zone
    L4_2 = L4_2.access
    if not L4_2 then
      L4_2 = INTERACT_ACCESS_TYPES
      L4_2 = L4_2.PRISONER_ONLY
    end
    L5_2 = SH
    L5_2 = L5_2.data
    L5_2 = L5_2.interaction
    L5_2 = L5_2[A2_2]
    L5_2 = L5_2.booth
    if not L5_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = "Booth is not defined."
      L9_2 = "error"
      return L6_2(L7_2, L8_2, L9_2)
    end
    L6_2 = BoothService
    L6_2 = L6_2.GetBooth
    L7_2 = L5_2.number
    L6_2 = L6_2(L7_2)
    L7_2 = INTERACT_ACCESS_TYPES
    L7_2 = L7_2.PRISONER_ONLY
    if L4_2 == L7_2 then
      L7_2 = PrisonService
      L7_2 = L7_2.CheckForAnySentence
      L8_2 = A0_2
      L7_2 = L7_2(L8_2)
      if not L7_2 then
        L7_2 = Framework
        L7_2 = L7_2.sendNotification
        L8_2 = A0_2
        L9_2 = "You do not have any active sentence."
        L10_2 = "error"
        return L7_2(L8_2, L9_2, L10_2)
      end
    end
    if not L6_2 then
      L7_2 = Framework
      L7_2 = L7_2.sendNotification
      L8_2 = A0_2
      L9_2 = "Booth is disabled!"
      L10_2 = "error"
      return L7_2(L8_2, L9_2, L10_2)
    end
    L7_2 = BoothService
    L7_2 = L7_2.IsOcuppied
    L8_2 = L6_2.number
    L9_2 = A0_2
    L7_2 = L7_2(L8_2, L9_2)
    if L7_2 then
      L7_2 = Framework
      L7_2 = L7_2.sendNotification
      L8_2 = A0_2
      L9_2 = "Booth is already in use."
      L10_2 = "error"
      return L7_2(L8_2, L9_2, L10_2)
    end
    L7_2 = Config
    L7_2 = L7_2.Phones
    L8_2 = Phones
    L8_2 = L8_2.NONE
    if L7_2 == L8_2 then
      return
    end
    L7_2 = dbg
    L7_2 = L7_2.debug
    L8_2 = "Booth with number %s is now active for player %s (%s)"
    L9_2 = L6_2.number
    L10_2 = GetPlayerName
    L11_2 = A0_2
    L10_2 = L10_2(L11_2)
    L11_2 = A0_2
    L7_2(L8_2, L9_2, L10_2, L11_2)
    L6_2.playerId = A0_2
    L7_2 = StartClient
    L8_2 = A0_2
    L9_2 = "openBooth"
    L10_2 = A2_2
    L7_2(L8_2, L9_2, L10_2)
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:requestBoothLeave"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  if A1_2 then
    L3_2 = SH
    L3_2 = L3_2.data
    L3_2 = L3_2.interaction
    L3_2 = L3_2[A2_2]
    if not L3_2 then
      L4_2 = Framework
      L4_2 = L4_2.sendNotification
      L5_2 = A0_2
      L6_2 = "Zone is not defined."
      L7_2 = "error"
      return L4_2(L5_2, L6_2, L7_2)
    end
    L4_2 = L3_2.zone
    L4_2 = L4_2.access
    if not L4_2 then
      L4_2 = INTERACT_ACCESS_TYPES
      L4_2 = L4_2.PRISONER_ONLY
    end
    L5_2 = SH
    L5_2 = L5_2.data
    L5_2 = L5_2.interaction
    L5_2 = L5_2[A2_2]
    L5_2 = L5_2.booth
    if not L5_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = "Booth is not defined."
      L9_2 = "error"
      return L6_2(L7_2, L8_2, L9_2)
    end
    L6_2 = BoothService
    L6_2 = L6_2.GetBooth
    L7_2 = L5_2.number
    L6_2 = L6_2(L7_2)
    L7_2 = INTERACT_ACCESS_TYPES
    L7_2 = L7_2.PRISONER_ONLY
    if L4_2 == L7_2 then
      L7_2 = PrisonService
      L7_2 = L7_2.CheckForAnySentence
      L8_2 = A0_2
      L7_2 = L7_2(L8_2)
      if not L7_2 then
        L7_2 = Framework
        L7_2 = L7_2.sendNotification
        L8_2 = A0_2
        L9_2 = "You do not have any active sentence."
        L10_2 = "error"
        return L7_2(L8_2, L9_2, L10_2)
      end
    end
    L7_2 = BoothService
    L7_2 = L7_2.IsOcuppied
    L8_2 = L6_2.number
    L9_2 = A0_2
    L7_2 = L7_2(L8_2, L9_2)
    if L7_2 then
      L7_2 = Framework
      L7_2 = L7_2.sendNotification
      L8_2 = A0_2
      L9_2 = "Booth is already in use."
      L10_2 = "error"
      return L7_2(L8_2, L9_2, L10_2)
    end
    L7_2 = Config
    L7_2 = L7_2.Phones
    L8_2 = Phones
    L8_2 = L8_2.NONE
    if L7_2 == L8_2 then
      return
    end
    L7_2 = dbg
    L7_2 = L7_2.debug
    L8_2 = "Booth with number %s is now inactive for player %s (%s)"
    L9_2 = L6_2.number
    L10_2 = GetPlayerName
    L11_2 = A0_2
    L10_2 = L10_2(L11_2)
    L11_2 = A0_2
    L7_2(L8_2, L9_2, L10_2, L11_2)
    L7_2 = BoothService
    L7_2 = L7_2.SendHeartbeat
    L8_2 = "BOOTH_LEAVE"
    function L9_2(A0_3)
      local L1_3, L2_3, L3_3, L4_3
      if A0_3 then
        L1_3 = Framework
        L1_3 = L1_3.sendNotification
        L2_3 = A0_2
        L3_3 = _U
        L4_3 = "BOOTHS.CALL_ENDED"
        L3_3 = L3_3(L4_3)
        L4_3 = "success"
        L1_3(L2_3, L3_3, L4_3)
      end
    end
    L10_2 = L6_2.callData
    L7_2(L8_2, L9_2, L10_2)
    L7_2 = CALL_ENUMS
    L7_2 = L7_2.IDLE
    L6_2.state = L7_2
    L6_2.playerId = nil
    L6_2.callData = nil
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:requestBoothCall"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if A1_2 then
    L4_2 = SH
    L4_2 = L4_2.data
    L4_2 = L4_2.interaction
    L4_2 = L4_2[A2_2]
    if not L4_2 then
      L5_2 = Framework
      L5_2 = L5_2.sendNotification
      L6_2 = A0_2
      L7_2 = "Zone is not defined."
      L8_2 = "error"
      return L5_2(L6_2, L7_2, L8_2)
    end
    L5_2 = L4_2.zone
    L5_2 = L5_2.access
    if not L5_2 then
      L5_2 = INTERACT_ACCESS_TYPES
      L5_2 = L5_2.PRISONER_ONLY
    end
    L6_2 = SH
    L6_2 = L6_2.data
    L6_2 = L6_2.interaction
    L6_2 = L6_2[A2_2]
    L6_2 = L6_2.booth
    if not L6_2 then
      L7_2 = Framework
      L7_2 = L7_2.sendNotification
      L8_2 = A0_2
      L9_2 = "Booth is not defined."
      L10_2 = "error"
      return L7_2(L8_2, L9_2, L10_2)
    end
    L7_2 = BoothService
    L7_2 = L7_2.GetBooth
    L8_2 = L6_2.number
    L7_2 = L7_2(L8_2)
    if not L7_2 then
      L8_2 = Framework
      L8_2 = L8_2.sendNotification
      L9_2 = A0_2
      L10_2 = "Booth is not defined."
      L11_2 = "error"
      return L8_2(L9_2, L10_2, L11_2)
    end
    L8_2 = INTERACT_ACCESS_TYPES
    L8_2 = L8_2.PRISONER_ONLY
    if L5_2 == L8_2 then
      L8_2 = PrisonService
      L8_2 = L8_2.CheckForAnySentence
      L9_2 = A0_2
      L8_2 = L8_2(L9_2)
      if not L8_2 then
        L8_2 = Framework
        L8_2 = L8_2.sendNotification
        L9_2 = A0_2
        L10_2 = "You do not have any active sentence."
        L11_2 = "error"
        return L8_2(L9_2, L10_2, L11_2)
      end
    end
    L8_2 = BoothService
    L8_2 = L8_2.SendHeartbeat
    L9_2 = "BOOTH_START_CALL"
    function L10_2(A0_3)
      local L1_3, L2_3, L3_3, L4_3
      if A0_3 then
        L1_3 = StartClient
        L2_3 = A0_2
        L3_3 = "startCall"
        L4_3 = A3_2
        L1_3(L2_3, L3_3, L4_3)
        L1_3 = Framework
        L1_3 = L1_3.sendNotification
        L2_3 = A0_2
        L3_3 = _U
        L4_3 = "BOOTHS.CALL_STARTED_FROM_BOOTH"
        L3_3 = L3_3(L4_3)
        L4_3 = "success"
        L1_3(L2_3, L3_3, L4_3)
      else
        L1_3 = CALL_ENUMS
        L1_3 = L1_3.IDLE
        L7_2.state = L1_3
        L7_2.playerId = nil
        L7_2.callData = nil
        L1_3 = StartClient
        L2_3 = A0_2
        L3_3 = "ResetCallState"
        L4_3 = A3_2
        L1_3(L2_3, L3_3, L4_3)
        L1_3 = Framework
        L1_3 = L1_3.sendNotification
        L2_3 = A0_2
        L3_3 = _U
        L4_3 = "BOOTHS.CALL_ENDED_FROM_BOOTH"
        L3_3 = L3_3(L4_3)
        L4_3 = "error"
        L1_3(L2_3, L3_3, L4_3)
      end
    end
    L11_2 = {}
    L11_2.targetNumber = A3_2
    L12_2 = L6_2.number
    L11_2.boothNumber = L12_2
    L11_2.initiatorPlayerId = A0_2
    L8_2(L9_2, L10_2, L11_2)
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = EventLimiterService
L1_1 = L1_1.RegisterNetEvent
L2_1 = "rcore_prison:server:requestBoothEndCall"
L3_1 = 0
L4_1 = 1
function L5_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if A1_2 then
    L3_2 = SH
    L3_2 = L3_2.data
    L3_2 = L3_2.interaction
    L3_2 = L3_2[A2_2]
    if not L3_2 then
      L4_2 = Framework
      L4_2 = L4_2.sendNotification
      L5_2 = A0_2
      L6_2 = "Zone is not defined."
      L7_2 = "error"
      return L4_2(L5_2, L6_2, L7_2)
    end
    L4_2 = L3_2.zone
    L4_2 = L4_2.access
    if not L4_2 then
      L4_2 = INTERACT_ACCESS_TYPES
      L4_2 = L4_2.PRISONER_ONLY
    end
    L5_2 = SH
    L5_2 = L5_2.data
    L5_2 = L5_2.interaction
    L5_2 = L5_2[A2_2]
    L5_2 = L5_2.booth
    if not L5_2 then
      L6_2 = Framework
      L6_2 = L6_2.sendNotification
      L7_2 = A0_2
      L8_2 = "Booth is not defined."
      L9_2 = "error"
      return L6_2(L7_2, L8_2, L9_2)
    end
    L6_2 = BoothService
    L6_2 = L6_2.GetBooth
    L7_2 = L5_2.number
    L6_2 = L6_2(L7_2)
    if not L6_2 then
      L7_2 = Framework
      L7_2 = L7_2.sendNotification
      L8_2 = A0_2
      L9_2 = "Booth is not defined."
      L10_2 = "error"
      return L7_2(L8_2, L9_2, L10_2)
    end
    if L6_2 then
      L7_2 = L6_2.playerId
      if not L7_2 then
        L7_2 = Framework
        L7_2 = L7_2.sendNotification
        L8_2 = A0_2
        L9_2 = "Booth is not in use."
        L10_2 = "error"
        return L7_2(L8_2, L9_2, L10_2)
      end
    end
    L7_2 = INTERACT_ACCESS_TYPES
    L7_2 = L7_2.PRISONER_ONLY
    if L4_2 == L7_2 then
      L7_2 = PrisonService
      L7_2 = L7_2.CheckForAnySentence
      L8_2 = A0_2
      L7_2 = L7_2(L8_2)
      if not L7_2 then
        L7_2 = Framework
        L7_2 = L7_2.sendNotification
        L8_2 = A0_2
        L9_2 = "You do not have any active sentence."
        L10_2 = "error"
        return L7_2(L8_2, L9_2, L10_2)
      end
    end
    L7_2 = L6_2.callData
    L7_2 = L7_2.targetPlayerId
    L8_2 = dbg
    L8_2 = L8_2.debug
    L9_2 = "Booth with number %s is now inactive for player %s (%s) since user request end call!"
    L10_2 = L6_2.number
    L11_2 = GetPlayerName
    L12_2 = A0_2
    L11_2 = L11_2(L12_2)
    L12_2 = A0_2
    L8_2(L9_2, L10_2, L11_2, L12_2)
    L8_2 = BoothService
    L8_2 = L8_2.SendHeartbeat
    L9_2 = "BOOTH_LEAVE"
    function L10_2(A0_3)
      local L1_3, L2_3, L3_3, L4_3
      if A0_3 then
        L1_3 = CALL_ENUMS
        L1_3 = L1_3.IDLE
        L6_2.state = L1_3
        L6_2.playerId = nil
        L6_2.callData = nil
        L1_3 = Framework
        L1_3 = L1_3.sendNotification
        L2_3 = A0_2
        L3_3 = _U
        L4_3 = "BOOTHS.LEAVE_CALL_ENDED"
        L3_3 = L3_3(L4_3)
        L4_3 = "success"
        L1_3(L2_3, L3_3, L4_3)
      end
    end
    L11_2 = {}
    L12_2 = L5_2.number
    L11_2.boothNumber = L12_2
    L11_2.targetPlayerId = L7_2
    L11_2.initiatorPlayerId = A0_2
    L12_2 = L6_2.callData
    L12_2 = L12_2.callId
    L11_2.callId = L12_2
    L8_2(L9_2, L10_2, L11_2)
  end
end
L1_1(L2_1, L3_1, L4_1, L5_1)
L1_1 = CreateThread
function L2_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2
  L0_2 = 0
  repeat
    L1_2 = Wait
    L2_2 = 250
    L1_2(L2_2)
    L0_2 = L0_2 + 1
    if L0_2 >= 50 then
      L1_2 = dbg
      L1_2 = L1_2.critical
      L2_2 = "Failed to load prison map in sv-l-booth.lua"
      L1_2(L2_2)
      break
    end
    L1_2 = L0_1
  until L1_2
  L1_2 = SH
  L1_2 = L1_2.data
  if not L1_2 then
    return
  end
  L1_2 = SH
  L1_2 = L1_2.data
  L1_2 = L1_2.interaction
  if not L1_2 then
    return
  end
  L1_2 = promise
  L1_2 = L1_2.new
  L1_2 = L1_2()
  L2_2 = {}
  L3_2 = {}
  L4_2 = "OK"
  L5_2 = next
  L6_2 = SH
  L6_2 = L6_2.data
  L6_2 = L6_2.interaction
  L5_2 = L5_2(L6_2)
  if L5_2 then
    L5_2 = 1
    L6_2 = SH
    L6_2 = L6_2.data
    L6_2 = L6_2.interaction
    L6_2 = #L6_2
    L7_2 = 1
    for L8_2 = L5_2, L6_2, L7_2 do
      L9_2 = SH
      L9_2 = L9_2.data
      L9_2 = L9_2.interaction
      L9_2 = L9_2[L8_2]
      if L9_2 then
        L10_2 = L9_2.type
        L11_2 = INTERACT_TYPES
        L11_2 = L11_2.BOOTH
        if L10_2 == L11_2 then
          L11_2 = L9_2.booth
          L12_2 = L11_2.number
          L13_2 = L3_2[L8_2]
          if not L13_2 then
            L13_2 = {}
            L13_2.id = L8_2
            L14_2 = L9_2.coords
            L13_2.coords = L14_2
            L13_2.number = L12_2
            L3_2[L8_2] = L13_2
          end
          L13_2 = L2_2[L12_2]
          if not L13_2 then
            L2_2[L12_2] = true
          else
            L4_2 = "FOUND_DUPLICATE_DISABLING_BOOTHS_MODULE"
            L13_2 = dbg
            L13_2 = L13_2.critical
            L14_2 = "Booth number is already in use: %s at index: %s"
            L15_2 = L12_2
            L16_2 = L8_2
            L13_2(L14_2, L15_2, L16_2)
          end
        end
      end
      L10_2 = SH
      L10_2 = L10_2.data
      L10_2 = L10_2.interaction
      L10_2 = #L10_2
      if L8_2 >= L10_2 then
        L11_2 = L1_2
        L10_2 = L1_2.resolve
        L12_2 = true
        L10_2(L11_2, L12_2)
      end
    end
  else
    L6_2 = L1_2
    L5_2 = L1_2.resolve
    L7_2 = true
    L5_2(L6_2, L7_2)
  end
  L5_2 = Citizen
  L5_2 = L5_2.Await
  L6_2 = L1_2
  L5_2(L6_2)
  L5_2 = "data/presets/%s.lua"
  L6_2 = L5_2
  L5_2 = L5_2.format
  L7_2 = SH
  L7_2 = L7_2.preset
  L5_2 = L5_2(L6_2, L7_2)
  L6_2 = "Booth module: %s"
  if "FOUND_DUPLICATE_DISABLING_BOOTHS_MODULE" == L4_2 then
    L4_2 = "ERROR"
    L7_2 = [[
%s - Path: %s 
 Please go to this path and adjust the booth number.]]
    L8_2 = L7_2
    L7_2 = L7_2.format
    L9_2 = L6_2
    L10_2 = L5_2
    L7_2 = L7_2(L8_2, L9_2, L10_2)
    L6_2 = L7_2
  end
  L7_2 = Config
  L7_2 = L7_2.Phones
  L8_2 = Phones
  L8_2 = L8_2.NONE
  if L7_2 == L8_2 then
    L4_2 = "ERROR"
    L7_2 = "%s - Phone resource is not supported by rcore_prison."
    L8_2 = L7_2
    L7_2 = L7_2.format
    L9_2 = L6_2
    L7_2 = L7_2(L8_2, L9_2)
    L6_2 = L7_2
    L7_2 = dbg
    L7_2 = L7_2.bridge
    L8_2 = L6_2
    L9_2 = L4_2
    L10_2 = L6_2
    return L7_2(L8_2, L9_2, L10_2)
  end
  L7_2 = dbg
  L7_2 = L7_2.bridge
  L8_2 = L6_2
  L9_2 = L4_2
  L10_2 = L6_2
  L7_2(L8_2, L9_2, L10_2)
  if "ERROR" == L4_2 then
    if L3_2 then
      L7_2 = next
      L8_2 = L3_2
      L7_2 = L7_2(L8_2)
      if L7_2 then
        L7_2 = tprint
        L8_2 = L3_2
        L7_2(L8_2)
      end
    end
  else
    L7_2 = BoothService
    L7_2 = L7_2.Register
    L8_2 = L3_2
    L7_2(L8_2)
  end
end
L1_1(L2_1)
