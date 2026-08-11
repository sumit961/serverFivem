local L0_1, L1_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = NONE_RESOURCE
  if A0_2 == L1_2 then
    L1_2 = true
    return L1_2
  end
  if "null" == A0_2 or nil == A0_2 then
    L1_2 = dbg
    L1_2 = L1_2.critical
    L2_2 = "isResourceLoaded: Resource is not defined - received %s"
    L3_2 = A0_2
    L1_2(L2_2, L3_2)
    L1_2 = false
    return L1_2
  end
  L1_2 = GetResourceState
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = "started" == L1_2 or "starting" == L1_2
  return L2_2
end
isResourceLoaded = L0_1
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2
  L2_2 = {}
  L3_2 = {}
  L4_2 = {}
  L5_2 = 1
  L6_2 = "{\n"
  while true do
    L7_2 = 0
    L8_2 = pairs
    L9_2 = A0_2
    L8_2, L9_2, L10_2, L11_2 = L8_2(L9_2)
    for L12_2, L13_2 in L8_2, L9_2, L10_2, L11_2 do
      L7_2 = L7_2 + 1
    end
    L8_2 = 1
    L9_2 = pairs
    L10_2 = A0_2
    L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
    for L13_2, L14_2 in L9_2, L10_2, L11_2, L12_2 do
      L15_2 = L2_2[A0_2]
      if nil ~= L15_2 then
        L15_2 = L2_2[A0_2]
        if not (L8_2 >= L15_2) then
          goto lbl_176
        end
      end
      L15_2 = string
      L15_2 = L15_2.find
      L16_2 = L6_2
      L17_2 = "}"
      L19_2 = L6_2
      L18_2 = L6_2.len
      L18_2, L19_2, L20_2, L21_2 = L18_2(L19_2)
      L15_2 = L15_2(L16_2, L17_2, L18_2, L19_2, L20_2, L21_2)
      if L15_2 then
        L15_2 = L6_2
        L16_2 = ",\n"
        L15_2 = L15_2 .. L16_2
        L6_2 = L15_2
      else
        L15_2 = string
        L15_2 = L15_2.find
        L16_2 = L6_2
        L17_2 = "\n"
        L19_2 = L6_2
        L18_2 = L6_2.len
        L18_2, L19_2, L20_2, L21_2 = L18_2(L19_2)
        L15_2 = L15_2(L16_2, L17_2, L18_2, L19_2, L20_2, L21_2)
        if not L15_2 then
          L15_2 = L6_2
          L16_2 = "\n"
          L15_2 = L15_2 .. L16_2
          L6_2 = L15_2
        end
      end
      L15_2 = table
      L15_2 = L15_2.insert
      L16_2 = L4_2
      L17_2 = L6_2
      L15_2(L16_2, L17_2)
      L6_2 = ""
      L15_2 = nil
      L16_2 = type
      L17_2 = L13_2
      L16_2 = L16_2(L17_2)
      if "number" ~= L16_2 then
        L16_2 = type
        L17_2 = L13_2
        L16_2 = L16_2(L17_2)
        if "boolean" ~= L16_2 then
          goto lbl_82
        end
      end
      L16_2 = "["
      L17_2 = tostring
      L18_2 = L13_2
      L17_2 = L17_2(L18_2)
      L18_2 = "]"
      L16_2 = L16_2 .. L17_2 .. L18_2
      L15_2 = L16_2
      goto lbl_89
      ::lbl_82::
      L16_2 = "['"
      L17_2 = tostring
      L18_2 = L13_2
      L17_2 = L17_2(L18_2)
      L18_2 = "']"
      L16_2 = L16_2 .. L17_2 .. L18_2
      L15_2 = L16_2
      ::lbl_89::
      L16_2 = type
      L17_2 = L14_2
      L16_2 = L16_2(L17_2)
      if "number" ~= L16_2 then
        L16_2 = type
        L17_2 = L14_2
        L16_2 = L16_2(L17_2)
        if "boolean" ~= L16_2 then
          goto lbl_113
        end
      end
      L16_2 = L6_2
      L17_2 = string
      L17_2 = L17_2.rep
      L18_2 = "\t"
      L19_2 = L5_2
      L17_2 = L17_2(L18_2, L19_2)
      L18_2 = L15_2
      L19_2 = " = "
      L20_2 = tostring
      L21_2 = L14_2
      L20_2 = L20_2(L21_2)
      L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2 .. L20_2
      L6_2 = L16_2
      goto lbl_157
      ::lbl_113::
      L16_2 = type
      L17_2 = L14_2
      L16_2 = L16_2(L17_2)
      if "table" == L16_2 then
        L16_2 = L6_2
        L17_2 = string
        L17_2 = L17_2.rep
        L18_2 = "\t"
        L19_2 = L5_2
        L17_2 = L17_2(L18_2, L19_2)
        L18_2 = L15_2
        L19_2 = " = {\n"
        L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2
        L6_2 = L16_2
        L16_2 = table
        L16_2 = L16_2.insert
        L17_2 = L3_2
        L18_2 = A0_2
        L16_2(L17_2, L18_2)
        L16_2 = table
        L16_2 = L16_2.insert
        L17_2 = L3_2
        L18_2 = L14_2
        L16_2(L17_2, L18_2)
        L16_2 = L8_2 + 1
        L2_2[A0_2] = L16_2
        break
      else
        L16_2 = L6_2
        L17_2 = string
        L17_2 = L17_2.rep
        L18_2 = "\t"
        L19_2 = L5_2
        L17_2 = L17_2(L18_2, L19_2)
        L18_2 = L15_2
        L19_2 = " = '"
        L20_2 = tostring
        L21_2 = L14_2
        L20_2 = L20_2(L21_2)
        L21_2 = "'"
        L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2 .. L20_2 .. L21_2
        L6_2 = L16_2
      end
      ::lbl_157::
      if L8_2 == L7_2 then
        L16_2 = L6_2
        L17_2 = "\n"
        L18_2 = string
        L18_2 = L18_2.rep
        L19_2 = "\t"
        L20_2 = L5_2 - 1
        L18_2 = L18_2(L19_2, L20_2)
        L19_2 = "}"
        L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2
        L6_2 = L16_2
      else
        L16_2 = L6_2
        L17_2 = ","
        L16_2 = L16_2 .. L17_2
        L6_2 = L16_2
        goto lbl_189
        ::lbl_176::
        if L8_2 == L7_2 then
          L15_2 = L6_2
          L16_2 = "\n"
          L17_2 = string
          L17_2 = L17_2.rep
          L18_2 = "\t"
          L19_2 = L5_2 - 1
          L17_2 = L17_2(L18_2, L19_2)
          L18_2 = "}"
          L15_2 = L15_2 .. L16_2 .. L17_2 .. L18_2
          L6_2 = L15_2
        end
      end
      ::lbl_189::
      L8_2 = L8_2 + 1
    end
    if 0 == L7_2 then
      L9_2 = L6_2
      L10_2 = "\n"
      L11_2 = string
      L11_2 = L11_2.rep
      L12_2 = "\t"
      L13_2 = L5_2 - 1
      L11_2 = L11_2(L12_2, L13_2)
      L12_2 = "}"
      L9_2 = L9_2 .. L10_2 .. L11_2 .. L12_2
      L6_2 = L9_2
    end
    L9_2 = #L3_2
    if not (L9_2 > 0) then
      break
    end
    L9_2 = #L3_2
    A0_2 = L3_2[L9_2]
    L9_2 = #L3_2
    L3_2[L9_2] = nil
    L9_2 = L2_2[A0_2]
    if nil == L9_2 then
      L9_2 = L5_2 + 1
      if L9_2 then
        goto lbl_225
        L5_2 = L9_2 or L5_2
      end
    end
    L5_2 = L5_2 - 1
    goto lbl_225
    do break end
    ::lbl_225::
  end
  L7_2 = table
  L7_2 = L7_2.insert
  L8_2 = L4_2
  L9_2 = L6_2
  L7_2(L8_2, L9_2)
  L7_2 = table
  L7_2 = L7_2.concat
  L8_2 = L4_2
  L7_2 = L7_2(L8_2)
  L6_2 = L7_2
  if not A1_2 then
    L7_2 = print
    L8_2 = L6_2
    L7_2(L8_2)
  end
  return L6_2
