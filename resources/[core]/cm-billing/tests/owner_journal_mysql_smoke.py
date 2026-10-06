"""Isolated MySQL smoke test for the owner-local exact-once money journals used by cm-billing refunds.

    python -u tests/owner_journal_mysql_smoke.py      (from resources/[core]/cm-billing; needs `pip install pymysql`)

SAFETY: connects with the local development `mysql_connection_string` (read from server.local.cfg, never printed), creates a SCRATCH database
cm_jrnl_smoke_<pid>, never touches another schema, and DROPs it at the end.

WHAT THIS IS: the journal SQL (MONEY_OP_SQL in cm-playerdata/server/main.lua, TREASURY_OP_SQL in cm-family/server/sv_bank.lua) and the table DDL
(playerdata migration 009, family sv_schema) are EXTRACTED from the production Lua source and run in real InnoDB transactions on separate
connections (independent callers: no shared Lua mutex). It first demonstrates the LEGACY evidence-based model (labelled, hard-coded from the
pre-hardening implementation) double-debiting when the generic log is missing or two callers race, then proves the journal model: replay,
conflict, concurrent duplicates, insufficient-funds retry, rollback, logging disabled, response loss and restart. It does NOT run the Lua exports
(that is the in-server `cm_billing_selftest` journal suite).
"""
import os
import re
import sys
import threading
from urllib.parse import urlparse

import pymysql

HERE = os.path.dirname(os.path.abspath(__file__))
BILLING = os.path.dirname(HERE)
CORE = os.path.abspath(os.path.join(BILLING, '..'))
ROOT = os.path.abspath(os.path.join(CORE, '..', '..'))
passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond:
        passed += 1
        print('PASS  ' + name)
    else:
        failed += 1
        print('FAIL  ' + name + (f'  ({detail})' if detail is not None else ''))


pd_src = open(os.path.join(CORE, 'cm-playerdata', 'server', 'main.lua'), encoding='utf-8').read()
fam_src = open(os.path.join(CORE, 'cm-family', 'server', 'sv_bank.lua'), encoding='utf-8').read()
fam_schema = open(os.path.join(CORE, 'cm-family', 'server', 'sv_schema.lua'), encoding='utf-8').read()


def lua_sql_block(src, start, end):
    block = src[src.index(start):src.index(end)]
    out = {}
    for m in re.finditer(r'^\s+(\w+) = (\[\[.*?\]\]|\'[^\'\n]*\'|"[^"\n]*"),?\s*$', block, re.M | re.S):
        raw = m.group(2)
        text = raw[2:-2] if raw.startswith('[[') else raw[1:-1]
        out[m.group(1)] = re.sub(r'\s+', ' ', text).strip().replace('?', '%s')
    return out


PSQL = lua_sql_block(pd_src, 'local MONEY_OP_SQL = {', 'local function MoneyOpFingerprint')
FSQL = lua_sql_block(fam_src, 'local TREASURY_OP_SQL = {', 'local function readTreasuryOp')
FCSQL = lua_sql_block(fam_src, 'local TREASURY_CREDIT_SQL = {', 'function CreditFamilyTreasuryOnce')
assert set(FCSQL) == {'credit', 'journal', 'log'}, sorted(FCSQL)
assert set(PSQL) == {'read', 'journal', 'log'} and set(FSQL) == {'read', 'debit', 'journal', 'log'}, (sorted(PSQL), sorted(FSQL))

pd_ddl = re.search(r'(CREATE TABLE IF NOT EXISTS cm_character_money_operations \(.*?ENGINE=InnoDB DEFAULT CHARSET=utf8mb4)', pd_src, re.S).group(1)
econ_ddl = re.search(r'(CREATE TABLE IF NOT EXISTS economy_transactions \(.*?\n                \))', pd_src, re.S).group(1)
fam_ddl = re.search(r'(CREATE TABLE IF NOT EXISTS `cm_family_treasury_operations` \(.*?ENGINE=InnoDB DEFAULT CHARSET=utf8mb4)', fam_schema, re.S).group(1)

cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
u = urlparse(re.search(r'mysql_connection_string\s+"?([^"\n]+)', cfg).group(1).strip())
SCRATCH = f'cm_jrnl_smoke_{os.getpid()}'
args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', autocommit=False, charset='utf8mb4')


