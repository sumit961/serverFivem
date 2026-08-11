local L0_1, L1_1
L0_1 = {}
ClothingService = L0_1
L0_1 = ClothingService
function L1_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = Cloth
  L2_2 = L2_2.QB
  if A0_2 == L2_2 then
    L2_2 = ClothingService
    L2_2 = L2_2.ConvertQBClothingToComponents
    L3_2 = A1_2
    return L2_2(L3_2)
  else
    L2_2 = Cloth
    L2_2 = L2_2.SKINCHANGER
    if A0_2 == L2_2 then
      L2_2 = ClothingService
      L2_2 = L2_2.ConvertSkinchangerToComponents
      L3_2 = A1_2
      return L2_2(L3_2)
    else
      L2_2 = Cloth
      L2_2 = L2_2.TGIANN
      if A0_2 == L2_2 then
        L2_2 = ClothingService
        L2_2 = L2_2.ConvertTGIANN
        L3_2 = A1_2
        return L2_2(L3_2)
      else
        L2_2 = Cloth
        L2_2 = L2_2.CRM
        if A0_2 == L2_2 then
          L2_2 = ClothingService
          L2_2 = L2_2.ConvertCRM
          L3_2 = A1_2
          return L2_2(L3_2)
        else
          L2_2 = Cloth
          L2_2 = L2_2.FAPPEARANCE
          if A0_2 == L2_2 then
            L2_2 = ClothingService
            L2_2 = L2_2.ConvertFivemAppearanceToComponents
            L3_2 = A1_2
            return L2_2(L3_2)
          else
            L2_2 = Cloth
            L2_2 = L2_2.BL_APPEARANCE
            if A0_2 == L2_2 then
              L2_2 = ClothingService
              L2_2 = L2_2.ConvertBLAppearanceToComponents
              L3_2 = A1_2
              return L2_2(L3_2)
            end
          end
        end
      end
    end
  end
end
L0_1.ConvertClothingComponents = L1_1
L0_1 = ClothingService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  if not A0_2 then
    return
  end
  L1_2 = {}
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.PANTS
  L1_2[L2_2] = "pants"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHOES
  L1_2[L2_2] = "shoes"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHIRT
  L1_2[L2_2] = "tshirt"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.ARMS
  L1_2[L2_2] = "arms"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.MASKS
  L1_2[L2_2] = "mask"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY
  L1_2[L2_2] = "torso"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.DECALS
  L1_2[L2_2] = "decals"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY_ARMOR
  L1_2[L2_2] = "bproof"
  L2_2 = {}
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.HATS
  L2_2[L3_2] = "helmet"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.EARS
  L2_2[L3_2] = "ears"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.GLASSES
  L2_2[L3_2] = "glass"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.WATCHES
  L2_2[L3_2] = "watch"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.BRACELETS
  L2_2[L3_2] = "bracelet"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.ACCESSORY
  L2_2[L3_2] = "chain"
  L3_2 = {}
  L4_2 = {}
  L3_2.crm_clothing = L4_2
  L4_2 = {}
  L3_2.crm_accessories = L4_2
  L4_2 = ipairs
  L5_2 = A0_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = nil
    L11_2 = nil
    L12_2 = L9_2.isProp
    if L12_2 then
      L12_2 = L9_2.componentId
      L10_2 = L2_2[L12_2]
      L12_2 = {}
      L13_2 = L9_2.componentId
      L12_2.crm_id = L13_2
      L13_2 = L9_2.drawableId
      L12_2.crm_style = L13_2
      L13_2 = L9_2.textureId
      L12_2.crm_texture = L13_2
      L11_2 = L12_2
      L12_2 = table
      L12_2 = L12_2.insert
      L13_2 = L3_2.crm_accessories
      L14_2 = L11_2
      L12_2(L13_2, L14_2)
    else
      L12_2 = L9_2.componentId
      L10_2 = L1_2[L12_2]
      L12_2 = {}
      L13_2 = L9_2.componentId
      L12_2.crm_id = L13_2
      L13_2 = L9_2.drawableId
      L12_2.crm_style = L13_2
      L13_2 = L9_2.textureId
      L12_2.crm_texture = L13_2
      L11_2 = L12_2
      L12_2 = table
      L12_2 = L12_2.insert
      L13_2 = L3_2.crm_clothing
      L14_2 = L11_2
      L12_2(L13_2, L14_2)
    end
  end
  return L3_2
