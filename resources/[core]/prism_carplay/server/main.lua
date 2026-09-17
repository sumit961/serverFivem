

local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1, L11_1, L12_1, L13_1, L14_1, L15_1, L16_1, L17_1, L18_1, L19_1, L20_1
function L0_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  L3_2 = exports
  L3_2 = L3_2.prism_carplay
  L4_2 = L3_2
  L3_2 = L3_2.uploadFivemanage
  L5_2 = A0_2
  L6_2 = A1_2
  L7_2 = A2_2
  L3_2(L4_2, L5_2, L6_2, L7_2)
end
L1_1 = GetResourcePath
L2_1 = GetCurrentResourceName
L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1, L11_1, L12_1, L13_1, L14_1, L15_1, L16_1, L17_1, L18_1, L19_1, L20_1 = L2_1()
L1_1 = L1_1(L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1, L11_1, L12_1, L13_1, L14_1, L15_1, L16_1, L17_1, L18_1, L19_1, L20_1)
-- Create the recording directory using the runtime's platform-independent
-- resource command. The previous implementation used a Windows-only shell
-- redirect and could leave a stray `nul` file on Linux servers.
if not LoadResourceFile(GetCurrentResourceName(), "recordings/dashcam/.keep") then
  SaveResourceFile(GetCurrentResourceName(), "recordings/dashcam/.keep", "", -1)
end
L2_1 = SetHttpHandler
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L2_2 = A0_2.method
  if "GET" ~= L2_2 then
    L2_2 = A1_2.send
    L3_2 = ""
    L2_2(L3_2)
    return
  end
  L2_2 = A0_2.path
  L4_2 = L2_2
  L3_2 = L2_2.match
  L5_2 = "^/recordings/dashcam/(.+%.webm)$"
  L3_2 = L3_2(L4_2, L5_2)
  if not L3_2 then
    L4_2 = A1_2.send
    L5_2 = ""
    L4_2(L5_2)
    return
  end
  L5_2 = L3_2
  L4_2 = L3_2.find
  L6_2 = "%.%."
  L4_2 = L4_2(L5_2, L6_2)
  if not L4_2 then
    L5_2 = L3_2
    L4_2 = L3_2.find
    L6_2 = "/"
    L4_2 = L4_2(L5_2, L6_2)
    if not L4_2 then
      L5_2 = L3_2
      L4_2 = L3_2.find
      L6_2 = "\\"
      L4_2 = L4_2(L5_2, L6_2)
      if not L4_2 then
        goto lbl_37
      end
    end
  end
  L4_2 = A1_2.send
  L5_2 = ""
  L4_2(L5_2)
  do return end
  ::lbl_37::
  L4_2 = L1_1
  L5_2 = "/recordings/dashcam/"
  L6_2 = L3_2
  L4_2 = L4_2 .. L5_2 .. L6_2
  L5_2 = io
  L5_2 = L5_2.open
  L6_2 = L4_2
  L7_2 = "rb"
  L5_2 = L5_2(L6_2, L7_2)
  if L5_2 then
    L7_2 = L5_2
    L6_2 = L5_2.read
    L8_2 = "*all"
    L6_2 = L6_2(L7_2, L8_2)
    L8_2 = L5_2
    L7_2 = L5_2.close
    L7_2(L8_2)
    L7_2 = A1_2.writeHead
    L8_2 = 200
    L9_2 = {}
    L9_2["Content-Type"] = "video/webm"
    L10_2 = tostring
    L11_2 = #L6_2
    L10_2 = L10_2(L11_2)
    L9_2["Content-Length"] = L10_2
    L9_2["Access-Control-Allow-Origin"] = "*"
    L7_2(L8_2, L9_2)
    L7_2 = A1_2.send
    L8_2 = L6_2
    L7_2(L8_2)
  else
    L6_2 = A1_2.writeHead
    L7_2 = 404
    L6_2(L7_2)
    L6_2 = A1_2.send
    L7_2 = ""
    L6_2(L7_2)
  end
end
L2_1(L3_1)
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = "dashcam_recordings_"
  L2_2 = A0_2
  L1_2 = L1_2 .. L2_2
  L2_2 = GetResourceKvpString
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L3_2 = json
    L3_2 = L3_2.decode
    L4_2 = L2_2
    L3_2 = L3_2(L4_2)
    if not L3_2 then
      L3_2 = {}
    end
    return L3_2
  end
  L3_2 = {}
  return L3_2
end
function L3_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = "dashcam_recordings_"
  L3_2 = A0_2
  L2_2 = L2_2 .. L3_2
  L3_2 = SetResourceKvp
  L4_2 = L2_2
  L5_2 = json
  L5_2 = L5_2.encode
  L6_2 = A1_2
  L5_2, L6_2 = L5_2(L6_2)
  L3_2(L4_2, L5_2, L6_2)
end
function L4_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2
  L0_2 = tostring
  L1_2 = os
  L1_2 = L1_2.time
  L1_2, L2_2, L3_2, L4_2, L5_2 = L1_2()
  L0_2 = L0_2(L1_2, L2_2, L3_2, L4_2, L5_2)
  L1_2 = "_"
  L2_2 = tostring
  L3_2 = math
  L3_2 = L3_2.random
  L4_2 = 1000
  L5_2 = 9999
  L3_2, L4_2, L5_2 = L3_2(L4_2, L5_2)
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L0_2 = L0_2 .. L1_2 .. L2_2
  return L0_2
