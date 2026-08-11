local L0_1, L1_1, L2_1, L3_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2
  L0_2 = IsDuplicityVersion
  L0_2 = L0_2()
  if L0_2 then
    L0_2 = dbg
    L0_2 = L0_2.debug
    L1_2 = "Server API loaded."
    L0_2(L1_2)
    L0_2 = exports
    L1_2 = "Jail"
    L2_2 = PrisonService
    L2_2 = L2_2.Jail
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "StartCOMS"
    L2_2 = COMSService
    L2_2 = L2_2.StartPerollForCitizen
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "Unjail"
    L2_2 = PrisonService
    L2_2 = L2_2.Unjail
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "UnjailOffline"
    L2_2 = PrisonService
    L2_2 = L2_2.UnjailOfflineCitizen
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "IsPrisoner"
    L2_2 = PrisonService
    L2_2 = L2_2.CheckForAnySentence
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "GetPrisonerData"
    L2_2 = PrisonService
    L2_2 = L2_2.getPlayer
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "EditPrisonerSentence"
    L2_2 = PrisonService
    L2_2 = L2_2.EditSentenceBySource
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "AddCredits"
    L2_2 = PrisonAccountService
    L2_2 = L2_2.AddCredits
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "RemoveCredits"
    L2_2 = PrisonAccountService
    L2_2 = L2_2.RemoveCredits
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "SetSolitary"
    L2_2 = SolitaryService
    L2_2 = L2_2.SetPrisonerSentence
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "IsPrisonerInSolitary"
    L2_2 = SolitaryService
    L2_2 = L2_2.HasSentence
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "ReleaseFromSolitary"
    L2_2 = SolitaryService
    L2_2 = L2_2.ReleasePrisoner
    L0_2(L1_2, L2_2)
  else
    L0_2 = exports
    L1_2 = "JailByIdentifier"
    L2_2 = JailByIdentifier
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "Jail"
    L2_2 = JailPlayer
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "IsPrisoner"
    L2_2 = PrisonService
    L2_2 = L2_2.IsPrisoner
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "Unjail"
    L2_2 = UnjailPlayer
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "IsPlayerInCutScene"
    L2_2 = PrologService
    L2_2 = L2_2.GetPlayerCutSceneState
    L0_2(L1_2, L2_2)
    L0_2 = exports
    L1_2 = "RestorePrisonerOutfit"
    function L2_2()
      local L0_3, L1_3
      L0_3 = ApplyOutfit
      L1_3 = Outfits
      L0_3(L1_3)
      L0_3 = true
      return L0_3
    end
    L0_2(L1_2, L2_2)
  end
end
L2_1 = "sv-api code name: Phoenix"
L0_1(L1_1, L2_1)
L0_1 = IsDuplicityVersion
L0_1 = L0_1()
if not L0_1 then
  L0_1 = {}
  function L1_1(A0_2, A1_2)
    local L2_2, L3_2, L4_2
    L2_2 = L0_1
    L2_2 = L2_2[A0_2]
    if not L2_2 then
      L2_2 = L0_1
      L3_2 = {}
      L2_2[A0_2] = L3_2
    end
    L2_2 = table
    L2_2 = L2_2.insert
    L3_2 = L0_1
    L3_2 = L3_2[A0_2]
    L4_2 = A1_2
    L2_2(L3_2, L4_2)
  end
  RegisterListener = L1_1
  function L1_1(A0_2, ...)
    local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
    L1_2 = L0_1
    L1_2 = L1_2[A0_2]
    if L1_2 then
      L1_2 = ipairs
      L2_2 = L0_1
      L2_2 = L2_2[A0_2]
      L1_2, L2_2, L3_2, L4_2 = L1_2(L2_2)
      for L5_2, L6_2 in L1_2, L2_2, L3_2, L4_2 do
        L7_2 = L6_2
        L8_2 = ...
        L7_2(L8_2)
      end
    end
  end
  TriggerListeners = L1_1
  function L1_1(A0_2, A1_2)
    local L2_2, L3_2, L4_2, L5_2, L6_2
    L2_2 = "%s:%s:%s"
    L3_2 = L2_2
    L2_2 = L2_2.format
    L4_2 = GetCurrentResourceName
    L4_2 = L4_2()
    L5_2 = "client"
    L6_2 = A0_2
    L2_2 = L2_2(L3_2, L4_2, L5_2, L6_2)
    if L2_2 then
      L3_2 = AddEventHandler
      L4_2 = A0_2
      function L5_2(...)
        local L0_3, L1_3
        L0_3 = A1_2
        L1_3 = ...
        L0_3(L1_3)
      end
      L3_2(L4_2, L5_2)
    end
  end
  RegisterLocalClientEvent = L1_1
  function L1_1(A0_2, ...)
    local L1_2, L2_2, L3_2, L4_2, L5_2
    L1_2 = "%s:%s:%s"
    L2_2 = L1_2
    L1_2 = L1_2.format
    L3_2 = GetCurrentResourceName
    L3_2 = L3_2()
    L4_2 = "client"
    L5_2 = A0_2
    L1_2 = L1_2(L2_2, L3_2, L4_2, L5_2)
    if L1_2 then
      L2_2 = TriggerEvent
      L3_2 = A0_2
      L4_2, L5_2 = ...
      L2_2(L3_2, L4_2, L5_2)
    end
  end
  TriggerLocalClientEvent = L1_1
  L1_1 = exports
  L2_1 = "registerListener"
  L3_1 = RegisterListener
  L1_1(L2_1, L3_1)
  L1_1 = RegisterLocalClientEvent
  L2_1 = "onHud"
  function L3_1(A0_2, A1_2, A2_2)
    local L3_2, L4_2, L5_2, L6_2, L7_2
    L3_2 = TriggerListeners
    L4_2 = "onHud"
    L5_2 = A0_2
    L6_2 = A1_2
    L7_2 = A2_2
    L3_2(L4_2, L5_2, L6_2, L7_2)
  end
  L1_1(L2_1, L3_1)
end
