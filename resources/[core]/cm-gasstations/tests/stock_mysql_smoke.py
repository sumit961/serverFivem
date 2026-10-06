"""Scratch-MySQL concurrency test for cm-gasstations stock (server/main.lua StationStock).

    python -u tests/stock_mysql_smoke.py      (from resources/[core]/cm-gasstations; needs pymysql)

Uses the local dev mysql_connection_string (never printed), creates scratch DB cm_gas_stock_smoke_<pid>, drops it at the end.
Executes the SAME SQL as main.lua (asserted verbatim in source, so drift fails) from two real connections.
Mutation guard: fails if any stock write other than station purchase/ownership reset uses an absolute `stock = ?`.
"""
import os, re, sys, threading
from urllib.parse import urlparse
import pymysql

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(RES, '..', '..', '..'))
passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond: passed += 1; print('PASS  ' + name)
    else: failed += 1; print('FAIL  ' + name + (f'  ({detail})' if detail is not None else ''))


def norm(s): return re.sub(r'\s+', ' ', s).strip()


src = open(os.path.join(RES, 'server', 'main.lua'), encoding='utf-8').read()
settle = open(os.path.join(RES, 'server', 'settlement.lua'), encoding='utf-8').read()
srcn = norm(src)
settlen = norm(settle)


def lua_sql(sql, source=None):
    assert norm(sql) in (source or srcn), 'statement drifted from source: ' + norm(sql)
    return sql.replace('?', '%s')


# Customer reserve/release run inside the purchase journal (settlement.lua): same atomic guarded deltas, now bound to a journal row.
RESERVE = lua_sql("""UPDATE cm_gas_stations s JOIN cm_gas_purchases p ON p.reference = ?
        SET s.stock = s.stock - ?, p.reserved_units = ?
        WHERE s.station_id = ? AND s.owner_character_id IS NOT NULL AND s.stock >= ? AND p.state = 'pending' AND p.reserved_units = 0""", settlen)
RELEASE = lua_sql("""UPDATE cm_gas_purchases p
        LEFT JOIN cm_gas_stations s ON s.station_id = p.station_id AND s.owner_character_id IS NOT NULL
        SET p.state = ?, p.refund_amount = ?, p.finished_at = NOW(),
            s.stock = LEAST(?, s.stock + ?),
            s.business_balance = s.business_balance + ?, s.daily_income = s.daily_income + ?, s.weekly_income = s.weekly_income + ?
        WHERE p.reference = ? AND p.state = 'pending'""", settlen)
RESTOCK = lua_sql('UPDATE cm_gas_stations SET stock = stock + ? WHERE station_id = ? AND owner_character_id = ? AND stock + ? <= ?')
PURCHASE_DDL = re.search(r'Settlement\.DDL = \[\[(.*?)\]\]', settle, re.S).group(1)

# ---- mutation guard: absolute stock writes allowed only for ownership transfer (buy / tax reset)
absolute = re.findall(r"UPDATE cm_gas_stations SET[^\n]*?\bstock = \?", src)
check('MUTATION GUARD: only ownership buy/reset use absolute stock=? (found %d, expect 2)' % len(absolute), len(absolute) == 2, absolute)
check('MUTATION GUARD: manageStation has no client-supplied absolute stock', 'data.stock' not in src)
check('RELEASE: the ONLY customer stock release is the journal terminal statement (no loose release in main.lua)',
      'StationStock.release' not in src and 'StationStock.reserve' not in src and settle.count('LEAST(?, s.stock + ?)') == 1)
check('EXCEPTION PATH: placeOrder has no reservation tracker; settlement.run owns every outcome', 'local reservation' not in src and 'engine.run({' in src)
check('MUTATION GUARD: no price_tier+stock combined write', 'price_tier = ?, stock = ?' not in src)

ddl = re.search(r'(CREATE TABLE IF NOT EXISTS cm_gas_stations \(.*?\n\s*\))\s*\]\]', src, re.S)
assert ddl, 'DDL not found'

# CM_TEST_MYSQL=host:port:user[:password] targets a throwaway instance; otherwise the local dev connection string is used (never printed)
if os.environ.get('CM_TEST_MYSQL'):
    _h, _p, _u, *_pw = os.environ['CM_TEST_MYSQL'].split(':')
    u = urlparse('mysql://%s:%s@%s:%s/x' % (_u, ''.join(_pw), _h, _p))
