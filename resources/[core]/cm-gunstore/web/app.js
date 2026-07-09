const app = document.getElementById('app');
const itemsEl = document.getElementById('items');
const titleEl = document.getElementById('title');
const modeLabel = document.getElementById('modeLabel');
const closeBtn = document.getElementById('closeBtn');
const refreshBtn = document.getElementById('refreshBtn');
const npcDialog = document.getElementById('npcDialog');
const dialogName = document.getElementById('dialogName');
const dialogTitle = document.getElementById('dialogTitle');
const dialogStoreBtn = document.getElementById('dialogStoreBtn');
const dialogCloseBtn = document.getElementById('dialogCloseBtn');
const interactionPrompt = document.getElementById('interactionPrompt');
const interactionKey = document.getElementById('interactionKey');
const interactionName = document.getElementById('interactionName');
const interactionTitle = document.getElementById('interactionTitle');
const interactionSubtitle = document.getElementById('interactionSubtitle');

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
  ammoSearch: ''
};

function resName() { return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-gunstore'; }
function post(path, body = {}) { return fetch(`https://${resName()}/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => null); }
function money(n) { n = Number(n) || 0; return `$${n.toLocaleString()}`; }
function escapeAttr(v) { return String(v ?? '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function escapeHtml(v) { return String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
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
  if (row.item_type === 'ammo') return `${row.pack_size || 1} Rounds${row.ammo_key ? ` • ${row.ammo_key}` : ''}`;
  if (row.item_type === 'armor') return `${row.armor_value || row.armorValue || 0} Armor`;
  const dmg = Number(row.damage || 0);
  return `${row.ammo_item ? `Uses ${row.ammo_item}` : 'Weapon'}${dmg ? ` • ${dmg} Damage` : ''}`;
}
function itemAccent(row) { return row.item_type === 'ammo' ? 'ammo' : row.item_type === 'armor' ? 'armor' : 'weapon'; }
function visibleRows() { return state.catalog.filter(row => (state.filter === 'all' || row.item_type === state.filter) && (state.mode === 'admin' || row.enabled !== false)); }

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
      <label><span>Price</span><input data-wfield="price" type="number" min="0" value="${Number(w.price)||0}"></label>
      <label><span>Stock</span><input data-wfield="stock" type="number" value="${Number(w.stock ?? -1)}"></label>
      <label><span>Damage</span><input value="${Number(w.damage)||0}" disabled></label>
      <label><span>Ammo</span><input value="${escapeAttr(w.ammo_item || w.ammo || '')}" disabled></label>
      <p class="ammo-damage-note wide">Weapon and ammo rules come from cm-weapons. Gun store only saves price, stock and store visibility.</p>
      <label class="wtoggle"><input data-wfield="enabled" type="checkbox" ${w.status==='store'?'checked':''}><span>In Store</span></label>
    </div>
    <div class="wbuttons">
      <button class="wcreate" data-wcreate="${itemName}">${w.status==='made'?'Set In Store':'Update Store'}</button>
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
      <label><span>Price</span><input data-afield="price" type="number" min="0" value="${Number(a.price)||0}"></label>
      <label><span>Stock</span><input data-afield="stock" type="number" value="${Number(a.stock ?? -1)}"></label>
      <label><span>Pack Size</span><input value="${Number(a.pack_size)||1}" disabled></label>
      <label><span>Pickup Hash</span><input value="${escapeAttr(a.pickup_hash || '')}" disabled></label>
      <p class="ammo-damage-note wide">Ammo name, pack size and pickup hash come from cm-weapons. Use /cmweaponadmin to edit them.</p>
      <label class="wtoggle"><input data-afield="enabled" type="checkbox" ${a.status==='store'?'checked':''}><span>In Store</span></label>
    </div>
    <div class="wbuttons">
      <button class="acreate" data-acreate="${itemName}">${a.status==='made'?'Set In Store':'Update Store'}</button>
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
  const groups = state.weaponGroups.length ? state.weaponGroups : ['pistol','smg','rifle','shotgun','sniper','heavy'];
  if (!groups.includes(state.weaponGroup)) state.weaponGroup = groups[0] || 'pistol';
  const tabs = groups.map(g => `<button class="wgroup ${state.weaponGroup === g ? 'active' : ''}" data-wgroup="${escapeAttr(g)}">${escapeHtml(g).toUpperCase()}</button>`).join('');
  const items = pickerSearch(state.weaponPicker, state.weaponGroup, state.weaponSearch);
  return `<section class="weapon-picker">
    <div class="wp-head">
      <div><p class="eyebrow">ALL SERVER WEAPONS</p><h2>Set weapon store price and visibility</h2></div>
      <input id="weaponSearch" class="wp-search" placeholder="Search weapons..." value="${escapeAttr(state.weaponSearch)}">
    </div>
    <div class="wgroups">${tabs}</div>
    <div class="wgrid">${items.map(weaponCard).join('') || '<div class="empty">No weapons found. Create weapons in /cmweaponadmin first.</div>'}</div>
    <p class="creator-note">Gun admin lists every weapon from cm-weapons. It only controls sale price, stock and In Store/Hidden.</p>
  </section>`;
}

function ammoPickerView() {
  const groups = state.ammoGroups.length ? state.ammoGroups : ['pistol','smg','rifle','mg','shotgun','sniper'];
  if (!groups.includes(state.ammoGroup)) state.ammoGroup = groups[0] || 'pistol';
  const tabs = groups.map(g => `<button class="wgroup ${state.ammoGroup === g ? 'active' : ''}" data-agroup="${escapeAttr(g)}">${escapeHtml(g).toUpperCase()}</button>`).join('');
  const items = pickerSearch(state.ammoPicker, state.ammoGroup, state.ammoSearch);
  return `<section class="weapon-picker">
    <div class="wp-head">
      <div><p class="eyebrow">ALL SERVER AMMO</p><h2>Set ammo store price and visibility</h2></div>
      <input id="ammoSearch" class="wp-search" placeholder="Search ammo..." value="${escapeAttr(state.ammoSearch)}">
    </div>
    <div class="wgroups">${tabs}</div>
    <div class="wgrid">${items.map(ammoCard).join('') || '<div class="empty">No ammo found. Create ammo in /cmweaponadmin first.</div>'}</div>
    <p class="creator-note">Gun admin lists every ammo item from cm-weapons. It only controls sale price, stock and In Store/Hidden.</p>
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
      <input type="hidden" id="newDrawable" value="0">
      <input type="hidden" id="newTexture" value="0">
      <input type="hidden" id="newGender" value="both">
      <input type="hidden" id="newStock" value="-1">
      <input type="hidden" id="newItemName" value="">
      <label><span>Name</span><input id="newLabel" placeholder="Heavy Tactical Vest" /></label>
      <label><span>Price</span><input id="newPrice" type="number" min="0" value="1000" /></label>
      <label><span>Armor Health</span><input id="newArmor" type="number" min="0" max="100" value="50" /></label>
    </div>
    <div class="creator-actions">
      <button id="captureVestBtn" class="ghost-action">Capture Vest (Clothing Studio)</button>
      <button id="createHiddenBtn" class="save secondary">Create Hidden</button>
      <button id="createStoreBtn" class="save">Create In Store</button>
    </div>
    <p class="creator-note">Gun and ammo creation moved to /cmweaponadmin. Use this only for wearable armor/vest store items.</p>
  </section>`;
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
      <div class="admin-summary"><h3>${escapeHtml(row.label)}</h3><div class="meta"><span>${escapeHtml(typeLabel(row))}</span><strong>${money(row.price)}</strong></div><p class="desc">Source: cm-weapons</p><span class="status ${row.enabled ? 'on' : 'off'}">${row.enabled ? 'Store' : 'Hidden'}</span></div>
      <div class="admin-fields">
        <label><span>Label</span><input value="${escapeAttr(row.label)}" disabled /></label>
        <label><span>Price</span><input data-field="price" data-name="${itemName}" type="number" min="0" value="${Number(row.price) || 0}" /></label>
        <label><span>Stock</span><input data-field="stock" data-name="${itemName}" type="number" value="${Number(row.stock ?? -1)}" /></label>
        ${row.item_type === 'weapon'
          ? `<label><span>Damage</span><input value="${Number(row.damage) || 0}" disabled /></label><label><span>Ammo</span><input value="${escapeAttr(row.ammo_item || '')}" disabled /></label>`
          : `<label><span>Pack Size</span><input value="${Number(row.pack_size) || 1}" disabled /></label><label><span>Pickup Hash</span><input value="${escapeAttr(row.pickup_hash || '')}" disabled /></label>`}
        <label class="wide"><span>Store Image Override</span><input data-field="image" data-name="${itemName}" value="${escapeAttr(row.image)}" /></label>
        <label class="wide"><span>Store Description Override</span><textarea data-field="description" data-name="${itemName}">${escapeHtml(row.description || '')}</textarea></label>
      </div>
      <div class="admin-actions"><label class="admin-toggle"><input data-field="enabled" data-name="${itemName}" type="checkbox" ${row.enabled ? 'checked' : ''}/><span>Store</span></label><button class="save" data-save="${itemName}">Save Store</button><button class="delete" data-delete="${itemName}">Remove Store</button></div>
    </article>`;
  }

  return `<article class="admin-item${row.enabled ? '' : ' disabled'}" data-name="${itemName}" data-type="armor">
    <div class="admin-preview"><span class="admin-type">armor</span><img src="${imgSrc(row.image)}" alt="${escapeAttr(row.label)}"><small>${escapeHtml(row.item_name)}</small></div>
    <div class="admin-summary"><h3>${escapeHtml(row.label)}</h3><div class="meta"><span>${escapeHtml(typeLabel(row))}</span><strong>${money(row.price)}</strong></div><p class="desc">${escapeHtml(row.description || '')}</p><span class="status ${row.enabled ? 'on' : 'off'}">${row.enabled ? 'Store' : 'Hidden'}</span></div>
    <div class="admin-fields">
      <label><span>Label</span><input data-field="label" data-name="${itemName}" value="${escapeAttr(row.label)}" /></label>
      <label><span>Price</span><input data-field="price" data-name="${itemName}" type="number" min="0" value="${Number(row.price) || 0}" /></label>
      <label><span>Armor</span><input data-field="armor_value" data-name="${itemName}" type="number" min="0" max="100" value="${Number(row.armor_value || row.armorValue) || 0}" /></label>
      <label><span>Component</span><input data-field="component_id" data-name="${itemName}" type="number" value="${Number(row.component_id || row.componentId || 9)}" /></label>
      <label><span>Drawable</span><input data-field="drawable_id" data-name="${itemName}" type="number" value="${row.drawable_id ?? row.drawableId ?? ''}" /></label>
      <label><span>Texture</span><input data-field="texture_id" data-name="${itemName}" type="number" value="${Number(row.texture_id || row.textureId || 0)}" /></label>
      <label><span>Gender</span><input data-field="gender" data-name="${itemName}" value="${escapeAttr(row.gender || 'both')}" /></label>
      <label><span>Stock</span><input data-field="stock" data-name="${itemName}" type="number" value="${Number(row.stock ?? -1)}" /></label>
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
  document.querySelectorAll('.tab').forEach(btn => btn.classList.toggle('active', btn.dataset.filter === state.filter));

  if (admin && state.filter === 'weapon') { itemsEl.innerHTML = weaponPickerView(); return; }
  if (admin && state.filter === 'ammo') { itemsEl.innerHTML = ammoPickerView(); return; }

  const rows = visibleRows();
  const creator = admin && (state.filter === 'armor' || state.filter === 'all') ? armorCreator() : '';
  itemsEl.innerHTML = creator + (rows.length ? rows.map(card).join('') : '<div class="empty">No items available</div>');
}

function setInteraction(data = {}) { if (!data.show) { interactionPrompt.classList.add('hidden'); return; } interactionKey.textContent = data.key || 'E'; interactionName.textContent = data.clerkName || 'Gun Store Clerk'; interactionTitle.textContent = data.title || 'Talk to Clerk'; interactionSubtitle.textContent = data.subtitle || 'Browse weapons, ammo, and armor'; interactionPrompt.classList.remove('hidden'); }
function open(data) { interactionPrompt.classList.add('hidden'); state.mode = data.mode || 'store'; state.catalog = Array.isArray(data.catalog) ? data.catalog : []; state.busy = false; npcDialog.classList.add('hidden'); if (state.mode === 'admin' && state.filter === 'all') state.filter = 'weapon'; app.classList.remove('hidden'); render(); if (state.mode === 'admin' && state.filter === 'weapon') post('adminRequestWeaponPicker', {}); if (state.mode === 'admin' && state.filter === 'ammo') post('adminRequestAmmoPicker', {}); }
function openDialog(data = {}) { interactionPrompt.classList.add('hidden'); state.mode = 'dialog'; state.busy = false; app.classList.add('hidden'); app.classList.remove('admin-mode'); dialogName.textContent = data.clerkName || 'Gun Store Clerk'; dialogTitle.textContent = data.title || 'How can I help you today?'; dialogStoreBtn.textContent = data.optionStore || 'Show me what you have got'; dialogCloseBtn.textContent = data.optionClose || 'No thanks'; npcDialog.classList.remove('hidden'); }
function close() { interactionPrompt.classList.add('hidden'); npcDialog.classList.add('hidden'); app.classList.add('hidden'); app.classList.remove('admin-mode'); state.busy = false; }

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
    gender: get('gender')?.value || 'both'
  };
}

function readFileAsData(file) { return new Promise((resolve) => { if (!file) return resolve(''); const r = new FileReader(); r.onload = () => resolve(String(r.result || '')); r.onerror = () => resolve(''); r.readAsDataURL(file); }); }
async function createArmorData(enabled) {
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
    drawable_id: Number(document.getElementById('newDrawable')?.value || 0),
    texture_id: Number(document.getElementById('newTexture')?.value || 0),
    gender: document.getElementById('newGender')?.value || 'both',
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

window.addEventListener('message', (event) => {
  const msg = event.data || {};
  if (msg.action === 'open') open(msg.data || {});
  if (msg.action === 'dialog') openDialog(msg.data || {});
  if (msg.action === 'close') close();
  if (msg.action === 'purchaseResult') state.busy = false;
  if (msg.action === 'interaction') setInteraction(msg.data || {});
  if (msg.action === 'captureFlash') document.body.classList.toggle('capture-flash', msg.data?.show === true);
  if (msg.action === 'prefillArmor') prefillArmorForm(msg.data || {});
  if (msg.action === 'weaponPicker') { state.weaponPicker = Array.isArray(msg.data?.list) ? msg.data.list : []; state.weaponGroups = Array.isArray(msg.data?.groups) ? msg.data.groups : state.weaponGroups; if (state.mode === 'admin' && state.filter === 'weapon') render(); }
  if (msg.action === 'ammoPicker') { state.ammoPicker = Array.isArray(msg.data?.list) ? msg.data.list : []; state.ammoGroups = Array.isArray(msg.data?.groups) ? msg.data.groups : state.ammoGroups; if (state.mode === 'admin' && state.filter === 'ammo') render(); }
});

document.addEventListener('click', async (e) => {
  const tab = e.target.closest('.tab');
  if (tab) {
    state.filter = tab.dataset.filter || 'all';
    if (state.mode === 'admin' && state.filter === 'weapon') post('adminRequestWeaponPicker', {});
    if (state.mode === 'admin' && state.filter === 'ammo') post('adminRequestAmmoPicker', {});
    render();
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
    // Send the cm-weapons row too. This lets the server save the store row even if an export cache is stale for one tick.
    post('adminCreateWeapon', {
      item_name: itemName,
      itemName,
      weapon_hash: source.weapon_hash || source.hash || '',
      weaponHash: source.weapon_hash || source.hash || '',
      label: source.label || itemName,
      group: source.group || 'pistol',
      ammo_item: source.ammo_item || source.ammo || '',
      ammoItem: source.ammo_item || source.ammo || '',
      damage: Number(source.damage || 0),
      magazine_size: Number(source.magazine_size || source.magazineSize || 0),
      magazineSize: Number(source.magazine_size || source.magazineSize || 0),
      image: source.image || '',
      description: source.description || '',
      price: Number(get('price')?.value || 0),
      stock: Number(get('stock')?.value ?? -1),
      enabled: get('enabled')?.checked === true,
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
      item_name: itemName,
      itemName,
      label: source.label || itemName,
      ammo_key: source.ammo_key || source.group || '',
      ammoKey: source.ammo_key || source.group || '',
      pickup_hash: Number(source.pickup_hash || 0),
      pickupHash: Number(source.pickup_hash || 0),
      drop_model: source.drop_model || '',
      dropModel: source.drop_model || '',
      pack_size: Number(source.pack_size || source.packSize || 1),
      packSize: Number(source.pack_size || source.packSize || 1),
      image: source.image || '',
      description: source.description || '',
      price: Number(get('price')?.value || 0),
      stock: Number(get('stock')?.value ?? -1),
      enabled: get('enabled')?.checked === true,
    });
    return;
  }

  const wdelete = e.target.closest('[data-wdelete]');
  if (wdelete) {
    const name = wdelete.dataset.wdelete || '';
    if (name && confirm(`Remove ${name} from this gun store? It will stay in cm-weapons.`)) post('adminDeleteItem', { item_name: name });
    return;
  }

  const buy = e.target.closest('[data-buy]'); if (buy && !state.busy) { state.busy = true; post('buyItem', { item_name: buy.dataset.name, method: buy.dataset.buy }); return; }
  const save = e.target.closest('[data-save]'); if (save) { const data = rowData(save.dataset.save); if (data) post('adminSaveItem', data); return; }
  const del = e.target.closest('[data-delete]'); if (del) { const name = del.dataset.delete || ''; if (name && confirm(`Remove ${name} from this gun store? Weapon/ammo stays in cm-weapons.`)) post('adminDeleteItem', { item_name: name }); return; }
  if (e.target.id === 'createStoreBtn') { createArmorData(true); return; }
  if (e.target.id === 'createHiddenBtn') { createArmorData(false); return; }
  if (e.target.id === 'captureVestBtn') { post('adminOpenVestCapture', {}); return; }
});

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
});

document.addEventListener('change', async (e) => {
  const fileInput = e.target.closest('[data-image-file]');
  if (fileInput) { const imageData = await readFileAsData(fileInput.files?.[0]); if (imageData) post('adminSaveImage', { item_name: fileInput.dataset.imageFile, imageData }); }
});

closeBtn.addEventListener('click', () => post('close'));
refreshBtn.addEventListener('click', () => post('refreshCatalog'));
dialogStoreBtn.addEventListener('click', () => post('dialogOpenStore'));
dialogCloseBtn.addEventListener('click', () => post('dialogClose'));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') post('close'); });
