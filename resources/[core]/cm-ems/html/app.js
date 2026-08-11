const app = document.getElementById('app');
const npcDialogue = document.getElementById('npcDialogue');
const res = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-ems';
let state = null;
let page = 'overview';
let editingRankId = null;
let employeeTasks = null;
let missionBoardData = null;
let emsCallHistory = null;
let missionAdminData = null;
let editingMissionId = null;
let missionStageDraft = [];

const post = (name, data = {}) => fetch(`https://${res}/${name}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
}).then((response) => response.json());
const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (character) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;',
})[character]);
const can = (permission) => state?.self?.isLeader === true || state?.self?.permissions?.[permission] === true;

document.getElementById('npcDialogueContinue').onclick = () => post('npcDialogueContinue');
document.getElementById('npcDialogueClose').onclick = () => post('npcDialogueClose');
window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !npcDialogue.hidden) post('npcDialogueClose');
});

function showPage(next) {
  page = next;
  document.querySelectorAll('.nav').forEach((item) => item.classList.toggle('active', item.dataset.page === page));
  document.querySelectorAll('.page').forEach((item) => item.classList.toggle('active', item.dataset.view === page));
  const names = { overview: 'Medical operations', members: 'EMS members', ranks: 'Ranks & access', outfits: 'Duty outfits', fleet: 'Fleet vehicles', logs: 'Activity logs', admin: 'EMS administration', medical: 'Medical records', tasks: 'Employee tasks', callhistory: 'Call history' };
  document.getElementById('pageTitle').textContent = names[page] || 'EMS';
  if (page === 'fleet' && fleetVehicles.length === 0) loadFleet();
  if (page === 'tasks' && !employeeTasks) loadEmployeeTasks();
  if (page === 'tasks' && !missionBoardData) loadMissionBoard();
  if (page === 'callhistory' && !emsCallHistory) loadCallHistory();
  if (page === 'admin' && state?.adminMode && !missionAdminData) loadMissionAdmin();
}

const historyEventNames = { created: 'Call created', accepted: 'Call accepted', en_route: 'En route', on_scene: 'Arrived on scene', transporting: 'Transporting patient', at_hospital: 'Arrived at hospital', clear: 'Responder cleared', resolved: 'Call resolved', removed: 'Call removed', expired: 'Call expired', declined: 'Call declined', ai_assigned: 'Government doctor assigned' };

function renderCallHistory() {
  document.getElementById('emsCallHistory').innerHTML = (emsCallHistory || []).map((call) => {
    const responders = [...new Set((call.timeline || []).filter((event) => event.type === 'accepted').map((event) => event.actorName).filter(Boolean))].join(', ') || 'No live EMS responder';
    const timeline = (call.timeline || []).map((event) => `<div class="ems-history-event"><i></i><div><strong>${esc(historyEventNames[event.type] || String(event.type || '').replaceAll('_', ' '))}</strong><small>${esc(event.actorName || 'System')} · ${esc(event.at || '')}</small></div></div>`).join('');
    return `<article class="ems-history-card"><div class="ems-history-head"><div><small>${esc(call.incidentNumber || `#${call.id}`)} · PRIORITY ${esc(call.priority || 3)}</small><h4>${esc(call.callerName || 'Unknown caller')}</h4></div><span>${esc(call.resolution || call.responseStatus || 'closed')}</span></div><p>${esc(call.emergencyType || 'medical')} · ${esc(call.details || 'Medical assistance requested.')} · ${esc(call.postal || 'No postal')}</p><div class="ems-history-meta"><strong>${esc(responders)}</strong><span>Accepted: ${esc(call.acceptedAt || '—')}</span><span>On scene: ${esc(call.onSceneAt || '—')}</span><span>Closed: ${esc(call.closedAt || call.resolvedAt || '—')}</span></div><div class="ems-history-timeline">${timeline || '<small>No detailed timeline was recorded for this older incident.</small>'}</div></article>`;
  }).join('') || '<article class="card">No EMS calls have been recorded.</article>';
}

async function loadCallHistory() {
  const result = await post('emsCallHistory');
  emsCallHistory = result?.rows || [];
  renderCallHistory();
}

function renderMissionBoard() {
  const active = missionBoardData?.active;
  const crew = active?.participants || [];
  document.getElementById('activeMissionCard').innerHTML = active ? `<article class="active-mission"><div><small>ACTIVE ${active.publicIncidentId ? 'PUBLIC EMERGENCY' : 'MISSION'} · ${esc(active.category)}</small><h4>${esc(active.label)}</h4><p>${esc(active.stage?.label || 'Continue the active route')} · Stage ${Number(active.stageIndex)} of ${Number(active.stageCount)}</p><div class="mission-crew">${crew.map((medic) => `<span>${medic.role === 'leader' ? '★ ' : ''}${esc(medic.name)} · ${Number(medic.contributedStages || 0)} stage(s)</span>`).join('')}</div></div><div><strong>$${Number(active.reward).toLocaleString()} · ${Number(active.xp)} XP</strong><small>${Number(active.participantCount || crew.length)} / ${Number(active.maximumMedics || 6)} MEDICS</small><button class="mini danger" id="cancelActiveMission">${active.isLeader ? (crew.length > 1 ? 'Leave & transfer lead' : 'Cancel mission') : 'Leave crew'}</button></div></article>` : '';
  const publicCalls = missionBoardData?.publicCalls || [];
  document.getElementById('publicEmergencySection').innerHTML = publicCalls.length ? `<div class="mission-live-section"><div class="mission-live-title"><span class="live-dot"></span><div><small>LIVE PUBLIC EMERGENCIES</small><h3>NPC emergency calls</h3></div></div><div class="mission-grid">${publicCalls.map((call) => `<article class="mission-card public-call"><div class="mission-card__top"><span>${esc(call.category)}</span><strong>CALL #${Number(call.id)}</strong></div><h4>${esc(call.label)}</h4><p>${esc(call.description)}</p><div class="mission-card__reward"><span>$${Number(call.reward).toLocaleString()}</span><span>${Number(call.xp)} XP</span></div><button class="primary" data-accept-public="${Number(call.id)}"${active ? ' disabled' : ''}>ACCEPT EMERGENCY</button></article>`).join('')}</div></div>` : '';
  const openCrews = missionBoardData?.openCrews || [];
  document.getElementById('openCrewSection').innerHTML = openCrews.length ? `<div class="mission-live-section"><div class="mission-live-title"><div><small>CO-OP RESPONSES</small><h3>Nearby EMS crews</h3></div></div><div class="crew-list">${openCrews.map((run) => `<article class="crew-card"><div><strong>${esc(run.label)}</strong><small>${esc(run.leaderName)} · Stage ${Number(run.stageIndex)}/${Number(run.stageCount)}</small></div><span>${Number(run.participantCount)}/${Number(run.maximumMedics)}</span><button class="mini" data-join-run="${Number(run.runId)}"${active ? ' disabled' : ''}>Join crew</button></article>`).join('')}</div></div>` : '';
  document.getElementById('missionBoard').innerHTML = (missionBoardData?.missions || []).map((mission) => {
    const cooldown = Number(mission.cooldownRemaining || 0);
    const disabled = active || cooldown > 0;
    const button = active ? 'MISSION ACTIVE' : cooldown > 0 ? `AVAILABLE IN ${Math.ceil(cooldown / 60)}M` : 'START TASK';
    return `<article class="mission-card"><div class="mission-card__top"><span>${esc(mission.category)}</span><strong>${Number(mission.stageCount)} STAGES</strong></div><h4>${esc(mission.label)}</h4><p>${esc(mission.description)}</p><div class="mission-card__reward"><span>$${Number(mission.reward).toLocaleString()}</span><span>${Number(mission.xp)} XP</span></div><button class="primary" data-start-mission="${esc(mission.id)}"${disabled ? ' disabled' : ''}>${button}</button></article>`;
  }).join('') || '<article class="card">No missions are configured.</article>';
  const cancel = document.getElementById('cancelActiveMission');
  if (cancel) cancel.onclick = async () => {
    if (active?.isLeader && crew.length > 1 && !window.confirm('Leave the mission and transfer leadership to another medic? Their crew keeps working the active run.')) return;
    const result = await post('cancelMission'); if (result?.board) missionBoardData = result.board; else await loadMissionBoard(); renderMissionBoard();
  };
}

async function loadMissionBoard() {
  const result = await post('missionBoard');
  missionBoardData = result?.board || { missions: [], active: null };
  renderMissionBoard();
}

const blankMissionStage = () => ({ type: 'treat', label: '', location: '', duration: 8000, radius: 18, x: '', y: '', z: '', requireTransportVehicle: false, spawnVehicle: 'ambulance', vehicleHeading: 0, heading: 0 });

function renderMissionAdminList() {
  const list = document.getElementById('missionAdminList');
  list.innerHTML = (missionAdminData || []).map((mission) => `<article class="mission-admin-row"><div><strong>${esc(mission.label)}</strong><small>${esc(mission.category)} · ${Number((mission.stages || []).length)} stages · $${Number(mission.reward).toLocaleString()} · ${Number(mission.xp)} XP${mission.automaticEmergency ? ' · AUTO CALL' : ''}${mission.enabled ? '' : ' · DISABLED'}</small></div><div><button class="mini" data-edit-admin-mission="${Number(mission.databaseId)}">Edit</button><button class="mini danger" data-delete-admin-mission="${Number(mission.databaseId)}">Delete</button></div></article>`).join('') || '<div class="empty-admin-missions">No custom missions yet. Built-in missions remain available from config.</div>';
}

async function loadMissionAdmin() {
  const result = await post('missionAdminList');
  missionAdminData = result?.missions || [];
  renderMissionAdminList();
}

function renderMissionStages() {
  document.getElementById('missionStageList').innerHTML = missionStageDraft.map((stage, index) => `<article class="mission-stage" data-stage-index="${index}">
    <div class="mission-stage-number">${String(index + 1).padStart(2, '0')}</div>
    <div class="mission-stage-fields">
      <label>Action<select data-stage-field="type"><option value="pickup">Collect / pickup</option><option value="deliver">Deliver</option><option value="treat">Treat patient</option><option value="recover">Recover patient</option><option value="escort_patient">Escort patient</option><option value="board_vehicle">Load into EMS vehicle</option><option value="transport">Transport to destination</option><option value="hospital_handoff">Hospital bay handoff</option><option value="unload_patient">Unload patient (legacy)</option><option value="deliver_patient">Take patient to bed (legacy)</option><option value="pickup_patient">Collect transfer patient</option><option value="repair">Repair EMS vehicle</option></select></label>
      <label>Objective<input data-stage-field="label" maxlength="96" value="${esc(stage.label)}" placeholder="Stabilize the patient"></label>
      <label>Location name<input data-stage-field="location" maxlength="96" value="${esc(stage.location)}" placeholder="Great Ocean Highway"></label>
      <label>Action time (ms)<input data-stage-field="duration" type="number" min="0" max="60000" value="${Number(stage.duration || 0)}"></label>
      <label>Radius (m)<input data-stage-field="radius" type="number" min="3" max="50" value="${Number(stage.radius || 18)}"></label>
      <label>X<input data-stage-field="x" type="number" step="0.0001" value="${esc(stage.x)}"></label>
      <label>Y<input data-stage-field="y" type="number" step="0.0001" value="${esc(stage.y)}"></label>
      <label>Z<input data-stage-field="z" type="number" step="0.0001" value="${esc(stage.z)}"></label>
      <label class="check-field"><input data-stage-field="requireTransportVehicle" type="checkbox"${stage.requireTransportVehicle ? ' checked' : ''}> Require EMS vehicle</label>
    </div>
    <div class="mission-stage-actions"><button class="mini" data-stage-position="${index}">Place in world</button><button class="mini danger" data-remove-stage="${index}">Remove</button></div>
  </article>`).join('');
  document.querySelectorAll('#missionStageList [data-stage-field="type"]').forEach((select, index) => { select.value = missionStageDraft[index].type; });
}

function openMissionEditor(mission = null) {
  editingMissionId = mission?.databaseId || null;
  document.getElementById('missionEditLabel').value = mission?.label || '';
  document.getElementById('missionEditCategory').value = mission?.category || 'LAND RESCUE';
  document.getElementById('missionEditDescription').value = mission?.description || '';
  document.getElementById('missionEditReward').value = mission?.reward ?? 1000;
  document.getElementById('missionEditXp').value = mission?.xp ?? 50;
  document.getElementById('missionEditTime').value = mission?.timeLimitSeconds ?? 0;
  document.getElementById('missionEditPatient').checked = mission?.patient !== false;
  document.getElementById('missionEditAutomatic').checked = mission?.automaticEmergency === true;
  document.getElementById('missionEditEnabled').checked = mission?.enabled !== false;
  missionStageDraft = (mission?.stages || [blankMissionStage()]).map((stage) => ({
    ...blankMissionStage(), ...stage, x: stage.coords?.x ?? stage.x ?? '', y: stage.coords?.y ?? stage.y ?? '', z: stage.coords?.z ?? stage.z ?? '',
  }));
  document.getElementById('missionEditor').hidden = false;
  renderMissionStages();
}

function closeMissionEditor() {
  editingMissionId = null;
  missionStageDraft = [];
  document.getElementById('missionEditor').hidden = true;
}

function readMissionStages() {
  document.querySelectorAll('#missionStageList [data-stage-index]').forEach((row) => {
    const index = Number(row.dataset.stageIndex);
    row.querySelectorAll('[data-stage-field]').forEach((field) => {
      const key = field.dataset.stageField;
      missionStageDraft[index][key] = field.type === 'checkbox' ? field.checked : (field.type === 'number' ? Number(field.value) : field.value);
    });
  });
}

function renderEmployeeTasks() {
  const career = employeeTasks?.progression || {};
  const start = Number(career.levelStartXp || 0);
  const end = Number(career.nextLevelXp || start);
  const careerPercent = career.maxLevel ? 100 : Math.min(100, Math.max(0, Math.round(((Number(career.xp || 0) - start) / Math.max(1, end - start)) * 100)));
  document.getElementById('careerProgress').innerHTML = `<div><small>EMS CAREER LEVEL</small><h3>Level ${Number(career.level || 1)} · ${esc(career.label || 'EMS Responder')}</h3><p>${career.maxLevel ? 'Maximum career level reached.' : `${Number(career.xp || 0).toLocaleString()} / ${end.toLocaleString()} XP · Next: ${esc(career.nextLevelLabel || '')}`}</p></div><strong>${Number(career.xp || 0).toLocaleString()} XP</strong><div class="career-progress"><i style="width:${careerPercent}%"></i></div>`;
  const renderPeriod = (period) => {
    const rows = employeeTasks?.[period] || [];
    document.getElementById(`${period}Tasks`).innerHTML = rows.map((task) => {
      const percent = Math.min(100, Math.round((Number(task.progress) / Number(task.target || 1)) * 100));
      const button = task.claimed ? '<button class="mini" disabled>CLAIMED</button>' : task.completed ? `<button class="primary" data-task-claim="${esc(task.id)}" data-task-period="${period}">CLAIM $${Number(task.reward).toLocaleString()}</button>` : '<button class="mini" disabled>IN PROGRESS</button>';
      return `<article class="task-card${task.completed ? ' complete' : ''}${task.claimed ? ' claimed' : ''}"><div class="task-card__top"><div><small>${period.toUpperCase()}</small><h4>${esc(task.label)}</h4></div><strong>$${Number(task.reward).toLocaleString()}</strong></div><p>${esc(task.description)}</p><div class="task-progress"><i style="width:${percent}%"></i></div><div class="task-card__foot"><span>${Number(task.progress).toLocaleString()} / ${Number(task.target).toLocaleString()}</span>${button}</div></article>`;
    }).join('') || '<article class="card">No tasks are available for your current rank.</article>';
  };
  renderPeriod('daily'); renderPeriod('weekly');
}

async function loadEmployeeTasks() {
  const result = await post('employeeTasks');
  employeeTasks = result?.tasks || null;
  renderEmployeeTasks();
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
    const grantable = can('ems.manage_permissions') && can(key);
    return `<label class="permission-check"><input type="checkbox" value="${esc(key)}"${checked}${grantable ? '' : ' disabled'}><span>${esc(label)}</span></label>`;
  }).join('');
  document.getElementById('rankEditor').hidden = false;
}

// ── Fleet vehicles ──────────────────────────────────────────────────────
// Appearance (model/label/category/image/mods) is sourced live from
// rn-vehicleshop's "EMS fleet vehicle" catalog status -- there is no editor
// for colors/livery/etc here; that lives entirely in /vehicleadmin.
//
// cm-ems only adds: minimum rank tier (edited inline below, like family's
// vehicle-sharing row) and a Spawn button. Spawn location is never set from
// the NUI -- it's set/updated in-game by driving the vehicle and pressing H
// (client/vehicles.lua), and "Spawn" always recalls/replaces any existing
// live instance instead of piling up duplicates.
let fleetVehicles = [];
let fleetStandalone = false;

function renderFleetList() {
  const manage = can('ems.manage_vehicles');
  document.getElementById('recallFleet').hidden = !manage;
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
        ${canSpawnThis ? `<button class="mini" data-fleet-spawn="${esc(v.model)}"${v.status === 'occupied' ? ' disabled' : ''}>${v.status === 'deployed' ? 'Return & call here' : v.status === 'occupied' ? 'Occupied' : 'Call vehicle'}</button>` : ''}
      </div>
    </article>`;
  }).join('') || `<article class="card">${manage ? 'No vehicles are tagged &quot;EMS fleet vehicle&quot; in /vehicleadmin yet.' : 'No EMS fleet vehicles are available to your rank yet.'}</article>`;
}

