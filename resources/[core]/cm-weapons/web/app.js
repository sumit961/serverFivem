const app = document.getElementById('app');
const state = { ammo: [], weapons: [], ammoGroups: [], defaultWeapons: [], defaultAmmo: [], tab: 'ammo', selectedAmmo: null, selectedWeapon: null, q: '' };

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

function post(name, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).then(r => r.json()).catch(() => ({}));
}

function showNotice(text) {
  const n = $('#notice');
  n.textContent = text;
  n.classList.remove('hidden');
  clearTimeout(showNotice.t);
  showNotice.t = setTimeout(() => n.classList.add('hidden'), 2500);
}

function asBool(v) { return v === true || v === 1 || v === '1' || v === 'true'; }
function num(v, fallback = 0) { const n = Number(v); return Number.isFinite(n) ? n : fallback; }
function itemNameFromHash(hash) { return String(hash || '').toLowerCase(); }

function formToObj(form) {
  const fd = new FormData(form);
  const out = {};
  for (const [k, v] of fd.entries()) { if (v instanceof File) continue; out[k] = v; }
  form.querySelectorAll('input[type="checkbox"]').forEach(x => out[x.name] = x.checked);
  ['weight','packSize','sortOrder','pickupHash','damage','magazineSize','recoil','durability'].forEach(k => {
    if (out[k] !== undefined) out[k] = num(out[k]);
  });
  return out;
}

function fillForm(form, data = {}) {
  form.reset();
  for (const [key, value] of Object.entries(data)) {
    const el = form.elements[key];
    if (!el) continue;
    if (el.type === 'checkbox') el.checked = asBool(value);
    else el.value = value ?? '';
  }
}

function imgPath(value) {
  const src = String(value || '').trim();
  if (!src) return '';
  const nui = src.match(/^nui:\/\/([^\/]+)\/(.+)$/i);
  if (nui) return `https://cfx-nui-${nui[1]}/${nui[2]}`;
  return src;
}

function imgHtml(src, fallbackText) {
  src = imgPath(src);
  if (!src) return `<div class="meta img-fallback">${fallbackText || 'No Image'}</div>`;
  return `<img src="${src}" onerror="this.style.display='none'" />`;
}

function readFileAsData(file) {
  return new Promise((resolve) => {
    if (!file) return resolve('');
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ''));
    reader.onerror = () => resolve('');
    reader.readAsDataURL(file);
  });
}

async function formToObjWithImage(form) {
  const data = formToObj(form);
  const file = form.querySelector('input[type="file"]')?.files?.[0];
  if (file) data.imageData = await readFileAsData(file);
  return data;
}

function applySearch(items) {
  const q = state.q.trim().toLowerCase();
  if (!q) return items;
  return items.filter(x => JSON.stringify(x).toLowerCase().includes(q));
}

function renderAmmoGroups() {
  const sel = $('#ammoKeySelect');
  sel.innerHTML = state.ammoGroups.map(g => `<option value="${g.key}" data-pickup="${g.pickupHash}">${g.label} (${g.pickupHash})</option>`).join('');
}

function renderAmmoDropdown() {
  const sel = $('#weaponAmmoSelect');
  const rows = state.ammo.slice().sort((a,b) => String(a.label).localeCompare(String(b.label)));
  sel.innerHTML = `<option value="">Select ammo used by this gun...</option>` + rows.map(a => `<option value="${a.itemName}">${a.label} • ${a.ammoKey} • ${a.itemName}</option>`).join('');
}

function renderDefaultWeaponPicker() {
  const sel = $('#defaultWeaponPicker');
  sel.innerHTML = `<option value="">Pick from fixed GTA weapon list...</option>` + state.defaultWeapons.map((w, i) => `<option value="${i}">${w.label} • ${w.weaponHash}</option>`).join('');
}

