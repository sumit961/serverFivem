-- cm-police tickets / citations. Fines are only ever issued through the MDT
-- terminal now (server/mdt.lua's issueSingleFine/mdtIssueFine/mdtIssueFines)
-- -- there used to be a parallel G-menu "Cite: <violation>" path too, but it
-- was removed so every fine goes through the MDT's fuller charge-selection
-- UI instead of two separate flows. This file now only owns the shared
-- violation lookup and the citations table itself.

-- Global (not local) so server/mdt.lua can reuse the exact same violation
-- list/fine amounts for its own "Issue Fine" flow, same cross-file-global
-- convention as cid/memberFor/has/log/rateLimit/nameFor from server/main.lua.
-- All cm-police server_scripts share one Lua global environment with no
-- enforced namespacing beyond that documented convention -- this assert
-- turns a future accidental redefinition elsewhere into a loud startup
-- error instead of a silent clobber (whichever file loaded last would
-- otherwise win with zero warning).
assert(rawget(_G, 'violationById') == nil, 'violationById is already defined elsewhere -- global name collision')
function violationById(id)
    for _, violation in ipairs(Config.Citations.Violations) do
        if violation.id == id then return violation end
    end
    return nil
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_citations (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        target_cid VARCHAR(64) NOT NULL,
        officer_cid VARCHAR(64) NULL,
        violation_id VARCHAR(32) NOT NULL,
        violation_label VARCHAR(64) NOT NULL,
        fine BIGINT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_cm_police_citation_target (target_cid)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    PoliceSchemaMarkReady('citations')
end)
