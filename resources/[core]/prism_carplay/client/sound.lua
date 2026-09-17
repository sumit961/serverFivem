

local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1, L9_1, L10_1, L11_1, L12_1, L13_1, L14_1, L15_1
L0_1 = {}
L1_1 = {}
L2_1 = GetCurrentResourceName
L2_1 = L2_1()
L3_1 = 50
L4_1 = {}
L5_1 = 5
L6_1 = true
L7_1 = {}
L8_1 = {}
L8_1.refDistance = 1.0
L8_1.maxDistance = 50.0
L8_1.rolloffFactor = 1.0
L8_1.coneInnerAngle = 360
L8_1.coneOuterAngle = 360
L8_1.coneOuterGain = 0.0
L8_1.fadeDurationMs = 1000
L8_1.volumeMultiplier = 1.0
L8_1.lowPassGainReductionPercent = 0
L8_1.lowPassFrequency = 0
L8_1.attachedEntity = nil
L8_1.attachedOffset = nil
L8_1.isInVehicle = false
L8_1.pannerDisabled = false
L8_1.pannerManuallySet = false
L9_1 = {}
L9_1.loop = false
L9_1.volume = 1.0
L9_1.playbackRate = 1.0
L9_1.fadeInDuration = 0
L9_1.fadeOutDuration = 0
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = {}
  L2_2 = "youtube.com/watch%?v="
  L3_2 = "youtu.be/"
  L4_2 = "youtube.com/embed/"
  L1_2[1] = L2_2
  L1_2[2] = L3_2
  L1_2[3] = L4_2
  L2_2 = string
  L2_2 = L2_2.match
  L3_2 = A0_2
  L4_2 = "^[a-zA-Z0-9_-]+$"
  L2_2 = L2_2(L3_2, L4_2)
  if L2_2 then
    L2_2 = string
    L2_2 = L2_2.len
    L3_2 = A0_2
    L2_2 = L2_2(L3_2)
    if 11 == L2_2 then
      L2_2 = true
      return L2_2
    end
  end
  L2_2 = ipairs
  L3_2 = L1_2
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = string
    L8_2 = L8_2.find
    L9_2 = A0_2
    L10_2 = L7_2
    L8_2 = L8_2(L9_2, L10_2)
    if L8_2 then
      L8_2 = true
      return L8_2
    end
  end
  L2_2 = false
  return L2_2
end
IsYoutubeUrl = L10_1
function L10_1()
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
    L2_2 = L1_1
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
createSourceID = L10_1
function L10_1(A0_2, A1_2, A2_2, A3_2, A4_2, A5_2)
  local L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2
  if not A1_2 then
    L6_2 = false
    return L6_2
  end
  if not A0_2 then
    L6_2 = tostring
    L7_2 = createSourceID
    L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2 = L7_2()
    L6_2 = L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2)
    A0_2 = L6_2
  end
  L6_2 = L1_1
  L6_2 = L6_2[A0_2]
  if L6_2 then
    L6_2 = StopAudioSource
    L7_2 = A0_2
    L6_2(L7_2)
  end
  L6_2 = A2_2 or L6_2
  if not A2_2 then
    L6_2 = L9_1
  end
  L7_2 = string
  L7_2 = L7_2.match
  L8_2 = A1_2
  L9_2 = "^https?://"
  L7_2 = L7_2(L8_2, L9_2)
  L7_2 = IsYoutubeUrl
  L8_2 = A1_2
  L7_2 = L7_2(L8_2)
  L7_2 = not L7_2 and L7_2
  L8_2 = L1_1
  L9_2 = {}
  L9_2.url = A1_2
  L9_2.config = L6_2
  L9_2.playing = false
  L9_2.currentTime = 0
  L9_2.isLocalFile = L7_2
  L10_2 = A5_2 or L10_2
  if not A4_2 or not A5_2 then
    L10_2 = GetPlayerServerId
    L11_2 = PlayerId
    L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2 = L11_2()
    L10_2 = L10_2(L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2)
  end
  L9_2.audioOwner = L10_2
  L8_2[A0_2] = L9_2
  if A3_2 then
    L8_2 = {}
    L9_2 = "onPlaybackStarted"
    L10_2 = "onPlaybackStopped"
    L11_2 = "onPlaybackPaused"
    L12_2 = "onPlaybackResumed"
    L13_2 = "onAudioReady"
    L14_2 = "onAudioError"
    L15_2 = "onAudioEnded"
    L8_2[1] = L9_2
    L8_2[2] = L10_2
    L8_2[3] = L11_2
    L8_2[4] = L12_2
    L8_2[5] = L13_2
    L8_2[6] = L14_2
    L8_2[7] = L15_2
    L9_2 = ipairs
    L10_2 = L8_2
    L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
    for L13_2, L14_2 in L9_2, L10_2, L11_2, L12_2 do
      L15_2 = A3_2[L14_2]
      if L15_2 then
        L15_2 = print
        L16_2 = "Registering callback for "
        L17_2 = L14_2
        L16_2 = L16_2 .. L17_2
        L17_2 = A0_2
        L18_2 = A4_2
        L15_2(L16_2, L17_2, L18_2)
        L15_2 = type
        L16_2 = A3_2[L14_2]
        L15_2 = L15_2(L16_2)
        if "function" == L15_2 then
          L15_2 = A3_2[L14_2]
          if L15_2 then
            goto lbl_89
          end
        end
        function L15_2()
          local L0_3, L1_3
        end
        ::lbl_89::
        L16_2 = RegisterAudioCallback
        L17_2 = A0_2
        L18_2 = L14_2
        L19_2 = L15_2
        L20_2 = A4_2
        L16_2(L17_2, L18_2, L19_2, L20_2)
      end
    end
  end
  L8_2 = SendNUIMessage
  L9_2 = {}
  L9_2.type = "addAudioSource"
  L9_2.audioSourceId = A0_2
  L9_2.url = A1_2
  L9_2.config = L6_2
  L8_2(L9_2)
  L8_2 = "standard"
  if L7_2 then
    L8_2 = "local"
  else
    L9_2 = IsYoutubeUrl
    L10_2 = A1_2
    L9_2 = L9_2(L10_2)
    if L9_2 then
      L8_2 = "YouTube"
    end
  end
  L9_2 = true
  return L9_2
end
AddAudioSource = L10_1
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.audioOwner
  L2_2 = StopAudioSource
  L3_2 = A0_2
  L2_2(L3_2)
  L2_2 = pairs
  L3_2 = L0_1
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = L7_2.audioSourceId
    if L8_2 == A0_2 then
      L8_2 = RemoveSpeaker
      L9_2 = L6_2
      L8_2(L9_2)
    end
  end
  L2_2 = L1_1
  L2_2[A0_2] = nil
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "removeAudioSource"
  L3_2.audioSourceId = A0_2
  L2_2(L3_2)
  L2_2 = GetPlayerServerId
  L3_2 = PlayerId
  L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2 = L3_2()
  L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2)
  if L1_2 == L2_2 then
    L2_2 = TriggerServerEvent
    L3_2 = "ts-sounds:server:RemoveAudioSource"
    L4_2 = A0_2
    L2_2(L3_2, L4_2)
  end
  L2_2 = true
  return L2_2
end
RemoveAudioSource = L10_1
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:AddSource"
L12_1 = AddAudioSource
L10_1(L11_1, L12_1)
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:RemoveSource"
L12_1 = RemoveAudioSource
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "AddAudioSource"
L12_1 = AddAudioSource
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "RemoveAudioSource"
L12_1 = RemoveAudioSource
L10_1(L11_1, L12_1)
function L10_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = L1_1
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = L1_1
  L2_2 = L2_2[A0_2]
  L2_2 = L2_2.config
  if L2_2 then
    L2_2 = L1_1
    L2_2 = L2_2[A0_2]
    L2_2 = L2_2.config
    L2_2.loop = A1_2
  else
    L2_2 = L1_1
    L2_2 = L2_2[A0_2]
    L3_2 = {}
    L3_2.loop = A1_2
    L2_2.config = L3_2
  end
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "setLoop"
  L3_2.audioSourceId = A0_2
  L3_2.loop = A1_2
  L2_2(L3_2)
  L2_2 = true
  return L2_2