end
dTable = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = print
  L2_2 = json
  L2_2 = L2_2.encode
  L3_2 = A0_2
  L4_2 = {}
  L4_2.indent = true
  L2_2, L3_2, L4_2 = L2_2(L3_2, L4_2)
  return L1_2(L2_2, L3_2, L4_2)
end
tprint = L0_1
function L0_1(A0_2, A1_2, ...)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = print
  L3_2 = string
  L3_2 = L3_2.format
  L4_2 = "%s %s"
  L5_2 = A1_2
  L7_2 = A0_2
  L6_2 = A0_2.format
  L8_2 = ...
  L6_2, L7_2, L8_2 = L6_2(L7_2, L8_2)
  L3_2, L4_2, L5_2, L6_2, L7_2, L8_2 = L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2)
end
afprint = L0_1
function L0_1(A0_2, A1_2, ...)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = print
  L3_2 = string
  L3_2 = L3_2.format
  L4_2 = "%s %s"
  L5_2 = A1_2
  L7_2 = A0_2
  L6_2 = A0_2.format
  L8_2 = ...
  L6_2, L7_2, L8_2 = L6_2(L7_2, L8_2)
  L3_2, L4_2, L5_2, L6_2, L7_2, L8_2 = L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2)
end
fprint = L0_1
function L0_1(A0_2, ...)
  local L1_2, L2_2, L3_2
  L1_2 = string
  L1_2 = L1_2.format
  L2_2 = A0_2
  L3_2 = ...
  return L1_2(L2_2, L3_2)
end
sprint = L0_1
function L0_1(A0_2, A1_2)
  local L2_2
  L2_2 = true
  return L2_2
end
isBridgeLoaded = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = A0_2 or nil
  if A0_2 then
    L2_2 = A0_2
    L1_2 = A0_2.match
    L3_2 = "^%d+$"
    L1_2 = L1_2(L2_2, L3_2)
    L1_2 = nil ~= L1_2
  end
  return L1_2
end
isNumber = L0_1
L0_1 = table
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = 0
  L2_2 = pairs
  L3_2 = A0_2
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L1_2 = L1_2 + 1
  end
  return L1_2
end
L0_1.len = L1_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = {}
  function L2_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3
    L1_3 = type
    L2_3 = A0_3
    L1_3 = L1_3(L2_3)
    if "table" ~= L1_3 then
      return A0_3
    else
      L1_3 = L1_2
      L1_3 = L1_3[A0_3]
      if L1_3 then
        L1_3 = L1_2
        L1_3 = L1_3[A0_3]
        return L1_3
      end
    end
    L1_3 = {}
    L2_3 = L1_2
    L2_3[A0_3] = L1_3
    L2_3 = pairs
    L3_3 = A0_3
    L2_3, L3_3, L4_3, L5_3 = L2_3(L3_3)
    for L6_3, L7_3 in L2_3, L3_3, L4_3, L5_3 do
      L8_3 = L2_2
      L9_3 = L6_3
      L8_3 = L8_3(L9_3)
      L9_3 = L2_2
      L10_3 = L7_3
      L9_3 = L9_3(L10_3)
      L1_3[L8_3] = L9_3
    end
    L2_3 = setmetatable
    L3_3 = L1_3
    L4_3 = getmetatable
    L5_3 = A0_3
    L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3 = L4_3(L5_3)
    return L2_3(L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3)
  end
  L3_2 = L2_2
  L4_2 = A0_2
  return L3_2(L4_2)
end
DeepCopy = L0_1
L0_1 = table
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L2_2 = DeepCopy
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = pairs
  L4_2 = A1_2
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
  for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
    L9_2 = type
    L10_2 = L8_2
    L9_2 = L9_2(L10_2)
    if "table" == L9_2 then
      L9_2 = type
      L10_2 = L2_2[L7_2]
      L9_2 = L9_2(L10_2)
      if "table" == L9_2 then
        L9_2 = table
        L9_2 = L9_2.merge
        L10_2 = L2_2[L7_2]
        L11_2 = L8_2
        L9_2 = L9_2(L10_2, L11_2)
        L2_2[L7_2] = L9_2
    end
    else
      L9_2 = DeepCopy
      L10_2 = L8_2
      L9_2 = L9_2(L10_2)
      L2_2[L7_2] = L9_2
    end
  end
  return L2_2
