CMPayday = CMPayday or {}

CMPayday.Config = {
    Debug = false,

    -- Preserve the existing AddCash behaviour. Set to 'bank' only when the
    -- server economy explicitly wants payday wages deposited to bank.
    PayoutAccount = 'cash',
    MaxPendingCash = 1000000000,
    MaxPendingXp = 1000000,

    -- Jobs that bank their earnings through cm-payday instead of paying
    -- instantly. `label` is used in payslip notifications; a job only gets
    -- `xp` deferred alongside its cash if it already has its own leveling
    -- system to apply it back through at payout time (see AddXp exports in
    -- cm-taxi, cm-fishing, and cm-farming).
    Jobs = {
        taxi = { label = 'Taxi', xp = true },
        fishing = { label = 'Fishing', xp = true },
        electrician = { label = 'Electrician', xp = false },
        farming = { label = 'Farming', xp = true },
    },
}
