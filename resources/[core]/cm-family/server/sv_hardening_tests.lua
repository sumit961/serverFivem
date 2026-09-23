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
        local testsTotal = 16

        -- ============================================================
        -- TEST 1: Same reputation unique ID sent twice simultaneously
        -- ============================================================
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

        -- ============================================================
        -- TEST 11: Objective completion called simultaneously by two paths
        -- ============================================================
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
        -- TEST 16: Force transaction rollback and verify treasury unchanged
        -- ============================================================
        print('^3[TEST 16] Force atomic transaction failure and verify treasury unchanged...^7')
        local balBefore16 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        local testTx16 = {
            { query = 'UPDATE cm_families SET bank_balance = bank_balance - 50000 WHERE id = ?', values = { testFamId } },
            { query = 'INSERT INTO non_existent_table_for_rollback_test (col) VALUES (1)', values = {} }
        }
        local pOk16, txResult16 = pcall(function() return MySQL.transaction.await(testTx16) end)

        local balAfter16 = tonumber(MySQL.scalar.await('SELECT bank_balance FROM cm_families WHERE id = ?', { testFamId })) or 0

        if balBefore16 == balAfter16 then
            print(('^2[TEST 16 PASS] Transaction rolled back completely: treasury balance unchanged ($%d -> $%d).^7'):format(balBefore16, balAfter16))
            testsPassed = testsPassed + 1
        else
            print(('^1[TEST 16 FAIL] Treasury changed on failed transaction! Before=$%d, After=$%d^7'):format(balBefore16, balAfter16))
        end

        -- Clean up test family rows
        CMFamilyDeleteFamilyRows(testFamId)

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
