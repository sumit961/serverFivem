

local L0_1, L1_1, L2_1, L3_1, L4_1
L0_1 = {}
L1_1 = {}
function L2_1()
  local L0_2, L1_2, L2_2, L3_2
  L0_2 = math
  L0_2 = L0_2.random
  L1_2 = 100000
  L2_2 = 999999
  L0_2 = L0_2(L1_2, L2_2)
  while true do
    L1_2 = tostring
    L2_2 = L0_2
    L1_2 = L1_2(L2_2)
    L2_2 = L0_1
    L1_2 = L2_2[L1_2]
    if not L1_2 then
      break
    end
    L1_2 = math
    L1_2 = L1_2.random
    L2_2 = 100000
    L3_2 = 999999
    L1_2 = L1_2(L2_2, L3_2)
    L0_2 = L1_2
  end
  return L0_2
end
createSourceID = L2_1
function L2_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L0_2 = math
  L0_2 = L0_2.huge
  L1_2 = nil
  L2_2 = ipairs
  L3_2 = GetPlayers
  L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2 = L3_2()
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = GetPlayerPing
    L9_2 = L7_2
    L8_2 = L8_2(L9_2)
    if L0_2 > L8_2 then
      L0_2 = L8_2
      L1_2 = L7_2
    end
  end
  L2_2 = tonumber
  L3_2 = L1_2
  return L2_2(L3_2)
end
AssignOwner = L2_1
function L2_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  if not A0_2 then
    L4_2 = createSourceID
    L4_2 = L4_2()
    A0_2 = L4_2
  end
  if not A1_2 then
    L4_2 = false
    return L4_2
  end
  L4_2 = {}
  if A3_2 then
    L5_2 = {}
    L6_2 = "onPlaybackStarted"
    L7_2 = "onPlaybackPaused"
    L8_2 = "onPlaybackResumed"
    L9_2 = "onAudioReady"
    L10_2 = "onAudioError"
    L11_2 = "onAudioEnded"
    L5_2[1] = L6_2
    L5_2[2] = L7_2
    L5_2[3] = L8_2
    L5_2[4] = L9_2
    L5_2[5] = L10_2
    L5_2[6] = L11_2
    L6_2 = ipairs
    L7_2 = L5_2
    L6_2, L7_2, L8_2, L9_2 = L6_2(L7_2)
    for L10_2, L11_2 in L6_2, L7_2, L8_2, L9_2 do
      L12_2 = tostring
      L13_2 = A0_2
      L12_2 = L12_2(L13_2)
      L13_2 = L1_1
      L14_2 = tostring
      L15_2 = A0_2
      L14_2 = L14_2(L15_2)
      L15_2 = L1_1
      L14_2 = L15_2[L14_2]
      if not L14_2 then
        L14_2 = {}
      end
      L13_2[L12_2] = L14_2
      L12_2 = tostring
      L13_2 = A0_2
      L12_2 = L12_2(L13_2)
      L13_2 = L1_1
      L12_2 = L13_2[L12_2]
      L13_2 = A3_2[L11_2]
      if not L13_2 then
        function L13_2()
          local L0_3, L1_3
        end
      end
      L12_2[L11_2] = L13_2
      L12_2 = A3_2[L11_2]
      if L12_2 then
        L4_2[L11_2] = true
      end
    end
  end
  L5_2 = tostring
  L6_2 = A0_2
  L5_2 = L5_2(L6_2)
  L6_2 = L0_1
  L7_2 = {}
  L7_2.url = A1_2
  L7_2.options = A2_2
  L8_2 = AssignOwner
  L8_2 = L8_2()
  L7_2.playerId = L8_2
  L6_2[L5_2] = L7_2
  L5_2 = TriggerClientEvent
  L6_2 = "ts-sounds:client:AddSource"
  L7_2 = -1
  L8_2 = A0_2
  L9_2 = A1_2
  L10_2 = A2_2
  L11_2 = L4_2
  L12_2 = true
  L13_2 = tostring
  L14_2 = A0_2
  L13_2 = L13_2(L14_2)
  L14_2 = L0_1
  L13_2 = L14_2[L13_2]
  L13_2 = L13_2.playerId
  L5_2(L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2)
end
AddAudioSource = L2_1
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = tostring
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = L0_1
  L1_2 = L2_2[L1_2]
  if L1_2 then
    L1_2 = TriggerClientEvent
    L2_2 = "ts-sounds:client:RemoveSource"
    L3_2 = -1
    L4_2 = A0_2
    L1_2(L2_2, L3_2, L4_2)
  end
end
RemoveAudioSource = L2_1
function L2_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L4_2 = TriggerClientEvent
  L5_2 = "ts-sounds:client:AddSpeaker"
  L6_2 = -1
  L7_2 = A0_2
  L8_2 = A1_2
  L9_2 = A2_2
  L10_2 = A3_2
  L4_2(L5_2, L6_2, L7_2, L8_2, L9_2, L10_2)
end
AddSpeaker = L2_1
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = TriggerClientEvent
  L3_2 = "ts-sounds:client:SetAudioLoop"
  L4_2 = -1
  L5_2 = A0_2
  L6_2 = A1_2
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
SetLoop = L2_1
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = tostring
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = L0_1
  L1_2 = L2_2[L1_2]
  if L1_2 then
    L1_2 = TriggerClientEvent
    L2_2 = "ts-sounds:client:PlayAudio"
    L3_2 = -1
    L4_2 = A0_2
    L1_2(L2_2, L3_2, L4_2)
  end
