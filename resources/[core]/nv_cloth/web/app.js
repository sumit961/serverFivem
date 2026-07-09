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
const purchaseStatus    = $('purchaseStatus');
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
const cropEditorModal   = $('cropEditorModal');
const cropEditorPreview = $('cropEditorPreview');
const cropTrimLeft      = $('cropTrimLeft');
const cropTrimTop       = $('cropTrimTop');
const cropTrimRight     = $('cropTrimRight');
const cropTrimBottom    = $('cropTrimBottom');
const cropTrimLeftVal   = $('cropTrimLeftVal');
const cropTrimTopVal    = $('cropTrimTopVal');
const cropTrimRightVal  = $('cropTrimRightVal');
const cropTrimBottomVal = $('cropTrimBottomVal');
const cropResetBtn      = $('cropResetBtn');
const cropSaveBtn       = $('cropSaveBtn');
const cropUseAutoBtn    = $('cropUseAutoBtn');
const cropCancelBtn     = $('cropCancelBtn');
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
const filterPanel       = $('filterPanel');
const searchInput       = $('searchInput');
const genderFilter      = $('genderFilter');
const drawableFilter    = $('drawableFilter');
const minPriceFilter    = $('minPriceFilter');
const maxPriceFilter    = $('maxPriceFilter');
const clearFiltersBtn   = $('clearFiltersBtn');
const cartPanel         = $('cartPanel');
const cartList          = $('cartList');
const cartTotal         = $('cartTotal');
const clearCartBtn      = $('clearCartBtn');
const checkoutModal     = $('checkoutModal');
const confirmTitle      = $('confirmTitle');
const confirmText       = $('confirmText');
const confirmItems      = $('confirmItems');
const confirmCashBtn    = $('confirmCashBtn');
const confirmBankBtn    = $('confirmBankBtn');
const confirmCancelBtn  = $('confirmCancelBtn');
const pricePreset       = $('pricePreset');
const requiredJob       = $('requiredJob');
const requiredGang      = $('requiredGang');
const requiredFamily    = $('requiredFamily');
const missingImageWarning = $('missingImageWarning');
const bulkEnableBtn     = $('bulkEnableBtn');
const bulkDisableBtn    = $('bulkDisableBtn');
const adminItemState    = $('adminItemState');

/* ── Category metadata ─────────────────────────────────── */
const CAT_ICONS = {
  torso:    svgIcon('shirt'),
  armor:    svgIcon('vest'),
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
  torso: 'Outerwear', armor: 'Armor / Vest', arms: 'Arms / Fit', tshirt: 'Shirts',
  pants: 'Pants & Shorts', shoes: 'Shoes', hat: 'Headwear',
  glasses: 'Glasses', earrings: 'Earrings', chains: 'Accessories',
  bags: 'Bags', watches: 'Watches',
};

// Categories that support manual "pose the ped, then confirm" capture.
const MANUAL_POSE_CATS = new Set(['hat', 'glasses', 'earrings', 'watches', 'chains', 'shoes']);


