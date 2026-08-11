local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1, L11_1, L12_1, L13_1, L14_1, L15_1, L16_1, L17_1, L18_1, L19_1, L20_1, L21_1, L22_1, L23_1, L24_1, L25_1, L26_1, L27_1, L28_1
L0_1 = {}
CigarProduction = L0_1
L0_1 = 0.05
L1_1 = 0.015
L2_1 = 0.04
L3_1 = Config
L3_1 = L3_1.Minigame
L3_1 = L3_1.MoveStep
if not L3_1 then
  L3_1 = 0.09
end
L4_1 = 0.4
L5_1 = 0.6
L6_1 = Config
L6_1 = L6_1.Minigame
L6_1 = L6_1.Tolerance
if not L6_1 then
  L6_1 = 0.025
end
L7_1 = false
L8_1 = {}
L9_1 = {}
L10_1 = nil
L11_1 = nil
L12_1 = CigarProduction
function L13_1()
  local L0_2, L1_2, L2_2
  L0_2 = TriggerServerEvent
  L1_2 = "rcore_prison:server:requestCigarProduction"
  L2_2 = SH
  L2_2 = L2_2.zoneId
  L0_2(L1_2, L2_2)
end
L12_1.RequestOpen = L13_1
function L12_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = pairs
  L2_2 = L8_1
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = math
    L7_2 = L7_2.abs
    L8_2 = L6_2.time
    L9_2 = L4_1
    L8_2 = L8_2 - L9_2
    L7_2 = L7_2(L8_2)
    L8_2 = L6_1
    if L7_2 <= L8_2 then
      L7_2 = L6_2.letter
      if L7_2 == A0_2 then
        return L5_2
      end
    end
  end
  L1_2 = nil
  return L1_2
end
function L13_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = pairs
  L2_2 = L9_1
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = math
    L7_2 = L7_2.abs
    L8_2 = L6_2.time
    L9_2 = 1
    L8_2 = L9_2 - L8_2
    L9_2 = L5_1
    L8_2 = L8_2 - L9_2
    L7_2 = L7_2(L8_2)
    L8_2 = L6_1
    if L7_2 <= L8_2 then
      L7_2 = L6_2.letter
      if L7_2 == A0_2 then
        return L5_2
      end
    end
  end
  L1_2 = nil
  return L1_2
end
function L14_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = StopAnimTask
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = L10_1
  L3_2 = L11_1
  L4_2 = 1.0
  L0_2(L1_2, L2_2, L3_2, L4_2)
end
function L15_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L2_2 = A1_2 or L2_2
  if not A1_2 or not A1_2 then
    L2_2 = 0.3
  end
  L3_2 = Config
  L3_2 = L3_2.Minigame
  L3_2 = L3_2.Keys
  if not L3_2 then
    L3_2 = {}
    L4_2 = "W"
    L5_2 = "S"
    L6_2 = "A"
    L7_2 = "D"
    L3_2[1] = L4_2
    L3_2[2] = L5_2
    L3_2[3] = L6_2
    L3_2[4] = L7_2
  end
  L4_2 = {}
  L8_1 = L4_2
  L4_2 = {}
  L9_1 = L4_2
  L4_2 = 1
  L5_2 = A0_2
  L6_2 = 1
  for L7_2 = L4_2, L5_2, L6_2 do
    L8_2 = math
    L8_2 = L8_2.random
    L9_2 = 70
    L10_2 = 150
    L8_2 = L8_2(L9_2, L10_2)
    L8_2 = L8_2 / 1000
    L2_2 = L2_2 - L8_2
    L8_2 = table
    L8_2 = L8_2.insert
    L9_2 = L8_1
    L10_2 = {}
    L10_2.time = L2_2
    L11_2 = math
    L11_2 = L11_2.random
    L12_2 = 1
    L13_2 = #L3_2
    L11_2 = L11_2(L12_2, L13_2)
    L11_2 = L3_2[L11_2]
    L10_2.letter = L11_2
    L8_2(L9_2, L10_2)
    L8_2 = math
    L8_2 = L8_2.random
    L9_2 = 1
    L10_2 = 100
    L8_2 = L8_2(L9_2, L10_2)
    if L8_2 < 80 then
      L8_2 = table
      L8_2 = L8_2.insert
      L9_2 = L9_1
      L10_2 = {}
      L10_2.time = L2_2
      L11_2 = math
      L11_2 = L11_2.random
      L12_2 = 1
      L13_2 = #L3_2
      L11_2 = L11_2(L12_2, L13_2)
      L11_2 = L3_2[L11_2]
      L10_2.letter = L11_2
      L8_2(L9_2, L10_2)
    end
  end
