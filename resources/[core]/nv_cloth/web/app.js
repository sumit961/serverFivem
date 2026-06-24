'use strict';

/* ══════════════════════════════════════════════════════════
   nv_cloth — app.js  v2
   ══════════════════════════════════════════════════════════ */

const resource = (typeof GetParentResourceName === 'function')
  ? GetParentResourceName() : 'nv_cloth';

const post = (name, data = {}) =>
  fetch(`https://${resource}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  }).then(r => r.json().catch(() => ({}))).catch(() => ({}));

const $ = id => document.getElementById(id);

/* ── DOM refs ──────────────────────────────────────────── */
const app               = $('app');
const categoriesEl      = $('categories');
const emptyNotice       = $('emptyNotice');
const buyBtn            = $('buyBtn');
const captureIconBtn    = $('captureIconBtn');
const captureStatus     = $('captureStatus');
const adminBlock        = $('adminBlock');
const customItemName    = $('customItemName');
const customItemPrice   = $('customItemPrice');
const itemDestination   = $('itemDestination');
const checkoutBtn       = $('checkoutBtn');
const bagLevelControls  = $('bagLevelControls');
const bagLevel          = $('bagLevel');
const adminCaptureControls = $('adminCaptureControls');
const captureAngle      = $('captureAngle');
const captureZOffset    = $('captureZOffset');
const captureBackground = $('captureBackground');
const previewWall = $('previewWall');
const previewWallWrap = $('previewWallWrap');
const sharedGender      = $('sharedGender');
const sharedGenderWrap  = $('sharedGenderWrap');
const textureStatus     = $('textureStatus');
const bulkProgress      = $('bulkProgress');
const capturePreview    = $('capturePreview');
const saveMissingBtn    = $('saveMissingBtn');
const saveAllBtn        = $('saveAllBtn');
const cancelBulkBtn     = $('cancelBulkBtn');
const payTabs           = document.querySelectorAll('.pay-tab');
const brandAdmin        = $('brandAdmin');
const brandNote         = $('brandNote');
const brandSub          = $('brandSub');
const rpEyebrow         = $('rpEyebrow');
const modeNote          = $('modeNote');
const controlsHint      = $('controlsHint');
const fitHelper         = $('fitHelper');
const fitHelperTitle    = $('fitHelperTitle');
const fitHelperText     = $('fitHelperText');
const openArmsFitBtn    = $('openArmsFitBtn');
const backToTorsoBtn    = $('backToTorsoBtn');

/* ── Category metadata ─────────────────────────────────── */
const CAT_ICONS = {
  torso:    svgIcon('shirt'),
  arms:     svgIcon('arm'),
  tshirt:   svgIcon('shirt2'),
  pants:    svgIcon('pants'),
  shoes:    svgIcon('shoe'),
  hat:      svgIcon('hat'),
  glasses:  svgIcon('glasses'),
  earrings: svgIcon('earring'),
  chains:   svgIcon('chain'),
  bags:     svgIcon('bag'),
  watches:  svgIcon('watch'),
};
const CAT_LABELS = {
  torso: 'Outerwear', arms: 'Arms / Fit', tshirt: 'Shirts',
  pants: 'Pants & Shorts', shoes: 'Shoes', hat: 'Headwear',
  glasses: 'Glasses', earrings: 'Earrings', chains: 'Accessories',
  bags: 'Bags', watches: 'Watches',
};

function svgIcon(name) {
  const icons = {
    shirt:    '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><path d="M20.38 3.46L16 2a4 4 0 01-8 0L3.62 3.46a2 2 0 00-1.34 2.23l.58 3.57a1 1 0 00.99.84H5v9a2 2 0 002 2h10a2 2 0 002-2v-9h1.15a1 1 0 00.99-.84l.58-3.57a2 2 0 00-1.33-2.23z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
    arm:      '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><rect x="4" y="3" width="16" height="18" rx="4" stroke="currentColor" stroke-width="1.6"/></svg>',
    shirt2:   '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><path d="M3 6l4-3h10l4 3-3 3v12H6V9L3 6z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
    pants:    '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><path d="M4 3h16v8l-4 10H4L8 11V3z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 3v8" stroke="currentColor" stroke-width="1.6"/></svg>',
    shoe:     '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><path d="M2 17l4-8h6l4 4 5 2v2a1 1 0 01-1 1H3a1 1 0 01-1-1v-1z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
    hat:      '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><path d="M12 3C8 3 4 6 4 10h16c0-4-4-7-8-7z" stroke="currentColor" stroke-width="1.6"/><rect x="2" y="10" width="20" height="3" rx="1.5" stroke="currentColor" stroke-width="1.6"/></svg>',
    glasses:  '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><circle cx="7" cy="12" r="3" stroke="currentColor" stroke-width="1.6"/><circle cx="17" cy="12" r="3" stroke="currentColor" stroke-width="1.6"/><path d="M1 12h3M20 12h3M10 12h4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    earring:  '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><circle cx="12" cy="5" r="2" stroke="currentColor" stroke-width="1.6"/><path d="M12 7v8" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><circle cx="12" cy="17" r="2" stroke="currentColor" stroke-width="1.6"/></svg>',
    chain:    '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><path d="M10 14a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M14 10a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    bag:      '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><path d="M6 2L3 6v14a2 2 0 002 2h14a2 2 0 002-2V6l-3-4z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M3 6h18M16 10a4 4 0 01-8 0" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    watch:    '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><circle cx="12" cy="12" r="5" stroke="currentColor" stroke-width="1.6"/><path d="M12 9v3l2 2M9.5 3h5l1 4h-7l1-4zM9.5 21h5l1-4h-7l1 4z" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  };
  return icons[name] || `<span>${name[0].toUpperCase()}</span>`;
}

/* ── Index maps (component/prop → category) ─────────── */
const COMP_IDX_CAT  = { 11:'torso', 8:'tshirt', 4:'pants', 6:'shoes', 7:'chains', 5:'bags' };
const PROP_IDX_CAT  = { 0:'hat', 1:'glasses', 2:'earrings', 6:'watches' };

/* ── Capture presets (server-mirrored) ─────────────── */
const CAPTURE_PRESETS = {
  torso:    { angle:'front',  zOffset:0.00, bg:'green' },
  tshirt:   { angle:'front',  zOffset:0.00, bg:'green' },
  pants:    { angle:'front',  zOffset:0.05, bg:'green' },
  shoes:    { angle:'front',  zOffset:0.28, bg:'green' },
  bags:     { angle:'back',   zOffset:0.00, bg:'green', sharedGender:true },
  hat:      { angle:'front',  zOffset:0.00, bg:'green' },
  glasses:  { angle:'front',  zOffset:0.00, bg:'green' },
  earrings: { angle:'right',  zOffset:0.00, bg:'green' },
  chains:   { angle:'front',  zOffset:0.00, bg:'green' },
  watches:  { angle:'left',   zOffset:0.00, bg:'green' },
};

/* ── App state ─────────────────────────────────────── */
let S = {
  open: false,
  isAdmin: false,
  payment: 'bank',
  categories: [],
  counts: {},
  prices: {},
  translations: {},
  catalog: [],
  useCatalogOnly: true,
  activeCategory: null,
  filtered: [],         // rows visible in current category
  itemPos: 0,
  selected: null,
  texture: 0,
  textureCount: 1,
  exactTextureRows: [], // catalog rows for current drawable's textures
  adminTorsoTarget: null,
  cart: [],
  bulkRunning: false,
  bulkCancel: false,
  pendingIconResolver: null,
};

/* ══════════════════════════════════════════════════════════
   NORMALISE CATALOG ROWS
   ══════════════════════════════════════════════════════════ */
function normCat(row) {
  let c = String(row.category || '').toLowerCase();
  if (c === 'top' || c === 'jacket' || c === 'outerwear') c = 'torso';
  if (c === 'shirt') c = 'tshirt';
  if (c === 'legs')  c = 'pants';
  if (c === 'chain') c = 'chains';
  if (!c) {
    const tp  = String(row.componentType || row.component_type || 'component').toLowerCase();
    const idx = Number(row.componentIndex ?? row.component_index);
    c = tp === 'prop' ? PROP_IDX_CAT[idx] : COMP_IDX_CAT[idx];
  }
  return c || '';
}

function normRow(row) {
  const category = normCat(row);
  const drawable  = Number(row.drawableId ?? row.drawable_id ?? row.drawable ?? 0);
  const texRaw    = Number(row.textureId  ?? row.texture_id  ?? row.texture  ?? 0);
  const texture   = texRaw < 0 ? 0 : texRaw;
  return {
    ...row,
    category,
    drawable,
    texture,
    label:   row.label || `${CAT_LABELS[category] || category} ${drawable}`,
    price:   Number(row.price ?? S.prices[category] ?? 0),
    enabled: !(row.enabled === false || row.enabled === 0 || row.enabled === '0'),
    hasCatalogRow: !row.generated,
  };
}

/* ── Catalog helpers ──────────────────────────────── */
const catalogRows = (inclDisabled = false) =>
  S.catalog.map(normRow).filter(r => r.category && (inclDisabled || r.enabled !== false));

const hasImage = r => String(r.image || r.icon || '').trim() !== '';

function drawKey(r)  { return `${r.category}:${Number(r.drawable)}`; }
function fullKey(r) {
  const t = Number(r.texture ?? r.textureId ?? 0);
  return `${r.category}:${Number(r.drawable)}:${t < 0 ? -1 : t}`;
}

function uniqueByDrawable(rows) {
  const out = [], seen = new Set();
  for (const r of rows) {
    const k = drawKey(r);
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(r);
  }
  return out;
}

/* ── Texture rows for selected drawable ───────────── */
function getTextureRowsForSelected() {
  if (!S.selected) return [];
  const { category, drawable } = S.selected;
  const rows = catalogRows(S.isAdmin)
    .filter(r => r.category === category && Number(r.drawable) === Number(drawable));
  const exact = rows.filter(r => Number(r.texture) >= 0);
  return exact.sort((a, b) => Number(a.texture) - Number(b.texture));
}

function applyTextureModeFromCatalog(preferredTex) {
  const exact = getTextureRowsForSelected();
  S.exactTextureRows = exact;
  if (!S.isAdmin && exact.length > 0) {
    let idx = exact.findIndex(r => Number(r.texture) === Number(preferredTex));
    if (idx < 0) idx = 0;
    S.texture      = Number(exact[idx].texture || 0);
    S.textureCount = exact.length;
    S.selected     = { ...S.selected, ...exact[idx] };
  } else {
    S.texture      = Number(preferredTex ?? (S.selected ? S.selected.texture : 0) ?? 0);
    S.textureCount = Math.max(1, S.textureCount || 1);
  }
}

/* ── Rows for a category ──────────────────────────── */
function getRowsForCategory(category) {
  if (!S.isAdmin) {
    const imaged  = catalogRows(false).filter(r => r.category === category && hasImage(r));
    const unique  = uniqueByDrawable(imaged);
    if (unique.length || S.useCatalogOnly) return unique;
  }
  // Admin: merge catalog rows with generated placeholders
  const byDrawKey = new Map(
    catalogRows(true).filter(r => r.category === category).map(r => [drawKey(r), r])
  );
  const count  = Number(S.counts[category] || 0);
  const result = [];
  for (let i = 0; i < count; i++) {
    const gen = {
      category, drawable: i, texture: 0,
      label: `${CAT_LABELS[category] || category} ${i}`,
      price: Number(S.prices[category] || 0),
      enabled: true, generated: true,
    };
    result.push(byDrawKey.get(drawKey(gen)) || gen);
  }
  return result;
}

/* ══════════════════════════════════════════════════════════
   RENDER
   ══════════════════════════════════════════════════════════ */
function renderCategories() {
  categoriesEl.innerHTML = '';
  S.categories.filter(c => c !== 'arms' && (S.isAdmin || c !== 'bags')).forEach(cat => {
    const rows        = getRowsForCategory(cat);
    const enabled     = rows.filter(r => r.enabled !== false).length;
    const isActive    = S.activeCategory === cat;

    const btn = document.createElement('button');
    btn.className = `category${isActive ? ' active' : ''}`;

    const countStr = S.isAdmin ? `${enabled}/${rows.length}` : String(rows.length);
    btn.innerHTML = `
      <span class="cat-icon">${CAT_ICONS[cat] || '★'}</span>
      <span class="cat-label">${CAT_LABELS[cat] || cat}</span>
      <span class="cat-count">${countStr}</span>`;
    btn.onclick = () => setCategory(cat);
    categoriesEl.appendChild(btn);
  });
}

/* ── Texture status pills ─────────────────────────── */
function textureSaved(texture) {
  if (!S.selected) return false;
  const { category, drawable } = S.selected;
  const t = Number(texture);
  return catalogRows(true).some(r =>
    r.category === category &&
    Number(r.drawable) === Number(drawable) &&
    Number(r.texture) === t &&
    r.enabled !== false &&
    hasImage(r)
  );
}

function renderTextureStatus() {
  if (!textureStatus) return;
  if (!S.isAdmin || !S.selected) { textureStatus.innerHTML = ''; return; }
  const count = Math.max(1, Number(S.textureCount || 1));
  textureStatus.innerHTML = Array.from({ length: count }, (_, i) => {
    const saved  = textureSaved(i);
    const active = Number(S.texture) === i;
    return `<button type="button" class="texture-pill ${saved?'saved':'missing'}${active?' active':''}" data-tex="${i}">T${i} ${saved?'✓':'✗'}</button>`;
  }).join('');
  textureStatus.querySelectorAll('.texture-pill').forEach(btn => {
    btn.onclick = () => {
      S.texture = Number(btn.dataset.tex || 0);
      if (S.activeCategory === 'torso' && S.selected)
        S.adminTorsoTarget = { ...S.selected, texture: S.texture, textureId: S.texture };
      updateBottom();
      previewSelected();
    };
  });
}


function updateFitHelper() {
  if (!fitHelper) return;
  const show = S.isAdmin && (S.activeCategory === 'torso' || S.activeCategory === 'arms' || !!S.adminTorsoTarget);
  fitHelper.classList.toggle('hidden', !show);
  if (!show) return;
  const torsoName = S.adminTorsoTarget ? (S.adminTorsoTarget.label || 'selected torso') : 'no torso selected';
  if (fitHelperTitle) fitHelperTitle.textContent = S.activeCategory === 'arms' ? 'Editing Arms / Fit' : 'Arms / Fit Helper';
  if (fitHelperText) fitHelperText.textContent = S.activeCategory === 'arms'
    ? `Changing arms for ${torsoName}. Other preview clothes are kept.`
    : `Current target: ${torsoName}. Open Arms / Fit to tune sleeves/body without clearing the preview.`;
  if (openArmsFitBtn) openArmsFitBtn.disabled = !S.adminTorsoTarget || S.activeCategory === 'arms';
  if (backToTorsoBtn) backToTorsoBtn.disabled = S.activeCategory !== 'arms';
}

function selectTorsoTarget() {
  if (!S.adminTorsoTarget) return false;
  S.activeCategory = 'torso';
  S.filtered = getRowsForCategory('torso');
  const targetDrawable = Number(S.adminTorsoTarget.drawable);
  const targetTexture = Number(S.adminTorsoTarget.texture || 0);
  const idx = S.filtered.findIndex(r => Number(r.drawable) === targetDrawable);
  S.itemPos = idx >= 0 ? idx : 0;
  S.selected = S.filtered[S.itemPos] || null;
  S.texture = targetTexture;
  S.textureCount = 1;
  applyTextureModeFromCatalog(S.texture);
  renderCategories();
  updateBottom();
  previewSelected();
  post('changeCamera', { camera: 'body' });
  return true;
}

/* ── Update right panel bottom ────────────────────── */
function updateBottom() {
  const item = S.selected;
  const has  = !!item;

  buyBtn.disabled = !has || S.bulkRunning;

  // Item name
  let nameText = has ? item.label : 'Select clothing';
  if (S.isAdmin && has) {
    if (S.activeCategory === 'arms' && S.adminTorsoTarget)
      nameText = `Fit for ${S.adminTorsoTarget.label} — pick arms/shirt`;
    else
      nameText += item.enabled === false ? '  ·  DISABLED' : '  ·  ENABLED';
  }
  $('itemName').textContent = nameText;

  // Price
  $('price').textContent = has ? String(item.price || 0) : '0';

  // Admin price field auto-fill
  if (S.isAdmin && customItemPrice && has && document.activeElement !== customItemPrice)
    customItemPrice.value = String(item.price || S.prices[item.category] || 0);

  // Selector counters
  $('itemIndex').textContent   = has ? `${S.itemPos+1} / ${S.filtered.length}` : '—';
  $('textureIndex').textContent = has ? `${S.texture} / ${Math.max(0, S.textureCount-1)}` : '—';

  // Empty notice
  const showEmpty = !has && catalogRows(false).length === 0 && !S.isAdmin;
  emptyNotice.classList.toggle('hidden', !showEmpty);

  // Bag level — only overwrite the dropdown when the item has a catalog-saved level.
  // If the user manually picked a level (item is a generated placeholder with no saved level),
  // leave the dropdown alone so the selected level survives previewSelected() / captureOneTexture() calls.
  if (bagLevelControls) bagLevelControls.classList.toggle('hidden', !(S.isAdmin && has && item.category === 'bags'));
  if (bagLevel && has && item.category === 'bags') {
    const savedLevel = item.bagLevel || item.bag_level || item.level;
    if (savedLevel) bagLevel.value = String(savedLevel);
  }

  // Admin capture panel
  if (adminCaptureControls) adminCaptureControls.classList.toggle('hidden', !S.isAdmin);

  updateFitHelper();
  updateAdminButton();
  renderTextureStatus();
  updateCartUI();
}

function updateAdminButton() {
  if (!S.isAdmin) {
    buyBtn.textContent = S.cart.length > 0 ? 'ADD TO CART +' : 'ADD TO CART';
    buyBtn.classList.remove('btn--fit');
    return;
  }
  if (S.activeCategory === 'arms' && S.adminTorsoTarget) {
    buyBtn.textContent = 'SAVE FIT TO TORSO';
    buyBtn.classList.add('btn--fit');
  } else {
    buyBtn.textContent = 'SAVE CURRENT TEXTURE';
    buyBtn.classList.remove('btn--fit');
  }
}

function updateCartUI() {
  const total = S.cart.reduce((s, i) => s + Number(i.price || 0), 0);
  if (checkoutBtn) {
    const show = !S.isAdmin && S.cart.length > 0;
    checkoutBtn.classList.toggle('hidden', !show);
    if (show) checkoutBtn.textContent = `CHECKOUT ${S.cart.length} ITEM${S.cart.length===1?'':'S'}  ·  $${total}`;
  }
}

/* ══════════════════════════════════════════════════════════
   CATEGORY / ITEM / TEXTURE NAVIGATION
   ══════════════════════════════════════════════════════════ */
function setCaptureControlsForCategory(cat) {
  const p = CAPTURE_PRESETS[cat] || {};
  if (captureAngle)      captureAngle.value      = 'auto';
  if (captureZOffset)    captureZOffset.value     = Number(p.zOffset || 0).toFixed(2);
  if (captureBackground) captureBackground.value  = p.bg || 'green';
  if (sharedGender)      sharedGender.checked     = cat === 'bags' || p.sharedGender === true;
  if (sharedGenderWrap)  sharedGenderWrap.classList.toggle('hidden', cat !== 'bags');
}

function refreshCaptureBackdropPreview() {
  if (!S.isAdmin) return;
  const mode = (previewWall && previewWall.checked)
    ? (captureBackground ? (captureBackground.value || 'green') : 'green')
    : 'none';
  post('setCaptureBackdrop', { mode });
}

function setCategory(cat) {
  S.activeCategory = cat;
  S.filtered       = getRowsForCategory(cat);
  S.itemPos        = 0;
  S.selected       = S.filtered[0] || null;
  if (cat === 'torso' && S.selected) S.adminTorsoTarget = { ...S.selected };
  if (S.isAdmin) {
    setCaptureControlsForCategory(cat);
    refreshCaptureBackdropPreview();
  }
  S.texture      = S.selected ? Number(S.selected.texture || 0) : 0;
  S.textureCount = 1;
  applyTextureModeFromCatalog(S.texture);
  renderCategories();
  updateBottom();
  previewSelected();
  // Camera preset per category
  if (cat === 'hat') post('changeCamera', { camera: 'head' });
  else if (['glasses','earrings'].includes(cat)) post('changeCamera', { camera: 'face' });
  else if (cat === 'shoes')                        post('changeCamera', { camera: 'feet' });
  else                                              post('changeCamera', { camera: 'body' });
}

async function previewSelected() {
  if (!S.selected) return;
  const item = {
    ...S.selected,
    drawable:    S.selected.drawable,
    texture:     S.texture,
    drawableId:  S.selected.drawable,
    textureId:   S.texture,
    category:    S.selected.category,
  };
  if (S.isAdmin && S.activeCategory === 'arms' && S.adminTorsoTarget)
    item.adminTorsoTarget = { ...S.adminTorsoTarget };

  const res   = await post('sendSelectedArticle', item);
  const count = Number(res.count ?? 1);
  if (S.isAdmin) S.textureCount = Math.max(1, count || 1);
  applyTextureModeFromCatalog(S.texture);
  updateBottom();
}

function moveItem(dir) {
  if (!S.filtered.length) return;
  S.itemPos  = (S.itemPos + dir + S.filtered.length) % S.filtered.length;
  S.selected = S.filtered[S.itemPos];
  if (S.activeCategory === 'torso' && S.selected) S.adminTorsoTarget = { ...S.selected };
  S.texture      = Number(S.selected.texture || 0);
  S.textureCount = 1;
  applyTextureModeFromCatalog(S.texture);
  updateBottom();
  previewSelected();
}

function moveTexture(dir) {
  if (!S.selected) return;
  if (!S.isAdmin && S.exactTextureRows.length > 0) {
    const cur  = Math.max(0, S.exactTextureRows.findIndex(r => Number(r.texture) === Number(S.texture)));
    const next = (cur + dir + S.exactTextureRows.length) % S.exactTextureRows.length;
    const row  = S.exactTextureRows[next];
    S.texture      = Number(row.texture || 0);
    S.textureCount = S.exactTextureRows.length;
    S.selected     = { ...S.selected, ...row };
  } else {
    const c = Math.max(1, S.textureCount || 1);
    S.texture = (S.texture + dir + c) % c;
  }
  if (S.activeCategory === 'torso' && S.selected)
    S.adminTorsoTarget = { ...S.selected, texture: S.texture, textureId: S.texture };
  updateBottom();
  previewSelected();
}

/* ══════════════════════════════════════════════════════════
   SHOP OPEN / CLOSE
   ══════════════════════════════════════════════════════════ */
function openShop(data) {
  S.open = data.value !== false;
  if (!S.open) { app.classList.add('hidden'); return; }

  S.categories  = Array.isArray(data.categories) ? data.categories : ['torso','tshirt','pants','shoes'];
  S.counts      = data.counts       || S.counts      || {};
  S.prices      = data.prices       || S.prices      || {};
  S.translations = data.translations || S.translations || {};
  S.useCatalogOnly = data.useCatalogOnly !== false;

  app.classList.remove('hidden');

  // Always reset UI navigation on every fresh open. This prevents the store from
  // reopening on the last category/item/texture the player selected earlier.
  S.activeCategory = S.categories.find(c => c !== 'arms' && c !== 'bags') || S.categories[0];
  S.itemPos = 0;
  S.texture = 0;
  S.textureCount = 1;
  S.selected = null;
  S.exactTextureRows = [];
  S.adminTorsoTarget = null;

  renderCategories();
  setCategory(S.activeCategory);
}

function setAdminMode(value) {
  S.isAdmin = value === true;
  app.classList.toggle('admin-mode', S.isAdmin);
  app.classList.toggle('store-mode', !S.isAdmin);

  // Update brand block
  brandAdmin.classList.toggle('hidden', !S.isAdmin);
  brandNote.classList.toggle('hidden', !S.isAdmin);

  // Show/hide admin controls
  adminBlock.classList.toggle('hidden', !S.isAdmin);
  if (adminCaptureControls) adminCaptureControls.classList.toggle('hidden', !S.isAdmin);

  // Admin never uses catalog-only filter — show all drawables
  if (S.isAdmin) S.useCatalogOnly = false;

  // Clear cart if leaving admin
  if (!S.isAdmin) { S.cart = []; updateCartUI(); post('setCaptureBackdrop', { mode: 'none' }); }

  // Eyebrow
  rpEyebrow.textContent = S.isAdmin ? 'ADMIN CREATOR' : 'CLOTHING STORE';
  if (modeNote) modeNote.textContent = S.isAdmin
    ? 'Create catalog items, capture images, and manage texture status.'
    : 'Preview outfits, switch colors, add items to cart, then checkout.';

  // Hide controls hint in admin (saves vertical space)
  if (controlsHint) controlsHint.classList.toggle('hidden', S.isAdmin);

  updateAdminButton();
  renderCategories();
  if (S.activeCategory) setCategory(S.activeCategory);
}

/* ══════════════════════════════════════════════════════════
   ADMIN HELPERS
   ══════════════════════════════════════════════════════════ */
const getAdminName   = (fb) => { const v = customItemName   ? customItemName.value.trim() : ''; return v || fb; };
const getAdminDest   = ()   => itemDestination ? (itemDestination.value || 'store') : 'store';
const getAdminPrice  = (fb) => { const v = customItemPrice ? Number(customItemPrice.value) : NaN; return Number.isFinite(v) && v >= 0 ? Math.floor(v) : Number(fb || 0) || 0; };
const getBagLevel    = ()   => {
  const v = bagLevel ? Number(bagLevel.value) : NaN;
  if (!Number.isFinite(v)) return null;
  return Math.max(1, Math.min(4, Math.floor(v)));
};

function getAdminTarget() {
  if (!S.isAdmin || !S.selected) return null;
  let base = S.selected;
  if (S.activeCategory === 'arms' && S.adminTorsoTarget) base = S.adminTorsoTarget;
  else if (S.activeCategory === 'arms') return null;

  const cat    = base.category;
  const preset = CAPTURE_PRESETS[cat] || {};
  const angle  = captureAngle ? captureAngle.value : 'auto';
  const z      = captureZOffset ? Number(captureZOffset.value) : Number(preset.zOffset || 0);

  const t = {
    ...base,
    texture:          Number(base.texture ?? S.texture ?? 0),
    textureId:        Number(base.texture ?? S.texture ?? 0),
    drawableId:       base.drawable,
    enabled:          true,
    captureAngle:     angle === 'auto' ? (preset.angle || 'front') : angle,
    zOffset:          Number.isFinite(z) ? z : Number(preset.zOffset || 0),
    captureBackground: captureBackground ? (captureBackground.value || preset.bg || 'green') : (preset.bg || 'green'),
    sharedGender:     cat === 'bags' ? (sharedGender ? sharedGender.checked !== false : true) : false,
  };
  t.label       = getAdminName(t.label);
  t.name        = t.label;
  t.destination = getAdminDest();
  t.price       = getAdminPrice(t.price ?? S.prices[t.category]);
  if (t.category === 'bags') {
    const lvl = getBagLevel();
    if (!lvl) { toast('Select bag level 1-4 before saving.', 'error'); return null; }
    t.level = lvl;
    t.bagLevel = lvl;
    t.bag_level = lvl;
  }
  console.log('[nv_cloth:UI] admin target', { category: t.category, drawable: t.drawableId, texture: t.textureId, image: t.image, bagLevel: t.bagLevel });
  return t;
}

/* ══════════════════════════════════════════════════════════
   CAPTURE PIPELINE
   ══════════════════════════════════════════════════════════ */
function setCaptureStatus(show, text) {
  if (!captureStatus) return;
  captureStatus.textContent = text || 'Processing…';
  captureStatus.classList.toggle('hidden', !show);
}

function setBulkProgress(text, show = true) {
  if (!bulkProgress) return;
  bulkProgress.textContent = text || '';
  bulkProgress.classList.toggle('hidden', !show);
}

function waitForIconResult(ms = 30000) {
  return new Promise(resolve => {
    const t = setTimeout(() => {
      S.pendingIconResolver = null;
      resolve({ success: false, error: 'capture_timeout' });
    }, ms);
    S.pendingIconResolver = data => {
      clearTimeout(t);
      S.pendingIconResolver = null;
      resolve(data || { success: false, error: 'unknown' });
    };
  });
}

function getTextureIndices(mode) {
  const count = Math.max(1, Number(S.textureCount || 1));
  const all   = Array.from({ length: count }, (_, i) => i);
  if (mode === 'current') return [Number(S.texture || 0)];
  if (mode === 'missing') return all.filter(i => !textureSaved(i));
  return all;
}

function applyBulkDisabled(disabled) {
  if (buyBtn)         buyBtn.disabled         = disabled || !S.selected;
  if (saveMissingBtn) saveMissingBtn.disabled  = disabled || !S.selected;
  if (saveAllBtn)     saveAllBtn.disabled      = disabled || !S.selected;
  if (cancelBulkBtn)  cancelBulkBtn.classList.toggle('hidden', !disabled);
}

async function captureOneTexture(texture) {
  S.texture = Number(texture || 0);
  if (S.activeCategory === 'torso' && S.selected)
    S.adminTorsoTarget = { ...S.selected, texture: S.texture, textureId: S.texture };
  updateBottom();
  await previewSelected();
  await delay(550);

  const target = getAdminTarget();
  if (!target) return { success: false, error: 'invalid_target' };
  target.texture   = S.texture;
  target.textureId = S.texture;

  const waiter = waitForIconResult();
  const res    = await post('captureInventoryIcon', target);
  if (res && res.success === false && S.pendingIconResolver)
    S.pendingIconResolver({ success: false, error: res.error || 'capture_start_failed' });
  return waiter;
}

async function runBulkCapture(mode) {
  if (!S.isAdmin || !S.selected || S.bulkRunning) return;
  const indices = getTextureIndices(mode);
  if (!indices.length) {
    setBulkProgress('All textures already saved.', true);
    setTimeout(() => setBulkProgress('', false), 2000);
    return;
  }
  if (indices.length > 1) {
    const msg = mode === 'all'
      ? `Capture all ${indices.length} texture(s)?`
      : `Capture ${indices.length} missing texture(s)?`;
    if (!window.confirm(msg)) return;
  }
  S.bulkRunning = true;
  S.bulkCancel  = false;
  applyBulkDisabled(true);

  let saved = 0; const failed = [];
  for (let i = 0; i < indices.length; i++) {
    if (S.bulkCancel) break;
    const tex = indices[i];
    setCaptureStatus(true, `Saving ${i+1}/${indices.length} (T${tex})…`);
    setBulkProgress(`Saving ${i+1}/${indices.length} · T${tex}`);
    const r = await captureOneTexture(tex);
    if (r && r.success) saved++;
    else failed.push(`T${tex}: ${r?.error || 'failed'}`);
    await delay(350);
  }
  S.bulkRunning = false;
  applyBulkDisabled(false);
  setCaptureStatus(false);
  renderTextureStatus();
  renderCategories();
  const done = S.bulkCancel ? 'Cancelled' : 'Done';
  setBulkProgress(`${done}: saved ${saved}/${indices.length}${failed.length ? ` · Failed: ${failed.join(', ')}` : ''}`, true);
  setTimeout(() => setBulkProgress('', false), 5000);
}

/* ══════════════════════════════════════════════════════════
   IMAGE PROCESSING — background removal
   ══════════════════════════════════════════════════════════ */
function clamp01(n, fb) { n = Number(n); return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : fb; }

function removeBackgroundAndCrop(dataUrl, payload = {}) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const src = document.createElement('canvas');
      src.width  = img.naturalWidth  || img.width;
      src.height = img.naturalHeight || img.height;
      const sctx = src.getContext('2d', { willReadFrequently: true });
      sctx.drawImage(img, 0, 0);

      const imageData = sctx.getImageData(0, 0, src.width, src.height);
      const d = imageData.data;
      const ch  = payload.chroma || {};
      const bg  = String(payload.captureBackground || payload.backgroundColor || 'green').toLowerCase();

      // Chroma key params
      const minGreen    = Number(ch.minGreen  ?? 95);
      const dominance   = Number(ch.dominance ?? 1.35);
      const greenMargin = Number(ch.greenMargin ?? 35);
      const maxRed      = Number(ch.maxRed    ?? 130);
      const maxBlue     = Number(ch.maxBlue   ?? 150);
      const soften      = ch.soften !== false;

      // Crop region
      const crop   = payload.crop || {};
      const rx = clamp01(crop.x, 0.25), ry = clamp01(crop.y, 0.08);
      const rw = clamp01(crop.w, 0.50), rh = clamp01(crop.h, 0.84);
      const minX = Math.max(0, Math.floor(src.width  * rx));
      const minY = Math.max(0, Math.floor(src.height * ry));
      const maxX = Math.min(src.width  - 1, Math.ceil(src.width  * Math.min(1, rx + rw)));
      const maxY = Math.min(src.height - 1, Math.ceil(src.height * Math.min(1, ry + rh)));

      const idx = (x, y) => (y * src.width + x) * 4;
      const makeTransparent = (x, y) => { d[idx(x,y)+3] = 0; };
      const isTransparent   = (x, y) => d[idx(x,y)+3] <= 10;

      function isKey(i) {
        const r = d[i], g = d[i+1], b = d[i+2];
        if (bg === 'blue')    return b >= 110 && b >= r*1.25 && b >= g*1.15 && (b - Math.max(r,g)) >= 25 && r <= 165 && g <= 190;
        if (bg === 'magenta' || bg === 'pink') return r >= 120 && b >= 120 && g <= 150 && Math.abs(r-b) <= 90 && (Math.min(r,b)-g) >= 25;
        if (bg === 'white')   return r >= 225 && g >= 225 && b >= 225 && Math.abs(r-g) <= 18 && Math.abs(r-b) <= 18 && Math.abs(g-b) <= 18;
        if (bg === 'black')   return r <= 25 && g <= 25 && b <= 25;
        // default green
        return g >= minGreen && g > Math.max(r,b)*dominance && (g-r) >= greenMargin && (g-b) >= greenMargin && r <= maxRed && b <= maxBlue;
      }

      function nearTransparent(x, y) {
        for (let yy = Math.max(minY, y-1); yy <= Math.min(maxY, y+1); yy++)
          for (let xx = Math.max(minX, x-1); xx <= Math.min(maxX, x+1); xx++)
            if (isTransparent(xx, yy)) return true;
        return false;
      }

      let removed = 0;

      // Step 1: crop outside region
      for (let y = 0; y < src.height; y++)
        for (let x = 0; x < src.width; x++)
          if (x < minX || x > maxX || y < minY || y > maxY) makeTransparent(x, y);

      // Step 2: chroma key inside crop
      for (let y = minY; y <= maxY; y++)
        for (let x = minX; x <= maxX; x++) {
          const i = idx(x, y);
          if (d[i+3] > 10 && isKey(i)) { d[i+3] = 0; removed++; }
        }

      // Step 3: green de-spill
      if (soften && bg === 'green')
        for (let y = minY; y <= maxY; y++)
          for (let x = minX; x <= maxX; x++) {
            const i = idx(x, y);
            if (d[i+3] > 10 && nearTransparent(x, y) && d[i+1] > d[i]*1.12 && d[i+1] > d[i+2]*1.12)
              d[i+1] = Math.max(d[i], d[i+2]);
          }

      // Find tight bounding box
      let bMinX = src.width, bMinY = src.height, bMaxX = 0, bMaxY = 0;
      for (let y = minY; y <= maxY; y++)
        for (let x = minX; x <= maxX; x++) {
          const a = d[idx(x,y)+3];
          if (a > 10) {
            if (x < bMinX) bMinX = x; if (y < bMinY) bMinY = y;
            if (x > bMaxX) bMaxX = x; if (y > bMaxY) bMaxY = y;
          }
        }

      if (bMaxX <= bMinX || bMaxY <= bMinY) { reject(new Error('No pixels found after BG removal')); return; }

      let pad = Number(payload.padding ?? 18);
      if (payload.crop && Number.isFinite(Number(payload.crop.padding))) pad = Number(payload.crop.padding);
      const fMinX = Math.max(0, bMinX - pad), fMinY = Math.max(0, bMinY - pad);
      const fMaxX = Math.min(src.width-1, bMaxX + pad), fMaxY = Math.min(src.height-1, bMaxY + pad);
      const fW = fMaxX - fMinX + 1, fH = fMaxY - fMinY + 1;

      sctx.putImageData(imageData, 0, 0);
      const out = document.createElement('canvas');
      out.width = fW; out.height = fH;
      out.getContext('2d').drawImage(src, fMinX, fMinY, fW, fH, 0, 0, fW, fH);

      const png = out.toDataURL('image/png');
      resolve({
        dataUrl: png,
        imageBase64: png.split(',')[1],
        meta: { removedPixels: removed, width: fW, height: fH, background: bg,
                crop: { x: fMinX, y: fMinY, w: fW, h: fH } },
      });
    };
    img.onerror = () => reject(new Error('Unable to load screenshot'));
    img.src = dataUrl;
  });
}

/* ══════════════════════════════════════════════════════════
   NUI MESSAGE HANDLER
   ══════════════════════════════════════════════════════════ */
const delay = ms => new Promise(r => setTimeout(r, ms));

window.addEventListener('message', ({ data = {} }) => {
  switch (data.type) {
    case 'openClothShop':     openShop(data);                                  break;
    case 'clothingCounts':    S.counts = data.counts || {}; renderCategories(); break;
    case 'clothingCatalog':
      S.catalog = Array.isArray(data.catalog) ? data.catalog : [];
      if (S.activeCategory) setCategory(S.activeCategory);
      else renderCategories();
      break;
    case 'adminMode':         setAdminMode(data.value);                         break;

    case 'prepareIconCapture':
      app.classList.toggle('capture-hidden', data.value === true);
      // Do not show any NUI toast/container while screenshot-basic is capturing;
      // otherwise the black processing pill can be saved inside the clothing icon.
      setCaptureStatus(false);
      break;

    case 'iconCaptureResult':
      if (!S.bulkRunning) { setCaptureStatus(false); refreshCaptureBackdropPreview(); }
      if (data.success) {
        if (data.entry) {
          const row = normRow(data.entry);
          const i   = S.catalog.findIndex(r => fullKey(normRow(r)) === fullKey(row));
          if (i >= 0) S.catalog[i] = { ...S.catalog[i], ...data.entry, enabled: true };
          else S.catalog.push({ ...data.entry, enabled: true });
          if (S.selected && drawKey(S.selected) === drawKey(row)) {
            S.selected = { ...S.selected, ...row, enabled: true };
            if (S.filtered[S.itemPos]) S.filtered[S.itemPos] = { ...S.filtered[S.itemPos], ...row, enabled: true };
          }
          renderCategories();
          updateBottom();
        }
        $('itemName').textContent = '✓ IMAGE SAVED — ITEM ADDED TO STORE';
      } else {
        $('itemName').textContent = `✗ ICON SAVE FAILED: ${data.error || 'unknown'}`;
      }
      if (S.pendingIconResolver) S.pendingIconResolver(data);
      break;

    case 'processIconImage':
      setCaptureStatus(true, 'Removing background…');
      removeBackgroundAndCrop(data.image, data.payload || {})
        .then(result => {
          if (capturePreview && result.dataUrl) {
            capturePreview.src = result.dataUrl;
            capturePreview.classList.remove('hidden');
          }
          return post('iconProcessed', { ...result, payload: data.payload || {} });
        })
        .then(() => { if (!S.bulkRunning) setCaptureStatus(false); })
        .catch(err => {
          setCaptureStatus(false);
          $('itemName').textContent = `✗ PROCESS FAILED: ${err.message || err}`;
          if (S.pendingIconResolver) S.pendingIconResolver({ success: false, error: String(err.message || err) });
        });
      break;
  }
});

/* ══════════════════════════════════════════════════════════
   EVENT LISTENERS
   ══════════════════════════════════════════════════════════ */

// Payment tabs
payTabs.forEach(btn => btn.onclick = () => {
  payTabs.forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  S.payment = btn.dataset.pay || 'bank';
});

// Selectors
$('prevItem').onclick    = () => moveItem(-1);
$('nextItem').onclick    = () => moveItem(1);
$('prevTexture').onclick = () => moveTexture(-1);
$('nextTexture').onclick = () => moveTexture(1);

if (openArmsFitBtn) openArmsFitBtn.onclick = () => {
  if (S.activeCategory === 'torso' && S.selected) S.adminTorsoTarget = { ...S.selected, texture: S.texture, textureId: S.texture };
  if (S.adminTorsoTarget) setCategory('arms');
};
if (backToTorsoBtn) backToTorsoBtn.onclick = () => selectTorsoTarget();

// Capture backdrop preview is optional while browsing. Capture always uses selected color.
if (captureBackground) captureBackground.onchange = () => refreshCaptureBackdropPreview();
if (previewWall) previewWall.onchange = () => refreshCaptureBackdropPreview();

// Bulk capture buttons
if (saveMissingBtn) saveMissingBtn.onclick = async () => runBulkCapture('missing');
if (saveAllBtn)     saveAllBtn.onclick     = async () => runBulkCapture('all');
if (captureIconBtn) captureIconBtn.onclick = async () => runBulkCapture('current');
if (cancelBulkBtn)  cancelBulkBtn.onclick  = () => {
  S.bulkCancel = true;
  setBulkProgress('Cancelling after current texture…');
};

// Buy / Save button
buyBtn.onclick = async () => {
  if (!S.selected) return;
  if (S.isAdmin) { await runBulkCapture('current'); return; }
  const item = { ...S.selected, texture: S.texture, textureId: S.texture, drawableId: S.selected.drawable };
  S.cart.push(item);
  updateCartUI();
  $('itemName').textContent = `${item.label} added to cart`;
};

// Checkout
if (checkoutBtn) checkoutBtn.onclick = async () => {
  if (S.isAdmin || S.cart.length <= 0) return;
  const items = [...S.cart];
  await post('buyClothes', { paymentMethod: S.payment, items, cart: items, name: items.map(i => i.label).join(', ') });
  S.cart = [];
  updateCartUI();
};

// Close
$('closeBtn').onclick = () => {
  S.isAdmin         = false;
  S.adminTorsoTarget = null;
  S.cart            = [];
  if (customItemName)   customItemName.value   = '';
  if (customItemPrice)  customItemPrice.value  = '';
  if (itemDestination)  itemDestination.value  = 'store';
  if (bulkProgress)     bulkProgress.classList.add('hidden');
  updateCartUI();
  setCaptureStatus(false);
  post('closeMenu');
  app.classList.add('hidden');
};

// Keyboard shortcuts
document.addEventListener('keydown', e => {
  if (!S.open) return;
  if (e.key === 'Escape')      $('closeBtn').click();
  if (e.key === 'ArrowLeft')   moveItem(-1);
  if (e.key === 'ArrowRight')  moveItem(1);
  if (e.key === 'ArrowUp')     moveTexture(1);
  if (e.key === 'ArrowDown')   moveTexture(-1);
});

// Mouse-drag ped rotation
let dragging = false, lastX = 0;
document.addEventListener('mousedown', e => { dragging = true; lastX = e.clientX; });
document.addEventListener('mouseup',   () => { dragging = false; });
document.addEventListener('mousemove', e => {
  if (!dragging || !S.open) return;
  const dx = e.clientX - lastX;
  lastX = e.clientX;
  if (Math.abs(dx) > 1) post('rotatePed', { delta: -dx * 0.45 });
});
