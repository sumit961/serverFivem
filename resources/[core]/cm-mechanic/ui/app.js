(() => {
  'use strict';
  // cm-mechanic work panel. Presentation only: every action is a request the server validates (it resolves the order from the
  // character, the business, the vehicle, the price and the completion). User/customer text is always rendered with textContent.
  const isNui = typeof GetParentResourceName === 'function';
  const RES = isNui ? GetParentResourceName() : 'cm-mechanic';
  const $ = (id) => document.getElementById(id);
  const root = $('root'), body = $('body'), modalLayer = $('modal');
  let current = null;       // last server state { ok, data | error }
  let busy = false;
  let modalCancel = null;
  let pollTimer = null;

  const ERRORS = {
    not_mechanic: 'You are not a mechanic at any workshop.', not_ready: 'Mechanic service is starting. Try again shortly.',
    no_vehicle_nearby: 'Stand next to the customer\'s vehicle first.', too_far: 'Move closer to the vehicle.', customer_too_far: 'The customer must stay near their vehicle.',
    wrong_vehicle: 'That is not the vehicle on this work order.', no_access: 'The customer has no access to this vehicle.', vehicle_protected: 'This vehicle cannot be serviced here.',
    vehicle_not_present: 'The vehicle is not here.', vehicle_not_persistent: 'This is not a registered vehicle.', condition_pending: 'Vehicle condition is still loading. Try again.',
    nothing_to_repair: 'Nothing needs repairing for that service.', condition_unknown: 'Vehicle condition is unavailable.', workshop_not_configured: 'This service needs a workshop bay.',
    not_in_workshop: 'This service must be done inside the workshop.', roadside_disabled: 'Roadside work is not offered by this workshop.', forbidden: 'Your rank does not allow this.',
    invalid_state: 'That is not possible right now.', vehicle_busy: 'Someone is already customising this vehicle.', amount_over_limit: 'That job is above the maximum invoice amount. Choose fewer upgrades.', service_unavailable: 'Tuning is unavailable right now.', use_tuning_session: 'Use the tuning option for this service.', binding_mismatch: 'That tuning session no longer matches this work order.', ownership_changed: 'The vehicle changed hands. Scan it again.', rate_limited: 'Slow down a moment.', busy: 'Please wait.',
    customer_offline: 'The customer is not here.', payment_pending: 'The customer has not paid yet.', too_early: 'The work is not finished yet.', wrong_bucket: 'You are not in the same place as the vehicle.',
    interrupted: 'Service interrupted.', failed: 'Something went wrong.', vehicle_service_failed: 'The vehicle could not be updated. It will be retried.',
    not_open: 'Another mechanic took this request.', already_claimed: 'Another mechanic took this request.', not_found: 'Nothing to do here.', self_service: 'You cannot take your own request.',
  };
  const STATE = { assigned: ['Assigned', 'wait'], diagnosing: ['Diagnosing', 'active'], quoted: ['Quote sent', 'wait'], awaiting_payment: ['Awaiting payment', 'wait'], servicing: ['Servicing', 'active'], completed: ['Completed', 'good'] };
  const STEPS = ['assigned', 'diagnosing', 'quoted', 'awaiting_payment', 'servicing'];

  const money = (n) => '$' + String(Math.floor(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  function h(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined && text !== null) e.textContent = String(text); return e; }
  function btn(label, cls, onClick) { const b = h('button', 'btn' + (cls ? ' ' + cls : ''), label); b.type = 'button'; b.addEventListener('click', onClick); return b; }

  async function api(endpoint, payload) {
    if (!isNui) return window.__cmMechanicMock ? window.__cmMechanicMock(endpoint, payload || {}) : { ok: false, error: 'failed' };
    try {
      const r = await fetch(`https://${RES}/${endpoint}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(payload || {}) });
      return await r.json();
    } catch (e) { return { ok: false, error: 'failed' }; }
  }

  function toast(text, kind) {
    const t = h('div', 'toast ' + (kind || ''), text); $('toasts').appendChild(t);
    setTimeout(() => t.remove(), 3200);
  }

  async function act(endpoint, payload, okText) {
    if (busy) return null;
    busy = true; render();
    const res = await api(endpoint, payload);
    busy = false;
    if (res && res.ok) { if (okText) toast(okText, 'ok'); } else toast(ERRORS[res && res.error] || ERRORS.failed, 'error');
    await refresh();
    return res;
  }

  async function refresh() {
    const res = await api('refresh');
    if (res) { current = res; render(); }
  }

  // ------------------------------------------------------------------ rendering
  function bar(label, pct) {
    const wrap = h('div', 'bar'); const l = h('div', 'lbl'); l.appendChild(h('span', '', label)); l.appendChild(h('b', '', pct === null || pct === undefined ? 'Unknown' : pct + '%'));
    const track = h('div', 'track'); const fill = h('div', 'fill' + (pct < 35 ? ' low' : pct < 70 ? ' mid' : ''));
    fill.style.width = (pct === null || pct === undefined ? 0 : Math.max(0, Math.min(100, pct))) + '%';
    track.appendChild(fill); wrap.appendChild(l); wrap.appendChild(track); return wrap;
  }

  function renderActive(w) {
    const card = h('div', 'card');
    const top = h('div', 'row-top'); top.style.display = 'flex'; top.style.justifyContent = 'space-between'; top.style.alignItems = 'center';
    top.appendChild(h('div', 'section', 'Work order'));
    const st = STATE[w.state] || [w.state, '']; top.appendChild(h('span', 'chip ' + st[1], st[0]));
    card.appendChild(top);
    const steps = h('div', 'steps'); const idx = STEPS.indexOf(w.state);
    STEPS.forEach((s, i) => steps.appendChild(h('div', 'step' + (i < idx ? ' done' : i === idx ? ' now' : ''))));
    card.appendChild(steps);
    card.appendChild(h('h2', '', w.vehicleLabel ? w.vehicleLabel : 'Customer vehicle'));
    if (w.note) card.appendChild(h('div', 'desc', w.note));

    if (w.diagnosis) {
      const bars = h('div', 'bars');
      bars.appendChild(bar('Engine', w.diagnosis.engine)); bars.appendChild(bar('Body', w.diagnosis.body)); bars.appendChild(bar('Fuel tank', w.diagnosis.tank));
      card.appendChild(bars);
      const c = h('div', 'counts');
      c.appendChild(h('span', 'chip', 'Broken windows: ' + w.diagnosis.brokenWindows)); c.appendChild(h('span', 'chip', 'Damaged doors: ' + w.diagnosis.damagedDoors)); c.appendChild(h('span', 'chip', 'Damaged tyres: ' + w.diagnosis.damagedTyres));
      card.appendChild(c);
    }
    const actions = h('div', 'actions');
    if (w.state === 'assigned') {
      card.appendChild(h('div', 'note', 'Drive to the customer (marked on your map), stand next to their vehicle and scan it.'));
      actions.appendChild(btn('SCAN VEHICLE', 'primary', () => act('diagnose', {}, 'Vehicle scanned')));
    } else if (w.state === 'diagnosing') {
      card.appendChild(h('div', 'section', 'Send a quote'));
      (w.offers || []).forEach((o) => {
        const row = h('div', 'svc'); const left = h('div'); left.appendChild(h('span', '', o.label)); left.appendChild(h('small', '', o.mode === 'workshop' ? 'Workshop only' : o.mode === 'roadside' ? 'Roadside' : 'Roadside or workshop'));
        row.appendChild(left);
        if (o.tuning) {
          // Tuning is priced and applied by cm-tuning: the mechanic picks a category and the tuning UI opens (the server authorizes it).
          const g = h('div', 'actions'); g.style.margin = '0';
          [['chip', 'PERFORMANCE'], ['workshop', 'BODY & PAINT'], ['livery', 'LIVERY']].forEach(([shop, text]) => g.appendChild(btn(text, '', () => act('tuning', { shop }))));
          row.appendChild(g);
        } else row.appendChild(btn('QUOTE', '', () => act('quote', { service: o.id }, 'Quote sent to the customer')));
        card.appendChild(row);
      });
      actions.appendChild(btn('RESCAN', '', () => act('diagnose', {})));
    } else if (w.state === 'quoted') {
      card.appendChild(h('div', 'big', money(w.quote)));
      card.appendChild(h('div', 'note', (w.serviceLabel || 'Service') + '. Waiting for the customer to approve or decline. The price is calculated by the server.'));
    } else if (w.state === 'awaiting_payment') {
      card.appendChild(h('div', 'big', money(w.quote)));
      card.appendChild(h('div', 'note', 'Invoice sent. The service starts after the customer pays it from their Bills.'));
    } else if (w.state === 'servicing') {
      card.appendChild(h('div', 'note', 'Paid. Stay next to the vehicle and carry out the service.'));
      actions.appendChild(btn('START SERVICE', 'primary', () => act('service', {})));
    }
    if (['assigned', 'diagnosing', 'quoted', 'awaiting_payment'].includes(w.state)) {
      actions.appendChild(btn('ABANDON JOB', 'danger', () => confirmAbandon(w)));
    }
    if (actions.children.length) card.appendChild(actions);
    for (const el of card.querySelectorAll('.btn')) el.disabled = busy;
    return card;
  }

  function renderBoard(requests) {
    const frag = document.createDocumentFragment();
    frag.appendChild(h('div', 'section', 'Open requests (' + requests.length + ')'));
    if (!requests.length) { frag.appendChild(h('div', 'empty', 'No requests right now.\nCustomers book you through their phone.')); return frag; }
    requests.forEach((r) => {
      const row = h('div', 'row'); const r1 = h('div', 'r1'); r1.appendChild(h('span', 'name', r.title || 'Mechanic request')); r1.appendChild(h('span', 'chip wait', r.hint || 'service')); row.appendChild(r1);
      if (r.description) row.appendChild(h('div', 'sub', r.description));
      row.appendChild(h('div', 'meta', r.area || ''));
      const b = btn('ACCEPT', 'primary', () => act('claim', { contract: r.contract }, 'Request accepted')); b.style.marginTop = '8px'; b.disabled = busy; row.appendChild(b);
      frag.appendChild(row);
    });
    return frag;
  }

  function render() {
    body.replaceChildren();
    if (!current) { body.appendChild(h('div', 'empty', 'Loading...')); return; }
    if (!current.ok) { body.appendChild(h('div', 'empty', ERRORS[current.error] || ERRORS.failed)); return; }
    const data = current.data || {};
    if (data.active) body.appendChild(renderActive(data.active));
    else body.appendChild(renderBoard(data.requests || []));
  }

  // ------------------------------------------------------------- confirm + lifecycle
  function closeModal() { modalLayer.classList.add('hidden'); modalLayer.replaceChildren(); modalCancel = null; }
  function confirmAbandon(w) {
    const box = h('div', 'cm-confirm-modal'); box.setAttribute('role', 'alertdialog');
    box.appendChild(h('div', 'cm-confirm-modal__title', 'CONFIRM ACTION'));
    box.appendChild(h('div', 'cm-confirm-modal__message', 'Abandon work order for ' + (w.vehicleLabel || 'this vehicle') + '?'));
    box.appendChild(h('div', 'cm-confirm-modal__consequence', 'The request returns to the board. Any unpaid invoice is cancelled.'));
    const actions = h('div', 'cm-confirm-modal__actions');
    const cancel = h('button', 'cm-confirm-modal__cancel', 'CANCEL'); cancel.type = 'button'; cancel.addEventListener('click', closeModal);
    const ok = h('button', 'cm-confirm-modal__confirm', 'CONFIRM'); ok.type = 'button';
    ok.addEventListener('click', async () => { ok.disabled = true; closeModal(); await act('abandon', {}, 'Job abandoned'); });
    actions.appendChild(cancel); actions.appendChild(ok); box.appendChild(actions);
    modalLayer.replaceChildren(box); modalLayer.classList.remove('hidden'); modalCancel = closeModal; cancel.focus();
  }

  function open() {
    root.classList.remove('hidden');
    clearInterval(pollTimer); pollTimer = setInterval(() => { if (!busy && !modalCancel) refresh(); }, 6000);
  }
  function close(notify) {
    closeModal(); root.classList.add('hidden'); clearInterval(pollTimer); pollTimer = null;
    if (notify !== false) api('close');
  }

  $('closeBtn').addEventListener('click', () => close());
  window.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || root.classList.contains('hidden')) return;
    if (modalCancel) { modalCancel(); return; }
    close();
  });
  window.addEventListener('message', (ev) => {
    const m = ev.data || {};
    if (m.action === 'open') open();
    else if (m.action === 'close') close(false);
    else if (m.action === 'state') { current = m.data; render(); }
  });

  if (!isNui) {
    const s = document.createElement('script'); s.src = 'dev-mock.js';
    s.onload = () => { if (window.__cmMechanicBoot) window.__cmMechanicBoot((state) => { open(); current = state; render(); }); };
    document.head.appendChild(s);
  }
})();
