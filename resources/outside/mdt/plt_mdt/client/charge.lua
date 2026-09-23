-- =============================================================================
-- charge.lua  (deobfuscated from decompiled SHX* form)
-- Resource: plt_mdt  —  Client-side charge management NUI callbacks
-- =============================================================================
-- All four callbacks follow the same pattern:
--   NUI sends a request → client triggers a server callback → result passed
--   straight back to the NUI callback function.
-- =============================================================================


-- =============================================================================
-- SECTION 1 — NUI callback: getAllCharges
-- Fetches the full list of charges from the server and returns it to the NUI.
-- originally lines 8-22:
--   SHX0_1 = RegisterNUICallback; SHX1_1 = "getAllCharges"
--   function SHX2_1(SHX0_2, SHX1_2) … end; SHX0_1(SHX1_1, SHX2_1)
-- =============================================================================

RegisterNUICallback("getAllCharges", function(data, cb)
    -- originally: SHX2_2 = TriggerCallback; SHX3_2 = "plt_mdt:server:getAllCharges"
    -- No extra arguments needed — the server returns the full charge list.
    TriggerCallback("plt_mdt:server:getAllCharges", function(chargeList)
        -- originally: SHX1_3 = SHX1_2; SHX2_3 = SHX0_3; SHX1_3(SHX2_3)
        cb(chargeList)
    end)
end)


-- =============================================================================
-- SECTION 2 — NUI callback: addCharge
-- Sends the full charge data object to the server to create a new charge,
-- then returns the server's response to the NUI.
-- originally lines 23-50:
--   SHX0_1 = RegisterNUICallback; SHX1_1 = "addCharge"
--   function SHX2_1(SHX0_2, SHX1_2) … end; SHX0_1(SHX1_1, SHX2_1)
-- =============================================================================

RegisterNUICallback("addCharge", function(data, cb)
    -- originally: SHX2_2 = TriggerCallback; SHX3_2 = "plt_mdt:server:addCharge"
    -- Pass the entire data payload (new charge object) to the server.
    -- originally: SHX5_2 = SHX0_2; SHX2_2(SHX3_2, SHX4_2, SHX5_2)
    TriggerCallback("plt_mdt:server:addCharge", function(result)
        -- originally: SHX1_3 = SHX1_2; SHX2_3 = SHX0_3; SHX1_3(SHX2_3)
        cb(result)
    end, data)
end)


-- =============================================================================
-- SECTION 3 — NUI callback: updateCharge
-- Sends the updated charge data object to the server, then returns the
-- server's response to the NUI.
-- originally lines 51-80:
--   SHX0_1 = RegisterNUICallback; SHX1_1 = "updateCharge"
--   function SHX2_1(SHX0_2, SHX1_2) … end; SHX0_1(SHX1_1, SHX2_1)
-- =============================================================================

RegisterNUICallback("updateCharge", function(data, cb)
    -- originally: SHX2_2 = TriggerCallback; SHX3_2 = "plt_mdt:server:updateCharge"
    -- Pass the full updated charge object to the server.
    -- originally: SHX5_2 = SHX0_2; SHX2_2(SHX3_2, SHX4_2, SHX5_2)
    TriggerCallback("plt_mdt:server:updateCharge", function(result)
        -- originally: SHX1_3 = SHX1_2; SHX2_3 = SHX0_3; SHX1_3(SHX2_3)
        cb(result)
    end, data)
end)


-- =============================================================================
-- SECTION 4 — NUI callback: deleteCharge
-- Sends only the charge's id to the server for deletion, then returns the
-- server's response to the NUI.
-- originally lines 81-127:
--   SHX0_1 = RegisterNUICallback; SHX1_1 = "deleteCharge"
--   function SHX2_1(SHX0_2, SHX1_2) … end; SHX0_1(SHX1_1, SHX2_1)
-- =============================================================================

RegisterNUICallback("deleteCharge", function(data, cb)
    -- originally: SHX2_2 = TriggerCallback; SHX3_2 = "plt_mdt:server:deleteCharge"
    -- Only the charge id is sent — not the full object.
    -- originally: SHX5_2 = SHX0_2.id; SHX2_2(SHX3_2, SHX4_2, SHX5_2)
    TriggerCallback("plt_mdt:server:deleteCharge", function(result)
        -- originally: SHX1_3 = SHX1_2; SHX2_3 = SHX0_3; SHX1_3(SHX2_3)
        cb(result)
    end, data.id)
end)


-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- Total lines in source:         127
-- Total lines in output:         ~80 (all logic preserved)
-- Obfuscation techniques found:
--   1. SHX* identifier obfuscation throughout — all renamed.
--   2. Module-level SHX0_1/SHX1_1 reused as scratch for each RegisterNUICallback
--      call — separated into inline literals.
--   3. Inner callback always written as a named function SHX4_2 then passed as
--      an arg — inlined as an anonymous function for clarity.
-- String arrays resolved:        0
-- Renamed identifiers:           3 module-level + ~12 inner-scope locals
-- Constructs flagged for review:
--   • deleteCharge extracts only data.id before the server call — confirmed
--     intentional (server needs only the id, not the full charge object).
--   • getAllCharges passes no extra args to TriggerCallback — confirmed correct;
--     the NUI data argument is unused (the server returns the full list regardless).
-- Functionality preserved:       YES