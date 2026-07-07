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
  data: { me: {}, players: [], admins: [], ranks: [], logs: [], permissions: [], server: {} },
  offline: { query: '', results: [] },
  map: { players: [], vehicles: [], showVehicles: false, cam: { x: 0, y: 0, zoom: 0.08 }, timer: null, drag: null },
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
      <div class="card stat"><small>Admins saved</small><strong>${admins.length}</strong><span>Database</span></div>
      <div class="card stat"><small>Ranks</small><strong>${ranks.length}</strong><span>Permission groups</span></div>
      <div class="card stat"><small>Recent logs</small><strong>${logs.length}</strong><span>Audit trail</span></div>
    </div>
    <div class="grid cols-2" style="margin-top:16px">
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
      <div class="avatar">${esc(p.id)}</div>
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
      <h3>${esc(p.name)} <span class="badge">ID ${esc(p.id)}</span></h3>
      <div class="detail-grid">
        <div class="kv"><small>Character ID</small><strong>${esc(p.characterId || '-')}</strong></div>
        <div class="kv"><small>Character name</small><strong>${esc(p.characterName || '-')}</strong></div>
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

function ranksPage() {
  const ranks = state.data.ranks || [];
  const perms = ['*'].concat(state.data.permissions || []);
  return `
    <div class="grid cols-2">
      <div class="card">
        <h3>Create / Edit Rank</h3>
        <div class="form">
          <div class="field"><label>Rank Name</label><input id="rankName" class="input" placeholder="senioradmin" /></div>
          <div class="field"><label>Label</label><input id="rankLabel" class="input" placeholder="Senior Admin" /></div>
          <div class="field"><label>Level</label><input id="rankLevel" class="input" type="number" value="20" /></div>
          <div class="actions"><button class="btn primary" onclick="cmSaveRank()">Save Rank</button><button class="btn danger" onclick="cmDeleteRank()">Delete Rank</button></div>
          <div class="field full"><label>Permissions</label><div class="permissions">${perms.map(p => `<label class="check"><input class="permCheck" type="checkbox" value="${esc(p)}" /> ${esc(p)}</label>`).join('')}</div></div>
        </div>
      </div>
      <div class="card">
        <h3>Ranks</h3>
        <div class="table-wrap"><table><thead><tr><th>Rank</th><th>Level</th><th>Permissions</th><th>Action</th></tr></thead><tbody>
          ${ranks.map(r => `<tr><td><strong>${esc(r.label)}</strong><br><small>${esc(r.name)}</small></td><td>${esc(r.level)}</td><td>${esc((r.permissions || []).join(', '))}</td><td><button class="btn small" onclick="cmLoadRank('${esc(r.name)}')">Edit</button></td></tr>`).join('')}
        </tbody></table></div>
      </div>
    </div>`;
}

window.cmLoadRank = function(name) {
  const r = (state.data.ranks || []).find(x => x.name === name);
  if (!r) return;
  document.getElementById('rankName').value = r.name;
  document.getElementById('rankLabel').value = r.label;
  document.getElementById('rankLevel').value = r.level;
  document.querySelectorAll('.permCheck').forEach(cb => { cb.checked = (r.permissions || []).includes(cb.value); });
};
window.cmSaveRank = function() {
  const permissions = Array.from(document.querySelectorAll('.permCheck:checked')).map(cb => cb.value);
  action('saveRank', {
    name: document.getElementById('rankName').value,
    label: document.getElementById('rankLabel').value,
    level: Number(document.getElementById('rankLevel').value || 0),
    permissions
  });
};
window.cmDeleteRank = function() {
  const name = document.getElementById('rankName').value;
  if (!name) return;
  if (confirm(`Delete rank ${name}?`)) action('deleteRank', { name });
};

function logsPage() {
  const logs = state.detail && state.detail.type === 'logs' ? state.detail.data.logs : (state.data.logs || []);
  return `
    <div class="card">
      <div class="actions" style="justify-content:space-between; margin-bottom:12px">
        <h3 style="margin:0">Audit Logs</h3>
        <button class="btn primary" onclick="action('viewLogs')">Load More</button>
      </div>
      <div class="table-wrap">
        <table><thead><tr><th>ID</th><th>Admin</th><th>Action</th><th>Target</th><th>Details</th><th>Time</th></tr></thead><tbody>
          ${logs.map(l => `<tr><td>${esc(l.id)}</td><td>${esc(l.adminName || l.identifier || '-')}<br><small>${esc(l.source || '')}</small></td><td><span class="badge">${esc(l.action)}</span></td><td>${esc(l.targetName || '-')}<br><small>${esc(l.targetIdentifier || '')}</small></td><td><div class="json">${esc(JSON.stringify(l.details || {}, null, 2))}</div></td><td>${esc(l.createdAt || '-')}</td></tr>`).join('')}
        </tbody></table>
      </div>
    </div>`;
}

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
    if (msg.data && msg.data.vehicles) state.map.vehicles = msg.data.vehicles;
    if (state.tab === 'map') drawMap();
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
// Live map (canvas radar: pan = drag, zoom = wheel, click = open profile).
// Drop a rendered GTA V atlas as ui/map.png to get a real map background.
// ---------------------------------------------------------------------------
const MAP_BOUNDS = { minX: -4230, maxX: 4600, minY: -4400, maxY: 8000 };
let mapImg = null, mapImgTried = false;

