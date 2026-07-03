let vehicle = null;
let featuresOpen = false;
let infoOpen = false;
let pickerOpen = false;
let pickerMode = null;
const $ = (id) => document.getElementById(id);

const actions = [
  { id: 1, key: 'info', icon: '🚗', title: 'VIEW TRANSPORT INFORMATION', mode: 'always' },
  { id: 2, key: 'features', icon: '🏁', title: 'MANAGE DRIFT SETTINGS', mode: 'outside' },
  { id: 3, key: 'giveKey', icon: '🔑', title: 'GIVE VEHICLE KEY', mode: 'outside' },
  { id: 4, key: 'repair', icon: '🔧', title: 'TRANSPORTATION REPAIR', mode: 'outside' },
  { id: 5, key: 'refuel', icon: '⛽', title: 'REFUEL THE VEHICLE', mode: 'outside' },
  { id: 6, key: 'charge', icon: '⚡', title: 'CHARGE TRANSPORT', mode: 'outside' },
  { id: 7, key: 'trunk', icon: '🚙', title: 'OPEN / CLOSE TRUNK', mode: 'always' },
  { id: 8, key: 'enterTrunk', icon: '📦', title: 'GET IN THE TRUNK', mode: 'outside' },
  { id: 9, key: 'getOutTrunk', icon: '⬆', title: 'GET PLAYER OUT OF THE TRUNK', mode: 'always' },
  { id: 10, key: 'passengers', icon: '👥', title: 'GET PASSENGER OUT OF CAR', mode: 'inside' }
];

function post(name, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  }).then(r => r.json().catch(() => ({}))).catch(() => ({}));
}
function setText(id, value) { const el = $(id); if (el) el.textContent = value ?? ''; }
function showToast(message, type = 'info') {
  const t = $('toast');
  if (!t) return;
  t.textContent = message || '';
  t.className = `toast ${type || 'info'}`;
  t.classList.remove('hidden');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => t.classList.add('hidden'), 2500);
}
function formatMoney(value) { return `$${Math.floor(Number(value) || 0).toLocaleString('en-US')}`; }

function hidePicker() {
  pickerOpen = false;
  pickerMode = null;
  $('playerPicker')?.classList.add('hidden');
}
function backToMenu() {
  hidePicker();
  infoOpen = false;
  featuresOpen = false;
  $('featuresPanel')?.classList.add('hidden');
  $('vehicleInfoScreen')?.classList.add('hidden');
  if (vehicle) {
    renderMenuActions();
    $('vehicleMenu')?.classList.remove('hidden');
  }
}
function closeAll() {
  $('vehicleMenu')?.classList.add('hidden');
  $('vehicleInfoScreen')?.classList.add('hidden');
  $('featuresPanel')?.classList.add('hidden');
  hidePicker();
  featuresOpen = false;
  infoOpen = false;
  post('close');
}

document.querySelectorAll('[data-close]').forEach(btn => btn.addEventListener('click', closeAll));
$('infoClose')?.addEventListener('click', closeAll);
$('infoBack')?.addEventListener('click', closeAll);
$('pickerBack')?.addEventListener('click', backToMenu);
$('pickerClose')?.addEventListener('click', closeAll);

document.addEventListener('keydown', (e) => {
  const key = String(e.key || '').toLowerCase();
  if (key === 'escape' || key === 'backspace') {
    if (infoOpen) closeAll();
    else if (pickerOpen) backToMenu();
    else closeAll();
  }
});

document.addEventListener('click', (e) => {
  const playerBtn = e.target.closest('[data-player-id]');
  if (playerBtn) { selectPickerPlayer(Number(playerBtn.dataset.playerId)); return; }
  const btn = e.target.closest('[data-action]');
  if (!btn) return;
  const action = btn.dataset.action;
  if (btn.classList.contains('disabled')) {
    const reason = disabledReason(action);
    if (reason) showToast(reason, 'error');
    return;
  }
  runAction(action);
});

function ctx() { return vehicle?.context || {}; }
function hasAccess() { return vehicle?.access === true; }
function isOwner() { return vehicle?.owner === true; }
function isLocked() { return vehicle?.locked === true || vehicle?.locked === 1; }
function inVehicle() { return ctx().inVehicle === true; }
function isDriver() { return ctx().isDriver === true; }
function plateText() { return vehicle?.plate || ctx().plate || 'NO PLATE'; }
function vehicleNetId() { return vehicle?.netId || ctx().netId; }