end
SetAudioLoop = L10_1
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:SetAudioLoop"
L12_1 = SetAudioLoop
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "SetAudioLoop"
L12_1 = SetAudioLoop
L10_1(L11_1, L12_1)
function L10_1(A0_2)
  local L1_2, L2_2
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  L1_2.playing = true
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.type = "playAudioSource"
  L2_2.audioSourceId = A0_2
  L1_2(L2_2)
  L1_2 = true
  return L1_2
end
PlayAudioSource = L10_1
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:PlayAudio"
L12_1 = PlayAudioSource
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "PlayAudioSource"
L12_1 = PlayAudioSource
L10_1(L11_1, L12_1)
function L10_1(A0_2)
  local L1_2, L2_2
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  L1_2.playing = false
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.type = "stopAudioSource"
  L2_2.audioSourceId = A0_2
  L1_2(L2_2)
  L1_2 = true
  return L1_2
end
StopAudioSource = L10_1
function L10_1(A0_2)
  local L1_2
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  if L1_2 then
    L1_2 = L1_1
    L1_2 = L1_2[A0_2]
    L1_2 = L1_2.playing
    if L1_2 then
      goto lbl_11
    end
  end
  L1_2 = false
  ::lbl_11::
  return L1_2
end
IsAudioSourcePlaying = L10_1
function L10_1(A0_2)
  local L1_2
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = 0
    return L1_2
  end
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.currentTime
  if not L1_2 then
    L1_2 = 0
  end
  return L1_2
end
GetAudioSourceTime = L10_1
function L10_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  if not (A0_2 and A1_2) or not A3_2 then
    L4_2 = false
    return L4_2
  end
  L4_2 = L1_1
  L4_2 = L4_2[A3_2]
  if not L4_2 then
    L4_2 = print
    L5_2 = "Error: Audio source "
    L6_2 = A3_2
    L7_2 = " not found"
    L5_2 = L5_2 .. L6_2 .. L7_2
    L4_2(L5_2)
    L4_2 = false
    return L4_2
  end
  L4_2 = {}
  L5_2 = A2_2.refDistance
  if not L5_2 then
    L5_2 = L8_1.refDistance
  end
  L4_2.refDistance = L5_2
  L5_2 = A2_2.maxDistance
  if not L5_2 then
    L5_2 = L8_1.maxDistance
  end
  L4_2.maxDistance = L5_2
  L5_2 = A2_2.rolloffFactor
  if not L5_2 then
    L5_2 = L8_1.rolloffFactor
  end
  L4_2.rolloffFactor = L5_2
  L5_2 = A2_2.coneInnerAngle
  if not L5_2 then
    L5_2 = L8_1.coneInnerAngle
  end
  L4_2.coneInnerAngle = L5_2
  L5_2 = A2_2.coneOuterAngle
  if not L5_2 then
    L5_2 = L8_1.coneOuterAngle
  end
  L4_2.coneOuterAngle = L5_2
  L5_2 = A2_2.coneOuterGain
  if not L5_2 then
    L5_2 = L8_1.coneOuterGain
  end
  L4_2.coneOuterGain = L5_2
  L5_2 = A2_2.fadeDurationMs
  if not L5_2 then
    L5_2 = L8_1.fadeDurationMs
  end
  L4_2.fadeDurationMs = L5_2
  L5_2 = A2_2.volumeMultiplier
  if not L5_2 then
    L5_2 = L8_1.volumeMultiplier
  end
  L4_2.volumeMultiplier = L5_2
  L5_2 = A2_2.lowPassGainReductionPercent
  if not L5_2 then
    L5_2 = L8_1.lowPassGainReductionPercent
  end
  L4_2.lowPassGainReductionPercent = L5_2
  L5_2 = A2_2.lowPassFrequency
  if not L5_2 then
    L5_2 = L8_1.lowPassFrequency
  end
  L4_2.lowPassFrequency = L5_2
  L5_2 = A2_2.netID
  if L5_2 then
    L5_2 = NetworkGetEntityFromNetworkId
    L6_2 = A2_2.netID
    L5_2 = L5_2(L6_2)
    if L5_2 then
      goto lbl_82
    end
  end
  L5_2 = A2_2.attachedEntity
  ::lbl_82::
  L4_2.attachedEntity = L5_2
  L5_2 = A2_2.attachedOffset
  if not L5_2 then
    L5_2 = L8_1.attachedOffset
  end
  L4_2.attachedOffset = L5_2
  L4_2.isInVehicle = false
  L4_2.pannerDisabled = false
  L4_2.pannerManuallySet = false
  L5_2 = L0_1
  L6_2 = {}
  L6_2.position = A1_2
  L6_2.config = L4_2
  L6_2.audioSourceId = A3_2
  L6_2.lastUpdate = 0
  L6_2.frameCount = 0
  L5_2[A0_2] = L6_2
  L5_2 = L4_1
  L5_2[A0_2] = A1_2
  L5_2 = SendNUIMessage
  L6_2 = {}
  L6_2.type = "addSpeaker"
  L6_2.speakerId = A0_2
  L7_2 = {}
  L8_2 = A1_2.x
  L9_2 = A1_2.y
  L10_2 = A1_2.z
  L7_2[1] = L8_2
  L7_2[2] = L9_2
  L7_2[3] = L10_2
  L6_2.position = L7_2
  L6_2.config = L4_2
  L6_2.audioSourceId = A3_2
  L5_2(L6_2)
  L5_2 = true
  return L5_2
end
AddSpeaker = L10_1
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:AddSpeaker"
L12_1 = AddSpeaker
L10_1(L11_1, L12_1)
function L10_1(A0_2)
  local L1_2, L2_2
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = L0_1
  L1_2[A0_2] = nil
  L1_2 = L4_1
  L1_2[A0_2] = nil
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.type = "removeSpeaker"
  L2_2.speakerId = A0_2
  L1_2(L2_2)
  L1_2 = true
  return L1_2
end
RemoveSpeaker = L10_1
L10_1 = exports
L11_1 = "AddSpeaker"
L12_1 = AddSpeaker
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "RemoveSpeaker"
L12_1 = RemoveSpeaker
L10_1(L11_1, L12_1)
function L10_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  if not A2_2 then
    A2_2 = 0.05
  end
  if not A0_2 or not A1_2 then
    L3_2 = true
    return L3_2
  end
  L3_2 = A0_2.x
  L4_2 = A1_2.x
  L3_2 = L3_2 - L4_2
  L4_2 = A0_2.y
  L5_2 = A1_2.y
  L4_2 = L4_2 - L5_2
  L5_2 = A0_2.z
  L6_2 = A1_2.z
  L5_2 = L5_2 - L6_2
  L6_2 = L3_2 * L3_2
  L7_2 = L4_2 * L4_2
  L6_2 = L6_2 + L7_2
  L7_2 = L5_2 * L5_2
  L6_2 = L6_2 + L7_2
  L7_2 = A2_2 * A2_2
  L6_2 = L6_2 > L7_2
  return L6_2
end
HasPositionChanged = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = HasPositionChanged
  L3_2 = A1_2
  L4_2 = L0_1
  L4_2 = L4_2[A0_2]
  L4_2 = L4_2.position
  L2_2 = L2_2(L3_2, L4_2)
  if L2_2 then
    L2_2 = L0_1
    L2_2 = L2_2[A0_2]
    L2_2.position = A1_2
    L2_2 = L4_1
    L2_2[A0_2] = A1_2
  end
  L2_2 = true
  return L2_2
