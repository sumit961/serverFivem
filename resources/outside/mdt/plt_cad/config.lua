Config = {}

-- Framework Configuration
-- Options: "QB", "ESX", or "AUTO"
Config.Framework = "AUTO" 

-- Notification Type
-- Options: "qb", "esx", "chat", or "AUTO"
Config.NotifyType = "AUTO"

-- UI Header Configuration
Config.HeaderLeftText = "POLICE DEPT."
Config.HeaderRightText = "MDT SYSTEM V1.2"

-- Optimization Settings
Config.RenderDistance = 10.0 -- The CAD will only render and run when within this distance (meters)

-- Command Configuration
Config.Commands = {
    open = "cad",
    close = "cadclose",
    key = "cadkey",
    test = "cad2d",
    edit = "cadedit"
}

-- Discord Integration
Config.Webhook = "" -- Paste your Discord Webhook URL here
Config.WebhookName = "LSPD Records"
Config.WebhookIcon = "https://i.imgur.com/83uA5fG.png"

-- UI Features
Config.AddFakeOfficers = true -- Add 2 fake officers to the unit status for testing

-- Access Configuration
Config.Jobs = { "police", "sheriff", "fib" } -- The jobs required to use/spawn the CAD