end
function L16_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = L14_1
  L0_2()
  L0_2 = PlaySoundFrontend
  L1_2 = -1
  L2_2 = "LOSER"
  L3_2 = "HUD_AWARDS"
  L0_2(L1_2, L2_2, L3_2)
  L0_2 = Wait
  L1_2 = 100
  L0_2(L1_2)
  L0_2 = false
  L7_1 = L0_2
  L0_2 = FreezePlayer
  L1_2 = PlayerId
  L1_2 = L1_2()
  L2_2 = false
  L0_2(L1_2, L2_2)
  L0_2 = TriggerEvent
  L1_2 = "rcore_prison:hudState"
  L2_2 = "cigar"
  L3_2 = true
  L0_2(L1_2, L2_2, L3_2)
  L0_2 = TriggerServerEvent
  L1_2 = "rcore_prison:server:requestCigarProductionFailed"
  L2_2 = SH
  L2_2 = L2_2.zoneId
  L0_2(L1_2, L2_2)
  L0_2 = TriggerLocalClientEvent
  L1_2 = "onHud"
  L2_2 = true
  L3_2 = "SHOW_HUD"
  L4_2 = "MINIGAME_FINISHED"
  L0_2(L1_2, L2_2, L3_2, L4_2)
end
function L17_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  if not A0_2 then
    return
  end
  L2_2 = L12_1
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = L16_1
    L3_2()
    if A1_2 then
      L3_2 = A1_2
      L3_2()
    end
  else
    L3_2 = L8_1
    L3_2[L2_2] = nil
    L3_2 = PlaySoundFrontend
    L4_2 = -1
    L5_2 = "CLICK_BACK"
    L6_2 = "WEB_NAVIGATION_SOUNDS_PHONE"
    L3_2(L4_2, L5_2, L6_2)
  end
end
function L18_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  if not A0_2 then
    return
  end
  L2_2 = L13_1
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = L16_1
    L3_2()
    if A1_2 then
      L3_2 = A1_2
      L3_2()
    end
  else
    L3_2 = L9_1
    L3_2[L2_2] = nil
    L3_2 = PlaySoundFrontend
    L4_2 = -1
    L5_2 = "CLICK_BACK"
    L6_2 = "WEB_NAVIGATION_SOUNDS_PHONE"
    L3_2(L4_2, L5_2, L6_2)
  end
end
function L19_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = L14_1
  L0_2()
  L0_2 = Wait
  L1_2 = 100
  L0_2(L1_2)
  L0_2 = false
  L7_1 = L0_2
  L0_2 = TriggerLocalClientEvent
  L1_2 = "onHud"
  L2_2 = true
  L3_2 = "SHOW_HUD"
  L4_2 = "MINIGAME_FINISHED"
  L0_2(L1_2, L2_2, L3_2, L4_2)
  L0_2 = FreezePlayer
  L1_2 = PlayerId
  L1_2 = L1_2()
  L2_2 = false
  L0_2(L1_2, L2_2)