end
L5_1 = RegisterNetEvent
L6_1 = "prism-carplay:server:startRecording"
function L7_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = source
  L2_2 = GetPlayerIdentifierByType
  L3_2 = L1_2
  L4_2 = "license"
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 then
    L2_2 = tostring
    L3_2 = L1_2
    L2_2 = L2_2(L3_2)
  end
  L3_2 = os
  L3_2 = L3_2.date
  L4_2 = "%Y%m%d_%H%M%S"
  L3_2 = L3_2(L4_2)
  L4_2 = "dashcam_"
  L6_2 = L2_2
  L5_2 = L2_2.gsub
  L7_2 = ":"
  L8_2 = "_"
  L5_2 = L5_2(L6_2, L7_2, L8_2)
  L6_2 = "_"
  L7_2 = L3_2
  L4_2 = L4_2 .. L5_2 .. L6_2 .. L7_2
  L5_2 = Config
  L5_2 = L5_2.Dashcam
  if L5_2 then
    L5_2 = Config
    L5_2 = L5_2.Dashcam
    L5_2 = L5_2.maxDuration
    if L5_2 then
      goto lbl_33
    end
  end
  L5_2 = 300
  ::lbl_33::
  L6_2 = exports
  L6_2 = L6_2["ts-medialib"]
  L7_2 = L6_2
  L6_2 = L6_2.requestVideoRecording
  L8_2 = L1_2
  L9_2 = {}
  L10_2 = A0_2 or L10_2
  if not A0_2 then
    L10_2 = L5_2
  end
  L9_2.duration = L10_2
  L9_2.quality = 0.5
  L9_2.format = "webm"
  L9_2.filename = L4_2
  L9_2.saveFolder = "recordings/dashcam"
  function L10_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3, L7_3, L8_3
    if A0_3 then
      L1_3 = A0_3.filename
      if L1_3 then
        L1_3 = Config
        L1_3 = L1_3.Dashcam
        if L1_3 then
          L1_3 = Config
          L1_3 = L1_3.Dashcam
          L1_3 = L1_3.storageType
          if L1_3 then
            goto lbl_16
          end
        end
        L1_3 = "local"
        ::lbl_16::
        function L2_3(A0_4, A1_4)
          local L2_4, L3_4, L4_4, L5_4, L6_4, L7_4
          L2_4 = L2_1
          L3_4 = L2_2
          L2_4 = L2_4(L3_4)
          L3_4 = {}
          L4_4 = L4_1
          L4_4 = L4_4()
          L3_4.id = L4_4
          L4_4 = A0_3.filename
          L3_4.filename = L4_4
          L4_4 = A0_3.path
          L3_4.path = L4_4
          L4_4 = "Recording "
          L5_4 = os
          L5_4 = L5_4.date
          L6_4 = "%m/%d/%Y %H:%M"
          L5_4 = L5_4(L6_4)
          L4_4 = L4_4 .. L5_4
          L3_4.name = L4_4
          L4_4 = os
          L4_4 = L4_4.date
          L5_4 = "%m/%d/%Y"
          L4_4 = L4_4(L5_4)
          L3_4.date = L4_4
          L3_4.duration = "00:00"
          L4_4 = os
          L4_4 = L4_4.time
          L4_4 = L4_4()
          L3_4.timestamp = L4_4
          L4_4 = L1_3
          L3_4.storageType = L4_4
          L3_4.url = A0_4
          L3_4.fivemanageId = A1_4
          L4_4 = table
          L4_4 = L4_4.insert
          L5_4 = L2_4
          L6_4 = 1
          L7_4 = L3_4
          L4_4(L5_4, L6_4, L7_4)
          L4_4 = L3_1
          L5_4 = L2_2
          L6_4 = L2_4
          L4_4(L5_4, L6_4)
          L4_4 = TriggerClientEvent
          L5_4 = "prism-carplay:client:recordingSaved"
          L6_4 = L1_2
          L7_4 = L3_4
          L4_4(L5_4, L6_4, L7_4)
        end
        if "fivemanage" == L1_3 then
          L3_3 = A0_3.filename
          L5_3 = L3_3
          L4_3 = L3_3.match
          L6_3 = "%.webm$"
          L4_3 = L4_3(L5_3, L6_3)
          if not L4_3 then
            L4_3 = L3_3
            L5_3 = ".webm"
            L4_3 = L4_3 .. L5_3
            L3_3 = L4_3
          end
          L4_3 = L1_1
          L5_3 = "/recordings/dashcam/"
          L6_3 = L3_3
          L4_3 = L4_3 .. L5_3 .. L6_3
          L5_3 = L0_1
          L6_3 = L4_3
          L7_3 = L3_3
          function L8_3(A0_4)
            local L1_4, L2_4, L3_4
            if A0_4 then
              L1_4 = L2_3
              L2_4 = A0_4.url
              L3_4 = A0_4.id
              L1_4(L2_4, L3_4)
              L1_4 = os
              L1_4 = L1_4.remove
              L2_4 = L4_3
              L1_4(L2_4)
            else
              L1_4 = L2_3
              L2_4 = nil
              L3_4 = nil
              L1_4(L2_4, L3_4)
            end
          end
          L5_3(L6_3, L7_3, L8_3)
        else
          L3_3 = L2_3
          L4_3 = nil
          L5_3 = nil
          L3_3(L4_3, L5_3)
        end
      end
    end
  end
  L6_2(L7_2, L8_2, L9_2, L10_2)
end
L5_1(L6_1, L7_1)
L5_1 = RegisterNetEvent
L6_1 = "prism-carplay:server:uploadRecording"
function L7_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  L1_2 = source
  L2_2 = GetPlayerIdentifierByType
  L3_2 = L1_2
  L4_2 = "license"
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 then
    L2_2 = tostring
    L3_2 = L1_2
    L2_2 = L2_2(L3_2)
  end
  L3_2 = L2_1
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = ipairs
  L5_2 = L3_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = L9_2.id
    if L10_2 == A0_2 then
      L10_2 = L9_2.url
      if L10_2 then
        L10_2 = TriggerClientEvent
        L11_2 = "prism-carplay:client:uploadComplete"
        L12_2 = L1_2
        L13_2 = A0_2
        L14_2 = L9_2.url
        L10_2(L11_2, L12_2, L13_2, L14_2)
        return
      end
      L10_2 = L9_2.filename
      L12_2 = L10_2
      L11_2 = L10_2.match
      L13_2 = "%.webm$"
      L11_2 = L11_2(L12_2, L13_2)
      if not L11_2 then
        L11_2 = L10_2
        L12_2 = ".webm"
        L11_2 = L11_2 .. L12_2
        L10_2 = L11_2
      end
      L11_2 = L1_1
      L12_2 = "/recordings/dashcam/"
      L13_2 = L10_2
      L11_2 = L11_2 .. L12_2 .. L13_2
      L12_2 = L0_1
      L13_2 = L11_2
      L14_2 = L10_2
      function L15_2(A0_3)
        local L1_3, L2_3, L3_3, L4_3, L5_3
        if A0_3 then
          L2_3 = L8_2
          L1_3 = L3_2
          L1_3 = L1_3[L2_3]
          L2_3 = A0_3.url
          L1_3.url = L2_3
          L2_3 = L8_2
          L1_3 = L3_2
          L1_3 = L1_3[L2_3]
          L2_3 = A0_3.id
          L1_3.fivemanageId = L2_3
          L2_3 = L8_2
          L1_3 = L3_2
          L1_3 = L1_3[L2_3]
          L1_3.storageType = "fivemanage"
          L1_3 = L3_1
          L2_3 = L2_2
          L3_3 = L3_2
          L1_3(L2_3, L3_3)
          L1_3 = os
          L1_3 = L1_3.remove
          L2_3 = L11_2
          L1_3(L2_3)
          L1_3 = TriggerClientEvent
          L2_3 = "prism-carplay:client:uploadComplete"
          L3_3 = L1_2
          L4_3 = A0_2
          L5_3 = A0_3.url
          L1_3(L2_3, L3_3, L4_3, L5_3)
        else
          L1_3 = TriggerClientEvent
          L2_3 = "prism-carplay:client:uploadFailed"
          L3_3 = L1_2
          L4_3 = A0_2
          L1_3(L2_3, L3_3, L4_3)
        end
      end
      L12_2(L13_2, L14_2, L15_2)
      return
    end
  end
  L4_2 = TriggerClientEvent
  L5_2 = "prism-carplay:client:uploadFailed"
  L6_2 = L1_2
  L7_2 = A0_2
  L4_2(L5_2, L6_2, L7_2)
