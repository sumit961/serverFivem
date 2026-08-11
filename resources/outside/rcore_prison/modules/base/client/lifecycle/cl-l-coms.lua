local L0_1, L1_1, L2_1
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "StartComsIntro"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2
  if A0_2 then
    L2_2 = A1_2.name
    L3_2 = A1_2.perollTarget
    L4_2 = A1_2.perollAmount
    L5_2 = {}
    L6_2 = {}
    L6_2.time = 4000
    L7_2 = _U
    L8_2 = "CS.COMMUNITY_SERVICE_STARTED_PROLOG"
    L9_2 = L2_2
    L10_2 = L4_2
    L11_2 = L3_2
    L7_2 = L7_2(L8_2, L9_2, L10_2, L11_2)
    L6_2.text = L7_2
    L7_2 = {}
    L7_2.time = 4000
    L8_2 = _U
    L9_2 = "CS.COMMUNITY_SERVICE_FINISH_PROLOG"
    L8_2 = L8_2(L9_2)
    L7_2.text = L8_2
    L5_2[1] = L6_2
    L5_2[2] = L7_2
    L6_2 = promise
    L6_2 = L6_2.new
    L6_2 = L6_2()
    L7_2 = 1
    L8_2 = #L5_2
    L9_2 = 1
    for L10_2 = L7_2, L8_2, L9_2 do
      L11_2 = L5_2[L10_2]
      L12_2 = L11_2.text
      L13_2 = L11_2.time
      L14_2 = Subtitles
      L14_2 = L14_2.Show
      L15_2 = L12_2
      L14_2(L15_2)
      L14_2 = Wait
      L15_2 = L13_2 + 300
      L14_2(L15_2)
      L14_2 = #L5_2
      if L10_2 >= L14_2 then
        L15_2 = L6_2
        L14_2 = L6_2.resolve
        L16_2 = true
        L14_2(L15_2, L16_2)
      end
    end
    L7_2 = Citizen
    L7_2 = L7_2.Await
    L8_2 = L6_2
    L7_2(L8_2)
    L7_2 = Subtitles
    L7_2 = L7_2.Hide
    L7_2()
  end
end
L0_1(L1_1, L2_1)
L0_1 = NetworkService
L0_1 = L0_1.RegisterNetEvent
L1_1 = "comsHeartbeat"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2
  if A0_2 then
    if A1_2 then
      L2_2 = dbg
      L2_2 = L2_2.debug
      L3_2 = "Your coms session data were loaded!"
      L2_2(L3_2)
      L2_2 = COMSService
      L2_2 = L2_2.RegisterSession
      L3_2 = A1_2
      L2_2(L3_2)
      L2_2 = COMSService
      L2_2 = L2_2.RenderPerollTime
      L2_2()
    else
      L2_2 = dbg
      L2_2 = L2_2.debug
      L3_2 = "Your coms session data were deleted!"
      L2_2(L3_2)
      L2_2 = COMSService
      L2_2 = L2_2.ClearUserData
      L2_2()
    end
  end
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNetEvent
L1_1 = "rcore_prison:client:UnregisterCOMSArea"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  L2_2 = CWZones
  if L2_2 then
    L2_2 = next
    L3_2 = CWZones
    L2_2 = L2_2(L3_2)
    if L2_2 then
      L2_2 = CWZones
      L2_2 = L2_2[A1_2]
      L3_2 = pairs
      L4_2 = L2_2
      L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
      for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
        L9_2 = L8_2.decal
        L10_2 = L8_2.entities
        if not L10_2 then
          L10_2 = L8_2.entities
          L10_2 = L10_2.entity
          if L10_2 then
            L11_2 = DeleteStashOnGround
            L12_2 = A1_2
            L13_2 = L7_2
            L14_2 = L10_2
            L15_2 = true
            L11_2(L12_2, L13_2, L14_2, L15_2)
          end
          L11_2 = dbg
          L11_2 = L11_2.critical
          L12_2 = "Lifecycle - COMS: Failed to stash on ground, failed to find any entities! SERVER ID: %s ZONE-ID: %s"
          L13_2 = A0_2
          L14_2 = A1_2
          L11_2(L12_2, L13_2, L14_2)
        end
        if L9_2 then
          L10_2 = IsDecalAlive
          L11_2 = L9_2
          L10_2 = L10_2(L11_2)
          if L10_2 then
            L10_2 = RemoveDecal
            L11_2 = L9_2
            L10_2(L11_2)
          end
        end
        if L7_2 then
          L10_2 = SetTimeout
          L11_2 = 0
          function L12_2()
            local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3
            L0_3 = pairs
            L1_3 = WorldCOMS
            L0_3, L1_3, L2_3, L3_3 = L0_3(L1_3)
            for L4_3, L5_3 in L0_3, L1_3, L2_3, L3_3 do
              L6_3 = L5_3.vertices
              if L6_3 then
                L6_3 = L5_3.id
                L7_3 = A1_2
                if L6_3 == L7_3 then
                  L6_3 = L5_3.vertices
                  L7_3 = L7_2
                  L6_3 = L6_3[L7_3]
                  if L6_3 then
                    L6_3 = L5_3.vertices
                    L7_3 = L7_2
                    L6_3[L7_3] = nil
                  end
                end
              end
            end
          end
          L10_2(L11_2, L12_2)
        end
      end
    end
  end
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNetEvent
L1_1 = "rcore_prison:client:removeVertice"
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = A0_2.zoneId
  L2_2 = A0_2.verticeId
  L3_2 = CWZones
  L3_2 = L3_2[L1_2]
  L4_2 = pairs
  L5_2 = WorldCOMS
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = L9_2.vertices
    if L10_2 then
      L10_2 = L9_2.id
      if L10_2 == L1_2 then
        L10_2 = L9_2.vertices
        L10_2 = L10_2[L2_2]
        if L10_2 then
          L10_2 = L9_2.vertices
          L10_2[L2_2] = nil
        end
      end
    end
  end
  if L3_2 then
    L4_2 = next
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    if L4_2 then
      L4_2 = L3_2[L2_2]
      if L4_2 then
        L5_2 = L4_2.decal
        L6_2 = L4_2.entities
        L6_2 = L6_2.entity
        if L5_2 then
          L7_2 = IsDecalAlive
          L8_2 = L5_2
          L7_2 = L7_2(L8_2)
          if L7_2 then
            L7_2 = RemoveDecal
            L8_2 = L5_2
            L7_2(L8_2)
          end
        end
        if L6_2 then
          L7_2 = DeleteStashOnGround
          L8_2 = L1_2
          L9_2 = L2_2
          L10_2 = L6_2
          L7_2(L8_2, L9_2, L10_2)
        end
      end
    end
  end
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNetEvent
L1_1 = "rcore_prison:client:registerZone"
function L2_1(A0_2)
  local L1_2, L2_2
  L1_2 = RegisterCOMSArea
  L2_2 = A0_2
  L1_2(L2_2)
end
L0_1(L1_1, L2_1)
L0_1 = RegisterNuiCallback
L1_1 = "getCOMS"
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = callback
  L2_2 = L2_2.await
  L3_2 = "rcore_prison:server:getAllComs"
  L4_2 = false
  L5_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L3_2 = A1_2
  L4_2 = L2_2
  L3_2(L4_2)
end
L0_1(L1_1, L2_1)