end
L0_1.merge = L1_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = tonumber
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = nil
  if L1_2 <= 0 then
    L2_2 = "00:00:00"
  else
    L3_2 = string
    L3_2 = L3_2.format
    L4_2 = "%02.f"
    L5_2 = math
    L5_2 = L5_2.floor
    L6_2 = L1_2 / 3600
    L5_2, L6_2, L7_2, L8_2, L9_2, L10_2 = L5_2(L6_2)
    L3_2 = L3_2(L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2)
    L4_2 = string
    L4_2 = L4_2.format
    L5_2 = "%02.f"
    L6_2 = math
    L6_2 = L6_2.floor
    L7_2 = L1_2 / 60
    L8_2 = L3_2 * 60
    L7_2 = L7_2 - L8_2
    L6_2, L7_2, L8_2, L9_2, L10_2 = L6_2(L7_2)
    L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2)
    L5_2 = string
    L5_2 = L5_2.format
    L6_2 = "%02.f"
    L7_2 = math
    L7_2 = L7_2.floor
    L8_2 = L3_2 * 3600
    L8_2 = L1_2 - L8_2
    L9_2 = L4_2 * 60
    L8_2 = L8_2 - L9_2
    L7_2, L8_2, L9_2, L10_2 = L7_2(L8_2)
    L5_2 = L5_2(L6_2, L7_2, L8_2, L9_2, L10_2)
    L6_2 = "%s:%s:%s"
    L7_2 = L6_2
    L6_2 = L6_2.format
    L8_2 = L3_2
    L9_2 = L4_2
    L10_2 = L5_2
    L6_2 = L6_2(L7_2, L8_2, L9_2, L10_2)
    L2_2 = L6_2
  end
  return L2_2
end
SecondsToClock = L0_1
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L2_2 = {}
  L3_2 = pairs
  L4_2 = A0_2
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
  for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
    L9_2 = table
    L9_2 = L9_2.insert
    L10_2 = L2_2
    L11_2 = string
    L11_2 = L11_2.format
    L12_2 = "^1%s.%s^7"
    L13_2 = A1_2
    L14_2 = L7_2
    L11_2, L12_2, L13_2, L14_2 = L11_2(L12_2, L13_2, L14_2)
    L9_2(L10_2, L11_2, L12_2, L13_2, L14_2)
  end
  L3_2 = table
  L3_2 = L3_2.concat
  L4_2 = L2_2
  L5_2 = ", "
  return L3_2(L4_2, L5_2)
end
formatPossible = L0_1
function L0_1(A0_2)
  local L1_2, L2_2
  if nil ~= A0_2 then
    L1_2 = type
    L2_2 = A0_2
    L1_2 = L1_2(L2_2)
    if "table" == L1_2 then
      L1_2 = true
      return L1_2
    end
    L1_2 = false
    return L1_2
  else
    L1_2 = false
    return L1_2
  end
end
isTable = L0_1
L0_1 = table
function L1_1(A0_2)
  local L1_2, L2_2
  L1_2 = isTable
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if L1_2 then
    L1_2 = next
    L2_2 = A0_2
    L1_2 = L1_2(L2_2)
    if nil == L1_2 then
      L1_2 = true
      return L1_2
    else
      L1_2 = false
      return L1_2
    end
  else
    L1_2 = true
    return L1_2
  end
end
L0_1.isEmpty = L1_1
L0_1 = table
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = 0
  L2_2 = pairs
  L3_2 = A0_2
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L1_2 = L1_2 + 1
  end
  return L1_2
end
L0_1.size = L1_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = false
  L2_2 = Config
  L2_2 = L2_2.DebugPlayerLoad
  if L2_2 then
    L2_2 = Config
    L3_2 = {}
    L4_2 = "PLAYER_LOAD"
    L3_2[1] = L4_2
    L2_2.DebugLevel = L3_2
  end
  L2_2 = Config
  L2_2 = L2_2.DebugLevel
  if L2_2 then
    L2_2 = isTable
    L3_2 = Config
    L3_2 = L3_2.DebugLevel
    L2_2 = L2_2(L3_2)
    if L2_2 then
      L2_2 = table
      L2_2 = L2_2.isEmpty
      L3_2 = Config
      L3_2 = L3_2.DebugLevel
      L2_2 = L2_2(L3_2)
      if not L2_2 then
        L2_2 = pairs
        L3_2 = Config
        L3_2 = L3_2.DebugLevel
        L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
        for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
          if L7_2 == A0_2 then
            L1_2 = true
          end
        end
    end
    else
      L2_2 = Config
      L2_2 = L2_2.DebugLevel
      if A0_2 == L2_2 then
        L1_2 = true
      end
    end
  end
  return L1_2
