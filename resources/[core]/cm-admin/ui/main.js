const app = document.getElementById('app');
const nav = document.getElementById('nav');
const page = document.getElementById('page');
const pageTitle = document.getElementById('pageTitle');
const pageKicker = document.getElementById('pageKicker');
const serverName = document.getElementById('serverName');
const adminName = document.getElementById('adminName');
const adminRank = document.getElementById('adminRank');

const state = {
  open: false,
  tab: 'dashboard',
  selectedPlayer: null,
  data: { me: {}, players: [], admins: [], ranks: [], logs: [], logCategories: [], permissions: [], server: {} },
  offline: { query: '', results: [] },
  map: { players: [], vehicles: [], showVehicles: true, showAdmins: true, cam: { x: 0, y: -800, zoom: 0.34 }, timer: null, drag: null, moved: false, cursor: null, resizeBound: false, selected: null, calibrating: false, calibration: null },
  rankEditor: { name: '', label: '', level: 20, permissions: [] },
  logFilter: 'all',
  detail: null,
};

function resourceName() {
  try { return GetParentResourceName(); } catch (e) { return 'cm-admin'; }
}

function post(name, payload) {
  return fetch(`https://${resourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload || {})
  }).catch(() => null);
}

function action(actionName, data) {
  return post('adminAction', { action: actionName, data: data || {} });
}
function sendAction(actionName, data) { return action(actionName, data); }

function closeUi() { post('close', {}); }

document.getElementById('closeBtn').addEventListener('click', closeUi);
document.getElementById('refreshBtn').addEventListener('click', () => action('refresh'));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeUi(); });

function esc(value) {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function hasPerm(permission) {
  const perms = (state.data.me && state.data.me.permissions) || [];
  return perms.includes('*') || perms.includes(permission);
}

function rankOptions(selected) {
  return (state.data.ranks || []).map(r => `<option value="${esc(r.name)}" ${r.name === selected ? 'selected' : ''}>${esc(r.label)} (${esc(r.name)})</option>`).join('');
}

const tabs = [
  { id: 'dashboard', label: 'Dashboard', hint: 'Overview', perm: null },
  { id: 'players', label: 'Players', hint: 'Online', perm: 'players.view' },
  { id: 'offline', label: 'Offline', hint: 'Search DB', perm: 'players.view' },
  { id: 'map', label: 'Map', hint: 'Live', perm: 'players.view' },
  { id: 'developer', label: 'Developer', hint: 'Tools', perm: 'dev.view' },
  { id: 'inventory', label: 'Inventory', hint: 'Items', perm: 'inventory.view' },
  { id: 'vehicles', label: 'Vehicles', hint: 'Cars', perm: 'vehicles.view' },
  { id: 'admins', label: 'Admins', hint: 'Staff', perm: 'admins.view' },
  { id: 'ranks', label: 'Ranks', hint: 'Perms', perm: 'ranks.view' },
  { id: 'logs', label: 'Logs', hint: 'Audit', perm: 'logs.view' },
];

function renderNav() {
  nav.innerHTML = tabs
    .filter(t => !t.perm || hasPerm(t.perm))
    .map(t => `<button class="${state.tab === t.id ? 'active' : ''}" onclick="cmSetTab('${t.id}')"><b>${t.label}</b><span>${t.hint}</span></button>`)
    .join('');
}

window.cmSetTab = function(tab) {
  state.tab = tab;
  state.detail = null;
  render();
};

function selectedPlayer() {
  const players = state.data.players || [];
  return players.find(p => Number(p.id) === Number(state.selectedPlayer)) || players[0] || null;
}

window.cmSelectPlayer = function(id) {
  state.selectedPlayer = Number(id);
  state.detail = null;
  render();
};

function formatCoords(p) {
  if (!p || !p.coords) return '-';
  return `${p.coords.x}, ${p.coords.y}, ${p.coords.z}`;
}

function money(value) {
  if (value === null || value === undefined || value === '') return '-';
  const n = Number(value);
  if (!Number.isFinite(n)) return '-';
  return '$' + n.toLocaleString();
}

function dashboard() {
  const players = state.data.players || [];
  const admins = state.data.admins || [];
  const ranks = state.data.ranks || [];
  const logs = state.data.logs || [];
  return `
    <div class="grid cols-4">
      <div class="card stat"><small>Online players</small><strong>${players.length}</strong><span>Live server</span></div>
      <div class="card stat"><small>Admins online</small><strong>${players.filter(p => p.adminMode).length}</strong><span>/admin mode</span></div>
      <div class="card stat"><small>Ranks</small><strong>${ranks.length}</strong><span>Permission groups</span></div>
      <div class="card stat"><small>Recent logs</small><strong>${logs.length}</strong><span>Audit trail</span></div>
    </div>
    <div class="grid cols-3" style="margin-top:16px">
      <div class="card">
        <h3>How this works</h3>
        <div class="detail-grid">
          <div class="kv"><small>Join game</small><strong>Normal player</strong></div>
          <div class="kv"><small>Enable admin</small><strong>/admin</strong></div>
          <div class="kv"><small>Open menu</small><strong>F11</strong></div>
          <div class="kv"><small>Noclip</small><strong>F2 / noclip</strong></div>
        </div>
      </div>
      <div class="card">
        <h3>Your admin profile</h3>
        <div class="detail-grid">
          <div class="kv"><small>Name</small><strong>${esc(state.data.me.name)}</strong></div>
          <div class="kv"><small>Rank</small><strong>${esc(state.data.me.rankLabel || state.data.me.rank)}</strong></div>
          <div class="kv"><small>Level</small><strong>${esc(state.data.me.level)}</strong></div>
          <div class="kv"><small>Character ID</small><strong>${esc(state.data.me.characterId || '-')}</strong></div><div class="kv"><small>Admin Key</small><strong>${esc(state.data.me.identifier)}</strong></div>
        </div>
      </div>
      <div class="card">
        <h3>Quick Tools</h3>
        <div class="actions vertical">
          ${(hasPerm('gps.teleport') || hasPerm('teleport') || hasPerm('players.teleport')) ? `<button class="btn primary" onclick="action('gpsTeleport')">GPS Teleport</button>` : ''}
          ${hasPerm('map.view') || hasPerm('players.view') ? `<button class="btn" onclick="cmSetTab('map')">Open Live Map</button>` : ''}
          ${hasPerm('dev.view') ? `<button class="btn" onclick="cmSetTab('developer')">Open Developer Launchers</button>` : ''}
        </div>
      </div>
    </div>`;
}

function playersPage() {
  const players = state.data.players || [];
  const selected = selectedPlayer();
  if (selected && !state.selectedPlayer) state.selectedPlayer = selected.id;

  const distLabel = (p) => {
    if (p.isSelf) return 'YOU';
    if (p.distance === undefined || p.distance === null) return '';
    if (p.distance < 50) return `NEARBY · ${p.distance}m`;
    if (p.distance < 1000) return `${p.distance}m`;
    return `${(p.distance / 1000).toFixed(1)}km`;
  };

  const list = players.map(p => `
    <button class="item ${selected && Number(selected.id) === Number(p.id) ? 'active' : ''}" onclick="cmSelectPlayer(${Number(p.id)})">
      <div class="avatar">${esc(p.characterId || '?')}</div>
      <div><strong>${esc(p.name)}</strong><small>Char ${esc(p.characterId || '-')} · Ping ${esc(p.ping)}${p.cash !== undefined && p.cash !== null ? ` · $${Number(p.cash).toLocaleString()} / $${Number(p.bank || 0).toLocaleString()}` : ''}${distLabel(p) ? ' · ' + distLabel(p) : ''}</small></div>
      <span class="badge ${p.distance !== undefined && p.distance < 50 && !p.isSelf ? 'near' : (p.adminMode ? '' : 'off')}">${p.isSelf ? 'You' : (p.distance !== undefined && p.distance < 50 ? 'Nearby' : (p.adminMode ? 'Admin' : 'Player'))}</span>
    </button>`).join('');

  return `
    <div class="player-list">
      <div class="card">
        <h3>Online Players</h3>
        <div class="list">${list || '<div class="empty">No players online</div>'}</div>
      </div>
      <div>${selected ? playerDetail(selected) : '<div class="empty">Select a player</div>'}</div>
    </div>`;
}

function playerDetail(p) {
  return `
    <div class="card">
      <h3>${esc(p.name)} <span class="badge">Char ${esc(p.characterId || '-')}</span></h3>
      <div class="detail-grid">
        <div class="kv"><small>Character ID</small><strong>${esc(p.characterId || '-')}</strong></div>
        <div class="kv"><small>Character name</small><strong>${esc(p.characterName || '-')}</strong></div>
        <div class="kv"><small>Session source</small><strong>${esc(p.id || '-')}</strong></div>
        <div class="kv"><small>Identifier</small><strong>${esc(p.identifier || '-')}</strong></div>
        <div class="kv"><small>Cash / Bank</small><strong>${esc(money(p.cash))} / ${esc(money(p.bank))}</strong></div>
        <div class="kv"><small>Coords</small><strong>${esc(formatCoords(p))}</strong></div>
      </div>
      <div class="actions">
        ${hasPerm('players.teleport') ? `<button class="btn small primary" onclick="cmPlayerAction(${p.id}, 'goto')">Go To</button><button class="btn small primary" onclick="cmPlayerAction(${p.id}, 'bring')">Bring</button>` : ''}
        ${hasPerm('players.freeze') ? `<button class="btn small" onclick="cmPlayerAction(${p.id}, 'freeze')">Freeze</button><button class="btn small" onclick="cmPlayerAction(${p.id}, 'unfreeze')">Unfreeze</button>` : ''}
        ${hasPerm('tools.heal') ? `<button class="btn small success" onclick="cmPlayerAction(${p.id}, 'heal')">Heal</button><button class="btn small success" onclick="cmPlayerAction(${p.id}, 'armor')">Armor</button>` : ''}
        ${(hasPerm('money.manage') || hasPerm('players.manage')) ? `<button class="btn small success" onclick="cmGiveCash(${p.id})">Give Cash</button>` : ''}
        ${hasPerm('inventory.view') ? `<button class="btn small" onclick="cmViewInventory(${p.id})">View Inventory</button>` : ''}
        ${hasPerm('vehicles.view') ? `<button class="btn small" onclick="cmViewVehicles(${p.id})">View Cars</button>` : ''}
        ${hasPerm('vehicles.manage') ? `<button class="btn small" onclick="cmPlayerAction(${p.id}, 'repair_vehicle')">Repair Vehicle</button><button class="btn small danger" onclick="cmPlayerAction(${p.id}, 'delete_vehicle')">Delete Vehicle</button>` : ''}
        ${hasPerm('players.kick') ? `<button class="btn small danger" onclick="cmKick(${p.id})">Kick</button>` : ''}
      </div>
    </div>
    ${detailBlock()}`;
}

window.cmPlayerAction = function(target, playerAction) {
  action('playerAction', { target, playerAction });
};

window.cmGiveCash = function(target) {
  const raw = prompt('Cash amount to give?', '1000');
  if (raw === null) return;
  const amount = Math.floor(Number(String(raw).replace(/[^0-9.]/g, '')));
  if (!Number.isFinite(amount) || amount < 1) {
    alert('Enter a valid cash amount.');
    return;
  }
  const reason = prompt('Reason for audit log?', 'Admin cash grant');
  if (reason === null) return;
  action('playerAction', { target, playerAction: 'give_cash', amount, reason });
};

window.cmKick = function(target) {
  const reason = prompt('Kick reason?', 'Kicked by admin');
  if (reason === null) return;
  action('playerAction', { target, playerAction: 'kick', reason });
};

window.cmViewInventory = function(target) {
  state.tab = 'inventory';
  state.selectedPlayer = Number(target);
  state.detail = null;
  render();
  action('viewInventory', { target });
};

window.cmViewVehicles = function(target) {
  state.tab = 'vehicles';
  state.selectedPlayer = Number(target);
  state.detail = null;
  render();
  action('viewVehicles', { target });
};

function inventoryPage() {
  const p = selectedPlayer();
  return `
    <div class="grid cols-2">
      <div class="card">
        <h3>Player Inventory</h3>
        ${p ? `<p class="mini-label">Selected player</p><div class="kv"><small>${esc(p.name)}</small><strong>ID ${esc(p.id)} · Char ${esc(p.characterId || '-')}</strong></div><br><button class="btn primary" onclick="cmViewInventory(${p.id})">Load Inventory</button>` : '<div class="empty">Select a player from Players tab first</div>'}
      </div>
      <div class="card">
        <h3>Bridge Info</h3>
        <p class="mini-label">The script safely tries your configured CM inventory SQL tables. Missing tables do not crash the server.</p>
      </div>
    </div>
    ${detailBlock()}`;
}

function vehiclesPage() {
  const p = selectedPlayer();
  return `
    <div class="grid cols-2">
      <div class="card">
        <h3>Player Cars</h3>
        ${p ? `<div class="kv"><small>${esc(p.name)}</small><strong>ID ${esc(p.id)} · Char ${esc(p.characterId || '-')}</strong></div><br><button class="btn primary" onclick="cmViewVehicles(${p.id})">Load Player Cars</button>` : '<div class="empty">Select a player from Players tab first</div>'}
      </div>
      <div class="card">
        <h3>Car Inventory</h3>
        <div class="form">
          <div class="field"><label>Plate</label><input id="plateInput" class="input" placeholder="ABC123" /></div>
          <button class="btn primary" onclick="cmViewVehicleInventory()">Load Trunk / Vehicle Inventory</button>
        </div>
      </div>
    </div>
    ${detailBlock()}`;
}

window.cmViewVehicleInventory = function() {
  const plate = document.getElementById('plateInput').value;
  action('viewVehicleInventory', { plate });
};

function adminsPage() {
  const admins = state.data.admins || [];
  return `
    <div class="grid cols-2">
      <div class="card">
        <h3>Add / Update Admin</h3>
        <div class="form">
          <div class="field full"><label>Character ID</label><input id="newAdminCharacterId" class="input" placeholder="Example: 12" /></div>
          <div class="field"><label>Name</label><input id="newAdminName" class="input" placeholder="Admin name" /></div>
          <div class="field"><label>Rank</label><select id="newAdminRank" class="select">${rankOptions('moderator')}</select></div>
          <button class="btn primary" onclick="cmAddAdmin()">Save Admin</button>
        </div>
      </div>
      <div class="card">
        <h3>Important</h3>
        <p class="mini-label">Admin access is saved by character ID only. Same account can have another character with no admin power. Staff still type /admin every session, then F11 opens this menu.</p>
      </div>
    </div>
    <div class="card" style="margin-top:16px">
      <h3>Saved Admins</h3>
      <div class="table-wrap">
        <table><thead><tr><th>Name</th><th>Character ID</th><th>Admin Key</th><th>Rank</th><th>Status</th><th>Actions</th></tr></thead><tbody>
          ${admins.map(a => `<tr>
            <td>${esc(a.name || '-')}</td>
            <td>${esc(a.characterId || '-')}</td>
            <td>${esc(a.identifier)}</td>
            <td><select class="select" style="min-height:34px" onchange="cmSetAdminRank('${esc(a.identifier)}', this.value)">${rankOptions(a.rank)}</select></td>
            <td><span class="badge ${a.active ? '' : 'off'}">${a.active ? 'Active' : 'Disabled'}</span></td>
            <td><button class="btn small danger" onclick="cmRemoveAdmin('${esc(a.identifier)}')">Disable</button></td>
          </tr>`).join('')}
        </tbody></table>
      </div>
    </div>`;
}

window.cmAddAdmin = function() {
  action('addAdmin', {
    characterId: document.getElementById('newAdminCharacterId').value,
    name: document.getElementById('newAdminName').value,
    rank: document.getElementById('newAdminRank').value
  });
};
window.cmRemoveAdmin = function(identifier) { if (confirm('Disable this admin?')) action('removeAdmin', { identifier }); };
window.cmSetAdminRank = function(identifier, rank) { action('setAdminRank', { identifier, rank }); };

function permissionLabel(permission) {
  return String(permission || '').replace(/\./g, ' / ');
}

function ensureRankEditor() {
  if (!state.rankEditor) state.rankEditor = { name: '', label: '', level: 20, permissions: [] };
  if (!state.rankEditor.name) {
    const first = (state.data.ranks || [])[0];
    if (first) {
      state.rankEditor = {
        name: first.name,
        label: first.label,
        level: Number(first.level || 0),
        permissions: Array.from(new Set(first.permissions || []))
      };
    }
  }
}

function ranksPage() {
  ensureRankEditor();
  const ranks = state.data.ranks || [];
  const allPerms = ['*'].concat(state.data.permissions || []);
  const assigned = Array.from(new Set(state.rankEditor.permissions || []));
  const available = allPerms.filter(p => !assigned.includes(p));

  const assignedHtml = assigned.map(p => `
    <button class="perm-pill assigned" draggable="true" ondragstart="cmDragPerm(event, '${esc(p)}')">
      <span>${esc(permissionLabel(p))}</span><b onclick="event.stopPropagation(); cmRemovePerm('${esc(p)}')">×</b>
    </button>`).join('');

  const availableHtml = available.map(p => `
    <button class="perm-pill" draggable="true" ondragstart="cmDragPerm(event, '${esc(p)}')" onclick="cmAddPerm('${esc(p)}')">
      ${esc(permissionLabel(p))}
    </button>`).join('');

  return `
    <div class="rank-layout">
      <div class="card rank-editor">
        <h3>Rank Permission Builder</h3>
        <div class="form">
          <div class="field"><label>Rank Name</label><input id="rankName" class="input" placeholder="senioradmin" value="${esc(state.rankEditor.name)}" /></div>
          <div class="field"><label>Label</label><input id="rankLabel" class="input" placeholder="Senior Admin" value="${esc(state.rankEditor.label)}" /></div>
          <div class="field"><label>Level</label><input id="rankLevel" class="input" type="number" value="${esc(state.rankEditor.level)}" /></div>
          <div class="actions"><button class="btn primary" onclick="cmSaveRank()">Save Rank</button><button class="btn danger" onclick="cmDeleteRank()">Delete Rank</button></div>
        </div>
        <div class="permission-builder">
          <div class="perm-box" ondragover="event.preventDefault()" ondrop="cmDropPerm(event, true)">
            <div class="perm-box-head"><strong>Assigned permissions</strong><small>Drag here to add · press × to remove</small></div>
            <div class="perm-list assigned-list">${assignedHtml || '<span class="empty-inline">No permissions assigned</span>'}</div>
          </div>
          <div class="perm-box" ondragover="event.preventDefault()" ondrop="cmDropPerm(event, false)">
            <div class="perm-box-head"><strong>Available permissions</strong><small>Click or drag into assigned</small></div>
            <div class="perm-list">${availableHtml || '<span class="empty-inline">All permissions assigned</span>'}</div>
          </div>
        </div>
      </div>
      <div class="card rank-list-card">
        <h3>Ranks</h3>
        <div class="rank-list">
          ${ranks.map(r => `<button class="rank-row ${state.rankEditor.name === r.name ? 'active' : ''}" onclick="cmLoadRank('${esc(r.name)}')">
            <strong>${esc(r.label)}</strong><small>${esc(r.name)} · Level ${esc(r.level)} · ${(r.permissions || []).length} permissions</small>
          </button>`).join('')}
        </div>
      </div>
    </div>`;
}

window.cmLoadRank = function(name) {
  const r = (state.data.ranks || []).find(x => x.name === name);
  if (!r) return;
  state.rankEditor = {
    name: r.name,
    label: r.label,
    level: Number(r.level || 0),
    permissions: Array.from(new Set(r.permissions || []))
  };
  render();
};

window.cmDragPerm = function(event, permission) {
  event.dataTransfer.setData('text/plain', permission);
  event.dataTransfer.effectAllowed = 'move';
};

window.cmDropPerm = function(event, assign) {
  event.preventDefault();
  const permission = event.dataTransfer.getData('text/plain');
  if (!permission) return;
  if (assign) cmAddPerm(permission);
  else cmRemovePerm(permission);
};

window.cmAddPerm = function(permission) {
  permission = String(permission || '');
  if (!permission) return;
  const set = new Set(state.rankEditor.permissions || []);
  set.add(permission);
  state.rankEditor.permissions = Array.from(set);
  render();
};

window.cmRemovePerm = function(permission) {
  state.rankEditor.permissions = (state.rankEditor.permissions || []).filter(p => p !== permission);
  render();
};

window.cmSaveRank = function() {
  const nameEl = document.getElementById('rankName');
  const labelEl = document.getElementById('rankLabel');
  const levelEl = document.getElementById('rankLevel');
  state.rankEditor.name = nameEl ? nameEl.value : state.rankEditor.name;
  state.rankEditor.label = labelEl ? labelEl.value : state.rankEditor.label;
  state.rankEditor.level = Number(levelEl ? levelEl.value : state.rankEditor.level || 0);
  action('saveRank', {
    name: state.rankEditor.name,
    label: state.rankEditor.label,
    level: state.rankEditor.level,
    permissions: Array.from(new Set(state.rankEditor.permissions || []))
  });
};

window.cmDeleteRank = function() {
  const nameEl = document.getElementById('rankName');
  const name = nameEl ? nameEl.value : state.rankEditor.name;
  if (!name) return;
  if (confirm(`Delete rank ${name}?`)) action('deleteRank', { name });
};

function logsPage() {
  const rawLogs = state.detail && state.detail.type === 'logs' ? state.detail.data.logs : (state.data.logs || []);
  const categories = (state.detail && state.detail.data && state.detail.data.categories) || state.data.logCategories || [];
  const logs = state.logFilter === 'all' ? rawLogs : rawLogs.filter(l => (l.category || 'system') === state.logFilter);
  const catButtons = [{ id: 'all', label: 'All' }].concat(categories).map(c =>
    `<button class="btn small ${state.logFilter === c.id ? 'primary' : ''}" onclick="cmLogFilter('${esc(c.id)}')">${esc(c.label || c.id)}</button>`
  ).join('');
  return `
    <div class="card">
      <div class="actions" style="justify-content:space-between; margin-bottom:12px">
        <h3 style="margin:0">Role-Based Audit Logs</h3>
        <button class="btn primary" onclick="action('viewLogs')">Load More</button>
      </div>
      <div class="actions log-filters">${catButtons}</div>
      <div class="table-wrap">
        <table><thead><tr><th>ID</th><th>Category</th><th>Admin</th><th>Action</th><th>Target</th><th>Details</th><th>Time</th></tr></thead><tbody>
          ${logs.map(l => `<tr><td>${esc(l.id)}</td><td><span class="badge">${esc(l.category || 'system')}</span></td><td>${esc(l.adminName || l.identifier || '-')}<br><small>${esc(l.source || '')}</small></td><td><span class="badge">${esc(l.action)}</span></td><td>${esc(l.targetName || '-')}<br><small>${esc(l.targetIdentifier || '')}</small></td><td><div class="json">${esc(JSON.stringify(l.details || {}, null, 2))}</div></td><td>${esc(l.createdAt || '-')}</td></tr>`).join('') || '<tr><td colspan="7" class="empty-cell">No logs available for your role/filter.</td></tr>'}
        </tbody></table>
      </div>
    </div>`;
}

window.cmLogFilter = function(category) {
  state.logFilter = category || 'all';
  render();
};

function tableFromRows(rows) {
  rows = rows || [];
  if (!rows.length) return '<div class="empty">No rows found from this bridge query.</div>';
  const keys = Array.from(rows.reduce((set, row) => { Object.keys(row || {}).slice(0, 12).forEach(k => set.add(k)); return set; }, new Set()));
  return `<div class="table-wrap"><table><thead><tr>${keys.map(k => `<th>${esc(k)}</th>`).join('')}<th>Raw</th></tr></thead><tbody>
    ${rows.map(row => `<tr>${keys.map(k => `<td>${esc(shortValue(row[k]))}</td>`).join('')}<td><div class="json">${esc(JSON.stringify(row, null, 2))}</div></td></tr>`).join('')}
  </tbody></table></div>`;
}

function shortValue(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'object') return JSON.stringify(v).slice(0, 120);
  const s = String(v);
  return s.length > 120 ? s.slice(0, 120) + '…' : s;
}

function detailBlock() {
  if (!state.detail) return '';
  const d = state.detail.data || {};
  if (state.detail.type === 'inventory') {
    return `<div class="card" style="margin-top:16px"><h3>Inventory Result</h3>${bridgeHeader(d.result)}${tableFromRows(d.result && d.result.rows)}</div>`;
  }
  if (state.detail.type === 'vehicles') {
    return `<div class="card" style="margin-top:16px"><h3>Vehicle Result</h3>${bridgeHeader(d.result)}${tableFromRows(d.result && d.result.rows)}</div>`;
  }
  if (state.detail.type === 'vehicleInventory') {
    return `<div class="card" style="margin-top:16px"><h3>Vehicle Inventory: ${esc(d.plate)}</h3>${bridgeHeader(d.result)}${tableFromRows(d.result && d.result.rows)}</div>`;
  }
  return '';
}

function bridgeHeader(result) {
  result = result || {};
  return `<div class="detail-grid">
    <div class="kv"><small>Source</small><strong>${esc(result.source || 'No matching table')}</strong></div>
    <div class="kv"><small>Rows</small><strong>${esc((result.rows || []).length)}</strong></div>
  </div>`;
}

function render() {
  const data = state.data;
  serverName.textContent = data.server && data.server.name ? data.server.name : 'CM Server';
  adminName.textContent = data.me && data.me.name ? data.me.name : '-';
  adminRank.textContent = data.me ? `${data.me.rankLabel || data.me.rank || '-'} · Level ${data.me.level || 0}` : '-';

  renderNav();
  const current = tabs.find(t => t.id === state.tab) || tabs[0];
  pageTitle.textContent = current.label;
  pageKicker.textContent = current.hint;

  if (state.tab === 'dashboard') page.innerHTML = dashboard();
  else if (state.tab === 'players') page.innerHTML = playersPage();
  else if (state.tab === 'inventory') page.innerHTML = inventoryPage();
  else if (state.tab === 'vehicles') page.innerHTML = vehiclesPage();
  else if (state.tab === 'admins') page.innerHTML = adminsPage();
  else if (state.tab === 'ranks') page.innerHTML = ranksPage();
  else if (state.tab === 'offline') page.innerHTML = offlinePage();
  else if (state.tab === 'map') { page.innerHTML = mapPage(); setTimeout(initMap, 0); }
  else if (state.tab === 'developer') page.innerHTML = developerPage();
  else if (state.tab === 'logs') page.innerHTML = logsPage();
  else page.innerHTML = '<div class="empty">Page not found</div>';
}

window.addEventListener('message', (event) => {
  const msg = event.data || {};
  if (msg.action === 'open') {
    state.open = true;
    state.data = msg.data || state.data;
    state.detail = null;
    app.classList.remove('hidden');
    render();
  }
  if (msg.action === 'update') {
    state.data = msg.data || state.data;
    render();
  }
  if (msg.action === 'mapData') {
    state.map.players = (msg.data && msg.data.players) || [];
    state.map.vehicles = (msg.data && msg.data.vehicles) || [];
    if (state.tab === 'map') scheduleMapDraw();
    return;
  }
  if (msg.action === 'detailResult') {
    state.detail = msg.data || null;
    if (state.detail && state.detail.type === 'offlineSearch') {
      state.offline.results = (state.detail.data && state.detail.data.results) || [];
      state.detail = null;
      state.tab = 'offline';
      render();
      return;
    }
    if (state.detail && state.detail.type === 'logs') state.tab = 'logs';
    if (state.detail && state.detail.type === 'inventory') state.tab = 'inventory';
    if (state.detail && (state.detail.type === 'vehicles' || state.detail.type === 'vehicleInventory')) state.tab = 'vehicles';
    render();
  }
  if (msg.action === 'close') {
    state.open = false;
    app.classList.add('hidden');
    stopMapTimer();
  }
});


// ---------------------------------------------------------------------------
// Offline characters
// ---------------------------------------------------------------------------
function offlinePage() {
  const rows = state.offline.results.map(r => `
    <tr>
      <td><strong>${esc(r.name)}</strong><small style="display:block;opacity:.6">${esc(r.dob || '')}</small></td>
      <td>${esc(r.characterId)}</td>
      <td>${r.cash !== undefined && r.cash !== null ? '$' + Number(r.cash).toLocaleString() : '-'}<small style="display:block;opacity:.6">${r.bank !== undefined && r.bank !== null ? 'Bank $' + Number(r.bank).toLocaleString() : ''}</small></td>
      <td class="actions">
        ${hasPerm('inventory.view') ? `<button class="btn small" onclick="cmOffline('offlineInventory', '${esc(r.characterId)}', '')">Inventory</button>` : ''}
        ${hasPerm('vehicles.view') ? `<button class="btn small" onclick="cmOffline('offlineVehicles', '${esc(r.characterId)}', '')">Vehicles</button>` : ''}
      </td>
    </tr>`).join('');

  return `
    <div class="card">
      <h3>Offline Character Search</h3>
      <div class="row">
        <input id="offlineQuery" placeholder="Character ID or name..." value="${esc(state.offline.query)}" />
        <button class="btn" onclick="cmOfflineSearch()">Search</button>
      </div>
      <table class="table">
        <thead><tr><th>Name</th><th>Char ID</th><th>Money</th><th></th></tr></thead>
        <tbody>${rows || '<tr><td colspan="4" class="empty">Search the characters database. Works while the player is offline.</td></tr>'}</tbody>
      </table>
    </div>`;
}

function cmOfflineSearch() {
  const el = document.getElementById('offlineQuery');
  state.offline.query = el ? el.value : '';
  sendAction('offlineSearch', { query: state.offline.query });
}

function cmOffline(action, characterId, identifier) {
  sendAction(action, { characterId, identifier });
}

// ---------------------------------------------------------------------------
// Live map (calibrated GTA atlas: pan = drag, zoom = wheel, click = select).
// Uses the same stitched 6-tile atlas style as cm-climatime, but with admin
// selection/action panels for players and vehicles.
// ---------------------------------------------------------------------------
const MAP_DEFAULT_BOUNDS = { minX: -4000, maxX: 4500, minY: -4300, maxY: 8000 };
let mapImg = null, mapImgTried = false, mapDrawQueued = false;

function cleanBounds(input) {
  const b = input || {};
  const out = {
    minX: Number(b.minX ?? MAP_DEFAULT_BOUNDS.minX),
    maxX: Number(b.maxX ?? MAP_DEFAULT_BOUNDS.maxX),
    minY: Number(b.minY ?? MAP_DEFAULT_BOUNDS.minY),
    maxY: Number(b.maxY ?? MAP_DEFAULT_BOUNDS.maxY),
  };
  if (!Number.isFinite(out.minX)) out.minX = MAP_DEFAULT_BOUNDS.minX;
  if (!Number.isFinite(out.maxX)) out.maxX = MAP_DEFAULT_BOUNDS.maxX;
  if (!Number.isFinite(out.minY)) out.minY = MAP_DEFAULT_BOUNDS.minY;
  if (!Number.isFinite(out.maxY)) out.maxY = MAP_DEFAULT_BOUNDS.maxY;
  if (out.maxX <= out.minX) out.maxX = out.minX + 1000;
  if (out.maxY <= out.minY) out.maxY = out.minY + 1000;
  return out;
}

function serverMapBounds() {
  return cleanBounds((state.data && state.data.server && state.data.server.mapBounds) || MAP_DEFAULT_BOUNDS);
}

function mapBounds() {
  if (state.map.calibrating && state.map.calibration && state.map.calibration.bounds) {
    return cleanBounds(state.map.calibration.bounds);
  }
  return serverMapBounds();
}

function canCalibrateMap() {
  const srv = (state.data && state.data.server) || {};
  return srv.mapAllowUiSave !== false && (hasPerm('map.calibrate') || hasPerm('ranks.manage') || hasPerm('dev.tools'));
}

function mapPage() {
  return `
    <div class="map-layout">
      <div class="card map-card">
        <div class="zoneMapHeader admin-map-head">
          <div>
            <span class="mapTag">GTA Live Staff Map</span>
            <p class="muted">Calibrated stitched 6-tile GTA atlas. Drag to pan, wheel to zoom, click player/vehicle blips for actions.</p>
          </div>
          <strong id="mapCoordsHint">X 0 Y 0</strong>
        </div>
        <div class="zoneMapToolbar admin-map-toolbar">
          <button class="btn small ghost" type="button" onclick="cmMapZoom(1)">＋ Zoom</button>
          <button class="btn small ghost" type="button" onclick="cmMapZoom(-1)">－ Zoom</button>
          <button class="btn small ghost" type="button" onclick="cmMapFocusSelf()">⌖ Focus Self</button>
          <button class="btn small ghost" type="button" onclick="cmMapClearSelection()">Clear Select</button>
          ${canCalibrateMap() ? `<button class="btn small warn" type="button" onclick="cmMapToggleCalibration()">${state.map.calibrating ? 'Close Calibration' : 'Calibrate Map'}</button>` : ''}
          ${(hasPerm('gps.teleport') || hasPerm('teleport') || hasPerm('players.teleport')) ? `<button class="btn small primary" type="button" onclick="action('gpsTeleport')">GPS TP</button>` : ''}
          <label class="check map-toggle"><input type="checkbox" id="mapVehToggle" ${state.map.showVehicles ? 'checked' : ''} onchange="cmMapVehToggle(this.checked)" /> Vehicles</label>
          <label class="check map-toggle"><input type="checkbox" id="mapAdminToggle" ${state.map.showAdmins ? 'checked' : ''} onchange="cmMapAdminToggle(this.checked)" /> Admins</label>
        </div>
        <div class="admin-map-wrap"><canvas id="mapCanvas"></canvas></div>
        <div class="map-legend"><span class="dot player"></span> Player <span class="dot admin"></span> Logged-in admin <span class="dot self"></span> You <span class="dot vehicle"></span> Vehicle <span class="dot selected"></span> Selected</div>
      </div>
      <div id="mapSelection" class="map-selection">${mapSidePanel()}</div>
    </div>`;
}

function mapSidePanel() {
  return `${mapCalibrationPanel()}${mapSelectionPanel()}`;
}

function mapCalibrationPanel() {
  if (!state.map.calibrating) return '';
  const b = mapBounds();
  const source = esc(((state.data && state.data.server && state.data.server.mapBoundsSource) || 'config'));
  const configText = `Config.Map.Bounds = {\n    minX = ${Math.round(b.minX)},\n    maxX = ${Math.round(b.maxX)},\n    minY = ${Math.round(b.minY)},\n    maxY = ${Math.round(b.maxY)}\n}`;
  return `<div class="card map-side-card map-cal-card">
    <h3>Map Calibration <span class="badge">${source}</span></h3>
    <p class="muted tiny">Tune the atlas once, preview live, then save. Saved values load every restart from <code>data/map_bounds.json</code>.</p>
    <div class="bounds-grid">
      ${['minX','maxX','minY','maxY'].map(k => `<label><span>${k}</span><input id="cal_${k}" type="number" value="${Math.round(b[k])}" onchange="cmMapCalSet('${k}', this.value)" /></label>`).join('')}
    </div>
    <div class="cal-nudge-grid">
      <button class="btn xsmall" onclick="cmMapCalShift('x', -100)">Map Left</button>
      <button class="btn xsmall" onclick="cmMapCalShift('x', 100)">Map Right</button>
      <button class="btn xsmall" onclick="cmMapCalShift('y', 100)">Map Up</button>
      <button class="btn xsmall" onclick="cmMapCalShift('y', -100)">Map Down</button>
      <button class="btn xsmall ghost" onclick="cmMapCalScale('x', 100)">Wider X</button>
      <button class="btn xsmall ghost" onclick="cmMapCalScale('x', -100)">Narrower X</button>
      <button class="btn xsmall ghost" onclick="cmMapCalScale('y', 100)">Taller Y</button>
      <button class="btn xsmall ghost" onclick="cmMapCalScale('y', -100)">Shorter Y</button>
    </div>
    <textarea id="mapBoundsConfig" class="config-copy" readonly>${esc(configText)}</textarea>
    <div class="actions">
      <button class="btn small primary" onclick="cmMapCalSave()">Save For Every Restart</button>
      <button class="btn small" onclick="cmMapCalCopy()">Copy Config</button>
      <button class="btn small ghost" onclick="cmMapCalReset()">Reset Config Bounds</button>
    </div>
  </div>`;
}

function mapSelectionPanel() {
  const sel = state.map.selected;
  if (!sel) {
    return `<div class="card map-side-card"><h3>Map Selection</h3><p class="empty">Click a player or vehicle blip on the map.</p><p class="muted tiny">Player actions are permission based. Vehicle actions use network entity/plate when available.</p></div>`;
  }
  if (sel.type === 'world') {
    const w = sel.data || {};
    return `<div class="card map-side-card"><h3>Map Point</h3>
      <div class="detail-grid compact"><div class="kv"><small>X</small><strong>${Math.round(w.x || 0)}</strong></div><div class="kv"><small>Y</small><strong>${Math.round(w.y || 0)}</strong></div><div class="kv"><small>Z</small><strong>${Math.round(w.z || 40)}</strong></div></div>
      <div class="actions">${hasPerm('map.teleport') || hasPerm('gps.teleport') || hasPerm('players.teleport') || hasPerm('teleport') ? `<button class="btn small primary" onclick="cmMapTeleport(${Number(w.x || 0)}, ${Number(w.y || 0)}, ${Number(w.z || 40)})">Teleport Here</button>` : ''}</div>
    </div>`;
  }
  if (sel.type === 'vehicle') {
    const v = sel.data || {};
    const plate = esc(v.plate || 'UNKNOWN');
    return `<div class="card map-side-card selected-vehicle"><h3>Vehicle <span class="badge">${plate}</span></h3>
      <div class="detail-grid compact">
        <div class="kv"><small>Plate</small><strong>${plate}</strong></div>
        <div class="kv"><small>Model Hash</small><strong>${esc(v.model || '-')}</strong></div>
        <div class="kv"><small>Net ID</small><strong>${esc(v.netId || '-')}</strong></div>
        <div class="kv"><small>Coords</small><strong>${esc(formatCoords(v))}</strong></div>
      </div>
      <div class="actions">
        ${(hasPerm('map.teleport') || hasPerm('players.teleport') || hasPerm('teleport') || hasPerm('vehicles.view')) ? `<button class="btn small primary" onclick="cmMapVehicleAction('${escJs(v.netId || 0)}','${escJs(v.plate || '')}','goto')">Go To Vehicle</button>` : ''}
        ${hasPerm('vehicles.manage') ? `<button class="btn small success" onclick="cmMapVehicleAction('${escJs(v.netId || 0)}','${escJs(v.plate || '')}','repair')">Repair</button><button class="btn small danger" onclick="cmMapVehicleAction('${escJs(v.netId || 0)}','${escJs(v.plate || '')}','delete')">Delete</button>` : ''}
      </div>
    </div>`;
  }
  const p = sel.data || {};
  return `<div class="card map-side-card selected-player"><h3>${esc(p.name || 'Player')} <span class="badge">Char ${esc(p.characterId || '-')}</span></h3>
    <div class="detail-grid compact">
      <div class="kv"><small>Status</small><strong>${p.self ? 'You' : (p.adminMode ? 'Admin' : 'Player')}</strong></div>
      <div class="kv"><small>Character ID</small><strong>${esc(p.characterId || '-')}</strong></div>
      <div class="kv"><small>Character name</small><strong>${esc(p.characterName || '-')}</strong></div>
      <div class="kv"><small>Coords</small><strong>${esc(formatCoords(p))}</strong></div>
    </div>
    <div class="actions">
      ${hasPerm('players.view') ? `<button class="btn small" onclick="cmMapInspectPlayer(${Number(p.id || 0)})">Inspect</button>` : ''}
      ${hasPerm('players.teleport') ? `<button class="btn small primary" onclick="cmPlayerAction(${Number(p.id || 0)}, 'goto')">Go To</button><button class="btn small primary" onclick="cmPlayerAction(${Number(p.id || 0)}, 'bring')">Bring</button>` : ''}
      ${hasPerm('players.freeze') ? `<button class="btn small" onclick="cmPlayerAction(${Number(p.id || 0)}, 'freeze')">Freeze</button><button class="btn small" onclick="cmPlayerAction(${Number(p.id || 0)}, 'unfreeze')">Unfreeze</button>` : ''}
      ${hasPerm('tools.heal') ? `<button class="btn small success" onclick="cmPlayerAction(${Number(p.id || 0)}, 'heal')">Heal</button><button class="btn small success" onclick="cmPlayerAction(${Number(p.id || 0)}, 'armor')">Armor</button>` : ''}
      ${hasPerm('inventory.view') ? `<button class="btn small" onclick="cmViewInventory(${Number(p.id || 0)})">Inventory</button>` : ''}
      ${hasPerm('vehicles.view') ? `<button class="btn small" onclick="cmViewVehicles(${Number(p.id || 0)})">Cars</button>` : ''}
      ${hasPerm('players.kick') ? `<button class="btn small danger" onclick="cmKick(${Number(p.id || 0)})">Kick</button>` : ''}
    </div>
  </div>`;
}

function escJs(value) {
  return String(value === null || value === undefined ? '' : value).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, ' ');
}

function updateMapSelection() {
  const el = document.getElementById('mapSelection');
  if (el) el.innerHTML = mapSidePanel();
  scheduleMapDraw();
}

function cmMapVehToggle(v) { state.map.showVehicles = v; requestMapData(); }
function cmMapAdminToggle(v) { state.map.showAdmins = v; scheduleMapDraw(); }
function cmMapZoom(dir) {
  const cam = state.map.cam;
  cam.zoom = Math.min(1.65, Math.max(0.035, cam.zoom * (dir > 0 ? 1.22 : 0.82)));
  scheduleMapDraw();
}
function cmMapFocusSelf() {
  const self = (state.map.players || []).find(p => p.self);
  if (self) {
    state.map.cam.x = Number(self.x) || 0;
    state.map.cam.y = Number(self.y) || 0;
    state.map.selected = { type: 'player', data: self };
    updateMapSelection();
  } else {
    requestMapData();
  }
}
function cmMapClearSelection() { state.map.selected = null; updateMapSelection(); }
function ensureMapCalibration() {
  if (!state.map.calibration || !state.map.calibration.bounds) {
    state.map.calibration = { bounds: cleanBounds(serverMapBounds()) };
  }
  return state.map.calibration.bounds;
}
function cmMapToggleCalibration() {
  state.map.calibrating = !state.map.calibrating;
  if (state.map.calibrating) ensureMapCalibration();
  render();
}
function cmMapCalSet(key, value) {
  const b = ensureMapCalibration();
  if (!Object.prototype.hasOwnProperty.call(b, key)) return;
  const n = Number(value);
  if (!Number.isFinite(n)) return;
  b[key] = Math.round(n);
  state.map.calibration.bounds = cleanBounds(b);
  updateMapSelection();
}
function cmMapCalShift(axis, amount) {
  const b = ensureMapCalibration();
  amount = Number(amount || 0);
  if (axis === 'x') { b.minX += amount; b.maxX += amount; }
  if (axis === 'y') { b.minY += amount; b.maxY += amount; }
  state.map.calibration.bounds = cleanBounds(b);
  updateMapSelection();
}
function cmMapCalScale(axis, amount) {
  const b = ensureMapCalibration();
  amount = Number(amount || 0);
  if (axis === 'x') { b.minX -= amount; b.maxX += amount; }
  if (axis === 'y') { b.minY -= amount; b.maxY += amount; }
  state.map.calibration.bounds = cleanBounds(b);
  updateMapSelection();
}
function cmMapCalSave() {
  const b = cleanBounds(ensureMapCalibration());
  state.data.server = state.data.server || {};
  state.data.server.mapBounds = b;
  state.data.server.mapBoundsSource = 'saved';
  sendAction('saveMapBounds', { bounds: b });
  updateMapSelection();
}
function cmMapCalReset() {
  const b = cleanBounds((state.data && state.data.server && state.data.server.mapConfigBounds) || MAP_DEFAULT_BOUNDS);
  state.map.calibration = { bounds: b };
  state.data.server = state.data.server || {};
  state.data.server.mapBounds = b;
  sendAction('resetMapBounds', {});
  updateMapSelection();
}
function cmMapCalCopy() {
  const ta = document.getElementById('mapBoundsConfig');
  if (!ta) return;
  ta.focus();
  ta.select();
  try { document.execCommand('copy'); } catch (e) {}
}
function cmMapInspectPlayer(id) {
  state.selectedPlayer = Number(id || 0);
  state.tab = 'players';
  stopMapTimer();
  sendAction('refresh', {});
  render();
}
function cmMapTeleport(x, y, z) { sendAction('mapTeleportToCoords', { x, y, z }); }
function cmMapVehicleAction(netId, plate, vehicleAction) { sendAction('vehicleMapAction', { netId: Number(netId || 0), plate: plate || '', vehicleAction }); }

function requestMapData() {
  sendAction('mapData', { vehicles: state.map.showVehicles, admins: state.map.showAdmins });
}

function stopMapTimer() {
  if (state.map.timer) { clearInterval(state.map.timer); state.map.timer = null; }
}

function initMap() {
  const canvas = document.getElementById('mapCanvas');
  if (!canvas) return;

  if (!mapImgTried) {
    mapImgTried = true;
    const img = new Image();
    img.onload = () => { mapImg = img; scheduleMapDraw(); };
    img.onerror = () => { mapImg = null; scheduleMapDraw(); };
    img.src = 'assets/gta-map-local.png';
  }

  resizeMapCanvas(canvas);
  if (!state.map.resizeBound) {
    state.map.resizeBound = true;
    window.addEventListener('resize', () => {
      if (state.tab === 'map' && state.open) {
        const c = document.getElementById('mapCanvas');
        if (c) resizeMapCanvas(c);
        scheduleMapDraw();
      }
    }, { passive: true });
  }

  canvas.onmousedown = (e) => { state.map.drag = { x: e.clientX, y: e.clientY }; state.map.moved = false; };
  window.onmouseup = () => { state.map.drag = null; };
  canvas.onmousemove = (e) => {
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    const w = screenToWorld(canvas, mx, my);
    state.map.cursor = w;
    const hint = document.getElementById('mapCoordsHint');
    if (hint) hint.textContent = `X ${Math.round(w.x)} Y ${Math.round(w.y)}`;

    if (!state.map.drag) return;
    const cam = state.map.cam;
    const dx = e.clientX - state.map.drag.x;
    const dy = e.clientY - state.map.drag.y;
    if (Math.abs(dx) + Math.abs(dy) > 3) state.map.moved = true;
    cam.x -= dx / cam.zoom;
    cam.y += dy / cam.zoom;
    state.map.drag = { x: e.clientX, y: e.clientY };
    scheduleMapDraw();
  };
  canvas.onwheel = (e) => {
    e.preventDefault();
    const before = screenToWorld(canvas, e.offsetX, e.offsetY);
    const cam = state.map.cam;
    cam.zoom = Math.min(1.65, Math.max(0.035, cam.zoom * (e.deltaY < 0 ? 1.18 : 0.85)));
    const after = screenToWorld(canvas, e.offsetX, e.offsetY);
    cam.x += before.x - after.x;
    cam.y += before.y - after.y;
    scheduleMapDraw();
  };
  canvas.onclick = (e) => {
    if (state.map.moved) return;
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;

    let best = null;
    for (const p of state.map.players || []) {
      const s = worldToScreen(canvas, p.x, p.y);
      const d = Math.hypot(s.x - mx, s.y - my);
      if (d < 18 && (!best || d < best.d)) best = { d, type: 'player', data: p };
    }
    if (state.map.showVehicles) {
      for (const v of state.map.vehicles || []) {
        const s = worldToScreen(canvas, v.x, v.y);
        const d = Math.hypot(s.x - mx, s.y - my);
        if (d < 16 && (!best || d < best.d)) best = { d, type: 'vehicle', data: v };
      }
    }
    state.map.selected = best ? { type: best.type, data: best.data } : { type: 'world', data: screenToWorld(canvas, mx, my) };
    updateMapSelection();
  };

  stopMapTimer();
  requestMapData();
  state.map.timer = setInterval(() => {
    if (state.tab === 'map' && state.open) requestMapData();
    else stopMapTimer();
  }, 1500);

  scheduleMapDraw();
}

function resizeMapCanvas(canvas) {
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
  canvas.width = Math.max(300, Math.floor(rect.width * dpr));
  canvas.height = Math.max(260, Math.floor(rect.height * dpr));
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  canvas._cmWidth = rect.width;
  canvas._cmHeight = rect.height;
}

function canvasW(canvas) { return canvas._cmWidth || canvas.clientWidth || canvas.width; }
function canvasH(canvas) { return canvas._cmHeight || canvas.clientHeight || canvas.height; }

function worldToScreen(canvas, wx, wy) {
  const cam = state.map.cam;
  return {
    x: (Number(wx || 0) - cam.x) * cam.zoom + canvasW(canvas) / 2,
    y: -(Number(wy || 0) - cam.y) * cam.zoom + canvasH(canvas) / 2
  };
}

function screenToWorld(canvas, sx, sy) {
  const cam = state.map.cam;
  return {
    x: ((sx - canvasW(canvas) / 2) / cam.zoom) + cam.x,
    y: -((sy - canvasH(canvas) / 2) / cam.zoom) + cam.y,
    z: 40
  };
}

function scheduleMapDraw() {
  if (mapDrawQueued) return;
  mapDrawQueued = true;
  requestAnimationFrame(() => { mapDrawQueued = false; drawMap(); });
}

function drawMap() {
  const canvas = document.getElementById('mapCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const w = canvasW(canvas), h = canvasH(canvas);
  const cam = state.map.cam;
  const bounds = mapBounds();

  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = '#07131b';
  ctx.fillRect(0, 0, w, h);

  if (mapImg) {
    const tl = worldToScreen(canvas, bounds.minX, bounds.maxY);
    const iw = (bounds.maxX - bounds.minX) * cam.zoom;
    const ih = (bounds.maxY - bounds.minY) * cam.zoom;
    ctx.globalAlpha = 0.92;
    ctx.drawImage(mapImg, tl.x, tl.y, iw, ih);
    ctx.globalAlpha = 1;
  } else {
    ctx.strokeStyle = 'rgba(140, 230, 255, 0.08)';
    ctx.lineWidth = 1;
    for (let gx = bounds.minX; gx <= bounds.maxX; gx += 500) {
      const a = worldToScreen(canvas, gx, bounds.minY), b = worldToScreen(canvas, gx, bounds.maxY);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
    for (let gy = bounds.minY; gy <= bounds.maxY; gy += 500) {
      const a = worldToScreen(canvas, bounds.minX, gy), b = worldToScreen(canvas, bounds.maxX, gy);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
  }

  const selected = state.map.selected;

  if (state.map.showVehicles) {
    for (const v of state.map.vehicles || []) {
      const s = worldToScreen(canvas, v.x, v.y);
      if (s.x < -20 || s.y < -20 || s.x > w + 20 || s.y > h + 20) continue;
      const isSel = selected && selected.type === 'vehicle' && ((selected.data.netId && selected.data.netId === v.netId) || (selected.data.plate && selected.data.plate === v.plate));
      ctx.save();
      ctx.translate(s.x, s.y);
      ctx.fillStyle = isSel ? '#ffffff' : 'rgba(255, 195, 72, 0.95)';
      ctx.strokeStyle = isSel ? '#ffd25a' : 'rgba(0,0,0,0.75)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.rect(-4.5, -4.5, 9, 9);
      ctx.fill();
      ctx.stroke();
      ctx.restore();
    }
  }

  for (const p of state.map.players || []) {
    const isAdmin = p.adminMode && state.map.showAdmins;
    const isSel = selected && selected.type === 'player' && Number(selected.data.id) === Number(p.id);
    const s = worldToScreen(canvas, p.x, p.y);
    if (s.x < -100 || s.y < -40 || s.x > w + 140 || s.y > h + 40) continue;
    ctx.beginPath();
    ctx.arc(s.x, s.y, isSel ? 9 : (p.self ? 8 : (isAdmin ? 7 : 5.5)), 0, Math.PI * 2);
    ctx.fillStyle = isSel ? '#ffffff' : (p.self ? '#52ffa9' : (isAdmin ? '#ff2d3d' : '#45e0ff'));
    ctx.fill();
    ctx.lineWidth = isSel ? 3 : 2;
    ctx.strokeStyle = isSel ? '#45e0ff' : 'rgba(0,0,0,0.72)';
    ctx.stroke();
    ctx.fillStyle = isAdmin ? '#ff2d3d' : 'rgba(235, 252, 255, 0.95)';
    ctx.font = isSel ? '800 11px Arial, sans-serif' : '700 11px Arial, sans-serif';
    const idText = p.characterId ? `#${p.characterId}` : 'No Char';
    const label = `${isAdmin ? 'ADMIN ' : ''}${p.name || 'Player'} ${idText}`;
    ctx.fillText(label, s.x + 10, s.y + 4);
  }
}

