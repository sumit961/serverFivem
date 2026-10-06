"""Scratch-MySQL/MariaDB test for the shared item-purchase journal (cm-core/shared/item_purchase.lua) as used by cm-store and nv_cloth,
plus the stock-restock delta statements of cm-store and cm-commercial-ownership (clothing).

    CM_TEST_MYSQL=host:port:user[:password] python -u tests/item_purchase_mysql_smoke.py      (from resources/[core]/cm-core; needs pymysql)

Without CM_TEST_MYSQL the local dev mysql_connection_string is used (never printed). Creates scratch DB cm_item_purchase_smoke_<pid>, drops it
at the end. SQL is produced by the module's OWN sqlFor() (executed through the real Lua interpreter) and the restock statements are parsed
from the consumers' source, so drift fails. Races use separate connections released together by a barrier.
"""
import os, re, subprocess, sys, threading
from urllib.parse import urlparse
import pymysql

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.dirname(HERE)
CORE = os.path.dirname(RES)
ROOT = os.path.abspath(os.path.join(RES, '..', '..', '..'))
passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond: passed += 1; print('PASS  ' + name)
    else: failed += 1; print('FAIL  ' + name + (detail and f'  ({detail})' or ''))


def lua_sql(cfg):
    """Run the real sqlFor() in Lua and return {name: sql} (each statement base64-free, separated by a marker)."""
    code = ("CMItemPurchase=nil dofile([[%s]]) local q=CMItemPurchase.sqlFor(%s) "
            "for _,k in ipairs({'ddl','insert','get','reserve','setItems','finalize','stale'}) do io.write('@@'..k..'@@'..q[k]) end") % (
        os.path.join(RES, 'shared', 'item_purchase.lua').replace('\\', '/'), cfg)
    out = subprocess.run(['lua', '-e', code], capture_output=True, text=True, check=True).stdout
    parts = re.split(r'@@(\w+)@@', out)
    return {parts[i]: parts[i + 1].replace('?', '%s') for i in range(1, len(parts), 2)}


STORE = lua_sql("{journal='cm_store_purchases',stockTable='cm_stores',stockKey='store_id',ownerColumn='owner_character_id'}")
CLOTH = lua_sql("{journal='nv_cloth_purchases',stockTable='cm_clothing_stores',stockKey='shop_id',ownerColumn='owner_character_id'}")

store_src = open(os.path.join(CORE, 'cm-store', 'server', 'main.lua'), encoding='utf-8').read()
co_src = open(os.path.join(CORE, 'cm-commercial-ownership', 'server', 'main.lua'), encoding='utf-8').read()
store_ddl = re.search(r'(CREATE TABLE IF NOT EXISTS cm_stores \(.*?\n\s*\))\]\]', store_src, re.S).group(1)
STORE_RESTOCK = re.search(r"'(UPDATE cm_stores SET stock = LEAST\(\?, stock \+ \?\) WHERE store_id = \? AND owner_character_id = \?)'", store_src).group(1).replace('?', '%s')
co_stmt = re.search(r"'(UPDATE %s SET stock = LEAST\(\?, stock \+ \?\) WHERE shop_id = \? AND owner_character_id = \?)'", co_src).group(1)
CLOTH_RESTOCK = (co_stmt % 'cm_clothing_stores').replace('?', '%s')
cloth_ddl = ('CREATE TABLE IF NOT EXISTS cm_clothing_stores (shop_id VARCHAR(50) NOT NULL PRIMARY KEY, owner_character_id BIGINT NULL, '
             'stock INT NOT NULL DEFAULT 5000, business_balance BIGINT NOT NULL DEFAULT 0, daily_income BIGINT NOT NULL DEFAULT 0, weekly_income BIGINT NOT NULL DEFAULT 0)')

if os.environ.get('CM_TEST_MYSQL'):
    _h, _p, _u, *_pw = os.environ['CM_TEST_MYSQL'].split(':')
    u = urlparse('mysql://%s:%s@%s:%s/x' % (_u, ''.join(_pw), _h, _p))
else:
    cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
    u = urlparse(re.search(r'mysql_connection_string\s+"?(\S+)"?', cfg).group(1).strip())