function svgIcon(name) {
  const icons = {
    vest:     '<svg width="16" height="16" fill="none" viewBox="0 0 24 24"><path d="M8 3l4 3 4-3 3 3-2 3v9H7v-9L5 6l3-3z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>',
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
const COMP_IDX_CAT  = { 11:'torso', 8:'tshirt', 4:'pants', 6:'shoes', 7:'chains', 5:'bags', 9:'armor' };
const PROP_IDX_CAT  = { 0:'hat', 1:'glasses', 2:'earrings', 6:'watches' };

/* ── Capture presets (server-mirrored) ─────────────── */
const CAPTURE_PRESETS = {
  torso:    { angle:'front',  zOffset:0.00, bg:'green' },
  armor:    { angle:'front',  zOffset:0.00, bg:'green' },
  tshirt:   { angle:'front',  zOffset:0.00, bg:'green' },
  pants:    { angle:'front',  zOffset:0.05, bg:'green' },
  shoes:    { angle:'front',  zOffset:0.00, bg:'green' },
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
  favourites: new Set(),   // fav keys: gender:category:drawable (global across shops)
  captureCrops: {},         // admin: saved per-category crop { left, top, right, bottom }
  armCropForCategory: null,  // when set to a category, the next capture opens the crop editor to (re)set it
  manualMode: false,         // admin: pose-and-shoot instead of auto-snapping the angle
  manualPosing: false,       // true while the on-screen pose bar is up
  manualShotPending: false,  // open crop editor after the confirmed manual shot
  singleManual: false,       // current run is a single manual-eligible capture
  manualDrag: null,          // drag state for rotate-by-drag
  economy: {},              // auto-pricing config (from Config.Economy)
  bulkRunning: false,
  bulkCancel: false,
  pendingIconResolver: null,
  pricePresets: {},
  filters: { q: '', gender: 'all', drawable: '', minPrice: '', maxPrice: '' },
  checkoutBusy: false,
  lastAdminSyncKey: '',
  captureMode: null,
  manualCropNextCapture: false,
  cropEditor: null,
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

function exactCmItemName(row = {}) {
  const v = row.itemName || row.item_name || row.nameKey || row.name_key || row.inventoryItem || row.inventory_item || row.item_key || '';
  const key = String(v || '').trim();
  // Do not use display labels as inventory item names. CM item keys are identifiers.
  return key && !/\s/.test(key) ? key : '';
}

function normRow(row) {
  const category = normCat(row);
  const drawable  = Number(row.drawableId ?? row.drawable_id ?? row.drawable ?? 0);
  const texRaw    = Number(row.textureId  ?? row.texture_id  ?? row.texture  ?? 0);
  const texture   = texRaw < 0 ? 0 : texRaw;
  const itemKey   = exactCmItemName(row);
  const normalised = {
    ...row,
    category,
    drawable,
    texture,
    label:   row.label || `${CAT_LABELS[category] || category} ${drawable}`,
    price:   Number(row.price ?? S.prices[category] ?? 0),
    enabled: !(row.enabled === false || row.enabled === 0 || row.enabled === '0'),
    gender: String(row.gender || row.sex || row.pedGender || 'all').toLowerCase(),
    requiredJob: row.requiredJob || row.required_job || row.job || '',
    requiredGang: row.requiredGang || row.required_gang || row.gang || row.org || '',
    requiredFamily: row.requiredFamily || row.required_family || row.family || row.familyId || '',
    hasCatalogRow: !row.generated,
  };
  if (itemKey) {
    normalised.itemName = itemKey;
    normalised.item_name = itemKey;
    normalised.nameKey = itemKey;
    normalised.inventoryItem = itemKey;
  }
  normalised.catalogKey = normalised.catalogKey || `${normalised.gender}:${category}:${drawable}:${texture}`;
  return normalised;
}

/* ── Catalog helpers ──────────────────────────────── */
const catalogRows = (inclDisabled = false) =>
  S.catalog.map(normRow).filter(r => r.category && (inclDisabled || r.enabled !== false));

const hasImage = r => String(r.image || r.icon || '').trim() !== '';
const hasStoredCatalogData = r => !!(r && (hasImage(r) || r.price != null || r.destination || r.requiredJob || r.requiredGang || r.requiredFamily || r.enabled !== undefined));
const destinationValue = r => {
  const d = String(r?.destination || r?.dest || r?.storeDestination || '').toLowerCase();
  if (d === 'hidden' || d === 'event' || d === 'private') return 'hidden';
  return 'store';
};
const currentSelectionKey = row => row ? `${row.category}:${Number(row.drawable)}:${Number((row.texture ?? row.textureId ?? S.texture) || 0)}` : '';
function syncAdminFormFromSelected(force = false) {
  if (!S.isAdmin || !S.selected) return;
  const item = S.selected;
  const key = currentSelectionKey(item);
  if (!force && key === S.lastAdminSyncKey) return;
  S.lastAdminSyncKey = key;
  if (customItemName && document.activeElement !== customItemName) customItemName.value = String(item.label || item.name || CAT_LABELS[item.category] || '').trim();
  const auto = autoPriceFor(item);
  const storedItem = hasStoredCatalogData(item);
  if (customItemPrice && document.activeElement !== customItemPrice) {
    if (auto && !storedItem) customItemPrice.value = String(auto.price);
    else customItemPrice.value = String(Number(item.price ?? S.prices[item.category] ?? 0));
  }
  if (itemDestination) {
    if (auto && !storedItem) itemDestination.value = auto.dest;
    else itemDestination.value = destinationValue(item);
  }
  if (requiredJob && document.activeElement !== requiredJob) requiredJob.value = String(item.requiredJob || item.required_job || item.job || '').trim();
  if (requiredGang && document.activeElement !== requiredGang) requiredGang.value = String(item.requiredGang || item.required_gang || item.gang || '').trim();
  if (requiredFamily && document.activeElement !== requiredFamily) requiredFamily.value = String(item.requiredFamily || item.required_family || item.family || '').trim();
}

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

function rowMatchesFilters(row) {
  const f = S.filters || {};
  const q = String(f.q || '').trim().toLowerCase();
  if (q) {
    const hay = [row.label, row.name, row.category, row.drawable, row.texture, row.price, row.requiredJob, row.requiredGang, row.requiredFamily]
      .map(v => String(v ?? '').toLowerCase()).join(' ');
    if (!hay.includes(q)) return false;
  }
  const gender = String(f.gender || 'all').toLowerCase();
  if (gender !== 'all') {
    const rg = String(row.gender || 'all').toLowerCase();
    if (rg !== 'all' && rg !== 'both' && rg !== 'unisex' && rg !== gender) return false;
  }
  if (String(f.drawable || '').trim() !== '' && Number(row.drawable) !== Number(f.drawable)) return false;
  const price = Number(row.price || 0);
  if (String(f.minPrice || '').trim() !== '' && price < Number(f.minPrice)) return false;
  if (String(f.maxPrice || '').trim() !== '' && price > Number(f.maxPrice)) return false;
  return true;
}

/* ── Rows for a category ──────────────────────────── */
function getRowsForCategory(category) {
  if (category === '__fav') {
    const imaged = catalogRows(false).filter(r =>
      r.category !== 'arms' && hasImage(r) && S.favourites.has(rowFavKey(r)) && rowMatchesFilters(r));
    return uniqueByDrawable(imaged);
  }
  if (!S.isAdmin) {
    const imaged  = catalogRows(false).filter(r => r.category === category && hasImage(r) && rowMatchesFilters(r));
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
  return result.filter(rowMatchesFilters);
}

/* ══════════════════════════════════════════════════════════
   RENDER
   ══════════════════════════════════════════════════════════ */
function renderCategories() {
  categoriesEl.innerHTML = '';

  // Favourites quick-access chip (store only). Jumps to every favourited item
  // across categories so players re-find fits they like without re-buying.
  if (!S.isAdmin) {
    const favChip = document.createElement('button');
    favChip.className = `category category--fav${S.activeCategory === '__fav' ? ' active' : ''}`;
    favChip.innerHTML = `
      <span class="cat-icon">★</span>
      <span class="cat-label">Favourites</span>
      <span class="cat-count">${S.favourites.size}</span>`;
    favChip.onclick = () => setCategory('__fav');
    categoriesEl.appendChild(favChip);
  }

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
  if (S.isAdmin && S.selected) syncAdminFormFromSelected();
  if (missingImageWarning) {
    const current = S.selected;
    const missing = S.isAdmin && !!current && !hasImage(current);
    missingImageWarning.classList.toggle('hidden', !missing);
  }
  if (adminItemState) {
    if (S.isAdmin && S.selected) {
      const current = S.selected;
      const stored = hasStoredCatalogData(current);
      const autoInfo = autoPriceFor(current);
      const flag = autoInfo ? (autoInfo.addon ? 'Add-on' : 'Store') : '';
      const tag = `#${Number(current.drawable)}${flag ? ` · ${flag}` : ''}`;
      const stateText = stored
        ? `${hasImage(current) ? 'Image saved' : 'No image yet'} · ${destinationValue(current) === 'hidden' ? 'Hidden / Event Only' : 'Public Store'} · Price $${Number(current.price ?? S.prices[current.category] ?? 0)} · ${tag}`
        : `New item · ${tag}. Set name / price / store, then capture and save the image.`;
      adminItemState.textContent = stateText;
      adminItemState.classList.remove('hidden');
      adminItemState.classList.toggle('item-state-note--ok', stored);
      adminItemState.classList.toggle('item-state-note--warn', !stored);
    } else {
      adminItemState.classList.add('hidden');
    }
  }

  updateFitHelper();
  updateAdminButton();
  renderTextureStatus();
  updateCartUI();
  updateFavButton();
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
    const existing = hasStoredCatalogData(S.selected || {});
    buyBtn.textContent = existing ? 'UPDATE / RETAKE IMAGE' : 'TAKE IMAGE + SAVE';
    buyBtn.classList.remove('btn--fit');
  }
}

function cartItemCount() {
  return S.cart.reduce((sum, item) => sum + Math.max(1, Number(item.qty || 1)), 0);
}

function cartAmount() {
  return S.cart.reduce((sum, item) => sum + (Number(item.price || 0) * Math.max(1, Number(item.qty || 1))), 0);
}

function addToCart(item) {
  const key = `${item.category}:${Number(item.drawable)}:${Number(item.texture || 0)}`;
  const existing = S.cart.find(i => i.cartKey === key);
  if (existing) existing.qty = Math.max(1, Number(existing.qty || 1)) + 1;
  else S.cart.push({ ...item, qty: 1, cartKey: key });
}

function expandedCartItems() {
  const out = [];
  for (const item of S.cart) {
    const qty = Math.max(1, Number(item.qty || 1));
    for (let i = 0; i < qty; i++) out.push({ ...item, qty: undefined });
  }
  return out.map(({ cartKey, qty, ...item }) => item);
}

function renderCartPreview() {
  if (!cartPanel || !cartList) return;
  const show = !S.isAdmin && S.cart.length > 0;
  cartPanel.classList.toggle('hidden', !show);
  if (!show) { cartList.innerHTML = ''; if (cartTotal) cartTotal.textContent = '$0'; return; }
  cartList.innerHTML = S.cart.map((item, idx) => {
    const qty = Math.max(1, Number(item.qty || 1));
    return `<div class="cart-row" data-index="${idx}">
      <div class="cart-info"><strong>${item.label || item.category}</strong><span>${item.category} · D${Number(item.drawable)} / T${Number(item.texture || 0)}</span></div>
      <div class="cart-controls"><button data-act="dec">−</button><b>${qty}</b><button data-act="inc">+</button><button data-act="remove">×</button></div>
    </div>`;
  }).join('');
  if (cartTotal) cartTotal.textContent = `$${cartAmount()}`;
}

function updateCartUI() {
  const total = cartAmount();
  const count = cartItemCount();
  if (checkoutBtn) {
    const show = !S.isAdmin && count > 0;
    checkoutBtn.classList.toggle('hidden', !show);
    if (show) checkoutBtn.textContent = `CHECKOUT ${count} ITEM${count===1?'':'S'}  ·  $${total}`;
  }
  renderCartPreview();
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
  // Manual pose & shoot only applies to accessories + shoes; hide the toggle
  // elsewhere so it's clear when it's available.
  const manualWrap = $('manualModeWrap');
  const manualNote = $('manualModeNote');
  const poseable = MANUAL_POSE_CATS.has(String(cat));
  if (manualWrap) manualWrap.classList.toggle('hidden', !poseable);
  if (manualNote) manualNote.classList.toggle('hidden', !poseable);
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
    syncCropSection();
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
   FAVOURITES (global across shops) + ADMIN CAMERA TUNER
   ══════════════════════════════════════════════════════════ */
function rowFavKey(r) {
  if (!r) return '';
  const g = String(r.gender || 'male').toLowerCase();
  return `${g}:${r.category}:${Number(r.drawable)}`;
}
function currentFavKey() {
  if (!S.selected) return '';
  const g = String(S.selected.gender || 'male').toLowerCase();
  return `${g}:${S.selected.category}:${Number(S.selected.drawable)}`;
}

function updateFavButton() {
  const btn = $('favBtn');
  if (!btn) return;
  // No favourites in admin mode, or when nothing is selected.
  const usable = !S.isAdmin && !!S.selected;
  btn.classList.toggle('hidden', !usable);
  if (!usable) return;
  const on = S.favourites.has(currentFavKey());
  btn.classList.toggle('is-fav', on);
  btn.setAttribute('aria-pressed', on ? 'true' : 'false');
  btn.title = on ? 'Remove from favourites' : 'Add to favourites';
}

function toggleCurrentFavourite() {
  if (S.isAdmin || !S.selected) return;
  const key = currentFavKey();
  if (!key) return;
  const on = !S.favourites.has(key);
  if (on) S.favourites.add(key); else S.favourites.delete(key);
  updateFavButton();
  renderCategories();               // refresh the ★ count
  if (S.activeCategory === '__fav') setCategory('__fav'); // keep the fav list live
  post('toggleFavourite', { key, on });
}

// ── Admin per-category crop ──────────────────────────────
// A saved crop for a category is reused automatically on every capture of that
// category until it is changed or cleared. Shape: { left, top, right, bottom }.
function savedCropFor(cat) {
  const c = S.captureCrops[cat];
  if (c && [c.left, c.top, c.right, c.bottom].every(v => Number.isFinite(Number(v)))) return c;
  return null;
}
function syncCropSection() {
  const section = $('cropSection');
  if (!section) return;
  const cat = S.activeCategory;
  const show = S.isAdmin && cat && cat !== 'arms' && cat !== '__fav';
  section.classList.toggle('hidden', !show);
  const catLabel = $('cropPanelCat');
  if (catLabel) catLabel.textContent = show ? (CAT_LABELS[cat] || cat) : '—';
  if (!show) return;

  const saved = savedCropFor(cat);
  const status = $('cropSectionStatus');
  if (status) {
    status.textContent = saved
      ? `Saved crop: L${saved.left}% · T${saved.top}% · R${saved.right}% · B${saved.bottom}% — applied to every ${CAT_LABELS[cat] || cat} capture.`
      : 'No saved crop for this category. Auto-crop is used.';
  }
  const clearBtn = $('clearCropBtn');
  if (clearBtn) clearBtn.disabled = !saved;
}
// Arm the next single capture to open the crop editor so the admin can set/reset
// the crop for the current category. The saved crop then reapplies on its own.
function armCropSetup() {
  const cat = S.activeCategory;
  if (!S.isAdmin || !cat || cat === 'arms' || cat === '__fav') return;
  if (!S.selected) { toast('Select an item first, then Set Crop.', 'error'); return; }
  S.armCropForCategory = cat;
  toast(`Capturing once so you can set the ${CAT_LABELS[cat] || cat} crop…`, 'info');
  runBulkCapture('current');
}
function clearSavedCrop() {
  const cat = S.activeCategory;
  if (!S.isAdmin || !cat) return;
  delete S.captureCrops[cat];
  post('resetCaptureCrop', { category: cat });
  syncCropSection();
  toast(`Cleared saved crop for ${CAT_LABELS[cat] || cat}.`, 'success');
}

// ── Manual pose & shoot ──────────────────────────────────
// When Manual mode is on, a single accessory/shoe capture pauses so the admin can
// rotate the ped (drag or buttons) and lift it (shoes) before shooting. Confirm
// takes the screenshot; the normal crop editor then opens to trim and save.
const poseBar = $('poseBar');
function enterPoseMode(category, heading) {
  S.manualPosing = true;
  setCaptureStatus(false);
  if (poseBar) poseBar.classList.remove('hidden');
  // Dim the panel so the ped is visible in the game view behind it.
  if (app) app.classList.add('posing');
  const catLabel = $('poseBarCat');
  if (catLabel) catLabel.textContent = CAT_LABELS[category] || category || 'item';
  const slider = $('poseHeading');
  if (slider) slider.value = Math.round(((heading % 360) + 360) % 360);
  const val = $('poseHeadingVal');
  if (val) val.textContent = `${Math.round(((heading % 360) + 360) % 360)}°`;
}
function exitPoseMode() {
  S.manualPosing = false;
  if (poseBar) poseBar.classList.add('hidden');
  if (app) app.classList.remove('posing');
}
function poseRotate(delta) {
  if (!S.manualPosing) return;
  post('manualPoseRotate', { delta });
}
function poseSetHeading(absolute) {
  if (!S.manualPosing) return;
  post('manualPoseRotate', { absolute });
  const val = $('poseHeadingVal');
  if (val) val.textContent = `${Math.round(absolute)}°`;
}
function poseLift(delta) {
  if (!S.manualPosing) return;
  post('manualPoseLift', { delta });
}
function poseConfirm() {
  if (!S.manualPosing) return;
  exitPoseMode();
  S.manualShotPending = true;   // open the crop editor after this shot
  setCaptureStatus(true, 'Shooting…');
  post('confirmManualShot', {});
}
function poseCancel() {
  if (!S.manualPosing) return;
  exitPoseMode();
  post('cancelManualShot', {});
  // Release the pending single-capture waiter so the flow doesn't hang.
  if (S.pendingIconResolver) S.pendingIconResolver({ success: false, error: 'manual_cancelled' });
}

// WASD + zoom camera control while posing.
//   W / S  = zoom in / out
//   A / D  = orbit camera left / right around the ped
//   R / F  = raise / lower the camera
//   Q / E  = widen / narrow lens (fov)
function poseCameraKey(key) {
  if (!S.manualPosing) return false;
  switch (key) {
    case 'w': post('manualPoseCam', { action: 'zoom',   amount:  0.12 }); return true;
    case 's': post('manualPoseCam', { action: 'zoom',   amount: -0.12 }); return true;
    case 'a': post('manualPoseCam', { action: 'orbit',  amount: -4.0  }); return true;
    case 'd': post('manualPoseCam', { action: 'orbit',  amount:  4.0  }); return true;
    case 'r': post('manualPoseCam', { action: 'height', amount:  0.04 }); return true;
    case 'f': post('manualPoseCam', { action: 'height', amount: -0.04 }); return true;
    case 'q': post('manualPoseCam', { action: 'fov',    amount: -2.0  }); return true;
    case 'e': post('manualPoseCam', { action: 'fov',    amount:  2.0  }); return true;
  }
  return false;
}
document.addEventListener('keydown', e => {
  if (!S.manualPosing) return;
  const k = (e.key || '').toLowerCase();
  if (poseCameraKey(k)) { e.preventDefault(); e.stopPropagation(); return; }
  if (k === 'enter') { e.preventDefault(); poseConfirm(); }
  else if (k === 'escape') { e.preventDefault(); poseCancel(); }
});

// ── Auto pricing (economy) ───────────────────────────────
function isAddonDrawable(category, drawable, gender) {
  const map = S.economy && S.economy.addonStartsAt;
  if (!map) return false;
  const t = map[category];
  if (t == null) return false;
  let thr;
  if (typeof t === 'object') thr = Number(t[gender] ?? t.male ?? t.female);
  else thr = Number(t);
  return Number.isFinite(thr) && Number(drawable) >= thr;
}
// Returns { price, addon, dest } or null when auto-pricing is off.
function autoPriceFor(row) {
  if (!row || !S.economy || S.economy.enabled === false) return null;
  const cat = row.category;
  const g = String(row.gender || 'male').toLowerCase();
  const addon = isAddonDrawable(cat, row.drawable, g);
  const table = addon ? (S.economy.addonPrices || {}) : (S.economy.storePrices || {});
  let price = table[cat];
  if (price == null) price = S.prices[cat] ?? 0;
  const dest = addon ? (S.economy.addonDestination || 'hidden') : 'store';
  return { price: Math.max(0, Math.floor(Number(price) || 0)), addon, dest };
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
  S.pricePresets = data.pricePresets || S.pricePresets || {};
  if (data.economy) S.economy = data.economy;

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
  if (missingImageWarning) {
    const current = S.selected;
    const missing = S.isAdmin && !!current && !hasImage(current);
    missingImageWarning.classList.toggle('hidden', !missing);
  }

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
  t.requiredJob = requiredJob ? requiredJob.value.trim() : '';
  t.requiredGang = requiredGang ? requiredGang.value.trim() : '';
  t.requiredFamily = requiredFamily ? requiredFamily.value.trim() : '';
  t.required_job = t.requiredJob;
  t.required_gang = t.requiredGang;
  t.required_family = t.requiredFamily;
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


function pctText(v) { return `${Math.round(Number(v) || 0)}%`; }
function syncCropReadouts() {
  if (cropTrimLeftVal && cropTrimLeft) cropTrimLeftVal.textContent = pctText(cropTrimLeft.value);
  if (cropTrimTopVal && cropTrimTop) cropTrimTopVal.textContent = pctText(cropTrimTop.value);
  if (cropTrimRightVal && cropTrimRight) cropTrimRightVal.textContent = pctText(cropTrimRight.value);
  if (cropTrimBottomVal && cropTrimBottom) cropTrimBottomVal.textContent = pctText(cropTrimBottom.value);
}
function cropEditorValues() {
  const left = Number(cropTrimLeft ? cropTrimLeft.value : 0) || 0;
  const top = Number(cropTrimTop ? cropTrimTop.value : 0) || 0;
  const right = Number(cropTrimRight ? cropTrimRight.value : 0) || 0;
  const bottom = Number(cropTrimBottom ? cropTrimBottom.value : 0) || 0;
  return { left, top, right, bottom };
}
function loadImage(url) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('crop_image_load_failed'));
    img.src = url;
  });
}
async function renderCropEditorPreview() {
  if (!S.cropEditor || !cropEditorPreview) return;
  syncCropReadouts();
  const { result } = S.cropEditor;
  const img = await loadImage(result.dataUrl);
  const vals = cropEditorValues();
  const maxTrim = 45;
  const leftPx = Math.floor(img.width * Math.min(maxTrim, Math.max(0, vals.left)) / 100);
  const topPx = Math.floor(img.height * Math.min(maxTrim, Math.max(0, vals.top)) / 100);
  const rightPx = Math.floor(img.width * Math.min(maxTrim, Math.max(0, vals.right)) / 100);
  const bottomPx = Math.floor(img.height * Math.min(maxTrim, Math.max(0, vals.bottom)) / 100);
  let sx = leftPx, sy = topPx;
  let sw = Math.max(1, img.width - leftPx - rightPx);
  let sh = Math.max(1, img.height - topPx - bottomPx);
  if (sw < 8 || sh < 8) { sx = 0; sy = 0; sw = img.width; sh = img.height; }

  const cvs = cropEditorPreview;
  const ctx = cvs.getContext('2d');
  cvs.width = 512; cvs.height = 512;
  ctx.clearRect(0,0,cvs.width,cvs.height);
  const scale = Math.min(cvs.width / sw, cvs.height / sh);
  const dw = Math.max(1, Math.round(sw * scale));
  const dh = Math.max(1, Math.round(sh * scale));
  const dx = Math.round((cvs.width - dw) / 2);
  const dy = Math.round((cvs.height - dh) / 2);
  ctx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh);
}
// Shared: given a processed square icon and { left, top, right, bottom } (percent
// trims), produce a re-centered square icon. Used both by the crop editor and by
// the silent per-category saved-crop path so the two always match exactly.
function cropTrimToPixels(img, vals) {
  const maxTrim = 45;
  const leftPx = Math.floor(img.width * Math.min(maxTrim, Math.max(0, vals.left)) / 100);
  const topPx = Math.floor(img.height * Math.min(maxTrim, Math.max(0, vals.top)) / 100);
  const rightPx = Math.floor(img.width * Math.min(maxTrim, Math.max(0, vals.right)) / 100);
  const bottomPx = Math.floor(img.height * Math.min(maxTrim, Math.max(0, vals.bottom)) / 100);
  const sx = leftPx, sy = topPx;
  const sw = Math.max(1, img.width - leftPx - rightPx);
  const sh = Math.max(1, img.height - topPx - bottomPx);
  return { sx, sy, sw, sh };
}
async function cropResultWithVals(result, vals) {
  const img = await loadImage(result.dataUrl);
  const { sx, sy, sw, sh } = cropTrimToPixels(img, vals);
  if (sw < 8 || sh < 8) throw new Error('crop_too_small');

  const out = document.createElement('canvas');
  out.width = img.width;
  out.height = img.height;
  const octx = out.getContext('2d');
  octx.clearRect(0, 0, out.width, out.height);
  const scale = Math.min(out.width / sw, out.height / sh);
  const dw = Math.max(1, Math.round(sw * scale));
  const dh = Math.max(1, Math.round(sh * scale));
  const dx = Math.round((out.width - dw) / 2);
  const dy = Math.round((out.height - dh) / 2);
  octx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh);
  const png = out.toDataURL('image/png');
  return {
    ...result,
    dataUrl: png,
    imageBase64: png.split(',')[1],
    meta: { ...(result.meta || {}), manualCrop: { left: vals.left, top: vals.top, right: vals.right, bottom: vals.bottom } },
  };
}
async function buildCroppedResult(result) {
  return cropResultWithVals(result, cropEditorValues());
}
// Silently apply a category's saved crop to a freshly processed icon.
async function applySavedCropToResult(result, saved) {
  return cropResultWithVals(result, {
    left: Number(saved.left) || 0,
    top: Number(saved.top) || 0,
    right: Number(saved.right) || 0,
    bottom: Number(saved.bottom) || 0,
  });
}
function openCropEditor(result, payload) {
  if (!cropEditorModal) return Promise.resolve(result);
  S.cropEditor = { result, payload };
  const cat = String((payload && payload.category) || S.activeCategory || '').toLowerCase();
  // Pre-fill sliders from any existing saved crop for this category so the admin
  // adjusts from the current setting instead of starting at zero.
  const saved = savedCropFor(cat) || { left: 0, top: 0, right: 0, bottom: 0 };
  if (cropTrimLeft) cropTrimLeft.value = saved.left || 0;
  if (cropTrimTop) cropTrimTop.value = saved.top || 0;
  if (cropTrimRight) cropTrimRight.value = saved.right || 0;
  if (cropTrimBottom) cropTrimBottom.value = saved.bottom || 0;
  if ($('cropEditorCat')) $('cropEditorCat').textContent = CAT_LABELS[cat] || cat || 'this category';
  syncCropReadouts();
  cropEditorModal.classList.remove('hidden');
  renderCropEditorPreview().catch(() => {});
  return new Promise((resolve, reject) => {
    S.cropEditor.resolve = resolve;
    S.cropEditor.reject = reject;
  });
}
function closeCropEditor() {
  if (cropEditorModal) cropEditorModal.classList.add('hidden');
  S.cropEditor = null;
}
async function saveCropEditor(useAuto) {
  if (!S.cropEditor) return;
  const payload = S.cropEditor.payload || {};
  const cat = String(payload.category || S.activeCategory || '').toLowerCase();
  try {
    const vals = cropEditorValues();
    const finalResult = useAuto ? S.cropEditor.result : await buildCroppedResult(S.cropEditor.result);
    if (capturePreview && finalResult.dataUrl) {
      capturePreview.src = finalResult.dataUrl;
      capturePreview.classList.remove('hidden');
    }

    // Persist this crop for the category (unless the admin chose plain auto-crop).
    if (!useAuto && cat) {
      const crop = { left: vals.left, top: vals.top, right: vals.right, bottom: vals.bottom };
      S.captureCrops[cat] = crop;
      post('saveCaptureCrop', { category: cat, ...crop });
      toast(`Crop saved for ${CAT_LABELS[cat] || cat}. It now applies to every capture of this category.`, 'success');
    }
    S.armCropForCategory = null;
    syncCropSection();

    const res = S.cropEditor.resolve;
    closeCropEditor();
    if (res) res(finalResult);
  } catch (err) {
    toast(`Crop failed: ${err.message || err}`, 'error');
  }
}
function cancelCropEditor() {
  if (!S.cropEditor) return;
  const rej = S.cropEditor.reject;
  S.armCropForCategory = null;
  closeCropEditor();
  if (rej) rej(new Error('crop_cancelled'));
}