end
isDebugAllowed = L0_1
function L0_1()
  local L0_2, L1_2
  L0_2 = {}
  L0_2.prefix = "System"
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L1_3 = isDebugAllowed
    L2_3 = "INFO"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = print
      L2_3 = "^5["
      L3_3 = L0_2.prefix
      L4_3 = " | info] ^7"
      L5_3 = sprint
      L6_3 = A0_3
      L7_3 = ...
      L5_3 = L5_3(L6_3, L7_3)
      L2_3 = L2_3 .. L3_3 .. L4_3 .. L5_3
      L1_3(L2_3)
    end
  end
  L0_2.info = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = isDebugAllowed
    L2_3 = "INFO"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = print
      L2_3 = "^7"
      L3_3 = sprint
      L4_3 = A0_3
      L5_3 = ...
      L3_3 = L3_3(L4_3, L5_3)
      L2_3 = L2_3 .. L3_3
      L1_3(L2_3)
    end
  end
  L0_2.init = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L1_3 = isDebugAllowed
    L2_3 = "SUCCESS"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = print
      L2_3 = "^3["
      L3_3 = L0_2.prefix
      L4_3 = " | success] ^7"
      L5_3 = sprint
      L6_3 = A0_3
      L7_3 = ...
      L5_3 = L5_3(L6_3, L7_3)
      L2_3 = L2_3 .. L3_3 .. L4_3 .. L5_3
      L1_3(L2_3)
    end
  end
  L0_2.success = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L1_3 = isDebugAllowed
    L2_3 = "CRITICAL"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = print
      L2_3 = "^1["
      L3_3 = L0_2.prefix
      L4_3 = " | critical] ^7"
      L5_3 = sprint
      L6_3 = A0_3
      L7_3 = ...
      L5_3 = L5_3(L6_3, L7_3)
      L2_3 = L2_3 .. L3_3 .. L4_3 .. L5_3
      L1_3(L2_3)
    end
  end
  L0_2.critical = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L1_3 = isDebugAllowed
    L2_3 = "ERROR"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = print
      L2_3 = "^1["
      L3_3 = L0_2.prefix
      L4_3 = " | error] ^7"
      L5_3 = sprint
      L6_3 = A0_3
      L7_3 = ...
      L5_3 = L5_3(L6_3, L7_3)
      L2_3 = L2_3 .. L3_3 .. L4_3 .. L5_3
      L1_3(L2_3)
    end
  end
  L0_2.error = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L1_3 = isDebugAllowed
    L2_3 = "SECURITY"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = print
      L2_3 = "^3["
      L3_3 = L0_2.prefix
      L4_3 = " | security] ^7"
      L5_3 = sprint
      L6_3 = A0_3
      L7_3 = ...
      L5_3 = L5_3(L6_3, L7_3)
      L2_3 = L2_3 .. L3_3 .. L4_3 .. L5_3
      L1_3(L2_3)
    end
  end
  L0_2.security = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
    L1_3 = isDebugAllowed
    L2_3 = "SECURITY_SPAM"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = print
      L2_3 = "^3["
      L3_3 = L0_2.prefix
      L4_3 = " | security] ^7"
      L5_3 = sprint
      L6_3 = A0_3
      L7_3 = ...
      L5_3 = L5_3(L6_3, L7_3)
      L2_3 = L2_3 .. L3_3 .. L4_3 .. L5_3
      L1_3(L2_3)
    end
  end
  L0_2.securitySpam = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = Config
    L1_3 = L1_3.Debug
    if L1_3 then
      L1_3 = print
      L2_3 = "^4[BRIDGE] ^7"
      L3_3 = sprint
      L4_3 = A0_3
      L5_3 = ...
      L3_3 = L3_3(L4_3, L5_3)
      L2_3 = L2_3 .. L3_3
      L1_3(L2_3)
    end
  end
  L0_2.bridge = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = Config
    L1_3 = L1_3.DebugClothing
    if L1_3 then
      L1_3 = print
      L2_3 = "^2[ Clothing module ] | debug] ^7"
      L3_3 = sprint
      L4_3 = A0_3
      L5_3 = ...
      L3_3 = L3_3(L4_3, L5_3)
      L2_3 = L2_3 .. L3_3
      L1_3(L2_3)
    end
  end
  L0_2.debugClothing = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = isDebugAllowed
    L2_3 = "NETWORK"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = Config
      L1_3 = L1_3.Debug
      if L1_3 then
        L1_3 = print
        L2_3 = "^3[ Network | debug] ^7"
        L3_3 = sprint
        L4_3 = A0_3
        L5_3 = ...
        L3_3 = L3_3(L4_3, L5_3)
        L2_3 = L2_3 .. L3_3
        L1_3(L2_3)
      end
    end
  end
  L0_2.debugNetwork = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = Config
    L1_3 = L1_3.DebugAPI
    if L1_3 then
      L1_3 = print
      L2_3 = "^5[ API module ] | debug] ^7"
      L3_3 = sprint
      L4_3 = A0_3
      L5_3 = ...
      L3_3 = L3_3(L4_3, L5_3)
      L4_3 = [[

 ^3This debug message can be disabled in configs/config.lua - DebugAPI = false]]
      L2_3 = L2_3 .. L3_3 .. L4_3
      L1_3(L2_3)
    end
  end
  L0_2.debugAPI = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = Config
    L1_3 = L1_3.DebugInventory
    if L1_3 then
      L1_3 = print
      L2_3 = "^5[ Inventory module ] | debug] ^7"
      L3_3 = sprint
      L4_3 = A0_3
      L5_3 = ...
      L3_3 = L3_3(L4_3, L5_3)
      L2_3 = L2_3 .. L3_3
      L1_3(L2_3)
    end
  end
  L0_2.debugInventory = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = isDebugAllowed
    L2_3 = "DEBUG"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = Config
      L1_3 = L1_3.Debug
      if L1_3 then
        L1_3 = print
        L2_3 = "^3[ Debug ] ^7"
        L3_3 = sprint
        L4_3 = A0_3
        L5_3 = ...
        L3_3 = L3_3(L4_3, L5_3)
        L2_3 = L2_3 .. L3_3
        L1_3(L2_3)
      end
    end
  end
  L0_2.debug = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = isDebugAllowed
    L2_3 = "PLAYER_LOAD"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = Config
      L1_3 = L1_3.Debug
      if L1_3 then
        L1_3 = print
        L2_3 = "^5[ PLAYER LOAD ] ^7"
        L3_3 = sprint
        L4_3 = A0_3
        L5_3 = ...
        L3_3 = L3_3(L4_3, L5_3)
        L2_3 = L2_3 .. L3_3
        L1_3(L2_3)
      end
    end
  end
  L0_2.playerLoad = L1_2
  function L1_2(A0_3, ...)
    local L1_3, L2_3, L3_3, L4_3, L5_3
    L1_3 = isDebugAllowed
    L2_3 = "MENU"
    L1_3 = L1_3(L2_3)
    if L1_3 then
      L1_3 = Config
      L1_3 = L1_3.Debug
      if L1_3 then
        L1_3 = print
        L2_3 = "^3[ Menu ] ^7"
        L3_3 = sprint
        L4_3 = A0_3
        L5_3 = ...
        L3_3 = L3_3(L4_3, L5_3)
        L2_3 = L2_3 .. L3_3
        L1_3(L2_3)
      end
    end
  end
  L0_2.menu = L1_2
  function L1_2(A0_3)
    local L1_3
    L0_2.prefix = A0_3
  end
  L0_2.setupPrefix = L1_2
  function L1_2()
    local L0_3, L1_3
    L0_3 = L0_2.prefix
    return L0_3
  end
  L0_2.getPrefix = L1_2
  return L0_2