end
UpdateSpeakerPosition = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = pairs
  L3_2 = A1_2
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = L0_1
    L8_2 = L8_2[A0_2]
    L8_2 = L8_2.config
    L8_2[L6_2] = L7_2
  end
  L2_2 = print
  L3_2 = "Update Volume:"
  L4_2 = L0_1
  L4_2 = L4_2[A0_2]
  L4_2 = L4_2.config
  L4_2 = L4_2.volumeMultiplier
  L2_2(L3_2, L4_2)
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "updateSpeakerConfig"
  L3_2.speakerId = A0_2
  L4_2 = L0_1
  L4_2 = L4_2[A0_2]
  L4_2 = L4_2.config
  L3_2.config = L4_2
  L2_2(L3_2)
  L2_2 = true
  return L2_2
end
UpdateSpeakerConfig = L10_1
function L10_1(A0_2)
  local L1_2
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = 0
    return L1_2
  end
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.config
  L1_2 = L1_2.volumeMultiplier
  return L1_2
end
GetSpeakerVolume = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = false
    return L2_2
  end
  if A1_2 < 0 then
    L2_2 = false
    return L2_2
  end
  L2_2 = UpdateSpeakerConfig
  L3_2 = A0_2
  L4_2 = {}
  L4_2.volumeMultiplier = A1_2
  L2_2(L3_2, L4_2)
end
SetSpeakerVolume = L10_1
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:SetSpeakerVolume"
L12_1 = SetSpeakerVolume
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "SetSpeakerVolume"
L12_1 = SetSpeakerVolume
L10_1(L11_1, L12_1)
L10_1 = Citizen
L10_1 = L10_1.CreateThread
function L11_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2, L22_2, L23_2, L24_2, L25_2, L26_2, L27_2
  while true do
    L0_2 = Citizen
    L0_2 = L0_2.Wait
    L1_2 = L3_1
    L0_2(L1_2)
    L0_2 = PlayerPedId
    L0_2 = L0_2()
    L1_2 = GetEntityCoords
    L2_2 = L0_2
    L1_2 = L1_2(L2_2)
    L2_2 = GetEntityForwardVector
    L3_2 = L0_2
    L2_2 = L2_2(L3_2)
    L3_2 = GetGameplayCamRot
    L4_2 = 2
    L3_2 = L3_2(L4_2)
    L4_2 = RotationToDirection
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    L5_2 = vector3
    L6_2 = 0.0
    L7_2 = 0.0
    L8_2 = 1.0
    L5_2 = L5_2(L6_2, L7_2, L8_2)
    L6_2 = {}
    L7_2 = GetGameTimer
    L7_2 = L7_2()
    L8_2 = 0
    L9_2 = pairs
    L10_2 = L0_1
    L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
    for L13_2, L14_2 in L9_2, L10_2, L11_2, L12_2 do
      L15_2 = L14_2.frameCount
      if not L15_2 then
        L15_2 = 0
      end
      L15_2 = L15_2 + 1
      L14_2.frameCount = L15_2
      L15_2 = L14_2.position
      L16_2 = L1_2 - L15_2
      L16_2 = #L16_2
      L17_2 = true
      L18_2 = L14_2.config
      L18_2 = L18_2.maxDistance
      L18_2 = L18_2 * 0.7
      if L16_2 > L18_2 then
        L18_2 = L14_2.frameCount
        L19_2 = L5_1
        L17_2 = L18_2 >= L19_2
      end
      if not L17_2 then
        L18_2 = L4_1
        L18_2 = L18_2[L13_2]
        if L18_2 then
          goto lbl_106
        end
      end
      L14_2.frameCount = 0
      L18_2 = L15_2 - L1_2
      L19_2 = 0.01
      if L16_2 > L19_2 then
        L18_2 = L18_2 / L16_2
      else
        L19_2 = vector3
        L20_2 = 0.0
        L21_2 = 0.0
        L22_2 = 1.0
        L19_2 = L19_2(L20_2, L21_2, L22_2)
        L18_2 = L19_2
      end
      L19_2 = {}
      L20_2 = L18_2.x
      L21_2 = L18_2.y
      L22_2 = L18_2.z
      L19_2[1] = L20_2
      L19_2[2] = L21_2
      L19_2[3] = L22_2
      L20_2 = 0.0
      L8_2 = L8_2 + 1
      L21_2 = table
      L21_2 = L21_2.insert
      L22_2 = L6_2
      L23_2 = {}
      L23_2.id = L13_2
      L24_2 = {}
      L25_2 = L15_2.x
      L26_2 = L15_2.y
      L27_2 = L15_2.z
      L24_2[1] = L25_2
      L24_2[2] = L26_2
      L24_2[3] = L27_2
      L23_2.position = L24_2
      L23_2.orientation = L19_2
      L23_2.distance = L16_2
      L23_2.lowPassFilterFade = L20_2
      L21_2(L22_2, L23_2)
      L21_2 = L4_1
      L21_2[L13_2] = L15_2
      ::lbl_106::
    end
    if L8_2 > 0 then
      L9_2 = SendNUIMessage
      L10_2 = {}
      L10_2.type = "update"
      L11_2 = L6_1
      L10_2.applyLowPassFilter = L11_2
      L11_2 = {}
      L12_2 = {}
      L13_2 = L1_2.x
      L14_2 = L1_2.y
      L15_2 = L1_2.z
      L12_2[1] = L13_2
      L12_2[2] = L14_2
      L12_2[3] = L15_2
      L11_2.position = L12_2
      L12_2 = {}
      L13_2 = L4_2.x
      L14_2 = L4_2.y
      L15_2 = L4_2.z
      L12_2[1] = L13_2
      L12_2[2] = L14_2
      L12_2[3] = L15_2
      L11_2.forward = L12_2
      L12_2 = {}
      L13_2 = L5_2.x
      L14_2 = L5_2.y
      L15_2 = L5_2.z
      L12_2[1] = L13_2
      L12_2[2] = L14_2
      L12_2[3] = L15_2
      L11_2.up = L12_2
      L10_2.listener = L11_2
      L10_2.speakers = L6_2
      L9_2(L10_2)
    end
  end
end
L10_1(L11_1)
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2
  L1_2 = {}
  L2_2 = math
  L2_2 = L2_2.pi
  L2_2 = L2_2 / 180
  L3_2 = A0_2.x
  L2_2 = L2_2 * L3_2
  L1_2.x = L2_2
  L2_2 = math
  L2_2 = L2_2.pi
  L2_2 = L2_2 / 180
  L3_2 = A0_2.y
  L2_2 = L2_2 * L3_2
  L1_2.y = L2_2
  L2_2 = math
  L2_2 = L2_2.pi
  L2_2 = L2_2 / 180
  L3_2 = A0_2.z
  L2_2 = L2_2 * L3_2
  L1_2.z = L2_2
  L2_2 = {}
  L3_2 = math
  L3_2 = L3_2.sin
  L4_2 = L1_2.z
  L3_2 = L3_2(L4_2)
  L3_2 = -L3_2
  L4_2 = math
  L4_2 = L4_2.abs
  L5_2 = math
  L5_2 = L5_2.cos
  L6_2 = L1_2.x
  L5_2, L6_2 = L5_2(L6_2)
  L4_2 = L4_2(L5_2, L6_2)
  L3_2 = L3_2 * L4_2
  L2_2.x = L3_2
  L3_2 = math
  L3_2 = L3_2.cos
  L4_2 = L1_2.z
  L3_2 = L3_2(L4_2)
  L4_2 = math
  L4_2 = L4_2.abs
  L5_2 = math
  L5_2 = L5_2.cos
  L6_2 = L1_2.x
  L5_2, L6_2 = L5_2(L6_2)
  L4_2 = L4_2(L5_2, L6_2)
  L3_2 = L3_2 * L4_2
  L2_2.y = L3_2
  L3_2 = math
  L3_2 = L3_2.sin
  L4_2 = L1_2.x
  L3_2 = L3_2(L4_2)
  L2_2.z = L3_2
  L3_2 = vector3
  L4_2 = L2_2.x
  L5_2 = L2_2.y
  L6_2 = L2_2.z
  return L3_2(L4_2, L5_2, L6_2)
