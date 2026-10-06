'use strict';

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const { spawn } = require('node:child_process');

const [, , ...argv] = process.argv;
const options = Object.fromEntries(argv.map((value, index) => value.startsWith('--') ? [value.slice(2), argv[index + 1]] : []).filter(Boolean));
const repo = path.resolve(options.root || path.join(__dirname, '..', '..', '..'));
const resource = options.resource || 'cm-electrician';
const output = path.resolve(options.output || path.join(repo, 'cm-agent-out', 'qa'));
const resolutions = [[1280, 720], [1920, 1080], [2560, 1440]];

function chromePath() {
  const candidates = [
    process.env.CM_QA_BROWSER,
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  ].filter(Boolean);
  return candidates.find((candidate) => fs.existsSync(candidate));
}

function sleep(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

function nextPort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
    server.on('error', reject);
  });
}

function contentType(file) {
  return { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json' }[path.extname(file)] || 'application/octet-stream';
}

function findUiRoot(resourceName) {
  const candidates = fs.readdirSync(path.join(repo, 'resources'), { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(repo, 'resources', entry.name, resourceName, 'ui'));
  return candidates.find((candidate) => fs.existsSync(path.join(candidate, 'index.html')));
}

async function startServer(uiRoot) {
  const server = http.createServer((request, response) => {
    const match = request.url.match(/^\/([^/]+)\/(.*?)(?:\?.*)?$/);
    if (!match || !/^[a-z0-9_-]+$/.test(match[1])) return response.writeHead(404).end();
    const file = path.resolve(uiRoot, match[2]);
    if (!file.startsWith(uiRoot + path.sep) || !fs.existsSync(file)) return response.writeHead(404).end();
    response.writeHead(200, { 'Content-Type': contentType(file), 'Cache-Control': 'no-store' });
    fs.createReadStream(file).pipe(response);
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return server;
}

async function runTransparentIdle(cdp, url, width, height, screenshotPath) {
  await cdp.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
  await cdp.send('Page.navigate', { url });
  await sleep(700);
  const idle = await evaluate(cdp, `(() => {
    const html = document.documentElement;
    const body = document.body;
    const root = document.querySelector('#qa-root');
    const card = root.querySelector('.card');
    const style = (node) => getComputedStyle(node);
    const rect = (node) => { const r = node.getBoundingClientRect(); return {left:r.left, top:r.top, right:r.right, bottom:r.bottom, width:r.width, height:r.height}; };
    return {
      htmlBackground: style(html).backgroundColor,
      bodyBackground: style(body).backgroundColor,
      bodyPointerEvents: style(body).pointerEvents,
      rootDisplay: style(root).display,
      rootPointerEvents: style(root).pointerEvents,
      rootBackground: style(root).backgroundColor,
      cardVisible: style(root).display !== 'none' && style(root).visibility !== 'hidden' && style(card).display !== 'none' && style(card).visibility !== 'hidden',
      viewport: { width: innerWidth, height: innerHeight },
    };
  })()`);
  await cdp.send('Page.captureScreenshot', { format: 'png' }).then((shot) => fs.writeFileSync(screenshotPath, Buffer.from(shot.data, 'base64')));
  const active = await evaluate(cdp, `(() => {
    window.postMessage({action:'qaOpen', scenario:'qa.ui.transparent-idle', title:'CM-QA', body:'localized'}, '*');
    return new Promise((resolve) => setTimeout(() => {
      const root = document.querySelector('#qa-root');
      const card = root.querySelector('.card');
      const rootStyle = getComputedStyle(root);
      const cardRect = card.getBoundingClientRect();
      resolve({display:rootStyle.display, pointerEvents:rootStyle.pointerEvents, background:rootStyle.backgroundColor, cardRect:{left:cardRect.left,top:cardRect.top,right:cardRect.right,bottom:cardRect.bottom,width:cardRect.width,height:cardRect.height}, viewport:{width:innerWidth,height:innerHeight}});
    }, 0));
  })()`);
  const reset = await evaluate(cdp, `(() => {
    window.postMessage({action:'qaReset'}, '*');
    return new Promise((resolve) => setTimeout(() => {
      const root = document.querySelector('#qa-root');
      resolve({hidden:root.classList.contains('hidden'), display:getComputedStyle(root).display, title:document.querySelector('#title').textContent, body:document.querySelector('#body').textContent, inlineStyle:root.getAttribute('style'), dataset:root.dataset.scenario || null});
    }, 0));
  })()`);
  const transparent = (value) => value === 'rgba(0, 0, 0, 0)' || value === 'transparent';
  const assertions = {
    viewport: idle.viewport.width === width && idle.viewport.height === height,
    htmlTransparent: transparent(idle.htmlBackground),
    bodyTransparent: transparent(idle.bodyBackground),
    bodyPointerEventsNone: idle.bodyPointerEvents === 'none',
    idleRootHidden: idle.rootDisplay === 'none',
    idleRootTransparent: transparent(idle.rootBackground),
    idleRootPointerEventsNone: idle.rootPointerEvents === 'none',
    idleCardNotVisible: idle.cardVisible === false,
    activeCardLocalized: active.display !== 'none' && active.pointerEvents === 'auto' && transparent(active.background) && active.cardRect.width < active.viewport.width && active.cardRect.height < active.viewport.height && active.cardRect.left >= 0 && active.cardRect.top >= 0 && active.cardRect.right <= active.viewport.width && active.cardRect.bottom <= active.viewport.height,
    resetClearsState: reset.hidden === true && reset.display === 'none' && reset.title === '' && reset.body === '' && reset.inlineStyle === null && reset.dataset === null,
  };
  return { id: 'qa.ui.transparent-idle', resolution: `${width}x${height}`, screenshot: screenshotPath, assertions, idle, active, reset };
}

function requestJson(port, requestPath, method = 'GET') {
  return new Promise((resolve, reject) => {
    const request = http.request({ host: '127.0.0.1', port, path: requestPath, method }, (response) => {
      let body = '';
      response.on('data', (chunk) => { body += chunk; });
      response.on('end', () => {
        try { resolve(JSON.parse(body)); } catch (error) { reject(error); }
      });
    });
    request.on('error', reject);
    request.end();
  });
}

class Cdp {
  constructor(url) { this.ws = new WebSocket(url); this.nextId = 1; this.waiters = new Map(); this.events = []; }
  async connect() { await new Promise((resolve, reject) => { this.ws.onopen = resolve; this.ws.onerror = reject; }); this.ws.onmessage = (event) => { const message = JSON.parse(event.data); if (message.id && this.waiters.has(message.id)) { this.waiters.get(message.id)(message); this.waiters.delete(message.id); } else this.events.push(message); }; }
  send(method, params = {}) { return new Promise((resolve, reject) => { const id = this.nextId++; this.waiters.set(id, (message) => message.error ? reject(new Error(message.error.message)) : resolve(message.result)); this.ws.send(JSON.stringify({ id, method, params })); }); }
  close() { this.ws.close(); }
}

async function evaluate(cdp, expression, returnByValue = true) {
  const result = await cdp.send('Runtime.evaluate', { expression, returnByValue, awaitPromise: true });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || 'browser evaluation failed');
  return result.result && result.result.value;
}

async function runResolution(cdp, url, width, height, screenshotPath) {
  await cdp.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
  await cdp.send('Page.navigate', { url });
  await sleep(700);
  const initial = await evaluate(cdp, `(() => {
    const visible = (node) => getComputedStyle(node).display !== 'none' && getComputedStyle(node).visibility !== 'hidden';
    const rect = (node) => { const r = node.getBoundingClientRect(); return {left:r.left,top:r.top,right:r.right,bottom:r.bottom,width:r.width,height:r.height}; };
    const critical = ['.job-panel', '#btnClose', '#btnToggle'].map((selector) => document.querySelector(selector)).filter(Boolean);
    return {
      scrollWidth: document.documentElement.scrollWidth,
      scrollHeight: document.documentElement.scrollHeight,
      viewportWidth: innerWidth,
      viewportHeight: innerHeight,
      menuVisible: !document.querySelector('#menu-root').classList.contains('hidden'),
      criticalRects: critical.filter(visible).map(rect),
      pointerBlockedWhenHidden: getComputedStyle(document.querySelector('#menu-root')).pointerEvents === 'none'
    };
  })()`);
  await cdp.send('Page.captureScreenshot', { format: 'png' }).then((shot) => fs.writeFileSync(screenshotPath, Buffer.from(shot.data, 'base64')));
  const toggled = await evaluate(cdp, `(() => { document.querySelector('#btnToggle').click(); return window.__cmQaFetches.slice(-1)[0] || null; })()`);
  const close = await evaluate(cdp, `(() => { window.postMessage({action:'openMenu',ctx:{}}, '*'); document.querySelector('#btnClose').click(); return {hidden:document.querySelector('#menu-root').classList.contains('hidden'), calls:window.__cmQaFetches.slice()}; })()`);
  const escape = await evaluate(cdp, `(() => { window.postMessage({action:'openMenu',ctx:{}}, '*'); document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',cancelable:true})); return {hidden:document.querySelector('#menu-root').classList.contains('hidden'), calls:window.__cmQaFetches.slice()}; })()`);
  const assertions = {
    viewport: initial.scrollWidth <= initial.viewportWidth && initial.scrollHeight <= initial.viewportHeight && initial.criticalRects.every((r) => r.left >= 0 && r.top >= 0 && r.right <= initial.viewportWidth && r.bottom <= initial.viewportHeight),
    pointerInput: initial.pointerBlockedWhenHidden,
    close: close.hidden === true,
    escape: escape.hidden === true,
    callbacks: Boolean(toggled && toggled.endpoint === 'toggleEmployment') && close.calls.some((call) => call.endpoint === 'close') && escape.calls.some((call) => call.endpoint === 'escape'),
  };
  return { resolution: `${width}x${height}`, screenshot: screenshotPath, assertions, initial, callbacks: { toggled, close, escape } };
}

async function runFishingResolution(cdp, url, width, height, screenshotPath) {
  await cdp.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
  await cdp.send('Page.navigate', { url });
  await sleep(700);
  const payload = {
    cash: 1250,
    status: { level: 2, xp: 80, xpForNext: 160, maxLevel: false },
    rods: [{ name: 'basic_rod', label: 'Basic Rod', price: 50, image: 'basic_rod.png', requiredLevel: 0, perks: ['NEVER BREAKS'] }],
    bait: [{ name: 'worms', label: 'Worms', price: 5, image: 'worms.png', perks: ['ALWAYS CONSUMED'] }],
    fish: [{ name: 'trout', label: 'Trout', rarity: 'Common', price: 15, xp: 4, count: 2, image: 'trout.png' }],
    boats: [{ name: 'dinghy', label: 'Dinghy', price: 1000 }],
    rentedBoat: null,
    levels: [],
    zones: [],
    mechanics: { heavyRodBreakChance: 35, sharkEnabled: true, sharkChance: 8, sharkDamage: 25, castCooldownSeconds: 1 },
  };
  const initial = await evaluate(cdp, `(() => {
    const hidden = (selector) => document.querySelector(selector).classList.contains('hidden');
    return {
      viewport: { width: innerWidth, height: innerHeight },
      scrollWidth: document.documentElement.scrollWidth,
      scrollHeight: document.documentElement.scrollHeight,
      storeHidden: hidden('#store'),
      minigameHidden: hidden('#minigame'),
      catchHidden: hidden('#catch-modal'),
      bodyBackground: getComputedStyle(document.body).backgroundColor,
      errors: window.__cmQaErrors.slice(),
    };
  })()`);
  await cdp.send('Page.captureScreenshot', { format: 'png' }).then((shot) => fs.writeFileSync(screenshotPath, Buffer.from(shot.data, 'base64')));
  await evaluate(cdp, `window.postMessage({ action: 'openStore', payload: ${JSON.stringify(payload)} }, '*'); new Promise((resolve) => setTimeout(resolve, 0));`);
  await sleep(150);
  const store = await evaluate(cdp, `(() => {
    const tabs = ['rods', 'bait', 'sell', 'boats'];
    const visible = (node) => !node.classList.contains('hidden');
    const tabState = {};
    for (const tab of tabs) {
      document.querySelector('.store-tab[data-tab="' + tab + '"]').click();
      tabState[tab] = visible(document.querySelector('#grid-' + tab));
    }
    document.querySelector('.store-tab[data-tab="rods"]').click();
    const rodButton = document.querySelector('#grid-rods .buy-btn');
    if (rodButton) rodButton.click();
    document.querySelector('.store-tab[data-tab="bait"]').click();
    const addBait = document.querySelector('#grid-bait .add-cart-btn');
    if (addBait) addBait.click();
    const checkout = document.querySelector('#cart-checkout-btn');
    if (checkout) checkout.click();
    document.querySelector('.store-tab[data-tab="sell"]').click();
    const sellButton = document.querySelector('#grid-sell .sell-btn');
    if (sellButton) sellButton.click();
    document.querySelector('.store-tab[data-tab="boats"]').click();
    const rentButton = document.querySelector('#grid-boats .rent-btn');
    if (rentButton) rentButton.click();
    return { tabState, cards: {
      rods: document.querySelectorAll('#grid-rods .item-card').length,
      bait: document.querySelectorAll('#grid-bait .item-card').length,
      sell: document.querySelectorAll('#grid-sell .item-card').length,
      boats: document.querySelectorAll('#grid-boats .item-card').length,
    }, calls: window.__cmQaFetches.slice() };
  })()`);
  const close = await evaluate(cdp, `(() => {
    document.querySelector('#store-close').click();
    return { hidden: document.querySelector('#store').classList.contains('hidden'), calls: window.__cmQaFetches.slice() };
  })()`);
  await evaluate(cdp, `window.postMessage({ action: 'openStore', payload: ${JSON.stringify(payload)} }, '*'); new Promise((resolve) => setTimeout(resolve, 0));`);
  const escape = await evaluate(cdp, `(() => {
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', cancelable: true }));
    return { hidden: document.querySelector('#store').classList.contains('hidden'), calls: window.__cmQaFetches.slice() };
  })()`);
  await evaluate(cdp, `window.postMessage({ action: 'startMinigame', token: 'qa-token', difficulty: 'easy', heavy: false, settings: { windowWidth: 32, targetSpeed: 34, moveSpeed: 55, gainRate: 60, lossRate: 28, timeLimitMs: 13000 } }, '*'); new Promise((resolve) => setTimeout(resolve, 50));`);
  const minigame = await evaluate(cdp, `(() => {
    const visibleBefore = !document.querySelector('#minigame').classList.contains('hidden');
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', cancelable: true }));
    return { visibleBefore, hiddenAfter: document.querySelector('#minigame').classList.contains('hidden'), calls: window.__cmQaFetches.slice() };
  })()`);
  await evaluate(cdp, `window.postMessage({ action: 'catchResult', success: true, label: 'Trout', rarity: 'Common', xpText: '+4 XP', heavy: false, rodBroke: false }, '*'); new Promise((resolve) => setTimeout(resolve, 0));`);
  const catchResult = await evaluate(cdp, `(() => {
    const visibleBefore = !document.querySelector('#catch-modal').classList.contains('hidden');
    document.querySelector('#catch-close').click();
    return { visibleBefore, hiddenAfter: document.querySelector('#catch-modal').classList.contains('hidden'), calls: window.__cmQaFetches.slice() };
  })()`);
  await sleep(300);
  const assets = await evaluate(cdp, `(() => ({
    missing: Array.from(document.images).filter((image) => image.src.startsWith(location.origin) && image.complete && image.naturalWidth === 0).map((image) => image.getAttribute('src')),
    externalDependencies: Array.from(document.querySelectorAll('script[src],link[href]')).map((node) => node.src || node.href).filter((value) => value && !value.startsWith(location.origin)),
    errors: window.__cmQaErrors.slice(),
  }))()`);
  const assertions = {
    viewport: initial.viewport.width === width && initial.viewport.height === height,
    idleHidden: initial.storeHidden && initial.minigameHidden && initial.catchHidden,
    noUnexpectedScroll: initial.scrollWidth <= initial.viewport.width && initial.scrollHeight <= initial.viewport.height,
    tabs: Object.values(store.tabState).every((value) => value === true),
    requiredCards: store.cards.rods > 0 && store.cards.bait > 0 && store.cards.sell > 0 && store.cards.boats > 0,
    callbacks: store.calls.some((call) => call.endpoint === 'buyItem') && store.calls.some((call) => call.endpoint === 'buyCart') && store.calls.some((call) => call.endpoint === 'sellFish') && store.calls.some((call) => call.endpoint === 'rentBoat'),
    close: close.hidden === true && close.calls.some((call) => call.endpoint === 'closeStore'),
    escape: escape.hidden === true && escape.calls.some((call) => call.endpoint === 'escape'),
    minigame: minigame.visibleBefore && minigame.hiddenAfter && minigame.calls.some((call) => call.endpoint === 'minigameResult'),
    catchResult: catchResult.visibleBefore && catchResult.hiddenAfter && catchResult.calls.some((call) => call.endpoint === 'closeCatch'),
    noMissingLocalAssets: assets.missing.length === 0,
    noJsExceptions: assets.errors.length === 0,
  };
  return { resolution: `${width}x${height}`, screenshot: screenshotPath, assertions, initial, store, close, escape, minigame, catchResult, assets };
}

async function main() {
  const browser = chromePath();
  if (!browser) return finish({ result: 'BLOCKED', reason: 'NO_LOCAL_CHROME_OR_EDGE', tests: [] }, 2);
  const uiRoot = findUiRoot(resource);
  if (!uiRoot) return finish({ result: 'BLOCKED', reason: 'NUI_ENTRY_NOT_FOUND', tests: [] }, 2);
  fs.mkdirSync(output, { recursive: true });
  const server = await startServer(uiRoot);
  const serverPort = server.address().port;
  const debugPort = await nextPort();
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cmqa-browser-'));
  const processHandle = spawn(browser, ['--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--remote-allow-origins=*', `--remote-debugging-port=${debugPort}`, `--user-data-dir=${profile}`, 'about:blank'], { windowsHide: true, stdio: ['ignore', 'ignore', 'ignore'] });
  try {
    let version;
    for (let attempt = 0; attempt < 30; attempt += 1) { try { version = await requestJson(debugPort, '/json/version'); break; } catch (_) { await sleep(100); } }
    if (!version) throw new Error('browser_debug_endpoint_unavailable');
    const targets = await requestJson(debugPort, '/json/list');
    const target = targets.find((item) => item.type === 'page');
    if (!target) throw new Error('browser_page_target_unavailable');
    const cdp = new Cdp(target.webSocketDebuggerUrl);
    await cdp.connect();
    await cdp.send('Page.enable'); await cdp.send('Runtime.enable'); await cdp.send('Network.enable');
    await cdp.send('Page.addScriptToEvaluateOnNewDocument', { source: `window.__cmQaFetches=[]; window.__cmQaErrors=[]; window.addEventListener('error',(event)=>{if(event.error||event.message) window.__cmQaErrors.push(String(event.message||event.error||'error'));}); window.addEventListener('unhandledrejection',(event)=>window.__cmQaErrors.push(String(event.reason||'unhandledrejection'))); window.GetParentResourceName=()=>${JSON.stringify(resource)}; window.fetch=(url, options)=>{const endpoint=String(url).split('/').pop(); window.__cmQaFetches.push({endpoint, url:String(url), payload:options&&options.body||null}); return Promise.resolve({ok:true,json:()=>Promise.resolve({})});};` });
    const tests = [];
    const browserTests = resource === 'cm-qa' ? runTransparentIdle : resource === 'cm-fishing' ? runFishingResolution : runResolution;
    const testResolutions = resource === 'cm-qa' ? resolutions.slice(0, 2) : resolutions;
    for (const [width, height] of testResolutions) {
      const scenarioName = resource === 'cm-qa' ? 'qa.ui.transparent-idle' : resource === 'cm-fishing' ? 'fishing.store.minigame.ui' : 'electrician.panel.ui';
      const screenshot = path.join(output, 'screenshots', resource, `${scenarioName}-${width}x${height}.png`);
      fs.mkdirSync(path.dirname(screenshot), { recursive: true });
      tests.push(await browserTests(cdp, `http://127.0.0.1:${serverPort}/${resource}/index.html?preview=1`, width, height, screenshot));
    }
    cdp.close();
    const failed = tests.some((test) => Object.values(test.assertions).some((value) => value !== true));
    return finish({ result: failed ? 'FAIL' : 'PASS', status: failed ? 'UI_AUTOMATION_FAIL' : 'UI_AUTOMATION_PASS', resource, tests, visualReview: 'VISUAL_REVIEW_NOT_RUN' }, failed ? 1 : 0);
  } catch (error) {
    return finish({ result: 'FAIL', reason: error.message, resource, tests: [] }, 1);
  } finally {
    server.close(); processHandle.kill();
    try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }); } catch (_) { /* Chrome may release its temp profile shortly after exit. */ }
  }
}

function finish(value, code) { process.stdout.write(`${JSON.stringify(value)}\n`); process.exitCode = code; return value; }
main().catch((error) => finish({ result: 'FAIL', reason: error.message, tests: [] }, 3));
