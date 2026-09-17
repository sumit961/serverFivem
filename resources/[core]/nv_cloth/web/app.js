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
const adjustCaptureBtn  = $('adjustCaptureBtn');
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
const captureBackground = $('captureBackground');
const previewWall = $('previewWall');
const previewWallWrap = $('previewWallWrap');
const sharedGender      = $('sharedGender');
const sharedGenderWrap  = $('sharedGenderWrap');
const textureStatus     = $('textureStatus');
const bulkProgress      = $('bulkProgress');
const capturePreview    = $('capturePreview');
const bagPairOverlay       = $('bagPairOverlay');
const bagPairGenderLabel   = $('bagPairGenderLabel');
const bagPairSourceLabel   = $('bagPairSourceLabel');
const bagPairSourceGender  = $('bagPairSourceGender');
const bagPairSourceDrawable = $('bagPairSourceDrawable');
const bagPairSourceTexture = $('bagPairSourceTexture');
const bagPairDrawableInput = $('bagPairDrawableInput');
const bagPairDrawableTotal = $('bagPairDrawableTotal');
const bagPairTextureInput  = $('bagPairTextureInput');
const bagPairTextureTotal  = $('bagPairTextureTotal');
const bagPairPrev          = $('bagPairPrev');
const bagPairNext          = $('bagPairNext');
const bagPairTexPrev       = $('bagPairTexPrev');
const bagPairTexNext       = $('bagPairTexNext');
const bagPairTurnPed       = $('bagPairTurnPed');
const bagPairConfirm       = $('bagPairConfirm');
const bagPairSkip          = $('bagPairSkip');
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
const pauseBulkBtn      = $('pauseBulkBtn');
const resumeBulkBtn     = $('resumeBulkBtn');
const allGendersBtn     = $('allGendersBtn');
const failedCapturePanel = $('failedCapturePanel');
const failedCaptureCount = $('failedCaptureCount');
const failedCaptureList = $('failedCaptureList');
// Only checkout payment buttons belong here. The store manager reuses the
// visual .pay-tab class for its MALE/FEMALE controls; selecting every .pay-tab
// caused this later payment handler to overwrite setManageGender().
const payTabs           = document.querySelectorAll('#payTabs .pay-tab');
const brandAdmin        = $('brandAdmin');
const brandNote         = $('brandNote');
const brandSub          = $('brandSub');
const rpEyebrow         = $('rpEyebrow');
const modeNote          = $('modeNote');
const controlsHint      = $('controlsHint');
const adminGenderSwitch = $('adminGenderSwitch');
const adminGenderMale   = $('adminGenderMale');
const adminGenderFemale = $('adminGenderFemale');
const adminGenderState  = $('adminGenderState');
/* /clothingstore manager */
const managePanel         = $('managePanel');
const manageCloseBtn      = $('manageCloseBtn');
const manageGenderMale    = $('manageGenderMale');
const manageGenderFemale  = $('manageGenderFemale');
const manageCategoryFilter = $('manageCategoryFilter');
const manageStatusFilter  = $('manageStatusFilter');
const manageSearch        = $('manageSearch');
const manageRefreshBtn    = $('manageRefreshBtn');
const manageCount         = $('manageCount');
const manageGrid          = $('manageGrid');
const manageDetailEmpty   = $('manageDetailEmpty');
const manageDetailBody    = $('manageDetailBody');
const manageDetailImg     = $('manageDetailImg');
const manageDetailNoImg   = $('manageDetailNoImg');
const manageDetailMeta    = $('manageDetailMeta');
const manageLabel         = $('manageLabel');
const managePrice         = $('managePrice');
const manageTempDisabled  = $('manageTempDisabled');
const manageOrgChoices    = $('manageOrgChoices');
const manageOrgSection    = $('manageOrgSection');
const manageArmorTypeSection = $('manageArmorTypeSection');
const manageArmorType     = $('manageArmorType');
const manageArmorSection  = $('manageArmorSection');
const manageArmorValue    = $('manageArmorValue');
const manageBagLevelSection = $('manageBagLevelSection');
const manageBagLevel      = $('manageBagLevel');
const manageBagPairSection = $('manageBagPairSection');
const manageBagPairGrid    = $('manageBagPairGrid');
const manageBagPairRestore = $('manageBagPairRestore');
const manageLockBanner    = $('manageLockBanner');
const manageAuditTrail    = $('manageAuditTrail');
const managePublishBtn    = $('managePublishBtn');
const manageSaveBtn       = $('manageSaveBtn');
const managePreviewBtn    = $('managePreviewBtn');
const manageRetakeBtn     = $('manageRetakeBtn');
const manageRevertBtn     = $('manageRevertBtn');
const manageCoverBtn      = $('manageCoverBtn');
const manageDetailState   = $('manageDetailState');
const manageTorsoFit      = $('manageTorsoFit');
const manageArmsPrev      = $('manageArmsPrev');
const manageArmsNext      = $('manageArmsNext');
const manageArmsValue     = $('manageArmsValue');
const manageUnderPrev     = $('manageUnderPrev');
const manageUnderNext     = $('manageUnderNext');
const manageUnderValue    = $('manageUnderValue');
const manageSaveTorsoFit  = $('manageSaveTorsoFit');
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
  bracelets: svgIcon('watch'),
};
const CAT_LABELS = {
  torso: 'Outerwear', armor: 'Armor / Vest', arms: 'Arms / Fit', tshirt: 'Shirts',
  pants: 'Pants & Shorts', shoes: 'Shoes', hat: 'Headwear',
  glasses: 'Glasses', earrings: 'Earrings', chains: 'Accessories',
  bags: 'Bags', watches: 'Watches', bracelets: 'Bracelets',
};

// Categories that support manual "pose the ped, then confirm" capture.
const MANUAL_POSE_CATS = new Set(['torso', 'tshirt', 'pants', 'shoes', 'hat', 'glasses', 'earrings', 'chains', 'bags', 'watches', 'bracelets', 'armor']);


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
const PROP_IDX_CAT  = { 0:'hat', 1:'glasses', 2:'earrings', 6:'watches', 7:'bracelets' };
const CAT_NATIVE = {
  torso:{type:'component',index:11}, tshirt:{type:'component',index:8},
  arms:{type:'component',index:3}, pants:{type:'component',index:4},
  shoes:{type:'component',index:6}, chains:{type:'component',index:7},
  bags:{type:'component',index:5}, armor:{type:'component',index:9},
  hat:{type:'prop',index:0}, glasses:{type:'prop',index:1},
  earrings:{type:'prop',index:2}, watches:{type:'prop',index:6},
  bracelets:{type:'prop',index:7},
};

/* ── Capture presets (server-mirrored) ─────────────── */
const CAPTURE_PRESETS = {
  torso:    { angle:'front',  zOffset:0.00, bg:'green' },
  armor:    { angle:'front',  zOffset:0.00, bg:'green' },
  tshirt:   { angle:'front',  zOffset:0.00, bg:'green' },
  pants:    { angle:'front',  zOffset:0.00, bg:'green' },
  shoes:    { angle:'front',  zOffset:0.00, bg:'green' },
  bags:     { angle:'back',   zOffset:0.00, bg:'green', sharedGender:true },
  hat:      { angle:'front',  zOffset:0.00, bg:'green' },
  glasses:  { angle:'front',  zOffset:0.00, bg:'green' },
  earrings: { angle:'right',  zOffset:0.00, bg:'green' },
  chains:   { angle:'front',  zOffset:0.00, bg:'green' },
  watches:  { angle:'left',   zOffset:0.00, bg:'green' },
  bracelets:{ angle:'right',  zOffset:0.00, bg:'green' },
};

/* ── App state ─────────────────────────────────────── */
let S = {
  open: false,
  isAdmin: false,
  adminGender: 'male',
  adminGenderSwitching: false,
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
  pendingRetake: null,                 // clothe handed over by /clothingstore for an image retake
  // Asset id of the clothe being retaken. While this is set, TAKE IMAGE
  // REPLACES that item -- new garment and new photo together -- instead of
  // adding a new one, so the admin can browse to different clothes during a
  // retake and have the item become them.
  retakeAssetId: null,
  retakeLabel: '',
  activeReplaceAssetId: null,          // armed for the single capture in flight only
  cart: [],
  favourites: new Set(),   // fav keys: gender:category:drawable (global across shops)
  captureCrops: {},         // admin: saved per-category crop { left, top, right, bottom }
  armCropForCategory: null,  // when set to a category, the next capture opens the crop editor to (re)set it
  manualPosing: false,       // true while the on-screen pose bar is up
  singleManual: false,       // current run is a single manual-eligible capture
  manualDrag: null,          // drag state for rotate-by-drag
  economy: {},              // auto-pricing config (from Config.Economy)
  bulkRunning: false,
  bulkCancel: false,
  bulkPaused: false,
  bulkFailures: [],
  pendingIconResolver: null,
  pricePresets: {},
  captureSettings: { maxRetries: 2, retryDelay: 650 },
  filters: { q: '', gender: 'all', drawable: '', minPrice: '', maxPrice: '' },
  checkoutBusy: false,
  lastAdminSyncKey: '',
  captureMode: null,
  manualCropNextCapture: false,
  cropEditor: null,
  // Post-capture bag pairing (see enterBagPairing). Non-null only while the
  // admin is being asked to pick the matching bag on the other gender, right
  // inside /clothingadmin -- never touches S.filtered/S.selected so it can't
  // corrupt normal capture browsing state.
  bagPairing: null,
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
  const rawIndex = row.componentIndex ?? row.component_index;
  if (rawIndex !== undefined && rawIndex !== null && rawIndex !== '') {
    const tp = String(row.componentType || row.component_type || 'component').toLowerCase();
    const indexedCategory = tp === 'prop' ? PROP_IDX_CAT[Number(rawIndex)] : COMP_IDX_CAT[Number(rawIndex)];
    // Native component metadata is unambiguous. In particular, old catalogs may
    // call both component 8 and component 11 "shirt"; 8 is Shirts/T-shirt while
    // 11 is Outerwear. Trust the actual native slot so the wrong item cannot be
    // selected or captured because of a legacy label.
    if (indexedCategory) c = indexedCategory;
  }
  return c || '';
}

// Valid "sell as" targets, mirroring sv_cloth.lua's CATEGORY_COMPONENTS minus
// 'armor' -- only a genuine component-9 capture can ever be sold as real
// armor (that's the native/no-override state for it), never a target choice.
const SELL_AS_CATEGORIES = ['tshirt', 'torso', 'pants', 'shoes', 'chains', 'bags', 'hat', 'glasses', 'earrings', 'watches', 'bracelets'];

// /clothingstore "sell as" override: the category this row is priced, grouped
// and equip-mechanic'd as. Falls back to the physical category (normCat) when
// no override is set. Physical identity (componentType/componentIndex,
// texture/master merging) must keep using normCat/row.category directly --
// only shop-tab/manage-grid grouping and filtering should use this.
function effCatOf(row) {
  const phys = normCat(row);
  const sell = String(row.sellCategory || row.sell_category || '').toLowerCase();
  return (sell && sell !== phys) ? sell : phys;
}

function exactCmItemName(row = {}) {
  const v = row.itemName || row.item_name || row.nameKey || row.name_key || row.inventoryItem || row.inventory_item || row.item_key || '';
  const key = String(v || '').trim();
  // Do not use display labels as inventory item names. CM item keys are identifiers.
  return key && !/\s/.test(key) ? key : '';
}

function clothingUniqueId(gender, category, drawable, texture, row = {}) {
  const g = String(gender || S.adminGender || 'male').toLowerCase() === 'female' ? 'female' : 'male';
  const c = String(category || 'unknown').toLowerCase().replace(/[^a-z0-9_-]/g, '_');
  const native = CAT_NATIVE[c] || {};
  const type = String(row.componentType || row.component_type || native.type || 'component').toLowerCase();
  const index = Number(row.componentIndex ?? row.component_index ?? native.index ?? -1);
  const draw = Math.floor(Number(drawable) || 0);
  const texNum = Math.floor(Number(texture) || 0);
  const tex = texNum < 0 ? 'all' : String(texNum);
  return `nvcloth_${g}_${c}_${type}_${index}_d${draw}_t${tex}`;
}