def connect(db=None):
    return pymysql.connect(database=db, **args)


admin = connect()
admin.autocommit(True)
admin.cursor().execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
print(f'scratch database created: {SCRATCH}')
conns = []


def fingerprint_c(direction, cid, account, amount):
    return f'{direction}|{cid}|{account}|{amount}'


def char_op(conn, cur, direction, cid, account, amount, ref, log=True, fail_after_balance=False, fail_after_journal=False):
    """Mirror of ApplyJournaledMoney (offline path). Returns 'applied' | 'replayed' | 'conflict' | 'insufficient' | 'failed'."""
    fp = fingerprint_c(direction, cid, account, amount)
    cur.execute(PSQL['read'], (ref,)); row = cur.fetchone(); conn.commit()
    if row:
        return 'replayed' if row['fingerprint'] == fp else 'conflict'
    cur.execute(f'SELECT {account} AS b FROM characters WHERE id = %s', (str(cid),)); bal = cur.fetchone(); conn.commit()
    if bal is None:
        return 'failed'
    before = int(bal['b'])
    if direction == 'debit' and before < amount:
        return 'insufficient'
    try:
        if direction == 'debit':
            cur.execute(f'UPDATE characters SET {account} = {account} - %s WHERE id = %s AND {account} >= %s', (amount, str(cid), amount))
        else:
            cur.execute(f'UPDATE characters SET {account} = {account} + %s WHERE id = %s', (amount, str(cid)))
        if fail_after_balance:
            raise RuntimeError('crash after balance update, before the journal')
        cur.execute(PSQL['journal'], (ref, str(cid), account, direction, amount, fp, 'cm-billing'))
        if fail_after_journal:
            raise RuntimeError('crash after the journal insert, before commit')
        if log:
            sign = -1 if direction == 'debit' else 1
            cur.execute(PSQL['log'], (cid, account, sign * amount, 'remove' if direction == 'debit' else 'add', ref[:100], 'cm-billing', before, before + sign * amount, '{}'))
        conn.commit()
        return 'applied'
    except pymysql.err.IntegrityError:
        conn.rollback()
    except RuntimeError:
        conn.rollback()
        return 'failed'
    cur.execute(PSQL['read'], (ref,)); row = cur.fetchone(); conn.commit()
    if row and row['fingerprint'] == fp:
        return 'replayed'
    return 'conflict' if row else 'failed'


