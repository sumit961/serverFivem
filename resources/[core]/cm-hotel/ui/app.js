const app = document.getElementById('app');
const content = document.getElementById('content');
const toast = document.getElementById('toast');
const confirmBox = document.getElementById('confirm');
const state = { data: null, token: null, focused: true };

function post(name, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data)
  }).catch(() => null);
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>'"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[ch]));
}

function point(stateKey) {
  const setup = state.data?.setup || {};
  if (stateKey === 'firstSpawn') return setup.firstSpawn;
  if (stateKey === 'receptionist') return setup.receptionist?.coords;
  if (stateKey === 'rentalNpc') return setup.rental?.coords;
  if (stateKey === 'rentalVehicleSpawn') return setup.rental?.vehicleSpawn;
  if (['license', 'jobCentre', 'hospital'].includes(stateKey)) return setup.help?.[stateKey];
  if (stateKey === 'blip') return setup.blip?.coords;
  const floorId = stateKey.includes('Rooms') ? 'rooms' : stateKey.includes('Lobby') ? 'lobby' : null;
  if (!floorId) return null;
  const floor = (setup.lifts?.main?.floors || []).find(item => item.id === floorId);
  return stateKey.includes('Interaction') ? floor?.interaction : (floor?.arrival || floor?.destination);
}

function assignPoint(stateKey, value) {
  const setup = state.data?.setup;
  if (!setup) return;
  if (stateKey === 'firstSpawn') { setup.firstSpawn = value; return; }
  if (stateKey === 'receptionist') { setup.receptionist = setup.receptionist || {}; setup.receptionist.coords = value; return; }
  if (stateKey === 'rentalNpc') { setup.rental = setup.rental || {}; setup.rental.coords = value; return; }
  if (stateKey === 'rentalVehicleSpawn') { setup.rental = setup.rental || {}; setup.rental.vehicleSpawn = value; return; }
  if (['license', 'jobCentre', 'hospital'].includes(stateKey)) { setup.help = setup.help || {}; setup.help[stateKey] = value; return; }
  if (stateKey === 'blip') { setup.blip = setup.blip || {}; setup.blip.coords = value; return; }
  const floorId = stateKey.includes('Rooms') ? 'rooms' : stateKey.includes('Lobby') ? 'lobby' : null;
  const floor = (setup.lifts?.main?.floors || []).find(item => item.id === floorId);
  if (!floor) return;
  if (stateKey.includes('Interaction')) floor.interaction = value;
  else floor.arrival = floor.destination = value;
}

function formatPoint(value) {
  if (!value || value.x === undefined || value.y === undefined || value.z === undefined) return '<span>NOT SET</span>';
  const base = `${Number(value.x).toFixed(4)}, ${Number(value.y).toFixed(4)}, ${Number(value.z).toFixed(4)}`;
  return `<span class="set">${base}${value.w === undefined ? '' : ` · H: ${Number(value.w).toFixed(2)}`}</span>`;
}

function statusPill(label, ready) { return `<span class="status-pill ${ready ? 'ready' : ''}">${label} ${ready ? 'READY' : 'MISSING'}</span>`; }

function button(label, action, attrs = '', klass = 'button-small button-secondary') {
  return `<button class="button ${klass}" data-action="${action}" ${attrs}>${label}</button>`;
}

function nudge(pointId, label, delta) {
  return `<button class="button button-small button-secondary" data-action="nudge" data-point="${pointId}" data-dx="${delta.dx || 0}" data-dy="${delta.dy || 0}" data-dz="${delta.dz || 0}" data-dw="${delta.dw || 0}">${label}</button>`;
}

function pointRow(id, label, options = {}) {
  const value = point(id);
  const nudgeControls = options.nudge === false ? '' : `<div class="nudge">${nudge(id, 'X−', { dx: -.05 })}${nudge(id, 'X+', { dx: .05 })}${nudge(id, 'Y−', { dy: -.05 })}${nudge(id, 'Y+', { dy: .05 })}${nudge(id, 'Z−', { dz: -.05 })}${nudge(id, 'Z+', { dz: .05 })}${nudge(id, 'H−', { dw: -1 })}${nudge(id, 'H+', { dw: 1 })}</div>`;
  return `<div class="point-row"><div><div class="point-name">${label}</div><div class="point-value">${formatPoint(value)}</div>${nudgeControls}</div><div class="point-actions">${button('SET TO MY POSITION', 'capture', `data-point="${id}"`, 'button-small button-primary')}${button('SAVE', 'save', `data-point="${id}"`)}${options.test ? button('TEST WAYPOINT', 'test-waypoint', `data-point="${id}"`) : ''}</div></div>`;
}

function npcBlock(kind, label, pointId, definition) {
  const model = definition?.model || '';
  return `<div class="section"><div class="section-title"><span>${label}</span><span class="section-subtitle">${point(pointId) ? 'POSITION SET' : 'POSITION MISSING'}</span></div>
    ${pointRow(pointId, `${label} POSITION`)}
    <div class="model-row"><label>NPC MODEL</label><input data-model-kind="${kind}" value="${escapeHtml(model)}" placeholder="e.g. s_m_m_highsec_01" />${button('SAVE MODEL', 'save-model', `data-kind="${kind}"`)}${button('SPAWN PREVIEW', 'preview-npc', `data-kind="${kind}"`)}</div></div>`;
}

function renderStatus() {
  const s = state.data?.status || {};
  const items = [['SPAWN', 'firstSpawn'], ['RECEPTION', 'receptionist'], ['RENTAL', 'rentalNpc'], ['LIFT', 'liftRooms'], ['HELP', 'license']];
  document.getElementById('statusSummary').innerHTML = items.map(([label, key]) => statusPill(label, s[key] === true)).join('');
}