end
rdebug = L0_1
function L0_1(A0_2, ...)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = rdebug
  L1_2 = L1_2()
  L2_2 = L1_2.info
  L3_2 = A0_2
  L4_2 = ...
  L2_2(L3_2, L4_2)
end
dprint = L0_1
function L0_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2
  L4_2 = Intervals
  L4_2 = L4_2[A0_2]
  if not L4_2 and A1_2 then
    L4_2 = collectgarbage
    L5_2 = "collect"
    L4_2(L5_2)
    L4_2 = Intervals
    L4_2[A0_2] = A1_2
    L4_2 = CreateThread
    function L5_2()
      local L0_3, L1_3, L2_3
      repeat
        L0_3 = Intervals
        L1_3 = A0_2
        L0_3 = L0_3[L1_3]
        L1_3 = Wait
        L2_3 = L0_3
        L1_3(L2_3)
        L1_3 = A2_2
        L2_3 = L0_3
        L1_3(L2_3)
      until -1 == L0_3
      L1_3 = A3_2
      if L1_3 then
        L1_3 = A3_2
        L1_3 = L1_3()
        if not L1_3 then
        end
      end
      L0_3 = Intervals
      L1_3 = A0_2
      L0_3[L1_3] = nil
    end
    L6_2 = "sh-utils code name: Phoenix"
    L4_2(L5_2, L6_2)
  elseif A1_2 then
    L4_2 = Intervals
    L4_2[A0_2] = A1_2
  end
end
SetCycle = L0_1
function L0_1(A0_2)
  local L1_2, L2_2
  L1_2 = false
  L2_2 = Intervals
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L1_2 = true
  end
  return L1_2
end
IsIntervalRunning = L0_1
function L0_1(A0_2)
  local L1_2
  L1_2 = Intervals
  L1_2[A0_2] = -1
end
ClearCycle = L0_1
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2
  L2_2 = nil
  L3_2 = nil
  L4_2 = ipairs
  L5_2 = A0_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = L9_2.x
    L11_2 = L9_2.y
    L12_2 = L9_2.z
    L13_2 = vector3
    L14_2 = L10_2
    L15_2 = L11_2
    L16_2 = L12_2
    L13_2 = L13_2(L14_2, L15_2, L16_2)
    if L2_2 then
      L14_2 = DrawLine
      L15_2 = L2_2
      L16_2 = L13_2
      L17_2 = 255
      L18_2 = 0
      L19_2 = 0
      L20_2 = 255
      L14_2(L15_2, L16_2, L17_2, L18_2, L19_2, L20_2)
      L14_2 = Draw3DText
      L15_2 = L13_2.x
      L16_2 = L13_2.y
      L17_2 = L13_2.z
      L18_2 = tostring
      L19_2 = L8_2
      L18_2 = L18_2(L19_2)
      L19_2 = "\n"
      L20_2 = L9_2
      L18_2 = L18_2 .. L19_2 .. L20_2
      L19_2 = 255
      L20_2 = 0
      L21_2 = 0
      L22_2 = 255
      L14_2(L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2)
    else
      L3_2 = L13_2
    end
    L2_2 = L13_2
    L14_2 = #A0_2
    if L8_2 == L14_2 then
      L14_2 = DrawLine
      L15_2 = L2_2
      L16_2 = L3_2
      L17_2 = 255
      L18_2 = 0
      L19_2 = 0
      L20_2 = 255
      L14_2(L15_2, L16_2, L17_2, L18_2, L19_2, L20_2)
      L14_2 = Draw3DText
      L15_2 = L3_2.x
      L16_2 = L3_2.y
      L17_2 = L3_2.z
      L18_2 = tostring
      L19_2 = #A0_2
      L18_2 = L18_2(L19_2)
      L19_2 = "\n"
      L20_2 = L3_2
      L18_2 = L18_2 .. L19_2 .. L20_2
      L19_2 = 255
      L20_2 = 0
      L21_2 = 0
      L22_2 = 255
      L14_2(L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2)
    end
  end
end
DrawDebugPolyZone = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = "./images/menu/"
  L2_2 = A0_2
  L3_2 = ".png"
  L1_2 = L1_2 .. L2_2 .. L3_2
  return L1_2
end
GetImageByName = L0_1
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  if not A0_2 then
    L2_2 = true
    return L2_2
  end
  L2_2 = A0_2.x
  if 0.0 == L2_2 then
    L2_2 = A0_2.y
    if 0.0 == L2_2 then
      L2_2 = true
      return L2_2
    end
  end
  L2_2 = #A1_2
  L3_2 = false
  L4_2 = 1
  L5_2 = L2_2
  L6_2 = 1
  for L7_2 = L4_2, L5_2, L6_2 do
    L8_2 = A1_2[L7_2]
    L9_2 = L7_2 % L2_2
    L9_2 = L9_2 + 1
    L9_2 = A1_2[L9_2]
    L10_2 = L8_2.y
    L11_2 = A0_2.y
    L10_2 = L10_2 > L11_2
    L11_2 = L9_2.y
    L12_2 = A0_2.y
    L11_2 = L11_2 > L12_2
    if L10_2 ~= L11_2 then
      L10_2 = A0_2.x
      L11_2 = L9_2.x
      L12_2 = L8_2.x
      L11_2 = L11_2 - L12_2
      L12_2 = A0_2.y
      L13_2 = L8_2.y
      L12_2 = L12_2 - L13_2
      L11_2 = L11_2 * L12_2
      L12_2 = L9_2.y
      L13_2 = L8_2.y
      L12_2 = L12_2 - L13_2
      L11_2 = L11_2 / L12_2
      L12_2 = L8_2.x
      L11_2 = L11_2 + L12_2
      if L10_2 < L11_2 then
        L3_2 = not L3_2
      end
    end
  end
  return L3_2
