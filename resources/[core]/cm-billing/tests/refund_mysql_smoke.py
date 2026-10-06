"""Isolated MySQL smoke test for the cm-billing refund SQL (server/refund.lua + server/schema.lua).

    python -u tests/refund_mysql_smoke.py      (from resources/[core]/cm-billing; needs `pip install pymysql`)

SAFETY: connects with the local development `mysql_connection_string` (read from server.local.cfg, never printed), creates a SCRATCH database
named cm_rfd_smoke_<pid>, never touches another schema, and DROPs it at the end.

WHAT THIS IS: the statements are EXTRACTED from the production Lua source (the `SQL` table in refund.lua and the DDL/migrations in schema.lua), so
there is no drift, and run in real InnoDB transactions on separate connections. It proves the DDL is valid and repeatable (including the additive
column migration on a pre-refund invoice table), the guarded reservation (no over-refund, even concurrently), the conditional journal insert
(ROW_COUNT() = 1), UNIQUE (provider, reference) rollback of the reservation, the completion/release transactions (idempotent, left-to-right
refund_state), and unsigned underflow protection. It does NOT run the Lua saga (that is `cm_billing_selftest` over real MySQL + owner doubles).
"""
import os
import re
import sys
import threading
import time
from urllib.parse import urlparse

import pymysql

HERE = os.path.dirname(os.path.abspath(__file__))
BILLING = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(BILLING, '..', '..', '..'))
passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond:
        passed += 1
        print('PASS  ' + name)
    else:
        failed += 1
        print('FAIL  ' + name + (f'  ({detail})' if detail is not None else ''))


refund_src = open(os.path.join(BILLING, 'server', 'refund.lua'), encoding='utf-8').read()
schema_src = open(os.path.join(BILLING, 'server', 'schema.lua'), encoding='utf-8').read()

block = refund_src[refund_src.index('local SQL = {'):refund_src.index('S.RefundSQL = SQL')]
SQL = {}
for m in re.finditer(r'^\s+(\w+) = (\[\[.*?\]\]|"[^"\n]*"|\'[^\'\n]*\'),\s*$', block, re.M | re.S):
    raw = m.group(2)
    text = raw[2:-2] if raw.startswith('[[') else raw[1:-1]
    SQL[m.group(1)] = re.sub(r'\s+', ' ', text).replace('?', '%s')
assert len(SQL) == 11, f'extracted only {len(SQL)} statements: {sorted(SQL)}'


