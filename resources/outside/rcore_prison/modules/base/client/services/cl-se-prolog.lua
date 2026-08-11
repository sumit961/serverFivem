local L0_1, L1_1, L2_1, L3_1
L0_1 = {}
PrologService = L0_1
L0_1 = false
L1_1 = PrologService
function L2_1()
  local L0_2, L1_2
  L0_2 = L0_1
  return L0_2
end
L1_1.GetPlayerCutSceneState = L2_1
L1_1 = PrologService
function L2_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L0_2 = Config
  L0_2 = L0_2.Prolog
  L0_2 = L0_2.ResetCache
  if L0_2 then
    L0_2 = Cache
    L0_2 = L0_2.GetPrologKVP
    L0_2 = L0_2()
    if 1 == L0_2 then
      L0_2 = dbg
      L0_2 = L0_2.debug
      L1_2 = "Prolog cache reset"
      L0_2(L1_2)
      L0_2 = Cache
      L0_2 = L0_2.DeletePrologKVP
      L0_2()
    end
  end
  L0_2 = Cache
  L0_2 = L0_2.GetPrologKVP
  L0_2 = L0_2()
  if 0 == L0_2 then
    L0_2 = true
    L0_1 = L0_2
    L0_2 = dbg
    L0_2 = L0_2.debug
    L1_2 = "Prolog started"
    L0_2(L1_2)
    L0_2 = Cache
    L0_2 = L0_2.SetPrologKVP
    L1_2 = 1
    L0_2(L1_2)
    L0_2 = SH
    L0_2 = L0_2.data
    L0_2 = L0_2.cameraProlog
    L1_2 = PlayerPedId
    L1_2 = L1_2()
    L2_2 = NetworkStartSoloTutorialSession
    L2_2()
    L2_2 = FreezeEntityPosition
    L3_2 = L1_2
    L4_2 = true
    L2_2(L3_2, L4_2)
    L2_2 = DisplayRadar
    L3_2 = false
    L2_2(L3_2)
    L2_2 = SH
    L2_2 = L2_2.data
    L2_2 = L2_2.prisonYard
    L3_2 = 0
    L4_2 = SetEntityCoords
    L5_2 = L1_2
    L6_2 = L2_2
    L4_2(L5_2, L6_2)
    L4_2 = SetEntityHeading
    L5_2 = L1_2
    L6_2 = L3_2
    L4_2(L5_2, L6_2)
    L4_2 = L0_2.initCameraPosition
    L5_2 = L0_2.initCameraRot
    L6_2 = L0_2.initGameplayCamRot
    L7_2 = L0_2.points
    L8_2 = CreateCameraLib
    L9_2 = L4_2
    L10_2 = L5_2
    L8_2 = L8_2(L9_2, L10_2)
    L9_2 = Wait
    L10_2 = 0
    L9_2(L10_2)
    L9_2 = SetGameplayCamRelativeRotation
    L10_2 = L6_2.x
    L11_2 = L6_2.y
    L12_2 = L6_2.z
    L9_2(L10_2, L11_2, L12_2)
    L9_2 = HelpKeys
    L9_2 = L9_2.Show
    L10_2 = {}
    L11_2 = {}
    L12_2 = _U
    L13_2 = "PROLOG.SKIP_HELP_LABEL"
    L12_2 = L12_2(L13_2)
    L11_2.label = L12_2
    L11_2.keyName = "E"
    L10_2[1] = L11_2
    L11_2 = Config
    L11_2 = L11_2.Prolog
    L11_2 = L11_2.SkipHelpKeyPosition
    L9_2(L10_2, L11_2)
    L9_2 = L8_2.startRendering
    L9_2()
    L9_2 = L8_2.skippable
    L9_2()
    L9_2 = L8_2.ActiveFXEffect
    L10_2 = CameraAnimFX
    L10_2 = L10_2.INTRO_LOGO
    L11_2 = 0
    L12_2 = false
    L9_2(L10_2, L11_2, L12_2)
    L9_2 = dbg
    L9_2 = L9_2.debug
    L10_2 = ">> Start init camera prolog"
    L9_2(L10_2)
    L9_2 = L8_2.moveCameraSmoothlyFromPoints
    L10_2 = L7_2
    L9_2(L10_2)
    L9_2 = dbg
    L9_2 = L9_2.debug
    L10_2 = ">> Finish init camera prolog"
    L9_2(L10_2)
    L9_2 = L8_2.exitCameraSmoothly
    L10_2 = 3000
    L9_2(L10_2)
    L9_2 = L8_2.StopAllFXEffects
    L9_2()
    L9_2 = Subtitles
    L9_2 = L9_2.Hide
    L9_2()
    L9_2 = HelpKeys
    L9_2 = L9_2.Hide
    L9_2()
    L9_2 = SetTimeout
    L10_2 = 1000
    function L11_2()
      local L0_3, L1_3, L2_3
      L0_3 = DisplayRadar
      L1_3 = true
      L0_3(L1_3)
      L0_3 = NetworkEndTutorialSession
      L0_3()
      L0_3 = FreezeEntityPosition
      L1_3 = L1_2
      L2_3 = false
      L0_3(L1_3, L2_3)
      L0_3 = false
      L0_1 = L0_3
    end
    L9_2(L10_2, L11_2)
    L9_2 = true
    return L9_2
  else
    L0_2 = dbg
    L0_2 = L0_2.debug
    L1_2 = "Skipping prolog as it has already been started before."
    L0_2(L1_2)
    L0_2 = true
    return L0_2
  end
end
L1_1.Start = L2_1
L1_1 = callback
L1_1 = L1_1.register
L2_1 = "prolog"
function L3_1()
  local L0_2, L1_2
  L0_2 = PrologService
  L0_2 = L0_2.Start
  L0_2()
  L0_2 = true
  return L0_2
end
L1_1(L2_1, L3_1)
