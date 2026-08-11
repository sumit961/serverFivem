local L0_1, L1_1, L2_1, L3_1, L4_1, L5_1, L6_1, L7_1, L8_1
L0_1 = {}
SH = L0_1
L0_1 = {}
Intervals = L0_1
L0_1 = {}
RegisterNetworkFlow = L0_1
L0_1 = require
L1_1 = "glm"
L0_1 = L0_1(L1_1)
glm = L0_1
MapsLoaded = false
L0_1 = {}
L0_1.sprunk = true
L0_1.sludgie = true
L0_1.ecola_light = true
L0_1.ecola = true
L0_1.coffee = true
L0_1.water = true
L0_1.fries = true
L0_1.pizza_ham = true
L0_1.chips = true
L0_1.donut = true
L0_1.cigarrete = true
PRISON_ITEMS = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = "data/%s.lua"
  L2_2 = L1_2
  L1_2 = L1_2.format
  L3_2 = A0_2
  L1_2 = L1_2(L2_2, L3_2)
  L2_2 = LoadResourceFile
  L3_2 = "rcore_prison"
  L4_2 = L1_2
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = pcall
  L4_2 = load
  L5_2 = L2_2
  L6_2 = "@@rcore_prison/%s"
  L7_2 = L6_2
  L6_2 = L6_2.format
  L8_2 = L1_2
  L6_2, L7_2, L8_2 = L6_2(L7_2, L8_2)
  L3_2, L4_2 = L3_2(L4_2, L5_2, L6_2, L7_2, L8_2)
  if not L3_2 then
    L5_2 = dbg
    L5_2 = L5_2.critical
    L6_2 = "Failed to load language file ["
    L7_2 = A0_2
    L8_2 = "] (%s)"
    L6_2 = L6_2 .. L7_2 .. L8_2
    L7_2 = L4_2
    L5_2(L6_2, L7_2)
  end
  L5_2 = L4_2
  return L5_2()
end
fetchData = L0_1
function L0_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = xpcall
  function L3_2()
    local L0_3, L1_3
    L0_3 = exports
    L1_3 = A0_2
    L0_3 = L0_3[L1_3]
    L1_3 = A1_2
    L0_3 = L0_3[L1_3]
  end
  L4_2 = debug
  L4_2 = L4_2.traceback
  L2_2, L3_2 = L2_2(L3_2, L4_2)
  return L2_2
end
doesExportExistInResource = L0_1
function L0_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2
  L3_2 = GetResourceState
  L4_2 = A1_2
  L3_2 = L3_2(L4_2)
  if "started" == L3_2 then
    L4_2 = "%s.lua"
    L5_2 = L4_2
    L4_2 = L4_2.format
    L6_2 = A0_2
    L4_2 = L4_2(L5_2, L6_2)
    L5_2 = LoadResourceFile
    L6_2 = A1_2
    L7_2 = L4_2
    L5_2 = L5_2(L6_2, L7_2)
    if not L5_2 then
      L6_2 = dbg
      L6_2 = L6_2.critical
      L7_2 = string
      L7_2 = L7_2.format
      L8_2 = "Error with loading file %s (script:%s)!"
      L9_2 = L4_2
      L10_2 = A1_2
      L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2 = L7_2(L8_2, L9_2, L10_2)
      L6_2(L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2)
      return
    end
    if not A2_2 then
      return L5_2
    end
    L6_2 = nil ~= A2_2 and L6_2
    L7_2 = "return "
    L8_2 = L6_2
    L7_2 = L7_2 .. L8_2
    L8_2 = pcall
    L9_2 = load
    L10_2 = L5_2
    L11_2 = L7_2
    L10_2 = L10_2 .. L11_2
    L11_2 = L4_2
    L12_2 = "t"
    L8_2, L9_2 = L8_2(L9_2, L10_2, L11_2, L12_2)
    if not L8_2 then
      L10_2 = dbg
      L10_2 = L10_2.critical
      L11_2 = string
      L11_2 = L11_2.format
      L12_2 = "Cannot load datafile %s with error %s"
      L13_2 = L4_2
      L14_2 = L9_2
      L11_2, L12_2, L13_2, L14_2 = L11_2(L12_2, L13_2, L14_2)
      L10_2(L11_2, L12_2, L13_2, L14_2)
    end
    L10_2 = L9_2
    return L10_2()
  else
    L4_2 = nil
    return L4_2
  end
end
LoadScriptData = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L1_2 = GetCurrentResourceName
  L1_2 = L1_2()
  L2_2 = "data/presets/%s.lua"
  L3_2 = L2_2
  L2_2 = L2_2.format
  L4_2 = A0_2
  L2_2 = L2_2(L3_2, L4_2)
  L3_2 = LoadResourceFile
  L4_2 = L1_2
  L5_2 = L2_2
  L3_2 = L3_2(L4_2, L5_2)
  L4_2 = "@@%s/%s"
  L5_2 = L4_2
  L4_2 = L4_2.format
  L6_2 = L1_2
  L7_2 = L2_2
  L4_2 = L4_2(L5_2, L6_2, L7_2)
  if not L3_2 then
    L5_2 = dbg
    L5_2 = L5_2.critical
    L6_2 = "Cannot get any data from %s file - LoadResourceFile"
    L7_2 = L2_2
    L5_2(L6_2, L7_2)
    L5_2 = {}
    return L5_2
  end
  L5_2 = pcall
  L6_2 = load
  L7_2 = L3_2
  L8_2 = L4_2
  L5_2, L6_2 = L5_2(L6_2, L7_2, L8_2)
  if not L5_2 then
    L7_2 = dbg
    L7_2 = L7_2.critical
    L8_2 = "Failed to fetch interior data for map %s with load function! Err: %s"
    L9_2 = A0_2 or L9_2
    if not A0_2 then
      L9_2 = "NIL"
    end
    L10_2 = L6_2
    return L7_2(L8_2, L9_2, L10_2)
  end
  L7_2 = L6_2
  return L7_2()
