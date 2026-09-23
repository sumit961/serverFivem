CMPayday = CMPayday or {}

CMPayday.Config = {
    Debug = false,

    -- Jobs that bank their earnings through cm-payday instead of paying
    -- instantly. `label` is used in payslip notifications; a job only gets
    -- `xp` deferred alongside its cash if it already has its own leveling
    -- system to apply it back through at payout time (see AddXp exports in
    -- cm-taxi/server/progression.lua and cm-fishing/server/main.lua).
    Jobs = {
        taxi = { label = 'Taxi' },
        fishing = { label = 'Fishing' },
        electrician = { label = 'Electrician' },
        farming = { label = 'Farming' },
    },
}
