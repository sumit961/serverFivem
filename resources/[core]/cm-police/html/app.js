const app = document.getElementById('app');
const npcDialogue = document.getElementById('npcDialogue');
const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-police';
let state = null;
let page = 'overview';
let armoryStandalone = false;
let fleetStandalone = false;
let dispatchStandalone = false;
let editingRankId = null;
const impoundRelease = document.getElementById('impoundRelease');
const impoundReleaseList = document.getElementById('impoundReleaseList');
let impoundReleaseVehicles = [];
let impoundReleaseIndex = 0;

const post = (name, data = {}) => fetch(`https://${res}/${name}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
}).then((response) => response.json());
const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
})[character]);
const can = (permission) => state?.self?.isLeader === true || state?.self?.permissions?.[permission] === true;

function renderImpoundRelease(vehicles) {
  if (vehicles) { impoundReleaseVehicles = vehicles; impoundReleaseIndex = 0; }
  if (!impoundReleaseVehicles.length) { impoundReleaseList.innerHTML = '<div class="impound-release__empty">No vehicles are currently held in impound.</div>'; return; }
  impoundReleaseIndex = Math.max(0, Math.min(impoundReleaseIndex, impoundReleaseVehicles.length - 1));
  const vehicle = impoundReleaseVehicles[impoundReleaseIndex];
  impoundReleaseList.innerHTML = `<article class="impound-cinematic">
    <section class="impound-cinematic__copy">
      <div class="impound-cinematic__selector"><button data-impound-direction="-1" ${impoundReleaseVehicles.length < 2 ? 'disabled' : ''}>⌃</button><i></i><button data-impound-direction="1" ${impoundReleaseVehicles.length < 2 ? 'disabled' : ''}>⌄</button></div>
      <div class="impound-cinematic__heading"><small>VEHICLE IMPOUND NOTICE</small><h1>THE CAR<br>IMPOUNDED</h1><h3>${esc(vehicle.model || 'UNKNOWN VEHICLE')}</h3><p>POLICE OFFICER <b>${esc(vehicle.officerName)}</b></p></div>
      <blockquote>${esc(vehicle.reason)}</blockquote>
      <div class="impound-cinematic__counter"><strong>${impoundReleaseIndex + 1}</strong><span>/ ${impoundReleaseVehicles.length}</span></div>
      <div class="impound-cinematic__penalty"><small>RELEASE PENALTY</small><b>$${Number(vehicle.fee || 0).toLocaleString()}</b></div>
    </section>
    <section class="impound-cinematic__evidence">
      <div class="impound-file impound-file--back"></div><div class="impound-file">
        <div class="impound-file__photo">${vehicle.imageUrl ? `<img src="${esc(vehicle.imageUrl)}" alt="Police evidence for ${esc(vehicle.plate)}">` : '<div>NO EVIDENCE IMAGE</div>'}<span>IMPOUNDED</span></div>
        <p>Vehicle <b>${esc(vehicle.plate)}</b> was impounded on ${esc(vehicle.impoundedAt)}.</p>
        <div class="impound-file__seal">★<small>CM POLICE</small></div>
      </div>
      <div class="impound-cinematic__badge">★<span>POLICE<br>DEPARTMENT</span></div>
    </section>
    <footer class="impound-cinematic__actions"><button class="secondary" id="impoundLotClose">⌖&nbsp;&nbsp; IMPOUND LOT</button><button class="primary" data-impound-pay="${Number(vehicle.vehicleId)}" data-impound-fee="${Number(vehicle.fee || 0)}" data-impound-plate="${esc(vehicle.plate)}">▣&nbsp;&nbsp; PAY &amp; RELEASE VEHICLE</button></footer>
  </article>`;
}

document.getElementById('impoundReleaseClose')?.addEventListener('click', () => post('closeImpoundRelease'));
impoundReleaseList?.addEventListener('click', async (event) => {
  const direction = event.target.closest('[data-impound-direction]');
  if (direction) {
    const count = impoundReleaseVehicles.length;
    impoundReleaseIndex = (impoundReleaseIndex + Number(direction.dataset.impoundDirection) + count) % count;
    renderImpoundRelease();
    return;
  }
  if (event.target.closest('#impoundLotClose')) { post('closeImpoundRelease'); return; }
  const button = event.target.closest('[data-impound-pay]');
  if (!button || button.disabled) return;
  button.disabled = true;
  await post('payImpoundRelease', { vehicleId: Number(button.dataset.impoundPay), fee: Number(button.dataset.impoundFee), plate: button.dataset.impoundPlate });
  button.disabled = false;
});
document.querySelector('[data-police-facilities]')?.insertAdjacentHTML('beforebegin', '<article class="card admin-panel"><h3>Jail spawn locations</h3><p>Stand inside a cell and add a spawn. Each location holds at most two active prisoners.</p><p id="adminJailSpawnsStatus">No jail spawns configured.</p><div class="operation-actions"><button class="primary" id="adminAddJailSpawn">Add jail spawn here</button><button class="mini danger" id="adminResetJailSpawns">Reset all jail spawns</button></div></article>');
document.querySelector('[data-police-facilities]')?.insertAdjacentHTML('beforebegin', '<article class="card admin-panel"><div class="section-head"><div><small>PRISON CONTROL</small><h3>Active prisoners</h3><p>Reduce an active sentence or release a prisoner immediately. Every action is audited.</p></div><button class="mini" id="adminRefreshPrisoners">Refresh</button></div><div class="list" id="adminPrisonerList"><p>No active prisoners.</p></div></article>');

function showPage(next) {
  if (next === 'admin' && !state?.adminMode) next = 'overview';
  page = next;
  document.querySelectorAll('.nav').forEach((item) => item.classList.toggle('active', item.dataset.page === page));
  document.querySelectorAll('.page').forEach((item) => item.classList.toggle('active', item.dataset.view === page));
  const names = { overview: 'Police operations', members: 'Police members', ranks: 'Ranks & access', outfits: 'Duty outfits', fleet: 'Fleet vehicles', logs: 'Activity logs', mdt: 'MDT records', dispatch: '911 dispatch', admin: 'Police administration' };
  document.getElementById('pageTitle').textContent = names[page] || 'Police';
  if (page === 'fleet' && fleetVehicles.length === 0) loadFleet();
  if (page === 'dispatch') { loadDispatchActiveCalls(); loadDispatchHistory(); }
  if (page === 'admin' && state?.adminMode) { loadPoliceAdminConfig(); loadArmoryManageList(); loadAdminPrisoners(); }
}

async function loadAdminPrisoners() {
  const result = await post('adminPrisoners');
  const list = document.getElementById('adminPrisonerList');
  if (!list) return;
  if (!result?.ok || !result.prisoners?.length) { list.innerHTML = '<p>No active prisoners.</p>'; return; }
  list.innerHTML = result.prisoners.map((row) => {
    const remaining = Math.max(0, Number(row.remaining_seconds) || 0);
    const minutes = Math.ceil(remaining / 60);
    return `<article class="list-row"><div><strong>${esc(row.character_name)}</strong><small>Character ${esc(row.character_id)} · ${minutes} minute(s) remaining · Arrested by ${esc(row.arrested_by_name || 'Police Department')}</small></div><div class="operation-actions"><input type="number" min="1" max="43200" value="15" data-prison-minutes="${esc(row.character_id)}"><button class="mini" data-prison-action="reduce" data-cid="${esc(row.character_id)}">Reduce time</button><button class="mini danger" data-prison-action="release" data-cid="${esc(row.character_id)}">Release</button></div></article>`;
  }).join('');
}

let policeAdminConfigLoading = false;
const formatLocation = (value) => value ? `${Number(value.x).toFixed(1)}, ${Number(value.y).toFixed(1)}, ${Number(value.z).toFixed(1)}` : 'not configured';
async function loadPoliceAdminConfig() {
  if (policeAdminConfigLoading) return;
  policeAdminConfigLoading = true;
  const result = await post('policeAdminConfig');
  policeAdminConfigLoading = false;
  if (!result?.ok || !result.config) return;
  const config = result.config;
  document.getElementById('adminMinutesPerStar').value = config.minutesPerStar;
  document.getElementById('adminBookingRadius').value = config.bookingRadius;
  document.getElementById('adminHandoffTimeout').value = config.handoffTimeoutMs;
  const cinematic = config.cinematicRules || {};
  document.getElementById('adminCinematicEnabled').checked = cinematic.enabled !== false;
  document.getElementById('adminCinematicSkip').checked = cinematic.allowSkip !== false;
  document.getElementById('adminCinematicCollision').checked = cinematic.cameraCollision !== false;
  document.getElementById('adminCinematicSound').checked = cinematic.soundEnabled !== false;
  document.getElementById('adminCinematicSpeed').value = cinematic.sequenceSpeed ?? 1;
  document.getElementById('adminCinematicFov').value = cinematic.cameraFov ?? 45;
  document.getElementById('adminCinematicResponse').value = cinematic.responseDurationMs ?? 2200;
  document.getElementById('adminCinematicVolume').value = cinematic.soundVolume ?? 1;
  document.getElementById('adminBookingDeskStatus').textContent = `Booking desk: ${config.bookingDesk?.name || 'Unnamed'} · ${formatLocation(config.bookingDesk)} · Bucket ${config.bookingDesk?.bucket ?? '--'}`;
  document.getElementById('adminJailIntakeStatus').textContent = `Jail intake: ${config.jailIntake?.name || 'Unnamed'} · ${formatLocation(config.jailIntake)} · Bucket ${config.jailIntake?.bucket ?? '--'}`;
  document.getElementById('adminJailSpawnsStatus').textContent = `${config.jailSpawns?.length || 0} jail spawn(s) configured · capacity ${(config.jailSpawns?.length || 0) * 2}`;
  document.getElementById('adminServiceNpcStatus').textContent = `Police front desk: ${config.serviceNpc?.name || 'Unnamed'} · ${formatLocation(config.serviceNpc)} · Bucket ${config.serviceNpc?.bucket ?? '--'}`;
  document.getElementById('adminArmoryNpcStatus').textContent = `Armory NPC: ${config.armoryNpc?.name || 'Unnamed'} · ${formatLocation(config.armoryNpc)} · Bucket ${config.armoryNpc?.bucket ?? '--'}`;
  document.getElementById('adminStorageNpcStatus').textContent = `Storage NPC: ${config.storageNpc?.name || 'Unnamed'} · ${formatLocation(config.storageNpc)} · Bucket ${config.storageNpc?.bucket ?? '--'}`;
  document.getElementById('adminClothingNpcStatus').textContent = `Clothing NPC: ${formatLocation(config.wardrobeNpc?.set ? config.wardrobeNpc : null)}`;
  document.getElementById('adminJailWarning').textContent = config.jailIntake?.warning || '';
  if (config.bookingDesk?.name) document.getElementById('adminBookingName').value = config.bookingDesk.name;
  if (config.jailIntake?.name) document.getElementById('adminJailName').value = config.jailIntake.name;
  if (config.serviceNpc?.name) document.getElementById('adminServiceNpcName').value = config.serviceNpc.name;
}

function closeRankEditor() {
  editingRankId = null;
  document.getElementById('rankEditor').hidden = true;
  document.getElementById('rankName').value = '';
  document.getElementById('rankTier').value = '';
}

function openRankEditor(rank = null) {
  editingRankId = rank?.id || null;
  document.getElementById('rankName').value = rank?.name || '';
  document.getElementById('rankTier').value = rank?.tier || '';
  document.getElementById('permissionEditor').innerHTML = Object.entries(state.permissions || {}).map(([key, label]) => {
    const checked = rank?.permissions?.[key] === true ? ' checked' : '';
    const grantable = can('police.manage_permissions') && can(key);
    return `<label class="permission-check"><input type="checkbox" value="${esc(key)}"${checked}${grantable ? '' : ' disabled'}><span>${esc(label)}</span></label>`;
  }).join('');
  document.getElementById('rankEditor').hidden = false;
}

// ── Fleet vehicles ──────────────────────────────────────────────────────
// Appearance (model/label/category/image/mods) is sourced live from
// rn-vehicleshop's "Police fleet vehicle" catalog status -- there is no
// editor for colors/livery/etc here; that lives entirely in /vehicleadmin.
//
// cm-police only adds: minimum rank tier (edited inline below) and a Spawn
// button. Spawn location is never set from the NUI -- it's set/updated
// in-game by driving the vehicle and pressing H (client/vehicles.lua), and
// "Spawn" always recalls/replaces any existing live instance instead of
// piling up duplicates.
let fleetVehicles = [];

function renderFleetList() {
  const manage = can('police.manage_vehicles');
  const rows = fleetVehicles;
  document.getElementById('fleetList').innerHTML = rows.map((v) => {
    const canSpawnThis = manage || (v.configured && v.enabled);
    return `
    <article class="fleet-row${v.configured && !v.enabled ? ' disabled' : ''}">
      ${v.image ? `<img class="fleet-thumb" src="${esc(v.image)}" alt="">` : '<div class="fleet-thumb fleet-thumb--empty">NO IMAGE</div>'}
      <div class="fleet-row__main">
        <div class="fleet-row__title">${esc(v.label)}${v.configured ? '' : ' <span class="fleet-badge">Not configured</span>'}</div>
        <div class="fleet-row__sub">${esc(v.model)} · ${esc(v.category || 'Custom')} · ${esc(String(v.status || 'available').replaceAll('_', ' '))}${v.assignedOfficer ? ` · Assigned: ${esc(v.assignedOfficer)}` : ''}${v.engineHealth != null ? ` · Engine ${Math.round(Number(v.engineHealth) / 10)}% · Body ${Math.round(Number(v.bodyHealth) / 10)}% · Fuel ${Math.round(Number(v.fuel || 0))}%` : ''}${v.location ? ` · ${v.location.x}, ${v.location.y}` : ''}${v.configured ? '' : ' · Set its location first'}</div>
      </div>
      <div class="fleet-row__actions">
        ${manage ? `
        <div class="fleet-tier-ctl">
          <label>Minimum rank tier</label>
          <input class="fleet-tier-input" type="number" min="0" max="100" value="${v.minTier}" data-fleet-tier="${esc(v.model)}"${v.configured ? '' : ' disabled title="Spawn it and press H to give it a location first"'}>
        </div>` : ''}
        ${manage ? `<button class="mini" data-fleet-location="${esc(v.model)}">Set location</button>` : ''}
        ${canSpawnThis ? `<button class="mini" data-fleet-spawn="${esc(v.model)}"${v.status === 'occupied' ? ' disabled' : ''}>${v.status === 'occupied' ? 'Occupied' : v.status === 'deployed' ? 'Return & call here' : 'Call vehicle'}</button>` : ''}
      </div>
    </article>`;
  }).join('') || `<article class="card">${manage ? 'No vehicles are tagged &quot;Police fleet vehicle&quot; in /vehicleadmin yet.' : 'No Police fleet vehicles are available to your rank yet.'}</article>`;
}

async function loadFleet() {
  const result = await post('fleetCatalog');
  fleetVehicles = result?.vehicles || [];
  renderFleetList();
}

document.getElementById('fleetList').addEventListener('click', (event) => {
  const spawn = event.target.closest('[data-fleet-spawn]');
  if (spawn) post('spawnFleetVehicle', { model: spawn.dataset.fleetSpawn });
  const location = event.target.closest('[data-fleet-location]');
  if (location) post('setFleetVehicleLocation', { model: location.dataset.fleetLocation }).then(() => loadFleet());
});
document.getElementById('fleetList').addEventListener('change', (event) => {
  const tierInput = event.target.closest('[data-fleet-tier]');
  if (!tierInput) return;
  post('setFleetVehicleMinTier', { model: tierInput.dataset.fleetTier, minTier: Number(tierInput.value || 0) }).then((result) => {
    if (!result?.ok) loadFleet();
  });
});

// ── 911 dispatch ─────────────────────────────────────────────────────────
// Citizens call in with /reportcrime (server/dispatch.lua); an on-duty
// officer with police.receive_dispatch sees the call arrive live (toast +
// map blip, client/dispatch.lua), can accept it here, and any officer who
// has accepted can resolve it. dispatchRefresh (below, in the message
// listener) keeps this list live if the tab is already open when a call
// changes.
let dispatchActiveCalls = [];
let dispatchHistory = [];

function timeAgo(epochSeconds) {
  const seconds = Math.max(0, Math.floor(Date.now() / 1000) - Number(epochSeconds || 0));
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  return `${Math.floor(seconds / 3600)}h ago`;
}

function renderDispatchActiveList() {
  const myCid = state?.self?.characterId;
  document.getElementById('policeDispatchActiveCount').textContent = dispatchActiveCalls.length;
  document.getElementById('policeDispatchAssignedCount').textContent = dispatchActiveCalls.filter((call) => (call.responders || []).length > 0).length;
  document.getElementById('dispatchActiveList').innerHTML = dispatchActiveCalls.map((call) => {
    const mine = myCid && (call.responders || []).find((r) => r.characterId === myCid);
    const responders = (call.responders || []).map((r) => `${esc(r.name)} (${r.status === 'en_route' ? 'En Route' : 'Accepted'})`).join(', ') || 'No one responding yet';
    return `<article class="dispatch-call-row">
      <div class="dispatch-call-main">
        <strong>${esc(call.details)}</strong>
        <small>Location: ${esc(call.location || 'Unknown')} · Caller: ${esc(call.callerName || 'Unknown')} · ${timeAgo(call.createdAt)}</small>
        <small>Responding: ${responders}</small>
      </div>
      <div class="dispatch-call-actions">
        ${!mine ? `<button class="mini" data-dispatch-accept="${call.id}">Accept</button>` : ''}
        ${mine && mine.status !== 'en_route' ? `<button class="mini" data-dispatch-enroute="${call.id}">En Route</button>` : ''}
        ${mine ? `<button class="mini" data-dispatch-resolve="${call.id}">Resolve</button>` : ''}
      </div>
    </article>`;
  }).join('') || '<article class="card">No active calls.</article>';
}

function renderDispatchHistoryList() {
  document.getElementById('dispatchHistoryList').innerHTML = dispatchHistory.map((row) => `<article class="dispatch-history-row"><strong>${esc(row.details)}</strong> · ${esc(row.status)}<small>Location: ${esc(row.location || 'Unknown')} · Caller: ${esc(row.callerName || 'Unknown')} · ${esc(row.createdAt)}${row.resolution ? ' · ' + esc(row.resolution) : ''}</small></article>`).join('') || '<article class="dispatch-history-row">No resolved calls yet.</article>';
}

async function loadDispatchActiveCalls() {
  const result = await post('dispatchActiveCalls');
  dispatchActiveCalls = result?.list || [];
  renderDispatchActiveList();
}

async function loadDispatchHistory() {
  const result = await post('dispatchHistory');
  dispatchHistory = result?.list || [];
  renderDispatchHistoryList();
}

// ── Armory (checkout list + admin enable/disable list) ──────────────────
let armoryAvailable = [];
let armoryManageList = [];
let armoryFilter = 'all';
let armorySelected = null;

function armoryImage(item) {
  return item?.image ? `<img src="${esc(item.image)}" alt="${esc(item.label)}" onerror="this.style.display='none'">` : '<span class="armory-no-image">CM</span>';
}

function renderArmoryFeature() {
  const item = armorySelected || armoryAvailable[0];
  const feature = document.getElementById('armoryFeature');
  if (!item) {
    feature.innerHTML = '<div class="armory-empty-feature"><b>CM POLICE</b><span>No equipment enabled</span></div>';
    return;
  }
  armorySelected = item;
  const type = item.itemType === 'armor' ? 'PROTECTIVE VEST' : item.itemType === 'ammo' ? 'DEPARTMENT AMMUNITION' : 'DEPARTMENT WEAPON';
  const stat = item.itemType === 'armor' ? `${Number(item.armorValue || 0)}% PROTECTION` : item.itemType === 'ammo' ? `${Number(item.issueAmount || 1)} ROUNDS / ISSUE` : String(item.category || 'WEAPON').toUpperCase();
  feature.innerHTML = `<div class="armory-feature-copy"><small>${type}</small><h2>${esc(item.label)}</h2><p>${esc(item.description || 'Department-issued equipment')}</p></div><div class="armory-feature-image">${armoryImage(item)}</div><div class="armory-feature-stats"><span>${esc(stat)}</span><span>STOCK <b>${Number(item.stock||0)}</b></span></div><button class="armory-checkout" data-armory-checkout="${esc(item.itemName)}" ${item.available?'':'disabled'}>${item.available?'CHECK OUT EQUIPMENT':'OUT OF STOCK'}</button>`;
}

function renderArmoryAvailable() {
  const rows = armoryAvailable.filter((item) => armoryFilter === 'all' || item.itemType === armoryFilter);
  document.getElementById('armoryAvailableList').innerHTML = rows.map((item) => `<article class="armory-item${armorySelected?.itemName === item.itemName ? ' selected' : ''}" data-armory-select="${esc(item.itemName)}"><div class="armory-item-image">${armoryImage(item)}</div><div class="armory-item-copy"><small>${item.itemType === 'armor' ? 'PROTECTIVE VEST' : item.itemType === 'ammo' ? 'AMMUNITION' : esc(String(item.category || 'weapon').toUpperCase())}</small><strong>${esc(item.label)}</strong><span>${Number(item.stock||0)} in stock · issue ${Number(item.issueAmount||1)}</span></div><button data-armory-checkout="${esc(item.itemName)}" ${item.available?'':'disabled'}>${item.available?'ISSUE':'EMPTY'}</button></article>`).join('') || '<div class="armory-empty">No equipment is enabled in this category.</div>';
  renderArmoryFeature();
}
async function loadArmoryAvailable() {
  const result = await post('armoryAvailable');
  armoryAvailable = result?.list || [];
  armorySelected = armoryAvailable.find((row) => row.itemName === armorySelected?.itemName) || armoryAvailable[0] || null;
  renderArmoryAvailable();
}

function renderArmoryManageList() {
  document.getElementById('armoryManageList').innerHTML = armoryManageList.map((w) => `<article class="card"><div class="armory-admin-image">${armoryImage(w)}</div><div><strong>${esc(w.label)}</strong><small>${w.itemType === 'armor' ? `Protective vest · ${Number(w.armorValue || 0)}%` : w.itemType === 'ammo' ? `Ammunition · ${Number(w.issueAmount || 1)} rounds` : `Weapon · ${esc(w.category || 'weapon')}`}</small></div><label><input type="checkbox" data-armory-toggle="${esc(w.itemName)}"${w.enabled ? ' checked' : ''}> Enabled</label></article>`).join('') || '<article class="card">No Gunstore weapons, ammunition, or protective vests found.</article>';
}
async function loadArmoryManageList() {
  const result = await post('armoryManageList');
  armoryManageList = result?.list || [];
  renderArmoryManageList();
}

document.getElementById('armoryAvailableList').addEventListener('click', async (event) => {
  const button = event.target.closest('[data-armory-checkout]');
  if (button) {
    const item = armoryAvailable.find((row) => row.itemName === button.dataset.armoryCheckout);
    if (!item || !(await showConfirmOverlay('Armory Checkout', `Check out ${item.label}? This issue will be recorded.`, 'Check Out', 'Cancel'))) return;
    await post('armoryCheckout', { itemName: item.itemName });
    return;
  }
  const card = event.target.closest('[data-armory-select]');
  if (!card) return;
  armorySelected = armoryAvailable.find((row) => row.itemName === card.dataset.armorySelect) || null;
  renderArmoryAvailable();
});
document.getElementById('armoryFeature').addEventListener('click', async (event) => {
  const button = event.target.closest('[data-armory-checkout]');
  if (!button) return;
  const item = armoryAvailable.find((row) => row.itemName === button.dataset.armoryCheckout);
  if (!item || !(await showConfirmOverlay('Armory Checkout', `Check out ${item.label}? This issue will be recorded.`, 'Check Out', 'Cancel'))) return;
  await post('armoryCheckout', { itemName: item.itemName });
});
document.querySelectorAll('[data-armory-filter]').forEach((button) => button.addEventListener('click', () => {
  armoryFilter = button.dataset.armoryFilter;
  document.querySelectorAll('[data-armory-filter]').forEach((row) => row.classList.toggle('active', row === button));
  renderArmoryAvailable();
}));
document.getElementById('armoryStandaloneClose').addEventListener('click', () => post('close'));
document.getElementById('armoryManageList').addEventListener('change', async (event) => {
  const box = event.target.closest('[data-armory-toggle]');
  if (!box) return;
  await post('setArmoryWeapon', { itemName: box.dataset.armoryToggle, enabled: box.checked });
  await Promise.all([loadArmoryAvailable(), loadArmoryManageList()]);
});
document.getElementById('armoryLoadStock').addEventListener('click', async (event) => {
  event.currentTarget.disabled = true;
  await post('loadArmoryStock');
  event.currentTarget.disabled = false;
  await Promise.all([loadArmoryAvailable(), loadArmoryManageList()]);
});

// ── ALPR camera locations (Overview page, manage_alpr only) ─────────────
let alprCameras = [];

function renderAlprCameraList() {
  document.getElementById('alprCameraList').innerHTML = alprCameras.map((cam) => `<article class="card"><div><strong>${esc(cam.label)}</strong></div><button class="mini danger" data-alpr-remove="${cam.id}">Delete</button></article>`).join('') || '<article class="card">No ALPR cameras placed yet.</article>';
}
async function loadAlprCameras() {
  const result = await post('alprCameraList');
  alprCameras = result?.list || [];
  renderAlprCameraList();
}
document.getElementById('addAlprCamera').addEventListener('click', async () => {
  // No custom label prompt -- FiveM's NUI browser doesn't reliably support
  // native window.prompt(). The server names it automatically (timestamp)
  // when no label is supplied, same as every other "stand here" action.
  await post('addAlprCamera', {});
  loadAlprCameras();
});
document.getElementById('alprCameraList').addEventListener('click', async (event) => {
  const button = event.target.closest('[data-alpr-remove]');
  if (!button) return;
  if (!(await showConfirmOverlay('Delete Camera', 'Delete this ALPR camera? This cannot be undone.', 'Delete', 'Cancel'))) return;
  await post('removeAlprCamera', { cameraId: Number(button.dataset.alprRemove) });
  loadAlprCameras();
});

// ── Barricade model catalog (Overview page's Barricades card) ───────────
let barricadeCatalog = [];
function renderBarricadeCatalogList() {
  document.getElementById('barricadeCatalogList').innerHTML = barricadeCatalog.map((entry) => `<article class="card"><div><strong>${esc(entry.modelName)}</strong></div><button class="mini danger" data-barricade-remove="${entry.id}">Delete</button></article>`).join('') || '<article class="card">No barricade models added yet.</article>';
}
async function loadBarricadeCatalog() {
  const result = await post('barricadeCatalogList');
  barricadeCatalog = result?.list || [];
  renderBarricadeCatalogList();
}
document.getElementById('addBarricadeModel').addEventListener('click', async () => {
  const modelName = document.getElementById('barricadeModelInput').value.trim();
  if (!modelName) return;
  const result = await post('addBarricadeModel', { modelName });
  if (result?.ok) {
    document.getElementById('barricadeModelInput').value = '';
    loadBarricadeCatalog();
  }
});
document.getElementById('barricadeCatalogList').addEventListener('click', async (event) => {
  const button = event.target.closest('[data-barricade-remove]');
  if (!button) return;
  if (!(await showConfirmOverlay('Delete Barricade Model', 'Delete this barricade model from the catalog? This cannot be undone.', 'Delete', 'Cancel'))) return;
  await post('removeBarricadeModel', { catalogId: Number(button.dataset.barricadeRemove) });
  loadBarricadeCatalog();
});

// ── Officer stats / leaderboard (Stats tab, police.view_logs only) ──────
function renderOfficerStatsList(list) {
  document.getElementById('officerStatsList').innerHTML = list.map((row, index) => `<article class="card"><div><strong>#${index + 1} ${esc(row.name)}</strong><small>CID ${esc(row.characterId)}</small></div><div>Arrests: ${esc(row.arrests)} · Citations: ${esc(row.citations)} · Calls: ${esc(row.callsCompleted)} · Avg response: ${esc(row.averageResponseMs ? Math.round(row.averageResponseMs / 1000) + 's' : '—')} · Impounds: ${esc(row.impounds)} · UOF: ${esc(row.useOfForce)} · Backup: ${esc(row.backupCalls)} · Panic: ${esc(row.panicActivations)} · BOLOs: ${esc(row.bolos)} · <strong>Total: ${esc(row.total)}</strong></div></article>`).join('') || '<article class="card">No recorded activity yet.</article>';
}
async function loadOfficerStats() {
  const result = await post('officerStats');
  renderOfficerStatsList(result?.list || []);
}

