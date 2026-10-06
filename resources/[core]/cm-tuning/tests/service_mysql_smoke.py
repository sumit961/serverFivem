"""Isolated MySQL smoke test for the mechanic-tuning journal (server/service_store.lua) and the vehicle-mods compare-and-swap (server/service.lua).

    python -u tests/service_mysql_smoke.py      (from resources/[core]/cm-tuning; needs `pip install pymysql`)

SAFETY: connects with the local development `mysql_connection_string` (read from server.local.cfg, never printed), creates a SCRATCH database
cm_tun_smoke_<pid>, never touches another schema, and DROPs it at the end. Real vehicles/journals are never read.
The DDL and every statement are extracted VERBATIM from the Lua source (drift fails the test) and executed in real InnoDB transactions.
"""
import os
import re
import sys
import threading
from urllib.parse import urlparse

import pymysql

HERE = os.path.dirname(os.path.abspath(__file__))
TUN = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(TUN, '..', '..', '..'))
passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond:
        passed += 1
        print('PASS  ' + name)
    else:
        failed += 1
        print('FAIL  ' + name + (f'  ({detail})' if detail is not None else ''))


store_src = open(os.path.join(TUN, 'server', 'service_store.lua'), encoding='utf-8').read()
svc_src = open(os.path.join(TUN, 'server', 'service.lua'), encoding='utf-8').read()


def lua_long(name):
    m = re.search(re.escape(name) + r'\s*=\s*\[\[(.*?)\]\]', store_src, re.S)
    assert m, name
    return m.group(1)


def lua_str(name):
    m = re.search(re.escape(name) + r"\s*=\s*(['\"])(.*?)\1\s*\n", store_src)
    assert m, name
    return m.group(2)


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


DDL = lua_long('S.DDL')
INSERT = lua_long('S.INSERT')
SEL_REF, SEL_ACTIVE, SEL_VEHICLE, SEL_EXP = (lua_str('S.SELECT_REF'), lua_str('S.SELECT_ACTIVE'), lua_str('S.SELECT_VEHICLE'), lua_str('S.SELECT_EXPIRABLE'))
CAS_TEMPLATE = "UPDATE cm_tuning_service_operations SET %s WHERE reference = ? AND status IN (%s)"
check('SQL the CAS builder template appears in service_store.lua', 'UPDATE cm_tuning_service_operations SET %s WHERE reference = ? AND status IN (%s)' in store_src)
MODS_CAS = 'UPDATE cm_owned_vehicles SET mods = ? WHERE id = ? AND mods <=> ?'
MODS_SEL = 'SELECT mods FROM cm_owned_vehicles WHERE id = ?'
check('SQL the mods compare-and-swap and read appear verbatim in service.lua', MODS_CAS in svc_src and MODS_SEL in svc_src)


def ps(sql):
    return sql.replace('?', '%s')


def cas_sql(sets, n_from):
    cols = ', '.join(sets)
    return f"UPDATE cm_tuning_service_operations SET {cols} WHERE reference = %s AND status IN ({','.join(['%s'] * n_from)})"


cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
u = urlparse(re.search(r'mysql_connection_string\s+"?([^"\n]+)', cfg).group(1).strip())
SCRATCH = f'cm_tun_smoke_{os.getpid()}'
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
    for _ in range(2):
        cur.execute(DDL)
        cur.execute('CREATE TABLE IF NOT EXISTS cm_owned_vehicles (id BIGINT PRIMARY KEY, plate VARCHAR(16) NOT NULL, mods LONGTEXT NULL)')
    cur.execute("INSERT INTO cm_owned_vehicles (id, plate, mods) VALUES (77, 'AB12CD', NULL), (78, 'ZZ99ZZ', '{\"a\":1}')"); c1.commit()
    check('DDL the journal table creates and is repeatable (extracted from the Lua source)', True)

    def row_args(ref, wo, vid, status='created', expires=2000):
        return (ref, wo, wo, str(vid), '5', '1', 'mechanic', 'main', vid, 'chip', 'character:1', 0, 50000, 'h' * 16, status, 0, 1000, 1000, expires)

    cur.execute(ps(INSERT), row_args('TUN-AAAA0001', 'WO-1', 77)); c1.commit()
    check('INSERT a journal row is stored with its binding', True)
    try:
        cur.execute(ps(INSERT), row_args('TUN-AAAA0002', 'WO-1', 78)); dup_active = None
    except pymysql.err.IntegrityError as e:
        dup_active = str(e)
    c1.rollback()
    check('UNIQUE one live authorization per work order (error names uq_tun_active, as the Lua detects it)', dup_active is not None and 'uq_tun_active' in dup_active, dup_active)
    try:
        cur.execute(ps(INSERT), row_args('TUN-AAAA0003', 'WO-2', 77)); dup_vehicle = None
    except pymysql.err.IntegrityError as e:
        dup_vehicle = str(e)
    c1.rollback()
    check('UNIQUE one live mechanic tuning operation per vehicle (error names uq_tun_vehicle)', dup_vehicle is not None and 'uq_tun_vehicle' in dup_vehicle, dup_vehicle)
    try:
        cur.execute(ps(INSERT), row_args('TUN-AAAA0001', 'WO-9', 79)); dup_ref = None
    except pymysql.err.IntegrityError as e:
        dup_ref = str(e)
    c1.rollback()
    check('UNIQUE the reference itself is unique', dup_ref is not None and 'uq_tun_ref' in dup_ref, dup_ref)

    def state(ref):
        cur.execute(ps(SEL_REF), (ref,)); r = cur.fetchone(); c1.commit(); return r

    def cas(conn, cr, ref, frm, sets_vals):
        names = sorted(sets_vals)
        sets = [f'`{n}` = NULL' if sets_vals[n] is False else f'`{n}` = %s' for n in names]
        vals = [sets_vals[n] for n in names if sets_vals[n] is not False]
        n = cr.execute(cas_sql(sets, len(frm)), vals + [ref] + list(frm)); conn.commit(); return n

    check('CAS created -> quoted (guarded UPDATE)', cas(c1, cur, 'TUN-AAAA0001', ['created', 'quoted'], {'status': 'quoted', 'amount': 25000, 'revision': 1, 'updated_at': 1100}) == 1 and state('TUN-AAAA0001')['status'] == 'quoted')
    check('CAS from the wrong state matches 0 rows', cas(c1, cur, 'TUN-AAAA0001', ['paid', 'applying'], {'status': 'applying', 'updated_at': 1101}) == 0 and state('TUN-AAAA0001')['status'] == 'quoted')
    check('CAS quoted -> invoiced binds the invoice', cas(c1, cur, 'TUN-AAAA0001', ['quoted'], {'status': 'invoiced', 'invoice_ref': 'INV-1', 'updated_at': 1102}) == 1 and state('TUN-AAAA0001')['invoice_ref'] == 'INV-1')

    # two workers racing for the paid transition: exactly one wins
    c2 = connect(SCRATCH); conns.append(c2); cur2 = c2.cursor(pymysql.cursors.DictCursor)
    res = {}
    barrier = threading.Barrier(2)

    def worker(name, conn, cr):
        barrier.wait(5)
        res[name] = cas(conn, cr, 'TUN-AAAA0001', ['invoiced'], {'status': 'paid', 'paid_at': 1200, 'updated_at': 1200})

    ts = [threading.Thread(target=worker, args=('a', c1, cur)), threading.Thread(target=worker, args=('b', c2, cur2))]
    for t in ts: t.start()
    for t in ts: t.join(10)
    check('CAS two concurrent MarkPaid transitions: exactly one wins', sorted(res.values()) == [0, 1], res)
    check('CAS paid -> applying -> committed releases the unique keys (NULL)', cas(c1, cur, 'TUN-AAAA0001', ['paid', 'applying'], {'status': 'applying', 'attempts': 1, 'updated_at': 1300}) == 1
          and cas(c1, cur, 'TUN-AAAA0001', ['applying'], {'status': 'committed', 'applied_at': 1301, 'active_key': False, 'vehicle_key': False, 'failure_reason': False, 'updated_at': 1301}) == 1)
    r = state('TUN-AAAA0001')
    check('CAS committed row keeps its record but frees work order and vehicle', r['status'] == 'committed' and r['active_key'] is None and r['vehicle_key'] is None and r['applied_at'] == 1301)
    cur.execute(ps(INSERT), row_args('TUN-AAAA0004', 'WO-1', 77)); c1.commit()
    check('UNIQUE after commit the same work order / vehicle can be authorized again (NULL keys are not unique)', state('TUN-AAAA0004') is not None)
    check('CAS a committed row cannot be moved again (replay-safe)', cas(c1, cur, 'TUN-AAAA0001', ['created', 'quoted', 'invoiced', 'paid', 'applying'], {'status': 'cancelled', 'updated_at': 1400}) == 0 and state('TUN-AAAA0001')['status'] == 'committed')

    # restart / response loss: another connection (a fresh process) reads the committed state
    c2.close(); conns.remove(c2)
    c3 = connect(SCRATCH); conns.append(c3); cur3 = c3.cursor(pymysql.cursors.DictCursor)
    cur3.execute(ps(SEL_REF), ('TUN-AAAA0001',)); rr = cur3.fetchone(); c3.commit()
    check('RESPONSE LOSS / RESTART a fresh connection sees the committed outcome', rr['status'] == 'committed')

    # expirable: only unpaid created/quoted rows past their expiry
    cur.execute(ps(INSERT), row_args('TUN-AAAA0005', 'WO-5', 81, status='quoted', expires=900)); c1.commit()
    cur.execute(ps(INSERT), row_args('TUN-AAAA0006', 'WO-6', 82, status='created', expires=5000)); c1.commit()
    cur.execute(ps(INSERT), row_args('TUN-AAAA0007', 'WO-7', 83, status='paid', expires=900)); c1.commit()
    cur.execute(ps(SEL_EXP), (2000, 50)); refs = sorted(r['reference'] for r in cur.fetchall()); c1.commit()
    check('EXPIRY only unpaid created/quoted rows past expiry are returned (paid never expires)', refs == ['TUN-AAAA0005'], refs)
    check('SELECT by active_key and vehicle_key use the unique indexes', (cur.execute(ps(SEL_ACTIVE), ('WO-6',)) or 1) and cur.fetchone()['reference'] == 'TUN-AAAA0006' and (cur.execute(ps(SEL_VEHICLE), ('83',)) or 1) and cur.fetchone()['reference'] == 'TUN-AAAA0007')
    c1.commit()

    # vehicle mods compare-and-swap: exactly one concurrent writer wins; NULL-safe
    cur.execute(ps(MODS_SEL), (77,)); old = cur.fetchone()['mods']; c1.commit()
    c4 = connect(SCRATCH); conns.append(c4); cur4 = c4.cursor(pymysql.cursors.DictCursor)
    out = {}
    bar2 = threading.Barrier(2)

    def writer(name, conn, cr, payload):
        bar2.wait(5)
        out[name] = cr.execute(ps(MODS_CAS), (payload, 77, old)); conn.commit()

    ts = [threading.Thread(target=writer, args=('a', c1, cur, '{"turbo":true}')), threading.Thread(target=writer, args=('b', c4, cur4, '{"mods":{"11":1}}'))]
    for t in ts: t.start()
    for t in ts: t.join(10)
    check('MODS CAS from NULL (never tuned): two concurrent writers, exactly one wins (no lost update)', sorted(out.values()) == [0, 1], out)
    cur.execute(ps(MODS_SEL), (77,)); now = cur.fetchone()['mods']; c1.commit()
    check('MODS CAS the loser re-reads the winner and its write against the OLD value is refused', cur.execute(ps(MODS_CAS), ('{"x":1}', 77, old)) == 0 and now in ('{"turbo":true}', '{"mods":{"11":1}}'))
    c1.commit()
    check('MODS CAS a write against the current value succeeds (retry path)', cur.execute(ps(MODS_CAS), ('{"merged":true}', 77, now)) == 1)
    c1.commit()
finally:
    for c in conns:
        try:
            c.close()
        except Exception:
            pass
    adm = admin.cursor()
    adm.execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
    print(f'scratch database dropped: {SCRATCH}')
    adm.execute('SHOW DATABASES LIKE %s', ('cm_tun_smoke_%',))
    check('CLEANUP no scratch database remains', len(adm.fetchall()) == 0)

print(f'\ncm-tuning service MySQL smoke: {passed} passed, {failed} failed')
sys.exit(0 if failed == 0 else 1)
