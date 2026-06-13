Config = Config or {}

-- Test mode only. Later set true for public server.
Config.RequireAce = false
Config.AcePermission = 'cm.admin.noclip'

Config.Commands = { 'cmfly', 'noclip', 'fly' }
Config.KeybindCommand = 'cm_admin_noclip_toggle'
Config.DefaultKey = 'F2'

Config.Speeds = {
    normal = 1.6,
    fast = 5.8,
    slow = 0.35
}

Config.ShowHelp = true
Config.MakeInvisible = false
Config.DisableCollision = true
Config.InvincibleDuringNoclip = true

-- If safe ground cannot be found, this is used as recovery point.
Config.SafeCoords = vector4(215.76, -810.12, 30.73, 157.0)
