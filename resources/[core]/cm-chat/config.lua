Config = Config or {}

-- Key and message limits
Config.OpenKey = 'T'
Config.MaxMessageLength = 180
Config.ChatCooldownMs = 650
Config.DefaultLocalRadius = 20.0

-- Messages stay visible. Set this higher only if you want old messages removed by count.
Config.MaxVisibleMessages = 45

-- UI position. Edit this only if you want to move the chat later.
-- Current default keeps chat at top-left so it does not cover minimap/HUD.
Config.UI = {
    left = 24,
    top = 26,
    width = 720,
    height = 430,
    inputWidth = 600,
    fontSize = 18
}

-- Color names you can use from other resources, for example:
-- exports['cm-chat']:SetPlayerChatGroup(source, 'family', familyId, 'green')
Config.ColorPalette = {
    cyan = '#31e6ff',
    blue = '#188cff',
    green = '#72ff8c',
    lime = '#72ff8c',
    red = '#ff5b5b',
    orange = '#ffad4d',
    yellow = '#ffe35b',
    purple = '#b889ff',
    pink = '#ff5cf7',
    white = '#ffffff',
    grey = '#9bb8c8',
    gray = '#9bb8c8'
}

-- Logs
Config.EnableDatabaseLogs = true
Config.EnableBlockedWords = true
Config.BlockedWords = {
    -- Add blocked words here if needed.
}

-- Character table used only to resolve first_name / last_name from character ID.
Config.CharacterTable = 'characters'
Config.CharacterIdColumn = 'id'
Config.CharacterFirstNameColumn = 'first_name'
Config.CharacterLastNameColumn = 'last_name'

-- Group state keys. Other resources can either set Player(source).state.familyId/orgId/clubId
-- OR call exports['cm-chat']:SetPlayerChatGroup(source, 'family', familyId, 'green')
Config.GroupStateKeys = {
    family = { 'cmFamily', 'familyId', 'family_id', 'family', 'familyName', 'family_name' },
    org    = { 'orgId', 'org_id', 'organisationId', 'organizationId', 'organization_id', 'org', 'organisation', 'organization' },
    club   = { 'clubId', 'club_id', 'club', 'clubName', 'club_name' }
}

-- UI actions shown under ACTIONS when chat is open.
Config.Actions = {
    { id = 'me',    label = 'ME',    command = '/me ' },
    { id = 'do',    label = 'DO',    command = '/do ' },
    { id = 'try',   label = 'TRY',   command = '/try ' },
    { id = 'low',   label = 'LOW',   command = '/low ' },
    { id = 'shout', label = 'SHOUT', command = '/s ' }
}

-- Channel types:
-- proximity = only nearby players
-- global    = everyone
-- group     = only players with same family/org/club id
-- staff     = only active/staff admins
Config.Channels = {
    rp = {
        id = 'rp', label = 'RP', type = 'proximity', radius = 20.0,
        always = true, color = '#31e6ff', format = 'rp'
    },

    nonrp = {
        id = 'nonrp', label = 'NON-RP', type = 'global',
        always = true, color = '#9bb8c8', format = 'nonrp'
    },

    family = {
        id = 'family', label = 'FAMILY', type = 'group', group = 'family',
        color = '#72ff8c', format = 'family'
    },

    org = {
        id = 'org', label = 'ORG', type = 'group', group = 'org',
        color = '#31e6ff', format = 'group'
    },

    club = {
        id = 'club', label = 'CLUB', type = 'group', group = 'club',
        color = '#b889ff', format = 'group'
    },

    admin = {
        id = 'admin', label = 'ADMIN', type = 'staff', staff = true,
        color = '#ff5cf7', format = 'admin'
    },

    me = {
        id = 'me', label = 'ME', type = 'proximity', radius = 20.0,
        hiddenTab = true, color = '#31e6ff', format = 'me'
    },

    doo = {
        id = 'doo', label = 'DO', type = 'proximity', radius = 20.0,
        hiddenTab = true, color = '#7df3ff', format = 'do'
    },

    low = {
        id = 'low', label = 'LOW', type = 'proximity', radius = 5.0,
        hiddenTab = true, color = '#c7d1dc', format = 'rp'
    },

    shout = {
        id = 'shout', label = 'SHOUT', type = 'proximity', radius = 35.0,
        hiddenTab = true, color = '#ffbe58', format = 'rp'
    }
}

Config.ChannelOrder = { 'rp', 'nonrp', 'family', 'org', 'club', 'admin' }

Config.CommandAliases = {
    ooc = 'nonrp',
    b = 'low',
    s = 'shout',
    a = 'admin',
    staff = 'admin'
}