end
getInteriorData = L0_1
L0_1 = CreateThread
function L1_1()
  local L0_2, L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2
  L0_2 = Wait
  L1_2 = 0
  L0_2(L1_2)
  L0_2 = {}
  L1_2 = Config
  L1_2 = L1_2.Map
  L0_2.name = L1_2
  L1_2 = {}
  L0_2.data = L1_2
  L1_2 = string
  L1_2 = L1_2.find
  L2_2 = Config
  L2_2 = L2_2.Map
  L3_2 = "MAPLIST"
  L1_2 = L1_2(L2_2, L3_2)
  if L1_2 then
    L1_2 = string
    L1_2 = L1_2.match
    L2_2 = Config
    L2_2 = L2_2.Map
    L3_2 = "_(.+)"
    L1_2 = L1_2(L2_2, L3_2)
    L2_2 = MapsList
    L2_2 = L2_2[L1_2]
    if L2_2 then
      L3_2 = next
      L4_2 = L2_2
      L3_2 = L3_2(L4_2)
      if L3_2 then
        L3_2 = pairs
        L4_2 = L2_2
        L3_2, L4_2, L5_2, L6_2 = L3_2(L4_2)
        for L7_2, L8_2 in L3_2, L4_2, L5_2, L6_2 do
          L9_2 = isResourcePresentProvideless
          L10_2 = L8_2
          L9_2 = L9_2(L10_2)
          if L9_2 then
            L9_2 = NONE_RESOURCE
            if L8_2 ~= L9_2 then
              L10_2 = L1_2
              L9_2 = L1_2.lower
              L9_2 = L9_2(L10_2)
              L0_2.name = L9_2
              break
            end
          end
        end
      end
    end
  end
  L1_2 = Config
  L2_2 = L0_2.name
  L1_2.Map = L2_2
  L1_2 = dbg
  L1_2 = L1_2.debug
  L2_2 = "Loading map data for map named: %s"
  L3_2 = L0_2.name
  L1_2(L2_2, L3_2)
  L1_2 = L0_2.name
  if "prompt" == L1_2 then
    L0_2.name = "prompt-prison"
  end
  L1_2 = getInteriorData
  L2_2 = L0_2.name
  L1_2 = L1_2(L2_2)
  L0_2.data = L1_2
  L1_2 = L0_2.name
  if not L1_2 then
    L1_2 = dbg
    L1_2 = L1_2.critical
    L2_2 = "Failed to load prison preset file, see config for supported maps or add own one."
    return L1_2(L2_2)
  else
    L1_2 = SH
    L2_2 = SH
    L3_2 = L0_2.name
    L4_2 = L0_2.data
    L2_2.data = L4_2
    L1_2.preset = L3_2
  end
  L1_2 = TriggerEvent
  L2_2 = "rcore_prison:shared:internal:MapLoaded"
  L1_2(L2_2)
end
L2_1 = "sh-init code name: Phoenix"
L0_1(L1_1, L2_1)
L0_1 = isResourceLoaded
L1_1 = "ox_lib"
L0_1 = L0_1(L1_1)
if L0_1 then
  L0_1 = "%s.lua"
  L1_1 = L0_1
  L0_1 = L0_1.format
  L2_1 = "init"
  L0_1 = L0_1(L1_1, L2_1)
  L1_1 = LoadResourceFile
  L2_1 = "ox_lib"
  L3_1 = L0_1
  L1_1 = L1_1(L2_1, L3_1)
  L2_1 = assert
  L3_1 = load
  L4_1 = L1_1
  L5_1 = "@@ox_lib/%s"
  L6_1 = L5_1
  L5_1 = L5_1.format
  L7_1 = L0_1
  L5_1, L6_1, L7_1, L8_1 = L5_1(L6_1, L7_1)
  L3_1, L4_1, L5_1, L6_1, L7_1, L8_1 = L3_1(L4_1, L5_1, L6_1, L7_1, L8_1)
  L2_1 = L2_1(L3_1, L4_1, L5_1, L6_1, L7_1, L8_1)
  L3_1 = L2_1
  L3_1()
end
L0_1 = isResourceLoaded
L1_1 = "ND_Core"
L0_1 = L0_1(L1_1)
if L0_1 then
  L0_1 = "%s.lua"
  L1_1 = L0_1
  L0_1 = L0_1.format
  L2_1 = "init"
  L0_1 = L0_1(L1_1, L2_1)
  L1_1 = LoadResourceFile
  L2_1 = "ND_Core"
  L3_1 = L0_1
  L1_1 = L1_1(L2_1, L3_1)
  L2_1 = assert
  L3_1 = load
  L4_1 = L1_1
  L5_1 = "@@ND_Core/%s"
  L6_1 = L5_1
  L5_1 = L5_1.format
  L7_1 = L0_1
  L5_1, L6_1, L7_1, L8_1 = L5_1(L6_1, L7_1)
  L3_1, L4_1, L5_1, L6_1, L7_1, L8_1 = L3_1(L4_1, L5_1, L6_1, L7_1, L8_1)
  L2_1 = L2_1(L3_1, L4_1, L5_1, L6_1, L7_1, L8_1)
  L3_1 = L2_1
  L3_1()
end
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2
  L1_2 = GetNumResources
  L1_2 = L1_2()
  L2_2 = 0
  L3_2 = L1_2 - 1
  L4_2 = 1
  for L5_2 = L2_2, L3_2, L4_2 do
    L6_2 = GetResourceByFindIndex
    L7_2 = L5_2
    L6_2 = L6_2(L7_2)
    if L6_2 == A0_2 then
      L7_2 = GetResourceState
      L8_2 = L6_2
      L7_2 = L7_2(L8_2)
      if "started" == L7_2 then
        L7_2 = true
        return L7_2
      end
    end
  end
  L2_2 = false
  return L2_2
end
isResourcePresentProvideless = L0_1
function L0_1()
  local L0_2, L1_2, L2_2
  L0_2 = IsDuplicityVersion
  L0_2 = L0_2()
  if L0_2 then
    L0_2 = Framework
    L0_2 = L0_2.getOfficers
    L0_2 = L0_2()
    if L0_2 then
      L1_2 = next
      L2_2 = L0_2
      L1_2 = L1_2(L2_2)
      if L1_2 then
        L1_2 = #L0_2
        return L1_2
    end
    else
      L1_2 = 0
      return L1_2
    end
  else
    L0_2 = 0
    return L0_2
  end
end
getPoliceCount = L0_1
function L0_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2
  L1_2 = GetNumResources
  L1_2 = L1_2()
  L2_2 = 0
  L3_2 = L1_2 - 1
  L4_2 = 1
  for L5_2 = L2_2, L3_2, L4_2 do
    L6_2 = GetResourceByFindIndex
    L7_2 = L5_2
    L6_2 = L6_2(L7_2)
    L7_2 = string
    L7_2 = L7_2.match
    L8_2 = L6_2
    L9_2 = A0_2
    L7_2 = L7_2(L8_2, L9_2)
    if L7_2 then
      L8_2 = isResourcePresentProvideless
      L9_2 = L6_2
      L8_2 = L8_2(L9_2)
      if L8_2 then
        return L6_2
      end
    end
  end