else:
    cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
    u = urlparse(re.search(r'mysql_connection_string\s+"?(\S+)"?', cfg).group(1).strip())
SCRATCH = f'cm_gas_stock_smoke_{os.getpid()}'
args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', charset='utf8mb4', autocommit=True)
admin = pymysql.connect(**args)
admin.cursor().execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
MAX = 25000
try:
    conns = [pymysql.connect(database=SCRATCH, **args) for _ in range(2)]
    c1 = conns[0].cursor()
    c1.execute(ddl.group(1))
    c1.execute(PURCHASE_DDL)
    c1.execute(ddl.group(1).replace('CREATE TABLE IF NOT EXISTS', 'CREATE TABLE IF NOT EXISTS'))  # repeatable

    def seed(stock, owner=7):
        c1.execute('DELETE FROM cm_gas_purchases'); c1.execute('DELETE FROM cm_gas_stations')
        c1.execute('INSERT INTO cm_gas_stations (station_id, stock, owner_character_id) VALUES (1, %s, %s)', (stock, owner))

    def stock():
        c1.execute('SELECT stock FROM cm_gas_stations WHERE station_id = 1')
        return c1.fetchone()[0]

    def run(*ops):
        """Run each op on its own connection concurrently, released together by a barrier."""
        bar = threading.Barrier(len(ops)); res = [None] * len(ops)
        def w(i, op):
            c = pymysql.connect(database=SCRATCH, **args).cursor()
            bar.wait(); res[i] = op(c)
        ts = [threading.Thread(target=w, args=(i, o)) for i, o in enumerate(ops)]
        [t.start() for t in ts]; [t.join() for t in ts]
        return res

    counter = [0]

    def newref():
        counter[0] += 1
        ref = 'S%06d' % counter[0]
        c1.execute("INSERT INTO cm_gas_purchases (reference, character_id, station_id, state) VALUES (%s, 1, 1, 'pending')", (ref,))
        return ref

    def reserve(n):
        ref = newref()
        return lambda c: c.execute(RESERVE, (ref, n, n, 1, n))

    restock = lambda n: (lambda c: c.execute(RESTOCK, (n, 1, 7, n, MAX)))
    def release(n):
        ref = newref()
        return lambda c: c.execute(RELEASE, ('compensated', 0, MAX, n, 0, 0, 0, ref))

    for i in range(25):  # repeat to shake out ordering
        seed(100); run(restock(50), reserve(10))
        if stock() != 140: check('reserve vs restock', False, stock()); break
    else: check('purchase(-10) vs restock(+50) from 100 -> 140 (25 runs)', True)

    ok = True
    for i in range(25):
        seed(100); run(restock(20), restock(30)); ok &= stock() == 150
    check('restock(+20) vs restock(+30) from 100 -> 150 (25 runs)', ok)

    ok = True
    for i in range(25):
        seed(1); r = run(reserve(1), reserve(1)); ok &= (sorted(int(x > 0) for x in r) == [0, 1] and stock() == 0)
    check('purchase vs purchase from 1 -> exactly one wins, final 0 (25 runs)', ok)

    ok = True
    for i in range(25):
        seed(90); run(restock(50), release(10)); ok &= stock() == 150
    check('release(+10) vs restock(+50) from 90 (after reserve) -> 150 (25 runs)', ok)

    ok = True
    for i in range(25):
        seed(24995); r = run(restock(5), restock(5)); ok &= (sorted(r) == [0, 1] and stock() == 25000)
    check('near-capacity: 24995 + two exact +5 -> one wins, final == max (25 runs)', ok)

    seed(24995); run(restock(100)); check('restock over capacity rejected, stock unchanged', stock() == 24995)
    seed(24995); run(release(100)); check('release capped at max (no overflow)', stock() == 25000)
    seed(5); r = run(reserve(10)); check('reserve above stock fails, never negative', r == [0] and stock() == 5)
    seed(50, owner=7); r = run(lambda c: c.execute(RESTOCK, (10, 1, 8, 10, MAX))); check('non-owner restock affects nothing', r == [0] and stock() == 50)
    c1.execute('UPDATE cm_gas_stations SET owner_character_id = NULL WHERE station_id = 1')
    r = run(reserve(1)); run(release(1)); check('unowned station: reserve is a no-op and release never changes stock', r == [0] and stock() == 50)
finally:
    admin.cursor().execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
print(f'\n{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