function showPurchaseStatus(message, type) {
  if (!purchaseStatus) return;
  purchaseStatus.innerHTML = message || 'Items will go to inventory first. Wear them later from inventory.';
  purchaseStatus.classList.remove('hidden', 'is-error', 'is-success');
  if (type) purchaseStatus.classList.add(`is-${type}`);
}

function hidePurchaseStatus() {
  if (!purchaseStatus) return;
  purchaseStatus.classList.add('hidden');
  purchaseStatus.classList.remove('is-error', 'is-success');
}

function setCaptureStatus(show, text) {
  if (!captureStatus) return;
  captureStatus.textContent = text || 'Processing…';
  captureStatus.classList.toggle('hidden', !show);
}

// Lightweight transient toast. Reuses the capture toast element so messages
// (crop saved, errors, etc.) surface without adding new UI. Auto-hides.
let _toastTimer = null;
function toast(message, _type) {
  if (!captureStatus) return;
  captureStatus.textContent = String(message || '');
  captureStatus.classList.remove('hidden');
  if (_toastTimer) clearTimeout(_toastTimer);
  _toastTimer = setTimeout(() => {
    if (!S.bulkRunning) captureStatus.classList.add('hidden');
  }, 2600);
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
  if ($('catMissingBtn')) $('catMissingBtn').disabled = disabled || !S.isAdmin;
  if ($('catAllBtn'))     $('catAllBtn').disabled     = disabled || !S.isAdmin;
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

  // Manual pose-and-shoot only applies to a genuine single capture of an
  // accessory/shoe category. Multi-texture and whole-category loops run auto.
  if (S.manualMode && S.singleManual && MANUAL_POSE_CATS.has(String(S.activeCategory))) {
    target.manual = true;
  }

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
  S.captureMode = 'category_' + mode;
  S.manualCropNextCapture = false;
  // Manual pose-and-shoot for accessories/shoes: pose the FIRST texture by hand,
  // then the remaining textures reuse that exact angle/lift/camera automatically.
  const manualRun = S.manualMode && MANUAL_POSE_CATS.has(String(S.activeCategory));
  S.singleManual = manualRun && (mode === 'current' && indices.length === 1);
  applyBulkDisabled(true);

  let saved = 0; const failed = [];
  for (let i = 0; i < indices.length; i++) {
    if (S.bulkCancel) break;
    const tex = indices[i];
    // Only the first texture is posed by hand; the rest replay the remembered pose.
    S.singleManual = manualRun && i === 0;
    setCaptureStatus(true, `Saving ${i+1}/${indices.length} (T${tex})…`);
    setBulkProgress(`Saving ${i+1}/${indices.length} · T${tex}`);
    const r = await captureOneTexture(tex);
    if (r && r.success) saved++;
    else failed.push(`T${tex}: ${r?.error || 'failed'}`);
    await delay(350);
  }
  S.bulkRunning = false;
  S.captureMode = null;
  S.manualCropNextCapture = false;
  S.singleManual = false;
  applyBulkDisabled(false);
  setCaptureStatus(false);
  renderTextureStatus();
  renderCategories();
  const done = S.bulkCancel ? 'Cancelled' : 'Done';
  setBulkProgress(`${done}: saved ${saved}/${indices.length}${failed.length ? ` · Failed: ${failed.join(', ')}` : ''}`, true);
  setTimeout(() => setBulkProgress('', false), 5000);
}

