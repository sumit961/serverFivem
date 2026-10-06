"""Isolated MySQL smoke test for the two-character item exchange SQL (server/exchange.lua).

    python -u tests/exchange_mysql_smoke.py      (from resources/[core]/cm-inventory; needs `pip install pymysql`)

SAFETY: connects with the local development `mysql_connection_string` (read from server.local.cfg, never printed), creates a SCRATCH database
cm_xchg_smoke_<pid>, never touches another schema, and DROPs it at the end (open transactions are closed first). Real player inventories are never read.

The statements are asserted to appear VERBATIM in exchange.lua / craft.lua and executed in the order the Lua uses, in real InnoDB transactions with two
connections: DDL, the (owner_type, owner_id, slot) UNIQUE key, the two-phase move (swap cycles), rollback, UNIQUE ledger reference + replay, row-lock waiting,
and the lock-ORDER proof (lowest id first never deadlocks; opposite order does). The planning logic is Lua (see exchange_selftest.lua); here the plan is fixed.
"""
import os
import re
import sys
import threading
import time
from urllib.parse import urlparse

import pymysql

HERE = os.path.dirname(os.path.abspath(__file__))
INV = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(INV, '..', '..', '..'))
passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond:
        passed += 1
        print('PASS  ' + name)
    else:
        failed += 1
        print('FAIL  ' + name + (f'  ({detail})' if detail is not None else ''))


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


ex_src = open(os.path.join(INV, 'server', 'exchange.lua'), encoding='utf-8').read()
craft_src = open(os.path.join(INV, 'server', 'craft.lua'), encoding='utf-8').read()
db_src = open(os.path.join(INV, 'server', 'db.lua'), encoding='utf-8').read()
both = norm(ex_src) + ' ' + norm(craft_src)


def sql(text):
    assert norm(text) in both, 'statement drifted from the Lua source: ' + norm(text)
    return text.replace('?', '%s')


def ddl(src, table):
    m = re.search(r'(CREATE TABLE IF NOT EXISTS ' + table + r' \(.*?\n\s*\))\s*\]\]', src, re.S)
    assert m, table
    return m.group(1)


ROWS_LOCK = sql('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY id FOR UPDATE')
LEDGER_SEL = sql('SELECT reference, character_id, payload, result_json FROM cm_inventory_transactions WHERE reference = ?')
CHAR = sql('SELECT id FROM characters WHERE id = ? LIMIT 1')
UPD_Q = sql('UPDATE inventory_items SET quantity = ? WHERE id = ? AND quantity = ?')
DEL = sql('DELETE FROM inventory_items WHERE id = ? AND quantity = ?')
MOVE1 = sql('UPDATE inventory_items SET owner_id = ?, slot = ? WHERE id = ? AND owner_type = ? AND owner_id = ? AND quantity = ?')
INS = sql('INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata) VALUES (?, ?, ?, ?, ?, ?)')
MOVE2 = sql('UPDATE inventory_items SET slot = ? WHERE id = ? AND owner_type = ? AND owner_id = ? AND slot = ?')
AUDIT = sql('INSERT INTO inventory_audit (character_id, action, item_name, quantity, from_slot, to_slot, reason) VALUES (?, ?, ?, ?, ?, ?, ?)')
LEDGER_INS = sql("""INSERT INTO cm_inventory_transactions
                        (reference, tx_type, character_id, payload_hash, payload, status, result_json, committed_at)
                        VALUES (?, ?, ?, ?, ?, 'committed', ?, NOW())""")
LEDGER_LOCK = sql('SELECT status, result_json, payload FROM cm_inventory_transactions WHERE reference = ? FOR UPDATE')
PREP_INS = sql("""INSERT INTO cm_inventory_transactions
                (reference, tx_type, character_id, payload_hash, payload, status, result_json)
                VALUES (?, ?, ?, ?, ?, 'prepared', ?)""")
