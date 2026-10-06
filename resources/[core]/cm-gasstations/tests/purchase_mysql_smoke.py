"""Scratch-MySQL test for the cm-gasstations purchase journal (server/settlement.lua Settlement.SQL / Settlement.DDL).

    python -u tests/purchase_mysql_smoke.py      (from resources/[core]/cm-gasstations; needs pymysql)

Uses the local dev mysql_connection_string (never printed), creates scratch DB cm_gas_purchase_smoke_<pid>, drops it at the end.
The statements are PARSED FROM server/settlement.lua (not retyped), so drift fails. Races use real separate connections released
together by a barrier and are repeated to shake out ordering.
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


settle = open(os.path.join(RES, 'server', 'settlement.lua'), encoding='utf-8').read()
main = open(os.path.join(RES, 'server', 'main.lua'), encoding='utf-8').read()

block = re.search(r'Settlement\.SQL = \{(.*?)\n\}', settle, re.S).group(1)
SQL = {}
for name, body in re.findall(r'''\b(\w+) = (\[\[.*?\]\]|"[^"\n]*"|'[^'\n]*')''', block, re.S):
    SQL[name] = (body[2:-2] if body.startswith('[[') else body[1:-1]).replace('?', '%s')
for key in ('insert', 'get', 'reserve', 'fuel', 'items', 'claimFuel', 'finalize', 'stale'):
    assert key in SQL, 'missing statement ' + key
ddl_p = re.search(r'Settlement\.DDL = \[\[(.*?)\]\]', settle, re.S).group(1)
ddl_s = re.search(r'(CREATE TABLE IF NOT EXISTS cm_gas_stations \(.*?\n\s*\))\s*\]\]', main, re.S).group(1)
restock_m = re.search(r"'(UPDATE cm_gas_stations SET stock = stock \+ \? WHERE station_id = \? AND owner_character_id = \? AND stock \+ \? <= \?)'", main)
assert restock_m, 'restock statement not found in main.lua'
RESTOCK = restock_m.group(1).replace('?', '%s')

# CM_TEST_MYSQL=host:port:user[:password] targets a throwaway instance; otherwise the local dev connection string is used (never printed)
if os.environ.get('CM_TEST_MYSQL'):
    _h, _p, _u, *_pw = os.environ['CM_TEST_MYSQL'].split(':')
    u = urlparse('mysql://%s:%s@%s:%s/x' % (_u, ''.join(_pw), _h, _p))
else:
    cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
    u = urlparse(re.search(r'mysql_connection_string\s+"?(\S+)"?', cfg).group(1).strip())
SCRATCH = f'cm_gas_purchase_smoke_{os.getpid()}'
args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', charset='utf8mb4', autocommit=True)
admin = pymysql.connect(**args)
admin.cursor().execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
MAX = 25000
try:
    c1 = pymysql.connect(database=SCRATCH, **args).cursor()
    c1.execute(ddl_s); c1.execute(ddl_p); c1.execute(ddl_p)
    check('DDL is repeatable (CREATE TABLE IF NOT EXISTS twice)', True)

    def reset(stock=100, owner=7, balance=0):
        c1.execute('DELETE FROM cm_gas_purchases'); c1.execute('DELETE FROM cm_gas_stations')
        c1.execute('INSERT INTO cm_gas_stations (station_id, stock, owner_character_id, business_balance) VALUES (1, %s, %s, %s)', (stock, owner, balance))

    def row(ref):
        c1.execute('SELECT state, reserved_units, fuel_state, items_state, refund_amount, finished_at FROM cm_gas_purchases WHERE reference = %s', (ref,))
        return c1.fetchone()

    def station():
        c1.execute('SELECT stock, business_balance, daily_income, weekly_income FROM cm_gas_stations WHERE station_id = 1')
        return c1.fetchone()

    def mk(ref, cid=1, fuel='pending', items='pending', total=1690, fuel_units=30):
        c1.execute(SQL['insert'], (ref, cid, 1, total, 240, total - 240, fuel_units, 'PLATE1', 20, 50, 'repair_kit=1', 80, fuel, items))

    def run(*ops):
        bar = threading.Barrier(len(ops)); res = [None] * len(ops)
        def w(i, op):
            c = pymysql.connect(database=SCRATCH, **args).cursor()
            bar.wait(); res[i] = op(c)
        ts = [threading.Thread(target=w, args=(i, o)) for i, o in enumerate(ops)]
        [t.start() for t in ts]; [t.join() for t in ts]
        return res

    reserve = lambda ref, n: (lambda c: c.execute(SQL['reserve'], (ref, n, n, 1, n)))
    finalize = lambda ref, state, refund, release, share: (lambda c: c.execute(SQL['finalize'], (state, refund, MAX, release, share, share, share, ref)))
    setleg = lambda ref, leg, to: (lambda c: c.execute(SQL[leg], (to, ref)))
    restock = lambda n: (lambda c: c.execute(RESTOCK, (n, 1, 7, n, MAX)))

    # ---- unique reference
    reset(); mk('GAS-PUR-1-0001')
    dup = False
    try: mk('GAS-PUR-1-0001')
    except pymysql.err.IntegrityError: dup = True
    check('UNIQUE reference: a second journal row with the same reference is rejected', dup)

    # ---- atomic reserve + journal
    reset(100); mk('R1')
    n = c1.execute(SQL['reserve'], ('R1', 30, 30, 1, 30))
    check('RESERVE decrements stock and records reserved_units in ONE statement', n >= 1 and station()[0] == 70 and row('R1')[1] == 30, (station(), row('R1')))
    n = c1.execute(SQL['reserve'], ('R1', 30, 30, 1, 30))
    check('RESERVE is once per reference (replay cannot reserve twice)', n == 0 and station()[0] == 70 and row('R1')[1] == 30)
    reset(10); mk('R2'); n = c1.execute(SQL['reserve'], ('R2', 30, 30, 1, 30))
    check('RESERVE above stock fails, stock untouched, journal untouched', n == 0 and station()[0] == 10 and row('R2')[1] == 0)
    reset(100, owner=None); mk('R3'); n = c1.execute(SQL['reserve'], ('R3', 30, 30, 1, 30))
    check('RESERVE on an unowned station is a no-op', n == 0 and station()[0] == 100 and row('R3')[1] == 0)

    ok = True
    for i in range(25):
        reset(30); mk('A'); mk('B')
        r = run(reserve('A', 30), reserve('B', 30))
        ok &= (sorted(int(x > 0) for x in r) == [0, 1] and station()[0] == 0)
    check('PURCHASE vs PURCHASE for the last 30 units: exactly one wins, stock 0 (25 runs)', ok)

    ok = True
    for i in range(25):
        reset(100); mk('A')
        run(restock(50), reserve('A', 10))
        ok &= station()[0] == 140
    check('PURCHASE(-10) vs RESTOCK(+50) from 100 -> 140 (25 runs)', ok)

    # ---- terminal transition
    reset(70); mk('F1'); c1.execute('UPDATE cm_gas_purchases SET reserved_units = 30 WHERE reference = %s', ('F1',))
    n = c1.execute(SQL['finalize'], ('completed', 0, MAX, 0, 1352, 1352, 1352, 'F1'))
    st = station()
    check('FINALIZE completed: state, revenue and income counters in one statement, stock untouched', n >= 1 and row('F1')[0] == 'completed' and st == (70, 1352, 1352, 1352) and row('F1')[5] is not None, (st, row('F1')))
    n = c1.execute(SQL['finalize'], ('compensated', 1690, MAX, 30, 0, 0, 0, 'F1'))
    check('FINALIZE replay / opposite outcome after terminal changes NOTHING (no double release, no flip)', n == 0 and row('F1')[0] == 'completed' and station() == (70, 1352, 1352, 1352))

    reset(70); mk('F2'); c1.execute('UPDATE cm_gas_purchases SET reserved_units = 30 WHERE reference = %s', ('F2',))
    n = c1.execute(SQL['finalize'], ('compensated', 1690, MAX, 30, 0, 0, 0, 'F2'))
    check('FINALIZE compensated releases the reservation once (70 -> 100), refund recorded', n >= 1 and station()[0] == 100 and row('F2')[0] == 'compensated' and row('F2')[4] == 1690)

    reset(24990); mk('F3'); n = c1.execute(SQL['finalize'], ('compensated', 0, MAX, 30, 0, 0, 0, 'F3'))
    check('FINALIZE release is capped at station capacity', station()[0] == MAX)

    reset(100, owner=None); mk('F4')
    n = c1.execute(SQL['finalize'], ('completed', 0, MAX, 0, 0, 0, 0, 'F4'))
    check('FINALIZE on an UNOWNED station (LEFT JOIN, sink) still terminates and touches no station row', n >= 1 and row('F4')[0] == 'completed' and station() == (100, 0, 0, 0), (n, station()))

    ok = True
    for i in range(25):
        reset(70); mk('W'); c1.execute("UPDATE cm_gas_purchases SET reserved_units = 30 WHERE reference = 'W'")
        run(finalize('W', 'compensated', 1690, 30, 0), finalize('W', 'compensated', 1690, 30, 0))
        ok &= (station()[0] == 100 and row('W')[0] == 'compensated')
    check('TWO COMPENSATION WORKERS: stock released once, one terminal state (25 runs)', ok)

    ok = True; seen = set()
    for i in range(40):
        reset(70); mk('X'); c1.execute("UPDATE cm_gas_purchases SET reserved_units = 30 WHERE reference = 'X'")
        run(finalize('X', 'completed', 0, 0, 1352), finalize('X', 'compensated', 1690, 30, 0))
        s, stt = row('X')[0], station()
        seen.add(s)
        # the winner's effects, and only the winner's, are present
        ok &= (s == 'completed' and stt == (70, 1352, 1352, 1352)) or (s == 'compensated' and stt == (100, 0, 0, 0))
    check('COMPENSATION vs SUCCESS: exactly one terminal result, effects match the winner (40 runs, outcomes seen: %s)' % sorted(seen), ok)

    # ---- legs
    reset(); mk('L1')
    run(setleg('L1', 'items', 'delivered'), setleg('L1', 'items', 'failed'))
    check('LEG items is first-writer-wins and never flips', row('L1')[3] in ('delivered', 'failed'))
    first = row('L1')[3]; c1.execute(SQL['items'], ('failed' if first == 'delivered' else 'delivered', 'L1'))
    check('LEG items decided once stays decided', row('L1')[3] == first)

    ok = True; seen = set()
    for i in range(40):
        reset(); mk('L2')
        r = run(lambda c: c.execute(SQL['claimFuel'], ('L2',)), setleg('L2', 'fuel', 'failed'))
        s = row('L2')[2]
        seen.add(s)
        # close first -> the claim must fail (no apply after refund); claim first -> the close may then see 'applying'
        ok &= (s == 'failed') if r[0] == 0 else (s in ('applying', 'failed'))
    check('LEG fuel claim vs close: one consistent outcome per run (seen: %s)' % sorted(seen), ok)
    reset(); mk('L3'); c1.execute(SQL['fuel'], ('failed', 'L3'))
    n = c1.execute(SQL['claimFuel'], ('L3',))
    check('LEG fuel: once a resolver closed the leg the live flow cannot claim it (no apply after refund)', n == 0 and row('L3')[2] == 'failed')
    reset(); mk('L4'); c1.execute(SQL['claimFuel'], ('L4',)); n = c1.execute(SQL['fuel'], ('delivered', 'L4'))
    check('LEG fuel: a claimed leg can be recorded delivered', n == 1 and row('L4')[2] == 'delivered')
    reset(); mk('L5'); c1.execute(SQL['finalize'], ('compensated', 0, MAX, 0, 0, 0, 0, 'L5'))
    n = c1.execute(SQL['items'], ('delivered', 'L5')) + c1.execute(SQL['claimFuel'], ('L5',))
    check('LEG writes are refused after the terminal transition', n == 0 and row('L5')[3] == 'pending')

    # ---- recovery scan
    reset(); mk('S1'); mk('S2'); c1.execute("UPDATE cm_gas_purchases SET created_at = NOW() - INTERVAL 5 MINUTE WHERE reference = 'S1'")
    c1.execute(SQL['finalize'], ('completed', 0, MAX, 0, 0, 0, 0, 'S2'))
    c1.execute(SQL['stale'], (60,)); refs = [r[0] for r in c1.fetchall()]
    check('STALE scan returns only old PENDING rows', refs == ['S1'], refs)
finally:
    admin.cursor().execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
print(f'\n{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
