Config = Config or {}

-- CM Admin v2.5 - character ID based staff access
-- You join as a normal player. Type /admin to enter/leave admin mode.
-- F11 opens the admin menu ONLY while admin mode is enabled.

Config.AdminToggleCommand = 'admin'
-- Renamed from cm_admin_menu so the F11 default applies to everyone
-- (FiveM caches keybinds per command name; the old name kept F12).
Config.MenuKeybindCommand = 'cm_admin_menu_v2'
Config.DefaultMenuKey = 'F11'

-- Bootstrap owners by CHARACTER ID only.
-- This is NOT your server id, FiveM id, license, or account id.
-- It must be the selected character id from your characters database.
-- Example from your logs: selectCharacter: 12, so character id 12 becomes owner.
Config.OwnerCharacterIds = {
    12
}

-- Security: old v2.0 account/license based admin rows should not be used.
Config.DisableLegacyIdentifierAdmins = true

-- Optional ACE development fallback. Keep false for your plan because admin must be character-id based only.
-- If true, ACE will only bootstrap the CURRENT selected character, not the whole account.
Config.AllowAceAdminBootstrap = false
Config.AdminAce = 'group.admin'


-- Optional event names from your character/spawn resources that can pass selected character data.
-- Best method: in cm-characters after select, set Player(source).state.charId = characterId
-- or TriggerEvent('cm-admin:server:setCharacterId', source, characterId, characterRow)
Config.CharacterLoadedEvents = {
    'cm-characters:server:characterLoaded',
    'cm-characters:server:characterSelected',
    'cm-spawn:server:characterLoaded',
    'cm-core:server:characterLoaded'
}

-- Noclip / utility commands kept from v1.5.
Config.Commands = { 'cmfly', 'noclip', 'fly' }
Config.KeybindCommand = 'cm_admin_noclip_toggle'
Config.DefaultKey = 'F2'

Config.AllowPlayerUnstuck = true
Config.UnstuckCooldown = 60000

Config.Speeds = {
    normal = 1.6,
    fast = 5.8,
    slow = 0.35
}

Config.ShowHelp = true
Config.MakeInvisible = false
Config.DisableCollision = true
Config.InvincibleDuringNoclip = true
Config.SafeCoords = vector4(215.76, -810.12, 30.73, 157.0)

-- Admin money tools. Give Cash uses characters.cash by default.
Config.AdminMoney = {
    MaxGiveCash = 1000000,
    AllowSelfGiveCash = true
}

-- Default rank templates. They are auto-created in DB on first start.
-- Permissions are server-side; the UI only displays what the server allows.
Config.DefaultRanks = {
    owner = {
        label = 'Owner', level = 100,
        permissions = { '*' }
    },
    co_owner = {
        label = 'Co-Owner', level = 90,
        permissions = { '*' }
    },
    head_admin = {
        label = 'Head Admin', level = 80,
        permissions = {
            'menu.open', 'players.view', 'players.manage', 'players.teleport', 'players.freeze', 'players.kick', 'money.manage',
            'inventory.view', 'vehicles.view', 'vehicles.manage', 'vehicle_inventory.view',
            'admins.view', 'admins.manage', 'ranks.view', 'ranks.manage', 'logs.view',
            'noclip', 'teleport', 'tools.heal',
            'dev.view', 'dev.tools', 'dev.clothing', 'dev.vehicles', 'dev.weapons', 'dev.climatime'
        }
    },
    senior_admin = {
        label = 'Senior Admin', level = 70,
        permissions = {
            'menu.open', 'players.view', 'players.manage', 'players.teleport', 'players.freeze', 'players.kick', 'money.manage',
            'inventory.view', 'vehicles.view', 'vehicles.manage', 'vehicle_inventory.view',
            'admins.view', 'logs.view', 'noclip', 'teleport', 'tools.heal', 'dev.view'
        }
    },
    admin = {
        label = 'Admin', level = 60,
        permissions = {
            'menu.open', 'players.view', 'players.manage', 'players.teleport', 'players.freeze', 'money.manage',
            'inventory.view', 'vehicles.view', 'vehicle_inventory.view', 'logs.view',
            'noclip', 'teleport', 'tools.heal'
        }
    },
    senior_mod = {
        label = 'Senior Moderator', level = 50,
        permissions = {
            'menu.open', 'players.view', 'players.manage', 'players.teleport', 'players.freeze', 'money.manage',
            'inventory.view', 'logs.view', 'noclip', 'tools.heal'
        }
    },
    moderator = {
        label = 'Moderator', level = 40,
        permissions = {
            'menu.open', 'players.view', 'players.teleport', 'players.freeze', 'logs.view', 'noclip'
        }
    },
    trial_mod = {
        label = 'Trial Moderator', level = 30,
        permissions = {
            'menu.open', 'players.view', 'players.freeze', 'logs.view'
        }
    },
    support = {
        label = 'Support', level = 20,
        permissions = {
            'menu.open', 'players.view', 'logs.view'
        }
    },
    trial_support = {
        label = 'Trial Support', level = 10,
        permissions = {
            'menu.open', 'players.view'
        }
    }
}

