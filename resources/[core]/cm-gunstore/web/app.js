/* cm-gunstore/web/app.js (v1.11.2)
 * Store rework: the player store no longer lists ammo in its own column.
 * Instead, selecting a weapon reveals an "Add ammunition" panel populated from
 * that weapon's linked ammo (resolved server-side). Ammo bought this way is
 * delivered together with the gun in a single validated purchase.
 * Admin panels (weapon picker / ammo picker / armor creator) are unchanged.
 *
 * The "Press E" prompt and the NPC conversation are cm-ui's shared components
 * now (client/main.lua uses exports['cm-ui']:ShowInteract/OpenNpcDialogue),
 * so this page only owns the catalog/admin UI -- no interaction/dialog DOM.
 */

const app = document.getElementById('app');
const itemsEl = document.getElementById('items');
const titleEl = document.getElementById('title');
const modeLabel = document.getElementById('modeLabel');
const closeBtn = document.getElementById('closeBtn');
const refreshBtn = document.getElementById('refreshBtn');

const state = {
  mode: 'store',
  filter: 'all',
  catalog: [],
  busy: false,
  imageData: '',
  capturedArmorImage: '',
  weaponPicker: [],
  weaponGroups: [],
  weaponGroup: 'pistol',
  weaponSearch: '',
  ammoPicker: [],
  ammoGroups: [],
  ammoGroup: 'pistol',
  ammoSearch: '',
  selectedName: '',
  npcs: [],            // custom NPCs loaded for the admin "Manage NPCs" tab
  npcName: '',
  npcLabel: 'Gun Store',
  npcModel: '',
  npcScenario: '',
  ammoQty: 1,          // ammo quantity when an ammo item is itself selected (admin/back-compat)
  // ammo-per-weapon flow:
  weaponAmmo: {},      // { [weaponItemName]: { item_name, label, image, price, pack_size, buyable } | null }
  addAmmo: false,      // is the "add ammunition" toggle on for the selected weapon
  ammoRounds: 30,      // how many rounds to bundle with the gun
  collapsedGroups: {}  // { [groupLabel]: true } -- catalog dropdowns that are collapsed
};

const DEFAULT_BUNDLE = 30;