function render() {
  if (!state.data) return;
  renderStatus();
  const setup = state.data.setup || {};
  const rentalModels = state.data.rentalModels || [];
  content.innerHTML = `
    <section class="section"><div class="section-title"><span>CORE HOTEL POINTS</span><span class="section-subtitle">SAVE EACH POINT INDEPENDENTLY</span></div>
      ${pointRow('firstSpawn', 'FIRST SPAWN')}
      ${pointRow('rentalVehicleSpawn', 'RENTAL VEHICLE SPAWN')}
      <div class="model-row"><label>RENTAL PREVIEW MODEL</label><select id="rentalModel"><option value="">NO CONFIGURED MODEL</option>${rentalModels.map(item => `<option value="${escapeHtml(item.id)}">${escapeHtml(item.label)} · ${escapeHtml(item.model)}</option>`).join('')}</select>${button('PREVIEW VEHICLE', 'preview-vehicle')}</div>
    </section>
    ${npcBlock('receptionist', 'RECEPTIONIST NPC', 'receptionist', setup.receptionist)}
    ${npcBlock('rental', 'RENTAL NPC', 'rentalNpc', setup.rental)}
    <section class="section"><div class="section-title"><span>HOTEL LIFT ENDPOINTS</span><span class="section-subtitle">CM-LIFT PRODUCTION TESTS</span></div>
      ${pointRow('liftRoomsInteraction', 'ROOMS FLOOR · INTERACTION')}
      ${pointRow('liftRoomsArrival', 'ROOMS FLOOR · ARRIVAL')}
      ${pointRow('liftLobbyInteraction', 'LOBBY FLOOR · INTERACTION')}
      ${pointRow('liftLobbyArrival', 'LOBBY FLOOR · ARRIVAL')}
      <div class="point-actions">${button('TEST ROOMS → LOBBY', 'test-lift', 'data-direction="roomsToLobby"', 'button-small button-primary')}${button('TEST LOBBY → ROOMS', 'test-lift', 'data-direction="lobbyToRooms"', 'button-small button-primary')}</div>
    </section>
    <section class="section"><div class="section-title"><span>HELP LOCATIONS</span><span class="section-subtitle">WAYPOINTS ONLY</span></div>
      ${pointRow('license', 'DRIVING LICENCE CENTRE', { test: true, nudge: false })}
      ${pointRow('jobCentre', 'JOB CENTRE', { test: true, nudge: false })}
      ${pointRow('hospital', 'HOSPITAL', { test: true, nudge: false })}
    </section>
    <section class="section"><div class="section-title"><span>HOTEL BLIP</span><span class="section-subtitle">SPRITE / COLOUR / SCALE STAY IN CONFIG</span></div>
      ${pointRow('blip', 'BLIP LOCATION', { nudge: false })}
    </section>`;
}

function setToast(message, kind = 'info') {
  toast.textContent = message || '';
  toast.className = `toast ${kind === 'error' ? 'error' : ''}`;
  clearTimeout(setToast.timer); setToast.timer = setTimeout(() => { toast.textContent = ''; }, 3500);
}

function setVisible(visible) { app.classList.toggle('hidden', !visible); }

window.addEventListener('message', event => {
  const msg = event.data || {};
  if (msg.action === 'open') { state.data = msg.data; state.token = msg.token; setVisible(true); render(); }
  if (msg.action === 'data') { state.data = msg.data; render(); }
  if (msg.action === 'pointUpdated') { assignPoint(msg.point, msg.coords); render(); }
  if (msg.action === 'focus') { state.focused = msg.active === true; document.getElementById('focusHint').textContent = state.focused ? 'Editor focus active. WALK MODE lets you move through the MLO.' : 'Walk mode active: press F7 to return to the editor.'; document.getElementById('walkBtn').textContent = state.focused ? 'WALK MODE' : 'RETURN TO UI'; }
  if (msg.action === 'toast') setToast(msg.message, msg.kind);
  if (msg.action === 'close') { setVisible(false); confirmBox.classList.add('hidden'); }
});

document.addEventListener('click', event => {
  const target = event.target.closest('[data-action]');
  if (!target) return;
  const action = target.dataset.action;
  if (action === 'capture') post('capturePosition', { point: target.dataset.point });
  if (action === 'save') post('save', { point: target.dataset.point });
  if (action === 'nudge') post('nudge', { point: target.dataset.point, dx: target.dataset.dx, dy: target.dataset.dy, dz: target.dataset.dz, dw: target.dataset.dw });
  if (action === 'test-waypoint') post('testWaypoint', { point: target.dataset.point });
  if (action === 'test-lift') post('testLift', { direction: target.dataset.direction });
  if (action === 'preview-npc') post('previewNpc', { kind: target.dataset.kind });
  if (action === 'preview-vehicle') post('previewVehicle', { optionId: document.getElementById('rentalModel')?.value || '' });
  if (action === 'save-model') post('saveModel', { kind: target.dataset.kind, model: document.querySelector(`[data-model-kind="${target.dataset.kind}"]`)?.value || '' });
});

document.getElementById('walkBtn').addEventListener('click', () => post('setFocus', { active: !state.focused }));
document.getElementById('closeBtn').addEventListener('click', () => post('close'));
document.getElementById('resetBtn').addEventListener('click', () => confirmBox.classList.remove('hidden'));
document.getElementById('resetCancel').addEventListener('click', () => confirmBox.classList.add('hidden'));
document.getElementById('resetConfirm').addEventListener('click', () => { confirmBox.classList.add('hidden'); post('reset'); });
document.addEventListener('keydown', event => { if (event.key === 'Escape') { if (!confirmBox.classList.contains('hidden')) confirmBox.classList.add('hidden'); else post('close'); } });