document.getElementById('dispatchActiveList').addEventListener('click', async (event) => {
  const accept = event.target.closest('[data-dispatch-accept]');
  const enRoute = event.target.closest('[data-dispatch-enroute]');
  const resolve = event.target.closest('[data-dispatch-resolve]');
  if (accept) {
    await post('dispatchAccept', { callId: Number(accept.dataset.dispatchAccept) });
    loadDispatchActiveCalls();
  }
  if (enRoute) {
    await post('dispatchEnRoute', { callId: Number(enRoute.dataset.dispatchEnroute) });
    loadDispatchActiveCalls();
  }
  if (resolve) {
    if (!(await showConfirmOverlay('Resolve Call', 'Mark this call as resolved and remove it from the active board?', 'Resolve', 'Cancel'))) return;
    const result = await post('dispatchResolve', { callId: Number(resolve.dataset.dispatchResolve) });
    if (result?.ok) { loadDispatchActiveCalls(); loadDispatchHistory(); }
  }
});

// ── Duty clothing (wardrobe presets) ────────────────────────────────────
// Presets are named clothing sets a police.manage_outfits manager saves from
// their own currently worn clothes (captured client-side -- the NUI has no
// access to ped component variations). Actually wearing one is no longer
// possible from here at all -- only in person at the admin-placed wardrobe
// NPC (client/wardrobe.lua), which also owns each officer's personal quick
// slots. This list is management-only reference + delete.
function renderOutfits() {
  const manage = state.capabilities?.manageOutfits === true;
  document.querySelectorAll('.manage-outfits-only').forEach((item) => { item.hidden = !manage; });
  const presets = state.outfitPresets || [];
  document.getElementById('outfitPresetList').innerHTML = presets.map((preset) => `<article class="member"><div class="member-main"><strong>${esc(preset.name)}</strong><small>Updated ${esc(preset.updatedAt)}</small></div><div class="member-actions">${manage ? `<button class="mini danger" data-outfit-delete="${preset.id}">Delete</button>` : ''}</div></article>`).join('')
    || `<article class="card">No clothing presets saved yet.${manage ? ' Save your current clothing above to create the first one.' : ' Ask a manager to save one.'}</article>`;
  const wardrobeNpc = state.wardrobeNpc || {};
  document.getElementById('wardrobeNpcStatus').textContent = wardrobeNpc.set
    ? 'Wardrobe NPC location is set.'
    : 'Wardrobe NPC location is not set -- officers cannot wear duty clothing until this is set.';
}