def ddl(table):
    m = re.search(r'(CREATE TABLE IF NOT EXISTS ' + table + r' \(.*?\n    \) %s)\]\]', schema_src, re.S)
    assert m, table
    return m.group(1).replace('%s', 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci')


cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
u = urlparse(re.search(r'mysql_connection_string\s+"?([^"\n]+)', cfg).group(1).strip())
SCRATCH = f'cm_rfd_smoke_{os.getpid()}'
args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', autocommit=False, charset='utf8mb4')


def connect(db=None):
    return pymysql.connect(database=db, **args)


admin = connect()
admin.autocommit(True)
admin.cursor().execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
print(f'scratch database created: {SCRATCH}')
conns = []


def new_invoice(cur, ref, amount=20000, status='paid'):
    cur.execute("INSERT INTO cm_billing_invoices (public_reference, recipient_character_id, issuer_type, issuer_label, issuer_resource, destination_type, destination_id, amount, label, status) "
                "VALUES (%s, 'c1', 'business', 'x', 'prov', 'business', 'store:1', %s, 'x', %s)", (ref, amount, status))
    return cur.lastrowid


def claim(conn, cur, inv_id, provider, ref, amount, paid, mode='exact'):
    """Mirror of RequestRefund's claim transaction. Returns 'claimed' | 'refused' | 'duplicate'."""
    try:
        cur.execute(SQL['reserve'], (amount, inv_id, provider, amount, paid))
        cur.execute(SQL['insert'], (provider, ref, inv_id, 'INV-X', 'c1', 'bank', 'business', 'store:1', amount, mode, 'service_failed'))
        inserted = cur.rowcount
        conn.commit()
        return 'claimed' if inserted == 1 else 'refused'
    except pymysql.err.IntegrityError:
        conn.rollback()
        return 'duplicate'


try:
    c1 = connect(SCRATCH); conns.append(c1)
    cur = c1.cursor(pymysql.cursors.DictCursor)

    # ---- DDL + migration of a pre-refund invoice table
    legacy = ddl('cm_billing_invoices')
    legacy = re.sub(r"\n\s+refunded_amount .*?\n\s+refunded_at TIMESTAMP NULL DEFAULT NULL,", '', legacy, flags=re.S)
    check('legacy invoice DDL (without refund columns) was derived', 'refunded_amount' not in legacy)
    cur.execute(legacy)
    cur.execute("SHOW COLUMNS FROM cm_billing_invoices LIKE 'refund_state'")
    check('legacy table has no refund columns yet', cur.fetchone() is None)
    for m in re.finditer(r"column = '(\w+)', ddl = ('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\")", schema_src):
        col, stmt = m.group(1), m.group(2)[1:-1]
        cur.execute("SHOW COLUMNS FROM cm_billing_invoices LIKE %s", (col,))
        if cur.fetchone() is None:
            cur.execute(stmt)
    for m in re.finditer(r"column = '(\w+)', ddl = ('(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\")", schema_src):   # second pass: repeatable no-op
        cur.execute("SHOW COLUMNS FROM cm_billing_invoices LIKE %s", (m.group(1),))
        assert cur.fetchone() is not None
    cur.execute("SELECT COUNT(*) AS n FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'cm_billing_invoices' AND column_name IN ('refunded_amount','refund_reserved_amount','refund_state','refunded_at')")
    check('additive migration adds the four invoice refund columns and is repeatable', cur.fetchone()['n'] == 4)
    for _ in range(2):
        cur.execute(ddl('cm_billing_refunds'))
    check('refund journal DDL creates and is repeatable (CREATE TABLE IF NOT EXISTS)', True)
    cur.execute("SELECT COUNT(*) AS n FROM information_schema.statistics WHERE table_schema = DATABASE() AND non_unique = 0 AND index_name = 'uq_refund_provider_ref'")
    check('UNIQUE (provider_resource, refund_reference) exists', cur.fetchone()['n'] == 2)
    c1.commit()

    # ---- claim: reservation + conditional journal insert
    inv = new_invoice(cur, 'INV-A', 20000); c1.commit()
    check('CLAIM first refund of 15000 on a paid 20000 invoice commits', claim(c1, cur, inv, 'prov', 'ref-0001-a', 15000, 20000) == 'claimed')
    cur.execute('SELECT refund_reserved_amount AS r, refund_state AS s FROM cm_billing_invoices WHERE id = %s', (inv,))
    row = cur.fetchone(); c1.commit()
    check('CLAIM reservation recorded and invoice shows processing', int(row['r']) == 15000 and row['s'] == 'processing', row)
    check('CLAIM second refund of 15000 is refused by the guard (30000 > 20000): no journal row, no reservation',
          claim(c1, cur, inv, 'prov', 'ref-0002-b', 15000, 20000) == 'refused')
    cur.execute('SELECT COUNT(*) AS n FROM cm_billing_refunds WHERE invoice_id = %s', (inv,)); n = cur.fetchone()['n']
    cur.execute('SELECT refund_reserved_amount AS r FROM cm_billing_invoices WHERE id = %s', (inv,)); r = int(cur.fetchone()['r']); c1.commit()
    check('CLAIM refusal left exactly one journal row and 15000 reserved', n == 1 and r == 15000, (n, r))
    check('CLAIM a refund of the remaining 5000 fits exactly', claim(c1, cur, inv, 'prov', 'ref-0003-c', 5000, 20000) == 'claimed')
    check('CLAIM nothing is left to reserve', claim(c1, cur, inv, 'prov', 'ref-0004-d', 1, 20000) == 'refused')

    # duplicate (provider, reference) rolls the reservation back
    inv2 = new_invoice(cur, 'INV-B', 10000); c1.commit()
    check('CLAIM duplicate refund reference aborts (UNIQUE) ...', claim(c1, cur, inv2, 'prov', 'ref-0001-a', 1000, 10000) == 'duplicate')
    cur.execute('SELECT refund_reserved_amount AS r FROM cm_billing_invoices WHERE id = %s', (inv2,)); r = int(cur.fetchone()['r']); c1.commit()
    check('CLAIM ... and its reservation is rolled back (0 reserved)', r == 0, r)
    check('CLAIM other provider is refused by the issuer guard', claim(c1, cur, inv2, 'someone-else', 'ref-0009-z', 1000, 10000) == 'refused')

    # unpaid / voided / settling invoices cannot reserve
    for st in ('pending', 'settling', 'voided', 'expired'):
        i = new_invoice(cur, f'INV-{st[:3].upper()}', 5000, st); c1.commit()
        check(f'CLAIM invoice in state {st} is refused (interlock: only a committed paid invoice)', claim(c1, cur, i, 'prov', f'ref-st-{st}', 1000, 5000) == 'refused')

    # ---- concurrent over-refund across two connections
    inv3 = new_invoice(cur, 'INV-C', 20000); c1.commit()
    c2 = connect(SCRATCH); conns.append(c2); cur2 = c2.cursor(pymysql.cursors.DictCursor)
    results = {}
    gate = threading.Barrier(2)

    def worker(conn, cursor, key, ref):
        gate.wait()
        results[key] = claim(conn, cursor, inv3, 'prov', ref, 15000, 20000)

    threads = [threading.Thread(target=worker, args=(c1, cur, 'a', 'ref-race-a')), threading.Thread(target=worker, args=(c2, cur2, 'b', 'ref-race-b'))]
    for t in threads: t.start()
    for t in threads: t.join(15)
    cur.execute('SELECT refund_reserved_amount AS r FROM cm_billing_invoices WHERE id = %s', (inv3,)); r = int(cur.fetchone()['r'])
    cur.execute('SELECT COUNT(*) AS n FROM cm_billing_refunds WHERE invoice_id = %s', (inv3,)); n = cur.fetchone()['n']; c1.commit()
    check('CONCURRENCY two simultaneous refunds of 15000 on 20000: exactly one claims, reserved stays 15000, one journal row',
          sorted(results.values()) == ['claimed', 'refused'] and r == 15000 and n == 1, (results, r, n))

    # same reference from two connections: one journal row, reservation counted once
    inv4 = new_invoice(cur, 'INV-D', 9000); c1.commit()
    results.clear()
    gate = threading.Barrier(2)

    def worker2(conn, cursor, key):
        gate.wait()
        results[key] = claim(conn, cursor, inv4, 'prov', 'ref-same-ref', 4000, 9000)

    threads = [threading.Thread(target=worker2, args=(c1, cur, 'a')), threading.Thread(target=worker2, args=(c2, cur2, 'b'))]
    for t in threads: t.start()
    for t in threads: t.join(15)
    cur.execute('SELECT refund_reserved_amount AS r FROM cm_billing_invoices WHERE id = %s', (inv4,)); r = int(cur.fetchone()['r'])
    cur.execute('SELECT COUNT(*) AS n FROM cm_billing_refunds WHERE invoice_id = %s', (inv4,)); n = cur.fetchone()['n']; c1.commit()
    check('CONCURRENCY same refund reference racing on two connections: one journal row, 4000 reserved (not 8000)',
          'claimed' in results.values() and r == 4000 and n == 1, (results, r, n))

    # ---- completion transaction (journal + invoice aggregate), idempotent, left-to-right refund_state
    cur.execute("UPDATE cm_billing_refunds SET status = 'destination_debited', debit_state = 'committed' WHERE refund_reference = 'ref-same-ref'")
    cur.execute("SELECT id FROM cm_billing_refunds WHERE refund_reference = 'ref-same-ref'"); jid = cur.fetchone()['id']; c1.commit()

    def complete(jid, amount, paid, inv_id):
        cur.execute(SQL['complete_journal'], (jid,))
        cur.execute(SQL['complete_invoice'], (amount, paid, inv_id))
        c1.commit()

    complete(jid, 4000, 9000, inv4)
    cur.execute('SELECT refunded_amount AS a, refund_reserved_amount AS r, refund_state AS s, refunded_at AS t FROM cm_billing_invoices WHERE id = %s', (inv4,)); row = cur.fetchone(); c1.commit()
    check('COMPLETE partial: refunded 4000 of 9000 => refund_state partial, refunded_at set', int(row['a']) == 4000 and row['s'] == 'partial' and row['t'] is not None, row)
    complete(jid, 4000, 9000, inv4)     # replay of the completion
    cur.execute('SELECT refunded_amount AS a FROM cm_billing_invoices WHERE id = %s', (inv4,)); a = int(cur.fetchone()['a']); c1.commit()
    check('COMPLETE replay is a no-op (journal already completed => invoice not credited twice)', a == 4000, a)
    # second refund for the remainder -> refunded
    claim(c1, cur, inv4, 'prov', 'ref-last-one', 5000, 9000)
    cur.execute("SELECT id FROM cm_billing_refunds WHERE refund_reference = 'ref-last-one'"); j2 = cur.fetchone()['id']
    cur.execute("UPDATE cm_billing_refunds SET status = 'destination_debited', debit_state = 'committed' WHERE id = %s", (j2,)); c1.commit()
    complete(j2, 5000, 9000, inv4)
    cur.execute('SELECT refunded_amount AS a, refund_state AS s, status AS st FROM cm_billing_invoices WHERE id = %s', (inv4,)); row = cur.fetchone(); c1.commit()
    check('COMPLETE full: refunded 9000 of 9000 => refund_state refunded; invoice status stays paid', int(row['a']) == 9000 and row['s'] == 'refunded' and row['st'] == 'paid', row)
    check('COMPLETE terminal: nothing more can be reserved', claim(c1, cur, inv4, 'prov', 'ref-after-full', 1, 9000) == 'refused')

    # ---- completion with another refund still in flight => processing
    inv5 = new_invoice(cur, 'INV-E', 10000); c1.commit()
    claim(c1, cur, inv5, 'prov', 'ref-e-one', 3000, 10000); claim(c1, cur, inv5, 'prov', 'ref-e-two', 3000, 10000)
    cur.execute("SELECT id FROM cm_billing_refunds WHERE refund_reference = 'ref-e-one'"); je = cur.fetchone()['id']
    cur.execute("UPDATE cm_billing_refunds SET status = 'destination_debited', debit_state = 'committed' WHERE id = %s", (je,)); c1.commit()
    complete(je, 3000, 10000, inv5)
    cur.execute('SELECT refund_state AS s, refunded_amount AS a, refund_reserved_amount AS r FROM cm_billing_invoices WHERE id = %s', (inv5,)); row = cur.fetchone(); c1.commit()
    check('COMPLETE with a sibling still in flight keeps refund_state processing (3000 done, 6000 reserved)', row['s'] == 'processing' and int(row['a']) == 3000 and int(row['r']) == 6000, row)

    # ---- release (abandon) transaction
    cur.execute("SELECT id FROM cm_billing_refunds WHERE refund_reference = 'ref-e-two'"); jt = cur.fetchone()['id']; c1.commit()
    cur.execute(SQL['fail_journal'], ('abandoned:test', jt)); cur.execute(SQL['release_invoice'], (3000, 10000, inv5)); c1.commit()
    cur.execute('SELECT refund_state AS s, refunded_amount AS a, refund_reserved_amount AS r FROM cm_billing_invoices WHERE id = %s', (inv5,))
    row = cur.fetchone(); c1.commit()
    check('RELEASE abandoned journal returns 3000 of reservation; state falls back to partial', row['s'] == 'partial' and int(row['r']) == 3000 and int(row['a']) == 3000, row)
    cur.execute(SQL['fail_journal'], ('again', jt)); cur.execute(SQL['release_invoice'], (3000, 10000, inv5)); c1.commit()
    cur.execute('SELECT refund_reserved_amount AS r FROM cm_billing_invoices WHERE id = %s', (inv5,)); r = int(cur.fetchone()['r']); c1.commit()
    check('RELEASE replay is a no-op (already failed => reservation not released twice)', r == 3000, r)
    cur.execute(SQL['fail_journal'], ('x', je)); cur.execute(SQL['release_invoice'], (3000, 10000, inv5)); c1.commit()
    cur.execute('SELECT refund_reserved_amount AS r FROM cm_billing_invoices WHERE id = %s', (inv5,)); r = int(cur.fetchone()['r']); c1.commit()
    check('RELEASE refuses a completed journal (cannot fail a refund whose money moved)', r == 3000, r)

    # ---- unsigned underflow protection
    try:
        cur.execute('UPDATE cm_billing_invoices SET refund_reserved_amount = refund_reserved_amount - 99999 WHERE id = %s', (inv5,))
        under = False
    except (pymysql.err.DataError, pymysql.err.OperationalError):
        under = True
    c1.rollback()
    check('BIGINT UNSIGNED refuses a negative reservation', under)
    try:
        cur.execute("INSERT INTO cm_billing_refunds (provider_resource, refund_reference, invoice_id, invoice_reference, payer_character_id, payment_account, destination_type, amount, reason) "
                    "VALUES ('prov', 'ref-0001-a', 1, 'x', 'c', 'bank', 'business', 1, 'service_failed')")
        dup = False
    except pymysql.err.IntegrityError:
        dup = True
    c1.rollback()
    check('UNIQUE journal key rejects a duplicate (provider, reference) in MySQL', dup)
    # ---- HIGH-VALUE billing (provider-specific limits): numeric storage, business credit/debit, refund and partial refund at real magnitudes
    cfg_src = open(os.path.join(BILLING, 'config.lua'), encoding='utf-8').read()
    hard = int(re.search(r'HardMaxAmount = (\d+)', cfg_src).group(1))
    mech_limit = int(re.search(r"\['cm-mechanic'\] = \{\s*enabled = true, maxAmount = (\d+)", cfg_src).group(1))
    comm_limit = int(re.search(r"\['cm-commercial-ownership'\] = \{\s*enabled = true, maxAmount = (\d+)", cfg_src).group(1))
    check('HV limits: mechanic provider limit is provider-specific (> commercial-ownership) and below the platform ceiling', comm_limit == 50000 and 50000 < mech_limit <= hard, (comm_limit, mech_limit, hard))
    check('HV limits: platform ceiling fits character INT cash/bank (2,147,483,647) and the 2,000,000,000 business balance cap with wide margin', hard * 100 < 2147483647 and hard < 2000000000)
    store_src = open(os.path.join(BILLING, '..', 'cm-mechanic', 'server', 'store.lua'), encoding='utf-8').read()
    shop_ddl = re.search(r'(CREATE TABLE IF NOT EXISTS cm_mechanic_shops \(.*?\n    \))\]\]', store_src, re.S).group(1)
    check('HV storage: the mechanic business balance column is BIGINT (extracted from cm-mechanic/store.lua)', 'business_balance BIGINT NOT NULL' in shop_ddl)
    cur.execute(shop_ddl)
    cur.execute("INSERT INTO cm_mechanic_shops (shop_id, label, owner_character_id, business_balance) VALUES ('qa', 'QA', 7, 0)"); c1.commit()
    found_src = open(os.path.join(BILLING, '..', 'cm-commercial-ownership', 'server', 'foundation.lua'), encoding='utf-8').read()
    check('HV storage: business credit/debit SQL templates are the production ones (guarded, no 50k clamp)',
          "`%s` + ? WHERE `%s` = ? AND `%s` = ? AND `%s` + ? <= ?" in found_src and "`%s` - ? WHERE `%s` = ? AND `%s` = ? AND `%s` >= ?" in found_src and 'local BALANCE_CAP = 2000000000' in found_src)

    def biz_credit(amount):
        n = cur.execute('UPDATE cm_mechanic_shops SET business_balance = business_balance + %s WHERE shop_id = %s AND owner_character_id = %s AND business_balance + %s <= %s', (amount, 'qa', 7, amount, 2000000000)); c1.commit(); return n
    def biz_debit(amount):
        n = cur.execute('UPDATE cm_mechanic_shops SET business_balance = business_balance - %s WHERE shop_id = %s AND owner_character_id = %s AND business_balance >= %s', (amount, 'qa', 7, amount)); c1.commit(); return n
    def biz_balance():
        cur.execute("SELECT business_balance AS b FROM cm_mechanic_shops WHERE shop_id = 'qa'"); b = int(cur.fetchone()['b']); c1.commit(); return b

    check('HV business credit of the mechanic limit applies exactly (no 50,000 truncation)', biz_credit(mech_limit) == 1 and biz_balance() == mech_limit)
    check('HV business credit of a 120,000 invoice then exact debit of the 120,000 refund', biz_credit(120000) == 1 and biz_debit(120000) == 1 and biz_balance() == mech_limit)
    check('HV business debit never goes negative (balance guard)', biz_debit(mech_limit + 1) == 0 and biz_balance() == mech_limit)
    check('HV business credit beyond the 2,000,000,000 application cap is refused', biz_credit(2000000000) == 0 and biz_balance() == mech_limit)

    hv_max = new_invoice(cur, 'INV-HVMAX', hard); hv = new_invoice(cur, 'INV-HV120', 120000); c1.commit()
    cur.execute('SELECT amount FROM cm_billing_invoices WHERE id = %s', (hv_max,)); amt = int(cur.fetchone()['amount']); c1.commit()
    check('HV invoice amount BIGINT UNSIGNED stores the platform ceiling exactly', amt == hard, amt)
    check('HV full refund of a 120,000 paid invoice reserves, journals and completes', claim(c1, cur, hv, 'prov', 'hv-full-0001', 120000, 120000, 'full') == 'claimed')
    cur.execute("SELECT id FROM cm_billing_refunds WHERE refund_reference = 'hv-full-0001'"); jf = cur.fetchone()['id']
    cur.execute("UPDATE cm_billing_refunds SET status = 'destination_debited', debit_state = 'committed' WHERE id = %s", (jf,)); c1.commit()
    complete(jf, 120000, 120000, hv)
    cur.execute('SELECT refunded_amount AS a, refund_state AS s FROM cm_billing_invoices WHERE id = %s', (hv,)); row = cur.fetchone(); c1.commit()
    check('HV full refund: refunded 120,000 of 120,000 => refunded; replay journal key conflicts', int(row['a']) == 120000 and row['s'] == 'refunded'
          and claim(c1, cur, hv, 'prov', 'hv-full-0001', 120000, 120000, 'full') in ('duplicate', 'refused'))
    hv2 = new_invoice(cur, 'INV-HVPART', 120000); c1.commit()
    check('HV partial refund 20,000 of 120,000 claims', claim(c1, cur, hv2, 'prov', 'hv-part-0001', 20000, 120000) == 'claimed')
    cur.execute("SELECT id FROM cm_billing_refunds WHERE refund_reference = 'hv-part-0001'"); jp = cur.fetchone()['id']
    cur.execute("UPDATE cm_billing_refunds SET status = 'destination_debited', debit_state = 'committed' WHERE id = %s", (jp,)); c1.commit()
    complete(jp, 20000, 120000, hv2)
    cur.execute('SELECT refunded_amount AS a, refund_reserved_amount AS r, refund_state AS s FROM cm_billing_invoices WHERE id = %s', (hv2,)); row = cur.fetchone(); c1.commit()
    check('HV partial: refunded 20,000, net paid 100,000, state partial', int(row['a']) == 20000 and 120000 - int(row['a']) == 100000 and row['s'] == 'partial', row)
    check('HV cumulative bound: 100,001 refused, exactly 100,000 accepted', claim(c1, cur, hv2, 'prov', 'hv-part-0002', 100001, 120000) == 'refused' and claim(c1, cur, hv2, 'prov', 'hv-part-0003', 100000, 120000) == 'claimed')
    check('HV refund is independent of any creation limit (a 1,800,000 invoice keeps its full refundable amount)', (lambda i: claim(c1, cur, i, 'prov', 'hv-big-0001', 1500000, 1800000) == 'claimed' and claim(c1, cur, i, 'prov', 'hv-big-0002', 300000, 1800000) == 'claimed')(new_invoice(cur, 'INV-HVBIG', 1800000)))
finally:
    for c in conns:
        try:
            c.close()
        except Exception:
            pass
    adm = admin.cursor()
    adm.execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
    print(f'scratch database dropped: {SCRATCH}')
    adm.execute('SHOW DATABASES LIKE %s', ('cm_rfd_smoke_%',))
    check('CLEANUP no scratch database remains', len(adm.fetchall()) == 0)

print(f'\ncm-billing refund MySQL smoke: {passed} passed, {failed} failed')
sys.exit(0 if failed == 0 else 1)
