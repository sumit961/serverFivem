'use strict';
// Headless-browser smoke test for the shared business staff panel (no FiveM needed; NUI messages are injected).
//   node resources/[core]/cm-commercial-ownership/tests/nui-smoke.js
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { spawn } = require('node:child_process');

const uiRoot = path.resolve(__dirname, '..', 'ui');
const repo = path.resolve(__dirname, '..', '..', '..', '..');
const outDir = path.join(repo, 'cm-agent-out', 'qa', 'screenshots', 'cm-commercial-ownership');
fs.mkdirSync(outDir, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
    s.on('error', reject);
  });
}

function chromePath() {
  return [process.env.CM_QA_BROWSER, 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'].filter(Boolean).find((p) => fs.existsSync(p));
}

function getJson(port, route) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port, path: route }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => { try { resolve(JSON.parse(body)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

(async () => {
  const exe = chromePath();
  if (!exe) { console.log('BLOCKED: no Chrome/Edge found (set CM_QA_BROWSER)'); process.exit(2); }

  const server = http.createServer((req, res) => {
    const name = req.url.split('?')[0].replace(/^\/+/, '') || 'index.html';
    if (name === 'favicon.ico') { res.writeHead(204).end(); return; }
    const file = path.resolve(uiRoot, name);
    if (!file.startsWith(uiRoot + path.sep) || !fs.existsSync(file)) { res.writeHead(404).end(); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}/index.html`;

  const debugPort = await freePort();
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cm-business-qa-'));
  const chrome = spawn(exe, ['--headless=new', `--remote-debugging-port=${debugPort}`, `--user-data-dir=${profile}`, '--no-first-run',
    '--disable-gpu', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });

  let page;
  for (let i = 0; i < 50 && !page; i++) {
    await sleep(200);
    try { page = (await getJson(debugPort, '/json/list')).find((t) => t.type === 'page'); } catch (e) { /* retry */ }
  }
  if (!page) { chrome.kill(); server.close(); console.log('BLOCKED: browser did not start'); process.exit(2); }

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let nextId = 1;
  const waiters = new Map();
  const consoleErrors = [];
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && waiters.has(m.id)) { waiters.get(m.id)(m); waiters.delete(m.id); return; }
    if (m.method === 'Runtime.exceptionThrown') consoleErrors.push(m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text);
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') consoleErrors.push(m.params.args.map((a) => a.value || a.description).join(' '));
    if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') consoleErrors.push(m.params.entry.text + ' ' + (m.params.entry.url || ''));
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextId++;
    waiters.set(id, (m) => (m.error ? reject(new Error(m.error.message)) : resolve(m.result)));
    ws.send(JSON.stringify({ id, method, params }));
  });
  const ev = async (expression) => {
    const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || 'evaluate failed');
    return r.result.value;
  };
  await send('Runtime.enable');
  await send('Log.enable');

  const results = [];
  const check = (name, pass, detail) => { results.push({ name, pass: !!pass, detail }); console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${pass ? '' : '  ' + JSON.stringify(detail)}`); };
  const shot = async (name) => { const s = await send('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(path.join(outDir, name + '.png'), Buffer.from(s.data, 'base64')); };

  await send('Page.enable');
  const DATA = {
    business: { type: 'store', id: '3', label: 'Store #3' }, you: { rank: 'Owner', isOwner: true, characterId: 1 },
    caps: { viewEmployees: true, invite: true, manageEmployees: true, manageRanks: true, managePermissions: true, viewActivity: true, viewFinance: true, payEmployees: true, managePayroll: true, createInvoice: true, manageOrders: true },
    payroll: { enabled: true, min: 100, max: 20000, cooldown: 600 }, balance: 12500, limits: { maxTier: 90, maxRanks: 8 },
    employees: [
      { characterId: 7, name: '<img src=x onerror=alert(1)>', rankId: 2, rank: 'Employee', tier: 40, hiredAt: '2026-10-02 10:00:00', payAmount: 500, canManage: true, canPay: true, isSelf: false },
      { characterId: 9, name: 'Sam Rivers', rankId: 1, rank: 'Manager', tier: 80, hiredAt: '2026-10-01 09:00:00', payAmount: 0, canManage: true, canPay: false, isSelf: false }],
    ranks: [
      { id: 1, name: 'Manager', tier: 80, permissions: ['business.invite', 'business.pay_employees'], payAmount: 0, isEntry: false, employees: 1, canEdit: true },
      { id: 2, name: 'Employee', tier: 40, permissions: ['business.manage_stock'], payAmount: 500, isEntry: true, employees: 1, canEdit: true },
      { id: 3, name: 'Trainee', tier: 10, permissions: [], payAmount: 0, isEntry: false, employees: 0, canEdit: true }],
    assignable: [{ id: 1, name: 'Manager', tier: 80 }, { id: 2, name: 'Employee', tier: 40 }, { id: 3, name: 'Trainee', tier: 10 }],
    permissions: [{ id: 'business.invite', label: 'Invite employees', implemented: true, grantable: true }, { id: 'business.manage_stock', label: 'Manage stock', implemented: false, grantable: true }],
    supply: { supported: true },
    orders: [
      { reference: 'SUP-AAA111', status: 'awaiting_fulfillment', total: 1980, units: 220, itemCount: 2, createdAt: '2026-10-02 10:00:00', canCancel: true },
      { reference: 'SUP-BBB222', status: 'delivered', total: 90, units: 10, itemCount: 1, createdAt: '2026-10-01 09:00:00', canCancel: false }],
    activity: [{ action: 'payroll_paid', actor: 'Owner', target: 'Sam Rivers', amount: 500, at: '2026-10-02 10:30:00' }],
  };
  const setup = `
    window.__posts = [];
    window.fetch = (url, opts) => { window.__posts.push({ url, body: JSON.parse(opts.body) }); return Promise.resolve({}); };
    window.__q = {
      text: (sel) => { const el = document.querySelector(sel); return el ? el.textContent : null; },
      all: (sel) => Array.from(document.querySelectorAll(sel)),
      click: (sel, contains) => { const els = Array.from(document.querySelectorAll(sel)); const el = contains ? els.find((e) => e.textContent.includes(contains)) : els[0]; if (!el) return false; el.click(); return true; },
      esc: () => window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })),
      wait: (fn, ms = 3000) => new Promise((res) => { const t0 = Date.now(); const tick = () => { let v; try { v = fn(); } catch (e) { v = false; } if (v) return res(true); if (Date.now() - t0 > ms) return res(false); setTimeout(tick, 40); }; tick(); }),
      visible: () => !document.getElementById('root').classList.contains('hidden'),
      send: (m) => window.dispatchEvent(new MessageEvent('message', { data: m })),
    };`;

  for (const [w, h, label] of [[1280, 720, '720p'], [1920, 1080, '1080p']]) {
    await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: base });
    await sleep(700);
    await ev(setup);
    await ev(`__q.send({ type: 'open', data: ${JSON.stringify(DATA)} })`);

    check(`[${label}] panel opens`, await ev(`__q.wait(() => __q.visible())`));
    check(`[${label}] title and funds`, (await ev(`__q.text('#title')`)) === 'Store #3' && (await ev(`__q.text('#fundsValue')`)) === '$12,500');
    check(`[${label}] two employees rendered`, (await ev(`__q.all('#view-employees .row.emp').length`)) === 2, consoleErrors);
    check(`[${label}] employee name is text (XSS-safe)`, (await ev(`document.querySelectorAll('#view-employees img').length`)) === 0 && (await ev(`__q.text('#view-employees .name')`)).includes('<img'));
    const g = await ev(`(() => { const r = document.querySelector('.panel').getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, vw: innerWidth, vh: innerHeight, hs: document.documentElement.scrollWidth > innerWidth, vs: document.documentElement.scrollHeight > innerHeight }; })()`);
    check(`[${label}] panel fits viewport, no page overflow`, g.l >= 0 && g.t >= 0 && g.r <= g.vw && g.b <= g.vh && !g.hs && !g.vs, g);
    await shot(`staff-${label}`);

    if (label === '720p') {
      await ev(`__q.click('.tab', 'RANKS')`);
      check('ranks tab lists 3 ranks', await ev(`__q.wait(() => __q.all('#view-ranks .row.rank').length === 3)`));
      await ev(`__q.click('#view-ranks .btn', 'EDIT')`);
      check('rank editor drawer opens with permission grid', await ev(`__q.wait(() => !document.getElementById('drawer').classList.contains('hidden') && __q.all('#drawer input[data-perm]').length === 2)`));
      await shot('staff-rank-editor');
      await ev(`__q.esc()`);
      check('ESC closes the drawer only', await ev(`__q.wait(() => document.getElementById('drawer').classList.contains('hidden')) && __q.visible()`));
      check('rank in use cannot be deleted from the UI', await ev(`(() => { const rows = __q.all('#view-ranks .row.rank'); return rows[0].querySelector('.btn.danger').disabled === true && rows[2].querySelector('.btn.danger').disabled === false; })()`));
      await ev(`__q.click('.tab', 'EMPLOYEES')`);
      await ev(`__q.click('#view-employees .btn.danger', 'REMOVE')`);
      check('removal needs a confirmation, focus on CANCEL', await ev(`__q.wait(() => !document.getElementById('confirm').classList.contains('hidden'))`)
        && (await ev(`document.activeElement && document.activeElement.id`)) === 'confirmCancel');
      await shot('staff-confirm');
      await ev(`__q.esc()`);
      check('ESC cancels the confirmation; nothing was sent', await ev(`__q.wait(() => document.getElementById('confirm').classList.contains('hidden'))`) && (await ev(`window.__posts.length`)) === 0);
      await ev(`__q.click('#view-employees .btn.danger', 'REMOVE')`);
      await ev(`__q.wait(() => !document.getElementById('confirm').classList.contains('hidden'))`);
      await ev(`__q.click('#confirmOk')`);
      const post = await ev(`__q.wait(() => window.__posts.length > 0) ? window.__posts[0] : null`);
      check('confirmed removal posts only action + target character id', post && post.body.action === 'remove' && Object.keys(post.body.payload).join() === 'characterId' && post.body.payload.characterId === 7, post);
      await ev(`__q.send({ type: 'update', data: ${JSON.stringify(DATA)} })`);
      await ev(`__q.esc()`);
      check('ESC closes the panel and notifies the client', await ev(`__q.wait(() => !__q.visible())`) && (await ev(`window.__posts.some((p) => p.url.endsWith('/close'))`)));
      await ev(`__q.send({ type: 'open', data: ${JSON.stringify(DATA)} })`);
      await ev(`__q.click('.tab', 'ACTIVITY')`);
      check('activity tab renders the feed', await ev(`__q.wait(() => /Payroll paid/.test(__q.text('#view-activity') || ''))`));

      // ---- ORDERS (supply) ----
      await ev(`__q.send({ type: 'open', data: ${JSON.stringify(DATA)} })`);
      await ev(`__q.click('.tab', 'ORDERS')`);
      check('orders tab lists active orders with status badges', await ev(`__q.wait(() => __q.all('#view-orders .row.ord').length === 2)`)
        && (await ev(`__q.all('#view-orders .badge').map((b) => b.textContent).join('|')`)) === 'AWAITING CARRIER|DELIVERED');
      check('only an awaiting order offers CANCEL', (await ev(`__q.all('#view-orders .btn.danger').length`)) === 1);
      await shot('staff-orders');
      await ev(`window.__posts.length = 0`);
      await ev(`__q.click('#view-orders .btn', 'DETAILS')`);
      check('details request carries only the reference', await ev(`__q.wait(() => window.__posts.length === 1)`) && JSON.stringify((await ev(`window.__posts[0].body`))) === JSON.stringify({ action: 'supplyDetail', payload: { reference: 'SUP-AAA111' } }));
      await ev(`__q.send({ type: 'supply', kind: 'detail', payload: { reference: 'SUP-AAA111', status: 'awaiting_fulfillment', total: 1980, lines: [{ id: 'water', label: '<b>Water</b>', quantity: 20, unitCost: 9, lineTotal: 180 }], refunded: false } })`);
      check('order detail shows lines (XSS-safe)', await ev(`__q.wait(() => document.querySelectorAll('#drawer .qline').length === 1)`) && (await ev(`document.querySelectorAll('#drawer b').length`)) === 0);
      await ev(`__q.esc()`);
      await ev(`window.__posts.length = 0`);
      await ev(`__q.click('#view-orders .btn', 'NEW ORDER')`);
      check('new order requests the server catalog', await ev(`__q.wait(() => window.__posts.length === 1 && window.__posts[0].body.action === 'supplyCatalog')`));
      await ev(`__q.send({ type: 'supply', kind: 'catalog', payload: { items: [{ id: 'water', label: 'Water Bottle', category: 'consumable', unitCost: 9 }, { id: 'lottery_ticket', label: 'Lottery', category: 'misc', unitCost: 6000 }], maxLine: 100, maxUnits: 200, fulfillment: 'external', capacity: { stock: 100, open: 0, capacity: 500, after: 100, unit: 'units' } } })`);
      check('catalog drawer shows server unit costs and quantity inputs', await ev(`__q.wait(() => __q.all('#drawer input[type=number]').length === 2)`) && (await ev(`__q.text('#drawer')`)).includes('$6,000'));
      await shot('staff-order-catalog');
      await ev(`window.__posts.length = 0`);
      await ev(`(() => { const i = __q.all('#drawer input[type=number]'); i[0].value = '12'; i[1].value = '0'; })()`);
      await ev(`__q.click('#drawer .btn', 'GET QUOTE')`);
      const qpost = await ev(`__q.wait(() => window.__posts.length === 1) ? window.__posts[0].body : null`);
      check('quote request sends only item ids and quantities (no prices)', qpost && qpost.action === 'supplyQuote' && JSON.stringify(qpost.payload) === JSON.stringify({ lines: [{ id: 'water', qty: 12 }] }), qpost);
      await ev(`__q.send({ type: 'supply', kind: 'quote', payload: { token: 'tok-1', expiresIn: 120, lines: [{ id: 'water', label: 'Water Bottle', qty: 12, unitCost: 9, lineTotal: 108 }], units: 12, subtotal: 108, fee: 0, total: 108, capacity: { stock: 100, open: 0, capacity: 500, after: 112, unit: 'units' }, affordable: true } })`);
      check('quote drawer shows the authoritative total', await ev(`__q.wait(() => (__q.text('#drawer') || '').includes('TOTAL $108'))`));
      await shot('staff-order-quote');
      await ev(`window.__posts.length = 0`);
      await ev(`__q.click('#drawer .btn', 'CONFIRM ORDER')`);
      check('placing an order needs a confirmation naming the total', await ev(`__q.wait(() => !document.getElementById('confirm').classList.contains('hidden'))`) && (await ev(`__q.text('#confirmMessage')`)).includes('$108') && (await ev(`window.__posts.length`)) === 0);
      await ev(`__q.click('#confirmOk')`);
      const ppost = await ev(`__q.wait(() => window.__posts.length === 1) ? window.__posts[0].body : null`);
      check('place request carries only the quote token', ppost && ppost.action === 'supplyPlace' && JSON.stringify(ppost.payload) === JSON.stringify({ token: 'tok-1' }), ppost);
      await ev(`__q.send({ type: 'result', result: { ok: true, message: 'Order placed' } })`);
      await ev(`window.__posts.length = 0`);
      await ev(`__q.click('#view-orders .btn.danger', 'CANCEL')`);
      await ev(`__q.wait(() => !document.getElementById('confirm').classList.contains('hidden'))`);
      check('cancel needs confirmation and mentions the one-time refund', (await ev(`__q.text('#confirmConsequence')`)).includes('refunded'));
      await ev(`__q.click('#confirmOk')`);
      const cpost = await ev(`__q.wait(() => window.__posts.length === 1) ? window.__posts[0].body : null`);
      check('cancel request carries only the reference', cpost && cpost.action === 'supplyCancel' && JSON.stringify(cpost.payload) === JSON.stringify({ reference: 'SUP-AAA111' }), cpost);
      const noPerm = JSON.parse(JSON.stringify(DATA)); noPerm.caps.manageOrders = false; delete noPerm.orders; delete noPerm.supply;
      await ev(`__q.send({ type: 'update', data: ${JSON.stringify(noPerm)} })`);
      check('orders tab is hidden without the permission', await ev(`__q.wait(() => document.querySelector('.tab[data-tab="orders"]').classList.contains('hidden'))`));
      await ev(`__q.esc()`);
      await ev(`__q.send({ type: 'invite', invite: { token: 't1', label: 'Store #3', rankName: 'Employee', expiresIn: 60 } })`);
      check('invite prompt shows', await ev(`__q.wait(() => !document.getElementById('invite').classList.contains('hidden'))`));
      await ev(`__q.esc()`);
      check('ESC declines the invitation through the callback', await ev(`__q.wait(() => window.__posts.some((p) => p.url.endsWith('/respondInvite') && p.body.accept === false && p.body.token === 't1'))`));
    }
  }

  const css = fs.readFileSync(path.join(uiRoot, 'style.css'), 'utf8') + fs.readFileSync(path.join(uiRoot, 'index.html'), 'utf8') + fs.readFileSync(path.join(uiRoot, 'app.js'), 'utf8');
  check('no backdrop-filter anywhere in the UI', !/backdrop-filter/i.test(css));
  check('no external URLs (CDN/fonts)', !/https?:\/\/(?!127\.0\.0\.1|\$\{RES\})/.test(css));
  check('no console errors', consoleErrors.length === 0, consoleErrors);

  ws.close(); chrome.kill(); server.close();
  const failed = results.filter((r) => !r.pass).length;
  console.log(`${failed ? 'RESULT FAIL' : 'RESULT PASS'}: ${results.length} checks, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('ERROR', e && e.stack || e); process.exit(1); });
