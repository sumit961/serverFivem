/* Browser-only harness (injected by app.js only when not running inside FiveM). Simulates the server callbacks. */
(() => {
  'use strict';
  const now = () => Math.floor(Date.now() / 1000);
  const db = {
    balances: { cash: 2500, bank: 18000 },
    pending: [
      { reference: 'INV-K7Q2MZ4P', issuer: 'LS Customs', label: 'Vehicle repair', description: 'Engine and body repair <b>not bold</b>', amount: 12500, status: 'pending', createdAt: now() - 3600, dueAt: now() + 86400 },
      { reference: 'INV-9XH3TWA8', issuer: 'City Services', label: 'Administrative fee', amount: 4000, status: 'pending', createdAt: now() - 7200, expiresAt: now() + 7200 },
      { reference: 'INV-BIG00001', issuer: 'Pillbox Medical', label: 'Hospital treatment', amount: 90000, status: 'pending', createdAt: now() - 90000 },
    ],
    history: [
      { reference: 'INV-OLD11111', issuer: 'LS Customs', label: 'Tyre change', amount: 800, status: 'paid', createdAt: now() - 400000, paidAt: now() - 390000, account: 'cash' },
      { reference: 'INV-OLD22222', issuer: 'City Services', label: 'Permit fee', amount: 1500, status: 'voided', createdAt: now() - 500000, voidReason: 'Issued in error' },
    ],
  };
  const snapshot = () => ({ pending: db.pending.slice(), history: db.history.slice(), balances: Object.assign({}, db.balances) });
  window.__cmBillingMock = async (endpoint, payload) => {
    await new Promise((r) => setTimeout(r, 40));
    if (endpoint === 'list') return { ok: true, data: snapshot() };
    if (endpoint === 'pay') {
      const inv = db.pending.find((i) => i.reference === payload.reference);
      if (!inv) return { ok: false, error: 'not_pending' };
      if (!['cash', 'bank'].includes(payload.account)) return { ok: false, error: 'invalid_account' };
      if (db.balances[payload.account] < inv.amount) return { ok: false, error: 'insufficient_funds' };
      db.balances[payload.account] -= inv.amount;
      db.pending = db.pending.filter((i) => i !== inv);
      db.history.unshift(Object.assign({}, inv, { status: 'paid', paidAt: now(), account: payload.account }));
      return { ok: true, data: Object.assign(snapshot(), { paid: { reference: inv.reference, amount: inv.amount } }) };
    }
    return { ok: false, error: 'invalid_request' };
  };
  window.__cmBillingBoot = (open) => open(snapshot());
})();