async function loadFleet() {
  const result = await post('fleetCatalog');
  fleetVehicles = result?.vehicles || [];
  renderFleetList();
}

document.getElementById('fleetList').addEventListener('click', async (event) => {
  const spawn = event.target.closest('[data-fleet-spawn]');
  if (spawn) post('spawnFleetVehicle', { model: spawn.dataset.fleetSpawn });
  const location = event.target.closest('[data-fleet-location]');
  if (location) {
    if (!window.confirm('Overwrite this vehicle\'s saved spawn location with your current position?')) return;
    await post('setFleetVehicleLocation', { model: location.dataset.fleetLocation });
    loadFleet();
  }
});
document.getElementById('fleetList').addEventListener('change', (event) => {
  const tierInput = event.target.closest('[data-fleet-tier]');
  if (!tierInput) return;
  post('setFleetVehicleMinTier', { model: tierInput.dataset.fleetTier, minTier: Number(tierInput.value || 0) }).then((result) => {
    if (!result?.ok) loadFleet();
  });
});

// ── Duty clothing (wardrobe presets) ────────────────────────────────────
// Presets are named clothing sets an ems.manage_outfits manager saves from
// their own currently worn clothes. Any EMS member picks one to wear -- it
// is applied directly to the ped (never an inventory item) and always
// reverts to the member's own clothes the moment they go off duty.
function render() {
  if (!state) return;
  const self = state.self;
  const permissions = self?.permissions || {};
  const capabilities = state.capabilities || {};
  document.getElementById('memberRank').textContent = self?.rankName || (state.adminMode ? 'Administrator' : 'Organization');
  document.querySelectorAll('.admin-only').forEach((item) => { item.hidden = !state.adminMode; });
  document.querySelectorAll('.logs-only').forEach((item) => { item.hidden = state.canViewLogs !== true; });
  if (page === 'logs' && state.canViewLogs !== true) page = 'overview';
  const canFleet = capabilities.manageVehicles === true || capabilities.spawnVehicles === true;
  document.querySelectorAll('.fleet-only').forEach((item) => { item.hidden = !canFleet || !fleetStandalone; });
  if (page === 'fleet' && !canFleet) page = 'overview';
  const canMedical = capabilities.viewMedicalReports === true || capabilities.writeMedicalReports === true;
  document.querySelectorAll('.medical-only').forEach((item) => { item.hidden = !canMedical; });
  document.getElementById('reportForm').hidden = capabilities.writeMedicalReports !== true;
  if (page === 'medical' && !canMedical) page = 'overview';
  document.querySelectorAll('.tasks-only').forEach((item) => { item.hidden = !self; });
  document.querySelectorAll('.history-only').forEach((item) => { item.hidden = !self; });
  if (page === 'callhistory' && !self) page = 'overview';
  if (page === 'tasks' && !self) page = 'overview';
  const online = state.members.filter((member) => member.online).length;
  const duty = state.members.filter((member) => member.onDuty).length;
  document.getElementById('stats').innerHTML = `
    <div class="stat"><span>EMS LEADER</span><strong>${esc(state.organization.leaderName)}</strong><small>CID ${esc(state.organization.leaderCid || '—')}</small></div>
    <div class="stat"><span>MEMBERS</span><strong>${state.members.length}</strong><small>${online} online</small></div>
    <div class="stat"><span>ON DUTY</span><strong>${duty}</strong><small>Available now</small></div>
    <div class="stat"><span>YOUR RANK</span><strong>${esc(self?.rankName || 'Admin')}</strong><small>${self ? `Tier ${self.tier}` : 'Management access'}</small></div>`;
  const medicStats = state.statistics || {};
  const responseSeconds = Number(medicStats.averageResponseSeconds || 0);
  document.getElementById('medicStats').innerHTML = `
    <div class="stat"><span>PATIENTS TREATED</span><strong>${Number(medicStats.patientsTreated || 0).toLocaleString()}</strong><small>${Number(medicStats.patientsRevived || 0).toLocaleString()} successful revives</small></div>
    <div class="stat"><span>CALLS COMPLETED</span><strong>${Number(medicStats.callsCompleted || 0).toLocaleString()}</strong><small>Resolved incidents</small></div>
    ${state.operations && Object.keys(state.operations).length ? `<div class="stat"><span>LIVE OPERATIONS</span><strong>${Number(state.operations.activeCalls || 0).toLocaleString()}</strong><small>${Number(state.operations.waitingTooLong || 0)} waiting over 2m · ${Number(state.operations.onDutyMedics || 0)} on duty</small></div><div class="stat"><span>MEDICINE STOCK</span><strong>${Number(state.operations.medicineStockPercent || 0)}%</strong><small>${Number(state.operations.pendingReconciliations || 0)} pending refund reconciliation(s)</small></div>` : ''}
    <div class="stat"><span>AVG RESPONSE</span><strong>${responseSeconds ? `${Math.floor(responseSeconds / 60)}m ${responseSeconds % 60}s` : '—'}</strong><small>Call created to on scene</small></div>`;

  const onDuty = self?.onDuty === true;
  document.getElementById('dutyTitle').textContent = onDuty ? 'On duty' : 'Off duty';
  document.getElementById('dutyText').textContent = onDuty ? 'Your EMS duty clothing is active.' : 'Go on duty to wear your chosen EMS clothing.';
  document.getElementById('dutyTitle').textContent = onDuty ? 'On duty' : 'Off duty';
  document.getElementById('dutyText').textContent = onDuty ? 'Your approved EMS uniform is active.' : 'Visit the EMS wardrobe NPC to choose an approved uniform and begin duty.';
  document.getElementById('memberMap').hidden = capabilities.viewMemberMap !== true;
  document.getElementById('meetingPoint').hidden = capabilities.setMeeting !== true;
  document.getElementById('setDailyMissionNpc').hidden = capabilities.manageMissions !== true;
  document.getElementById('dailyMissionNpcStatus').textContent = state.dailyMissionNpc
    ? 'Daily mission NPC location is set.' : 'Daily mission NPC location is not set yet.';
  document.getElementById('setClothingNpc').hidden = capabilities.manageOutfits !== true;
  document.getElementById('clothingNpcStatus').textContent = state.clothingNpc
    ? 'Wardrobe NPC location is set.' : 'Wardrobe NPC location is not set yet.';

  document.getElementById('members').innerHTML = state.members.map((member) => {
    const lower = self && (self.isLeader || self.tier > member.tier) && !member.isLeader;
    return `<article class="member"><div class="avatar">${esc(member.name.slice(0, 1).toUpperCase())}</div><div class="member-main"><strong>${esc(member.name)}</strong><small>CID ${esc(member.characterId)} · ${esc(member.rankName)} · ${member.online ? 'Online' : 'Offline'}${member.onDuty ? ' · On duty' : ''}</small></div><div class="member-actions">${lower && (self.isLeader || permissions['ems.promote']) ? `<button class="mini" data-action="promote" data-cid="${esc(member.characterId)}">Promote</button>` : ''}${lower && (self.isLeader || permissions['ems.demote']) ? `<button class="mini danger" data-action="demote" data-cid="${esc(member.characterId)}">Demote</button>` : ''}${lower && (self.isLeader || permissions['ems.kick']) ? `<button class="mini danger" data-action="kick" data-cid="${esc(member.characterId)}">Remove</button>` : ''}</div></article>`;
  }).join('') || '<article class="card">No EMS members.</article>';

  document.getElementById('newRank').hidden = !self || capabilities.manageRanks !== true;
  document.getElementById('ranks').innerHTML = state.ranks.map((rank) => {
    const manageable = self && !rank.isLeader && rank.tier < self.tier && capabilities.manageRanks === true;
    const permissionBadges = Object.keys(rank.permissions || {}).filter((key) => rank.permissions[key]).map((key) => `<span class="permission">${esc(state.permissions[key] || key)}</span>`).join('');
    return `<article class="rank"><div class="rank-head"><h4>${esc(rank.name)} · Tier ${rank.tier}${rank.isLeader ? ' · ALL PERMISSIONS' : ''}</h4><div class="rank-actions">${manageable ? `<button class="mini" data-rank-edit="${rank.id}">Edit</button><button class="mini danger" data-rank-delete="${rank.id}">Delete</button>` : ''}</div></div><div class="permissions">${permissionBadges || '<span class="permission">No permissions</span>'}</div></article>`;
  }).join('');

  const actionNames = {
    duty_started: 'Started duty', duty_ended: 'Ended duty',
    outfit_preset_created: 'Created clothing preset', outfit_preset_updated: 'Updated clothing preset',
    outfit_preset_deleted: 'Deleted clothing preset', outfit_chosen: 'Chose EMS clothing',
    rank_created: 'Created rank', rank_updated: 'Updated rank', rank_deleted: 'Deleted rank',
    member_promoted: 'Promoted member', member_demoted: 'Demoted member', member_removed: 'Removed member',
    invite_sent: 'Sent invitation', invite_accepted: 'Accepted invitation', leader_assigned: 'Assigned EMS leader',
    ambulance_call_requested: 'Requested an ambulance', ambulance_call_accepted: 'Accepted ambulance call',
    ambulance_call_removed: 'Removed ambulance call', ambulance_call_resolved: 'Resolved ambulance call',
    government_doctor_dispatched: 'Sent government doctor', government_doctor_treated: 'Government doctor treated patient',
    government_doctor_failed: 'Government doctor response failed', employee_task_claimed: 'Claimed employee task reward',
    ems_mission_started: 'Started EMS mission', ems_mission_completed: 'Completed EMS mission',
    ems_mission_cancelled: 'Cancelled EMS mission', ems_mission_joined: 'Joined EMS mission crew',
    ems_mission_left: 'Left EMS mission crew', ems_mission_definition_saved: 'Saved custom EMS mission',
    ems_mission_definition_deleted: 'Deleted custom EMS mission', ems_public_emergency_created: 'Created public EMS emergency',
  };
  const describe = (detail = {}) => {
    const parts = [];
    if (detail.targetCid) parts.push(`Target CID ${esc(detail.targetCid)}`);
    if (detail.name) parts.push(esc(detail.name));
    if (detail.rank) parts.push(esc(detail.rank));
    if (detail.tier !== undefined) parts.push(`Tier ${esc(detail.tier)}`);
    if (detail.sex) parts.push(`${esc(detail.sex)} clothing`);
    if (detail.presetId !== undefined) parts.push(`Preset #${esc(detail.presetId)}`);
    if (detail.callId !== undefined) parts.push(`Call #${esc(detail.callId)}`);
    if (detail.taskId) parts.push(esc(detail.taskId));
    if (detail.period) parts.push(esc(detail.period));
    if (detail.reward !== undefined) parts.push(`$${Number(detail.reward).toLocaleString()} reward`);
    if (detail.missionId) parts.push(esc(detail.missionId));
    if (detail.runId !== undefined) parts.push(`Mission #${esc(detail.runId)}`);
    if (detail.respondersNotified !== undefined) parts.push(`${esc(detail.respondersNotified)} EMS notified`);
    return parts.join(' · ') || 'No additional details';
  };
  document.getElementById('logs').innerHTML = (state.logs || []).map((entry) => `<article class="log-row"><div class="log-who"><strong>${esc(entry.actorName)}</strong><small>${entry.actorCid ? `CID ${esc(entry.actorCid)}` : 'System'}</small></div><div><strong class="log-action">${esc(actionNames[entry.action] || entry.action)}</strong><small>${describe(entry.detail)}</small></div><time>${esc(entry.createdAt)}</time></article>`).join('') || '<article class="card">No EMS activity has been recorded yet.</article>';
  if (state.adminMode) {
    document.getElementById('staffRank').innerHTML = state.ranks.filter((rank) => !rank.isLeader).map((rank) => `<option value="${rank.id}">${esc(rank.name)} · Tier ${rank.tier}</option>`).join('');
    const settings = state.settings || {};
    document.getElementById('settingTreatment').value = settings.treatmentPrice ?? 250;
    document.getElementById('settingRespawn').value = settings.deathRespawnPrice ?? 500;
    document.getElementById('settingReward').value = settings.medicReward ?? 100;
    document.getElementById('settingArrival').value = Math.round(Number(settings.aiArrivalMs || 120000) / 1000);
    document.getElementById('settingRadius').value = settings.sharedResponseRadius ?? 40;
    document.getElementById('settingHospital').checked = settings.hospitalEnabled !== false;
    document.getElementById('settingAutoDispatch').checked = settings.autoDispatchEnabled !== false;
  }
  const favorites = state.favoriteOutfits || [];
  const favoriteBySlot = new Map(favorites.map((item) => [Number(item.slot), item]));
  document.getElementById('favoriteOutfitList').innerHTML = Array.from({ length: Number(state.maxFavoriteOutfitSlots || 5) }, (_, index) => {
    const slot = index + 1;
    const favorite = favoriteBySlot.get(slot);
    const selected = Number(state.selectedFavoriteOutfitSlot) === slot;
    return `<article class="member"><div class="member-main"><strong>Slot ${slot}${favorite ? ` · ${esc(favorite.name)}` : ''}</strong><small>${favorite ? `Saved ${esc(favorite.updatedAt)}` : 'Empty favorite slot'}</small></div><div class="member-actions">${selected ? '<span class="permission">Selected for duty</span>' : ''}${favorite ? `<button class="mini danger" data-favorite-delete="${slot}">Clear</button>` : ''}</div></article>`;
  }).join('');
  showPage(page);
}

