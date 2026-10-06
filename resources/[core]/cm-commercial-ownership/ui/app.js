'use strict';
// Shared business staff panel. Presentation only: every action is re-validated by the server,
// which also decides the business, caller authority, amounts and target identity.

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-commercial-ownership';
const $ = (id) => document.getElementById(id);
const ACTION_LABELS = {
  employee_invited: 'Invited', invite_accepted: 'Invite accepted', invite_declined: 'Invite declined', invite_expired: 'Invite expired',
  employee_removed: 'Removed', employee_resigned: 'Resigned', rank_changed: 'Rank changed', rank_created: 'Rank created',
  rank_edited: 'Rank edited', rank_deleted: 'Rank deleted', rank_pay_changed: 'Rank pay changed', permissions_changed: 'Permissions changed',
  payroll_paid: 'Payroll paid', supply_order_created: 'Supply ordered', supply_claimed: 'Supply accepted', supply_in_transit: 'Supply in transit',
  supply_delivered: 'Supply delivered', supply_cancelled: 'Supply cancelled', supply_refunded: 'Supply refunded', supply_failed: 'Supply failed', invoice_created: 'Invoice created', ownership_changed: 'Ownership changed',
  admin_employee_removed: 'Removed by admin', admin_rank_reset: 'Rank reset by admin', admin_repair: 'Repaired by admin',
};

let S = null;
let tab = 'employees';
let busy = false;
let confirmCb = null;
let inviteToken = null;
let inviteTimer = null;

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
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return el;
}

const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');
const fmtDate = (s) => (s || '').slice(0, 10);

function setStatus(text, kind) {
  const el = $('status');
  el.textContent = text || '';
  el.className = 'status' + (kind ? ' ' + kind : '');
}

function request(action, payload) {
  if (busy) return;
  busy = true;
  setStatus('Working...', '');
  render();
  post('request', { action, payload });
  setTimeout(() => { if (busy) { busy = false; render(); } }, 6000);
}

// ---- Confirmation (ui/AGENTS.md: .cm-confirm-modal) --------------------------------------
function confirmAction(opts, cb) {
  $('confirmTitle').textContent = (opts.title || 'CONFIRM ACTION').toUpperCase();
  $('confirmMessage').textContent = opts.message || '';
  $('confirmConsequence').textContent = opts.consequence || '';
  $('confirm').classList.toggle('danger', !!opts.danger);
  $('confirm').classList.remove('hidden');
  confirmCb = cb;
  (opts.danger ? $('confirmCancel') : $('confirmOk')).focus();
}
function closeConfirm() { $('confirm').classList.add('hidden'); confirmCb = null; }
$('confirmCancel').addEventListener('click', closeConfirm);
$('confirm').addEventListener('click', (e) => { if (e.target === $('confirm')) closeConfirm(); });
$('confirmOk').addEventListener('click', () => { const cb = confirmCb; closeConfirm(); if (cb) cb(); });

// ---- Drawer ---------------------------------------------------------------------------------
function openDrawer(...kids) {
  const d = $('drawer');
  d.replaceChildren(h('div', { class: 'drawer-card' }, ...kids));
  d.classList.remove('hidden');
}
function closeDrawer() { $('drawer').classList.add('hidden'); $('drawer').replaceChildren(); }
$('drawer').addEventListener('click', (e) => { if (e.target === $('drawer')) closeDrawer(); });

