local L0_1, L1_1
L0_1 = {}
SIntervals = L0_1
function L0_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2
  L4_2 = SIntervals
  L4_2 = L4_2[A0_2]
  if not L4_2 and A1_2 then
    L4_2 = SIntervals
    L4_2[A0_2] = A1_2
    L4_2 = CreateThread
    function L5_2()
      local L0_3, L1_3, L2_3
      while true do
        L0_3 = SIntervals
        L1_3 = A0_2
        L0_3 = L0_3[L1_3]
        if -1 == L0_3 then
          L1_3 = A3_2
          if L1_3 then
            L1_3 = A3_2
            L2_3 = A0_2
            L1_3(L2_3)
          end
          L1_3 = SIntervals
          L2_3 = A0_2
          L1_3[L2_3] = nil
          break
        end
        L1_3 = Wait
        L2_3 = L0_3
        L1_3(L2_3)
        L1_3 = A2_2
        L2_3 = L0_3
        L1_3(L2_3)
        L1_3 = SIntervals
        L2_3 = A0_2
        L1_3 = L1_3[L2_3]
        if -1 == L1_3 then
          L1_3 = A3_2
          if L1_3 then
            L1_3 = A3_2
            L2_3 = A0_2
            L1_3(L2_3)
          end
          L1_3 = SIntervals
          L2_3 = A0_2
          L1_3[L2_3] = nil
          break
        end
      end
    end
    L6_2 = "sv-lib-intervals code name: Phoenix"
    L4_2(L5_2, L6_2)
  elseif A1_2 then
    L4_2 = SIntervals
    L4_2[A0_2] = A1_2
  end
end
SetServerInterval = L0_1
function L0_1(A0_2)
  local L1_2, L2_2
  L1_2 = false
  L2_2 = SIntervals
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L1_2 = true
  end
  return L1_2
end
IsServerIntervalRunning = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = SIntervals
  L1_2 = L1_2[A0_2]
  if L1_2 then
    L1_2 = SIntervals
    L1_2[A0_2] = -1
    L1_2 = dbg
    L1_2 = L1_2.debug
    L2_2 = "Interval with ID %s was cleared."
    L3_2 = A0_2
    L1_2(L2_2, L3_2)
  end
end
ClearServerInterval = L0_1