let wardrobeItems = [], wardrobeCategories = [], wardrobeCategory = null, wardrobeOptionIndex = 0, wardrobeColorIndex = 0;
const wardrobeDrawables = (category) => {
  const seen = new Set();
  return wardrobeItems.filter((item) => item.category === category && !seen.has(item.drawableId) && seen.add(item.drawableId));
};
const wardrobeTextures = (category, drawableId) => wardrobeItems.filter((item) => item.category === category && item.drawableId === drawableId);
function renderWardrobe() {
  document.getElementById('wardrobeCategoryList').innerHTML = wardrobeCategories.map((category) => `<button class="wardrobe-category-item${category === wardrobeCategory ? ' active' : ''}" data-wardrobe-category="${esc(category)}">${esc(category.replaceAll('_', ' '))}</button>`).join('');
  const drawables = wardrobeDrawables(wardrobeCategory);
  const current = drawables[wardrobeOptionIndex];
  const colors = current ? wardrobeTextures(wardrobeCategory, current.drawableId) : [];
  const selected = colors[wardrobeColorIndex] || colors[0];
  document.getElementById('wardrobeOptionLabel').textContent = current?.label || '--';
  document.getElementById('wardrobeColorLabel').textContent = selected ? `#${selected.textureId}` : '--';
  if (selected) post('previewWardrobeItem', selected);
}
async function openWardrobeRoom() {
  const result = await post('openWardrobeDressingRoom');
  if (!result?.ok) return;
  wardrobeItems = (result.items || []).map((item) => ({ ...item, category: item.category || 'other' }));
  wardrobeCategories = [...new Set(wardrobeItems.map((item) => item.category))].sort();
  wardrobeCategory = wardrobeCategories[0] || null; wardrobeOptionIndex = 0; wardrobeColorIndex = 0;
  app.hidden = true; document.getElementById('wardrobeRoom').hidden = false; renderWardrobe();
}
async function closeWardrobeRoom() {
  document.getElementById('wardrobeRoom').hidden = true; app.hidden = false;
  await post('closeWardrobeDressingRoom');
}