SCRATCH = f'cm_item_purchase_smoke_{os.getpid()}'
args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', charset='utf8mb4', autocommit=True)
admin = pymysql.connect(**args)
admin.cursor().execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
CAP = 8000
try:
    c1 = pymysql.connect(database=SCRATCH, **args).cursor()
    c1.execute('SELECT VERSION()'); print('engine:', c1.fetchone()[0])
    c1.execute(store_ddl); c1.execute(cloth_ddl)
    for q in (STORE, CLOTH): c1.execute(q['ddl']); c1.execute(q['ddl'])
    check('DDL repeatable for both journals', True)

    def run(*ops):
        bar = threading.Barrier(len(ops)); res = [None] * len(ops)
        def w(i, op):
            c = pymysql.connect(database=SCRATCH, **args).cursor()
            bar.wait(); res[i] = op(c)
        ts = [threading.Thread(target=w, args=(i, o)) for i, o in enumerate(ops)]
        [t.start() for t in ts]; [t.join() for t in ts]
        return res

    # ---------------------------------------------------------------- run the same suite for both resources
    for label, Q, table, key, journal, sid in (('cm-store', STORE, 'cm_stores', 'store_id', 'cm_store_purchases', 1),
                                               ('nv_cloth', CLOTH, 'cm_clothing_stores', 'shop_id', 'nv_cloth_purchases', 'clothes_1')):
        L = lambda s: f'[{label}] {s}'

        def reset(stock=100, owner=7, balance=0):
            c1.execute(f'DELETE FROM {journal}'); c1.execute(f'DELETE FROM {table}')
            c1.execute(f'INSERT INTO {table} ({key}, stock, owner_character_id, business_balance) VALUES (%s, %s, %s, %s)', (sid, stock, owner, balance))

        def srow():
            c1.execute(f'SELECT stock, business_balance, daily_income, weekly_income FROM {table} WHERE {key} = %s', (sid,)); return c1.fetchone()

        def jrow(ref):
            c1.execute(f'SELECT state, reserved_units, items_state, refund_amount, finished_at FROM {journal} WHERE reference = %s', (ref,)); return c1.fetchone()

        def mk(ref, total=70, pct=80, account='bank'):
            c1.execute(Q['insert'], (ref, 1, str(sid), account, total, pct))

        reserve = lambda ref, n: (lambda c: c.execute(Q['reserve'], (ref, n, n, sid, n)))
        fin = lambda ref, state, refund, release, share: (lambda c: c.execute(Q['finalize'], (state, refund, CAP, release, share, share, share, ref)))

        reset(); mk('A1'); dup = False
        try: mk('A1')
        except pymysql.err.IntegrityError: dup = True
        check(L('UNIQUE reference rejects a duplicate purchase row'), dup)

        reset(100); mk('R1')
        n = c1.execute(Q['reserve'], ('R1', 5, 5, sid, 5))
        check(L('RESERVE of the WHOLE cart is one statement: stock down and reserved_units recorded together'), n >= 1 and srow()[0] == 95 and jrow('R1')[1] == 5, (srow(), jrow('R1')))
        n = c1.execute(Q['reserve'], ('R1', 5, 5, sid, 5))
        check(L('RESERVE is once per reference'), n == 0 and srow()[0] == 95)
        reset(3); mk('R2'); n = c1.execute(Q['reserve'], ('R2', 5, 5, sid, 5))
        check(L('RESERVE above stock fails atomically: no partial line, stock and journal untouched'), n == 0 and srow()[0] == 3 and jrow('R2')[1] == 0)
        reset(100, owner=None); mk('R3'); n = c1.execute(Q['reserve'], ('R3', 5, 5, sid, 5))
        check(L('UNOWNED store still has finite stock (existing semantics): reserve works'), n >= 1 and srow()[0] == 95)

        ok = True
        for i in range(25):
            reset(5); mk('A'); mk('B')
            r = run(reserve('A', 5), reserve('B', 5))
            ok &= (sorted(int(x > 0) for x in r) == [0, 1] and srow()[0] == 0)
        check(L('LAST UNITS: two buyers race for the last 5 units, exactly one wins, stock 0 (25 runs)'), ok)

        reset(70); mk('F1'); c1.execute(f"UPDATE {journal} SET reserved_units = 5, items_state = 'delivered' WHERE reference = 'F1'")
        n = c1.execute(Q['finalize'], ('completed', 0, CAP, 0, 56, 56, 56, 'F1'))
        check(L('FINALIZE completed: state + owner revenue + income counters in one statement, stock untouched'), n >= 1 and jrow('F1')[0] == 'completed' and srow() == (70, 56, 56, 56), srow())
        n = c1.execute(Q['finalize'], ('compensated', 70, CAP, 5, 0, 0, 0, 'F1'))
        check(L('FINALIZE after terminal (replay / opposite outcome) changes NOTHING'), n == 0 and jrow('F1')[0] == 'completed' and srow() == (70, 56, 56, 56))
        reset(95); mk('F2'); c1.execute(f"UPDATE {journal} SET reserved_units = 5 WHERE reference = 'F2'")
        n = c1.execute(Q['finalize'], ('compensated', 70, CAP, 5, 0, 0, 0, 'F2'))
        check(L('FINALIZE compensated releases the reservation once (95 -> 100), refund recorded'), n >= 1 and srow()[0] == 100 and jrow('F2')[0] == 'compensated' and jrow('F2')[3] == 70)
        reset(7998); mk('F3'); c1.execute(Q['finalize'], ('compensated', 0, CAP, 50, 0, 0, 0, 'F3'))
        check(L('FINALIZE release is capped at capacity'), srow()[0] == CAP)
        reset(100, owner=None); mk('F4'); n = c1.execute(Q['finalize'], ('completed', 0, CAP, 0, 0, 0, 0, 'F4'))
        check(L('FINALIZE on an UNOWNED store: terminates, owner revenue guarded off (no credit)'), n >= 1 and jrow('F4')[0] == 'completed' and srow() == (100, 0, 0, 0), srow())
        reset(95, owner=None); mk('F5'); c1.execute(f"UPDATE {journal} SET reserved_units = 5 WHERE reference = 'F5'")
        c1.execute(Q['finalize'], ('completed', 0, CAP, 0, 56, 56, 56, 'F5'))
        check(L('UNOWNED store: even a non-zero share parameter credits nothing (IF owner IS NOT NULL)'), srow() == (95, 0, 0, 0), srow())

        ok = True
        for i in range(25):
            reset(95); mk('W'); c1.execute(f"UPDATE {journal} SET reserved_units = 5 WHERE reference = 'W'")
            run(fin('W', 'compensated', 70, 5, 0), fin('W', 'compensated', 70, 5, 0))
            ok &= (srow()[0] == 100 and jrow('W')[0] == 'compensated')
        check(L('TWO COMPENSATION WORKERS: stock released once, one terminal state (25 runs)'), ok)

        ok = True; seen = set()
        for i in range(40):
            reset(95); mk('X'); c1.execute(f"UPDATE {journal} SET reserved_units = 5 WHERE reference = 'X'")
            run(fin('X', 'completed', 0, 0, 56), fin('X', 'compensated', 70, 5, 0))
            s_, st = jrow('X')[0], srow(); seen.add(s_)
            ok &= (s_ == 'completed' and st == (95, 56, 56, 56)) or (s_ == 'compensated' and st == (100, 0, 0, 0))
        check(L('COMPENSATION vs SUCCESS: exactly one terminal result, effects match the winner (40 runs; seen %s)' % sorted(seen)), ok)

        reset(); mk('L1'); run(lambda c: c.execute(Q['setItems'], ('delivered', 'L1')), lambda c: c.execute(Q['setItems'], ('failed', 'L1')))
        first = jrow('L1')[2]; c1.execute(Q['setItems'], ('failed' if first == 'delivered' else 'delivered', 'L1'))
        check(L('DELIVERY decision is first-writer-wins and never flips'), first in ('delivered', 'failed') and jrow('L1')[2] == first)
        reset(); mk('L2'); c1.execute(Q['finalize'], ('compensated', 0, CAP, 0, 0, 0, 0, 'L2'))
        check(L('DELIVERY decision refused after the terminal transition'), c1.execute(Q['setItems'], ('delivered', 'L2')) == 0 and jrow('L2')[2] == 'pending')

        reset(); mk('S1'); mk('S2'); c1.execute(f"UPDATE {journal} SET created_at = NOW() - INTERVAL 5 MINUTE WHERE reference = 'S1'")
        c1.execute(Q['finalize'], ('completed', 0, CAP, 0, 0, 0, 0, 'S2'))
        c1.execute(Q['stale'], (60,)); refs = [r[0] for r in c1.fetchall()]
        check(L('STALE scan returns only old PENDING rows'), refs == ['S1'], refs)

    # ---------------------------------------------------------------- restock deltas (cm-store manageStore, CO Manage for clothing)
    for label, stmt, table, key, sid in (('cm-store restock', STORE_RESTOCK, 'cm_stores', 'store_id', 1), ('clothing restock', CLOTH_RESTOCK, 'cm_clothing_stores', 'shop_id', 'clothes_1')):
        res_q = (STORE if table == 'cm_stores' else CLOTH)['reserve']
        jr = 'cm_store_purchases' if table == 'cm_stores' else 'nv_cloth_purchases'
        ok = True
        for i in range(25):
            c1.execute(f'DELETE FROM {jr}'); c1.execute(f'DELETE FROM {table}')
            c1.execute(f'INSERT INTO {table} ({key}, stock, owner_character_id) VALUES (%s, 100, 7)', (sid,))
            c1.execute((STORE if table == 'cm_stores' else CLOTH)['insert'], ('RR', 1, str(sid), 'bank', 70, 80))
            run(lambda c: c.execute(stmt, (CAP, 50, sid, 7)), lambda c: c.execute(res_q, ('RR', 10, 10, sid, 10)))
            c1.execute(f'SELECT stock FROM {table} WHERE {key} = %s', (sid,)); ok &= c1.fetchone()[0] == 140
        check(f'[{label}] owner restock(+50) racing a customer reservation(-10) from 100 -> 140 (no lost update, 25 runs)', ok)
        c1.execute(f'UPDATE {table} SET stock = 7990 WHERE {key} = %s', (sid,)); c1.execute(stmt, (CAP, 50, sid, 7))
        c1.execute(f'SELECT stock FROM {table} WHERE {key} = %s', (sid,))
        check(f'[{label}] restock is capped at capacity', c1.fetchone()[0] == CAP)
        c1.execute(f'UPDATE {table} SET stock = 100 WHERE {key} = %s', (sid,)); n = c1.execute(stmt, (CAP, 50, sid, 8))
        check(f'[{label}] a non-owner restock affects nothing', n == 0)
finally:
    admin.cursor().execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
print(f'\n{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
