/* Browser-only harness (injected by app.js only when not running inside FiveM). Simulates the server callbacks. */
(() => {
  'use strict';
  const offers = [
    { id: 'diagnostic', label: 'Vehicle diagnostic', category: 'DIAGNOSTIC', mode: 'both' },
    { id: 'repair_basic', label: 'Engine and fuel system repair', category: 'BASIC_REPAIR', mode: 'both' },
    { id: 'repair_full', label: 'Full workshop repair', category: 'BASIC_REPAIR', mode: 'workshop' },
    { id: 'tuning_request', label: 'Vehicle tuning', category: 'TUNING', mode: 'both', tuning: true },
  ];
  const db = {
    requests: [
      { contract: 'CT-AAAAAAAA01', title: 'Mechanic request', description: 'Repair: engine <b>not bold</b> smoking', area: 'Roadside near 200, -1100', hint: 'repair' },
      { contract: 'CT-AAAAAAAA02', title: 'Mechanic request', description: 'Tyres', area: 'Roadside near -300, 500', hint: 'tires' },
    ],
    active: null,
  };
  const state = () => ({ ok: true, data: { requests: db.active ? [] : db.requests.slice(), active: db.active ? JSON.parse(JSON.stringify(db.active)) : null } });
  window.__cmMechanicMock = async (endpoint, payload) => {
    await new Promise((r) => setTimeout(r, 30));
    if (endpoint === 'refresh') return state();
    if (endpoint === 'close') return { ok: true };
    if (endpoint === 'claim') {
      const r = db.requests.find((x) => x.contract === payload.contract); if (!r) return { ok: false, error: 'not_open' };
      db.requests = db.requests.filter((x) => x !== r);
      db.active = { workOrder: 'WO-MOCK0001', state: 'assigned', note: r.description, customerPosition: { x: 200, y: -1100 } };
      return { ok: true, data: db.active };
    }
    if (!db.active) return { ok: false, error: 'not_found' };
    if (endpoint === 'diagnose') {
      Object.assign(db.active, { state: 'diagnosing', vehicleLabel: 'Sultan', offers, diagnosis: { engine: 40, body: 70, tank: 100, brokenWindows: 1, damagedDoors: 1, damagedTyres: 0 } });
      return { ok: true, data: db.active };
    }
    if (endpoint === 'quote') {
      const o = offers.find((x) => x.id === payload.service); if (!o) return { ok: false, error: 'failed' };
      if (o.mode === 'workshop') return { ok: false, error: 'workshop_not_configured' };
      Object.assign(db.active, { state: 'quoted', quote: 7260, serviceLabel: o.label, service: o.id }); delete db.active.offers; return { ok: true, data: { amount: 7260 } };
    }
    if (endpoint === 'tuning') {
      if (!['chip', 'workshop', 'livery'].includes(payload.shop)) return { ok: false, error: 'invalid_service' };
      Object.assign(db.active, { state: 'quoted', quote: 25000, serviceLabel: 'Vehicle tuning', service: 'tuning_request' }); delete db.active.offers; return { ok: true, data: { opened: true } };
    }
    if (endpoint === 'service') { db.active = null; return { ok: true, data: {} }; }
    if (endpoint === 'abandon') {
      db.requests.unshift({ contract: 'CT-AAAAAAAA01', title: 'Mechanic request', description: 'Repair: engine smoking', area: 'Roadside near 200, -1100', hint: 'repair' }); db.active = null; return { ok: true };
    }
    return { ok: false, error: 'failed' };
  };
  // test hook: advance the mock order the way the server would (customer approval, payment)
  window.__cmMechanicAdvance = (to) => { if (db.active) db.active.state = to; };
  window.__cmMechanicBoot = (open) => open(state());
})();
