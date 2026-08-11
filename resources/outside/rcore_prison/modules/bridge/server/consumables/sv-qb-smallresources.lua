local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1
L0_1 = {}
L1_1 = {}
L1_1.name = "sprunk"
L1_1.label = "Sprunk"
L1_1.type = "drink"
L2_1 = {}
L2_1.name = "sludgie"
L2_1.label = "Sludgie"
L2_1.type = "drink"
L3_1 = {}
L3_1.name = "ecola_light"
L3_1.label = "Ecola light"
L3_1.type = "drink"
L4_1 = {}
L4_1.name = "ecola"
L4_1.label = "Ecola"
L4_1.type = "drink"
L5_1 = {}
L5_1.name = "water"
L5_1.label = "Water"
L5_1.type = "drink"
L6_1 = {}
L6_1.name = "fries"
L6_1.label = "Fries"
L6_1.type = "eat"
L7_1 = {}
L7_1.name = "pizza_ham"
L7_1.label = "Pizza Ham"
L7_1.type = "eat"
L8_1 = {}
L8_1.name = "chips"
L8_1.label = "Chips"
L8_1.type = "eat"
L9_1 = {}
L9_1.name = "donut"
L9_1.label = "Donut"
L9_1.type = "eat"
L0_1[1] = L1_1
L0_1[2] = L2_1
L0_1[3] = L3_1
L0_1[4] = L4_1
L0_1[5] = L5_1
L0_1[6] = L6_1
L0_1[7] = L7_1
L0_1[8] = L8_1
L0_1[9] = L9_1
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = 0
  L2_2 = A0_2.type
  if "eat" == L2_2 then
    L1_2 = "math.random(35, 54)"
  else
    L2_2 = A0_2.type
    if "drink" == L2_2 then
      L1_2 = "math.random(35, 54)"
    else
      L2_2 = A0_2.type
      if "alcohol" == L2_2 then
        L1_2 = "math.random(20, 40)"
      end
    end
  end
  L2_2 = string
  L2_2 = L2_2.format
  L3_2 = "        ['%s'] = %s"
  L4_2 = A0_2.name
  L5_2 = L1_2
  return L2_2(L3_2, L4_2, L5_2)
end
L2_1 = CreateThread
function L3_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L0_2 = isResourcePresentProvideless
  L1_2 = CONSUMABLES
  L1_2 = L1_2.ESX
  L0_2 = L0_2(L1_2)
  if L0_2 then
    L0_2 = AssetDeployer
    L1_2 = L0_2
    L0_2 = L0_2.registerFileDeploy
    L2_2 = "consumables"
    L3_2 = CONSUMABLES
    L3_2 = L3_2.QB
    L4_2 = "config.lua"
    function L5_2(A0_3, A1_3)
      local L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3
      L2_3 = {}
      L3_3 = {}
      L4_3 = {}
      L6_3 = A0_3
      L5_3 = A0_3.strtrim
      L5_3 = L5_3(L6_3)
      L6_3 = L5_3
      L5_3 = L5_3.gsub
      L7_3 = "}$"
      L8_3 = ""
      L5_3 = L5_3(L6_3, L7_3, L8_3)
      A0_3 = L5_3
      L5_3 = ipairs
      L6_3 = A1_3
      L5_3, L6_3, L7_3, L8_3 = L5_3(L6_3)
      for L9_3, L10_3 in L5_3, L6_3, L7_3, L8_3 do
        L11_3 = L1_1
        L12_3 = L10_3
        L11_3 = L11_3(L12_3)
        L12_3 = L10_3.type
        if "eat" == L12_3 then
          L12_3 = table
          L12_3 = L12_3.insert
          L13_3 = L2_3
          L14_3 = L11_3
          L12_3(L13_3, L14_3)
        else
          L12_3 = L10_3.type
          if "drink" == L12_3 then
            L12_3 = table
            L12_3 = L12_3.insert
            L13_3 = L3_3
            L14_3 = L11_3
            L12_3(L13_3, L14_3)
          else
            L12_3 = L10_3.type
            if "alcohol" == L12_3 then
              L12_3 = table
              L12_3 = L12_3.insert
              L13_3 = L4_3
              L14_3 = L11_3
              L12_3(L13_3, L14_3)
            end
          end
        end
      end
      L5_3 = #L2_3
      if L5_3 > 0 then
        L5_3 = appendQBConsumablesEat
        L6_3 = A0_3
        L7_3 = table
        L7_3 = L7_3.concat
        L8_3 = L2_3
        L9_3 = ",\n"
        L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3 = L7_3(L8_3, L9_3)
        L5_3 = L5_3(L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3)
        A0_3 = L5_3
      end
      L5_3 = #L3_3
      if L5_3 > 0 then
        L5_3 = appendQBConsumablesDrink
        L6_3 = A0_3
        L7_3 = table
        L7_3 = L7_3.concat
        L8_3 = L3_3
        L9_3 = ",\n"
        L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3 = L7_3(L8_3, L9_3)
        L5_3 = L5_3(L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3)
        A0_3 = L5_3
      end
      L5_3 = append
      L6_3 = A0_3
      L7_3 = ""
      L8_3 = ASSET_DEPLOYER_WATERMARK_SUFFIX
      L9_3 = "}"
      L5_3 = L5_3(L6_3, L7_3, L8_3, L9_3)
      A0_3 = L5_3
      return A0_3
    end
    L6_2 = L0_1
    L0_2(L1_2, L2_2, L3_2, L4_2, L5_2, L6_2)
  end
end
L2_1(L3_1)
