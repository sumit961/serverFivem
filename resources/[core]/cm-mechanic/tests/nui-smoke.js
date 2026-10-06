'use strict';
// Headless-browser smoke test for the cm-mechanic NUI (runs against ui/ + the dev mock; no FiveM needed).
//   node resources/[core]/cm-mechanic/tests/nui-smoke.js
// Checks: opens, board, claim, scan, quote, abandon confirmation, ESC semantics, XSS-safe text, no console errors,
// no backdrop-filter / external fonts / CDN, no horizontal scroll, viewport fit.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { spawn } = require('node:child_process');

const uiRoot = path.resolve(__dirname, '..', 'ui');
const repo = path.resolve(__dirname, '..', '..', '..', '..');
const outDir = path.join(repo, 'cm-agent-out', 'qa', 'screenshots', 'cm-mechanic');
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
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cm-mechanic-qa-'));
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

    check(`[${label}] panel opens`, await ev(`__q.wait(() => __q.visible())`));
    check(`[${label}] board lists 2 requests`, await ev(`__q.wait(() => __q.all('.row').length === 2)`));
    const g = await ev(`(() => { const r = document.querySelector('.panel').getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, vw: innerWidth, vh: innerHeight, hs: document.documentElement.scrollWidth > innerWidth, vs: document.documentElement.scrollHeight > innerHeight }; })()`);
    check(`[${label}] panel fits viewport, no overflow`, g.l >= 0 && g.t >= 0 && g.r <= g.vw && g.b <= g.vh && !g.hs && !g.vs, g);
    await shot(`mechanic-board-${label}`);

    if (label === '720p') {
      check('request text rendered as text (XSS-safe)', (await ev(`__q.text('.row .sub')`)).includes('<b>not bold</b>') && (await ev(`document.querySelectorAll('.row .sub b').length`)) === 0);
      await ev(`__q.click('.btn.primary', 'ACCEPT')`);
      check('accepting a request opens the assigned work order', await ev(`__q.wait(() => /Assigned/.test(__q.text('.card .chip') || '') && __q.all('.btn').some((b) => b.textContent === 'SCAN VEHICLE'))`));
      await ev(`__q.click('.btn', 'SCAN VEHICLE')`);
      check('scanning shows diagnosis bars and the service offers', await ev(`__q.wait(() => __q.all('.bar').length === 3 && __q.all('.svc').length === 4)`));
      check('the tuning offer opens a cm-tuning session by category (no repair quote button)', await ev(`(() => { const row = __q.all('.svc').find((r) => r.textContent.includes('Vehicle tuning')); const t = [...row.querySelectorAll('.btn')].map((b) => b.textContent); return t.join('|') === 'PERFORMANCE|BODY & PAINT|LIVERY'; })()`));
      await shot('mechanic-diagnosis');
      await ev(`(() => { const rows = __q.all('.svc'); rows.find((r) => r.textContent.includes('Full workshop')).querySelector('.btn').click(); })()`);
      check('a workshop-only service outside a workshop shows a clear error toast', await ev(`__q.wait(() => /workshop bay/i.test(__q.text('.toast.error') || ''))`));
      await ev(`__q.wait(() => __q.all('.svc .btn').length === 6 && __q.all('.svc .btn').every((b) => !b.disabled))`);
      await ev(`(() => { const rows = __q.all('.svc'); rows.find((r) => r.textContent.includes('Engine and fuel')).querySelector('.btn').click(); })()`);
            check('quote is shown with the server amount and waits for the customer', await ev(`__q.wait(() => __q.text('.big') === '$7,260' && /Quote sent/.test(__q.text('.card .chip') || ''))`));
      await shot('mechanic-quoted');
      await ev(`__q.click('.btn.danger')`);
      check('abandon requires a confirmation naming the vehicle and the consequence', await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal'))`) && (await ev(`__q.text('.cm-confirm-modal__title')`)) === 'CONFIRM ACTION' && /unpaid invoice/i.test(await ev(`__q.text('.cm-confirm-modal__consequence')`)));
      await shot('mechanic-confirm');
      await ev(`__q.esc()`);
      check('ESC cancels the confirmation only (panel stays open, order unchanged)', await ev(`__q.wait(() => !document.querySelector('.cm-confirm-modal')) && __q.visible() && /Quote sent/.test(__q.text('.card .chip'))`));
      await ev(`__q.click('.btn.danger')`);
      await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal'))`);
      await ev(`__q.click('.cm-confirm-modal__confirm')`);
      check('confirmed abandon returns the request to the board', await ev(`__q.wait(() => __q.all('.row').length === 2 && !document.querySelector('.card'))`));
      await ev(`__q.esc()`);
      check('ESC closes the panel when nothing else is open', await ev(`__q.wait(() => !__q.visible())`));
    }
  }

  const css = fs.readFileSync(path.join(uiRoot, 'style.css'), 'utf8');
  const html = fs.readFileSync(path.join(uiRoot, 'index.html'), 'utf8') + fs.readFileSync(path.join(uiRoot, 'app.js'), 'utf8');
  check('no backdrop-filter anywhere in the UI', !/backdrop-filter/i.test(css + html));
  check('no external fonts / CDN / remote assets', !/https?:\/\/(?!127\.0\.0\.1)/i.test(css + fs.readFileSync(path.join(uiRoot, 'index.html'), 'utf8')) && !/@import|fonts\.googleapis|cdn\./i.test(css));
  check('no console errors during the run', consoleErrors.length === 0, consoleErrors.slice(0, 3));

  chrome.kill();
  server.close();
  try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) { /* profile cleanup is best effort */ }
  const failed = results.filter((r) => !r.pass).length;
  console.log(`\ncm-mechanic NUI smoke: ${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
