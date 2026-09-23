-- ============================================================
-- cm-family | sv_hardening_tests.lua | v1.8.1
-- Automated concurrency, idempotency, and transaction test suite.
-- Command: run_family_hardening_tests
-- ============================================================

print('^2[cm-family] sv_hardening_tests.lua loaded successfully!^7')

local function RunFamilyHardeningTests()
    CreateThread(function()
        local waitCount = 0
        while not CMFamilyDatabaseReady do
            Wait(500)
            waitCount = waitCount + 1
            if waitCount > 20 then
                print('^1[TEST SUITE] Timed out waiting for CMFamilyDatabaseReady!^7')
                return
            end
        end

        local ok, err = xpcall(function()
        print('^2============================================================^7')
        print('^2[TEST SUITE] STARTING FAMILY TRANSACTION HARDENING TESTS^7')
        print('^2============================================================^7')

        -- Create or identify a test family
        local testFamId = 999999
        local testCid1 = 'test_char_1'
        local testCid2 = 'test_char_2'

        -- Clean up previous test runs
        pcall(function()
            MySQL.query.await('DELETE FROM cm_family_reward_history WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_hq_upgrades WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_objective_progress WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_contribution_daily WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_member_contributions WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_progression WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_members WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_ranks WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_families WHERE id = ?', { testFamId })
        end)

        -- Insert isolated test family
        MySQL.query.await([[
            INSERT INTO cm_families (id, name, founder_cid, bank_balance)
            VALUES (?, 'Test Hardening Family', ?, 1000000)
        ]], { testFamId, testCid1 })

        if Families then
            Families[testFamId] = {
                id = testFamId,
                name = 'Test Hardening Family',
                founder_cid = testCid1,
                bank_balance = 1000000,
                ranks = {},
                ranksById = {},
            }
        end

        local founderRankId = CreateDefaultRanks(testFamId)
        CMFamilyInsertMember(testFamId, testCid1, founderRankId)
        CMFamilyInsertMember(testFamId, testCid2, founderRankId)

        if CMFamilyReloadRanks then CMFamilyReloadRanks(testFamId) end
        if MemberByCid then
            MemberByCid[testCid1] = { family_id = testFamId, rank_id = founderRankId }
            MemberByCid[testCid2] = { family_id = testFamId, rank_id = founderRankId }
        end

        local testsPassed = 0
        local testsTotal = 9

        -- ============================================================
        -- TEST A: Same reputation unique ID sent twice simultaneously
        -- ============================================================
        print('^3[TEST A] Same reputation unique ID sent twice simultaneously...^7')
        local uidA = 'testA_uniq_' .. os.time()
        local resA1, resA2
        local doneA1, doneA2 = false, false

        CreateThread(function()
            resA1 = AddFamilyReputation(testFamId, 100, 'test', uidA, { test = 'A1' })
            doneA1 = true
        end)
        CreateThread(function()
            resA2 = AddFamilyReputation(testFamId, 100, 'test', uidA, { test = 'A2' })
            doneA2 = true
        end)

        while not (doneA1 and doneA2) do Wait(10) end

        local historyCountA = MySQL.scalar.await([[
            SELECT COUNT(*) FROM cm_family_reward_history WHERE unique_id = ?
        ]], { uidA }) or 0

        if historyCountA == 1 and ((resA1 == true and resA2 == false) or (resA1 == false and resA2 == true)) then
            print('^2[TEST A PASS] Exactly one reward committed, duplicate rejected.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST A FAIL] historyCount=%s, resA1=%s, resA2=%s^7'):format(tostring(historyCountA), tostring(resA1), tostring(resA2)))
        end

        -- ============================================================
        -- TEST B: Two DIFFERENT XP rewards simultaneously from 500 XP
        -- Starting XP: 500. Rewards: +100, +200. Expected: Exactly 800 (Never 600 or 700)
        -- ============================================================
        print('^3[TEST B] Two different XP rewards simultaneously (+100 and +200 from 500)...^7')
        MySQL.query.await([[
            UPDATE cm_family_progression
            SET level = 1, current_xp = 500, lifetime_reputation = 500
            WHERE family_id = ?
        ]], { testFamId })
        if ProgressionByFamily then
            ProgressionByFamily[testFamId] = { level = 1, currentXp = 500, lifetimeReputation = 500, seasonReputation = 500 }
        end

        local uidB1 = 'testB_1_' .. os.time()
        local uidB2 = 'testB_2_' .. os.time()
        local doneB1, doneB2 = false, false

        CreateThread(function()
            AddFamilyReputation(testFamId, 100, 'testB1', uidB1)
            doneB1 = true
        end)
        CreateThread(function()
            AddFamilyReputation(testFamId, 200, 'testB2', uidB2)
            doneB2 = true
        end)

        while not (doneB1 and doneB2) do Wait(10) end

        local finalXpB = MySQL.scalar.await([[
            SELECT current_xp FROM cm_family_progression WHERE family_id = ?
        ]], { testFamId }) or 0

        if tonumber(finalXpB) == 800 then
            print('^2[TEST B PASS] Concurrent XP rewards correctly serialized: final XP = 800 (no lost XP).^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST B FAIL] Expected 800 XP, got %s^7'):format(tostring(finalXpB)))
        end

        -- ============================================================
        -- TEST C: Same contribution unique ID twice simultaneously
        -- ============================================================
        print('^3[TEST C] Same contribution unique ID twice simultaneously...^7')
        local uidC = 'testC_uniq_' .. os.time()
        local resC1, resC2
        local doneC1, doneC2 = false, false

        CreateThread(function()
            resC1 = AddFamilyMemberContribution(testCid1, testFamId, 50, 'activity', 'test', uidC)
            doneC1 = true
        end)
        CreateThread(function()
            resC2 = AddFamilyMemberContribution(testCid1, testFamId, 50, 'activity', 'test', uidC)
            doneC2 = true
        end)

        while not (doneC1 and doneC2) do Wait(10) end

        local historyCountC = MySQL.scalar.await([[
            SELECT COUNT(*) FROM cm_family_reward_history WHERE unique_id = ?
        ]], { uidC }) or 0

        if historyCountC == 1 and ((resC1 == true and resC2 == false) or (resC1 == false and resC2 == true)) then
            print('^2[TEST C PASS] Contribution duplicate unique ID atomically rejected.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST C FAIL] historyCount=%s, resC1=%s, resC2=%s^7'):format(tostring(historyCountC), tostring(resC1), tostring(resC2)))
        end

        -- ============================================================
        -- TEST D: Financial daily cap (Daily max: 100 points)
        -- Three deposits: $60k (60 pts), $50k (50 pts), $40k (40 pts) -> Total cash $150k, but points must cap at 100!
        -- ============================================================
        print('^3[TEST D] Financial daily cap ($60k + $50k + $40k deposits)...^7')
        MySQL.query.await('DELETE FROM cm_family_contribution_daily WHERE family_id = ? AND character_id = ?', { testFamId, testCid1 })
        MySQL.query.await('DELETE FROM cm_family_member_contributions WHERE family_id = ? AND character_id = ?', { testFamId, testCid1 })

        local okD1, pts1 = RecordFinancialContribution(testCid1, testFamId, 60000) -- should give 60
        local okD2, pts2 = RecordFinancialContribution(testCid1, testFamId, 50000) -- should give 40 (capped)
        local okD3, pts3 = RecordFinancialContribution(testCid1, testFamId, 40000) -- should give 0 (capped)

        local contribRowD = MySQL.single.await([[
            SELECT financial_points, money_contributed FROM cm_family_member_contributions
            WHERE family_id = ? AND character_id = ?
        ]], { testFamId, testCid1 })

        local dailyRowD = MySQL.single.await([[
            SELECT financial_points, money_contributed FROM cm_family_contribution_daily
            WHERE family_id = ? AND character_id = ?
        ]], { testFamId, testCid1 })

        local totalPtsAwarded = (tonumber(pts1) or 0) + (tonumber(pts2) or 0) + (tonumber(pts3) or 0)
        local dbPts = tonumber(contribRowD and contribRowD.financial_points) or 0
        local dbMoney = tonumber(contribRowD and contribRowD.money_contributed) or 0
        local dailyPts = tonumber(dailyRowD and dailyRowD.financial_points) or 0

        if dbPts == 100 and dailyPts == 100 and dbMoney == 150000 and totalPtsAwarded == 100 then
            print(('^2[TEST D PASS] Daily financial cap strictly enforced: %d points, $%d full cash recorded.^7'):format(dbPts, dbMoney))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST D FAIL] dbPts=%s, dailyPts=%s, dbMoney=%s, awarded=%s^7'):format(tostring(dbPts), tostring(dailyPts), tostring(dbMoney), tostring(totalPtsAwarded)))
        end

        -- ============================================================
        -- TEST E: Treasury-only activity reward called twice with same activity unique ID
        -- ============================================================
        print('^3[TEST E] Treasury-only activity reward called twice with same unique ID...^7')
        local uidE = 'testE_treasury_' .. os.time()
        local startBal = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        local resE1 = AwardFamilyActivityReward({
            familyId = testFamId,
            uniqueId = uidE,
            eventType = 'test_event',
            reputation = 0,
            treasuryAmount = 35000,
        })
        local resE2 = AwardFamilyActivityReward({
            familyId = testFamId,
            uniqueId = uidE,
            eventType = 'test_event',
            reputation = 0,
            treasuryAmount = 35000,
        })

        local endBal = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local diffBal = endBal - startBal

        if resE1 ~= false and resE2 == false and diffBal == 35000 then
            print(('^2[TEST E PASS] Treasury reward paid exactly once (+$%d), duplicate rejected.^7'):format(diffBal))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST E FAIL] resE1=%s, resE2=%s, diffBal=%s^7'):format(tostring(resE1 ~= false), tostring(resE2), tostring(diffBal)))
        end

        -- ============================================================
        -- TEST F: Objective completion called simultaneously by two execution paths
        -- ============================================================
        print('^3[TEST F] Objective completion called simultaneously by two paths...^7')
        local testObj = {
            key = 'test_obj_' .. os.time(),
            title = 'Test Objective',
            targetValue = 10,
            rewardReputation = 300,
            rewardTreasury = 20000,
        }
        local weekKeyF = '2026-W99'
        local resF1, resF2
        local doneF1, doneF2 = false, false

        CreateThread(function()
            resF1 = CompleteObjective(testFamId, testObj, weekKeyF, 10)
            doneF1 = true
        end)
        CreateThread(function()
            resF2 = CompleteObjective(testFamId, testObj, weekKeyF, 10)
            doneF2 = true
        end)

        while not (doneF1 and doneF2) do Wait(10) end

        local objRowF = MySQL.single.await([[
            SELECT reward_claimed, reward_state FROM cm_family_objective_progress
            WHERE family_id = ? AND objective_key = ? AND week_key = ?
        ]], { testFamId, testObj.key, weekKeyF })

        local objRewardsCount = MySQL.scalar.await([[
            SELECT COUNT(*) FROM cm_family_reward_history
            WHERE unique_id = ?
        ]], { ('obj:%s:%s:%s'):format(testFamId, weekKeyF, testObj.key) }) or 0

        if objRewardsCount == 1 and objRowF and objRowF.reward_state == 'delivered' and ((resF1 == true and resF2 == false) or (resF1 == false and resF2 == true)) then
            print('^2[TEST F PASS] Objective completion correctly idempotent: exactly 1 payout committed.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST F FAIL] rewardsCount=%s, state=%s, resF1=%s, resF2=%s^7'):format(tostring(objRewardsCount), tostring(objRowF and objRowF.reward_state), tostring(resF1), tostring(resF2)))
        end

        -- ============================================================
        -- TEST G: Simulate objective payout failure & verify safe retry
        -- ============================================================
        print('^3[TEST G] Simulate objective payout failure and safe retry...^7')
        local failObjKey = 'test_fail_obj_' .. os.time()
        local weekKeyG = '2026-W98'

        -- Pre-seed objective in 'failed' state
        MySQL.query.await([[
            INSERT INTO cm_family_objective_progress
              (family_id, objective_key, week_key, current_value, completed, completed_at, reward_claimed, reward_state)
            VALUES (?, ?, ?, 10, 1, NOW(), 0, 'failed')
        ]], { testFamId, failObjKey, weekKeyG })

        local retryObj = {
            key = failObjKey,
            title = 'Recoverable Objective',
            targetValue = 10,
            rewardReputation = 250,
            rewardTreasury = 15000,
        }

        local retryOk = CompleteObjective(testFamId, retryObj, weekKeyG, 10)
        local stateG = MySQL.scalar.await([[
            SELECT reward_state FROM cm_family_objective_progress
            WHERE family_id = ? AND objective_key = ? AND week_key = ?
        ]], { testFamId, failObjKey, weekKeyG })

        if retryOk == true and stateG == 'delivered' then
            print('^2[TEST G PASS] Previously failed objective safely recovered and delivered.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST G FAIL] retryOk=%s, stateG=%s^7'):format(tostring(retryOk), tostring(stateG)))
        end

        -- ============================================================
        -- TEST H: Two authorised members purchase same HQ tier simultaneously
        -- ============================================================
        print('^3[TEST H] Two members purchase the same HQ tier simultaneously...^7')
        MySQL.query.await('DELETE FROM cm_family_hq_upgrades WHERE family_id = ?', { testFamId })
        -- Ensure high level for requirements
        MySQL.query.await('UPDATE cm_family_progression SET level = 20 WHERE family_id = ?', { testFamId })
        if ProgressionByFamily then ProgressionByFamily[testFamId].level = 20 end

        local resH1, resH2
        local doneH1, doneH2 = false, false

        CreateThread(function()
            resH1 = PurchaseHQUpgrade(testCid1, 'storage_capacity')
            doneH1 = true
        end)
        CreateThread(function()
            resH2 = PurchaseHQUpgrade(testCid2, 'storage_capacity')
            doneH2 = true
        end)

        while not (doneH1 and doneH2) do Wait(10) end

        local tierH = MySQL.scalar.await([[
            SELECT tier FROM cm_family_hq_upgrades WHERE family_id = ? AND upgrade_key = 'storage_capacity'
        ]], { testFamId }) or 0

        local bankLogH = MySQL.scalar.await([[
            SELECT COUNT(*) FROM cm_family_bank_log WHERE family_id = ? AND category = 'hq_upgrade'
        ]], { testFamId }) or 0

        if tonumber(tierH) == 1 and tonumber(bankLogH) == 1 and ((resH1 == true and resH2 == false) or (resH1 == false and resH2 == true)) then
            print('^2[TEST H PASS] Simultaneous upgrade purchase correctly serialized: exactly 1 upgrade and 1 treasury deduction.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST H FAIL] tier=%s, bankLogCount=%s, resH1=%s, resH2=%s^7'):format(tostring(tierH), tostring(bankLogH), tostring(resH1), tostring(resH2)))
        end

        -- ============================================================
        -- TEST I: Force transaction rollback and verify treasury remains unchanged
        -- ============================================================
        print('^3[TEST I] Force atomic transaction failure and verify treasury unchanged...^7')
        local balBeforeI = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        -- Simulate a transaction where bank balance is deducted, but a subsequent query intentionally fails
        local testTx = {
            { query = 'UPDATE cm_families SET bank_balance = bank_balance - 50000 WHERE id = ?', values = { testFamId } },
            { query = 'INSERT INTO non_existent_table_for_rollback_test (col) VALUES (1)', values = {} }
        }
        local pOk, txResult = pcall(function() return MySQL.transaction.await(testTx) end)

        local balAfterI = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        if balBeforeI == balAfterI then
            print(('^2[TEST I PASS] Transaction rolled back completely: treasury balance unchanged ($%d -> $%d).^7'):format(balBeforeI, balAfterI))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST I FAIL] Treasury changed on failed transaction! Before=$%d, After=$%d^7'):format(balBeforeI, balAfterI))
        end

        print('^2============================================================^7')
        print(('^2[TEST SUITE COMPLETE] %d / %d TESTS PASSED.^7'):format(testsPassed, testsTotal))
        print('^2============================================================^7')
        end, debug.traceback)

        if not ok then
            print('^1[TEST SUITE ERROR] Unhandled error during test execution: ' .. tostring(err) .. '^7')
        end
    end)
end

RegisterCommand('run_family_hardening_tests', function(source, args, raw)
    if source ~= 0 then
        print('^1[TEST] This command can only be run from the server console.^7')
        return
    end
    RunFamilyHardeningTests()
end, false)