function actionVisible(action) {
  if (!action) return false;
  const inside = inVehicle();
  const slots = Number(vehicle?.trunkSlots || 0);
  if (action.mode === 'inside' && !inside) return false;
  if (action.mode === 'outside' && inside) return false;
  if ((action.key === 'trunk' || action.key === 'enterTrunk') && slots <= 0) return false;
  if (inside && ['repair','refuel','charge','features','giveKey','enterTrunk'].includes(action.key)) return false;
  return true;
}
function actionDisabled(key) {
  const locked = isLocked();
  const trunkSlots = Number(vehicle?.trunkSlots || 0);
  if (key === 'info') return false;
  if (key === 'features') return !hasAccess();
  if (key === 'giveKey') return !isOwner();
  if (key === 'trunk') return !hasAccess() || locked || trunkSlots <= 0;
  if (key === 'enterTrunk') return locked || trunkSlots <= 0;
  if (key === 'getOutTrunk') return !hasAccess();
  if (key === 'passengers') return !inVehicle() || !isDriver();
  if (key === 'repair' || key === 'refuel' || key === 'charge') return inVehicle();
  if (key === 'sellState') return !isOwner() || Number(vehicle?.sellValue || 0) <= 0;
  return false;
}
function disabledReason(key) {
  const locked = isLocked();
  const trunkSlots = Number(vehicle?.trunkSlots || 0);
  if (key === 'features' && !hasAccess()) return 'No key';
  if (key === 'giveKey' && !isOwner()) return 'Owner only';
  if ((key === 'trunk' || key === 'enterTrunk') && locked) return 'Unlock vehicle first with L';
  if ((key === 'trunk' || key === 'enterTrunk') && trunkSlots <= 0) return 'No trunk';
  if (key === 'trunk' && !hasAccess()) return 'No key';
  if (key === 'getOutTrunk' && !hasAccess()) return 'No key';
  if (key === 'passengers' && !inVehicle()) return 'Inside only';
  if (key === 'passengers' && !isDriver()) return 'Driver only';
  if (key === 'sellState' && !isOwner()) return 'Owner only';
  if (key === 'sellState' && Number(vehicle?.sellValue || 0) <= 0) return 'No state value';
  return '';
}

