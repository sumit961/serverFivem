'use strict';
// Trade window. Presentation only: the server owns sessions, offers, confirmations and settlement.
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-trade';
const $ = (id) => document.getElementById(id);

let V = null;            // latest server view
let inventory = [];
let ended = false;
let inviteId = null;
let inviteTimer = null;
let pending = false;

function post(name, body) {
  return fetch(`https://${RES}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body || {}) }).catch(() => {});
}
function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === false || v == null) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'text') el.textContent = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) { if (kid == null || kid === false) continue; el.append(kid.nodeType ? kid : document.createTextNode(String(kid))); }
  return el;
}
const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');
function setStatus(text, kind) { const el = $('status'); el.textContent = text || ''; el.className = 'status' + (kind ? ' ' + kind : ''); }
function send(op, a, b) { pending = true; post('offer', { op, a, b }); setTimeout(() => { pending = false; }, 600); }

// ---- confirmation modal (ui/AGENTS.md classes) ----
let confirmCb = null;
function askConfirm(message, consequence, cb) {
  $('confirmMessage').textContent = message; $('confirmConsequence').textContent = consequence;
  $('confirm').classList.remove('hidden'); confirmCb = cb; $('confirmOk').focus();
}
function closeConfirm() { $('confirm').classList.add('hidden'); confirmCb = null; }
$('confirmCancel').addEventListener('click', closeConfirm);
$('confirm').addEventListener('click', (e) => { if (e.target === $('confirm')) closeConfirm(); });
$('confirmOk').addEventListener('click', () => { const cb = confirmCb; closeConfirm(); if (cb) cb(); });

function closeDrawer() { $('drawer').classList.add('hidden'); $('drawer').replaceChildren(); }
$('drawer').addEventListener('click', (e) => { if (e.target === $('drawer')) closeDrawer(); });

function summarize(offer) {
  const parts = [];
  if (offer.cash > 0) parts.push(money(offer.cash));
  for (const it of offer.items) parts.push(it.quantity + ' x ' + it.label);
  return parts.length ? parts.join('\n') : 'nothing';
}

function pickerDrawer() {
  const list = h('div', { class: 'plist' });
  const mine = new Set(V.you.offer.items.map((i) => i.ref));
  for (const it of inventory) {
    const qty = h('input', { type: 'number', min: 1, max: Math.min(it.quantity, V.caps.maxQuantity), value: 1, 'aria-label': 'Quantity of ' + it.label });
    list.append(h('div', { class: 'pick' },
      h('span', {}, it.label, ' ', h('span', { class: 'muted', text: '(have ' + it.quantity + ')' }), it.summary ? h('span', { class: 'sub', text: it.summary }) : null),
      qty,
      h('button', { class: 'btn small', type: 'button', text: mine.has(it.ref) ? 'UPDATE' : 'ADD', onclick: () => { closeDrawer(); send('addItem', it.ref, Math.floor(Number(qty.value) || 0)); } })));
  }
  if (!inventory.length) list.append(h('div', { class: 'empty', text: 'Nothing tradeable in your inventory.' }));
  $('drawer').replaceChildren(h('div', { class: 'drawer-card' }, h('div', { class: 'col-title', text: 'Add an item' }), list,
    h('div', { class: 'actions' }, h('button', { class: 'btn secondary', type: 'button', text: 'CLOSE', onclick: closeDrawer }))));
  $('drawer').classList.remove('hidden');
}

function itemRow(it, editable) {
  return h('div', { class: 'item' },
    h('span', {}, it.label, it.summary ? h('span', { class: 'sub', text: it.summary }) : null),
    h('span', { class: 'qty', text: 'x' + it.quantity }),
    editable ? h('button', { class: 'btn small secondary', type: 'button', 'aria-label': 'Remove ' + it.label, text: 'REMOVE', disabled: V.state !== 'open', onclick: () => send('removeItem', it.ref) }) : h('span'));
}

function render() {
  if (!V) return;
  const locked = V.state === 'committing' || ended;
  $('title').textContent = 'Trade with ' + V.other.label;
  const both = V.you.confirmed && V.other.confirmed;
  const chip = $('stateChip');
  let chipText = 'EDITING', chipCls = 'state';
  if (V.state === 'committing' || both) { chipText = 'COMMITTING'; chipCls += ' committing'; }
  else if (V.you.confirmed) { chipText = 'YOU CONFIRMED'; chipCls += ' confirmed'; }
  else if (V.other.confirmed) { chipText = 'THEY CONFIRMED'; chipCls += ' confirmed'; }
  chip.textContent = chipText; chip.className = chipCls;

  const cashInput = h('input', { type: 'number', min: 0, max: V.caps.maxCash, value: V.you.offer.cash, 'aria-label': 'Cash you offer', disabled: locked || V.state !== 'open' });
  const commitCash = () => { const n = Math.floor(Number(cashInput.value) || 0); if (n !== V.you.offer.cash) send('cash', n); };
  cashInput.addEventListener('change', commitCash);
  cashInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') commitCash(); });
  $('colYou').className = 'col' + (V.you.confirmed ? ' locked' : '');
  $('colYou').replaceChildren(
    h('div', { class: 'col-head' }, h('div', { class: 'col-title', text: 'Your offer' }), h('span', { class: 'badge' + (V.you.confirmed ? ' on' : ''), text: V.you.confirmed ? 'CONFIRMED' : 'NOT CONFIRMED' })),
    h('div', { class: 'cash' }, h('span', { class: 'label', text: 'CASH (WALLET ' + money(V.wallet) + ')' }), cashInput),
    h('div', { class: 'label', text: 'ITEMS' }),
    h('div', { class: 'items' }, ...(V.you.offer.items.length ? V.you.offer.items.map((i) => itemRow(i, true)) : [h('div', { class: 'empty', text: V.caps.items ? 'No items offered' : 'Item trading is not available yet' })])),
    V.caps.items ? h('button', { class: 'btn small secondary', type: 'button', disabled: locked || V.state !== 'open' || V.you.offer.items.length >= V.caps.maxLines, text: 'ADD ITEM', onclick: pickerDrawer }) : null);
  $('colOther').className = 'col' + (V.other.confirmed ? ' locked' : '');
  $('colOther').replaceChildren(
    h('div', { class: 'col-head' }, h('div', { class: 'col-title', text: V.other.label + ' offers' }), h('span', { class: 'badge' + (V.other.confirmed ? ' on' : ''), text: V.other.confirmed ? 'CONFIRMED' : 'NOT CONFIRMED' })),
    h('div', { class: 'cash' }, h('span', { class: 'label', text: 'CASH' }), h('div', { class: 'value', text: money(V.other.offer.cash) })),
    h('div', { class: 'label', text: 'ITEMS' }),
    h('div', { class: 'items' }, ...(V.other.offer.items.length ? V.other.offer.items.map((i) => itemRow(i, false)) : [h('div', { class: 'empty', text: 'No items offered' })])));

  $('confirmBtn').disabled = locked || V.state !== 'open' || V.you.confirmed;
  $('confirmBtn').textContent = V.you.confirmed ? 'WAITING FOR THEM' : 'CONFIRM';
  $('cancelBtn').disabled = locked;
  $('hint').textContent = V.state === 'committing' ? 'Completing the trade...' : 'Any change to either offer clears both confirmations.';
  $('overlay').classList.toggle('hidden', V.state !== 'committing' || ended);
  $('overlayText').textContent = 'Completing trade...';
}

function showEnded(info) {
  ended = true;
  $('overlay').classList.remove('hidden');
  const ok = info.outcome === 'completed';
  $('overlayText').className = 'overlay-card ' + (ok ? 'ok' : 'bad');
  $('overlayText').textContent = info.message || (ok ? 'Trade complete.' : 'Trade cancelled.');
  const chip = $('stateChip'); chip.textContent = ok ? 'COMPLETED' : 'CANCELLED'; chip.className = 'state ' + (ok ? 'done' : 'bad');
  $('confirmBtn').disabled = true; $('cancelBtn').disabled = true;
}

function resetUi() {
  V = null; inventory = []; ended = false; pending = false;
  closeConfirm(); closeDrawer();
  $('root').classList.add('hidden'); $('invite').classList.add('hidden');
  $('overlayText').className = 'overlay-card';
  clearInterval(inviteTimer); inviteId = null; setStatus('', '');
}

$('confirmBtn').addEventListener('click', () => {
  if (!V || V.state !== 'open' || V.you.confirmed) return;
  askConfirm('You give:\n' + summarize(V.you.offer) + '\n\nYou receive:\n' + summarize(V.other.offer), 'The trade completes only when both of you confirm these exact offers.',
    () => post('confirm', { rev: V.rev }));
});
$('cancelBtn').addEventListener('click', () => post('cancel'));

function showInvite(inv) {
  inviteId = inv.id;
  $('inviteTitle').textContent = inv.from + ' wants to trade';
  let left = Number(inv.expiresIn) || 45;
  const tick = () => { $('inviteTimer').textContent = 'Expires in ' + left + 's'; if (left-- <= 0) respond(false); };
  clearInterval(inviteTimer); tick(); inviteTimer = setInterval(tick, 1000);
  $('invite').classList.remove('hidden');
  $('inviteDecline').focus();
}
function respond(accept) {
  if (!inviteId) return;
  const id = inviteId; inviteId = null; clearInterval(inviteTimer);
  $('invite').classList.add('hidden');
  post('respond', { id, accept });
}
$('inviteAccept').addEventListener('click', () => respond(true));
$('inviteDecline').addEventListener('click', () => respond(false));

window.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  e.preventDefault();
  if (!$('confirm').classList.contains('hidden')) return closeConfirm();
  if (!$('drawer').classList.contains('hidden')) return closeDrawer();
  if (inviteId) return respond(false);
  if (ended) { post('forceClose'); return; }
  if (V) post('close');
});

window.addEventListener('message', (ev) => {
  const m = ev.data || {};
  if (m.type === 'open') { resetUi(); V = m.view; $('root').classList.remove('hidden'); render(); }
  else if (m.type === 'state') { V = m.view; setStatus('', ''); render(); }
  else if (m.type === 'inventory') { inventory = Array.isArray(m.list) ? m.list : []; }
  else if (m.type === 'result') { setStatus(m.result.message, m.result.ok ? 'ok' : 'err'); }
  else if (m.type === 'ended') { showEnded(m.info); }
  else if (m.type === 'invite') { showInvite(m.invite); }
  else if (m.type === 'close') { resetUi(); }
});
