CM.Shared = {
    Keys = {INTERACT = 38, CANCEL = 177, PHONE = 311, INVENTORY = 289, VOICE = 137, HUD = 212},
    Colors = {primary = "#1a73e8", success = "#34a853", warning = "#fbbc04", error = "#ea4335", info = "#4285f4", background = "#121212", surface = "#1e1e1e", text = "#ffffff", textMuted = "#aaaaaa"},
    Notify = {position = "top-right", duration = 5000},
    Time = {dateFormat = "%d/%m/%Y", timeFormat = "%H:%M"},
    Distance = {interaction = 2.0, voice = 15.0, whisper = 5.0, yell = 30.0},
}

if IsDuplicityVersion() then
    GlobalState.CMShared = CM.Shared
else
    CM.Shared = GlobalState.CMShared or CM.Shared
end