end
RotationToDirection = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L2_2 = StartShapeTestRay
  L3_2 = A0_2.x
  L4_2 = A0_2.y
  L5_2 = A0_2.z
  L6_2 = A1_2.x
  L7_2 = A1_2.y
  L8_2 = A1_2.z
  L9_2 = -1
  L10_2 = -1
  L11_2 = 1
  L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2)
  L3_2 = GetShapeTestResult
  L4_2 = L2_2
  L3_2, L4_2, L5_2, L6_2, L7_2 = L3_2(L4_2)
  L8_2 = 1 == L4_2
  return L8_2
end
IsObstructed = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = IsObstructed
  L3_2 = A0_2
  L4_2 = A1_2
  L2_2 = L2_2(L3_2, L4_2)
  if not L2_2 then
    L2_2 = 0.0
    return L2_2
  end
  L2_2 = 0.8
  return L2_2
end
CalculateOcclusionStrength = L10_1
function L10_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L0_2 = pairs
  L1_2 = L0_1
  L0_2, L1_2, L2_2, L3_2 = L0_2(L1_2)
  for L4_2, L5_2 in L0_2, L1_2, L2_2, L3_2 do
    L6_2 = RemoveSpeaker
    L7_2 = L4_2
    L6_2(L7_2)
  end
  L0_2 = pairs
  L1_2 = L1_1
  L0_2, L1_2, L2_2, L3_2 = L0_2(L1_2)
  for L4_2, L5_2 in L0_2, L1_2, L2_2, L3_2 do
    L6_2 = RemoveAudioSource
    L7_2 = L4_2
    L6_2(L7_2)
  end
  L0_2 = {}
  L4_1 = L0_2
end
CleanupAudioResources = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = L7_1
  L2_2[A0_2] = A1_2
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "setSpeakerFilter"
  L3_2.speakerId = A0_2
  L3_2.enabled = A1_2
  L2_2(L3_2)
  L2_2 = true
  return L2_2
end
SetSpeakerLowPassFilter = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  if not L2_2 or not A1_2 then
    L2_2 = false
    return L2_2
  end
  if A1_2 < 0 or A1_2 > 100 then
    L2_2 = false
    return L2_2
  end
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  L2_2 = L2_2.config
  L2_2.lowPassGainReductionPercent = A1_2
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "updateSpeakerConfig"
  L3_2.speakerId = A0_2
  L4_2 = L0_1
  L4_2 = L4_2[A0_2]
  L4_2 = L4_2.config
  L3_2.config = L4_2
  L2_2(L3_2)
  L2_2 = true
  return L2_2
end
SetSpeakerLowPassFilterPercentage = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = tonumber
  L3_2 = A1_2
  L2_2 = L2_2(L3_2)
  A1_2 = L2_2
  if A1_2 and not (A1_2 < 20) then
    L2_2 = 22050
    if not (A1_2 > L2_2) then
      goto lbl_20
    end
  end
  L2_2 = false
  do return L2_2 end
  ::lbl_20::
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  L2_2 = L2_2.config
  L2_2.lowPassFrequency = A1_2
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "updateSpeakerConfig"
  L3_2.speakerId = A0_2
  L4_2 = L0_1
  L4_2 = L4_2[A0_2]
  L4_2 = L4_2.config
  L3_2.config = L4_2
  L2_2(L3_2)
  L2_2 = true
  return L2_2
end
SetSpeakerLowPassFilterFrequency = L10_1
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = pairs
  L2_2 = L0_1
  L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
  for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
    if nil ~= A0_2 then
      L7_2 = L6_2.config
      L7_2.lowPassGainReductionPercent = A0_2
    end
    L7_2 = SendNUIMessage
    L8_2 = {}
    L8_2.type = "updateSpeakerConfig"
    L8_2.speakerId = L5_2
    L9_2 = L6_2.config
    L8_2.config = L9_2
    L7_2(L8_2)
  end
end
UpdateAllSpeakersLowPassFilter = L10_1
L10_1 = AddEventHandler
L11_1 = "onResourceStop"
function L12_1(A0_2)
  local L1_2
  L1_2 = L2_1
  if A0_2 == L1_2 then
    L1_2 = CleanupAudioResources
    L1_2()
  end
end
L10_1(L11_1, L12_1)
function L10_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = L1_1
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    L2_2 = false
    return L2_2
  end
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "seekAudioSource"
  L3_2.audioSourceId = A0_2
  L3_2.position = A1_2
  L2_2(L3_2)
  L2_2 = true
  return L2_2
end
SeekAudioSource = L10_1
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:SeekAudio"
L12_1 = SeekAudioSource
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "SeekAudioSource"
L12_1 = SeekAudioSource
L10_1(L11_1, L12_1)
function L10_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2
  L3_2 = L0_1
  L3_2 = L3_2[A0_2]
  if not L3_2 then
    L3_2 = print
    L4_2 = "Error: Speaker "
    L5_2 = A0_2
    L6_2 = " not found"
    L4_2 = L4_2 .. L5_2 .. L6_2
    L3_2(L4_2)
    L3_2 = false
    return L3_2
  end
  L3_2 = DoesEntityExist
  L4_2 = A1_2
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    L3_2 = print
    L4_2 = "Error: Entity "
    L5_2 = A1_2
    L6_2 = " does not exist"
    L4_2 = L4_2 .. L5_2 .. L6_2
    L3_2(L4_2)
    L3_2 = false
    return L3_2
  end
  if not A2_2 then
    L3_2 = vector3
    L4_2 = 0.0
    L5_2 = 0.0
    L6_2 = 0.0
    L3_2 = L3_2(L4_2, L5_2, L6_2)
    A2_2 = L3_2
  end
  L3_2 = L0_1
  L3_2 = L3_2[A0_2]
  L3_2 = L3_2.config
  L3_2.attachedEntity = A1_2
  L3_2 = L0_1
  L3_2 = L3_2[A0_2]
  L3_2 = L3_2.config
  L3_2.attachedOffset = A2_2
  L3_2 = true
  return L3_2
end
AttachSpeakerToEntity = L10_1
function L10_1(A0_2)
  local L1_2
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.config
  L1_2 = L1_2.attachedEntity
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.config
  L1_2.attachedEntity = nil
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  L1_2 = L1_2.config
  L1_2.attachedOffset = nil
  L1_2 = true
  return L1_2
