local L0_1, L1_1
L0_1 = Locales
if not L0_1 then
  L0_1 = {}
end
Locales = L0_1
function L0_1(A0_2, ...)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = Config
  if L1_2 then
    L1_2 = Config
    L1_2 = L1_2.Locale
    if L1_2 then
      goto lbl_15
    end
  end
  L1_2 = dbg
  L1_2 = L1_2.critical
  L2_2 = "Cannot find Locale in the config"
  L1_2(L2_2)
  L1_2 = "not_found_config"
  do return L1_2 end
  ::lbl_15::
  L1_2 = Locales
  L2_2 = Config
  L2_2 = L2_2.Locale
  L1_2 = L1_2[L2_2]
  if not L1_2 then
    L1_2 = dbg
    L1_2 = L1_2.critical
    L2_2 = "Cannot find locale %s"
    L3_2 = Config
    L3_2 = L3_2.Locale
    L1_2(L2_2, L3_2)
    L1_2 = "not_found_locale"
    return L1_2
  end
  L1_2 = string
  L1_2 = L1_2.find
  L2_2 = A0_2
  L3_2 = "."
  L4_2 = 1
  L5_2 = true
  L1_2 = L1_2(L2_2, L3_2, L4_2, L5_2)
  if L1_2 then
    L3_2 = A0_2
    L2_2 = A0_2.match
    L4_2 = "([^%.]+)%.([^%.]+)"
    L2_2, L3_2 = L2_2(L3_2, L4_2)
    L4_2 = Locales
    L5_2 = Config
    L5_2 = L5_2.Locale
    L4_2 = L4_2[L5_2]
    L4_2 = L4_2[L2_2]
    if not L4_2 then
      L4_2 = dbg
      L4_2 = L4_2.critical
      L5_2 = "Cannot find locale category %s for string %s in locale %s"
      L6_2 = L2_2
      L7_2 = L3_2
      L8_2 = Config
      L8_2 = L8_2.Locale
      L4_2(L5_2, L6_2, L7_2, L8_2)
      return A0_2
    end
    L4_2 = Locales
    L5_2 = Config
    L5_2 = L5_2.Locale
    L4_2 = L4_2[L5_2]
    L4_2 = L4_2[L2_2]
    L4_2 = L4_2[L3_2]
    if not L4_2 then
      L4_2 = dbg
      L4_2 = L4_2.critical
      L5_2 = "Cannot find locale string %s in category %s in locale %s"
      L6_2 = L3_2
      L7_2 = L2_2
      L8_2 = Config
      L8_2 = L8_2.Locale
      L4_2(L5_2, L6_2, L7_2, L8_2)
      return A0_2
    end
    L4_2 = string
    L4_2 = L4_2.format
    L5_2 = Locales
    L6_2 = Config
    L6_2 = L6_2.Locale
    L5_2 = L5_2[L6_2]
    L5_2 = L5_2[L2_2]
    L5_2 = L5_2[L3_2]
    L6_2, L7_2, L8_2 = ...
    return L4_2(L5_2, L6_2, L7_2, L8_2)
  end
  L2_2 = Locales
  L3_2 = Config
  L3_2 = L3_2.Locale
  L2_2 = L2_2[L3_2]
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = dbg
    L2_2 = L2_2.critical
    L3_2 = "Cannot find locale string %s in locale %s"
    L4_2 = A0_2
    L5_2 = Config
    L5_2 = L5_2.Locale
    L2_2(L3_2, L4_2, L5_2)
    return A0_2
  end
  L2_2 = string
  L2_2 = L2_2.format
  L3_2 = Locales
  L4_2 = Config
  L4_2 = L4_2.Locale
  L3_2 = L3_2[L4_2]
  L3_2 = L3_2[A0_2]
  L4_2, L5_2, L6_2, L7_2, L8_2 = ...
  return L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2)
end
_U = L0_1