end
IsPointInPolygon = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L1_2 = 0
  L2_2 = 0
  L3_2 = 0
  L4_2 = #A0_2
  L5_2 = ipairs
  L6_2 = A0_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = L10_2.x
    L1_2 = L1_2 + L11_2
    L11_2 = L10_2.y
    L2_2 = L2_2 + L11_2
    L11_2 = L10_2.z
    L3_2 = L3_2 + L11_2
  end
  L5_2 = vector3
  L6_2 = L1_2 / L4_2
  L7_2 = L2_2 / L4_2
  L8_2 = L3_2 / L4_2
  return L5_2(L6_2, L7_2, L8_2)
end
CalculateCentroid = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = pairs
  L2_2 = A0_2
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = print
    L8_2 = "^3"
    L9_2 = L6_2.name
    L10_2 = "^7"
    L8_2 = L8_2 .. L9_2 .. L10_2
    L7_2(L8_2)
    L7_2 = L6_2.version
    if L7_2 then
      L7_2 = print
      L8_2 = "^7version: ^3"
      L9_2 = L6_2.version
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.database
    if L7_2 then
      L7_2 = print
      L8_2 = "^7database: ^3"
      L9_2 = L6_2.database
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.debug
    if L7_2 then
      L7_2 = print
      L8_2 = "^7debug: ^3"
      L9_2 = L6_2.debug
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.locale
    if L7_2 then
      L7_2 = print
      L8_2 = "^7locale: ^3"
      L9_2 = L6_2.locale
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.preset
    if L7_2 then
      L7_2 = print
      L8_2 = "^7map: ^3"
      L9_2 = L6_2.preset
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.notify
    if L7_2 then
      L7_2 = print
      L8_2 = "^7notify: ^3"
      L9_2 = L6_2.notify
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.inventory
    if L7_2 then
      L7_2 = L6_2.inventory
      if "auto_detect" == L7_2 then
        L6_2.inventory = "none"
      end
      L7_2 = print
      L8_2 = "^7inventory: ^3"
      L9_2 = L6_2.inventory
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.dispatch
    if L7_2 then
      L7_2 = print
      L8_2 = "^7dispatch: ^3"
      L9_2 = L6_2.dispatch
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.clothing
    if L7_2 then
      L7_2 = print
      L8_2 = "^7clothing: ^3"
      L9_2 = L6_2.clothing
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.framework
    if L7_2 then
      L7_2 = print
      L8_2 = "^7framework: ^3"
      L9_2 = L6_2.framework
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.jailTime
    if L7_2 then
      L7_2 = print
      L8_2 = "^7jail time conversion: ^3"
      L9_2 = L6_2.jailTime
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.phone
    if L7_2 then
      L7_2 = print
      L8_2 = "^7phone: ^3"
      L9_2 = L6_2.phone
      if "auto_detect" == L9_2 then
        L9_2 = "Not any supported phone loaded"
        if L9_2 then
          goto lbl_115
        end
      end
      L9_2 = L6_2.phone
      ::lbl_115::
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.economy
    if L7_2 then
      L7_2 = print
      L8_2 = "^7economy item: ^3"
      L9_2 = L6_2.economy
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
    L7_2 = L6_2.docs
    if L7_2 then
      L7_2 = print
      L8_2 = [[

^7Docs: ^3 ]]
      L9_2 = L6_2.docs
      L8_2 = L8_2 .. L9_2
      L7_2(L8_2)
    end
  end
end
printResource = L0_1
function L0_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = {}
  L1_2 = {}
  L2_2 = GetCurrentResourceName
  L2_2 = L2_2()
  L1_2.name = L2_2
  L2_2 = GetResourceMetadata
  L3_2 = GetCurrentResourceName
  L3_2 = L3_2()
  L4_2 = "version"
  L5_2 = 0
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L1_2.version = L2_2
  L2_2 = SH
  L2_2 = L2_2.preset
  L1_2.preset = L2_2
  L2_2 = Bridge
  L2_2 = L2_2.SQL
  L1_2.database = L2_2
  L2_2 = Config
  L2_2 = L2_2.Locale
  L1_2.locale = L2_2
  L2_2 = Config
  L2_2 = L2_2.Framework
  L1_2.framework = L2_2
  L2_2 = Config
  L2_2 = L2_2.Time
  L1_2.jailTime = L2_2
  L2_2 = Bridge
  L2_2 = L2_2.Phone
  L1_2.phone = L2_2
  L2_2 = Bridge
  L2_2 = L2_2.Dispatch
  L1_2.dispatch = L2_2
  L2_2 = tostring
  L3_2 = Config
  L3_2 = L3_2.Debug
  L2_2 = L2_2(L3_2)
  L1_2.debug = L2_2
  L2_2 = Bridge
  L2_2 = L2_2.Clothing
  L1_2.clothing = L2_2
  L2_2 = Config
  L2_2 = L2_2.Inventories
  L1_2.inventory = L2_2
  L2_2 = Config
  L2_2 = L2_2.Framework
  L1_2.notify = L2_2
  L2_2 = Config
  L2_2 = L2_2.EconomyItem
  L1_2.economy = L2_2
  L2_2 = "%s/%s"
  L3_2 = L2_2
  L2_2 = L2_2.format
  L4_2 = "https://documentation.rcore.cz/paid-resources"
  L5_2 = GetCurrentResourceName
  L5_2 = L5_2()
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L1_2.docs = L2_2
  L0_2[1] = L1_2
  L1_2 = printResource
  L2_2 = L0_2
  L1_2(L2_2)
end
renderResourceInfo = L0_1
function L0_1()
  local L0_2, L1_2
  L0_2 = Config
  L0_2 = L0_2.ReduceSentenceType
  return L0_2