end
L5_1(L6_1, L7_1)
L5_1 = RegisterNetEvent
L6_1 = "prism-carplay:server:stopRecording"
function L7_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L1_2 = source
  L2_2 = GetPlayerIdentifierByType
  L3_2 = L1_2
  L4_2 = "license"
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 then
    L2_2 = tostring
    L3_2 = L1_2
    L2_2 = L2_2(L3_2)
  end
  L3_2 = TriggerClientEvent
  L4_2 = "ts-medialib:stopRecording"
  L5_2 = L1_2
  L3_2(L4_2, L5_2)
  L3_2 = L2_1
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = #L3_2
  if L4_2 > 0 then
    L4_2 = math
    L4_2 = L4_2.floor
    L5_2 = A0_2 / 3600
    L4_2 = L4_2(L5_2)
    L5_2 = math
    L5_2 = L5_2.floor
    L6_2 = A0_2 % 3600
    L6_2 = L6_2 / 60
    L5_2 = L5_2(L6_2)
    L6_2 = A0_2 % 60
    L7_2 = L3_2[1]
    L8_2 = string
    L8_2 = L8_2.format
    L9_2 = "%02d:%02d:%02d"
    L10_2 = L4_2
    L11_2 = L5_2
    L12_2 = L6_2
    L8_2 = L8_2(L9_2, L10_2, L11_2, L12_2)
    L7_2.duration = L8_2
    L7_2 = L3_1
    L8_2 = L2_2
    L9_2 = L3_2
    L7_2(L8_2, L9_2)
  end
end
L5_1(L6_1, L7_1)
L5_1 = RegisterNetEvent
L6_1 = "prism-carplay:server:getRecordings"
function L7_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L0_2 = source
  L1_2 = GetPlayerIdentifierByType
  L2_2 = L0_2
  L3_2 = "license"
  L1_2 = L1_2(L2_2, L3_2)
  if not L1_2 then
    L1_2 = tostring
    L2_2 = L0_2
    L1_2 = L1_2(L2_2)
  end
  L2_2 = L2_1
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  L3_2 = TriggerClientEvent
  L4_2 = "prism-carplay:client:receiveRecordings"
  L5_2 = L0_2
  L6_2 = L2_2
  L3_2(L4_2, L5_2, L6_2)
end
L5_1(L6_1, L7_1)
L5_1 = RegisterNetEvent
L6_1 = "prism-carplay:server:deleteRecording"
function L7_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2
  L1_2 = source
  L2_2 = GetPlayerIdentifierByType
  L3_2 = L1_2
  L4_2 = "license"
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 then
    L2_2 = tostring
    L3_2 = L1_2
    L2_2 = L2_2(L3_2)
  end
  L3_2 = L2_1
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = ipairs
  L5_2 = L3_2
  L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
  for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
    L10_2 = L9_2.id
    if L10_2 == A0_2 then
      L10_2 = L9_2.fivemanageId
      if L10_2 then
        L10_2 = exports
        L10_2 = L10_2.prism_carplay
        L11_2 = L10_2
        L10_2 = L10_2.deleteFivemanage
        L12_2 = L9_2.fivemanageId
        L10_2(L11_2, L12_2)
      end
      L10_2 = L9_2.filename
      if L10_2 then
        L10_2 = L9_2.filename
        L12_2 = L10_2
        L11_2 = L10_2.match
        L13_2 = "%.webm$"
        L11_2 = L11_2(L12_2, L13_2)
        if not L11_2 then
          L11_2 = L10_2
          L12_2 = ".webm"
          L11_2 = L11_2 .. L12_2
          L10_2 = L11_2
        end
        L11_2 = L1_1
        L12_2 = "/recordings/dashcam/"
        L13_2 = L10_2
        L11_2 = L11_2 .. L12_2 .. L13_2
        L12_2 = os
        L12_2 = L12_2.remove
        L13_2 = L11_2
        L12_2(L13_2)
      end
      L10_2 = table
      L10_2 = L10_2.remove
      L11_2 = L3_2
      L12_2 = L8_2
      L10_2(L11_2, L12_2)
      break
    end
  end
  L4_2 = L3_1
  L5_2 = L2_2
  L6_2 = L3_2
  L4_2(L5_2, L6_2)
  L4_2 = TriggerClientEvent
  L5_2 = "prism-carplay:client:receiveRecordings"
  L6_2 = L1_2
  L7_2 = L3_2
  L4_2(L5_2, L6_2, L7_2)
end
L5_1(L6_1, L7_1)
L5_1 = RegisterNetEvent
L6_1 = "prism-carplay:server:clearAllRecordings"
function L7_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
  L0_2 = source
  L1_2 = GetPlayerIdentifierByType
  L2_2 = L0_2
  L3_2 = "license"
  L1_2 = L1_2(L2_2, L3_2)
  if not L1_2 then
    L1_2 = tostring
    L2_2 = L0_2
    L1_2 = L1_2(L2_2)
  end
  L2_2 = L2_1
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  L3_2 = ipairs
  L4_2 = L2_2
  L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
  for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
    L9_2 = L8_2.fivemanageId
    if L9_2 then
      L9_2 = exports
      L9_2 = L9_2.prism_carplay
      L10_2 = L9_2
      L9_2 = L9_2.deleteFivemanage
      L11_2 = L8_2.fivemanageId
      L9_2(L10_2, L11_2)
    end
    L9_2 = L8_2.filename
    if L9_2 then
      L9_2 = L8_2.filename
      L11_2 = L9_2
      L10_2 = L9_2.match
      L12_2 = "%.webm$"
      L10_2 = L10_2(L11_2, L12_2)
      if not L10_2 then
        L10_2 = L9_2
        L11_2 = ".webm"
        L10_2 = L10_2 .. L11_2
        L9_2 = L10_2
      end
      L10_2 = L1_1
      L11_2 = "/recordings/dashcam/"
      L12_2 = L9_2
      L10_2 = L10_2 .. L11_2 .. L12_2
      L11_2 = os
      L11_2 = L11_2.remove
      L12_2 = L10_2
      L11_2(L12_2)
    end
  end
  L3_2 = L3_1
  L4_2 = L1_2
  L5_2 = {}
  L3_2(L4_2, L5_2)
  L3_2 = TriggerClientEvent
  L4_2 = "prism-carplay:client:receiveRecordings"
  L5_2 = L0_2
  L6_2 = {}
  L3_2(L4_2, L5_2, L6_2)