function renderAmmoList() {
  const list = $('#ammoList');
  const rows = applySearch(state.ammo);
  list.innerHTML = rows.map(a => `
    <article class="card ${state.selectedAmmo === a.itemName ? 'active' : ''}" data-ammo="${a.itemName}">
      ${imgHtml(a.image, a.ammoKey)}
      <h3>${a.label}</h3>
      <div class="meta">${a.itemName}<br/>type: ${a.ammoKey}<br/>pickup: ${a.pickupHash}<br/>pack: ${a.packSize}</div>
      <span class="badge ${a.enabled ? '' : 'off'}">${a.enabled ? 'Enabled' : 'Disabled'}</span>
    </article>
  `).join('') || '<div class="meta">No ammo found.</div>';
  list.querySelectorAll('[data-ammo]').forEach(card => card.addEventListener('click', () => selectAmmo(card.dataset.ammo)));
}

function renderWeaponList() {
  const list = $('#weaponList');
  const rows = applySearch(state.weapons);
  list.innerHTML = rows.map(w => {
    const ammo = state.ammo.find(a => a.itemName === w.ammoItem);
    return `
      <article class="card ${state.selectedWeapon === w.itemName ? 'active' : ''}" data-weapon="${w.itemName}">
        ${imgHtml(w.image, w.group)}
        <h3>${w.label}</h3>
        <div class="meta">${w.weaponHash}<br/>${w.itemName}<br/>ammo: ${ammo ? ammo.label : (w.ammoItem || 'none')}<br/>damage: ${w.damage} • mag: ${w.magazineSize}</div>
        <span class="badge ${w.enabled ? '' : 'off'}">${w.enabled ? 'Enabled' : 'Disabled'}</span>
      </article>
    `;
  }).join('') || '<div class="meta">No weapons found.</div>';
  list.querySelectorAll('[data-weapon]').forEach(card => card.addEventListener('click', () => selectWeapon(card.dataset.weapon)));
}

function renderAll() {
  $('#ammoCount').textContent = `Ammo: ${state.ammo.length}`;
  $('#weaponCount').textContent = `Weapons: ${state.weapons.length}`;
  renderAmmoGroups();
  renderAmmoDropdown();
  renderDefaultWeaponPicker();
  renderAmmoList();
  renderWeaponList();
  updatePickupHash();
}

function selectAmmo(itemName) {
  const a = state.ammo.find(x => x.itemName === itemName);
  if (!a) return;
  state.selectedAmmo = a.itemName;
  fillForm($('#ammoForm'), {
    itemName: a.itemName,
    label: a.label,
    ammoKey: a.ammoKey,
    pickupHash: a.pickupHash,
    packSize: a.packSize,
    weight: a.weight,
    sortOrder: a.sortOrder,
    image: a.image,
    description: a.description,
    enabled: a.enabled,
    stack: a.stack !== false
  });
  renderAmmoList();
  updatePickupHash();
}

function selectWeapon(itemName) {
  const w = state.weapons.find(x => x.itemName === itemName);
  if (!w) return;
  state.selectedWeapon = w.itemName;
  fillForm($('#weaponForm'), {
    itemName: w.itemName,
    label: w.label,
    weaponHash: w.weaponHash,
    group: w.group,
    ammoItem: w.ammoItem,
    damage: w.damage,
    magazineSize: w.magazineSize,
    weight: w.weight,
    sortOrder: w.sortOrder,
    image: w.image,
    description: w.description,
    enabled: w.enabled
  });
  renderWeaponList();
}

function newAmmo() {
  state.selectedAmmo = null;
  fillForm($('#ammoForm'), { itemName: '', label: '', ammoKey: 'pistol', pickupHash: '', packSize: 30, weight: 10, sortOrder: 0, enabled: true, stack: true });
  updatePickupHash();
  renderAmmoList();
}

function newWeapon() {
  state.selectedWeapon = null;
  fillForm($('#weaponForm'), { itemName: '', label: '', weaponHash: '', group: 'pistol', ammoItem: '', damage: 25, magazineSize: 12, weight: 1000, sortOrder: 0, enabled: true });
  renderWeaponList();
}

function updatePickupHash() {
  const form = $('#ammoForm');
  const sel = form.elements.ammoKey;
  if (!sel) return;
  const opt = sel.options[sel.selectedIndex];
  if (form.elements.pickupHash && opt) form.elements.pickupHash.value = opt.dataset.pickup || '';
}

