'use strict';
// Headless-browser smoke test for the cm-phone NUI (runs against ui/ + the dev mock; no FiveM needed).
//   node resources/[core]/cm-phone/tests/nui-smoke.js
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
const outDir = path.join(repo, 'cm-agent-out', 'qa', 'screenshots', 'cm-phone');
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
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cm-phone-qa-'));
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

  // Helpers evaluated in the page.
  await send('Page.enable');
  const setup = `
    window.__q = {
      text: (sel) => { const el = document.querySelector(sel); return el ? el.textContent : null; },
      all: (sel) => Array.from(document.querySelectorAll(sel)),
      click: (sel, contains) => { const els = Array.from(document.querySelectorAll(sel)); const el = contains ? els.find((e) => e.textContent.includes(contains)) : els[0]; if (!el) return false; el.click(); return true; },
      esc: () => window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })),
      wait: (fn, ms = 3000) => new Promise((res) => { const t0 = Date.now(); const tick = () => { let v; try { v = fn(); } catch (e) { v = false; } if (v) return res(true); if (Date.now() - t0 > ms) return res(false); setTimeout(tick, 40); }; tick(); }),
      type: (sel, value) => { const el = document.querySelector(sel); el.value = value; el.dispatchEvent(new Event('input', { bubbles: true })); },
      enter: (sel) => document.querySelector(sel).dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })),
      visible: () => !document.getElementById('root').classList.contains('hidden'),
      header: () => { const h = document.querySelector('.app-header h1'); return h ? h.childNodes[0].textContent : null; },
    };`;

  for (const [w, h, label] of [[1280, 720, '720p'], [1920, 1080, '1080p']]) {
    await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: base });
    await sleep(700);
    await ev(setup);

    check(`[${label}] phone opens via harness`, await ev(`__q.wait(() => __q.visible())`));
    check(`[${label}] home shows 7 apps`, (await ev(`__q.all('.app-tile').length`)) === 7);
    check(`[${label}] messages badge shows unread`, (await ev(`__q.text('.app-tile .badge')`)) === '2');
    const geometry = await ev(`(() => { const r = document.getElementById('phone').getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, vw: innerWidth, vh: innerHeight, hs: document.documentElement.scrollWidth > innerWidth }; })()`);
    check(`[${label}] phone fits viewport, no horizontal scroll`, geometry.l >= 0 && geometry.t >= 0 && geometry.r <= geometry.vw && geometry.b <= geometry.vh && !geometry.hs, geometry);
    await shot(`home-${label}`);

    // ---- Services app (both resolutions) ----
    await ev(`__q.click('.app-tile', 'Services')`);
    check(`[${label}] services list renders 3 cards`, await ev(`__q.wait(() => __q.all('.svc').length === 3)`));
    check(`[${label}] taxi shows Available, mechanic Coming soon, courier Unavailable`, await ev(`(() => { const t = (id) => (document.querySelector('.svc[data-service="' + id + '"] .pill') || {}).textContent; return t('taxi') === 'Available' && t('mechanic') === 'Coming soon' && t('courier') === 'Unavailable'; })()`));
    check(`[${label}] services layout has no horizontal overflow`, await ev(`(() => { const sc = document.querySelector('.screen'); return sc.scrollWidth <= sc.clientWidth + 1 && document.documentElement.scrollWidth <= innerWidth; })()`));
    await shot(`services-${label}`);
    await ev(`__q.click('.svc[data-service="courier"]')`);
    check(`[${label}] unavailable service does not open a form`, await ev(`__q.wait(() => !!document.querySelector('.toast')) && __q.header() === 'Services'`));
    await ev(`__q.click('.home-bar')`);

    if (label === '720p') {
      // Navigation + messages
      await ev(`__q.click('.app-tile', 'Messages')`);
      check('messages list renders conversations', await ev(`__q.wait(() => __q.all('.row').length === 2)`));
      await shot('messages');
      await ev(`__q.click('.row')`);
      check('conversation opens with bubbles', await ev(`__q.wait(() => __q.all('.bubble').length >= 4)`));
      check('message HTML is rendered as text (XSS-safe)', (await ev(`__q.text('.bubble')`)).includes('<b>there</b>') && (await ev(`document.querySelectorAll('.bubble b').length`)) === 0);
      check('location bubble offers Set GPS', await ev(`__q.all('.bubble.loc button').length === 1`));
      await ev(`__q.type('.composer input', 'On my way')`);
      await ev(`__q.enter('.composer input')`);
      check('composed message appears as outgoing bubble', await ev(`__q.wait(() => __q.all('.bubble.out').some((b) => b.textContent.includes('On my way')))`));
      await shot('conversation');
      await ev(`__q.esc()`);
      check('ESC from thread returns to messages (not close)', (await ev(`__q.visible() && __q.header()`)) === 'Messages');
      await ev(`__q.esc()`);
      check('ESC returns to home', await ev(`__q.wait(() => !!document.querySelector('.home-time'))`));
      await ev(`__q.esc()`);
      check('ESC on home closes the phone', await ev(`__q.wait(() => !__q.visible())`));
      await send('Page.navigate', { url: base });
      await sleep(700);
      await ev(setup);
      await ev(`__q.wait(() => __q.visible())`);

      // Contacts form validation + save
      await ev(`__q.click('.app-tile', 'Contacts')`);
      await ev(`__q.wait(() => __q.all('.row').length >= 2)`);
      await ev(`__q.click('.icon-btn', '')`.replace("'.icon-btn', ''", "'.app-header .icon-btn.accent'"));
      await ev(`__q.wait(() => !!document.querySelector('.field input'))`);
      await ev(`__q.type('.field input', 'Test')`);
      await ev(`__q.click('.btn.primary')`);
      check('contact form rejects an invalid number', await ev(`__q.wait(() => __q.text('.err') && __q.text('.err').length > 0)`));
      await ev(`(() => { const inputs = document.querySelectorAll('.field input'); inputs[1].value = '3105559999'; inputs[1].dispatchEvent(new Event('input', { bubbles: true })); })()`);
      await ev(`__q.click('.btn.primary')`);
      check('contact saves and list updates', await ev(`__q.wait(() => __q.all('.row').length >= 3)`));
      await ev(`__q.click('.home-bar')`);

      // Dial + call overlay
      await ev(`__q.click('.app-tile', 'Phone')`);
      await ev(`__q.wait(() => !!document.querySelector('.dial-input'))`);
      await ev(`__q.type('.dial-input', '3235551')`);
      await ev(`document.querySelector('.dial-input').value`);
      await ev(`__q.type('.dial-input', '3235551234')`);
      check('dial input formats as AAA-BBBB', (await ev(`document.querySelector('.dial-input').value`)) === '323-5551');
      await ev(`__q.click('.call-btn')`);
      check('call overlay shows ringing/dialing', await ev(`__q.wait(() => !!document.querySelector('.call-screen'))`));
      check('call becomes connected', await ev(`__q.wait(() => /Connected/.test(__q.text('.call-screen .state') || ''), 4000)`));
      await shot('call-active');
      await ev(`__q.click('.call-screen .round')`);
      check('hang up removes the call overlay', await ev(`__q.wait(() => !document.querySelector('.call-screen'))`));
      await ev(`window.__cmPhoneMockIncoming()`);
      check('incoming call offers Answer and Decline', await ev(`__q.wait(() => __q.all('.call-screen .round').length === 2)`));
      await shot('call-incoming');
      await ev(`__q.click('.call-screen .round.red')`);
      check('decline clears incoming call', await ev(`__q.wait(() => !document.querySelector('.call-screen'))`));
      await ev(`__q.click('.home-bar')`);

      // Adverts confirmation (fee) + ESC cancels modal
      await ev(`__q.click('.app-tile', 'Ads')`);
      await ev(`__q.wait(() => !!document.querySelector('.ad'))`);
      await ev(`__q.click('.app-header .icon-btn.accent')`);
      await ev(`__q.wait(() => !!document.querySelector('textarea'))`);
      await ev(`__q.type('textarea', 'Selling a bicycle, call me!')`);
      await ev(`__q.click('.btn.primary')`);
      check('advert post requires a fee confirmation', await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal'))`));
      check('confirmation states the fee', (await ev(`__q.text('.cm-confirm-modal__consequence')`) || '').includes('1,500'));
      await shot('advert-confirm');
      await ev(`__q.esc()`);
      check('ESC cancels the confirmation only', await ev(`__q.wait(() => !document.querySelector('.cm-confirm-modal')) && __q.visible()`));
      await ev(`__q.click('.home-bar')`);


      // ---- Services flow (720p): request, status states, push, cancel, fallback, ESC/back ----
      await ev(`__q.click('.app-tile', 'Services')`);
      await ev(`__q.wait(() => __q.all('.svc').length === 3)`);
      await ev(`__q.click('.svc[data-service="taxi"]')`);
      check('taxi request form shows service-defined fields only', await ev(`__q.wait(() => __q.all('.field').length === 2 && __q.header() === 'Taxi')`));
      await ev(`__q.type('textarea', '<img src=x onerror=alert(1)> Airport')`);
      await ev(`__q.click('.btn.primary')`);
      check('request requires a confirmation that states location sharing', await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal'))`) && (await ev(`__q.text('.cm-confirm-modal__consequence')`) || '').includes('location'));
      await shot('service-confirm');
      await ev(`__q.esc()`);
      check('ESC cancels only the confirmation', await ev(`__q.wait(() => !document.querySelector('.cm-confirm-modal')) && __q.header() === 'Taxi'`));
      await ev(`__q.click('.btn.primary')`);
      await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal'))`);
      await ev(`__q.click('.cm-confirm-modal__confirm')`);
      check('WAITING state shown after request', await ev(`__q.wait(() => (__q.text('.svc-status .big') || '') === 'Looking for a worker' && !!document.querySelector('.svc-status.wait'))`));
      check('user text was sent as data and never rendered as HTML', await ev(`document.querySelectorAll('img').length === 0 && (window.__cmPhoneMockLastServiceRequest.fields.details || '').includes('<img')`));
      await shot('service-waiting');
      await ev(`window.__cmPhoneMockSetService('assigned', { workerLabel: 'Driver assigned', etaSeconds: 240 })`);
      check('ASSIGNED state pushed (green) with worker label and ETA', await ev(`__q.wait(() => !!document.querySelector('.svc-status.good') && (__q.text('.svc-status .big') || '') === 'Worker assigned' && /Driver assigned/.test(__q.text('.svc-status') || '') && /4 min/.test(__q.text('.svc-status') || ''))`));
      await shot('service-assigned');
      await ev(`window.__cmPhoneMockSetService('active')`);
      check('ACTIVE state (cyan), no cancel offered once service is in progress', await ev(`__q.wait(() => !!document.querySelector('.svc-status.active') && __q.all('.btn.danger').length === 0)`));
      await ev(`window.__cmPhoneMockSetService('assigned')`);
      await ev(`__q.wait(() => __q.all('.btn.danger').length === 1)`);
      await ev(`__q.click('.btn.danger')`);
      check('cancel needs a danger confirmation', await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal.danger'))`));
      await ev(`__q.esc()`);
      await ev(`__q.wait(() => !document.querySelector('.cm-confirm-modal'))`);
      await ev(`__q.click('.btn.danger')`);
      await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal.danger'))`);
      await ev(`__q.click('.cm-confirm-modal__confirm')`);
      check('CANCELLED state (red) after confirmed cancel', await ev(`__q.wait(() => (__q.text('.svc-status .big') || '') === 'Cancelled' && !!document.querySelector('.svc-status.bad') && __q.all('.field').length === 2)`));
      await shot('service-cancelled');
      await ev(`window.__cmPhoneMockSetService('completed')`);
      check('COMPLETED state (green) shown', await ev(`__q.wait(() => (__q.text('.svc-status .big') || '') === 'Completed' && !!document.querySelector('.svc-status.good'))`));
      await ev(`window.__cmPhoneMockSetService('fallback_completed')`);
      check('FALLBACK completion is shown as an automatic completion (no internal state name)', await ev(`__q.wait(() => (__q.text('.svc-status .big') || '') === 'Completed automatically' && !/fallback/i.test(document.getElementById('screen').textContent))`));
      await shot('service-fallback');
      check('no internal fields rendered', await ev(`!/claimed|claim_expires|character/i.test(document.getElementById('screen').textContent)`));
      await ev(`__q.esc()`);
      check('ESC returns to the services list (not close)', await ev(`__q.visible() && __q.wait(() => __q.header() === 'Services')`));
      await ev(`__q.esc()`);
      check('ESC returns home', await ev(`__q.wait(() => !!document.querySelector('.home-time'))`));
      await ev(`__q.click('.app-tile', 'Services')`);
      await ev(`__q.wait(() => __q.all('.svc').length === 3)`);
      await ev(`__q.click('.app-header .icon-btn')`);
      check('back button returns home from services', await ev(`__q.wait(() => !!document.querySelector('.home-time'))`));
      await ev(`__q.click('.app-tile', 'Services')`);
      await ev(`__q.wait(() => __q.all('.svc').length === 3)`);
      await ev(`__q.click('.svc[data-service="taxi"]')`);
      await ev(`__q.wait(() => __q.all('.field').length === 2)`);
      await ev(`__q.type('textarea', 'FAIL')`);
      await ev(`__q.click('.btn.primary')`);
      await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal'))`);
      await ev(`__q.click('.cm-confirm-modal__confirm')`);
      check('source failure shows an error toast, no fake success', await ev(`__q.wait(() => (__q.all('.toast.error').some((t) => /could not take your request/i.test(t.textContent))))`) && await ev(`__q.all('.field').length === 2`));
      await ev(`__q.click('.home-bar')`);

      // Emergency
      await ev(`__q.click('.app-tile', 'Emergency')`);
      await ev(`__q.wait(() => __q.all('.emg-card').length === 2)`);
      await ev(`__q.click('.emg-card.ems .btn.danger')`);
      check('emergency request requires confirmation', await ev(`__q.wait(() => !!document.querySelector('.cm-confirm-modal.danger'))`));
      await shot('emergency-confirm');
      await ev(`__q.esc()`);
    }

    // Global hygiene
    const bf = await ev(`(() => { for (const el of document.querySelectorAll('*')) { const s = getComputedStyle(el); if ((s.backdropFilter && s.backdropFilter !== 'none') || (s.webkitBackdropFilter && s.webkitBackdropFilter !== 'none')) return el.className; } return null; })()`);
    check(`[${label}] no backdrop-filter in computed styles`, bf === null, bf);
  }

  check('no console errors or exceptions', consoleErrors.length === 0, consoleErrors.slice(0, 5));
  const css = fs.readFileSync(path.join(uiRoot, 'style.css'), 'utf8');
  check('stylesheet has no backdrop-filter', !/backdrop-filter/i.test(css));
  const js = fs.readFileSync(path.join(uiRoot, 'app.js'), 'utf8') + fs.readFileSync(path.join(uiRoot, 'index.html'), 'utf8');
  check('no external URLs/CDNs referenced', !/(?:src|href)\s*=\s*["']https?:/i.test(js) && !/@import|cdn\./i.test(css + js));

  const failed = results.filter((r) => !r.pass);
  fs.writeFileSync(path.join(repo, 'cm-agent-out', 'qa', 'cm-phone-nui.json'), JSON.stringify({ at: new Date().toISOString(), failed: failed.length, results }, null, 2));
  console.log(`RESULT ${failed.length ? 'FAIL' : 'PASS'}: ${results.length} checks, ${failed.length} failed; screenshots in ${outDir}`);
  ws.close(); chrome.kill(); server.close();
  setTimeout(() => process.exit(failed.length ? 1 : 0), 300);
})().catch((e) => { console.error('ERROR', e); process.exit(1); });