document.querySelectorAll('.nav').forEach((item) => { item.onclick = () => showPage(item.dataset.page); });
document.getElementById('close').onclick = () => post('close');
document.getElementById('memberMap').onclick = () => post('action', { action: 'toggle_member_map', payload: {} });
document.getElementById('meetingPoint').onclick = () => post('action', { action: 'set_meeting', payload: {} });
document.getElementById('setClothingNpc').onclick = () => post('action', { action: 'set_clothing_npc', payload: {} });
document.getElementById('recallFleet').onclick = () => { if (window.confirm('Recall every free EMS fleet vehicle back to its spawn point?')) post('recallAllFleetVehicles', {}); };
document.getElementById('openEmsClothingAdmin').onclick = () => post('openEmsClothingAdmin', {});
document.getElementById('wardrobeDone').onclick = closeWardrobeRoom;
document.getElementById('wardrobeCategoryList').onclick = (event) => { const item = event.target.closest('[data-wardrobe-category]'); if (item) { wardrobeCategory = item.dataset.wardrobeCategory; wardrobeOptionIndex = 0; wardrobeColorIndex = 0; renderWardrobe(); } };
document.getElementById('wardrobeOptionPrev').onclick = () => { const list = wardrobeDrawables(wardrobeCategory); if (list.length) { wardrobeOptionIndex = (wardrobeOptionIndex - 1 + list.length) % list.length; wardrobeColorIndex = 0; renderWardrobe(); } };
document.getElementById('wardrobeOptionNext').onclick = () => { const list = wardrobeDrawables(wardrobeCategory); if (list.length) { wardrobeOptionIndex = (wardrobeOptionIndex + 1) % list.length; wardrobeColorIndex = 0; renderWardrobe(); } };
document.getElementById('wardrobeColorPrev').onclick = () => { const current = wardrobeDrawables(wardrobeCategory)[wardrobeOptionIndex]; const list = current ? wardrobeTextures(wardrobeCategory, current.drawableId) : []; if (list.length) { wardrobeColorIndex = (wardrobeColorIndex - 1 + list.length) % list.length; renderWardrobe(); } };
document.getElementById('wardrobeColorNext').onclick = () => { const current = wardrobeDrawables(wardrobeCategory)[wardrobeOptionIndex]; const list = current ? wardrobeTextures(wardrobeCategory, current.drawableId) : []; if (list.length) { wardrobeColorIndex = (wardrobeColorIndex + 1) % list.length; renderWardrobe(); } };
document.getElementById('saveFavoriteOutfit').onclick = async () => {
  const slot = Number(document.getElementById('favoriteOutfitSlot').value);
  const existing = (state.favoriteOutfits || []).find((item) => Number(item.slot) === slot);
  if (existing && !window.confirm(`Replace slot ${slot} (${existing.name}) with your current clothing?`)) return;
  post('action', { action: 'save_favorite_outfit', payload: { slot, name: document.getElementById('favoriteOutfitName').value.trim() || `Favorite ${slot}` } });
};
document.getElementById('favoriteOutfitList').onclick = (event) => {
  const del = event.target.closest('[data-favorite-delete]');
  if (del && window.confirm('Delete this favorite outfit slot?')) post('action', { action: 'delete_favorite_outfit', payload: { slot: Number(del.dataset.favoriteDelete) } });
};
(() => { const viewport = document.getElementById('wardrobeViewport'); let dragging = false, lastX = 0; viewport.onmousedown = (event) => { dragging = true; lastX = event.clientX; }; window.addEventListener('mouseup', () => { dragging = false; }); window.addEventListener('mousemove', (event) => { if (!dragging) return; const dx = event.clientX - lastX; lastX = event.clientX; post('rotateWardrobePed', { delta: -dx * .45 }); }); })();
document.getElementById('assignLeader').onclick = () => {
  const characterId = document.getElementById('leaderCid').value;
  if (!window.confirm(`Hand over full EMS leadership to character ID ${characterId}? This replaces the current leader immediately.`)) return;
  post('assignLeader', { characterId });
};
document.querySelectorAll('[data-staff-action]').forEach((button) => { button.onclick = () => {
  const confirmMessages = { fire: 'Fire this EMS employee?', suspend: 'Suspend this EMS employee?' };
  const message = confirmMessages[button.dataset.staffAction];
  if (message && !window.confirm(message)) return;
  post('adminStaffAction', { action: button.dataset.staffAction, characterId: document.getElementById('staffCid').value, rankId: Number(document.getElementById('staffRank').value), minutes: Number(document.getElementById('staffMinutes').value), reason: document.getElementById('staffReason').value });
}; });
document.getElementById('saveSettings').onclick = () => post('adminSaveSettings', { treatmentPrice: Number(document.getElementById('settingTreatment').value), deathRespawnPrice: Number(document.getElementById('settingRespawn').value), medicReward: Number(document.getElementById('settingReward').value), aiArrivalMs: Number(document.getElementById('settingArrival').value) * 1000, sharedResponseRadius: Number(document.getElementById('settingRadius').value), hospitalEnabled: document.getElementById('settingHospital').checked, autoDispatchEnabled: document.getElementById('settingAutoDispatch').checked });
document.getElementById('medicalSearch').onclick = async () => {
  const result = await post('medicalHistory', { patientCid: document.getElementById('medicalSearchCid').value });
  document.getElementById('medicalHistory').innerHTML = (result.rows || []).map((report) => `<article class="medical-report"><strong>#${esc(report.id)} · ${esc(report.patientName)} · ${esc(report.outcome)}</strong><small>${esc(report.createdAt)} · Medic: ${esc(report.medicName)} · Bill: $${Number(report.billing || 0).toLocaleString()}</small><small>${esc(report.treatment || 'No treatment notes')}</small></article>`).join('') || '<article class="card">No medical history found.</article>';
};
document.getElementById('saveMedicalReport').onclick = () => post('createMedicalReport', { patientCid: document.getElementById('reportPatientCid').value, incidentId: document.getElementById('reportIncidentId').value, injuries: document.getElementById('reportInjuries').value, medications: document.getElementById('reportMedications').value.split(',').map((v) => v.trim()).filter(Boolean), treatment: document.getElementById('reportTreatment').value, outcome: document.getElementById('reportOutcome').value, billing: Number(document.getElementById('reportBilling').value) });
document.getElementById('refreshTasks').onclick = () => { employeeTasks = null; loadEmployeeTasks(); };
document.getElementById('refreshMissions').onclick = () => { missionBoardData = null; loadMissionBoard(); };
document.getElementById('refreshCallHistory').onclick = () => { emsCallHistory = null; loadCallHistory(); };
document.querySelector('.mission-section').onclick = async (event) => {
  const button = event.target.closest('[data-start-mission]');
  const publicCall = event.target.closest('[data-accept-public]');
  const join = event.target.closest('[data-join-run]');
  if ((!button && !publicCall && !join) || button?.disabled || publicCall?.disabled || join?.disabled) return;
  let result;
  if (button) result = await post('startMission', { missionId: button.dataset.startMission });
  if (publicCall) result = await post('acceptPublicIncident', { incidentId: Number(publicCall.dataset.acceptPublic) });
  if (join) result = await post('joinMission', { runId: Number(join.dataset.joinRun) });
  if (result?.board) missionBoardData = result.board;
  renderMissionBoard();
};
document.querySelector('[data-view="tasks"]').onclick = async (event) => {
  const button = event.target.closest('[data-task-claim]');
  if (!button) return;
  const result = await post('claimEmployeeTask', { period: button.dataset.taskPeriod, taskId: button.dataset.taskClaim });
  if (result?.tasks) employeeTasks = result.tasks; else await loadEmployeeTasks();
  renderEmployeeTasks();
};
document.getElementById('newRank').onclick = () => openRankEditor();
document.getElementById('cancelRank').onclick = closeRankEditor;
document.getElementById('saveRank').onclick = () => {
  const permissions = [...document.querySelectorAll('#permissionEditor input:checked')].map((input) => input.value);
  post('action', { action: 'save_rank', payload: { rankId: editingRankId, name: document.getElementById('rankName').value, tier: document.getElementById('rankTier').value, permissions } });
};
document.getElementById('members').onclick = (event) => {
  const button = event.target.closest('[data-action]');
  if (!button) return;
  const confirmMessages = { demote: 'Demote this EMS member?', kick: 'Remove this member from the EMS roster?' };
  const message = confirmMessages[button.dataset.action];
  if (message && !window.confirm(message)) return;
  post('action', { action: button.dataset.action, payload: { characterId: button.dataset.cid } });
};
document.getElementById('ranks').onclick = (event) => {
  const edit = event.target.closest('[data-rank-edit]');
  const remove = event.target.closest('[data-rank-delete]');
  if (edit) openRankEditor(state.ranks.find((rank) => rank.id === Number(edit.dataset.rankEdit)));
  if (remove && window.confirm('Delete this rank? Members holding it will need to be reassigned.')) {
    post('action', { action: 'delete_rank', payload: { rankId: Number(remove.dataset.rankDelete) } });
  }
};
document.getElementById('newAdminMission').onclick = () => openMissionEditor();
document.getElementById('cancelMissionEdit').onclick = closeMissionEditor;
document.getElementById('addMissionStage').onclick = () => {
  readMissionStages();
  if (missionStageDraft.length >= 12) return;
  missionStageDraft.push(blankMissionStage());
  renderMissionStages();
};
document.getElementById('missionStageList').oninput = readMissionStages;
document.getElementById('missionStageList').onchange = readMissionStages;
document.getElementById('missionStageList').onclick = async (event) => {
  const position = event.target.closest('[data-stage-position]');
  const remove = event.target.closest('[data-remove-stage]');
  readMissionStages();
  if (position) {
    await post('missionPlaceStage', { stageIndex: Number(position.dataset.stagePosition) });
  }
  if (remove) {
    missionStageDraft.splice(Number(remove.dataset.removeStage), 1);
    renderMissionStages();
  }
};
document.getElementById('missionAdminList').onclick = async (event) => {
  const edit = event.target.closest('[data-edit-admin-mission]');
  const remove = event.target.closest('[data-delete-admin-mission]');
  if (edit) openMissionEditor((missionAdminData || []).find((mission) => Number(mission.databaseId) === Number(edit.dataset.editAdminMission)));
  if (remove && window.confirm('Delete this custom EMS mission? Existing active runs will not be interrupted.')) {
    const result = await post('deleteAdminMission', { databaseId: Number(remove.dataset.deleteAdminMission) });
    if (result?.ok) { missionAdminData = null; closeMissionEditor(); await loadMissionAdmin(); }
  }
};
document.getElementById('saveAdminMission').onclick = async () => {
  readMissionStages();
  const result = await post('saveAdminMission', {
    databaseId: editingMissionId,
    label: document.getElementById('missionEditLabel').value,
    category: document.getElementById('missionEditCategory').value,
    description: document.getElementById('missionEditDescription').value,
    reward: Number(document.getElementById('missionEditReward').value),
    xp: Number(document.getElementById('missionEditXp').value),
    timeLimitSeconds: Number(document.getElementById('missionEditTime').value),
    patient: document.getElementById('missionEditPatient').checked,
    automaticEmergency: document.getElementById('missionEditAutomatic').checked,
    enabled: document.getElementById('missionEditEnabled').checked,
    stages: missionStageDraft,
  });
  if (result?.ok) { missionAdminData = null; closeMissionEditor(); await loadMissionAdmin(); }
};
window.addEventListener('message', (event) => {
  // Setting a fleet vehicle's location closes this menu entirely (you drive
  // the location dummy in-game) without ever re-rendering the fleet list.
  // Clearing the cached list here forces a fresh fleetCatalog fetch the next
  // time the Fleet page is shown, instead of silently keeping the
  // pre-location-save snapshot (still showing "Not configured").
  if (event.data.action === 'open') { state = event.data.data; fleetStandalone = event.data.fleetStandalone === true; fleetVehicles = []; employeeTasks = null; missionBoardData = null; emsCallHistory = null; missionAdminData = null; if (event.data.initialPage) page = event.data.initialPage; app.hidden = false; closeRankEditor(); closeMissionEditor(); render(); }
  else if (event.data.action === 'close') { app.hidden = true; state = null; employeeTasks = null; missionBoardData = null; emsCallHistory = null; missionAdminData = null; closeRankEditor(); closeMissionEditor(); }
});
window.addEventListener('message', (event) => {
  const message = event.data || {};
  if (message.action === 'mission:placementMode') {
    app.classList.add('placing-stage');
  } else if (message.action === 'mission:positionCaptured') {
    const stage = missionStageDraft[Number(message.stageIndex)];
    if (stage) {
      stage.x = Number(message.x).toFixed(4); stage.y = Number(message.y).toFixed(4); stage.z = Number(message.z).toFixed(4);
      stage.vehicleHeading = Number(message.heading || 0);
      stage.heading = Number(message.heading || 0);
      renderMissionStages();
    }
    app.classList.remove('placing-stage');
  } else if (message.action === 'mission:placementCancelled') {
    app.classList.remove('placing-stage');
  }
});
window.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;
  if (!document.getElementById('wardrobeRoom').hidden) closeWardrobeRoom();
  else post('escape');
});