function mapPage() {
  return `
    <div class="card map-card">
      <h3>Live Map
        <label class="check map-toggle"><input type="checkbox" id="mapVehToggle" ${state.map.showVehicles ? 'checked' : ''} onchange="cmMapVehToggle(this.checked)" /> Show vehicles</label>
      </h3>
      <canvas id="mapCanvas"></canvas>
      <div class="map-hint">Drag = pan · Wheel = zoom · Click blip = open profile</div>
    </div>`;
}

function cmMapVehToggle(v) { state.map.showVehicles = v; requestMapData(); }

function requestMapData() {
  sendAction('mapData', { vehicles: state.map.showVehicles });
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
    img.onload = () => { mapImg = img; drawMap(); };
    img.src = 'map.png';
  }

  canvas.width = canvas.clientWidth;
  canvas.height = canvas.clientHeight;

  canvas.onmousedown = (e) => { state.map.drag = { x: e.clientX, y: e.clientY }; };
  window.onmouseup = () => { state.map.drag = null; };
  canvas.onmousemove = (e) => {
    if (!state.map.drag) return;
    const cam = state.map.cam;
    cam.x -= (e.clientX - state.map.drag.x) / cam.zoom;
    cam.y += (e.clientY - state.map.drag.y) / cam.zoom;
    state.map.drag = { x: e.clientX, y: e.clientY };
    drawMap();
  };
  canvas.onwheel = (e) => {
    e.preventDefault();
    const cam = state.map.cam;
    cam.zoom = Math.min(1.2, Math.max(0.02, cam.zoom * (e.deltaY < 0 ? 1.18 : 0.85)));
    drawMap();
  };
  canvas.onclick = (e) => {
    if (state.map.dragMoved) return;
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left, my = e.clientY - rect.top;
    for (const p of state.map.players) {
      const s = worldToScreen(canvas, p.x, p.y);
      if (Math.hypot(s.x - mx, s.y - my) < 12) {
        state.selectedPlayer = p.id;
        state.tab = 'players';
        stopMapTimer();
        sendAction('refresh', {});
        render();
        return;
      }
    }
  };

  stopMapTimer();
  requestMapData();
  state.map.timer = setInterval(() => {
    if (state.tab === 'map' && state.open) requestMapData();
    else stopMapTimer();
  }, 2000);

  drawMap();
}

function worldToScreen(canvas, wx, wy) {
  const cam = state.map.cam;
  return {
    x: (wx - cam.x) * cam.zoom + canvas.width / 2,
    y: -(wy - cam.y) * cam.zoom + canvas.height / 2
  };
}

function drawMap() {
  const canvas = document.getElementById('mapCanvas');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const cam = state.map.cam;

  ctx.fillStyle = '#0a141b';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  if (mapImg) {
    const tl = worldToScreen(canvas, MAP_BOUNDS.minX, MAP_BOUNDS.maxY);
    const w = (MAP_BOUNDS.maxX - MAP_BOUNDS.minX) * cam.zoom;
    const h = (MAP_BOUNDS.maxY - MAP_BOUNDS.minY) * cam.zoom;
    ctx.globalAlpha = 0.55;
    ctx.drawImage(mapImg, tl.x, tl.y, w, h);
    ctx.globalAlpha = 1;
  } else {
    // Grid every 500m
    ctx.strokeStyle = 'rgba(140, 230, 255, 0.07)';
    ctx.lineWidth = 1;
    for (let gx = MAP_BOUNDS.minX; gx <= MAP_BOUNDS.maxX; gx += 500) {
      const a = worldToScreen(canvas, gx, MAP_BOUNDS.minY), b = worldToScreen(canvas, gx, MAP_BOUNDS.maxY);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
    for (let gy = MAP_BOUNDS.minY; gy <= MAP_BOUNDS.maxY; gy += 500) {
      const a = worldToScreen(canvas, MAP_BOUNDS.minX, gy), b = worldToScreen(canvas, MAP_BOUNDS.maxX, gy);
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
    }
  }

  if (state.map.showVehicles) {
    ctx.fillStyle = 'rgba(255, 176, 32, 0.85)';
    for (const v of state.map.vehicles) {
      const s = worldToScreen(canvas, v.x, v.y);
      ctx.fillRect(s.x - 2.5, s.y - 2.5, 5, 5);
    }
  }

  for (const p of state.map.players) {
    const s = worldToScreen(canvas, p.x, p.y);
    ctx.beginPath();
    ctx.arc(s.x, s.y, p.self ? 7 : 5.5, 0, Math.PI * 2);
    ctx.fillStyle = p.self ? '#39ff88' : '#00e6ff';
    ctx.fill();
    ctx.strokeStyle = 'rgba(0,0,0,0.65)';
    ctx.stroke();
    ctx.fillStyle = 'rgba(235, 252, 255, 0.92)';
    ctx.font = '600 11px Nunito, sans-serif';
    ctx.fillText(`${p.name} [${p.id}]`, s.x + 9, s.y + 4);
  }
}


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