// ── Police Wardrobe dressing room ────────────────────────────────────────
// Items an admin tagged for the "police" job through the clothing store's
// own management panel (stored in cm-items, not cm-police). The room is a
// full-screen overlay (client/wardrobe.lua builds the camera); OPTION
// cycles distinct drawables for the active category, COLOR cycles texture
// variants of the selected drawable -- mirrors nv_cloth's own real store
// exactly, just reading cm-police's police-tagged catalog instead. Every
// arrow step calls the existing previewWardrobeItem callback (pure
// client-side ped preview, no server state, no inventory). Closing the
// room returns to this same Outfits tab, dashboard state untouched, so the
// existing "Save current clothing" button above captures the result.
let wardrobeItems = [];
let wardrobeCategories = [];
let wardrobeCategory = null;
let wardrobeOptionIndex = 0;
let wardrobeColorIndex = 0;
let wardrobeNpcMode = false;
let wardrobeFavorites = [];
let wardrobeMaxSlots = 5;
let wardrobeReturnToApp = false;

const wardrobeCategoryLabels = { hat: 'Headwear', torso: 'Outerwear', tshirt: 'Shirts', pants: 'Pants & shorts', shoes: 'Shoes', glasses: 'Glasses', mask: 'Masks', arms: 'Arms & gloves', bags: 'Bags', chains: 'Accessories', decals: 'Badges & decals', earrings: 'Earrings', watches: 'Watches', bracelet: 'Bracelets', armor: 'Armor & vests' };
const wardrobeCategoryIcons = { hat: '⌂', torso: '♜', tshirt: 'T', pants: 'Ⅱ', shoes: '⌁', glasses: '∞', mask: '◉', arms: '✦', bags: '▣', chains: '◇', decals: '★', earrings: '◌', watches: '◷', bracelet: '○', armor: '⬟' };
const wardrobeCategoryLabel = (category) => wardrobeCategoryLabels[category] || category.replace(/(^|_)([a-z])/g, (_, sep, letter) => (sep ? ' ' : '') + letter.toUpperCase());

function wardrobeDrawablesForCategory(category) {
  const seen = new Set();
  const list = [];
  wardrobeItems.forEach((item) => {
    if (item.category !== category || seen.has(item.drawableId)) return;
    seen.add(item.drawableId);
    list.push(item);
  });
  return list;
}

function wardrobeTexturesForDrawable(category, drawableId) {
  return wardrobeItems.filter((item) => item.category === category && item.drawableId === drawableId);
}

function renderWardrobeCategoryList() {
  document.getElementById('wardrobeCategoryList').innerHTML = wardrobeCategories.map((category) => `<button class="wardrobe-category-item${category === wardrobeCategory ? ' active' : ''}" data-wardrobe-category="${esc(category)}"><b>${esc(wardrobeCategoryIcons[category] || '•')}</b><span>${esc(wardrobeCategoryLabel(category))}</span></button>`).join('');
}

function applyWardrobeSelection() {
  const optionLabel = document.getElementById('wardrobeOptionLabel');
  const colorLabel = document.getElementById('wardrobeColorLabel');
  const drawables = wardrobeCategory ? wardrobeDrawablesForCategory(wardrobeCategory) : [];
  const current = drawables[wardrobeOptionIndex];
  if (!current) {
    optionLabel.textContent = '--';
    colorLabel.textContent = '--';
    return;
  }
  optionLabel.textContent = `${current.label || `Option ${current.drawableId}`} · ${wardrobeOptionIndex + 1}/${drawables.length}`;
  const textures = wardrobeTexturesForDrawable(wardrobeCategory, current.drawableId);
  const colorItem = textures[wardrobeColorIndex] || textures[0];
  colorLabel.textContent = colorItem ? `Color ${wardrobeColorIndex + 1}/${textures.length}` : '--';
  if (colorItem) {
    post('previewWardrobeItem', {
      componentType: colorItem.componentType,
      componentIndex: colorItem.componentIndex,
      drawableId: colorItem.drawableId,
      textureId: colorItem.textureId,
    });
  }
}

function selectWardrobeCategory(category) {
  wardrobeCategory = category;
  wardrobeOptionIndex = 0;
  wardrobeColorIndex = 0;
  renderWardrobeCategoryList();
  applyWardrobeSelection();
}

function moveWardrobeOption(delta) {
  const drawables = wardrobeCategory ? wardrobeDrawablesForCategory(wardrobeCategory) : [];
  if (drawables.length === 0) return;
  wardrobeOptionIndex = (wardrobeOptionIndex + delta + drawables.length) % drawables.length;
  wardrobeColorIndex = 0;
  applyWardrobeSelection();
}

function moveWardrobeColor(delta) {
  const drawables = wardrobeCategory ? wardrobeDrawablesForCategory(wardrobeCategory) : [];
  const current = drawables[wardrobeOptionIndex];
  if (!current) return;
  const textures = wardrobeTexturesForDrawable(wardrobeCategory, current.drawableId);
  if (textures.length === 0) return;
  wardrobeColorIndex = (wardrobeColorIndex + delta + textures.length) % textures.length;
  applyWardrobeSelection();
}

function renderWardrobeFavorites() {
  const bySlot = new Map(wardrobeFavorites.map((favorite) => [Number(favorite.slot), favorite]));
  document.getElementById('wardrobeFavoritesList').innerHTML = Array.from({ length: wardrobeMaxSlots }, (_, index) => {
    const slot = index + 1; const favorite = bySlot.get(slot);
    return favorite ? `<article class="wardrobe-favorite-slot"><strong>Slot ${slot}: ${esc(favorite.name)}</strong><small>Saved Police outfit</small><div class="wardrobe-favorite-slot-actions"><button class="mini" data-favorite-wear="${slot}">Wear</button><button class="mini danger" data-favorite-remove="${slot}">Remove</button></div></article>` : `<article class="wardrobe-favorite-slot"><strong>Slot ${slot}: Empty</strong><small>Add the current outfit to fill this slot.</small></article>`;
  }).join('');
}

async function openWardrobeRoom(mode = 'manager') {
  wardrobeNpcMode = mode === 'npc';
  wardrobeReturnToApp = !document.getElementById('app').hidden;
  const result = await post(wardrobeNpcMode ? 'openPoliceNpcCloset' : 'openWardrobeDressingRoom');
  if (!result?.ok) return;
  wardrobeItems = (result.items || []).map((item) => ({ ...item, category: item.category || 'other' }));
  wardrobeCategories = [...new Set(wardrobeItems.map((item) => item.category))].sort();
  wardrobeCategory = wardrobeCategories[0] || null;
  wardrobeOptionIndex = 0;
  wardrobeColorIndex = 0;
  wardrobeFavorites = result.favorites || [];
  wardrobeMaxSlots = Number(result.maxSlots || 5);
  document.getElementById('wardrobeFavoriteActions').hidden = !wardrobeNpcMode;
  document.getElementById('wardrobeFavorites').hidden = true;
  renderWardrobeFavorites();
  renderWardrobeCategoryList();
  applyWardrobeSelection();
  document.getElementById('app').hidden = true;
  document.getElementById('wardrobeRoom').hidden = false;
}

async function closeWardrobeRoom() {
  document.getElementById('wardrobeRoom').hidden = true;
  document.getElementById('app').hidden = !wardrobeReturnToApp;
  await post('closeWardrobeDressingRoom');
  wardrobeNpcMode = false;
}

document.getElementById('openWardrobeRoom')?.addEventListener('click', () => openWardrobeRoom());
document.getElementById('wardrobeDone')?.addEventListener('click', async () => {
  if (wardrobeNpcMode) {
    const result = await post('finishWardrobeDuty');
    if (!result?.ok) return;
  }
  await closeWardrobeRoom();
});
document.getElementById('wardrobeCategoryList')?.addEventListener('click', (event) => {
  const button = event.target.closest('[data-wardrobe-category]');
  if (button) selectWardrobeCategory(button.dataset.wardrobeCategory);
});
document.getElementById('wardrobeOptionPrev')?.addEventListener('click', () => moveWardrobeOption(-1));
document.getElementById('wardrobeOptionNext')?.addEventListener('click', () => moveWardrobeOption(1));
document.getElementById('wardrobeColorPrev')?.addEventListener('click', () => moveWardrobeColor(-1));
document.getElementById('wardrobeColorNext')?.addEventListener('click', () => moveWardrobeColor(1));
document.getElementById('wardrobeAddFavorite')?.addEventListener('click', async () => {
  const name = document.getElementById('wardrobeFavoriteName').value.trim();
  const result = await post('saveWardrobeFavorite', { name });
  if (result?.ok) { wardrobeFavorites = result.favorites || []; document.getElementById('wardrobeFavoriteName').value = ''; renderWardrobeFavorites(); }
});
document.getElementById('wardrobeSelectedClothes')?.addEventListener('click', () => { document.getElementById('wardrobeFavorites').hidden = false; });
document.getElementById('wardrobeFavoritesClose')?.addEventListener('click', () => { document.getElementById('wardrobeFavorites').hidden = true; });
document.getElementById('wardrobeFavoritesList')?.addEventListener('click', async (event) => {
  const wear = event.target.closest('[data-favorite-wear]'); const remove = event.target.closest('[data-favorite-remove]');
  if (wear) await post('wearWardrobeFavorite', { slot: Number(wear.dataset.favoriteWear) });
  if (remove) { const result = await post('removeWardrobeFavorite', { slot: Number(remove.dataset.favoriteRemove) }); if (result?.ok) { wardrobeFavorites = result.favorites || []; renderWardrobeFavorites(); } }
});

// Drag-to-rotate -- same mousedown/mousemove-delta approach nv_cloth's own
// real store uses (there is no A/D key polling under the hood).
(() => {
  const viewport = document.getElementById('wardrobeViewport');
  if (!viewport) return;
  let dragging = false;
  let lastX = 0;
  viewport.addEventListener('mousedown', (event) => { dragging = true; lastX = event.clientX; });
  window.addEventListener('mouseup', () => { dragging = false; });
  window.addEventListener('mousemove', (event) => {
    if (!dragging) return;
    const dx = event.clientX - lastX;
    lastX = event.clientX;
    post('rotateWardrobePed', { delta: -dx * 0.45 });
  });
})();

document.getElementById('saveOutfitPreset').onclick = async () => {
  const nameInput = document.getElementById('outfitPresetName');
  const name = nameInput.value.trim();
  if (!name) return;
  const result = await post('action', { action: 'save_outfit_preset', payload: { name } });
  if (result?.ok) nameInput.value = '';
};
document.getElementById('outfitPresetList').onclick = async (event) => {
  const del = event.target.closest('[data-outfit-delete]');
  if (del) {
    if (!(await showConfirmOverlay('Delete Clothing Preset', 'Delete this Police clothing preset? This cannot be undone.', 'Delete', 'Cancel'))) return;
    post('action', { action: 'delete_outfit_preset', payload: { presetId: Number(del.dataset.outfitDelete) } });
  }
};

// ── MDT records lookup ───────────────────────────────────────────────────
// All search-driven, on demand -- nothing to preload when the tab opens
// (mirrors the Fleet tab's own on-demand fetch shape, just with no default
// list until the officer actually searches).
let mdtResults = [];
let mdtProfile = null;
let mdtVehicleResult = null;

function renderMdtResults() {
  document.getElementById('mdtResults').innerHTML = mdtResults.map((row) => `<article class="mdt-result-row" data-mdt-cid="${esc(row.characterId)}"><div><strong>${esc(row.name)}</strong><small>CID ${esc(row.characterId)}</small></div><div class="mdt-result-badges">${row.stars ? `<span class="mdt-result-stars">${'★'.repeat(row.stars)}</span>` : ''}${row.wanted ? '<span class="mdt-result-wanted">WANTED</span>' : ''}</div></article>`).join('') || '<article class="card">No matches.</article>';
}

async function mdtSearch() {
  const query = document.getElementById('mdtQuery').value.trim();
  if (!query) return;
  const result = await post('mdtSearch', { query });
  mdtResults = result?.results || [];
  renderMdtResults();
}

function renderMdtStars() {
  const stars = mdtProfile?.criminalStars || 0;
  document.getElementById('mdtStars').innerHTML = [1, 2, 3, 4, 5].map((n) => `<button class="mdt-star${n <= stars ? ' filled' : ''}" data-mdt-star="${n}">★</button>`).join('');
}

function renderMdtViolationOptions() {
  document.getElementById('mdtViolationSelect').innerHTML = (state?.violations || []).map((v) => `<option value="${esc(v.id)}">${esc(v.label)} · $${esc(v.fine)}</option>`).join('');
}

function renderMdtProfile() {
  const card = document.getElementById('mdtProfileCard');
  if (!mdtProfile) { card.hidden = true; return; }
  card.hidden = false;
  document.getElementById('mdtProfileName').textContent = `${mdtProfile.name} · CID ${mdtProfile.characterId}`;
  const wantedButton = document.getElementById('mdtWantedToggle');
  wantedButton.textContent = mdtProfile.wanted ? 'Clear Wanted' : 'Mark Wanted';
  wantedButton.classList.toggle('active', mdtProfile.wanted === true);
  renderMdtStars();
  renderMdtViolationOptions();
  document.getElementById('mdtCitations').innerHTML = (mdtProfile.citations || []).map((c) => `<article class="mdt-record-row"><strong>${esc(c.violation_label)}</strong> · $${esc(c.fine)}<small>${esc(c.createdAt)}</small></article>`).join('') || '<article class="mdt-record-row">No citations.</article>';
  document.getElementById('mdtBookings').innerHTML = (mdtProfile.bookings || []).map((b) => `<article class="mdt-record-row"><strong>${b.releasedAt ? 'Released' : b.handoffStatus === 'failed' ? 'Failed' : b.handoffStatus === 'processing' ? 'Processing' : 'Active'} · ${esc(b.sentenceMinutes)} min · ${esc(b.wantedStars)} star(s)</strong><small>Booked ${esc(b.bookedAt)}${b.reason ? ' · Reason: ' + esc(b.reason) : ''}${b.charges ? ' · Charges: ' + esc(b.charges) : ''} · Handoff: ${esc(b.handoffStatus)}${b.releaseReason ? ' · Release: ' + esc(b.releaseReason) : ''}</small></article>`).join('') || '<article class="mdt-record-row">No bookings.</article>';
  document.getElementById('mdtImpounds').innerHTML = (mdtProfile.impounds || []).map((i) => `<article class="mdt-record-row"><strong>${esc(i.plate)}</strong> · $${esc(i.fee)}<small>${i.releasedAt ? `Released` : 'Still impounded'} · ${esc(i.impoundedAt)}</small></article>`).join('') || '<article class="mdt-record-row">No impound history.</article>';
  document.getElementById('mdtVehicles').innerHTML = (mdtProfile.vehicles || []).map((v) => `<article class="mdt-record-row"><strong>${esc(v.plate)}</strong> · ${esc(v.model)}<small>${esc(v.locationState)}</small></article>`).join('') || '<article class="mdt-record-row">No registered vehicles.</article>';
  document.getElementById('mdtNotes').innerHTML = (mdtProfile.notes || []).map((n) => {
    const mine = n.authorCid && state?.self?.characterId && n.authorCid === state.self.characterId;
    return `<article class="mdt-note-row"><div class="mdt-note-text">${esc(n.note)}<small>${esc(n.authorName)} · ${esc(n.createdAt)}</small></div>${mine ? `<button class="mini danger" data-mdt-note-delete="${n.id}">Delete</button>` : ''}</article>`;
  }).join('') || '<article class="mdt-note-row">No notes yet.</article>';
}

async function mdtLoadProfile(characterId) {
  const result = await post('mdtCitizenProfile', { characterId });
  mdtProfile = result?.profile || null;
  renderMdtProfile();
}

async function mdtAddNote() {
  if (!mdtProfile) return;
  const input = document.getElementById('mdtNoteInput');
  const note = input.value.trim();
  if (!note) return;
  const result = await post('mdtAddNote', { characterId: mdtProfile.characterId, note });
  if (result?.ok) { input.value = ''; mdtLoadProfile(mdtProfile.characterId); }
}