end
L0_1.ConvertCRM = L1_1
L0_1 = ClothingService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2, L26_2
  if not A0_2 then
    return
  end
  L1_2 = {}
  L2_2 = {}
  L2_2.name = "decals_1"
  L2_2.val = 0
  L3_2 = {}
  L3_2.name = "decals_2"
  L3_2.val = 0
  L4_2 = {}
  L4_2.name = "pants_1"
  L4_2.val = 0
  L5_2 = {}
  L5_2.name = "pants_2"
  L5_2.val = 0
  L6_2 = {}
  L6_2.name = "mask_1"
  L6_2.val = 0
  L7_2 = {}
  L7_2.name = "mask_2"
  L7_2.val = 0
  L8_2 = {}
  L8_2.name = "bproof_1"
  L8_2.val = 0
  L9_2 = {}
  L9_2.name = "bproof_2"
  L9_2.val = 0
  L10_2 = {}
  L10_2.name = "tshirt_1"
  L10_2.val = 0
  L11_2 = {}
  L11_2.name = "tshirt_2"
  L11_2.val = 0
  L12_2 = {}
  L12_2.name = "torso_1"
  L12_2.val = 0
  L13_2 = {}
  L13_2.name = "torso_2"
  L13_2.val = 0
  L14_2 = {}
  L14_2.name = "shoes_1"
  L14_2.val = 0
  L15_2 = {}
  L15_2.name = "shoes_2"
  L15_2.val = 0
  L16_2 = {}
  L16_2.name = "arms"
  L16_2.val = 0
  L17_2 = {}
  L17_2.name = "chain_1"
  L17_2.val = 0
  L18_2 = {}
  L18_2.name = "chain_2"
  L18_2.val = 0
  L19_2 = {}
  L19_2.name = "helmet_1"
  L19_2.val = 0
  L20_2 = {}
  L20_2.name = "helmet_2"
  L20_2.val = 0
  L21_2 = {}
  L21_2.name = "glasses_1"
  L21_2.val = -1
  L22_2 = {}
  L22_2.name = "glasses_2"
  L22_2.val = 0
  L23_2 = {}
  L23_2.name = "watch_1"
  L23_2.val = 0
  L24_2 = {}
  L24_2.name = "watch_2"
  L24_2.val = 0
  L25_2 = {}
  L25_2.name = "bracelet_1"
  L25_2.val = 0
  L26_2 = {}
  L26_2.name = "bracelet_2"
  L26_2.val = 0
  L1_2[1] = L2_2
  L1_2[2] = L3_2
  L1_2[3] = L4_2
  L1_2[4] = L5_2
  L1_2[5] = L6_2
  L1_2[6] = L7_2
  L1_2[7] = L8_2
  L1_2[8] = L9_2
  L1_2[9] = L10_2
  L1_2[10] = L11_2
  L1_2[11] = L12_2
  L1_2[12] = L13_2
  L1_2[13] = L14_2
  L1_2[14] = L15_2
  L1_2[15] = L16_2
  L1_2[16] = L17_2
  L1_2[17] = L18_2
  L1_2[18] = L19_2
  L1_2[19] = L20_2
  L1_2[20] = L21_2
  L1_2[21] = L22_2
  L1_2[22] = L23_2
  L1_2[23] = L24_2
  L1_2[24] = L25_2
  L1_2[25] = L26_2
  L2_2 = {}
  L3_2 = CLOTHING_COMPONENTS
  L3_2 = L3_2.PANTS
  L4_2 = {}
  L5_2 = "pants_1"
  L6_2 = "pants_2"
  L4_2[1] = L5_2
  L4_2[2] = L6_2
  L2_2[L3_2] = L4_2
  L3_2 = CLOTHING_COMPONENTS
  L3_2 = L3_2.SHOES
  L4_2 = {}
  L5_2 = "shoes_1"
  L6_2 = "shoes_2"
  L4_2[1] = L5_2
  L4_2[2] = L6_2
  L2_2[L3_2] = L4_2
  L3_2 = CLOTHING_COMPONENTS
  L3_2 = L3_2.SHIRT
  L4_2 = {}
  L5_2 = "tshirt_1"
  L6_2 = "tshirt_2"
  L4_2[1] = L5_2
  L4_2[2] = L6_2
  L2_2[L3_2] = L4_2
  L3_2 = CLOTHING_COMPONENTS
  L3_2 = L3_2.ARMS
  L4_2 = {}
  L5_2 = "arms"
  L4_2[1] = L5_2
  L2_2[L3_2] = L4_2
  L3_2 = CLOTHING_COMPONENTS
  L3_2 = L3_2.MASKS
  L4_2 = {}
  L5_2 = "mask_1"
  L6_2 = "mask_2"
  L4_2[1] = L5_2
  L4_2[2] = L6_2
  L2_2[L3_2] = L4_2
  L3_2 = CLOTHING_COMPONENTS
  L3_2 = L3_2.BODY
  L4_2 = {}
  L5_2 = "torso_1"
  L6_2 = "torso_2"
  L4_2[1] = L5_2
  L4_2[2] = L6_2
  L2_2[L3_2] = L4_2
  L3_2 = CLOTHING_COMPONENTS
  L3_2 = L3_2.DECALS
  L4_2 = {}
  L5_2 = "decals_1"
  L6_2 = "decals_2"
  L4_2[1] = L5_2
  L4_2[2] = L6_2
  L2_2[L3_2] = L4_2
  L3_2 = CLOTHING_COMPONENTS
  L3_2 = L3_2.BODY_ARMOR
  L4_2 = {}
  L5_2 = "bproof_1"
  L6_2 = "bproof_2"
  L4_2[1] = L5_2
  L4_2[2] = L6_2
  L2_2[L3_2] = L4_2
  L3_2 = {}
  L4_2 = PROP_COMPONENTS
  L4_2 = L4_2.HATS
  L5_2 = {}
  L6_2 = "helmet_1"
  L7_2 = "helmet_2"
  L5_2[1] = L6_2
  L5_2[2] = L7_2
  L3_2[L4_2] = L5_2
  L4_2 = PROP_COMPONENTS
  L4_2 = L4_2.EARS
  L5_2 = {}
  L6_2 = "ear_1"
  L7_2 = "ear_2"
  L5_2[1] = L6_2
  L5_2[2] = L7_2
  L3_2[L4_2] = L5_2
  L4_2 = PROP_COMPONENTS
  L4_2 = L4_2.GLASSES
  L5_2 = {}
  L6_2 = "glasses_1"
  L7_2 = "glasses_2"
  L5_2[1] = L6_2
  L5_2[2] = L7_2
  L3_2[L4_2] = L5_2
  L4_2 = PROP_COMPONENTS
  L4_2 = L4_2.WATCHES
  L5_2 = {}
  L6_2 = "watch_1"
  L7_2 = "watch_2"
  L5_2[1] = L6_2
  L5_2[2] = L7_2
  L3_2[L4_2] = L5_2
  L4_2 = PROP_COMPONENTS
  L4_2 = L4_2.BRACELETS
  L5_2 = {}
  L6_2 = "bracelet_1"
  L7_2 = "bracelet_2"
  L5_2[1] = L6_2
  L5_2[2] = L7_2
  L3_2[L4_2] = L5_2
  L4_2 = PROP_COMPONENTS
  L4_2 = L4_2.ACCESSORY
  L5_2 = {}
  L6_2 = "chain_1"
  L7_2 = "chain_2"
  L5_2[1] = L6_2
  L5_2[2] = L7_2
  L3_2[L4_2] = L5_2
  function L4_2(A0_3, A1_3, A2_3)
    local L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3
    L3_3 = ipairs
    L4_3 = A0_3
    L3_3, L4_3, L5_3, L6_3 = L3_3(L4_3)
    for L7_3, L8_3 in L3_3, L4_3, L5_3, L6_3 do
      L9_3 = L8_3.name
      if L9_3 == A1_3 then
        L8_3.val = A2_3
        break
      end
    end
  end
  L5_2 = ipairs
  L6_2 = A0_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = nil
    L12_2 = L10_2.isProp
    if L12_2 then
      L12_2 = L10_2.componentId
      L11_2 = L3_2[L12_2]
    else
      L12_2 = L10_2.componentId
      L11_2 = L2_2[L12_2]
    end
    if L11_2 then
      L12_2 = #L11_2
      if 2 == L12_2 then
        L12_2 = L4_2
        L13_2 = L1_2
        L14_2 = L11_2[1]
        L15_2 = L10_2.drawableId
        L12_2(L13_2, L14_2, L15_2)
        L12_2 = L4_2
        L13_2 = L1_2
        L14_2 = L11_2[2]
        L15_2 = L10_2.textureId
        L12_2(L13_2, L14_2, L15_2)
      else
        L12_2 = L4_2
        L13_2 = L1_2
        L14_2 = L11_2[1]
        L15_2 = L10_2.drawableId
        L12_2(L13_2, L14_2, L15_2)
      end
    end
  end
  return L1_2