-- Data bridge. Your server has custom resources, so these queries are intentionally configurable.
-- The script tries each query safely. If a table does not exist, it falls back without crashing.
-- Offline character search (Players > Offline tab). Tried in order.
Config.OfflineSearchQueries = {
    { label = 'characters by exact id', mode = 'id',
      sql = 'SELECT id, first_name, last_name, dob, cash, bank FROM characters WHERE id = ? LIMIT 20' },
    { label = 'characters by name', mode = 'name',
      sql = "SELECT id, first_name, last_name, dob, cash, bank FROM characters WHERE CONCAT(first_name, ' ', last_name) LIKE ? ORDER BY last_played DESC LIMIT 20" }
}

-- Built-in developer tools (Developer tab). Adjust commands to match your
-- stores. NEW RESOURCES DO NOT GO HERE: they self-register at startup with
--   exports['cm-admin']:RegisterDevTool({ ... })
-- and appear automatically with permission gating and audit logging.
Config.DevToolsBuiltin = {
    {
        id = 'clothing', label = 'Clothing Store', category = 'Stores',
        icon = 'shirt', permission = 'dev.clothing',
        actions = {
            { id = 'open_store', label = 'Open Clothing Shop (Admin)', type = 'command', command = 'clothShop',
              hint = 'Opens nv_cloth. Set your admin variant command here if different.' }
        }
    },
    {
        id = 'vehicles', label = 'Vehicle Admin', category = 'Stores',
        icon = 'car', permission = 'dev.vehicles',
        actions = {
            { id = 'open', label = 'Open Vehicle Admin', type = 'command', command = 'vehicleadmin' }
        }
    },
    {
        id = 'weapons', label = 'Weapon Admin', category = 'Stores',
        icon = 'gun', permission = 'dev.weapons',
        actions = {
            { id = 'open', label = 'Open Weapon Picker', type = 'command', command = 'gunadmin' }
        }
    }
}

Config.Map = {
    RefreshMs = 2000,
    MaxVehicles = 300
}

Config.DatabaseBridge = {
    -- Matched to the real CM Framework schemas (cm-core, cm-inventory, cm-vehicles).
    -- NOTE: online identity comes from the character statebag; the characters
    -- table has NO license column (auth is username-based via accounts), so
    -- there is intentionally no license-based character lookup here.
    CharacterQuery = nil,

    -- Money lives in characters (cash/bank). Used as fallback + offline profile.
    MoneyQuery = 'SELECT cash, bank FROM characters WHERE id = ? LIMIT 1',
    AddCashQuery = 'UPDATE characters SET cash = GREATEST(0, COALESCE(cash, 0) + ?) WHERE id = ?',

    InventoryQueries = {
        { label = 'inventory_items (character)', mode = 'charId',
          sql = "SELECT slot, item_name, quantity FROM inventory_items WHERE owner_type = 'character' AND owner_id = ? ORDER BY slot LIMIT 200" }
    },

    VehicleQueries = {
        { label = 'cm_owned_vehicles', mode = 'charId',
          sql = 'SELECT plate, model, label, fuel, engine_health, body_health, is_stored, garage FROM cm_owned_vehicles WHERE owner_character_id = ? ORDER BY id DESC LIMIT 200' }
    },

    VehicleInventoryQueries = {
        { label = 'inventory_items (vehicle by plate)', mode = 'plate',
          sql = "SELECT owner_type, slot, item_name, quantity FROM inventory_items WHERE owner_id = ? AND owner_type <> 'character' ORDER BY owner_type, slot LIMIT 200" }
    }
}