end
L5_1(L6_1, L7_1)
L5_1 = {}
function L6_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = GetPlayerPed
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if not L1_2 or 0 == L1_2 then
    L2_2 = nil
    return L2_2
  end
  L2_2 = GetVehiclePedIsIn
  L3_2 = L1_2
  L4_2 = false
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 or 0 == L2_2 then
    L3_2 = nil
    return L3_2
  end
  L3_2 = GetVehicleNumberPlateText
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = L3_2
  L3_2 = L3_2.gsub
  L5_2 = "%s+"
  L6_2 = ""
  L3_2 = L3_2(L4_2, L5_2, L6_2)
  L4_2 = L3_2
  L3_2 = L3_2.upper
  return L3_2(L4_2)
end
function L7_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = os
  L2_2 = L2_2.time
  L2_2 = L2_2()
  L3_2 = A0_2
  L4_2 = "_"
  L5_2 = A1_2
  L3_2 = L3_2 .. L4_2 .. L5_2
  L4_2 = L5_1
  L4_2 = L4_2[L3_2]
  if L4_2 then
    L4_2 = L5_1
    L4_2 = L4_2[L3_2]
    L4_2 = L2_2 - L4_2
    if L4_2 < 1 then
      L4_2 = true
      return L4_2
    end
  end
  L4_2 = L5_1
  L4_2[L3_2] = L2_2
  L4_2 = false
  return L4_2
end
L8_1 = CreateThread
function L9_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  while true do
    L0_2 = Wait
    L1_2 = 60000
    L0_2(L1_2)
    L0_2 = os
    L0_2 = L0_2.time
    L0_2 = L0_2()
    L1_2 = pairs
    L2_2 = L5_1
    L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
    for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
      L7_2 = L0_2 - L6_2
      if L7_2 > 60 then
        L7_2 = L5_1
        L7_2[L5_2] = nil
      end
    end
  end
end
L8_1(L9_1)
function L8_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  if not A0_2 then
    return
  end
  L2_2 = "carplay_"
  L4_2 = A0_2
  L3_2 = A0_2.gsub
  L5_2 = "%s+"
  L6_2 = ""
  L3_2 = L3_2(L4_2, L5_2, L6_2)
  L2_2 = L2_2 .. L3_2
  L3_2 = SetResourceKvp
  L4_2 = L2_2
  L5_2 = json
  L5_2 = L5_2.encode
  L6_2 = {}
  L7_2 = true == A1_2
  L6_2.installed = L7_2
  L5_2, L6_2, L7_2 = L5_2(L6_2)
  L3_2(L4_2, L5_2, L6_2, L7_2)
end
function L9_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  if not A0_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = "carplay_"
  L3_2 = A0_2
  L2_2 = A0_2.gsub
  L4_2 = "%s+"
  L5_2 = ""
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L1_2 = L1_2 .. L2_2
  L2_2 = GetResourceKvpString
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L3_2 = json
    L3_2 = L3_2.decode
    L4_2 = L2_2
    L3_2 = L3_2(L4_2)
    L4_2 = L3_2 or L4_2
    if L3_2 then
      L4_2 = L3_2.installed
      L4_2 = true == L4_2
    end
    return L4_2
  end
  L3_2 = false
  return L3_2
end
L10_1 = RegisterNetEvent
L11_1 = "prism-carplay:server:getCarplayInstalled"
function L12_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = source
  if A0_2 then
    L2_2 = type
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if "string" == L2_2 then
      goto lbl_10
    end
  end
  do return end
  ::lbl_10::
  L2_2 = L6_1
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L4_2 = A0_2
    L3_2 = A0_2.gsub
    L5_2 = "%s+"
    L6_2 = ""
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    L4_2 = L3_2
    L3_2 = L3_2.upper
    L3_2 = L3_2(L4_2)
    if L2_2 == L3_2 then
      goto lbl_24
    end
  end
  do return end
  ::lbl_24::
  L3_2 = L9_1
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = TriggerClientEvent
  L5_2 = "prism-carplay:client:receiveCarplayInstalled"
  L6_2 = L1_2
  L7_2 = A0_2
  L8_2 = L3_2
  L4_2(L5_2, L6_2, L7_2, L8_2)
end
L10_1(L11_1, L12_1)
L10_1 = RegisterNetEvent
L11_1 = "prism-carplay:server:saveCarplayInstalled"
function L12_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = source
  if not A0_2 then
    return
  end
  L3_2 = L6_1
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  if L3_2 then
    L5_2 = A0_2
    L4_2 = A0_2.gsub
    L6_2 = "%s+"
    L7_2 = ""
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    L5_2 = L4_2
    L4_2 = L4_2.upper
    L4_2 = L4_2(L5_2)
    if L3_2 == L4_2 then
      goto lbl_25
    end
  end
  L4_2 = print
  L5_2 = "^1[Prism-CarPlay]^7 Security: Player "
  L6_2 = L2_2
  L7_2 = " attempted to modify carplay data for vehicle they are not in"
  L5_2 = L5_2 .. L6_2 .. L7_2
  L4_2(L5_2)
  do return end
  ::lbl_25::
  L4_2 = L9_1
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  L5_2 = L8_1
  L6_2 = A0_2
  L7_2 = A1_2
  L5_2(L6_2, L7_2)
  if L4_2 and not A1_2 then
    L5_2 = RemoveCarplayItem
    L6_2 = L2_2
    L7_2 = A0_2
    L5_2(L6_2, L7_2)
  end
  L5_2 = TriggerClientEvent
  L6_2 = "prism-carplay:client:carplayInstalledUpdated"
  L7_2 = -1
  L8_2 = A0_2
  L9_2 = true == A1_2
  L5_2(L6_2, L7_2, L8_2, L9_2)
end
L10_1(L11_1, L12_1)
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  if not A0_2 then
    return
  end
  L2_2 = "tunerchip_"
  L4_2 = A0_2
  L3_2 = A0_2.gsub
  L5_2 = "%s+"
  L6_2 = ""
  L3_2 = L3_2(L4_2, L5_2, L6_2)
  L2_2 = L2_2 .. L3_2
  L3_2 = SetResourceKvp
  L4_2 = L2_2
  L5_2 = json
  L5_2 = L5_2.encode
  L6_2 = A1_2
  L5_2, L6_2 = L5_2(L6_2)
  L3_2(L4_2, L5_2, L6_2)
