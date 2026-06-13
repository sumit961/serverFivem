const root = document.getElementById('parking');
const lotTitle = document.getElementById('lot-title');
const listLeft = document.getElementById('list-left');
const listRight = document.getElementById('list-right');
const toastEl = document.getElementById('toast');
const pageLabel = document.getElementById('page-label');
const prevBtn = document.getElementById('prev-page');
const nextBtn = document.getElementById('next-page');
const statOwned = document.getElementById('stat-owned');
const statParked = document.getElementById('stat-parked');
const statOut = document.getElementById('stat-out');
const selectedName = document.getElementById('selected-name');
const selectedStatus = document.getElementById('selected-status');
const selectedId = document.getElementById('selected-id');
const selectedTrunk = document.getElementById('selected-trunk');
const selectedFuel = document.getElementById('selected-fuel');
const selectedAction = document.getElementById('selected-action');

let state = { lotId: null, lotLabel: 'Parking', vehicles: [], allowRetrieveFromAnyParking: false };
let page = 0;
let selectedIdValue = null;
const pageSize = 10;

function resourceUrl(path) { return `https://${GetParentResourceName()}/${path}`; }
function post(path, body) { return fetch(resourceUrl(path), { method:'POST', headers:{'Content-Type':'application/json; charset=UTF-8'}, body: JSON.stringify(body || {}) }); }
function showToast(msg) { toastEl.textContent = msg || ''; toastEl.classList.remove('hidden'); clearTimeout(showToast.t); showToast.t = setTimeout(() => toastEl.classList.add('hidden'), 2600); }
function statusText(v) { return v?.is_stored ? `PARKED • ${v.parking_label || v.parking_id || 'PARKING'}` : 'OUT • CALL AVAILABLE'; }
function canRetrieve(v) { if (!v) return false; if (!v.is_stored) return true; if (state.allowRetrieveFromAnyParking) return true; return String(v.parking_id || '') === String(state.lotId || ''); }
function vehicleName(v) { return String(v?.label || v?.model || 'Vehicle').toUpperCase(); }
function currentSelected() { return (state.vehicles || []).find(v => String(v.id) === String(selectedIdValue)) || null; }

function selectVehicle(id) { selectedIdValue = id; render(); }
function renderStats() {
  const vehicles = state.vehicles || [];
  statOwned.textContent = vehicles.length;
  statParked.textContent = vehicles.filter(v => v.is_stored).length;
  statOut.textContent = vehicles.filter(v => !v.is_stored).length;
}
function renderSelected() {
  const v = currentSelected();
  if (!v) {
    selectedName.textContent = 'NO VEHICLE SELECTED';
    selectedStatus.textContent = 'Choose a vehicle from the parking list.';
    selectedId.textContent = '-'; selectedTrunk.textContent = '-'; selectedFuel.textContent = '-';
    selectedAction.textContent = 'SELECT VEHICLE'; selectedAction.className = 'main-action disabled';
    return;
  }
  selectedName.textContent = vehicleName(v);
  selectedStatus.textContent = statusText(v);
  selectedId.textContent = v.id ?? '-';
  selectedTrunk.textContent = `LVL ${v.trunk_level || 0}`;
  selectedFuel.textContent = `${Math.floor(Number(v.fuel || 0))}%`;
  const allowed = canRetrieve(v);
  selectedAction.textContent = v.is_stored ? 'TAKE OUT VEHICLE' : 'CALL VEHICLE';
  selectedAction.className = `main-action ${allowed ? '' : 'disabled'}`;
  selectedAction.onclick = () => {
    if (!allowed) { showToast(`Vehicle is parked at ${v.parking_label || v.parking_id}`); return; }
    post('retrieve', { vehicleId: v.id, plate: v.plate });
  };
}
function renderLists() {
  const vehicles = state.vehicles || [];
  const pages = Math.max(1, Math.ceil(vehicles.length / pageSize));
  if (page >= pages) page = pages - 1;
  if (page < 0) page = 0;
  pageLabel.textContent = `PAGE ${page + 1} / ${pages}`;
  prevBtn.classList.toggle('disabled', page <= 0);
  nextBtn.classList.toggle('disabled', page >= pages - 1);
  listLeft.innerHTML = ''; listRight.innerHTML = '';
  if (!vehicles.length) { listLeft.innerHTML = '<div class="empty">No owned vehicles</div>'; return; }
  const chunk = vehicles.slice(page * pageSize, page * pageSize + pageSize);
  chunk.forEach((v, idx) => {
    const el = document.createElement('div');
    el.className = `vehicle-card ${v.is_stored ? 'parked' : 'out'} ${String(v.id) === String(selectedIdValue) ? 'selected' : ''}`;
    el.innerHTML = `<span>${vehicleName(v)}</span><small>#${v.id}<br>${v.is_stored ? 'PARKED' : 'OUT'}</small>`;
    el.onclick = () => selectVehicle(v.id);
    (idx < 5 ? listLeft : listRight).appendChild(el);
  });
}
function render() {
  lotTitle.textContent = String(state.lotLabel || 'Parking').toUpperCase();
  renderStats(); renderLists(); renderSelected();
}
function applyPayload(payload) {
  state = Object.assign(state, payload || {});
  state.vehicles = Array.isArray(state.vehicles) ? state.vehicles : [];
  if (selectedIdValue && !currentSelected()) selectedIdValue = null;
  if (!selectedIdValue && state.vehicles.length) selectedIdValue = state.vehicles[0].id;
  render();
}
window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') { root.classList.remove('hidden'); page = 0; applyPayload(data); }
  if (data.action === 'update') applyPayload(data);
  if (data.action === 'close') root.classList.add('hidden');
  if (data.action === 'toast') showToast(data.message);
});
document.getElementById('close').onclick = () => post('close', {});
document.getElementById('park-current').onclick = () => post('parkCurrent', {});
document.getElementById('refresh').onclick = () => post('refresh', {});
prevBtn.onclick = () => { page--; render(); };
nextBtn.onclick = () => { page++; render(); };
document.addEventListener('keydown', e => { if (e.key === 'Escape') post('close', {}); });