end
PlayAudioSource = L2_1
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = tostring
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = L0_1
  L1_2 = L2_2[L1_2]
  if L1_2 then
    L1_2 = TriggerClientEvent
    L2_2 = "ts-sounds:client:PauseAudio"
    L3_2 = -1
    L4_2 = A0_2
    L1_2(L2_2, L3_2, L4_2)
  end
end
PauseAudioSource = L2_1
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = tostring
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = L0_1
  L1_2 = L2_2[L1_2]
  if L1_2 then
    L1_2 = TriggerClientEvent
    L2_2 = "ts-sounds:client:ResumeAudio"
    L3_2 = -1
    L4_2 = A0_2
    L1_2(L2_2, L3_2, L4_2)
  end
end
ResumeAudioSource = L2_1
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = tostring
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = L0_1
  L2_2 = L3_2[L2_2]
  if L2_2 then
    L2_2 = TriggerClientEvent
    L3_2 = "ts-sounds:client:SeekAudio"
    L4_2 = -1
    L5_2 = A0_2
    L6_2 = A1_2
    L2_2(L3_2, L4_2, L5_2, L6_2)
  end
end
SeekAudioSource = L2_1
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = TriggerClientEvent
  L3_2 = "ts-sounds:client:SetSpeakerVolume"
  L4_2 = -1
  L5_2 = A0_2
  L6_2 = A1_2
  L2_2(L3_2, L4_2, L5_2, L6_2)
end
SetSpeakerVolume = L2_1
L2_1 = exports
L3_1 = "SetSpeakerVolume"
L4_1 = SetSpeakerVolume
L2_1(L3_1, L4_1)
L2_1 = exports
L3_1 = "AddAudioSource"
L4_1 = AddAudioSource
L2_1(L3_1, L4_1)
L2_1 = exports
L3_1 = "RemoveAudioSource"
L4_1 = RemoveAudioSource
L2_1(L3_1, L4_1)
L2_1 = exports
L3_1 = "AddSpeaker"
L4_1 = AddSpeaker
L2_1(L3_1, L4_1)
L2_1 = exports
L3_1 = "PlayAudioSource"
L4_1 = PlayAudioSource
L2_1(L3_1, L4_1)
L2_1 = exports
L3_1 = "PauseAudioSource"
L4_1 = PauseAudioSource
L2_1(L3_1, L4_1)
L2_1 = exports
L3_1 = "ResumeAudioSource"
L4_1 = ResumeAudioSource
L2_1(L3_1, L4_1)
L2_1 = exports
L3_1 = "SeekAudioSource"
L4_1 = SeekAudioSource
L2_1(L3_1, L4_1)
L2_1 = exports
L3_1 = "SetLoop"
L4_1 = SetLoop
L2_1(L3_1, L4_1)
L2_1 = RegisterNetEvent
L3_1 = "ts-sounds:server:RemoveAudioSource"
function L4_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  L1_2 = tostring
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L2_2 = L0_1
  L1_2 = L2_2[L1_2]
  if L1_2 then
    L1_2 = TriggerEvent
    L2_2 = "ts-sounds:server:AudioCallback"
    L3_2 = A0_2
    L4_2 = "onAudioEnded"
    L1_2(L2_2, L3_2, L4_2)
  end
end
L2_1(L3_1, L4_1)
L2_1 = RegisterNetEvent
L3_1 = "ts-sounds:server:AudioCallback"
function L4_1(A0_2, A1_2, ...)
  local L2_2, L3_2, L4_2
  L2_2 = tostring
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = L1_1
  L2_2 = L3_2[L2_2]
  if L2_2 then
    L2_2 = tostring
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    L3_2 = L1_1
    L2_2 = L3_2[L2_2]
    L2_2 = L2_2[A1_2]
    if L2_2 then
      L2_2 = tostring
      L3_2 = A0_2
      L2_2 = L2_2(L3_2)
      L3_2 = L1_1
      L2_2 = L3_2[L2_2]
      L2_2 = L2_2[A1_2]
      if "onAudioEnded" == A1_2 then
        L3_2 = tostring
        L4_2 = A0_2
        L3_2 = L3_2(L4_2)
        L4_2 = L0_1
        L4_2[L3_2] = nil
        L3_2 = tostring
        L4_2 = A0_2
        L3_2 = L3_2(L4_2)
        L4_2 = L1_1
        L4_2[L3_2] = nil
      end
      L3_2 = L2_2
      L4_2 = ...
      L3_2(L4_2)
    end
  end
end
L2_1(L3_1, L4_1)
L2_1 = AddEventHandler
L3_1 = "playerDropped"
function L4_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L0_2 = source
  L1_2 = pairs
  L2_2 = L0_1
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    L7_2 = L6_2.playerId
    if L7_2 == L0_2 then
      L7_2 = AssignOwner
      L7_2 = L7_2()
      L6_2.playerId = L7_2
      L7_2 = TriggerClientEvent
      L8_2 = "ts-sounds:client:ChangeOwner"
      L9_2 = -1
      L10_2 = L5_2
      L11_2 = L6_2.playerId
      L7_2(L8_2, L9_2, L10_2, L11_2)
      break
    end
  end
end
L2_1(L3_1, L4_1)