end
function L11_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  if not A0_2 then
    L1_2 = nil
    return L1_2
  end
  L1_2 = "tunerchip_"
  L3_2 = A0_2
  L2_2 = A0_2.gsub
  L4_2 = "%s+"
  L5_2 = ""
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L1_2 = L1_2 .. L2_2
  L2_2 = GetResourceKvpString
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L3_2 = json
    L3_2 = L3_2.decode
    L4_2 = L2_2
    return L3_2(L4_2)
  end
  L3_2 = nil
  return L3_2
end
function L12_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = type
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if "table" ~= L1_2 then
    L1_2 = nil
    return L1_2
  end
  L1_2 = {}
  L2_2 = A0_2.installed
  L2_2 = true == L2_2
  L1_2.installed = L2_2
  L2_2 = type
  L3_2 = A0_2.boostPower
  L2_2 = L2_2(L3_2)
  if "number" == L2_2 then
    L2_2 = math
    L2_2 = L2_2.max
    L3_2 = 0
    L4_2 = math
    L4_2 = L4_2.min
    L5_2 = 100
    L6_2 = A0_2.boostPower
    L4_2, L5_2, L6_2 = L4_2(L5_2, L6_2)
    L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
    if L2_2 then
      goto lbl_33
    end
  end
  L2_2 = 0
  ::lbl_33::
  L1_2.boostPower = L2_2
  L2_2 = type
  L3_2 = A0_2.gearChange
  L2_2 = L2_2(L3_2)
  if "number" == L2_2 then
    L2_2 = math
    L2_2 = L2_2.max
    L3_2 = 0
    L4_2 = math
    L4_2 = L4_2.min
    L5_2 = 100
    L6_2 = A0_2.gearChange
    L4_2, L5_2, L6_2 = L4_2(L5_2, L6_2)
    L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
    if L2_2 then
      goto lbl_51
    end
  end
  L2_2 = 0
  ::lbl_51::
  L1_2.gearChange = L2_2
  L2_2 = type
  L3_2 = A0_2.acceleration
  L2_2 = L2_2(L3_2)
  if "number" == L2_2 then
    L2_2 = math
    L2_2 = L2_2.max
    L3_2 = 0
    L4_2 = math
    L4_2 = L4_2.min
    L5_2 = 100
    L6_2 = A0_2.acceleration
    L4_2, L5_2, L6_2 = L4_2(L5_2, L6_2)
    L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
    if L2_2 then
      goto lbl_69
    end
  end
  L2_2 = 0
  ::lbl_69::
  L1_2.acceleration = L2_2
  L2_2 = type
  L3_2 = A0_2.brakes
  L2_2 = L2_2(L3_2)
  if "number" == L2_2 then
    L2_2 = math
    L2_2 = L2_2.max
    L3_2 = 0
    L4_2 = math
    L4_2 = L4_2.min
    L5_2 = 100
    L6_2 = A0_2.brakes
    L4_2, L5_2, L6_2 = L4_2(L5_2, L6_2)
    L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
    if L2_2 then
      goto lbl_87
    end
  end
  L2_2 = 0
  ::lbl_87::
  L1_2.brakes = L2_2
  return L1_2
end
L13_1 = RegisterNetEvent
L14_1 = "prism-carplay:server:getTunerChipData"
function L15_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = source
  if A0_2 then
    L2_2 = type
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if "string" == L2_2 then
      goto lbl_10
    end
  end
  do return end
  ::lbl_10::
  L2_2 = L6_1
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L4_2 = A0_2
    L3_2 = A0_2.gsub
    L5_2 = "%s+"
    L6_2 = ""
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    L4_2 = L3_2
    L3_2 = L3_2.upper
    L3_2 = L3_2(L4_2)
    if L2_2 == L3_2 then
      goto lbl_24
    end
  end
  do return end
  ::lbl_24::
  L3_2 = L11_1
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = TriggerClientEvent
  L5_2 = "prism-carplay:client:receiveTunerChipData"
  L6_2 = L1_2
  L7_2 = A0_2
  L8_2 = L3_2
  L4_2(L5_2, L6_2, L7_2, L8_2)
end
L13_1(L14_1, L15_1)
L13_1 = RegisterNetEvent
L14_1 = "prism-carplay:server:saveTunerChipData"
function L15_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L2_2 = source
  if not A0_2 or not A1_2 then
    return
  end
  L3_2 = L6_1
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  if L3_2 then
    L5_2 = A0_2
    L4_2 = A0_2.gsub
    L6_2 = "%s+"
    L7_2 = ""
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    L5_2 = L4_2
    L4_2 = L4_2.upper
    L4_2 = L4_2(L5_2)
    if L3_2 == L4_2 then
      goto lbl_27
    end
  end
  L4_2 = print
  L5_2 = "^1[Prism-CarPlay]^7 Security: Player "
  L6_2 = L2_2
  L7_2 = " attempted to modify tuner chip data for vehicle they are not in"
  L5_2 = L5_2 .. L6_2 .. L7_2
  L4_2(L5_2)
  do return end
  ::lbl_27::
  L4_2 = L12_1
  L5_2 = A1_2
  L4_2 = L4_2(L5_2)
  A1_2 = L4_2
  if not A1_2 then
    return
  end
  L4_2 = L11_1
  L5_2 = A0_2
  L4_2 = L4_2(L5_2)
  if L4_2 then
    L5_2 = L4_2.installed
    if L5_2 then
      L5_2 = A1_2.installed
      if not L5_2 then
        L5_2 = RemoveTunerChip
        L6_2 = L2_2
        L7_2 = A0_2
        L5_2(L6_2, L7_2)
      end
    end
  end
  L5_2 = L10_1
  L6_2 = A0_2
  L7_2 = A1_2
  L5_2(L6_2, L7_2)
  L5_2 = TriggerClientEvent
  L6_2 = "prism-carplay:client:tunerChipDataUpdated"
  L7_2 = -1
  L8_2 = A0_2
  L9_2 = A1_2
  L5_2(L6_2, L7_2, L8_2, L9_2)
end
L13_1(L14_1, L15_1)
function L13_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  if not A0_2 then
    return
  end
  L2_2 = "modifications_"
  L4_2 = A0_2
  L3_2 = A0_2.gsub
  L5_2 = "%s+"
  L6_2 = ""
  L3_2 = L3_2(L4_2, L5_2, L6_2)
  L2_2 = L2_2 .. L3_2
  L3_2 = SetResourceKvp
  L4_2 = L2_2
  L5_2 = json
  L5_2 = L5_2.encode
  L6_2 = A1_2
  L5_2, L6_2 = L5_2(L6_2)
  L3_2(L4_2, L5_2, L6_2)
