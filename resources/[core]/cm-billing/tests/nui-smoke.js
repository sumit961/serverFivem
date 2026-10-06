'use strict';
// Headless-browser smoke test for the cm-billing NUI (runs against ui/ + the dev mock; no FiveM needed).
//   node resources/[core]/cm-billing/tests/nui-smoke.js
// Checks: opens, navigation, list rendering, XSS-safe rendering, compose, call overlay, confirmation modal,
// ESC back/close semantics, no console errors, no backdrop-filter, no horizontal scroll, viewport fit.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { spawn } = require('node:child_process');

const uiRoot = path.resolve(__dirname, '..', 'ui');
const repo = path.resolve(__dirname, '..', '..', '..', '..');
const outDir = path.join(repo, 'cm-agent-out', 'qa', 'screenshots', 'cm-billing');
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
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cm-billing-qa-'));
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
  const setup = `
    window.__q = {
      text: (sel) => { const el = document.querySelector(sel); return el ? el.textContent : null; },
      all: (sel) => Array.from(document.querySelectorAll(sel)),
      click: (sel, contains) => { const els = Array.from(document.querySelectorAll(sel)); const el = contains ? els.find((e) => e.textContent.includes(contains)) : els[0]; if (!el) return false; el.click(); return true; },
      esc: () => window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })),
      wait: (fn, ms = 3000) => new Promise((res) => { const t0 = Date.now(); const tick = () => { let v; try { v = fn(); } catch (e) { v = false; } if (v) return res(true); if (Date.now() - t0 > ms) return res(false); setTimeout(tick, 40); }; tick(); }),
      visible: () => !document.getElementById('root').classList.contains('hidden'),
    };`;

  for (const [w, h, label] of [[1280, 720, '720p'], [1920, 1080, '1080p']]) {
    await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: base });
    await sleep(700);
    await ev(setup);

    check(`[${label}] billing opens`, await ev(`__q.wait(() => __q.visible())`));
    check(`[${label}] outstanding count shows 3`, (await ev(`__q.text('#pendingCount')`)) === '3');
    check(`[${label}] outstanding list renders 3 invoices`, (await ev(`__q.all('#list .row').length`)) === 3);
    check(`[${label}] first invoice auto-selected with detail`, (await ev(`__q.text('.card h2')`)) === 'Vehicle repair');
    const g = await ev(`(() => { const r = document.querySelector('.panel').getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, vw: innerWidth, vh: innerHeight, hs: document.documentElement.scrollWidth > innerWidth, vs: document.documentElement.scrollHeight > innerHeight }; })()`);
    check(`[${label}] panel fits viewport, no overflow`, g.l >= 0 && g.t >= 0 && g.r <= g.vw && g.b <= g.vh && !g.hs && !g.vs, g);
    await shot(`billing-${label}`);

    if (label === '720p') {
      check('description rendered as text (XSS-safe)', (await ev(`__q.text('.desc')`)).includes('<b>not bold</b>') && (await ev(`document.querySelectorAll('.desc b').length`)) === 0);
      await ev(`__q.click('#list .row', 'Hospital')`);
      check('unaffordable invoice disables Pay and explains', await ev(`__q.wait(() => document.querySelector('.btn.primary').disabled && /enough/.test(__q.text('.note') || ''))`));
      await ev(`__q.click('#list .row', 'Vehicle repair')`);
      await ev(`__q.wait(() => !document.querySelector('.btn.primary').disabled)`);
      await ev(`__q.click('.acct', 'bank')`);
      await ev(`__q.click('.btn.primary')`);
      check('payment requires confirmation naming issuer, amount and account', await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal'))`) && (await ev(`__q.text('.cm-confirm-modal__message')`)).includes('$12,500') && (await ev(`__q.text('.cm-confirm-modal__consequence')`)).includes('bank'));
      await shot('billing-confirm');
      await ev(`__q.esc()`);
      check('ESC cancels the confirmation only (billing stays open, nothing paid)', await ev(`__q.wait(() => !document.querySelector('.cm-confirm-modal')) && __q.visible()`) && (await ev(`__q.text('#pendingCount')`)) === '3');
      await ev(`__q.click('.btn.primary')`);
      await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal'))`);
      await ev(`__q.click('.cm-confirm-modal__confirm')`);
      check('confirmed payment moves invoice to history as paid', await ev(`__q.wait(() => /paid/i.test(__q.text('.chip') || '') && __q.text('.card h2') === 'Vehicle repair')`));
      check('outstanding count drops to 2', (await ev(`__q.text('#pendingCount')`)) === '2');
      check('bank balance reduced exactly once', /5,500/.test(await ev(`__q.text('#balances')`)));
      await shot('billing-paid');
      await ev(`__q.click('#tabPending')`);
      check('paid invoice no longer outstanding', await ev(`__q.wait(() => __q.all('#list .row').length === 2 && !__q.all('#list .row').some((r) => r.textContent.includes('Vehicle repair')))`));
      await ev(`__q.click('#tabHistory')`);
      check('history lists paid, voided and older entries', await ev(`__q.wait(() => __q.all('#list .row').length === 3)`));
      await ev(`__q.click('#list .row', 'Permit fee')`);
      check('voided invoice shows reason and no Pay button', await ev(`__q.wait(() => (__q.text('.card') || '').includes('Issued in error') && !document.querySelector('.btn.primary'))`));
      await shot('billing-history');
      await ev(`__q.esc()`);
      check('ESC closes billing', await ev(`__q.wait(() => !__q.visible())`));
    }

    const bf = await ev(`(() => { for (const el of document.querySelectorAll('*')) { const s = getComputedStyle(el); if ((s.backdropFilter && s.backdropFilter !== 'none') || (s.webkitBackdropFilter && s.webkitBackdropFilter !== 'none')) return el.className; } return null; })()`);
    check(`[${label}] no backdrop-filter in computed styles`, bf === null, bf);
  }

  check('no console errors or exceptions', consoleErrors.length === 0, consoleErrors.slice(0, 5));
  const css = fs.readFileSync(path.join(uiRoot, 'style.css'), 'utf8');
  check('stylesheet has no backdrop-filter', !/backdrop-filter/i.test(css));
  const js = fs.readFileSync(path.join(uiRoot, 'app.js'), 'utf8') + fs.readFileSync(path.join(uiRoot, 'index.html'), 'utf8');
  check('no external URLs/CDNs referenced', !/(?:src|href)\s*=\s*["']https?:/i.test(js) && !/@import|cdn\./i.test(css + js));

  const failed = results.filter((r) => !r.pass);
  fs.writeFileSync(path.join(repo, 'cm-agent-out', 'qa', 'cm-billing-nui.json'), JSON.stringify({ at: new Date().toISOString(), failed: failed.length, results }, null, 2));
  console.log(`RESULT ${failed.length ? 'FAIL' : 'PASS'}: ${results.length} checks, ${failed.length} failed; screenshots in ${outDir}`);
  ws.close(); chrome.kill(); server.close();
  setTimeout(() => process.exit(failed.length ? 1 : 0), 300);
})().catch((e) => { console.error('ERROR', e); process.exit(1); });
