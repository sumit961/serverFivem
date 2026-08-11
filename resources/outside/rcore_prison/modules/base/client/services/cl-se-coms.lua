local L0_1, L1_1
L0_1 = {}
COMSService = L0_1
L0_1 = COMSService
function L1_1(A0_2)
  local L1_2, L2_2
  L1_2 = OpenStartCOMS
  L2_2 = A0_2
  L1_2(L2_2)
end
L0_1.RequestMenu = L1_1
L0_1 = COMSService
function L1_1(A0_2, ...)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = TriggerEvent
  L2_2 = "rcore_prison:client:heartbeat"
  L3_2 = A0_2
  L4_2 = ...
  L1_2(L2_2, L3_2, L4_2)
end
L0_1.SendHeartbeat = L1_1
L0_1 = COMSService
function L1_1()
  local L0_2, L1_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_COMS
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = L0_2.GetCOMS
  return L1_2()
end
L0_1.GetUser = L1_1
L0_1 = COMSService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_COMS
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = Config
  L1_2 = L1_2.COMS
  L1_2 = L1_2.RenderPerollTime
  if not L1_2 then
    return
  end
  L1_2 = SH
  L1_2 = L1_2.isRenderingTime
  if L1_2 then
    return
  end
  L1_2 = SH
  L1_2.isRenderingTime = true
  L1_2 = promise
  L1_2 = L1_2.new
  L1_2 = L1_2()
  L2_2 = CreateThread
  function L3_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3
    while true do
      L0_3 = SH
      L0_3 = L0_3.isRenderingTime
      if not L0_3 then
        break
      end
      L0_3 = Wait
      L1_3 = 0
      L0_3(L1_3)
      L0_3 = L0_2.GetCOMS
      L0_3 = L0_3()
      L1_3 = "%s / %s"
      L2_3 = L1_3
      L1_3 = L1_3.format
      L3_3 = L0_3.perollAmount
      L4_3 = L0_3.perollTarget
      L1_3 = L1_3(L2_3, L3_3, L4_3)
      L2_3 = L0_3.perollAmount
      L3_3 = L0_3.perollTarget
      if L2_3 < L3_3 then
        L2_3 = Config
        L2_3 = L2_3.COMS
        L2_3 = L2_3.RenderPerollTime
        if not L2_3 then
        else
          L2_3 = PrisonService
          L2_3 = L2_3.DisplayTime
          L3_3 = _U
          L4_3 = "CS.DISPLAY_PEROLL_TIME"
          L5_3 = L1_3
          L3_3, L4_3, L5_3 = L3_3(L4_3, L5_3)
          L2_3(L3_3, L4_3, L5_3)
        end
      else
        L2_3 = L0_3.perollAmount
        L3_3 = L0_3.perollTarget
        if L2_3 >= L3_3 then
          L2_3 = SH
          L2_3.isRenderingTime = false
          L2_3 = Text
          L2_3 = L2_3.Hide
          L2_3()
          L2_3 = L1_2
          L3_3 = L2_3
          L2_3 = L2_3.resolve
          L4_3 = true
          L2_3(L3_3, L4_3)
        end
      end
      L2_3 = Wait
      L3_3 = 1000
      L2_3(L3_3)
    end
  end
  L4_2 = "cl-se-coms code name: Phoenix"
  L2_2(L3_2, L4_2)
  L2_2 = Citizen
  L2_2 = L2_2.Await
  L3_2 = L1_2
  L2_2(L3_2)
  L2_2 = dbg
  L2_2 = L2_2.debug
  L3_2 = "RequestRelease: COMS parolle has finished - release citizen. 2/2."
  L2_2(L3_2)
  L2_2 = TriggerServerEvent
  L3_2 = "rcore_prison:server:requestPerollRelease"
  L2_2(L3_2)
end
L0_1.RenderPerollTime = L1_1
L0_1 = COMSService
function L1_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = COMSModel
  L1_2 = L1_2()
  L2_2 = Object
  L2_2 = L2_2.getStorage
  L3_2 = STORAGE_COMS
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    return
  end
  L1_2 = A0_2
  L3_2 = L2_2.RegisterActiveCOMS
  L4_2 = L1_2
  L3_2 = L3_2(L4_2)
  return L3_2
end
L0_1.RegisterSession = L1_1
L0_1 = COMSService
function L1_1()
  local L0_2, L1_2, L2_2, L3_2
  L0_2 = Object
  L0_2 = L0_2.getStorage
  L1_2 = STORAGE_COMS
  L0_2 = L0_2(L1_2)
  if not L0_2 then
    return
  end
  L1_2 = SH
  L1_2.isRenderingTime = false
  L1_2 = SH
  L1_2.screen = nil
  L1_2 = SH
  L1_2.zoneId = nil
  L1_2 = L0_2.UnregisterActiveCOMS
  L1_2()
  L1_2 = HelpKeys
  L1_2 = L1_2.Hide
  L1_2()
  L1_2 = Text
  L1_2 = L1_2.Hide
  L1_2()
  L1_2 = FrontendService
  L1_2 = L1_2.SendReactMessage
  L2_2 = FE_EVENTS
  L2_2 = L2_2.LOAD_APP
  L3_2 = {}
  L3_2.visible = false
  L3_2.screen = nil
  L1_2(L2_2, L3_2)
  L1_2 = DestroyAllMenus
  L1_2()
  L1_2 = ClearAllHelpMessages
  L1_2()
  L1_2 = BusyspinnerOff
  L1_2()
  L1_2 = TextService
  L1_2 = L1_2.Hide
  L1_2()
end
L0_1.ClearUserData = L1_1
