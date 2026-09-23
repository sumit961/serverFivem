-- =============================================================================
-- charge.lua  (deobfuscated from decompiled SHX* form)
-- Resource: plt_mdt  —  Server-side charge management callbacks
-- =============================================================================
-- Four RegisterCallback handlers covering full CRUD for the mdt_charges table.
-- All are direct DB operations with no access checks — assumed to be controlled
-- at the NUI/client layer (officer-only UI).
-- =============================================================================


-- =============================================================================
-- SECTION 1 — RegisterCallback "plt_mdt:server:getAllCharges"
-- Returns all charges ordered by category then title.
-- originally lines 8-21:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:getAllCharges"
--   function SHX2_1(SHX0_2, SHX1_2) … end
-- =============================================================================

-- Callback signature: (source, cb)  — no extra data
RegisterCallback("plt_mdt:server:getAllCharges", function(source, cb)
    -- originally: MySQL.query.await("SELECT * FROM mdt_charges ORDER BY category, title")
    local charges = MySQL.query.await("SELECT * FROM mdt_charges ORDER BY category, title")

    -- originally: SHX3_2 = SHX1_2; SHX4_2 = SHX2_2; SHX3_2(SHX4_2)
    cb(charges)
end)


-- =============================================================================
-- SECTION 2 — RegisterCallback "plt_mdt:server:addCharge"
-- Inserts a new charge. Returns true if the insert succeeded (id > 0).
-- originally lines 22-51:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:addCharge"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end
-- Callback signature: (source, cb, data)
--   data = { title, description, category, fine, jail }
-- =============================================================================

RegisterCallback("plt_mdt:server:addCharge", function(source, cb, data)
    -- originally: MySQL.insert.await("INSERT INTO mdt_charges (title,description,category,fine,jail) VALUES (?,?,?,?,?)", {…})
    local insertedId = MySQL.insert.await(
        "INSERT INTO mdt_charges (title, description, category, fine, jail) VALUES (?, ?, ?, ?, ?)",
        {
            data.title,
            data.description,
            data.category,
            data.fine,
            data.jail,
        }
    )

    -- originally: SHX4_2 = SHX1_2; SHX5_2 = SHX3_2 > 0; SHX4_2(SHX5_2)
    -- insertedId is the last insert id; > 0 means a valid row was created.
    cb(insertedId > 0)
end)


-- =============================================================================
-- SECTION 3 — RegisterCallback "plt_mdt:server:updateCharge"
-- Updates all editable fields on an existing charge by id.
-- Returns true if at least one row was affected.
-- originally lines 52-89:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:updateCharge"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end
-- Callback signature: (source, cb, data)
--   data = { id, title, description, category, fine, jail }
-- =============================================================================

RegisterCallback("plt_mdt:server:updateCharge", function(source, cb, data)
    -- originally: MySQL.update.await("UPDATE mdt_charges SET title=?,description=?,category=?,fine=?,jail=? WHERE id=?", {…})
    local affectedRows = MySQL.update.await(
        "UPDATE mdt_charges SET title = ?, description = ?, category = ?, fine = ?, jail = ? WHERE id = ?",
        {
            data.title,
            data.description,
            data.category,
            data.fine,
            data.jail,
            data.id,
        }
    )

    -- originally: SHX4_2 = SHX1_2; SHX5_2 = SHX3_2 > 0; SHX4_2(SHX5_2)
    cb(affectedRows > 0)
end)


-- =============================================================================
-- SECTION 4 — RegisterCallback "plt_mdt:server:deleteCharge"
-- Deletes a charge by id.
-- Returns true if at least one row was affected.
-- originally lines 90-114:
--   SHX0_1 = RegisterCallback; SHX1_1 = "plt_mdt:server:deleteCharge"
--   function SHX2_1(SHX0_2, SHX1_2, SHX2_2) … end
-- Callback signature: (source, cb, chargeId)
--   NOTE: data argument here is the raw id, not a table (unlike addCharge/updateCharge).
-- =============================================================================

RegisterCallback("plt_mdt:server:deleteCharge", function(source, cb, chargeId)
    -- originally: MySQL.update.await("DELETE FROM mdt_charges WHERE id = ?", {SHX2_2})
    -- NOTE: MySQL.update.await used for DELETE — preserved as-is (same pattern as
    -- deleteVehicleBolo and deleteBolo). Works correctly; MySQL.query.await is more
    -- conventional for non-UPDATE DML.
    local affectedRows = MySQL.update.await(
        "DELETE FROM mdt_charges WHERE id = ?",
        { chargeId }
    )

    -- originally: SHX4_2 = SHX1_2; SHX5_2 = SHX3_2 > 0; SHX4_2(SHX5_2)
    cb(affectedRows > 0)
end)


-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Total lines in source:         114
-- Total lines in output:         ~95 (all logic preserved; boilerplate stripped)
-- Obfuscation techniques found:
--   1. SHX* identifier obfuscation — all renamed.
--   2. Module-level SHX0_1/SHX1_1/SHX2_1 reused as scratch on each
--      RegisterCallback call — separated into inline literals.
-- goto/label constructs:         0 (none present)
-- String arrays resolved:        0
-- Renamed identifiers:           3 module-level + ~28 inner-scope locals
-- Constructs flagged for review:
--   • deleteCharge receives the raw charge id as the third argument (not a
--     table), unlike addCharge and updateCharge which receive a data table.
--     This is consistent with the client-side charge.lua which passes data.id.
--   • MySQL.update.await used for DELETE — preserved verbatim; same pattern
--     appears throughout this resource (vehicle.lua, warrant.lua, etc.).
--   • No server-side access / job check on any of the four callbacks — access
--     is assumed to be enforced at the NUI / client level.
-- Functionality preserved:       YES