/* cm-phone NUI. All dynamic text is rendered with textContent (never innerHTML). The NUI holds no
   authority: identity, ownership, fees and call state come from the server on every action. */
(() => {
  'use strict';

  const isNui = typeof GetParentResourceName === 'function';
  const RES = isNui ? GetParentResourceName() : 'cm-phone';

  const ERRORS = {
    rate_limited: 'Slow down a moment.', busy: 'Still working on your last request.', internal_error: 'Something went wrong.',
    character_not_loaded: 'Phone unavailable.', no_phone: 'Phone unavailable.', invalid_request: 'Invalid request.',
    invalid_number: 'Enter a valid 7-digit number.', invalid_name: 'Enter a name.', invalid_recipient: 'That number is not in service.',
    invalid_message: 'Message is empty or invalid.', invalid_target: 'You cannot do that.', duplicate_number: 'That number is already saved.',
    contact_limit: 'Contact list is full.', not_found: 'Not found.', forbidden: 'You cannot do that.', undeliverable: 'Message could not be delivered.',
    unavailable: 'Number unavailable.', already_in_call: 'You are already in a call.', no_call: 'No active call.', already_active: 'Call already connected.',
    location_unavailable: 'Location is not available.', group_limit: 'Group is full.', already_member: 'Already in the group.',
    service_unavailable: 'This service is not available right now.', invalid_service: 'Unknown service.', invalid_field: 'Check the request details.',
    missing_field: 'Fill in the required details.', already_active: 'You already have an open request.', service_failed: 'The service could not take your request.',
    status_unavailable: 'Status is unavailable right now.', cancel_not_allowed: 'This request can no longer be cancelled.', no_waypoint: 'Set a waypoint on your map first.',
    no_provider: 'No provider is available.', too_far: 'That is too far away.', invalid_destination: 'Choose a valid destination.',
    insufficient_funds: 'You cannot afford the posting fee.', cooldown: 'You posted recently. Please wait.', dispatch_failed: 'Emergency services could not be reached.',
  };
  const BUSY_MSG = 'Line busy.';

  const ICONS = {
    phone: '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/>',
    message: '<path d="M4 5h16v11H9l-5 4z"/>',
    contacts: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/>',
    siren: '<path d="M7 18v-5a5 5 0 0 1 10 0v5"/><path d="M5 18h14v3H5z"/><path d="M12 3v2M4.5 6l1.5 1.5M19.5 6 18 7.5"/>',
    ad: '<path d="M4 10v4l12 5V5z"/><path d="M16 9a3 3 0 0 1 0 6"/><path d="M7 14l1 5h3l-1-4"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>',
    services: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><path d="M16.5 13v7M13 16.5h7"/>',
    taxi: '<path d="M5 15l1.6-5.2A2 2 0 0 1 8.5 8.4h7a2 2 0 0 1 1.9 1.4L19 15"/><path d="M4 15h16v4H4z"/><path d="M10 5h4v3h-4z"/><circle cx="8" cy="17" r=".6"/><circle cx="16" cy="17" r=".6"/>',
    wrench: '<path d="M14.5 6.5a4 4 0 0 0 5 5L11 20a2.1 2.1 0 0 1-3-3z"/><path d="M14.5 6.5l3 3"/>',
    box: '<path d="M4 8l8-4 8 4v8l-8 4-8-4z"/><path d="M4 8l8 4 8-4M12 12v8"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    send: '<path d="M4 12l16-8-6 16-3-6z"/>',
    pin: '<path d="M12 21s7-6.2 7-11a7 7 0 0 0-14 0c0 4.8 7 11 7 11z"/><circle cx="12" cy="10" r="2.5"/>',
    users: '<circle cx="9" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M3 20c0-3.5 2.7-5.5 6-5.5s6 2 6 5.5M15 15c3 0 6 1.3 6 4.5"/>',
    x: '<path d="M6 6l12 12M18 6 6 18"/>',
    hang: '<path d="M3 14c5-5 13-5 18 0l-2 3-4-1.5v-2.5a10 10 0 0 0-6 0V15.5L5 17z"/>',
    answer: '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/>',
  };

  const $ = (id) => document.getElementById(id);
  const root = $('root'), screenEl = $('screen'), modalEl = $('modal'), toastsEl = $('toasts');

  const state = {
    me: null, contacts: [], conversations: [], calls: [], blocks: [], limits: {}, unread: 0,
    view: 'home', stack: [], params: {}, call: null, activeSince: 0,
    thread: null, adverts: [], dial: '', tab: 'keypad', search: '', draft: '', callMin: false, services: [],
  };
  const inflight = new Set();
  let callTimer = null;

  // ---- DOM helpers -------------------------------------------------------------
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

  const SVG_NS = 'http://www.w3.org/2000/svg';
  const iconCache = {};
  // Icon markup is static, trusted path data; it is parsed as SVG (not injected as HTML).
  function icon(name) {
    const svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    if (!iconCache[name]) {
      const doc = new DOMParser().parseFromString(`<svg xmlns="${SVG_NS}">${ICONS[name] || ''}</svg>`, 'image/svg+xml');
      iconCache[name] = Array.from(doc.documentElement.childNodes);
    }
    for (const node of iconCache[name]) svg.appendChild(document.importNode(node, true));
    return svg;
  }

  function iconButton(name, label, onclick, extra) {
    return h('button', { class: 'icon-btn' + (extra ? ' ' + extra : ''), 'aria-label': label, title: label, onclick }, icon(name));
  }

  // ---- Formatting ----------------------------------------------------------------
  function pad(n) { return String(n).padStart(2, '0'); }
  function fmtTime(epoch) {
    if (!epoch) return '';
    const d = new Date(epoch * 1000), now = new Date();
    if (d.toDateString() === now.toDateString()) return pad(d.getHours()) + ':' + pad(d.getMinutes());
    return pad(d.getDate()) + '/' + pad(d.getMonth() + 1);
  }
  function fmtDuration(sec) {
    sec = Math.max(0, Math.floor(sec || 0));
    return pad(Math.floor(sec / 60)) + ':' + pad(sec % 60);
  }
  function nameFor(number) {
    const c = state.contacts.find((x) => x.number === number);
    return c ? c.name : number;
  }
  function initials(text) {
    const t = String(text || '?').trim();
    return (t[0] || '?').toUpperCase();
  }
  function formatNumberInput(value) {
    const digits = String(value || '').replace(/\D/g, '').slice(0, 7);
    return digits.length > 3 ? digits.slice(0, 3) + '-' + digits.slice(3) : digits;
  }
  function errText(code) { return ERRORS[code] || 'Request failed.'; }

  // ---- Server bridge ---------------------------------------------------------------
  async function api(endpoint, payload) {
    if (!isNui) return (window.__cmPhoneMock ? window.__cmPhoneMock(endpoint, payload) : { ok: false, error: 'internal_error' });
    try {
      const response = await fetch(`https://${RES}/api`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ endpoint, payload }),
      });
      return await response.json();
    } catch (e) {
      return { ok: false, error: 'internal_error' };
    }
  }

  // Runs fn once per key until it settles (prevents duplicate submissions).
  async function once(key, fn) {
    if (inflight.has(key)) return;
    inflight.add(key);
    try { return await fn(); } finally { inflight.delete(key); }
  }

  function post(path, body) {
    if (!isNui) {
      // Browser harness: emulate the Lua close handler so ESC/close behaviour can be tested.
      if (path === 'close') window.postMessage({ action: 'close' }, '*');
      return Promise.resolve();
    }
    return fetch(`https://${RES}/${path}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body || {}),
    }).catch(() => {});
  }

  // ---- Toasts / modal ----------------------------------------------------------------
  function toast(message, kind, title) {
    const el = h('div', { class: 'toast ' + (kind || '') }, title ? h('b', { text: title }) : null, h('span', { text: message }));
    toastsEl.appendChild(el);
    while (toastsEl.children.length > 3) toastsEl.removeChild(toastsEl.firstChild);
    setTimeout(() => el.remove(), 3200);
  }
  function fail(code) { toast(code === 'busy_line' ? BUSY_MSG : errText(code), 'error', 'Phone'); }

  let modalCancel = null;
  function closeModal() {
    modalEl.classList.add('hidden');
    modalEl.replaceChildren();
    modalCancel = null;
  }
  // Presentation-only confirmation; the server independently validates every action.
  function confirmModal({ title, message, consequence, confirmLabel, danger, onConfirm }) {
    const confirmBtn = h('button', { class: 'btn cm-confirm-modal__confirm', text: confirmLabel || 'CONFIRM' });
    const cancelBtn = h('button', { class: 'btn cm-confirm-modal__cancel', text: 'CANCEL', onclick: closeModal });
    confirmBtn.addEventListener('click', async () => {
      confirmBtn.disabled = true;
      confirmBtn.textContent = '...';
      try { await onConfirm(); } finally { closeModal(); }
    });
    modalEl.replaceChildren(h('div', { class: 'cm-confirm-modal' + (danger ? ' danger' : ''), role: 'dialog', 'aria-modal': 'true' },
      h('div', { class: 'cm-confirm-modal__title', text: title || 'CONFIRM ACTION' }),
      h('div', { class: 'cm-confirm-modal__message', text: message }),
      consequence ? h('div', { class: 'cm-confirm-modal__consequence', text: consequence }) : null,
      h('div', { class: 'cm-confirm-modal__actions' }, danger ? cancelBtn : confirmBtn, danger ? confirmBtn : cancelBtn)));
    modalEl.classList.remove('hidden');
    modalCancel = closeModal;
    (danger ? cancelBtn : confirmBtn).focus();
  }

  // ---- Navigation ------------------------------------------------------------------
  function pushView(view, params) {
    state.stack.push({ view: state.view, params: state.params });
    state.view = view;
    state.params = params || {};
    render();
  }
  // Navigates after refreshing list data from the server where the target view needs it.
  function nav(view, params) {
    return enterView(view).then(() => pushView(view, params));
  }
  function back() {
    const prev = state.stack.pop();
    if (!prev) { close(); return; }
    state.view = prev.view;
    state.params = prev.params;
    state.thread = null;
    render();
    if (state.view === 'messages') refreshConversations().then(() => { if (state.view === 'messages') render(); });
  }
  function goHome() {
    state.stack = [];
    state.view = 'home';
    state.params = {};
    state.thread = null;
    render();
  }
  function close() { closeModal(); post('close'); }

  function header(title, subtitle, actions) {
    return h('div', { class: 'app-header' },
      iconButton('back', 'Back', back),
      h('h1', {}, title, subtitle ? h('small', { text: subtitle }) : null),
      ...(actions || []));
  }

  // ---- Views -----------------------------------------------------------------------
  function viewHome() {
    const now = new Date();
    const tile = (view, label, ic, cls, badge) => h('button', { class: 'app-tile ' + (cls || ''), onclick: () => nav(view) },
      h('span', { class: 'glyph' }, icon(ic)), h('span', { class: 'label', text: label }),
      badge ? h('span', { class: 'badge', text: badge > 99 ? '99+' : String(badge) }) : null);
    const missed = state.calls.filter((c) => c.status === 'missed' && c.direction === 'incoming').length;
    return [
      h('div', { class: 'home-top' },
        h('div', { class: 'home-time', text: pad(now.getHours()) + ':' + pad(now.getMinutes()) }),
        h('div', { class: 'home-date', text: now.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' }) })),
      state.call && state.callMin ? h('button', { class: 'call-banner', onclick: () => { state.callMin = false; renderCall(); } }, h('b', { text: 'Call with ' + nameFor(state.call.number) }), h('span', { text: 'Return' })) : null,
      h('div', { class: 'app-grid' },
        tile('contacts', 'Contacts', 'contacts'),
        tile('messages', 'Messages', 'message', '', state.unread),
        tile('phone', 'Phone', 'phone', '', missed),
        tile('services', 'Services', 'services'),
        tile('emergency', 'Emergency', 'siren', 'danger'),
        tile('ads', 'Ads', 'ad', 'warn'),
        tile('settings', 'Settings', 'gear')),
    ];
  }

  function contactRow(c) {
    return h('button', { class: 'row', onclick: () => nav('contact', { id: c.id }) },
      h('span', { class: 'avatar', text: initials(c.name) }),
      h('span', { class: 'main' }, h('div', { class: 'title', text: c.name }), h('div', { class: 'sub', text: c.number })),
      c.favourite ? h('span', { class: 'star', text: '★' }) : null);
  }

  function viewContacts() {
    const list = h('div', {});
    const draw = () => {
      const q = state.search.trim().toLowerCase();
      const rows = state.contacts.filter((c) => !q || c.name.toLowerCase().includes(q) || c.number.includes(q));
      list.replaceChildren(...(rows.length ? rows.map(contactRow) : [h('div', { class: 'empty', text: q ? 'No matching contacts.' : 'No contacts yet. Tap + to add one.' })]));
    };
    const search = h('input', { class: 'search', placeholder: 'Search contacts', value: state.search, maxlength: 32 });
    search.addEventListener('input', () => { state.search = search.value; draw(); });
    draw();
    return [header('Contacts', state.contacts.length + ' saved', [iconButton('plus', 'Add contact', () => nav('contactForm', {}), 'accent')]),
      h('div', { class: 'body' }, search, list)];
  }

  function viewContact() {
    const c = state.contacts.find((x) => x.id === state.params.id);
    if (!c) { return [header('Contact'), h('div', { class: 'empty', text: 'Contact not found.' })]; }
    const blocked = state.blocks.includes(c.number);
    return [header(c.name, c.number),
      h('div', { class: 'body' },
        h('div', { class: 'btn-row' },
          h('button', { class: 'btn primary', onclick: () => openThread({ number: c.number }) }, 'Message'),
          h('button', { class: 'btn success', onclick: () => dial(c.number) }, 'Call')),
        h('div', { class: 'btn-row' },
          h('button', { class: 'btn secondary', onclick: () => nav('contactForm', { id: c.id }) }, 'Edit'),
          h('button', { class: 'btn secondary', onclick: () => blocked ? unblock(c.number) : confirmBlock(c.number) }, blocked ? 'Unblock' : 'Block')))];
  }

  function viewContactForm() {
    const existing = state.params.id ? state.contacts.find((x) => x.id === state.params.id) : null;
    const prefill = state.params.number || '';
    const name = h('input', { maxlength: state.limits.nameMax || 32, value: existing ? existing.name : '', placeholder: 'Name' });
    const number = h('input', { maxlength: 8, value: existing ? existing.number : prefill, placeholder: '000-0000', inputmode: 'numeric' });
    number.addEventListener('input', () => { number.value = formatNumberInput(number.value); });
    const fav = h('input', { type: 'checkbox' });
    if (existing && existing.favourite) fav.checked = true;
    const err = h('div', { class: 'err' });
    const save = h('button', { class: 'btn primary full', text: 'Save contact' });
    save.addEventListener('click', () => once('contactSave', async () => {
      err.textContent = '';
      save.disabled = true;
      const res = await api('contactSave', { id: existing ? existing.id : undefined, name: name.value, number: number.value, favourite: fav.checked });
      save.disabled = false;
      if (!res.ok) { err.textContent = errText(res.error); return; }
      state.contacts = res.data.contacts;
      toast('Contact saved.', 'success', 'Contacts');
      back();
    }));
    return [header(existing ? 'Edit contact' : 'New contact'),
      h('div', { class: 'body' },
        h('label', { class: 'field' }, h('span', { text: 'Name' }), name),
        h('label', { class: 'field' }, h('span', { text: 'Number' }), number),
        h('label', { class: 'field' }, h('span', { text: 'Favourite' }), fav),
        err, save,
        existing ? h('div', { class: 'btn-row' }, h('button', { class: 'btn danger', text: 'Delete contact', onclick: () => confirmDeleteContact(existing) })) : null)];
  }

  function confirmDeleteContact(c) {
    confirmModal({
      title: 'CONFIRM DELETE', danger: true, message: `Delete contact ${c.name} (${c.number})?`,
      consequence: 'The saved name is removed. Existing messages stay.', confirmLabel: 'DELETE',
      onConfirm: () => once('contactDelete', async () => {
        const res = await api('contactDelete', c.id);
        if (!res.ok) return fail(res.error);
        state.contacts = res.data.contacts;
        toast('Contact deleted.', 'success', 'Contacts');
        goBackTo('contacts');
      }),
    });
  }

  function goBackTo(view) {
    while (state.stack.length && state.view !== view) {
      const prev = state.stack.pop();
      state.view = prev.view; state.params = prev.params;
    }
    state.thread = null;
    render();
  }

  function confirmBlock(number) {
    confirmModal({
      title: 'CONFIRM BLOCK', danger: true, message: `Block ${nameFor(number)}?`,
      consequence: 'They can no longer message or call you. They are not told.', confirmLabel: 'BLOCK',
      onConfirm: () => once('block', async () => {
        const res = await api('block', number);
        if (!res.ok) return fail(res.error);
        state.blocks = res.data.blocks;
        toast('Number blocked.', 'success', 'Phone');
        render();
      }),
    });
  }
  function unblock(number) {
    return once('block', async () => {
      const res = await api('unblock', number);
      if (!res.ok) return fail(res.error);
      state.blocks = res.data.blocks;
      toast('Number unblocked.', 'success', 'Phone');
      render();
    });
  }

  // Messages -------------------------------------------------------------------------
  function convTitle(c) {
    if (c.kind === 'direct') return nameFor(c.number);
    return c.name || 'Group';
  }

  function viewMessages() {
    const rows = state.conversations.map((c) => h('button', { class: 'row' + (c.unread ? ' unread' : ''), onclick: () => openThread({ conversationId: c.id }) },
      h('span', { class: 'avatar ' + (c.kind === 'group' ? 'group' : c.kind === 'system' ? 'system' : ''), text: c.kind === 'group' ? '#' : initials(convTitle(c)) }),
      h('span', { class: 'main' }, h('div', { class: 'title', text: convTitle(c) }), h('div', { class: 'sub', text: c.preview || '' })),
      h('span', { class: 'meta' }, h('span', { text: fmtTime(c.lastAt) }), c.unread ? h('span', { class: 'dot', text: String(c.unread) }) : null)));
    return [header('Messages', state.unread ? state.unread + ' unread' : 'All caught up', [
      iconButton('users', 'New group', () => nav('groupForm')), iconButton('plus', 'New message', () => nav('newMessage'), 'accent')]),
      h('div', { class: 'body' }, ...(rows.length ? rows : [h('div', { class: 'empty', text: 'No conversations yet.\nTap + to start one.' })]))];
  }

  function viewNewMessage() {
    const number = h('input', { class: 'search', maxlength: 8, placeholder: 'Enter number (000-0000)', inputmode: 'numeric' });
    number.addEventListener('input', () => { number.value = formatNumberInput(number.value); });
    const go = () => { const n = number.value; if (n.length === 8) openThread({ number: n }); else toast(errText('invalid_number'), 'error', 'Messages'); };
    number.addEventListener('keydown', (e) => { if (e.key === 'Enter') go(); });
    const list = state.contacts.map((c) => h('button', { class: 'row', onclick: () => openThread({ number: c.number }) },
      h('span', { class: 'avatar', text: initials(c.name) }),
      h('span', { class: 'main' }, h('div', { class: 'title', text: c.name }), h('div', { class: 'sub', text: c.number }))));
    return [header('New message', null, [iconButton('send', 'Start', go, 'accent')]),
      h('div', { class: 'body' }, number, h('div', { class: 'section-label', text: 'Contacts' }), ...(list.length ? list : [h('div', { class: 'empty', text: 'No contacts saved.' })]))];
  }

  function viewGroupForm() {
    const name = h('input', { maxlength: state.limits.groupNameMax || 32, placeholder: 'Group name' });
    const numbers = h('textarea', { rows: 3, placeholder: '310-1234, 323-5555', maxlength: 200 });
    const err = h('div', { class: 'err' });
    const create = h('button', { class: 'btn primary full', text: 'Create group' });
    create.addEventListener('click', () => once('groupCreate', async () => {
      err.textContent = '';
      create.disabled = true;
      const list = numbers.value.split(/[\s,;]+/).filter(Boolean).map(formatNumberInput);
      const res = await api('groupCreate', { name: name.value, numbers: list });
      create.disabled = false;
      if (!res.ok) { err.textContent = errText(res.error); return; }
      await refreshConversations();
      state.stack.pop();
      state.view = 'messages';
      openThread({ conversationId: res.data.conversationId });
    }));
    return [header('New group'),
      h('div', { class: 'body' },
        h('label', { class: 'field' }, h('span', { text: 'Group name' }), name),
        h('label', { class: 'field' }, h('span', { text: 'Member numbers' }), numbers,
          h('div', { class: 'hint', text: `Up to ${(state.limits.groupMembersMax || 8) - 1} other members.` })),
        err, create)];
  }

  async function refreshConversations() {
    const res = await api('conversations');
    if (res.ok) { state.conversations = res.data.conversations; state.unread = res.data.unread; }
  }

  async function openThread(target) {
    state.stack.push({ view: state.view, params: state.params });
    state.draft = '';
    state.view = 'thread';
    state.params = target;
    state.thread = { messages: [], conversation: null, more: false, loading: true };
    render();
    if (target.conversationId) await loadThread(target.conversationId);
    else {
      // Direct thread by number: reuse an existing conversation when there is one.
      const known = state.conversations.find((c) => c.kind === 'direct' && c.number === target.number);
      if (known) { state.params = { conversationId: known.id }; await loadThread(known.id); }
      else { state.thread = { messages: [], conversation: { kind: 'direct', number: target.number, members: [target.number] }, more: false, loading: false }; render(); }
    }
  }

  async function loadThread(conversationId, before) {
    const res = await api('openConversation', { conversationId, before });
    if (!res.ok) { toast(errText(res.error), 'error', 'Messages'); state.thread = null; back(); return; }
    const t = state.thread || { messages: [] };
    state.thread = {
      conversation: res.data.conversation,
      messages: before ? res.data.messages.concat(t.messages) : res.data.messages,
      more: res.data.more, loading: false,
    };
    state.params = { conversationId };
    if (!before) { const conv = state.conversations.find((c) => c.id === conversationId); if (conv) { state.unread = Math.max(0, state.unread - conv.unread); conv.unread = 0; } }
    render();
  }

  function bubble(m, group) {
    if (m.kind === 'system') return h('div', { class: 'bubble system', text: m.body });
    const cls = 'bubble ' + (m.mine ? 'out' : 'in') + (m.kind === 'location' ? ' loc' : '');
    const kids = [];
    if (group && !m.mine) kids.push(h('span', { class: 'who', text: nameFor(m.from) }));
    if (m.kind === 'location') {
      kids.push(h('span', { text: '📍 ' + ((m.payload && m.payload.label) || 'Shared location') }));
      if (!m.mine && m.payload) kids.push(h('button', { text: 'Set GPS', onclick: () => post('setGps', { x: m.payload.x, y: m.payload.y }) }));
    } else kids.push(h('span', { text: m.body }));
    kids.push(h('span', { class: 'time', text: fmtTime(m.at) }));
    return h('div', { class: cls }, ...kids);
  }

  function viewThread() {
    const t = state.thread;
    const target = state.params;
    if (!t || t.loading) return [header('Messages'), h('div', { class: 'empty', text: 'Loading…' })];
    const conv = t.conversation || {};
    const isGroup = conv.kind === 'group';
    const title = isGroup ? (conv.name || 'Group') : conv.kind === 'system' ? (conv.name || 'City') : nameFor(conv.number || target.number);
    const subtitle = isGroup ? (conv.members.length + 1) + ' members' : conv.kind === 'system' ? 'Notice' : (conv.number || target.number);
    const actions = [];
    if (conv.kind === 'direct') {
      actions.push(iconButton('phone', 'Call', () => dial(conv.number || target.number)));
      if (!state.contacts.some((c) => c.number === (conv.number || target.number))) actions.push(iconButton('plus', 'Save contact', () => nav('contactForm', { number: conv.number || target.number })));
    }
    if (isGroup) actions.push(iconButton('users', 'Group', () => nav('groupInfo', { conversationId: target.conversationId })));
    const thread = h('div', { class: 'thread', id: 'thread' },
      t.more ? h('button', { class: 'more-btn', text: 'Load earlier messages', onclick: () => loadThread(target.conversationId, t.messages[0] && t.messages[0].id) }) : null,
      ...t.messages.map((m) => bubble(m, isGroup)));
    let composer = null;
    if (conv.kind !== 'system') {
      const input = h('input', { maxlength: state.limits.textMax || 500, placeholder: 'Message', autocomplete: 'off' });
      input.value = state.draft;
      input.addEventListener('input', () => { state.draft = input.value; });
      const send = () => once('send', async () => {
        const text = input.value;
        if (!text.trim()) return;
        input.value = '';
        state.draft = '';
        const res = await api('send', target.conversationId ? { conversationId: target.conversationId, text } : { number: target.number, text });
        if (!res.ok) { input.value = text; state.draft = text; return fail(res.error); }
        await afterSend(res.data.conversationId);
      });
      input.addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); });
      composer = h('div', { class: 'composer' }, iconButton('pin', 'Share my location', () => once('send', async () => {
        const res = await api('sendLocation', target.conversationId ? { conversationId: target.conversationId } : { number: target.number });
        if (!res.ok) return fail(res.error);
        await afterSend(res.data.conversationId);
      })), input, iconButton('send', 'Send', send, 'accent'));
      setTimeout(() => input.focus(), 30);
    }
    setTimeout(() => { const el = $('thread'); if (el) el.scrollTop = el.scrollHeight; }, 0);
    return [header(title, subtitle, actions), thread, composer];
  }

  async function afterSend(conversationId) {
    state.params = { conversationId };
    await loadThread(conversationId);
    refreshConversations();
  }

  function viewGroupInfo() {
    const t = state.thread;
    const conv = (t && t.conversation) || {};
    const err = h('div', { class: 'err' });
    const add = h('input', { class: 'search', maxlength: 8, placeholder: 'Add member number', inputmode: 'numeric' });
    add.addEventListener('input', () => { add.value = formatNumberInput(add.value); });
    const members = (conv.members || []).map((n) => h('div', { class: 'row' },
      h('span', { class: 'avatar', text: initials(nameFor(n)) }),
      h('span', { class: 'main' }, h('div', { class: 'title', text: nameFor(n) }), h('div', { class: 'sub', text: n })),
      conv.isOwner ? iconButton('x', 'Remove', () => once('groupRemove', async () => {
        const res = await api('groupRemove', { conversationId: conv.id, number: n });
        if (!res.ok) return fail(res.error);
        await loadThread(conv.id); render();
      })) : null));
    return [header(conv.name || 'Group', (members.length + 1) + ' members'),
      h('div', { class: 'body' },
        conv.isOwner ? h('div', {}, add, h('button', { class: 'btn primary full', text: 'Add member', onclick: () => once('groupAdd', async () => {
          err.textContent = '';
          const res = await api('groupAdd', { conversationId: conv.id, number: add.value });
          if (!res.ok) { err.textContent = errText(res.error); return; }
          await loadThread(conv.id);
        }) }), err) : null,
        h('div', { class: 'section-label', text: 'Members' }), ...members,
        h('div', { class: 'btn-row' }, h('button', { class: 'btn danger', text: 'Leave group', onclick: () => confirmModal({
          title: 'CONFIRM LEAVE', danger: true, message: `Leave ${conv.name || 'this group'}?`, consequence: 'You will no longer see this conversation.', confirmLabel: 'LEAVE',
          onConfirm: () => once('groupLeave', async () => {
            const res = await api('groupLeave', conv.id);
            if (!res.ok) return fail(res.error);
            await refreshConversations();
            goBackTo('messages');
          }) }) })))];
  }

  // Calls ------------------------------------------------------------------------------
  async function dial(number) {
    return once('dial', async () => {
      const res = await api('dial', number);
      if (!res.ok) return fail(res.error === 'busy' ? 'busy_line' : res.error);
    });
  }

  function viewPhone() {
    const input = h('input', { class: 'dial-input', maxlength: 8, value: state.dial, placeholder: '000-0000', inputmode: 'numeric' });
    input.addEventListener('input', () => { state.dial = formatNumberInput(input.value); input.value = state.dial; });
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') dial(state.dial); });
    const tabs = h('div', { class: 'tabs' },
      h('button', { class: 'tab' + (state.tab === 'keypad' ? ' active' : ''), text: 'Keypad', onclick: () => { state.tab = 'keypad'; render(); } }),
      h('button', { class: 'tab' + (state.tab === 'recent' ? ' active' : ''), text: 'Recent', onclick: async () => { state.tab = 'recent'; const res = await api('calls'); if (res.ok) state.calls = res.data.calls; render(); } }));
    let content;
    if (state.tab === 'keypad') {
      const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '⌫'];
      content = h('div', { class: 'body' }, input,
        h('div', { class: 'keypad' }, ...keys.map((k) => h('button', { class: 'key', text: k, onclick: () => {
          if (k === '⌫') state.dial = state.dial.slice(0, -1).replace(/-$/, '');
          else if (/\d/.test(k)) state.dial = formatNumberInput(state.dial + k);
          input.value = state.dial;
        } }))),
        h('button', { class: 'call-btn', text: 'Call', disabled: false, onclick: () => dial(state.dial) }));
    } else {
      const label = { answered: 'Answered', declined: 'Declined', no_answer: 'No answer', missed: 'Missed' };
      const rows = state.calls.map((c) => h('button', { class: 'row', onclick: () => dial(c.number) },
        h('span', { class: 'avatar', text: c.direction === 'outgoing' ? '↗' : '↙' }),
        h('span', { class: 'main' }, h('div', { class: 'title ' + (c.status === 'missed' ? 'call-miss' : ''), text: nameFor(c.number) }),
          h('div', { class: 'sub', text: (c.direction === 'outgoing' ? 'Outgoing' : 'Incoming') + ' · ' + label[c.status] + (c.duration ? ' · ' + fmtDuration(c.duration) : '') })),
        h('span', { class: 'meta', text: fmtTime(c.at) })));
      content = h('div', { class: 'body' }, ...(rows.length ? rows : [h('div', { class: 'empty', text: 'No recent calls.' })]));
    }
    return [header('Phone'), tabs, content];
  }

  function renderCall() {
    const existing = document.querySelector('.call-screen');
    if (existing) existing.remove();
    if (callTimer) { clearInterval(callTimer); callTimer = null; }
    const c = state.call;
    if (!c || state.callMin) return;
    const stateLabel = { dialing: 'Dialing…', ringing: 'Ringing…', incoming: 'Incoming call', active: 'Connected' }[c.state] || '';
    const stateEl = h('div', { class: 'state' + (c.state === 'active' ? ' active' : ''), text: stateLabel });
    const actions = h('div', { class: 'actions' });
    const hang = () => once('hangup', async () => { const res = await api('hangup'); if (!res.ok) fail(res.error); });
    if (c.state === 'incoming') {
      actions.append(
        h('button', { class: 'round red', 'aria-label': 'Decline', onclick: () => once('decline', async () => { const r = await api('decline'); if (!r.ok) fail(r.error); }) }, icon('hang'), 'Decline'),
        h('button', { class: 'round green pulse', 'aria-label': 'Answer', onclick: () => once('answer', async () => { const r = await api('answer'); if (!r.ok) fail(r.error); }) }, icon('answer'), 'Answer'));
    } else {
      actions.append(h('button', { class: 'round red', 'aria-label': 'Hang up', onclick: hang }, icon('hang'), 'End'));
    }
    const screen = h('div', { class: 'call-screen' },
      c.state === 'incoming' ? null : h('button', { class: 'icon-btn', style: 'position:absolute;top:14px;right:14px', 'aria-label': 'Minimise call', title: 'Minimise', onclick: () => { state.callMin = true; renderCall(); render(); } }, icon('x')),
      h('div', { class: 'avatar' + (c.state === 'active' ? '' : ' pulse'), text: initials(nameFor(c.number)) }),
      h('div', { class: 'who', text: nameFor(c.number) }),
      h('div', { class: 'num', text: c.number }),
      stateEl, actions);
    $('phone').appendChild(screen);
    if (c.state === 'active') {
      const tick = () => { stateEl.textContent = 'Connected · ' + fmtDuration((Date.now() - state.activeSince) / 1000); };
      tick();
      callTimer = setInterval(tick, 1000);
    }
  }

  // Emergency ----------------------------------------------------------------------------
  function viewEmergency() {
    const card = (service, title, blurb) => {
      const details = h('textarea', { rows: 2, maxlength: state.limits.detailsMax || 200, placeholder: 'What is happening? (optional)' });
      const send = h('button', { class: 'btn danger full', text: 'Request ' + title });
      send.addEventListener('click', () => confirmModal({
        title: 'SEND EMERGENCY REQUEST', danger: true, message: `Contact ${title} with your current location?`,
        consequence: 'False reports can have consequences. Only use for real emergencies.', confirmLabel: 'SEND',
        onConfirm: () => once('emergency', async () => {
          const res = await api('emergency', { service, details: details.value });
          if (!res.ok) return toast(res.extra || errText(res.error), 'error', 'Emergency');
          toast(res.data.message || 'Request sent.', 'success', 'Emergency');
        }),
      }));
      return h('div', { class: 'emg-card ' + service }, h('h3', { text: title }), h('p', { text: blurb }), details, h('div', { style: 'height:8px' }), send);
    };
    return [header('Emergency', 'Your location is sent with the request'),
      h('div', { class: 'body' }, card('police', 'Police', 'Report a crime or request an officer.'), card('ems', 'EMS', 'Request an ambulance for medical help.'))];
  }

  // Adverts --------------------------------------------------------------------------------
  function viewAds() {
    const rows = state.adverts.map((a) => h('div', { class: 'ad' },
      h('div', { class: 'text', text: a.body }),
      h('div', { class: 'by' }, h('span', { text: nameFor(a.number) + ' · ' + fmtTime(a.at) }),
        h('span', {}, h('button', { class: 'link', text: 'Message', onclick: () => openThread({ number: a.number }) }), ' ',
          h('button', { class: 'link', text: 'Call', onclick: () => dial(a.number) })))));
    return [header('Classifieds', 'City advertisements', [iconButton('plus', 'Post advert', () => nav('adForm'), 'accent')]),
      h('div', { class: 'body' }, ...(rows.length ? rows : [h('div', { class: 'empty', text: 'No active adverts.' })]))];
  }

  function viewAdForm() {
    const fee = state.limits.advertFee || 0;
    const text = h('textarea', { rows: 5, maxlength: state.limits.advertMax || 240, placeholder: 'Write your advert…' });
    const counter = h('div', { class: 'hint', text: '0 / ' + (state.limits.advertMax || 240) });
    text.addEventListener('input', () => { counter.textContent = text.value.length + ' / ' + (state.limits.advertMax || 240); });
    const post = h('button', { class: 'btn primary full', text: fee ? `Post advert · $${fee.toLocaleString()}` : 'Post advert' });
    post.addEventListener('click', () => {
      if (text.value.trim().length < (state.limits.advertMin || 5)) return toast(errText('invalid_message'), 'error', 'Ads');
      confirmModal({
        title: 'CONFIRM POSTING FEE', message: `Post this advert publicly under your number ${state.me}?`,
        consequence: fee ? `$${fee.toLocaleString()} will be charged from your cash or bank.` : null, confirmLabel: 'POST',
        onConfirm: () => once('advertPost', async () => {
          const res = await api('advertPost', text.value);
          if (!res.ok) return toast(res.error === 'cooldown' && res.extra ? `Please wait ${res.extra}s before posting again.` : errText(res.error), 'error', 'Ads');
          state.adverts = res.data.adverts;
          toast('Advert posted.', 'success', 'Ads');
          back();
        }),
      });
    });
    return [header('New advert'), h('div', { class: 'body' }, h('label', { class: 'field' }, h('span', { text: 'Advert text' }), text, counter,
      h('div', { class: 'hint', text: 'Visible to everyone for 48 hours. Your number is shown, not your name.' })), post)];
  }

  // Services (marketplace frontend) -----------------------------------------------------------------------------
  // The phone holds no request: the owner resource does. Everything shown comes from the server on open/refresh or from an
  // owner push, already reduced to a public, player-friendly status. Internal states never reach this file.
  const AVAIL = { available: ['Available', 'avail'], limited: ['Limited', 'limited'], offline: ['Unavailable', 'offline'], soon: ['Coming soon', 'soon'] };
  function pill(text, cls) { return h('span', { class: 'pill ' + cls, text }); }
  function serviceById(id) { return state.services.find((x) => x.id === id); }

  function viewServices() {
    const cards = state.services.map((s) => {
      const meta = AVAIL[s.state] || AVAIL.offline;
      const cur = s.current && !s.current.terminal ? s.current : null;
      return h('button', {
        class: 'svc' + (s.canRequest ? '' : ' off'), 'data-service': s.id,
        onclick: () => (s.canRequest ? pushView('serviceForm', { id: s.id }) : toast(s.state === 'soon' ? 'This service is coming soon.' : 'This service is currently unavailable.', 'info', s.name)),
      },
      h('span', { class: 'glyph' }, icon(s.icon)),
      h('span', { class: 'main' }, h('span', { class: 'title', text: s.name }), h('span', { class: 'sub', text: s.description })),
      cur ? pill(cur.label, cur.tone) : pill(meta[0], meta[1]));
    });
    return [header('Services', 'Request help from city services'),
      h('div', { class: 'body' }, ...(cards.length ? cards : [h('div', { class: 'empty', text: 'No services are registered.' })]))];
  }

  async function refreshService(s) {
    const res = await api('serviceStatus', s.id);
    if (!res.ok) return toast(errText(res.error), 'error', s.name);
    s.current = res.data.status || undefined;
    render();
  }

  function confirmCancelService(s) {
    confirmModal({
      title: 'CANCEL REQUEST', danger: true, message: `Cancel your ${s.name.toLowerCase()} request?`,
      consequence: 'A worker who already accepted it will be told.', confirmLabel: 'CANCEL REQUEST',
      onConfirm: () => once('serviceCancel', async () => {
        const res = await api('serviceCancel', { serviceId: s.id, ref: s.current && s.current.ref });
        if (!res.ok) { toast(errText(res.error), 'error', s.name); await refreshService(s); return; }
        s.current = res.data.status || undefined;
        toast('Request cancelled.', 'success', s.name);
        render();
      }),
    });
  }

  function viewServiceForm() {
    const s = serviceById(state.params.id);
    if (!s) return [header('Service'), h('div', { class: 'body' }, h('div', { class: 'empty', text: 'Service not found.' }))];
    const cur = s.current;
    if (cur && !cur.terminal) {
      const eta = typeof cur.etaSeconds === 'number' ? 'About ' + Math.max(1, Math.round(cur.etaSeconds / 60)) + ' min away' : null;
      return [header(s.name, 'Your request'),
        h('div', { class: 'body' },
          h('div', { class: 'svc-status ' + cur.tone },
            h('div', { class: 'big', text: cur.label }),
            cur.workerLabel ? h('div', { class: 'sub', text: cur.workerLabel }) : null,
            eta ? h('div', { class: 'sub', text: eta }) : null,
            cur.detail ? h('div', { class: 'sub', text: cur.detail }) : null),
          h('div', { class: 'btn-row' },
            h('button', { class: 'btn secondary', text: 'Refresh', onclick: () => once('serviceRefresh', () => refreshService(s)) }),
            cur.canCancel ? h('button', { class: 'btn danger', text: 'Cancel request', onclick: () => confirmCancelService(s) }) : null))];
    }
    const inputs = {};
    const fieldEls = (s.fields || []).map((f) => {
      let control;
      if (f.type === 'enum') {
        control = h('select', {}, f.required ? null : h('option', { value: '', text: 'No preference' }),
          ...(f.options || []).map((o) => h('option', { value: o, text: o.charAt(0).toUpperCase() + o.slice(1) })));
      } else if (f.type === 'waypoint') {
        control = h('input', { type: 'checkbox' });
      } else {
        control = h('textarea', { rows: 2, maxlength: f.max || 120, placeholder: f.hint || '' });
      }
      inputs[f.key] = control;
      const label = f.label + (f.required ? ' *' : '');
      return h('label', { class: 'field' }, h('span', { text: f.type === 'waypoint' ? label : label }), control,
        f.type === 'waypoint' ? h('div', { class: 'hint', text: 'Use my map waypoint. ' + (f.hint || '') }) : null);
    });
    const send = h('button', { class: 'btn primary full', text: 'Request ' + s.name.toLowerCase() });
    send.addEventListener('click', () => {
      const fields = {};
      for (const f of s.fields || []) {
        const el = inputs[f.key];
        if (f.type === 'waypoint') { if (el.checked) fields[f.key] = '@waypoint'; else if (f.required) return toast('Tick “Use my map waypoint” after setting one.', 'error', s.name); }
        else if (el.value.trim() !== '') fields[f.key] = el.value.trim();
        else if (f.required) return toast(errText('missing_field'), 'error', s.name);
      }
      confirmModal({
        title: 'REQUEST ' + s.name.toUpperCase(), message: `Send this ${s.name.toLowerCase()} request from your current location?`,
        consequence: 'Your location is shared with the service for this request only.', confirmLabel: 'REQUEST',
        onConfirm: () => once('serviceRequest', async () => {
          const res = await api('serviceRequest', { serviceId: s.id, fields });
          if (!res.ok) {
            if (res.error === 'already_active' && res.extra) { s.current = res.extra; render(); }
            return toast(errText(res.error), 'error', s.name);
          }
          s.current = res.data.status;
          toast('Request sent.', 'success', s.name);
          render();
        }),
      });
    });
    return [header(s.name, s.category),
      h('div', { class: 'body' },
        cur ? h('div', { class: 'svc-status ' + cur.tone }, h('div', { class: 'big', text: cur.label }), cur.detail ? h('div', { class: 'sub', text: cur.detail }) : null) : null,
        h('div', { class: 'hint', text: s.description }), h('div', { style: 'height:8px' }), ...fieldEls, send)];
  }

  // Event-driven status from the owner (already sanitised server-side). No polling.
  function onServiceStatus(data) {
    if (!data || typeof data.service !== 'string' || !data.status) return;
    const s = serviceById(data.service);
    if (s) s.current = data.status;
    toast(data.message || data.status.label, 'info', 'Services');
    if (state.view === 'services' || state.view === 'serviceForm') render();
  }

  // Settings ---------------------------------------------------------------------------------
  function viewSettings() {
    const number = h('input', { class: 'search', maxlength: 8, placeholder: 'Block a number', inputmode: 'numeric' });
    number.addEventListener('input', () => { number.value = formatNumberInput(number.value); });
    const rows = state.blocks.map((n) => h('div', { class: 'row' },
      h('span', { class: 'avatar', text: '⦸' }), h('span', { class: 'main' }, h('div', { class: 'title', text: nameFor(n) }), h('div', { class: 'sub', text: n })),
      h('button', { class: 'btn secondary', text: 'Unblock', onclick: () => unblock(n) })));
    return [header('Settings'),
      h('div', { class: 'body' },
        h('div', { class: 'section-label', text: 'My number' }), h('div', { class: 'row' }, h('span', { class: 'main' }, h('div', { class: 'title', text: state.me || '' }), h('div', { class: 'sub', text: 'Tied to your character' }))),
        h('div', { class: 'section-label', text: 'Blocked numbers' }), number,
        h('button', { class: 'btn secondary full', text: 'Block number', onclick: () => number.value.length === 8 ? confirmBlock(number.value) : toast(errText('invalid_number'), 'error', 'Phone') }),
        h('div', { style: 'height:10px' }), ...(rows.length ? rows : [h('div', { class: 'empty', text: 'No blocked numbers.' })]))];
  }

  // ---- Render ---------------------------------------------------------------------------------
  const VIEWS = {
    home: viewHome, contacts: viewContacts, contact: viewContact, contactForm: viewContactForm,
    messages: viewMessages, newMessage: viewNewMessage, groupForm: viewGroupForm, thread: viewThread, groupInfo: viewGroupInfo,
    phone: viewPhone, emergency: viewEmergency, ads: viewAds, adForm: viewAdForm, settings: viewSettings,
    services: viewServices, serviceForm: viewServiceForm,
  };

  function render() {
    const build = VIEWS[state.view] || viewHome;
    const parts = build().filter(Boolean);
    // Views return [header?, body...]; wrap non-scroll parts as flex children.
    screenEl.replaceChildren(...parts);
    renderCall();
  }

  async function enterView(view) {
    if (view === 'messages') await refreshConversations();
    if (view === 'ads') { const res = await api('adverts'); if (res.ok) state.adverts = res.data.adverts; }
    if (view === 'phone') { const res = await api('calls'); if (res.ok) state.calls = res.data.calls; }
    if (view === 'services') { const res = await api('services'); if (res.ok) state.services = res.data; }
  }

  // ---- Open / events ------------------------------------------------------------------------------
  function open(data) {
    Object.assign(state, {
      me: data.number, contacts: data.contacts || [], conversations: data.conversations || [], calls: data.calls || [],
      blocks: data.blocks || [], limits: data.limits || {}, unread: data.unread || 0, call: data.call || null,
      view: 'home', stack: [], params: {}, thread: null, search: '', dial: '', tab: 'keypad', services: [],
    });
    if (state.call && state.call.state === 'active') state.activeSince = Date.now();
    state.callMin = false;
    $('myNumber').textContent = state.me || '';
    root.classList.remove('hidden');
    render();
  }

  function hide() {
    root.classList.add('hidden');
    closeModal();
    if (callTimer) { clearInterval(callTimer); callTimer = null; }
    const cs = document.querySelector('.call-screen');
    if (cs) cs.remove();
    toastsEl.replaceChildren();
    inflight.clear();
  }

  function onCall(data) {
    if (!data) return;
    if (data.state === 'ended') {
      const reasons = { declined: 'Call declined.', timeout: 'No answer.', hangup: 'Call ended.', cancelled: 'Call cancelled.', disconnect: 'Call ended.', shutdown: 'Call ended.', max_duration: 'Call ended.' };
      state.call = null;
      state.callMin = false;
      toast(reasons[data.reason] || 'Call ended.', 'info', 'Phone');
      renderCall();
      api('calls').then((r) => { if (r.ok) state.calls = r.data.calls; if (state.view === 'phone' || state.view === 'home') render(); });
      return;
    }
    if (data.state === 'active') state.activeSince = Date.now();
    if (data.state === 'incoming' || data.state === 'dialing') state.callMin = false;
    state.call = data;
    renderCall();
  }

  async function onMessage(data) {
    if (!data) return;
    const viewing = state.view === 'thread' && state.params && state.params.conversationId === data.conversationId;
    if (viewing) { await loadThread(data.conversationId); api('markRead', data.conversationId); }
    else {
      toast(data.kind === 'location' ? 'Shared a location' : (data.preview || 'New message'), 'info', data.group || nameFor(data.from));
      await refreshConversations();
      if (state.view === 'messages' || state.view === 'home') render();
    }
  }

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'open') open(msg.data || {});
    else if (msg.action === 'close') hide();
    else if (msg.action === 'call') onCall(msg.data);
    else if (msg.action === 'message') onMessage(msg.data);
    else if (msg.action === 'serviceStatus') onServiceStatus(msg.data);
    else if (msg.action === 'toast' && msg.data) toast(msg.data.message, 'info', msg.data.title);
  });

  window.addEventListener('keydown', (e) => {
    if (root.classList.contains('hidden')) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      if (modalCancel) closeModal();
      else if (state.stack.length) back();
      else close();
    }
  });

  $('homeBtn').addEventListener('click', goHome);
  const tickClock = () => { const el = $('clock'); if (el) { const n = new Date(); el.textContent = pad(n.getHours()) + ':' + pad(n.getMinutes()); } };
  tickClock();
  setInterval(tickClock, 1000);

  // Browser-only development harness (never loaded inside FiveM).
  if (!isNui) {
    const s = document.createElement('script');
    s.src = 'dev-mock.js';
    s.onload = () => { if (window.__cmPhoneBoot) window.__cmPhoneBoot(open); };
    document.head.appendChild(s);
  }
})();