// EMS dispatch cards. The layout follows the supplied Unique Dispatch UI,
// implemented locally without jQuery, Font Awesome or external CDNs.
const dispatchOverlay = document.getElementById('dispatchOverlay');
const dispatchTimers = new Map();
const dispatchCard = (callId) => [...dispatchOverlay.children]
  .find((card) => card.dataset.dispatchId === String(callId));

function removeDispatchCard(callId) {
  const card = dispatchCard(callId);
  if (!card) return;
  card.classList.add('leaving');
  setTimeout(() => card.remove(), 360);
  const timer = dispatchTimers.get(String(callId));
  if (timer) clearTimeout(timer);
  dispatchTimers.delete(String(callId));
}

function addDispatchCard(call = {}) {
  const callId = String(call.id ?? '—');
  removeDispatchCard(callId);
  const card = document.createElement('article');
  card.className = 'dispatch-call';
  card.dataset.dispatchId = callId;
  card.innerHTML = `
    <div class="dispatch-call__top">
      <span class="dispatch-pill id">#${esc(callId)}</span>
      <span class="dispatch-pill code">${esc(call.code || 'AMB-01')}</span>
      <strong class="dispatch-call__title">${esc(call.title || 'Ambulance requested')}</strong>
    </div>
    <div class="dispatch-call__body">
      <div class="dispatch-call__row"><span class="dispatch-call__icon">●</span><span>${esc(call.location || 'Location unavailable')}</span></div>
      <div class="dispatch-call__row"><span class="dispatch-call__icon">+</span><span>${esc(call.details || 'Medical assistance requested.')}</span></div>
      ${Number(call.bucket || 0) !== 0 ? `<div class="dispatch-call__row"><span class="dispatch-call__icon">!</span><span>Caller is inside an instanced location</span></div>` : ''}
      <div class="dispatch-call__hint">Press Y to respond and set GPS</div>
    </div>`;
  dispatchOverlay.prepend(card);
  requestAnimationFrame(() => card.classList.add('visible'));
  const lifetime = Math.max(5000, Number(call.cardLifetimeMs) || 18000);
  dispatchTimers.set(callId, setTimeout(() => removeDispatchCard(callId), lifetime));
}

