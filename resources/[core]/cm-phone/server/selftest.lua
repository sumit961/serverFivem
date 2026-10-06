-- Development-only service-layer self-test for cm-phone.
--   server console:  cm_phone_selftest
-- Runs only when cm_environment=development, only from the server console, and only
-- touches synthetic characters whose ids start with "qa-phone-" (all of their rows are deleted afterwards).
-- It exercises the same service functions the NUI callbacks use; it adds no player-reachable mutation path.
local S = CMPhone.Server
local Config = CMPhone.Config

local PREFIX = 'qa-phone-'

local function enabled()
    local st = Config.SelfTest
    return GetConvar(st.convar, 'production') == st.value
end

local function cleanup()
    local like = PREFIX .. '%'
    MySQL.query.await('DELETE m FROM cm_phone_messages m JOIN cm_phone_conversation_members cm ON cm.conversation_id = m.conversation_id WHERE cm.character_id LIKE ?', { like })
    MySQL.query.await('DELETE c FROM cm_phone_conversations c JOIN cm_phone_conversation_members cm ON cm.conversation_id = c.id WHERE cm.character_id LIKE ?', { like })
    MySQL.query.await('DELETE FROM cm_phone_conversation_members WHERE character_id LIKE ?', { like })
    MySQL.query.await('DELETE FROM cm_phone_contacts WHERE owner_character_id LIKE ?', { like })
    MySQL.query.await('DELETE FROM cm_phone_blocks WHERE owner_character_id LIKE ?', { like })
    MySQL.query.await('DELETE FROM cm_phone_calls WHERE caller_character_id LIKE ? OR callee_character_id LIKE ?', { like, like })
    MySQL.query.await('DELETE FROM cm_phone_adverts WHERE author_character_id LIKE ?', { like })
    MySQL.query.await('DELETE FROM cm_phone_numbers WHERE character_id LIKE ?', { like })
end