end
L0_1.ConvertTGIANN = L1_1
L0_1 = ClothingService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  if not A0_2 then
    return
  end
  L1_2 = {}
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.PANTS
  L1_2[L2_2] = "pants"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHOES
  L1_2[L2_2] = "shoes"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHIRT
  L1_2[L2_2] = "t-shirt"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.ARMS
  L1_2[L2_2] = "arms"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.MASKS
  L1_2[L2_2] = "mask"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY
  L1_2[L2_2] = "torso2"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.DECALS
  L1_2[L2_2] = "decals"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY_ARMOR
  L1_2[L2_2] = "vest"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.MASKS
  L1_2[L2_2] = "mask"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BAGS_AND_PARACHUTE
  L1_2[L2_2] = "bag"
  L2_2 = {}
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.HATS
  L2_2[L3_2] = "hat"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.EARS
  L2_2[L3_2] = "ear"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.GLASSES
  L2_2[L3_2] = "glass"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.WATCHES
  L2_2[L3_2] = "watch"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.BRACELETS
  L2_2[L3_2] = "bracelet"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.ACCESSORY
  L2_2[L3_2] = "accessory"
  L3_2 = {}
  L4_2 = {}
  L3_2.outfitData = L4_2
  L4_2 = ipairs
  L5_2 = A0_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = nil
    L11_2 = L9_2.isProp
    if L11_2 then
      L11_2 = L9_2.componentId
      L10_2 = L2_2[L11_2]
    else
      L11_2 = L9_2.componentId
      L10_2 = L1_2[L11_2]
    end
    if L10_2 then
      L11_2 = L3_2.outfitData
      L12_2 = {}
      L13_2 = L9_2.drawableId
      L12_2.item = L13_2
      L13_2 = L9_2.textureId
      L12_2.texture = L13_2
      L12_2.defaultItem = 1
      L12_2.defaultTexture = 0
      L11_2[L10_2] = L12_2
    end
  end
  return L3_2