end
function L14_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  if not A0_2 then
    L1_2 = nil
    return L1_2
  end
  L1_2 = "modifications_"
  L3_2 = A0_2
  L2_2 = A0_2.gsub
  L4_2 = "%s+"
  L5_2 = ""
  L2_2 = L2_2(L3_2, L4_2, L5_2)
  L1_2 = L1_2 .. L2_2
  L2_2 = GetResourceKvpString
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L3_2 = json
    L3_2 = L3_2.decode
    L4_2 = L2_2
    return L3_2(L4_2)
  end
  L3_2 = nil
  return L3_2
end
L15_1 = RegisterNetEvent
L16_1 = "prism-carplay:server:getModificationsData"
function L17_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = source
  if A0_2 then
    L2_2 = type
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if "string" == L2_2 then
      goto lbl_10
    end
  end
  do return end
  ::lbl_10::
  L2_2 = L6_1
  L3_2 = L1_2
  L2_2 = L2_2(L3_2)
  if L2_2 then
    L4_2 = A0_2
    L3_2 = A0_2.gsub
    L5_2 = "%s+"
    L6_2 = ""
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    L4_2 = L3_2
    L3_2 = L3_2.upper
    L3_2 = L3_2(L4_2)
    if L2_2 == L3_2 then
      goto lbl_24
    end
  end
  do return end
  ::lbl_24::
  L3_2 = L14_1
  L4_2 = A0_2
  L3_2 = L3_2(L4_2)
  L4_2 = TriggerClientEvent
  L5_2 = "prism-carplay:client:receiveModificationsData"
  L6_2 = L1_2
  L7_2 = A0_2
  L8_2 = L3_2
  L4_2(L5_2, L6_2, L7_2, L8_2)
end
L15_1(L16_1, L17_1)
L15_1 = RegisterNetEvent
L16_1 = "prism-carplay:server:saveModificationsData"
function L17_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = source
  if not A0_2 or not A1_2 then
    return
  end
  L3_2 = L6_1
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  if L3_2 then
    L5_2 = A0_2
    L4_2 = A0_2.gsub
    L6_2 = "%s+"
    L7_2 = ""
    L4_2 = L4_2(L5_2, L6_2, L7_2)
    L5_2 = L4_2
    L4_2 = L4_2.upper
    L4_2 = L4_2(L5_2)
    if L3_2 == L4_2 then
      goto lbl_27
    end
  end
  L4_2 = print
  L5_2 = "^1[Prism-CarPlay]^7 Security: Player "
  L6_2 = L2_2
  L7_2 = " attempted to modify vehicle data they are not in"
  L5_2 = L5_2 .. L6_2 .. L7_2
  L4_2(L5_2)
  do return end
  ::lbl_27::
  L4_2 = type
  L5_2 = A1_2
  L4_2 = L4_2(L5_2)
  if "table" ~= L4_2 then
    return
  end
  L4_2 = L13_1
  L5_2 = A0_2
  L6_2 = A1_2
  L4_2(L5_2, L6_2)
  L4_2 = TriggerClientEvent
  L5_2 = "prism-carplay:client:modificationsDataUpdated"
  L6_2 = -1
  L7_2 = A0_2
  L8_2 = A1_2
  L4_2(L5_2, L6_2, L7_2, L8_2)
end
L15_1(L16_1, L17_1)
L15_1 = {}
function L16_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  if not A0_2 or not A1_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = L6_1
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  if not L2_2 then
    L3_2 = false
    return L3_2
  end
  L4_2 = A1_2
  L3_2 = A1_2.gsub
  L5_2 = "%s+"
  L6_2 = ""
  L3_2 = L3_2(L4_2, L5_2, L6_2)
  L4_2 = L3_2
  L3_2 = L3_2.upper
  L3_2 = L3_2(L4_2)
  L4_2 = L2_2 == L3_2
  return L4_2
end
function L17_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = type
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if "table" ~= L1_2 then
    L1_2 = nil
    return L1_2
  end
  L1_2 = {}
  L2_2 = type
  L3_2 = A0_2.id
  L2_2 = L2_2(L3_2)
  if "string" == L2_2 then
    L2_2 = A0_2.id
    L3_2 = L2_2
    L2_2 = L2_2.sub
    L4_2 = 1
    L5_2 = 100
    L2_2 = L2_2(L3_2, L4_2, L5_2)
    if L2_2 then
      goto lbl_23
    end
  end
  L2_2 = nil
  ::lbl_23::
  L1_2.id = L2_2
  L2_2 = type
  L3_2 = A0_2.title
  L2_2 = L2_2(L3_2)
  if "string" == L2_2 then
    L2_2 = A0_2.title
    L3_2 = L2_2
    L2_2 = L2_2.sub
    L4_2 = 1
    L5_2 = 200
    L2_2 = L2_2(L3_2, L4_2, L5_2)
    if L2_2 then
      goto lbl_37
    end
  end
  L2_2 = "Unknown"
  ::lbl_37::
  L1_2.title = L2_2
  L2_2 = type
  L3_2 = A0_2.artist
  L2_2 = L2_2(L3_2)
  if "string" == L2_2 then
    L2_2 = A0_2.artist
    L3_2 = L2_2
    L2_2 = L2_2.sub
    L4_2 = 1
    L5_2 = 200
    L2_2 = L2_2(L3_2, L4_2, L5_2)
    if L2_2 then
      goto lbl_51
    end
  end
  L2_2 = "Unknown"
  ::lbl_51::
  L1_2.artist = L2_2
  L2_2 = type
  L3_2 = A0_2.filePath
  L2_2 = L2_2(L3_2)
  if "string" == L2_2 then
    L2_2 = A0_2.filePath
    L3_2 = L2_2
    L2_2 = L2_2.sub
    L4_2 = 1
    L5_2 = 500
    L2_2 = L2_2(L3_2, L4_2, L5_2)
    if L2_2 then
      goto lbl_65
    end
  end
  L2_2 = nil
  ::lbl_65::
  L1_2.filePath = L2_2
  L2_2 = type
  L3_2 = A0_2.url
  L2_2 = L2_2(L3_2)
  if "string" == L2_2 then
    L2_2 = A0_2.url
    L3_2 = L2_2
    L2_2 = L2_2.sub
    L4_2 = 1
    L5_2 = 500
    L2_2 = L2_2(L3_2, L4_2, L5_2)
    if L2_2 then
      goto lbl_79
    end
  end
  L2_2 = nil
  ::lbl_79::
  L1_2.url = L2_2
  L2_2 = type
  L3_2 = A0_2.thumbnail
  L2_2 = L2_2(L3_2)
  if "string" == L2_2 then
    L2_2 = A0_2.thumbnail
    L3_2 = L2_2
    L2_2 = L2_2.sub
    L4_2 = 1
    L5_2 = 500
    L2_2 = L2_2(L3_2, L4_2, L5_2)
    if L2_2 then
      goto lbl_93
    end
  end
  L2_2 = nil
  ::lbl_93::
  L1_2.thumbnail = L2_2
  L2_2 = A0_2.isYouTube
  L2_2 = true == L2_2
  L1_2.isYouTube = L2_2
  L2_2 = type
  L3_2 = A0_2.videoId
  L2_2 = L2_2(L3_2)
  if "string" == L2_2 then
    L2_2 = A0_2.videoId
    L3_2 = L2_2
    L2_2 = L2_2.sub
    L4_2 = 1
    L5_2 = 20
    L2_2 = L2_2(L3_2, L4_2, L5_2)
    if L2_2 then
      goto lbl_113
    end
  end
  L2_2 = nil
  ::lbl_113::
  L1_2.videoId = L2_2
  L2_2 = type
  L3_2 = A0_2.duration
  L2_2 = L2_2(L3_2)
  if "number" == L2_2 then
    L2_2 = A0_2.duration
    if L2_2 then
      goto lbl_123
    end
  end
  L2_2 = nil
  ::lbl_123::
  L1_2.duration = L2_2
  return L1_2