local function run()
    local results, failed = {}, 0
    local function check(name, condition, detail)
        results[#results + 1] = { name = name, pass = condition == true }
        if condition ~= true then
            failed = failed + 1
            print(('[cm-phone:selftest] FAIL  %s %s'):format(name, detail and ('(' .. tostring(detail) .. ')') or ''))
        else
            print(('[cm-phone:selftest] PASS  %s'):format(name))
        end
    end

    cleanup()
    local A, B, Cc, D = PREFIX .. 'a', PREFIX .. 'b', PREFIX .. 'c', PREFIX .. 'd'
    local numA = S.EnsureNumber(A)
    local numB = S.EnsureNumber(B)
    local numC = S.EnsureNumber(Cc)
    local numD = S.EnsureNumber(D)

    -- IDENTITY ---------------------------------------------------------------
    check('identity.format', numA and numA:match('^%d%d%d%-%d%d%d%d$') ~= nil, numA)
    check('identity.stable', S.EnsureNumber(A) == numA)
    check('identity.distinct', numA ~= numB and numB ~= numC and numC ~= numD)
    S.ForgetNumberCache(A)
    check('identity.persists_after_cache_clear', S.GetNumber(A) == numA)
    local dupOk = pcall(function()
        return MySQL.insert.await('INSERT INTO cm_phone_numbers (character_id, phone_number) VALUES (?, ?)', { PREFIX .. 'dupe', numA })
    end)
    check('identity.duplicate_number_impossible', dupOk == false)
    check('identity.normalize', S.NormalizeNumber('3235551') == '323-5551' and S.NormalizeNumber('abc') == nil and S.NormalizeNumber('12345') == nil)

    -- CONTACTS ---------------------------------------------------------------
    local ok, id = S.SaveContact(A, { number = numB, name = 'Bob' })
    check('contacts.add', ok == true and id ~= nil)
    check('contacts.duplicate_rejected', select(2, S.SaveContact(A, { number = numB, name = 'Bob 2' })) == 'duplicate_number')
    check('contacts.invalid_number_rejected', select(2, S.SaveContact(A, { number = '12', name = 'x' })) == 'invalid_number')
    check('contacts.edit', S.SaveContact(A, { id = id, number = numB, name = 'Bobby', favourite = true }) == true and S.ListContacts(A)[1].name == 'Bobby')
    check('contacts.cannot_edit_foreign', select(2, S.SaveContact(B, { id = id, number = numA, name = 'Hacked' })) == 'not_found')
    check('contacts.cannot_delete_foreign', select(2, S.DeleteContact(B, id)) == 'not_found')
    check('contacts.foreign_untouched', S.ListContacts(A)[1].name == 'Bobby')
    check('contacts.delete', S.DeleteContact(A, id) == true and #S.ListContacts(A) == 0)

    -- SMS --------------------------------------------------------------------
    local sent, origEmit = {}, S.Emit
    S.Emit = function(src, event, ...) sent[#sent + 1] = { src = src, event = event, args = { ... } } return true end

    -- offline recipient (no TestOnline entry): persisted, unread, readable later
    local sOk, sRes = S.SendMessage(A, numA, { number = numB }, 'text', 'hello <b>offline</b>')
    check('sms.offline_send', sOk == true and sRes ~= nil and sRes.conversationId ~= nil)
    local convId = sRes and sRes.conversationId
    check('sms.offline_no_live_event', #sent == 0)
    local list = S.ListConversations(B)
    check('sms.recipient_unread_after_reconnect', list[1] and list[1].unread == 1 and list[1].number == numA)
    check('sms.unread_total', S.UnreadTotal(B) == 1)
    check('sms.sender_unread_zero', S.UnreadTotal(A) == 0)
    local openOk, openRes = S.OpenConversation(B, convId)
    check('sms.open_returns_history', openOk == true and #openRes.messages == 1 and openRes.messages[1].body == 'hello <b>offline</b>' and openRes.messages[1].mine == false)
    check('sms.read_clears_unread', S.UnreadTotal(B) == 0)

    -- online recipient: live notification, no history in the event
    S.TestOnline = { [B] = -2002 }
    sOk = S.SendMessage(A, numA, { conversationId = convId }, 'text', 'second')
    check('sms.online_send_live_event', sOk == true and sent[#sent] and sent[#sent].event == 'cm-phone:client:message' and sent[#sent].src == -2002 and sent[#sent].args[1].preview == 'second')
    S.TestOnline = nil

    -- spoof/forgery
    check('sms.third_party_cannot_open', select(2, S.OpenConversation(Cc, convId)) == 'not_found')
    check('sms.third_party_cannot_send_to_conversation', select(2, S.SendMessage(Cc, numC, { conversationId = convId }, 'text', 'x')) == 'not_found')
    check('sms.third_party_cannot_mark_read_foreign', (function()
        local before = S.UnreadTotal(B)
        S.MarkRead(Cc, convId)
        return S.UnreadTotal(B) == before
    end)())
    check('sms.invalid_recipient', select(2, S.SendMessage(A, numA, { number = '999-0000' }, 'text', 'x')) == 'invalid_recipient')
    check('sms.cannot_message_self', select(2, S.SendMessage(A, numA, { number = numA }, 'text', 'x')) == 'invalid_recipient')
    check('sms.empty_rejected', select(2, S.SendMessage(A, numA, { number = numB }, 'text', '   ')) == 'invalid_message')
    check('sms.bad_target_rejected', select(2, S.SendMessage(A, numA, 'nope', 'text', 'x')) == 'invalid_request')
    local long = string.rep('a', Config.Messages.textMax + 200)
    local _, longRes = S.SendMessage(A, numA, { number = numB }, 'text', long)
    local _, openLong = S.OpenConversation(B, convId)
    check('sms.length_bounded', longRes and #openLong.messages[#openLong.messages].body == Config.Messages.textMax)
    check('sms.system_thread_receive_only', (function()
        local sysOk, sysRes = S.SendSystem(B, 'City', 'Notice')
        if not sysOk then return false end
        return select(2, S.SendMessage(B, numB, { conversationId = sysRes.conversationId }, 'text', 'x')) == 'forbidden'
    end)())

    -- blocking
    S.Block(B, numB, numA)
    check('block.sender_rejected_sms', select(2, S.SendMessage(A, numA, { number = numB }, 'text', 'blocked?')) == 'undeliverable')
    check('block.sender_rejected_in_conversation', select(2, S.SendMessage(A, numA, { conversationId = convId }, 'text', 'blocked?')) == 'undeliverable')
    check('block.cannot_block_self', select(2, S.Block(B, numB, numB)) == 'invalid_target')
    check('block.is_blocked_contract', S.IsBlocked(B, numA) == true and S.IsBlocked(A, numB) == false)
    S.Unblock(B, numA)
    check('block.unblock_restores', S.SendMessage(A, numA, { number = numB }, 'text', 'again') == true)

    -- location (server-built payload shape; coordinates come from the server, never the client)
    local locOk = S.SendMessage(A, numA, { number = numB }, 'location', '', { x = 1.5, y = 2.5, label = 'Here' })
    local _, openLoc = S.OpenConversation(B, convId)
    check('sms.location_message', locOk == true and openLoc.messages[#openLoc.messages].kind == 'location' and openLoc.messages[#openLoc.messages].payload.x == 1.5)

    -- rate limit
    local rl1 = S.RateLimit(PREFIX .. 'rate', 'sms')
    local rl2 = S.RateLimit(PREFIX .. 'rate', 'sms')
    check('sms.rate_limited', rl1 == true and rl2 == false)

    -- GROUPS -----------------------------------------------------------------
    local gOk, gRes = S.CreateGroup(A, numA, 'Crew', { numB, numC })
    check('group.create', gOk == true and gRes.conversationId ~= nil)
    local gid = gRes and gRes.conversationId
    check('group.member_can_open', select(1, S.OpenConversation(B, gid)) == true)
    check('group.non_member_cannot_open', select(2, S.OpenConversation(D, gid)) == 'not_found')
    check('group.non_member_cannot_send', select(2, S.SendMessage(D, numD, { conversationId = gid }, 'text', 'x')) == 'not_found')
    check('group.member_send', S.SendMessage(B, numB, { conversationId = gid }, 'text', 'hi crew') == true)
    check('group.non_owner_cannot_add', select(2, S.GroupAdd(B, numB, gid, numD)) == 'forbidden')
    check('group.owner_add', S.GroupAdd(A, numA, gid, numD) == true)
    check('group.owner_remove', S.GroupRemove(A, gid, numD) == true)
    check('group.removed_cannot_open', select(2, S.OpenConversation(D, gid)) == 'not_found')
    check('group.forged_membership_rejected', select(2, S.GroupRemove(B, gid, numC)) == 'forbidden')
    check('group.leave', S.LeaveGroup(Cc, numC, gid) == true and select(2, S.OpenConversation(Cc, gid)) == 'not_found')
    check('group.limit_enforced', select(2, S.CreateGroup(A, numA, 'Big', { numB, numC, numD, '310-0001', '310-0002', '310-0003', '310-0004', '310-0005', '310-0006' })) == 'group_limit')

    S.Emit = origEmit

    -- CALLS ------------------------------------------------------------------
    local callEvents = {}
    S.Emit = function(src, event, payload) if event == 'cm-phone:client:call' then callEvents[#callEvents + 1] = { src = src, state = payload.state, role = payload.role } end return true end
    S.TestOnline = { [A] = -2001, [B] = -2002, [Cc] = -2003 }

    local cOk, cRes = S.StartCall(A, numA, -2001, numB)
    check('call.outgoing_ringing', cOk == true and cRes.state == 'ringing')
    check('call.states_emitted', (function()
        local caller, callee = {}, {}
        for _, e in ipairs(callEvents) do if e.src == -2001 then caller[#caller + 1] = e.state else callee[#callee + 1] = e.state end end
        return caller[1] == 'dialing' and caller[2] == 'ringing' and callee[2] == 'incoming'
    end)())
    check('call.caller_cannot_double_dial', select(2, S.StartCall(A, numA, -2001, numC)) == 'already_in_call')
    check('call.busy_target', select(2, S.StartCall(Cc, numC, -2003, numB)) == 'busy')
    check('call.caller_cannot_answer', select(2, S.AnswerCall(A)) == 'forbidden')
    check('call.stranger_cannot_answer', select(2, S.AnswerCall(Cc)) == 'no_call')
    check('call.answer', S.AnswerCall(B) == true)
    check('call.duplicate_answer_rejected', select(2, S.AnswerCall(B)) == 'already_active')
    check('call.state_active', S.CallState(A).state == 'active' and S.CallState(B).state == 'active')
    Wait(1100)
    check('call.hangup', S.HangupCall(A) == true and S.CallState(A) == nil and S.CallState(B) == nil)
    check('call.hangup_idempotent', select(2, S.HangupCall(A)) == 'no_call')
    local history = S.ListCalls(A)
    check('call.history_answered', history[1] and history[1].status == 'answered' and history[1].direction == 'outgoing' and history[1].number == numB and history[1].duration >= 1)
    check('call.history_incoming_view', S.ListCalls(B)[1].direction == 'incoming' and S.ListCalls(B)[1].number == numA)

    S.StartCall(A, numA, -2001, numB)
    check('call.decline', S.DeclineCall(B) == true and S.CallState(A) == nil)
    check('call.decline_history', S.ListCalls(A)[1].status == 'declined')

    S.StartCall(A, numA, -2001, numB)
    check('call.cancel_by_caller', S.HangupCall(A) == true and S.ListCalls(B)[1].status == 'missed')

    local savedTimeout = Config.Calls.ringTimeoutMs
    Config.Calls.ringTimeoutMs = 400
    S.StartCall(A, numA, -2001, numB)
    Wait(900)
    Config.Calls.ringTimeoutMs = savedTimeout
    check('call.timeout_cleans_state', S.CallState(A) == nil and S.CallState(B) == nil and S.ActiveCallCount() == 0)
    check('call.timeout_history', S.ListCalls(B)[1].status == 'missed')

    check('call.self_rejected', select(2, S.StartCall(A, numA, -2001, numA)) == 'invalid_target')
    check('call.invalid_number', select(2, S.StartCall(A, numA, -2001, '000')) == 'invalid_number')
    check('call.offline_target', select(2, S.StartCall(A, numA, -2001, numD)) == 'unavailable')
    check('call.offline_recorded_missed', S.ListCalls(D)[1] and S.ListCalls(D)[1].status == 'missed')
    S.Block(B, numB, numA)
    check('call.blocked_caller_rejected', select(2, S.StartCall(A, numA, -2001, numB)) == 'unavailable' and S.ActiveCallCount() == 0)
    S.Unblock(B, numA)

    S.StartCall(A, numA, -2001, numB)
    S.AnswerCall(B)
    S.EndCallsForSource(-2002)
    check('call.disconnect_cleanup', S.CallState(A) == nil and S.CallState(B) == nil and S.ActiveCallCount() == 0)
    S.StartCall(A, numA, -2001, numB)
    S.EndAllCalls('shutdown')
    check('call.resource_stop_cleanup', S.ActiveCallCount() == 0)
    S.TestOnline = nil
    S.Emit = origEmit

    -- ADVERTS ----------------------------------------------------------------
    local ledger = { balance = { [A] = 5000, [B] = 100 }, charges = 0, refunds = 0 }
    local origMoney = S.Money
    S.Money = {
        Charge = function(src, amount) if ledger.balance[src] and ledger.balance[src] >= amount then ledger.balance[src] = ledger.balance[src] - amount ledger.charges = ledger.charges + 1 return true, 'cash' end return false end,
        Refund = function(src, _, amount) ledger.balance[src] = (ledger.balance[src] or 0) + amount ledger.refunds = ledger.refunds + 1 return true end,
    }
    local aOk, aRes = S.PostAdvert(A, A, numA, 'Selling a legal used bicycle, call me!')
    check('advert.created', aOk == true and aRes.id ~= nil)
    check('advert.fee_charged_once', ledger.charges == 1 and ledger.balance[A] == 5000 - Config.Adverts.fee)
    check('advert.cooldown_rejected', select(2, S.PostAdvert(A, A, numA, 'Another advert too soon')) == 'cooldown' and ledger.charges == 1)
    check('advert.insufficient_funds', select(2, S.PostAdvert(B, B, numB, 'Not enough money here')) == 'insufficient_funds' and ledger.charges == 1)
    check('advert.too_short_rejected', select(2, S.PostAdvert(A, A, numA, 'hi')) == 'invalid_message')
    check('advert.feed_contains', (function() for _, ad in ipairs(S.ListAdverts()) do if ad.number == numA then return true end end return false end)())
    check('advert.operation_lock', (function()
        S.Lock(Cc, 'advert')
        local locked = select(2, S.PostAdvert(Cc, Cc, numC, 'Locked advert attempt')) == 'busy'
        S.Unlock(Cc, 'advert')
        return locked
    end)())
    S.Money = origMoney

    -- EMERGENCY --------------------------------------------------------------
    local origDispatch, forwarded = S.Dispatch, {}
    S.Dispatch = {
        ems = function(src, details) forwarded[#forwarded + 1] = { 'ems', src, details } return true, 'ok' end,
        police = function(src, details) forwarded[#forwarded + 1] = { 'police', src, details } return true, 'ok' end,
    }
    check('emergency.ems_forwarded', S.SendEmergency(-2001, A, 'ems', 'Man down') == true and forwarded[1][1] == 'ems' and forwarded[1][3] == 'Man down')
    check('emergency.police_forwarded', S.SendEmergency(-2001, A, 'police', 'Robbery') == true and forwarded[2][1] == 'police')
    check('emergency.invalid_service_rejected', select(2, S.SendEmergency(-2001, A, 'fire', 'x')) == 'invalid_request')
    S.Dispatch = origDispatch

    -- RESTART PERSISTENCE ----------------------------------------------------
    S.ForgetNumberCache(A)
    check('restart.numbers_persist', S.GetNumber(A) == numA)
    check('restart.messages_persist', S.OpenConversation(B, convId) == true)

    cleanup()
    check('cleanup.numbers_removed', (MySQL.scalar.await('SELECT COUNT(*) FROM cm_phone_numbers WHERE character_id LIKE ?', { PREFIX .. '%' }) or 1) == 0)

    print(('[cm-phone:selftest] RESULT %s: %d checks, %d failed'):format(failed == 0 and 'PASS' or 'FAIL', #results, failed))
    return failed == 0, #results, failed
end

RegisterCommand('cm_phone_selftest', function(source)
    if source ~= 0 then return end
    if not enabled() then
        print('[cm-phone:selftest] BLOCKED: requires cm_environment=development')
        return
    end
    if not S.AwaitSchema() then
        print('[cm-phone:selftest] BLOCKED: schema not ready')
        return
    end
    local ok, err = pcall(run)
    if not ok then
        S.TestOnline = nil
        pcall(cleanup)
        print('[cm-phone:selftest] ERROR ' .. tostring(err))
    end
end, true)
