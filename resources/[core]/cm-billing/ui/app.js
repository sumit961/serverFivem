/* cm-billing NUI. Renders with textContent only. Holds no authority: the server lists the caller's own invoices and
   performs payment; the NUI only says "pay this reference from cash/bank". */
(() => {
  'use strict';
  const isNui = typeof GetParentResourceName === 'function';
  const RES = isNui ? GetParentResourceName() : 'cm-billing';

  const ERRORS = {
    rate_limited: 'Please wait a moment.', busy: 'That payment is already being processed.', internal_error: 'Something went wrong.',
    character_not_loaded: 'Billing unavailable.', unavailable: 'Billing is starting up.', invalid_account: 'Choose cash or bank.',
    not_found: 'Invoice not found.', not_pending: 'This invoice can no longer be paid.', insufficient_funds: 'Not enough funds in that account.',
    destination_unavailable: 'This invoice cannot be settled right now.', settlement_failed: 'Payment could not be completed. You were not charged.',
    invalid_request: 'Invalid request.',
  };

  const $ = (id) => document.getElementById(id);
  const root = $('root'), listEl = $('list'), detailEl = $('detail'), modalEl = $('modal'), toastsEl = $('toasts');
  const state = { tab: 'pending', pending: [], history: [], balances: { cash: 0, bank: 0 }, selected: null, account: 'bank', busy: false };
  let modalCancel = null;

  function h(tag, props, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(props || {})) {
      if (value === undefined || value === null || value === false) continue;
      if (key === 'class') el.className = value;
      else if (key === 'text') el.textContent = value;
      else if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
      else if (key === 'disabled') el.disabled = true;
      else el.setAttribute(key, value === true ? '' : String(value));
    }
    for (const child of children.flat()) {
      if (child === null || child === undefined || child === false) continue;
      el.appendChild(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return el;
  }

  const money = (n) => '$' + Math.floor(Number(n) || 0).toLocaleString('en-US');
  const pad = (n) => String(n).padStart(2, '0');
  function fmtDate(epoch) {
    if (!epoch) return '—';
    const d = new Date(epoch * 1000);
    return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  const errText = (code) => ERRORS[code] || 'Request failed.';

  async function api(endpoint, payload) {
    if (!isNui) return window.__cmBillingMock ? window.__cmBillingMock(endpoint, payload) : { ok: false, error: 'internal_error' };
    try {
      const response = await fetch(`https://${RES}/api`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify({ endpoint, payload }),
      });
      return await response.json();
    } catch (e) { return { ok: false, error: 'internal_error' }; }
  }

  function post(path) {
    if (!isNui) { if (path === 'close') window.postMessage({ action: 'close' }, '*'); return Promise.resolve(); }
    return fetch(`https://${RES}/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: '{}' }).catch(() => {});
  }

  function toast(message, kind) {
    const el = h('div', { class: 'toast ' + (kind || ''), text: message });
    toastsEl.appendChild(el);
    while (toastsEl.children.length > 3) toastsEl.removeChild(toastsEl.firstChild);
    setTimeout(() => el.remove(), 3500);
  }

  function closeModal() { modalEl.classList.add('hidden'); modalEl.replaceChildren(); modalCancel = null; }
  // Presentation-only confirmation; the server independently validates ownership, status, funds and destination.
  function confirmModal({ title, message, consequence, confirmLabel, onConfirm }) {
    const confirmBtn = h('button', { class: 'btn cm-confirm-modal__confirm', text: confirmLabel || 'CONFIRM' });
    const cancelBtn = h('button', { class: 'btn cm-confirm-modal__cancel', text: 'CANCEL', onclick: closeModal });
    confirmBtn.addEventListener('click', async () => {
      confirmBtn.disabled = true;
      confirmBtn.textContent = '...';
      try { await onConfirm(); } finally { closeModal(); }
    });
    modalEl.replaceChildren(h('div', { class: 'cm-confirm-modal', role: 'dialog', 'aria-modal': 'true' },
      h('div', { class: 'cm-confirm-modal__title', text: title }), h('div', { class: 'cm-confirm-modal__message', text: message }),
      consequence ? h('div', { class: 'cm-confirm-modal__consequence', text: consequence }) : null,
      h('div', { class: 'cm-confirm-modal__actions' }, confirmBtn, cancelBtn)));
    modalEl.classList.remove('hidden');
    modalCancel = closeModal;
    confirmBtn.focus();
  }

  const current = () => (state.tab === 'pending' ? state.pending : state.history);
  const selectedInvoice = () => current().find((i) => i.reference === state.selected) || null;

  function renderBalances() {
    $('balances').replaceChildren(
      h('div', {}, 'Cash', h('b', { text: money(state.balances.cash) })),
      h('div', {}, 'Bank', h('b', { text: money(state.balances.bank) })));
    const count = $('pendingCount');
    count.textContent = String(state.pending.length);
    count.classList.toggle('zero', state.pending.length === 0);
    $('subtitle').textContent = state.pending.length ? `${state.pending.length} outstanding · ${money(state.pending.reduce((a, i) => a + i.amount, 0))}` : 'No outstanding invoices';
  }

  function renderList() {
    const rows = current();
    if (!rows.length) {
      listEl.replaceChildren(h('div', { class: 'empty', text: state.tab === 'pending' ? 'You have no outstanding invoices.' : 'No invoice history yet.' }));
      return;
    }
    listEl.replaceChildren(...rows.map((inv) => h('button', {
      class: 'row' + (inv.reference === state.selected ? ' selected' : '') + (state.tab === 'history' ? ' settled' : ''),
      onclick: () => { state.selected = inv.reference; render(); },
    },
      h('div', { class: 'r1' }, h('span', { class: 'name', text: inv.label }), h('span', { class: 'amt', text: money(inv.amount) })),
      h('div', { class: 'r2' }, h('span', { text: inv.issuer }), h('span', { text: fmtDate(inv.createdAt).slice(0, 10) })))));
  }

  function renderDetail() {
    const inv = selectedInvoice();
    if (!inv) {
      detailEl.replaceChildren(h('div', { class: 'empty', text: current().length ? 'Select an invoice to see its details.' : '' }));
      return;
    }
    const pending = inv.status === 'pending';
    const canAfford = (acct) => (state.balances[acct] || 0) >= inv.amount;
    if (pending && !canAfford(state.account) && canAfford(state.account === 'bank' ? 'cash' : 'bank')) state.account = state.account === 'bank' ? 'cash' : 'bank';
    const payBtn = h('button', { class: 'btn primary', text: `Pay ${money(inv.amount)}`, disabled: !(pending && canAfford(state.account)) });
    payBtn.addEventListener('click', () => confirmModal({
      title: 'CONFIRM PAYMENT', message: `Pay ${money(inv.amount)} to ${inv.issuer} for "${inv.label}" (${inv.reference})?`,
      consequence: `${money(inv.amount)} will be taken from your ${state.account} account.`, confirmLabel: 'PAY',
      onConfirm: () => pay(inv),
    }));
    detailEl.replaceChildren(h('div', { class: 'card' },
      h('div', { class: 'ref' }, h('span', { text: inv.reference }), h('span', { class: 'chip ' + inv.status, text: inv.status })),
      h('h2', { text: inv.label }), h('div', { class: 'issuer', text: 'Issued by ' + inv.issuer }),
      h('div', { class: 'big', text: money(inv.amount) }),
      inv.description ? h('div', { class: 'desc', text: inv.description }) : null,
      h('div', { class: 'facts' },
        h('div', {}, 'Issued', h('b', { text: fmtDate(inv.createdAt) })),
        inv.paidAt ? h('div', {}, 'Paid', h('b', { text: fmtDate(inv.paidAt) + (inv.account ? ' · ' + inv.account : '') })) : (inv.expiresAt ? h('div', {}, 'Expires', h('b', { text: fmtDate(inv.expiresAt) })) : h('div', {}, 'Due', h('b', { text: inv.dueAt ? fmtDate(inv.dueAt) : 'No due date' }))),
        inv.voidReason ? h('div', {}, 'Reason', h('b', { text: inv.voidReason })) : null),
      pending ? h('div', { class: 'accounts' },
        ['bank', 'cash'].map((acct) => h('button', { class: 'acct' + (state.account === acct ? ' active' : ''), disabled: !canAfford(acct), onclick: () => { state.account = acct; renderDetail(); } },
          h('div', { class: 'a1', text: 'Pay from ' + acct }), h('div', { class: 'a2', text: money(state.balances[acct]) })))) : null,
      pending ? payBtn : null,
      pending && !canAfford('cash') && !canAfford('bank') ? h('div', { class: 'note', text: 'You do not have enough in either account.' }) : null,
      inv.status === 'processing' ? h('div', { class: 'note', text: 'This payment is being processed.' }) : null));
  }

  async function pay(inv) {
    if (state.busy) return;
    state.busy = true;
    const res = await api('pay', { reference: inv.reference, account: state.account });
    state.busy = false;
    if (!res.ok) {
      toast(errText(res.error), 'error');
      await refresh();
      return;
    }
    apply(res.data);
    state.selected = inv.reference;
    state.tab = 'history';
    syncTabs();
    toast(`Paid ${money(inv.amount)} to ${inv.issuer}.`, 'success');
    render();
  }

  function apply(data) {
    if (!data) return;
    state.pending = data.pending || [];
    state.history = data.history || [];
    state.balances = data.balances || state.balances;
  }

  async function refresh() {
    const res = await api('list');
    if (res.ok) apply(res.data);
    if (state.selected && !selectedInvoice()) state.selected = null;
    render();
  }

  function syncTabs() {
    $('tabPending').classList.toggle('active', state.tab === 'pending');
    $('tabHistory').classList.toggle('active', state.tab === 'history');
  }

  function render() {
    renderBalances();
    renderList();
    renderDetail();
  }

  function setTab(tab) {
    state.tab = tab;
    state.selected = current()[0] ? current()[0].reference : null;
    syncTabs();
    render();
  }

  function open(data) {
    apply(data);
    closeModal();
    state.tab = 'pending';
    state.selected = state.pending[0] ? state.pending[0].reference : null;
    state.account = (state.balances.bank >= (state.pending[0] ? state.pending[0].amount : 0)) ? 'bank' : 'cash';
    state.busy = false;
    syncTabs();
    root.classList.remove('hidden');
    render();
  }

  function hide() {
    root.classList.add('hidden');
    closeModal();
    toastsEl.replaceChildren();
    state.busy = false;
  }

  $('tabPending').addEventListener('click', () => setTab('pending'));
  $('tabHistory').addEventListener('click', () => setTab('history'));
  $('closeBtn').addEventListener('click', () => { closeModal(); post('close'); });

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'open') open(msg.data || {});
    else if (msg.action === 'close') hide();
    else if (msg.action === 'changed') refresh();
  });

  window.addEventListener('keydown', (e) => {
    if (root.classList.contains('hidden') || e.key !== 'Escape') return;
    e.preventDefault();
    if (modalCancel) closeModal(); else post('close');
  });

  if (!isNui) {
    const s = document.createElement('script');
    s.src = 'dev-mock.js';
    s.onload = () => { if (window.__cmBillingBoot) window.__cmBillingBoot(open); };
    document.head.appendChild(s);
  }
})();