end
DetachSpeakerFromEntity = L10_1
L10_1 = Citizen
L10_1 = L10_1.CreateThread
function L11_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2
  L0_2 = 100
  L1_2 = {}
  L2_2 = {}
  while true do
    L3_2 = Citizen
    L3_2 = L3_2.Wait
    L4_2 = L0_2
    L3_2(L4_2)
    L3_2 = {}
    L1_2 = L3_2
    L3_2 = pairs
    L4_2 = L0_1
    L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
    for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
      L9_2 = L8_2.config
      L9_2 = L9_2.attachedEntity
      if not L9_2 then
      else
        L9_2 = L8_2.config
        L9_2 = L9_2.attachedEntity
        L10_2 = DoesEntityExist
        L11_2 = L9_2
        L10_2 = L10_2(L11_2)
        if not L10_2 then
          L10_2 = L2_2[L9_2]
          if not L10_2 then
            L10_2 = {}
            L2_2[L9_2] = L10_2
          end
          L10_2 = table
          L10_2 = L10_2.insert
          L11_2 = L2_2[L9_2]
          L12_2 = L7_2
          L10_2(L11_2, L12_2)
          L10_2 = L8_2.audioSourceId
          L11_2 = RemoveSpeaker
          L12_2 = L7_2
          L11_2(L12_2)
          L11_2 = false
          L12_2 = pairs
          L13_2 = L0_1
          L12_2, L13_2, L14_2, L15_2 = L12_2(L13_2)
          for L16_2, L17_2 in L12_2, L13_2, L14_2, L15_2 do
            L18_2 = L17_2.audioSourceId
            if L18_2 == L10_2 then
              L11_2 = true
              break
            end
          end
          if not L11_2 then
            L12_2 = RemoveAudioSource
            L13_2 = L10_2
            L12_2(L13_2)
          end
        else
          L10_2 = L1_2[L9_2]
          if L10_2 then
            L10_2 = IsEntityVehicle
            L11_2 = L9_2
            L10_2 = L10_2(L11_2)
            if L10_2 then
              L10_2 = L1_2[L9_2]
              L11_2 = L8_2.config
              L11_2.attachedEntity = nil
              L11_2 = L8_2.config
              L11_2.attachedOffset = nil
            else
              L10_2 = L1_2[L9_2]
              L11_2 = L1_2[L9_2]
              L11_2 = #L11_2
              L11_2 = L11_2 + 1
              L10_2[L11_2] = L7_2
              else
                L10_2 = IsEntityVehicle
                L11_2 = L9_2
                L10_2 = L10_2(L11_2)
                if L10_2 then
                  L1_2[L9_2] = L7_2
                  L10_2 = UpdateVehicleSpeakerAudio
                  L11_2 = L7_2
                  L10_2(L11_2)
                else
                  L10_2 = {}
                  L11_2 = L7_2
                  L10_2[1] = L11_2
                  L1_2[L9_2] = L10_2
                end
              end
              L10_2 = UpdateAttachedSpeakerPosition
              L11_2 = L7_2
              L12_2 = L8_2
              L10_2(L11_2, L12_2)
            end
        end
      end
    end
    L3_2 = GetGameTimer
    L3_2 = L3_2()
    L4_2 = pairs
    L5_2 = L2_2
    L4_2, L5_2, L6_2, L7_2 = L4_2(L5_2)
    for L8_2, L9_2 in L4_2, L5_2, L6_2, L7_2 do
      L10_2 = L9_2.timestamp
      if not L10_2 then
        L10_2 = L2_2[L8_2]
        L10_2.timestamp = L3_2
      else
        L10_2 = L9_2.timestamp
        L10_2 = L3_2 - L10_2
        L11_2 = 30000
        if L10_2 > L11_2 then
          L2_2[L8_2] = nil
        end
      end
    end
  end
end
L10_1(L11_1)
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L2_2 = A1_2.config
  L2_2 = L2_2.attachedEntity
  if L2_2 then
    L3_2 = DoesEntityExist
    L4_2 = L2_2
    L3_2 = L3_2(L4_2)
    if L3_2 then
      goto lbl_12
    end
  end
  L3_2 = false
  do return L3_2 end
  ::lbl_12::
  L3_2 = GetEntityCoords
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = A1_2.config
  L4_2 = L4_2.attachedOffset
  if L4_2 then
    L4_2 = A1_2.config
    L4_2 = L4_2.attachedOffset
    L4_2 = L4_2.x
    if 0 == L4_2 then
      L4_2 = A1_2.config
      L4_2 = L4_2.attachedOffset
      L4_2 = L4_2.y
      if 0 == L4_2 then
        L4_2 = A1_2.config
        L4_2 = L4_2.attachedOffset
        L4_2 = L4_2.z
        if 0 == L4_2 then
          goto lbl_61
        end
      end
    end
    L4_2 = GetEntityRotation
    L5_2 = L2_2
    L6_2 = 2
    L4_2 = L4_2(L5_2, L6_2)
    L5_2 = RotationToMatrix
    L6_2 = L4_2
    L5_2 = L5_2(L6_2)
    L6_2 = ApplyRotationToOffset
    L7_2 = L5_2
    L8_2 = A1_2.config
    L8_2 = L8_2.attachedOffset
    L6_2 = L6_2(L7_2, L8_2)
    L7_2 = vector3
    L8_2 = L3_2.x
    L9_2 = L6_2.x
    L8_2 = L8_2 + L9_2
    L9_2 = L3_2.y
    L10_2 = L6_2.y
    L9_2 = L9_2 + L10_2
    L10_2 = L3_2.z
    L11_2 = L6_2.z
    L10_2 = L10_2 + L11_2
    L7_2 = L7_2(L8_2, L9_2, L10_2)
    L3_2 = L7_2
  end
  ::lbl_61::
  L4_2 = HasPositionChanged
  L5_2 = L3_2
  L6_2 = A1_2.position
  L4_2 = L4_2(L5_2, L6_2)
  if L4_2 then
    L4_2 = UpdateSpeakerPosition
    L5_2 = A0_2
    L6_2 = L3_2
    L4_2(L5_2, L6_2)
    L4_2 = true
    return L4_2
  end
  L4_2 = false
  return L4_2
end
UpdateAttachedSpeakerPosition = L10_1
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2
  L1_2 = math
  L1_2 = L1_2.pi
  L1_2 = L1_2 / 180
  L2_2 = A0_2.x
  L1_2 = L1_2 * L2_2
  L2_2 = math
  L2_2 = L2_2.pi
  L2_2 = L2_2 / 180
  L3_2 = A0_2.y
  L2_2 = L2_2 * L3_2
  L3_2 = math
  L3_2 = L3_2.pi
  L3_2 = L3_2 / 180
  L4_2 = A0_2.z
  L3_2 = L3_2 * L4_2
  L4_2 = math
  L4_2 = L4_2.sin
  L5_2 = L1_2
  L4_2 = L4_2(L5_2)
  L5_2 = math
  L5_2 = L5_2.cos
  L6_2 = L1_2
  L5_2 = L5_2(L6_2)
  L6_2 = math
  L6_2 = L6_2.sin
  L7_2 = L2_2
  L6_2 = L6_2(L7_2)
  L7_2 = math
  L7_2 = L7_2.cos
  L8_2 = L2_2
  L7_2 = L7_2(L8_2)
  L8_2 = math
  L8_2 = L8_2.sin
  L9_2 = L3_2
  L8_2 = L8_2(L9_2)
  L9_2 = math
  L9_2 = L9_2.cos
  L10_2 = L3_2
  L9_2 = L9_2(L10_2)
  L10_2 = {}
  L11_2 = {}
  L12_2 = L9_2 * L7_2
  L13_2 = L9_2 * L6_2
  L13_2 = L13_2 * L4_2
  L14_2 = L8_2 * L5_2
  L13_2 = L13_2 - L14_2
  L14_2 = L9_2 * L6_2
  L14_2 = L14_2 * L5_2
  L15_2 = L8_2 * L4_2
  L14_2 = L14_2 + L15_2
  L11_2[1] = L12_2
  L11_2[2] = L13_2
  L11_2[3] = L14_2
  L12_2 = {}
  L13_2 = L8_2 * L7_2
  L14_2 = L8_2 * L6_2
  L14_2 = L14_2 * L4_2
  L15_2 = L9_2 * L5_2
  L14_2 = L14_2 + L15_2
  L15_2 = L8_2 * L6_2
  L15_2 = L15_2 * L5_2
  L16_2 = L9_2 * L4_2
  L15_2 = L15_2 - L16_2
  L12_2[1] = L13_2
  L12_2[2] = L14_2
  L12_2[3] = L15_2
  L13_2 = {}
  L14_2 = -L6_2
  L15_2 = L7_2 * L4_2
  L16_2 = L7_2 * L5_2
  L13_2[1] = L14_2
  L13_2[2] = L15_2
  L13_2[3] = L16_2
  L10_2[1] = L11_2
  L10_2[2] = L12_2
  L10_2[3] = L13_2
  return L10_2
