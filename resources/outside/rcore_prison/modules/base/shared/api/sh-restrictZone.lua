local L0_1, L1_1
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = false
  if not A1_2 then
    L3_2 = true
    return L3_2
  end
  L3_2 = Config
  L3_2 = L3_2.RestrictZones
  if L3_2 then
    L3_2 = Config
    L3_2 = L3_2.RestrictZones
    L3_2 = L3_2.Enable
    if not L3_2 then
      L3_2 = true
      return L3_2
    end
  end
  L3_2 = RestrictZone
  if L3_2 then
    L3_2 = next
    L4_2 = RestrictZone
    L3_2 = L3_2(L4_2)
    if L3_2 then
      L3_2 = RestrictZone
      L3_2 = L3_2.access
      if L3_2 then
        L4_2 = next
        L5_2 = L3_2
        L4_2 = L4_2(L5_2)
        if L4_2 then
          L4_2 = L3_2[A1_2]
          if L4_2 then
            L2_2 = true
            L4_2 = dbg
            L4_2 = L4_2.debug
            L5_2 = "Officer has access to this command: %s since in the zone"
            L6_2 = A1_2
            L4_2(L5_2, L6_2)
          end
        end
      end
  end
  else
    if A0_2 then
      L3_2 = Framework
      L3_2 = L3_2.sendNotification
      L4_2 = A0_2
      L5_2 = _U
      L6_2 = "RESTRICT_ZONE.NOT_IN_ZONE"
      L7_2 = A1_2
      L5_2 = L5_2(L6_2, L7_2)
      L6_2 = "error"
      L3_2(L4_2, L5_2, L6_2)
    end
    L3_2 = dbg
    L3_2 = L3_2.debug
    L4_2 = "Officer is not in zone when restrict zones are enabled when using command: %s"
    L5_2 = A1_2
    L3_2(L4_2, L5_2)
  end
  L3_2 = dbg
  L3_2 = L3_2.debug
  L4_2 = "Restriction zone for command: %s with state: %s"
  L5_2 = A1_2
  L6_2 = L2_2
  L3_2(L4_2, L5_2, L6_2)
  return L2_2
end
CheckRestrictionZone = L0_1