// ---- Views ----------------------------------------------------------------------------------
function renderEmployees() {
  const root = $('view-employees');
  const rows = (S.employees || []).map((e) => {
    const rankCell = e.canManage
      ? h('select', { 'aria-label': 'Rank for ' + e.name, disabled: busy, onchange: (ev) => request('setRank', { characterId: e.characterId, rankId: Number(ev.target.value) }) },
        (S.assignable || []).concat((S.assignable || []).some((r) => r.id === e.rankId) ? [] : [{ id: e.rankId, name: e.rank, tier: e.tier }])
          .map((r) => h('option', { value: r.id, selected: r.id === e.rankId }, r.name)))
      : h('div', {}, h('span', { text: e.rank }), e.rankMissing ? h('span', { class: 'tag warn', text: ' NEEDS RANK' }) : null);
    return h('div', { class: 'row emp' },
      h('div', {}, h('div', { class: 'name' }, e.name, e.isSelf ? h('span', { class: 'tag owner', text: ' YOU' }) : null), h('div', { class: 'muted', text: '#' + e.characterId })),
      rankCell,
      h('div', { class: 'muted', text: 'Hired ' + fmtDate(e.hiredAt) }),
      h('div', { class: 'actions' },
        e.canPay ? h('button', { class: 'btn small green', type: 'button', disabled: busy, text: 'PAY ' + money(e.payAmount), onclick: () => confirmAction(
          { title: 'Confirm payroll', message: 'Pay ' + e.name + ' ' + money(e.payAmount) + ' from business funds?', consequence: 'The amount is taken from the business balance.' },
          () => request('pay', { characterId: e.characterId })) }) : null,
        (e.canManage || e.isSelf) ? h('button', { class: 'btn small danger', type: 'button', disabled: busy, text: e.isSelf ? 'RESIGN' : 'REMOVE', onclick: () => confirmAction(
          { title: e.isSelf ? 'Confirm resignation' : 'Confirm removal', danger: true, message: (e.isSelf ? 'Resign from ' : 'Remove ' + e.name + ' from ') + S.business.label + '?', consequence: 'This takes effect immediately.' },
          () => request('remove', { characterId: e.characterId })) }) : null));
  });
  root.replaceChildren(
    h('div', { class: 'toolbar' },
      h('div', { class: 'section-title', text: 'Employees (' + (S.employees || []).length + ')' }),
      S.caps.invite ? h('button', { class: 'btn', type: 'button', disabled: busy, text: 'INVITE NEARBY', onclick: () => { request('candidates'); openDrawer(h('div', { class: 'section-title', text: 'Invite nearby person' }), h('div', { class: 'muted', text: 'Searching...' })); } }) : null),
    ...(rows.length ? rows : [h('div', { class: 'empty', text: 'No employees yet.' })]));
}

function permissionGrid(selected, locked) {
  const grid = h('div', { class: 'perm-grid' });
  for (const p of S.permissions || []) {
    const disabled = locked || !p.grantable;
    grid.append(h('label', { class: 'perm' + (disabled ? ' locked' : '') },
      h('input', { type: 'checkbox', 'data-perm': p.id, checked: selected.includes(p.id), disabled }),
      p.label + (p.implemented ? '' : ' (future)')));
  }
  return grid;
}
const collectPerms = (scope) => [...scope.querySelectorAll('input[data-perm]')].filter((i) => i.checked).map((i) => i.dataset.perm);

function rankDrawer(rank) {
  const creating = !rank;
  const r = rank || { name: '', tier: Math.max(1, Math.min(S.limits.maxTier, 10)), permissions: [], payAmount: 0 };
  const card = h('div', {});
  const name = h('input', { type: 'text', maxlength: 32, value: r.name });
  const tier = h('input', { type: 'number', min: 1, max: S.limits.maxTier, value: r.tier });
  const pay = h('input', { type: 'number', min: 0, max: S.payroll.max, value: r.payAmount, disabled: !S.caps.managePayroll || creating });
  const grid = permissionGrid(r.permissions, !S.caps.managePermissions);
  card.append(
    h('div', { class: 'section-title', text: creating ? 'New rank' : 'Edit ' + r.name }),
    h('div', { class: 'field' }, h('label', { text: 'NAME' }), name),
    h('div', { class: 'field' }, h('label', { text: 'TIER (higher = more authority)' }), tier),
    h('div', { class: 'field' }, h('label', { text: 'PAY PER PAYMENT (0 = NONE, MAX ' + money(S.payroll.max) + ')' }), pay),
    h('div', { class: 'field' }, h('label', { text: 'PERMISSIONS' }), grid),
    h('div', { class: 'actions' },
      h('button', { class: 'btn secondary', type: 'button', text: 'CANCEL', onclick: closeDrawer }),
      h('button', { class: 'btn', type: 'button', text: 'SAVE', onclick: () => {
        const payload = { name: name.value.trim(), tier: Number(tier.value) };
        if (S.caps.managePermissions) payload.permissions = collectPerms(grid);
        if (!creating && S.caps.managePayroll) payload.payAmount = Number(pay.value);
        if (!creating) payload.rankId = r.id;
        closeDrawer();
        request(creating ? 'createRank' : 'updateRank', payload);
      } })));
  openDrawer(card);
  name.focus();
}