end
GetReducingTimeType = L0_1
L0_1 = IsDuplicityVersion
L0_1 = L0_1()
if L0_1 then
  function L0_1(A0_2, A1_2, ...)
    local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
    L2_2 = GetCurrentResourceName
    L2_2 = L2_2()
    if not A1_2 then
      L3_2 = dbg
      L3_2 = L3_2.critical
      L4_2 = "Invalid event name for %s"
      L5_2 = L2_2
      return L3_2(L4_2, L5_2)
    end
    L3_2 = "%s:%s"
    L4_2 = L3_2
    L3_2 = L3_2.format
    L5_2 = L2_2
    L6_2 = "client:"
    L7_2 = A1_2
    L6_2 = L6_2 .. L7_2
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    if not L3_2 then
      return
    end
    L4_2 = nil
    if -1 == A0_2 then
      L4_2 = "ALL PLAYERS"
    else
      L5_2 = GetPlayerName
      L6_2 = A0_2
      L5_2 = L5_2(L6_2)
      L4_2 = L5_2
    end
    if nil == L4_2 then
      L4_2 = ""
    end
    L5_2 = dbg
    L5_2 = L5_2.debugNetwork
    L6_2 = "Starting client with %s for user %s | Target: %s"
    L7_2 = A1_2
    L8_2 = L4_2
    L9_2 = A0_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
    L5_2 = 1000000
    L6_2 = TriggerLatentClientEvent
    L7_2 = L3_2
    L8_2 = A0_2
    L9_2 = L5_2
    L10_2 = ...
    L6_2(L7_2, L8_2, L9_2, L10_2)
  end
  StartClient = L0_1
else
  function L0_1(A0_2, A1_2, A2_2, A3_2, A4_2)
    local L5_2, L6_2, L7_2, L8_2, L9_2
    if nil == A4_2 then
      A4_2 = "keyboard"
    end
    L5_2 = dbg
    L5_2 = L5_2.debug
    L6_2 = "Registering key %s %s %s"
    L7_2 = A3_2
    L8_2 = A1_2
    L9_2 = A2_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
    L5_2 = RegisterCommand
    L6_2 = A1_2
    L7_2 = A3_2
    L6_2 = L6_2 .. L7_2
    L7_2 = A0_2
    L8_2 = false
    L5_2(L6_2, L7_2, L8_2)
    L5_2 = RegisterKeyMapping
    L6_2 = A1_2
    L7_2 = A3_2
    L6_2 = L6_2 .. L7_2
    L7_2 = "PRISON:"
    L8_2 = " "
    L9_2 = A2_2
    L7_2 = L7_2 .. L8_2 .. L9_2
    L8_2 = A4_2
    L9_2 = A3_2
    L5_2(L6_2, L7_2, L8_2, L9_2)
  end
  RegisterKey = L0_1
  function L0_1(A0_2)
    local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
    L1_2 = GetWorldCoordFromScreenCoord
    L2_2 = 0.5
    L3_2 = 0.5
    L1_2, L2_2 = L1_2(L2_2, L3_2)
    L3_2 = L2_2 * 10
    L3_2 = L1_2 + L3_2
    L4_2 = StartShapeTestLosProbe
    L5_2 = L1_2.x
    L6_2 = L1_2.y
    L7_2 = L1_2.z
    L8_2 = L3_2.x
    L9_2 = L3_2.y
    L10_2 = L3_2.z
    L11_2 = A0_2
    L12_2 = PlayerPedId
    L12_2 = L12_2()
    L13_2 = 4
    L4_2 = L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
    while true do
      L5_2 = Wait
      L6_2 = 0
      L5_2(L6_2)
      L5_2 = GetShapeTestResultIncludingMaterial
      L6_2 = L4_2
      L5_2, L6_2, L7_2, L8_2, L9_2, L10_2 = L5_2(L6_2)
      if 1 ~= L5_2 then
        L11_2 = L6_2
        L12_2 = L10_2
        L13_2 = L7_2
        L14_2 = L8_2
        L15_2 = L9_2
        return L11_2, L12_2, L13_2, L14_2, L15_2
      end
    end
  end
  RaycastFromCamera = L0_1
