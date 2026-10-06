"""Isolated MySQL smoke test for the business material platform SQL (server/materials.lua + server/schema.lua).

    python -u tests/materials_mysql_smoke.py      (from resources/[core]/cm-commercial-ownership; needs `pip install pymysql`)

SAFETY: connects with the local development `mysql_connection_string` (read from server.local.cfg, never printed), creates a SCRATCH database named
cm_mat_smoke_<pid>, never touches another schema, and DROPs the scratch database at the end (open transactions are closed first).

WHAT THIS IS: the SQL statements are EXTRACTED from the production Lua source (the `SQL` table in materials.lua and the DDL in schema.lua), so there is no
drift, and executed in the same order the Lua saga uses, in real InnoDB transactions with two connections. It proves DDL validity/idempotency, UNIQUE keys
(journal / delivery reference / inventory reference / idempotency key), BIGINT UNSIGNED underflow protection, FOR UPDATE row locking (no overfill, no double
spend), full rollback and replay. It does NOT run the Lua (that is materials_selftest.lua over a SQL double): this script drives the SQL by hand.
"""
import os
import re
import sys
import threading
import time
from urllib.parse import urlparse

import pymysql

HERE = os.path.dirname(os.path.abspath(__file__))
CO = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(CO, '..', '..', '..'))
passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond:
        passed += 1
        print('PASS  ' + name)
    else:
        failed += 1
        print('FAIL  ' + name + (f'  ({detail})' if detail is not None else ''))


mat_src = open(os.path.join(CO, 'server', 'materials.lua'), encoding='utf-8').read()
schema_src = open(os.path.join(CO, 'server', 'schema.lua'), encoding='utf-8').read()

# ---- statements straight out of the production source
block = mat_src[mat_src.index('local SQL = {'):mat_src.index('MAT.SQL = SQL')]
SQL = {}
for m in re.finditer(r'^\s+(\w+) = (\'(?:[^\'\\]|\\.)*\'|"(?:[^"\\]|\\.)*"),\s*$', block, re.M):
    SQL[m.group(1)] = m.group(2)[1:-1].replace('?', '%s')
assert len(SQL) >= 30, f'extracted only {len(SQL)} statements'


def ddl(table):
    m = re.search(r'(CREATE TABLE IF NOT EXISTS ' + table + r' \(.*?\n    \))\]\]', schema_src, re.S)
    assert m, table
    return m.group(1)


cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
u = urlparse(re.search(r'mysql_connection_string\s+"?([^"\n]+)', cfg).group(1).strip())
SCRATCH = f'cm_mat_smoke_{os.getpid()}'
args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', autocommit=False, charset='utf8mb4')


def connect(db=None):
    return pymysql.connect(database=db, **args)


admin = connect()
admin.autocommit(True)
admin.cursor().execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
print(f'scratch database created: {SCRATCH}')
conns = []