window.addEventListener('message', (event) => {
  const message = event.data || {};
  if (message.action === 'npcDialogue:open') {
    document.getElementById('npcDialogueName').textContent = message.name || 'Medical Staff';
    document.getElementById('npcDialogueRole').textContent = message.role || 'CM MEDICAL';
    document.getElementById('npcDialogueQuote').textContent = message.quote || 'How can I help you?';
    document.getElementById('npcDialogueSignature').textContent = `— ${message.name || 'Medical Staff'}`;
    document.getElementById('npcDialogueContinue').textContent = message.continueLabel || 'Continue';
    npcDialogue.hidden = false;
  } else if (message.action === 'npcDialogue:close') {
    npcDialogue.hidden = true;
  } else if (message.action === 'dispatch:newCall') addDispatchCard(message.call);
  else if (message.action === 'dispatch:accepted') {
    const card = dispatchCard(message.callId);
    if (card) {
      card.classList.add('accepted');
      const hint = card.querySelector('.dispatch-call__hint');
      if (hint) hint.textContent = 'Responding · GPS route active';
    }
  } else if (message.action === 'dispatch:clear') {
    [...dispatchOverlay.children].forEach((card) => removeDispatchCard(card.dataset.dispatchId));
  }
});

// Full F10 dispatch board.
const dispatchBoard = document.getElementById('dispatchBoard');
const dispatchBoardRows = document.getElementById('dispatchBoardRows');
let dispatchBoardData = { calls: [], canManage: false, selfCharacterId: null };
let dispatchFilter = 'active';