end
L18_1 = RegisterNetEvent
L19_1 = "prism-carplay:server:playMusic"
function L20_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L3_2 = source
  if not (A0_2 and A1_2) or not A2_2 then
    return
  end
  L4_2 = L16_1
  L5_2 = L3_2
  L6_2 = A0_2
  L4_2 = L4_2(L5_2, L6_2)
  if not L4_2 then
    L4_2 = print
    L5_2 = "^1[Prism-CarPlay]^7 Security: Player "
    L6_2 = L3_2
    L7_2 = " attempted to play music on vehicle they are not in"
    L5_2 = L5_2 .. L6_2 .. L7_2
    L4_2(L5_2)
    return
  end
  L4_2 = L7_1
  L5_2 = L3_2
  L6_2 = "playMusic"
  L4_2 = L4_2(L5_2, L6_2)
  if L4_2 then
    return
  end
  L4_2 = type
  L5_2 = A2_2
  L4_2 = L4_2(L5_2)
  if "number" ~= L4_2 then
    return
  end
  L4_2 = L17_1
  L5_2 = A1_2
  L4_2 = L4_2(L5_2)
  A1_2 = L4_2
  if A1_2 then
    L4_2 = A1_2.url
    if L4_2 then
      goto lbl_48
    end
    L4_2 = A1_2.filePath
    if L4_2 then
      goto lbl_48
    end
  end
  do return end
  ::lbl_48::
  L4_2 = A0_2
  L5_2 = "carplay"
  L4_2 = L4_2 .. L5_2
  L5_2 = A0_2
  L6_2 = "carplay_speaker"
  L5_2 = L5_2 .. L6_2
  L6_2 = L15_1
  L6_2 = L6_2[A0_2]
  if L6_2 then
    L6_2 = RemoveAudioSource
    L7_2 = L4_2
    L6_2(L7_2)
  end
  L6_2 = L15_1
  L7_2 = {}
  L7_2.currentSong = A1_2
  L7_2.isPlaying = false
  L7_2.volume = 100
  L7_2.vehicleNetId = A2_2
  L7_2.startedBy = L3_2
  L6_2[A0_2] = L7_2
  L6_2 = AddAudioSource
  L7_2 = L4_2
  L8_2 = A1_2.url
  if not L8_2 then
    L8_2 = A1_2.filePath
  end
  L9_2 = {}
  L9_2.loop = false
  L9_2.volume = 1.0
  L10_2 = {}
  function L11_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3, L5_3, L6_3
    if A0_3 then
      L1_3 = A0_3.duration
      if L1_3 then
        L2_3 = A0_2
        L1_3 = L15_1
        L1_3 = L1_3[L2_3]
        if L1_3 then
          L2_3 = A0_2
          L1_3 = L15_1
          L1_3 = L1_3[L2_3]
          L2_3 = A0_3.duration
          L1_3.actualDuration = L2_3
        end
      end
    end
    L1_3 = AddSpeaker
    L2_3 = L5_2
    L3_3 = vec3
    L4_3 = 0
    L5_3 = 0
    L6_3 = 0
    L3_3 = L3_3(L4_3, L5_3, L6_3)
    L4_3 = {}
    L4_3.maxDistance = 15.0
    L4_3.rolloffFactor = 0.5
    L6_3 = A0_2
    L5_3 = L15_1
    L5_3 = L5_3[L6_3]
    if L5_3 then
      L6_3 = A0_2
      L5_3 = L15_1
      L5_3 = L5_3[L6_3]
      L5_3 = L5_3.volume
      L5_3 = L5_3 / 100
      if L5_3 then
        goto lbl_41
      end
    end
    L5_3 = 1.0
    ::lbl_41::
    L4_3.volumeMultiplier = L5_3
    L5_3 = A2_2
    L4_3.netID = L5_3
    L5_3 = L4_2
    L1_3(L2_3, L3_3, L4_3, L5_3)
    L1_3 = PlayAudioSource
    L2_3 = L4_2
    L1_3(L2_3)
  end
  L10_2.onAudioReady = L11_2
  function L11_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3, L6_3
    L1_3 = A0_2
    L0_3 = L15_1
    L0_3 = L0_3[L1_3]
    if L0_3 then
      L1_3 = A0_2
      L0_3 = L15_1
      L0_3 = L0_3[L1_3]
      L0_3.isPlaying = true
      L0_3 = A1_2.duration
      if not L0_3 then
        L1_3 = A0_2
        L0_3 = L15_1
        L0_3 = L0_3[L1_3]
        L0_3 = L0_3.actualDuration
      end
      L1_3 = {}
      L2_3 = A1_2.id
      L1_3.id = L2_3
      L2_3 = A1_2.title
      L1_3.title = L2_3
      L2_3 = A1_2.artist
      L1_3.artist = L2_3
      L2_3 = A1_2.filePath
      L1_3.filePath = L2_3
      L2_3 = A1_2.url
      L1_3.url = L2_3
      L2_3 = A1_2.thumbnail
      L1_3.thumbnail = L2_3
      L2_3 = A1_2.isYouTube
      L1_3.isYouTube = L2_3
      L2_3 = A1_2.videoId
      L1_3.videoId = L2_3
      L1_3.duration = L0_3
      L3_3 = A0_2
      L2_3 = L15_1
      L2_3 = L2_3[L3_3]
      L2_3.currentSong = L1_3
      L2_3 = TriggerClientEvent
      L3_3 = "prism-carplay:client:musicStarted"
      L4_3 = -1
      L5_3 = A0_2
      L6_3 = L1_3
      L2_3(L3_3, L4_3, L5_3, L6_3)
    else
      L0_3 = TriggerClientEvent
      L1_3 = "prism-carplay:client:musicStarted"
      L2_3 = -1
      L3_3 = A0_2
      L4_3 = A1_2
      L0_3(L1_3, L2_3, L3_3, L4_3)
    end
  end
  L10_2.onPlaybackStarted = L11_2
  function L11_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3
    L1_3 = A0_2
    L0_3 = L15_1
    L0_3 = L0_3[L1_3]
    if L0_3 then
      L1_3 = A0_2
      L0_3 = L15_1
      L0_3 = L0_3[L1_3]
      L0_3.isPlaying = false
    end
    L0_3 = TriggerClientEvent
    L1_3 = "prism-carplay:client:playbackStatus"
    L2_3 = -1
    L3_3 = A0_2
    L4_3 = false
    L0_3(L1_3, L2_3, L3_3, L4_3)
  end
  L10_2.onPlaybackPaused = L11_2
  function L11_2()
    local L0_3, L1_3, L2_3, L3_3, L4_3
    L1_3 = A0_2
    L0_3 = L15_1
    L0_3 = L0_3[L1_3]
    if L0_3 then
      L1_3 = A0_2
      L0_3 = L15_1
      L0_3 = L0_3[L1_3]
      L0_3.isPlaying = true
    end
    L0_3 = TriggerClientEvent
    L1_3 = "prism-carplay:client:playbackStatus"
    L2_3 = -1
    L3_3 = A0_2
    L4_3 = true
    L0_3(L1_3, L2_3, L3_3, L4_3)
  end
  L10_2.onPlaybackResumed = L11_2
  function L11_2()
    local L0_3, L1_3, L2_3, L3_3
    L1_3 = A0_2
    L0_3 = L15_1
    L0_3 = L0_3[L1_3]
    if L0_3 then
      L1_3 = A0_2
      L0_3 = L15_1
      L0_3 = L0_3[L1_3]
      L0_3 = L0_3.isPlaying
      if L0_3 then
        L1_3 = A0_2
        L0_3 = L15_1
        L0_3[L1_3] = nil
        L0_3 = TriggerClientEvent
        L1_3 = "prism-carplay:client:trackEnded"
        L2_3 = -1
        L3_3 = A0_2
        L0_3(L1_3, L2_3, L3_3)
      end
    end
  end
  L10_2.onAudioEnded = L11_2
  L6_2(L7_2, L8_2, L9_2, L10_2)
