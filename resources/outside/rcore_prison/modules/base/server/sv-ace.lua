local L0_1, L1_1, L2_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2
  L0_2 = true
  L1_2 = pairs
  L2_2 = PermissionMap
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    if not L0_2 then
      break
    end
    L7_2 = pairs
    L8_2 = L6_2
    L7_2, L8_2, L9_2, L10_2 = L7_2(L8_2)
    for L11_2, L12_2 in L7_2, L8_2, L9_2, L10_2 do
      L13_2 = Ace
      L13_2 = L13_2.Allow
      L14_2 = L5_2
      L15_2 = L12_2
      L13_2(L14_2, L15_2)
      L13_2 = Ace
      L13_2 = L13_2.CanGroup
      L14_2 = L5_2
      L15_2 = L12_2
      L13_2 = L13_2(L14_2, L15_2)
      L0_2 = L13_2
      if not L0_2 then
        L13_2 = 1
        L14_2 = 5
        L15_2 = 1
        for L16_2 = L13_2, L14_2, L15_2 do
          L17_2 = print
          L18_2 = string
          L18_2 = L18_2.format
          L19_2 = "^1Ace Permissions failed! You probably forgot to add add_ace to server.cfg"
          L18_2, L19_2 = L18_2(L19_2)
          L17_2(L18_2, L19_2)
        end
        L13_2 = print
        L14_2 = string
        L14_2 = L14_2.format
        L15_2 = "^2Please go to this page for resolve guide -> ^3https://documentation.rcore.cz/paid-resources/rcore_prison/installation^7"
        L14_2, L15_2, L16_2, L17_2, L18_2, L19_2 = L14_2(L15_2)
        L13_2(L14_2, L15_2, L16_2, L17_2, L18_2, L19_2)
        break
      end
    end
  end
end
L2_1 = "sv-ace code name: Phoenix"
L0_1(L1_1, L2_1)
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = string
  L1_2 = L1_2.format
  L2_2 = "%s_%s"
  L3_2 = GetCurrentResourceName
  L3_2 = L3_2()
  L4_2 = A0_2
  return L1_2(L2_2, L3_2, L4_2)
end
L1_1 = {}
Ace = L1_1
L1_1 = Ace
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = ExecuteCommand
  L3_2 = string
  L3_2 = L3_2.format
  L4_2 = "add_principal %s %s"
  L5_2 = A0_2
  L6_2 = A1_2
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2, L5_2, L6_2)
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
L1_1.AddPrincipal = L2_1
L1_1 = Ace
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = ExecuteCommand
  L3_2 = string
  L3_2 = L3_2.format
  L4_2 = "remove_principal %s %s"
  L5_2 = A0_2
  L6_2 = A1_2
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2, L5_2, L6_2)
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
L1_1.RemovePrincipal = L2_1
L1_1 = Ace
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = ExecuteCommand
  L3_2 = string
  L3_2 = L3_2.format
  L4_2 = "add_ace %s %s allow"
  L5_2 = A0_2
  L6_2 = L0_1
  L7_2 = A1_2
  L6_2, L7_2 = L6_2(L7_2)
  L3_2, L4_2, L5_2, L6_2, L7_2 = L3_2(L4_2, L5_2, L6_2, L7_2)
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2)
end
L1_1.Allow = L2_1
L1_1 = Ace
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = ExecuteCommand
  L3_2 = string
  L3_2 = L3_2.format
  L4_2 = "add_ace %s %s deny"
  L5_2 = A0_2
  L6_2 = L0_1
  L7_2 = A1_2
  L6_2, L7_2 = L6_2(L7_2)
  L3_2, L4_2, L5_2, L6_2, L7_2 = L3_2(L4_2, L5_2, L6_2, L7_2)
  L2_2(L3_2, L4_2, L5_2, L6_2, L7_2)
end
L1_1.Deny = L2_1
L1_1 = Ace
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = IsPlayerAceAllowed
  L3_2 = A0_2
  L4_2 = L0_1
  L5_2 = A1_2
  L4_2, L5_2 = L4_2(L5_2)
  return L2_2(L3_2, L4_2, L5_2)
end
L1_1.Can = L2_1
L1_1 = Ace
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = IsPrincipalAceAllowed
  L3_2 = A0_2
  L4_2 = L0_1
  L5_2 = A1_2
  L4_2, L5_2 = L4_2(L5_2)
  return L2_2(L3_2, L4_2, L5_2)
end
L1_1.CanGroup = L2_1
