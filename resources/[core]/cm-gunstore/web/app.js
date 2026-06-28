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

const state = { mode: 'store', filter: 'all', catalog: [], busy: false, imageData: '', armorCaptureData: '', capturedArmorImage: '', weaponPicker: [], weaponGroups: [], weaponGroup: 'pistol', weaponSearch: '', creatorType: 'ammo' };

function resName() { return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-gunstore'; }
function post(path, body = {}) { return fetch(`https://${resName()}/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body) }).catch(() => null); }
function imgSrc(value) {
  let icon = String(value || '').trim();
  if (!icon) return 'images/weapon_pistol.svg';
  const nui = icon.match(/^nui:\/\/([^\/]+)\/(.+)$/i);
  if (nui) return `https://cfx-nui-${nui[1]}/${nui[2]}`;
  if (icon.startsWith('http://') || icon.startsWith('https://') || icon.startsWith('data:')) return icon;
  if (icon.startsWith('images/')) return icon;
  return `images/${icon}`;
}
function money(n) { n = Number(n) || 0; return `$${n.toLocaleString()}`; }
function typeLabel(row) {
  if (row.item_type === 'ammo') return `${row.pack_size || 1} Rounds`;
  if (row.item_type === 'armor') return `${row.armor_value || row.armorValue || 0} Armor`;
  return row.damage ? `${row.damage} Damage / Bullet` : (row.ammo_item ? `Uses ${row.ammo_item}` : 'Weapon');
}
function itemAccent(row) { return row.item_type === 'ammo' ? 'ammo' : row.item_type === 'armor' ? 'armor' : 'weapon'; }
function visibleRows() { return state.catalog.filter(row => (state.filter === 'all' || row.item_type === state.filter) && (state.mode === 'admin' || row.enabled !== false)); }
function escapeAttr(v) { return String(v ?? '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function escapeHtml(v) { return String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

function statusBadge(status) {
  if (status === 'store') return '<span class="wstatus on">In Store</span>';
  if (status === 'hidden') return '<span class="wstatus hidden">Hidden</span>';
  if (status === 'made') return '<span class="wstatus made">On Server</span>';
  return '<span class="wstatus new">Not Created</span>';
}

function weaponPickerView() {
  const groups = state.weaponGroups.length ? state.weaponGroups : ['pistol','smg','rifle','shotgun','sniper','heavy'];
  const search = (state.weaponSearch || '').toLowerCase();
  const tabs = groups.map(g =>
    `<button class="wgroup ${state.weaponGroup === g ? 'active' : ''}" data-wgroup="${g}">${g.toUpperCase()}</button>`
  ).join('');

  let items = state.weaponPicker.filter(w => w.group === state.weaponGroup);
  if (search) items = items.filter(w => (w.label || '').toLowerCase().includes(search) || (w.hash || '').toLowerCase().includes(search));

  const cards = items.map(w => `
    <article class="wcard" data-whash="${escapeAttr(w.hash)}">
      <div class="wimg"><img src="${escapeAttr(w.image)}" alt="${escapeAttr(w.label)}" onerror="this.style.opacity=0.2"></div>
      <div class="whead"><h4>${escapeHtml(w.label)}</h4>${statusBadge(w.status)}</div>
      <code class="whash">${escapeHtml(w.hash)}</code>
      <div class="wfields">
        <label><span>Price</span><input data-wfield="price" type="number" min="0" value="${Number(w.price)||0}"></label>
        <label><span>Damage / Bullet</span><input data-wfield="damage" type="number" min="0" value="${Number(w.damage)||0}"></label>
        <label><span>Ammo Item</span><input data-wfield="ammo" value="${escapeAttr(w.ammo||'')}"></label>
        <label class="wtoggle"><input data-wfield="enabled" type="checkbox" ${w.status==='store'?'checked':''}><span>In Store</span></label>
      </div>
      <button class="wcreate" data-wcreate="${escapeAttr(w.hash)}">${w.status==='new'?'Create':'Update'}</button>
    </article>`).join('');

  return `
  <section class="weapon-picker">
    <div class="wp-head">
      <div><p class="eyebrow">WEAPON CATALOG</p><h2>Pick a weapon to add</h2></div>
      <input id="weaponSearch" class="wp-search" placeholder="Search weapons..." value="${escapeAttr(state.weaponSearch)}">
    </div>
    <div class="wgroups">${tabs}</div>
    <div class="wgrid">${cards || '<div class="empty">No weapons in this group</div>'}</div>
    <p class="creator-note">Pick a weapon, set price / damage / ammo, toggle In Store, then Create. The definition + image are saved to cm-items; price/stock stay in this shop. Status shows what's already on the server.</p>
  </section>`;
}

function adminCreator() {
  const type = state.creatorType || 'ammo';
  // Hidden inputs carry capture/auto data so createData() can always read them.
  const hidden = `
      <input type="hidden" id="newWeaponHash" value="">
      <input type="hidden" id="newDamage" value="0">
      <input type="hidden" id="newComponent" value="9">
      <input type="hidden" id="newDrawable" value="0">
      <input type="hidden" id="newTexture" value="0">
      <input type="hidden" id="newGender" value="both">
      <input type="hidden" id="newStock" value="-1">
      <input type="hidden" id="newItemName" value="">`;

  let fields = '';
  let actions = '';
  let note = '';

  if (type === 'armor') {
    fields = `
      <label><span>Name</span><input id="newLabel" placeholder="Heavy Tactical Vest" /></label>
      <label><span>Price</span><input id="newPrice" type="number" min="0" value="1000" /></label>
      <label><span>Armor Health</span><input id="newArmor" type="number" min="0" max="100" value="50" /></label>`;
    actions = `
      <button id="captureVestBtn" class="ghost-action">Capture Vest (Clothing Studio)</button>
      <button id="createHiddenBtn" class="save secondary">Create Hidden</button>
      <button id="createStoreBtn" class="save">Create In Store</button>`;
    note = `Click "Capture Vest (Clothing Studio)" to pick and photograph a vest. The image and component/drawable/texture are filled in automatically — then set name, price, and armor health, and click Create.`;
  } else {
    // ammo
    fields = `
      <label><span>Name</span><input id="newLabel" placeholder="9mm Ammo" /></label>
      <label><span>Price</span><input id="newPrice" type="number" min="0" value="100" /></label>
      <label><span>Pack Size (rounds)</span><input id="newPack" type="number" min="1" value="30" /></label>
      <label class="wide file-line"><span>Image (upload PNG)</span><input id="newFile" type="file" accept="image/png,image/jpeg,image/webp" /></label>`;
    actions = `
      <button id="createHiddenBtn" class="save secondary">Create Hidden</button>
      <button id="createStoreBtn" class="save">Create In Store</button>`;
    note = `Set a name, price, and how many rounds per pack, optionally upload an image, then click Create.`;
  }

  return `
  <section class="creator-panel">
    <div class="creator-head">
      <div><p class="eyebrow">CREATE NEW ITEM</p><h2>${type === 'armor' ? 'Wearable Vest / Armor' : 'Ammo'} Creator</h2></div>
      <span>Store = visible • Hidden = admin/event item</span>
    </div>
    <div class="creator-grid">
      <label><span>Type</span><select id="newType"><option value="ammo"${type==='ammo'?' selected':''}>Ammo</option><option value="armor"${type==='armor'?' selected':''}>Wearable Vest / Armor</option></select></label>
      ${fields}
      ${hidden}
    </div>
    <div class="creator-actions">${actions}</div>
    <p class="creator-note">${note}</p>
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
  return `<article class="admin-item${row.enabled ? '' : ' disabled'}" data-name="${itemName}">
    <div class="admin-preview"><span class="admin-type">${escapeHtml(row.item_type || 'weapon')}</span><img src="${imgSrc(row.image)}" alt="${escapeAttr(row.label)}"><small>${escapeHtml(row.item_name)}</small></div>
    <div class="admin-summary"><h3>${escapeHtml(row.label)}</h3><div class="meta"><span>${escapeHtml(typeLabel(row))}</span><strong>${money(row.price)}</strong></div><p class="desc">${escapeHtml(row.description || '')}</p><span class="status ${row.enabled ? 'on' : 'off'}">${row.enabled ? 'Store' : 'Hidden'}</span></div>
    <div class="admin-fields">
      <label><span>Label</span><input data-field="label" data-name="${itemName}" value="${escapeAttr(row.label)}" /></label>
      <label><span>Price</span><input data-field="price" data-name="${itemName}" type="number" min="0" value="${Number(row.price) || 0}" /></label>
      <label><span>Damage</span><input data-field="damage" data-name="${itemName}" type="number" min="0" value="${Number(row.damage) || 0}" /></label>
      <label><span>Armor</span><input data-field="armor_value" data-name="${itemName}" type="number" min="0" max="100" value="${Number(row.armor_value || row.armorValue) || 0}" /></label>
      <label><span>Component</span><input data-field="component_id" data-name="${itemName}" type="number" value="${Number(row.component_id || row.componentId || 9)}" /></label>
      <label><span>Drawable</span><input data-field="drawable_id" data-name="${itemName}" type="number" value="${row.drawable_id ?? row.drawableId ?? ''}" /></label>
      <label><span>Texture</span><input data-field="texture_id" data-name="${itemName}" type="number" value="${Number(row.texture_id || row.textureId || 0)}" /></label>
      <label><span>Gender</span><input data-field="gender" data-name="${itemName}" value="${escapeAttr(row.gender || 'both')}" /></label>
      <label><span>Stock</span><input data-field="stock" data-name="${itemName}" type="number" value="${Number(row.stock ?? -1)}" /></label>
      <label><span>Pack Size</span><input data-field="pack_size" data-name="${itemName}" type="number" min="1" value="${Number(row.pack_size) || 1}" /></label>
      <label><span>Weapon Hash</span><input data-field="weapon_hash" data-name="${itemName}" value="${escapeAttr(row.weapon_hash || '')}" /></label>
      <label><span>Ammo Item</span><input data-field="ammo_item" data-name="${itemName}" value="${escapeAttr(row.ammo_item || '')}" /></label>
      <label class="wide"><span>Image Path</span><input data-field="image" data-name="${itemName}" value="${escapeAttr(row.image)}" /></label>
      <label class="wide file-line"><span>Replace Image From PC</span><input data-image-file="${itemName}" type="file" accept="image/png,image/jpeg,image/webp" /></label>
      <label class="wide"><span>Description</span><textarea data-field="description" data-name="${itemName}">${escapeHtml(row.description || '')}</textarea></label>
    </div>
    <div class="admin-actions"><label class="admin-toggle"><input data-field="enabled" data-name="${itemName}" type="checkbox" ${row.enabled ? 'checked' : ''}/><span>Store</span></label><button class="save" data-save="${itemName}">Save</button></div>
  </article>`;
}

function render() {
  const admin = state.mode === 'admin';
  titleEl.textContent = admin ? 'Gun Store Admin' : 'Gun Store';
  modeLabel.textContent = admin ? 'CATALOG ADMIN' : 'STORE';
  app.classList.toggle('admin-mode', admin);
  document.querySelectorAll('.tab').forEach(btn => btn.classList.toggle('active', btn.dataset.filter === state.filter));

  // Admin + Weapons tab => weapon picker (full GTA firearm list with status).
  if (admin && state.filter === 'weapon') {
    itemsEl.innerHTML = weaponPickerView();
    return;
  }

  const rows = visibleRows();
  itemsEl.innerHTML = (admin ? adminCreator() : '') + (rows.length ? rows.map(card).join('') : '<div class="empty">No items available</div>');
}
function setInteraction(data = {}) { if (!data.show) { interactionPrompt.classList.add('hidden'); return; } interactionKey.textContent = data.key || 'E'; interactionName.textContent = data.clerkName || 'Gun Store Clerk'; interactionTitle.textContent = data.title || 'Talk to Clerk'; interactionSubtitle.textContent = data.subtitle || 'Browse weapons, ammo, and armor'; interactionPrompt.classList.remove('hidden'); }
function open(data) { interactionPrompt.classList.add('hidden'); state.mode = data.mode || 'store'; state.catalog = Array.isArray(data.catalog) ? data.catalog : []; state.busy = false; npcDialog.classList.add('hidden'); app.classList.remove('hidden'); render(); }
function openDialog(data = {}) { interactionPrompt.classList.add('hidden'); state.mode = 'dialog'; state.busy = false; app.classList.add('hidden'); app.classList.remove('admin-mode'); dialogName.textContent = data.clerkName || 'Gun Store Clerk'; dialogTitle.textContent = data.title || 'How can I help you today?'; dialogStoreBtn.textContent = data.optionStore || 'Show me what you have got'; dialogCloseBtn.textContent = data.optionClose || 'No thanks'; npcDialog.classList.remove('hidden'); }
function close() { interactionPrompt.classList.add('hidden'); npcDialog.classList.add('hidden'); app.classList.add('hidden'); app.classList.remove('admin-mode'); state.busy = false; }
function rowData(itemName) { const item = Array.from(document.querySelectorAll('.card, .admin-item')).find(el => el.dataset.name === itemName); if (!item) return null; const get = f => item.querySelector(`[data-field="${f}"]`); return { item_name: itemName, label: get('label')?.value || itemName, price: Number(get('price')?.value || 0), enabled: get('enabled')?.checked === true, image: get('image')?.value || '', description: get('description')?.value || '', armor_value: Number(get('armor_value')?.value || 0), damage: Number(get('damage')?.value || 0), stock: Number(get('stock')?.value ?? -1), weapon_hash: get('weapon_hash')?.value || '', ammo_item: get('ammo_item')?.value || '', pack_size: Number(get('pack_size')?.value || 1), component_id: Number(get('component_id')?.value || 9), drawable_id: get('drawable_id')?.value === '' ? null : Number(get('drawable_id')?.value), texture_id: Number(get('texture_id')?.value || 0), gender: get('gender')?.value || 'both' }; }
function readFileAsData(file) { return new Promise((resolve) => { if (!file) return resolve(''); const r = new FileReader(); r.onload = () => resolve(String(r.result || '')); r.onerror = () => resolve(''); r.readAsDataURL(file); }); }
async function createData(enabled) {
  const type = document.getElementById('newType')?.value || 'ammo';
  const data = {
    item_type: type,
    label: document.getElementById('newLabel')?.value || '',
    item_name: document.getElementById('newItemName')?.value || '',
    price: Number(document.getElementById('newPrice')?.value || 0),
    weapon_hash: document.getElementById('newWeaponHash')?.value || '',
    ammo_item: document.getElementById('newAmmoItem')?.value || '',
    damage: Number(document.getElementById('newDamage')?.value || 0),
    armor_value: Number(document.getElementById('newArmor')?.value || 0),
    pack_size: Number(document.getElementById('newPack')?.value || 1),
    stock: Number(document.getElementById('newStock')?.value ?? -1),
    description: document.getElementById('newDesc')?.value || '',
    image: document.getElementById('newImage')?.value || '',
    component_id: Number(document.getElementById('newComponent')?.value || 9),
    drawable_id: Number(document.getElementById('newDrawable')?.value || 0),
    texture_id: Number(document.getElementById('newTexture')?.value || 0),
    gender: document.getElementById('newGender')?.value || 'both',
    enabled,
  };
  // cm-items saves the PNG from base64 imageData. Armor uses the captured vest
  // base64; guns use the PC-uploaded file. An explicit image path (if typed)
  // overrides and skips base64.
  if (!data.image) {
    if (type === 'armor') {
      data.imageData = state.capturedArmorImage || state.imageData || '';
    } else {
      const file = document.getElementById('newFile')?.files?.[0];
      data.imageData = state.imageData || await readFileAsData(file);
    }
  }
  post('adminCreateItem', data);
  state.imageData = '';
  state.armorCaptureData = '';
  state.capturedArmorImage = '';
}
// Fill the create form from a captured vest payload (sent by client after nv_cloth capture).
function prefillArmorForm(p) {
  p = p || {};
  // Ensure the armor creator form is showing (capture cached values used by createData).
  state.creatorType = 'armor';
  state.capturedArmorImage = p.imageData || p.image || '';
  state.imageData = '';
  state.capturedVest = {
    componentId: p.componentId ?? p.component_id ?? 9,
    drawableId: p.drawableId ?? p.drawable,
    textureId: p.textureId ?? p.texture ?? 0,
    gender: p.gender || 'both',
  };
  // Move off the Weapons tab so the creator (armor form) renders.
  if (state.filter === 'weapon') state.filter = 'armor';
  render();

  // After render, fill the visible/hidden fields.
  const set = (id, v) => { const el = document.getElementById(id); if (el != null && v != null && v !== '') el.value = v; };
  set('newType', 'armor');
  set('newComponent', state.capturedVest.componentId);
  if (state.capturedVest.drawableId != null) set('newDrawable', state.capturedVest.drawableId);
  if (state.capturedVest.textureId != null) set('newTexture', state.capturedVest.textureId);
  if (state.capturedVest.gender) set('newGender', state.capturedVest.gender);
  if (p.armorValue) set('newArmor', p.armorValue);
  const note = document.querySelector('.creator-note');
  if (note) note.textContent = 'Vest captured ✓ — set name, price, and armor health, then click Create In Store or Create Hidden.';
}

window.addEventListener('message', (event) => { const msg = event.data || {}; if (msg.action === 'open') open(msg.data || {}); if (msg.action === 'dialog') openDialog(msg.data || {}); if (msg.action === 'close') close(); if (msg.action === 'purchaseResult') state.busy = false; if (msg.action === 'interaction') setInteraction(msg.data || {}); if (msg.action === 'captureFlash') document.body.classList.toggle('capture-flash', msg.data?.show === true); if (msg.action === 'prefillArmor') prefillArmorForm(msg.data || {}); if (msg.action === 'weaponPicker') { state.weaponPicker = Array.isArray(msg.data?.list) ? msg.data.list : []; state.weaponGroups = Array.isArray(msg.data?.groups) ? msg.data.groups : state.weaponGroups; if (state.mode === 'admin' && state.filter === 'weapon') render(); } });

document.addEventListener('click', async (e) => {
  const tab = e.target.closest('.tab');
  if (tab) {
    state.filter = tab.dataset.filter || 'all';
    // Opening the admin Weapons tab loads the full firearm picker from the server.
    if (state.mode === 'admin' && state.filter === 'weapon') {
      if (!state.weaponPicker.length) post('adminRequestWeaponPicker', {});
    }
    render();
    return;
  }

  const wgroup = e.target.closest('[data-wgroup]');
  if (wgroup) { state.weaponGroup = wgroup.dataset.wgroup; render(); return; }

  const wcreate = e.target.closest('[data-wcreate]');
  if (wcreate) {
    const card = wcreate.closest('.wcard');
    const get = f => card.querySelector(`[data-wfield="${f}"]`);
    post('adminCreateWeapon', {
      hash: wcreate.dataset.wcreate,
      price: Number(get('price')?.value || 0),
      damage: Number(get('damage')?.value || 0),
      ammo_item: get('ammo')?.value || '',
      enabled: get('enabled')?.checked === true,
    });
    return;
  }

  const buy = e.target.closest('[data-buy]'); if (buy && !state.busy) { state.busy = true; post('buyItem', { item_name: buy.dataset.name, method: buy.dataset.buy }); return; }
  const save = e.target.closest('[data-save]'); if (save) { const data = rowData(save.dataset.save); if (data) post('adminSaveItem', data); return; }
  if (e.target.id === 'createStoreBtn') { createData(true); return; }
  if (e.target.id === 'createHiddenBtn') { createData(false); return; }
  if (e.target.id === 'captureVestBtn') { post('adminOpenVestCapture', {}); return; }
});

document.addEventListener('input', (e) => {
  if (e.target.id === 'weaponSearch') {
    state.weaponSearch = e.target.value || '';
    // Re-render just the grid without losing focus on the search box.
    const grid = document.querySelector('.wgrid');
    if (grid) {
      const search = state.weaponSearch.toLowerCase();
      let items = state.weaponPicker.filter(w => w.group === state.weaponGroup);
      if (search) items = items.filter(w => (w.label||'').toLowerCase().includes(search) || (w.hash||'').toLowerCase().includes(search));
      grid.innerHTML = items.map(w => `
        <article class="wcard" data-whash="${escapeAttr(w.hash)}">
          <div class="wimg"><img src="${escapeAttr(w.image)}" alt="${escapeAttr(w.label)}" onerror="this.style.opacity=0.2"></div>
          <div class="whead"><h4>${escapeHtml(w.label)}</h4>${statusBadge(w.status)}</div>
          <code class="whash">${escapeHtml(w.hash)}</code>
          <div class="wfields">
            <label><span>Price</span><input data-wfield="price" type="number" min="0" value="${Number(w.price)||0}"></label>
            <label><span>Damage / Bullet</span><input data-wfield="damage" type="number" min="0" value="${Number(w.damage)||0}"></label>
            <label><span>Ammo Item</span><input data-wfield="ammo" value="${escapeAttr(w.ammo||'')}"></label>
            <label class="wtoggle"><input data-wfield="enabled" type="checkbox" ${w.status==='store'?'checked':''}><span>In Store</span></label>
          </div>
          <button class="wcreate" data-wcreate="${escapeAttr(w.hash)}">${w.status==='new'?'Create':'Update'}</button>
        </article>`).join('') || '<div class="empty">No weapons match</div>';
    }
  }
});

document.addEventListener('change', async (e) => {
  if (e.target.id === 'newType') { state.creatorType = e.target.value || 'ammo'; render(); return; }
  if (e.target.id === 'newFile') state.imageData = await readFileAsData(e.target.files?.[0]);
  const fileInput = e.target.closest('[data-image-file]');
  if (fileInput) { const imageData = await readFileAsData(fileInput.files?.[0]); if (imageData) post('adminSaveImage', { item_name: fileInput.dataset.imageFile, imageData }); }
});

closeBtn.addEventListener('click', () => post('close'));
refreshBtn.addEventListener('click', () => post('refreshCatalog'));
dialogStoreBtn.addEventListener('click', () => post('dialogOpenStore'));
dialogCloseBtn.addEventListener('click', () => post('dialogClose'));
document.addEventListener('keydown', (e) => { if (e.key === 'Escape') post('close'); });
