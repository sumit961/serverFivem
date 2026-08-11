local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = {}
OccupiedChairs = L0_1
L0_1 = RegisterCommand
L1_1 = "seats"
function L2_1(A0_2)
  local L1_2, L2_2
  if 0 == A0_2 then
    L1_2 = tprint
    L2_2 = OccupiedChairs
    L1_2(L2_2)
  end
end
L3_1 = false
L0_1(L1_1, L2_1, L3_1)
function L0_1(A0_2, A1_2)
  local L2_2
  L2_2 = OccupiedChairs
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L2_2 = OccupiedChairs
    L2_2 = L2_2[A0_2]
    L2_2 = L2_2.user
  end
  L2_2 = L2_2 == A1_2 or L2_2
  return L2_2
end
IsSeatOccupiedByUser = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = nil
  L2_2 = pairs
  L3_2 = OccupiedChairs
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = L7_2.user
    if L8_2 == A0_2 then
      L1_2 = L6_2
      break
    end
  end
  return L1_2
end
GetSeatIdxByServerId = L0_1
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:unregisterSeat"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if A1_2 then
    L4_2 = source
    if not A3_2 then
      return
    end
    L5_2 = SH
    L5_2 = L5_2.data
    L5_2 = L5_2.Chairs
    L6_2 = joaat
    L7_2 = A3_2
    L6_2 = L6_2(L7_2)
    L5_2 = L5_2[L6_2]
    if L5_2 then
      L6_2 = L5_2.positions
      L6_2 = L6_2[A2_2]
      if L6_2 then
        L7_2 = L6_2.offset
        if L7_2 then
          L7_2 = IsUserAtSeatPos
          L8_2 = L4_2
          L9_2 = L6_2.offset
          function L10_2(A0_3, A1_3)
            local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
            if A0_3 then
              L2_3 = GetIdxByPos
              L3_3 = A1_3
              L2_3 = L2_3(L3_3)
              L3_3 = OccupiedChairs
              L3_3 = L3_3[L2_3]
              if not L3_3 then
                L3_3 = GetSeatIdxByServerId
                L4_3 = L4_2
                L3_3 = L3_3(L4_3)
                L2_3 = L3_3
              end
              L3_3 = OccupiedChairs
              L3_3 = L3_3[L2_3]
              if L3_3 then
                L3_3 = OccupiedChairs
                L3_3 = L3_3[L2_3]
                L4_3 = IsSeatOccupiedByUser
                L5_3 = L2_3
                L6_3 = L4_2
                L4_3 = L4_3(L5_3, L6_3)
                if L4_3 then
                  L4_3 = StartClient
                  L5_3 = L4_2
                  L6_3 = "startExit"
                  L7_3 = L3_3
                  L4_3(L5_3, L6_3, L7_3)
                  L4_3 = SetTimeout
                  L5_3 = 500
                  function L6_3()
                    local L0_4, L1_4, L2_4
                    L0_4 = OccupiedChairs
                    L1_4 = L2_3
                    L0_4[L1_4] = nil
                    L0_4 = Inventory
                    L0_4 = L0_4.HandleOpenState
                    L1_4 = L4_2
                    L2_4 = false
                    L0_4(L1_4, L2_4)
                  end
                  L4_3(L5_3, L6_3)
                end
              end
            end
          end
          L7_2(L8_2, L9_2, L10_2)
        end
      end
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
L0_1 = EventLimiterService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "rcore_prison:server:registerSeat"
L2_1 = 0
L3_1 = 1
function L4_1(A0_2, A1_2, A2_2, A3_2, A4_2, A5_2)
  local L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if A1_2 then
    L6_2 = source
    if not A5_2 then
      return
    end
    L7_2 = SH
    L7_2 = L7_2.data
    L7_2 = L7_2.Chairs
    L8_2 = joaat
    L9_2 = A5_2
    L8_2 = L8_2(L9_2)
    L7_2 = L7_2[L8_2]
    if L7_2 then
      L8_2 = L7_2.positions
      L8_2 = L8_2[A4_2]
      if L8_2 then
        L9_2 = L8_2.offset
        if L9_2 then
          L9_2 = IsUserAtSeatPos
          L10_2 = L6_2
          L11_2 = L8_2.offset
          function L12_2(A0_3, A1_3)
            local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3
            if A0_3 then
              L2_3 = GetIdxByPos
              L3_3 = A1_3
              L2_3 = L2_3(L3_3)
              L3_3 = OccupiedChairs
              L3_3 = L3_3[L2_3]
              if L3_3 then
                L3_3 = OccupiedChairs
                L3_3 = L3_3[L2_3]
                L3_3 = L3_3.seatPosIdx
                L4_3 = A4_2
                if L3_3 == L4_3 then
                  L3_3 = Framework
                  L3_3 = L3_3.sendNotification
                  L4_3 = L6_2
                  L5_3 = _U
                  L6_3 = "CHAIRS.SOMEBODY_IS_SITTING"
                  L5_3 = L5_3(L6_3)
                  L6_3 = "error"
                  L3_3(L4_3, L5_3, L6_3)
                  return
                end
              end
              L3_3 = RegisterSeatPos
              L4_3 = L6_2
              L5_3 = A4_2
              L6_3 = A5_2
              L7_3 = A3_2
              L8_3 = A2_2
              L9_3 = L7_2
              L10_3 = A1_3
              L3_3(L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3)
            end
          end
          L9_2(L10_2, L11_2, L12_2)
        end
      end
    end
  end