end
FindTargetResource = L0_1
L0_1 = RegisterCommand
L1_1 = "rcore_prison_debug"
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  L3_2 = {}
  L4_2 = Config
  L4_2 = L4_2.Framework
  L3_2.framework = L4_2
  L4_2 = Config
  L4_2 = L4_2.Notifies
  L3_2.notify = L4_2
  L4_2 = Config
  L4_2 = L4_2.Inventories
  L3_2.inventory = L4_2
  L4_2 = Config
  L4_2 = L4_2.Cloth
  L3_2.clothing = L4_2
  L4_2 = Config
  L4_2 = L4_2.Dispatch
  L3_2.dispatch = L4_2
  L4_2 = Config
  L4_2 = L4_2.Interactions
  if "none" == L4_2 then
    L4_2 = "GTA-DISTANCE"
    if L4_2 then
      goto lbl_27
    end
  end
  L4_2 = Config
  L4_2 = L4_2.Interactions
  ::lbl_27::
  L3_2.interact = L4_2
  L4_2 = Config
  L4_2 = L4_2.Menus
  L3_2.menu = L4_2
  L4_2 = Config
  L4_2 = L4_2.Phone
  L3_2.phone = L4_2
  L4_2 = Config
  L4_2 = L4_2.TextUI
  L3_2.textUI = L4_2
  L4_2 = Config
  L4_2 = L4_2.Map
  L3_2.map = L4_2
  L4_2 = GetResourceMetadata
  L5_2 = GetCurrentResourceName
  L5_2 = L5_2()
  L6_2 = "version"
  L7_2 = 0
  L4_2 = L4_2(L5_2, L6_2, L7_2)
  L3_2.prisonVersion = L4_2
  L4_2 = getPoliceCount
  L4_2 = L4_2()
  L3_2.policeCount = L4_2
  if L3_2 then
    L4_2 = type
    L5_2 = L3_2
    L4_2 = L4_2(L5_2)
    if "table" == L4_2 then
      L4_2 = next
      L5_2 = L3_2
      L4_2 = L4_2(L5_2)
      if L4_2 then
        L4_2 = tprint
        L5_2 = L3_2
        L4_2(L5_2)
    end
  end
  else
    L4_2 = dbg
    L4_2 = L4_2.debug
    L5_2 = "Debug prison: failed to find any data in the list to debug enviroment!"
    L4_2(L5_2)
  end
end
L3_1 = false
L0_1(L1_1, L2_1, L3_1)
L0_1 = RegisterCommand
L1_1 = "debugNetwork"
function L2_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2
  if 0 == A0_2 then
    L3_2 = RegisterNetworkFlow
    if L3_2 then
      L3_2 = next
      L4_2 = RegisterNetworkFlow
      L3_2 = L3_2(L4_2)
      if L3_2 then
        L3_2 = tprint
        L4_2 = RegisterNetworkFlow
        L3_2(L4_2)
    end
    else
      L3_2 = dbg
      L3_2 = L3_2.debug
      L4_2 = "The network event flow is empty."
      L3_2(L4_2)
    end
  end
end
L3_1 = false
L0_1(L1_1, L2_1, L3_1)
L0_1 = IsDuplicityVersion
L0_1 = L0_1()
if L0_1 then
  L0_1 = {}
  L1_1 = {}
  L1_1.jail = "esx-qalle-jail:jailPlayer"
  L1_1.unjail = "esx-qalle-jail:unJailPlayer"
  L0_1.qalle = L1_1
  L1_1 = {}
  L1_1.jail = "police:server:JailPlayer"
  L1_1.coms = "qb-communityservice:server:StartCommunityService"
  L0_1.qbcore = L1_1
  L1_1 = {}
  L1_1.jail = "qs-dispatch:server:addPenalListToPlayer"
  L0_1.quasar = L1_1
  EMULATOR_EVENTS_BY_RESOURCE_NAME = L0_1
  EnableGuidebook = false
  function L0_1(A0_2, A1_2, A2_2, A3_2)
    local L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2
    if not A0_2 then
      return
    end
    if not A1_2 then
      return
    end
    if not A2_2 then
      return
    end
    if not A3_2 then
      return
    end
    L4_2 = "UNK_EVENT_NAME"
    L5_2 = EMULATOR_EVENTS_BY_RESOURCE_NAME
    L5_2 = L5_2[A1_2]
    if L5_2 and A3_2 then
      L5_2 = EMULATOR_EVENTS_BY_RESOURCE_NAME
      L5_2 = L5_2[A1_2]
      L5_2 = L5_2[A3_2]
      if L5_2 then
        L5_2 = EMULATOR_EVENTS_BY_RESOURCE_NAME
        L5_2 = L5_2[A1_2]
        L4_2 = L5_2[A3_2]
      end
    end
    L5_2 = dbg
    L5_2 = L5_2.debugAPI
    L6_2 = "[%s] was invoked by user [%s | %s] - Loading %s %s event named: %s"
    L7_2 = A0_2
    L8_2 = A2_2
    if A2_2 then
      L9_2 = GetPlayerName
      L10_2 = A2_2
      L9_2 = L9_2(L10_2)
      if L9_2 then
        goto lbl_41
      end
    end
    L9_2 = "UNK-PLAYER"
    ::lbl_41::
    L10_2 = A3_2
    L11_2 = A1_2 or L11_2
    if not A1_2 then
      L11_2 = "UNK_RESOURCE"
    end
    L12_2 = L4_2
    L5_2(L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2)
  end
  provideDebugEmulator = L0_1
end
function L0_1(A0_2, A1_2, A2_2)
  local L3_2, L4_2, L5_2, L6_2, L7_2
  L3_2 = dbg
  if not L3_2 then
    L3_2 = rdebug
    L3_2 = L3_2()
    dbg = L3_2
  end
  L3_2 = GetCurrentResourceName
  L3_2 = L3_2()
  if A1_2 ~= L3_2 then
    L3_2 = dbg
    L3_2 = L3_2.debugAPI
    L4_2 = "Providing export emulation for export named: %s | resource: %s"
    L5_2 = A0_2
    L6_2 = A1_2
    L3_2(L4_2, L5_2, L6_2)
  end
  L3_2 = AddEventHandler
  L4_2 = "__cfx_export_%s_%s"
  L5_2 = L4_2
  L4_2 = L4_2.format
  L6_2 = A1_2
  L7_2 = A0_2
  L4_2 = L4_2(L5_2, L6_2, L7_2)
  function L5_2(A0_3)
    local L1_3, L2_3, L3_3, L4_3
    L1_3 = dbg
    L1_3 = L1_3.debugAPI
    L2_3 = "Emulator was called from %s | emulate-resource: %s"
    L3_3 = GetInvokingResource
    L3_3 = L3_3()
    L4_3 = A1_2
    L1_3(L2_3, L3_3, L4_3)
    L1_3 = A0_3
    L2_3 = A2_2
    L1_3(L2_3)
  end
  L3_2(L4_2, L5_2)