window.addEventListener('message', (event) => {
  const msg = event.data || {};
  if (msg.type === 'show') app.classList.remove('hidden');
  if (msg.type === 'hide') app.classList.add('hidden');
  if (msg.type === 'adminData') {
    const p = msg.payload || {};
    state.ammo = p.ammo || [];
    state.weapons = p.weapons || [];
    state.ammoGroups = p.ammoGroups || [];
    state.defaultAmmo = p.defaultAmmo || [];
    state.defaultWeapons = p.defaultWeapons || [];
    renderAll();
  }
});

$$('.tab').forEach(btn => btn.addEventListener('click', () => {
  state.tab = btn.dataset.tab;
  $$('.tab').forEach(b => b.classList.toggle('active', b === btn));
  $$('.tabpage').forEach(p => p.classList.remove('active'));
  $(`#${state.tab}Tab`).classList.add('active');
}));

$('#close').addEventListener('click', () => post('close'));
$('#refresh').addEventListener('click', () => post('refresh'));
$('#syncItems').addEventListener('click', () => { post('syncItems'); showNotice('Sync requested.'); });
$('#search').addEventListener('input', (e) => { state.q = e.target.value; renderAmmoList(); renderWeaponList(); });
$('#ammoKeySelect').addEventListener('change', updatePickupHash);
$('#newAmmo').addEventListener('click', newAmmo);
$('#newWeapon').addEventListener('click', newWeapon);

$('#ammoForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const data = await formToObjWithImage(e.currentTarget);
  post('saveAmmo', data);
  showNotice(data.imageData ? 'Saving ammo and uploading image...' : 'Saving ammo...');
});

$('#weaponForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const data = await formToObjWithImage(e.currentTarget);
  if (!data.ammoItem) return showNotice('Select ammo used by this gun first.');
  post('saveWeapon', data);
  showNotice(data.imageData ? 'Saving weapon and uploading image...' : 'Saving weapon...');
});

$('#deleteAmmo').addEventListener('click', () => {
  const data = formToObj($('#ammoForm'));
  if (!data.itemName) return showNotice('Select ammo first.');
  const force = confirm(`Delete ${data.itemName}?\n\nIf weapons use this ammo, press Cancel and change them first. Press OK to force delete and clear linked weapons.`);
  post('deleteAmmo', { itemName: data.itemName, force });
  showNotice('Delete ammo requested...');
});

$('#deleteWeapon').addEventListener('click', () => {
  const data = formToObj($('#weaponForm'));
  if (!data.itemName) return showNotice('Select weapon first.');
  if (!confirm(`Delete ${data.itemName}?`)) return;
  post('deleteWeapon', { itemName: data.itemName });
  showNotice('Delete weapon requested...');
});

$('#fillWeapon').addEventListener('click', () => {
  const idx = Number($('#defaultWeaponPicker').value);
  const w = state.defaultWeapons[idx];
  if (!w) return;
  fillForm($('#weaponForm'), {
    itemName: w.itemName || itemNameFromHash(w.weaponHash),
    label: w.label || '',
    weaponHash: w.weaponHash || '',
    group: w.group || 'pistol',
    ammoItem: w.ammoItem || '',
    damage: w.damage || 25,
    magazineSize: w.magazineSize || 0,
    weight: w.weight || 1000,
    sortOrder: w.sortOrder || 0,
    image: w.image || '',
    description: w.description || '',
    enabled: w.enabled !== false
  });
});



document.addEventListener('change', async (e) => {
  const file = e.target.closest('input[type="file"]');
  if (!file || !file.files || !file.files[0]) return;
  const form = file.closest('form');
  const kind = form && form.id === 'ammoForm' ? 'ammo' : (form && form.id === 'weaponForm' ? 'weapon' : '');
  const itemName = form?.elements?.itemName?.value || '';
  if (!itemName) return showNotice('Type item name first, then save or upload image.');
  // The selected file is also sent on Save. For existing items, upload immediately too.
  const exists = kind === 'ammo' ? state.ammo.some(x => x.itemName === itemName) : state.weapons.some(x => x.itemName === itemName);
  if (exists) {
    const imageData = await readFileAsData(file.files[0]);
    if (imageData) {
      post('saveImage', { kind, itemName, imageData });
      showNotice('Uploading image...');
    }
  } else {
    showNotice('Image selected. Click Save to create item with this image.');
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') post('close');
});
