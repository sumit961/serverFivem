PrisonConfig = {
    AdminResource = 'cm-admin',
    Intake = {
        model = 's_m_m_prisguard_01',
        name = 'Officer Daniels',
        role = 'Prison Intake Officer',
        drawDistance = 18.0,
        interactDistance = 2.5,
    },
    SpawnCapacity = 2,
    IntakeRadius = 8.0,
    AdminPermission = 'orgs.manage',
}

-- Task-based sentence reduction: a prisoner can perform a small world task
-- (trash pickup, pushups, sweeping) near a jail spawn to shave time off their
-- own sentence via the ReduceSentence export, on a per-player cooldown so it
-- can't be spammed. Locations are relative offsets from each jail spawn
-- (PrisonLocations.spawns, server/main.lua) rather than fixed world
-- coordinates, since spawn placement is admin-configured and can move.
PrisonConfig.Tasks = {
    Enabled = true,
    ReductionMinutes = 5,
    DurationMs = 8000,
    CooldownMs = 60000,
    InteractDistance = 2.0,
    -- Offsets are added to each configured jail spawn's coordinates so a task
    -- point exists at every spawn without per-spawn admin configuration.
    Offsets = {
        { x = 2.5, y = 0.0, z = 0.0, label = 'Pick up trash', anim = { dict = 'anim@amb@nightclub@mini@cleaning@low@', clip = 'low_clean_cabinets_2', flag = 1 } },
        { x = -2.5, y = 0.0, z = 0.0, label = 'Do pushups', anim = { dict = 'amb@world_human_muscle_flex@male@base', clip = 'base', flag = 1 } },
        { x = 0.0, y = 2.5, z = 0.0, label = 'Sweep the cell', anim = { dict = 'amb@world_human_janitor@male@base', clip = 'base', flag = 1 } },
    },
}