end
provideExport = L0_1
L0_1 = Config
L0_1 = L0_1.ErrorDebug
if not L0_1 then
  L0_1 = false
end
L1_1 = {}
function L2_1(A0_2)
  local L1_2, L2_2, L3_2
  L1_2 = L0_1
  if L1_2 then
    L1_2 = L1_1
    L2_2 = {}
    L2_2.stepCount = 0
    L3_2 = {}
    L2_2.stepData = L3_2
    L1_2[A0_2] = L2_2
  end
end
StartDebugSession = L2_1
function L2_1(A0_2)
  local L1_2, L2_2
  L1_2 = DisplayCurrentRecordSteps
  L2_2 = A0_2
  L1_2(L2_2)
  L1_2 = L0_1
  if L1_2 then
    L1_2 = L1_1
    L1_2[A0_2] = nil
  end
end
DestoryDebugSession = L2_1
function L2_1(A0_2, A1_2)
  local L2_2, L3_2, L4_2
  L2_2 = L0_1
  if L2_2 then
    L2_2 = L1_1
    L2_2 = L2_2[A0_2]
    if L2_2 then
      L3_2 = L2_2.stepCount
      L3_2 = L3_2 + 1
      L2_2.stepCount = L3_2
      L3_2 = L2_2.stepData
      L4_2 = L2_2.stepCount
      L3_2[L4_2] = A1_2
    end
  end
end
DebugRecordStep = L2_1
function L2_1(A0_2)
  local L1_2, L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2
  L1_2 = L0_1
  if L1_2 then
    L1_2 = L1_1
    L1_2 = L1_2[A0_2]
    if L1_2 then
      L2_2 = ipairs
      L3_2 = L1_2.stepData
      L2_2, L3_2, L4_2, L5_2 = L2_2(L3_2)
      for L6_2, L7_2 in L2_2, L3_2, L4_2, L5_2 do
        L8_2 = print
        L9_2 = "^0Step name: ^1"
        L10_2 = tostring
        L11_2 = L7_2
        L10_2 = L10_2(L11_2)
        L9_2 = L9_2 .. L10_2
        L8_2(L9_2)
      end
      L2_2 = print
      L3_2 = "^5=====^0"
      L2_2(L3_2)
      L2_2 = print
      L3_2 = "^0Last step before the error: ^1"
      L4_2 = tostring
      L5_2 = L1_2.stepData
      L6_2 = L1_2.stepData
      L6_2 = #L6_2
      L5_2 = L5_2[L6_2]
      L4_2 = L4_2(L5_2)
      L3_2 = L3_2 .. L4_2
      L2_2(L3_2)
    end
  end
