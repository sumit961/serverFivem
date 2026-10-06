/* Browser-only harness: loaded by app.js when GetParentResourceName is undefined (i.e. outside FiveM).
   Simulates the server callbacks so the NUI can be exercised in a plain browser / headless QA.
   It is never reachable inside FiveM (app.js only injects it when not running as NUI). */
(() => {
  'use strict';
  const now = () => Math.floor(Date.now() / 1000);
  const db = {
    me: '323-5550',
    contacts: [{ id: 1, number: '310-1111', name: 'Alex Morgan', favourite: true }, { id: 2, number: '424-2222', name: 'Taxi Office', favourite: false }],
    blocks: [],
    convs: [
      { id: 1, kind: 'direct', name: null, number: '310-1111', lastAt: now() - 300, unread: 2, preview: 'Are you coming tonight?', lastSender: '310-1111' },
      { id: 2, kind: 'group', name: 'Crew', number: null, lastAt: now() - 3600, unread: 0, preview: 'See you at 8', lastSender: '424-2222' },
    ],
    messages: {
      1: [
        { id: 1, from: '310-1111', mine: false, kind: 'text', body: 'Hey <b>there</b>', at: now() - 900 },
        { id: 2, from: '323-5550', mine: true, kind: 'text', body: 'Hi!', at: now() - 800 },
        { id: 3, from: '310-1111', mine: false, kind: 'location', body: '', payload: { x: 120.5, y: -220.1, label: 'Meet here' }, at: now() - 400 },
        { id: 4, from: '310-1111', mine: false, kind: 'text', body: 'Are you coming tonight?', at: now() - 300 },
      ],
      2: [
        { id: 5, from: 'system', mine: false, kind: 'system', body: '310-1111 created the group', at: now() - 7200 },
        { id: 6, from: '424-2222', mine: false, kind: 'text', body: 'See you at 8', at: now() - 3600 },
      ],
    },
    calls: [
      { id: 1, direction: 'incoming', number: '310-1111', status: 'missed', at: now() - 5000, duration: 0 },
      { id: 2, direction: 'outgoing', number: '424-2222', status: 'answered', at: now() - 9000, duration: 75 },
    ],
    adverts: [{ id: 1, number: '424-2222', body: 'LS Taxi is hiring drivers. Call the office!', at: now() - 1200 }],
    call: null,
    // Service marketplace mock: mirrors the server's PUBLIC shapes only (a state key + player-friendly label/tone).
    svcStates: {
      searching: { label: 'Looking for a worker', tone: 'wait', terminal: false },
      assigned: { label: 'Worker assigned', tone: 'good', terminal: false },
      enroute: { label: 'Worker on the way', tone: 'good', terminal: false },
      active: { label: 'Service in progress', tone: 'active', terminal: false },
      completed: { label: 'Completed', tone: 'good', terminal: true },
      fallback_completed: { label: 'Completed automatically', tone: 'good', terminal: true },
      cancelled: { label: 'Cancelled', tone: 'bad', terminal: true },
    },
    services: [
      { id: 'taxi', name: 'Taxi', icon: 'taxi', category: 'Transport', description: 'Request a taxi to your current location.', state: 'available', canRequest: true,
        fields: [{ key: 'destination', label: 'Destination', type: 'waypoint', required: false, hint: 'Optional. Set a map waypoint first.' }, { key: 'details', label: 'Note for the driver', type: 'text', max: 120, required: false }] },
      { id: 'mechanic', name: 'Mechanic', icon: 'wrench', category: 'Vehicle', description: 'Roadside repair and vehicle service.', state: 'soon', canRequest: false, fields: [] },
      { id: 'courier', name: 'Courier', icon: 'box', category: 'Delivery', description: 'Send a parcel across the city.', state: 'offline', reason: 'provider_unavailable', canRequest: false, fields: [] },
    ],
  };
  const svcStatus = (key, extra) => Object.assign({ state: key, ref: 'TX-1', canCancel: !db.svcStates[key].terminal && key !== 'active' }, db.svcStates[key], extra || {});
  const ok = (data) => ({ ok: true, data });
  const bad = (error) => ({ ok: false, error });
  const emit = (action, data) => window.postMessage({ action, data }, '*');
  const norm = (n) => { const d = String(n || '').replace(/\D/g, ''); return d.length === 7 ? d.slice(0, 3) + '-' + d.slice(3) : null; };

  window.__cmPhoneMock = async (endpoint, p) => {
    await new Promise((r) => setTimeout(r, 40));
    switch (endpoint) {
      case 'contactSave': {
        const n = norm(p.number);
        if (!n) return bad('invalid_number');
        if (!String(p.name || '').trim()) return bad('invalid_name');
        if (p.id) {
          const c = db.contacts.find((x) => x.id === p.id);
          if (!c) return bad('not_found');
          Object.assign(c, { number: n, name: p.name, favourite: !!p.favourite });
        } else {
          if (db.contacts.some((x) => x.number === n)) return bad('duplicate_number');
          db.contacts.push({ id: Date.now(), number: n, name: p.name, favourite: !!p.favourite });
        }
        return ok({ contacts: db.contacts.slice() });
      }
      case 'contactDelete': db.contacts = db.contacts.filter((c) => c.id !== p); return ok({ contacts: db.contacts.slice() });
      case 'block': db.blocks.push(p); return ok({ blocks: db.blocks.slice() });
      case 'unblock': db.blocks = db.blocks.filter((n) => n !== p); return ok({ blocks: db.blocks.slice() });
      case 'conversations': return ok({ conversations: db.convs.slice(), unread: db.convs.reduce((a, c) => a + c.unread, 0) });
      case 'openConversation': {
        const conv = db.convs.find((c) => c.id === p.conversationId);
        if (!conv) return bad('not_found');
        conv.unread = 0;
        return ok({
          conversation: { id: conv.id, kind: conv.kind, name: conv.name, number: conv.number, isOwner: conv.kind === 'group', members: conv.kind === 'group' ? ['310-1111', '424-2222'] : [conv.number] },
          messages: db.messages[conv.id] || [], more: false,
        });
      }
      case 'markRead': return ok({ unread: 0 });
      case 'send': case 'sendLocation': {
        let conv = p.conversationId ? db.convs.find((c) => c.id === p.conversationId) : db.convs.find((c) => c.number === norm(p.number));
        if (!conv) {
          const n = norm(p.number);
          if (!n) return bad('invalid_recipient');
          conv = { id: Date.now(), kind: 'direct', number: n, lastAt: now(), unread: 0, preview: '' };
          db.convs.unshift(conv);
          db.messages[conv.id] = [];
        }
        const body = endpoint === 'send' ? String(p.text || '') : '';
        if (endpoint === 'send' && !body.trim()) return bad('invalid_message');
        db.messages[conv.id].push({ id: Date.now(), from: db.me, mine: true, kind: endpoint === 'send' ? 'text' : 'location', body, payload: endpoint === 'send' ? null : { x: 1, y: 2, label: 'Shared location' }, at: now() });
        conv.preview = endpoint === 'send' ? body : 'Shared a location';
        conv.lastAt = now();
        return ok({ conversationId: conv.id, id: Date.now() });
      }
      case 'groupCreate': {
        const id = Date.now();
        db.convs.unshift({ id, kind: 'group', name: p.name, number: null, lastAt: now(), unread: 0, preview: '' });
        db.messages[id] = [];
        return ok({ conversationId: id });
      }
      case 'groupAdd': case 'groupRemove': return ok({});
      case 'groupLeave': db.convs = db.convs.filter((c) => c.id !== p); return ok({});
      case 'dial': {
        const n = norm(p);
        if (!n) return bad('invalid_number');
        if (n === db.me) return bad('invalid_target');
        if (n === '999-9999') return bad('unavailable');
        db.call = { state: 'dialing', role: 'caller', number: n };
        emit('call', db.call);
        setTimeout(() => { db.call = { state: 'ringing', role: 'caller', number: n }; emit('call', db.call); }, 300);
        setTimeout(() => { if (db.call && db.call.state === 'ringing') { db.call = { state: 'active', role: 'caller', number: n }; emit('call', db.call); } }, 1500);
        return ok({ state: 'ringing' });
      }
      case 'answer': db.call = Object.assign({}, db.call, { state: 'active' }); emit('call', db.call); return ok({});
      case 'decline': case 'hangup': {
        const c = db.call;
        db.call = null;
        emit('call', { state: 'ended', role: c && c.role, number: c && c.number, reason: 'hangup' });
        return ok({});
      }
      case 'calls': return ok({ calls: db.calls });
      case 'adverts': return ok({ adverts: db.adverts });
      case 'advertPost': {
        if (String(p).trim().length < 5) return bad('invalid_message');
        db.adverts.unshift({ id: Date.now(), number: db.me, body: String(p), at: now() });
        return ok({ adverts: db.adverts, fee: 1500 });
      }
      case 'emergency': return ok({ message: 'Dispatch received your request.' });
      case 'services': return ok(db.services.map((x) => Object.assign({}, x)));
      case 'serviceStatus': { const x = db.services.find((y) => y.id === p); return x ? ok({ status: x.current || null }) : bad('invalid_service'); }
      case 'serviceRequest': {
        const x = db.services.find((y) => y.id === (p && p.serviceId));
        if (!x) return bad('invalid_service');
        if (!x.canRequest) return bad('service_unavailable');
        if (x.current && !x.current.terminal) return { ok: false, error: 'already_active', extra: x.current };
        if (p.fields && p.fields.details === 'FAIL') return bad('service_failed');
        window.__cmPhoneMockLastServiceRequest = p;
        x.current = svcStatus('searching');
        return ok({ status: x.current });
      }
      case 'serviceCancel': {
        const x = db.services.find((y) => y.id === (p && p.serviceId));
        if (!x || !x.current || x.current.ref !== p.ref) return bad('not_found');
        if (!x.current.canCancel) return bad('cancel_not_allowed');
        x.current = svcStatus('cancelled', { ref: p.ref });
        return ok({ status: x.current });
      }
      default: return bad('invalid_request');
    }
  };

  window.__cmPhoneBoot = (open) => {
    open({
      number: db.me, contacts: db.contacts.slice(), conversations: db.convs.slice(), calls: db.calls, blocks: [], unread: 2, call: null,
      limits: { textMax: 500, nameMax: 32, groupNameMax: 32, groupMembersMax: 8, advertMax: 240, advertMin: 5, advertFee: 1500, advertCooldown: 300, detailsMax: 200 },
    });
    window.__cmPhoneMockIncoming = () => { db.call = { state: 'incoming', role: 'callee', number: '310-1111' }; emit('call', db.call); };
    // Simulates an owner push / change of the taxi request state (what the server sends after sanitising).
    window.__cmPhoneMockSetService = (key, extra) => {
      const taxi = db.services.find((y) => y.id === 'taxi');
      taxi.current = svcStatus(key, extra);
      emit('serviceStatus', { service: 'taxi', status: taxi.current, message: 'Taxi: ' + taxi.current.label });
    };
    window.__cmPhoneMockMessage = () => emit('message', { conversationId: 1, id: 99, from: '310-1111', kind: 'text', preview: 'Ping!' });
  };
})();