end
L18_1(L19_1, L20_1)
L18_1 = RegisterNetEvent
L19_1 = "prism-carplay:server:toggleMusic"
function L20_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = source
  if A0_2 then
    L2_2 = L15_1
    L2_2 = L2_2[A0_2]
    if L2_2 then
      goto lbl_9
    end
  end
  do return end
  ::lbl_9::
  L2_2 = L16_1
  L3_2 = L1_2
  L4_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 then
    return
  end
  L2_2 = A0_2
  L3_2 = "carplay"
  L2_2 = L2_2 .. L3_2
  L3_2 = L15_1
  L3_2 = L3_2[A0_2]
  L3_2 = L3_2.isPlaying
  if L3_2 then
    L3_2 = PauseAudioSource
    L4_2 = L2_2
    L3_2(L4_2)
  else
    L3_2 = ResumeAudioSource
    L4_2 = L2_2
    L3_2(L4_2)
  end
end
L18_1(L19_1, L20_1)
L18_1 = RegisterNetEvent
L19_1 = "prism-carplay:server:stopMusic"
function L20_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = source
  if not A0_2 then
    return
  end
  L2_2 = L16_1
  L3_2 = L1_2
  L4_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 then
    return
  end
  L2_2 = L7_1
  L3_2 = L1_2
  L4_2 = "stopMusic"
  L2_2 = L2_2(L3_2, L4_2)
  if L2_2 then
    return
  end
  L2_2 = A0_2
  L3_2 = "carplay"
  L2_2 = L2_2 .. L3_2
  L3_2 = RemoveAudioSource
  L4_2 = L2_2
  L3_2(L4_2)
  L3_2 = L15_1
  L3_2[A0_2] = nil
  L3_2 = TriggerClientEvent
  L4_2 = "prism-carplay:client:musicStopped"
  L5_2 = -1
  L6_2 = A0_2
  L3_2(L4_2, L5_2, L6_2)
end
L18_1(L19_1, L20_1)
L18_1 = RegisterNetEvent
L19_1 = "prism-carplay:server:seekMusic"
function L20_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = source
  if A0_2 then
    L3_2 = L15_1
    L3_2 = L3_2[A0_2]
    if L3_2 then
      goto lbl_9
    end
  end
  do return end
  ::lbl_9::
  L3_2 = L16_1
  L4_2 = L2_2
  L5_2 = A0_2
  L3_2 = L3_2(L4_2, L5_2)
  if not L3_2 then
    return
  end
  L3_2 = type
  L4_2 = A1_2
  L3_2 = L3_2(L4_2)
  if "number" ~= L3_2 or A1_2 < 0 then
    return
  end
  L3_2 = A0_2
  L4_2 = "carplay"
  L3_2 = L3_2 .. L4_2
  L4_2 = SeekAudioSource
  L5_2 = L3_2
  L6_2 = A1_2
  L4_2(L5_2, L6_2)
end
L18_1(L19_1, L20_1)
L18_1 = RegisterNetEvent
L19_1 = "prism-carplay:server:setMusicVolume"
function L20_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = source
  if A0_2 then
    L3_2 = L15_1
    L3_2 = L3_2[A0_2]
    if L3_2 then
      goto lbl_9
    end
  end
  do return end
  ::lbl_9::
  L3_2 = L16_1
  L4_2 = L2_2
  L5_2 = A0_2
  L3_2 = L3_2(L4_2, L5_2)
  if not L3_2 then
    return
  end
  L3_2 = type
  L4_2 = A1_2
  L3_2 = L3_2(L4_2)
  if "number" ~= L3_2 or A1_2 < 0 or A1_2 > 100 then
    return
  end
  L3_2 = A0_2
  L4_2 = "carplay_speaker"
  L3_2 = L3_2 .. L4_2
  L4_2 = L15_1
  L4_2 = L4_2[A0_2]
  L4_2.volume = A1_2
  L4_2 = SetSpeakerVolume
  L5_2 = L3_2
  L6_2 = A1_2 / 100
  L4_2(L5_2, L6_2)
end
L18_1(L19_1, L20_1)
L18_1 = RegisterNetEvent
L19_1 = "prism-carplay:server:getMusicState"
function L20_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = source
  L2_2 = L15_1
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L2_2 = TriggerClientEvent
    L3_2 = "prism-carplay:client:syncMusicState"
    L4_2 = L1_2
    L5_2 = A0_2
    L6_2 = L15_1
    L6_2 = L6_2[A0_2]
    L2_2(L3_2, L4_2, L5_2, L6_2)
  end
end
L18_1(L19_1, L20_1)