end
L0_1.ConvertQBClothingToComponents = L1_1
L0_1 = ClothingService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  if not A0_2 then
    return
  end
  L1_2 = {}
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.PANTS
  L1_2[L2_2] = "pants"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHOES
  L1_2[L2_2] = "shoes"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHIRT
  L1_2[L2_2] = "tshirt"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.ARMS
  L1_2[L2_2] = "arms"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.MASKS
  L1_2[L2_2] = "mask"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY
  L1_2[L2_2] = "torso"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.DECALS
  L1_2[L2_2] = "decals"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY_ARMOR
  L1_2[L2_2] = "bproof"
  L2_2 = {}
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.HATS
  L2_2[L3_2] = "helmet"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.EARS
  L2_2[L3_2] = "ears"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.GLASSES
  L2_2[L3_2] = "glass"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.WATCHES
  L2_2[L3_2] = "watch"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.BRACELETS
  L2_2[L3_2] = "bracelet"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.ACCESSORY
  L2_2[L3_2] = "chain"
  L3_2 = {}
  L4_2 = ipairs
  L5_2 = A0_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = nil
    L11_2 = L9_2.isProp
    if L11_2 then
      L11_2 = L9_2.componentId
      L10_2 = L2_2[L11_2]
    else
      L11_2 = L9_2.componentId
      L10_2 = L1_2[L11_2]
    end
    if L10_2 then
      if "arms" == L10_2 then
        L11_2 = L9_2.isProp
        if not L11_2 then
          L11_2 = L9_2.drawableId
          L3_2[L10_2] = L11_2
          L11_2 = L10_2
          L12_2 = "_2"
          L11_2 = L11_2 .. L12_2
          L12_2 = L9_2.textureId
          L3_2[L11_2] = L12_2
      end
      else
        L11_2 = L10_2
        L12_2 = "_1"
        L11_2 = L11_2 .. L12_2
        L12_2 = L9_2.drawableId
        L3_2[L11_2] = L12_2
        L11_2 = L10_2
        L12_2 = "_2"
        L11_2 = L11_2 .. L12_2
        L12_2 = L9_2.textureId
        L3_2[L11_2] = L12_2
      end
    end
  end
  return L3_2
