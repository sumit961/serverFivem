'use strict';
// Headless-browser smoke test for the trade window (no FiveM needed; NUI messages are injected).
//   node resources/[core]/cm-trade/tests/nui-smoke.js
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { spawn } = require('node:child_process');

const uiRoot = path.resolve(__dirname, '..', 'ui');
const repo = path.resolve(__dirname, '..', '..', '..', '..');
const outDir = path.join(repo, 'cm-agent-out', 'qa', 'screenshots', 'cm-trade');
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
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cm-trade-qa-'));
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
  const view = (state, over) => Object.assign({
    id: 'TRD-AAAA1111', state, rev: 3, wallet: 12000, caps: { items: true, maxCash: 1000000, maxLines: 8, maxQuantity: 100 },
    you: { offer: { cash: 500, items: [{ ref: 'a1', label: '<b>Water</b>', quantity: 3, summary: 'Serial SN-1' }] }, confirmed: false },
    other: { label: 'Stranger #77', offer: { cash: 0, items: [] }, confirmed: false },
  }, over || {});
  const J = (o) => JSON.stringify(o);
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
      hidden: (id) => document.getElementById(id).classList.contains('hidden'),
      send: (m) => window.dispatchEvent(new MessageEvent('message', { data: m })),
    };`;

  for (const [w, h, label] of [[1280, 720, '720p'], [1920, 1080, '1080p']]) {
    await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: base });
    await sleep(700);
    await ev(setup);
    await ev(`__q.send({ type: 'open', view: ${J(view('open'))} })`);
    await ev(`__q.send({ type: 'inventory', list: [{ ref: 'a1', label: 'Water Bottle', quantity: 10 }, { ref: 'a2', label: 'Advanced Lockpick', quantity: 1, summary: 'Serial SN-77' }] })`);
    check(`[${label}] trade window opens with the other party's safe label`, await ev(`__q.wait(() => __q.visible())`) && (await ev(`__q.text('#title')`)) === 'Trade with Stranger #77');
    check(`[${label}] two-sided view`, (await ev(`__q.text('#colYou')`)).includes('Your offer') && (await ev(`__q.text('#colOther')`)).includes('Stranger #77 offers'));
    const g = await ev(`(() => { const r = document.querySelector('.panel').getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, vw: innerWidth, vh: innerHeight, hs: document.documentElement.scrollWidth > innerWidth, vs: document.documentElement.scrollHeight > innerHeight }; })()`);
    check(`[${label}] fits viewport, no overflow`, g.l >= 0 && g.t >= 0 && g.r <= g.vw && g.b <= g.vh && !g.hs && !g.vs, g);
    await shot(`trade-${label}`);

    if (label === '720p') {
      check('item label is rendered as text (unsafe HTML inert)', (await ev(`document.querySelectorAll('#colYou .item b').length`)) === 0 && (await ev(`__q.text('#colYou .item')`)).includes('<b>Water</b>'));
      check('cash input shows the server value', (await ev(`document.querySelector('#colYou .cash input').value`)) === '500');
      await ev(`(() => { const i = document.querySelector('#colYou .cash input'); i.value = '750'; i.dispatchEvent(new Event('change')); })()`);
      const cashPost = await ev(`__q.wait(() => window.__posts.length === 1) ? window.__posts[0].body : null`);
      check('cash edit posts op + amount only', cashPost && J(cashPost) === J({ op: 'cash', a: 750 }), cashPost);
      await ev(`window.__posts.length = 0`);
      await ev(`__q.click('#colYou .btn', 'ADD ITEM')`);
      check('item picker lists the safe inventory snapshot', await ev(`__q.wait(() => !__q.hidden('drawer') && __q.all('#drawer .pick').length === 2)`));
      await shot('trade-picker');
      await ev(`(() => { const rows = __q.all('#drawer .pick'); rows[1].querySelector('input').value = '1'; rows[1].querySelector('button').click(); })()`);
      const addPost = await ev(`__q.wait(() => window.__posts.length === 1) ? window.__posts[0].body : null`);
      check('add item posts only the opaque ref and quantity', addPost && J(addPost) === J({ op: 'addItem', a: 'a2', b: 1 }), addPost);
      await ev(`window.__posts.length = 0`);
      await ev(`(() => { __q.click('#colYou .btn', 'ADD ITEM'); const rows = __q.all('#drawer .pick'); rows[0].querySelector('input').value = '2'; rows[0].querySelector('button').click(); })()`);
      const qtyPost = await ev(`__q.wait(() => window.__posts.length === 1) ? window.__posts[0].body : null`);
      check('quantity edit (update line) posts the new quantity', qtyPost && J(qtyPost) === J({ op: 'addItem', a: 'a1', b: 2 }), qtyPost);
      await ev(`window.__posts.length = 0`);
      await ev(`__q.click('#colYou .item .btn', 'REMOVE')`);
      check('remove item posts the ref', await ev(`__q.wait(() => window.__posts.length === 1)`) && J(await ev(`window.__posts[0].body`)) === J({ op: 'removeItem', a: 'a1' }));
      await ev(`window.__posts.length = 0`);

      await ev(`__q.click('#confirmBtn')`);
      check('confirm shows both sides and needs a second click', await ev(`__q.wait(() => !__q.hidden('confirm'))`) && (await ev(`__q.text('#confirmMessage')`)).includes('You give') && (await ev(`__q.text('#confirmMessage')`)).includes('$500') && (await ev(`window.__posts.length`)) === 0);
      await shot('trade-confirm');
      await ev(`__q.esc()`);
      check('ESC cancels the confirm dialog only', await ev(`__q.wait(() => __q.hidden('confirm'))`) && (await ev(`__q.visible()`)) && (await ev(`window.__posts.length`)) === 0);
      await ev(`__q.click('#confirmBtn')`);
      await ev(`__q.click('#confirmOk')`);
      check('confirm posts only the revision the player saw', await ev(`__q.wait(() => window.__posts.length === 1)`) && J(await ev(`window.__posts[0].body`)) === J({ rev: 3 }));
      await ev(`__q.send({ type: 'state', view: ${J(view('open', { you: { offer: { cash: 500, items: [] }, confirmed: true } }))} })`);
      check('state: you confirmed', (await ev(`__q.text('#stateChip')`)) === 'YOU CONFIRMED' && await ev(`document.getElementById('confirmBtn').disabled`) && (await ev(`__q.text('#confirmBtn')`)) === 'WAITING FOR THEM');
      await ev(`__q.send({ type: 'state', view: ${J(view('open', { rev: 4 }))} })`);
      check('offer mutation: server reset shows both unconfirmed again', (await ev(`__q.text('#stateChip')`)) === 'EDITING' && !(await ev(`document.getElementById('confirmBtn').disabled`)));
      await ev(`__q.send({ type: 'state', view: ${J(view('open', { other: { label: 'Stranger #77', offer: { cash: 100, items: [] }, confirmed: true } }))} })`);
      check('state: other player confirmed', (await ev(`__q.text('#stateChip')`)) === 'THEY CONFIRMED');
      await ev(`__q.send({ type: 'state', view: ${J(view('committing', { you: { offer: { cash: 500, items: [] }, confirmed: true }, other: { label: 'Stranger #77', offer: { cash: 0, items: [] }, confirmed: true } }))} })`);
      check('state: committing locks the window', (await ev(`__q.text('#stateChip')`)) === 'COMMITTING' && !(await ev(`__q.hidden('overlay')`)) && await ev(`document.getElementById('cancelBtn').disabled`) && await ev(`document.querySelector('#colYou .cash input').disabled`));
      await shot('trade-committing');
      await ev(`__q.send({ type: 'ended', info: { id: 'TRD-AAAA1111', outcome: 'completed', message: 'Trade complete.' } })`);
      check('state: completed', (await ev(`__q.text('#overlayText')`)) === 'Trade complete.' && (await ev(`__q.text('#stateChip')`)) === 'COMPLETED');
      await ev(`window.__posts.length = 0`);
      await ev(`__q.esc()`);
      check('ESC after completion only force-closes the UI', await ev(`__q.wait(() => window.__posts.some((p) => p.url.endsWith('/forceClose')))`));
      await ev(`__q.send({ type: 'close' })`);

      await ev(`__q.send({ type: 'open', view: ${J(view('open'))} })`);
      await ev(`window.__posts.length = 0`);
      await ev(`__q.esc()`);
      check('ESC while editing requests a safe cancel from the server', await ev(`__q.wait(() => window.__posts.some((p) => p.url.endsWith('/close')))`));
      await ev(`__q.send({ type: 'ended', info: { id: 'TRD-AAAA1111', outcome: 'cancelled', message: 'You moved apart.' } })`);
      check('state: cancelled shows the reason', (await ev(`__q.text('#overlayText')`)) === 'You moved apart.' && (await ev(`__q.text('#stateChip')`)) === 'CANCELLED');
      await ev(`__q.send({ type: 'close' })`);

      await ev(`__q.send({ type: 'open', view: ${J(view('open', { caps: { items: false, maxCash: 1000000, maxLines: 8, maxQuantity: 100 }, you: { offer: { cash: 0, items: [] }, confirmed: false } }))} })`);
      check('items disabled: no ADD ITEM button and a clear note', (await ev(`__q.all('#colYou .btn').length`)) === 0 && (await ev(`__q.text('#colYou')`)).includes('not available yet'));
      await ev(`__q.send({ type: 'close' })`);

      await ev(`window.__posts.length = 0`);
      await ev(`__q.send({ type: 'invite', invite: { id: 'TRD-BBBB2222', from: '<i>Stranger #5</i>', expiresIn: 45 } })`);
      check('incoming invite is shown (text only) and ESC declines', await ev(`__q.wait(() => !__q.hidden('invite'))`) && (await ev(`document.querySelectorAll('#invite i').length`)) === 0 && (await ev(`(__q.esc(), true)`))
        && await ev(`__q.wait(() => window.__posts.some((p) => p.url.endsWith('/respond') && p.body.accept === false && p.body.id === 'TRD-BBBB2222'))`));
      await ev(`window.__posts.length = 0`);
      await ev(`__q.send({ type: 'invite', invite: { id: 'TRD-CCCC3333', from: 'Stranger #6', expiresIn: 45 } })`);
      await ev(`__q.click('#inviteAccept')`);
      check('accept posts the session id and accept=true', await ev(`__q.wait(() => window.__posts.some((p) => p.url.endsWith('/respond') && p.body.accept === true && p.body.id === 'TRD-CCCC3333'))`));
    }
  }

  const all = fs.readFileSync(path.join(uiRoot, 'style.css'), 'utf8') + fs.readFileSync(path.join(uiRoot, 'index.html'), 'utf8') + fs.readFileSync(path.join(uiRoot, 'app.js'), 'utf8');
  check('no backdrop-filter anywhere in the UI', !/backdrop-filter/i.test(all));
  check('no external URLs (CDN/fonts)', !/https?:\/\/(?!127\.0\.0\.1|\$\{RES\})/.test(all));
  check('no console errors', consoleErrors.length === 0, consoleErrors);

  ws.close(); chrome.kill(); server.close();
  const failed = results.filter((r) => !r.pass).length;
  console.log(`${failed ? 'RESULT FAIL' : 'RESULT PASS'}: ${results.length} checks, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.log('ERROR', e && e.stack || e); process.exit(1); });