try:
    c1 = connect(SCRATCH); conns.append(c1)
    cur = c1.cursor(pymysql.cursors.DictCursor)
    cur.execute('CREATE TABLE characters (id VARCHAR(50) PRIMARY KEY, cash INT DEFAULT 0, bank INT DEFAULT 0)')
    cur.execute(econ_ddl)
    for _ in range(2):
        cur.execute(pd_ddl)
    cur.execute('CREATE TABLE cm_families (id BIGINT UNSIGNED PRIMARY KEY, bank_balance BIGINT NOT NULL DEFAULT 0)')
    cur.execute("CREATE TABLE cm_family_bank_log (id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, family_id BIGINT UNSIGNED NOT NULL, character_id VARCHAR(64) NULL, direction ENUM('deposit','withdraw') NOT NULL, category VARCHAR(32) NULL, amount BIGINT NOT NULL, balance_after BIGINT NOT NULL, reason VARCHAR(128) NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)")
    for _ in range(2):
        cur.execute(fam_ddl)
    c1.commit()
    check('DDL both journal tables extracted from production source create and are repeatable', True)
    cur.execute("SELECT COUNT(*) AS n FROM information_schema.statistics WHERE table_schema = DATABASE() AND non_unique = 0 AND index_name IN ('uq_money_op_reference', 'uq_treasury_op_reference')")
    check('DDL UNIQUE(reference) exists on both journals', cur.fetchone()['n'] == 2)

    def set_bal(cid, bank):
        cur.execute('INSERT INTO characters (id, bank) VALUES (%s, %s) ON DUPLICATE KEY UPDATE bank = %s', (str(cid), bank, bank)); c1.commit()

    def get_bal(cid):
        cur.execute('SELECT bank FROM characters WHERE id = %s', (str(cid),)); b = int(cur.fetchone()['bank']); c1.commit(); return b

    # ------------------------------------------------------------------ LEGACY MODEL (pre-hardening), demonstrated and labelled
    def legacy_debit(conn, cursor, cid, amount, reason, log):
        """LEGACY: evidence = a generic economy_transactions row with this reason (only exists when logging is enabled)."""
        cursor.execute("SELECT COUNT(*) AS n FROM economy_transactions WHERE character_id = %s AND action = 'remove' AND reason = %s", (cid, reason)); seen = int(cursor.fetchone()['n']); conn.commit()
        if seen > 0:
            return 'replayed'
        cursor.execute('UPDATE characters SET bank = bank - %s WHERE id = %s AND bank >= %s', (amount, str(cid), amount))
        if cursor.rowcount != 1:
            conn.rollback(); return 'insufficient'
        if log:
            cursor.execute("INSERT INTO economy_transactions (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata) VALUES (%s, 'bank', %s, 'remove', %s, 'cm-billing', 0, 0, '{}')", (cid, -amount, reason))
        conn.commit(); return 'applied'

    set_bal(501, 10000)
    legacy_debit(c1, cur, 501, 3000, 'legacy-ref-1', log=False)
    again = legacy_debit(c1, cur, 501, 3000, 'legacy-ref-1', log=False)
    check('WEAKNESS legacy character debit with logging disabled: replay finds no evidence and debits AGAIN (10000 -> 4000)', again == 'applied' and get_bal(501) == 4000, (again, get_bal(501)))
    set_bal(502, 10000)
    gate = threading.Barrier(2)
    legacy_out = {}
    c2 = connect(SCRATCH); conns.append(c2); cur2 = c2.cursor(pymysql.cursors.DictCursor)

    def legacy_racer(key, conn, cursor):
        cursor.execute("SELECT COUNT(*) AS n FROM economy_transactions WHERE character_id = 502 AND action = 'remove' AND reason = 'legacy-ref-2'"); seen = int(cursor.fetchone()['n']); conn.commit()
        gate.wait()   # two independent callers both checked the evidence before either committed (no shared process lock)
        if seen == 0:
            cursor.execute('UPDATE characters SET bank = bank - 3000 WHERE id = 502 AND bank >= 3000')
            cursor.execute("INSERT INTO economy_transactions (character_id, account_type, amount, action, reason, resource_name, balance_before, balance_after, metadata) VALUES (502, 'bank', -3000, 'remove', 'legacy-ref-2', 'cm-billing', 0, 0, '{}')")
            conn.commit(); legacy_out[key] = 'applied'
    ts = [threading.Thread(target=legacy_racer, args=('a', c1, cur)), threading.Thread(target=legacy_racer, args=('b', c2, cur2))]
    for t in ts: t.start()
    for t in ts: t.join(15)
    check('WEAKNESS legacy model: two independent callers racing the same reference both debit (no DB uniqueness) -> 4000', get_bal(502) == 4000 and list(legacy_out.values()) == ['applied', 'applied'], (get_bal(502), legacy_out))

    # ------------------------------------------------------------------ CHARACTER JOURNAL
    set_bal(1, 10000); set_bal(2, 500)
    check('CHAR debit applies once with journal row + log', char_op(c1, cur, 'debit', 1, 'bank', 3000, 'rfd-c-0001') == 'applied' and get_bal(1) == 7000)
    check('CHAR replay is replayed and debits nothing', char_op(c1, cur, 'debit', 1, 'bank', 3000, 'rfd-c-0001') == 'replayed' and get_bal(1) == 7000)
    check('CHAR same reference with a different amount conflicts (no 10,000 + 12,000 style double debit)', char_op(c1, cur, 'debit', 1, 'bank', 12000, 'rfd-c-0001') == 'conflict' and get_bal(1) == 7000)
    check('CHAR same reference on another character / account / direction conflicts',
          char_op(c1, cur, 'debit', 2, 'bank', 3000, 'rfd-c-0001') == 'conflict' and char_op(c1, cur, 'debit', 1, 'cash', 3000, 'rfd-c-0001') == 'conflict'
          and char_op(c1, cur, 'credit', 1, 'bank', 3000, 'rfd-c-0001') == 'conflict' and get_bal(1) == 7000 and get_bal(2) == 500)
    cur.execute('DELETE FROM economy_transactions'); c1.commit()
    check('CHAR logging disabled/unavailable (generic log rows deleted): replay is STILL exact-once from the journal', char_op(c1, cur, 'debit', 1, 'bank', 3000, 'rfd-c-0001') == 'replayed' and get_bal(1) == 7000)
    check('CHAR logging disabled from the start: debit still applies exactly once', char_op(c1, cur, 'debit', 1, 'bank', 1000, 'rfd-c-nolog', log=False) == 'applied'
          and char_op(c1, cur, 'debit', 1, 'bank', 1000, 'rfd-c-nolog', log=False) == 'replayed' and get_bal(1) == 6000)
    check('CHAR insufficient funds changes nothing and is NOT journaled', char_op(c1, cur, 'debit', 2, 'bank', 5000, 'rfd-c-0002') == 'insufficient' and get_bal(2) == 500)
    cur.execute('SELECT COUNT(*) AS n FROM cm_character_money_operations WHERE reference = %s', ('rfd-c-0002',)); n = cur.fetchone()['n']; c1.commit()
    check('CHAR no tombstone for the insufficient reference', n == 0)
    set_bal(2, 9000)
    check('CHAR the SAME reference + payload is retryable once funds are restored', char_op(c1, cur, 'debit', 2, 'bank', 5000, 'rfd-c-0002') == 'applied' and get_bal(2) == 4000)
    check('CHAR credit direction is exactly-once too', char_op(c1, cur, 'credit', 2, 'bank', 700, 'rfd-c-0003') == 'applied' and char_op(c1, cur, 'credit', 2, 'bank', 700, 'rfd-c-0003') == 'replayed' and get_bal(2) == 4700)
    # rollback boundaries
    set_bal(3, 10000)
    check('CHAR crash AFTER the balance update, BEFORE the journal: whole transaction rolled back, balance intact, reference unused',
          char_op(c1, cur, 'debit', 3, 'bank', 2000, 'rfd-c-crash1', fail_after_balance=True) == 'failed' and get_bal(3) == 10000)
    check('CHAR crash AFTER the journal insert, BEFORE commit: balance AND journal rolled back together',
          char_op(c1, cur, 'debit', 3, 'bank', 2000, 'rfd-c-crash2', fail_after_journal=True) == 'failed' and get_bal(3) == 10000)
    cur.execute("SELECT COUNT(*) AS n FROM cm_character_money_operations WHERE reference IN ('rfd-c-crash1','rfd-c-crash2')"); n = cur.fetchone()['n']; c1.commit()
    check('CHAR no journal rows survive the rolled-back crashes', n == 0)
    check('CHAR those references then apply exactly once (the crashed attempts left nothing behind)',
          char_op(c1, cur, 'debit', 3, 'bank', 2000, 'rfd-c-crash1') == 'applied' and char_op(c1, cur, 'debit', 3, 'bank', 2000, 'rfd-c-crash1') == 'replayed' and get_bal(3) == 8000)
    # response loss + restart: the commit happened, the caller never saw it; a brand-new connection (process restart) replays
    check('CHAR DB commit but the caller lost the response: replay from a NEW connection (restart) returns replayed, no second debit',
          char_op(c1, cur, 'debit', 3, 'bank', 500, 'rfd-c-lost') == 'applied' and (lambda c: (lambda cr: char_op(c, cr, 'debit', 3, 'bank', 500, 'rfd-c-lost'))(c.cursor(pymysql.cursors.DictCursor)))(connect(SCRATCH)) == 'replayed' and get_bal(3) == 7500)
    # concurrent duplicates on independent connections
    set_bal(4, 10000)
    outs = {}
    gate = threading.Barrier(2)
    def racer(key, conn, cursor):
        gate.wait(); outs[key] = char_op(conn, cursor, 'debit', 4, 'bank', 3000, 'rfd-c-race')
    ts = [threading.Thread(target=racer, args=('a', c1, cur)), threading.Thread(target=racer, args=('b', c2, cur2))]
    for t in ts: t.start()
    for t in ts: t.join(15)
    cur.execute('SELECT COUNT(*) AS n FROM cm_character_money_operations WHERE reference = %s', ('rfd-c-race',)); n = cur.fetchone()['n']; c1.commit()
    check('CHAR two independent connections racing the same reference: exactly one debit (7000), one journal row, results applied+replayed',
          sorted(outs.values()) == ['applied', 'replayed'] and get_bal(4) == 7000 and n == 1, (outs, get_bal(4), n))
    # conflicting duplicates racing: 10,000 vs 12,000
    set_bal(5, 50000)
    outs.clear(); gate = threading.Barrier(2)
    def racer2(key, conn, cursor, amount):
        gate.wait(); outs[key] = char_op(conn, cursor, 'debit', 5, 'bank', amount, 'rfd-c-conf')
    ts = [threading.Thread(target=racer2, args=('a', c1, cur, 10000)), threading.Thread(target=racer2, args=('b', c2, cur2, 12000))]
    for t in ts: t.start()
    for t in ts: t.join(15)
    check('CHAR racing conflicting payloads (10,000 vs 12,000) on one reference: only one is applied, never 22,000', get_bal(5) in (40000, 38000) and sorted(outs.values()) == ['applied', 'conflict'], (outs, get_bal(5)))

    # ------------------------------------------------------------------ FAMILY JOURNAL
    def fam_op(conn, cursor, fid, amount, ref, log=True, fail_after_balance=False, fail_after_journal=False):
        fp = f'debit|{fid}|{amount}'
        cursor.execute(FSQL['read'], (ref,)); row = cursor.fetchone(); conn.commit()
        if row:
            return 'replayed' if row['fingerprint'] == fp else 'conflict'
        cursor.execute('SELECT bank_balance FROM cm_families WHERE id = %s', (fid,)); b = cursor.fetchone(); conn.commit()
        if not b or int(b['bank_balance']) < amount:
            return 'insufficient'
        try:
            cursor.execute(FSQL['debit'], (amount, fid, amount))
            if fail_after_balance:
                raise RuntimeError('crash')
            cursor.execute(FSQL['journal'], (ref, fid, amount, fp))
            if fail_after_journal:
                raise RuntimeError('crash')
            if log:
                cursor.execute(FSQL['log'], (fid, 'refund', amount, fid, ref))
            conn.commit(); return 'applied'
        except pymysql.err.IntegrityError:
            conn.rollback()
        except RuntimeError:
            conn.rollback(); return 'failed'
        cursor.execute(FSQL['read'], (ref,)); row = cursor.fetchone(); conn.commit()
        return 'replayed' if row and row['fingerprint'] == fp else ('conflict' if row else 'failed')

    def set_fam(fid, bal):
        cur.execute('INSERT INTO cm_families (id, bank_balance) VALUES (%s, %s) ON DUPLICATE KEY UPDATE bank_balance = %s', (fid, bal, bal)); c1.commit()
    def get_fam(fid):
        cur.execute('SELECT bank_balance FROM cm_families WHERE id = %s', (fid,)); b = int(cur.fetchone()['bank_balance']); c1.commit(); return b

    # legacy family evidence = bank-log row with the reason; with the log lost the replay debits again
    set_fam(90, 10000)
    cur.execute('UPDATE cm_families SET bank_balance = bank_balance - 4000 WHERE id = 90'); c1.commit()   # legacy debit committed, log row then lost / never written
    cur.execute("SELECT COUNT(*) AS n FROM cm_family_bank_log WHERE family_id = 90 AND direction = 'withdraw' AND reason = 'legacy-fam'"); seen = cur.fetchone()['n']; c1.commit()
    if seen == 0:
        cur.execute('UPDATE cm_families SET bank_balance = bank_balance - 4000 WHERE id = 90 AND bank_balance >= 4000'); c1.commit()
    check('WEAKNESS legacy family debit: bank-log evidence missing => the replay debits AGAIN (10000 -> 2000)', get_fam(90) == 2000, get_fam(90))

    set_fam(10, 10000)
    check('FAMILY debit applies once with journal row + bank log', fam_op(c1, cur, 10, 4000, 'rfd-f-0001') == 'applied' and get_fam(10) == 6000)
    check('FAMILY replay debits nothing', fam_op(c1, cur, 10, 4000, 'rfd-f-0001') == 'replayed' and get_fam(10) == 6000)
    check('FAMILY same reference with a different amount conflicts', fam_op(c1, cur, 10, 5000, 'rfd-f-0001') == 'conflict' and get_fam(10) == 6000)
    cur.execute('DELETE FROM cm_family_bank_log'); c1.commit()
    check('FAMILY bank log lost/unavailable: replay is STILL exact-once from the journal', fam_op(c1, cur, 10, 4000, 'rfd-f-0001') == 'replayed' and get_fam(10) == 6000)
    check('FAMILY logging unavailable from the start: still exactly once', fam_op(c1, cur, 10, 1000, 'rfd-f-nolog', log=False) == 'applied' and fam_op(c1, cur, 10, 1000, 'rfd-f-nolog', log=False) == 'replayed' and get_fam(10) == 5000)
    check('FAMILY insufficient treasury changes nothing and is not journaled', fam_op(c1, cur, 10, 50000, 'rfd-f-0002') == 'insufficient' and get_fam(10) == 5000)
    cur.execute('SELECT COUNT(*) AS n FROM cm_family_treasury_operations WHERE reference = %s', ('rfd-f-0002',)); n = cur.fetchone()['n']; c1.commit()
    check('FAMILY no tombstone for the insufficient reference', n == 0)
    set_fam(10, 80000)
    check('FAMILY same reference + payload retryable after replenishment', fam_op(c1, cur, 10, 50000, 'rfd-f-0002') == 'applied' and get_fam(10) == 30000)
    set_fam(11, 10000)
    check('FAMILY crash after balance update before journal: rolled back, treasury intact', fam_op(c1, cur, 11, 2000, 'rfd-f-crash1', fail_after_balance=True) == 'failed' and get_fam(11) == 10000)
    check('FAMILY crash after journal insert before commit: balance and journal rolled back together', fam_op(c1, cur, 11, 2000, 'rfd-f-crash2', fail_after_journal=True) == 'failed' and get_fam(11) == 10000)
    check('FAMILY the crashed references apply exactly once afterwards', fam_op(c1, cur, 11, 2000, 'rfd-f-crash1') == 'applied' and fam_op(c1, cur, 11, 2000, 'rfd-f-crash1') == 'replayed' and get_fam(11) == 8000)
    check('FAMILY commit then response lost: replay from a NEW connection (restart) returns replayed', fam_op(c1, cur, 11, 500, 'rfd-f-lost') == 'applied'
          and (lambda c: fam_op(c, c.cursor(pymysql.cursors.DictCursor), 11, 500, 'rfd-f-lost'))(connect(SCRATCH)) == 'replayed' and get_fam(11) == 7500)
    set_fam(12, 10000)
    outs.clear(); gate = threading.Barrier(2)
    def fracer(key, conn, cursor):
        gate.wait(); outs[key] = fam_op(conn, cursor, 12, 3000, 'rfd-f-race')
    ts = [threading.Thread(target=fracer, args=('a', c1, cur)), threading.Thread(target=fracer, args=('b', c2, cur2))]
    for t in ts: t.start()
    for t in ts: t.join(15)
    cur.execute('SELECT COUNT(*) AS n FROM cm_family_treasury_operations WHERE reference = %s', ('rfd-f-race',)); n = cur.fetchone()['n']; c1.commit()
    check('FAMILY two independent connections racing one reference: exactly one debit (7000), one journal row', sorted(outs.values()) == ['applied', 'replayed'] and get_fam(12) == 7000 and n == 1, (outs, get_fam(12), n))
    set_fam(13, 50000)
    outs.clear(); gate = threading.Barrier(2)
    def fracer2(key, conn, cursor, amount):
        gate.wait(); outs[key] = fam_op(conn, cursor, 13, amount, 'rfd-f-conf')
    ts = [threading.Thread(target=fracer2, args=('a', c1, cur, 10000)), threading.Thread(target=fracer2, args=('b', c2, cur2, 12000))]
    for t in ts: t.start()
    for t in ts: t.join(15)
    check('FAMILY racing conflicting payloads (10,000 vs 12,000): only one applies, never 22,000', get_fam(13) in (40000, 38000) and sorted(outs.values()) == ['applied', 'conflict'], (outs, get_fam(13)))
    try:
        cur.execute('UPDATE cm_families SET bank_balance = bank_balance - 99999999 WHERE id = 13 AND bank_balance >= 99999999')
        ok_guard = cur.rowcount == 0
    except Exception:
        ok_guard = True
    c1.rollback()
    check('FAMILY the guarded UPDATE never drives the treasury negative', ok_guard and get_fam(13) >= 0)
    try:
        cur.execute(FSQL['debit'], (1, 10, 1)); cur.execute(FSQL['journal'], ('rfd-f-0001', 10, 1, 'x')); dup = False
    except pymysql.err.IntegrityError:
        dup = True
    c1.rollback()
    check('FAMILY UNIQUE reference rejects a duplicate journal row in MySQL', dup)
    # ------------------------------------------------------------------ PAYMENT-TIME DESTINATION CREDITS (same journals, direction credit)
    MAXBAL = 2000000000

    def fam_credit(conn, cursor, fid, amount, ref, log=True):
        """Mirror of CreditFamilyTreasuryOnce. Returns ('applied'|'replayed'|'conflict'|'full', accepted)."""
        fp = f'credit|{fid}|{amount}'
        cursor.execute(FSQL['read'], (ref,)); row = cursor.fetchone(); conn.commit()
        if row:
            return ('replayed' if row['fingerprint'] == fp else 'conflict', int(row['amount']))
        cursor.execute('SELECT bank_balance FROM cm_families WHERE id = %s', (fid,)); bal = int(cursor.fetchone()['bank_balance']); conn.commit()
        accepted = min(amount, max(0, MAXBAL - bal))
        if accepted < 1:
            return ('full', 0)
        try:
            cursor.execute(FCSQL['credit'], (accepted, fid, accepted, MAXBAL))
            cursor.execute(FCSQL['journal'], (ref, fid, accepted, fp))
            if log:
                cursor.execute(FCSQL['log'], (fid, 'invoice', accepted, fid, ref))
            conn.commit()
            return ('applied', accepted)
        except pymysql.err.IntegrityError:
            conn.rollback()
            cursor.execute(FSQL['read'], (ref,)); row = cursor.fetchone(); conn.commit()
            return ('replayed' if row and row['fingerprint'] == fp else 'conflict', int(row['amount']) if row else 0)

    set_fam(20, 7000)
    check('PAY family credit applies once and journals the ACCEPTED amount', fam_credit(c1, cur, 20, 3000, 'cm-billing-pay-credit:INV-A1') == ('applied', 3000) and get_fam(20) == 10000)
    check('PAY family credit replay (response lost) returns the original accepted amount, no second credit', fam_credit(c1, cur, 20, 3000, 'cm-billing-pay-credit:INV-A1') == ('replayed', 3000) and get_fam(20) == 10000)
    check('PAY family credit with a different request on the same reference conflicts', fam_credit(c1, cur, 20, 3500, 'cm-billing-pay-credit:INV-A1')[0] == 'conflict' and get_fam(20) == 10000)
    check('PAY family credit vs debit on the same reference conflicts (direction is in the fingerprint)', fam_op(c1, cur, 20, 3000, 'cm-billing-pay-credit:INV-A1') == 'conflict' and get_fam(20) == 10000)
    cur.execute('DELETE FROM cm_family_bank_log'); c1.commit()
    check('PAY family bank log gone: replay still exact-once from the journal', fam_credit(c1, cur, 20, 3000, 'cm-billing-pay-credit:INV-A1') == ('replayed', 3000) and get_fam(20) == 10000)
    check('PAY family credit with logging unavailable from the start still applies exactly once', fam_credit(c1, cur, 20, 500, 'cm-billing-pay-credit:INV-A2', log=False) == ('applied', 500)
          and fam_credit(c1, cur, 20, 500, 'cm-billing-pay-credit:INV-A2', log=False)[0] == 'replayed' and get_fam(20) == 10500)
    set_fam(21, MAXBAL - 1000)
    check('PAY family capacity: accepts only 1000 of 3000 (accepted amount is authoritative; remainder 2000 returns to the payer)', fam_credit(c1, cur, 21, 3000, 'cm-billing-pay-credit:INV-A3') == ('applied', 1000)
          and get_fam(21) == MAXBAL and fam_credit(c1, cur, 21, 3000, 'cm-billing-pay-credit:INV-A3') == ('replayed', 1000) and get_fam(21) == MAXBAL)
    check('PAY family full treasury is not journaled (retryable)', fam_credit(c1, cur, 21, 100, 'cm-billing-pay-credit:INV-A4') == ('full', 0))
    cur.execute('SELECT COUNT(*) AS n FROM cm_family_treasury_operations WHERE reference = %s', ('cm-billing-pay-credit:INV-A4',)); n = cur.fetchone()['n']; c1.commit()
    check('PAY family full treasury leaves no journal row', n == 0)
    check('PAY family response lost then DB-only recovery from a NEW connection (owner restart): replayed, no double credit',
          fam_credit(c1, cur, 20, 700, 'cm-billing-pay-credit:INV-A5')[0] == 'applied'
          and (lambda c: fam_credit(c, c.cursor(pymysql.cursors.DictCursor), 20, 700, 'cm-billing-pay-credit:INV-A5'))(connect(SCRATCH)) == ('replayed', 700) and get_fam(20) == 11200)
    set_fam(22, 1000)
    outs.clear(); gate = threading.Barrier(2)

    def pracer(key, conn, cursor):
        gate.wait(); outs[key] = fam_credit(conn, cursor, 22, 2500, 'cm-billing-pay-credit:INV-RACE')

    ts = [threading.Thread(target=pracer, args=('a', c1, cur)), threading.Thread(target=pracer, args=('b', c2, cur2))]
    for t in ts: t.start()
    for t in ts: t.join(15)
    check('PAY family two recovery workers racing one invoice credit exactly once (3500)', sorted(v[0] for v in outs.values()) == ['applied', 'replayed'] and get_fam(22) == 3500, (outs, get_fam(22)))
    set_fam(23, 5000)
    fam_credit(c1, cur, 23, 3000, 'cm-billing-pay-credit:INV-RT')
    check('PAY family payment -> refund roundtrip: refund debit uses its own reference and the treasury returns to its start', fam_op(c1, cur, 23, 3000, 'cm-billing-rfd-debit:INV-RT:1') == 'applied'
          and get_fam(23) == 5000 and fam_op(c1, cur, 23, 3000, 'cm-billing-rfd-debit:INV-RT:1') == 'replayed' and get_fam(23) == 5000)
    set_bal(30, 5000); set_bal(31, 10000)
    check('PAY character payment: payer debit + destination credit, each exactly once under distinct references',
          char_op(c1, cur, 'debit', 31, 'bank', 4000, 'cm-billing-pay-debit:INV-RC') == 'applied' and char_op(c1, cur, 'credit', 30, 'bank', 4000, 'cm-billing-pay-credit:INV-RC') == 'applied'
          and char_op(c1, cur, 'credit', 30, 'bank', 4000, 'cm-billing-pay-credit:INV-RC') == 'replayed' and get_bal(31) == 6000 and get_bal(30) == 9000)
    check('PAY character: reusing a payment credit reference as a debit conflicts', char_op(c1, cur, 'debit', 30, 'bank', 4000, 'cm-billing-pay-credit:INV-RC') == 'conflict' and get_bal(30) == 9000)
    check('PAY character payment -> refund roundtrip returns both balances exactly',
          char_op(c1, cur, 'debit', 30, 'bank', 4000, 'cm-billing-rfd-debit:INV-RC:1') == 'applied' and char_op(c1, cur, 'credit', 31, 'bank', 4000, 'cm-billing-rfd-credit:INV-RC:1') == 'applied'
          and get_bal(30) == 5000 and get_bal(31) == 10000)
    cur.execute('DELETE FROM economy_transactions'); c1.commit()
    check('PAY character logging off: every payment/refund reference still replays from the journal', all(char_op(c1, cur, d, c, 'bank', 4000, r) == 'replayed' for d, c, r in [
        ('debit', 31, 'cm-billing-pay-debit:INV-RC'), ('credit', 30, 'cm-billing-pay-credit:INV-RC'), ('debit', 30, 'cm-billing-rfd-debit:INV-RC:1'), ('credit', 31, 'cm-billing-rfd-credit:INV-RC:1')])
          and get_bal(30) == 5000 and get_bal(31) == 10000)
finally:
    for c in conns:
        try:
            c.close()
        except Exception:
            pass
    adm = admin.cursor()
    adm.execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
    print(f'scratch database dropped: {SCRATCH}')
    adm.execute('SHOW DATABASES LIKE %s', ('cm_jrnl_smoke_%',))
    check('CLEANUP no scratch database remains', len(adm.fetchall()) == 0)

print(f'\ncm-billing owner journal MySQL smoke: {passed} passed, {failed} failed')
sys.exit(0 if failed == 0 else 1)