end
L0_1.ConvertSkinchangerToComponents = L1_1
L0_1 = ClothingService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  if not A0_2 then
    return
  end
  L1_2 = {}
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.PANTS
  L1_2[L2_2] = "pants"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHOES
  L1_2[L2_2] = "shoes"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHIRT
  L1_2[L2_2] = "tshirt"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.ARMS
  L1_2[L2_2] = "arms"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.MASKS
  L1_2[L2_2] = "mask"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY
  L1_2[L2_2] = "torso"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.DECALS
  L1_2[L2_2] = "decals"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY_ARMOR
  L1_2[L2_2] = "bproof"
  L2_2 = {}
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.HATS
  L2_2[L3_2] = "helmet"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.EARS
  L2_2[L3_2] = "ears"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.GLASSES
  L2_2[L3_2] = "glass"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.WATCHES
  L2_2[L3_2] = "watch"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.BRACELETS
  L2_2[L3_2] = "bracelet"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.ACCESSORY
  L2_2[L3_2] = "chain"
  L3_2 = {}
  L4_2 = {}
  L5_2 = ipairs
  L6_2 = A0_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = {}
    L12_2 = L10_2.isProp
    if L12_2 then
      L12_2 = L10_2.componentId
      L13_2 = CLOTHING_COMPONENTS
      L13_2 = L13_2.MASKS
      if L12_2 ~= L13_2 then
        goto lbl_90
      end
    end
    L12_2 = L10_2.componentId
    L12_2 = L1_2[L12_2]
    if L12_2 then
      L13_2 = L10_2.textureId
      if not L13_2 then
        L13_2 = 0
      end
      L11_2.texture = L13_2
      L13_2 = L10_2.drawableId
      if not L13_2 then
        L13_2 = 0
      end
      L11_2.drawable = L13_2
      L13_2 = L10_2.componentId
      L11_2.component_id = L13_2
      L13_2 = table
      L13_2 = L13_2.insert
      L14_2 = L3_2
      L15_2 = L11_2
      L13_2(L14_2, L15_2)
      goto lbl_111
      ::lbl_90::
      L12_2 = L10_2.componentId
      L12_2 = L2_2[L12_2]
      if L12_2 then
        L13_2 = L10_2.textureId
        if not L13_2 then
          L13_2 = -1
        end
        L11_2.texture = L13_2
        L13_2 = L10_2.drawableId
        if not L13_2 then
          L13_2 = -1
        end
        L11_2.drawable = L13_2
        L13_2 = L10_2.componentId
        L11_2.prop_id = L13_2
        L13_2 = table
        L13_2 = L13_2.insert
        L14_2 = L4_2
        L15_2 = L11_2
        L13_2(L14_2, L15_2)
      end
    end
    ::lbl_111::
  end
  L5_2 = L3_2
  L6_2 = L4_2
  return L5_2, L6_2