end
RotationToMatrix = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  L2_2 = vector3
  L3_2 = A0_2[1]
  L3_2 = L3_2[1]
  L4_2 = A1_2.x
  L3_2 = L3_2 * L4_2
  L4_2 = A0_2[1]
  L4_2 = L4_2[2]
  L5_2 = A1_2.y
  L4_2 = L4_2 * L5_2
  L3_2 = L3_2 + L4_2
  L4_2 = A0_2[1]
  L4_2 = L4_2[3]
  L5_2 = A1_2.z
  L4_2 = L4_2 * L5_2
  L3_2 = L3_2 + L4_2
  L4_2 = A0_2[2]
  L4_2 = L4_2[1]
  L5_2 = A1_2.x
  L4_2 = L4_2 * L5_2
  L5_2 = A0_2[2]
  L5_2 = L5_2[2]
  L6_2 = A1_2.y
  L5_2 = L5_2 * L6_2
  L4_2 = L4_2 + L5_2
  L5_2 = A0_2[2]
  L5_2 = L5_2[3]
  L6_2 = A1_2.z
  L5_2 = L5_2 * L6_2
  L4_2 = L4_2 + L5_2
  L5_2 = A0_2[3]
  L5_2 = L5_2[1]
  L6_2 = A1_2.x
  L5_2 = L5_2 * L6_2
  L6_2 = A0_2[3]
  L6_2 = L6_2[2]
  L7_2 = A1_2.y
  L6_2 = L6_2 * L7_2
  L5_2 = L5_2 + L6_2
  L6_2 = A0_2[3]
  L6_2 = L6_2[3]
  L7_2 = A1_2.z
  L6_2 = L6_2 * L7_2
  L5_2 = L5_2 + L6_2
  return L2_2(L3_2, L4_2, L5_2)
end
ApplyRotationToOffset = L10_1
L10_1 = exports
L11_1 = "AttachSpeakerToEntity"
L12_1 = AttachSpeakerToEntity
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "DetachSpeakerFromEntity"
L12_1 = DetachSpeakerFromEntity
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "CreateAttachedSpeaker"
function L12_1(A0_2, A1_2, A2_2, A3_2, A4_2)
  local L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  if not (A0_2 and A1_2) or not A3_2 then
    L5_2 = print
    L6_2 = "Error: Missing required parameters for CreateAttachedSpeaker"
    L5_2(L6_2)
    L5_2 = false
    return L5_2
  end
  L5_2 = DoesEntityExist
  L6_2 = A1_2
  L5_2 = L5_2(L6_2)
  if not L5_2 then
    L5_2 = print
    L6_2 = "Error: Entity "
    L7_2 = A1_2
    L8_2 = " does not exist"
    L6_2 = L6_2 .. L7_2 .. L8_2
    L5_2(L6_2)
    L5_2 = false
    return L5_2
  end
  L5_2 = GetEntityCoords
  L6_2 = A1_2
  L5_2 = L5_2(L6_2)
  L6_2 = A2_2 or L6_2
  if not A2_2 then
    L6_2 = L8_1
  end
  if not A4_2 then
    L7_2 = vector3
    L8_2 = 0.0
    L9_2 = 0.0
    L10_2 = 0.0
    L7_2 = L7_2(L8_2, L9_2, L10_2)
    A4_2 = L7_2
  end
  L6_2.attachedEntity = A1_2
  L6_2.attachedOffset = A4_2
  L7_2 = AddSpeaker
  L8_2 = A0_2
  L9_2 = L5_2
  L10_2 = L6_2
  L11_2 = A3_2
  L7_2 = L7_2(L8_2, L9_2, L10_2, L11_2)
  if not L7_2 then
    L7_2 = false
    return L7_2
  end
  L7_2 = true
  return L7_2
end
L10_1(L11_1, L12_1)
function L10_1(A0_2)
  local L1_2, L2_2
  if not A0_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = GetEntityType
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  L1_2 = 2 == L1_2
  return L1_2
end
IsEntityVehicle = L10_1
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2
  if A0_2 then
    L1_2 = DoesEntityExist
    L2_2 = A0_2
    L1_2 = L1_2(L2_2)
    if L1_2 then
      goto lbl_10
    end
  end
  L1_2 = false
  do return L1_2 end
  ::lbl_10::
  L1_2 = PlayerPedId
  L1_2 = L1_2()
  L2_2 = GetVehiclePedIsIn
  L3_2 = L1_2
  L4_2 = false
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = L2_2 == A0_2
  return L3_2
end
IsPlayerInEntity = L10_1
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2
  if A0_2 then
    L1_2 = DoesEntityExist
    L2_2 = A0_2
    L1_2 = L1_2(L2_2)
    if L1_2 then
      goto lbl_10
    end
  end
  L1_2 = false
  do return L1_2 end
  ::lbl_10::
  L1_2 = 0
  L2_2 = GetNumberOfVehicleDoors
  L3_2 = A0_2
  L2_2 = L2_2(L3_2)
  L3_2 = 1
  for L4_2 = L1_2, L2_2, L3_2 do
    L5_2 = DoesVehicleHaveDoor
    L6_2 = A0_2
    L7_2 = L4_2
    L5_2 = L5_2(L6_2, L7_2)
    if L5_2 then
      L5_2 = GetVehicleDoorAngleRatio
      L6_2 = A0_2
      L7_2 = L4_2
      L5_2 = L5_2(L6_2, L7_2)
      L6_2 = 0.1
      if L5_2 > L6_2 then
        L6_2 = true
        return L6_2
      end
    end
  end
  L1_2 = AreAllVehicleWindowsIntact
  L2_2 = A0_2
  L1_2 = L1_2(L2_2)
  if L1_2 then
    L1_2 = windowsOpen
    if not L1_2 then
      goto lbl_42
    end
  end
  L1_2 = true
  do return L1_2 end
  ::lbl_42::
  L1_2 = false
  return L1_2
end
IsVehicleOpenOrDamaged = L10_1
function L10_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = L0_1
  L2_2 = L2_2[A0_2]
  if L2_2 then
    L3_2 = L2_2.config
    L3_2.pannerDisabled = A1_2
    L3_2 = L2_2.config
    L3_2.pannerManuallySet = true
    L3_2 = SendNUIMessage
    L4_2 = {}
    L4_2.type = "updateVehicleSpeaker"
    L4_2.speakerId = A0_2
    L4_2.priority = true
    L5_2 = {}
    L6_2 = L2_2.config
    L6_2 = L6_2.pannerDisabled
    L5_2.pannerDisabled = L6_2
    L6_2 = L2_2.config
    L6_2 = L6_2.lowPassFrequency
    L5_2.lowPassFrequency = L6_2
    L6_2 = L2_2.config
    L6_2 = L6_2.lowPassGainReductionPercent
    L5_2.lowPassGainReductionPercent = L6_2
    L6_2 = L2_2.config
    L6_2 = L6_2.isInVehicle
    L5_2.isInVehicle = L6_2
    L4_2.config = L5_2
    L3_2(L4_2)
    L3_2 = GetGameTimer
    L3_2 = L3_2()
    L2_2.lastFilterUpdate = L3_2
  end
end
ToggleSpeakerPanner = L10_1
L10_1 = exports
L11_1 = "ToggleSpeakerPanner"
L12_1 = ToggleSpeakerPanner
L10_1(L11_1, L12_1)
function L10_1(A0_2)
  local L1_2, L2_2
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  if L1_2 then
    L2_2 = L1_2.config
    L2_2.pannerManuallySet = false
    L2_2 = true
    return L2_2
  end
  L2_2 = false
  return L2_2