function normRow(row) {
  const category = normCat(row);
  const drawable  = Number(row.drawableId ?? row.drawable_id ?? row.drawable ?? 0);
  const texRaw    = Number(row.textureId  ?? row.texture_id  ?? row.texture  ?? 0);
  const texture   = texRaw;
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
  const uniqueId = row.uniqueId || row.unique_id || row.clothingId || row.clothing_id
    || clothingUniqueId(normalised.gender, category, drawable, texRaw, row);
  normalised.uniqueId = uniqueId;
  normalised.unique_id = uniqueId;
  normalised.clothingId = uniqueId;
  normalised.clothing_id = uniqueId;
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
  const g = String(r.gender || 'all').toLowerCase();
  return `${g}:${r.category}:${Number(r.drawable)}:${t < 0 ? -1 : t}`;
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

// Catalog texture -1 means "this drawable covers every texture". It is valid
// metadata but is never a valid native preview/capture texture index.
function previewTexture(value) {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? Math.floor(n) : 0;
}

function applyTextureModeFromCatalog(preferredTex) {
  const exact = getTextureRowsForSelected();
  S.exactTextureRows = exact;
  if (!S.isAdmin && exact.length > 0) {
    let idx = exact.findIndex(r => Number(r.texture) === Number(preferredTex));
    if (idx < 0) idx = 0;
    S.texture      = previewTexture(exact[idx].texture);
    S.textureCount = exact.length;
    S.selected     = { ...S.selected, ...exact[idx] };
  } else {
    S.texture      = previewTexture(preferredTex ?? (S.selected ? S.selected.texture : 0) ?? 0);
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
    const imaged  = catalogRows(false).filter(r => effCatOf(r) === category && hasImage(r) && rowMatchesFilters(r));
    return uniqueByDrawable(imaged);
  }
  // Admin & fallback: merge catalog rows with native GTA clothing drawables
  const byDrawKey = new Map();
  for (const row of catalogRows(true).filter(r => r.category === category)) {
    const key = drawKey(row);
    const existing = byDrawKey.get(key);
    if (!existing) {
      byDrawKey.set(key, row);
      continue;
    }
    const rowMaster = Number(row.texture) < 0;
    const existingMaster = Number(existing.texture) < 0;
    if (rowMaster) {
      byDrawKey.set(key, {
        ...existing, ...row,
        image: row.image || row.icon || existing.image || existing.icon,
        icon: row.icon || row.image || existing.icon || existing.image,
      });
    } else if (existingMaster && !hasImage(existing) && hasImage(row)) {
      byDrawKey.set(key, { ...existing, image: row.image || row.icon, icon: row.icon || row.image });
    }
  }
  const count  = Number(S.counts[category] || 0);
  const result = [];
  for (let i = 0; i < count; i++) {
    const gen = {
      category, drawable: i, texture: 0,
      gender: S.adminGender,
      label: `${CAT_LABELS[category] || category} #${i + 1}`,
      price: Number(S.prices[category] || 50),
      enabled: true, generated: true,
    };
    const uid = clothingUniqueId(gen.gender, category, i, 0, gen);
    gen.uniqueId = uid;
    gen.unique_id = uid;
    gen.clothingId = uid;
    gen.clothing_id = uid;
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
      <span class="cat-left">
        <span class="cat-icon">★</span>
        <span class="cat-label">FAVOURITES</span>
      </span>
      <span class="cat-count">${S.favourites.size} ITEMS</span>`;
    favChip.onclick = () => setCategory('__fav');
    categoriesEl.appendChild(favChip);
  }

  S.categories.filter(c => c !== 'arms' && (S.isAdmin || c !== 'bags')).forEach(cat => {
    const rows        = getRowsForCategory(cat);
    const enabled     = rows.filter(r => r.enabled !== false).length;
    const isActive    = S.activeCategory === cat;

    const btn = document.createElement('button');
    btn.className = `category${isActive ? ' active' : ''}`;
    btn.disabled = S.bulkRunning;

    const countStr = S.isAdmin ? `${enabled}/${rows.length}` : (isActive ? 'ACTIVE' : `${rows.length} ITEMS`);
    btn.innerHTML = `
      <span class="cat-left">
        <span class="cat-icon">${CAT_ICONS[cat] || '★'}</span>
        <span class="cat-label">${(CAT_LABELS[cat] || cat).toUpperCase()}</span>
      </span>
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
  // "Captured" means a photo exists for this exact texture -- NOT that it's
  // published. /clothingadmin captures always save unpublished (enabled=false)
  // until an admin publishes them in /clothingstore, so requiring
  // enabled !== false here meant this pill could never show as done for a
  // capture-only session, no matter how many textures had already been shot.
  return catalogRows(true).some(r =>
    r.category === category &&
    Number(r.drawable) === Number(drawable) &&
    Number(r.texture) === t &&
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

function renderStoreTextureSwatches(has) {
  const container = $('textureSwatches');
  if (!container) return;
  if (!has || S.isAdmin) {
    container.innerHTML = '';
    return;
  }
  const count = (S.exactTextureRows && S.exactTextureRows.length > 0)
    ? S.exactTextureRows.length
    : Math.max(1, S.textureCount || 1);
  if (count <= 1) {
    container.innerHTML = '';
    return;
  }
  const palette = [
    '#2C3E50', '#E74C3C', '#3498DB', '#2ECC71', '#F1C40F', '#9B59B6',
    '#E67E22', '#1ABC9C', '#34495E', '#D35400', '#7F8C8D', '#BDC3C7',
    '#16A085', '#27AE60', '#2980B9', '#8E44AD'
  ];
  let html = '';
  const displayCount = Math.min(count, 16);
  for (let i = 0; i < displayCount; i++) {
    let texVal = i;
    if (S.exactTextureRows && S.exactTextureRows.length > 0) {
      texVal = previewTexture(S.exactTextureRows[i].texture);
    }
    const isActive = Number(S.texture) === texVal;
    const bg = palette[i % palette.length];
    html += `<button type="button" class="tex-swatch-dot${isActive ? ' active' : ''}" data-tex="${texVal}" style="background-color: ${bg};" title="Texture ${texVal}"></button>`;
  }
  container.innerHTML = html;
  container.querySelectorAll('.tex-swatch-dot').forEach(btn => {
    btn.onclick = (e) => {
      e.stopPropagation();
      const t = Number(btn.dataset.tex);
      if (S.exactTextureRows && S.exactTextureRows.length > 0) {
        const row = S.exactTextureRows.find(r => Number(r.texture) === t) || S.exactTextureRows[0];
        S.texture = previewTexture(row.texture);
        S.selected = { ...S.selected, ...row };
      } else {
        S.texture = t;
      }
      if (S.activeCategory === 'torso' && S.selected)
        S.adminTorsoTarget = { ...S.selected, texture: S.texture, textureId: S.texture };
      updateBottom();
      previewSelected();
    };
  });
  if (container) container.innerHTML = '';
}

/* ── Update right panel bottom ────────────────────── */
function updateBottom() {
  const item = S.selected;
  const has  = !!item;

  buyBtn.disabled = !has || S.bulkRunning;

  // Category Title
  const catLabel = (CAT_LABELS[S.activeCategory] || S.activeCategory || 'OUTERWEAR').toUpperCase();
  if ($('rpCategoryTitle')) {
    $('rpCategoryTitle').textContent = has ? `${catLabel} #${S.itemPos + 1}` : catLabel;
  }
  if ($('previewCategoryIcon')) {
    $('previewCategoryIcon').innerHTML = CAT_ICONS[S.activeCategory] || '👕';
  }
  if ($('previewVariantSub')) {
    $('previewVariantSub').textContent = has ? (item.label || `${catLabel} APPAREL`).toUpperCase() : 'SELECT GARMENT';
  }

  // Item name / variant
  let nameText = has ? (S.isAdmin ? item.label : `CLOTHING ITEM VARIANT #${S.itemPos + 1}`) : 'Select clothing';
  if (S.isAdmin && has) {
    if (S.activeCategory === 'arms' && S.adminTorsoTarget)
      nameText = `Fit for ${S.adminTorsoTarget.label} — pick arms/shirt`;
    else
      nameText += item.enabled === false ? '  ·  DISABLED' : '  ·  ENABLED';
  }
  $('itemName').textContent = nameText;

  // Price
  const priceVal = has ? (item.price || 50) : 0;
  $('price').textContent = String(priceVal);

  if (!S.isAdmin && buyBtn) {
    buyBtn.innerHTML = has ? `<span class="btn-content">BUY CLOTHING ($${priceVal})</span>` : `<span class="btn-content">NO ITEMS AVAILABLE</span>`;
  }

  // Floating outfit summary pill (store mode)
  if ($('outfitName')) $('outfitName').textContent = has ? item.label : 'None selected';
  if ($('outfitCost')) $('outfitCost').textContent = `$${has ? (item.price || 0) : 0}`;

  // Clothing preview image viewport
  const previewImg = $('storeClothingImg');
  const placeholder = $('storeClothingPlaceholder');
  if (previewImg && placeholder) {
    const url = has ? manageImageUrl(item) : '';
    if (url) {
      previewImg.src = url;
      previewImg.classList.remove('hidden');
      placeholder.classList.add('hidden');
    } else {
      previewImg.src = '';
      previewImg.classList.add('hidden');
      placeholder.classList.remove('hidden');
    }
  }

  // Model scrub slider sync
  const scrubSlider = $('modelScrubSlider');
  if (scrubSlider) {
    scrubSlider.max = Math.max(0, S.filtered.length - 1);
    scrubSlider.value = S.itemPos;
  }

  // Interactive texture swatches
  renderStoreTextureSwatches(has);
  // Direct cloth type & texture number inputs sync
  const typeInput = $('clothTypeInput');
  if (typeInput && document.activeElement !== typeInput) {
    typeInput.min = 1;
    typeInput.max = Math.max(1, S.filtered.length);
    typeInput.value = has ? (S.itemPos + 1) : 1;
  }
  const texInput = $('clothTextureInput');
  if (texInput && document.activeElement !== texInput) {
    texInput.min = 0;
    texInput.max = Math.max(0, S.textureCount - 1);
    texInput.value = has ? S.texture : 0;
  }

  // Admin price field auto-fill
  if (S.isAdmin && customItemPrice && has && document.activeElement !== customItemPrice)
    customItemPrice.value = String(item.price || S.prices[item.category] || 0);

  // Selector counters matching mockup
  const modelMax = Math.max(1, S.filtered.length);
  const texMax = Math.max(1, S.textureCount);
  if ($('modelCounter')) $('modelCounter').textContent = has ? `${S.itemPos + 1} / ${modelMax}` : '—';
  if ($('textureCounter')) $('textureCounter').textContent = has ? `${S.texture + 1} / ${texMax}` : '—';
  if ($('itemIndex')) $('itemIndex').textContent = has ? String(S.itemPos + 1) : '1';
  if ($('textureIndex')) $('textureIndex').textContent = has ? String(S.texture) : '0';

  // Empty notice
  const showEmpty = !has && catalogRows(false).length === 0 && !S.isAdmin;
  emptyNotice.classList.toggle('hidden', !showEmpty);

  // Bag level controls
  if (bagLevelControls)
    bagLevelControls.classList.toggle('hidden', !S.isAdmin || !has || item.category !== 'bags');
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

  updateAdminButton();
  renderTextureStatus();
  updateCartUI();
  updateFavButton();
}

function updateAdminButton() {
  if (!S.isAdmin) {
    const total = S.cart.length > 0 ? cartAmount() : (S.selected ? (S.selected.price || 0) : 150);
    buyBtn.innerHTML = `<span class="btn-content">BUY CLOTHING ($${total})</span>`;
    buyBtn.classList.remove('btn--fit');
    if (adjustCaptureBtn) adjustCaptureBtn.classList.add('hidden');
    return;
  }
  if (adjustCaptureBtn) {
    const canAdjust = S.activeCategory !== 'arms' && S.activeCategory !== '__fav' && !!S.selected;
    adjustCaptureBtn.classList.toggle('hidden', !canAdjust);
    adjustCaptureBtn.disabled = !canAdjust;
  }
  if (S.activeCategory === 'arms' && S.adminTorsoTarget) {
    buyBtn.innerHTML = '<span class="btn-content">SAVE FIT TO TORSO</span>';
    buyBtn.classList.add('btn--fit');
  } else {
    const existing = hasStoredCatalogData(S.selected || {});
    buyBtn.innerHTML = `<span class="btn-content">${existing ? 'UPDATE / RETAKE IMAGE' : 'TAKE IMAGE + SAVE'}</span>`;
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
  const captureCategory = cat === 'arms' ? 'torso' : cat;
  window.__currentCaptureCategory = captureCategory;
  S.filtered       = getRowsForCategory(cat);
  S.itemPos        = 0;
  S.selected       = S.filtered[0] || null;
  if (cat === 'torso' && S.selected) S.adminTorsoTarget = { ...S.selected };
  if (S.isAdmin) {
    setCaptureControlsForCategory(captureCategory);
    refreshCaptureBackdropPreview();
    syncCropSection();
  }
  S.texture      = S.selected ? previewTexture(S.selected.texture) : 0;
  S.textureCount = 1;
  applyTextureModeFromCatalog(S.texture);
  renderCategories();
  updateBottom();
  previewSelected();
  // Camera preset per category
  if (cat === 'hat') post('changeCamera', { camera: 'head', category: captureCategory });
  else if (['glasses','earrings'].includes(cat)) post('changeCamera', { camera: 'face', category: captureCategory });
  else if (cat === 'shoes') post('changeCamera', { camera: 'feet', category: captureCategory });
  else post('changeCamera', { camera: 'body', category: captureCategory });
}

async function previewSelected() {
  if (!S.selected) return;
  const item = {
    ...S.selected,
    drawable:    S.selected.drawable,
    texture:     previewTexture(S.texture),
    drawableId:  S.selected.drawable,
    textureId:   previewTexture(S.texture),
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
  S.texture      = previewTexture(S.selected.texture);
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
    S.texture      = previewTexture(row.texture);
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
  const key = normCat({ category: cat });
  const c = S.captureCrops[key];
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
  const setBtn = $('setCropBtn');
  if (setBtn) setBtn.textContent = saved ? 'CHANGE SAVED CROP' : 'SET CROP FOR THIS CATEGORY';
}
// Arm the next single capture to open the crop editor so the admin can set/reset
// the crop for the current category. The saved crop then reapplies on its own.
function armCropSetup() {
  const cat = normCat({ category: S.activeCategory });
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
// takes the screenshot and silently reuses the category crop, when one is saved.
const poseBar = $('poseBar');
function updatePoseReadout(extra = {}) {
  S.poseTelemetry = { ...(S.poseTelemetry || {}), ...extra };
  const t = S.poseTelemetry || {};
  const out = $('poseReadout');
  if (!out) return;
  const h = Number(t.playerHeading || 0).toFixed(1);
  const mx = Number(t.moveX || 0).toFixed(2);
  const my = Number(t.moveY || 0).toFixed(2);
  const lift = Number(t.lift || 0).toFixed(2);
  const d = Number(t.dist || 0).toFixed(2);
  const ch = Number(t.cameraHeading || 0).toFixed(1);
  const z = Number(t.relZ || 0).toFixed(2);
  const f = Number(t.fov || 0).toFixed(1);
  out.textContent = `PLAYER heading ${h}° · offset X ${mx} / Y ${my} / Z ${lift}  |  CAMERA orbit ${ch}° · distance ${d} · height ${z} · FOV ${f}`;
}
function enterPoseMode(category, heading, camera) {
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
  S.poseTelemetry = {
    playerHeading: heading, moveX: 0, moveY: 0,
    dist: camera?.dist, cameraHeading: camera?.heading,
    relZ: camera?.relZ, fov: camera?.fov,
  };
  updatePoseReadout();
}
function exitPoseMode() {
  S.manualPosing = false;
  if (poseBar) poseBar.classList.add('hidden');
  if (app) app.classList.remove('posing');
}
async function poseRotate(delta) {
  if (!S.manualPosing) return;
  const r = await post('manualPoseRotate', { delta });
  if (r && r.heading != null) {
    const slider = $('poseHeading'); if (slider) slider.value = Math.round(r.heading);
    const val = $('poseHeadingVal'); if (val) val.textContent = `${Math.round(r.heading)}°`;
    updatePoseReadout({ playerHeading: r.heading });
  }
}
function poseSetHeading(absolute) {
  if (!S.manualPosing) return;
  post('manualPoseRotate', { absolute });
  const val = $('poseHeadingVal');
  if (val) val.textContent = `${Math.round(absolute)}°`;
  updatePoseReadout({ playerHeading: absolute });
}
async function poseLift(delta) {
  if (!S.manualPosing) return;
  const r = await post('manualPoseLift', { delta });
  if (r && r.lift != null) updatePoseReadout({ lift: r.lift });
}
async function poseMove(axis, amount) {
  if (!S.manualPosing) return;
  const r = await post('manualPoseMove', { axis, amount });
  if (r && r.success) updatePoseReadout({ moveX: r.moveX, moveY: r.moveY });
}
async function poseCamera(action, amount) {
  if (!S.manualPosing) return;
  const r = await post('manualPoseCam', { action, amount });
  const c = r && r.camera;
  if (c) updatePoseReadout({ dist: c.dist, cameraHeading: c.heading, relZ: c.relZ, fov: c.fov });
}
function poseConfirm() {
  if (!S.manualPosing) return;
  exitPoseMode();
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
    case 'w': poseCamera('zoom',    0.12); return true;
    case 's': poseCamera('zoom',   -0.12); return true;
    case 'a': poseCamera('orbit',  -4.0 ); return true;
    case 'd': poseCamera('orbit',   4.0 ); return true;
    case 'r': poseCamera('height',  0.04); return true;
    case 'f': poseCamera('height', -0.04); return true;
    case 'q': poseCamera('fov',    -2.0 ); return true;
    case 'e': poseCamera('fov',     2.0 ); return true;
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
  if (!S.open) {
    app.classList.add('hidden');
    app.classList.remove('store-mode');
    app.classList.remove('admin-mode');
    app.style.display = 'none';
    return;
  }
  app.classList.remove('hidden');
  app.style.display = '';

  if (data.adminMode !== undefined) {
    setAdminMode(data.adminMode === true);
  } else if (!S.isAdmin) {
    setAdminMode(false);
  }

  if (String(data.gender || '').toLowerCase() === 'female') S.adminGender = 'female';
  else if (String(data.gender || '').toLowerCase() === 'male') S.adminGender = 'male';
  S.categories  = Array.isArray(data.categories) ? data.categories : ['torso','tshirt','pants','shoes'];
  S.counts      = data.counts       || S.counts      || {};
  S.prices      = data.prices       || S.prices      || {};
  S.translations = data.translations || S.translations || {};
  S.useCatalogOnly = data.useCatalogOnly !== false;
  S.pricePresets = data.pricePresets || S.pricePresets || {};
  if (data.economy) S.economy = data.economy;
  if (data.iconCapture) S.captureSettings = { ...S.captureSettings, ...data.iconCapture };

  app.classList.remove('hidden');

  if (data.bank !== undefined) {
    if ($('brandBank')) $('brandBank').textContent = `$${Number(data.bank).toLocaleString()} BANK`;
    if ($('storeTopBank')) $('storeTopBank').textContent = `$${Number(data.bank).toLocaleString()}`;
  }
  if (data.cash !== undefined && $('storeTopCash')) {
    $('storeTopCash').textContent = `$${Number(data.cash).toLocaleString()}`;
  }
  if (data.label) {
    if ($('brandSublabel')) $('brandSublabel').textContent = String(data.label).toUpperCase();
    if ($('storeBrandSub')) $('storeBrandSub').textContent = String(data.label).toUpperCase();
  }

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
  if (adminGenderSwitch) adminGenderSwitch.classList.toggle('hidden', !S.isAdmin);
  if (adminCaptureControls) adminCaptureControls.classList.toggle('hidden', !S.isAdmin);
  if (adjustCaptureBtn) adjustCaptureBtn.classList.toggle('hidden', !S.isAdmin);
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
    ? 'Capture clothing images only. Use /clothingstore for torso fit and catalog management.'
    : 'Preview outfits, switch colors, add items to cart, then checkout.';

  // Hide controls hint in admin (saves vertical space)
  if (controlsHint) controlsHint.classList.toggle('hidden', S.isAdmin);

  updateAdminButton();
  syncAdminGenderSwitch();
  renderCategories();
  if (S.activeCategory) setCategory(S.activeCategory);
}

function syncAdminGenderSwitch() {
  const gender = S.adminGender === 'female' ? 'female' : 'male';
  if (adminGenderMale) {
    adminGenderMale.classList.toggle('active', gender === 'male');
    adminGenderMale.disabled = S.adminGenderSwitching || S.bulkRunning;
  }
  if (adminGenderFemale) {
    adminGenderFemale.classList.toggle('active', gender === 'female');
    adminGenderFemale.disabled = S.adminGenderSwitching || S.bulkRunning;
  }
  if (adminGenderState) adminGenderState.textContent = S.adminGenderSwitching
    ? `Loading ${gender.toUpperCase()} model…`
    : `Editing ${gender.toUpperCase()} clothing`;
}

function applyAdminGenderChanged(gender, counts) {
  S.adminGender = String(gender || '').toLowerCase() === 'female' ? 'female' : 'male';
  if (counts && typeof counts === 'object') S.counts = counts;
  S.catalog = [];
  S.selected = null;
  S.itemPos = 0;
  S.texture = 0;
  S.textureCount = 1;
  S.exactTextureRows = [];
  S.adminTorsoTarget = null;
  S.lastAdminSyncKey = '';
  if (genderFilter) genderFilter.value = S.adminGender;
  S.filters.gender = S.adminGender;
  syncAdminGenderSwitch();
  renderCategories();
  if (S.activeCategory) setCategory(S.activeCategory);
}

async function switchAdminGender(gender, force = false) {
  gender = String(gender || '').toLowerCase() === 'female' ? 'female' : 'male';
  if (!S.isAdmin || S.adminGenderSwitching || (!force && S.bulkRunning)) return;
  if (gender === S.adminGender && !force) return;
  S.adminGenderSwitching = true;
  syncAdminGenderSwitch();
  const res = await post('adminSetGender', { gender });
  S.adminGenderSwitching = false;
  if (!res || res.success !== true) {
    syncAdminGenderSwitch();
    toast(`Could not load ${gender} clothing model: ${res?.error || 'unknown error'}`, 'error');
    return;
  }
  applyAdminGenderChanged(res.gender || gender, res.counts || {});
}

/* ══════════════════════════════════════════════════════════
   POST-CAPTURE BAG PAIRING (stays inside /clothingadmin)
   GTA/addon bag meshes don't reliably look the same at the same drawable
   index on both freemode models, so a captured bag isn't "done" until the
   admin also says which drawable on the OTHER gender is the same physical
   bag. This switches the ped to that gender right here and lets the admin
   scroll through its already-photographed bags (never blank/uncaptured
   slots) to pick the match, then saves the pairing via the same
   pairedDrawableId/pairedTextureId mechanism /clothingstore uses.
   ══════════════════════════════════════════════════════════ */
function renderBagPairOverlay() {
  if (!bagPairOverlay) return;
  const bp = S.bagPairing;
  bagPairOverlay.classList.toggle('hidden', !bp);
  if (!bp) return;

  if (bagPairGenderLabel) bagPairGenderLabel.textContent = bp.otherGender.toUpperCase();
  if (bagPairSourceLabel) bagPairSourceLabel.textContent = bp.sourceEntry?.label || 'Bag';
  if (bagPairSourceGender) bagPairSourceGender.textContent = bp.sourceGender.charAt(0).toUpperCase() + bp.sourceGender.slice(1);
  if (bagPairSourceDrawable) bagPairSourceDrawable.textContent = String(bp.sourceDrawable);
  if (bagPairSourceTexture) bagPairSourceTexture.textContent = String(bp.sourceTexture);

  if (bagPairDrawableInput && document.activeElement !== bagPairDrawableInput) {
    bagPairDrawableInput.value = bp.currentDrawable;
    bagPairDrawableInput.max = Math.max(0, bp.maxDrawables - 1);
  }
  if (bagPairDrawableTotal) {
    bagPairDrawableTotal.textContent = `/ ${Math.max(0, bp.maxDrawables - 1)}`;
  }

  if (bagPairTextureInput && document.activeElement !== bagPairTextureInput) {
    bagPairTextureInput.value = bp.currentTexture;
    bagPairTextureInput.max = Math.max(0, bp.maxTextures - 1);
  }
  if (bagPairTextureTotal) {
    bagPairTextureTotal.textContent = `/ ${Math.max(0, bp.maxTextures - 1)}`;
  }
}

async function previewBagPair() {
  const bp = S.bagPairing;
  if (!bp) return;
  const res = await post('sendSelectedArticle', {
    category: 'bags',
    drawable: bp.currentDrawable,
    texture: bp.currentTexture,
    drawableId: bp.currentDrawable,
    textureId: bp.currentTexture,
  });
  if (res && Number.isFinite(res.count) && res.count > 0) {
    bp.maxTextures = res.count;
    if (bp.currentTexture >= bp.maxTextures) {
      bp.currentTexture = 0;
    }
    renderBagPairOverlay();
  }
}

function stepBagPairDrawable(dir) {
  const bp = S.bagPairing;
  if (!bp || bp.maxDrawables <= 0) return;
  bp.currentDrawable = (bp.currentDrawable + dir + bp.maxDrawables) % bp.maxDrawables;
  bp.currentTexture = 0;
  renderBagPairOverlay();
  previewBagPair();
}

function setBagPairDrawable(val) {
  const bp = S.bagPairing;
  if (!bp) return;
  const max = Math.max(1, bp.maxDrawables);
  bp.currentDrawable = Math.max(0, Math.min(max - 1, Number(val) || 0));
  bp.currentTexture = 0;
  renderBagPairOverlay();
  previewBagPair();
}

function stepBagPairTexture(dir) {
  const bp = S.bagPairing;
  if (!bp || bp.maxTextures <= 0) return;
  bp.currentTexture = (bp.currentTexture + dir + bp.maxTextures) % bp.maxTextures;
  renderBagPairOverlay();
  previewBagPair();
}

function setBagPairTexture(val) {
  const bp = S.bagPairing;
  if (!bp) return;
  const max = Math.max(1, bp.maxTextures);
  bp.currentTexture = Math.max(0, Math.min(max - 1, Number(val) || 0));
  renderBagPairOverlay();
  previewBagPair();
}

async function exitBagPairing(switchBack) {
  const bp = S.bagPairing;
  S.bagPairing = null;
  renderBagPairOverlay();
  if (switchBack && bp) {
    await switchAdminGender(bp.sourceGender, true);
  }
}

async function confirmBagPairing() {
  const bp = S.bagPairing;
  if (!bp) return;
  const entry = bp.sourceEntry || {};
  const isSkin = bp.isSkin === true;
  const bagLevelVal = isSkin ? null : Math.max(1, Math.min(4, Number(bp.bagLevel || 1)));

  const payload = {
    category: 'bags',
    sourceGender: bp.sourceGender,
    sourceDrawable: bp.sourceDrawable,
    sourceTexture: bp.sourceTexture,
    targetGender: bp.otherGender,
    targetDrawable: bp.currentDrawable,
    targetTexture: bp.currentTexture,
    image: entry.image || entry.icon || '',
    label: entry.label || getAdminName('Bag'),
    price: Number(entry.price || 0),
    orgs: Array.isArray(entry.organizations) ? entry.organizations : [],
    publicStore: String(entry.shop || 'clothes').toLowerCase() === 'clothes',
    published: entry.enabled === true,
    bagSkin: isSkin,
    bagLevel: bagLevelVal,
  };

  const res = await post('saveBagPairing', payload);
  if (res && res.success !== false) {
    toast(`Bag paired & saved for both ${bp.sourceGender} (D${bp.sourceDrawable}) and ${bp.otherGender} (D${bp.currentDrawable})!`, 'success');
  } else {
    toast(`Pair save failed: ${res?.error || 'unknown error'}`, 'error');
  }
  await exitBagPairing(true);
}

async function enterBagPairing(entry) {
  if (!entry) return;
  const isAutomatedBulk = S.captureMode && (
    S.captureMode.startsWith('wholecategory_') ||
    S.captureMode === 'all_genders_all_textures' ||
    S.captureMode === 'category_missing' ||
    S.captureMode === 'category_all'
  );
  if (isAutomatedBulk) return; // never interrupt mass automated capture

  const sourceGender = String(entry.gender || S.adminGender || 'male').toLowerCase() === 'female' ? 'female' : 'male';
  const otherGender = sourceGender === 'female' ? 'male' : 'female';
  const sourceDrawable = Number(entry.drawableId ?? entry.drawable ?? 0);
  const sourceTexture = Number(entry.textureId ?? entry.texture ?? 0);
  const rawLvl = entry.bagLevel || entry.bag_level || (bagLevel ? bagLevel.value : 'skin');
  const isSkin = entry.bagSkin === true || String(rawLvl) === 'skin';

  S.bagPairing = {
    sourceGender,
    sourceDrawable,
    sourceTexture,
    sourceEntry: entry,
    otherGender,
    currentDrawable: sourceDrawable,
    currentTexture: 0,
    maxDrawables: 250,
    maxTextures: 1,
    isSkin,
    bagLevel: isSkin ? null : Math.max(1, Math.min(4, Number(rawLvl) || 1)),
  };

  renderBagPairOverlay();
  await switchAdminGender(otherGender, true);
  if (!S.bagPairing) return;

  const count = (S.counts && S.counts['bags']) ? Number(S.counts['bags']) : 250;
  S.bagPairing.maxDrawables = count;
  if (S.bagPairing.currentDrawable >= count) {
    S.bagPairing.currentDrawable = Math.max(0, count - 1);
  }

  renderBagPairOverlay();
  await previewBagPair();
  await post('rotatePed', { turn180: true, delta: 180.0 });
}

// Re-derive the bag-pairing drawable/texture bounds once a fresh catalog
// (and its counts) for the target gender has actually landed -- switchAdminGender's
// own promise can resolve before the async 'clothingCatalog' push arrives.
function refreshBagPairCandidates() {
  const bp = S.bagPairing;
  if (!bp) return;
  const count = (S.counts && S.counts['bags']) ? Number(S.counts['bags']) : bp.maxDrawables;
  if (Number.isFinite(count) && count > 0) {
    bp.maxDrawables = count;
    if (bp.currentDrawable >= count) bp.currentDrawable = Math.max(0, count - 1);
  }
  renderBagPairOverlay();
}

if (bagPairPrev)          bagPairPrev.onclick          = () => stepBagPairDrawable(-1);
if (bagPairNext)          bagPairNext.onclick          = () => stepBagPairDrawable(1);
if (bagPairTexPrev)       bagPairTexPrev.onclick       = () => stepBagPairTexture(-1);
if (bagPairTexNext)       bagPairTexNext.onclick       = () => stepBagPairTexture(1);
if (bagPairDrawableInput) bagPairDrawableInput.onchange= (e) => setBagPairDrawable(e.target.value);
if (bagPairTextureInput)  bagPairTextureInput.onchange = (e) => setBagPairTexture(e.target.value);
if (bagPairTurnPed)       bagPairTurnPed.onclick       = () => post('rotatePed', { delta: 180.0 });
if (bagPairConfirm)       bagPairConfirm.onclick       = () => confirmBagPairing();
if (bagPairSkip)          bagPairSkip.onclick          = () => exitBagPairing(true);

/* ══════════════════════════════════════════════════════════
   ADMIN HELPERS
   ══════════════════════════════════════════════════════════ */
const getAdminName   = (fb) => { const v = customItemName   ? customItemName.value.trim() : ''; return v || fb; };
const getAdminDest   = ()   => itemDestination ? (itemDestination.value || 'store') : 'store';
const getAdminPrice  = (fb) => { const v = customItemPrice ? Number(customItemPrice.value) : NaN; return Number.isFinite(v) && v >= 0 ? Math.floor(v) : Number(fb || 0) || 0; };
const getBagLevel    = ()   => {
  const v = bagLevel ? bagLevel.value : '';
  if (v === 'skin') return 'skin';
  const num = Number(v);
  if (!Number.isFinite(num)) return null;
  return Math.max(1, Math.min(4, Math.floor(num)));
};

function getAdminTarget() {
  if (!S.isAdmin || !S.selected) return null;
  let base = S.selected;
  if (S.activeCategory === 'arms' && S.adminTorsoTarget) base = S.adminTorsoTarget;
  else if (S.activeCategory === 'arms') return null;

  const cat    = base.category;
  const preset = CAPTURE_PRESETS[cat] || {};
  const z = Number(preset.zOffset || 0);

  const t = {
    ...base,
    gender:           S.adminGender,
    texture:          previewTexture(S.texture ?? base.texture ?? 0),
    textureId:        previewTexture(S.texture ?? base.texture ?? 0),
    drawableId:       base.drawable,
    enabled:          true,
    captureAngle:     preset.angle || 'front',
    captureAngleOverride: false,
    zOffset:          Number.isFinite(z) ? z : Number(preset.zOffset || 0),
    captureBackground: captureBackground ? (captureBackground.value || preset.bg || 'green') : (preset.bg || 'green'),
    sharedGender:     cat === 'bags' ? (sharedGender ? sharedGender.checked !== false : true) : false,
  };
  // Present only while a /clothingstore RETAKE is in flight. The server
  // validates it and, when set, moves that item onto this garment + photo
  // instead of creating a new catalog row.
  t.replaceAssetId = S.activeReplaceAssetId || null;
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
  const uid = clothingUniqueId(t.gender, t.category, t.drawableId, t.textureId, t);
  t.uniqueId = uid;
  t.unique_id = uid;
  t.clothingId = uid;
  t.clothing_id = uid;
  if (t.category === 'bags') {
    const lvl = getBagLevel();
    if (!lvl) { toast('Select bag level 1-4 or Skin before saving.', 'error'); return null; }
    if (lvl === 'skin') {
      t.bagSkin = true;
      t.level = null;
      t.bagLevel = null;
      t.bag_level = null;
    } else {
      t.bagSkin = false;
      t.level = lvl;
      t.bagLevel = lvl;
      t.bag_level = lvl;
    }
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
  const cat = normCat({ category: (payload && payload.category) || S.activeCategory || '' });
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
  const cat = normCat({ category: payload.category || S.activeCategory || '' });
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
      await post('saveCaptureCrop', { category: cat, ...crop });
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

function resetBulkFailures() {
  S.bulkFailures = [];
  renderBulkFailures();
}

function recordBulkFailure(target, error, attempts) {
  const row = target || {};
  S.bulkFailures.push({
    gender: String(row.gender || 'current'),
    category: String(row.category || S.activeCategory || '?'),
    drawable: Number(row.drawableId ?? row.drawable ?? -1),
    texture: Number(row.textureId ?? row.texture ?? -1),
    attempts: Number(attempts || 1),
    error: String(error || 'failed'),
  });
  renderBulkFailures();
}

function renderBulkFailures() {
  const rows = Array.isArray(S.bulkFailures) ? S.bulkFailures : [];
  if (failedCapturePanel) failedCapturePanel.classList.toggle('hidden', rows.length === 0);
  if (failedCaptureCount) failedCaptureCount.textContent = String(rows.length);
  if (failedCaptureList) {
    failedCaptureList.textContent = rows.map(r =>
      `${r.gender} · ${r.category} · D${r.drawable}/T${r.texture} · ${r.error} (${r.attempts} attempts)`
    ).join('\n');
  }
}

async function waitWhileBulkPaused() {
  while (S.bulkRunning && S.bulkPaused && !S.bulkCancel) await delay(150);
}

function beginBulk(mode) {
  S.bulkRunning = true;
  S.bulkCancel = false;
  S.bulkPaused = false;
  S.captureMode = mode;
  resetBulkFailures();
  applyBulkDisabled(true);
}

function endBulk() {
  S.bulkRunning = false;
  S.bulkPaused = false;
  S.captureMode = null;
  applyBulkDisabled(false);
}

const RETRYABLE_CAPTURE_ERROR = /unloaded|empty|too_small|no pixels|screenshot|timeout|decode|webp|save_file|save_failed/i;
async function captureWithRetry(target, captureFn, label) {
  const maxRetries = Math.max(0, Math.min(10, Number(S.captureSettings?.maxRetries ?? 2)));
  const retryDelay = Math.max(100, Number(S.captureSettings?.retryDelay ?? 650));
  let result = null;
  let attempts = 0;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    await waitWhileBulkPaused();
    if (S.bulkCancel) return { success: false, error: 'cancelled', attempts: attempt };
    if (attempt > 0) {
      setBulkProgress(`Retry ${attempt}/${maxRetries} · ${label}`);
      await delay(retryDelay * attempt);
    }
    attempts++;
    result = await captureFn();
    if (result && result.success) return { ...result, attempts: attempt + 1 };
    if (!RETRYABLE_CAPTURE_ERROR.test(String(result?.error || 'failed'))) break;
  }
  recordBulkFailure(target, result?.error || 'failed', attempts);
  return { ...(result || {}), success: false, attempts };
}

function waitForIconResult(ms = 60000) {
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
  if (allGendersBtn)      allGendersBtn.disabled      = disabled || !S.isAdmin;
  if (adjustCaptureBtn)   adjustCaptureBtn.disabled   = disabled || !S.selected;
  syncAdminGenderSwitch();
  if (cancelBulkBtn)  cancelBulkBtn.classList.toggle('hidden', !disabled);
  if (pauseBulkBtn) pauseBulkBtn.classList.toggle('hidden', !disabled || S.bulkPaused);
  if (resumeBulkBtn) resumeBulkBtn.classList.toggle('hidden', !disabled || !S.bulkPaused);
  for (const id of ['prevItem','nextItem','prevTexture','nextTexture']) {
    const el = $(id); if (el) el.disabled = disabled;
  }
  renderCategories();
}

async function captureOneTexture(texture, sourceTarget = null) {
  // Lock this before any await. Preview callbacks and catalog refreshes may update
  // S.texture while the capture is preparing; the requested native texture must
  // remain the exact texture visible when the admin pressed Take Image.
  const lockedTexture = previewTexture(texture);
  const lockedSource = sourceTarget ? normRow({ ...sourceTarget, texture: lockedTexture, textureId: lockedTexture }) : null;
  S.texture = lockedTexture;
  if (S.activeCategory === 'torso' && S.selected)
    S.adminTorsoTarget = { ...S.selected, texture: S.texture, textureId: S.texture };
  updateBottom();
  if (lockedSource) {
    await post('sendSelectedArticle', {
      ...lockedSource,
      category: lockedSource.category,
      drawable: lockedSource.drawable,
      drawableId: lockedSource.drawable,
      texture: lockedTexture,
      textureId: lockedTexture,
    });
  } else {
    await previewSelected();
  }
  await delay(550);

  const target = getAdminTarget();
  if (!target) return { success: false, error: 'invalid_target' };
  // Keep the native item identity immutable for the entire job. Bulk retries can
  // outlive preview/UI updates; rebuilding only from S.selected could otherwise
  // capture a newly selected drawable under the previous file name.
  if (lockedSource) {
    const locked = lockedSource;
    target.category = locked.category;
    target.drawable = locked.drawable;
    target.drawableId = locked.drawable;
    target.gender = locked.gender;
    target.componentType = locked.componentType || locked.component_type || target.componentType;
    target.componentIndex = locked.componentIndex ?? locked.component_index ?? target.componentIndex;
    target.label = sourceTarget.label || target.label;
  }
  target.texture   = lockedTexture;
  target.textureId = lockedTexture;

  // Only the explicit Adjust Position button opens the live editor. Normal single
  // and bulk captures use the saved/default category composition immediately.
  const useManualEditor = S.singleManual === true && MANUAL_POSE_CATS.has(String(S.activeCategory));
  target.manual = useManualEditor;
  if (useManualEditor) S.singleManual = false; // retries reuse the confirmed saved pose

  const waiter = waitForIconResult();
  const res    = await post('captureInventoryIcon', target);
  if (res && res.success === false && S.pendingIconResolver)
    S.pendingIconResolver({ success: false, error: res.error || 'capture_start_failed' });
  return waiter;
}

async function runBulkCapture(mode, adjustPosition = false) {
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
  // A replace targets ONE item, so it is armed only for a single deliberate
  // capture. A bulk or whole-category run must never replay the same replace
  // across many drawables, which would overwrite that item repeatedly.
  S.activeReplaceAssetId = (mode === 'current' && indices.length === 1)
    ? (S.retakeAssetId || null)
    : null;
  beginBulk('category_' + mode);
  S.manualCropNextCapture = false;
  const manualRun = adjustPosition === true && MANUAL_POSE_CATS.has(String(S.activeCategory));
  S.singleManual = manualRun && (mode === 'current' && indices.length === 1);
  let saved = 0;
  let lastCapturedEntry = null;
  for (let i = 0; i < indices.length; i++) {
    await waitWhileBulkPaused();
    if (S.bulkCancel) break;
    const tex = indices[i];
    // Only the first texture is posed by hand; the rest replay the remembered pose.
    S.singleManual = manualRun && i === 0;
    setCaptureStatus(true, `Saving ${i+1}/${indices.length} (T${tex})…`);
    setBulkProgress(`Saving ${i+1}/${indices.length} · T${tex}`);
    const target = { ...(S.selected || {}), texture: tex, textureId: tex };
    const r = await captureWithRetry(target, () => captureOneTexture(tex, target), `T${tex}`);
    if (r && r.success) {
      saved++;
      lastCapturedEntry = r.entry || target;
    }
    await delay(350);
  }
  endBulk();
  // The replace is spent: consumed on success, and dropped on failure so a
  // retry is a deliberate act rather than a stale arm firing later.
  if (S.activeReplaceAssetId) {
    S.activeReplaceAssetId = null;
    if (saved > 0) clearRetakeTarget();
  }
  S.manualCropNextCapture = false;
  S.singleManual = false;
  setCaptureStatus(false);
  renderTextureStatus();
  renderCategories();
  const done = S.bulkCancel ? 'Cancelled' : 'Done';
  setBulkProgress(`${done}: saved ${saved}/${indices.length}${S.bulkFailures.length ? ` · Failed: ${S.bulkFailures.length}` : ''}`, true);
  setTimeout(() => setBulkProgress('', false), 5000);

  if (mode === 'current' && String(S.activeCategory || '').toLowerCase() === 'bags' && saved > 0 && lastCapturedEntry) {
    if (!lastCapturedEntry.imageOnly) {
      await enterBagPairing(lastCapturedEntry);
    }
  }
}

// Batch capture every drawable and every native texture in the active category.
// mode 'missing' skips items that already have an image; 'all' recaptures everything.
// Each item is auto-named, auto-priced, and routed to store/hidden by the economy rules.
async function runCategoryCapture(mode) {
  if (!S.isAdmin || !S.activeCategory || S.bulkRunning) return;
  // Captures many different drawables; a replace targets exactly one item.
  S.activeReplaceAssetId = null;
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

  beginBulk('wholecategory_' + mode);
  S.manualCropNextCapture = false;

  let saved = 0, attempted = 0;
  for (let i = 0; i < targets.length; i++) {
    await waitWhileBulkPaused();
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

    // Query the native texture count for this drawable, then capture every one.
    await previewSelected();
    const textureCount = Math.max(1, Number(S.textureCount || 1));

    const tag = `#${row.drawable}${auto && auto.addon ? ' · Add-on' : ''}`;
    for (let tex = 0; tex < textureCount; tex++) {
      await waitWhileBulkPaused();
      if (S.bulkCancel) break;
      attempted++;
      setCaptureStatus(true, `Drawable ${i + 1}/${targets.length} · ${tag} · T${tex + 1}/${textureCount}`);
      setBulkProgress(`Saved ${saved}/${attempted} · ${tag} · T${tex}`);
      const target = { ...row, texture: tex, textureId: tex };
      const r = await captureWithRetry(target, () => captureOneTexture(tex, target), `${tag} · T${tex}`);
      if (r && r.success) saved++;
      await delay(300);
    }
  }

  endBulk();
  S.manualCropNextCapture = false;
  setCaptureStatus(false);
  renderTextureStatus();
  renderCategories();

  const done = S.bulkCancel ? 'Cancelled' : 'Done';
  const failStr = S.bulkFailures.length ? ` · ${S.bulkFailures.length} failed (open list above)` : '';
  setBulkProgress(`${done}: saved ${saved}/${attempted}${failStr}`, true);
  setTimeout(() => setBulkProgress('', false), 9000);
}

async function captureDirectJob(job) {
  const preset = CAPTURE_PRESETS[job.category] || {};
  const target = {
    ...job,
    drawable: Number(job.drawableId ?? job.drawable),
    texture: Number(job.textureId ?? job.texture ?? 0),
    drawableId: Number(job.drawableId ?? job.drawable),
    textureId: Number(job.textureId ?? job.texture ?? 0),
    captureAngle: preset.angle || 'front',
    captureAngleOverride: false,
    zOffset: Number(preset.zOffset || 0),
    captureBackground: 'green',
    destination: 'hidden',
    enabled: true,
    price: 0,
  };
  const waiter = waitForIconResult(60000);
  const res = await post('captureInventoryIcon', target);
  if (res && res.success === false && S.pendingIconResolver)
    S.pendingIconResolver({ success: false, error: res.error || 'capture_start_failed' });
  return waiter;
}

async function runAllGenderCapture() {
  if (!S.isAdmin || S.bulkRunning) return;
  setBulkProgress('Enumerating male and female drawable/texture combinations…');
  const enumeration = await post('enumerateCaptureJobs');
  const jobs = Array.isArray(enumeration?.jobs) ? enumeration.jobs : [];
  if (!enumeration?.success || !jobs.length) {
    setBulkProgress(`Enumeration failed: ${enumeration?.error || 'no jobs returned'}`);
    return;
  }
  if (enumeration.truncated) {
    setBulkProgress('Safety limit reached while enumerating; capture was not started.');
    return;
  }
  if (!window.confirm(`Capture ${jobs.length} male + female images? Every drawable and every texture will be saved as a single PNG. You can pause or cancel safely.`)) {
    setBulkProgress('', false);
    return;
  }

  beginBulk('all_genders_all_textures');
  S.manualCropNextCapture = false;
  S.armCropForCategory = null;
  let saved = 0;

  for (let i = 0; i < jobs.length; i++) {
    await waitWhileBulkPaused();
    if (S.bulkCancel) break;
    const job = jobs[i];
    const label = `${job.gender} · ${job.category} · D${job.drawableId}/T${job.textureId}`;
    setCaptureStatus(true, `Capturing ${i + 1}/${jobs.length} · ${label}`);
    setBulkProgress(`${i + 1}/${jobs.length} · saved ${saved} · ${label}`);
    const result = await captureWithRetry(job, () => captureDirectJob(job), label);
    if (result && result.success) saved++;
    await delay(250);
  }

  const cancelled = S.bulkCancel;
  endBulk();
  setCaptureStatus(false);
  const failed = S.bulkFailures.length;
  setBulkProgress(`${cancelled ? 'Cancelled' : 'Done'}: saved ${saved}/${jobs.length}${failed ? ` · ${failed} failed (open list)` : ''}`, true);
}

/* ══════════════════════════════════════════════════════════
   IMAGE PROCESSING — background removal
   ══════════════════════════════════════════════════════════ */
function clamp01(n, fb) { n = Number(n); return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : fb; }

async function addRequestedOutputFormats(result, payload = {}) {
  const formats = payload.formats || { png: true, webp: true };
  if (!result || !result.dataUrl || formats.webp === false) return result;
  const image = await new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('webp_image_load_failed'));
    img.src = result.dataUrl;
  });
  const canvas = document.createElement('canvas');
  canvas.width = image.naturalWidth || image.width;
  canvas.height = image.naturalHeight || image.height;
  canvas.getContext('2d').drawImage(image, 0, 0);
  const quality = Math.max(0.1, Math.min(1, Number(payload.webpQuality ?? 0.94)));
  const webp = canvas.toDataURL('image/webp', quality);
  if (!webp.startsWith('data:image/webp;base64,')) throw new Error('webp_encoding_unavailable');
  return { ...result, webpDataUrl: webp, webpBase64: webp.split(',')[1] };
}

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
      const differenceIsolated = payload.differenceIsolated === true;
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
      if (!differenceIsolated && ac.floodFillBackground !== false) {
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
      if (!differenceIsolated) {
        for (let y = minY; y <= maxY; y++) {
          for (let x = minX; x <= maxX; x++) {
            const i = idx(x, y);
            if (d[i+3] > 10 && isKey(i)) { d[i+3] = 0; removed++; }
          }
        }
      }

      // Step 4: green de-spill on remaining item edge pixels.
      if (!differenceIsolated && soften && bg === 'green') {
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
      if (!differenceIsolated) removed += removeHeadFallbackPixels();

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
   /clothingstore · STORE MANAGER (admin)
   Browse every saved clothe (with its captured image), publish/unpublish to
   the player store, set price, assign to an org locker, preview on a
   disposable fake ped (male + female), and jump back into /clothingadmin
   with the clothe preselected to retake its image.
   ══════════════════════════════════════════════════════════ */
const M = {
  open: false,
  rows: [],
  gender: 'male',
  category: 'all',
  status: 'all',
  q: '',
  orgs: [],
  selectedKey: null,
  fit: { arms: null, armsTexture: 0, armsCount: 0, undershirt: null, undershirtTexture: 0, undershirtCount: 0 },
  switchingGender: false,
  previewReady: false,
  // Cross-gender bag pairing picker state (see renderManageDetail). Not part
  // of the saved row -- rowKey tracks which row this pending choice belongs
  // to, so switching to a different clothe resets it from that row's own
  // saved pairing instead of leaking a previous item's in-progress pick.
  bagPair: { rowKey: null, pending: null, previewingOther: false },
};

function manageImageUrl(row) {
  const img = String(row.image || row.icon || '').trim();
  if (!img) return '';
  if (/^(nui:|https?:|data:)/i.test(img)) return img;
  // The capture file name is stable across retakes (same drawable/texture/gender
  // always writes the same path), so CEF happily keeps serving the pre-retake
  // bytes unless the URL itself changes. row.imageVersion (stamped fresh server
  // side on every manage-catalog fetch) busts that cache -- every branch below
  // must apply it, not just the local-dev generated_images/ copy.
  const version = encodeURIComponent(String(row.imageVersion || row.image_version || ''));
  const withVersion = (url) => version ? `${url}?v=${version}` : url;
  if (img.startsWith('generated_images/')) return withVersion(`nui://${resource}/${img}`);
  if (img.startsWith('ui/images/')) return withVersion(`nui://cm-items/${img}`);
  if (img.startsWith('images/')) return withVersion(`nui://cm-items/ui/${img}`);
  if (img.startsWith('custom/')) return withVersion(`nui://cm-items/ui/images/clothing/${img}`);
  if (img.startsWith('items/')) return withVersion(`nui://cm-items/ui/images/clothing/${img}`);
  if (img.startsWith('clothing/')) return withVersion(`nui://cm-items/ui/images/${img}`);
  return img;
}

function manageDrawableOf(r) { return Number(r.drawableId ?? r.drawable_id ?? r.drawable); }
function manageTextureOf(r) {
  const texture = Number(r._previewTexture ?? r.textureId ?? r.texture_id ?? r.texture ?? -1);
  return Number.isFinite(texture) ? texture : -1;
}
function manageBaseKey(r) { return `${String(r.gender || 'male').toLowerCase()}|${normCat(r)}|${manageDrawableOf(r)}`; }
function manageRowKey(r) { return `${manageBaseKey(r)}|${manageTextureOf(r)}`; }
function manageEnabled(r) { return !(r.enabled === false || r.enabled === 0 || r.enabled === '0'); }
function manageHasImage(r) { return String(r.image || r.icon || '').trim() !== ''; }

function manageOrgOf(r) {
  const org = String(r.org || '').toLowerCase();
  if (org) return org;
  const m = String(r.shop || '').toLowerCase().match(/^org_(.+)$/);
  return m ? m[1] : '';
}

function manageOrganizationsOf(r) {
  const values = Array.isArray(r.organizations) ? r.organizations : [];
  const normalized = [...new Set(values.map(v => String(v || '').toLowerCase()).filter(Boolean))];
  if (!normalized.length) {
    const legacy = manageOrgOf(r);
    if (legacy) normalized.push(legacy);
  }
  return normalized;
}

function selectedManageDestinations() {
  if (!manageOrgChoices) return { publicStore: true, organizations: [] };
  const publicStore = manageOrgChoices.querySelector('[data-public-store]')?.checked === true;
  const organizations = [...manageOrgChoices.querySelectorAll('[data-org]:checked')].map(input => input.dataset.org);
  return { publicStore, organizations };
}

// One card per captured texture. The texture=-1 row owns shared management
// state, but must not collapse every photographed texture into one card.
function manageGrouped() {
  const masters = new Map();
  const exact = new Map();
  for (const r of M.rows) {
    const cat = normCat(r);
    if (!cat || cat === 'arms') continue;
    const drawable = manageDrawableOf(r);
    if (!Number.isFinite(drawable)) continue;
    const base = `${String(r.gender || 'male').toLowerCase()}|${cat}|${drawable}`;
    const tex = Number(r.textureId ?? r.texture_id ?? r.texture ?? -1);
    const normalized = { ...r, category: cat };
    if (tex < 0) masters.set(base, normalized);
    else exact.set(`${base}|${tex}`, { ...normalized, _previewTexture: tex });
  }

  const rows = [];
  const basesWithExact = new Set();
  for (const captured of exact.values()) {
    const base = manageBaseKey(captured);
    const master = masters.get(base);
    basesWithExact.add(base);
    if (master) {
      rows.push({
        ...captured, ...master,
        category: captured.category,
        _tex: -1,
        _previewTexture: manageTextureOf(captured),
        image: captured.image || captured.icon || master.image || master.icon,
        icon: captured.icon || captured.image || master.icon || master.image,
        // The spread above lets the drawable-level row win, but identity must
        // come from the CAPTURED texture row: that is the row players' owned
        // items are linked to. Taking the master's id here would aim a retake
        // (and a revert) at the grouping row instead of the real item, and
        // nobody's inventory would change.
        assetId: captured.assetId || master.assetId,
      });
    } else {
      rows.push({ ...captured, _tex: manageTextureOf(captured) });
    }
  }
  for (const [base, master] of masters) {
    if (!basesWithExact.has(base)) rows.push({ ...master, _tex: -1, _previewTexture: 0 });
  }
  return rows;
}

function manageFiltered() {
  const q = M.q.trim().toLowerCase();
  return manageGrouped()
    .filter(r => {
      if (String(r.gender || 'male').toLowerCase() !== M.gender) return false;
      if (M.category !== 'all' && effCatOf(r) !== M.category) return false;
      const org = manageOrgOf(r);
      const pub = manageEnabled(r);
      if (M.status === 'published' && !pub) return false;
      if (M.status === 'unpublished' && pub) return false;
      if (M.status === 'org' && !org) return false;
      if (M.status === 'noimage' && manageHasImage(r)) return false;
      if (q) {
        const hay = `${r.label || ''} ${effCatOf(r)} ${manageDrawableOf(r)} ${manageTextureOf(r)} ${org}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    })
    .sort((a, b) => a.category === b.category
      ? (manageDrawableOf(a) - manageDrawableOf(b)) || (manageTextureOf(a) - manageTextureOf(b))
      : a.category.localeCompare(b.category));
}

function manageSelectedRow() {
  if (!M.selectedKey) return null;
  return manageGrouped().find(r => manageRowKey(r) === M.selectedKey) || null;
}

function managePreviewPayload(row) {
  if (!row) return null;
  const texture = Math.max(0, Number(row._previewTexture ?? row.textureId ?? row.texture ?? 0));
  return { ...row, texture, textureId: texture, texture_id: texture };
}

function fillManageOrgOptions() {
  if (!manageOrgChoices) return;
  manageOrgChoices.innerHTML =
    '<label class="manage-org-choice"><input type="checkbox" data-public-store> <span>PUBLIC STORE</span></label>' +
    M.orgs.map(o => `<label class="manage-org-choice"><input type="checkbox" data-org="${o.key}"> <span>${o.label || String(o.key).toUpperCase()}</span></label>`).join('');
}

function fillManageCategoryOptions() {
  if (!manageCategoryFilter) return;
  const cats = [...new Set(manageGrouped().map(r => effCatOf(r)))].sort();
  const cur = M.category;
  manageCategoryFilter.innerHTML = '<option value="all">All categories</option>' +
    cats.map(c => `<option value="${c}">${CAT_LABELS[c] || c}</option>`).join('');
  manageCategoryFilter.value = cats.includes(cur) ? cur : 'all';
  M.category = manageCategoryFilter.value;
}

function setManageGenderTabs() {
  if (manageGenderMale) manageGenderMale.classList.toggle('active', M.gender === 'male');
  if (manageGenderFemale) manageGenderFemale.classList.toggle('active', M.gender === 'female');
  if (manageGenderMale) manageGenderMale.disabled = M.switchingGender;
  if (manageGenderFemale) manageGenderFemale.disabled = M.switchingGender;
}

function applyManageFitState(data = {}, markReady = true) {
  M.fit = {
    arms: data.arms == null ? null : Number(data.arms),
    armsTexture: Number(data.armsTexture ?? data.arms_texture ?? 0),
    armsCount: Number(data.armsCount || 0),
    undershirt: data.undershirt == null ? null : Number(data.undershirt),
    undershirtTexture: Number(data.undershirtTexture ?? data.undershirt_texture ?? 0),
    undershirtCount: Number(data.undershirtCount || 0),
  };
  if (markReady) M.previewReady = true;
  if (manageArmsValue) {
    const max = Math.max(0, Number(M.fit.arms || 0), M.fit.armsCount - 1);
    manageArmsValue.textContent = M.fit.arms == null ? '—' : `${M.fit.arms} / ${max}`;
  }
  if (manageUnderValue) {
    const max = Math.max(0, Number(M.fit.undershirt || 0), M.fit.undershirtCount - 1);
    manageUnderValue.textContent = M.fit.undershirt == null ? '—' : `${M.fit.undershirt} / ${max}`;
  }
  const disabled = !M.previewReady || M.switchingGender;
  if (manageArmsPrev) manageArmsPrev.disabled = disabled;
  if (manageArmsNext) manageArmsNext.disabled = disabled;
  if (manageUnderPrev) manageUnderPrev.disabled = disabled;
  if (manageUnderNext) manageUnderNext.disabled = disabled;
  if (manageSaveTorsoFit) manageSaveTorsoFit.disabled = disabled;
}

function renderManageGrid() {
  if (!manageGrid) return;
  const rows = manageFiltered();
  if (manageCount) manageCount.textContent = `${rows.length} clothe${rows.length === 1 ? '' : 's'} · ${M.gender.toUpperCase()}`;
  manageGrid.innerHTML = rows.map(r => {
    const key = manageRowKey(r);
    const img = manageImageUrl(r);
    const pub = manageEnabled(r);
    const organizations = manageOrganizationsOf(r);
    const org = organizations.join(' ');
    const effCat = effCatOf(r);
    const overridden = normCat(r) !== effCat;
    let accentCls = 'accent-cyan';
    if (!manageHasImage(r)) accentCls = 'accent-red';
    else if (r.pairedDrawableId !== undefined && Number(r.pairedDrawableId) >= 0) accentCls = 'accent-yellow';
    else if (pub) accentCls = 'accent-green';

    const isPaired = (r.pairedDrawableId !== undefined && Number(r.pairedDrawableId) >= 0);
    const badges = [
      isPaired ? '<span class="m-badge m-badge--both">BOTH</span>' : '',
      organizations.map(value => `<span class="m-badge m-badge--org">${value.toUpperCase()}</span>`).join(''),
      pub ? '<span class="m-badge m-badge--on">IN STORE</span>' : '<span class="m-badge m-badge--off">SAVED</span>',
      manageHasImage(r) ? '' : '<span class="m-badge m-badge--warn">NO IMG</span>',
      r.tempDisabled === true ? '<span class="m-badge m-badge--warn">TEMP DISABLED</span>' : '',
      overridden ? `<span class="m-badge m-badge--org">TYPE: ${(CAT_LABELS[effCat] || effCat).toUpperCase()}</span>` : '',
      (normCat(r) === 'bags' && r.bagSkin === true) ? '<span class="m-badge m-badge--warn">SKIN — NO CAPACITY</span>' : '',
    ].join('');
    const name = r.label || `${CAT_LABELS[effCat] || effCat} ${manageDrawableOf(r)}/${manageTextureOf(r)}`;
    const formattedPrice = `$${Number(r.price || 0).toLocaleString()}`;
    return `<button type="button" class="m-card ${accentCls}${key === M.selectedKey ? ' active' : ''}" data-key="${key}">
      <div class="m-card-img">${img ? `<img src="${img}" loading="lazy" alt="" onerror="this.style.display='none'">` : '<span class="m-card-noimg">NO IMG</span>'}</div>
      <div class="m-card-name">${name}</div>
      <div class="m-card-sub">${CAT_LABELS[effCat] || effCat} · D${manageDrawableOf(r)} T${manageTextureOf(r)} · <strong class="m-card-price">${formattedPrice}</strong></div>
      <div class="m-card-badges">${badges}</div>
    </button>`;
  }).join('');
  manageGrid.querySelectorAll('.m-card').forEach(el => { el.onclick = () => selectManageRow(el.dataset.key); });
}

function renderManageDetail() {
  const row = manageSelectedRow();
  const has = !!row;
  if (manageDetailEmpty) manageDetailEmpty.classList.toggle('hidden', has);
  if (manageDetailBody) manageDetailBody.classList.toggle('hidden', !has);
  if (!has) return;
  const img = manageImageUrl(row);
  if (manageDetailImg) {
    manageDetailImg.src = img || '';
    manageDetailImg.classList.toggle('hidden', !img);
  }
  if (manageDetailNoImg) manageDetailNoImg.classList.toggle('hidden', !!img);
  if (manageDetailMeta) {
    // Bags are captured once (male) and mirrored identically to female --
    // there's no separate male/female bag, so showing a gender tag here would
    // wrongly imply this specific bag only applies to one gender.
    const genderPart = normCat(row) === 'bags' ? '' : ` · ${String(row.gender || 'male').toUpperCase()}`;
    manageDetailMeta.textContent =
      `${CAT_LABELS[row.category] || row.category}${genderPart} · Drawable ${manageDrawableOf(row)} · Texture ${manageTextureOf(row)}`;
  }
  if (manageLabel && document.activeElement !== manageLabel) manageLabel.value = row.label || '';
  if (managePrice && document.activeElement !== managePrice) managePrice.value = String(Number(row.price || 0));
  if (manageTempDisabled) manageTempDisabled.checked = row.tempDisabled === true;

  const physCat = normCat(row);
  const storedSellCategory = String(row.sellCategory || row.sell_category || '').toLowerCase();
  const effCat = (storedSellCategory && storedSellCategory !== physCat) ? storedSellCategory : physCat;
  const isVestMode = physCat === 'armor' && effCat === 'armor';

  if (manageArmorTypeSection) {
    manageArmorTypeSection.classList.remove('hidden');
    if (manageArmorType) {
      const nativeLabel = physCat === 'armor' ? 'Body Armor (Gun Store)' : `Default (${CAT_LABELS[physCat] || physCat})`;
      const options = [`<option value="">${nativeLabel}</option>`]
        .concat(SELL_AS_CATEGORIES.filter(c => c !== physCat)
          .map(c => `<option value="${c}">${CAT_LABELS[c] || c}</option>`));
      manageArmorType.innerHTML = options.join('');
      manageArmorType.value = effCat === physCat ? '' : effCat;
    }
  }

  if (manageOrgSection) manageOrgSection.classList.toggle('hidden', isVestMode);
  if (manageArmorSection) manageArmorSection.classList.toggle('hidden', effCat !== 'armor');
  if (manageBagLevelSection) manageBagLevelSection.classList.toggle('hidden', effCat !== 'bags');
  if (effCat === 'armor') {
    if (manageArmorValue && document.activeElement !== manageArmorValue) {
      manageArmorValue.value = String(Number(row.armorValue ?? row.armor_value ?? 50));
    }
  }
  if (effCat === 'bags' && manageBagLevel) {
    // Skin (cosmetic, no capacity) only makes sense on a NATIVE bags capture
    // -- an off-slot item "sold as bags" has no bag-slot look to reskin, so
    // it's always functional there and only gets the plain level choices.
    const isNativeBags = physCat === 'bags';
    // Only 4 real bags total, one per level, shared across genders (same
    // drawable = same logical bag). A level already published on a DIFFERENT
    // drawable is disabled here -- once all 4 are taken, Skin is the only
    // selectable option left, matching the server-side rule that actually
    // enforces this at save time.
    const myDrawable = manageDrawableOf(row);
    const myLevel = Number(row.bagLevel ?? row.bag_level ?? -1);
    const takenLevels = new Map();
    for (const other of M.rows) {
      if (normCat(other) !== 'bags' || other.bagSkin === true) continue;
      if (manageEnabled(other) !== true) continue;
      if (manageDrawableOf(other) === myDrawable) continue;
      const lvl = Number(other.bagLevel ?? other.bag_level);
      // Never lock out the item's OWN current level, even if a pre-existing
      // data conflict has it duplicated elsewhere -- the server still blocks
      // publishing a genuine duplicate, this is display-only.
      if (lvl >= 1 && lvl <= 4 && lvl !== myLevel) takenLevels.set(lvl, manageDrawableOf(other));
    }
    const levelOptions = [1, 2, 3, 4].map(n => {
      const takenBy = takenLevels.get(n);
      return `<option value="${n}" ${takenBy != null ? 'disabled' : ''}>Level ${n}${takenBy != null ? ` — taken (D${takenBy})` : ''}</option>`;
    }).join('');
    manageBagLevel.innerHTML = isNativeBags
      ? `<option value="skin">Skin (No Capacity)</option>${levelOptions}`
      : levelOptions;
    if (document.activeElement !== manageBagLevel) {
      let defaultLevel = String(Math.max(1, Math.min(4, Number(row.bagLevel ?? row.bag_level ?? 1))));
      // A fresh/never-leveled capture defaulting to a level someone else
      // already holds would select a disabled option -- fall back to Skin
      // (native bags only) or the first still-open level.
      if (takenLevels.has(Number(defaultLevel)) && Number(defaultLevel) !== myLevel) {
        const firstOpen = [1, 2, 3, 4].find(n => !takenLevels.has(n));
        defaultLevel = isNativeBags ? 'skin' : (firstOpen != null ? String(firstOpen) : defaultLevel);
      }
      manageBagLevel.value = (isNativeBags && row.bagSkin === true) ? 'skin' : defaultLevel;
    }
  }

  const isNativeBagsRow = physCat === 'bags';
  const showBagPair = isNativeBagsRow && effCat === 'bags';
  if (manageBagPairSection) manageBagPairSection.classList.toggle('hidden', !showBagPair);
  if (showBagPair && manageBagPairGrid) {
    const rowKey = manageRowKey(row);
    if (M.bagPair.rowKey !== rowKey) {
      const d = row.pairedDrawableId ?? row.paired_drawable_id;
      const t = row.pairedTextureId ?? row.paired_texture_id;
      M.bagPair = { rowKey, pending: (d != null) ? { d: Number(d), t: Number(t ?? -1) } : null, previewingOther: false };
    }
    const otherGender = String(row.gender || 'male').toLowerCase() === 'female' ? 'male' : 'female';
    const candidates = M.rows.filter(r => normCat(r) === 'bags' && String(r.gender || 'male').toLowerCase() === otherGender);
    const pending = M.bagPair.pending;

    const noneCard = `<div class="pair-card none-card${!pending ? ' active' : ''}" data-pair-none>NO PAIR<br>(CLEAR)</div>`;
    const cards = candidates.map(c => {
      const d = manageDrawableOf(c), t = manageTextureOf(c);
      const active = pending && pending.d === d && pending.t === t;
      const img = manageImageUrl(c);
      const tag = c.bagSkin === true ? 'Skin' : `Lvl ${c.bagLevel ?? c.bag_level ?? '?'}`;
      const name = c.label || `Bag ${d}/${t}`;
      return `<div class="pair-card${active ? ' active' : ''}" data-pair-d="${d}" data-pair-t="${t}" title="${name} — ${tag} — D${d} T${t}">
        <div class="pair-card-img">${img ? `<img src="${img}" loading="lazy">` : ''}</div>
        <div class="pair-card-label">D${d} T${t}</div>
      </div>`;
    });
    manageBagPairGrid.innerHTML = [noneCard, ...cards].join('');

    const noneEl = manageBagPairGrid.querySelector('[data-pair-none]');
    if (noneEl) noneEl.onclick = () => {
      M.bagPair.pending = null;
      M.bagPair.previewingOther = false;
      post('managePreviewItem', { row });
      renderManageDetail();
    };
    manageBagPairGrid.querySelectorAll('[data-pair-d]').forEach(el => {
      el.onclick = () => {
        const d = Number(el.dataset.pairD), t = Number(el.dataset.pairT);
        M.bagPair.pending = { d, t };
        M.bagPair.previewingOther = true;
        const candidate = candidates.find(c => manageDrawableOf(c) === d && manageTextureOf(c) === t);
        if (candidate) post('managePreviewItem', { row: candidate });
        renderManageDetail();
      };
    });

    if (manageBagPairRestore) {
      manageBagPairRestore.classList.toggle('hidden', !M.bagPair.previewingOther);
      manageBagPairRestore.onclick = () => {
        M.bagPair.previewingOther = false;
        post('managePreviewItem', { row });
        renderManageDetail();
      };
    }
  }

  if (!isVestMode && manageOrgChoices) {
    const organizations = new Set(manageOrganizationsOf(row));
    const publicInput = manageOrgChoices.querySelector('[data-public-store]');
    if (publicInput) publicInput.checked = row.publicStore === true || String(row.shop || '').toLowerCase() === 'clothes';
    manageOrgChoices.querySelectorAll('[data-org]').forEach(input => { input.checked = organizations.has(input.dataset.org); });
  }

  if (manageLockBanner) {
    if (row.lockedBy) {
      manageLockBanner.textContent = `${row.lockedBy} has this clothe open right now — saves here may overwrite theirs.`;
      manageLockBanner.classList.remove('hidden');
    } else {
      manageLockBanner.classList.add('hidden');
    }
  }
  if (manageAuditTrail) {
    const who = row.updatedBy || row.createdBy || '';
    const when = row.updatedAt || row.createdAt || '';
    if (who || when) {
      manageAuditTrail.textContent = `Last saved by ${who || 'unknown'}${when ? ` on ${when}` : ''}.`;
      manageAuditTrail.classList.remove('hidden');
    } else {
      manageAuditTrail.classList.add('hidden');
    }
  }
  const isTorso = row.category === 'torso';
  if (manageTorsoFit) manageTorsoFit.classList.toggle('hidden', !isTorso);
  if (isTorso) {
    applyManageFitState({
      arms: M.fit.arms == null ? row.arms : M.fit.arms,
      armsTexture: M.fit.arms == null ? (row.armsTexture ?? row.arms_texture ?? 0) : M.fit.armsTexture,
      armsCount: M.fit.armsCount,
      undershirt: M.fit.undershirt == null ? row.undershirt : M.fit.undershirt,
      undershirtTexture: M.fit.undershirt == null ? (row.undershirtTexture ?? row.undershirt_texture ?? 0) : M.fit.undershirtTexture,
      undershirtCount: M.fit.undershirtCount,
    }, false);
  }
  const pub = manageEnabled(row);
  if (managePublishBtn) {
    managePublishBtn.textContent = pub ? 'REMOVE FROM STORE' : 'PUBLISH TO STORE';
    managePublishBtn.classList.toggle('btn--green', !pub);
    managePublishBtn.classList.toggle('btn--close', pub);
  }
  if (manageDetailState) {
    if (isVestMode) {
      manageDetailState.textContent = pub
        ? 'Published: purchasable in the gun store.'
        : 'Saved only — not yet purchasable in the gun store.';
    } else {
      const organizations = manageOrganizationsOf(row);
      const destinations = [row.publicStore === true || String(row.shop || '').toLowerCase() === 'clothes' ? 'PUBLIC STORE' : '',
        ...organizations.map(value => `${value.toUpperCase()} LOCKER`)].filter(Boolean);
      manageDetailState.textContent = pub
        ? `Published in: ${destinations.join(' · ') || 'no destination selected'}.`
        : 'Saved only — players cannot see this clothe yet.';
    }
    manageDetailState.classList.remove('hidden');
    manageDetailState.classList.toggle('item-state-note--ok', pub);
    manageDetailState.classList.toggle('item-state-note--warn', !pub);
  }
}

function manageLockPayload(row) {
  return row ? { gender: row.gender, category: row.category, drawableId: manageDrawableOf(row) } : null;
}
function unlockManageRow(row) {
  const payload = manageLockPayload(row);
  if (payload) post('manageUnlockRow', payload);
}
function lockManageRow(row) {
  const payload = manageLockPayload(row);
  if (payload) post('manageLockRow', payload);
}

function selectManageRow(key) {
  const previous = manageSelectedRow();
  if (previous && manageRowKey(previous) !== key) unlockManageRow(previous);
  M.selectedKey = key || null;
  const row = manageSelectedRow();
  M.previewReady = false;
  M.fit = {
    arms: row && row.arms != null ? Number(row.arms) : null,
    armsTexture: Number(row && (row.armsTexture ?? row.arms_texture) || 0),
    armsCount: 0,
    undershirt: row && row.undershirt != null ? Number(row.undershirt) : null,
    undershirtTexture: Number(row && (row.undershirtTexture ?? row.undershirt_texture) || 0),
    undershirtCount: 0,
  };
  renderManageGrid();
  renderManageDetail();
  // Selection is the preview action. The explicit PREVIEW button remains as a
  // retry, but admins no longer need a second click for every clothe.
  if (row) post('managePreviewItem', { row: managePreviewPayload(row) });
}

function manageBuildSavePayload(row, published) {
  const destinations = selectedManageDestinations();
  const payload = {
    category: row.category,
    drawableId: manageDrawableOf(row),
    textureId: -1,
    gender: String(row.gender || 'male').toLowerCase(),
    label: manageLabel && manageLabel.value.trim() ? manageLabel.value.trim() : (row.label || ''),
    price: managePrice && managePrice.value !== ''
      ? Math.max(0, Math.floor(Number(managePrice.value) || 0))
      : Number(row.price || 0),
    orgs: destinations.organizations,
    publicStore: destinations.publicStore,
    published: published === true,
    image: row.image || row.icon || '',
    tempDisabled: manageTempDisabled ? manageTempDisabled.checked : (row.tempDisabled === true),
  };
  if (row.category === 'torso') {
    payload.arms = M.fit.arms;
    payload.armsTexture = M.fit.armsTexture;
    payload.undershirt = M.fit.undershirt;
    payload.undershirtTexture = M.fit.undershirtTexture;
  }
  const physCat = normCat(row);
  const sellCategory = manageArmorType ? manageArmorType.value : (row.sellCategory || row.sell_category || '');
  payload.sellCategory = sellCategory || '';
  const effCat = (sellCategory && sellCategory !== physCat) ? sellCategory : physCat;
  if (effCat === 'armor') {
    payload.armorValue = manageArmorValue && manageArmorValue.value !== ''
      ? Math.max(0, Math.min(100, Math.floor(Number(manageArmorValue.value) || 0)))
      : Number(row.armorValue ?? row.armor_value ?? 50);
  }
  if (effCat === 'bags') {
    const bagValue = manageBagLevel ? manageBagLevel.value : (row.bagSkin === true ? 'skin' : String(row.bagLevel ?? row.bag_level ?? 1));
    if (physCat === 'bags' && bagValue === 'skin') {
      payload.bagSkin = true;
    } else {
      payload.bagSkin = false;
      payload.bagLevel = bagValue !== '' ? Math.max(1, Math.min(4, Math.floor(Number(bagValue) || 1))) : Number(row.bagLevel ?? row.bag_level ?? 1);
    }
  }
  if (physCat === 'bags' && effCat === 'bags' && M.bagPair.rowKey === manageRowKey(row)) {
    const pending = M.bagPair.pending;
    if (pending) {
      payload.pairedDrawableId = pending.d;
      payload.pairedTextureId = pending.t;
    } else {
      // Explicitly cleared (picked "No Pair") -- send -1 to distinguish "leave
      // whatever pairing already existed" (field omitted) from "the admin
      // picked None" (server treats this drawable as unpaired).
      payload.pairedDrawableId = -1;
    }
  }
  return payload;
}

async function manageSaveSelected(publishOverride) {
  const row = manageSelectedRow();
  if (!row) return;
  const published = publishOverride === undefined ? manageEnabled(row) : publishOverride;
  if (published && !manageHasImage(row)) {
    toast('This clothe has no image. Use RETAKE IMAGE first, then publish.', 'error');
    return;
  }
  await post('manageSaveItem', manageBuildSavePayload(row, published));
  // If a pairing candidate on the other gender was left previewing on the
  // ped, switch back to showing this row's own look now that the save (and
  // its pairing choice) is committed.
  if (M.bagPair.previewingOther && M.bagPair.rowKey === manageRowKey(row)) {
    M.bagPair.previewingOther = false;
    post('managePreviewItem', { row });
    renderManageDetail();
  }
}

function applyManageSaved(row) {
  if (!row) return;
  const base = manageBaseKey(row);
  const selectedKey = M.selectedKey;
  let updated = false;
  M.rows = M.rows.map(existing => {
    if (manageBaseKey(existing) !== base) return existing;
    updated = true;
    return {
      ...existing,
      label: row.label,
      description: row.description,
      price: row.price,
      enabled: row.enabled,
      shop: row.shop,
      org: row.org,
      organizations: row.organizations,
      publicStore: row.publicStore,
      arms: row.arms,
      armsTexture: row.armsTexture ?? row.arms_texture,
      undershirt: row.undershirt,
      undershirtTexture: row.undershirtTexture ?? row.undershirt_texture,
      armorValue: row.armorValue ?? row.armor_value,
      bagLevel: row.bagLevel ?? row.bag_level ?? existing.bagLevel,
      bagSkin: row.bagSkin ?? existing.bagSkin,
      pairedDrawableId: row.pairedDrawableId ?? row.paired_drawable_id ?? existing.pairedDrawableId,
      pairedTextureId: row.pairedTextureId ?? row.paired_texture_id ?? existing.pairedTextureId,
      sellCategory: row.sellCategory ?? row.sell_category ?? existing.sellCategory,
      createdBy: row.createdBy ?? existing.createdBy,
      updatedBy: row.updatedBy ?? existing.updatedBy,
      createdAt: row.createdAt ?? existing.createdAt,
      updatedAt: row.updatedAt ?? existing.updatedAt,
    };
  });
  if (!updated) M.rows.push(row);
  M.selectedKey = selectedKey;
  fillManageCategoryOptions();
  renderManageGrid();
  renderManageDetail();
  // Keep the shop catalog copy consistent if it is loaded in this session.
  const i = S.catalog.findIndex(c => drawKey(normRow(c)) === drawKey(normRow(row)));
  if (i >= 0) S.catalog[i] = { ...S.catalog[i], ...row };
}

function openManage(data) {
  M.open = data.value !== false;
  if (managePanel) managePanel.classList.toggle('hidden', !M.open);
  app.classList.toggle('manage-mode', M.open);
  if (M.open) {
    app.classList.remove('hidden');
    app.classList.remove('store-mode');
    app.classList.remove('admin-mode');
    app.style.display = 'block';
  } else if (!S.open) {
    app.classList.add('hidden');
    app.classList.remove('manage-mode');
    app.style.display = 'none';
  }
  if (!M.open) return;
  M.orgs = Array.isArray(data.orgs) ? data.orgs : [];
  M.rows = [];
  M.gender = String(data.gender || 'male').toLowerCase() === 'female' ? 'female' : 'male';
  M.selectedKey = null;
  M.q = '';
  if (manageSearch) manageSearch.value = '';
  setManageGenderTabs();
  fillManageOrgOptions();
  renderManageGrid();
  renderManageDetail();
}

async function setManageGender(g) {
  const next = g === 'female' ? 'female' : 'male';
  if (M.switchingGender) return;

  // Always round-trip through manageSetGender, even on a same-tab click — the
  // manager can reopen with stale NUI state after a model swap/retake, and the
  // Lua side now re-verifies the ped's actual model hash rather than trusting
  // the tab we last rendered, so a repeat click self-heals a desynced ped.
  M.switchingGender = true;
  M.gender = next;
  M.selectedKey = null;
  M.previewReady = false;
  setManageGenderTabs();
  renderManageGrid();
  renderManageDetail();
  const res = await Promise.race([
    post('manageSetGender', { gender: next }),
    new Promise(resolve => setTimeout(() => resolve({ success: false, error: 'model_switch_timeout' }), 10000)),
  ]);
  M.switchingGender = false;
  setManageGenderTabs();
  if (!res || res.success !== true) toast(`Could not switch to ${next} model.`, 'error');
}

async function cycleManageFit(slot, dir) {
  const row = manageSelectedRow();
  if (!row || row.category !== 'torso') return;
  if (!M.previewReady) { toast('Wait for the live preview to finish loading.', 'info'); return; }
  const res = await post('manageCycleFit', { slot, dir });
  if (res && res.success) applyManageFitState(res);
}

async function saveManageTorsoFit() {
  const row = manageSelectedRow();
  if (!row || row.category !== 'torso') return;
  if (!M.previewReady) { toast('Wait for the live preview to finish loading.', 'info'); return; }
  const fit = await post('manageGetFit', {});
  if (!fit || fit.success === false) return;
  applyManageFitState(fit);
  await manageSaveSelected(undefined);
}

// /clothingstore handed us a clothe to re-photograph. Once the admin panel is
// open and its catalog has loaded, jump straight to that exact item.
function tryApplyPendingRetake() {
  const row = S.pendingRetake;
  if (!row || !S.open || !S.isAdmin) return;
  const cat = normCat(row);
  if (!cat || !S.categories.includes(cat)) return;
  S.pendingRetake = null;
  setCategory(cat);
  const target = manageDrawableOf(row);
  const idx = S.filtered.findIndex(r => Number(r.drawable) === target);
  if (idx >= 0) {
    S.itemPos = idx;
    S.selected = S.filtered[idx];
    const tex = Number(row.textureId ?? row.texture ?? 0);
    S.texture = tex >= 0 ? tex : 0;
    S.textureCount = 1;
    applyTextureModeFromCatalog(S.texture);
    updateBottom();
    previewSelected();
  }
  // Keep the item's identity for the capture that follows. Browsing to another
  // drawable now changes THIS item rather than creating a second one.
  S.retakeAssetId = row.assetId || row.asset_id || null;
  S.retakeLabel = row.label || `${cat} ${target}`;
  renderRetakeBanner();
  $('itemName').textContent = S.retakeAssetId
    ? `RETAKE: ${S.retakeLabel} — pick any clothes, TAKE IMAGE replaces it`
    : `RETAKE: ${S.retakeLabel} — use TAKE IMAGE / UPDATE`;
}

// Standing reminder that the next capture replaces an existing item, with a way
// out. Without it an admin who wandered off to browse would have no way of
// knowing their next photo overwrites a clothe rather than adding one.
function renderRetakeBanner() {
  let el = document.getElementById('retakeBanner');
  if (!S.retakeAssetId) { if (el) el.remove(); return; }
  if (!el) {
    el = document.createElement('div');
    el.id = 'retakeBanner';
    el.style.cssText = 'position:fixed;left:50%;transform:translateX(-50%);top:calc(12px + env(safe-area-inset-top,0px));z-index:9999;background:#1d4ed8;color:#fff;padding:8px 14px;border-radius:8px;font:600 13px system-ui,sans-serif;display:flex;gap:12px;align-items:center;box-shadow:0 4px 16px rgba(0,0,0,.35);max-width:92vw;';
    document.body.appendChild(el);
  }
  el.innerHTML = '';
  const text = document.createElement('span');
  text.textContent = `REPLACING "${S.retakeLabel}" — your next photo changes this item's clothes and picture`;
  const cancel = document.createElement('button');
  cancel.type = 'button';
  cancel.textContent = 'CANCEL';
  cancel.style.cssText = 'background:rgba(255,255,255,.18);color:#fff;border:0;border-radius:5px;padding:4px 10px;font:600 12px system-ui,sans-serif;cursor:pointer;';
  cancel.onclick = () => { clearRetakeTarget(); toast('Replace cancelled — captures now add new items.', 'success'); };
  el.appendChild(text);
  el.appendChild(cancel);
}

function clearRetakeTarget() {
  S.retakeAssetId = null;
  S.retakeLabel = '';
  S.activeReplaceAssetId = null;
  renderRetakeBanner();
}

if (manageCloseBtn)   manageCloseBtn.onclick   = () => {
  const r = manageSelectedRow();
  if (r) unlockManageRow(r);
  M.open = false;
  if (managePanel) managePanel.classList.add('hidden');
  app.classList.remove('manage-mode');
  if (!S.open) {
    app.classList.add('hidden');
    app.style.display = 'none';
  }
  post('manageClose');
};
if (manageRefreshBtn) manageRefreshBtn.onclick = () => post('manageRefresh');
if (manageGenderMale)   manageGenderMale.onclick   = () => setManageGender('male');
if (manageGenderFemale) manageGenderFemale.onclick = () => setManageGender('female');
if (manageCategoryFilter) manageCategoryFilter.onchange = () => {
  M.category = manageCategoryFilter.value;
  M.selectedKey = null;
  renderManageGrid();
  renderManageDetail();
};
if (manageStatusFilter) manageStatusFilter.onchange = () => { M.status = manageStatusFilter.value; renderManageGrid(); };
if (manageArmorType) manageArmorType.onchange = () => {
  const r = manageSelectedRow();
  if (!r) return;
  // Preview the section swap immediately; nothing is persisted until SAVE CHANGES.
  const physCat = normCat(r);
  const sellCategory = manageArmorType.value;
  const effCat = (sellCategory && sellCategory !== physCat) ? sellCategory : physCat;
  const isVestMode = physCat === 'armor' && effCat === 'armor';
  if (manageOrgSection) manageOrgSection.classList.toggle('hidden', isVestMode);
  if (manageArmorSection) manageArmorSection.classList.toggle('hidden', effCat !== 'armor');
  if (manageBagLevelSection) manageBagLevelSection.classList.toggle('hidden', effCat !== 'bags');
};
if (manageSearch) manageSearch.addEventListener('input', () => { M.q = manageSearch.value; renderManageGrid(); });
if (managePublishBtn) managePublishBtn.onclick = () => {
  const r = manageSelectedRow();
  if (r) manageSaveSelected(!manageEnabled(r));
};
if (manageSaveBtn) manageSaveBtn.onclick = () => manageSaveSelected(undefined);
if (managePreviewBtn) managePreviewBtn.onclick = () => {
  const r = manageSelectedRow();
  if (r) post('managePreviewItem', { row: managePreviewPayload(r) });
};
if (manageArmsPrev) manageArmsPrev.onclick = () => cycleManageFit('arms', -1);
if (manageArmsNext) manageArmsNext.onclick = () => cycleManageFit('arms', 1);
if (manageUnderPrev) manageUnderPrev.onclick = () => cycleManageFit('undershirt', -1);
if (manageUnderNext) manageUnderNext.onclick = () => cycleManageFit('undershirt', 1);
if (manageSaveTorsoFit) manageSaveTorsoFit.onclick = () => saveManageTorsoFit();
if (manageRetakeBtn) manageRetakeBtn.onclick = () => {
  const r = manageSelectedRow();
  if (r) post('manageRetake', { row: r });
};
if (manageRevertBtn) manageRevertBtn.onclick = async () => {
  const r = manageSelectedRow();
  if (!r || r.id == null) { toast('Nothing to revert — refresh and try again.', 'error'); return; }
  await post('manageRevertImage', { id: r.id, assetId: r.assetId || null });
  post('manageRefresh');
};
if (manageCoverBtn) manageCoverBtn.onclick = async () => {
  const r = manageSelectedRow();
  if (!r || !manageHasImage(r)) { toast('This clothe has no image to use as a cover photo.', 'error'); return; }
  await post('manageSetCoverImage', {
    gender: r.gender, category: r.category, drawableId: manageDrawableOf(r), image: r.image || r.icon || '',
  });
  post('manageRefresh');
};

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
      // A /clothingstore retake may be waiting for this catalog.
      tryApplyPendingRetake();
      // The real catalog for a just-switched gender arrives here, async and
      // AFTER switchAdminGender's own promise already resolved -- refresh
      // bag-pairing candidates now that S.catalog actually reflects it.
      refreshBagPairCandidates();
      break;
    case 'adminMode':         setAdminMode(data.value);                         break;
    case 'adminGenderChanged':
      S.adminGenderSwitching = false;
      applyAdminGenderChanged(data.gender, data.counts || {});
      break;

    case 'openManagePanel':   openManage(data);                                 break;
    case 'manageCatalog':
      M.rows = Array.isArray(data.rows) ? data.rows : [];
      fillManageCategoryOptions();
      if (data.focusRow) {
        // Handed off straight from a fresh bag capture -- jump the manager
        // to that exact row so the admin can pick its cross-gender pairing
        // immediately, instead of having to find it themselves.
        const fr = data.focusRow;
        const frGender = String(fr.gender || 'male').toLowerCase() === 'female' ? 'female' : 'male';
        const frCat = String(fr.category || '').toLowerCase();
        const match = M.rows.find(r => normCat(r) === frCat
          && String(r.gender || 'male').toLowerCase() === frGender
          && manageDrawableOf(r) === Number(fr.drawableId)
          && manageTextureOf(r) === Number(fr.textureId));
        if (match) {
          M.gender = frGender;
          M.category = frCat || 'all';
          setManageGenderTabs();
          if (manageCategoryFilter) manageCategoryFilter.value = M.category;
          M.selectedKey = manageRowKey(match);
        }
      }
      renderManageGrid();
      renderManageDetail();
      break;
    case 'manageItemSaved':   applyManageSaved(data.row);                       break;
    case 'manageFitState':    applyManageFitState(data);                         break;
    case 'manageRetakeTarget':
      S.pendingRetake = data.row || null;
      tryApplyPendingRetake();
      break;

    case 'favourites':
      S.favourites = new Set((data.keys || []).map(k => String(k).toLowerCase()));
      updateFavButton();
      renderCategories();
      if (S.activeCategory === '__fav') setCategory('__fav');
      break;

    case 'captureCrops':
      S.captureCrops = {};
      Object.entries(data.crops || {}).forEach(([category, crop]) => {
        const key = normCat({ category });
        if (key) S.captureCrops[key] = crop;
      });
      syncCropSection();
      break;

    case 'manualPoseStart':
      enterPoseMode(data.category, Number(data.heading) || 0, data.camera || {});
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
          // Build 2.19: captures save the clothe UNPUBLISHED unless it was
          // already published; the server's entry carries the real enabled
          // state, so never force enabled: true here.
          const row = normRow(data.entry);
          const i   = S.catalog.findIndex(r => fullKey(normRow(r)) === fullKey(row));
          if (i >= 0) S.catalog[i] = { ...S.catalog[i], ...data.entry };
          else S.catalog.push({ ...data.entry });
          if (S.selected && drawKey(S.selected) === drawKey(row)) {
            S.selected = { ...S.selected, ...row };
            if (S.filtered[S.itemPos]) S.filtered[S.itemPos] = { ...S.filtered[S.itemPos], ...row };
          }
          renderCategories();
          updateBottom();
        }
        $('itemName').textContent = data.entry?.imageOnly
          ? '✓ PNG + WEBP SAVED LOCALLY'
          : (data.entry?.enabled === true
            ? '✓ IMAGE RETAKEN — CLOTHE STAYS PUBLISHED'
            : '✓ CLOTHE SAVED — PUBLISH IT IN /clothingstore');
        if (data.entry && !data.entry.imageOnly && String(data.entry.category || '').toLowerCase() === 'bags') {
          if (!S.bulkRunning) {
            enterBagPairing(data.entry);
          }
        }
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
      setCaptureStatus(true, 'Removing background from single capture…');
      removeBackgroundAndCrop(data.image, data.payload || {})
        .then(result => {
          const cat = normCat({ category: (data.payload && data.payload.category) || S.activeCategory || '' });

          // 1) Admin is (re)setting the crop for this category: open the editor.
          //    Whatever they save becomes the category's persistent crop.
          //    Only during a single capture — never mid category bulk run.
          const inCategoryBulk = String(S.captureMode || '').startsWith('wholecategory_');
          if (S.armCropForCategory && S.armCropForCategory === cat && !inCategoryBulk) {
            // Consume the request before opening the editor. If image saving later
            // retries, it must use the saved crop automatically instead of opening
            // the crop editor a second time.
            S.armCropForCategory = null;
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
        // Show exactly the pixels that continue to encoding/saving. Previously
        // the preview was updated before the saved category crop ran, so a retake
        // looked uncropped even though its output file was cropped afterward.
        .then(result => {
          if (capturePreview && result && result.dataUrl) {
            capturePreview.src = result.dataUrl;
            capturePreview.classList.remove('hidden');
          }
          return result;
        })
        .then(result => addRequestedOutputFormats(result, data.payload || {}))
        .then(result => post('iconProcessed', { ...result, payload: data.payload || {} }))
        .then(() => { if (!S.bulkRunning) setCaptureStatus(false); })
        .catch(err => {
          setCaptureStatus(false);
          $('itemName').textContent = `✗ PROCESS FAILED: ${err.message || err}`;
          if (S.pendingIconResolver) S.pendingIconResolver({ success: false, error: String(err.message || err) });
        });
      break;

    case 'captureDiagnostic': {
      const d = data.diagnostic || {};
      const attached = d.itemAttached === true ? 'PROP/ITEM OK' : 'PROP/ITEM FAILED';
      const message = `${attached} · expected D${d.expectedDrawable}/T${d.expectedTexture}, actual D${d.actualDrawable}/T${d.actualTexture} · ` +
        `model ${d.expectedGender || '?'}→${d.actualGender || '?'} · isolation ${d.isolationMode || 'unknown'} · empty head ${d.emptyHeadAccepted ? 'OK' : 'fallback'}`;
      console.log('[nv_cloth] capture diagnostic', d);
      setCaptureStatus(true, message);
      break;
    }
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
if ($('modelScrubSlider')) {
  $('modelScrubSlider').oninput = (e) => {
    const idx = Number(e.target.value);
    if (idx !== S.itemPos && S.filtered[idx]) {
      S.itemPos = idx;
      S.selected = S.filtered[S.itemPos];
      if (S.activeCategory === 'torso' && S.selected) S.adminTorsoTarget = { ...S.selected };
      S.texture = previewTexture(S.selected.texture);
      S.textureCount = 1;
      applyTextureModeFromCatalog(S.texture);
      updateBottom();
      previewSelected();
    }
  };
}

if ($('clothTypeInput')) {
  $('clothTypeInput').onchange = (e) => {
    let val = parseInt(e.target.value, 10);
    if (isNaN(val)) val = 1;
    val = Math.max(1, Math.min(S.filtered.length, val));
    e.target.value = val;
    const newPos = val - 1;
    if (newPos !== S.itemPos && S.filtered[newPos]) {
      S.itemPos = newPos;
      S.selected = S.filtered[S.itemPos];
      if (S.activeCategory === 'torso' && S.selected) S.adminTorsoTarget = { ...S.selected };
      S.texture = previewTexture(S.selected.texture);
      S.textureCount = 1;
      applyTextureModeFromCatalog(S.texture);
      updateBottom();
      previewSelected();
    }
  };
  $('clothTypeInput').onkeydown = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      $('clothTypeInput').blur();
    }
  };
}

if ($('clothTextureInput')) {
  $('clothTextureInput').onchange = (e) => {
    let val = parseInt(e.target.value, 10);
    if (isNaN(val)) val = 0;
    const maxTex = Math.max(0, S.textureCount - 1);
    val = Math.max(0, Math.min(maxTex, val));
    e.target.value = val;
    if (val !== S.texture) {
      if (S.exactTextureRows && S.exactTextureRows.length > 0) {
        const row = S.exactTextureRows.find(r => Number(r.texture) === val) || S.exactTextureRows[0];
        S.texture = previewTexture(row.texture);
        S.selected = { ...S.selected, ...row };
      } else {
        S.texture = val;
      }
      if (S.activeCategory === 'torso' && S.selected)
        S.adminTorsoTarget = { ...S.selected, texture: S.texture, textureId: S.texture };
      updateBottom();
      previewSelected();
    }
  };
  $('clothTextureInput').onkeydown = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      $('clothTextureInput').blur();
    }
  };
}

if (adminGenderMale) adminGenderMale.onclick = () => switchAdminGender('male');
if (adminGenderFemale) adminGenderFemale.onclick = () => switchAdminGender('female');

// Capture backdrop preview is optional while browsing. Capture always uses selected color.
if (captureBackground) captureBackground.onchange = () => refreshCaptureBackdropPreview();
if (previewWall) previewWall.onchange = () => refreshCaptureBackdropPreview();

// Bulk capture buttons
if (saveMissingBtn) saveMissingBtn.onclick = async () => runBulkCapture('missing');
if (saveAllBtn)     saveAllBtn.onclick     = async () => runBulkCapture('all');
if ($('catMissingBtn')) $('catMissingBtn').onclick = async () => runCategoryCapture('missing');
if ($('catAllBtn'))     $('catAllBtn').onclick     = async () => runCategoryCapture('all');
if (allGendersBtn)      allGendersBtn.onclick      = async () => runAllGenderCapture();
if (adjustCaptureBtn) adjustCaptureBtn.onclick = async () => runBulkCapture('current', true);
if (pauseBulkBtn) pauseBulkBtn.onclick = () => {
  if (!S.bulkRunning) return;
  S.bulkPaused = true;
  applyBulkDisabled(true);
  setBulkProgress('Paused after the current image. Press Resume to continue.');
};
if (resumeBulkBtn) resumeBulkBtn.onclick = () => {
  if (!S.bulkRunning) return;
  S.bulkPaused = false;
  applyBulkDisabled(true);
  setBulkProgress('Resuming capture…');
};
if (cancelBulkBtn)  cancelBulkBtn.onclick  = () => {
  S.bulkCancel = true;
  S.bulkPaused = false;
  setBulkProgress('Cancelling after current texture…');
};

// Buy / Save button
buyBtn.onclick = async () => {
  if (!S.selected) return;
  if (S.isAdmin) { await runBulkCapture('current'); return; }
  const item = { ...S.selected, texture: previewTexture(S.texture), textureId: previewTexture(S.texture), drawableId: S.selected.drawable };
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
  if (S.bulkRunning) {
    toast('Cancel the capture queue first. The player will be restored after the current image.', 'error');
    return;
  }
  S.isAdmin         = false;
  S.adminTorsoTarget = null;
  S.cart            = [];
  // Leaving the panel drops any pending replace, so reopening it later starts
  // clean and a forgotten retake cannot overwrite an item much later.
  clearRetakeTarget();
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
  S.open = false;
  app.classList.add('hidden');
  app.classList.remove('store-mode');
  app.classList.remove('admin-mode');
  app.style.display = 'none';
};

// Keyboard shortcuts
document.addEventListener('keydown', e => {
  if (M.open) {
    if (e.key === 'Escape') {
      if (manageCloseBtn) manageCloseBtn.click();
      else post('manageClose');
    }
    return;
  }
  if (!S.open) return;
  if (S.bulkRunning && !S.manualPosing) return;
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
  if (!dragging || (!S.open && !M.open)) return;
  const dx = e.clientX - lastX;
  lastX = e.clientX;
  if (Math.abs(dx) <= 1) return;
  if (M.open) {
    // Only rotate when dragging on the open game area, not over the manager UI.
    if (managePanel && managePanel.contains(e.target) && e.target.closest('.manage-left, .manage-detail')) return;
    post('manageRotatePed', { delta: -dx * 0.45 });
  } else if (S.manualPosing) {
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

// Pose bar controls
if ($('poseRotLeftBig'))  $('poseRotLeftBig').addEventListener('click',  () => poseRotate(-45));
if ($('poseRotLeft'))     $('poseRotLeft').addEventListener('click',     () => poseRotate(-15));
if ($('poseRotRight'))    $('poseRotRight').addEventListener('click',    () => poseRotate(15));
if ($('poseRotRightBig')) $('poseRotRightBig').addEventListener('click', () => poseRotate(45));
if ($('poseHeading'))     $('poseHeading').addEventListener('input', e => poseSetHeading(Number(e.target.value) || 0));
if ($('poseLiftUp'))      $('poseLiftUp').addEventListener('click',   () => poseLift(0.08));
if ($('poseLiftDown'))    $('poseLiftDown').addEventListener('click', () => poseLift(-0.08));
if ($('poseMoveLeft'))    $('poseMoveLeft').addEventListener('click',   () => poseMove('side', -0.05));
if ($('poseMoveRight'))   $('poseMoveRight').addEventListener('click',  () => poseMove('side',  0.05));
if ($('poseMoveToward'))  $('poseMoveToward').addEventListener('click', () => poseMove('depth', 0.05));
if ($('poseMoveAway'))    $('poseMoveAway').addEventListener('click',   () => poseMove('depth', -0.05));
if ($('poseCamOrbitLeft'))  $('poseCamOrbitLeft').addEventListener('click',  () => poseCamera('orbit', -4.0));
if ($('poseCamOrbitRight')) $('poseCamOrbitRight').addEventListener('click', () => poseCamera('orbit',  4.0));
if ($('poseCamIn'))         $('poseCamIn').addEventListener('click',         () => poseCamera('zoom',    0.10));
if ($('poseCamOut'))        $('poseCamOut').addEventListener('click',        () => poseCamera('zoom',   -0.10));
if ($('poseCamDown'))       $('poseCamDown').addEventListener('click',       () => poseCamera('height', -0.04));
if ($('poseCamUp'))         $('poseCamUp').addEventListener('click',         () => poseCamera('height',  0.04));
if ($('poseFovWide'))       $('poseFovWide').addEventListener('click',       () => poseCamera('fov',    -2.0));
if ($('poseFovTight'))      $('poseFovTight').addEventListener('click',      () => poseCamera('fov',     2.0));
if ($('poseConfirm'))     $('poseConfirm').addEventListener('click', poseConfirm);
if ($('poseCancel'))      $('poseCancel').addEventListener('click', poseCancel);
