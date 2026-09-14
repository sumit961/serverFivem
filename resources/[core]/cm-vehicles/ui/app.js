let vehicle = null;
let featuresOpen = false;
let infoOpen = false;
let pickerOpen = false;
let pickerMode = null;
let saleConfirmOpen = false;
const actionBusy = new Set();
const $ = (id) => document.getElementById(id);

const actions = [
  { id: 1, key: 'info', icon: '🚗', title: 'VIEW TRANSPORT INFORMATION', mode: 'always', category: 'vehicle' },
  { id: 2, key: 'features', icon: '🏁', title: 'MANAGE DRIFT SETTINGS', mode: 'outside', category: 'vehicle' },
  { id: 3, key: 'giveKey', icon: '🔑', title: 'GIVE VEHICLE KEY', mode: 'outside', category: 'vehicle' },
  { id: 4, key: 'repair', icon: '🔧', title: 'TRANSPORTATION REPAIR', mode: 'outside', category: 'vehicle' },
  { id: 5, key: 'refuel', icon: '⛽', title: 'REFUEL THE VEHICLE', mode: 'outside', category: 'vehicle' },
  { id: 6, key: 'wash', icon: '🧽', title: 'WASH THE VEHICLE', mode: 'outside', category: 'vehicle' },
  { id: 7, key: 'charge', icon: '⚡', title: 'CHARGE TRANSPORT', mode: 'outside', category: 'vehicle' },
  { id: 8, key: 'trunk', icon: '🚙', title: 'OPEN / CLOSE TRUNK', mode: 'always', category: 'trunk' },
  { id: 9, key: 'enterTrunk', icon: '📦', title: 'GET IN THE TRUNK', mode: 'outside', category: 'trunk' },
  { id: 10, key: 'getOutTrunk', icon: '⬆', title: 'GET PLAYER OUT OF THE TRUNK', mode: 'always', category: 'trunk' },
  { id: 11, key: 'passengers', icon: '👥', title: 'GET PASSENGER OUT OF CAR', mode: 'inside', category: 'vehicle' },
  { id: 12, key: 'policePutDragged', icon: '🛡️', title: 'PUT DRAGGED SUSPECT IN VEHICLE', mode: 'outside', category: 'vehicle' },
  { id: 13, key: 'policeRemoveCuffed', icon: '🛡️', title: 'REMOVE CUFFED SUSPECT FROM VEHICLE', mode: 'outside', category: 'vehicle' },
  { id: 14, key: 'sellState', icon: '💰', title: 'SELL VEHICLE TO STATE', mode: 'always', category: 'vehicle' },
];

