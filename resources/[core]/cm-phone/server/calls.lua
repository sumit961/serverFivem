-- Server-authoritative call state machine: dialing -> ringing -> active -> ended
-- (terminal outcomes: answered, missed, declined, timeout, busy, unavailable).
-- Calls are keyed by character id; the client never supplies a call id, so a player can only act on
-- the call they are a participant of. Active calls are transient (not restored after restart).
-- Audio routing is NOT implemented (no voice resource installed): a local, non-network server event
-- is emitted on every state change for a future voice bridge.
local S = CMPhone.Server
local Config = CMPhone.Config
local C = Config.Calls

local Active = {}      -- Active[cid] = call (both participants map to the same table)
local nextCallId = 0

local function now() return os.time() end

local function other(call, cid)
    if tostring(call.callerCid) == tostring(cid) then
        return call.calleeCid, call.calleeNumber
    end
    return call.callerCid, call.callerNumber
end

local function voiceHook(call, state)
    TriggerEvent(Config.Voice.stateEvent, call.id, state, call.callerSrc, call.calleeSrc)
end

local function emitBoth(call, state, reason)
    local payloadCaller = { state = state, role = 'caller', number = call.calleeNumber, reason = reason, startedAt = call.startedAt, answeredAt = call.answeredAt }
    local payloadCallee = { state = state == 'ringing' and 'incoming' or state, role = 'callee', number = call.callerNumber, reason = reason, startedAt = call.startedAt, answeredAt = call.answeredAt }
    S.Emit(call.callerSrc, 'cm-phone:client:call', payloadCaller)
    S.Emit(call.calleeSrc, 'cm-phone:client:call', payloadCallee)
    voiceHook(call, state)
end

local function persist(call, outcome, durationSeconds)
    local answered = call.answeredAt or 0
    local ok, err = pcall(function()
        return MySQL.insert.await([[INSERT INTO cm_phone_calls
            (caller_character_id, caller_number, callee_character_id, callee_number, outcome, started_at, answered_at, ended_at, duration_seconds)
            VALUES (?, ?, ?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(NULLIF(?, 0)), CURRENT_TIMESTAMP, ?)]],
            { tostring(call.callerCid), call.callerNumber, tostring(call.calleeCid), call.calleeNumber, outcome, call.startedAt, answered, durationSeconds or 0 })
    end)
    if not ok then print('[cm-phone] call history insert failed: ' .. tostring(err)) end
end

-- Terminal transition. Idempotent: a call can only finish once.
local function finish(call, outcome, reason)
    if not call or call.finished then return false end
    call.finished = true
    call.state = 'ended'
    Active[tostring(call.callerCid)] = nil
    Active[tostring(call.calleeCid)] = nil
    local duration = 0
    if call.answeredAt then
        duration = math.max(0, math.min(now() - call.answeredAt, C.maxDurationSeconds))
    end
    persist(call, outcome, duration)
    emitBoth(call, 'ended', reason or outcome)
    return true
end

-- Starts an outgoing call. Returns true, { state } or false, reason.
function S.StartCall(callerCid, callerNumber, callerSrc, rawNumber)
    callerCid = tostring(callerCid)
    if Active[callerCid] then return false, 'already_in_call' end
    local number = S.NormalizeNumber(rawNumber)
    if not number then return false, 'invalid_number' end
    if number == callerNumber then return false, 'invalid_target' end
    local calleeCid = S.CidByNumber(number)
    if not calleeCid or calleeCid == callerCid then return false, 'invalid_number' end

    nextCallId = nextCallId + 1
    local call = {
        id = nextCallId, callerCid = callerCid, callerNumber = callerNumber, callerSrc = callerSrc,
        calleeCid = calleeCid, calleeNumber = number, state = 'dialing', startedAt = now(),
    }

    -- Blocked callers get the same result as an unreachable number; the callee is never notified.
    if S.IsBlocked(calleeCid, callerNumber) then return false, 'unavailable' end

    local calleeSrc = S.SourceOf(calleeCid)
    if not calleeSrc then
        persist(call, 'missed', 0)
        return false, 'unavailable'
    end
    if Active[calleeCid] then
        persist(call, 'busy', 0)
        return false, 'busy'
    end

    call.calleeSrc = calleeSrc
    Active[callerCid] = call
    Active[calleeCid] = call
    emitBoth(call, 'dialing')
    call.state = 'ringing'
    emitBoth(call, 'ringing')

    CreateThread(function()
        Wait(C.ringTimeoutMs)
        if not call.finished and call.state == 'ringing' then
            finish(call, 'timeout', 'timeout')
        end
    end)
    return true, { state = 'ringing', number = number }
