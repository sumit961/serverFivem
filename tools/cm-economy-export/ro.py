"""Read-only MySQL helper for CM economy audits. Never prints credentials.

Connection comes from server.local.cfg (mysql_connection_string). Refuses any
non-local host and any statement that is not SELECT/SHOW/DESCRIBE.
"""
import re, pathlib, urllib.parse
import pymysql

ROOT = pathlib.Path(__file__).resolve().parents[2]
_ALLOWED = re.compile(r'^\s*(select|show|describe|desc)\b', re.I)
_FORBIDDEN = re.compile(r'\b(insert|update|delete|replace|alter|drop|truncate|create|grant|call|into\s+outfile)\b', re.I)


def connect():
    cfg = (ROOT / 'server.local.cfg').read_text(encoding='utf-8', errors='replace')
    m = re.search(r'mysql_connection_string\s+"([^"]+)"', cfg)
    if not m:
        raise SystemExit('DATABASE EXPORT BLOCKED: no mysql_connection_string in server.local.cfg')
    u = urllib.parse.urlparse(m.group(1))
    if u.hostname not in ('localhost', '127.0.0.1', '::1'):
        raise SystemExit('refusing: DB host is not local')
    conn = pymysql.connect(host=u.hostname, port=u.port or 3306, user=urllib.parse.unquote(u.username or ''),
                           password=urllib.parse.unquote(u.password or ''), database=u.path.lstrip('/'),
                           charset='utf8mb4', cursorclass=pymysql.cursors.DictCursor, autocommit=True)
    with conn.cursor() as c:
        c.execute('SET SESSION TRANSACTION READ ONLY')
    return conn


def q(conn, sql, args=None):
    if not _ALLOWED.match(sql) or _FORBIDDEN.search(re.sub(r"'[^']*'", "''", sql)):
        raise ValueError('read-only helper: statement rejected')
    with conn.cursor() as c:
        c.execute(sql, args)
        return list(c.fetchall())