function post(name, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  }).then(r => r.json().catch(() => ({}))).catch(() => ({}));
}
function setText(id, value) { const el = $(id); if (el) el.textContent = value ?? ''; }
function escapeHtml(value) { return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#039;'}[c])); }
function setMeter(id, value) {
  const el = $(id);
  if (!el) return;
  const pct = Math.max(0, Math.min(100, Number(value) || 0));
  el.style.width = `${pct}%`;
  el.classList.toggle('low', pct < 30);
  el.classList.toggle('mid', pct >= 30 && pct < 65);
}
function setStatusChip(id, text, tone = '') {
  const el = $(id);
  if (!el) return;
  el.textContent = text;
  el.className = `status-chip ${tone}`.trim();
}
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
function hideSaleConfirm() {
  saleConfirmOpen = false;
  const modal = $('saleConfirm');
  if (modal) {
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
  }
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
  hideSaleConfirm();
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
$('infoBack')?.addEventListener('click', backToMenu);
$('pickerBack')?.addEventListener('click', backToMenu);
$('pickerClose')?.addEventListener('click', closeAll);
$('saleConfirmCancel')?.addEventListener('click', () => hideSaleConfirm());
$('saleConfirmAccept')?.addEventListener('click', () => {
  if (!saleConfirmOpen) return;
  const accept = $('saleConfirmAccept');
  if (accept?.disabled) return;
  if (accept) {
    accept.disabled = true;
    accept.textContent = 'PROCESSING SALE...';
  }
  hideSaleConfirm();
  post('vehicleAction', { action: 'sellState', plate: plateText(), netId: vehicleNetId() });
  showToast('Selling vehicle to state...');
  closeAll();
});

document.addEventListener('contextmenu', (e) => {
  e.preventDefault();
  if (infoOpen || pickerOpen || featuresOpen) backToMenu();
  else closeAll();
});

document.addEventListener('keydown', (e) => {
  const key = String(e.key || '').toLowerCase();
  if (key === 'escape' || key === 'backspace') {
    if (infoOpen) closeAll();
    else if (pickerOpen) backToMenu();
    else closeAll();
    return;
  }

  // ── Number keys select a menu action ──
  // Each visible action is numbered in order (1..9, then 0 for the 10th).
  // Only works on the main menu, not while a sub-panel/picker is open.
  if (infoOpen || pickerOpen) return;
  if (!/^[0-9]$/.test(key)) return;

  const list = visibleActions();
  if (!list.length) return;

  const idx = (key === '0') ? 9 : (Number(key) - 1);
  const target = list[idx];
  if (!target) return;

  e.preventDefault();
  if (actionDisabled(target.key)) {
    const reason = disabledReason(target.key);
    if (reason) showToast(reason, 'error');
    return;
  }
  runAction(target.key);
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
  if (action.key === 'policePutDragged' && !vehicle?.policeDraggedSuspect) return false;
  if (action.key === 'policeRemoveCuffed' && !vehicle?.policeCuffedOccupant) return false;
  if ((action.key === 'trunk' || action.key === 'enterTrunk') && slots <= 0) return false;
  if (inside && ['repair','refuel','wash','charge','features','giveKey','enterTrunk'].includes(action.key)) return false;
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
  if (key === 'repair' || key === 'refuel' || key === 'wash' || key === 'charge') return inVehicle();
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
    row.innerHTML = `<span>${escapeHtml(p.name || ('Player ' + p.id))}</span><b>ID ${Number(p.id) || 0}</b><small>${escapeHtml(detail)}</small>`;
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
  if (actionBusy.has(action)) {
    showToast('This vehicle action is already processing.', 'info');
    return;
  }
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
  if (['repair','refuel','wash','charge'].includes(action)) {
    // Handled client-side: uses a repair kit / jerry can from the player's
    // inventory. The client notifies on success or tells them what they need.
    actionBusy.add(action);
    showToast(`${action.toUpperCase()} request processing...`);
    post('vehicleAction', { action, plate: plateText(), netId: vehicleNetId() });
    closeAll();
    setTimeout(() => actionBusy.delete(action), 3500);
    return;
  }
  if (action === 'getOutTrunk') {
    actionBusy.add(action);
    post('vehicleAction', { action, plate: plateText(), netId: vehicleNetId() });
    showToast('Checking trunk...');
    setTimeout(() => actionBusy.delete(action), 2500);
    return;
  }
  if (action === 'sellState') {
    const payout = formatMoney(vehicle?.sellValue || 0);
    const modal = $('saleConfirm');
    if (!modal) return;
    setText('saleConfirmPayout', payout);
    setText('saleConfirmText', `Sell ${vehicle?.label || vehicle?.model || 'this vehicle'} to the state? This permanently removes the vehicle and its ownership record.`);
    saleConfirmOpen = true;
    const accept = $('saleConfirmAccept');
    if (accept) {
      accept.disabled = false;
      accept.textContent = 'CONFIRM SALE';
    }
    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');
    return;
  }
  post('vehicleAction', { action, plate: plateText(), netId: vehicleNetId() });
  actionBusy.add(action);
  setTimeout(() => actionBusy.delete(action), 2500);
  if (action === 'trunk') { showToast('Trunk opened/closed. Press I near the open trunk for inventory.'); return; }
  if (action === 'enterTrunk') { showToast('Getting in trunk...'); closeAll(); return; }
  if (action === 'drift') { showToast('Request sent.'); return; }
  closeAll();
}
function makeActionButton(a, displayIndex, tone = 'cyan') {
  const div = document.createElement('button');
  const disabled = actionDisabled(a.key);
  const active = (a.key === 'features' && featuresOpen);
  div.className = `radial-action ${tone} ${disabled ? 'disabled' : ''} ${active ? 'active' : ''}`;
  div.dataset.action = a.key;
  const reason = disabled ? `<em>${disabledReason(a.key)}</em>` : '';
  div.innerHTML = `<span class="action-num-badge ${tone}">${displayIndex}</span><span class="action-title">${a.title}</span>${reason}`;
  return div;
}
// The exact list (and order) the menu renders, so number keys always match
// the numbers shown on the buttons.
function visibleActions() {
  return actions.filter(actionVisible);
}

function renderMenuActions() {
  const wrap = $('radialActions');
  if (!wrap) return;
  wrap.innerHTML = '';
  const list = visibleActions();
  const vehicleActions = list.filter(a => a.category !== 'trunk');
  const trunkActions = list.filter(a => a.category === 'trunk');
  const cols = document.createElement('div');
  cols.className = 'action-columns';
  // Vehicle column
  if (vehicleActions.length) {
    const col = document.createElement('div');
    col.className = 'action-col vehicle-col';
    const hdr = document.createElement('div');
    hdr.className = 'action-col-header';
    hdr.innerHTML = `<div class="hdr-left"><span class="hdr-dot cyan"></span> VEHICLE OPTIONS</div><span class="action-count">${vehicleActions.length} ACTIONS</span>`;
    col.appendChild(hdr);
    const listDiv = document.createElement('div');
    listDiv.className = 'col-actions-list';
    vehicleActions.forEach((a, index) => listDiv.appendChild(makeActionButton(a, index + 1, 'cyan')));
    col.appendChild(listDiv);
    cols.appendChild(col);
  }
  // Trunk column
  if (trunkActions.length) {
    const col = document.createElement('div');
    col.className = 'action-col trunk-col';
    const hdr = document.createElement('div');
    hdr.className = 'action-col-header';
    hdr.innerHTML = `<div class="hdr-left"><span class="hdr-dot orange"></span> TRUNK OPTIONS</div><span class="action-count">${trunkActions.length} ACTIONS</span>`;
    col.appendChild(hdr);
    const listDiv = document.createElement('div');
    listDiv.className = 'col-actions-list';
    trunkActions.forEach((a, index) => listDiv.appendChild(makeActionButton(a, index + 1, 'orange')));
    col.appendChild(listDiv);

    // Trunk status footer
    const trunkFooter = document.createElement('div');
    trunkFooter.className = 'trunk-footer';
    const isLockedState = isLocked();
    const isTrunkOpen = vehicle?.trunkOpen === true;
    const trunkStatusText = isTrunkOpen ? 'OPEN & ACCESSIBLE' : (isLockedState ? 'LOCKED' : 'EMPTY & ACCESSIBLE');
    const isGood = !isLockedState;
    trunkFooter.innerHTML = `<span class="trunk-footer-lbl">TRUNK STATUS:</span><span class="trunk-footer-val ${isGood ? 'green' : 'red'}">${trunkStatusText}</span>`;
    col.appendChild(trunkFooter);

    cols.appendChild(col);
  }
  wrap.appendChild(cols);
  wrap.classList.toggle('inside-mode', inVehicle());
}
function openMenu(data) {
  vehicle = data.vehicle || data || {};
  vehicle.netId = vehicle.netId || vehicle?.context?.netId;
  vehicle.plate = vehicle.plate || vehicle?.context?.plate || '';
  const c = ctx();
  const accessText = vehicle.access
    ? (vehicle.owner ? 'Owner' : (vehicle.familyKey || vehicle.accessReason === 'family' || vehicle.accessReason === 'family_key'
      ? 'Family key'
      : 'Temporary key'))
    : 'No key';
  const lockText = isLocked() ? 'Locked' : 'Unlocked';
  const body = Number(vehicle.bodyHealth || 1000);
  const engine = Number(vehicle.engineHealth || 1000);
  const tank = Number(vehicle.tankHealth || 1000);
  const fuel = Math.max(0, Math.min(100, Number(vehicle.fuel ?? 100)));
  const dirtLevel = Math.max(0, Math.min(15, Number(vehicle.dirtLevel ?? 0)));
  const cleanPct = Math.max(0, Math.min(100, 100 - ((dirtLevel / 15) * 100)));
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
  const notice = $('vehicleNotice');
  if (notice) {
    notice.textContent = vehicle.vehicleNotice || '';
    notice.classList.toggle('hidden', !vehicle.vehicleNotice);
    notice.classList.toggle('temporary', vehicle.temporaryReplacement === true);
    notice.classList.toggle('permanent', vehicle.permanentlyRemoved === true);
  }
  setText('infoOwnerName', vehicle.ownerName || vehicle.owner_name || vehicle.ownerCharacterId || 'Unknown');
  setText('infoPlate', plateText());

  // Populate vehicle header card in G menu
  setText('mvhName', (vehicle.label || vehicle.model || 'Vehicle').toUpperCase());
  setText('mvhPlate', plateText());
  const lockEl = $('mvhLock');
  if (lockEl) {
    const locked = isLocked();
    lockEl.textContent = locked ? '• LOCKED' : '• UNLOCKED';
    lockEl.className = `mvh-status ${locked ? 'locked' : 'unlocked'}`;
  }
  setText('mvhMileage', `${mileage.toFixed(1)} KM`);
  setText('mvhFuel', `${Math.round(fuel)}%`);
  const mvhFuelBar = $('mvhFuelBar');
  if (mvhFuelBar) {
    mvhFuelBar.style.width = `${fuel}%`;
  }

  const vehicleImage = $('infoVehicleImage');
  if (vehicleImage) {
    if (vehicle.vehicleImage) {
      vehicleImage.src = vehicle.vehicleImage;
      vehicleImage.alt = vehicle.label || vehicle.model || 'Vehicle';
      vehicleImage.classList.remove('hidden');
    } else {
      vehicleImage.removeAttribute('src');
      vehicleImage.classList.add('hidden');
    }
  }

  const familyCard = $('infoFamilyCard');
  if (familyCard) familyCard.classList.toggle('hidden', !vehicle.familyName);
  setText('infoFamilyName', vehicle.familyName
    ? `${vehicle.familyTag ? '[' + vehicle.familyTag + '] ' : ''}${vehicle.familyName}`
    : 'Not shared');
  setText('infoInsuranceDays', `${insuranceDays} Day${insuranceDays === 1 ? '' : 's'}`);
  setText('infoStateValue', formatMoney(stateValue));
  setText('infoSellValue', formatMoney(sellValue));
  const bodyPct = Math.max(0, Math.min(100, Math.round(body / 10)));
  const enginePct = Math.max(0, Math.min(100, Math.round(engine / 10)));
  const tankPct = Math.max(0, Math.min(100, Math.round(tank / 10)));
  setText('infoAccess', accessText);
  setText('infoLock', lockText);
  setText('infoFuel', `${Math.round(fuel)}%`);
  setText('infoBody', `${bodyPct}%`);
  setText('infoEngine', `${enginePct}%`);
  setText('infoTank', `${tankPct}%`);
  setText('infoDirt', cleanPct > 85 ? 'Clean' : (cleanPct > 55 ? 'Used' : 'Dirty'));
  setMeter('infoFuelBar', fuel);
  setMeter('infoBodyBar', bodyPct);
  setMeter('infoEngineBar', enginePct);
  setMeter('infoTankBar', tankPct);
  setMeter('infoDirtBar', cleanPct);
  setStatusChip('infoAccessChip', accessText.toUpperCase(), vehicle.access ? 'good' : 'bad');
  setStatusChip('infoLockChip', lockText.toUpperCase(), isLocked() ? 'warn' : 'good');
  setStatusChip('infoHarnessChip', vehicle.racingHarness ? 'RACING HARNESS' : 'STANDARD BELT', vehicle.racingHarness ? 'good' : '');
  setText('infoTrunk', `${vehicle.trunkSlots || 0} slots`);
  setText('infoMileage', `${mileage.toFixed(1)} km`);
  setText('infoMileagePenalty', mileagePenalty);
  setText('infoHarness', harnessText);
  setText('infoContext', contextText);
  setText('infoVehicleId', vehicle.id ? `#${vehicle.id}` : 'Unknown');
  const tsNow = Number(vehicle.topSpeed) || 0;
  const tsStock = Number(vehicle.topSpeedStock) || 0;
  setText('infoTopSpeed', tsNow > tsStock
    ? `${tsStock} → ${tsNow} km/h`
    : (tsNow ? `${tsNow} km/h` : '-'));
  renderInstalledParts(vehicle.parts);
  const sellBtn = $('sellStateBtn');
  if (sellBtn) {
    sellBtn.textContent = `SELL CAR TO STATE FOR ${formatMoney(sellValue)}${vehicle.permanentlyRemoved ? ' (FULL REFUND)' : ' (30%)'}`;
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

/* ============================================================
   SERVICE PROGRESS (refuel / repair)
   Driven entirely from Lua: it sends svcProgress start/update/stop.
   ============================================================ */
const svcEl   = () => document.getElementById('svcProgress');
const svcFill = () => document.getElementById('svcFill');
const svcPct  = () => document.getElementById('svcPct');

function svcStart(kind, title, sub){
  const el = svcEl(); if(!el) return;
  el.classList.toggle('repair', kind === 'repair');
  document.getElementById('svcIcon').textContent = (kind === 'repair') ? '🔧' : '⛽';
  document.getElementById('svcTitle').textContent = title || (kind === 'repair' ? 'Repairing' : 'Refueling');
  document.getElementById('svcSub').textContent   = sub || 'Hold still…';
  svcFill().style.width = '0%';
  svcPct().textContent = '0';
  el.classList.remove('hidden');
}
function svcUpdate(pct){
  const p = Math.max(0, Math.min(100, Math.round(Number(pct)||0)));
  if (svcFill()) svcFill().style.width = p + '%';
  if (svcPct())  svcPct().textContent = p;
}
function svcStop(){
  const el = svcEl(); if(!el) return;
  el.classList.add('hidden');
  el.classList.remove('repair');
}

window.addEventListener('message', (e) => {
  const d = e.data || {};
  if (d.action === 'svcStart')  svcStart(d.kind, d.title, d.sub);
  else if (d.action === 'svcUpdate') svcUpdate(d.pct);
  else if (d.action === 'svcStop')   svcStop();
});


/* ============================================================
   INSTALLED PARTS  (upgrade levels shown in the info screen)
   Populated from vehicle.parts, which the client reads live off the car.
   ============================================================ */
function renderInstalledParts(parts){
  const box = document.getElementById('infoParts');
  if(!box) return;

  if(!Array.isArray(parts) || !parts.length){
    box.innerHTML = '<div class="parts-empty">No upgrades fitted.</div>';
    return;
  }

  box.innerHTML = parts.map(p => {
    const lvl = Number(p.level) || 0;
    const max = Number(p.max) || 0;
    const fitted = lvl > 0;

    // level pips
    let pips = '';
    if(max > 0){
      for(let i = 1; i <= max; i++){
        pips += `<i class="${i <= lvl ? 'on' : ''}"></i>`;
      }
    }

    return `<div class="part ${fitted ? 'fitted' : ''}">
      <div class="part-top">
        <span class="part-name">${escapeHtml(p.label || '')}</span>
        <span class="part-lvl">${escapeHtml(p.text || (fitted ? ('Lv ' + lvl) : 'Stock'))}</span>
      </div>
      ${max > 0 ? `<div class="part-pips">${pips}</div>` : ''}
    </div>`;
  }).join('');
}
