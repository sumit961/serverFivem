Config = Config or {}

Config.Security = {
    adminCooldownMs = 750,
    maxNoticeId = 48,
    maxTitle = 96,
    maxSummary = 240,
    maxBody = 4000,
    maxCategory = 32,
    maxPriority = 16,
    maxTimestamp = 4102444800,
    dashboardLimit = 200,
    adminListLimit = 500,
}

Config.Admin = {
    permission = 'orgs.manage',
    invokingResource = 'cm-admin',
}

Config.Categories = {
    general = true,
    city = true,
    safety = true,
    services = true,
    community = true,
    events = true,
}

Config.Priorities = {
    normal = 1,
    important = 2,
    urgent = 3,
}

Config.Commands = {
    primary = 'bulletin',
    alias = 'news',
}