async function mdtSetStars(stars) {
  if (!mdtProfile) return;
  // Clicking the currently-set star again clears the rating to 0.
  const next = mdtProfile.criminalStars === stars ? 0 : stars;
  const result = await post('mdtSetCriminalStatus', { characterId: mdtProfile.characterId, stars: next, wanted: mdtProfile.wanted === true });
  if (result?.ok) { mdtProfile.criminalStars = result.stars; mdtProfile.wanted = result.wanted; renderMdtStars(); }
}

async function mdtToggleWanted() {
  if (!mdtProfile) return;
  const settingWanted = !mdtProfile.wanted;
  if (settingWanted && !(await showConfirmOverlay('Mark Wanted', 'Mark this citizen as wanted? This drives their in-game wanted behavior.', 'Mark Wanted', 'Cancel'))) return;
  const result = await post('mdtSetCriminalStatus', { characterId: mdtProfile.characterId, stars: mdtProfile.criminalStars || 0, wanted: settingWanted });
  if (result?.ok) {
    mdtProfile.criminalStars = result.stars;
    mdtProfile.wanted = result.wanted;
    const wantedButton = document.getElementById('mdtWantedToggle');
    wantedButton.textContent = mdtProfile.wanted ? 'Clear Wanted' : 'Mark Wanted';
    wantedButton.classList.toggle('active', mdtProfile.wanted === true);
  }
}

async function mdtIssueFine() {
  if (!mdtProfile) return;
  const violationId = document.getElementById('mdtViolationSelect').value;
  if (!violationId) return;
  const violation = (state?.violations || []).find((v) => v.id === violationId);
  if (!(await showConfirmOverlay('Issue Fine', `Fine ${mdtProfile.name} $${violation ? violation.fine : ''} for ${violation ? violation.label : 'this violation'}?`, 'Issue Fine', 'Cancel'))) return;
  const result = await post('mdtIssueFine', { characterId: mdtProfile.characterId, violationId });
  if (result?.ok) mdtLoadProfile(mdtProfile.characterId);
}

function renderMdtVehicleResult() {
  const el = document.getElementById('mdtVehicleResult');
  if (!mdtVehicleResult) { el.innerHTML = '<article class="card">No vehicle found for that plate.</article>'; return; }
  const v = mdtVehicleResult;
  el.innerHTML = `<article class="mdt-vehicle-card">
    <strong>${esc(v.plate)}</strong> · ${esc(v.model)}
    <small>Owner: ${esc(v.ownerName)}${v.ownerCid ? ` (CID ${esc(v.ownerCid)})` : ''}</small>
    <small>Status: ${esc(v.locationState)}</small>
    ${v.impound ? `<span class="impound-tag">Impounded · $${esc(v.impound.fee)} fee · ${esc(v.impound.impoundedAt)}</span>` : ''}
  </article>`;
}

async function mdtVehicleSearch() {
  const plate = document.getElementById('mdtPlateQuery').value.trim();
  if (!plate) return;
  const result = await post('mdtVehicleSearch', { plate });
  mdtVehicleResult = result?.vehicle || null;
  renderMdtVehicleResult();
}

document.getElementById('mdtSearchButton')?.addEventListener('click', () => mdtSearch());
document.getElementById('mdtResults')?.addEventListener('click', (event) => {
  const row = event.target.closest('[data-mdt-cid]');
  if (row) mdtLoadProfile(row.dataset.mdtCid);
});
document.getElementById('mdtAddNoteButton')?.addEventListener('click', () => mdtAddNote());
document.getElementById('mdtWantedToggle')?.addEventListener('click', () => mdtToggleWanted());
document.getElementById('mdtStars')?.addEventListener('click', (event) => {
  const button = event.target.closest('[data-mdt-star]');
  if (button) mdtSetStars(Number(button.dataset.mdtStar));
});
document.getElementById('mdtIssueFineButton')?.addEventListener('click', () => mdtIssueFine());
document.getElementById('mdtNotes')?.addEventListener('click', async (event) => {
  const del = event.target.closest('[data-mdt-note-delete]');
  if (!del) return;
  if (!(await showConfirmOverlay('Delete Note', 'Delete this MDT note? This cannot be undone.', 'Delete', 'Cancel'))) return;
  const result = await post('mdtDeleteNote', { noteId: Number(del.dataset.mdtNoteDelete) });
  if (result?.ok && mdtProfile) mdtLoadProfile(mdtProfile.characterId);
});
document.getElementById('mdtPlateSearchButton')?.addEventListener('click', () => mdtVehicleSearch());

function render() {
  if (!state) return;
  const self = state.self;
  const permissions = self?.permissions || {};
  const capabilities = state.capabilities || {};
  document.getElementById('memberRank').textContent = self?.rankName || (state.adminMode ? 'Administrator' : 'Organization');
  document.querySelectorAll('.admin-only').forEach((item) => { item.hidden = !state.adminMode; });
  document.querySelectorAll('.logs-only').forEach((item) => { item.hidden = state.canViewLogs !== true; });
  if (page === 'logs' && state.canViewLogs !== true) page = 'overview';
  if (page === 'stats' && state.canViewLogs !== true) page = 'overview';
  if (page === 'stats') loadOfficerStats();
  const canFleet = capabilities.manageVehicles === true || capabilities.spawnVehicles === true;
  document.querySelectorAll('.fleet-only').forEach((item) => { item.hidden = !canFleet || !fleetStandalone; });
  if (page === 'fleet' && !canFleet) page = 'overview';
  document.querySelectorAll('.mdt-only').forEach((item) => { item.hidden = capabilities.useMdt !== true; });
  if (page === 'mdt' && capabilities.useMdt !== true) page = 'overview';
  document.querySelectorAll('.dispatch-only').forEach((item) => { item.hidden = capabilities.receiveDispatch !== true; });
  if (page === 'dispatch' && capabilities.receiveDispatch !== true) page = 'overview';
  if (page === 'dispatch') { loadDispatchActiveCalls(); loadDispatchHistory(); }
  document.querySelectorAll('.armory-only').forEach((item) => { item.hidden = !armoryStandalone || capabilities.useArmory !== true; });
  document.querySelectorAll('.manage-armory-only').forEach((item) => { item.hidden = capabilities.manageArmory !== true; });
  if (page === 'armory' && capabilities.useArmory !== true) page = 'overview';
  if (page === 'armory') loadArmoryAvailable();
  if (page === 'admin' && state.adminMode) loadArmoryManageList();
  const online = state.members.filter((member) => member.online).length;
  const duty = state.members.filter((member) => member.onDuty).length;
  document.getElementById('stats').innerHTML = `
    <div class="stat"><span>POLICE LEADER</span><strong>${esc(state.organization.leaderName)}</strong><small>CID ${esc(state.organization.leaderCid || '—')}</small></div>
    <div class="stat"><span>MEMBERS</span><strong>${state.members.length}</strong><small>${online} online</small></div>
    <div class="stat"><span>ON DUTY</span><strong>${duty}</strong><small>Available now</small></div>
    <div class="stat"><span>YOUR RANK</span><strong>${esc(self?.rankName || 'Admin')}</strong><small>${self ? `Tier ${self.tier}` : 'Management access'}</small></div>
    ${capabilities.viewFund ? `<div class="stat"><span>DEPARTMENT FUND</span><strong>$${esc((state.fund?.balance ?? 0).toLocaleString())}</strong><small>From citations</small></div>` : ''}`;

  document.getElementById('memberMap').hidden = capabilities.viewMemberMap !== true;
  document.getElementById('meetingPoint').hidden = capabilities.setMeeting !== true;
  document.querySelectorAll('.manage-alpr-only').forEach((item) => { item.hidden = capabilities.manageAlpr !== true; });
  document.querySelectorAll('.manage-impound-only').forEach((item) => { item.hidden = capabilities.manageImpound !== true; });
  document.querySelectorAll('.manage-barricades-only').forEach((item) => { item.hidden = capabilities.manageBarricades !== true; });
  if (capabilities.manageAlpr) loadAlprCameras();
  if (state.adminMode && capabilities.manageBarricades) loadBarricadeCatalog();
  const impoundKiosk = state.impoundKiosk || {};
  document.getElementById('impoundKioskStatus').textContent = impoundKiosk.set
    ? `${Number(impoundKiosk.count) || 1} Impound Operator(s) configured.`
    : 'No Impound Operators configured — delivery and release are disabled.';

  document.getElementById('members').innerHTML = state.members.map((member) => {
    const lower = self && (self.isLeader || self.tier > member.tier) && !member.isLeader;
    const canSuspend = lower && (self.isLeader || permissions['police.suspend_members']);
    const canSignOff = (self.isLeader || capabilities.signOffCadets) && !member.ftoSignedOff;
    return `<article class="member"><div class="avatar">${esc(member.name.slice(0, 1).toUpperCase())}</div><div class="member-main"><strong>${esc(member.name)}</strong><small>CID ${esc(member.characterId)} · ${esc(member.rankName)} · ${member.online ? 'Online' : 'Offline'}${member.onDuty ? ` · On duty · ${member.radioStatus === '10-6' ? '10-6' : '10-8'}` : ''}${member.suspended ? ' · Suspended' : ''}${member.ftoSignedOff === false ? ' · FTO restricted' : ''}</small></div><div class="member-actions">${lower && (self.isLeader || permissions['police.promote']) ? `<button class="mini" data-action="promote" data-cid="${esc(member.characterId)}">Promote</button>` : ''}${lower && (self.isLeader || permissions['police.demote']) ? `<button class="mini danger" data-action="demote" data-cid="${esc(member.characterId)}">Demote</button>` : ''}${canSignOff ? `<button class="mini" data-action="sign_off_cadet" data-cid="${esc(member.characterId)}">Sign Off</button>` : ''}${canSuspend ? (member.suspended ? `<button class="mini" data-action="reinstate_member" data-cid="${esc(member.characterId)}">Reinstate</button>` : `<button class="mini danger" data-action="suspend_member" data-cid="${esc(member.characterId)}">Suspend</button>`) : ''}${lower && (self.isLeader || permissions['police.kick']) ? `<button class="mini danger" data-action="kick" data-cid="${esc(member.characterId)}">Remove</button>` : ''}</div></article>`;
  }).join('') || '<article class="card">No Police members.</article>';

  document.getElementById('newRank').hidden = !self || capabilities.manageRanks !== true;
  document.getElementById('ranks').innerHTML = state.ranks.map((rank) => {
    const manageable = self && !rank.isLeader && rank.tier < self.tier && capabilities.manageRanks === true;
    const permissionBadges = Object.keys(rank.permissions || {}).filter((key) => rank.permissions[key]).map((key) => `<span class="permission">${esc(state.permissions[key] || key)}</span>`).join('');
    return `<article class="rank"><div class="rank-head"><h4>${esc(rank.name)} · Tier ${rank.tier}${rank.isLeader ? ' · ALL PERMISSIONS' : ''}</h4><div class="rank-actions">${manageable ? `<button class="mini" data-rank-edit="${rank.id}">Edit</button><button class="mini danger" data-rank-delete="${rank.id}">Delete</button>` : ''}</div></div><div class="permissions">${permissionBadges || '<span class="permission">No permissions</span>'}</div></article>`;
  }).join('');

  renderOutfits();

  const actionNames = {
    duty_started: 'Started duty', duty_ended: 'Ended duty',
    outfit_preset_created: 'Created clothing preset', outfit_preset_updated: 'Updated clothing preset',
    outfit_preset_deleted: 'Deleted clothing preset', outfit_chosen: 'Chose Police clothing',
    rank_created: 'Created rank', rank_updated: 'Updated rank', rank_deleted: 'Deleted rank',
    member_promoted: 'Promoted member', member_demoted: 'Demoted member', member_removed: 'Removed member',
    invite_sent: 'Sent invitation', invite_accepted: 'Accepted invitation', leader_assigned: 'Assigned Police leader',
    meeting_point_set: 'Set meeting point',
    admin_member_hired: 'Hired member', admin_member_fired: 'Fired member',
    member_suspended: 'Suspended member', member_reinstated: 'Reinstated member',
    fleet_vehicle_location_saved: 'Saved fleet vehicle location', fleet_vehicle_spawned: 'Spawned fleet vehicle',
    fleet_vehicle_min_tier_set: 'Changed fleet vehicle minimum tier', fleet_recalled_all: 'Recalled the fleet',
    holding_cell_set: 'Set holding cell location', suspect_booked: 'Booked a suspect', suspect_released: 'Released a suspect from holding',
    citation_issued: 'Issued a citation',
    vehicle_impounded: 'Impounded a vehicle', vehicle_towed: 'Towed an untracked vehicle',
    vehicle_released_from_impound: 'Released a vehicle from impound',
    mdt_note_added: 'Added an MDT note', mdt_note_deleted: 'Deleted an MDT note',
  };
  const describe = (detail = {}) => {
    const parts = [];
    if (detail.targetCid) parts.push(`Target CID ${esc(detail.targetCid)}`);
    if (detail.name) parts.push(esc(detail.name));
    if (detail.rank) parts.push(esc(detail.rank));
    if (detail.tier !== undefined) parts.push(`Tier ${esc(detail.tier)}`);
    if (detail.sex) parts.push(`${esc(detail.sex)} clothing`);
    if (detail.presetId !== undefined) parts.push(`Preset #${esc(detail.presetId)}`);
    if (detail.model) parts.push(esc(detail.model));
    if (detail.minutes !== undefined) parts.push(`${esc(detail.minutes)} minute(s)`);
    if (detail.recipients !== undefined) parts.push(`${esc(detail.recipients)} notified`);
    if (detail.auto) parts.push('Automatic');
    if (detail.violation) parts.push(esc(detail.violation));
    if (detail.fine !== undefined) parts.push(`$${esc(detail.fine)}`);
    if (detail.plate) parts.push(`Plate ${esc(detail.plate)}`);
    if (detail.ownerCid) parts.push(`Owner CID ${esc(detail.ownerCid)}`);
    if (detail.fee !== undefined) parts.push(`$${esc(detail.fee)}`);
    return parts.join(' · ') || 'No additional details';
  };
  document.getElementById('logs').innerHTML = (state.logs || []).map((entry) => `<article class="log-row"><div class="log-who"><strong>${esc(entry.actorName)}</strong><small>${entry.actorCid ? `CID ${esc(entry.actorCid)}` : 'System'}</small></div><div><strong class="log-action">${esc(actionNames[entry.action] || entry.action)}</strong><small>${describe(entry.detail)}</small></div><time>${esc(entry.createdAt)}</time></article>`).join('') || '<article class="card">No Police activity has been recorded yet.</article>';
  if (state.adminMode) {
    document.getElementById('staffRank').innerHTML = state.ranks.filter((rank) => !rank.isLeader).map((rank) => `<option value="${rank.id}">${esc(rank.name)} · Tier ${rank.tier}</option>`).join('');
  }
  showPage(page);
}