function renderRanks() {
  const root = $('view-ranks');
  const rows = (S.ranks || []).map((r) => h('div', { class: 'row rank' },
    h('div', { class: 'tier', text: r.tier }),
    h('div', {}, h('div', { class: 'name', text: r.name }), h('div', { class: 'muted', text: r.employees + ' employee' + (r.employees === 1 ? '' : 's') })),
    h('div', { class: 'chips' }, r.permissions.length ? r.permissions.map((p) => h('span', { class: 'chip', text: p.replace('business.', '').replace(/_/g, ' ') })) : h('span', { class: 'muted', text: 'No permissions' })),
    h('div', { class: r.payAmount ? 'money' : 'muted', text: r.payAmount ? money(r.payAmount) : 'No pay' }),
    h('div', { class: 'actions' },
      r.canEdit ? h('button', { class: 'btn small secondary', type: 'button', disabled: busy, text: 'EDIT', onclick: () => rankDrawer(r) }) : null,
      r.canEdit ? h('button', { class: 'btn small danger', type: 'button', disabled: busy || r.employees > 0, title: r.employees > 0 ? 'Reassign employees first' : '', text: 'DELETE', onclick: () => confirmAction(
        { title: 'Confirm rank deletion', danger: true, message: 'Delete the rank "' + r.name + '"?', consequence: 'This cannot be undone.' }, () => request('deleteRank', { rankId: r.id })) }) : null)));
  root.replaceChildren(
    h('div', { class: 'toolbar' }, h('div', { class: 'section-title', text: 'Ranks' }),
      S.caps.manageRanks ? h('button', { class: 'btn', type: 'button', disabled: busy || (S.ranks || []).length >= S.limits.maxRanks, text: 'NEW RANK', onclick: () => rankDrawer(null) }) : null),
    ...(rows.length ? rows : [h('div', { class: 'empty', text: 'No ranks.' })]));
}

function renderActivity() {
  const root = $('view-activity');
  const rows = (S.activity || []).map((a) => h('div', { class: 'row act' },
    h('div', { class: 'muted', text: (a.at || '').replace('T', ' ').slice(0, 16) }),
    h('div', {}, h('b', { text: ACTION_LABELS[a.action] || a.action }), a.actor ? ' by ' + a.actor : '', a.target ? ' -> ' + a.target : ''),
    h('div', { class: a.amount ? 'money' : 'muted', text: a.amount ? money(a.amount) : '' })));
  root.replaceChildren(h('div', { class: 'toolbar' }, h('div', { class: 'section-title', text: 'Recent activity' })),
    ...(rows.length ? rows : [h('div', { class: 'empty', text: 'No activity recorded.' })]));
}


// ---- Orders (supply) ---------------------------------------------------------------------------------
let catalog = null;
let catalogKeep = null;
const STATUS_LABELS = { pending_payment: 'PAYING', awaiting_fulfillment: 'AWAITING CARRIER', claimed: 'ACCEPTED', in_transit: 'IN TRANSIT', delivering: 'DELIVERING', delivered: 'DELIVERED', cancelled: 'CANCELLED', failed: 'FAILED' };
const ordersEnabled = () => !!(S && S.caps.manageOrders && S.supply && S.supply.supported);

function renderOrders() {
  const root = $('view-orders');
  if (!ordersEnabled()) {
    root.replaceChildren(h('div', { class: 'empty', text: 'This business does not order supplies.' }));
    return;
  }
  const rows = (S.orders || []).map((o) => h('div', { class: 'row ord' },
    h('div', { class: 'name', text: o.reference }),
    h('div', {}, h('span', { class: 'badge ' + o.status, text: STATUS_LABELS[o.status] || o.status })),
    h('div', { class: 'muted', text: fmtDate(o.createdAt) + ' - ' + o.itemCount + ' item' + (o.itemCount === 1 ? '' : 's') + ' (' + o.units + ' units)' }),
    h('div', { class: 'money right', text: money(o.total) }),
    h('div', { class: 'actions' },
      h('button', { class: 'btn small secondary', type: 'button', disabled: busy, text: 'DETAILS', onclick: () => request('supplyDetail', { reference: o.reference }) }),
      o.canCancel ? h('button', { class: 'btn small danger', type: 'button', disabled: busy, text: 'CANCEL', onclick: () => confirmAction(
        { title: 'Confirm cancellation', danger: true, message: 'Cancel supply order ' + o.reference + '?', consequence: 'The order total (' + money(o.total) + ') is refunded to the business balance once.' },
        () => request('supplyCancel', { reference: o.reference })) }) : null)));
  root.replaceChildren(
    h('div', { class: 'toolbar' }, h('div', { class: 'section-title', text: 'Supply orders' }),
      h('button', { class: 'btn', type: 'button', disabled: busy, text: 'NEW ORDER', onclick: () => request('supplyCatalog') })),
    ...(rows.length ? rows : [h('div', { class: 'empty', text: 'No supply orders yet.' })]));
}

