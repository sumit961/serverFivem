"""Isolated MySQL smoke test for the cm-inventory craft settlement SQL (server/craft.lua).

    python -u tests/craft_mysql_smoke.py          (from resources/[core]/cm-inventory; needs `pip install pymysql`)

SAFETY: connects with the credentials of the local development `mysql_connection_string` (read from server.local.cfg, never printed),
creates a SCRATCH database named cm_craft_smoke_<pid>, never touches any other schema, and DROPs the scratch database at the end.

WHAT THIS IS (and is not): it executes the SAME SQL statements craft.lua issues (verified to appear verbatim in craft.lua, so drift is
detected) in the same order, inside real InnoDB transactions, with two connections. It proves: DDL validity and idempotency, the UNIQUE
reference constraint, FOR UPDATE row locking (double-spend is impossible), rollback of the whole transaction, guarded updates (`<=>`), and
replay by ledger. It does NOT run the Lua planning code (that is covered by craft_selftest.lua) -- the plan here is a fixed, hand-written one.
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


def norm(sql):
    return re.sub(r'\s+', ' ', sql).strip()


craft_src = open(os.path.join(INV, 'server', 'craft.lua'), encoding='utf-8').read()
craft_norm = norm(craft_src)
db_src = open(os.path.join(INV, 'server', 'db.lua'), encoding='utf-8').read()


def lua_sql(sql):
    """Assert the statement text is present in craft.lua (whitespace-insensitive) and return it."""
    assert norm(sql) in craft_norm, 'statement drifted from craft.lua: ' + norm(sql)
    return sql


def ddl(src, table):
    m = re.search(r'(CREATE TABLE IF NOT EXISTS ' + table + r' \(.*?\n\s*\))\s*\]\]', src, re.S)
    assert m, 'DDL not found for ' + table
    return m.group(1)


# ---- connection (scratch database only)
cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
m = re.search(r'mysql_connection_string\s+"?([^"\n]+)', cfg)
assert m, 'no mysql_connection_string in server.local.cfg'
u = urlparse(m.group(1).strip())
SCRATCH = f'cm_craft_smoke_{os.getpid()}'
conn_args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', autocommit=False, charset='utf8mb4')


def connect(db=None):
    return pymysql.connect(database=db, **conn_args)


admin = connect()
admin.autocommit(True)
cur = admin.cursor()
cur.execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
print(f'scratch database created: {SCRATCH}')

try:
    c1 = connect(SCRATCH)
    cur1 = c1.cursor(pymysql.cursors.DictCursor)

    # ------------------------------------------------------------ DDL (verbatim from the real source files)
    LEDGER_DDL = ddl(craft_src, 'cm_inventory_transactions')
    ITEMS_DDL = ddl(db_src, 'inventory_items')
    AUDIT_DDL = ddl(db_src, 'inventory_audit')
    for _ in range(2):  # repeatable
        for stmt in (ITEMS_DDL, AUDIT_DDL, LEDGER_DDL, 'CREATE TABLE IF NOT EXISTS characters (id BIGINT PRIMARY KEY)'):
            cur1.execute(stmt)
    c1.commit()
    check('DDL ledger/inventory/audit tables create and are repeatable', True)
    cur1.execute('SHOW INDEX FROM cm_inventory_transactions WHERE Key_name = %s', ('uq_cm_inventory_tx_reference',))
    idx = cur1.fetchall()
    check('DDL reference is a UNIQUE index', len(idx) == 1 and idx[0]['Non_unique'] == 0)

    cur1.execute('INSERT INTO characters (id) VALUES (9001)')

    def seed():
        cur1.execute('DELETE FROM inventory_items WHERE owner_id = %s', ('9001',))
        cur1.execute('DELETE FROM cm_inventory_transactions')
        cur1.execute('DELETE FROM inventory_audit')
        rows = [('pocket-1', 'iron_ore', 3, None), ('pocket-2', 'iron_ore', 2, None), ('pocket-3', 'hammer', 1, '{"durability":50}')]
        for slot, item, qty, meta in rows:
            cur1.execute('INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata) VALUES (%s,%s,%s,%s,%s,%s)',
                         ('character', '9001', slot, item, qty, meta))
        c1.commit()

    def state(cur):
        cur.execute('SELECT slot, item_name, quantity, metadata FROM inventory_items WHERE owner_id = %s ORDER BY slot', ('9001',))
        return [tuple(r.values()) for r in cur.fetchall()]

    LEDGER_IN_TXN = lua_sql('SELECT reference, character_id, payload, result_json FROM cm_inventory_transactions WHERE reference = ?').replace('?', '%s')
    CHAR_SQL = lua_sql('SELECT id FROM characters WHERE id = ? LIMIT 1').replace('?', '%s')
    ROWS_SQL = lua_sql('SELECT * FROM inventory_items WHERE owner_type = ? AND owner_id = ? ORDER BY id FOR UPDATE').replace('?', '%s')
    UPD_QTY = lua_sql('UPDATE inventory_items SET quantity = ? WHERE id = ? AND quantity = ?').replace('?', '%s')
    UPD_META = lua_sql('UPDATE inventory_items SET metadata = ? WHERE id = ? AND metadata <=> ?').replace('?', '%s')
    DEL_ROW = lua_sql('DELETE FROM inventory_items WHERE id = ? AND quantity = ?').replace('?', '%s')
    INS_ROW = lua_sql('INSERT INTO inventory_items (owner_type, owner_id, slot, item_name, quantity, metadata) VALUES (?, ?, ?, ?, ?, ?)').replace('?', '%s')
    INS_AUDIT = lua_sql("""INSERT INTO inventory_audit (character_id, action, item_name, quantity, from_slot, to_slot, reason)
                            VALUES (?, ?, ?, ?, ?, ?, ?)""").replace('?', '%s')
    INS_LEDGER = lua_sql("""INSERT INTO cm_inventory_transactions
                        (reference, tx_type, character_id, payload_hash, payload, status, result_json, committed_at)
                        VALUES (?, ?, ?, ?, ?, 'committed', ?, NOW())""").replace('?', '%s')
    LOOKUP = lua_sql('SELECT reference, character_id, payload_hash, payload, status, result_json, tx_type FROM cm_inventory_transactions WHERE reference = ? LIMIT 1').replace('?', '%s')
    check('SQL every statement used here appears verbatim in craft.lua', True)

    def settle(conn, cur, ref, need=4, fail_before_ledger=False, hold=None):
        """The craft.lua sequence for: 4 iron_ore (+ hammer wear 10) -> 1 plate. Returns 'committed' | 'replay' | 'insufficient' | 'rolled_back'."""
        try:
            cur.execute(ROWS_SQL, ('character', '9001'))
            rows = cur.fetchall()
            cur.execute(LEDGER_IN_TXN, (ref,))
            if cur.fetchall():
                conn.rollback()
                return 'replay'
            cur.execute(CHAR_SQL, ('9001',))
            assert cur.fetchall()
            if hold:
                hold()  # keep the row locks while another connection competes
            ore = sorted([r for r in rows if r['item_name'] == 'iron_ore'], key=lambda r: (-r['quantity'], r['slot']))
            have = sum(r['quantity'] for r in ore)
            if have < need:
                conn.rollback()
                return 'insufficient'
            hammer = next(r for r in rows if r['item_name'] == 'hammer')
            assert cur.execute(UPD_META, ('{"durability":40}', hammer['id'], hammer['metadata'])) == 1
            remaining = need
            for r in ore:
                take = min(r['quantity'], remaining)
                if take == r['quantity']:
                    assert cur.execute(DEL_ROW, (r['id'], r['quantity'])) == 1
                else:
                    assert cur.execute(UPD_QTY, (r['quantity'] - take, r['id'], r['quantity'])) == 1
                remaining -= take
                cur.execute(INS_AUDIT, ('9001', 'craft_consume', 'iron_ore', -take, r['slot'], None, ref))
            cur.execute(INS_ROW, ('character', '9001', 'pocket-4', 'plate', 1, None))
            if fail_before_ledger:
                raise RuntimeError('injected')
            cur.execute(INS_LEDGER, (ref, 'craft', '9001', 'deadbeefdeadbeef', '{payload}', '{"outputs":[]}'))
            conn.commit()
            return 'committed'
        except Exception:
            conn.rollback()
            return 'rolled_back'

    # ------------------------------------------------------------ atomic success
    seed()
    r = settle(c1, cur1, 'CRAFT-SMOKE0001')
    st = state(cur1)
    check('ATOMIC success: inputs consumed across stacks, output created, tool worn, ledger committed',
          r == 'committed' and st == [('pocket-2', 'iron_ore', 1, None), ('pocket-3', 'hammer', 1, '{"durability":40}'), ('pocket-4', 'plate', 1, None)], st)
    cur1.execute('SELECT COUNT(*) AS n FROM cm_inventory_transactions WHERE reference = %s', ('CRAFT-SMOKE0001',))
    check('ATOMIC success wrote exactly one ledger row', cur1.fetchone()['n'] == 1)

    # ------------------------------------------------------------ replay
    before = state(cur1)
    r = settle(c1, cur1, 'CRAFT-SMOKE0001')
    check('REPLAY same reference returns the ledger result and mutates nothing', r == 'replay' and state(cur1) == before)
    cur1.execute(LOOKUP, ('CRAFT-SMOKE0001',))
    check('STATUS ledger lookup answers committed', cur1.fetchone()['status'] == 'committed')
    cur1.execute(LOOKUP, ('CRAFT-NEVERSEEN1',))
    check('STATUS unknown reference has no row (not_applied)', cur1.fetchone() is None)

    # ------------------------------------------------------------ UNIQUE reference
    try:
        cur1.execute(INS_LEDGER, ('CRAFT-SMOKE0001', 'craft', '9001', 'x' * 16, 'p', '{}'))
        dup = False
    except pymysql.err.IntegrityError:
        dup = True
    c1.rollback()
    check('UNIQUE a second ledger row for the same reference is rejected by MySQL', dup)

    # ------------------------------------------------------------ rollback
    seed()
    before = state(cur1)
    r = settle(c1, cur1, 'CRAFT-SMOKE0002', fail_before_ledger=True)
    check('ROLLBACK failure before the ledger insert reverts every mutation', r == 'rolled_back' and state(cur1) == before)
    cur1.execute('SELECT COUNT(*) AS n FROM cm_inventory_transactions')
    n_ledger = cur1.fetchone()['n']
    cur1.execute('SELECT COUNT(*) AS n FROM inventory_audit')
    check('ROLLBACK leaves no ledger row and no audit rows', n_ledger == 0 and cur1.fetchone()['n'] == 0)
    r = settle(c1, cur1, 'CRAFT-SMOKE0002')
    check('ROLLBACK the same reference then commits once', r == 'committed')

    # ------------------------------------------------------------ guarded update on NULL metadata (<=>)
    seed()
    cur1.execute('SELECT id FROM inventory_items WHERE slot = %s AND owner_id = %s', ('pocket-1', '9001'))
    rid = cur1.fetchone()['id']
    check('GUARD metadata <=> NULL matches a NULL column', cur1.execute(UPD_META, ('{"x":1}', rid, None)) == 1)
    check('GUARD stale metadata guard matches no row', cur1.execute(UPD_META, ('{"x":2}', rid, None)) == 0)
    c1.rollback()

    # ------------------------------------------------------------ concurrency: two connections, one stock for one craft
    seed()
    c2 = connect(SCRATCH)
    cur2 = c2.cursor(pymysql.cursors.DictCursor)
    results = {}
    locked = threading.Event()

    def worker_b():
        locked.wait(5)
        t0 = time.time()
        results['b'] = settle(c2, cur2, 'CRAFT-SMOKEB001')
        results['b_waited'] = time.time() - t0

    def hold():
        locked.set()
        time.sleep(1.0)  # A holds the FOR UPDATE locks; B must block here, not read stale stock

    # stock supports exactly ONE craft of 4 ore (5 ore total)
    t = threading.Thread(target=worker_b)
    t.start()
    results['a'] = settle(c1, cur1, 'CRAFT-SMOKEA001', hold=hold)
    t.join(10)
    check('CONCURRENCY exactly one of two competing references commits', sorted([results['a'], results['b']]) == ['committed', 'insufficient'], results)
    check('CONCURRENCY the second transaction was blocked by the row locks until the first committed', results.get('b_waited', 0) >= 0.7, results.get('b_waited'))
    cur1.execute('SELECT COALESCE(SUM(quantity),0) AS q FROM inventory_items WHERE owner_id = %s AND item_name = %s', ('9001', 'iron_ore'))
    ore_left = int(cur1.fetchone()['q'])
    cur1.execute('SELECT COALESCE(SUM(quantity),0) AS q FROM inventory_items WHERE owner_id = %s AND item_name = %s', ('9001', 'plate'))
    plates = int(cur1.fetchone()['q'])
    check('CONCURRENCY no negative stock and no duplicated output', ore_left == 1 and plates == 1, (ore_left, plates))
    c2.close()

    # ------------------------------------------------------------ concurrent duplicate reference
    seed()
    c3 = connect(SCRATCH)
    cur3 = c3.cursor(pymysql.cursors.DictCursor)
    res2 = {}
    locked2 = threading.Event()

    def dup_b():
        locked2.wait(5)
        res2['b'] = settle(c3, cur3, 'CRAFT-SMOKEDUP01')

    def hold2():
        locked2.set()
        time.sleep(0.8)

    t = threading.Thread(target=dup_b)
    t.start()
    res2['a'] = settle(c1, cur1, 'CRAFT-SMOKEDUP01', hold=hold2)
    t.join(10)
    cur1.execute('SELECT COUNT(*) AS n FROM cm_inventory_transactions WHERE reference = %s', ('CRAFT-SMOKEDUP01',))
    check('CONCURRENCY simultaneous duplicate reference applies once (other side replays or is refused)',
          cur1.fetchone()['n'] == 1 and res2['a'] == 'committed' and res2['b'] in ('replay', 'insufficient', 'rolled_back'), res2)
    c3.close()
finally:
    for name in ('c1', 'c2', 'c3'):   # open transactions would hold metadata locks and block the DROP
        try:
            globals()[name].close()
        except Exception:
            pass
    cur = admin.cursor()
    cur.execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
    print(f'scratch database dropped: {SCRATCH}')
    cur.execute('SHOW DATABASES LIKE %s', ('cm_craft_smoke_%',))
    check('CLEANUP no scratch database remains', len(cur.fetchall()) == 0)

print(f'\ncm-inventory craft MySQL smoke: {passed} passed, {failed} failed')
sys.exit(0 if failed == 0 else 1)
