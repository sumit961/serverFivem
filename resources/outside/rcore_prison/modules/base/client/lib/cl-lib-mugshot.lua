local L0_1, L1_1
L0_1 = {}
Mugshot = L0_1
L0_1 = Mugshot
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = 1
  L1_2 = 32
  L2_2 = 1
  for L3_2 = L0_2, L1_2, L2_2 do
    L4_2 = IsPedheadshotValid
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    if L4_2 then
      L4_2 = UnregisterPedheadshot
      L5_2 = L3_2
      L4_2(L5_2)
    end
  end
end
L0_1.ResetHeadMemory = L1_1
L0_1 = Mugshot
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L0_2 = promise
  L0_2 = L0_2.new
  L0_2 = L0_2()
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = RegisterPedheadshotTransparent
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L2_2 = RegisterPedheadshot_3
    L3_2 = L1_2
    L2_2 = L2_2(L3_2)
  end
  L3_2 = dbg
  L3_2 = L3_2.debug
  L4_2 = "[MUGSHOT] Registering ped headshot 1/4"
  L3_2(L4_2)
  while true do
    L3_2 = IsPedheadshotReady
    L4_2 = L2_2
    L3_2 = L3_2(L4_2)
    if L3_2 then
      L3_2 = IsPedheadshotValid
      L4_2 = L2_2
      L3_2 = L3_2(L4_2)
      if L3_2 then
        break
      end
    end
    L3_2 = Wait
    L4_2 = 150
    L3_2(L4_2)
  end
  L3_2 = dbg
  L3_2 = L3_2.debug
  L4_2 = "[MUGSHOT] Ped headshot loaded, initiating payload 2/4"
  L3_2(L4_2)
  L3_2 = GetPedheadshotTxdString
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = string
  L4_2 = L4_2.format
  L5_2 = "https://nui-img/%s/%s"
  L6_2 = L3_2
  L7_2 = L3_2
  L4_2 = L4_2(L5_2, L6_2, L7_2)
  L5_2 = {}
  L5_2.url = L4_2
  L5_2.txd = L3_2
  L5_2.nuiImage = L4_2
  L6_2 = GetPlayerServerId
  L7_2 = PlayerId
  L7_2, L8_2 = L7_2()
  L6_2 = L6_2(L7_2, L8_2)
  L5_2.id = L6_2
  L6_2 = dbg
  L6_2 = L6_2.debug
  L7_2 = "[MUGSHOT] Payload defined, initiating converting of ped mugshot 3/4"
  L6_2(L7_2)
  L6_2 = FrontendService
  L6_2 = L6_2.SendReactMessage
  L7_2 = "convertImage"
  L8_2 = L5_2
  L6_2(L7_2, L8_2)
  L6_2 = CreateThread
  function L7_2()
    local L0_3, L1_3, L2_3
    L0_3 = FrontendService
    L0_3 = L0_3.RegisterFrontendCallback
    L1_3 = "convertedMugshot"
    function L2_3(A0_4)
      local L1_4, L2_4, L3_4, L4_4
      L1_4 = A0_4
      L2_4 = next
      L3_4 = L1_4
      L2_4 = L2_4(L3_4)
      if L2_4 then
        L2_4 = L0_2
        L3_4 = L2_4
        L2_4 = L2_4.resolve
        L4_4 = L1_4
        L2_4(L3_4, L4_4)
      else
        L2_4 = L0_2
        L3_4 = L2_4
        L2_4 = L2_4.reject
        L4_4 = L1_4
        L2_4(L3_4, L4_4)
      end
      L2_4 = UnregisterPedheadshot
      L3_4 = L1_4.txd
      L2_4(L3_4)
      L2_4 = dbg
      L2_4 = L2_4.debug
      L3_4 = "[MUGSHOT] Obtained mugshot data, returning 4/4"
      L2_4(L3_4)
    end
    L0_3(L1_3, L2_3)
  end
  L8_2 = "cl-lib-mugshot code name: Phoenix"
  L6_2(L7_2, L8_2)
  L6_2 = Citizen
  L6_2 = L6_2.Await
  L7_2 = L0_2
  return L6_2(L7_2)
end
L0_1.GetFromPed = L1_1
