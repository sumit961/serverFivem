local L0_1, L1_1
L0_1 = {}
Sound = L0_1
L0_1 = Sound
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Sound
  L1_2 = L1_2.HandleAmbientSound
  L2_2 = "AZ_COUNTRYSIDE_PRISON_01_ANNOUNCER_GENERAL"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
end
L0_1.HandleAnnoucement = L1_1
L0_1 = Sound
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Sound
  L1_2 = L1_2.HandleAmbientSound
  L2_2 = "AZ_COUNTRYSIDE_PRISON_01_ANNOUNCER_ALARM"
  L3_2 = A0_2
  L1_2(L2_2, L3_2)
end
L0_1.HandleAlarmAnnoucement = L1_1
L0_1 = Sound
function L1_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2, L5_2
  L2_2 = SetAmbientZoneState
  L3_2 = A0_2
  L4_2 = A1_2
  L5_2 = true
  L2_2(L3_2, L4_2, L5_2)
end
L0_1.HandleAmbientSound = L1_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2
  L0_2 = Config
  L0_2 = L0_2.Sounds
  if L0_2 then
    L0_2 = Config
    L0_2 = L0_2.Sounds
    L0_2 = L0_2.UseCustomAlarmSound
    if L0_2 then
      L0_2 = dbg
      L0_2 = L0_2.debug
      L1_2 = "Audio bank is disabled, using own solution"
      return L0_2(L1_2)
    end
  end
  L0_2 = Sound
  L0_2 = L0_2.RequestAlarm
  L0_2()
end
L0_1(L1_1)
L0_1 = Sound
function L1_1(A0_2)
  local L1_2, L2_2
  if A0_2 then
    L1_2 = dbg
    L1_2 = L1_2.debug
    L2_2 = "Alarm started, since Prison break is active!"
    L1_2(L2_2)
    L1_2 = Sound
    L1_2 = L1_2.HandleAlarmAnnoucement
    L2_2 = true
    L1_2(L2_2)
    L1_2 = Sound
    L1_2 = L1_2.SetPrisonAlarm
    L2_2 = true
    L1_2(L2_2)
  elseif not A0_2 then
    L1_2 = Sound
    L1_2 = L1_2.StopAlarm
    L1_2()
  end
end
L0_1.StartAlarm = L1_1
L0_1 = Sound
function L1_1()
  local L0_2, L1_2
  L0_2 = Sound
  L0_2 = L0_2.HandleAlarmAnnoucement
  L1_2 = false
  L0_2(L1_2)
  L0_2 = Sound
  L0_2 = L0_2.SetPrisonAlarm
  L1_2 = false
  L0_2(L1_2)
end
L0_1.StopAlarm = L1_1
L0_1 = Sound
function L1_1()
  local L0_2, L1_2
  L0_2 = PrepareAlarm
  L1_2 = "PRISON_ALARMS"
  L0_2(L1_2)
end
L0_1.RequestAlarm = L1_1
L0_1 = Sound
function L1_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = Config
  L1_2 = L1_2.Sounds
  if L1_2 then
    L1_2 = Config
    L1_2 = L1_2.Sounds
    L1_2 = L1_2.UseCustomAlarmSound
    if L1_2 then
      if A0_2 then
        L1_2 = dbg
        L1_2 = L1_2.debug
        L2_2 = "Starting alarm sound - custom"
        L1_2(L2_2)
        L1_2 = StartAlarm
        L1_2()
      else
        L1_2 = dbg
        L1_2 = L1_2.debug
        L2_2 = "Stopping alarm sound - custom"
        L1_2(L2_2)
        L1_2 = StopAlarm
        L1_2()
      end
      return
    end
  end
  if A0_2 then
    L1_2 = StartAlarm
    L2_2 = "PRISON_ALARMS"
    L3_2 = true
    L1_2(L2_2, L3_2)
  else
    L1_2 = StopAlarm
    L2_2 = "PRISON_ALARMS"
    L3_2 = true
    L1_2(L2_2, L3_2)
  end
end
L0_1.SetPrisonAlarm = L1_1
