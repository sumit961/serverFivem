"""Isolated MySQL smoke test for the two SQL queries behind cm-law `GetOnDutyCount` (server/main.lua).

    python -u tests/duty_count_mysql_smoke.py      (from resources/[core]/cm-law; needs `pip install pymysql`)

SAFETY: connects with the local development `mysql_connection_string` (read from server.local.cfg, never printed), creates a SCRATCH database
cm_law_smoke_<pid> with minimal copies of the member/rank tables (only the columns the queries use), never reads real roster data, and DROPs the scratch
database at the end. The queries are EXTRACTED from the production Lua source, so they cannot drift.
"""
import os
import re
import sys
from urllib.parse import urlparse

import pymysql

HERE = os.path.dirname(os.path.abspath(__file__))
LAW = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(LAW, '..', '..', '..'))
passed = failed = 0


def check(name, cond, detail=None):
    global passed, failed
    if cond:
        passed += 1
        print('PASS  ' + name)
    else:
        failed += 1
        print('FAIL  ' + name + (f'  ({detail})' if detail is not None else ''))


src = open(os.path.join(LAW, 'server', 'main.lua'), encoding='utf-8').read()
block = src[src.index('local dutyCounter = LawDutyCount.New({'):src.index("exports('GetOnDutyCount'")]
central = re.search(r'queryCentral = function\(orgId\)\s*return MySQL\.query\.await\(\[\[(.*?)\]\], \{ orgId \}\)', block, re.S).group(1).replace('?', '%s')
legacy = re.search(r'queryLegacy = function\(\)\s*return MySQL\.query\.await\(\[\[(.*?)\]\]\)', block, re.S).group(1)
assert 'on_duty = 1' in central and 'on_duty = 1' in legacy

cfg = open(os.path.join(ROOT, 'server.local.cfg'), encoding='utf-8').read()
u = urlparse(re.search(r'mysql_connection_string\s+"?([^"\n]+)', cfg).group(1).strip())
SCRATCH = f'cm_law_smoke_{os.getpid()}'
args = dict(host=u.hostname, port=u.port or 3306, user=u.username, password=u.password or '', autocommit=True, charset='utf8mb4')
admin = pymysql.connect(**args)
admin.cursor().execute(f'CREATE DATABASE `{SCRATCH}` CHARACTER SET utf8mb4')
print(f'scratch database created: {SCRATCH}')
conn = None
try:
    conn = pymysql.connect(database=SCRATCH, **args)
    cur = conn.cursor()
    for stmt in (
        "CREATE TABLE cm_legal_ranks (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, organization_id VARCHAR(32) NOT NULL, name VARCHAR(40) NOT NULL)",
        "CREATE TABLE cm_legal_members (organization_id VARCHAR(32) NOT NULL, character_id VARCHAR(64) NOT NULL, rank_id BIGINT UNSIGNED NOT NULL, on_duty TINYINT(1) NOT NULL DEFAULT 0, suspended_until DATETIME NULL, PRIMARY KEY (organization_id, character_id))",
        "CREATE TABLE cm_police_ranks (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, name VARCHAR(40) NOT NULL)",
        "CREATE TABLE cm_police_members (character_id VARCHAR(64) NOT NULL PRIMARY KEY, rank_id BIGINT UNSIGNED NOT NULL, on_duty TINYINT(1) NOT NULL DEFAULT 0, suspended_until DATETIME NULL)",
    ):
        cur.execute(stmt)
    cur.execute("INSERT INTO cm_legal_ranks (organization_id, name) VALUES ('sahp','Trooper'),('sheriff','Deputy')")
    cur.execute("INSERT INTO cm_police_ranks (name) VALUES ('Officer')")
    sahp_rank, sheriff_rank = 1, 2
    m = [
        ('sahp', 'a1', sahp_rank, 1, None),                                  # counted
        ('sahp', 'a2', sahp_rank, 0, None),                                  # off duty
        ('sahp', 'a3', sahp_rank, 1, '2099-01-01 00:00:00'),                 # suspended
        ('sahp', 'a4', 999, 1, None),                                        # rank missing (orphan row)
        ('sahp', 'a5', sheriff_rank, 1, None),                               # rank of another organization
        ('sheriff', 'b1', sheriff_rank, 1, None),                            # other organization
        ('sheriff', 'a1', sheriff_rank, 1, None),                            # same character in two organizations: counted once per organization
    ]
    cur.executemany('INSERT INTO cm_legal_members (organization_id, character_id, rank_id, on_duty, suspended_until) VALUES (%s,%s,%s,%s,%s)', m)
    cur.executemany('INSERT INTO cm_police_members (character_id, rank_id, on_duty, suspended_until) VALUES (%s,%s,%s,%s)', [
        ('p1', 1, 1, None), ('p2', 1, 0, None), ('p3', 1, 1, '2099-01-01 00:00:00'), ('p4', 1, 1, '2000-01-01 00:00:00'), ('p5', 77, 1, None)])

    def ids(sql, params=None):
        cur.execute(sql, params) if params is not None else cur.execute(sql)
        return sorted(r[0] for r in cur.fetchall())

    check('CENTRAL sahp: only the on-duty, ranked, unsuspended member is returned', ids(central, ('sahp',)) == ['a1'], ids(central, ('sahp',)))
    check('CENTRAL sheriff: other organizations and the shared character are independent', ids(central, ('sheriff',)) == ['a1', 'b1'])
    check('CENTRAL an organization with no members returns an empty list (zero, not an error)', ids(central, ('fib',)) == [])
    check('CENTRAL DISTINCT: one row per character', len(ids(central, ('sheriff',))) == len(set(ids(central, ('sheriff',)))))
    check('LEGACY police: on duty, ranked, not currently suspended (a past suspension no longer blocks)', ids(legacy) == ['p1', 'p4'], ids(legacy))
    cur.execute('EXPLAIN ' + central, ('sahp',)); plan = cur.fetchall()
    check('PERFORMANCE the central query uses the (organization_id, character_id) primary key prefix, not a full scan', any((row[5] or '') in ('PRIMARY',) or 'PRIMARY' in str(row) for row in plan), plan)
finally:
    try:
        if conn: conn.close()
    except Exception:
        pass
    a = admin.cursor()
    a.execute(f'DROP DATABASE IF EXISTS `{SCRATCH}`')
    print(f'scratch database dropped: {SCRATCH}')
    a.execute('SHOW DATABASES LIKE %s', ('cm_law_smoke_%',))
    check('CLEANUP no scratch database remains', len(a.fetchall()) == 0)

print(f'\ncm-law on-duty count MySQL smoke: {passed} passed, {failed} failed')
sys.exit(0 if failed == 0 else 1)