end
KeyPressMinigameSuccess = L19_1
function L19_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2
  L4_2 = SetTextFont
  L5_2 = 7
  L4_2(L5_2)
  L4_2 = SetTextScale
  L5_2 = 1.0
  L6_2 = 1.0
  L4_2(L5_2, L6_2)
  if A3_2 then
    L4_2 = SetTextColour
    L5_2 = 200
    L6_2 = 255
    L7_2 = 200
    L8_2 = 255
    L4_2(L5_2, L6_2, L7_2, L8_2)
  else
    L4_2 = SetTextColour
    L5_2 = 255
    L6_2 = 255
    L7_2 = 255
    L8_2 = 255
    L4_2(L5_2, L6_2, L7_2, L8_2)
  end
  L4_2 = SetTextOutline
  L4_2()
  L4_2 = SetTextCentre
  L5_2 = true
  L4_2(L5_2)
  L4_2 = SetTextJustification
  L5_2 = 0
  L4_2(L5_2)
  L4_2 = BeginTextCommandDisplayText
  L5_2 = "STRING"
  L4_2(L5_2)
  L4_2 = AddTextComponentSubstringPlayerName
  L5_2 = A0_2
  L4_2(L5_2)
  L4_2 = EndTextCommandDisplayText
  L5_2 = A1_2
  L6_2 = A2_2 - 0.027
  L4_2(L5_2, L6_2)