end

function S.AnswerCall(cid)
    cid = tostring(cid)
    local call = Active[cid]
    if not call or call.finished then return false, 'no_call' end
    if tostring(call.calleeCid) ~= cid then return false, 'forbidden' end
    if call.state ~= 'ringing' then return false, 'already_active' end
    call.state = 'active'
    call.answeredAt = now()
    emitBoth(call, 'active')
    CreateThread(function()
        Wait(C.maxDurationSeconds * 1000)
        if not call.finished and call.state == 'active' then finish(call, 'answered', 'max_duration') end
    end)
    return true, { state = 'active' }
end

function S.DeclineCall(cid)
    cid = tostring(cid)
    local call = Active[cid]
    if not call or call.finished then return false, 'no_call' end
    if tostring(call.calleeCid) ~= cid or call.state ~= 'ringing' then return false, 'forbidden' end
    finish(call, 'declined', 'declined')
    return true
end

-- Hang up: caller cancelling a ringing call, callee rejecting it, or either side ending an active call.
function S.HangupCall(cid)
    cid = tostring(cid)
    local call = Active[cid]
    if not call or call.finished then return false, 'no_call' end
    if call.state == 'active' then
        finish(call, 'answered', 'hangup')
    elseif tostring(call.callerCid) == cid then
        finish(call, 'missed', 'cancelled')
    else
        finish(call, 'declined', 'declined')
    end
    return true
end

function S.CallState(cid)
    local call = Active[tostring(cid)]
    if not call or call.finished then return nil end
    local role = tostring(call.callerCid) == tostring(cid) and 'caller' or 'callee'
    local _, number = other(call, cid)
    return { state = (role == 'callee' and call.state == 'ringing') and 'incoming' or call.state, role = role, number = number,
             startedAt = call.startedAt, answeredAt = call.answeredAt }
end

-- Ends any call involving this character/source (disconnect, unload, death handling).
function S.EndCallsForCharacter(cid, reason)
    local call = Active[tostring(cid)]
    if call and not call.finished then
        finish(call, call.answeredAt and 'answered' or 'missed', reason or 'disconnect')
    end
end

function S.EndCallsForSource(src)
    src = tonumber(src)
    local seen = {}
    for _, call in pairs(Active) do
        if not seen[call] and (call.callerSrc == src or call.calleeSrc == src) then
            seen[call] = true
            finish(call, call.answeredAt and 'answered' or 'missed', 'disconnect')
        end
    end
end

function S.EndAllCalls(reason)
    local seen = {}
    for _, call in pairs(Active) do
        if not seen[call] then
            seen[call] = true
            finish(call, call.answeredAt and 'answered' or 'missed', reason or 'shutdown')
        end
    end
end

AddEventHandler('cm-phone:internal:characterUnloaded', function(src) S.EndCallsForSource(src) end)
AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then S.EndAllCalls('shutdown') end
end)

function S.ListCalls(cid)
    cid = tostring(cid)
    local rows = MySQL.query.await([[SELECT id, caller_character_id, caller_number, callee_character_id, callee_number, outcome,
            UNIX_TIMESTAMP(started_at) AS at, duration_seconds
        FROM cm_phone_calls WHERE caller_character_id = ? OR callee_character_id = ? ORDER BY id DESC LIMIT ?]], { cid, cid, C.historyMax }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local outgoing = tostring(r.caller_character_id) == cid
        local status
        if r.outcome == 'answered' then status = 'answered'
        elseif r.outcome == 'declined' then status = 'declined'
        else status = outgoing and 'no_answer' or 'missed' end
        out[#out + 1] = {
            id = r.id, direction = outgoing and 'outgoing' or 'incoming', number = outgoing and r.callee_number or r.caller_number,
            status = status, at = tonumber(r.at) or 0, duration = tonumber(r.duration_seconds) or 0,
        }
    end
    return out
end

-- Selftest hook: number of tracked participants (should be 0 when idle).
function S.ActiveCallCount()
    local n = 0
    for _ in pairs(Active) do n = n + 1 end
    return n
end