function capacityNote(c) {
  return h('div', { class: 'muted', text: 'Stock ' + c.stock + ' + incoming ' + c.open + ' / capacity ' + c.capacity + ' ' + c.unit });
}

function orderDrawer(cat, keep) {
  const qty = {};
  const list = h('div', { class: 'qlist' }, h('div', { class: 'qline qhead' }, h('span', { text: 'ITEM' }), h('span', { class: 'right', text: 'UNIT COST' }), h('span', { class: 'right', text: 'QTY' })));
  let lastCat = null;
  for (const it of cat.items) {
    if (it.category !== lastCat) { lastCat = it.category; list.append(h('div', { class: 'qhead', text: (it.category || 'items').toUpperCase() })); }
    const input = h('input', { type: 'number', min: 0, max: cat.maxLine, value: (keep && keep[it.id]) || 0, 'aria-label': 'Quantity of ' + it.label });
    qty[it.id] = input;
    list.append(h('div', { class: 'qline' }, h('span', { text: it.label }), h('span', { class: 'right money', text: money(it.unitCost) }), input));
  }
  openDrawer(
    h('div', { class: 'section-title', text: 'New supply order' }),
    capacityNote(cat.capacity),
    h('div', { class: 'note', text: 'Wholesale prices are set by the supplier. You will see the exact total before confirming.' }),
    list,
    h('div', { class: 'actions' },
      h('button', { class: 'btn secondary', type: 'button', text: 'CLOSE', onclick: closeDrawer }),
      h('button', { class: 'btn', type: 'button', text: 'GET QUOTE', onclick: () => {
        const lines = Object.entries(qty).map(([id, el]) => ({ id, qty: Math.floor(Number(el.value) || 0) })).filter((l) => l.qty > 0);
        if (!lines.length) { setStatus('Choose at least one item.', 'err'); return; }
        catalogKeep = Object.fromEntries(lines.map((l) => [l.id, l.qty]));
        request('supplyQuote', { lines });
      } })));
}

function quoteDrawer(q) {
  openDrawer(
    h('div', { class: 'section-title', text: 'Review order' }),
    h('div', { class: 'qlist' }, q.lines.map((l) => h('div', { class: 'qline' }, h('span', { text: l.qty + ' x ' + l.label }), h('span', { class: 'right muted', text: money(l.unitCost) + ' ea' }), h('span', { class: 'right money', text: money(l.lineTotal) })))),
    h('div', { class: 'qsum' }, h('span', { text: q.units + ' units' }), h('span', { class: 'money', text: 'TOTAL ' + money(q.total) })),
    capacityNote({ stock: q.capacity.stock, open: q.capacity.open + q.units, capacity: q.capacity.capacity, unit: q.capacity.unit }),
    q.affordable ? null : h('div', { class: 'note', text: 'The business cannot currently afford this order.' }),
    h('div', { class: 'note', text: 'Quote valid for ' + q.expiresIn + ' seconds. Paid from business funds when confirmed.' }),
    h('div', { class: 'actions' },
      h('button', { class: 'btn secondary', type: 'button', text: 'BACK', onclick: () => { if (catalog) orderDrawer(catalog, catalogKeep); } }),
      h('button', { class: 'btn', type: 'button', disabled: !q.affordable, text: 'CONFIRM ORDER', onclick: () => confirmAction(
        { title: 'Confirm supply order', message: 'Place this order for ' + money(q.total) + '?', consequence: 'The amount is taken from the business balance now. Cancelling before a carrier accepts refunds it once.' },
        () => { closeDrawer(); request('supplyPlace', { token: q.token }); }) })));
}

function detailDrawer(o) {
  openDrawer(
    h('div', { class: 'section-title', text: o.reference }),
    h('div', { class: 'toolbar' }, h('span', { class: 'badge ' + o.status, text: STATUS_LABELS[o.status] || o.status }), h('span', { class: 'money', text: money(o.total) })),
    h('div', { class: 'qlist' }, (o.lines || []).map((l) => h('div', { class: 'qline' }, h('span', { text: l.quantity + ' x ' + l.label }), h('span', { class: 'right muted', text: money(l.unitCost) + ' ea' }), h('span', { class: 'right money', text: money(l.lineTotal) })))),
    o.refunded ? h('div', { class: 'muted', text: 'Refunded to the business balance.' }) : null,
    h('div', { class: 'actions' }, h('button', { class: 'btn secondary', type: 'button', text: 'CLOSE', onclick: closeDrawer })));
}