TOMB_INS = sql("""INSERT INTO cm_inventory_transactions
                (reference, tx_type, character_id, payload_hash, payload, status, result_json)
                VALUES (?, ?, ?, ?, ?, 'not_applied', ?)""")
CAS_LEASE = sql("""UPDATE cm_inventory_transactions SET result_json = ?
            WHERE reference = ? AND status = 'prepared' AND result_json = ?""")
CAS_TERM = sql("""UPDATE cm_inventory_transactions SET status = 'not_applied', result_json = ?
            WHERE reference = ? AND status = 'prepared' AND result_json = ?""")
COMMIT_UPD = sql("""UPDATE cm_inventory_transactions SET status = 'committed', result_json = ?, committed_at = NOW()
                        WHERE reference = ? AND status = 'prepared' AND result_json = ?""")
check('SQL every statement used here appears verbatim in exchange.lua / craft.lua', True)

cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
u = urlparse(re.search(r'mysql_connection_string\s+"?([^"\n]+)', cfg).group(1).strip())
SCRATCH = f'cm_xchg_smoke_{os.getpid()}'
args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', autocommit=False, charset='utf8mb4')


def connect(db=None):
    return pymysql.connect(database=db, **args)


admin = connect(); admin.autocommit(True)
admin.cursor().execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
print(f'scratch database created: {SCRATCH}')
conns = []
try:
    c1 = connect(SCRATCH); conns.append(c1)
    cur = c1.cursor(pymysql.cursors.DictCursor)
    ledger_ddl = re.search(r'(CREATE TABLE IF NOT EXISTS cm_inventory_transactions \(.*?\n\s*\))\s*\]\]', craft_src, re.S).group(1)
    for _ in range(2):
        for stmt in (ddl(db_src, 'inventory_items'), ddl(db_src, 'inventory_audit'), ledger_ddl, 'CREATE TABLE IF NOT EXISTS characters (id BIGINT PRIMARY KEY)'):
            cur.execute(stmt)
    cur.execute('INSERT INTO characters (id) VALUES (1),(2)'); c1.commit()
    check('DDL tables create and are repeatable (extracted from the Lua source)', True)

    def seed():
        cur.execute('DELETE FROM inventory_items'); cur.execute('DELETE FROM cm_inventory_transactions'); cur.execute('DELETE FROM inventory_audit')
        rows = [('1', 'pocket-1', 'water', 10, None), ('1', 'pocket-2', 'rare_gem', 1, '{"serial":"S1","durability":70}'),
                ('2', 'pocket-1', 'sandwich', 4, None), ('2', 'pocket-2', 'rare_gem', 1, '{"serial":"S2","durability":55}')]
        for o, s, i, q, m in rows:
            cur.execute(INS, ('character', o, s, i, q, m))
        c1.commit()

    def state():
        cur.execute('SELECT id, owner_id, slot, item_name, quantity, metadata FROM inventory_items ORDER BY id')
        r = [tuple(x.values()) for x in cur.fetchall()]; c1.commit(); return r

    def rowid(owner, item):
        cur.execute('SELECT id FROM inventory_items WHERE owner_id = %s AND item_name = %s', (owner, item)); r = cur.fetchone(); c1.commit(); return r['id']

    def prepare(ref, lease):
        cur.execute(PREP_INS, (ref, 'trade_exchange', '1', 'deadbeefdeadbeef', '{payload}', lease)); c1.commit()

    def exchange(conn, cr, ref, fail_at=None, order=('1', '2'), hold=None, lease=None):
        """The Lua sequence: A(1) gives 4 water + its gem; B(2) gives 2 sandwich + its gem. Gems swap in place (two-phase)."""
        try:
            for who in order:
                cr.execute(ROWS_LOCK, ('character', who)); cr.fetchall()
                if hold and who == order[0]:
                    hold()
            lease = lease or ('L-' + ref)
            cr.execute(LEDGER_LOCK, (ref,))
            led = cr.fetchall()
            if not led or led[0]['status'] != 'prepared' or led[0]['result_json'] != lease:
                conn.rollback(); return 'lost:' + (led[0]['status'] if led else 'none')
            for c in ('1', '2'):
                cr.execute(CHAR, (c,)); assert cr.fetchall()
            water, sandwich = rowid_cache['water'], rowid_cache['sandwich']
            gemA, gemB = rowid_cache['gemA'], rowid_cache['gemB']
            assert cr.execute(UPD_Q, (6, water, 10)) == 1
            assert cr.execute(UPD_Q, (2, sandwich, 4)) == 1
            if fail_at == 'after_remove': raise RuntimeError('injected')
            assert cr.execute(MOVE1, ('2', f'xfer-{gemA}', gemA, 'character', '1', 1)) == 1
            assert cr.execute(MOVE1, ('1', f'xfer-{gemB}', gemB, 'character', '2', 1)) == 1
            cr.execute(INS, ('character', '2', 'pocket-3', 'water', 4, None))
            cr.execute(INS, ('character', '1', 'pocket-3', 'sandwich', 2, None))
            if fail_at == 'after_add': raise RuntimeError('injected')
            assert cr.execute(MOVE2, ('pocket-2', gemA, 'character', '2', f'xfer-{gemA}')) == 1
            assert cr.execute(MOVE2, ('pocket-2', gemB, 'character', '1', f'xfer-{gemB}')) == 1
            for c, act, item, q in (('1', 'trade_out', 'water', 4), ('2', 'trade_in', 'water', 4)):
                cr.execute(AUDIT, (c, act, item, q, None, None, ref))
            if fail_at == 'before_ledger': raise RuntimeError('injected')
            assert cr.execute(COMMIT_UPD, ('{"pieces":4}', ref, lease)) == 1
            conn.commit(); return 'committed'
        except pymysql.err.OperationalError as e:
            conn.rollback(); return f'oper:{e.args[0]}'
        except Exception as e:
            conn.rollback(); return 'rolled_back:' + type(e).__name__

    seed()
    rowid_cache = {'water': rowid('1', 'water'), 'sandwich': rowid('2', 'sandwich'), 'gemA': rowid('1', 'rare_gem'), 'gemB': rowid('2', 'rare_gem')}
    before = state()
    prepare('TRD-SMOKE0001', 'L-TRD-SMOKE0001')
    r = exchange(c1, cur, 'TRD-SMOKE0001')
    after = state()
    check('EXCHANGE commits both directions in one transaction', r == 'committed', r)
    idmap = {row[0]: row for row in after}
    gemA_now, gemB_now = idmap[rowid_cache['gemA']], idmap[rowid_cache['gemB']]
    check('EXCHANGE unique gems swapped owners IN PLACE (same row ids, metadata and slot rewritten without a UNIQUE collision)',
          gemA_now[1] == '2' and gemA_now[2] == 'pocket-2' and '"S1"' in gemA_now[5] and gemB_now[1] == '1' and gemB_now[2] == 'pocket-2' and '"S2"' in gemB_now[5], (gemA_now, gemB_now))
    cur.execute("SELECT item_name, owner_id, SUM(quantity) q FROM inventory_items WHERE item_name IN ('water','sandwich') GROUP BY item_name, owner_id ORDER BY item_name, owner_id"); sums = [(x['item_name'], x['owner_id'], int(x['q'])) for x in cur.fetchall()]; c1.commit()
    check('EXCHANGE quantities moved exactly (water 6/4, sandwich 2/2) and nothing was minted', sums == [('sandwich', '1', 2), ('sandwich', '2', 2), ('water', '1', 6), ('water', '2', 4)], sums)
    cur.execute('SELECT status FROM cm_inventory_transactions WHERE reference = %s', ('TRD-SMOKE0001',)); st1 = cur.fetchone()['status']; c1.commit()
    check('LIFECYCLE prepared -> committed in the same transaction as the item moves', st1 == 'committed', st1)
    check('REPLAY a committed reference is no longer claimable: a second executor loses the guard and changes nothing', exchange(c1, cur, 'TRD-SMOKE0001') == 'lost:committed' and state() == after)
    try:
        cur.execute(LEDGER_INS, ('TRD-SMOKE0001', 'trade_exchange', '1', 'x' * 16, 'p', '{}')); dup = False
    except pymysql.err.IntegrityError:
        dup = True
    c1.rollback()
    check('UNIQUE a second ledger row for the same reference is refused by MySQL', dup)

    # naive swap proves the temp-slot design is necessary
    try:
        seed(); rid = {'a': rowid('1', 'rare_gem'), 'b': rowid('2', 'rare_gem')}
        cur.execute(MOVE1, ('2', 'pocket-2', rid['a'], 'character', '1', 1)); naive = False
    except pymysql.err.IntegrityError:
        naive = True
    c1.rollback()
    check('UNIQUE (owner,slot): a direct in-place swap collides, which is why the exchange moves through unique temporary slots', naive)

    # rollback at every boundary
    for point in ('after_remove', 'after_add', 'before_ledger'):
        seed(); rowid_cache.update({'water': rowid('1', 'water'), 'sandwich': rowid('2', 'sandwich'), 'gemA': rowid('1', 'rare_gem'), 'gemB': rowid('2', 'rare_gem')})
        pre = state()
        prepare('TRD-SMOKEF' + point[:3], 'L-TRD-SMOKEF' + point[:3])
        r = exchange(c1, cur, 'TRD-SMOKEF' + point[:3], fail_at=point)
        cur.execute("SELECT COUNT(*) n FROM cm_inventory_transactions WHERE status = 'committed'"); n_led = cur.fetchone()['n']; cur.execute('SELECT COUNT(*) n FROM inventory_audit'); n_aud = cur.fetchone()['n']; c1.commit()
        cur.execute('SELECT status FROM cm_inventory_transactions WHERE reference = %s', ('TRD-SMOKEF' + point[:3],)); stf = cur.fetchone()['status']; c1.commit()
        check(f'ROLLBACK failure {point} reverts both inventories, audit and the commit marker (row stays prepared)', r.startswith('rolled_back') and state() == pre and n_led == 0 and n_aud == 0 and stf == 'prepared', (r, stf))

    # concurrency: A<->B (1 then 2) and B<->A (opposite order, as an unsorted implementation would): the proof of lock ORDER
    c2 = connect(SCRATCH); conns.append(c2)
    cur2 = c2.cursor(pymysql.cursors.DictCursor)

    def run_pair(order1, order2, ref1, ref2):
        seed(); rowid_cache.update({'water': rowid('1', 'water'), 'sandwich': rowid('2', 'sandwich'), 'gemA': rowid('1', 'rare_gem'), 'gemB': rowid('2', 'rare_gem')})
        prepare(ref1, 'L-' + ref1)
        if ref2 != ref1: prepare(ref2, 'L-' + ref2)
        res = {}
        barrier = threading.Barrier(2)

        def slow():
            barrier.wait(5); time.sleep(0.6)

        def t1():
            res['1'] = exchange(c1, cur, ref1, order=order1, hold=slow)

        def t2():
            barrier.wait(5)
            res['2'] = exchange(c2, cur2, ref2, order=order2, hold=slow2)

        slow2 = lambda: time.sleep(0.2)
        th = [threading.Thread(target=t1), threading.Thread(target=t2)]
        for t in th: t.start()
        for t in th: t.join(30)
        return res

    # same exchange submitted twice concurrently under the SAME sorted order: second waits, then replays
    res = run_pair(('1', '2'), ('1', '2'), 'TRD-SMOKEDUP1', 'TRD-SMOKEDUP1')
    cur.execute('SELECT COUNT(*) n FROM cm_inventory_transactions WHERE reference = %s', ('TRD-SMOKEDUP1',)); n = cur.fetchone()['n']; c1.commit()
    check('LOCK ORDER same-order double submit: one commits, the other waits on the row locks and loses the lease guard; exactly one ledger row', sorted(res.values()) == ['committed', 'lost:committed'] and n == 1, res)
    # opposite lock order = classic deadlock; MySQL kills one victim (error 1213). The implementation therefore ALWAYS locks the lowest character id first.
    res2 = run_pair(('1', '2'), ('2', '1'), 'TRD-SMOKEDL01', 'TRD-SMOKEDL02')
    deadlocked = any(v.startswith('oper:1213') or v.startswith('oper:1205') for v in res2.values())
    check('LOCK ORDER evidence: acquiring the two characters in OPPOSITE orders deadlocks in MySQL (so sorted order is mandatory)', deadlocked, res2)
    res3 = run_pair(('1', '2'), ('1', '2'), 'TRD-SMOKESRT1', 'TRD-SMOKESRT2')
    check('LOCK ORDER sorted order: two different exchanges over the same two characters never deadlock (one commits; the other waits and then fails its guard cleanly)', not any(v.startswith('oper:') for v in res3.values()) and 'committed' in res3.values(), res3)
    # ---------------------------------------------------------------- ledger lifecycle (the crash-recovery proofs)
    def status_of(ref):
        cur.execute('SELECT status, result_json FROM cm_inventory_transactions WHERE reference = %s', (ref,)); r = cur.fetchone(); c1.commit(); return r

    # 1. fence never-submitted: tombstone; later prepare of the same reference is impossible (UNIQUE) -> late submit can never claim
    cur.execute(TOMB_INS, ('TRD-FENCE0001', 'trade_exchange', '0', '0' * 16, '', '{"reason":"fenced"}')); c1.commit()
    try:
        cur.execute(PREP_INS, ('TRD-FENCE0001', 'trade_exchange', '1', 'x' * 16, 'p', '{}')); late = False
    except pymysql.err.IntegrityError:
        late = True
    c1.rollback()
    check('TERMINAL a fenced (never-submitted) reference cannot be claimed afterwards: UNIQUE refuses the late prepare', late and status_of('TRD-FENCE0001')['status'] == 'not_applied')

    # 2. lease reclaim is a compare-and-set: exactly one of two reclaimers wins
    prepare('TRD-LEASE0001', 'OLD'); c2 = connect(SCRATCH); conns.append(c2); cur2 = c2.cursor(pymysql.cursors.DictCursor)
    w1 = cur.execute(CAS_LEASE, ('NEW1', 'TRD-LEASE0001', 'OLD')); c1.commit()
    w2 = cur2.execute(CAS_LEASE, ('NEW2', 'TRD-LEASE0001', 'OLD')); c2.commit()
    check('LEASE two reclaimers racing on the same stale lease: exactly one compare-and-set wins', (w1, w2) == (1, 0) and status_of('TRD-LEASE0001')['result_json'] == 'NEW1', (w1, w2))

    # 3. a zombie executor holding the OLD lease cannot commit after the reclaim (guarded marker updates 0 rows)
    zr = cur2.execute(COMMIT_UPD, ('{"pieces":1}', 'TRD-LEASE0001', 'OLD')); c2.rollback()
    check('LEASE a zombie executor with the superseded lease updates 0 rows, so its whole transaction must roll back', zr == 0)

    # 4. fence (terminal) vs commit marker: whoever updates first wins; the loser changes nothing
    prepare('TRD-FENCE0002', 'L1')
    t = cur.execute(CAS_TERM, ('{"reason":"fenced_stale"}', 'TRD-FENCE0002', 'L1')); c1.commit()
    cm = cur2.execute(COMMIT_UPD, ('{"pieces":1}', 'TRD-FENCE0002', 'L1')); c2.rollback()
    check('TERMINAL once fenced to not_applied the commit marker matches 0 rows (a late executor can never commit)', t == 1 and cm == 0 and status_of('TRD-FENCE0002')['status'] == 'not_applied', (t, cm))
    prepare('TRD-FENCE0003', 'L1')
    cm2 = cur2.execute(COMMIT_UPD, ('{"pieces":1}', 'TRD-FENCE0003', 'L1')); c2.commit()
    t2 = cur.execute(CAS_TERM, ('{"reason":"fenced_stale"}', 'TRD-FENCE0003', 'L1')); c1.commit()
    check('TERMINAL once committed, a fence matches 0 rows (committed is never revoked)', cm2 == 1 and t2 == 0 and status_of('TRD-FENCE0003')['status'] == 'committed', (cm2, t2))

    # 5. fence queued behind a transaction that holds the ledger row lock: it waits, then sees committed (InnoDB row lock)
    prepare('TRD-FENCE0004', 'L1')
    holder = {}

    def committer():
        cur2.execute(LEDGER_LOCK, ('TRD-FENCE0004',)); cur2.fetchall()
        holder['locked'] = True
        time.sleep(0.8)
        holder['n'] = cur2.execute(COMMIT_UPD, ('{"pieces":1}', 'TRD-FENCE0004', 'L1')); c2.commit()

    th = threading.Thread(target=committer); th.start()
    while not holder.get('locked'): time.sleep(0.02)
    started = time.time()
    fenced = cur.execute(CAS_TERM, ('{"reason":"fenced_stale"}', 'TRD-FENCE0004', 'L1')); c1.commit()
    waited = time.time() - started
    th.join(10)
    check('LOCK a fence issued while the executor holds the ledger row waits for it, then matches 0 rows (committed wins)', holder.get('n') == 1 and fenced == 0 and waited > 0.4 and status_of('TRD-FENCE0004')['status'] == 'committed', (holder, fenced, waited))

    # 6. response loss: the database commit stands whatever the caller saw
    prepare('TRD-LOST0001', 'L1')
    cur2.execute(LEDGER_LOCK, ('TRD-LOST0001',)); cur2.fetchall(); cur2.execute(COMMIT_UPD, ('{"pieces":1}', 'TRD-LOST0001', 'L1')); c2.commit()
    c2.close(); conns.remove(c2)     # the executor connection/process disappears right after COMMIT
    check('RESPONSE LOSS the committed marker survives losing the executor connection (status answers committed)', status_of('TRD-LOST0001')['status'] == 'committed')

    # 7. executor connection dies mid-transaction: MySQL rolls the transaction back, the row stays prepared (not committed)
    prepare('TRD-DEAD0001', 'L1')
    c3 = connect(SCRATCH); conns.append(c3); cur3 = c3.cursor(pymysql.cursors.DictCursor)
    cur3.execute(LEDGER_LOCK, ('TRD-DEAD0001',)); cur3.fetchall(); cur3.execute(COMMIT_UPD, ('{"pieces":1}', 'TRD-DEAD0001', 'L1'))
    c3.close(); conns.remove(c3)     # crash before COMMIT
    time.sleep(0.3)
    check('CRASH mid-transaction: the marker is rolled back with the items, the row remains prepared (reclaimable)', status_of('TRD-DEAD0001')['status'] == 'prepared')
    cur.execute(CAS_TERM, ('{"reason":"fenced_stale"}', 'TRD-DEAD0001', 'L1')); c1.commit()
    check('CRASH then fence after lease expiry makes it terminal not_applied', status_of('TRD-DEAD0001')['status'] == 'not_applied')
finally:
    for c in conns:
        try:
            c.close()
        except Exception:
            pass
    adm = admin.cursor()
    adm.execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
    print(f'scratch database dropped: {SCRATCH}')
    adm.execute('SHOW DATABASES LIKE %s', ('cm_xchg_smoke_%',))
    check('CLEANUP no scratch database remains', len(adm.fetchall()) == 0)

print(f'\ncm-inventory exchange MySQL smoke: {passed} passed, {failed} failed')
sys.exit(0 if failed == 0 else 1)
