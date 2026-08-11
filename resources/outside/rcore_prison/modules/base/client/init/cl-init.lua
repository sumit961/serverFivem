local L0_1, L1_1, L2_1
PrisonService = nil
L0_1 = GetPlayerServerId
L1_1 = PlayerId
L1_1, L2_1 = L1_1()
L0_1 = L0_1(L1_1, L2_1)
MyServerId = L0_1
IsAtBooth = false
L0_1 = {}
RestrictZone = L0_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2
  L0_2 = RemoveAllTargetZones
  L0_2()
  L0_2 = Object
  L0_2 = L0_2.getService
  L1_2 = SERVICE_PRISONER
  L0_2 = L0_2(L1_2)
  PrisonService = L0_2
  L0_2 = PrisonService
  if not L0_2 then
    L0_2 = dbg
    L0_2 = L0_2.critical
    L1_2 = "Cannot find prison service - cl-init.lua"
    L0_2(L1_2)
    return
  end
  L0_2 = FreezePlayer
  L1_2 = PlayerId
  L1_2 = L1_2()
  L2_2 = false
  L0_2(L1_2, L2_2)
  L0_2 = Text
  L0_2 = L0_2.Hide
  L0_2()
  L0_2 = HelpKeys
  L0_2 = L0_2.Hide
  L0_2()
  L0_2 = Subtitles
  L0_2 = L0_2.Hide
  L0_2()
  L0_2 = Sound
  L0_2 = L0_2.StopAlarm
  L0_2()
  L0_2 = Sound
  L0_2 = L0_2.HandleAnnoucement
  L1_2 = Config
  L1_2 = L1_2.PrisonYardAnnoucement
  L0_2(L1_2)
  L0_2 = Mugshot
  L0_2 = L0_2.ResetHeadMemory
  L0_2()
  L0_2 = FreezeEntityPosition
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = false
  L0_2(L1_2, L2_2)
  L0_2 = FreezePlayer
  L1_2 = PlayerId
  L1_2 = L1_2()
  L2_2 = false
  L0_2(L1_2, L2_2)
  while true do
    L0_2 = Config
    L0_2 = L0_2.DebugEnviroment
    if not L0_2 then
      break
    end
    L0_2 = Wait
    L1_2 = 0
    L0_2(L1_2)
    L0_2 = DrawDebugPolyZone
    L1_2 = SH
    L1_2 = L1_2.data
    L1_2 = L1_2.prisonVertices
    L2_2 = 1
    L0_2(L1_2, L2_2)
  end
end
L2_1 = "cl-init code name: Phoenix"
L0_1(L1_1, L2_1)
