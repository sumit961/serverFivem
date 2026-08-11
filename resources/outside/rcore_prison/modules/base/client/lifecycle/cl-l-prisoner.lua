local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "prisonerHeartbeat"
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2
  if A0_2 then
    if A1_2 then
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "Your prisoner data were loaded from server!"
      L3_2(L4_2)
      L3_2 = FreezeEntityPosition
      L4_2 = PlayerPedId
      L4_2 = L4_2()
      L5_2 = false
      L3_2(L4_2, L5_2)
      L3_2 = FreezePlayer
      L4_2 = PlayerId
      L4_2 = L4_2()
      L5_2 = false
      L3_2(L4_2, L5_2)
      L3_2 = PrisonService
      L3_2 = L3_2.RegisterPrisoner
      L4_2 = A1_2
      L3_2(L4_2)
      L3_2 = Config
      L3_2 = L3_2.DisplayPrisonMapForEverybody
      if not L3_2 then
        L3_2 = SetTimeout
        L4_2 = 0
        function L5_2()
          local L0_3, L1_3
          L0_3 = pcall
          function L1_3()
            local L0_4, L1_4
            L0_4 = PrisonService
            L0_4 = L0_4.DisplayPrisonMap
            L0_4()
          end
          L0_3 = L0_3(L1_3)
        end
        L3_2(L4_2, L5_2)
      end
      L3_2 = PrisonService
      L3_2 = L3_2.HandleJailTime
      L4_2 = A1_2
      if L4_2 then
        L4_2 = L4_2.jail_time
      end
      L5_2 = A1_2
      if L5_2 then
        L5_2 = L5_2.hasTimeChange
      end
      L6_2 = A1_2
      if L6_2 then
        L6_2 = L6_2.solitary_time
      end
      L3_2(L4_2, L5_2, L6_2)
    else
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "Your prisoner data were deleted!"
      L3_2(L4_2)
      L3_2 = PrisonService
      L3_2 = L3_2.ClearPrisonerData
      L4_2 = A2_2
      L3_2(L4_2)
    end
  end
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNuiCallback
L1_1 = "getPrisoners"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = callback
  L2_2 = L2_2.await
  L3_2 = "rcore_prison:server:getAllPrisoners"
  L4_2 = false
  L5_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L3_2 = A1_2
  L4_2 = L2_2
  L3_2(L4_2)
end
L0_1(L1_1, L2_1)