// Batch capture EVERY drawable in the active category (one icon per item, texture 0).
// mode 'missing' skips items that already have an image; 'all' recaptures everything.
// Each item is auto-named, auto-priced, and routed to store/hidden by the economy rules.
async function runCategoryCapture(mode) {
  if (!S.isAdmin || !S.activeCategory || S.bulkRunning) return;
  const cat = S.activeCategory;
  if (cat === 'arms' || cat === '__fav') {
    setBulkProgress('Pick a clothing category first.', true);
    setTimeout(() => setBulkProgress('', false), 2500);
    return;
  }

  const rows = getRowsForCategory(cat).slice();
  const targets = mode === 'missing' ? rows.filter(r => !hasImage(r)) : rows;
  if (!targets.length) {
    setBulkProgress(mode === 'missing' ? 'Every item here already has an image.' : 'Nothing to capture.', true);
    setTimeout(() => setBulkProgress('', false), 2500);
    return;
  }
  if (!window.confirm(`Capture ${targets.length} ${CAT_LABELS[cat] || cat} item(s)? This can take a few minutes — don't touch the game while it runs.`)) return;

  S.bulkRunning = true;
  S.bulkCancel  = false;
  S.captureMode = 'wholecategory_' + mode;
  S.manualCropNextCapture = false;
  applyBulkDisabled(true);

  let saved = 0, empty = 0; const failed = [];
  for (let i = 0; i < targets.length; i++) {
    if (S.bulkCancel) break;
    const row = targets[i];

    // Select this drawable so preview + capture use it.
    const pos = S.filtered.findIndex(r => drawKey(r) === drawKey(row));
    S.itemPos  = pos >= 0 ? pos : 0;
    S.selected = row;
    S.texture  = 0;

    // Auto name / price / destination for this item.
    const auto = autoPriceFor(row);
    if (customItemName) customItemName.value = String(row.label || `${CAT_LABELS[cat] || cat} ${row.drawable}`);
    if (auto) {
      if (customItemPrice) customItemPrice.value = String(auto.price);
      if (itemDestination) itemDestination.value = auto.dest;
    }
    updateBottom();

    const tag = `#${row.drawable}${auto && auto.addon ? ' · Add-on' : ''}`;
    setCaptureStatus(true, `Capturing ${i + 1}/${targets.length} · ${tag}`);
    setBulkProgress(`Capturing ${i + 1}/${targets.length} · ${tag}`);

    const r = await captureOneTexture(0);
    if (r && r.success) saved++;
    else if (r && /empty|too_small|no pixels/i.test(String(r.error || ''))) { empty++; failed.push(`#${row.drawable}: empty`); }
    else failed.push(`#${row.drawable}: ${r?.error || 'failed'}`);
    await delay(300);
  }

  S.bulkRunning = false;
  S.captureMode = null;
  S.manualCropNextCapture = false;
  applyBulkDisabled(false);
  setCaptureStatus(false);
  renderTextureStatus();
  renderCategories();

  const done = S.bulkCancel ? 'Cancelled' : 'Done';
  const emptyStr = empty ? ` · ${empty} empty — re-shoot these` : '';
  const failStr  = failed.length ? ` · ${failed.slice(0, 6).join(', ')}${failed.length > 6 ? '…' : ''}` : '';
  setBulkProgress(`${done}: saved ${saved}/${targets.length}${emptyStr}${failStr}`, true);
  setTimeout(() => setBulkProgress('', false), 9000);
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
      const ac  = payload.autoCrop || {};
      const bg  = String(payload.captureBackground || payload.backgroundColor || 'green').toLowerCase();

      // Chroma key params. The normal key is conservative so green clothing is safer.
      // The broad key is only used by edge flood-fill, so it can also remove
      // shadowed/darker green backdrop without eating disconnected green clothes.
      const minGreen    = Number(ch.minGreen  ?? 95);
      const dominance   = Number(ch.dominance ?? 1.35);
      const greenMargin = Number(ch.greenMargin ?? 35);
      const maxRed      = Number(ch.maxRed    ?? 130);
      const maxBlue     = Number(ch.maxBlue   ?? 150);
      const soften      = ch.soften !== false;
      const shadowKey   = ch.shadowKey !== false;
      const shadowMinGreen    = Number(ch.shadowMinGreen ?? 35);
      const shadowDominance   = Number(ch.shadowDominance ?? 1.10);
      const shadowGreenMargin = Number(ch.shadowGreenMargin ?? 8);

      // Crop region. This is a generous safety window. After background removal,
      // we auto-trim to the real visible clothing pixels.
      const crop   = payload.crop || {};
      const rx = clamp01(crop.x, 0.10), ry = clamp01(crop.y, 0.05);
      const rw = clamp01(crop.w, 0.80), rh = clamp01(crop.h, 0.90);
      const minX = Math.max(0, Math.floor(src.width  * rx));
      const minY = Math.max(0, Math.floor(src.height * ry));
      const maxX = Math.min(src.width  - 1, Math.ceil(src.width  * Math.min(1, rx + rw)));
      const maxY = Math.min(src.height - 1, Math.ceil(src.height * Math.min(1, ry + rh)));

      const idx = (x, y) => (y * src.width + x) * 4;
      const key1 = (x, y) => y * src.width + x;
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

      function isBroadKey(i) {
        if (isKey(i)) return true;
        if (!shadowKey) return false;
        const r = d[i], g = d[i+1], b = d[i+2];
        if (bg === 'green') {
          return g >= shadowMinGreen &&
            g > Math.max(r,b) * shadowDominance &&
            (g - Math.max(r,b)) >= shadowGreenMargin &&
            r <= Math.max(165, maxRed + 30) && b <= Math.max(180, maxBlue + 30);
        }
        if (bg === 'blue') {
          return b >= 45 && b > Math.max(r,g) * 1.08 && (b - Math.max(r,g)) >= 8;
        }
        if (bg === 'magenta' || bg === 'pink') {
          return r >= 55 && b >= 55 && g <= 165 && (Math.min(r,b) - g) >= 8;
        }
        if (bg === 'white') {
          return r >= 185 && g >= 185 && b >= 185;
        }
        if (bg === 'black') {
          return r <= 45 && g <= 45 && b <= 45;
        }
        return false;
      }

      function shouldRunHeadFallback() {
        const cat = String(payload.category || '').toLowerCase();
        if (payload.forceRemoveHead === false) return false;
        return ['torso','tshirt','armor','chains','bags'].includes(cat);
      }

      function isSkinLike(i) {
        const r = d[i], g = d[i+1], b = d[i+2], a = d[i+3];
        if (a <= 10) return false;
        const max = Math.max(r,g,b), min = Math.min(r,g,b);
        return r > 75 && g > 35 && b > 20 && (max - min) > 15 && r > g * 1.05 && r > b * 1.18 && (r - b) > 18;
      }

      function removeHeadFallbackPixels() {
        if (!shouldRunHeadFallback()) return 0;
        const cat = String(payload.category || '').toLowerCase();
        let count = 0;

        if (['torso','tshirt','armor','chains','bags'].includes(cat)) {
          const cx = Math.floor(minX + (maxX - minX) * 0.50);
          const cy = Math.floor(minY + (maxY - minY) * 0.16);
          const rxE = Math.floor((maxX - minX) * 0.135);
          const ryE = Math.floor((maxY - minY) * 0.125);
          for (let y = Math.max(minY, cy - ryE); y <= Math.min(maxY, cy + ryE); y++) {
            for (let x = Math.max(minX, cx - rxE); x <= Math.min(maxX, cx + rxE); x++) {
              const nx = (x - cx) / Math.max(1, rxE);
              const ny = (y - cy) / Math.max(1, ryE);
              if ((nx*nx + ny*ny) <= 1.05 && d[idx(x,y)+3] > 10) {
                d[idx(x,y)+3] = 0; count++;
              }
            }
          }
        }

        return count;
      }

      function nearTransparent(x, y) {
        for (let yy = Math.max(minY, y-1); yy <= Math.min(maxY, y+1); yy++)
          for (let xx = Math.max(minX, x-1); xx <= Math.min(maxX, x+1); xx++)
            if (isTransparent(xx, yy)) return true;
        return false;
      }

      let removed = 0;

      // Step 1: remove everything outside the generous crop window.
      for (let y = 0; y < src.height; y++) {
        for (let x = 0; x < src.width; x++) {
          if (x < minX || x > maxX || y < minY || y > maxY) makeTransparent(x, y);
        }
      }

      // Step 2: edge flood-fill background removal.
      // This is what removes daylight/shadow variation from the green screen.
      // It starts only from crop edges, so disconnected green clothing is much safer.
      if (ac.floodFillBackground !== false) {
        const visited = new Uint8Array(src.width * src.height);
        const queue = [];
        const push = (x, y) => {
          if (x < minX || x > maxX || y < minY || y > maxY) return;
          const k = key1(x, y);
          if (visited[k]) return;
          visited[k] = 1;
          const i = idx(x, y);
          if (d[i+3] > 10 && isBroadKey(i)) queue.push([x, y]);
        };

        for (let x = minX; x <= maxX; x++) { push(x, minY); push(x, maxY); }
        for (let y = minY; y <= maxY; y++) { push(minX, y); push(maxX, y); }

        for (let q = 0; q < queue.length; q++) {
          const [x, y] = queue[q];
          const i = idx(x, y);
          if (d[i+3] > 10) { d[i+3] = 0; removed++; }
          push(x + 1, y); push(x - 1, y); push(x, y + 1); push(x, y - 1);
        }
      }

      // Step 3: normal chroma key inside crop.
      for (let y = minY; y <= maxY; y++) {
        for (let x = minX; x <= maxX; x++) {
          const i = idx(x, y);
          if (d[i+3] > 10 && isKey(i)) { d[i+3] = 0; removed++; }
        }
      }

      // Step 4: green de-spill on remaining item edge pixels.
      if (soften && bg === 'green') {
        for (let y = minY; y <= maxY; y++) {
          for (let x = minX; x <= maxX; x++) {
            const i = idx(x, y);
            if (d[i+3] > 10 && nearTransparent(x, y) && d[i+1] > d[i]*1.12 && d[i+1] > d[i+2]*1.12) {
              d[i+1] = Math.max(d[i], d[i+2]);
            }
          }
        }
      }

      // Step 5: fallback head removal if streamed invisible head/reset flag fails.
      removed += removeHeadFallbackPixels();

      // Step 6: remove tiny isolated leftover pixels caused by shadow/compression.
      const passes = ac.removeLoosePixels === false ? 0 : Math.max(0, Number(ac.loosePixelPasses ?? 1));
      for (let pass = 0; pass < passes; pass++) {
        const toClear = [];
        for (let y = minY + 1; y <= maxY - 1; y++) {
          for (let x = minX + 1; x <= maxX - 1; x++) {
            const i = idx(x, y);
            if (d[i+3] <= 10) continue;
            let neighbours = 0;
            if (d[idx(x+1,y)+3] > 10) neighbours++;
            if (d[idx(x-1,y)+3] > 10) neighbours++;
            if (d[idx(x,y+1)+3] > 10) neighbours++;
            if (d[idx(x,y-1)+3] > 10) neighbours++;
            if (neighbours <= 1) toClear.push(i);
          }
        }
        for (const i of toClear) { d[i+3] = 0; removed++; }
      }

      // Step 7: find a tight bounding box around the final visible clothing pixels.
      const alphaMin = Number(ac.minAlpha ?? 12);
      let bMinX = src.width, bMinY = src.height, bMaxX = 0, bMaxY = 0;
      for (let y = minY; y <= maxY; y++) {
        for (let x = minX; x <= maxX; x++) {
          const a = d[idx(x,y)+3];
          if (a > alphaMin) {
            if (x < bMinX) bMinX = x; if (y < bMinY) bMinY = y;
            if (x > bMaxX) bMaxX = x; if (y > bMaxY) bMaxY = y;
          }
        }
      }

      if (bMaxX <= bMinX || bMaxY <= bMinY) { reject(new Error('icon_empty_or_too_small')); return; }

      const bboxW = bMaxX - bMinX + 1, bboxH = bMaxY - bMinY + 1;
      const minRatio = Number(ac.minItemRatio ?? 0.025);
      const minSide = Math.max(8, Math.floor(Math.min(src.width, src.height) * minRatio));
      if (bboxW < minSide && bboxH < minSide) { reject(new Error('icon_empty_or_too_small')); return; }

      let pad = Number(payload.padding ?? 18);
      if (payload.crop && Number.isFinite(Number(payload.crop.padding))) pad = Number(payload.crop.padding);
      const fMinX = Math.max(0, bMinX - pad), fMinY = Math.max(0, bMinY - pad);
      const fMaxX = Math.min(src.width-1, bMaxX + pad), fMaxY = Math.min(src.height-1, bMaxY + pad);
      const fW = fMaxX - fMinX + 1, fH = fMaxY - fMinY + 1;

      sctx.putImageData(imageData, 0, 0);

      const out = document.createElement('canvas');
      let meta;

      if (ac.squareOutput !== false) {
        const outW = Math.max(32, Number(ac.outputWidth || payload.width || 512));
        const outH = Math.max(32, Number(ac.outputHeight || payload.height || 512));
        const outPad = Math.max(0, Number(ac.outputPadding ?? 18));
        const fitW = Math.max(1, outW - outPad * 2);
        const fitH = Math.max(1, outH - outPad * 2);
        const scale = Math.min(fitW / fW, fitH / fH);
        const drawW = Math.max(1, Math.round(fW * scale));
        const drawH = Math.max(1, Math.round(fH * scale));
        const dx = Math.round((outW - drawW) / 2);
        const dy = Math.round((outH - drawH) / 2);

        out.width = outW;
        out.height = outH;
        const octx = out.getContext('2d');
        octx.clearRect(0, 0, outW, outH);
        octx.drawImage(src, fMinX, fMinY, fW, fH, dx, dy, drawW, drawH);

        meta = {
          removedPixels: removed,
          width: outW,
          height: outH,
          background: bg,
          sourceCrop: { x: fMinX, y: fMinY, w: fW, h: fH },
          fitted: { x: dx, y: dy, w: drawW, h: drawH, scale },
        };
      } else {
        out.width = fW;
        out.height = fH;
        out.getContext('2d').drawImage(src, fMinX, fMinY, fW, fH, 0, 0, fW, fH);
        meta = { removedPixels: removed, width: fW, height: fH, background: bg,
                 crop: { x: fMinX, y: fMinY, w: fW, h: fH } };
      }

      const png = out.toDataURL('image/png');
      resolve({
        dataUrl: png,
        imageBase64: png.split(',')[1],
        meta,
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

    case 'favourites':
      S.favourites = new Set((data.keys || []).map(k => String(k).toLowerCase()));
      updateFavButton();
      renderCategories();
      if (S.activeCategory === '__fav') setCategory('__fav');
      break;

    case 'captureCrops':
      S.captureCrops = data.crops || {};
      syncCropSection();
      break;

    case 'manualPoseStart':
      enterPoseMode(data.category, Number(data.heading) || 0);
      break;

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

    case 'purchaseResult':
      S.checkoutBusy = false;
      if (checkoutModal) checkoutModal.classList.add('hidden');
      showPurchaseStatus(data.message || (data.success ? '<strong>Purchased.</strong> Item is now in inventory.' : '<strong>Purchase failed.</strong> Try again.'), data.success ? 'success' : 'error');
      if (data.success) { S.cart = []; updateCartUI(); }
      break;

    case 'processIconImage':
      setCaptureStatus(true, 'Removing background…');
      removeBackgroundAndCrop(data.image, data.payload || {})
        .then(result => {
          if (capturePreview && result.dataUrl) {
            capturePreview.src = result.dataUrl;
            capturePreview.classList.remove('hidden');
          }
          const cat = String((data.payload && data.payload.category) || S.activeCategory || '').toLowerCase();

          // Manual pose shot just confirmed: always open the crop editor so the
          // admin trims and saves this hand-posed image.
          if (S.manualShotPending) {
            S.manualShotPending = false;
            setCaptureStatus(true, 'Crop the shot, then save…');
            return openCropEditor(result, data.payload || {});
          }

          // 1) Admin is (re)setting the crop for this category: open the editor.
          //    Whatever they save becomes the category's persistent crop.
          //    Only during a single capture — never mid category bulk run.
          const inCategoryBulk = String(S.captureMode || '').startsWith('wholecategory_');
          if (S.armCropForCategory && S.armCropForCategory === cat && !inCategoryBulk) {
            setCaptureStatus(true, 'Set the crop for this category, then save…');
            return openCropEditor(result, data.payload || {});
          }

          // 2) A saved crop exists for this category: apply it silently so every
          //    capture of this category is cropped the same way, no editor needed.
          const saved = savedCropFor(cat);
          if (saved) {
            return applySavedCropToResult(result, saved).catch(() => result);
          }

          return result;
        })
        .then(result => post('iconProcessed', { ...result, payload: data.payload || {} }))
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


// Filters
function readFilters() {
  S.filters = {
    q: searchInput ? searchInput.value : '',
    gender: genderFilter ? genderFilter.value : 'all',
    drawable: drawableFilter ? drawableFilter.value : '',
    minPrice: minPriceFilter ? minPriceFilter.value : '',
    maxPrice: maxPriceFilter ? maxPriceFilter.value : '',
  };
  if (S.activeCategory) setCategory(S.activeCategory);
}
[searchInput, genderFilter, drawableFilter, minPriceFilter, maxPriceFilter].forEach(el => {
  if (el) el.addEventListener(el.tagName === 'SELECT' ? 'change' : 'input', readFilters);
});

// Favourites star
if ($('favBtn')) $('favBtn').addEventListener('click', toggleCurrentFavourite);

// Admin per-category crop section
if ($('setCropBtn')) $('setCropBtn').addEventListener('click', armCropSetup);
if ($('clearCropBtn')) $('clearCropBtn').addEventListener('click', clearSavedCrop);
if (clearFiltersBtn) clearFiltersBtn.onclick = () => {
  if (searchInput) searchInput.value = '';
  if (genderFilter) genderFilter.value = 'all';
  if (drawableFilter) drawableFilter.value = '';
  if (minPriceFilter) minPriceFilter.value = '';
  if (maxPriceFilter) maxPriceFilter.value = '';
  readFilters();
};

if (pricePreset) pricePreset.onchange = () => {
  if (!S.selected || !customItemPrice) return;
  const presetName = pricePreset.value;
  const table = S.pricePresets[presetName] || null;
  if (table && table[S.selected.category] != null) customItemPrice.value = String(table[S.selected.category]);
  else customItemPrice.value = String(S.prices[S.selected.category] || S.selected.price || 0);
};

if (cartList) cartList.onclick = e => {
  const btn = e.target.closest('button[data-act]');
  const row = e.target.closest('.cart-row');
  if (!btn || !row) return;
  const idx = Number(row.dataset.index);
  const item = S.cart[idx];
  if (!item) return;
  const act = btn.dataset.act;
  if (act === 'inc') item.qty = Math.max(1, Number(item.qty || 1)) + 1;
  if (act === 'dec') item.qty = Math.max(1, Number(item.qty || 1)) - 1;
  if (act === 'remove' || Number(item.qty || 1) <= 0) S.cart.splice(idx, 1);
  updateCartUI();
};
if (clearCartBtn) clearCartBtn.onclick = () => { S.cart = []; updateCartUI(); hidePurchaseStatus(); };
if (confirmCancelBtn) confirmCancelBtn.onclick = () => checkoutModal && checkoutModal.classList.add('hidden');
if (confirmCashBtn) confirmCashBtn.onclick = () => processCheckout('cash');
if (confirmBankBtn) confirmBankBtn.onclick = () => processCheckout('bank');
if (checkoutModal) checkoutModal.onclick = e => { if (e.target === checkoutModal) checkoutModal.classList.add('hidden'); };

async function adminBulkToggle(enabled) {
  if (!S.isAdmin || !S.filtered.length) return;
  const visible = S.filtered.slice(0, 250).map(r => ({
    ...r,
    label: customItemName && customItemName.value.trim() ? customItemName.value.trim() : r.label,
    price: getAdminPrice(r.price ?? S.prices[r.category]),
    destination: getAdminDest(),
    requiredJob: requiredJob ? requiredJob.value.trim() : '',
    requiredGang: requiredGang ? requiredGang.value.trim() : '',
    requiredFamily: requiredFamily ? requiredFamily.value.trim() : '',
  }));
  const ok = window.confirm(`${enabled ? 'Enable' : 'Disable'} ${visible.length} visible ${S.activeCategory} item(s)?`);
  if (!ok) return;
  setBulkProgress(`${enabled ? 'Enabling' : 'Disabling'} ${visible.length} item(s)…`);
  await post('adminBulkToggleItems', { enabled, items: visible, category: S.activeCategory });
  for (const row of visible) {
    const key = drawKey(row);
    const i = S.catalog.findIndex(c => drawKey(normRow(c)) === key);
    if (i >= 0) S.catalog[i] = { ...S.catalog[i], ...row, enabled };
    else S.catalog.push({ ...row, enabled, texture: -1, textureId: -1 });
  }
  setCategory(S.activeCategory);
  setBulkProgress(`${enabled ? 'Enabled' : 'Disabled'} ${visible.length} item(s).`, true);
  setTimeout(() => setBulkProgress('', false), 3000);
}
if (bulkEnableBtn) bulkEnableBtn.onclick = () => adminBulkToggle(true);
if (bulkDisableBtn) bulkDisableBtn.onclick = () => adminBulkToggle(false);

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
if ($('catMissingBtn')) $('catMissingBtn').onclick = async () => runCategoryCapture('missing');
if ($('catAllBtn'))     $('catAllBtn').onclick     = async () => runCategoryCapture('all');
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
  addToCart(item);
  updateCartUI();
  hidePurchaseStatus();
  $('itemName').textContent = `${item.label} added to cart`;

  // Buying is inventory-first. After adding to cart, remove the preview clothing from the ped
  // so the player does not look like they already own/wear it.
  await post('resetCartItems');
};

// Checkout
function openCheckoutModal() {
  if (!checkoutModal || S.cart.length <= 0) return;
  const count = cartItemCount();
  const total = cartAmount();
  if (confirmTitle) confirmTitle.textContent = `Buy ${count} clothing item${count === 1 ? '' : 's'}?`;
  if (confirmText) confirmText.textContent = `Total $${total}. Choose cash or bank. Items go to inventory first; wear them from your bag.`;
  if (confirmItems) confirmItems.innerHTML = S.cart.map(i => `<div><span>${i.label || i.category} × ${Math.max(1, Number(i.qty || 1))}</span><b>$${Number(i.price || 0) * Math.max(1, Number(i.qty || 1))}</b></div>`).join('');
  checkoutModal.classList.remove('hidden');
}

async function processCheckout(method) {
  if (S.checkoutBusy || S.isAdmin || S.cart.length <= 0) return;
  S.checkoutBusy = true;
  const items = expandedCartItems();
  const payment = method || S.payment || 'bank';
  showPurchaseStatus(`Processing checkout by ${payment.toUpperCase()}… items will go to inventory only.`, 'success');
  await post('buyClothes', { paymentMethod: payment, items, cart: items, name: items.map(i => i.label).join(', ') });
}

if (checkoutBtn) checkoutBtn.onclick = () => {
  if (S.isAdmin || S.cart.length <= 0) return;
  openCheckoutModal();
};

// Close
$('closeBtn').onclick = () => {
  S.isAdmin         = false;
  S.adminTorsoTarget = null;
  S.cart            = [];
  S.lastAdminSyncKey = ''; 
  hidePurchaseStatus();
  if (customItemName)   customItemName.value   = '';
  if (customItemPrice)  customItemPrice.value  = '';
  if (itemDestination)  itemDestination.value  = 'store';
  if (bulkProgress)     bulkProgress.classList.add('hidden');
  if (checkoutModal)    checkoutModal.classList.add('hidden');
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
document.addEventListener('mousedown', e => {
  // While posing, don't start a drag when clicking on the pose bar itself.
  if (S.manualPosing && poseBar && poseBar.contains(e.target)) return;
  dragging = true; lastX = e.clientX;
});
document.addEventListener('mouseup',   () => { dragging = false; });
document.addEventListener('mousemove', e => {
  if (!dragging || !S.open) return;
  const dx = e.clientX - lastX;
  lastX = e.clientX;
  if (Math.abs(dx) <= 1) return;
  if (S.manualPosing) {
    // During manual posing, drag rotates the posed ped via the manual callback.
    post('manualPoseRotate', { delta: -dx * 0.5 });
  } else {
    post('rotatePed', { delta: -dx * 0.45 });
  }
});


;[cropTrimLeft, cropTrimTop, cropTrimRight, cropTrimBottom].forEach(el => { if (el) el.addEventListener('input', () => { renderCropEditorPreview().catch(() => {}); }); });
if (cropResetBtn) cropResetBtn.addEventListener('click', () => { if (cropTrimLeft) cropTrimLeft.value = 0; if (cropTrimTop) cropTrimTop.value = 0; if (cropTrimRight) cropTrimRight.value = 0; if (cropTrimBottom) cropTrimBottom.value = 0; renderCropEditorPreview().catch(() => {}); });
if (cropSaveBtn) cropSaveBtn.addEventListener('click', () => { saveCropEditor(false); });
if (cropUseAutoBtn) cropUseAutoBtn.addEventListener('click', () => { saveCropEditor(true); });
if (cropCancelBtn) cropCancelBtn.addEventListener('click', cancelCropEditor);

// Manual mode toggle
if ($('manualMode')) $('manualMode').addEventListener('change', e => { S.manualMode = !!e.target.checked; });

// Pose bar controls
if ($('poseRotLeftBig'))  $('poseRotLeftBig').addEventListener('click',  () => poseRotate(-45));
if ($('poseRotLeft'))     $('poseRotLeft').addEventListener('click',     () => poseRotate(-15));
if ($('poseRotRight'))    $('poseRotRight').addEventListener('click',    () => poseRotate(15));
if ($('poseRotRightBig')) $('poseRotRightBig').addEventListener('click', () => poseRotate(45));
if ($('poseHeading'))     $('poseHeading').addEventListener('input', e => poseSetHeading(Number(e.target.value) || 0));
if ($('poseLiftUp'))      $('poseLiftUp').addEventListener('click',   () => poseLift(0.08));
if ($('poseLiftDown'))    $('poseLiftDown').addEventListener('click', () => poseLift(-0.08));
if ($('poseConfirm'))     $('poseConfirm').addEventListener('click', poseConfirm);
if ($('poseCancel'))      $('poseCancel').addEventListener('click', poseCancel);