function renderDispatchBoard() {
  const calls = dispatchBoardData.calls || [];
  const isMine = (call) => (call.responders || []).some((responder) => String(responder.characterId) === String(dispatchBoardData.selfCharacterId));
  const assigned = calls.filter((call) => (call.responders || []).length > 0 || call.responderType).length;
  document.getElementById('dispatchActiveCount').textContent = String(calls.length - assigned);
  document.getElementById('dispatchAssignedCount').textContent = String(assigned);
  document.querySelectorAll('[data-dispatch-filter]').forEach((button) => {
    button.classList.toggle('active', button.dataset.dispatchFilter === dispatchFilter);
  });
  const visible = dispatchFilter === 'assigned' ? calls.filter((call) => (call.responders || []).length > 0 || call.responderType) : calls.filter((call) => (call.responders || []).length === 0 && !call.responderType);
  dispatchBoardRows.innerHTML = visible.map((call) => {
    const mine = isMine(call);
    const government = call.responderType === 'government_doctor';
    const priorityRequest = call.backupRequested || call.emergencyType === 'ems_panic';
    const responders = (call.responders || []).map((responder) => responder.name).join(', ');
    const notes = (call.notes || []).slice(-2).map((note) => `${note.author || 'EMS'}: ${note.text}`).join(' · ');
    const units = (dispatchBoardData.availableUnits || []).map((unit) =>
      `<option value="${esc(unit.characterId)}">${esc(unit.name)}</option>`).join('');
    const action = mine ? 'RESPONDING' : government ? 'GOV DOCTOR ASSIGNED' : (responders ? 'JOIN RESPONSE' : '♡ TAKE THE CALL');
    return `<article class="dispatch-board__row" data-board-call="${esc(call.id)}">
      <div class="dispatch-board__caller"><strong>${esc(call.callerName || 'Unknown caller')}</strong><small>${esc(call.incidentNumber || `#${call.id}`)} · ${esc(call.postal || call.location || 'Location unavailable')}</small></div>
      <div class="dispatch-board__status"><strong><span class="dispatch-priority">P${esc(call.priority || 3)}</span> ${esc(call.emergencyType || call.status || 'Medical')}</strong><small>${esc(call.details || 'Medical assistance requested.')} · ${esc(call.patientCount || 1)} patient(s)${responders ? ` · ${esc(responders)}` : ''}${call.patientInAmbulance ? ` · PATIENT IN AMBULANCE${call.transportVehiclePlate ? ` [${esc(call.transportVehiclePlate)}]` : ''}` : ''}${call.priorityAcknowledgedBy ? ` · BACKUP ACK: ${esc(call.priorityAcknowledgedBy)}` : ''}</small></div>
      <div class="dispatch-board__distance">${Number(call.distance || 0).toLocaleString()} M<br><small>ETA ${Math.max(1, Math.ceil(Number(call.etaSeconds || 0) / 60))} min</small></div>
      <div class="dispatch-board__actions">${priorityRequest && !mine ? `<button class="dispatch-board__take" data-dispatch-ack="${esc(call.id)}">ACKNOWLEDGE + GPS</button>` : ''}${mine ? `<select class="dispatch-board__status-select" data-dispatch-status="${esc(call.id)}"><option value="">${esc(call.responseStatus || 'en route').replaceAll('_', ' ')}</option><option value="en_route">En route</option><option value="on_scene">On scene</option><option value="transporting">Transporting</option><option value="at_hospital">At hospital</option><option value="clear">Clear call</option></select>${dispatchBoardData.canRequestBackup ? `<button class="dispatch-board__secondary" data-dispatch-backup="${esc(call.id)}">REQUEST BACKUP</button>` : ''}` : `${priorityRequest ? '' : `<button class="dispatch-board__take" data-dispatch-take="${esc(call.id)}"${government ? ' disabled' : ''}>${action}</button>`}<button class="dispatch-board__secondary" data-dispatch-reject="${esc(call.id)}">DECLINE</button>${dispatchBoardData.canSendGovernmentDoctor && !government && !responders && !priorityRequest ? `<button class="dispatch-board__government" data-dispatch-government="${esc(call.id)}">SEND GOV DOC</button>` : ''}`}${priorityRequest && (mine || dispatchBoardData.canManage || String(call.callerCharacterId) === String(dispatchBoardData.selfCharacterId)) ? `<button class="dispatch-board__secondary dispatch-board__secondary--danger" data-dispatch-clear-priority="${esc(call.id)}">CLEAR ALERT</button>` : ''}</div>
      ${dispatchBoardData.canManage ? `<button class="dispatch-board__remove" data-dispatch-remove="${esc(call.id)}" title="Remove call" aria-label="Remove call">×</button>` : '<span></span>'}
      <div class="dispatch-board__tools">${notes ? `<span class="dispatch-board__notes">${esc(notes)}</span>` : ''}<button class="dispatch-board__secondary" data-dispatch-route="${esc(call.id)}">SET GPS</button>${mine || dispatchBoardData.canManage ? `<button class="dispatch-board__secondary" data-dispatch-note="${esc(call.id)}">ADD NOTE</button>` : ''}${dispatchBoardData.canManage && units ? `<select class="dispatch-board__status-select" data-dispatch-unit="${esc(call.id)}"><option value="">Select EMS unit</option>${units}</select><button class="dispatch-board__secondary" data-dispatch-assign="${esc(call.id)}">ASSIGN UNIT</button>${responders ? `<button class="dispatch-board__secondary dispatch-board__secondary--danger" data-dispatch-replace="${esc(call.id)}">REPLACE CREW</button>` : ''}` : ''}</div>
    </article>`;
  }).join('') || '<div class="dispatch-board__empty">No emergency calls in this view.</div>';
}

document.querySelectorAll('[data-dispatch-filter]').forEach((button) => {
  button.onclick = () => { dispatchFilter = button.dataset.dispatchFilter; renderDispatchBoard(); };
});
document.getElementById('dispatchClose').onclick = () => post('dispatchClose');
document.getElementById('dispatchRefresh').onclick = () => post('dispatchRefresh');
dispatchBoardRows.onclick = (event) => {
  const take = event.target.closest('[data-dispatch-take]');
  const remove = event.target.closest('[data-dispatch-remove]');
  const government = event.target.closest('[data-dispatch-government]');
  const reject = event.target.closest('[data-dispatch-reject]');
  const backup = event.target.closest('[data-dispatch-backup]');
  const acknowledge = event.target.closest('[data-dispatch-ack]');
  const clearPriority = event.target.closest('[data-dispatch-clear-priority]');
  const route = event.target.closest('[data-dispatch-route]');
  const note = event.target.closest('[data-dispatch-note]');
  const assign = event.target.closest('[data-dispatch-assign]');
  const replace = event.target.closest('[data-dispatch-replace]');
  if (take && !take.disabled) post('dispatchTake', { callId: Number(take.dataset.dispatchTake) });
  if (remove && window.confirm('Remove this call from dispatch? This cannot be undone.')) post('dispatchRemove', { callId: Number(remove.dataset.dispatchRemove) });
  if (government) post('dispatchGovernmentDoctor', { callId: Number(government.dataset.dispatchGovernment) });
  if (reject) post('dispatchReject', { callId: Number(reject.dataset.dispatchReject) });
  if (backup) post('dispatchBackup', { callId: Number(backup.dataset.dispatchBackup) });
  if (acknowledge) post('dispatchAcknowledgePriority', { callId: Number(acknowledge.dataset.dispatchAck) });
  if (clearPriority && window.confirm('Clear this priority backup alert? Other responders will no longer see it.')) post('dispatchClearPriority', { callId: Number(clearPriority.dataset.dispatchClearPriority) });
  if (route) post('dispatchRoute', { callId: Number(route.dataset.dispatchRoute) });
  if (note) {
    const value = window.prompt('Incident note (maximum 120 characters):', '');
    if (value?.trim()) post('dispatchNote', { callId: Number(note.dataset.dispatchNote), note: value.trim() });
  }
  if (assign || replace) {
    const button = assign || replace;
    const callId = Number(assign ? button.dataset.dispatchAssign : button.dataset.dispatchReplace);
    const select = dispatchBoardRows.querySelector(`[data-dispatch-unit="${callId}"]`);
    if (select?.value && (!replace || window.confirm('Replace the unit(s) currently assigned to this call?'))) {
      post('dispatchAssignUnit', { callId, characterId: select.value, replace: Boolean(replace) });
    }
  }
};
dispatchBoardRows.onchange = (event) => { const select = event.target.closest('[data-dispatch-status]'); if (select?.value) post('dispatchStatus', { callId: Number(select.dataset.dispatchStatus), status: select.value }); };

window.addEventListener('message', (event) => {
  const message = event.data || {};
  if (message.action === 'dispatch:openMenu' || message.action === 'dispatch:updateMenu') {
    dispatchBoardData = message.board || dispatchBoardData;
    dispatchBoard.hidden = false;
    renderDispatchBoard();
  } else if (message.action === 'dispatch:closeMenu') {
    dispatchBoard.hidden = true;
  }
});
window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !dispatchBoard.hidden) post('dispatchClose');
});
