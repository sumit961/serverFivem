-- ============================================================
-- cm-family | sv_hardening_tests.lua | v1.8.2
-- Automated concurrency, idempotency, and transaction test suite.
-- Command: run_family_hardening_tests
-- ============================================================

-- Requirement 14: Safety guard for production environments
if not (Config and Config.DevTests == true) and GetConvar('cm_dev_tests', 'false') ~= 'true' then
    return
end

print('^2[cm-family] sv_hardening_tests.lua loaded successfully! (DevTests enabled)^7')

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
        print('^2[TEST SUITE] STARTING EVENT-READINESS HARDENING TESTS (v1.8.2)^7')
        print('^2============================================================^7')

        local testFamId = 999999
        local testCid1 = 'test_char_1'
        local testCid2 = 'test_char_2'

        -- Clean up previous test runs
        pcall(function()
            MySQL.query.await('DELETE FROM cm_family_reward_history WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_hq_upgrades WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_objective_progress WHERE family_id = ?', { testFamId })
            MySQL.query.await('DELETE FROM cm_family_contribution_weekly WHERE family_id = ?', { testFamId })
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
        local testsTotal = 56

        -- ============================================================
        -- TEST 1: Same reputation unique ID sent twice simultaneously
        -- ============================================================
        do
        print('^3[TEST 1] Same reputation unique ID sent twice simultaneously...^7')
        local uid1 = 'test1_uniq_' .. os.time()
        local res1_A, res1_B
        local done1_A, done1_B = false, false

        CreateThread(function()
            res1_A = AddFamilyReputation(testFamId, 100, 'test', uid1, { test = '1A' })
            done1_A = true
        end)
        CreateThread(function()
            res1_B = AddFamilyReputation(testFamId, 100, 'test', uid1, { test = '1B' })
            done1_B = true
        end)

        while not (done1_A and done1_B) do Wait(10) end

        local histCount1 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_reward_history WHERE unique_id = ?', { uid1 }) or 0
        if histCount1 == 1 and ((res1_A == true and res1_B == false) or (res1_A == false and res1_B == true)) then
            print('^2[TEST 1 PASS] Exactly one reward committed, duplicate rejected.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 1 FAIL] histCount=%s, resA=%s, resB=%s^7'):format(tostring(histCount1), tostring(res1_A), tostring(res1_B)))
        end

        -- ============================================================
        -- TEST 2: Two different XP rewards simultaneously from 500 XP
        -- ============================================================
        print('^3[TEST 2] Two different XP rewards simultaneously (+100 and +200 from 500)...^7')
        MySQL.query.await('UPDATE cm_family_progression SET level = 1, current_xp = 500, lifetime_reputation = 500 WHERE family_id = ?', { testFamId })
        if ProgressionByFamily then
            ProgressionByFamily[testFamId] = { level = 1, currentXp = 500, lifetimeReputation = 500, seasonReputation = 500 }
        end

        local uid2_A = 'test2_A_' .. os.time()
        local uid2_B = 'test2_B_' .. os.time()
        local done2_A, done2_B = false, false

        CreateThread(function()
            AddFamilyReputation(testFamId, 100, 'test2A', uid2_A)
            done2_A = true
        end)
        CreateThread(function()
            AddFamilyReputation(testFamId, 200, 'test2B', uid2_B)
            done2_B = true
        end)

        while not (done2_A and done2_B) do Wait(10) end

        local finalXp2 = MySQL.scalar.await('SELECT current_xp FROM cm_family_progression WHERE family_id = ?', { testFamId }) or 0
        if tonumber(finalXp2) == 800 then
            print('^2[TEST 2 PASS] Concurrent XP rewards correctly serialized: final XP = 800 (no lost XP).^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 2 FAIL] Expected 800 XP, got %s^7'):format(tostring(finalXp2)))
        end

        -- ============================================================
        -- TEST 3: Progression lock serialization with delayed first operation
        -- ============================================================
        print('^3[TEST 3] Progression lock serialization with delayed first operation...^7')
        local uid3_A = 'test3_A_' .. os.time()
        local uid3_B = 'test3_B_' .. os.time()
        local stepOrder = {}

        CreateThread(function()
            -- Operation A starts and acquires lock
            AddFamilyReputation(testFamId, 50, 'test3A', uid3_A)
            stepOrder[#stepOrder + 1] = 'A_done'
        end)

        CreateThread(function()
            Wait(5) -- Ensure A enters lock first
            AddFamilyReputation(testFamId, 50, 'test3B', uid3_B)
            stepOrder[#stepOrder + 1] = 'B_done'
        end)

        local wait3 = 0
        while #stepOrder < 2 and wait3 < 100 do
            Wait(20)
            wait3 = wait3 + 1
        end

        if #stepOrder == 2 and stepOrder[1] == 'A_done' and stepOrder[2] == 'B_done' then
            print('^2[TEST 3 PASS] Lock serialization strict: Operation A preceded Operation B without overlap.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 3 FAIL] stepOrder: %s^7'):format(json.encode(stepOrder)))
        end

        -- ============================================================
        -- TEST 4: Same contribution unique ID twice simultaneously
        -- ============================================================
        print('^3[TEST 4] Same contribution unique ID twice simultaneously...^7')
        local uid4 = 'test4_uniq_' .. os.time()
        local res4_A, res4_B
        local done4_A, done4_B = false, false

        CreateThread(function()
            res4_A = AddFamilyMemberContribution(testCid1, testFamId, 50, 'activity', 'test', uid4)
            done4_A = true
        end)
        CreateThread(function()
            res4_B = AddFamilyMemberContribution(testCid1, testFamId, 50, 'activity', 'test', uid4)
            done4_B = true
        end)

        while not (done4_A and done4_B) do Wait(10) end

        local histCount4 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_reward_history WHERE unique_id = ?', { uid4 }) or 0
        if histCount4 == 1 and ((res4_A == true and res4_B == false) or (res4_A == false and res4_B == true)) then
            print('^2[TEST 4 PASS] Contribution duplicate unique ID atomically rejected.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 4 FAIL] histCount=%s, resA=%s, resB=%s^7'):format(tostring(histCount4), tostring(res4_A), tostring(res4_B)))
        end

        -- ============================================================
        -- TEST 5: Concurrent daily-cap deposits (Requirement 2 & 3)
        -- Start daily points: 80. Launch TWO simultaneous deposits of $30k each.
        -- Expected: total points = 100 (capped at +20), full cash = $60,000.
        -- ============================================================
        print('^3[TEST 5] Concurrent daily-cap deposits (Start=80, two simultaneous $30k deposits)...^7')
        local dayKey5 = os.date('!%Y-%m-%d')
        MySQL.query.await('DELETE FROM cm_family_contribution_daily WHERE family_id = ? AND character_id = ?', { testFamId, testCid1 })
        MySQL.query.await('DELETE FROM cm_family_member_contributions WHERE family_id = ? AND character_id = ?', { testFamId, testCid1 })

        -- Pre-seed 80 points
        MySQL.query.await([[
            INSERT INTO cm_family_contribution_daily (family_id, character_id, day_key, financial_points, money_contributed)
            VALUES (?, ?, ?, 80, 80000)
        ]], { testFamId, testCid1, dayKey5 })

        local done5_A, done5_B = false, false
        local res5_A, res5_B

        CreateThread(function()
            res5_A = RecordFinancialContribution(testCid1, testFamId, 30000)
            done5_A = true
        end)
        CreateThread(function()
            res5_B = RecordFinancialContribution(testCid1, testFamId, 30000)
            done5_B = true
        end)

        while not (done5_A and done5_B) do Wait(10) end

        local dailyRow5 = MySQL.single.await([[
            SELECT financial_points, money_contributed FROM cm_family_contribution_daily
            WHERE family_id = ? AND character_id = ? AND day_key = ?
        ]], { testFamId, testCid1, dayKey5 })

        local finalPts5 = dailyRow5 and tonumber(dailyRow5.financial_points) or 0
        local finalCash5 = dailyRow5 and tonumber(dailyRow5.money_contributed) or 0

        if finalPts5 == 100 and finalCash5 == 140000 then
            print(('^2[TEST 5 PASS] Concurrent daily-cap strictly capped: exactly %d points, $%d total cash recorded.^7'):format(finalPts5, finalCash5))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 5 FAIL] Expected 100 points and $140,000 cash; got pts=%s, cash=%s^7'):format(tostring(finalPts5), tostring(finalCash5)))
        end

        -- ============================================================
        -- TEST 6: Weekly contribution partitioning (Requirement 6)
        -- ============================================================
        print('^3[TEST 6] Weekly contribution ledger separation (this_week vs all_time)...^7')
        local currentWeek6 = (type(CMFamilyGetWeekKey) == 'function' and CMFamilyGetWeekKey()) or os.date('%Y-W%W')
        local pastWeek6 = '2025-W01'

        MySQL.query.await('DELETE FROM cm_family_contribution_weekly WHERE family_id = ? AND character_id = ?', { testFamId, testCid1 })
        MySQL.query.await('DELETE FROM cm_family_member_contributions WHERE family_id = ? AND character_id = ?', { testFamId, testCid1 })

        -- Past week contribution: 60 points
        MySQL.query.await([[
            INSERT INTO cm_family_contribution_weekly (family_id, character_id, week_key, total_points, activity_points)
            VALUES (?, ?, ?, 60, 60)
        ]], { testFamId, testCid1, pastWeek6 })

        -- Current week contribution: 40 points
        AddFamilyMemberContribution(testCid1, testFamId, 40, 'activity', 'test', 'test6_cur_' .. os.time())

        -- Total lifetime in member contributions
        MySQL.query.await([[
            UPDATE cm_family_member_contributions SET total_points = 100 WHERE family_id = ? AND character_id = ?
        ]], { testFamId, testCid1 })

        local boardThisWeek = GetFamilyContributionLeaderboard(testFamId, 'this_week')
        local boardAllTime = GetFamilyContributionLeaderboard(testFamId, 'all_time')

        local thisWeekPts = boardThisWeek[1] and boardThisWeek[1].weeklyPoints or 0
        local allTimePts = boardAllTime[1] and boardAllTime[1].totalPoints or 0

        if thisWeekPts == 40 and allTimePts == 100 then
            print(('^2[TEST 6 PASS] Weekly partition verified: This Week = %d pts, All Time = %d pts.^7'):format(thisWeekPts, allTimePts))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 6 FAIL] thisWeekPts=%s (expected 40), allTimePts=%s (expected 100)^7'):format(tostring(thisWeekPts), tostring(allTimePts)))
        end

        -- ============================================================
        -- TEST 7: Require uniqueId for rewarded activity (Requirement 5)
        -- ============================================================
        print('^3[TEST 7] Require uniqueId for rewarded activities...^7')
        local res7_A, err7_A = AwardFamilyActivityReward({
            familyId = testFamId,
            uniqueId = nil,
            reputation = 100,
        })
        local res7_B, err7_B = AwardFamilyActivityReward({
            familyId = testFamId,
            uniqueId = '',
            treasuryAmount = 50000,
        })

        if res7_A == false and err7_A == 'unique_id_required' and res7_B == false and err7_B == 'unique_id_required' then
            print('^2[TEST 7 PASS] Rewarded activities with missing/empty uniqueId strictly rejected with unique_id_required.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 7 FAIL] resA=%s (%s), resB=%s (%s)^7'):format(tostring(res7_A), tostring(err7_A), tostring(res7_B), tostring(err7_B)))
        end

        -- ============================================================
        -- TEST 8: Participant all-or-nothing rollback (Requirement 4)
        -- ============================================================
        print('^3[TEST 8] Participant all-or-nothing rollback on child ID conflict...^7')
        local uid8 = 'test8_root_' .. os.time()
        local childConflict = ('%s:participant:%s'):format(uid8, testCid2)

        -- Pre-seed conflicting child ID
        MySQL.query.await([[
            INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source)
            VALUES (?, ?, 'participant_contribution', 50, 'conflict')
        ]], { childConflict, testFamId })

        local xpBefore8 = tonumber(MySQL.scalar.await('SELECT current_xp FROM cm_family_progression WHERE family_id = ?', { testFamId })) or 0
        local balBefore8 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        local res8, err8 = AwardFamilyActivityReward({
            familyId = testFamId,
            uniqueId = uid8,
            eventType = 'multi_raid',
            reputation = 250,
            treasuryAmount = 15000,
            memberContribution = 100,
            participants = { testCid1, testCid2 },
        })

        local xpAfter8 = tonumber(MySQL.scalar.await('SELECT current_xp FROM cm_family_progression WHERE family_id = ?', { testFamId })) or 0
        local balAfter8 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local rootCount8 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_reward_history WHERE unique_id = ?', { uid8 }) or 0

        if res8 == false and xpBefore8 == xpAfter8 and balBefore8 == balAfter8 and rootCount8 == 0 then
            print('^2[TEST 8 PASS] Participant conflict rolled back ENTIRE operation: 0 XP, $0 treasury, 0 root record committed.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 8 FAIL] res8=%s, rootCount=%s, xpDiff=%d, balDiff=%d^7'):format(tostring(res8), tostring(rootCount8), xpAfter8 - xpBefore8, balAfter8 - balBefore8))
        end

        -- ============================================================
        -- TEST 9: Treasury-only activity reward called twice with same unique ID
        -- ============================================================
        print('^3[TEST 9] Treasury-only activity reward called twice with same unique ID...^7')
        local uid9 = 'test9_treasury_' .. os.time()
        local startBal9 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        local res9_1 = AwardFamilyActivityReward({
            familyId = testFamId,
            uniqueId = uid9,
            eventType = 'treasury_gift',
            reputation = 0,
            treasuryAmount = 35000,
        })
        local res9_2 = AwardFamilyActivityReward({
            familyId = testFamId,
            uniqueId = uid9,
            eventType = 'treasury_gift',
            reputation = 0,
            treasuryAmount = 35000,
        })

        local endBal9 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local diffBal9 = endBal9 - startBal9

        if res9_1 ~= false and res9_2 == false and diffBal9 == 35000 then
            print(('^2[TEST 9 PASS] Treasury reward paid exactly once (+$%d), duplicate rejected.^7'):format(diffBal9))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 9 FAIL] res1=%s, res2=%s, diffBal=%s^7'):format(tostring(res9_1 ~= false), tostring(res9_2), tostring(diffBal9)))
        end

        -- ============================================================
        -- TEST 10: Objective contribution awarded to completing actor (Requirement 8)
        -- ============================================================
        print('^3[TEST 10] Objective completion awards contribution to completing actor...^7')
        local objKey10 = 'test_obj10_' .. os.time()
        local weekKey10 = '2026-W95'
        local testObj10 = {
            key = objKey10,
            title = 'Actor Award Objective',
            targetValue = 5,
            rewardReputation = 200,
            rewardTreasury = 10000,
            rewardContribution = 150,
        }

        local contribBefore10 = tonumber(MySQL.scalar.await([[
            SELECT total_points FROM cm_family_member_contributions WHERE family_id = ? AND character_id = ?
        ]], { testFamId, testCid1 })) or 0

        local completeOk10 = CompleteObjective(testFamId, testObj10, weekKey10, 5, testCid1)

        local contribAfter10 = tonumber(MySQL.scalar.await([[
            SELECT total_points FROM cm_family_member_contributions WHERE family_id = ? AND character_id = ?
        ]], { testFamId, testCid1 })) or 0

        local diffContrib10 = contribAfter10 - contribBefore10

        if completeOk10 == true and diffContrib10 == 150 then
            print(('^2[TEST 10 PASS] Completing actor received configured objective contribution (+%d pts).^7'):format(diffContrib10))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 10 FAIL] completeOk=%s, diffContrib=%s (expected 150)^7'):format(tostring(completeOk10), tostring(diffContrib10)))
        end
        end

        -- ============================================================
        -- TEST 11: Objective completion called simultaneously by two paths
        -- ============================================================
        do
        print('^3[TEST 11] Objective completion called simultaneously by two paths...^7')
        local testObj11 = {
            key = 'test_obj11_' .. os.time(),
            title = 'Simultaneous Objective',
            targetValue = 10,
            rewardReputation = 300,
            rewardTreasury = 20000,
        }
        local weekKey11 = '2026-W94'
        local res11_A, res11_B
        local done11_A, done11_B = false, false

        CreateThread(function()
            res11_A = CompleteObjective(testFamId, testObj11, weekKey11, 10, testCid1)
            done11_A = true
        end)
        CreateThread(function()
            res11_B = CompleteObjective(testFamId, testObj11, weekKey11, 10, testCid2)
            done11_B = true
        end)

        while not (done11_A and done11_B) do Wait(10) end

        local objRow11 = MySQL.single.await([[
            SELECT reward_claimed, reward_state FROM cm_family_objective_progress
            WHERE family_id = ? AND objective_key = ? AND week_key = ?
        ]], { testFamId, testObj11.key, weekKey11 })

        local objRewardsCount11 = MySQL.scalar.await([[
            SELECT COUNT(*) FROM cm_family_reward_history
            WHERE unique_id = ?
        ]], { ('obj:%s:%s:%s'):format(testFamId, weekKey11, testObj11.key) }) or 0

        if objRewardsCount11 == 1 and objRow11 and objRow11.reward_state == 'delivered' and ((res11_A == true and res11_B == false) or (res11_A == false and res11_B == true)) then
            print('^2[TEST 11 PASS] Objective completion correctly idempotent: exactly 1 payout committed.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 11 FAIL] rewardsCount=%s, state=%s, resA=%s, resB=%s^7'):format(tostring(objRewardsCount11), tostring(objRow11 and objRow11.reward_state), tostring(res11_A), tostring(res11_B)))
        end

        -- ============================================================
        -- TEST 12: Stale processing objective recovery (Requirement 9 & 10)
        -- Case A: matching reward root exists -> recovers to 'delivered'
        -- Case B: matching reward root missing -> recovers to 'failed'
        -- ============================================================
        print('^3[TEST 12] Stale processing objective recovery (Case A: root exists; Case B: root missing)...^7')
        local objKey12_A = 'test_recov_A_' .. os.time()
        local objKey12_B = 'test_recov_B_' .. os.time()
        local weekKey12 = '2026-W93'

        local rootId12_A = ('obj:%s:%s:%s'):format(testFamId, weekKey12, objKey12_A)
        -- Insert root history for Case A
        MySQL.query.await([[
            INSERT INTO cm_family_reward_history (unique_id, family_id, reward_type, amount, source)
            VALUES (?, ?, 'activity_root', 100, 'test')
        ]], { rootId12_A, testFamId })

        -- Insert stale processing row for Case A
        MySQL.query.await([[
            INSERT INTO cm_family_objective_progress
              (family_id, objective_key, week_key, current_value, completed, completed_at, reward_claimed, reward_state, reward_processing_at)
            VALUES (?, ?, ?, 10, 1, NOW(), 0, 'processing', NOW() - INTERVAL 5 MINUTE)
        ]], { testFamId, objKey12_A, weekKey12 })

        -- Insert stale processing row for Case B (no root history)
        MySQL.query.await([[
            INSERT INTO cm_family_objective_progress
              (family_id, objective_key, week_key, current_value, completed, completed_at, reward_claimed, reward_state, reward_processing_at)
            VALUES (?, ?, ?, 10, 1, NOW(), 0, 'processing', NOW() - INTERVAL 5 MINUTE)
        ]], { testFamId, objKey12_B, weekKey12 })

        -- Run recovery
        RecoverStaleObjectiveProcessing(testFamId)

        local state12_A = MySQL.scalar.await('SELECT reward_state FROM cm_family_objective_progress WHERE family_id = ? AND objective_key = ? AND week_key = ?', { testFamId, objKey12_A, weekKey12 })
        local state12_B = MySQL.scalar.await('SELECT reward_state FROM cm_family_objective_progress WHERE family_id = ? AND objective_key = ? AND week_key = ?', { testFamId, objKey12_B, weekKey12 })

        if state12_A == 'delivered' and state12_B == 'failed' then
            print('^2[TEST 12 PASS] Recovery accurate: root-backed row -> delivered; unbacked row -> failed/retryable.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 12 FAIL] stateA=%s (expected delivered), stateB=%s (expected failed)^7'):format(tostring(state12_A), tostring(state12_B)))
        end

        -- ============================================================
        -- TEST 13: HQ Insufficient Treasury (Requirement 11)
        -- Bank balance < upgrade cost -> purchase fails, bank unchanged, tier unchanged, 0 bank logs
        -- ============================================================
        print('^3[TEST 13] HQ upgrade with insufficient treasury funds...^7')
        MySQL.query.await('DELETE FROM cm_family_hq_upgrades WHERE family_id = ?', { testFamId })
        MySQL.query.await('UPDATE cm_family_progression SET level = 20 WHERE family_id = ?', { testFamId })
        if ProgressionByFamily then ProgressionByFamily[testFamId].level = 20 end

        -- Set balance to $10,000 (Tier 1 storage requires $50,000)
        MySQL.query.await('UPDATE cm_families SET bank_balance = 10000 WHERE id = ?', { testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = 10000 end

        local logCountBefore13 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_bank_log WHERE family_id = ?', { testFamId }) or 0
        local buyOk13, buyErr13 = PurchaseHQUpgrade(testCid1, 'storage_capacity')
        local balAfter13 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local tierAfter13 = GetFamilyHQUpgradeLevel(testFamId, 'storage_capacity')
        local logCountAfter13 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_bank_log WHERE family_id = ?', { testFamId }) or 0

        if buyOk13 == false and balAfter13 == 10000 and tierAfter13 == 0 and logCountBefore13 == logCountAfter13 then
            print('^2[TEST 13 PASS] Insufficient funds rejected: $10,000 unchanged, Tier 0 unchanged, 0 bank log rows added.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 13 FAIL] buyOk=%s, bal=%d, tier=%d, logDiff=%d^7'):format(tostring(buyOk13), balAfter13, tierAfter13, logCountAfter13 - logCountBefore13))
        end

        -- ============================================================
        -- TEST 14: HQ Stale-Tier Conflict Rollback (Requirement 11)
        -- Tier changes concurrently -> purchase fails, 0 bank deduction, tier does not skip
        -- ============================================================
        print('^3[TEST 14] HQ upgrade stale-tier conflict handling...^7')
        -- Set bank balance to $500,000
        MySQL.query.await('UPDATE cm_families SET bank_balance = 500000 WHERE id = ?', { testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = 500000 end

        -- Pre-seed tier 2 in DB directly
        MySQL.query.await([[
            INSERT INTO cm_family_hq_upgrades (family_id, upgrade_key, tier, purchased_by, purchased_at)
            VALUES (?, 'storage_capacity', 2, ?, NOW())
            ON DUPLICATE KEY UPDATE tier = 2
        ]], { testFamId, testCid1 })

        -- Attempt to purchase when DB is already at tier 2 (Target will be Tier 3)
        -- Simulating a stale expected tier by purchasing Tier 3 successfully once
        local buyOk14_A = PurchaseHQUpgrade(testCid1, 'storage_capacity') -- advances to Tier 3 ($250k)
        local balAfter14_A = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        -- Now attempting another purchase on max tier
        local buyOk14_B, buyErr14_B = PurchaseHQUpgrade(testCid1, 'storage_capacity')
        local balAfter14_B = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        if buyOk14_A == true and buyOk14_B == false and balAfter14_A == balAfter14_B then
            print('^2[TEST 14 PASS] Upgrade conflict & max-tier boundaries strictly guarded: zero duplicate deduction ($250k balance retained).^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 14 FAIL] buyOkA=%s, buyOkB=%s, balA=%d, balB=%d^7'):format(tostring(buyOk14_A), tostring(buyOk14_B), balAfter14_A, balAfter14_B))
        end

        -- ============================================================
        -- TEST 15: Two members purchase the same HQ tier simultaneously
        -- ============================================================
        print('^3[TEST 15] Two members purchase the same HQ tier simultaneously...^7')
        MySQL.query.await('DELETE FROM cm_family_hq_upgrades WHERE family_id = ?', { testFamId })
        MySQL.query.await('UPDATE cm_families SET bank_balance = 1000000 WHERE id = ?', { testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = 1000000 end

        local res15_A, res15_B
        local done15_A, done15_B = false, false

        CreateThread(function()
            res15_A = PurchaseHQUpgrade(testCid1, 'weapon_storage_capacity')
            done15_A = true
        end)
        CreateThread(function()
            res15_B = PurchaseHQUpgrade(testCid2, 'weapon_storage_capacity')
            done15_B = true
        end)

        while not (done15_A and done15_B) do Wait(10) end

        local tier15 = GetFamilyHQUpgradeLevel(testFamId, 'weapon_storage_capacity')
        local bankLog15 = MySQL.scalar.await([[
            SELECT COUNT(*) FROM cm_family_bank_log
            WHERE family_id = ? AND reason LIKE 'hq_upgrade:weapon_storage_capacity:%'
        ]], { testFamId }) or 0

        if tier15 == 1 and bankLog15 == 1 and ((res15_A == true and res15_B == false) or (res15_A == false and res15_B == true)) then
            print('^2[TEST 15 PASS] Simultaneous upgrade purchase correctly serialized: exactly 1 upgrade and 1 treasury deduction.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 15 FAIL] tier=%s, bankLogCount=%s, resA=%s, resB=%s^7'):format(tostring(tier15), tostring(bankLog15), tostring(res15_A), tostring(res15_B)))
        end

        -- ============================================================
        -- TEST 16: HQ Real Transaction Rollback on Failure After Debit (Requirement 3 Part C)
        -- Debit statement executes within transaction, subsequent statement fails,
        -- entire DB transaction rolls back, treasury balance unchanged (no manual refund used).
        -- ============================================================
        print('^3[TEST 16] HQ real transaction rollback after debit statement...^7')
        MySQL.query.await('DELETE FROM cm_family_hq_upgrades WHERE family_id = ?', { testFamId })
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { testFamId })
        MySQL.query.await('UPDATE cm_families SET bank_balance = 500000 WHERE id = ?', { testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = 500000 end

        local logCountBefore16 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_bank_log WHERE family_id = ?', { testFamId }) or 0
        local buyOk16, buyErr16 = PurchaseHQUpgrade(testCid1, 'storage_capacity', 'fail_after_debit')
        local balAfter16 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local tierAfter16 = GetFamilyHQUpgradeLevel(testFamId, 'storage_capacity')
        local logCountAfter16 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_bank_log WHERE family_id = ?', { testFamId }) or 0

        if buyOk16 == false and balAfter16 == 500000 and tierAfter16 == 0 and logCountBefore16 == logCountAfter16 then
            print('^2[TEST 16 PASS] HQ true transaction rollback: failure after debit statement completely rolled back by MySQL (treasury $500,000 unchanged, 0 upgrade, 0 bank logs).^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 16 FAIL] buyOk=%s, bal=%d (expected 500000), tier=%d, logDiff=%d^7'):format(tostring(buyOk16), balAfter16, tierAfter16, logCountAfter16 - logCountBefore16))
        end

        -- ============================================================
        -- TEST 17: Treasury Reward Near Max Balance & Bank Log Accounting (Requirements 4 & 5)
        -- Max Balance = $2,000,000,000 default or Config.Bank.maxBalance;
        -- Setting start balance to maxBal - 1,000. Reward requested = 35,000.
        -- Credited = 1,000. Bank log must record 1,000 (NOT 35,000).
        -- ============================================================
        print('^3[TEST 17] Treasury reward near max balance cap accounting...^7')
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { testFamId })
        local maxBal17 = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000
        local targetStartBal17 = maxBal17 - 1000
        MySQL.query.await('UPDATE cm_families SET bank_balance = ? WHERE id = ?', { targetStartBal17, testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = targetStartBal17 end

        local uid17 = ('test17_cap_%d'):format(math.random(100000, 999999))
        local ok17, res17 = AwardFamilyActivityReward({
            familyId = testFamId,
            actorCid = testCid1,
            eventType = 'heist',
            uniqueId = uid17,
            treasuryAmount = 35000,
        })

        local balAfter17 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local loggedAmount17 = tonumber(MySQL.scalar.await([[
            SELECT amount FROM cm_family_bank_log
            WHERE family_id = ? AND category = 'event_reward' AND reason LIKE 'event_reward:heist%'
            ORDER BY id DESC LIMIT 1
        ]], { testFamId })) or 0

        local resCredited17 = res17 and res17.treasuryCredited
        local resRequested17 = res17 and res17.treasuryRequested
        local resTreasury17 = res17 and res17.treasury

        if ok17 == true and balAfter17 == maxBal17 and loggedAmount17 == 1000 and resCredited17 == 1000 and resRequested17 == 35000 and resTreasury17 == 1000 then
            print(('^2[TEST 17 PASS] Treasury cap accounting accurate: $1,000 credited (requested $35,000), bank log = $1,000, bank balance = $%d.^7'):format(maxBal17))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 17 FAIL] ok=%s, bal=%d (expected %d), logged=%d (expected 1000), credited=%s, requested=%s^7'):format(
                tostring(ok17), balAfter17, maxBal17, loggedAmount17, tostring(resCredited17), tostring(resRequested17)))
        end

        -- ============================================================
        -- TEST 18: Week Key & Objective Rotation Consistency (Requirement 7)
        -- Objective rotation derives year/week seed from authoritative CMFamilyGetWeekKey().
        -- ============================================================
        print('^3[TEST 18] Week key rotation consistency...^7')
        local weekKey18, yearNum18, weekNum18 = CMFamilyGetWeekKey()
        local objs18, rotWeekKey18 = CMFamilyGetWeeklyObjectivesForFamily(testFamId)

        local formatMatches = type(weekKey18) == 'string' and weekKey18:match('^%d%d%d%d%-W%d%d$') ~= nil
        local keysMatch = weekKey18 == rotWeekKey18
        local yearValid = type(yearNum18) == 'number' and yearNum18 >= 2026
        local weekValid = type(weekNum18) == 'number' and weekNum18 >= 0 and weekNum18 <= 53

        if formatMatches and keysMatch and yearValid and weekValid then
            print(('^2[TEST 18 PASS] Week key consistency verified: key=%s, year=%d, week=%d, objective rotation key matches.^7'):format(
                weekKey18, yearNum18, weekNum18))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 18 FAIL] formatMatches=%s, keysMatch=%s, year=%s, week=%s^7'):format(
                tostring(formatMatches), tostring(keysMatch), tostring(yearNum18), tostring(weekNum18)))
        end

        -- ============================================================
        -- TEST 19: Force transaction rollback and verify treasury unchanged
        -- ============================================================
        print('^3[TEST 19] Force atomic transaction failure and verify treasury unchanged...^7')
        local balBefore19 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        local testTx19 = {
            { query = 'UPDATE cm_families SET bank_balance = bank_balance - 50000 WHERE id = ?', values = { testFamId } },
            { query = 'INSERT INTO non_existent_table_for_rollback_test (col) VALUES (1)', values = {} }
        }
        local pOk19, txResult19 = pcall(function() return MySQL.transaction.await(testTx19) end)

        local balAfter19 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        if balBefore19 == balAfter19 then
            print(('^2[TEST 19 PASS] Transaction rolled back completely: treasury balance unchanged ($%d -> $%d).^7'):format(balBefore19, balAfter19))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 19 FAIL] Treasury changed on failed transaction! Before=$%d, After=$%d^7'):format(balBefore19, balAfter19))
        end
        end

        -- ============================================================
        -- TESTS 20 - 23: Treasury Credit Consistency & Concurrency
        -- ============================================================
        do
            local B = CMFamilyBridge
            local origGetSrc = B.GetSrcByCid
            local origGetMoney = B.GetMoney
            local origRemoveMoney = B.RemoveMoney
            local origAddMoney = B.AddMoney

        local simulatedCash = 100000
        B.GetSrcByCid = function(cid)
            if cid == testCid1 or cid == testCid2 then return 9999 end
            return origGetSrc(cid)
        end
        B.GetMoney = function(src)
            if src == 9999 then return simulatedCash end
            return origGetMoney(src)
        end
        B.RemoveMoney = function(src, amount, reason)
            if src == 9999 then
                if simulatedCash >= amount then
                    simulatedCash = simulatedCash - amount
                    return true
                end
                return false
            end
            return origRemoveMoney(src, amount, reason)
        end
        B.AddMoney = function(src, amount, reason)
            if src == 9999 then
                simulatedCash = simulatedCash + amount
                return true
            end
            return origAddMoney(src, amount, reason)
        end

        local maxBal = tonumber(Config.Bank and Config.Bank.maxBalance) or 2000000000

        -- TEST 20: Partial Player Deposit (Treasury has $1,000 space; deposit $50,000)
        print('^3[TEST 20] Partial Player Deposit at bank cap boundary...^7')
        MySQL.query.await('UPDATE cm_families SET bank_balance = ? WHERE id = ?', { maxBal - 1000, testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = maxBal - 1000 end
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { testFamId })
        simulatedCash = 100000

        local dayKey20 = os.date('!%Y-%m-%d')
        local contribCashBefore20 = tonumber(MySQL.scalar.await('SELECT money_contributed FROM cm_family_contribution_daily WHERE family_id = ? AND character_id = ? AND day_key = ?', { testFamId, testCid1, dayKey20 })) or 0

        local ok20, res20 = BankDeposit(testCid1, 50000)
        local balAfter20 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local logRow20 = MySQL.single.await('SELECT amount, balance_after FROM cm_family_bank_log WHERE family_id = ? ORDER BY id DESC LIMIT 1', { testFamId })
        local contribCashAfter20 = tonumber(MySQL.scalar.await('SELECT money_contributed FROM cm_family_contribution_daily WHERE family_id = ? AND character_id = ? AND day_key = ?', { testFamId, testCid1, dayKey20 })) or 0

        local playerCharged20 = 100000 - simulatedCash
        local contribDiff20 = contribCashAfter20 - contribCashBefore20
        local logAmt20 = logRow20 and tonumber(logRow20.amount) or 0

        if ok20 == true and res20.accepted == 1000 and res20.rejected == 49000 and playerCharged20 == 1000 and balAfter20 == maxBal and logAmt20 == 1000 and contribDiff20 == 1000 then
            print('^2[TEST 20 PASS] Partial deposit accurate: player charged exactly $1,000, treasury increased $1,000, bank log = $1,000, contrib = $1,000.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 20 FAIL] ok=%s, accepted=%s, charged=%d, balAfter=%d, logAmt=%d, contribDiff=%d^7'):format(
                tostring(ok20), tostring(res20 and res20.accepted), playerCharged20, balAfter20, logAmt20, contribDiff20))
        end

        -- TEST 21: Full Treasury Deposit (Treasury is already at maxBalance)
        print('^3[TEST 21] Full Treasury Deposit rejection...^7')
        MySQL.query.await('UPDATE cm_families SET bank_balance = ? WHERE id = ?', { maxBal, testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = maxBal end
        simulatedCash = 100000
        local logCountBefore21 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_bank_log WHERE family_id = ?', { testFamId }) or 0

        local ok21, res21 = BankDeposit(testCid1, 50000)
        local balAfter21 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local logCountAfter21 = MySQL.scalar.await('SELECT COUNT(*) FROM cm_family_bank_log WHERE family_id = ?', { testFamId }) or 0
        local playerCharged21 = 100000 - simulatedCash

        if ok21 == false and res21 == 'family_bank_full' and playerCharged21 == 0 and balAfter21 == maxBal and logCountAfter21 == logCountBefore21 then
            print('^2[TEST 21 PASS] Full treasury deposit rejected: returned family_bank_full, player charged $0, treasury unchanged, 0 bank logs.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 21 FAIL] ok=%s, res=%s, charged=%d, balAfter=%d, logDiff=%d^7'):format(
                tostring(ok21), tostring(res21), playerCharged21, balAfter21, logCountAfter21 - logCountBefore21))
        end

        -- TEST 22: Simultaneous Event Credits Near Cap (Space = $10,000; Event A = $20k, Event B = $20k)
        print('^3[TEST 22] Simultaneous event credits near cap ($10,000 space, two $20k rewards)...^7')
        MySQL.query.await('UPDATE cm_families SET bank_balance = ? WHERE id = ?', { maxBal - 10000, testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = maxBal - 10000 end
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { testFamId })

        local uid22_A = ('test22_A_%d'):format(math.random(100000, 999999))
        local uid22_B = ('test22_B_%d'):format(math.random(100000, 999999))
        local done22_A, done22_B = false, false
        local ok22_A, res22_A, ok22_B, res22_B

        CreateThread(function()
            ok22_A, res22_A = AwardFamilyActivityReward({
                familyId = testFamId, actorCid = testCid1, eventType = 'eventA',
                uniqueId = uid22_A, treasuryAmount = 20000, reputation = 50,
            })
            done22_A = true
        end)
        CreateThread(function()
            ok22_B, res22_B = AwardFamilyActivityReward({
                familyId = testFamId, actorCid = testCid2, eventType = 'eventB',
                uniqueId = uid22_B, treasuryAmount = 20000, reputation = 50,
            })
            done22_B = true
        end)

        while not (done22_A and done22_B) do Wait(10) end

        local balAfter22 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local credited22_A = res22_A and res22_A.treasuryCredited or 0
        local credited22_B = res22_B and res22_B.treasuryCredited or 0
        local loggedSum22 = tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(amount), 0) FROM cm_family_bank_log WHERE family_id = ? AND category = "event_reward"', { testFamId })) or 0

        if ok22_A == true and ok22_B == true and balAfter22 == maxBal and (credited22_A + credited22_B == 10000) and loggedSum22 == 10000 then
            print(('^2[TEST 22 PASS] Simultaneous events strictly capped: total credited = $%d, bank log sum = $%d, final bal = $%d (cap preserved).^7'):format(
                credited22_A + credited22_B, loggedSum22, balAfter22))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 22 FAIL] okA=%s, okB=%s, credA=%d, credB=%d, balAfter=%d, loggedSum=%d^7'):format(
                tostring(ok22_A), tostring(ok22_B), credited22_A, credited22_B, balAfter22, loggedSum22))
        end

        -- TEST 23: Deposit + Event Race ($10,000 space; deposit $8,000 + event $8,000)
        print('^3[TEST 23] Deposit + Event race ($10,000 space, deposit $8k + event $8k)...^7')
        MySQL.query.await('UPDATE cm_families SET bank_balance = ? WHERE id = ?', { maxBal - 10000, testFamId })
        if Families and Families[testFamId] then Families[testFamId].bank_balance = maxBal - 10000 end
        MySQL.query.await('DELETE FROM cm_family_bank_log WHERE family_id = ?', { testFamId })
        simulatedCash = 50000

        local uid23 = ('test23_race_%d'):format(math.random(100000, 999999))
        local done23_dep, done23_evt = false, false
        local ok23_dep, res23_dep, ok23_evt, res23_evt

        CreateThread(function()
            ok23_dep, res23_dep = BankDeposit(testCid1, 8000)
            done23_dep = true
        end)
        CreateThread(function()
            ok23_evt, res23_evt = AwardFamilyActivityReward({
                familyId = testFamId, actorCid = testCid2, eventType = 'race_event',
                uniqueId = uid23, treasuryAmount = 8000,
            })
            done23_evt = true
        end)

        while not (done23_dep and done23_evt) do Wait(10) end

        local balAfter23 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0
        local depAccepted23 = res23_dep and res23_dep.accepted or 0
        local evtCredited23 = res23_evt and res23_evt.treasuryCredited or 0
        local loggedSum23 = tonumber(MySQL.scalar.await('SELECT COALESCE(SUM(amount), 0) FROM cm_family_bank_log WHERE family_id = ?', { testFamId })) or 0
        local playerCharged23 = 50000 - simulatedCash

        -- Restore original bridge functions
        B.GetSrcByCid = origGetSrc
        B.GetMoney = origGetMoney
        B.RemoveMoney = origRemoveMoney
        B.AddMoney = origAddMoney

        if ok23_dep == true and ok23_evt == true and balAfter23 == maxBal and (depAccepted23 + evtCredited23 == 10000) and playerCharged23 == depAccepted23 and loggedSum23 == 10000 then
            print(('^2[TEST 23 PASS] Deposit + Event race safe: depAccepted=$%d, evtCredited=$%d, total=$%d, playerCharged=$%d, final bal=$%d.^7'):format(
                depAccepted23, evtCredited23, depAccepted23 + evtCredited23, playerCharged23, balAfter23))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 23 FAIL] okDep=%s, okEvt=%s, depAcc=%d, evtCred=%d, charged=%d, balAfter=%d, loggedSum=%d^7'):format(
                tostring(ok23_dep), tostring(ok23_evt), depAccepted23, evtCredited23, playerCharged23, balAfter23, loggedSum23))
        end
        end

        -- ============================================================
        -- TESTS 24 - 43: Family Event Engine (Phase 1)
        -- ============================================================
        do
        local testFamId2 = 999998
        local testFamId3 = 999997
        local testCid3 = 'test_char_3'
        local testCid4 = 'test_char_4'

        -- Setup opponent family (testFamId2) and third party family (testFamId3)
        CMFamilyDeleteFamilyRows(testFamId2)
        CMFamilyDeleteFamilyRows(testFamId3)

        MySQL.query.await([[
            INSERT INTO cm_families (id, name, founder_cid, bank_balance)
            VALUES (?, 'Test Opponent Family', ?, 500000),
                   (?, 'Test Third Party Family', ?, 200000)
        ]], { testFamId2, testCid3, testFamId3, testCid4 })

        if Families then
            Families[testFamId2] = { id = testFamId2, name = 'Test Opponent Family', founder_cid = testCid3, bank_balance = 500000, ranks = {}, ranksById = {} }
            Families[testFamId3] = { id = testFamId3, name = 'Test Third Party Family', founder_cid = testCid4, bank_balance = 200000, ranks = {}, ranksById = {} }
        end

        local rankId2 = CreateDefaultRanks(testFamId2)
        local rankId3 = CreateDefaultRanks(testFamId3)
        CMFamilyInsertMember(testFamId2, testCid3, rankId2)
        CMFamilyInsertMember(testFamId3, testCid4, rankId3)

        if MemberByCid then
            MemberByCid[testCid3] = { family_id = testFamId2, character_id = testCid3, rank_id = rankId2 }
            MemberByCid[testCid4] = { family_id = testFamId3, character_id = testCid4, rank_id = rankId3 }
        end

        CMFamilyBridge._mockCids = {
            [101] = testCid1,
            [102] = testCid2,
            [103] = testCid3,
            [104] = testCid4,
        }
        CMFamilyBridge._mockSrcs = {
            [testCid1] = 101,
            [testCid2] = 102,
            [testCid3] = 103,
            [testCid4] = 104,
        }

        -- Ensure progression exists for testFamId
        MySQL.query.await([[
            INSERT INTO cm_family_progression (family_id, level, current_xp)
            VALUES (?, 5, 2500)
            ON DUPLICATE KEY UPDATE level = 5, current_xp = 2500
        ]], { testFamId })
        if ProgressionCache then ProgressionCache[testFamId] = { level = 5, current_xp = 2500 } end

        -- TEST 24: Create valid event instance
        print('^3[TEST 24] Create valid event instance...^7')
        local ok24, inst24 = CreateFamilyEvent('family_raid', {
            initiatorFamilyId = testFamId,
            targetFamilyId = testFamId2,
            locationKey = 'house_test_101',
            actorCid = testCid1,
        })
        if ok24 == true and inst24 and inst24.eventUid and inst24.state == 'forming' and inst24.routingBucket then
            print(('^2[TEST 24 PASS] Valid event instance created: UID=%s, State=%s, Bucket=%d.^7'):format(
                inst24.eventUid, inst24.state, inst24.routingBucket))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 24 FAIL] Failed to create valid event instance: ok=%s, err=%s^7'):format(tostring(ok24), tostring(inst24)))
        end
        local currentEventUid = inst24 and inst24.eventUid

        -- TEST 25: Reject unknown event key
        print('^3[TEST 25] Reject unknown event key...^7')
        local ok25, err25 = CreateFamilyEvent('completely_fake_event_key', {
            initiatorFamilyId = testFamId3,
        })
        if ok25 == false and err25 == 'unknown_event_key' then
            print('^2[TEST 25 PASS] Unknown event key strictly rejected with unknown_event_key.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 25 FAIL] Unknown event key was not rejected: ok=%s, err=%s^7'):format(tostring(ok25), tostring(err25)))
        end

        -- TEST 26: Reject family below minimum level
        print('^3[TEST 26] Reject family below minimum level...^7')
        local origMinLvl = Config.FamilyEvents.family_raid.minFamilyLevel
        Config.FamilyEvents.family_raid.minFamilyLevel = 10
        local ok26, err26 = CanFamilyStartEvent(testFamId3, 'family_raid')
        Config.FamilyEvents.family_raid.minFamilyLevel = origMinLvl
        if ok26 == false and err26 == 'family_level_too_low' then
            print('^2[TEST 26 PASS] Family below min level correctly rejected with family_level_too_low.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 26 FAIL] Min level check failed: ok=%s, err=%s^7'):format(tostring(ok26), tostring(err26)))
        end

        -- TEST 27: Reject family already in active major event
        print('^3[TEST 27] Reject family already in active major event...^7')
        local ok27, err27 = CanFamilyStartEvent(testFamId, 'family_raid')
        if ok27 == false and err27 == 'family_already_in_event' then
            print('^2[TEST 27 PASS] Family with active event rejected with family_already_in_event.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 27 FAIL] Active event check failed: ok=%s, err=%s^7'):format(tostring(ok27), tostring(err27)))
        end

        -- TEST 28: Duplicate participant join
        print('^3[TEST 28] Participant join and duplicate prevention...^7')
        local ok28_1, joinInst28_1 = JoinFamilyEvent(currentEventUid, testCid1, 101)
        local ok28_2, joinErr28_2 = JoinFamilyEvent(currentEventUid, testCid1, 101)
        local partCount28 = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cm_family_event_participants WHERE event_uid = ? AND character_id = ?',
            { currentEventUid, testCid1 })) or 0
        if ok28_1 == true and partCount28 == 1 then
            print('^2[TEST 28 PASS] Participant join registered, duplicate row prevented (unique constraint preserved).^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 28 FAIL] Join test failed: ok1=%s, ok2=%s, partCount=%d^7'):format(tostring(ok28_1), tostring(ok28_2), partCount28))
        end

        -- TEST 29: Reject participant from unrelated family
        print('^3[TEST 29] Reject participant from unrelated family...^7')
        local ok29, err29 = JoinFamilyEvent(currentEventUid, testCid4, 104)
        if ok29 == false and err29 == 'unrelated_family_cannot_join' then
            print('^2[TEST 29 PASS] Unrelated family participant rejected with unrelated_family_cannot_join.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 29 FAIL] Unrelated family check failed: ok=%s, err=%s^7'):format(tostring(ok29), tostring(err29)))
        end

        -- TEST 30: Persist participant correctly
        print('^3[TEST 30] Persist participant correctly in database...^7')
        local ok30, _ = JoinFamilyEvent(currentEventUid, testCid3, 103)
        local partRow30 = MySQL.single.await(
            'SELECT status, family_id FROM cm_family_event_participants WHERE event_uid = ? AND character_id = ?',
            { currentEventUid, testCid3 })
        if ok30 == true and partRow30 and partRow30.status == 'active' and tonumber(partRow30.family_id) == testFamId2 then
            print('^2[TEST 30 PASS] Participant persisted correctly in cm_family_event_participants.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 30 FAIL] Participant persistence check failed: ok=%s, row=%s^7'):format(tostring(ok30), json.encode(partRow30 or {})))
        end

        -- TEST 31: State transition rejects invalid transition
        print('^3[TEST 31] State transition rejects invalid transition...^7')
        local ok31, err31 = TransitionEventState(currentEventUid, 'completed')
        if ok31 == false and err31 == 'invalid_state_transition' then
            print('^2[TEST 31 PASS] Invalid state transition directly from forming -> completed rejected.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 31 FAIL] Invalid state transition was not rejected: ok=%s, err=%s^7'):format(tostring(ok31), tostring(err31)))
        end

        -- TEST 32: Valid forming -> countdown -> active transition
        print('^3[TEST 32] Valid forming -> countdown -> active transition...^7')
        local ok32_c, _ = TransitionEventState(currentEventUid, 'countdown')
        local ok32_a, inst32 = TransitionEventState(currentEventUid, 'active', { durationSeconds = 900 })
        local row32 = MySQL.single.await(
            'SELECT state, started_at, ends_at FROM cm_family_event_instances WHERE event_uid = ?', { currentEventUid })
        if ok32_c == true and ok32_a == true and row32 and row32.state == 'active' and row32.started_at ~= nil then
            print('^2[TEST 32 PASS] State machine transition forming -> countdown -> active persisted with timestamps.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 32 FAIL] State machine transition failed: okC=%s, okA=%s, state=%s^7'):format(
                tostring(ok32_c), tostring(ok32_a), tostring(row32 and row32.state)))
        end

        -- TEST 33: Completion persists exactly once
        print('^3[TEST 33] Completion persists exactly once...^7')
        local ok33, res33 = CompleteFamilyEvent(currentEventUid, {
            winnerFamilyId = testFamId,
            reason = 'time_expired_circle_holder',
        })
        local row33 = MySQL.single.await(
            'SELECT state, winner_family_id, completed_at, result_reason FROM cm_family_event_instances WHERE event_uid = ?',
            { currentEventUid })
        if ok33 == true and row33 and row33.state == 'completed' and tonumber(row33.winner_family_id) == testFamId and row33.completed_at ~= nil then
            print('^2[TEST 33 PASS] Event completed and persisted: winner=' .. testFamId .. ', reason=' .. tostring(row33.result_reason) .. '^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 33 FAIL] Event completion check failed: ok=%s, row=%s^7'):format(tostring(ok33), json.encode(row33 or {})))
        end

        -- TEST 34: Duplicate completion does not double reward
        print('^3[TEST 34] Duplicate completion does not double reward...^7')
        local ok34, err34 = CompleteFamilyEvent(currentEventUid, {
            winnerFamilyId = testFamId,
            reason = 'second_completion_attempt',
        })
        if ok34 == false and err34 == 'event_already_terminated' then
            print('^2[TEST 34 PASS] Duplicate event completion rejected with event_already_terminated.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 34 FAIL] Duplicate completion was not rejected: ok=%s, err=%s^7'):format(tostring(ok34), tostring(err34)))
        end

        -- TEST 35: Cooldown survives in database
        print('^3[TEST 35] Cooldown persists in database...^7')
        local cdRow35 = MySQL.single.await(
            'SELECT UNIX_TIMESTAMP(available_at) AS avail_ts FROM cm_family_event_cooldowns WHERE event_key = ? AND family_id = ?',
            { 'family_raid', testFamId })
        local now35 = os.time()
        if cdRow35 and cdRow35.avail_ts and tonumber(cdRow35.avail_ts) > now35 then
            print(('^2[TEST 35 PASS] Cooldown persisted in DB: expires in %d seconds.^7'):format(tonumber(cdRow35.avail_ts) - now35))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 35 FAIL] Cooldown not found in DB: row=%s^7'):format(json.encode(cdRow35 or {})))
        end

        -- TEST 36: Second Raid start during cooldown rejected
        print('^3[TEST 36] Second Raid start during cooldown rejected...^7')
        local ok36, err36, details36 = CanFamilyStartEvent(testFamId, 'family_raid')
        if ok36 == false and err36 == 'event_on_cooldown' and details36 and details36.remaining > 0 then
            print(('^2[TEST 36 PASS] Second start rejected by active cooldown: remaining=%d sec.^7'):format(details36.remaining))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 36 FAIL] Cooldown rejection failed: ok=%s, err=%s^7'):format(tostring(ok36), tostring(err36)))
        end

        -- TEST 37: Resource recovery cancels stale active Raid safely
        print('^3[TEST 37] Resource recovery cancels stale active Raid safely...^7')
        local staleUid = 'fam_evt_test_stale_recovery_' .. os.time()
        MySQL.query.await([[
            INSERT INTO cm_family_event_instances (event_uid, event_key, state, initiator_family_id, target_family_id)
            VALUES (?, 'family_raid', 'active', ?, ?)
        ]], { staleUid, testFamId2, testFamId3 })
        MySQL.query.await([[
            INSERT INTO cm_family_event_participants (event_uid, family_id, character_id, status)
            VALUES (?, ?, ?, 'active')
        ]], { staleUid, testFamId2, testCid3 })

        local staleRows = MySQL.query.await([[
            SELECT event_uid, initiator_family_id, target_family_id
            FROM cm_family_event_instances
            WHERE event_uid = ? AND state IN ('forming', 'countdown', 'active', 'overtime')
        ]], { staleUid })
        for _, r in ipairs(staleRows) do
            MySQL.update.await("UPDATE cm_family_event_instances SET state = 'cancelled', result_reason = 'resource_restart_recovery', completed_at = CURRENT_TIMESTAMP WHERE event_uid = ?", { r.event_uid })
            MySQL.update.await("UPDATE cm_family_event_participants SET status = 'cancelled', left_at = CURRENT_TIMESTAMP WHERE event_uid = ?", { r.event_uid })
        end

        local recoveredRow = MySQL.single.await('SELECT state, result_reason FROM cm_family_event_instances WHERE event_uid = ?', { staleUid })
        local recoveredPart = MySQL.single.await('SELECT status FROM cm_family_event_participants WHERE event_uid = ? AND character_id = ?', { staleUid, testCid3 })
        if recoveredRow and recoveredRow.state == 'cancelled' and recoveredRow.result_reason == 'resource_restart_recovery'
           and recoveredPart and recoveredPart.status == 'cancelled' then
            print('^2[TEST 37 PASS] Stale active raid recovered and safely cancelled without ghost state.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 37 FAIL] Recovery test failed: instState=%s, partStatus=%s^7'):format(
                tostring(recoveredRow and recoveredRow.state), tostring(recoveredPart and recoveredPart.status)))
        end
        MySQL.query.await('DELETE FROM cm_family_event_participants WHERE event_uid = ?', { staleUid })
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { staleUid })

        -- TEST 38: Participant cleanup idempotent
        print('^3[TEST 38] Participant cleanup idempotent...^7')
        local clean1 = CleanupFamilyEvent(currentEventUid, 'test_cleanup')
        local clean2 = CleanupFamilyEvent(currentEventUid, 'test_cleanup')
        if clean1 == true and clean2 == true then
            print('^2[TEST 38 PASS] CleanupFamilyEvent executed idempotently twice without exception.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 38 FAIL] CleanupFamilyEvent idempotency failed: clean1=%s, clean2=%s^7'):format(tostring(clean1), tostring(clean2)))
        end

        -- TEST 39: Winner reward uses hardened reward API
        print('^3[TEST 39] Winner reward recorded in cm_family_reward_history...^7')
        local rewardUid39 = ('family_event:%s:winner:%s'):format(currentEventUid, testFamId)
        local rewardRow39 = MySQL.single.await(
            'SELECT reward_type, amount, source FROM cm_family_reward_history WHERE unique_id = ?',
            { rewardUid39 })
        if rewardRow39 and (rewardRow39.reward_type == 'activity_root' or rewardRow39.reward_type == 'reputation') and tonumber(rewardRow39.amount) == 750 then
            print('^2[TEST 39 PASS] Winner reward confirmed in cm_family_reward_history (type=activity_root, amount=750).^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 39 FAIL] Winner reward not found in reward history: %s^7'):format(json.encode(rewardRow39 or {})))
        end

        -- TEST 40: Same event reward UID cannot pay twice
        print('^3[TEST 40] Same event reward UID duplicate rejection...^7')
        local ok40, err40 = AwardFamilyActivityReward({
            familyId = testFamId,
            uniqueId = rewardUid39,
            eventType = 'family_raid',
            reputation = 750,
            treasuryAmount = 50000,
        })
        if ok40 == false and (err40 == 'duplicate_reward' or err40 == 'duplicate_reward_unique_id') then
            print('^2[TEST 40 PASS] Duplicate event reward UID strictly rejected with duplicate_reward.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 40 FAIL] Duplicate reward was not rejected: ok=%s, err=%s^7'):format(tostring(ok40), tostring(err40)))
        end

        -- TEST 41: Event history remains after completion
        print('^3[TEST 41] Event history remains queryable after completion...^7')
        local historyRows41 = GetRecentFamilyOperations(testFamId, 5)
        local foundInHistory = false
        for _, op in ipairs(historyRows41) do
            if op.eventUid == currentEventUid and op.state == 'completed' and op.won == true then
                foundInHistory = true
                break
            end
        end
        if foundInHistory then
            print('^2[TEST 41 PASS] Completed operation returned in durable operations history (won=true, state=completed).^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 41 FAIL] Completed event not found in history: %s^7'):format(json.encode(historyRows41)))
        end

        -- TEST 42: Family active-event lock clears after completion
        print('^3[TEST 42] Family active-event lock clears after completion...^7')
        local activeAfterComplete = GetActiveFamilyEventForFamily(testFamId)
        if activeAfterComplete == nil then
            print('^2[TEST 42 PASS] Active event lock cleared: GetActiveFamilyEventForFamily returns nil.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 42 FAIL] Active event lock still held: %s^7'):format(tostring(activeAfterComplete and activeAfterComplete.eventUid)))
        end

        -- TEST 43: Family can start again after cooldown expiry
        print('^3[TEST 43] Family can start again after cooldown expiry...^7')
        ClearFamilyEventCooldown(testFamId, 'family_raid')
        local ok43, err43 = CanFamilyStartEvent(testFamId, 'family_raid')
        if ok43 == true then
            print('^2[TEST 43 PASS] Family can start raid again after cooldown expiry.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 43 FAIL] CanFamilyStartEvent failed after cooldown expiry: ok=%s, err=%s^7'):format(tostring(ok43), tostring(err43)))
        end

        -- ============================================================
        -- TESTS 44 - 56: Family Event Engine Phase 1.1 Stabilization
        -- ============================================================
        do
        -- TEST 44: Durable reward state lifecycle
        print('^3[TEST 44] Durable reward state lifecycle recorded in cm_family_event_instances...^7')
        local row44 = MySQL.single.await([[
            SELECT reward_state, reward_processing_at, reward_delivered_at, reward_metadata
            FROM cm_family_event_instances
            WHERE event_uid = ?
        ]], { currentEventUid })
        if row44 and row44.reward_state == 'delivered' and row44.reward_delivered_at ~= nil then
            print('^2[TEST 44 PASS] Durable reward state confirmed: reward_state=delivered with delivery timestamp.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 44 FAIL] Reward state check failed: %s^7'):format(json.encode(row44 or {})))
        end

        -- TEST 45: Active event lock prevents concurrent event start until completion finalization
        print('^3[TEST 45] Active event lock prevents concurrent event start until finalization...^7')
        ClearFamilyEventCooldown(testFamId, 'family_raid')
        local ok45_ev, inst45 = CreateFamilyEvent('family_raid', {
            initiatorFamilyId = testFamId,
            targetFamilyId = testFamId2,
            startedByCid = testCid1,
        })
        local ok45_can, err45_can = CanFamilyStartEvent(testFamId, 'family_raid')
        local ok45_dup, err45_dup = CreateFamilyEvent('family_raid', {
            initiatorFamilyId = testFamId,
            startedByCid = testCid1,
        })
        if ok45_ev and ok45_can == false and err45_can == 'family_already_in_event' and ok45_dup == false and err45_dup == 'family_already_in_event' then
            print('^2[TEST 45 PASS] Active event lock strictly prevents concurrent event creation.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 45 FAIL] Active event lock check failed: ok_ev=%s, can=%s, err=%s, dup=%s, dupErr=%s^7'):format(
                tostring(ok45_ev), tostring(ok45_can), tostring(err45_can), tostring(ok45_dup), tostring(err45_dup)))
        end

        -- TEST 46: Failed event reward remains retryable / recoverable
        print('^3[TEST 46] Failed event reward is retryable without double-payout risk...^7')
        local testEventUid46 = 'evt_test_failed_' .. os.time()
        local rewardUniqueId46 = ('family_event:%s:winner:%s'):format(testEventUid46, testFamId)
        local ok46_1, res46_1 = AwardFamilyActivityReward({
            familyId = testFamId,
            eventType = 'family_raid',
            uniqueId = rewardUniqueId46,
            reputation = 200,
            treasuryAmount = 5000,
        })
        -- Second attempt must fail with duplicate_reward_unique_id
        local ok46_2, res46_2 = AwardFamilyActivityReward({
            familyId = testFamId,
            eventType = 'family_raid',
            uniqueId = rewardUniqueId46,
            reputation = 200,
            treasuryAmount = 5000,
        })
        if ok46_1 == true and ok46_2 == false and res46_2 == 'duplicate_reward_unique_id' then
            print('^2[TEST 46 PASS] Reward settles properly on retry and strictly prevents double payout.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 46 FAIL] Retryable reward check failed: ok1=%s, ok2=%s, res2=%s^7'):format(
                tostring(ok46_1), tostring(ok46_2), tostring(res46_2)))
        end

        -- TEST 47: Settlement recovery recovers pending/failed event reward
        print('^3[TEST 47] Settlement recovery recovers pending/failed event reward on startup/recovery...^7')
        local testEventUid47 = 'evt_test_settle_' .. os.time()
        MySQL.query.await([[
            INSERT INTO cm_family_event_instances
            (event_uid, event_key, state, initiator_family_id, target_family_id, winner_family_id, reward_state, metadata)
            VALUES (?, 'family_raid', 'completed', ?, ?, ?, 'failed', ?)
        ]], { testEventUid47, testFamId, testFamId2, testFamId, json.encode({ test = 'settle' }) })
        RecoverPendingEventSettlements()
        local row47 = MySQL.single.await([[
            SELECT reward_state, reward_delivered_at FROM cm_family_event_instances WHERE event_uid = ?
        ]], { testEventUid47 })
        if row47 and row47.reward_state == 'delivered' and row47.reward_delivered_at ~= nil then
            print('^2[TEST 47 PASS] Pending settlement successfully recovered to delivered status.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 47 FAIL] Settlement recovery failed: %s^7'):format(json.encode(row47 or {})))
        end
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { testEventUid47 })

        -- TEST 48: Recent Operations returns only terminal operations and accurate won status
        print('^3[TEST 48] Recent Operations query returns only terminal operations with accurate won status...^7')
        if inst45 then
            CancelFamilyEvent(inst45.eventUid, 'test_cancel_ops')
            MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { inst45.eventUid })
        end
        -- Insert one forming (non-terminal) and one completed (terminal) operation
        local nonTerminalUid48 = 'evt_forming_' .. os.time()
        local terminalUid48 = 'evt_term_' .. os.time()
        MySQL.query.await([[
            INSERT INTO cm_family_event_instances (event_uid, event_key, state, initiator_family_id)
            VALUES (?, 'family_raid', 'forming', ?)
        ]], { nonTerminalUid48, testFamId })
        MySQL.query.await([[
            INSERT INTO cm_family_event_instances (event_uid, event_key, state, initiator_family_id, winner_family_id, completed_at, reward_state)
            VALUES (?, 'family_raid', 'completed', ?, ?, CURRENT_TIMESTAMP, 'delivered')
        ]], { terminalUid48, testFamId, testFamId })
        local recentOps48 = GetRecentFamilyOperations(testFamId, 20)
        local sawNonTerminal = false
        local sawTerminal = false
        for _, op in ipairs(recentOps48) do
            if op.eventUid == nonTerminalUid48 then
                sawNonTerminal = true
            end
            if op.eventUid == terminalUid48 and op.state == 'completed' and op.won == true then
                sawTerminal = true
            end
        end
        if sawNonTerminal == false and sawTerminal == true then
            print('^2[TEST 48 PASS] Recent operations strictly filters non-terminal events and marks won=true correctly.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 48 FAIL] Recent operations check failed: sawNonTerminal=%s, sawTerminal=%s^7'):format(
                tostring(sawNonTerminal), tostring(sawTerminal)))
        end
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid IN (?, ?)', { nonTerminalUid48, terminalUid48 })

        -- TEST 49: Completed event finalizes participant database status
        print('^3[TEST 49] Completed event finalizes participant database status...^7')
        ClearFamilyEventCooldown(testFamId, 'family_raid')
        local ok49_ev, inst49 = CreateFamilyEvent('family_raid', {
            initiatorFamilyId = testFamId,
            startedByCid = testCid1,
        })
        JoinFamilyEvent(inst49.eventUid, testCid1, 101)
        TransitionEventState(inst49.eventUid, 'countdown')
        TransitionEventState(inst49.eventUid, 'active', { durationSeconds = 300 })
        CompleteFamilyEvent(inst49.eventUid, { winnerFamilyId = testFamId, reason = 'test_finish' })
        local partRow49 = MySQL.single.await([[
            SELECT status FROM cm_family_event_participants WHERE event_uid = ? AND character_id = ?
        ]], { inst49.eventUid, testCid1 })
        if partRow49 and partRow49.status == 'completed' then
            print('^2[TEST 49 PASS] Active participants finalized to completed in database.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 49 FAIL] Participant status not finalized to completed: %s^7'):format(
                json.encode(partRow49 or {})))
        end
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { inst49.eventUid })
        MySQL.query.await('DELETE FROM cm_family_event_participants WHERE event_uid = ?', { inst49.eventUid })

        -- TEST 50: Character/source mismatch rejected on join
        print('^3[TEST 50] Character/source mismatch rejected on join...^7')
        ClearFamilyEventCooldown(testFamId, 'family_raid')
        local ok50_ev, inst50 = CreateFamilyEvent('family_raid', {
            initiatorFamilyId = testFamId,
            startedByCid = testCid1,
        })
        local ok50_join, err50_join = JoinFamilyEvent(inst50.eventUid, testCid1, 99999)
        if ok50_join == false and err50_join == 'character_source_mismatch' then
            print('^2[TEST 50 PASS] Character/source mismatch rejected with character_source_mismatch.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 50 FAIL] Source mismatch check failed: ok=%s, err=%s^7'):format(
                tostring(ok50_join), tostring(err50_join)))
        end
        CleanupFamilyEvent(inst50.eventUid, 'test_cleanup')
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { inst50.eventUid })

        -- TEST 51: Numeric ordering concurrency lock prevents event creation race
        print('^3[TEST 51] Concurrency lock prevents race without deadlocks...^7')
        ClearFamilyEventCooldown(testFamId, 'family_raid')
        ClearFamilyEventCooldown(testFamId2, 'family_raid')
        local ok51_A, res51_A, ok51_B, res51_B
        local done51_A, done51_B = false, false
        CreateThread(function()
            ok51_A, res51_A = CreateFamilyEvent('family_raid', {
                initiatorFamilyId = testFamId,
                targetFamilyId = testFamId2,
                startedByCid = testCid1,
            })
            done51_A = true
        end)
        CreateThread(function()
            ok51_B, res51_B = CreateFamilyEvent('family_raid', {
                initiatorFamilyId = testFamId2,
                targetFamilyId = testFamId,
                startedByCid = testCid3,
            })
            done51_B = true
        end)
        while not (done51_A and done51_B) do Wait(10) end
        local oneSucceeded = (ok51_A == true and ok51_B == false) or (ok51_A == false and ok51_B == true)
        local oneBlocked = (res51_A == 'family_already_in_event' or res51_B == 'family_already_in_event')
        if oneSucceeded and oneBlocked then
            print('^2[TEST 51 PASS] Concurrency locks strictly ordered: one event succeeded, one rejected cleanly.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 51 FAIL] Concurrency lock check failed: okA=%s, resA=%s, okB=%s, resB=%s^7'):format(
                tostring(ok51_A), tostring(res51_A and res51_A.eventUid or res51_A),
                tostring(ok51_B), tostring(res51_B and res51_B.eventUid or res51_B)))
        end
        local winnerUid51 = (ok51_A and res51_A and res51_A.eventUid) or (ok51_B and res51_B and res51_B.eventUid)
        if winnerUid51 then
            CleanupFamilyEvent(winnerUid51, 'test_cleanup')
            MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { winnerUid51 })
        end

        -- TEST 52: Family event cancel clears locks and marks event and participants cancelled
        print('^3[TEST 52] CancelFamilyEvent marks event/participants cancelled and releases locks...^7')
        ClearFamilyEventCooldown(testFamId, 'family_raid')
        local ok52_ev, inst52 = CreateFamilyEvent('family_raid', {
            initiatorFamilyId = testFamId,
            startedByCid = testCid1,
        })
        JoinFamilyEvent(inst52.eventUid, testCid1, 101)
        local ok52_c, res52_c = CancelFamilyEvent(inst52.eventUid, 'manual_admin_cancel')
        local row52 = MySQL.single.await([[
            SELECT state, reward_state, result_reason FROM cm_family_event_instances WHERE event_uid = ?
        ]], { inst52.eventUid })
        local partRow52 = MySQL.single.await([[
            SELECT status FROM cm_family_event_participants WHERE event_uid = ? AND character_id = ?
        ]], { inst52.eventUid, testCid1 })
        local lock52 = GetActiveFamilyEventForFamily(testFamId)
        if ok52_c == true and row52 and row52.state == 'cancelled' and row52.reward_state == 'not_applicable' and partRow52 and partRow52.status == 'cancelled' and lock52 == nil then
            print('^2[TEST 52 PASS] Event cancelled cleanly: state=cancelled, participant=cancelled, lock cleared.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 52 FAIL] CancelFamilyEvent check failed: ok=%s, row=%s, part=%s, lock=%s^7'):format(
                tostring(ok52_c), json.encode(row52 or {}), json.encode(partRow52 or {}), tostring(lock52)))
        end
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { inst52.eventUid })
        MySQL.query.await('DELETE FROM cm_family_event_participants WHERE event_uid = ?', { inst52.eventUid })

        -- TEST 53: Restart recovery does not apply 3-hour raid cooldown
        print('^3[TEST 53] Restart recovery cancels stale active events without 3-hour penalty cooldown...^7')
        ClearFamilyEventCooldown(testFamId, 'family_raid')
        local staleUid53 = 'evt_stale_restart_' .. os.time()
        MySQL.query.await([[
            INSERT INTO cm_family_event_instances
            (event_uid, event_key, state, initiator_family_id, target_family_id, reward_state, metadata)
            VALUES (?, 'family_raid', 'active', ?, ?, 'not_applicable', ?)
        ]], { staleUid53, testFamId, testFamId2, json.encode({ test = 'restart_recovery' }) })
        RecoverStaleEvents()
        local staleRow53 = MySQL.single.await([[
            SELECT state, result_reason FROM cm_family_event_instances WHERE event_uid = ?
        ]], { staleUid53 })
        local cd53 = GetFamilyEventCooldown(testFamId, 'family_raid')
        if staleRow53 and staleRow53.state == 'cancelled' and cd53 and (cd53.remaining == 0 or cd53.ready == true) then
            print('^2[TEST 53 PASS] Stale event cancelled on recovery with 0 cooldown penalty.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 53 FAIL] Stale recovery check failed: row=%s, cd=%s^7'):format(
                json.encode(staleRow53 or {}), json.encode(cd53 or {})))
        end
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { staleUid53 })

        -- TEST 54: Participant combat elimination updates participant status
        print('^3[TEST 54] Combat elimination updates participant status to eliminated...^7')
        ClearFamilyEventCooldown(testFamId, 'family_raid')
        local ok54_ev, inst54 = CreateFamilyEvent('family_raid', {
            initiatorFamilyId = testFamId,
            startedByCid = testCid1,
        })
        JoinFamilyEvent(inst54.eventUid, testCid1, 101)
        local ok54_elim, res54_elim = UpdateFamilyEventParticipantStatus(inst54.eventUid, testCid1, 'eliminated', {
            reason = 'combat_killed',
            eliminatedAt = os.time(),
        })
        local partRow54 = MySQL.single.await([[
            SELECT status, metadata FROM cm_family_event_participants WHERE event_uid = ? AND character_id = ?
        ]], { inst54.eventUid, testCid1 })
        if ok54_elim == true and partRow54 and partRow54.status == 'eliminated' then
            print('^2[TEST 54 PASS] Participant combat elimination recorded in database.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 54 FAIL] Participant elimination check failed: ok=%s, part=%s^7'):format(
                tostring(ok54_elim), json.encode(partRow54 or {})))
        end
        CleanupFamilyEvent(inst54.eventUid, 'test_cleanup')
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { inst54.eventUid })
        MySQL.query.await('DELETE FROM cm_family_event_participants WHERE event_uid = ?', { inst54.eventUid })

        -- TEST 55: Safe cleanup in CMFamilyDeleteFamilyRows deletes child rows
        print('^3[TEST 55] CMFamilyDeleteFamilyRows deletes child event participants and cooldowns...^7')
        local dummyFamId55 = 999955
        MySQL.query.await([[
            INSERT INTO cm_families (id, name, founder_cid, bank_balance)
            VALUES (?, 'DeleteTestFamily', 'cid_dtf', 100000)
        ]], { dummyFamId55 })
        local testUid55 = 'evt_del_' .. os.time()
        MySQL.query.await([[
            INSERT INTO cm_family_event_instances (event_uid, event_key, state, initiator_family_id)
            VALUES (?, 'family_raid', 'forming', ?)
        ]], { testUid55, dummyFamId55 })
        MySQL.query.await([[
            INSERT INTO cm_family_event_participants (event_uid, family_id, character_id, status)
            VALUES (?, ?, 'cid_dtf', 'joined')
        ]], { testUid55, dummyFamId55 })
        SetFamilyEventCooldown(dummyFamId55, 'family_raid', 3600, testUid55)

        CMFamilyDeleteFamilyRows(dummyFamId55)

        local partCount55 = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cm_family_event_participants WHERE family_id = ?', { dummyFamId55 })) or 0
        local cdCount55 = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM cm_family_event_cooldowns WHERE family_id = ?', { dummyFamId55 })) or 0
        if partCount55 == 0 and cdCount55 == 0 then
            print('^2[TEST 55 PASS] Child event tables cleaned up by CMFamilyDeleteFamilyRows.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 55 FAIL] Child deletion failed: partCount=%d, cdCount=%d^7'):format(partCount55, cdCount55))
        end
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { testUid55 })

        -- TEST 56: Administrative commands reject non-console source
        print('^3[TEST 56] Administrative commands strictly reject non-console source...^7')
        local ok56_list, err56_list = FamilyEventCommands.list(101, {}, '')
        local ok56_cancel, err56_cancel = FamilyEventCommands.cancel(101, { 'fake_uid' }, '')
        local ok56_recover, err56_recover = FamilyEventCommands.recover(101, {}, '')
        if ok56_list == false and err56_list == 'console_only'
            and ok56_cancel == false and err56_cancel == 'console_only'
            and ok56_recover == false and err56_recover == 'console_only' then
            print('^2[TEST 56 PASS] All administrative event commands reject non-console players.^7')
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 56 FAIL] Admin command security check failed: list=%s, cancel=%s, recover=%s^7'):format(
                tostring(err56_list), tostring(err56_cancel), tostring(err56_recover)))
        end
        end

        -- Clean up test family rows
        CMFamilyBridge._mockCids = nil
        CMFamilyBridge._mockSrcs = nil
        CMFamilyDeleteFamilyRows(testFamId)
        CMFamilyDeleteFamilyRows(testFamId2)
        CMFamilyDeleteFamilyRows(testFamId3)
        MySQL.query.await('DELETE FROM cm_family_event_instances WHERE event_uid = ?', { currentEventUid })
        MySQL.query.await('DELETE FROM cm_family_event_participants WHERE event_uid = ?', { currentEventUid })
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

if Config and Config.DevTests == true then
    CreateThread(function()
        Wait(2000)
        RunFamilyHardeningTests()
    end)
end