end
DrawLetter = L19_1
function L19_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2
  L4_2 = RequestStreamedTextureDict
  L5_2 = "mparrow"
  L6_2 = false
  L4_2(L5_2, L6_2)
  L4_2 = 255
  L5_2 = 255
  L6_2 = 255
  if A3_2 then
    L7_2 = 200
    L8_2 = 255
    L6_2 = 200
    L5_2 = L8_2
    L4_2 = L7_2
  end
  L7_2 = Config
  L7_2 = L7_2.Minigame
  L7_2 = L7_2.Keys
  L7_2 = L7_2[4]
  if A0_2 == L7_2 then
    L7_2 = DrawSprite
    L8_2 = "mparrow"
    L9_2 = "mp_arrowlarge"
    L10_2 = A1_2
    L11_2 = A2_2
    L12_2 = L1_1
    L13_2 = L1_1
    L13_2 = 2 * L13_2
    L14_2 = GetAspectRatio
    L14_2 = L14_2()
    L13_2 = L13_2 * L14_2
    L14_2 = 0.0
    L15_2 = L4_2
    L16_2 = L5_2
    L17_2 = L6_2
    L18_2 = 255
    L7_2(L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
  else
    L7_2 = Config
    L7_2 = L7_2.Minigame
    L7_2 = L7_2.Keys
    L7_2 = L7_2[3]
    if A0_2 == L7_2 then
      L7_2 = DrawSprite
      L8_2 = "mparrow"
      L9_2 = "mp_arrowlarge"
      L10_2 = A1_2
      L11_2 = A2_2
      L12_2 = L1_1
      L13_2 = L1_1
      L13_2 = 2 * L13_2
      L14_2 = GetAspectRatio
      L14_2 = L14_2()
      L13_2 = L13_2 * L14_2
      L14_2 = 180.0
      L15_2 = L4_2
      L16_2 = L5_2
      L17_2 = L6_2
      L18_2 = 255
      L7_2(L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
    else
      L7_2 = Config
      L7_2 = L7_2.Minigame
      L7_2 = L7_2.Keys
      L7_2 = L7_2[2]
      if A0_2 == L7_2 then
        L7_2 = DrawSprite
        L8_2 = "mparrow"
        L9_2 = "mp_arrowlarge"
        L10_2 = A1_2
        L11_2 = A2_2
        L12_2 = L1_1
        L12_2 = 2 * L12_2
        L13_2 = L1_1
        L14_2 = GetAspectRatio
        L14_2 = L14_2()
        L13_2 = L13_2 * L14_2
        L14_2 = 90.0
        L15_2 = L4_2
        L16_2 = L5_2
        L17_2 = L6_2
        L18_2 = 255
        L7_2(L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
      else
        L7_2 = Config
        L7_2 = L7_2.Minigame
        L7_2 = L7_2.Keys
        L7_2 = L7_2[1]
        if A0_2 == L7_2 then
          L7_2 = DrawSprite
          L8_2 = "mparrow"
          L9_2 = "mp_arrowlarge"
          L10_2 = A1_2
          L11_2 = A2_2
          L12_2 = L1_1
          L12_2 = 2 * L12_2
          L13_2 = L1_1
          L14_2 = GetAspectRatio
          L14_2 = L14_2()
          L13_2 = L13_2 * L14_2
          L14_2 = -90.0
          L15_2 = L4_2
          L16_2 = L5_2
          L17_2 = L6_2
          L18_2 = 255
          L7_2(L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2)
        end
      end
    end
  end
end
L20_1 = Config
L20_1 = L20_1.Minigame
L20_1 = L20_1.Keybinds
L21_1 = {}
L21_1.ARROW_UP = "UP"
L21_1.ARROW_DOWN = "DOWN"
L21_1.LEFT_ARROW = "LEFT"
L21_1.RIGHT_ARROW = "RIGHT"
L22_1 = nil
L23_1 = nil
function L24_1()
  local L0_2, L1_2, L2_2
  L0_2 = L7_1
  if not L0_2 then
    return
  end
  L0_2 = L17_1
  L1_2 = L20_1.W
  L2_2 = L22_1
  L0_2(L1_2, L2_2)
end
PressLeftW = L24_1
function L24_1()
  local L0_2, L1_2, L2_2
  L0_2 = L7_1
  if not L0_2 then
    return
  end
  L0_2 = L17_1
  L1_2 = L20_1.S
  L2_2 = L22_1
  L0_2(L1_2, L2_2)
end
PressLeftS = L24_1
function L24_1()
  local L0_2, L1_2, L2_2
  L0_2 = L7_1
  if not L0_2 then
    return
  end
  L0_2 = L17_1
  L1_2 = L20_1.A
  L2_2 = L22_1
  L0_2(L1_2, L2_2)
end
PressLeftA = L24_1
function L24_1()
  local L0_2, L1_2, L2_2
  L0_2 = L7_1
  if not L0_2 then
    return
  end
  L0_2 = L17_1
  L1_2 = L20_1.D
  L2_2 = L22_1
  L0_2(L1_2, L2_2)
end
PressLeftD = L24_1
function L24_1()
  local L0_2, L1_2, L2_2
  L0_2 = L7_1
  if not L0_2 then
    return
  end
  L0_2 = L18_1
  L1_2 = L20_1.W
  L2_2 = L22_1
  L0_2(L1_2, L2_2)
end
PressRightW = L24_1
function L24_1()
  local L0_2, L1_2, L2_2
  L0_2 = L7_1
  if not L0_2 then
    return
  end
  L0_2 = L18_1
  L1_2 = L20_1.S
  L2_2 = L22_1
  L0_2(L1_2, L2_2)
end
PressRightS = L24_1
function L24_1()
  local L0_2, L1_2, L2_2
  L0_2 = L7_1
  if not L0_2 then
    return
  end
  L0_2 = L18_1
  L1_2 = L20_1.A
  L2_2 = L22_1
  L0_2(L1_2, L2_2)
end
PressRightA = L24_1
function L24_1()
  local L0_2, L1_2, L2_2
  L0_2 = L7_1
  if not L0_2 then
    return
  end
  L0_2 = L18_1
  L1_2 = L20_1.D
  L2_2 = L22_1
  L0_2(L1_2, L2_2)
end
PressRightD = L24_1
L24_1 = RegisterKey
L25_1 = PressLeftW
L26_1 = "MINIGAME_LEFT_W"
L27_1 = _U
L28_1 = "MINIGAME_CIGAR_PRODUCTION.KEY_MAPPING_PRESS_LEFT_W"
L27_1 = L27_1(L28_1)
L28_1 = L20_1.W
L24_1(L25_1, L26_1, L27_1, L28_1)
L24_1 = RegisterKey
L25_1 = PressLeftS
L26_1 = "MINIGAME_LEFT_S"
L27_1 = _U
L28_1 = "MINIGAME_CIGAR_PRODUCTION.KEY_MAPPING_PRESS_LEFT_S"
L27_1 = L27_1(L28_1)
L28_1 = L20_1.S
L24_1(L25_1, L26_1, L27_1, L28_1)
L24_1 = RegisterKey
L25_1 = PressLeftA
L26_1 = "MINIGAME_LEFT_A"
L27_1 = _U
L28_1 = "MINIGAME_CIGAR_PRODUCTION.KEY_MAPPING_PRESS_LEFT_A"
L27_1 = L27_1(L28_1)
L28_1 = L20_1.A
L24_1(L25_1, L26_1, L27_1, L28_1)
L24_1 = RegisterKey
L25_1 = PressLeftD
L26_1 = "MINIGAME_LEFT_D"
L27_1 = _U
L28_1 = "MINIGAME_CIGAR_PRODUCTION.KEY_MAPPING_PRESS_LEFT_D"
L27_1 = L27_1(L28_1)
L28_1 = L20_1.D
L24_1(L25_1, L26_1, L27_1, L28_1)
L24_1 = RegisterKey
L25_1 = PressRightW
L26_1 = "MINIGAME_RIGHT_W"
L27_1 = _U
L28_1 = "MINIGAME_CIGAR_PRODUCTION.KEY_MAPPING_PRESS_RIGHT_W"
L27_1 = L27_1(L28_1)
L28_1 = L21_1.ARROW_UP
L24_1(L25_1, L26_1, L27_1, L28_1)
L24_1 = RegisterKey
L25_1 = PressRightS
L26_1 = "MINIGAME_RIGHT_S"
L27_1 = _U
L28_1 = "MINIGAME_CIGAR_PRODUCTION.KEY_MAPPING_PRESS_RIGHT_S"
L27_1 = L27_1(L28_1)
L28_1 = L21_1.ARROW_DOWN
L24_1(L25_1, L26_1, L27_1, L28_1)
L24_1 = RegisterKey
L25_1 = PressRightA
L26_1 = "MINIGAME_RIGHT_A"
L27_1 = _U
L28_1 = "MINIGAME_CIGAR_PRODUCTION.KEY_MAPPING_PRESS_RIGHT_A"
L27_1 = L27_1(L28_1)
L28_1 = L21_1.LEFT_ARROW
L24_1(L25_1, L26_1, L27_1, L28_1)
L24_1 = RegisterKey
L25_1 = PressRightD
L26_1 = "MINIGAME_RIGHT_D"
L27_1 = _U
L28_1 = "MINIGAME_CIGAR_PRODUCTION.KEY_MAPPING_PRESS_RIGHT_D"
L27_1 = L27_1(L28_1)
L28_1 = L21_1.RIGHT_ARROW
L24_1(L25_1, L26_1, L27_1, L28_1)
function L24_1(A0_2, A1_2, A2_2, A3_2, A4_2, A5_2)
  local L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2
  L6_2 = L7_1
  if L6_2 then
    return
  end
  L6_2 = FreezePlayer
  L7_2 = PlayerId
  L7_2 = L7_2()
  L8_2 = true
  L6_2(L7_2, L8_2)
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "RCore Minigame: Setting up settings"
  L6_2(L7_2)
  L10_1 = A2_2
  L11_1 = A3_2
  L6_2 = true
  L7_1 = L6_2
  L6_2 = RequestStreamedTextureDict
  L7_2 = "helicopterhud"
  L8_2 = false
  L6_2(L7_2, L8_2)
  L6_2 = TriggerLocalClientEvent
  L7_2 = "onHud"
  L8_2 = false
  L9_2 = "HIDE_HUD"
  L10_2 = "MINIGAME_STARTED"
  L6_2(L7_2, L8_2, L9_2, L10_2)
  L6_2 = LoadAnim
  L7_2 = L10_1
  L6_2(L7_2)
  L6_2 = TaskPlayAnim
  L7_2 = PlayerPedId
  L7_2 = L7_2()
  L8_2 = L10_1
  L9_2 = L11_1
  L10_2 = 5.0
  L11_2 = 1.0
  L12_2 = -1
  L13_2 = 17
  L14_2 = 0
  L15_2 = 0
  L16_2 = 0
  L17_2 = 0
  L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2)
  L6_2 = L15_1
  L7_2 = A0_2
  L8_2 = A1_2
  L6_2(L7_2, L8_2)
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "RCore Minigame: Keys are defined!"
  L6_2(L7_2)
  L6_2 = L20_1
  if not L6_2 then
    L6_2 = dbg
    L6_2 = L6_2.critical
    L7_2 = "Minigame keys are not defined!"
    L6_2(L7_2)
    return
  end
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "RCore Minigame: Starting minigame"
  L6_2(L7_2)
  L6_2 = A5_2
  L7_2 = A4_2
  L8_2 = CreateThread
  function L9_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3
    while true do
      L0_3 = L7_1
      if not L0_3 then
        break
      end
      L0_3 = Wait
      L1_3 = 0
      L0_3(L1_3)
      L0_3 = DrawSprite
      L1_3 = "helicopterhud"
      L2_3 = "hud_outline"
      L3_3 = L4_1
      L4_3 = 0.8
      L5_3 = L0_1
      L6_3 = L0_1
      L7_3 = GetAspectRatio
      L7_3 = L7_3()
      L6_3 = L6_3 * L7_3
      L7_3 = 0.0
      L8_3 = 255
      L9_3 = 255
      L10_3 = 255
      L11_3 = 255
      L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
      L0_3 = DrawRect
      L1_3 = 0.4
      L2_3 = 0.8
      L3_3 = L2_1
      L4_3 = L2_1
      L5_3 = GetAspectRatio
      L5_3 = L5_3()
      L4_3 = L4_3 * L5_3
      L5_3 = 0
      L6_3 = 0
      L7_3 = 0
      L8_3 = 150
      L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3)
      L0_3 = DrawSprite
      L1_3 = "helicopterhud"
      L2_3 = "hud_outline"
      L3_3 = L5_1
      L4_3 = 0.8
      L5_3 = L0_1
      L6_3 = L0_1
      L7_3 = GetAspectRatio
      L7_3 = L7_3()
      L6_3 = L6_3 * L7_3
      L7_3 = 0.0
      L8_3 = 255
      L9_3 = 255
      L10_3 = 255
      L11_3 = 255
      L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3)
      L0_3 = DrawRect
      L1_3 = 0.6
      L2_3 = 0.8
      L3_3 = L2_1
      L4_3 = L2_1
      L5_3 = GetAspectRatio
      L5_3 = L5_3()
      L4_3 = L4_3 * L5_3
      L5_3 = 0
      L6_3 = 0
      L7_3 = 0
      L8_3 = 150
      L0_3(L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3)
      L0_3 = table
      L0_3 = L0_3.size
      L1_3 = L8_1
      L0_3 = L0_3(L1_3)
      L1_3 = table
      L1_3 = L1_3.size
      L2_3 = L9_1
      L1_3 = L1_3(L2_3)
      L0_3 = L0_3 + L1_3
      if 0 == L0_3 then
        L0_3 = KeyPressMinigameSuccess
        L0_3()
        L0_3 = L7_2
        if L0_3 then
          L0_3 = dbg
          L0_3 = L0_3.debug
          L1_3 = "Minigame: Invoking succ callback"
          L0_3(L1_3)
          L0_3 = L7_2
          L0_3()
        end
        L0_3 = false
        L7_1 = L0_3
        return
      end
      L0_3 = pairs
      L1_3 = L8_1
      L0_3, L1_3, L2_3, L3_3 = L0_3(L1_3)
      for L4_3, L5_3 in L0_3, L1_3, L2_3, L3_3 do
        L6_3 = L5_3.time
        L7_3 = L3_1
        L8_3 = GetFrameTime
        L8_3 = L8_3()
        L7_3 = L7_3 * L8_3
        L6_3 = L6_3 + L7_3
        L5_3.time = L6_3
        L6_3 = DrawLetter
        L7_3 = L5_3.letter
        L8_3 = L5_3.time
        L9_3 = 0.8
        L10_3 = math
        L10_3 = L10_3.abs
        L11_3 = L5_3.time
        L12_3 = L4_1
        L11_3 = L11_3 - L12_3
        L10_3 = L10_3(L11_3)
        L11_3 = L6_1
        L10_3 = L10_3 <= L11_3
        L6_3(L7_3, L8_3, L9_3, L10_3)
        L6_3 = L5_3.time
        L7_3 = L4_1
        L8_3 = L6_1
        L7_3 = L7_3 + L8_3
        if L6_3 > L7_3 then
          L6_3 = L16_1
          L6_3()
          L6_3 = L6_2
          if L6_3 then
            L6_3 = dbg
            L6_3 = L6_3.debug
            L7_3 = "Minigame: Invoking failure callback"
            L6_3(L7_3)
            L6_3 = L6_2
            L6_3()
          end
          L6_3 = false
          L7_1 = L6_3
          return
        end
      end
      L0_3 = pairs
      L1_3 = L9_1
      L0_3, L1_3, L2_3, L3_3 = L0_3(L1_3)
      for L4_3, L5_3 in L0_3, L1_3, L2_3, L3_3 do
        L6_3 = L5_3.time
        L7_3 = L3_1
        L8_3 = GetFrameTime
        L8_3 = L8_3()
        L7_3 = L7_3 * L8_3
        L6_3 = L6_3 + L7_3
        L5_3.time = L6_3
        L6_3 = L19_1
        L7_3 = L5_3.letter
        L8_3 = L5_3.time
        L9_3 = 1
        L8_3 = L9_3 - L8_3
        L9_3 = 0.8
        L10_3 = math
        L10_3 = L10_3.abs
        L11_3 = L5_3.time
        L12_3 = 1
        L11_3 = L12_3 - L11_3
        L12_3 = L5_1
        L11_3 = L11_3 - L12_3
        L10_3 = L10_3(L11_3)
        L11_3 = L6_1
        L10_3 = L10_3 <= L11_3
        L6_3(L7_3, L8_3, L9_3, L10_3)
        L6_3 = L5_3.time
        L7_3 = L5_1
        L8_3 = L6_1
        L7_3 = L7_3 + L8_3
        if L6_3 > L7_3 then
          L6_3 = L16_1
          L6_3()
          L6_3 = L6_2
          if L6_3 then
            L6_3 = dbg
            L6_3 = L6_3.debug
            L7_3 = "Minigame: Invoking failure callback"
            L6_3(L7_3)
            L6_3 = L6_2
            L6_3()
          end
          L6_3 = false
          L7_1 = L6_3
          return
        end
      end
    end
  end
  L10_2 = "cl-lib-cigar-production code name: Phoenix"
  L8_2(L9_2, L10_2)
end
StartCigarProduction = L24_1
function L24_1(A0_2)
  local L1_2, L2_2
  L1_2 = RequestAnimDict
  L2_2 = A0_2
  L1_2(L2_2)
  while true do
    L1_2 = HasAnimDictLoaded
    L2_2 = A0_2
    L1_2 = L1_2(L2_2)
    if L1_2 then
      break
    end
    L1_2 = Wait
    L2_2 = 0
    L1_2(L2_2)
  end
end
LoadAnim = L24_1
