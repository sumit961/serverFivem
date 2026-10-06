Config = Config or {}

Config.Security = {
    inviteExpirySeconds = 90,
    inviteCooldownMs = 1500,
    mutationCooldownMs = 750,
    interactionMaxDistance = 5.0,
    maxClubId = 32,
    maxName = 64,
    maxTag = 12,
    maxDescription = 255,
    maxActivityDetail = 180,
}

Config.Permissions = {
    viewMembers = 'club.view_members',
    invite = 'club.invite',
    manageMembers = 'club.manage_members',
    manageRanks = 'club.manage_ranks',
    chat = 'club.chat',
}

Config.Admin = {
    permission = 'orgs.manage',
    invokingResource = 'cm-admin',
}

Config.Chat = {
    group = 'club',
    fallbackColor = '#00E5FF',
}

-- Physical locations are database/admin configuration, not permanent world
-- defaults. A clubhouse with disabled state or missing coordinates never
-- spawns an NPC and never authorizes access.
Config.Clubhouse = {
    spawnDistance = 125.0,
    despawnDistance = 150.0,
    markerDistance = 35.0,
    defaultInteractionDistance = 2.5,
    maxInteractionDistance = 8.0,
    requestCooldownMs = 750,
    modelLoadTimeoutMs = 5000,
    modelNames = {
        a_m_m_business_01 = true,
        a_m_y_business_02 = true,
        a_f_y_business_02 = true,
        s_m_m_highsec_01 = true,
    },
    marker = {
        type = 1,
        scale = { x = 0.72, y = 0.72, z = 0.22 },
        colour = { r = 0, g = 229, b = 255, a = 125 },
        bobUpAndDown = false,
        faceCamera = false,
        rotate = false,
    },
}

-- Administrators may provide their own rank definitions when creating a club.
-- These are only defaults; there is no automatic club seed or player creation path.
Config.DefaultRanks = {
    {
        rankKey = 'leader',
        name = 'Leader',
        tier = 100,
        isLeader = true,
        permissions = {
            ['club.view_members'] = true,
            ['club.invite'] = true,
            ['club.manage_members'] = true,
            ['club.manage_ranks'] = true,
            ['club.chat'] = true,
        },
    },
    {
        rankKey = 'officer',
        name = 'Officer',
        tier = 60,
        isLeader = false,
        permissions = {
            ['club.view_members'] = true,
            ['club.invite'] = true,
            ['club.manage_members'] = true,
            ['club.chat'] = true,
        },
    },
    {
        rankKey = 'member',
        name = 'Member',
        tier = 10,
        isLeader = false,
        permissions = {
            ['club.view_members'] = true,
            ['club.chat'] = true,
        },
    },
}