document.querySelectorAll('.nav').forEach((item) => { item.onclick = () => showPage(item.dataset.page); });
document.getElementById('close').onclick = () => post('close');
document.getElementById('memberMap').onclick = () => post('action', { action: 'toggle_member_map', payload: {} });
document.getElementById('meetingPoint').onclick = () => post('action', { action: 'set_meeting', payload: {} });
document.getElementById('setImpoundKiosk').onclick = () => post('action', { action: 'set_impound_kiosk', payload: {} });
document.getElementById('resetImpoundKiosks').onclick = async () => {
  if (!(await showConfirmOverlay('Reset Impound Operators', 'Remove every configured Impound Operator NPC?', 'Reset All', 'Cancel'))) return;
  post('action', { action: 'reset_impound_kiosks', payload: {} });
};
document.getElementById('setWardrobeNpc').onclick = () => post('action', { action: 'set_wardrobe_npc', payload: {} });
document.getElementById('recallFleet').onclick = async () => {
  if (!(await showConfirmOverlay('Recall Fleet', 'Recall every free Police fleet vehicle back to its spawn point?', 'Recall', 'Cancel'))) return;
  post('recallAllFleetVehicles', {});
};
document.getElementById('assignLeader').onclick = async () => {
  const characterId = document.getElementById('leaderCid').value;
  if (!(await showConfirmOverlay('Assign Leader', `Hand over full Police leadership to character ID ${characterId}? This replaces the current leader immediately.`, 'Assign Leader', 'Cancel'))) return;
  post('assignLeader', { characterId });
};
const staffActionConfirm = {
  fire: ['Fire Member', 'Remove this character from Police? This cannot be undone.', 'Fire'],
  suspend: ['Suspend Member', 'Suspend this character from Police duty?', 'Suspend'],
};
document.querySelectorAll('[data-staff-action]').forEach((button) => {
  button.onclick = async () => {
    const confirmArgs = staffActionConfirm[button.dataset.staffAction];
    if (confirmArgs && !(await showConfirmOverlay(...confirmArgs, 'Cancel'))) return;
    post('adminStaffAction', { action: button.dataset.staffAction, characterId: document.getElementById('staffCid').value, rankId: Number(document.getElementById('staffRank').value), minutes: Number(document.getElementById('staffMinutes').value), reason: document.getElementById('staffReason').value });
  };
});
document.getElementById('adminSetBookingDesk').onclick = async () => {
  if (!(await showConfirmOverlay('Set Booking Desk', 'Use your current position as the secure Police booking desk?', 'Save Location', 'Cancel'))) return;
  await post('setPoliceAdminLocation', { locationType: 'booking_desk', name: document.getElementById('adminBookingName').value });
  loadPoliceAdminConfig();
};
document.getElementById('adminSetJailIntake').onclick = async () => {
  if (!(await showConfirmOverlay('Set Jail Intake', 'Send newly booked prisoners to your current position after prison confirms custody?', 'Save Location', 'Cancel'))) return;
  await post('setPoliceAdminLocation', { locationType: 'jail_intake', name: document.getElementById('adminJailName').value });
  loadPoliceAdminConfig();
};
document.getElementById('adminAddJailSpawn').onclick = async () => {
  if (!(await showConfirmOverlay('Add Jail Spawn', 'Use your current position as a jail spawn with capacity for two prisoners?', 'Add Spawn', 'Cancel'))) return;
  await post('setPoliceAdminLocation', { locationType: 'jail_spawn', name: 'Jail Spawn' });
  loadPoliceAdminConfig();
};
document.getElementById('adminResetJailSpawns').onclick = async () => {
  if (!(await showConfirmOverlay('Reset Jail Spawns', 'Remove every configured jail spawn?', 'Reset All', 'Cancel'))) return;
  await post('resetPoliceAdminLocation', { locationType: 'jail_spawns' });
  loadPoliceAdminConfig();
};
document.getElementById('adminSetServiceNpc').onclick = async () => {
  if (!(await showConfirmOverlay('Set Police Front Desk', 'Spawn the public Police service NPC at your current position and heading?', 'Save Location', 'Cancel'))) return;
  await post('setPoliceAdminLocation', { locationType: 'service_npc', name: document.getElementById('adminServiceNpcName').value });
  loadPoliceAdminConfig();
};
const setFacilityNpc = async (locationType, title) => {
  if (!(await showConfirmOverlay(title, 'Spawn this Police facility NPC at your current position and heading?', 'Save Location', 'Cancel'))) return;
  await post('setPoliceAdminLocation', { locationType });
  loadPoliceAdminConfig();
};
document.getElementById('adminSetArmoryNpc').onclick = () => setFacilityNpc('armory_npc', 'Set Armory NPC');
document.getElementById('adminSetStorageNpc').onclick = () => setFacilityNpc('storage_npc', 'Set Storage NPC');
document.getElementById('adminSetClothingNpc').onclick = async () => {
  if (!(await showConfirmOverlay('Set Clothing NPC', 'Move the Police wardrobe NPC to your current position and heading?', 'Save Location', 'Cancel'))) return;
  await post('action', { action: 'set_wardrobe_npc', payload: {} });
  loadPoliceAdminConfig();
};
document.getElementById('adminOpenClothingMenu').onclick = async () => {
  await post('openPoliceClothingAdmin', {});
};
const locationButton = (id, callback, locationType) => {
  document.getElementById(id).onclick = async () => {
    if (callback === 'resetPoliceAdminLocation' && !(await showConfirmOverlay('Reset Location', 'Remove this configured location?', 'Reset', 'Cancel'))) return;
    await post(callback, { locationType });
    if (callback === 'resetPoliceAdminLocation') loadPoliceAdminConfig();
  };
};
locationButton('adminPreviewBookingDesk', 'previewPoliceAdminLocation', 'booking_desk');
locationButton('adminTeleportBookingDesk', 'teleportPoliceAdminLocation', 'booking_desk');
locationButton('adminResetBookingDesk', 'resetPoliceAdminLocation', 'booking_desk');
locationButton('adminPreviewJailIntake', 'previewPoliceAdminLocation', 'jail_intake');
locationButton('adminTeleportJailIntake', 'teleportPoliceAdminLocation', 'jail_intake');
locationButton('adminResetJailIntake', 'resetPoliceAdminLocation', 'jail_intake');
locationButton('adminPreviewServiceNpc', 'previewPoliceAdminLocation', 'service_npc');
locationButton('adminTeleportServiceNpc', 'teleportPoliceAdminLocation', 'service_npc');
locationButton('adminResetServiceNpc', 'resetPoliceAdminLocation', 'service_npc');
locationButton('adminPreviewArmoryNpc', 'previewPoliceAdminLocation', 'armory_npc');
locationButton('adminTeleportArmoryNpc', 'teleportPoliceAdminLocation', 'armory_npc');
locationButton('adminResetArmoryNpc', 'resetPoliceAdminLocation', 'armory_npc');
locationButton('adminPreviewStorageNpc', 'previewPoliceAdminLocation', 'storage_npc');
locationButton('adminTeleportStorageNpc', 'teleportPoliceAdminLocation', 'storage_npc');
locationButton('adminResetStorageNpc', 'resetPoliceAdminLocation', 'storage_npc');
document.getElementById('adminReleaseCustody').onclick = async () => {
  const characterId = document.getElementById('adminCustodyReleaseCid').value;
  if (!(await showConfirmOverlay('Clear Police Custody', `Release cuffed or processing custody for character ${characterId}?`, 'Release', 'Cancel'))) return;
  await post('adminReleasePoliceCustody', { characterId });
};
document.getElementById('adminRefreshPrisoners').onclick = loadAdminPrisoners;
document.getElementById('adminPrisonerList').onclick = async (event) => {
  const button = event.target.closest('[data-prison-action]');
  if (!button) return;
  const action = button.dataset.prisonAction;
  const characterId = button.dataset.cid;
  const input = document.querySelector(`[data-prison-minutes="${CSS.escape(characterId)}"]`);
  const minutes = Math.floor(Number(input?.value) || 0);
  const confirmed = action === 'release'
    ? await showConfirmOverlay('Release Prisoner', `Immediately release character ${characterId} from jail?`, 'Release', 'Cancel')
    : await showConfirmOverlay('Reduce Sentence', `Remove ${minutes} minute(s) from character ${characterId}'s sentence?`, 'Reduce Time', 'Cancel');
  if (!confirmed) return;
  const result = await post('adminPrisonAction', { action, characterId, minutes });
  if (result?.ok) loadAdminPrisoners();
};
document.getElementById('adminSaveBookingRules').onclick = async () => {
  if (!(await showConfirmOverlay('Save Booking Rules', 'Apply these sentence, distance, and prison handoff settings immediately?', 'Save Rules', 'Cancel'))) return;
  await post('savePoliceAdminRules', {
    minutesPerStar: Number(document.getElementById('adminMinutesPerStar').value),
    bookingRadius: Number(document.getElementById('adminBookingRadius').value),
    handoffTimeoutMs: Number(document.getElementById('adminHandoffTimeout').value),
  });
  loadPoliceAdminConfig();
};
document.getElementById('adminSaveCinematics').onclick = async () => {
  if (!(await showConfirmOverlay('Save Cinematic Settings', 'Apply these camera, sound and timing settings to every Police cinematic?', 'Save Settings', 'Cancel'))) return;
  await post('savePoliceAdminRules', {
    minutesPerStar: Number(document.getElementById('adminMinutesPerStar').value),
    bookingRadius: Number(document.getElementById('adminBookingRadius').value),
    handoffTimeoutMs: Number(document.getElementById('adminHandoffTimeout').value),
    cinematicRules: {
      enabled: document.getElementById('adminCinematicEnabled').checked,
      allowSkip: document.getElementById('adminCinematicSkip').checked,
      cameraCollision: document.getElementById('adminCinematicCollision').checked,
      soundEnabled: document.getElementById('adminCinematicSound').checked,
      sequenceSpeed: Number(document.getElementById('adminCinematicSpeed').value),
      cameraFov: Number(document.getElementById('adminCinematicFov').value),
      responseDurationMs: Number(document.getElementById('adminCinematicResponse').value),
      soundVolume: Number(document.getElementById('adminCinematicVolume').value),
    },
  });
  loadPoliceAdminConfig();
};
document.getElementById('adminPreviewBookingCinematic').onclick = () => post('previewPoliceCinematic', { kind: 'booking' });
document.getElementById('adminPreviewImpoundCinematic').onclick = () => post('previewPoliceCinematic', { kind: 'impound' });
document.getElementById('newRank').onclick = () => openRankEditor();
document.getElementById('cancelRank').onclick = closeRankEditor;
document.getElementById('saveRank').onclick = () => {
  const permissions = [...document.querySelectorAll('#permissionEditor input:checked')].map((input) => input.value);
  post('action', { action: 'save_rank', payload: { rankId: editingRankId, name: document.getElementById('rankName').value, tier: document.getElementById('rankTier').value, permissions } });
};
const memberActionConfirm = {
  kick: ['Remove Member', 'Remove this member from Police? This cannot be undone.', 'Remove'],
  demote: ['Demote Member', 'Demote this member to the next rank down?', 'Demote'],
  suspend_member: ['Suspend Member', 'Suspend this member from Police duty for 60 minutes?', 'Suspend'],
};
document.getElementById('members').onclick = async (event) => {
  const button = event.target.closest('[data-action]');
  if (!button) return;
  const confirmArgs = memberActionConfirm[button.dataset.action];
  if (confirmArgs && !(await showConfirmOverlay(...confirmArgs, 'Cancel'))) return;
  post('action', { action: button.dataset.action, payload: { characterId: button.dataset.cid } });
};
document.getElementById('ranks').onclick = async (event) => {
  const edit = event.target.closest('[data-rank-edit]');
  const remove = event.target.closest('[data-rank-delete]');
  if (edit) openRankEditor(state.ranks.find((rank) => rank.id === Number(edit.dataset.rankEdit)));
  if (remove) {
    if (!(await showConfirmOverlay('Delete Rank', 'Delete this rank? This cannot be undone.', 'Delete', 'Cancel'))) return;
    post('action', { action: 'delete_rank', payload: { rankId: Number(remove.dataset.rankDelete) } });
  }
};
// ── Shared UI toolkit: toasts / bottom hint / confirm dialog / quick menu ─
// Replaces every ox_lib UI surface (lib.notify/showTextUI/hideTextUI/
// alertDialog/registerContext+showContext) with cm-police's own NUI. Driven
// both by client Lua (client/ui.lua, via SendNUIMessage) and directly by
// this file's own destructive-action buttons below (showConfirmOverlay is
// the one shared implementation for both paths).
const policeToasts = document.getElementById('policeToasts');
function showToast(title, description, type = 'inform') {
  const colors = { success: '#2effa5', error: '#ff5b5b', warning: '#ffc02e', inform: '#31e6ff' };
  const item = document.createElement('div');
  item.className = 'police-toast';
  item.style.setProperty('--pt-color', colors[type] || colors.inform);
  item.innerHTML = `<div class="police-toast-bar"></div><div class="police-toast-body"><div class="police-toast-title">${esc(title || 'Police')}</div><div class="police-toast-text">${esc(description || '')}</div></div>`;
  policeToasts.appendChild(item);
  requestAnimationFrame(() => item.classList.add('show'));
  setTimeout(() => {
    item.classList.remove('show');
    item.classList.add('hide');
    setTimeout(() => item.remove(), 220);
  }, 4000);
}

const policeHint = document.getElementById('policeHint');
const policeHintText = document.getElementById('policeHintText');
function showHint(text) { policeHintText.textContent = text || ''; policeHint.hidden = false; }
function hideHint() { policeHint.hidden = true; }

const policeConfirmOverlay = document.getElementById('policeConfirm');
// #policeConfirm is one shared DOM node used by every confirm call site in
// this file (delete rank/preset/note, kick/demote, MDT fine, plus the
// Lua-driven confirmOpen path from client/ui.lua's PoliceConfirm). Without
// this queue, a second call arriving before the first resolves would
// silently overwrite the visible prompt's text/buttons and orphan the first
// caller's promise forever -- it would just never resolve, so whatever
// action was waiting on it (e.g. delete_rank) would silently never fire.
// Queuing means the second prompt simply waits its turn instead.
let confirmQueue = Promise.resolve();
function showConfirmOverlay(title, message, yesLabel = 'Confirm', noLabel = 'Cancel') {
  const run = () => new Promise((resolve) => {
    document.getElementById('policeConfirmTitle').textContent = title || 'Confirm';
    document.getElementById('policeConfirmMessage').textContent = message || 'Are you sure?';
    const yesBtn = document.getElementById('policeConfirmYes');
    const noBtn = document.getElementById('policeConfirmNo');
    yesBtn.textContent = yesLabel;
    noBtn.textContent = noLabel;
    policeConfirmOverlay.classList.toggle('impound-confirm', !impoundRelease.hidden);
    policeConfirmOverlay.hidden = false;
    const cleanup = (result) => {
      policeConfirmOverlay.hidden = true;
      policeConfirmOverlay.classList.remove('impound-confirm');
      yesBtn.onclick = null;
      noBtn.onclick = null;
      resolve(result);
    };
    yesBtn.onclick = () => cleanup(true);
    noBtn.onclick = () => cleanup(false);
  });
  const result = confirmQueue.then(run);
  confirmQueue = result;
  return result;
}

const policeQuickMenuOverlay = document.getElementById('policeQuickMenu');
const policeQuickMenuItems = document.getElementById('policeQuickMenuItems');
function openQuickMenu(title, items) {
  document.getElementById('policeQuickMenuTitle').textContent = title || 'Menu';
  policeQuickMenuItems.innerHTML = (items || []).map((item, index) => `<button class="police-quick-menu-item" data-quick-menu-index="${index + 1}"><span class="police-quick-menu-item-title">${esc(item.title || '')}</span>${item.description ? `<span class="police-quick-menu-item-desc">${esc(item.description)}</span>` : ''}</button>`).join('');
  policeQuickMenuOverlay.hidden = false;
}
function closeQuickMenuOverlay() { policeQuickMenuOverlay.hidden = true; }
policeQuickMenuItems.addEventListener('click', (event) => {
  const button = event.target.closest('[data-quick-menu-index]');
  if (!button) return;
  closeQuickMenuOverlay();
  post('quickMenuChoice', { index: Number(button.dataset.quickMenuIndex) });
});