end
ResetSpeakerPannerOverride = L10_1
L10_1 = exports
L11_1 = "ResetSpeakerPannerOverride"
L12_1 = ResetSpeakerPannerOverride
L10_1(L11_1, L12_1)
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  if L1_2 then
    L2_2 = L1_2.config
    L2_2 = L2_2.attachedEntity
    if L2_2 then
      goto lbl_10
    end
  end
  do return end
  ::lbl_10::
  L2_2 = L1_2.config
  L2_2 = L2_2.attachedEntity
  L3_2 = IsEntityVehicle
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    return
  end
  L3_2 = IsPlayerInEntity
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  L4_2 = IsVehicleOpenOrDamaged
  L5_2 = L2_2
  L4_2 = L4_2(L5_2)
  L5_2 = false
  L6_2 = L1_2.config
  L6_2 = L6_2.isInVehicle
  if L6_2 ~= L3_2 then
    L6_2 = L1_2.config
    L6_2.isInVehicle = L3_2
    L5_2 = true
  end
  if L3_2 then
    L6_2 = L1_2.config
    L6_2 = L6_2.pannerManuallySet
    if not L6_2 then
      L6_2 = L1_2.config
      L6_2 = L6_2.pannerDisabled
      if true ~= L6_2 then
        L6_2 = L1_2.config
        L6_2.pannerDisabled = true
        L5_2 = true
      end
    end
    L6_2 = L1_2.config
    L6_2 = L6_2.lowPassFrequency
    if L6_2 then
      L6_2 = L1_2.config
      L6_2 = L6_2.lowPassFrequency
      if L6_2 > 0 then
        goto lbl_57
      end
    end
    L6_2 = L1_2.config
    L6_2 = L6_2.lowPassGainReductionPercent
    ::lbl_57::
    if L6_2 > 0 then
      L6_2 = L1_2.config
      L6_2.lowPassFrequency = 0
      L6_2 = L1_2.config
      L6_2.lowPassGainReductionPercent = 0
      L5_2 = true
    end
  else
    L6_2 = L1_2.config
    L6_2 = L6_2.pannerManuallySet
    if not L6_2 then
      L6_2 = L1_2.config
      L6_2 = L6_2.pannerDisabled
      if false ~= L6_2 then
        L6_2 = L1_2.config
        L6_2.pannerDisabled = false
        L5_2 = true
      end
    end
    if L4_2 then
      L6_2 = L1_2.config
      L6_2 = L6_2.lowPassFrequency
      if L6_2 then
        L6_2 = L1_2.config
        L6_2 = L6_2.lowPassFrequency
        if L6_2 > 0 then
          goto lbl_88
        end
      end
      L6_2 = L1_2.config
      L6_2 = L6_2.lowPassGainReductionPercent
      ::lbl_88::
      if L6_2 > 0 then
        L6_2 = L1_2.config
        L6_2.lowPassFrequency = 0
        L6_2 = L1_2.config
        L6_2.lowPassGainReductionPercent = 0
        L5_2 = true
      end
    else
      L6_2 = L1_2.config
      L6_2 = L6_2.lowPassFrequency
      if L6_2 then
        L6_2 = L1_2.config
        L6_2 = L6_2.lowPassFrequency
        if 250 ~= L6_2 then
          goto lbl_106
        end
      end
      L6_2 = L1_2.config
      L6_2 = L6_2.lowPassGainReductionPercent
      ::lbl_106::
      if 60 ~= L6_2 then
        L6_2 = L1_2.config
        L6_2.lowPassFrequency = 250
        L6_2 = L1_2.config
        L6_2.lowPassGainReductionPercent = 60
        L5_2 = true
      end
    end
  end
  if L5_2 then
    L6_2 = SendNUIMessage
    L7_2 = {}
    L7_2.type = "updateVehicleSpeaker"
    L7_2.speakerId = A0_2
    L7_2.priority = true
    L8_2 = {}
    L9_2 = L1_2.config
    L9_2 = L9_2.pannerDisabled
    L8_2.pannerDisabled = L9_2
    L9_2 = L1_2.config
    L9_2 = L9_2.lowPassFrequency
    L8_2.lowPassFrequency = L9_2
    L9_2 = L1_2.config
    L9_2 = L9_2.lowPassGainReductionPercent
    L8_2.lowPassGainReductionPercent = L9_2
    L9_2 = L1_2.config
    L9_2 = L9_2.isInVehicle
    L8_2.isInVehicle = L9_2
    L7_2.config = L8_2
    L6_2(L7_2)
    L6_2 = GetGameTimer
    L6_2 = L6_2()
    L1_2.lastFilterUpdate = L6_2
  end
end
UpdateVehicleSpeakerAudio = L10_1
function L10_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2
  L1_2 = L0_1
  L1_2 = L1_2[A0_2]
  if L1_2 then
    L2_2 = L1_2.config
    L2_2 = L2_2.attachedEntity
    if L2_2 then
      goto lbl_10
    end
  end
  do return end
  ::lbl_10::
  L2_2 = L1_2.config
  L2_2 = L2_2.attachedEntity
  L3_2 = DoesEntityExist
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  if not L3_2 then
    return
  end
  L3_2 = IsEntityVehicle
  L4_2 = L2_2
  L3_2 = L3_2(L4_2)
  if L3_2 then
    L3_2 = UpdateVehicleSpeakerAudio
    L4_2 = A0_2
    L3_2(L4_2)
  else
    L3_2 = IsEntityAPed
    L4_2 = L2_2
    L3_2 = L3_2(L4_2)
    if L3_2 then
      L3_2 = L1_2.config
      L3_2 = L3_2.pannerManuallySet
      if not L3_2 then
        L3_2 = L1_2.config
        L3_2 = L3_2.pannerDisabled
        if L3_2 then
          L3_2 = L1_2.config
          L3_2.pannerDisabled = false
          L3_2 = SendNUIMessage
          L4_2 = {}
          L4_2.type = "updateSpeakerConfig"
          L4_2.speakerId = A0_2
          L5_2 = {}
          L5_2.pannerDisabled = false
          L4_2.config = L5_2
          L3_2(L4_2)
        end
      end
    else
      L3_2 = IsEntityAnObject
      L4_2 = L2_2
      L3_2 = L3_2(L4_2)
      if L3_2 then
        L3_2 = L1_2.config
        L3_2 = L3_2.pannerManuallySet
        if not L3_2 then
          L3_2 = L1_2.config
          L3_2 = L3_2.pannerDisabled
          if L3_2 then
            L3_2 = L1_2.config
            L3_2.pannerDisabled = false
            L3_2 = SendNUIMessage
            L4_2 = {}
            L4_2.type = "updateSpeakerConfig"
            L4_2.speakerId = A0_2
            L5_2 = {}
            L5_2.pannerDisabled = false
            L4_2.config = L5_2
            L3_2(L4_2)
          end
        end
      end
    end
  end
end
UpdateEntitySpeakerAudio = L10_1
function L10_1(A0_2)
  local L1_2, L2_2
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.type = "pauseAudioSource"
  L2_2.audioSourceId = A0_2
  L1_2(L2_2)
  L1_2 = true
  return L1_2
end
PauseAudioSource = L10_1
function L10_1(A0_2)
  local L1_2, L2_2
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = SendNUIMessage
  L2_2 = {}
  L2_2.type = "resumeAudioSource"
  L2_2.audioSourceId = A0_2
  L1_2(L2_2)
  L1_2 = true
  return L1_2
end
ResumeAudioSource = L10_1
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:PauseAudio"
L12_1 = PauseAudioSource
L10_1(L11_1, L12_1)
L10_1 = RegisterNetEvent
L11_1 = "ts-sounds:client:ResumeAudio"
L12_1 = ResumeAudioSource
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "PauseAudioSource"
L12_1 = PauseAudioSource
L10_1(L11_1, L12_1)
L10_1 = exports
L11_1 = "ResumeAudioSource"
L12_1 = ResumeAudioSource
L10_1(L11_1, L12_1)
L10_1 = {}
L11_1 = {}
L10_1.onPlaybackStarted = L11_1
L11_1 = {}
L10_1.onPlaybackStopped = L11_1
L11_1 = {}
L10_1.onPlaybackPaused = L11_1
L11_1 = {}
L10_1.onPlaybackResumed = L11_1
L11_1 = {}
L10_1.onAudioReady = L11_1
L11_1 = {}
L10_1.onAudioError = L11_1
L11_1 = {}
L10_1.onAudioEnded = L11_1
function L11_1(A0_2, A1_2, A2_2, A3_2)
  local L4_2, L5_2, L6_2
  L4_2 = L1_1
  L4_2 = L4_2[A0_2]
  if not L4_2 then
    L4_2 = print
    L5_2 = "Warning: Registering callback for non-existent audio source: "
    L6_2 = A0_2
    L5_2 = L5_2 .. L6_2
    L4_2(L5_2)
  end
  L4_2 = L10_1
  L4_2 = L4_2[A1_2]
  if not L4_2 then
    L4_2 = print
    L5_2 = "Error: Invalid audio event type: "
    L6_2 = A1_2
    L5_2 = L5_2 .. L6_2
    L4_2(L5_2)
    L4_2 = false
    return L4_2
  end
  L4_2 = L10_1
  L4_2 = L4_2[A1_2]
  L4_2 = L4_2[A0_2]
  if not L4_2 then
    L4_2 = L10_1
    L4_2 = L4_2[A1_2]
    L5_2 = {}
    L4_2[A0_2] = L5_2
  end
  L4_2 = table
  L4_2 = L4_2.insert
  L5_2 = L10_1
  L5_2 = L5_2[A1_2]
  L5_2 = L5_2[A0_2]
  L6_2 = {}
  L6_2.callback = A2_2
  L6_2.isServer = A3_2
  L4_2(L5_2, L6_2)
  L4_2 = true
  return L4_2