end
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2
  L2_2 = {}
  L3_2 = {}
  L4_2 = {}
  L5_2 = 1
  L6_2 = "{\n"
  while true do
    L7_2 = 0
    L8_2 = pairs
    L9_2 = A0_2
    L8_2, L9_2, L10_2, L11_2 = L8_2(L9_2)
    for L12_2, L13_2 in L8_2, L9_2, L10_2, L11_2 do
      L7_2 = L7_2 + 1
    end
    L8_2 = 1
    L9_2 = pairs
    L10_2 = A0_2
    L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
    for L13_2, L14_2 in L9_2, L10_2, L11_2, L12_2 do
      L15_2 = L2_2[A0_2]
      if nil ~= L15_2 then
        L15_2 = L2_2[A0_2]
        if not (L8_2 >= L15_2) then
          goto lbl_211
        end
      end
      L15_2 = string
      L15_2 = L15_2.find
      L16_2 = L6_2
      L17_2 = "}"
      L19_2 = L6_2
      L18_2 = L6_2.len
      L18_2, L19_2, L20_2, L21_2 = L18_2(L19_2)
      L15_2 = L15_2(L16_2, L17_2, L18_2, L19_2, L20_2, L21_2)
      if L15_2 then
        L15_2 = L6_2
        L16_2 = ",\n"
        L15_2 = L15_2 .. L16_2
        L6_2 = L15_2
      else
        L15_2 = string
        L15_2 = L15_2.find
        L16_2 = L6_2
        L17_2 = "\n"
        L19_2 = L6_2
        L18_2 = L6_2.len
        L18_2, L19_2, L20_2, L21_2 = L18_2(L19_2)
        L15_2 = L15_2(L16_2, L17_2, L18_2, L19_2, L20_2, L21_2)
        if not L15_2 then
          L15_2 = L6_2
          L16_2 = "\n"
          L15_2 = L15_2 .. L16_2
          L6_2 = L15_2
        end
      end
      L15_2 = table
      L15_2 = L15_2.insert
      L16_2 = L4_2
      L17_2 = L6_2
      L15_2(L16_2, L17_2)
      L6_2 = ""
      L15_2 = nil
      L16_2 = type
      L17_2 = L13_2
      L16_2 = L16_2(L17_2)
      if "number" ~= L16_2 then
        L16_2 = type
        L17_2 = L13_2
        L16_2 = L16_2(L17_2)
        if "boolean" ~= L16_2 then
          goto lbl_82
        end
      end
      L16_2 = ""
      L17_2 = tostring
      L18_2 = L13_2
      L17_2 = L17_2(L18_2)
      L18_2 = ""
      L16_2 = L16_2 .. L17_2 .. L18_2
      L15_2 = L16_2
      goto lbl_89
      ::lbl_82::
      L16_2 = ""
      L17_2 = tostring
      L18_2 = L13_2
      L17_2 = L17_2(L18_2)
      L18_2 = ""
      L16_2 = L16_2 .. L17_2 .. L18_2
      L15_2 = L16_2
      ::lbl_89::
      L16_2 = type
      L17_2 = L14_2
      L16_2 = L16_2(L17_2)
      if "number" ~= L16_2 then
        L16_2 = type
        L17_2 = L14_2
        L16_2 = L16_2(L17_2)
        if "boolean" ~= L16_2 then
          goto lbl_113
        end
      end
      L16_2 = L6_2
      L17_2 = string
      L17_2 = L17_2.rep
      L18_2 = "\t"
      L19_2 = L5_2
      L17_2 = L17_2(L18_2, L19_2)
      L18_2 = L15_2
      L19_2 = " = "
      L20_2 = tostring
      L21_2 = L14_2
      L20_2 = L20_2(L21_2)
      L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2 .. L20_2
      L6_2 = L16_2
      goto lbl_192
      ::lbl_113::
      L16_2 = type
      L17_2 = L14_2
      L16_2 = L16_2(L17_2)
      if "table" == L16_2 then
        L16_2 = type
        L17_2 = L13_2
        L16_2 = L16_2(L17_2)
        if "number" == L16_2 then
          L16_2 = L6_2
          L17_2 = string
          L17_2 = L17_2.rep
          L18_2 = "\t"
          L19_2 = L5_2
          L17_2 = L17_2(L18_2, L19_2)
          L18_2 = "{\n"
          L16_2 = L16_2 .. L17_2 .. L18_2
          L6_2 = L16_2
        else
          L16_2 = L6_2
          L17_2 = string
          L17_2 = L17_2.rep
          L18_2 = "\t"
          L19_2 = L5_2
          L17_2 = L17_2(L18_2, L19_2)
          L18_2 = L15_2
          L19_2 = " = {\n"
          L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2
          L6_2 = L16_2
        end
        L16_2 = table
        L16_2 = L16_2.insert
        L17_2 = L3_2
        L18_2 = A0_2
        L16_2(L17_2, L18_2)
        L16_2 = table
        L16_2 = L16_2.insert
        L17_2 = L3_2
        L18_2 = L14_2
        L16_2(L17_2, L18_2)
        L16_2 = L8_2 + 1
        L2_2[A0_2] = L16_2
        break
      else
        L16_2 = type
        L17_2 = L14_2
        L16_2 = L16_2(L17_2)
        if "vector3" == L16_2 then
          L16_2 = L6_2
          L17_2 = string
          L17_2 = L17_2.rep
          L18_2 = "\t"
          L19_2 = L5_2
          L17_2 = L17_2(L18_2, L19_2)
          L18_2 = L15_2
          L19_2 = " = "
          L20_2 = tostring
          L21_2 = L14_2
          L20_2 = L20_2(L21_2)
          L21_2 = ""
          L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2 .. L20_2 .. L21_2
          L6_2 = L16_2
        else
          L16_2 = L6_2
          L17_2 = string
          L17_2 = L17_2.rep
          L18_2 = "\t"
          L19_2 = L5_2
          L17_2 = L17_2(L18_2, L19_2)
          L18_2 = L15_2
          L19_2 = " = '"
          L20_2 = tostring
          L21_2 = L14_2
          L20_2 = L20_2(L21_2)
          L21_2 = "'"
          L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2 .. L20_2 .. L21_2
          L6_2 = L16_2
        end
      end
      ::lbl_192::
      if L8_2 == L7_2 then
        L16_2 = L6_2
        L17_2 = "\n"
        L18_2 = string
        L18_2 = L18_2.rep
        L19_2 = "\t"
        L20_2 = L5_2 - 1
        L18_2 = L18_2(L19_2, L20_2)
        L19_2 = "}"
        L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2
        L6_2 = L16_2
      else
        L16_2 = L6_2
        L17_2 = ","
        L16_2 = L16_2 .. L17_2
        L6_2 = L16_2
        goto lbl_224
        ::lbl_211::
        if L8_2 == L7_2 then
          L15_2 = L6_2
          L16_2 = "\n"
          L17_2 = string
          L17_2 = L17_2.rep
          L18_2 = "\t"
          L19_2 = L5_2 - 1
          L17_2 = L17_2(L18_2, L19_2)
          L18_2 = "}"
          L15_2 = L15_2 .. L16_2 .. L17_2 .. L18_2
          L6_2 = L15_2
        end
      end
      ::lbl_224::
      L8_2 = L8_2 + 1
    end
    if 0 == L7_2 then
      L9_2 = L6_2
      L10_2 = "\n"
      L11_2 = string
      L11_2 = L11_2.rep
      L12_2 = "\t"
      L13_2 = L5_2 - 1
      L11_2 = L11_2(L12_2, L13_2)
      L12_2 = ""
      L9_2 = L9_2 .. L10_2 .. L11_2 .. L12_2
      L6_2 = L9_2
    end
    L9_2 = #L3_2
    if not (L9_2 > 0) then
      break
    end
    L9_2 = #L3_2
    A0_2 = L3_2[L9_2]
    L9_2 = #L3_2
    L3_2[L9_2] = nil
    L9_2 = L2_2[A0_2]
    if nil == L9_2 then
      L9_2 = L5_2 + 1
      if L9_2 then
        goto lbl_260
        L5_2 = L9_2 or L5_2
      end
    end
    L5_2 = L5_2 - 1
    goto lbl_260
    do break end
    ::lbl_260::
  end
  L7_2 = table
  L7_2 = L7_2.insert
  L8_2 = L4_2
  L9_2 = L6_2
  L7_2(L8_2, L9_2)
  L7_2 = table
  L7_2 = L7_2.concat
  L8_2 = L4_2
  L7_2 = L7_2(L8_2)
  L6_2 = L7_2
  if not A1_2 then
  end
  return L6_2
end
dumpTable = L0_1
