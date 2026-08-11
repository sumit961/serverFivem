local L0_1, L1_1, L2_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L0_2 = StopResource
  L1_2 = "qb-prison"
  L0_2(L1_2)
  L0_2 = isResourcePresentProvideless
  L1_2 = PoliceResources
  L1_2 = L1_2.QB
  L0_2 = L0_2(L1_2)
  if L0_2 then
    L0_2 = AssetDeployer
    L1_2 = L0_2
    L0_2 = L0_2.registerFileDeploy
    L2_2 = "jail-api-event"
    L3_2 = PoliceResources
    L3_2 = L3_2.QB
    L4_2 = "server/main.lua"
    function L5_2(A0_3, A1_3)
      local L2_3, L3_3, L4_3, L5_3
      L3_3 = A0_3
      L2_3 = A0_3.strtrim
      L2_3 = L2_3(L3_3)
      L3_3 = L2_3
      L2_3 = L2_3.gsub
      L4_3 = "}$"
      L5_3 = ""
      L2_3 = L2_3(L3_3, L4_3, L5_3)
      A0_3 = L2_3
      L2_3 = [[

            -- This part was added by rcore_prison!
            -- Backward compatibility for this event is done by rcore_prison.
            -- Path: rcore_prison/modules/base/server/api/sv-jailPlayer.lua

            local blockInvoke = true

            if blockInvoke then
                return
            end

                ]]
      L3_3 = appendQBJailEvent
      L4_3 = A0_3
      L5_3 = L2_3
      L3_3 = L3_3(L4_3, L5_3)
      A0_3 = L3_3
      return A0_3
    end
    L6_2 = {}
    L0_2(L1_2, L2_2, L3_2, L4_2, L5_2, L6_2)
    L0_2 = AssetDeployer
    L1_2 = L0_2
    L0_2 = L0_2.registerFileDeploy
    L2_2 = "jail-api-commands"
    L3_2 = PoliceResources
    L3_2 = L3_2.QB
    L4_2 = "server/main.lua"
    function L5_2(A0_3, A1_3)
      local L2_3, L3_3, L4_3, L5_3
      L3_3 = A0_3
      L2_3 = A0_3.strtrim
      L2_3 = L2_3(L3_3)
      L3_3 = L2_3
      L2_3 = L2_3.gsub
      L4_3 = "}$"
      L5_3 = ""
      L2_3 = L2_3(L3_3, L4_3, L5_3)
      A0_3 = L2_3
      L2_3 = appendQBJailCommand
      L3_3 = A0_3
      L2_3 = L2_3(L3_3)
      A0_3 = L2_3
      L2_3 = appendQBUnjailCommand
      L3_3 = A0_3
      L2_3 = L2_3(L3_3)
      A0_3 = L2_3
      return A0_3
    end
    L6_2 = {}
    L0_2(L1_2, L2_2, L3_2, L4_2, L5_2, L6_2)
  end
end
L2_1 = "qb-policejob code name: Phoenix"
L0_1(L1_1, L2_1)