// ── MDT TERMINAL (Tab key, standalone green console) ──────────────────────
// Independent presentation layer over the SAME server callbacks the F7 MDT
// tab already uses (mdtSearch/mdtCitizenProfile/mdtVehicleSearch/mdtAddNote/
// mdtDeleteNote/mdtSetCriminalStatus/mdtWantedList), plus newer ones added
// for this terminal specifically (mdtIssueFines, mdtSetPhoto, mdtAddEvidence/
// mdtDeleteEvidence) and the dispatch callbacks the F7 Dispatch tab already
// uses (dispatchActiveCalls/dispatchAccept/dispatchEnRoute/dispatchResolve/
// dispatchHistory) -- reused here for the Dispatch & Units / Case Files
// tabs, no server-side duplication. Deliberately does not share state/render
// functions with the F7 tab's own renderMdtResults/renderMdtProfile so the
// two entry points stay independent.
let mdtTermResults = [];
let mdtTermProfile = null;
let mdtTermWantedList = [];
let mdtTermVehicleResult = null;
let mdtTermSelectedCharges = new Set();
let mdtTermCases = [];
let mdtTermDispatchActive = [];

function renderMdtTermResults() {
  document.getElementById('mdtTermResults').innerHTML = mdtTermResults.map((row) => `<div class="mdt-term-row-item" data-mdt-term-cid="${esc(row.characterId)}"><div>${esc(row.name)}<small>CID ${esc(row.characterId)}</small></div><div>${row.stars ? `<span class="star-tag">${'★'.repeat(row.stars)}</span> ` : ''}${row.wanted ? '<span class="wanted-tag">WANTED</span>' : ''}</div></div>`).join('') || '<div class="mdt-term-record">NO MATCHES</div>';
}

async function mdtTermSearch() {
  const query = document.getElementById('mdtTermQuery').value.trim();
  if (!query) return;
  const result = await post('mdtSearch', { query });
  mdtTermResults = result?.results || [];
  renderMdtTermResults();
}

function renderMdtTermStars() {
  const stars = mdtTermProfile?.criminalStars || 0;
  document.getElementById('mdtTermStars').innerHTML = [1, 2, 3, 4, 5].map((n) => `<button class="mdt-term-star${n <= stars ? ' filled' : ''}" data-mdt-term-star="${n}">★</button>`).join('');
}

// Purely cosmetic, deterministic from the character id -- no forensic
// mechanic exists anywhere in this codebase, this is flavor text only, not
// stored anywhere.
function mdtTermDnaLabel(characterId) {
  let hash = 0;
  const str = String(characterId);
  for (let i = 0; i < str.length; i++) { hash = (hash * 31 + str.charCodeAt(i)) >>> 0; }
  const digits = String(hash).padStart(4, '0').slice(-4);
  const letter = String.fromCharCode(65 + (hash % 26));
  return `DNA-${digits}-${letter} · FP-${String(hash % 90000 + 10000)}`;
}

const MDT_TERM_BADGE_CLASS = {
  OUTSIDE: 'mdt-term-badge-outside',
  STORED: 'mdt-term-badge-stored',
  HOUSE_GARAGE: 'mdt-term-badge-house_garage',
  PUBLIC_GARAGE: 'mdt-term-badge-public_garage',
  JOB_GARAGE: 'mdt-term-badge-job_garage',
  IMPOUND: 'mdt-term-badge-impound',
  POLICE_SEIZED: 'mdt-term-badge-police_seized',
  DESTROYED: 'mdt-term-badge-destroyed',
};
function mdtTermLocationBadge(state) {
  const cls = MDT_TERM_BADGE_CLASS[state] || 'mdt-term-badge-default';
  return `<span class="mdt-term-badge ${cls}">${esc(state || 'UNKNOWN')}</span>`;
}

function renderMdtTermMugshot() {
  const box = document.getElementById('mdtTermMugshot');
  const url = mdtTermProfile?.photoUrl;
  const initial = esc((mdtTermProfile?.name || '?').slice(0, 1).toUpperCase());
  box.innerHTML = url
    ? `<img src="${esc(url)}" onerror="this.parentElement.innerHTML='${initial}'">`
    : initial;
  document.getElementById('mdtTermPhotoUrl').value = url || '';
}

function renderMdtTermCharges() {
  const list = document.getElementById('mdtTermChargeList');
  list.innerHTML = (state?.violations || []).map((v) => `<label class="mdt-term-charge-row"><input type="checkbox" data-mdt-term-charge="${esc(v.id)}"${mdtTermSelectedCharges.has(v.id) ? ' checked' : ''}> ${esc(v.label)} · $${esc(v.fine)}${v.jailMinutes ? `<span class="mdt-term-charge-jail">(${esc(v.jailMinutes)}m)</span>` : ''}</label>`).join('');
  const selected = (state?.violations || []).filter((v) => mdtTermSelectedCharges.has(v.id));
  const total = selected.reduce((sum, v) => sum + (Number(v.fine) || 0), 0);
  const jailTotal = selected.reduce((sum, v) => sum + (Number(v.jailMinutes) || 0), 0);
  document.getElementById('mdtTermChargeTotal').textContent = total;
  const jailEl = document.getElementById('mdtTermChargeJailTotal');
  if (jailEl) jailEl.textContent = jailTotal > 0 ? `SUGGESTED SENTENCE: ${jailTotal} min -- book manually via the G-menu` : '';
}

function renderMdtTermLicenses() {
  const list = document.getElementById('mdtTermLicenses');
  // 'unlicensed' (firearms only, no row yet -- self-purchase in cm-gunstore)
  // has nothing to revoke, so its button is inert -- an officer can't
  // fabricate a firearms license here, only view whether one was purchased.
  list.innerHTML = (mdtTermProfile?.licenses || []).map((lic) => {
    const label = lic.status === 'revoked' ? 'REVOKED' : lic.status === 'unlicensed' ? 'UNLICENSED' : 'ACTIVE';
    const numberSuffix = lic.number ? ` · #${esc(lic.number)}` : '';
    if (lic.status === 'unlicensed') {
      return `<div class="mdt-term-license-row"><span>${esc(lic.type)}</span><button class="unlicensed" disabled>${label}</button></div>`;
    }
    return `<div class="mdt-term-license-row"><span>${esc(lic.type)}${numberSuffix}${lic.reason ? ` · ${esc(lic.reason)}` : ''}</span><button class="${lic.status === 'revoked' ? 'revoked' : ''}" data-mdt-term-license="${esc(lic.type)}" data-mdt-term-license-status="${lic.status}">${label}</button></div>`;
  }).join('') || '<div class="mdt-term-record">NO LICENSES CONFIGURED</div>';
}

async function mdtTermToggleLicense(licenseType, currentStatus) {
  if (!mdtTermProfile) return;
  const nextStatus = currentStatus === 'revoked' ? 'active' : 'revoked';
  let reason = '';
  if (nextStatus === 'revoked') {
    if (!(await showConfirmOverlay('Revoke License', `Revoke this citizen's ${licenseType} license?`, 'Revoke', 'Cancel'))) return;
  }
  const result = await post('mdtSetLicenseStatus', { characterId: mdtTermProfile.characterId, licenseType, status: nextStatus, reason });
  if (result?.ok) mdtTermLoadProfile(mdtTermProfile.characterId);
}

function renderMdtTermProfile() {
  const card = document.getElementById('mdtTermProfileCard');
  const rightSidebar = document.getElementById('mdtTermRight');
  if (!mdtTermProfile) { card.hidden = true; rightSidebar.hidden = true; return; }
  card.hidden = false;
  rightSidebar.hidden = false;
  document.getElementById('mdtTermProfileName').textContent = `${mdtTermProfile.name} :: CID ${mdtTermProfile.characterId}`;
  document.getElementById('mdtTermProfileDna').textContent = mdtTermDnaLabel(mdtTermProfile.characterId);
  document.getElementById('mdtTermProfileBank').textContent = `$${Number(mdtTermProfile.bank || 0).toLocaleString('en-US')}`;
  document.getElementById('mdtTermWarrantBanner').hidden = mdtTermProfile.wanted !== true;
  renderMdtTermMugshot();
  const wantedButton = document.getElementById('mdtTermWantedToggle');
  wantedButton.textContent = mdtTermProfile.wanted ? 'CLEAR WANTED' : 'MARK WANTED';
  wantedButton.classList.toggle('active', mdtTermProfile.wanted === true);
  renderMdtTermStars();
  mdtTermSelectedCharges = new Set();
  renderMdtTermCharges();
  document.getElementById('mdtTermCitations').innerHTML = (mdtTermProfile.citations || []).map((c) => `<div class="mdt-term-record">${esc(c.violation_label)} · $${esc(c.fine)}<small>${esc(c.createdAt)}</small></div>`).join('') || '<div class="mdt-term-record">NO CITATIONS</div>';
  document.getElementById('mdtTermBookings').innerHTML = (mdtTermProfile.bookings || []).map((b) => `<div class="mdt-term-record">${b.releasedAt ? 'RELEASED' : b.handoffStatus === 'failed' ? 'FAILED' : b.handoffStatus === 'processing' ? 'PROCESSING' : 'ACTIVE'} · ${esc(b.sentenceMinutes)} MIN · ${esc(b.wantedStars)} STAR(S)<small>Booked ${esc(b.bookedAt)}${b.reason ? ' · Reason: ' + esc(b.reason) : ''}${b.charges ? ' · Charges: ' + esc(b.charges) : ''} · Handoff: ${esc(b.handoffStatus)}${b.releaseReason ? ' · Release: ' + esc(b.releaseReason) : ''}</small></div>`).join('') || '<div class="mdt-term-record">NO BOOKINGS</div>';
  document.getElementById('mdtTermImpounds').innerHTML = (mdtTermProfile.impounds || []).map((i) => `<div class="mdt-term-record">${esc(i.plate)} · $${esc(i.fee)}<small>${i.releasedAt ? 'Released' : 'Still impounded'} · ${esc(i.impoundedAt)}</small></div>`).join('') || '<div class="mdt-term-record">NO IMPOUND HISTORY</div>';
  // Only license-registered vehicles ever reach this list (unlicensed cars
  // are filtered out server-side) -- no location/storage badge shown here.
  document.getElementById('mdtTermVehicles').innerHTML = (mdtTermProfile.vehicles || []).map((v) => `<div class="mdt-term-record">${esc(v.plate)} · ${esc(v.model)} · #${esc(v.licenseNumber)}</div>`).join('') || '<div class="mdt-term-record">NO REGISTERED VEHICLES</div>';
  renderMdtTermLicenses();
  document.getElementById('mdtTermNotes').innerHTML = (mdtTermProfile.notes || []).map((n) => {
    const mine = n.authorCid && state?.self?.characterId && n.authorCid === state.self.characterId;
    return `<div class="mdt-term-note"><div>${esc(n.note)}<small>${esc(n.authorName)} · ${esc(n.createdAt)}</small></div>${mine ? `<button data-mdt-term-note-delete="${n.id}">DEL</button>` : ''}</div>`;
  }).join('') || '<div class="mdt-term-note">NO NOTES YET</div>';
  document.getElementById('mdtTermEvidence').innerHTML = (mdtTermProfile.evidence || []).map((ev) => {
    const mine = ev.authorCid && state?.self?.characterId && ev.authorCid === state.self.characterId;
    return `<div class="mdt-term-evidence"><img src="${esc(ev.url)}" onerror="this.style.display='none'"><div class="mdt-term-evidence-body"><a href="${esc(ev.url)}" target="_blank" rel="noopener">${esc(ev.caption)}</a><small>${esc(ev.authorName)} · ${esc(ev.createdAt)}</small></div>${mine ? `<button data-mdt-term-evidence-delete="${ev.id}">DEL</button>` : ''}</div>`;
  }).join('') || '<div class="mdt-term-note">NO EVIDENCE YET</div>';
}

async function mdtTermLoadProfile(characterId) {
  const result = await post('mdtCitizenProfile', { characterId });
  mdtTermProfile = result?.profile || null;
  renderMdtTermProfile();
}

async function mdtTermAddNote() {
  if (!mdtTermProfile) return;
  const input = document.getElementById('mdtTermNoteInput');
  const note = input.value.trim();
  if (!note) return;
  const result = await post('mdtAddNote', { characterId: mdtTermProfile.characterId, note });
  if (result?.ok) { input.value = ''; mdtTermLoadProfile(mdtTermProfile.characterId); }
}

async function mdtTermAddEvidence() {
  if (!mdtTermProfile) return;
  const urlInput = document.getElementById('mdtTermEvidenceUrl');
  const captionInput = document.getElementById('mdtTermEvidenceCaption');
  const url = urlInput.value.trim();
  if (!url) return;
  const result = await post('mdtAddEvidence', { characterId: mdtTermProfile.characterId, url, caption: captionInput.value.trim() });
  if (result?.ok) { urlInput.value = ''; captionInput.value = ''; mdtTermLoadProfile(mdtTermProfile.characterId); }
}

async function mdtTermSetPhoto() {
  if (!mdtTermProfile) return;
  const url = document.getElementById('mdtTermPhotoUrl').value.trim();
  if (!(await showConfirmOverlay('Set Mugshot', 'Replace this citizen\'s mugshot photo? The previous one cannot be recovered.', 'Set Photo', 'Cancel'))) return;
  const result = await post('mdtSetPhoto', { characterId: mdtTermProfile.characterId, url });
  if (result?.ok) { mdtTermProfile.photoUrl = result.photoUrl || null; renderMdtTermMugshot(); }
}

async function mdtTermSetStars(stars) {
  if (!mdtTermProfile) return;
  const next = mdtTermProfile.criminalStars === stars ? 0 : stars;
  let reason = '';
  if (next > 0) {
    reason = String(window.prompt('Enter the reason for assigning this wanted level:') || '').trim();
    if (reason.length < 3) return;
  }
  const result = await post('mdtSetCriminalStatus', { characterId: mdtTermProfile.characterId, stars: next, wanted: next > 0, reason });
  if (result?.ok) { mdtTermProfile.criminalStars = result.stars; mdtTermProfile.wanted = result.wanted; renderMdtTermStars(); }
}

async function mdtTermToggleWanted() {
  if (!mdtTermProfile) return;
  const settingWanted = !mdtTermProfile.wanted;
  if (settingWanted && !(await showConfirmOverlay('Mark Wanted', 'Mark this citizen as wanted? This drives their in-game wanted behavior.', 'Mark Wanted', 'Cancel'))) return;
  let reason = '';
  if (settingWanted) {
    reason = String(window.prompt('Enter the reason this citizen is wanted:') || '').trim();
    if (reason.length < 3) return;
  }
  const result = await post('mdtSetCriminalStatus', { characterId: mdtTermProfile.characterId, stars: mdtTermProfile.criminalStars || 0, wanted: settingWanted, reason });
  if (result?.ok) {
    mdtTermProfile.criminalStars = result.stars;
    mdtTermProfile.wanted = result.wanted;
    const wantedButton = document.getElementById('mdtTermWantedToggle');
    wantedButton.textContent = mdtTermProfile.wanted ? 'CLEAR WANTED' : 'MARK WANTED';
    wantedButton.classList.toggle('active', mdtTermProfile.wanted === true);
    document.getElementById('mdtTermWarrantBanner').hidden = mdtTermProfile.wanted !== true;
    mdtTermLoadWantedList();
  }
}

async function mdtTermIssueFines() {
  if (!mdtTermProfile || mdtTermSelectedCharges.size === 0) return;
  const violationIds = [...mdtTermSelectedCharges];
  const total = (state?.violations || []).filter((v) => mdtTermSelectedCharges.has(v.id)).reduce((sum, v) => sum + (Number(v.fine) || 0), 0);
  if (!(await showConfirmOverlay('Issue Charges', `Issue ${violationIds.length} charge(s) to ${mdtTermProfile.name} totaling $${total}?`, 'Issue', 'Cancel'))) return;
  const result = await post('mdtIssueFines', { characterId: mdtTermProfile.characterId, violationIds });
  if (result?.ok) { mdtTermSelectedCharges = new Set(); mdtTermLoadProfile(mdtTermProfile.characterId); }
}