end
RegisterAudioCallback = L11_1
L11_1 = RegisterNetEvent
L12_1 = "ts-sounds:client:ChangeOwner"
function L13_1(A0_2, A1_2)
  local L2_2
  L2_2 = L1_1
  L2_2 = L2_2[A0_2]
  if not L2_2 then
    return
  end
  L2_2 = L1_1
  L2_2 = L2_2[A0_2]
  L2_2.audioOwner = A1_2
end
L11_1(L12_1, L13_1)
function L11_1(A0_2, A1_2, ...)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2
  L2_2 = L10_1
  L2_2 = L2_2[A1_2]
  if L2_2 then
    L2_2 = L10_1
    L2_2 = L2_2[A1_2]
    L2_2 = L2_2[A0_2]
    if L2_2 then
      goto lbl_12
    end
  end
  do return end
  ::lbl_12::
  L2_2 = ipairs
  L3_2 = L10_1
  L3_2 = L3_2[A1_2]
  L3_2 = L3_2[A0_2]
  L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
  for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
    L8_2 = L7_2.callback
    L9_2 = L7_2.isServer
    if L9_2 then
      L10_2 = L1_1
      L10_2 = L10_2[A0_2]
      if L10_2 then
        L10_2 = L1_1
        L10_2 = L10_2[A0_2]
        L10_2 = L10_2.audioOwner
      end
      L11_2 = GetPlayerServerId
      L12_2 = PlayerId
      L12_2, L13_2, L14_2, L15_2 = L12_2()
      L11_2 = L11_2(L12_2, L13_2, L14_2, L15_2)
      if L10_2 == L11_2 then
        L11_2 = TriggerServerEvent
        L12_2 = "ts-sounds:server:AudioCallback"
        L13_2 = A0_2
        L14_2 = A1_2
        L15_2 = ...
        L11_2(L12_2, L13_2, L14_2, L15_2)
      end
    else
      L10_2 = L8_2
      L11_2, L12_2, L13_2, L14_2, L15_2 = ...
      L10_2(L11_2, L12_2, L13_2, L14_2, L15_2)
    end
  end
end
TriggerAudioCallbacks = L11_1
L11_1 = {}
L12_1 = {}
function L13_1(A0_2, A1_2)
  local L2_2, L3_2
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "fetchData"
  L3_2.url = A0_2
  L2_2(L3_2)
  L2_2 = L11_1
  L2_2[A0_2] = A1_2
end
FetchData = L13_1
L13_1 = exports
L14_1 = "FetchData"
L15_1 = FetchData
L13_1(L14_1, L15_1)
function L13_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = L1_1
  L1_2 = L1_2[A0_2]
  if not L1_2 then
    L1_2 = false
    return L1_2
  end
  L1_2 = promise
  L2_2 = L1_2
  L1_2 = L1_2.new
  L1_2 = L1_2(L2_2)
  L2_2 = L12_1
  L2_2[A0_2] = L1_2
  L2_2 = SendNUIMessage
  L3_2 = {}
  L3_2.type = "getCurrentTime"
  L3_2.audioSourceId = A0_2
  L2_2(L3_2)
  L2_2 = Citizen
  L2_2 = L2_2.Await
  L3_2 = L1_2
  L2_2(L3_2)
  L2_2 = math
  L2_2 = L2_2.floor
  L3_2 = L1_2.value
  if not L3_2 then
    L3_2 = 0
  end
  return L2_2(L3_2)
end
GetCurrentTime = L13_1
L13_1 = exports
L14_1 = "GetCurrentTime"
L15_1 = GetCurrentTime
L13_1(L14_1, L15_1)
L13_1 = RegisterNUICallback
L14_1 = "currentTime"
function L15_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2
  L2_2 = A0_2.audioSourceId
  L3_2 = A0_2.currentTime
  L4_2 = L12_1
  L4_2 = L4_2[L2_2]
  if L4_2 then
    L4_2 = L12_1
    L4_2 = L4_2[L2_2]
    L5_2 = L4_2
    L4_2 = L4_2.resolve
    L6_2 = L3_2
    L4_2(L5_2, L6_2)
    L4_2 = L12_1
    L4_2[L2_2] = nil
  end
  L4_2 = A1_2
  L5_2 = "ok"
  L4_2(L5_2)
end
L13_1(L14_1, L15_1)
L13_1 = RegisterNUICallback
L14_1 = "receiveTitle"
function L15_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = A0_2.url
  L3_2 = L11_1
  L3_2 = L3_2[L2_2]
  if L3_2 then
    L3_2 = L11_1
    L3_2 = L3_2[L2_2]
    L4_2 = A0_2
    L3_2(L4_2)
    L3_2 = L11_1
    L3_2[L2_2] = nil
  end
  L3_2 = A1_2
  L4_2 = "ok"
  L3_2(L4_2)
end
L13_1(L14_1, L15_1)
L13_1 = RegisterNUICallback
L14_1 = "audioEvent"
function L15_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L2_2 = A1_2
  L3_2 = {}
  L2_2(L3_2)
  L2_2 = A0_2.eventType
  L3_2 = A0_2.audioSourceId
  L4_2 = A0_2.data
  if not L3_2 or not L2_2 then
    return
  end
  L5_2 = {}
  L5_2.playbackStarted = "onPlaybackStarted"
  L5_2.playbackPaused = "onPlaybackPaused"
  L5_2.playbackResumed = "onPlaybackResumed"
  L5_2.ready = "onAudioReady"
  L5_2.error = "onAudioError"
  L5_2.ended = "onAudioEnded"
  L6_2 = L5_2[L2_2]
  if not L6_2 then
    return
  end
  if "playbackStarted" == L2_2 then
    L7_2 = L1_1
    L7_2 = L7_2[L3_2]
    if L7_2 then
      L7_2 = L1_1
      L7_2 = L7_2[L3_2]
      L7_2.playing = true
    end
  elseif "playbackPaused" == L2_2 then
    L7_2 = L1_1
    L7_2 = L7_2[L3_2]
    if L7_2 then
      L7_2 = L1_1
      L7_2 = L7_2[L3_2]
      L7_2.playing = false
    end
  elseif "playbackResumed" == L2_2 then
    L7_2 = L1_1
    L7_2 = L7_2[L3_2]
    if L7_2 then
      L7_2 = L1_1
      L7_2 = L7_2[L3_2]
      L7_2.playing = true
    end
  elseif "ended" == L2_2 then
    L7_2 = L1_1
    L7_2 = L7_2[L3_2]
    if L7_2 then
      L7_2 = RemoveAudioSource
      L8_2 = L3_2
      L7_2(L8_2)
      L7_2 = L1_1
      L7_2[L3_2] = nil
    end
  end
  L7_2 = TriggerAudioCallbacks
  L8_2 = L3_2
  L9_2 = L6_2
  L10_2 = L4_2
  L7_2(L8_2, L9_2, L10_2)
end
L13_1(L14_1, L15_1)
L13_1 = exports
L14_1 = "RegisterAudioCallback"
L15_1 = RegisterAudioCallback
L13_1(L14_1, L15_1)