end
L0_1.ConvertFivemAppearanceToComponents = L1_1
L0_1 = ClothingService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  if not A0_2 then
    return
  end
  L1_2 = {}
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.PANTS
  L1_2[L2_2] = "legs"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHOES
  L1_2[L2_2] = "shoes"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHIRT
  L1_2[L2_2] = "shirts"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY
  L1_2[L2_2] = "torsos"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.DECALS
  L1_2[L2_2] = "decals"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.ARMS
  L1_2[L2_2] = "arms"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BODY_ARMOR
  L1_2[L2_2] = "vest"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.HAIR_STYLES
  L1_2[L2_2] = "hair"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.MASKS
  L1_2[L2_2] = "masks"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.BAGS_AND_PARACHUTE
  L1_2[L2_2] = "bags"
  L2_2 = CLOTHING_COMPONENTS
  L2_2 = L2_2.SHIRT
  L1_2[L2_2] = "jackets"
  L2_2 = {}
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.HATS
  L2_2[L3_2] = "hats"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.EARS
  L2_2[L3_2] = "earrings"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.GLASSES
  L2_2[L3_2] = "glasses"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.WATCHES
  L2_2[L3_2] = "watches"
  L3_2 = PROP_COMPONENTS
  L3_2 = L3_2.BRACELETS
  L2_2[L3_2] = "bracelets"
  L3_2 = {}
  L4_2 = {}
  L5_2 = ipairs
  L6_2 = A0_2
  L5_2, L6_2, L7_2, L8_2 = L5_2(L6_2)
  for L9_2, L10_2 in L5_2, L6_2, L7_2, L8_2 do
    L11_2 = {}
    L12_2 = L10_2.isProp
    if not L12_2 then
      L12_2 = L10_2.componentId
      L12_2 = L1_2[L12_2]
      if L12_2 then
        L13_2 = {}
        L14_2 = L10_2.drawableId
        if not L14_2 then
          L14_2 = 0
        end
        L13_2.value = L14_2
        L13_2.id = L12_2
        L14_2 = L10_2.textureId
        if not L14_2 then
          L14_2 = 0
        end
        L13_2.texture = L14_2
        L14_2 = L10_2.componentId
        L13_2.index = L14_2
        L3_2[L12_2] = L13_2
      end
    else
      L12_2 = L10_2.componentId
      L12_2 = L2_2[L12_2]
      if L12_2 then
        L13_2 = {}
        L14_2 = L10_2.drawableId
        if not L14_2 then
          L14_2 = 0
        end
        L13_2.value = L14_2
        L13_2.id = L12_2
        L14_2 = L10_2.textureId
        if not L14_2 then
          L14_2 = 0
        end
        L13_2.texture = L14_2
        L14_2 = L10_2.componentId
        L13_2.index = L14_2
        L4_2[L12_2] = L13_2
      end
    end
  end
  L5_2 = {}
  L5_2.drawables = L3_2
  L5_2.props = L4_2
  return L5_2
end
L0_1.ConvertBLAppearanceToComponents = L1_1
