local L0_1, L1_1
function L0_1()
  local L0_2, L1_2
  L0_2 = {}
  L0_2.id = nil
  L0_2.charId = nil
  L0_2.perollAmount = 0
  L0_2.perollTarget = nil
  L0_2.zoneId = nil
  L1_2 = COMS_STATES
  L1_2 = L1_2.IDLE
  L0_2.state = L1_2
  return L0_2
end
COMSPlayerModel = L0_1