end
L0_1(L1_1, L2_1, L3_1, L4_1)
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = math
  L1_2 = L1_2.ceil
  L2_2 = A0_2.x
  L2_2 = L2_2 / 2
  L1_2 = L1_2(L2_2)
  L1_2 = L1_2 * 2
  L1_2 = L1_2 - 1
  L2_2 = ""
  L3_2 = math
  L3_2 = L3_2.ceil
  L4_2 = A0_2.y
  L4_2 = L4_2 / 2
  L3_2 = L3_2(L4_2)
  L3_2 = L3_2 * 2
  L3_2 = L3_2 - 1
  L1_2 = L1_2 .. L2_2 .. L3_2
  L3_2 = L1_2
  L2_2 = L1_2.gsub
  L4_2 = "%-"
  L5_2 = ""
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L3_2 = tonumber
  L4_2 = L2_2
  return L3_2(L4_2)
end
GetIdxByPos = L0_1
function L0_1(A0_2, A1_2, A2_2, A3_2, A4_2, A5_2, A6_2)
  local L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  L7_2 = GetIdxByPos
  L8_2 = A6_2
  L7_2 = L7_2(L8_2)
  L8_2 = OccupiedChairs
  L8_2 = L8_2[L7_2]
  if not L8_2 then
    L8_2 = OccupiedChairs
    L9_2 = {}
    L9_2.user = A0_2
    L10_2 = GetPlayerName
    L11_2 = A0_2
    L10_2 = L10_2(L11_2)
    L9_2.name = L10_2
    L9_2.model = A2_2
    L9_2.seatType = A3_2
    L9_2.seatPosIdx = A1_2
    L8_2[L7_2] = L9_2
  end
  L8_2 = Inventory
  L8_2 = L8_2.HandleOpenState
  L9_2 = A0_2
  L10_2 = true
  L8_2(L9_2, L10_2)
  L8_2 = ""
  if "lay" == A3_2 then
    L9_2 = _U
    L10_2 = "CHAIRS.YOU_ARE_NOW_LAYING"
    L9_2 = L9_2(L10_2)
    L8_2 = L9_2
  elseif "sit" == A3_2 then
    L9_2 = _U
    L10_2 = "CHAIRS.YOU_ARE_NOW_SITTING"
    L9_2 = L9_2(L10_2)
    L8_2 = L9_2
  else
    L9_2 = _U
    L10_2 = "CHAIRS.YOU_ARE_NOW_SITTING"
    L9_2 = L9_2(L10_2)
    L8_2 = L9_2
  end
  L9_2 = Framework
  L9_2 = L9_2.sendNotification
  L10_2 = A0_2
  L11_2 = L8_2
  L12_2 = "success"
  L9_2(L10_2, L11_2, L12_2)
  L9_2 = StartClient
  L10_2 = A0_2
  L11_2 = "startSit"
  L12_2 = A3_2
  L13_2 = A4_2
  L14_2 = A5_2
  L15_2 = A1_2
  L9_2(L10_2, L11_2, L12_2, L13_2, L14_2, L15_2)
end
RegisterSeatPos = L0_1
function L0_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L3_2 = GetPlayerPed
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = GetEntityCoords
  L5_2 = L3_2
  L4_2 = L4_2(L5_2)
  L5_2 = L4_2 + A1_2
  L6_2 = L4_2 - L5_2
  L6_2 = #L6_2
  if L6_2 <= 2.0 then
    L7_2 = A2_2
    L8_2 = true
    L9_2 = L5_2
    L7_2(L8_2, L9_2)
  else
    L7_2 = A2_2
    L8_2 = false
    L7_2(L8_2)
  end
end
IsUserAtSeatPos = L0_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L0_2 = Config
  L0_2 = L0_2.Chairs
  L0_2 = L0_2.HealLayingPlayers
  if not L0_2 then
    return
  end
  L0_2 = dbg
  L0_2 = L0_2.debug
  L1_2 = "Starting healing player"
  L0_2(L1_2)
  while true do
    L0_2 = Wait
    L1_2 = 0
    L0_2(L1_2)
    L0_2 = next
    L1_2 = OccupiedChairs
    L0_2 = L0_2(L1_2)
    if not L0_2 then
    else
      L0_2 = pairs
      L1_2 = OccupiedChairs
      L0_2, L1_2, L2_2, L3_2 = L0_2(L1_2)
      for L4_2, L5_2 in L0_2, L1_2, L2_2, L3_2 do
        L6_2 = L5_2.seatType
        if "lay" == L6_2 then
          L6_2 = L5_2.user
          L7_2 = GetPlayerPed
          L8_2 = L6_2
          L7_2 = L7_2(L8_2)
          if L7_2 > 0 then
            L8_2 = GetEntityHealth
            L9_2 = L7_2
            L8_2 = L8_2(L9_2)
            if L8_2 then
              L9_2 = StartClient
              L10_2 = L6_2
              L11_2 = "healPlayer"
              L12_2 = Config
              L12_2 = L12_2.Chairs
              L12_2 = L12_2.HealModifier
              if not L12_2 then
                L12_2 = 1
              end
              L12_2 = L8_2 + L12_2
              L9_2(L10_2, L11_2, L12_2)
            end
          end
        end
      end
    end
    L0_2 = Wait
    L1_2 = Config
    L1_2 = L1_2.Chairs
    L1_2 = L1_2.HealLayingPlayersTimeCycle
    L1_2 = L1_2 * 60
    L1_2 = L1_2 * 1000
    L0_2(L1_2)
  end
end
L0_1(L1_1)