function showVehicleInfo() {
  infoOpen = true;
  featuresOpen = false;
  hidePicker();
  $('featuresPanel')?.classList.add('hidden');
  $('vehicleMenu')?.classList.add('hidden');
  $('vehicleInfoScreen')?.classList.remove('hidden');
}
async function openPlayerPicker(mode) {
  pickerMode = mode;
  pickerOpen = true;
  $('featuresPanel')?.classList.add('hidden');
  featuresOpen = false;
  const title = mode === 'key' ? 'Give Vehicle Key' : 'Remove Passenger';
  const subtitle = mode === 'key' ? 'Select a nearby player close to you or the vehicle.' : 'Only passengers are shown. Driver is never listed.';
  setText('pickerTitle', title);
  setText('pickerSubtitle', subtitle);
  const list = $('pickerList');
  if (list) list.innerHTML = '<div class="empty-list">Loading players...</div>';
  $('playerPicker')?.classList.remove('hidden');
  const event = mode === 'key' ? 'requestNearbyPlayers' : 'requestVehiclePassengers';
  const result = await post(event, { plate: plateText(), netId: vehicleNetId() });
  renderPickerList(Array.isArray(result.players) ? result.players : [], mode);
}
function renderPickerList(players, mode) {
  const list = $('pickerList');
  if (!list) return;
  list.innerHTML = '';
  if (!players.length) {
    list.innerHTML = `<div class="empty-list">${mode === 'key' ? 'No nearby players found.' : 'No passengers inside this vehicle.'}</div>`;
    return;
  }
  players.forEach(p => {
    const row = document.createElement('button');
    row.className = 'picker-player';
    row.dataset.playerId = p.id;
    const detail = mode === 'key' ? `${p.distance ?? '?'}m away` : `Seat ${Number(p.seat || 0) + 1}`;
    row.innerHTML = `<span>${p.name || ('Player ' + p.id)}</span><b>ID ${p.id}</b><small>${detail}</small>`;
    list.appendChild(row);
  });
}
function selectPickerPlayer(id) {
  if (!id) return;
  if (pickerMode === 'key') {
    post('vehicleAction', { action: 'key', plate: plateText(), netId: vehicleNetId(), target: id });
    showToast('Key request sent.');
  } else if (pickerMode === 'passenger') {
    post('vehicleAction', { action: 'ejectPassenger', plate: plateText(), netId: vehicleNetId(), target: id });
    showToast('Passenger remove request sent.');
  }
  hidePicker();
}
function runAction(action) {
  if (actionDisabled(action)) {
    const reason = disabledReason(action);
    if (reason) showToast(reason, 'error');
    return;
  }
  if (action === 'info') { showVehicleInfo(); return; }
  if (action === 'features') {
    featuresOpen = !featuresOpen;
    $('featuresPanel')?.classList.toggle('hidden', !featuresOpen);
    renderMenuActions();
    return;
  }
  if (action === 'giveKey') { openPlayerPicker('key'); return; }
  if (action === 'passengers') { openPlayerPicker('passenger'); return; }
  if (['repair','refuel','charge'].includes(action)) {
    post('vehicleAction', { action, plate: plateText(), netId: vehicleNetId() });
    showToast('This RP option is coming soon.');
    return;
  }
  if (action === 'getOutTrunk') {
    post('vehicleAction', { action, plate: plateText(), netId: vehicleNetId() });
    showToast('Checking trunk...');
    return;
  }
  if (action === 'sellState') {
    const payout = formatMoney(vehicle?.sellValue || 0);
    const ok = window.confirm(`Sell this vehicle to the state for ${payout}? This cannot be undone.`);
    if (!ok) return;
    post('vehicleAction', { action, plate: plateText(), netId: vehicleNetId() });
    showToast('Selling vehicle to state...');
    return;
  }
  post('vehicleAction', { action, plate: plateText(), netId: vehicleNetId() });
  if (action === 'trunk') { showToast('Trunk opened/closed. Press I near the open trunk for inventory.'); return; }
  if (action === 'enterTrunk') { showToast('Getting in trunk...'); closeAll(); return; }
  if (action === 'drift') { showToast('Request sent.'); return; }
  closeAll();
}
function makeActionButton(a, displayIndex) {
  const div = document.createElement('button');
  const disabled = actionDisabled(a.key);
  const active = (a.key === 'features' && featuresOpen);
  div.className = `radial-action ${disabled ? 'disabled' : ''} ${active ? 'active' : ''}`;
  div.dataset.action = a.key;
  const reason = disabled ? `<em>${disabledReason(a.key)}</em>` : '';
  div.innerHTML = `<span class="num">${displayIndex}</span><span class="r-icon">${a.icon}</span><span class="action-title">${a.title}</span>${reason}`;
  return div;
}
function renderMenuActions() {
  const wrap = $('radialActions');
  if (!wrap) return;
  wrap.innerHTML = '';
  const list = document.createElement('div');
  list.className = 'action-list center';
  actions.filter(actionVisible).forEach((a, index) => list.appendChild(makeActionButton(a, index + 1)));
  wrap.appendChild(list);
  wrap.classList.toggle('inside-mode', inVehicle());
}
function openMenu(data) {
  vehicle = data.vehicle || data || {};
  vehicle.netId = vehicle.netId || vehicle?.context?.netId;
  vehicle.plate = vehicle.plate || vehicle?.context?.plate || '';
  const c = ctx();
  const accessText = vehicle.access ? (vehicle.owner ? 'Owner' : 'Temporary key') : 'No key';
  const lockText = isLocked() ? 'Locked' : 'Unlocked';
  const body = Number(vehicle.bodyHealth || 1000);
  const engine = Number(vehicle.engineHealth || 1000);
  const contextText = c.inVehicle ? (c.isDriver ? 'Inside vehicle · driver seat' : 'Inside vehicle · passenger seat') : 'Outside vehicle · looking at vehicle';
  const insuranceDays = Number(vehicle.insuranceDays || vehicle.insurance_days || 0);
  const stateValue = Number(vehicle.stateValue || vehicle.state_value || 0);
  const sellValue = Number(vehicle.sellValue || Math.floor(stateValue * 0.30));
  const mileage = Number(vehicle.mileage || vehicle?.metadata?.mileage || 0);
  const mileagePenalty = vehicle.mileagePenaltyText || 'No mileage data';
  const harnessText = vehicle.racingHarness ? 'Installed' : 'Not installed';
  vehicle.stateValue = stateValue;
  vehicle.sellValue = sellValue;
  setText('infoVehicleName', vehicle.label || vehicle.model || 'Vehicle');
  setText('infoOwnerName', vehicle.ownerName || vehicle.owner_name || vehicle.ownerCharacterId || 'Unknown');
  setText('infoPlate', plateText());
  setText('infoInsuranceDays', `${insuranceDays} Day${insuranceDays === 1 ? '' : 's'}`);
  setText('infoStateValue', formatMoney(stateValue));
  setText('infoSellValue', formatMoney(sellValue));
  setText('infoAccess', accessText);
  setText('infoLock', lockText);
  setText('infoFuel', `${vehicle.fuel ?? 100}%`);
  setText('infoBody', `${Math.max(0, Math.min(100, Math.round(body / 10)))}%`);
  setText('infoEngine', `${Math.max(0, Math.min(100, Math.round(engine / 10)))}%`);
  setText('infoTrunk', `${vehicle.trunkSlots || 0} slots`);
  setText('infoMileage', `${mileage.toFixed(1)} km`);
  setText('infoMileagePenalty', mileagePenalty);
  setText('infoHarness', harnessText);
  setText('infoContext', contextText);
  setText('infoVehicleId', vehicle.id ? `#${vehicle.id}` : 'Unknown');
  const sellBtn = $('sellStateBtn');
  if (sellBtn) {
    sellBtn.textContent = `SELL CAR TO STATE FOR ${formatMoney(sellValue)} (30%)`;
    sellBtn.classList.toggle('disabled', actionDisabled('sellState'));
  }
  featuresOpen = false;
  infoOpen = false;
  hidePicker();
  $('featuresPanel')?.classList.add('hidden');
  $('vehicleInfoScreen')?.classList.add('hidden');
  renderMenuActions();
  $('vehicleMenu')?.classList.remove('hidden');
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'openMenu') openMenu(data);
  if (data.action === 'toast') showToast(data.message, data.type || 'info');
  if (data.action === 'close') {
    $('vehicleMenu')?.classList.add('hidden');
    $('vehicleInfoScreen')?.classList.add('hidden');
    $('featuresPanel')?.classList.add('hidden');
    hidePicker();
    featuresOpen = false;
    infoOpen = false;
  }
});