function render() {
  if (!S) return;
  $('title').textContent = S.business.label;
  $('sub').textContent = 'Your rank: ' + S.you.rank + (S.you.isOwner ? ' (owner)' : '');
  $('funds').classList.toggle('hidden', S.balance == null);
  $('fundsValue').textContent = money(S.balance);
  const actTab = document.querySelector('.tab[data-tab="activity"]');
  actTab.classList.toggle('hidden', !S.caps.viewActivity);
  document.querySelector('.tab[data-tab="orders"]').classList.toggle('hidden', !ordersEnabled());
  if (tab === 'orders' && !ordersEnabled()) tab = 'employees';
  if (tab === 'activity' && !S.caps.viewActivity) tab = 'employees';
  document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === tab));
  for (const v of ['employees', 'ranks', 'orders', 'activity']) $('view-' + v).classList.toggle('hidden', v !== tab);
  renderEmployees(); renderRanks(); renderOrders(); renderActivity();
}

function closeAll() {
  closeConfirm(); closeDrawer();
  $('root').classList.add('hidden');
  S = null; busy = false;
}

// ---- Invite prompt (target side) ---------------------------------------------------------------
function showInvite(inv) {
  inviteToken = inv.token;
  $('inviteTitle').textContent = 'Work at ' + inv.label;
  $('inviteBody').textContent = 'You have been invited to join as ' + inv.rankName + '.';
  let left = Number(inv.expiresIn) || 60;
  const tick = () => { $('inviteTimer').textContent = 'Expires in ' + left + 's'; if (left-- <= 0) respond(false); };
  clearInterval(inviteTimer); tick(); inviteTimer = setInterval(tick, 1000);
  $('invite').classList.remove('hidden');
  $('inviteDecline').focus();
}
function respond(accept) {
  if (!inviteToken) return;
  const token = inviteToken;
  inviteToken = null; clearInterval(inviteTimer);
  $('invite').classList.add('hidden');
  post('respondInvite', { token, accept });
}
$('inviteAccept').addEventListener('click', () => respond(true));
$('inviteDecline').addEventListener('click', () => respond(false));

// ---- Wiring -------------------------------------------------------------------------------------------
$('closeBtn').addEventListener('click', () => { closeAll(); post('close'); });
document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => { tab = t.dataset.tab; render(); }));

window.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  e.preventDefault();
  if (!$('confirm').classList.contains('hidden')) return closeConfirm();
  if (!$('drawer').classList.contains('hidden')) return closeDrawer();
  if (inviteToken) return respond(false);
  if (S) { closeAll(); post('close'); }
});

window.addEventListener('message', (ev) => {
  const m = ev.data || {};
  if (m.type === 'open') { S = m.data; tab = 'employees'; busy = false; setStatus('', ''); $('root').classList.remove('hidden'); render(); }
  else if (m.type === 'update') { S = m.data; busy = false; render(); }
  else if (m.type === 'result') { busy = false; setStatus(m.result.message, m.result.ok ? 'ok' : 'err'); render(); }
  else if (m.type === 'candidates') {
    busy = false;
    const list = m.list || [];
    const ranks = (S && S.assignable) || [];
    const rankSel = h('select', {}, ranks.map((r) => h('option', { value: r.id }, r.name)));
    const defaultRank = ranks.slice().sort((a, b) => a.tier - b.tier)[0];
    if (defaultRank) rankSel.value = defaultRank.id;
    openDrawer(h('div', { class: 'section-title', text: 'Invite nearby person' }),
      h('div', { class: 'field' }, h('label', { text: 'STARTING RANK' }), rankSel),
      list.length ? list.map((c) => h('div', { class: 'cand' }, h('span', { text: c.label }),
        h('button', { class: 'btn small', type: 'button', text: 'INVITE', onclick: () => { closeDrawer(); request('invite', { candidate: c.key, rankId: Number(rankSel.value) }); } })))
        : h('div', { class: 'empty', text: 'Nobody suitable is close enough.' }),
      h('div', { class: 'actions' }, h('button', { class: 'btn secondary', type: 'button', text: 'CLOSE', onclick: closeDrawer })));
  }
  else if (m.type === 'supply') {
    busy = false; setStatus('', '');
    if (m.kind === 'catalog') { catalog = m.payload; orderDrawer(catalog, null); }
    else if (m.kind === 'quote') quoteDrawer(m.payload);
    else if (m.kind === 'detail') detailDrawer(m.payload);
    render();
  }
  else if (m.type === 'invite') showInvite(m.invite);
  else if (m.type === 'close') { closeAll(); respond(false); }
});