function renderMdtTermVehicleResult() {
  const el = document.getElementById('mdtTermVehicleResult');
  if (!mdtTermVehicleResult) { el.innerHTML = '<div class="mdt-term-record">NO VEHICLE FOUND</div>'; return; }
  const v = mdtTermVehicleResult;
  const registration = v.licenseNumber
    ? `<span class="mdt-term-badge mdt-term-badge-default">REG #${esc(v.licenseNumber)}</span>`
    : `<span class="mdt-term-badge mdt-term-badge-outside">UNREGISTERED</span><button data-mdt-term-issue-vehicle-license="${esc(v.plate)}">ISSUE LICENSE</button>`;
  el.innerHTML = `<div class="mdt-term-record">${esc(v.plate)} · ${esc(v.model)} ${registration}<small>Owner: ${esc(v.ownerName)}${v.ownerCid ? ` (CID ${esc(v.ownerCid)})` : ''}</small>${v.impound ? `<small class="wanted-tag">Impounded · $${esc(v.impound.fee)} fee</small>` : ''}${v.impoundEvidence ? `<small>Latest pre-tow evidence: ${esc(v.impoundEvidence.message)} · ${esc(v.impoundEvidence.capturedAt)}</small><img class="mdt-term-vehicle-evidence" src="${esc(v.impoundEvidence.imageUrl)}" onerror="this.style.display='none'">` : ''}</div>`;
}

async function mdtTermVehicleSearch() {
  const plate = document.getElementById('mdtTermPlateQuery').value.trim();
  if (!plate) return;
  const result = await post('mdtVehicleSearch', { plate });
  mdtTermVehicleResult = result?.vehicle || null;
  renderMdtTermVehicleResult();
}

async function mdtTermIssueVehicleLicense(plate) {
  const result = await post('mdtIssueVehicleLicense', { plate });
  if (result?.ok) mdtTermVehicleSearch();
}

async function mdtTermCaptureImpoundEvidence() {
  const input = document.getElementById('mdtTermImpoundMessage');
  const message = input.value.trim();
  if (message.length < 5) return;
  if (!(await showConfirmOverlay('Capture Impound Evidence', 'The MDT will close and photograph your current view. Make sure the full vehicle is visible.', 'Capture Image', 'Cancel'))) return;
  await post('mdtCaptureImpoundEvidence', { message });
}

async function mdtTermStartImpound() {
  if (!(await showConfirmOverlay('Impound Vehicle', 'Start an impound process for the nearest vehicle? You must document and photograph it before towing.', 'Start Process', 'Cancel'))) return;
  document.getElementById('mdtTermStartImpoundButton').hidden = true;
  document.getElementById('mdtTermImpoundForm').hidden = false;
  document.getElementById('mdtTermImpoundStatus').textContent = 'IN PROGRESS — Write the reason and capture an image of the vehicle.';
  document.getElementById('mdtTermImpoundMessage').focus();
}

document.getElementById('mdtTermVehicleResult')?.addEventListener('click', (event) => {
  const button = event.target.closest('[data-mdt-term-issue-vehicle-license]');
  if (button) mdtTermIssueVehicleLicense(button.dataset.mdtTermIssueVehicleLicense);
});

function renderMdtTermWantedList() {
  document.getElementById('mdtTermWantedList').innerHTML = mdtTermWantedList.map((row) => `<div class="mdt-term-row-item" data-mdt-term-cid="${esc(row.characterId)}"><div>${esc(row.name)}<small>CID ${esc(row.characterId)}</small></div><span class="star-tag">${'★'.repeat(row.stars || 0)}</span></div>`).join('') || '<div class="mdt-term-record">NO WANTED PERSONS</div>';
}

async function mdtTermLoadWantedList() {
  const result = await post('mdtWantedList', {});
  mdtTermWantedList = result?.list || [];
  renderMdtTermWantedList();
}

// ── Case Files tab (reuses the already-built dispatch history) ───────────
function renderMdtTermCases() {
  document.getElementById('mdtTermCases').innerHTML = mdtTermCases.map((row) => `<div class="mdt-term-record">${esc(row.details)} · ${esc(row.status).toUpperCase()}<small>Location: ${esc(row.location || 'Unknown')} · Caller: ${esc(row.callerName || 'Unknown')} · ${esc(row.createdAt)}${row.resolution ? ' · ' + esc(row.resolution) : ''}</small></div>`).join('') || '<div class="mdt-term-record">NO CASE FILES YET</div>';
}
async function mdtTermLoadCases() {
  const result = await post('dispatchHistory');
  mdtTermCases = result?.list || [];
  renderMdtTermCases();
}

// ── Dispatch & Units tab (reuses the already-built F7 Dispatch tab's own
// server callbacks -- Accept/En Route/Resolve behave identically here) ──
function renderMdtTermDispatchActive() {
  const myCid = state?.self?.characterId;
  document.getElementById('mdtTermDispatchActive').innerHTML = mdtTermDispatchActive.map((call) => {
    const mine = myCid && (call.responders || []).find((r) => r.characterId === myCid);
    const responders = (call.responders || []).map((r) => `${esc(r.name)} (${r.status === 'en_route' ? 'En Route' : 'Accepted'})`).join(', ') || 'No one responding';
    return `<div class="mdt-term-record">${esc(call.details)}<small>Location: ${esc(call.location || 'Unknown')} · Responding: ${responders}</small>
      <div class="mdt-term-row">
        ${!mine ? `<button data-mdt-term-dispatch-accept="${call.id}">ACCEPT</button>` : ''}
        ${mine && mine.status !== 'en_route' ? `<button data-mdt-term-dispatch-enroute="${call.id}">EN ROUTE</button>` : ''}
        ${mine ? `<button data-mdt-term-dispatch-resolve="${call.id}">RESOLVE</button>` : ''}
      </div>
    </div>`;
  }).join('') || '<div class="mdt-term-record">NO ACTIVE CALLS</div>';
}
async function mdtTermLoadDispatchActive() {
  const result = await post('dispatchActiveCalls');
  mdtTermDispatchActive = result?.list || [];
  renderMdtTermDispatchActive();
}
function renderMdtTermUnits() {
  const units = (state?.members || []).filter((m) => m.onDuty);
  document.getElementById('mdtTermUnits').innerHTML = units.map((m) => `<div class="mdt-term-record">${esc(m.name)} · ${esc(m.rankName)}<small>CID ${esc(m.characterId)} · ${m.radioStatus === '10-6' ? '10-6 (Busy)' : '10-8 (Available)'}</small></div>`).join('') || '<div class="mdt-term-record">NO UNITS ON DUTY</div>';
}

// ── BOLO Alerts tab ────────────────────────────────────────────────────────
let mdtTermBoloActive = [];
let mdtTermBoloHistory = [];

function boloRecord(row, showClear) {
  const plate = row.plate ? ` · Plate: ${esc(row.plate)}` : '';
  const clearedInfo = row.clearedByName ? `<small>Cleared by ${esc(row.clearedByName)} · ${esc(row.clearedAt)}</small>` : '';
  return `<div class="mdt-term-record">${esc(row.description)}${plate}<small>Issued by ${esc(row.officerName)} · ${esc(row.createdAt)}</small>${clearedInfo}${showClear ? `<div class="mdt-term-row"><button data-mdt-term-bolo-clear="${row.id}">CLEAR</button></div>` : ''}</div>`;
}

function renderMdtTermBoloActive() {
  document.getElementById('mdtTermBoloActive').innerHTML = mdtTermBoloActive.map((row) => boloRecord(row, true)).join('') || '<div class="mdt-term-record">NO ACTIVE BOLOS</div>';
}
async function mdtTermLoadBoloActive() {
  const result = await post('mdtActiveBolos');
  mdtTermBoloActive = result?.list || [];
  renderMdtTermBoloActive();
}

function renderMdtTermBoloHistory() {
  document.getElementById('mdtTermBoloHistory').innerHTML = mdtTermBoloHistory.map((row) => boloRecord(row, false)).join('') || '<div class="mdt-term-record">NO BOLO HISTORY</div>';
}
async function mdtTermLoadBoloHistory() {
  const result = await post('mdtBoloHistory');
  mdtTermBoloHistory = result?.list || [];
  renderMdtTermBoloHistory();
}

async function mdtTermIssueBolo() {
  const description = document.getElementById('mdtTermBoloDescription').value.trim();
  if (!description) return;
  const plate = document.getElementById('mdtTermBoloPlate').value.trim();
  const result = await post('mdtIssueBolo', { description, plate });
  if (result?.ok) {
    document.getElementById('mdtTermBoloDescription').value = '';
    document.getElementById('mdtTermBoloPlate').value = '';
    mdtTermLoadBoloActive();
  }
}

async function mdtTermClearBolo(boloId) {
  if (!(await showConfirmOverlay('Clear BOLO', 'Clear this BOLO alert for every officer?', 'Clear', 'Cancel'))) return;
  const result = await post('mdtClearBolo', { boloId });
  if (result?.ok) { mdtTermLoadBoloActive(); mdtTermLoadBoloHistory(); }
}

// ── Use of Force tab ───────────────────────────────────────────────────────
let mdtTermUofHistory = [];

function uofRecord(row) {
  const mine = row.officerCid && state?.self?.characterId && row.officerCid === state.self.characterId;
  return `<div class="mdt-term-record">${esc(row.forceType)} · ${esc(row.subject)}<small>${esc(row.narrative)}</small><small>Filed by ${esc(row.officerName)} · ${esc(row.createdAt)}</small>${mine ? `<div class="mdt-term-row"><button data-mdt-term-uof-delete="${row.id}">DEL</button></div>` : ''}</div>`;
}

function renderMdtTermUof() {
  document.getElementById('mdtTermUofHistory').innerHTML = mdtTermUofHistory.map((row) => uofRecord(row)).join('') || '<div class="mdt-term-record">NO USE-OF-FORCE REPORTS</div>';
}
async function mdtTermLoadUofHistory() {
  const result = await post('mdtUseOfForceHistory');
  mdtTermUofHistory = result?.list || [];
  renderMdtTermUof();
}

async function mdtTermFileUof() {
  const subject = document.getElementById('mdtTermUofSubject').value.trim();
  const narrative = document.getElementById('mdtTermUofNarrative').value.trim();
  if (!subject || !narrative) return;
  const forceType = document.getElementById('mdtTermUofType').value;
  const result = await post('mdtFileUseOfForce', { subject, forceType, narrative });
  if (result?.ok) {
    document.getElementById('mdtTermUofSubject').value = '';
    document.getElementById('mdtTermUofNarrative').value = '';
    mdtTermLoadUofHistory();
  }
}

async function mdtTermDeleteUof(reportId) {
  if (!(await showConfirmOverlay('Delete Report', 'Delete this use-of-force report? This cannot be undone.', 'Delete', 'Cancel'))) return;
  const result = await post('mdtDeleteUseOfForce', { reportId });
  if (result?.ok) mdtTermLoadUofHistory();
}

// ── Penal Code tab (read-only reference, no fetch -- state.violations is
// already loaded) ─────────────────────────────────────────────────────────
function renderMdtTermPenalList() {
  document.getElementById('mdtTermPenalList').innerHTML = (state?.violations || []).map((v) => `<div class="mdt-term-record">${esc(v.label)} · $${esc(v.fine)}</div>`).join('') || '<div class="mdt-term-record">NO VIOLATIONS CONFIGURED</div>';
}

// ── Tab switching ──────────────────────────────────────────────────────────
function mdtTermSwitchTab(tab) {
  document.querySelectorAll('.mdt-term-tab').forEach((btn) => btn.classList.toggle('active', btn.dataset.mdtTermTab === tab));
  document.querySelectorAll('.mdt-term-panel-view').forEach((view) => view.classList.toggle('active', view.dataset.mdtTermView === tab));
  if (tab === 'cases') mdtTermLoadCases();
  else if (tab === 'dispatch') { mdtTermLoadDispatchActive(); renderMdtTermUnits(); }
  else if (tab === 'penal') renderMdtTermPenalList();
  else if (tab === 'bolo') { mdtTermLoadBoloActive(); mdtTermLoadBoloHistory(); }
  else if (tab === 'uof') mdtTermLoadUofHistory();
}

document.getElementById('mdtTermSearchButton')?.addEventListener('click', () => mdtTermSearch());
document.getElementById('mdtTermResults')?.addEventListener('click', (event) => {
  const row = event.target.closest('[data-mdt-term-cid]');
  if (row) mdtTermLoadProfile(row.dataset.mdtTermCid);
});
document.getElementById('mdtTermWantedList')?.addEventListener('click', (event) => {
  const row = event.target.closest('[data-mdt-term-cid]');
  if (row) mdtTermLoadProfile(row.dataset.mdtTermCid);
});
document.getElementById('mdtTermRefreshWanted')?.addEventListener('click', () => mdtTermLoadWantedList());
document.getElementById('mdtTermPlateSearchButton')?.addEventListener('click', () => mdtTermVehicleSearch());
document.getElementById('mdtTermCaptureImpoundButton')?.addEventListener('click', () => mdtTermCaptureImpoundEvidence());
document.getElementById('mdtTermStartImpoundButton')?.addEventListener('click', () => mdtTermStartImpound());
document.getElementById('mdtTermAddNoteButton')?.addEventListener('click', () => mdtTermAddNote());
document.getElementById('mdtTermNotes')?.addEventListener('click', async (event) => {
  const del = event.target.closest('[data-mdt-term-note-delete]');
  if (!del) return;
  if (!(await showConfirmOverlay('Delete Note', 'Delete this MDT note? This cannot be undone.', 'Delete', 'Cancel'))) return;
  const result = await post('mdtDeleteNote', { noteId: Number(del.dataset.mdtTermNoteDelete) });
  if (result?.ok && mdtTermProfile) mdtTermLoadProfile(mdtTermProfile.characterId);
});
document.getElementById('mdtTermAddEvidenceButton')?.addEventListener('click', () => mdtTermAddEvidence());
document.getElementById('mdtTermEvidence')?.addEventListener('click', async (event) => {
  const del = event.target.closest('[data-mdt-term-evidence-delete]');
  if (!del) return;
  if (!(await showConfirmOverlay('Delete Evidence', 'Delete this evidence entry? This cannot be undone.', 'Delete', 'Cancel'))) return;
  const result = await post('mdtDeleteEvidence', { evidenceId: Number(del.dataset.mdtTermEvidenceDelete) });
  if (result?.ok && mdtTermProfile) mdtTermLoadProfile(mdtTermProfile.characterId);
});
document.getElementById('mdtTermSetPhotoButton')?.addEventListener('click', () => mdtTermSetPhoto());
document.getElementById('mdtTermLicenses')?.addEventListener('click', (event) => {
  const button = event.target.closest('[data-mdt-term-license]');
  if (button) mdtTermToggleLicense(button.dataset.mdtTermLicense, button.dataset.mdtTermLicenseStatus);
});
document.getElementById('mdtTermWantedToggle')?.addEventListener('click', () => mdtTermToggleWanted());
document.getElementById('mdtTermStars')?.addEventListener('click', (event) => {
  const button = event.target.closest('[data-mdt-term-star]');
  if (button) mdtTermSetStars(Number(button.dataset.mdtTermStar));
});
document.getElementById('mdtTermChargeList')?.addEventListener('change', (event) => {
  const box = event.target.closest('[data-mdt-term-charge]');
  if (!box) return;
  if (box.checked) mdtTermSelectedCharges.add(box.dataset.mdtTermCharge);
  else mdtTermSelectedCharges.delete(box.dataset.mdtTermCharge);
  renderMdtTermCharges();
});
document.getElementById('mdtTermIssueFinesButton')?.addEventListener('click', () => mdtTermIssueFines());
document.getElementById('mdtTermIssueBoloButton')?.addEventListener('click', () => mdtTermIssueBolo());
document.getElementById('mdtTermRefreshBolos')?.addEventListener('click', () => { mdtTermLoadBoloActive(); mdtTermLoadBoloHistory(); });
document.getElementById('mdtTermBoloActive')?.addEventListener('click', (event) => {
  const button = event.target.closest('[data-mdt-term-bolo-clear]');
  if (button) mdtTermClearBolo(Number(button.dataset.mdtTermBoloClear));
});
document.getElementById('mdtTermFileUofButton')?.addEventListener('click', () => mdtTermFileUof());
document.getElementById('mdtTermRefreshUof')?.addEventListener('click', () => mdtTermLoadUofHistory());
document.getElementById('mdtTermUofHistory')?.addEventListener('click', (event) => {
  const button = event.target.closest('[data-mdt-term-uof-delete]');
  if (button) mdtTermDeleteUof(Number(button.dataset.mdtTermUofDelete));
});
document.getElementById('mdtTermClose')?.addEventListener('click', () => post('closeMdtTerminal'));
document.querySelectorAll('.mdt-term-tab').forEach((btn) => btn.addEventListener('click', () => mdtTermSwitchTab(btn.dataset.mdtTermTab)));
document.getElementById('mdtTermRefreshCases')?.addEventListener('click', () => mdtTermLoadCases());
document.getElementById('mdtTermRefreshDispatch')?.addEventListener('click', () => { mdtTermLoadDispatchActive(); renderMdtTermUnits(); });
document.getElementById('mdtTermDispatchActive')?.addEventListener('click', async (event) => {
  const accept = event.target.closest('[data-mdt-term-dispatch-accept]');
  const enRoute = event.target.closest('[data-mdt-term-dispatch-enroute]');
  const resolve = event.target.closest('[data-mdt-term-dispatch-resolve]');
  if (accept) { await post('dispatchAccept', { callId: Number(accept.dataset.mdtTermDispatchAccept) }); mdtTermLoadDispatchActive(); }
  if (enRoute) { await post('dispatchEnRoute', { callId: Number(enRoute.dataset.mdtTermDispatchEnroute) }); mdtTermLoadDispatchActive(); }
  if (resolve) {
    if (!(await showConfirmOverlay('Resolve Call', 'Mark this call as resolved and remove it from the active board?', 'Resolve', 'Cancel'))) return;
    const result = await post('dispatchResolve', { callId: Number(resolve.dataset.mdtTermDispatchResolve) });
    if (result?.ok) mdtTermLoadDispatchActive();
  }
});