window.cmMapToggleCalibration = cmMapToggleCalibration;
window.cmMapCalSet = cmMapCalSet;
window.cmMapCalShift = cmMapCalShift;
window.cmMapCalScale = cmMapCalScale;
window.cmMapCalSave = cmMapCalSave;
window.cmMapCalReset = cmMapCalReset;
window.cmMapCalCopy = cmMapCalCopy;
window.cmMapVehToggle = cmMapVehToggle;
window.cmMapAdminToggle = cmMapAdminToggle;
window.cmMapZoom = cmMapZoom;
window.cmMapFocusSelf = cmMapFocusSelf;
window.cmMapClearSelection = cmMapClearSelection;
window.cmMapInspectPlayer = cmMapInspectPlayer;
window.cmMapTeleport = cmMapTeleport;
window.cmMapVehicleAction = cmMapVehicleAction;

// ---------------------------------------------------------------------------
// Developer tools (plugin-registered by other resources; nothing hardcoded).
// ---------------------------------------------------------------------------
function developerPage() {
  const tools = state.data.devTools || [];
  if (!tools.length) {
    return `<div class="card"><h3>Developer Tools</h3>
      <p class="empty">No tools registered (or none you have permission for).<br><br>
      Resources self-register with:<br>
      <code>exports['cm-admin']:RegisterDevTool({ ... })</code><br>
      and appear here automatically — this panel never needs editing.</p></div>`;
  }

  const selected = tools.find(t => t.id === state.devTool) || tools[0];
  state.devTool = selected.id;

  let lastCat = null;
  const list = tools.map(t => {
    const cat = t.category !== lastCat ? `<div class="dev-cat">${esc(t.category)}</div>` : '';
    lastCat = t.category;
    return `${cat}<button class="item ${t.id === selected.id ? 'active' : ''}" onclick="cmDevSelect('${esc(t.id)}')">
      <div><strong>${esc(t.label)}</strong><small>${(t.actions || []).length} actions</small></div>
    </button>`;
  }).join('');

  const actions = (selected.actions || []).map(a => {
    if (a.type === 'form') {
      const fields = (a.fields || []).map(f => {
        const fid = `devf_${selected.id}_${a.id}_${f.id}`;
        if (f.type === 'select') {
          const opts = (f.options || []).map(o => `<option value="${esc(o)}">${esc(o)}</option>`).join('');
          return `<label class="dev-field"><span>${esc(f.label)}</span><select id="${fid}">${opts}</select></label>`;
        }
        return `<label class="dev-field"><span>${esc(f.label)}</span>
          <input id="${fid}" type="${f.type === 'number' ? 'number' : 'text'}" placeholder="${esc(f.placeholder || '')}" /></label>`;
      }).join('');
      return `<div class="dev-action form">
        <div class="dev-action-head"><strong>${esc(a.label)}</strong>${a.hint ? `<small>${esc(a.hint)}</small>` : ''}</div>
        ${fields}
        <button class="btn" onclick="cmDevForm('${esc(selected.id)}', '${esc(a.id)}')">Run</button>
      </div>`;
    }
    return `<div class="dev-action">
      <div class="dev-action-head"><strong>${esc(a.label)}</strong>${a.hint ? `<small>${esc(a.hint)}</small>` : ''}</div>
      <button class="btn" onclick="cmDevAction('${esc(selected.id)}', '${esc(a.id)}')">Run</button>
    </div>`;
  }).join('');

  return `
    <div class="split">
      <div class="card list-card">${list}</div>
      <div class="card"><h3>${esc(selected.label)}</h3><div class="dev-actions">${actions}</div></div>
    </div>`;
}

function cmDevSelect(id) { state.devTool = id; render(); }

function cmDevAction(tool, actionId) {
  sendAction('devAction', { tool, actionId });
}

function cmDevForm(tool, actionId) {
  const t = (state.data.devTools || []).find(x => x.id === tool);
  const a = t && (t.actions || []).find(x => x.id === actionId);
  if (!a) return;
  const values = {};
  for (const f of (a.fields || [])) {
    const el = document.getElementById(`devf_${tool}_${actionId}_${f.id}`);
    if (!el) continue;
    if (f.required && !el.value) { el.focus(); return; }
    values[f.id] = el.value;
  }
  sendAction('devAction', { tool, actionId, values });
}