end
DisplayCurrentRecordSteps = L2_1
if L0_1 then
  L2_1 = AddEventHandler
  L3_1 = RegisterNetEvent
  L4_1 = CreateThread
  L5_1 = RegisterCommand
  L6_1 = RegisterNUICallback
  function L7_1(A0_2, A1_2)
    local L2_2, L3_2, L4_2, L5_2, L6_2, L7_2, L8_2, L9_2, L10_2, L11_2, L12_2, L13_2, L14_2, L15_2, L16_2, L17_2, L18_2, L19_2, L20_2, L21_2
    L2_2 = {}
    L3_2 = {}
    L4_2 = {}
    L5_2 = 1
    L6_2 = "{\n"
    while true do
      L7_2 = 0
      L8_2 = pairs
      L9_2 = A0_2
      L8_2, L9_2, L10_2, L11_2 = L8_2(L9_2)
      for L12_2, L13_2 in L8_2, L9_2, L10_2, L11_2 do
        L7_2 = L7_2 + 1
      end
      L8_2 = 1
      L9_2 = pairs
      L10_2 = A0_2
      L9_2, L10_2, L11_2, L12_2 = L9_2(L10_2)
      for L13_2, L14_2 in L9_2, L10_2, L11_2, L12_2 do
        L15_2 = L2_2[A0_2]
        if nil ~= L15_2 then
          L15_2 = L2_2[A0_2]
          if not (L8_2 >= L15_2) then
            goto lbl_176
          end
        end
        L15_2 = string
        L15_2 = L15_2.find
        L16_2 = L6_2
        L17_2 = "}"
        L19_2 = L6_2
        L18_2 = L6_2.len
        L18_2, L19_2, L20_2, L21_2 = L18_2(L19_2)
        L15_2 = L15_2(L16_2, L17_2, L18_2, L19_2, L20_2, L21_2)
        if L15_2 then
          L15_2 = L6_2
          L16_2 = ",\n"
          L15_2 = L15_2 .. L16_2
          L6_2 = L15_2
        else
          L15_2 = string
          L15_2 = L15_2.find
          L16_2 = L6_2
          L17_2 = "\n"
          L19_2 = L6_2
          L18_2 = L6_2.len
          L18_2, L19_2, L20_2, L21_2 = L18_2(L19_2)
          L15_2 = L15_2(L16_2, L17_2, L18_2, L19_2, L20_2, L21_2)
          if not L15_2 then
            L15_2 = L6_2
            L16_2 = "\n"
            L15_2 = L15_2 .. L16_2
            L6_2 = L15_2
          end
        end
        L15_2 = table
        L15_2 = L15_2.insert
        L16_2 = L4_2
        L17_2 = L6_2
        L15_2(L16_2, L17_2)
        L6_2 = ""
        L15_2 = nil
        L16_2 = type
        L17_2 = L13_2
        L16_2 = L16_2(L17_2)
        if "number" ~= L16_2 then
          L16_2 = type
          L17_2 = L13_2
          L16_2 = L16_2(L17_2)
          if "boolean" ~= L16_2 then
            goto lbl_82
          end
        end
        L16_2 = "["
        L17_2 = tostring
        L18_2 = L13_2
        L17_2 = L17_2(L18_2)
        L18_2 = "]"
        L16_2 = L16_2 .. L17_2 .. L18_2
        L15_2 = L16_2
        goto lbl_89
        ::lbl_82::
        L16_2 = "['"
        L17_2 = tostring
        L18_2 = L13_2
        L17_2 = L17_2(L18_2)
        L18_2 = "']"
        L16_2 = L16_2 .. L17_2 .. L18_2
        L15_2 = L16_2
        ::lbl_89::
        L16_2 = type
        L17_2 = L14_2
        L16_2 = L16_2(L17_2)
        if "number" ~= L16_2 then
          L16_2 = type
          L17_2 = L14_2
          L16_2 = L16_2(L17_2)
          if "boolean" ~= L16_2 then
            goto lbl_113
          end
        end
        L16_2 = L6_2
        L17_2 = string
        L17_2 = L17_2.rep
        L18_2 = "\t"
        L19_2 = L5_2
        L17_2 = L17_2(L18_2, L19_2)
        L18_2 = L15_2
        L19_2 = " = "
        L20_2 = tostring
        L21_2 = L14_2
        L20_2 = L20_2(L21_2)
        L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2 .. L20_2
        L6_2 = L16_2
        goto lbl_157
        ::lbl_113::
        L16_2 = type
        L17_2 = L14_2
        L16_2 = L16_2(L17_2)
        if "table" == L16_2 then
          L16_2 = L6_2
          L17_2 = string
          L17_2 = L17_2.rep
          L18_2 = "\t"
          L19_2 = L5_2
          L17_2 = L17_2(L18_2, L19_2)
          L18_2 = L15_2
          L19_2 = " = {\n"
          L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2
          L6_2 = L16_2
          L16_2 = table
          L16_2 = L16_2.insert
          L17_2 = L3_2
          L18_2 = A0_2
          L16_2(L17_2, L18_2)
          L16_2 = table
          L16_2 = L16_2.insert
          L17_2 = L3_2
          L18_2 = L14_2
          L16_2(L17_2, L18_2)
          L16_2 = L8_2 + 1
          L2_2[A0_2] = L16_2
          break
        else
          L16_2 = L6_2
          L17_2 = string
          L17_2 = L17_2.rep
          L18_2 = "\t"
          L19_2 = L5_2
          L17_2 = L17_2(L18_2, L19_2)
          L18_2 = L15_2
          L19_2 = " = '"
          L20_2 = tostring
          L21_2 = L14_2
          L20_2 = L20_2(L21_2)
          L21_2 = "'"
          L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2 .. L20_2 .. L21_2
          L6_2 = L16_2
        end
        ::lbl_157::
        if L8_2 == L7_2 then
          L16_2 = L6_2
          L17_2 = "\n"
          L18_2 = string
          L18_2 = L18_2.rep
          L19_2 = "\t"
          L20_2 = L5_2 - 1
          L18_2 = L18_2(L19_2, L20_2)
          L19_2 = "}"
          L16_2 = L16_2 .. L17_2 .. L18_2 .. L19_2
          L6_2 = L16_2
        else
          L16_2 = L6_2
          L17_2 = ","
          L16_2 = L16_2 .. L17_2
          L6_2 = L16_2
          goto lbl_189
          ::lbl_176::
          if L8_2 == L7_2 then
            L15_2 = L6_2
            L16_2 = "\n"
            L17_2 = string
            L17_2 = L17_2.rep
            L18_2 = "\t"
            L19_2 = L5_2 - 1
            L17_2 = L17_2(L18_2, L19_2)
            L18_2 = "}"
            L15_2 = L15_2 .. L16_2 .. L17_2 .. L18_2
            L6_2 = L15_2
          end
        end
        ::lbl_189::
        L8_2 = L8_2 + 1
      end
      if 0 == L7_2 then
        L9_2 = L6_2
        L10_2 = "\n"
        L11_2 = string
        L11_2 = L11_2.rep
        L12_2 = "\t"
        L13_2 = L5_2 - 1
        L11_2 = L11_2(L12_2, L13_2)
        L12_2 = "}"
        L9_2 = L9_2 .. L10_2 .. L11_2 .. L12_2
        L6_2 = L9_2
      end
      L9_2 = #L3_2
      if not (L9_2 > 0) then
        break
      end
      L9_2 = #L3_2
      A0_2 = L3_2[L9_2]
      L9_2 = #L3_2
      L3_2[L9_2] = nil
      L9_2 = L2_2[A0_2]
      if nil == L9_2 then
        L9_2 = L5_2 + 1
        if L9_2 then
          goto lbl_225
          L5_2 = L9_2 or L5_2
        end
      end
      L5_2 = L5_2 - 1
      goto lbl_225
      do break end
      ::lbl_225::
    end
    L7_2 = table
    L7_2 = L7_2.insert
    L8_2 = L4_2
    L9_2 = L6_2
    L7_2(L8_2, L9_2)
    L7_2 = table
    L7_2 = L7_2.concat
    L8_2 = L4_2
    L7_2 = L7_2(L8_2)
    L6_2 = L7_2
    if not A1_2 then
      L7_2 = print
      L8_2 = L6_2
      L7_2(L8_2)
    end
    return L6_2
  end
  function L8_1(A0_2, A1_2)
    local L2_2, L3_2, L4_2
    L2_2 = L5_1
    L3_2 = A0_2
    function L4_2(A0_3, A1_3, A2_3)
      local L3_3, L4_3, L5_3, L6_3, L7_3, L8_3, L9_3, L10_3, L11_3, L12_3, L13_3, L14_3, L15_3
      L3_3 = xpcall
      function L4_3()
        local L0_4, L1_4, L2_4, L3_4
        L0_4 = A1_2
        L1_4 = A0_3
        L2_4 = A1_3
        L3_4 = A2_3
        L0_4(L1_4, L2_4, L3_4)
      end
      L5_3 = debug
      L5_3 = L5_3.traceback
      L3_3, L4_3 = L3_3(L4_3, L5_3)
      if not L3_3 then
        L5_3 = {}
        L5_3[1] = A0_3
        L5_3[2] = A1_3
        L5_3[3] = A2_3
        L6_3 = print
        L7_3 = "^5=========================^0"
        L6_3(L7_3)
        L6_3 = print
        L7_3 = "^2Error in: ^1RegisterCommand^0"
        L6_3(L7_3)
        L6_3 = print
        L7_3 = "^2Event name: ^1"
        L8_3 = A0_2
        L9_3 = "^0"
        L7_3 = L7_3 .. L8_3 .. L9_3
        L6_3(L7_3)
        L6_3 = print
        L7_3 = "^5=========================^0"
        L6_3(L7_3)
        L6_3 = DisplayCurrentRecordSteps
        L7_3 = A0_2
        L6_3(L7_3)
        L6_3 = print
        L7_3 = "^5=========================^0"
        L6_3(L7_3)
        L6_3 = pairs
        L7_3 = L5_3
        L6_3, L7_3, L8_3, L9_3 = L6_3(L7_3)
        for L10_3, L11_3 in L6_3, L7_3, L8_3, L9_3 do
          L12_3 = print
          L13_3 = "^0Argument key: ^1"
          L14_3 = L10_3
          L13_3 = L13_3 .. L14_3
          L12_3(L13_3)
          L12_3 = print
          L13_3 = "^0Argument value type: ^1"
          L14_3 = type
          L15_3 = L11_3
          L14_3 = L14_3(L15_3)
          L13_3 = L13_3 .. L14_3
          L12_3(L13_3)
          L12_3 = print
          L13_3 = " "
          L12_3(L13_3)
          L12_3 = type
          L13_3 = L11_3
          L12_3 = L12_3(L13_3)
          if "table" == L12_3 then
            L12_3 = print
            L13_3 = "^0Argument value: ^1"
            L14_3 = tostring
            L15_3 = L11_3
            L14_3 = L14_3(L15_3)
            L13_3 = L13_3 .. L14_3
            L12_3(L13_3)
            L12_3 = L7_1
            L13_3 = L11_3
            L12_3(L13_3)
          else
            L12_3 = print
            L13_3 = "^0Argument value: ^1"
            L14_3 = tostring
            L15_3 = L11_3
            L14_3 = L14_3(L15_3)
            L13_3 = L13_3 .. L14_3
            L12_3(L13_3)
          end
          L12_3 = print
          L13_3 = "^5=====^0"
          L12_3(L13_3)
        end
        L6_3 = print
        L7_3 = "^5=========================^0"
        L6_3(L7_3)
        L6_3 = print
        L7_3 = L4_3
        L6_3(L7_3)
        L6_3 = print
        L7_3 = "^5=========================^0"
        L6_3(L7_3)
      end
    end
    L2_2(L3_2, L4_2)
  end
  RegisterCommand = L8_1
  function L8_1(A0_2, A1_2)
    local L2_2, L3_2, L4_2
    if not A1_2 then
      L2_2 = L3_1
      L3_2 = A0_2
      L2_2(L3_2)
      return
    end
    L2_2 = L3_1
    L3_2 = A0_2
    function L4_2(A0_3, A1_3, A2_3, A3_3, A4_3, A5_3, A6_3, A7_3, A8_3, A9_3, A10_3, A11_3)
      local L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3, L20_3, L21_3, L22_3, L23_3, L24_3
      L12_3 = xpcall
      function L13_3()
        local L0_4, L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4
        L0_4 = A1_2
        L1_4 = A0_3
        L2_4 = A1_3
        L3_4 = A2_3
        L4_4 = A3_3
        L5_4 = A4_3
        L6_4 = A5_3
        L7_4 = A6_3
        L8_4 = A7_3
        L9_4 = A8_3
        L10_4 = A9_3
        L11_4 = A10_3
        L12_4 = A11_3
        L0_4(L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4)
      end
      L14_3 = debug
      L14_3 = L14_3.traceback
      L12_3, L13_3 = L12_3(L13_3, L14_3)
      if not L12_3 then
        L14_3 = {}
        L14_3[1] = A0_3
        L14_3[2] = A1_3
        L14_3[3] = A2_3
        L14_3[4] = A3_3
        L14_3[5] = A4_3
        L14_3[6] = A5_3
        L14_3[7] = A6_3
        L14_3[8] = A7_3
        L14_3[9] = A8_3
        L14_3[10] = A9_3
        L14_3[11] = A10_3
        L14_3[12] = A11_3
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^2Error in: ^1RegisterNetEvent^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^2Event name: ^1"
        L17_3 = A0_2
        L18_3 = "^0"
        L16_3 = L16_3 .. L17_3 .. L18_3
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = DisplayCurrentRecordSteps
        L16_3 = A0_2
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = pairs
        L16_3 = L14_3
        L15_3, L16_3, L17_3, L18_3 = L15_3(L16_3)
        for L19_3, L20_3 in L15_3, L16_3, L17_3, L18_3 do
          L21_3 = print
          L22_3 = "^0Argument key: ^1"
          L23_3 = L19_3
          L22_3 = L22_3 .. L23_3
          L21_3(L22_3)
          L21_3 = print
          L22_3 = "^0Argument value type: ^1"
          L23_3 = type
          L24_3 = L20_3
          L23_3 = L23_3(L24_3)
          L22_3 = L22_3 .. L23_3
          L21_3(L22_3)
          L21_3 = print
          L22_3 = " "
          L21_3(L22_3)
          L21_3 = type
          L22_3 = L20_3
          L21_3 = L21_3(L22_3)
          if "table" == L21_3 then
            L21_3 = print
            L22_3 = "^0Argument value: ^1"
            L23_3 = tostring
            L24_3 = L20_3
            L23_3 = L23_3(L24_3)
            L22_3 = L22_3 .. L23_3
            L21_3(L22_3)
            L21_3 = L7_1
            L22_3 = L20_3
            L21_3(L22_3)
          else
            L21_3 = print
            L22_3 = "^0Argument value: ^1"
            L23_3 = tostring
            L24_3 = L20_3
            L23_3 = L23_3(L24_3)
            L22_3 = L22_3 .. L23_3
            L21_3(L22_3)
          end
          L21_3 = print
          L22_3 = "^5=====^0"
          L21_3(L22_3)
        end
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = L13_3
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = ""
        L16_3 = 1
        L17_3 = 12
        L18_3 = 1
        for L19_3 = L16_3, L17_3, L18_3 do
          L20_3 = L14_3[L19_3]
          L21_3 = type
          L22_3 = L20_3
          L21_3 = L21_3(L22_3)
          if "table" == L21_3 then
            L21_3 = L15_3
            L22_3 = L7_1
            L23_3 = L20_3
            L24_3 = true
            L22_3 = L22_3(L23_3, L24_3)
            L23_3 = ","
            L21_3 = L21_3 .. L22_3 .. L23_3
            L15_3 = L21_3
          else
            L21_3 = type
            L22_3 = L20_3
            L21_3 = L21_3(L22_3)
            if "string" == L21_3 then
              L21_3 = L15_3
              L22_3 = "'"
              L23_3 = L20_3
              L24_3 = "',"
              L21_3 = L21_3 .. L22_3 .. L23_3 .. L24_3
              L15_3 = L21_3
            else
              L21_3 = L15_3
              L22_3 = tostring
              L23_3 = L20_3
              L22_3 = L22_3(L23_3)
              L23_3 = ","
              L21_3 = L21_3 .. L22_3 .. L23_3
              L15_3 = L21_3
            end
          end
        end
        L16_3 = print
        L17_3 = "^0Replication trigger event:"
        L16_3(L17_3)
        L16_3 = print
        L17_3 = "^1TriggerEvent('"
        L18_3 = A0_2
        L19_3 = "', "
        L21_3 = L15_3
        L20_3 = L15_3.gsub
        L22_3 = "\n"
        L23_3 = ""
        L20_3 = L20_3(L21_3, L22_3, L23_3)
        L21_3 = L20_3
        L20_3 = L20_3.sub
        L22_3 = 1
        L23_3 = -2
        L20_3 = L20_3(L21_3, L22_3, L23_3)
        L21_3 = ")"
        L17_3 = L17_3 .. L18_3 .. L19_3 .. L20_3 .. L21_3
        L16_3(L17_3)
        L16_3 = print
        L17_3 = "^5=========================^0"
        L16_3(L17_3)
      end
    end
    L2_2(L3_2, L4_2)
  end
  RegisterNetEvent = L8_1
  function L8_1(A0_2, A1_2)
    local L2_2, L3_2, L4_2
    L2_2 = L6_1
    L3_2 = A0_2
    function L4_2(A0_3, A1_3, A2_3, A3_3, A4_3, A5_3, A6_3, A7_3, A8_3, A9_3, A10_3, A11_3)
      local L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3, L20_3, L21_3, L22_3, L23_3, L24_3
      L12_3 = xpcall
      function L13_3()
        local L0_4, L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4
        L0_4 = A1_2
        L1_4 = A0_3
        L2_4 = A1_3
        L3_4 = A2_3
        L4_4 = A3_3
        L5_4 = A4_3
        L6_4 = A5_3
        L7_4 = A6_3
        L8_4 = A7_3
        L9_4 = A8_3
        L10_4 = A9_3
        L11_4 = A10_3
        L12_4 = A11_3
        L0_4(L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4)
      end
      L14_3 = debug
      L14_3 = L14_3.traceback
      L12_3, L13_3 = L12_3(L13_3, L14_3)
      if not L12_3 then
        L14_3 = {}
        L14_3[1] = A0_3
        L14_3[2] = A1_3
        L14_3[3] = A2_3
        L14_3[4] = A3_3
        L14_3[5] = A4_3
        L14_3[6] = A5_3
        L14_3[7] = A6_3
        L14_3[8] = A7_3
        L14_3[9] = A8_3
        L14_3[10] = A9_3
        L14_3[11] = A10_3
        L14_3[12] = A11_3
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^2Error in: ^1RegisterNUICallback^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^2Event name: ^1"
        L17_3 = A0_2
        L18_3 = "^0"
        L16_3 = L16_3 .. L17_3 .. L18_3
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = DisplayCurrentRecordSteps
        L16_3 = A0_2
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = pairs
        L16_3 = L14_3
        L15_3, L16_3, L17_3, L18_3 = L15_3(L16_3)
        for L19_3, L20_3 in L15_3, L16_3, L17_3, L18_3 do
          L21_3 = print
          L22_3 = "^0Argument key: ^1"
          L23_3 = L19_3
          L22_3 = L22_3 .. L23_3
          L21_3(L22_3)
          L21_3 = print
          L22_3 = "^0Argument value type: ^1"
          L23_3 = type
          L24_3 = L20_3
          L23_3 = L23_3(L24_3)
          L22_3 = L22_3 .. L23_3
          L21_3(L22_3)
          L21_3 = print
          L22_3 = " "
          L21_3(L22_3)
          L21_3 = type
          L22_3 = L20_3
          L21_3 = L21_3(L22_3)
          if "table" == L21_3 then
            L21_3 = print
            L22_3 = "^0Argument value: ^1"
            L23_3 = tostring
            L24_3 = L20_3
            L23_3 = L23_3(L24_3)
            L22_3 = L22_3 .. L23_3
            L21_3(L22_3)
            L21_3 = L7_1
            L22_3 = L20_3
            L21_3(L22_3)
          else
            L21_3 = print
            L22_3 = "^0Argument value: ^1"
            L23_3 = tostring
            L24_3 = L20_3
            L23_3 = L23_3(L24_3)
            L22_3 = L22_3 .. L23_3
            L21_3(L22_3)
          end
          L21_3 = print
          L22_3 = "^5=====^0"
          L21_3(L22_3)
        end
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = L13_3
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = ""
        L16_3 = 1
        L17_3 = 12
        L18_3 = 1
        for L19_3 = L16_3, L17_3, L18_3 do
          L20_3 = L14_3[L19_3]
          L21_3 = type
          L22_3 = L20_3
          L21_3 = L21_3(L22_3)
          if "table" == L21_3 then
            L21_3 = L15_3
            L22_3 = L7_1
            L23_3 = L20_3
            L24_3 = true
            L22_3 = L22_3(L23_3, L24_3)
            L23_3 = ","
            L21_3 = L21_3 .. L22_3 .. L23_3
            L15_3 = L21_3
          else
            L21_3 = type
            L22_3 = L20_3
            L21_3 = L21_3(L22_3)
            if "string" == L21_3 then
              L21_3 = L15_3
              L22_3 = "'"
              L23_3 = L20_3
              L24_3 = "',"
              L21_3 = L21_3 .. L22_3 .. L23_3 .. L24_3
              L15_3 = L21_3
            else
              L21_3 = L15_3
              L22_3 = tostring
              L23_3 = L20_3
              L22_3 = L22_3(L23_3)
              L23_3 = ","
              L21_3 = L21_3 .. L22_3 .. L23_3
              L15_3 = L21_3
            end
          end
        end
        L16_3 = print
        L17_3 = "^0Replication trigger event:"
        L16_3(L17_3)
        L16_3 = print
        L17_3 = "^1TriggerEvent('__cfx_nui:"
        L18_3 = A0_2
        L19_3 = "', "
        L21_3 = L15_3
        L20_3 = L15_3.gsub
        L22_3 = "\n"
        L23_3 = ""
        L20_3 = L20_3(L21_3, L22_3, L23_3)
        L21_3 = L20_3
        L20_3 = L20_3.sub
        L22_3 = 1
        L23_3 = -2
        L20_3 = L20_3(L21_3, L22_3, L23_3)
        L21_3 = ")"
        L17_3 = L17_3 .. L18_3 .. L19_3 .. L20_3 .. L21_3
        L16_3(L17_3)
        L16_3 = print
        L17_3 = "^5=========================^0"
        L16_3(L17_3)
      end
    end
    L2_2(L3_2, L4_2)
  end
  RegisterNUICallback = L8_1
  function L8_1(A0_2, A1_2)
    local L2_2, L3_2
    L2_2 = L4_1
    function L3_2()
      local L0_3, L1_3, L2_3, L3_3, L4_3, L5_3
      L0_3 = xpcall
      L1_3 = A0_2
      L2_3 = debug
      L2_3 = L2_3.traceback
      L0_3, L1_3 = L0_3(L1_3, L2_3)
      if not L0_3 then
        L2_3 = print
        L3_3 = "========================="
        L2_3(L3_3)
        L2_3 = print
        L3_3 = "^2Error in: ^1CreateThread^0"
        L2_3(L3_3)
        L2_3 = print
        L3_3 = "^1"
        L4_3 = A1_2
        if not L4_3 then
          L4_3 = "non defined"
        end
        L5_3 = "^0"
        L3_3 = L3_3 .. L4_3 .. L5_3
        L2_3(L3_3)
        L2_3 = print
        L3_3 = "========================="
        L2_3(L3_3)
        L2_3 = DisplayCurrentRecordSteps
        L3_3 = A1_2
        L2_3(L3_3)
        L2_3 = print
        L3_3 = "^5=========================^0"
        L2_3(L3_3)
        L2_3 = print
        L3_3 = L1_3
        L2_3(L3_3)
        L2_3 = print
        L3_3 = "========================="
        L2_3(L3_3)
      end
    end
    L2_2(L3_2)
  end
  CreateThread = L8_1
  function L8_1(A0_2, A1_2)
    local L2_2, L3_2, L4_2
    L2_2 = L2_1
    L3_2 = A0_2
    function L4_2(A0_3, A1_3, A2_3, A3_3, A4_3, A5_3, A6_3, A7_3, A8_3, A9_3, A10_3, A11_3)
      local L12_3, L13_3, L14_3, L15_3, L16_3, L17_3, L18_3, L19_3, L20_3, L21_3, L22_3, L23_3, L24_3
      L12_3 = xpcall
      function L13_3()
        local L0_4, L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4
        L0_4 = A1_2
        L1_4 = A0_3
        L2_4 = A1_3
        L3_4 = A2_3
        L4_4 = A3_3
        L5_4 = A4_3
        L6_4 = A5_3
        L7_4 = A6_3
        L8_4 = A7_3
        L9_4 = A8_3
        L10_4 = A9_3
        L11_4 = A10_3
        L12_4 = A11_3
        L0_4(L1_4, L2_4, L3_4, L4_4, L5_4, L6_4, L7_4, L8_4, L9_4, L10_4, L11_4, L12_4)
      end
      L14_3 = debug
      L14_3 = L14_3.traceback
      L12_3, L13_3 = L12_3(L13_3, L14_3)
      if not L12_3 then
        L14_3 = {}
        L14_3[1] = A0_3
        L14_3[2] = A1_3
        L14_3[3] = A2_3
        L14_3[4] = A3_3
        L14_3[5] = A4_3
        L14_3[6] = A5_3
        L14_3[7] = A6_3
        L14_3[8] = A7_3
        L14_3[9] = A8_3
        L14_3[10] = A9_3
        L14_3[11] = A10_3
        L14_3[12] = A11_3
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^2Error in: ^1AddEventHandler^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^2Event name: ^1"
        L17_3 = A0_2
        L18_3 = "^0"
        L16_3 = L16_3 .. L17_3 .. L18_3
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = DisplayCurrentRecordSteps
        L16_3 = A0_2
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = pairs
        L16_3 = L14_3
        L15_3, L16_3, L17_3, L18_3 = L15_3(L16_3)
        for L19_3, L20_3 in L15_3, L16_3, L17_3, L18_3 do
          L21_3 = print
          L22_3 = "^0Argument key: ^1"
          L23_3 = L19_3
          L22_3 = L22_3 .. L23_3
          L21_3(L22_3)
          L21_3 = print
          L22_3 = "^0Argument value type: ^1"
          L23_3 = type
          L24_3 = L20_3
          L23_3 = L23_3(L24_3)
          L22_3 = L22_3 .. L23_3
          L21_3(L22_3)
          L21_3 = print
          L22_3 = " "
          L21_3(L22_3)
          L21_3 = type
          L22_3 = L20_3
          L21_3 = L21_3(L22_3)
          if "table" == L21_3 then
            L21_3 = print
            L22_3 = "^0Argument value: ^1"
            L23_3 = tostring
            L24_3 = L20_3
            L23_3 = L23_3(L24_3)
            L22_3 = L22_3 .. L23_3
            L21_3(L22_3)
            L21_3 = L7_1
            L22_3 = L20_3
            L21_3(L22_3)
          else
            L21_3 = print
            L22_3 = "^0Argument value: ^1"
            L23_3 = tostring
            L24_3 = L20_3
            L23_3 = L23_3(L24_3)
            L22_3 = L22_3 .. L23_3
            L21_3(L22_3)
          end
          L21_3 = print
          L22_3 = "^5=====^0"
          L21_3(L22_3)
        end
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = print
        L16_3 = L13_3
        L15_3(L16_3)
        L15_3 = print
        L16_3 = "^5=========================^0"
        L15_3(L16_3)
        L15_3 = ""
        L16_3 = 1
        L17_3 = 12
        L18_3 = 1
        for L19_3 = L16_3, L17_3, L18_3 do
          L20_3 = L14_3[L19_3]
          L21_3 = type
          L22_3 = L20_3
          L21_3 = L21_3(L22_3)
          if "table" == L21_3 then
            L21_3 = L15_3
            L22_3 = L7_1
            L23_3 = L20_3
            L24_3 = true
            L22_3 = L22_3(L23_3, L24_3)
            L23_3 = ","
            L21_3 = L21_3 .. L22_3 .. L23_3
            L15_3 = L21_3
          else
            L21_3 = type
            L22_3 = L20_3
            L21_3 = L21_3(L22_3)
            if "string" == L21_3 then
              L21_3 = L15_3
              L22_3 = "'"
              L23_3 = L20_3
              L24_3 = "',"
              L21_3 = L21_3 .. L22_3 .. L23_3 .. L24_3
              L15_3 = L21_3
            else
              L21_3 = L15_3
              L22_3 = tostring
              L23_3 = L20_3
              L22_3 = L22_3(L23_3)
              L23_3 = ","
              L21_3 = L21_3 .. L22_3 .. L23_3
              L15_3 = L21_3
            end
          end
        end
        L16_3 = print
        L17_3 = "^0Replication trigger event:"
        L16_3(L17_3)
        L16_3 = print
        L17_3 = "^1TriggerEvent('"
        L18_3 = A0_2
        L19_3 = "', "
        L21_3 = L15_3
        L20_3 = L15_3.gsub
        L22_3 = "\n"
        L23_3 = ""
        L20_3 = L20_3(L21_3, L22_3, L23_3)
        L21_3 = L20_3
        L20_3 = L20_3.sub
        L22_3 = 1
        L23_3 = -2
        L20_3 = L20_3(L21_3, L22_3, L23_3)
        L21_3 = ")"
        L17_3 = L17_3 .. L18_3 .. L19_3 .. L20_3 .. L21_3
        L16_3(L17_3)
        L16_3 = print
        L17_3 = "^5=========================^0"
        L16_3(L17_3)
      end
    end
    L2_2(L3_2, L4_2)
  end
  AddEventHandler = L8_1
end