function resName() { return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-gunstore'; }
function post(path, body = {}) { return fetch(`https://${resName()}/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => null); }
function money(n) { n = Number(n) || 0; return `$${n.toLocaleString()}`; }
function escapeAttr(v) { return String(v ?? '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function escapeHtml(v) { return String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

/* Native `confirm()` is unreliable inside FiveM's CEF NUI (it can return
 * immediately without actually blocking/showing), which is why the old
 * delete buttons here silently did nothing. cm-ui's CMUI.confirm is a real
 * DOM modal that returns a Promise<boolean>, so use that when cm-ui is
 * running and fall back to native confirm only if it truly isn't loaded. */
function cmConfirm(message, opts = {}) {
  if (window.CMUI && typeof CMUI.confirm === 'function') {
    return CMUI.confirm({ title: opts.title || 'Confirm', message, confirmText: opts.confirmText || 'Confirm', danger: opts.danger === true });
  }
  return Promise.resolve(confirm(message));
}
function confirmDelete(message) { return cmConfirm(message, { title: 'Remove item', confirmText: 'Remove', danger: true }); }
function clampRounds(n) { return Math.max(1, Math.min(999, Math.floor(Number(n) || 1))); }

function imgSrc(value) {
  let icon = String(value || '').trim();
  if (!icon) return 'images/weapon_pistol.svg';
  const nui = icon.match(/^nui:\/\/([^\/]+)\/(.+)$/i);
  if (nui) return `https://cfx-nui-${nui[1]}/${nui[2]}`;
  if (icon.startsWith('http://') || icon.startsWith('https://') || icon.startsWith('data:')) return icon;
  if (icon.startsWith('images/')) return icon;
  return `images/${icon}`;
}

function typeLabel(row) {
  if (row.item_type === 'ammo') return `${row.ammo_key ? row.ammo_key.toUpperCase() + ' • ' : ''}Per round`;
  if (row.item_type === 'armor') return `${row.armor_value || row.armorValue || 0} Armor`;
  const dmg = Number(row.damage || 0);
  return `${row.item_type === 'weapon' ? 'Weapon' : 'Item'}${dmg ? ` • ${dmg} Damage` : ''}`;
}
function itemAccent(row) { return row.item_type === 'ammo' ? 'ammo' : row.item_type === 'armor' ? 'armor' : 'weapon'; }

/* Player store shows weapons, ammo and armor. Ammo is buyable on its own AND
 * offered as a convenience add-on when a weapon is selected. Admin sees all. */
function visibleRows() {
  return state.catalog.filter(row => {
    if (state.mode === 'admin') return (state.filter === 'all' || row.item_type === state.filter);
    if (row.enabled === false) return false;
    if (state.filter === 'all') return true;
    return row.item_type === state.filter;
  });
}

function getSelectedRow(rows = visibleRows()) {
  if (!rows.length) return null;
  let row = rows.find(x => x.item_name === state.selectedName);
  if (!row) { row = rows[0]; state.selectedName = row.item_name; }
  return row;
}

function groupLabel(row) {
  if (row.item_type === 'ammo') return 'Ammunition';
  if (row.item_type === 'armor') return 'Armor';
  const raw = String(row.group || row.group_key || row.weapon_group || '').toLowerCase();
  if (raw === 'smg') return 'Submachine Guns';
  if (raw === 'rifle') return 'Assault Rifles';
  if (raw === 'shotgun') return 'Shotguns';
  if (raw === 'sniper') return 'Sniper Rifles';
  if (raw === 'machinegun' || raw === 'mg') return 'Machine Guns';
  return 'Pistols';
}

function statBars(value, max = 100) {
  const lit = Math.max(1, Math.min(7, Math.round((Number(value) || 0) / max * 7)));
  return Array.from({ length: 7 }, (_, i) => `<span class="bar ${i < lit ? 'on' : ''}"></span>`).join('');
}

/* When a weapon is selected, ask the server for its linked ammo once and cache
 * it. Reset the add-ammo toggle each time the selection changes. */
function ensureWeaponAmmo(row) {
  if (!row || row.item_type !== 'weapon') return;
  if (Object.prototype.hasOwnProperty.call(state.weaponAmmo, row.item_name)) return;
  state.weaponAmmo[row.item_name] = undefined; // pending marker
  post('requestWeaponAmmo', { item_name: row.item_name });
}

function storeList(rows) {
  const groups = [];
  const seen = {};
  rows.forEach(row => { const g = groupLabel(row); if (!seen[g]) { seen[g] = []; groups.push(g); } seen[g].push(row); });

  // The group that holds the current selection is always shown open.
  const selectedGroup = (() => {
    const sel = rows.find(x => x.item_name === state.selectedName);
    return sel ? groupLabel(sel) : null;
  })();

  return groups.map(g => {
    const collapsed = state.collapsedGroups[g] === true && g !== selectedGroup;
    const items = seen[g].map(row => `
      <button class="shop-list-item ${row.item_name === state.selectedName ? 'active' : ''}" data-select="${escapeAttr(row.item_name)}">
        <img src="${imgSrc(row.image)}" onerror="this.style.opacity=.18" />
        <span>${escapeHtml(row.label)}</span>
        <strong>${money(row.price)}</strong>
      </button>`).join('');
    return `<section class="shop-group ${collapsed ? 'collapsed' : ''}">
      <button class="shop-group-head" data-group="${escapeAttr(g)}" aria-expanded="${collapsed ? 'false' : 'true'}">
        <span class="shop-group-title">${escapeHtml(g)}</span>
        <span class="shop-group-meta"><span class="shop-group-count">${seen[g].length}</span><span class="shop-group-chevron">⌄</span></span>
      </button>
      <div class="shop-group-list">${items}</div>
    </section>`;
  }).join('');
}

/* The "Add ammunition" block, shown only for weapons that have buyable linked
 * ammo. The rounds stepper feeds ammo_rounds into buyItem. */
function ammoAddonPanel(row) {
  const ammo = state.weaponAmmo[row.item_name];
  if (ammo === undefined) {
    return `<div class="ammo-addon pending"><span>Checking ammunition…</span></div>`;
  }
  if (!ammo) {
    return `<div class="ammo-addon none"><span>No ammunition sold here for this weapon.</span></div>`;
  }
  if (!ammo.buyable) {
    return `<div class="ammo-addon none"><span>${escapeHtml(ammo.label)} is currently out of stock.</span></div>`;
  }
  const rounds = clampRounds(state.ammoRounds || DEFAULT_BUNDLE);
  const ammoTotal = (Number(ammo.price) || 0) * rounds;
  return `<div class="ammo-addon ${state.addAmmo ? 'on' : ''}">
    <label class="ammo-addon-toggle">
      <input type="checkbox" id="addAmmoToggle" ${state.addAmmo ? 'checked' : ''} />
      <span class="ammo-addon-head">
        <img src="${imgSrc(ammo.image)}" onerror="this.style.opacity=.2" />
        <span class="ammo-addon-copy"><strong>Add ammunition</strong><small>${escapeHtml(ammo.label)} · ${money(ammo.price)}/round</small></span>
      </span>
    </label>
    <div class="ammo-addon-body ${state.addAmmo ? '' : 'collapsed'}">
      <div class="qty">
        <button data-rounds="-10">−10</button>
        <button data-rounds="-1">−</button>
        <input id="ammoRounds" value="${rounds}" inputmode="numeric" />
        <button data-rounds="1">+</button>
        <button data-rounds="10">+10</button>
      </div>
      <span class="ammo-addon-total">+${money(ammoTotal)}</span>
    </div>
  </div>`;
}

function storeDetail(row) {
  if (!row) return '<section class="shop-detail empty">No item selected</section>';
  const isArmor = row.item_type === 'armor';
  const isWeapon = row.item_type === 'weapon';
  const isAmmo = row.item_type === 'ammo';

  // ----- Ammo: standalone purchase with a quantity stepper -----
  if (isAmmo) {
    const qty = clampRounds(state.ammoQty || DEFAULT_BUNDLE);
    const total = (Number(row.price) || 0) * qty;
    return `<section class="shop-detail">
      <p class="shop-kicker">Ammunition</p>
      <h2>${escapeHtml(row.label)}</h2>
      <div class="detail-image"><img src="${imgSrc(row.image)}" onerror="this.style.opacity=.18" /></div>
      <div class="detail-price">${money(row.price)}<small>/ round</small></div>
      <div class="stat-row"><span>Caliber</span><div class="stat-text">${escapeHtml((row.ammo_key || 'standard').toUpperCase())}</div></div>
      <p class="detail-desc">${escapeHtml(row.description || 'Ammunition round.')}</p>
      <div class="ammo-buy">
        <span class="ammo-buy-label">Rounds</span>
        <div class="qty">
          <button data-ammoqty="-10">−10</button>
          <button data-ammoqty="-1">−</button>
          <input id="ammoQty" value="${qty}" inputmode="numeric" />
          <button data-ammoqty="1">+</button>
          <button data-ammoqty="10">+10</button>
        </div>
      </div>
      <div class="detail-total"><span>Total</span><strong>${money(total)}</strong></div>
      <div class="buy-row">
        <button class="buy cash" data-buy="cash" data-name="${escapeAttr(row.item_name)}">Buy Cash</button>
        <button class="buy" data-buy="bank" data-name="${escapeAttr(row.item_name)}">Buy Bank</button>
      </div>
    </section>`;
  }

  // ----- Weapon / armor -----
  const statOne = isArmor ? Number(row.armor_value || row.armorValue || 0) : Number(row.damage || 0);
  const statTwo = isArmor ? 35 : Number(row.magazine_size || row.magazineSize || 0);

  // grand total = weapon + optional ammo bundle
  let grand = Number(row.price) || 0;
  if (isWeapon && state.addAmmo) {
    const ammo = state.weaponAmmo[row.item_name];
    if (ammo && ammo.buyable) grand += (Number(ammo.price) || 0) * clampRounds(state.ammoRounds || DEFAULT_BUNDLE);
  }

  return `<section class="shop-detail">
    <p class="shop-kicker">${isArmor ? 'Armor Information' : 'Weapon Information'}</p>
    <h2>${escapeHtml(row.label)}</h2>
    <div class="detail-image"><img src="${imgSrc(row.image)}" onerror="this.style.opacity=.18" /></div>
    <div class="detail-price">${money(row.price)}</div>
    <div class="stat-row"><span>${isArmor ? 'Protection' : 'Damage'}</span><div>${statBars(statOne, isArmor ? 100 : 160)}</div></div>
    <div class="stat-row"><span>${isArmor ? 'Weight' : 'Magazine'}</span><div>${statBars(statTwo, isArmor ? 100 : 100)}</div></div>
    ${isWeapon ? `<div class="stat-row"><span>Range</span><div>${statBars(row.group === 'sniper' ? 90 : row.group === 'shotgun' ? 25 : row.group === 'rifle' ? 70 : 45, 100)}</div></div>` : ''}
    <p class="detail-desc">${escapeHtml(row.description || 'Inventory item.')}</p>
    ${isWeapon ? ammoAddonPanel(row) : ''}
    <div class="detail-total"><span>Total</span><strong>${money(grand)}</strong></div>
    <div class="buy-row">
      <button class="buy cash" data-buy="cash" data-name="${escapeAttr(row.item_name)}">Buy Cash</button>
      <button class="buy" data-buy="bank" data-name="${escapeAttr(row.item_name)}">Buy Bank</button>
    </div>
  </section>`;
}

function storeView() {
  const rows = visibleRows();
  const selected = getSelectedRow(rows);
  if (selected) ensureWeaponAmmo(selected);
  return `<section class="shop-ui">
    <aside class="shop-left"><div class="shop-title"><p>CM Ammu-Nation</p><h2>Catalog</h2></div>${storeList(rows)}</aside>
    <section class="shop-center">${selected ? `<div class="hero-card"><img src="${imgSrc(selected.image)}" onerror="this.style.opacity=.18" /><h3>${escapeHtml(selected.label)}</h3><p>${escapeHtml(typeLabel(selected))}</p></div>` : ''}</section>
    ${storeDetail(selected)}
  </section>`;
}

/* ===== Admin: weapon / ammo pickers (unchanged behaviour) ===== */
function statusBadge(status) {
  if (status === 'store') return '<span class="wstatus on">In Store</span>';
  if (status === 'hidden') return '<span class="wstatus off">Hidden</span>';
  return '<span class="wstatus made">In cm-weapons</span>';
}

function weaponCard(w) {
  const itemName = escapeAttr(w.item_name || String(w.hash || '').toLowerCase());
  return `<article class="wcard" data-whash="${escapeAttr(w.hash || w.weapon_hash)}" data-item="${itemName}">
    <div class="wimg"><img src="${imgSrc(w.image)}" alt="${escapeAttr(w.label)}" onerror="this.style.opacity=0.2"></div>
    <div class="whead"><h4>${escapeHtml(w.label)}</h4>${statusBadge(w.status)}</div>
    <code class="whash">${escapeHtml(w.item_name || '')}</code>
    <div class="wfields">
      <label><span>Config Price</span><input data-wfield="price" type="number" min="0" value="${Number(w.price) || 0}" disabled></label>
      <label><span>Stock</span><input data-wfield="stock" type="number" value="${Number(w.stock ?? -1)}"></label>
      <label><span>Damage</span><input value="${Number(w.damage) || 0}" disabled></label>
      <label><span>Ammo</span><input value="${escapeAttr(w.ammo_item || w.ammo || '')}" disabled></label>
      <p class="ammo-damage-note wide">Price comes from shared/config.lua. Gun admin only saves stock and Store/Hidden.</p>
      <label class="wtoggle"><input data-wfield="enabled" type="checkbox" ${w.status === 'store' ? 'checked' : ''}><span>In Store</span></label>
    </div>
    <div class="wbuttons">
      <button class="wcreate" data-wcreate="${itemName}">${w.status === 'made' ? 'Set In Store' : 'Update Store'}</button>
      ${w.status !== 'made' ? `<button class="wdelete" data-wdelete="${itemName}">Remove Store</button>` : ''}
    </div>
  </article>`;
}

function ammoCard(a) {
  const itemName = escapeAttr(a.item_name || '');
  return `<article class="wcard ammo" data-ammo="${itemName}" data-item="${itemName}">
    <div class="wimg"><img src="${imgSrc(a.image)}" alt="${escapeAttr(a.label)}" onerror="this.style.opacity=0.2"></div>
    <div class="whead"><h4>${escapeHtml(a.label)}</h4>${statusBadge(a.status)}</div>
    <code class="whash">${escapeHtml(a.item_name || '')}</code>
    <div class="wfields">
      <label><span>Config Price</span><input data-afield="price" type="number" min="0" value="${Number(a.price) || 0}" disabled></label>
      <label><span>Stock</span><input data-afield="stock" type="number" value="${Number(a.stock ?? -1)}"></label>
      <label><span>Pack Size</span><input value="${Number(a.pack_size) || 1}" disabled></label>
      <label><span>Pickup Hash</span><input value="${escapeAttr(a.pickup_hash || '')}" disabled></label>
      <p class="ammo-damage-note wide">Ammo and price are config-controlled. Gun admin only saves stock and Store/Hidden.</p>
      <label class="wtoggle"><input data-afield="enabled" type="checkbox" ${a.status === 'store' ? 'checked' : ''}><span>In Store</span></label>
    </div>
    <div class="wbuttons">
      <button class="acreate" data-acreate="${itemName}">${a.status === 'made' ? 'Set In Store' : 'Update Store'}</button>
      ${a.status !== 'made' ? `<button class="wdelete" data-wdelete="${itemName}">Remove Store</button>` : ''}
    </div>
  </article>`;
}

function pickerSearch(list, group, search, groupKey = 'group') {
  let rows = list.filter(x => String(x[groupKey] || 'pistol').toLowerCase() === String(group || '').toLowerCase());
  const s = String(search || '').toLowerCase();
  if (s) rows = rows.filter(x => String(x.label || '').toLowerCase().includes(s) || String(x.item_name || '').toLowerCase().includes(s) || String(x.hash || '').toLowerCase().includes(s));
  return rows;
}

function weaponPickerView() {
  const groups = state.weaponGroups.length ? state.weaponGroups : ['pistol', 'smg', 'rifle', 'shotgun', 'sniper', 'machinegun'];
  if (!groups.includes(state.weaponGroup)) state.weaponGroup = groups[0] || 'pistol';
  const tabs = groups.map(g => `<button class="wgroup ${state.weaponGroup === g ? 'active' : ''}" data-wgroup="${escapeAttr(g)}">${escapeHtml(g).toUpperCase()}</button>`).join('');
  const items = pickerSearch(state.weaponPicker, state.weaponGroup, state.weaponSearch);
  return `<section class="weapon-picker">
    <div class="wp-head">
      <div><p class="eyebrow">ALL SERVER WEAPONS</p><h2>Set weapon stock and visibility</h2></div>
      <input id="weaponSearch" class="wp-search" placeholder="Search weapons..." value="${escapeAttr(state.weaponSearch)}">
    </div>
    <div class="wgroups">${tabs}</div>
    <div class="wgrid">${items.map(weaponCard).join('') || '<div class="empty">No weapons found. Create weapons in /cmweaponadmin first.</div>'}</div>
    <p class="creator-note">Gun admin lists every weapon from cm-weapons. Prices come from shared/config.lua; this admin only controls stock and In Store/Hidden.</p>
  </section>`;
}

function ammoPickerView() {
  const groups = state.ammoGroups.length ? state.ammoGroups : ['pistol', 'smg', 'rifle', 'mg', 'shotgun', 'sniper'];
  if (!groups.includes(state.ammoGroup)) state.ammoGroup = groups[0] || 'pistol';
  const tabs = groups.map(g => `<button class="wgroup ${state.ammoGroup === g ? 'active' : ''}" data-agroup="${escapeAttr(g)}">${escapeHtml(g).toUpperCase()}</button>`).join('');
  const items = pickerSearch(state.ammoPicker, state.ammoGroup, state.ammoSearch);
  return `<section class="weapon-picker">
    <div class="wp-head">
      <div><p class="eyebrow">ALL SERVER AMMO</p><h2>Set ammo stock and visibility</h2></div>
      <input id="ammoSearch" class="wp-search" placeholder="Search ammo..." value="${escapeAttr(state.ammoSearch)}">
    </div>
    <div class="wgroups">${tabs}</div>
    <div class="wgrid">${items.map(ammoCard).join('') || '<div class="empty">No ammo found. Create ammo in /cmweaponadmin first.</div>'}</div>
    <p class="creator-note">Gun admin lists every ammo item from cm-weapons. Prices come from shared/config.lua; this admin only controls stock and In Store/Hidden.</p>
  </section>`;
}

function armorCreator() {
  return `<section class="creator-panel">
    <div class="creator-head">
      <div><p class="eyebrow">CREATE STORE ARMOR</p><h2>Wearable Vest / Armor</h2></div>
      <span>Weapons/ammo are created in /cmweaponadmin</span>
    </div>
    <div class="creator-grid">
      <input type="hidden" id="newType" value="armor">
      <input type="hidden" id="newWeaponHash" value="">
      <input type="hidden" id="newComponent" value="9">
      <input type="hidden" id="newDrawable" value="">
      <input type="hidden" id="newTexture" value="0">
      <input type="hidden" id="newGender" value="both">
      <input type="hidden" id="newStock" value="-1">
      <input type="hidden" id="newItemName" value="">
      <label><span>Name</span><input id="newLabel" placeholder="Heavy Tactical Vest" /></label>
      <label><span>Price</span><input id="newPrice" type="number" min="0" value="1000" /></label>
      <label><span>Armor Health</span><input id="newArmor" type="number" min="0" max="100" value="50" /></label>
      ${accessFieldsHtml('public', '')}
    </div>
    <div class="creator-actions">
      <button id="captureVestBtn" class="ghost-action">Capture Vest (Clothing Studio)</button>
      <button id="createHiddenBtn" class="save secondary">Create Hidden</button>
      <button id="createStoreBtn" class="save">Create In Store</button>
    </div>
    <p class="creator-note">Gun and ammo creation moved to /cmweaponadmin. Use this only for wearable armor/vest store items.</p>
  </section>`;
}

/* ===== Admin: Manage NPCs (add a live clerk from the player's own position) ===== */
function npcRow(n) {
  return `<article class="npc-item" data-npcid="${escapeAttr(n.id)}">
    <div class="npc-summary">
      <h4>${escapeHtml(n.name)}</h4>
      <span class="npc-meta">${escapeHtml(n.label || 'Gun Store')} · ${escapeHtml(n.model || '')}</span>
      <code class="npc-coords">${Number(n.x).toFixed(1)}, ${Number(n.y).toFixed(1)}, ${Number(n.z).toFixed(1)}</code>
    </div>
    <button class="delete" data-npcdelete="${escapeAttr(n.id)}">Remove</button>
  </article>`;
}

function npcManagerView() {
  const list = Array.isArray(state.npcs) ? state.npcs : [];
  return `<section class="npc-manager">
    <div class="creator-head">
      <div><p class="eyebrow">MANAGE NPCS</p><h2>Add a gun store clerk here</h2></div>
      <span>Walk to where you want the clerk, fill this in, then click Add NPC Here</span>
    </div>
    <div class="creator-grid">
      <label><span>Name</span><input id="npcName" placeholder="Marcus Reed" value="${escapeAttr(state.npcName)}" /></label>
      <label><span>Shop Label (blip)</span><input id="npcLabel" placeholder="Gun Store" value="${escapeAttr(state.npcLabel)}" /></label>
      <label><span>Ped Model</span><input id="npcModel" placeholder="s_m_y_ammucity_01 (blank = default)" value="${escapeAttr(state.npcModel)}" /></label>
      <label><span>Scenario</span><input id="npcScenario" placeholder="WORLD_HUMAN_GUARD_STAND (blank = default)" value="${escapeAttr(state.npcScenario)}" /></label>
    </div>
    <div class="creator-actions">
      <button id="addNpcHereBtn" class="save">Add NPC Here</button>
    </div>
    <p class="creator-note">The NPC spawns at your exact position/heading, opens the normal cinematic dialog + store, and is saved so it survives a restart. Remove it below any time.</p>
    <div class="npc-list">${list.length ? list.map(npcRow).join('') : '<div class="empty">No custom NPCs yet.</div>'}</div>
  </section>`;
}

/* ===== Access control (Public / Gang Members / Law Org) shared by every
 * admin card + the armor creator. Fixed gang roster mirrors cm-gang's
 * Config.GangIds (marabunta/bloods/ballas/families/vagos never change). ===== */
const FIXED_GANGS = ['marabunta', 'bloods', 'ballas', 'families', 'vagos'];
function gangLabel(id) { return id ? id.charAt(0).toUpperCase() + id.slice(1) : id; }

function accessFieldsHtml(scope, gangId, itemName) {
  scope = scope || 'public';
  gangId = gangId || '';
  const nameAttr = itemName ? ` data-name="${escapeAttr(itemName)}"` : '';
  const scopeIdAttr = itemName ? '' : ' id="newAccessScope"';
  const gangIdAttr = itemName ? '' : ' id="newAccessGang"';
  const gangOptions = FIXED_GANGS.map(g => `<option value="${g}" ${gangId === g ? 'selected' : ''}>${gangLabel(g)}</option>`).join('');
  return `
    <label><span>Access</span>
      <select data-field="access_scope"${nameAttr}${scopeIdAttr}>
        <option value="public" ${scope === 'public' ? 'selected' : ''}>Public Store</option>
        <option value="gang" ${scope === 'gang' ? 'selected' : ''}>Gang Members</option>
        <option value="law" ${scope === 'law' ? 'selected' : ''}>Law Org (any)</option>
      </select>
    </label>
    <label><span>Gang (if Gang access)</span>
      <select data-field="access_gang_id"${nameAttr}${gangIdAttr}>
        <option value="">Any Gang</option>
        ${gangOptions}
      </select>
    </label>`;
}

function card(row) {
  if (state.mode === 'admin') return adminRow(row);
  const disabled = row.enabled === false ? ' disabled' : '';
  const badge = row.enabled === false ? 'Hidden' : row.item_type;
  return `<article class="card ${itemAccent(row)}${disabled}" data-name="${escapeAttr(row.item_name)}">
    <span class="badge">${escapeHtml(badge)}</span>
    <div class="image-box"><img src="${imgSrc(row.image)}" alt="${escapeAttr(row.label)}"></div>
    <h3>${escapeHtml(row.label)}</h3>
    <div class="meta"><span>${escapeHtml(typeLabel(row))}</span><strong>${money(row.price)}</strong></div>
    <p class="desc">${escapeHtml(row.description || 'Inventory item.')}</p>
    <div class="actions"><button class="buy cash" data-buy="cash" data-name="${escapeAttr(row.item_name)}">Buy Cash</button><button class="buy" data-buy="bank" data-name="${escapeAttr(row.item_name)}">Buy Bank</button></div>
  </article>`;
}

function adminRow(row) {
  const itemName = escapeAttr(row.item_name);
  if (row.item_type === 'weapon' || row.item_type === 'ammo') {
    return `<article class="admin-item${row.enabled ? '' : ' disabled'}" data-name="${itemName}" data-type="${escapeAttr(row.item_type)}">
      <div class="admin-preview"><span class="admin-type">${escapeHtml(row.item_type)}</span><img src="${imgSrc(row.image)}" alt="${escapeAttr(row.label)}"><small>${escapeHtml(row.item_name)}</small></div>
      <div class="admin-summary"><h3>${escapeHtml(row.label)}</h3><div class="meta"><span>${escapeHtml(typeLabel(row))}</span><strong>${money(row.price)}</strong></div><p class="desc">Source: cm-weapons + config price</p><span class="status ${row.enabled ? 'on' : 'off'}">${row.enabled ? 'Store' : 'Hidden'}</span></div>
      <div class="admin-fields">
        <label><span>Label</span><input value="${escapeAttr(row.label)}" disabled /></label>
        <label><span>Config Price</span><input data-field="price" data-name="${itemName}" type="number" min="0" value="${Number(row.price) || 0}" disabled /></label>
        <label><span>Stock</span><input data-field="stock" data-name="${itemName}" type="number" value="${Number(row.stock ?? -1)}" /></label>
        ${row.item_type === 'weapon'
      ? `<label><span>Damage</span><input value="${Number(row.damage) || 0}" disabled /></label><label><span>Ammo</span><input value="${escapeAttr(row.ammo_item || '')}" disabled /></label>`
      : `<label><span>Pack Size</span><input value="${Number(row.pack_size) || 1}" disabled /></label><label><span>Pickup Hash</span><input value="${escapeAttr(row.pickup_hash || '')}" disabled /></label>`}
        ${accessFieldsHtml(row.access_scope, row.access_gang_id, itemName)}
        <label class="wide"><span>Image from /cmweaponadmin</span><input data-field="image" data-name="${itemName}" value="${escapeAttr(row.image)}" disabled /></label>
        <label class="wide"><span>Description from cm-weapons config</span><textarea data-field="description" data-name="${itemName}" disabled>${escapeHtml(row.description || '')}</textarea></label>
      </div>
      <div class="admin-actions">
        <label class="admin-toggle"><input data-field="enabled" data-name="${itemName}" type="checkbox" ${row.enabled ? 'checked' : ''}/><span>Store</span></label>
        ${row.item_type === 'weapon' ? `<label class="admin-toggle banned-toggle"><input data-field="banned" data-name="${itemName}" type="checkbox" ${row.banned ? 'checked' : ''}/><span>Banned everywhere</span></label>` : ''}
        <button class="save" data-save="${itemName}">Save Store</button><button class="delete" data-delete="${itemName}">Remove Store</button>
      </div>
    </article>`;
  }

  return `<article class="admin-item${row.enabled ? '' : ' disabled'}" data-name="${itemName}" data-type="armor">
    <div class="admin-preview"><span class="admin-type">armor</span><img src="${imgSrc(row.image)}" alt="${escapeAttr(row.label)}"><small>${escapeHtml(row.item_name)}</small></div>
    <div class="admin-summary"><h3>${escapeHtml(row.label)}</h3><div class="meta"><span>${escapeHtml(typeLabel(row))}</span><strong>${money(row.price)}</strong></div><p class="desc">${escapeHtml(row.description || '')}</p><span class="status ${row.enabled ? 'on' : 'off'}">${row.enabled ? 'Store' : 'Hidden'}</span></div>
    <div class="admin-fields">
      <label><span>Label</span><input data-field="label" data-name="${itemName}" value="${escapeAttr(row.label)}" /></label>
      <label><span>Config Price</span><input data-field="price" data-name="${itemName}" type="number" min="0" value="${Number(row.price) || 0}" disabled /></label>
      <label><span>Armor</span><input data-field="armor_value" data-name="${itemName}" type="number" min="0" max="100" value="${Number(row.armor_value || row.armorValue) || 0}" /></label>
      <label><span>Component</span><input data-field="component_id" data-name="${itemName}" type="number" value="${Number(row.component_id || row.componentId || 9)}" /></label>
      <label><span>Drawable</span><input data-field="drawable_id" data-name="${itemName}" type="number" value="${row.drawable_id ?? row.drawableId ?? ''}" /></label>
      <label><span>Texture</span><input data-field="texture_id" data-name="${itemName}" type="number" value="${Number(row.texture_id || row.textureId || 0)}" /></label>
      <label><span>Gender</span><input data-field="gender" data-name="${itemName}" value="${escapeAttr(row.gender || 'both')}" /></label>
      <label><span>Stock</span><input data-field="stock" data-name="${itemName}" type="number" value="${Number(row.stock ?? -1)}" /></label>
      ${accessFieldsHtml(row.access_scope, row.access_gang_id, itemName)}
      <label class="wide"><span>Image Path</span><input data-field="image" data-name="${itemName}" value="${escapeAttr(row.image)}" /></label>
      <label class="wide file-line"><span>Replace Image From PC</span><input data-image-file="${itemName}" type="file" accept="image/png,image/jpeg,image/webp" /></label>
      <label class="wide"><span>Description</span><textarea data-field="description" data-name="${itemName}">${escapeHtml(row.description || '')}</textarea></label>
    </div>
    <div class="admin-actions"><label class="admin-toggle"><input data-field="enabled" data-name="${itemName}" type="checkbox" ${row.enabled ? 'checked' : ''}/><span>Store</span></label><button class="save" data-save="${itemName}">Save</button><button class="delete" data-delete="${itemName}">Delete</button></div>
  </article>`;
}

function render() {
  const admin = state.mode === 'admin';
  titleEl.textContent = admin ? 'Gun Store Admin' : 'Gun Store';
  modeLabel.textContent = admin ? 'STORE ADMIN' : 'STORE';
  app.classList.toggle('admin-mode', admin);
  app.classList.toggle('store-mode', !admin);
  document.querySelectorAll('.tab').forEach(btn => btn.classList.toggle('active', btn.dataset.filter === state.filter));

  if (!admin) { itemsEl.innerHTML = storeView(); return; }
  if (admin && state.filter === 'weapon') { itemsEl.innerHTML = weaponPickerView(); return; }
  if (admin && state.filter === 'ammo') { itemsEl.innerHTML = ammoPickerView(); return; }
  if (admin && state.filter === 'npc') { itemsEl.innerHTML = npcManagerView(); return; }

  const rows = visibleRows();
  const creator = admin && (state.filter === 'armor' || state.filter === 'all') ? armorCreator() : '';
  itemsEl.innerHTML = creator + (rows.length ? rows.map(card).join('') : '<div class="empty">No items available</div>');
}

function resetSelectionAmmoState() {
  state.addAmmo = false;
  state.ammoRounds = DEFAULT_BUNDLE;
  state.ammoQty = DEFAULT_BUNDLE;
}

function open(data) {
  state.mode = data.mode || 'store';
  state.catalog = Array.isArray(data.catalog) ? data.catalog : [];
  state.busy = false;
  state.ammoQty = 1;
  state.weaponAmmo = {};
  resetSelectionAmmoState();
  if (state.mode !== 'admin') state.filter = 'all';
  if (!state.catalog.some(x => x.item_name === state.selectedName)) state.selectedName = '';
  if (state.mode === 'admin' && state.filter === 'all') state.filter = 'weapon';
  app.classList.remove('hidden');
  render();
  if (state.mode === 'admin' && state.filter === 'weapon') post('adminRequestWeaponPicker', {});
  if (state.mode === 'admin' && state.filter === 'ammo') post('adminRequestAmmoPicker', {});
}

function close() {
  app.classList.add('hidden');
  app.classList.remove('admin-mode');
  state.busy = false;
}

function rowData(itemName) {
  const item = Array.from(document.querySelectorAll('.card, .admin-item')).find(el => el.dataset.name === itemName);
  if (!item) return null;
  const get = f => item.querySelector(`[data-field="${f}"]`);
  return {
    item_name: itemName,
    item_type: item.dataset.type || '',
    label: get('label')?.value || itemName,
    price: Number(get('price')?.value || 0),
    enabled: get('enabled')?.checked === true,
    image: get('image')?.value || '',
    description: get('description')?.value || '',
    armor_value: Number(get('armor_value')?.value || 0),
    stock: Number(get('stock')?.value ?? -1),
    component_id: Number(get('component_id')?.value || 9),
    drawable_id: get('drawable_id')?.value === '' ? null : Number(get('drawable_id')?.value),
    texture_id: Number(get('texture_id')?.value || 0),
    gender: get('gender')?.value || 'both',
    access_scope: get('access_scope')?.value || 'public',
    access_gang_id: get('access_gang_id')?.value || '',
    banned: get('banned')?.checked === true
  };
}

function readFileAsData(file) { return new Promise((resolve) => { if (!file) return resolve(''); const r = new FileReader(); r.onload = () => resolve(String(r.result || '')); r.onerror = () => resolve(''); r.readAsDataURL(file); }); }

async function createArmorData(enabled) {
  // Empty string here means "Capture Vest" was never run (or didn't return a
  // component) -- must stay null, NOT coerce to 0. Drawable 0 is itself a
  // real, valid GTA component variation (usually "nothing equipped" for the
  // Accessories slot armor uses), so silently defaulting an un-captured vest
  // to drawable_id=0 makes it LOOK captured while actually just clearing
  // whatever the player is wearing there -- no visible vest ever appears,
  // even though armor value still applies. This was the actual bug behind
  // "gives shield but doesn't put a vest on the body."
  const drawableRaw = document.getElementById('newDrawable')?.value ?? '';
  const hasCapturedLook = drawableRaw !== '';

  if (!hasCapturedLook) {
    const proceed = await cmConfirm(
      'No vest look was captured (click "Capture Vest" first to attach one). ' +
      'This item will only give armor value — it will not visually equip anything. Create it anyway?',
      { title: 'No vest look captured', confirmText: 'Create Anyway', danger: true }
    );
    if (!proceed) return;
  }

  const data = {
    item_type: 'armor',
    label: document.getElementById('newLabel')?.value || '',
    item_name: document.getElementById('newItemName')?.value || '',
    price: Number(document.getElementById('newPrice')?.value || 0),
    armor_value: Number(document.getElementById('newArmor')?.value || 0),
    stock: Number(document.getElementById('newStock')?.value ?? -1),
    description: document.getElementById('newDesc')?.value || '',
    image: document.getElementById('newImage')?.value || '',
    component_id: Number(document.getElementById('newComponent')?.value || 9),
    drawable_id: hasCapturedLook ? Number(drawableRaw) : null,
    texture_id: Number(document.getElementById('newTexture')?.value || 0),
    gender: document.getElementById('newGender')?.value || 'both',
    access_scope: document.getElementById('newAccessScope')?.value || 'public',
    access_gang_id: document.getElementById('newAccessGang')?.value || '',
    enabled,
  };
  if (!data.image) data.imageData = state.capturedArmorImage || state.imageData || '';
  post('adminCreateItem', data);
  state.imageData = '';
  state.capturedArmorImage = '';
}

function prefillArmorForm(p) {
  p = p || {};
  state.capturedArmorImage = p.imageData || p.image || '';
  if (state.filter === 'weapon' || state.filter === 'ammo') state.filter = 'armor';
  render();
  const set = (id, v) => { const el = document.getElementById(id); if (el != null && v != null && v !== '') el.value = v; };
  set('newComponent', p.componentId ?? p.component_id ?? 9);
  set('newDrawable', p.drawableId ?? p.drawable);
  set('newTexture', p.textureId ?? p.texture ?? 0);
  set('newGender', p.gender || 'both');
  if (p.armorValue) set('newArmor', p.armorValue);
  const note = document.querySelector('.creator-note');
  if (note) note.textContent = 'Vest captured ✓ — set name, price, and armor health, then click Create In Store or Create Hidden.';
}

/* ===== message bridge ===== */
window.addEventListener('message', (event) => {
  const msg = event.data || {};
  if (msg.action === 'open') open(msg.data || {});
  if (msg.action === 'close') close();
  if (msg.action === 'purchaseResult') state.busy = false;
  if (msg.action === 'captureFlash') document.body.classList.toggle('capture-flash', msg.data?.show === true);
  if (msg.action === 'prefillArmor') prefillArmorForm(msg.data || {});
  if (msg.action === 'weaponPicker') { state.weaponPicker = Array.isArray(msg.data?.list) ? msg.data.list : []; state.weaponGroups = Array.isArray(msg.data?.groups) ? msg.data.groups : state.weaponGroups; if (state.mode === 'admin' && state.filter === 'weapon') render(); }
  if (msg.action === 'ammoPicker') { state.ammoPicker = Array.isArray(msg.data?.list) ? msg.data.list : []; state.ammoGroups = Array.isArray(msg.data?.groups) ? msg.data.groups : state.ammoGroups; if (state.mode === 'admin' && state.filter === 'ammo') render(); }
  if (msg.action === 'npcAdminList') { state.npcs = Array.isArray(msg.data?.list) ? msg.data.list : []; if (state.mode === 'admin' && state.filter === 'npc') render(); }
  if (msg.action === 'weaponAmmo') {
    const d = msg.data || {};
    if (d.weapon) {
      state.weaponAmmo[d.weapon] = d.ammo || null;
      // only re-render if the affected weapon is the one on screen
      if (state.mode !== 'admin' && state.selectedName === d.weapon) render();
    }
  }
});

/* ===== clicks ===== */
document.addEventListener('click', async (e) => {
  const tab = e.target.closest('.tab');
  if (tab) {
    state.filter = tab.dataset.filter || 'all';
    if (state.mode === 'admin' && state.filter === 'weapon') post('adminRequestWeaponPicker', {});
    if (state.mode === 'admin' && state.filter === 'ammo') post('adminRequestAmmoPicker', {});
    if (state.mode === 'admin' && state.filter === 'npc') post('adminRequestNpcs', {});
    render();
    return;
  }

  if (e.target.id === 'addNpcHereBtn') {
    const name = document.getElementById('npcName')?.value.trim() || '';
    if (!name) { document.getElementById('npcName')?.focus(); return; }
    state.npcName = name;
    state.npcLabel = document.getElementById('npcLabel')?.value.trim() || 'Gun Store';
    state.npcModel = document.getElementById('npcModel')?.value.trim() || '';
    state.npcScenario = document.getElementById('npcScenario')?.value.trim() || '';
    post('adminCreateNpcHere', { name: state.npcName, label: state.npcLabel, model: state.npcModel, scenario: state.npcScenario });
    state.npcName = '';
    return;
  }

  const npcDelete = e.target.closest('[data-npcdelete]');
  if (npcDelete) {
    const id = npcDelete.dataset.npcdelete;
    if (id && await confirmDelete('Remove this NPC and its gun store?')) post('adminDeleteNpc', { id: Number(id) });
    return;
  }

  const wgroup = e.target.closest('[data-wgroup]');
  if (wgroup) { state.weaponGroup = wgroup.dataset.wgroup; render(); return; }
  const agroup = e.target.closest('[data-agroup]');
  if (agroup) { state.ammoGroup = agroup.dataset.agroup; render(); return; }

  const wcreate = e.target.closest('[data-wcreate]');
  if (wcreate) {
    const card = wcreate.closest('.wcard');
    const get = f => card.querySelector(`[data-wfield="${f}"]`);
    const itemName = wcreate.dataset.wcreate || card?.dataset.item || '';
    const source = state.weaponPicker.find(x => String(x.item_name || '').toLowerCase() === String(itemName).toLowerCase()) || {};
    post('adminCreateWeapon', {
      item_name: itemName, itemName,
      weapon_hash: source.weapon_hash || source.hash || '', weaponHash: source.weapon_hash || source.hash || '',
      label: source.label || itemName, group: source.group || 'pistol',
      ammo_item: source.ammo_item || source.ammo || '', ammoItem: source.ammo_item || source.ammo || '',
      damage: Number(source.damage || 0),
      magazine_size: Number(source.magazine_size || source.magazineSize || 0), magazineSize: Number(source.magazine_size || source.magazineSize || 0),
      image: source.image || '', description: source.description || '',
      price: Number(get('price')?.value || 0), stock: Number(get('stock')?.value ?? -1), enabled: get('enabled')?.checked === true,
    });
    return;
  }

  const acreate = e.target.closest('[data-acreate]');
  if (acreate) {
    const card = acreate.closest('.wcard');
    const get = f => card.querySelector(`[data-afield="${f}"]`);
    const itemName = acreate.dataset.acreate || card?.dataset.item || '';
    const source = state.ammoPicker.find(x => String(x.item_name || '').toLowerCase() === String(itemName).toLowerCase()) || {};
    post('adminCreateAmmo', {
      item_name: itemName, itemName, label: source.label || itemName,
      ammo_key: source.ammo_key || source.group || '', ammoKey: source.ammo_key || source.group || '',
      pickup_hash: Number(source.pickup_hash || 0), pickupHash: Number(source.pickup_hash || 0),
      drop_model: source.drop_model || '', dropModel: source.drop_model || '',
      pack_size: Number(source.pack_size || source.packSize || 1), packSize: Number(source.pack_size || source.packSize || 1),
      image: source.image || '', description: source.description || '',
      price: Number(get('price')?.value || 0), stock: Number(get('stock')?.value ?? -1), enabled: get('enabled')?.checked === true,
    });
    return;
  }

  const wdelete = e.target.closest('[data-wdelete]');
  if (wdelete) {
    const name = wdelete.dataset.wdelete || '';
    if (name && await confirmDelete(`Remove ${name} from this gun store? It will stay in cm-weapons.`)) post('adminDeleteItem', { item_name: name });
    return;
  }

  // catalog dropdown: toggle a weapon-type group open/closed
  const groupHead = e.target.closest('[data-group]');
  if (groupHead) {
    const g = groupHead.dataset.group;
    state.collapsedGroups[g] = !state.collapsedGroups[g];
    render();
    return;
  }

  const select = e.target.closest('[data-select]');
  if (select) { state.selectedName = select.dataset.select || ''; resetSelectionAmmoState(); render(); return; }

  // standalone ammo quantity stepper (ammo detail panel)
  const ammoQtyBtn = e.target.closest('[data-ammoqty]');
  if (ammoQtyBtn) {
    state.ammoQty = clampRounds((Number(state.ammoQty) || DEFAULT_BUNDLE) + Number(ammoQtyBtn.dataset.ammoqty || 0));
    render();
    return;
  }

  // ammo rounds stepper (weapon add-on)
  const roundsBtn = e.target.closest('[data-rounds]');
  if (roundsBtn) {
    state.ammoRounds = clampRounds((Number(state.ammoRounds) || DEFAULT_BUNDLE) + Number(roundsBtn.dataset.rounds || 0));
    render();
    return;
  }

  const buy = e.target.closest('[data-buy]');
  if (buy && !state.busy) {
    state.busy = true;
    const row = state.catalog.find(x => x.item_name === buy.dataset.name) || {};
    const payload = { item_name: buy.dataset.name, method: buy.dataset.buy };
    if (row.item_type === 'ammo') {
      const qtyEl = document.getElementById('ammoQty');
      payload.quantity = clampRounds(Number(qtyEl?.value || state.ammoQty || 1));
    } else if (row.item_type === 'weapon' && state.addAmmo) {
      const ammo = state.weaponAmmo[row.item_name];
      if (ammo && ammo.buyable) {
        const roundsEl = document.getElementById('ammoRounds');
        payload.ammo_rounds = clampRounds(Number(roundsEl?.value || state.ammoRounds || DEFAULT_BUNDLE));
      }
    }
    post('buyItem', payload);
    return;
  }

  const save = e.target.closest('[data-save]');
  if (save) { const data = rowData(save.dataset.save); if (data) post('adminSaveItem', data); return; }
  const del = e.target.closest('[data-delete]');
  if (del) {
    const name = del.dataset.delete || '';
    if (name && await confirmDelete(`Remove ${name} from this gun store? Weapon/ammo stays in cm-weapons.`)) post('adminDeleteItem', { item_name: name });
    return;
  }
  if (e.target.id === 'createStoreBtn') { createArmorData(true); return; }
  if (e.target.id === 'createHiddenBtn') { createArmorData(false); return; }
  if (e.target.id === 'captureVestBtn') { post('adminOpenVestCapture', {}); return; }
});

/* ===== change: toggle add-ammo checkbox ===== */
document.addEventListener('change', async (e) => {
  if (e.target.id === 'addAmmoToggle') {
    state.addAmmo = e.target.checked === true;
    render();
    return;
  }
  const fileInput = e.target.closest('[data-image-file]');
  if (fileInput) { const imageData = await readFileAsData(fileInput.files?.[0]); if (imageData) post('adminSaveImage', { item_name: fileInput.dataset.imageFile, imageData }); }
});

/* ===== input: live search + numeric fields (no full re-render on keystroke) ===== */
document.addEventListener('input', (e) => {
  if (e.target.id === 'weaponSearch') {
    state.weaponSearch = e.target.value || '';
    const grid = document.querySelector('.wgrid');
    if (grid) grid.innerHTML = pickerSearch(state.weaponPicker, state.weaponGroup, state.weaponSearch).map(weaponCard).join('') || '<div class="empty">No weapons match</div>';
  }
  if (e.target.id === 'ammoSearch') {
    state.ammoSearch = e.target.value || '';
    const grid = document.querySelector('.wgrid');
    if (grid) grid.innerHTML = pickerSearch(state.ammoPicker, state.ammoGroup, state.ammoSearch).map(ammoCard).join('') || '<div class="empty">No ammo match</div>';
  }
  if (e.target.id === 'ammoRounds') {
    state.ammoRounds = clampRounds(e.target.value || DEFAULT_BUNDLE);
    // update the totals without stealing input focus
    const ammo = state.weaponAmmo[state.selectedName];
    const totalEl = document.querySelector('.ammo-addon-total');
    if (ammo && ammo.buyable && totalEl) totalEl.textContent = `+${money((Number(ammo.price) || 0) * state.ammoRounds)}`;
    const row = state.catalog.find(x => x.item_name === state.selectedName);
    const grandEl = document.querySelector('.detail-total strong');
    if (row && ammo && ammo.buyable && grandEl) {
      grandEl.textContent = money((Number(row.price) || 0) + (Number(ammo.price) || 0) * state.ammoRounds);
    }
  }
  if (e.target.id === 'ammoQty') {
    state.ammoQty = clampRounds(e.target.value || DEFAULT_BUNDLE);
    // live total update without re-rendering (keeps input focus)
    const row = state.catalog.find(x => x.item_name === state.selectedName);
    const grandEl = document.querySelector('.detail-total strong');
    if (row && grandEl) grandEl.textContent = money((Number(row.price) || 0) * state.ammoQty);
  }
});

closeBtn.addEventListener('click', () => post('close'));
refreshBtn.addEventListener('click', () => post('refreshCatalog'));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') post('close'); });