try:
    c1 = connect(SCRATCH); conns.append(c1)
    cur = c1.cursor(pymysql.cursors.DictCursor)
    for _ in range(2):   # repeatable
        for t in ('cm_business_material_stock', 'cm_business_material_events', 'cm_business_material_demands', 'cm_business_material_deliveries'):
            cur.execute(ddl(t))
    c1.commit()
    check('DDL four material tables create and are repeatable (extracted from schema.lua)', True)
    cur.execute("SELECT COUNT(*) AS n FROM information_schema.statistics WHERE table_schema = DATABASE() AND non_unique = 0 AND index_name IN ('uq_material_journal','uq_material_demand_ref','uq_material_demand_idem','uq_material_delivery_ref','uq_material_delivery_inventory')")
    check('DDL UNIQUE keys: journal, demand reference, idempotency key, delivery reference, inventory reference', cur.fetchone()['n'] == 5)

    T, I, M = 'store', '1', 'timber'

    def credit(conn, cr, ref, qty, key, ignore_fail=False):
        cr.execute(SQL['eventByJournal'], (key,))
        if cr.fetchall():
            conn.rollback(); return 'replay'
        cr.execute(SQL['stockEnsure'], (T, I, M))
        cr.execute(SQL['stockLock'], (T, I, M))
        rows = cr.fetchall()
        cur_q = int(rows[0]['quantity']) if rows else 0
        n = cr.execute(SQL['stockSet'], (cur_q + qty, T, I, M, cur_q))
        assert n == 1
        cr.execute(SQL['eventInsert'], (ref, T, I, M, qty, cur_q + qty, 'credit', 'smoke', None, key))
        conn.commit(); return 'ok'

    # ---------------------------------------------------------- stock credit / journal
    check('STOCK credit commits', credit(c1, cur, 'CRD-1', 25, 'credit:CRD-1') == 'ok')
    check('STOCK duplicate journal key replays (no second credit)', credit(c1, cur, 'CRD-1', 25, 'credit:CRD-1') == 'replay')
    cur.execute(SQL['stockRead'], (T, I, M))
    check('STOCK balance is 25', int(cur.fetchone()['quantity']) == 25)
    try:
        cur.execute(SQL['eventInsert'], ('CRD-X', T, I, M, 1, 26, 'credit', 'smoke', None, 'credit:CRD-1'))
        dup = False
    except pymysql.err.IntegrityError:
        dup = True
    c1.rollback()
    check('STOCK the UNIQUE journal key rejects a duplicate event row in MySQL', dup)
    try:
        cur.execute('UPDATE cm_business_material_stock SET quantity = quantity - 100 WHERE business_type = %s AND business_id = %s AND material_id = %s', (T, I, M))
        under = False
    except pymysql.err.DataError:
        under = True
    except pymysql.err.OperationalError:
        under = True
    c1.rollback()
    check('STOCK BIGINT UNSIGNED refuses a negative balance at the database level (belt and braces)', under)

    # ---------------------------------------------------------- consume all-or-nothing rollback
    cur.execute(SQL['stockEnsure'], (T, I, 'iron_ingot')); cur.execute(SQL['stockEnsure'], (T, I, 'log')); c1.commit()
    cur.execute(SQL['stockLock'], (T, I, 'iron_ingot')); cur.execute(SQL['stockSet'], (4, T, I, 'iron_ingot', 0))
    cur.execute(SQL['eventInsert'], ('CRD-2', T, I, 'iron_ingot', 4, 4, 'credit', 'smoke', None, 'credit:CRD-2')); c1.commit()

    def consume(conn, cr, ref, reqs):
        cr.execute(SQL['consumeEvents'], (ref,))
        if cr.fetchall():
            conn.rollback(); return 'replay'
        cur_q = {}
        for mat, q in sorted(reqs):
            cr.execute(SQL['stockLock'], (T, I, mat)); r = cr.fetchall()
            cur_q[mat] = int(r[0]['quantity']) if r else 0
        for mat, q in reqs:
            if cur_q[mat] < q:
                conn.rollback(); return 'insufficient'
        for mat, q in sorted(reqs):
            assert cr.execute(SQL['stockSet'], (cur_q[mat] - q, T, I, mat, cur_q[mat])) == 1
            cr.execute(SQL['eventInsert'], (ref, T, I, mat, -q, cur_q[mat] - q, 'consume', 'smoke', None, f'consume:{ref}:{mat}'))
        conn.commit(); return 'ok'

    check('CONSUME multi-material succeeds atomically', consume(c1, cur, 'CNS-1', [(M, 5), ('iron_ingot', 1)]) == 'ok')
    cur.execute(SQL['stockList'], (T, I)); before = cur.fetchall(); c1.commit()
    check('CONSUME insufficient line rolls back EVERY line', consume(c1, cur, 'CNS-2', [(M, 1), ('iron_ingot', 99)]) == 'insufficient')
    cur.execute(SQL['stockList'], (T, I)); after = cur.fetchall(); c1.commit()
    check('CONSUME balances unchanged after the refused consume', before == after)
    check('CONSUME replay by reference consumes nothing', consume(c1, cur, 'CNS-1', [(M, 5), ('iron_ingot', 1)]) == 'replay')

    # ---------------------------------------------------------- demand + delivery saga
    cur.execute(SQL['demandInsert'], ('MD-TEST0001', 'key-1', T, I, M, 10, 'business_need', None, 0, None, int(time.time()))); c1.commit()
    try:
        cur.execute(SQL['demandInsert'], ('MD-TEST0002', 'key-1', T, I, M, 10, 'business_need', None, 0, None, int(time.time()))); dupk = False
    except pymysql.err.IntegrityError:
        dupk = True
    c1.rollback()
    check('DEMAND the UNIQUE idempotency key rejects a second demand', dupk)
    cur.execute(SQL['demandInsert'], ('MD-TEST0003', None, T, I, M, 5, 'business_need', None, 0, None, int(time.time())))
    cur.execute(SQL['demandInsert'], ('MD-TEST0004', None, T, I, M, 5, 'business_need', None, 0, None, int(time.time()))); c1.commit()
    check('DEMAND several demands without an idempotency key coexist (NULLs are not unique)', True)

    def prepare(conn, cr, dref, delref, qty, hold=None):
        try:
            cr.execute(SQL['demandLock'], (dref,)); d = cr.fetchall()[0]
            if hold: hold()
            remaining = d['quantity_required'] - d['quantity_fulfilled'] - d['quantity_reserved']
            if d['status'] not in ('open', 'published', 'partially_fulfilled') or qty > remaining:
                conn.rollback(); return 'over_remaining'
            assert cr.execute(SQL['demandReserve'], (d['quantity_reserved'] + qty, d['id'], d['quantity_reserved'])) == 1
            cr.execute(SQL['deliveryInsert'], (delref, d['id'], dref, T, I, 1, M, qty, None, 'inv-ref-' + delref, 'payload', int(time.time()), int(time.time())))
            conn.commit(); return 'prepared'
        except Exception as e:
            conn.rollback(); return 'error:' + type(e).__name__

    # concurrent: two deliveries of 8 against a demand of 10
    c2 = connect(SCRATCH); conns.append(c2)
    cur2 = c2.cursor(pymysql.cursors.DictCursor)
    res = {}
    held = threading.Event()

    def b_thread():
        held.wait(5)
        t0 = time.time()
        res['b'] = prepare(c2, cur2, 'MD-TEST0001', 'DEL-B', 8)
        res['b_wait'] = time.time() - t0

    def hold():
        held.set(); time.sleep(1.0)

    th = threading.Thread(target=b_thread); th.start()
    res['a'] = prepare(c1, cur, 'MD-TEST0001', 'DEL-A', 8, hold=hold)
    th.join(10)
    check('SAGA two concurrent deliveries of 8 vs a demand of 10: exactly one is prepared (FOR UPDATE on the demand row, no overfill)', sorted([res['a'], res['b']]) == ['over_remaining', 'prepared'], res)
    check('SAGA the second transaction really waited on the row lock', res.get('b_wait', 0) >= 0.7, res.get('b_wait'))
    cur.execute('SELECT quantity_reserved FROM cm_business_material_demands WHERE reference = %s', ('MD-TEST0001',))
    check('SAGA reserved quantity is 8 (not 16)', int(cur.fetchone()['quantity_reserved']) == 8); c1.commit()
    cur.execute('SELECT COUNT(*) AS n FROM cm_business_material_deliveries'); n_del = cur.fetchone()['n']; c1.commit()
    check('SAGA exactly one delivery row exists', n_del == 1)

    winner = 'DEL-A' if res['a'] == 'prepared' else 'DEL-B'
    try:
        cur.execute(SQL['deliveryInsert'], (winner, 1, 'MD-TEST0001', T, I, 1, M, 1, None, 'inv-other', 'payload', 1, 1)); dupd = False
    except pymysql.err.IntegrityError:
        dupd = True
    c1.rollback()
    check('SAGA the UNIQUE delivery reference rejects a duplicate', dupd)
    try:
        cur.execute(SQL['deliveryInsert'], ('DEL-ZZ', 1, 'MD-TEST0001', T, I, 1, M, 1, None, 'inv-ref-' + winner, 'payload', 1, 1)); dupi = False
    except pymysql.err.IntegrityError:
        dupi = True
    c1.rollback()
    check('SAGA the UNIQUE inventory reference rejects two deliveries sharing one inventory debit', dupi)

    # cancel is blocked while reserved > 0 (the delivery is in flight)
    cur.execute(SQL['demandLock'], ('MD-TEST0001',)); d = cur.fetchall()[0]
    n = cur.execute(SQL['demandEnd'], ('cancelled', 'cancel:test', int(time.time()), d['id'])); c1.rollback()
    check('CANCEL the guarded demandEnd refuses while a quantity is reserved', n == 0)

    # inventory committed marker, then ONE finalize transaction: credit + demand progress + delivery complete
    cur.execute(SQL['deliveryCas'], ('inventory_committed', int(time.time()), None, winner, 'prepared')); c1.commit()

    def finalize(conn, cr, delref):
        cr.execute(SQL['deliveryLock'], (delref,)); d = cr.fetchall()[0]
        if d['status'] == 'completed':
            conn.rollback(); return 'replay'
        assert d['status'] == 'inventory_committed'
        cr.execute(SQL['eventByJournal'], ('delivery:' + delref,))
        if not cr.fetchall():
            cr.execute(SQL['stockEnsure'], (T, I, M)); cr.execute(SQL['stockLock'], (T, I, M)); q0 = int(cr.fetchall()[0]['quantity'])
            assert cr.execute(SQL['stockSet'], (q0 + d['quantity'], T, I, M, q0)) == 1
            cr.execute(SQL['eventInsert'], (delref, T, I, M, d['quantity'], q0 + d['quantity'], 'delivery', 'smoke', d['character_id'], 'delivery:' + delref))
        cr.execute(SQL['demandLock'], (d['demand_reference'],)); dem = cr.fetchall()[0]
        nf, nr = dem['quantity_fulfilled'] + d['quantity'], dem['quantity_reserved'] - d['quantity']
        if nf >= dem['quantity_required']:
            assert cr.execute(SQL['demandFulfilled'], (nf, nr, int(time.time()), dem['id'], dem['quantity_fulfilled'], dem['quantity_reserved'])) == 1
        else:
            assert cr.execute(SQL['demandProgress'], (nf, nr, 'partially_fulfilled', dem['id'], dem['quantity_fulfilled'], dem['quantity_reserved'])) == 1
        assert cr.execute(SQL['deliveryComplete'], (int(time.time()), int(time.time()), delref)) == 1
        conn.commit(); return 'completed'

    cur.execute(SQL['stockRead'], (T, I, M)); stock_before = int(cur.fetchone()['quantity']); c1.commit()
    check('FINALIZE credit + demand progress + delivery completion commit as one transaction', finalize(c1, cur, winner) == 'completed')
    cur.execute(SQL['stockRead'], (T, I, M)); stock_after = int(cur.fetchone()['quantity']); c1.commit()
    cur.execute('SELECT status, quantity_fulfilled, quantity_reserved FROM cm_business_material_demands WHERE reference = %s', ('MD-TEST0001',)); dr = cur.fetchone(); c1.commit()
    check('FINALIZE stock +8, demand partially_fulfilled 8/10, reserved back to 0', stock_after - stock_before == 8 and dr['status'] == 'partially_fulfilled' and dr['quantity_fulfilled'] == 8 and dr['quantity_reserved'] == 0, (stock_after - stock_before, dr))
    check('FINALIZE replay changes nothing', finalize(c1, cur, winner) == 'replay')
    cur.execute(SQL['eventByJournal'], ('delivery:' + winner,)); check('FINALIZE exactly one delivery journal event', len(cur.fetchall()) == 1); c1.commit()

    # rollback: a failing statement inside the finalize transaction leaves nothing behind
    cur.execute(SQL['demandLock'], ('MD-TEST0003',)); d3 = cur.fetchall()[0]
    assert cur.execute(SQL['demandReserve'], (5, d3['id'], 0)) == 1
    cur.execute(SQL['deliveryInsert'], ('DEL-C', d3['id'], 'MD-TEST0003', T, I, 1, M, 5, None, 'inv-ref-DEL-C', 'payload', 1, 1)); c1.commit()
    cur.execute(SQL['deliveryCas'], ('inventory_committed', 1, None, 'DEL-C', 'prepared')); c1.commit()
    cur.execute(SQL['stockRead'], (T, I, M)); s0 = int(cur.fetchone()['quantity']); c1.commit()
    try:
        cur.execute(SQL['deliveryLock'], ('DEL-C',)); cur.fetchall()
        cur.execute(SQL['stockLock'], (T, I, M)); q = int(cur.fetchall()[0]['quantity'])
        cur.execute(SQL['stockSet'], (q + 5, T, I, M, q))
        cur.execute(SQL['eventInsert'], ('DEL-C', T, I, M, 5, q + 5, 'delivery', 'smoke', 1, 'delivery:' + winner))   # duplicate journal key -> fails
        c1.commit(); failed_ok = False
    except pymysql.err.IntegrityError:
        c1.rollback(); failed_ok = True
    cur.execute(SQL['stockRead'], (T, I, M)); s1 = int(cur.fetchone()['quantity']); c1.commit()
    check('ROLLBACK a failure inside the credit transaction reverts the balance change', failed_ok and s1 == s0)

    # concurrent consumes of one balance
    cur.execute(SQL['stockEnsure'], (T, I, 'reclaimed_metal')); cur.execute(SQL['stockLock'], (T, I, 'reclaimed_metal')); cur.fetchall()
    cur.execute(SQL['stockSet'], (5, T, I, 'reclaimed_metal', 0))
    cur.execute(SQL['eventInsert'], ('CRD-R', T, I, 'reclaimed_metal', 5, 5, 'credit', 'smoke', None, 'credit:CRD-R')); c1.commit()
    out2 = {}
    evt = threading.Event()

    def cons_b():
        evt.wait(5); out2['b'] = consume(c2, cur2, 'CNS-B', [('reclaimed_metal', 4)])

    def cons_a():
        # hold the lock briefly inside the same flow by locking first
        cur.execute(SQL['stockLock'], (T, I, 'reclaimed_metal')); cur.fetchall(); evt.set(); time.sleep(0.8)
        qa = 5
        assert cur.execute(SQL['stockSet'], (qa - 4, T, I, 'reclaimed_metal', qa)) == 1
        cur.execute(SQL['eventInsert'], ('CNS-A', T, I, 'reclaimed_metal', -4, 1, 'consume', 'smoke', None, 'consume:CNS-A:reclaimed_metal')); c1.commit(); out2['a'] = 'ok'

    tb = threading.Thread(target=cons_b); tb.start(); cons_a(); tb.join(10)
    cur.execute(SQL['stockRead'], (T, I, 'reclaimed_metal')); rem = int(cur.fetchone()['quantity']); c1.commit()
    check('CONCURRENCY two consumes of 4 from a balance of 5: one commits, the other sees 1 and is refused; balance 1, never negative', out2 == {'a': 'ok', 'b': 'insufficient'} and rem == 1, (out2, rem))
finally:
    for c in conns:
        try:
            c.close()
        except Exception:
            pass
    adm = admin.cursor()
    adm.execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
    print(f'scratch database dropped: {SCRATCH}')
    adm.execute('SHOW DATABASES LIKE %s', ('cm_mat_smoke_%',))
    check('CLEANUP no scratch database remains', len(adm.fetchall()) == 0)

print(f'\ncm-commercial-ownership materials MySQL smoke: {passed} passed, {failed} failed')
sys.exit(0 if failed == 0 else 1)