function openMdtTerminal() {
  mdtTermResults = [];
  mdtTermProfile = null;
  mdtTermSelectedCharges = new Set();
  document.getElementById('mdtTermProfileCard').hidden = true;
  document.getElementById('mdtTermRight').hidden = true;
  document.getElementById('mdtTermResults').innerHTML = '';
  document.getElementById('mdtTermQuery').value = '';
  document.getElementById('mdtTermVehicleResult').innerHTML = '';
  document.getElementById('mdtTermPlateQuery').value = '';
  const officer = state?.self;
  document.getElementById('mdtTermOfficerName').textContent = officer ? officer.rankName : '--';
  document.getElementById('mdtTermOfficerBadge').textContent = officer ? `CID ${officer.characterId}` : '--';
  document.getElementById('mdtTermOfficerAvatar').textContent = officer ? officer.rankName.trim().split(/\s+/).map((w) => w[0]).join('').slice(0, 2).toUpperCase() : '--';
  document.getElementById('mdtTermUofType').innerHTML = (state?.useOfForceTypes || []).map((t) => `<option value="${esc(t)}">${esc(t)}</option>`).join('');
  mdtTermSwitchTab('directory');
  document.getElementById('mdtTerminal').hidden = false;
  mdtTermLoadWantedList();
}

window.addEventListener('message', (event) => {
  if (event.data.action === 'open') { state = event.data.data; armoryStandalone = event.data.armoryStandalone === true; fleetStandalone = event.data.fleetStandalone === true; dispatchStandalone = event.data.dispatchStandalone === true; fleetVehicles = []; mdtResults = []; mdtProfile = null; mdtVehicleResult = null; wardrobeItems = []; wardrobeCategories = []; wardrobeCategory = null; if (event.data.initialPage) page = event.data.initialPage; document.body.classList.toggle('armory-standalone', armoryStandalone); document.body.classList.toggle('dispatch-standalone', dispatchStandalone); app.hidden = false; closeRankEditor(); render(); }
  else if (event.data.action === 'close') {
    document.body.classList.remove('armory-standalone');
    document.body.classList.remove('dispatch-standalone');
    app.hidden = true; state = null; closeRankEditor();
    if (!document.getElementById('wardrobeRoom').hidden) { document.getElementById('wardrobeRoom').hidden = true; post('closeWardrobeDressingRoom'); }
  }
  else if (event.data.action === 'notify') { showToast(event.data.title, event.data.description, event.data.type); }
  else if (event.data.action === 'showHint') { showHint(event.data.text); }
  else if (event.data.action === 'hideHint') { hideHint(); }
  else if (event.data.action === 'npcInteraction:show') {
    document.getElementById('npcInteractionKey').textContent = event.data.key || 'E';
    document.getElementById('npcInteractionLabel').textContent = event.data.label || 'INTERACTION';
    document.getElementById('npcInteractionIdentity').textContent = [event.data.name, event.data.role].filter(Boolean).join(' · ');
    document.getElementById('npcInteraction').hidden = false;
  }
  else if (event.data.action === 'npcInteraction:hide') { document.getElementById('npcInteraction').hidden = true; }
  else if (event.data.action === 'npcDialogue:open') {
    npcDialogue.className = 'npc-dialogue';
    document.getElementById('npcInteraction').hidden = true;
    document.getElementById('npcDialogueName').textContent = event.data.name || 'Police Officer';
    document.getElementById('npcDialogueRole').textContent = event.data.role || 'CM POLICE';
    document.getElementById('npcDialogueQuote').textContent = event.data.quote || 'How can I help you?';
    document.getElementById('npcDialogueSignature').textContent = `— ${event.data.name || 'Police Officer'}`;
    document.getElementById('npcDialogueContinue').textContent = event.data.continueLabel || 'Continue';
    const dialogueOptions = document.getElementById('npcDialogueOptions');
    const choices = Array.isArray(event.data.choices) ? event.data.choices : [];
    const deferredChoices = choices.length > 0 && event.data.deferChoices === true;
    dialogueOptions.innerHTML = choices.map((choice, index) => `<button class="npc-dialogue__option ${index === 0 ? 'npc-dialogue__option--primary' : ''}" data-npc-dialogue-choice="${esc(choice.id)}"><b>${esc(choice.label)}</b>${choice.description ? `<small>${esc(choice.description)}</small>` : ''}</button>`).join('');
    dialogueOptions.hidden = choices.length === 0 || deferredChoices;
    document.getElementById('npcDialogueContinue').hidden = choices.length > 0 && !deferredChoices;
    document.getElementById('npcDialogueContinue').dataset.revealChoices = deferredChoices ? 'true' : 'false';
    npcDialogue.hidden = false;
  }
  else if (event.data.action === 'npcDialogue:response') {
    npcDialogue.className = `npc-dialogue npc-dialogue--response npc-dialogue--${event.data.tone || 'inform'}`;
    document.getElementById('npcDialogueQuote').textContent = event.data.message || '';
  }
  else if (event.data.action === 'npcDialogue:restoreChoices') {
    npcDialogue.className = 'npc-dialogue';
    document.getElementById('npcDialogueOptions').hidden = false;
    document.getElementById('npcDialogueClose').hidden = false;
    document.getElementById('npcDialogueQuote').textContent = 'Please choose the Police service you need.';
  }
  else if (event.data.action === 'npcDialogue:close') { npcDialogue.hidden = true; }
  else if (event.data.action === 'policeCloset:open') { openWardrobeRoom('npc'); }
  else if (event.data.action === 'confirmOpen') {
    showConfirmOverlay(event.data.title, event.data.message, event.data.yesLabel, event.data.noLabel)
      .then((confirmed) => post('confirmResponse', { confirmed }));
  }
  else if (event.data.action === 'confirmClose') { policeConfirmOverlay.hidden = true; policeConfirmOverlay.classList.remove('impound-confirm'); }
  else if (event.data.action === 'quickMenuOpen') { openQuickMenu(event.data.title, event.data.items); }
  else if (event.data.action === 'quickMenuClose') { closeQuickMenuOverlay(); }
  else if (event.data.action === 'openMdtTerminal') { if (event.data.data) state = event.data.data; openMdtTerminal(); }
  else if (event.data.action === 'closeMdtTerminal') { document.getElementById('mdtTerminal').hidden = true; }
  else if (event.data.action === 'impoundCamera:show') { document.getElementById('impoundCamera').hidden = false; }
  else if (event.data.action === 'impoundCamera:hide') { document.getElementById('impoundCamera').hidden = true; }
  else if (event.data.action === 'impoundRelease:open') { renderImpoundRelease(event.data.vehicles); impoundRelease.hidden = false; }
  else if (event.data.action === 'impoundRelease:close') { impoundRelease.hidden = true; }
  else if (event.data.action === 'policeCinematic:show' || event.data.action === 'policeCinematic:update') {
    const cinematic = document.getElementById('policeCinematic');
    cinematic.className = `police-cinematic police-cinematic--${event.data.mode || 'booking'}`;
    document.getElementById('policeCinematicEyebrow').textContent = event.data.eyebrow || 'CM POLICE';
    document.getElementById('policeCinematicTitle').textContent = event.data.title || 'PROCESSING';
    document.getElementById('policeCinematicStars').textContent = event.data.stars ? '★'.repeat(Math.min(6, Number(event.data.stars))) : '';
    document.getElementById('policeCinematicReason').textContent = event.data.reason || '';
    const photo = document.getElementById('policeCinematicPhoto');
    photo.hidden = !event.data.imageUrl;
    if (event.data.imageUrl) document.getElementById('policeCinematicImage').src = event.data.imageUrl;
    document.getElementById('policeCinematicDetails').innerHTML = [event.data.suspect ? `SUSPECT <b>${esc(event.data.suspect)}</b>` : '', event.data.characterId ? `CHARACTER ID <b>${esc(event.data.characterId)}</b>` : '', event.data.minutes ? `SENTENCE <b>${Number(event.data.minutes)} MINUTES</b>` : '', event.data.plate ? `VEHICLE <b>${esc(event.data.plate)}</b>` : '', event.data.model ? `MODEL <b>${esc(event.data.model)}</b>` : '', event.data.owner ? `OWNER <b>${esc(event.data.owner)}</b>` : '', event.data.officer ? `OFFICER <b>${esc(event.data.officer)}</b>` : '', event.data.completedAt ? `COMPLETED <b>${esc(event.data.completedAt)}</b>` : '', event.data.fee ? `RELEASE FEE <b>$${Number(event.data.fee).toLocaleString()}</b>` : ''].filter(Boolean).join('<br>');
    document.getElementById('policeCinematicStamp').hidden = true; cinematic.hidden = false;
  }
  else if (event.data.action === 'policeCinematic:stamp') { const stamp = document.getElementById('policeCinematicStamp'); stamp.textContent = event.data.label || 'COMPLETE'; stamp.hidden = false; }
  else if (event.data.action === 'policeCinematic:flash') { const flash = document.getElementById('policeCinematicFlash'); flash.classList.remove('active'); void flash.offsetWidth; flash.classList.add('active'); }
  else if (event.data.action === 'policeCinematic:hide') { document.getElementById('policeCinematic').hidden = true; }
  else if (event.data.action === 'cinematicAccessibility:open') {
    const value = event.data.preferences || {};
    document.getElementById('accessCinematicMode').value = value.mode || 'full';
    document.getElementById('accessSubtitleScale').value = String(value.subtitleScale || 1);
    document.getElementById('accessSoundVolume').value = Number(value.soundVolume ?? 1);
    document.getElementById('accessReducedFlash').checked = value.reducedFlash === true;
    document.getElementById('accessSkipSeen').checked = value.skipSeen === true;
    document.getElementById('cinematicAccessibility').hidden = false;
  }
  else if (event.data.action === 'cinematicAccessibility:close') { document.getElementById('cinematicAccessibility').hidden = true; }
  else if (event.data.action === 'cinematicAccessibility:apply') { document.documentElement.style.setProperty('--cinematic-subtitle-scale', String(event.data.subtitleScale || 1)); }
  else if (event.data.action === 'dispatchRefresh') {
    if (!app.hidden && page === 'dispatch') loadDispatchActiveCalls();
    if (!document.getElementById('mdtTerminal').hidden && document.querySelector('.mdt-term-tab.active')?.dataset.mdtTermTab === 'dispatch') mdtTermLoadDispatchActive();
  }
  else if (event.data.action === 'bolosRefresh') {
    if (!document.getElementById('mdtTerminal').hidden && document.querySelector('.mdt-term-tab.active')?.dataset.mdtTermTab === 'bolo') { mdtTermLoadBoloActive(); mdtTermLoadBoloHistory(); }
  }
});
window.addEventListener('keydown', (event) => {
  if (!document.getElementById('wardrobeRoom').hidden && !event.repeat) {
    const key = event.key.toLowerCase();
    if (key === 'w') { event.preventDefault(); moveWardrobeOption(1); return; }
    if (key === 's') { event.preventDefault(); moveWardrobeOption(-1); return; }
    if (key === 'a') { event.preventDefault(); post('rotateWardrobePed', { delta: -12 }); return; }
    if (key === 'd') { event.preventDefault(); post('rotateWardrobePed', { delta: 12 }); return; }
  }
  if (event.key !== 'Escape') return;
  if (!document.getElementById('cinematicAccessibility').hidden) { post('closeCinematicAccessibility'); return; }
  if (!policeConfirmOverlay.hidden) { document.getElementById('policeConfirmNo').click(); return; }
  if (!impoundRelease.hidden) { post('closeImpoundRelease'); return; }
  if (!npcDialogue.hidden) { post('npcDialogueClose'); return; }
  if (!document.getElementById('wardrobeRoom').hidden) { closeWardrobeRoom(); return; }
  if (!policeQuickMenuOverlay.hidden) { closeQuickMenuOverlay(); post('quickMenuClosed'); return; }
  if (!document.getElementById('mdtTerminal').hidden) { post('closeMdtTerminal'); return; }
  post('escape');
});
document.getElementById('npcDialogueContinue').onclick = (event) => {
  if (event.currentTarget.dataset.revealChoices === 'true') {
    event.currentTarget.dataset.revealChoices = 'false';
    event.currentTarget.hidden = true;
    document.getElementById('npcDialogueOptions').hidden = false;
    document.getElementById('npcDialogueQuote').textContent = 'Please choose the Police service you need.';
    post('npcDialogueStage', { stage: 'services' });
    return;
  }
  post('npcDialogueContinue');
};
document.getElementById('npcDialogueClose').onclick = () => post('npcDialogueClose');
document.getElementById('npcDialogueOptions').onclick = async (event) => {
  const choice = event.target.closest('[data-npc-dialogue-choice]');
  if (!choice || choice.disabled) return;
  document.querySelectorAll('[data-npc-dialogue-choice]').forEach((button) => { button.disabled = true; });
  await post('npcDialogueChoice', { choice: choice.dataset.npcDialogueChoice });
  document.querySelectorAll('[data-npc-dialogue-choice]').forEach((button) => { button.disabled = false; });
};
document.getElementById('accessSave').onclick = () => post('saveCinematicAccessibility', {
  mode: document.getElementById('accessCinematicMode').value,
  subtitleScale: Number(document.getElementById('accessSubtitleScale').value),
  soundVolume: Number(document.getElementById('accessSoundVolume').value),
  reducedFlash: document.getElementById('accessReducedFlash').checked,
  skipSeen: document.getElementById('accessSkipSeen').checked,
});
document.getElementById('accessClose').onclick = () => post('closeCinematicAccessibility');

setInterval(() => {
  const clock = document.getElementById('mdtTermClock');
  if (clock) clock.textContent = new Date().toLocaleTimeString('en-GB');
}, 1000);
