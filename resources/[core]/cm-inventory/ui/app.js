
// FiveM CEF transparency safety: force page background transparent in-game.
document.documentElement.style.background = 'rgba(0,0,0,0)';
document.body.style.background = 'rgba(0,0,0,0)';
document.documentElement.style.backgroundColor = 'rgba(0,0,0,0)';
document.body.style.backgroundColor = 'rgba(0,0,0,0)';

const root = document.getElementById('inventory');
const quickEl = document.getElementById('quick-slots');
const pocketEl = document.getElementById('pocket-slots');
const backpackEl = document.getElementById('backpack-slots');
const gearEl = document.getElementById('gear-slots');
const contextEl = document.getElementById('context-menu');
const tooltipEl = document.getElementById('tooltip');
const splitModal = document.getElementById('split-modal');
const splitAmount = document.getElementById('split-amount');
const splitLabel = document.getElementById('split-label');
const giveModal = document.getElementById('give-modal');
const giveAmount = document.getElementById('give-amount');
const giveLabel = document.getElementById('give-label');
const dropModal = document.getElementById('drop-modal');
const dropAmount = document.getElementById('drop-amount');
const dropLabel = document.getElementById('drop-label');
const progressOverlay = document.getElementById('use-progress');
const progressFill = document.getElementById('progress-fill');
const progressLabel = document.getElementById('progress-label');
const toastEl = document.getElementById('toast');
const giveDropZone = document.getElementById('give-drop-zone');
const dropPickupPanel = document.getElementById('drop-pickup-panel');
const dropPickupList = document.getElementById('drop-pickup-list');

let state = {
  open: false,
  items: [],
  slots: null,
  weight: { current: 0, max: 82000 },
  dragged: null,
  contextItem: null,
  contextOpen: false,
  splitSource: null,
  splitTarget: null,
  giveSource: null,
  dropSource: null,
  bag: { level: 0, backpackSlots: 0, maxWeight: 25000 },
  external: null
};

const equipmentLabels = {
  mask: 'Mask', glasses: 'Glasses', headwear: 'Headwear', earrings: 'Earrings',
  outerwear: 'Outerwear', shirt: 'Shirt', bodyarmor: 'Body Armor', bag: 'Bag', accessory: 'Accessories',
  weapon: 'Weapon', ammo: 'Ammo', watch: 'Watch', pants: 'Pants', shoes: 'Shoes'
};

function equipmentIconSvg(slot) {
  const common = 'viewBox="0 0 24 24" aria-hidden="true" class="equip-svg"';
  const stroke = 'fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"';
  const icons = {
    mask: `<svg ${common}><path ${stroke} d="M5 9c1.9-2 4.2-3 7-3s5.1 1 7 3v5.2c0 2.3-1.8 4.2-4 4.2-1.3 0-2.3-.5-3-1.4-0.7.9-1.7 1.4-3 1.4-2.2 0-4-1.9-4-4.2V9z"/><path ${stroke} d="M8.2 11.2h2M13.8 11.2h2M10 15h4"/></svg>`,
    glasses: `<svg ${common}><circle ${stroke} cx="8" cy="13" r="3.3"/><circle ${stroke} cx="16" cy="13" r="3.3"/><path ${stroke} d="M11.3 13h1.4M4.7 12.3 3 11M19.3 12.3 21 11"/></svg>`,
    headwear: `<svg ${common}><path ${stroke} d="M5 12c.7-4 3-6 7-6s6.3 2 7 6"/><path ${stroke} d="M4 13h16M7 13v4h10v-4"/></svg>`,
    earrings: `<svg ${common}><path ${stroke} d="M12 5v5"/><circle ${stroke} cx="12" cy="13" r="2.2"/><path ${stroke} d="M12 15.2v3.8"/><circle ${stroke} cx="12" cy="20" r="1"/></svg>`,
    outerwear: `<svg ${common}><path ${stroke} d="M8 4 5 7v13h5v-8h4v8h5V7l-3-3"/><path ${stroke} d="M9 4c.5 1.7 1.5 2.6 3 2.6S14.5 5.7 15 4"/></svg>`,
    shirt: `<svg ${common}><path ${stroke} d="M9 4 5 6.5 3.5 11 7 12.5V20h10v-7.5L20.5 11 19 6.5 15 4"/><path ${stroke} d="M9 4c.8 1.2 1.8 1.8 3 1.8S14.2 5.2 15 4"/></svg>`,
    bodyarmor: `<svg ${common}><path ${stroke} d="M12 3 5.5 6v5.3c0 4.1 2.6 7.3 6.5 9.7 3.9-2.4 6.5-5.6 6.5-9.7V6L12 3z"/><path ${stroke} d="M9 10h6M9 14h6"/></svg>`,
    bag: `<svg ${common}><path ${stroke} d="M7 9V7a5 5 0 0 1 10 0v2"/><rect ${stroke} x="5" y="8" width="14" height="12" rx="3"/><path ${stroke} d="M9 12v4M15 12v4"/></svg>`,
    accessory: `<svg ${common}><path ${stroke} d="M7 5c3 4 7 4 10 0"/><path ${stroke} d="M8 5c0 5 1.3 9.2 4 14 2.7-4.8 4-9 4-14"/><circle ${stroke} cx="12" cy="15" r="1.4"/></svg>`,
    weapon: `<svg ${common}><path ${stroke} d="M4 12h10l3-3h3v4h-4l-2 2H9l-1 4H5l1-4H4z"/></svg>`,
    ammo: `<svg ${common}><path ${stroke} d="M10 4h4l1 3v12a2 2 0 0 1-2 2h-2a2 2 0 0 1-2-2V7l1-3z"/><path ${stroke} d="M9 8h6"/></svg>`,
    watch: `<svg ${common}><path ${stroke} d="M9 3h6l-1 4H10L9 3zM10 17h4l1 4H9l1-4z"/><circle ${stroke} cx="12" cy="12" r="4.5"/><path ${stroke} d="M12 10v2.5l1.7 1"/></svg>`,
    pants: `<svg ${common}><path ${stroke} d="M8 4h8l-1 16h-4l-1-9-1 9H5L8 4z"/><path ${stroke} d="M10 4v7"/></svg>`,
    shoes: `<svg ${common}><path ${stroke} d="M5 15c2.8 1.2 5.7 1.2 9 0l2 2h3c.7 0 1 .4 1 1v1H4v-2.5c0-.8.4-1.3 1-1.5z"/></svg>`
  };
  return icons[slot] || `<svg ${common}><path ${stroke} d="M12 4 20 12 12 20 4 12z"/></svg>`;
}


const equipmentByCategory = {
  mask: 'mask', glasses: 'glasses', headwear: 'headwear', hat: 'headwear', earrings: 'earrings',
  outerwear: 'outerwear', jacket: 'outerwear', shirt: 'shirt', tshirt: 'shirt', armor: 'bodyarmor', bodyarmor: 'bodyarmor',
  bag: 'bag', backpack: 'bag', accessory: 'accessory', weapon: 'weapon', ammo: 'ammo', watch: 'watch', pants: 'pants', shoes: 'shoes'
};
const equipmentSlots = new Set(Object.keys(equipmentLabels));
function bestEquipmentSlot(item) {
  const cat = String(item?.category || item?.type || '').toLowerCase();
  const name = String(item?.item_name || item?.name || '').toLowerCase();
  const metaCat = String(item?.metadata?.categoryType || item?.metadata?.category || '').toLowerCase();
  const equipSlot = String(item?.equipmentSlot || item?.equipSlot || item?.metadata?.equipmentSlot || '').toLowerCase();
  if (equipmentSlots.has(equipSlot)) return equipSlot;

  if (name.startsWith('clothing_')) {
    const clothingCat = metaCat || name.replace('clothing_', '');
    const clothingMap = {
      tshirt: 'shirt', torso: 'outerwear', pants: 'pants', shoes: 'shoes',
      chains: 'accessory', bags: 'bag', hat: 'headwear', glasses: 'glasses',
      earrings: 'earrings', watches: 'watch'
    };
    return clothingMap[clothingCat] || null;
  }

  if (name === 'armor' || name === 'body_armor' || name === 'bodyarmor' || name.includes('armor')) return 'bodyarmor';
  if (name.startsWith('weapon_')) return 'weapon';
  if (name.startsWith('ammo_') || name.includes('ammo')) return 'ammo';
  return equipmentByCategory[cat] || null;
}
function firstEmptyMainSlot() {
  const all = [];
  for (let i = 1; i <= 6; i++) all.push(`pocket-${i}`);
  for (let i = 1; i <= 30; i++) all.push(`backpack-${i}`);
  for (const slot of all) if (!isLockedSlot(slot) && !itemBySlot(slot)) return slot;
  return null;
}

function resourceUrl(path) {
  return `https://${GetParentResourceName()}/${path}`;
}

function post(path, body) {
  return fetch(resourceUrl(path), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body || {})
  });
}


const INVENTORY_DEBUG = false;
function debugLog(tag, payload = {}) {
  if (!INVENTORY_DEBUG) return;
  const safePayload = payload || {};
  try {
    console.log(`[CM-INVENTORY-UI][${tag}]`, JSON.parse(JSON.stringify(safePayload)));
  } catch (e) {
    console.log(`[CM-INVENTORY-UI][${tag}]`, safePayload);
  }
  try {
    fetch(resourceUrl('debugMove'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ tag, payload: safePayload })
    }).catch(() => {});
  } catch (e) {}
}

function elementDebugAt(x, y) {
  const el = document.elementFromPoint(x, y);
  const slotEl = el && el.closest ? el.closest('.slot') : null;
  return {
    x: Math.round(Number(x) || 0),
    y: Math.round(Number(y) || 0),
    elementTag: el ? String(el.tagName || '') : null,
    elementClass: el ? String(el.className || '') : null,
    elementDataSlot: el?.dataset?.slot || null,
    closestSlotClass: slotEl ? String(slotEl.className || '') : null,
    closestSlotDataSlot: slotEl?.dataset?.slot || null,
    closestSlotGroup: slotEl?.dataset?.group || null,
    externalSlotByRect: state.external?.active ? findSlotByRect(x, y, '.slot.external', 2) : null,
    externalSlotByNearest: state.external?.active ? getExternalSlotByNearest(x, y) : null,
    anySlotByRect: findSlotByRect(x, y, '.slot', 2)
  };
}

function imgSrc(item) {
  const meta = item?.metadata || {};
  let icon = meta.image || meta.icon || item?.image || item?.icon || 'placeholder.png';

  if (typeof icon === 'string') {
    icon = icon.trim();

    // FiveM NUI is more reliable with cfx-nui HTTPS URLs, especially across resources.
    const nuiMatch = icon.match(/^nui:\/\/([^\/]+)\/(.+)$/i);
    if (nuiMatch) {
      return `https://cfx-nui-${nuiMatch[1]}/${nuiMatch[2]}`;
    }

    if (icon.startsWith('https://') || icon.startsWith('http://') || icon.startsWith('data:')) {
      return icon;
    }

    // Catalog clothing images (e.g. "custom/shared_bags_5_86_19.png") live in cm-items, not cm-inventory.
    if (icon.startsWith('custom/')) {
      return `https://cfx-nui-cm-items/ui/images/clothing/${icon}`;
    }
    if (icon.startsWith('clothing/')) {
      return `https://cfx-nui-cm-items/ui/images/${icon}`;
    }
  }

  return `images/${icon}`;
}

function itemBySlot(slot) {
  return state.items.find(i => i.slot === slot);
}

function externalSlotIndex(slot) {
  if (slot === null || slot === undefined) return null;
  const raw = String(slot).trim();
  if (!raw) return null;

  // The UI always sends external-1..external-30, but this parser is intentionally
  // tolerant so older HTML/CSS or future storage modules cannot fall back into
  // normal player-slot validation and cause "Invalid slot".
  const patterns = [
    /^external[-_](\d+)$/i,
    /^externalSlot[-_](\d+)$/i,
    /^storage[-_](\d+)$/i,
    /^storageSlot[-_](\d+)$/i
  ];

  const prefix = String(state.external?.slotPrefix || '').trim();
  if (prefix) {
    const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    patterns.push(new RegExp(`^${escaped}(\\d+)$`, 'i'));
  }

  for (const pattern of patterns) {
    const m = raw.match(pattern);
    if (m) {
      const idx = Number(m[1]);
      return Number.isFinite(idx) && idx > 0 ? Math.floor(idx) : null;
    }
  }

  return null;
}

function isExternalSlot(slot) {
  return externalSlotIndex(slot) !== null;
}

function normalizeSlot(slot) {
  const idx = externalSlotIndex(slot);
  if (idx !== null) return `external-${idx}`;
  return typeof slot === 'string' ? slot.trim() : slot;
}

function externalSlotLimit() {
  return Math.max(0, Number(state.external?.slotCount || state.external?.slots || 0));
}

function externalDisplaySlots() {
  const usable = externalSlotLimit();
  const display = Number(state.external?.displaySlots || state.external?.display_slots || 30);
  return Math.max(usable, Math.min(30, Math.max(1, display || 30)));
}

function isExternalLockedSlot(slot) {
  const idx = externalSlotIndex(slot);
  return !!idx && externalSlotLimit() > 0 && idx > externalSlotLimit();
}

function externalLabel() {
  const ext = state.external || {};
  const label = String(ext.label || 'STORAGE').toUpperCase();
  const slots = Number(ext.slotCount || ext.slots || 0);
  const used = Array.isArray(ext.items) ? ext.items.length : 0;
  return `${label} • ${used}/${slots} slots`;
}

function kg(grams) {
  return ((Number(grams) || 0) / 1000).toFixed(1);
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>'"]/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#039;', '"': '&quot;'
  }[char]));
}

function compactValue(value, fallback = '') {
  const text = String(value ?? fallback).trim();
  return text || fallback;
}

function rarityOf(item) {
  const r = String(item?.rarity || item?.itemType || item?.metadata?.rarity || item?.metadata?.itemType || 'normal').toLowerCase();
  if (r === 'rare' || r === 'unique') return r;
  return 'normal';
}

function itemDurability(item) {
  const d = item?.durability ?? item?.metadata?.durability;
  if (d === null || d === undefined || d === '') return null;
  const n = Number(d);
  if (Number.isNaN(n)) return null;
  return Math.max(0, Math.min(100, Math.floor(n)));
}


function isBagItem(item) {
  const meta = item?.metadata || {};
  const name = String(item?.item_name || item?.name || '').toLowerCase();
  return item?.isBag === true || name === 'clothing_bags' || String(meta.categoryType || meta.category || '').toLowerCase() === 'bags';
}

function isClothingItem(item) {
  const name = String(item?.item_name || item?.name || '').toLowerCase();
  return item?.isClothing === true || name.startsWith('clothing_') || !!item?.metadata?.drawableId;
}

function bagLevelOf(item) {
  const meta = item?.metadata || {};
  const lvl = Number(item?.bagLevel || meta.bagLevel || meta.bag_level || meta.level || 0);
  if (!lvl) return 0;
  return Math.max(1, Math.min(4, Math.floor(lvl)));
}

function itemLabel(item) {
  const level = bagLevelOf(item);
  const current = String(item?.label || '').trim();
  if (isBagItem(item) && level && (!current || current === 'Bag' || current === 'Clothing Bag' || current === 'clothing_bags')) {
    return `Level ${level} Bag`;
  }
  return current || item?.item_name || 'ITEM';
}

function itemSubtitle(item) {
  const meta = item?.metadata || {};
  const level = bagLevelOf(item);
  if (isBagItem(item) && level) return `BAG LEVEL ${level}`;
  if (isClothingItem(item)) {
    const cat = String(meta.categoryType || meta.category || item?.category || '').toUpperCase();
    const drawable = meta.drawableId ?? meta.drawable;
    const texture = meta.textureId ?? meta.texture;
    if (cat && drawable !== undefined && drawable !== null) return `${cat} • ${drawable}/${texture ?? 0}`;
    if (cat) return cat;
  }
  return `${kg((item.weight || 0) * (item.quantity || 1))} KG`;
}

function isLockedSlot(slot) {
  if (!slot || !slot.startsWith('backpack-')) return false;
  const idx = Number(slot.replace('backpack-', ''));
  const open = Number(state.bag?.backpackSlots || 0);
  return idx > open;
}

function metadataRows(item) {
  const meta = item?.metadata || {};
  const rows = [];
  const durability = itemDurability(item);
  if (durability !== null) rows.push(['Durability', `${durability}%`]);

  const bagLevel = bagLevelOf(item);
  if (bagLevel) rows.push(['Bag Level', `Level ${bagLevel}`]);
  if (isBagItem(item) && bagLevel) {
    const cfgSlots = Number(item?.bagSlots || item?.backpackSlots || state.bag?.backpackSlots || 0);
    if (cfgSlots) rows.push(['Slots', `${cfgSlots}/30`]);
  }

  if (isClothingItem(item)) {
    const category = compactValue(meta.categoryType || meta.category || item?.category, 'Clothing');
    const drawable = meta.drawableId ?? meta.drawable;
    const texture = meta.textureId ?? meta.texture;
    rows.push(['Type', String(category).toUpperCase()]);
    if (meta.gender || meta.sex) rows.push(['Gender', String(meta.gender || meta.sex).toUpperCase()]);
    if (drawable !== undefined && drawable !== null) rows.push(['Style', `${drawable}/${texture ?? 0}`]);
  } else if (item?.category) {
    rows.push(['Category', String(item.category).toUpperCase()]);
  }

  if (meta.serial) rows.push(['Serial', meta.serial]);
  if (meta.owner || meta.registeredTo) rows.push(['Owner', meta.owner || meta.registeredTo]);
  return rows.slice(0, 6);
}

function tooltipRows(item) {
  const rows = [];
  rows.push(['Qty', item.quantity || 1]);
  rows.push(['Weight', `${kg((item.weight || 0) * (item.quantity || 1))} KG`]);

  const durability = itemDurability(item);
  if (durability !== null) rows.push(['Durability', `${durability}%`]);

  const bagLevel = bagLevelOf(item);
  if (isBagItem(item) && bagLevel) {
    rows.push(['Bag', `Level ${bagLevel}`]);
    const slots = Number(item?.bagSlots || item?.backpackSlots || state.bag?.backpackSlots || 0);
    if (slots) rows.push(['Slots', `${slots}/30`]);
    return rows.slice(0, 4);
  }

  if (isClothingItem(item)) {
    const meta = item?.metadata || {};
    const category = compactValue(meta.categoryType || meta.category || item?.category, 'Clothing');
    const drawable = meta.drawableId ?? meta.drawable;
    const texture = meta.textureId ?? meta.texture;
    rows.push(['Type', String(category).toUpperCase()]);
    if (meta.gender || meta.sex) rows.push(['Gender', String(meta.gender || meta.sex).toUpperCase()]);
    if (drawable !== undefined && drawable !== null) rows.push(['Style', `${drawable}/${texture ?? 0}`]);
    return rows.slice(0, 4);
  }

  return rows.slice(0, 3);
}

function closeContext() {
  contextEl.classList.add('hidden');
  state.contextItem = null;
  state.contextOpen = false;
}

function closeTooltip() {
  tooltipEl.classList.add('hidden');
}

function showToast(message, type = 'info') {
  toastEl.textContent = message || '';
  toastEl.className = `toast ${type || 'info'}`;
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => toastEl.classList.add('hidden'), 2500);
}

function setWeight() {
  const current = Number(state.weight?.current || 0);
  const max = Number(state.weight?.max || 82000);
  document.getElementById('weight-current').textContent = kg(current);
  document.getElementById('weight-max').textContent = `/ ${kg(max)} KG`;
  const pct = Math.max(0, Math.min(100, (current / max) * 100));
  document.getElementById('weight-fill').style.width = `${pct}%`;
}

function makeSlot(slot, group) {
  const item = itemBySlot(slot);
  const el = document.createElement('div');
  el.className = `slot ${group || ''}`;
  el.dataset.group = group || '';
  el.dataset.slot = normalizeSlot(slot);
  if (group === 'external') {
    const extIdx = externalSlotIndex(slot);
    if (extIdx !== null) {
      el.dataset.externalIndex = String(extIdx);
      el.dataset.slot = `external-${extIdx}`;
    }
  }
  if (!item) el.classList.add('empty');
  if (group === 'external' && isExternalLockedSlot(slot)) {
    el.classList.add('storage-locked');
  }
  if (isLockedSlot(slot)) {
    el.classList.add('locked');
    const lock = document.createElement('div');
    lock.className = 'lock-label';
    lock.textContent = 'LOCKED';
    el.appendChild(lock);
  }

  if (group === 'quick') {
    const hotkey = document.createElement('span');
    hotkey.className = 'hotkey';
    hotkey.textContent = slot.split('-')[1];
    el.appendChild(hotkey);
  }

  if (group === 'equipment' && !item) {
    const icon = document.createElement('div');
    icon.className = 'slot-label';
    icon.innerHTML = `${equipmentIconSvg(slot)}<br><span>${escapeHtml(equipmentLabels[slot] || slot)}</span>`;
    el.appendChild(icon);
  }

  if (group === 'external' && !item) {
    const idx = externalSlotIndex(slot);
    const icon = document.createElement('div');
    icon.className = 'slot-label external-label';
    icon.innerHTML = `<span>${idx || ''}</span>`;
    el.appendChild(icon);
  }

  if (item) el.appendChild(makeItem(item));
  return el;
}

let activeDrag = null;

function clearDropTargets() {
  document.querySelectorAll('.drop-target, .invalid-target').forEach(x => x.classList.remove('drop-target', 'invalid-target'));
  if (giveDropZone) giveDropZone.classList.remove('active');
}

function isGiveZone(x, y) {
  if (!activeDrag) return false;
  if (activeDrag.item?.external || isExternalSlot(activeDrag.fromSlot)) return false;
  return y >= window.innerHeight - Math.max(94, Math.round(window.innerHeight * 0.12));
}

function showGiveDropZone() {
  if (!giveDropZone || activeDrag?.item?.external || isExternalSlot(activeDrag?.fromSlot)) return;
  giveDropZone.classList.remove('hidden');
}

function hideGiveDropZone() {
  if (!giveDropZone) return;
  giveDropZone.classList.add('hidden');
  giveDropZone.classList.remove('active');
}

function slotFromElement(el) {
  if (!el) return null;
  const slotEl = el.closest ? el.closest('.slot') : null;
  if (!slotEl) return null;
  return normalizeSlot(slotEl.dataset.slot || '');
}

function findSlotByRect(x, y, selector, padding = 0) {
  const slots = Array.from(document.querySelectorAll(selector || '.slot'));
  for (const slotEl of slots) {
    const rect = slotEl.getBoundingClientRect();
    if (x >= rect.left - padding && x <= rect.right + padding && y >= rect.top - padding && y <= rect.bottom + padding) {
      return normalizeSlot(slotEl.dataset.slot || '');
    }
  }
  return null;
}

function getExternalSlotByNearest(x, y) {
  if (!state.external?.active) return null;

  const slots = Array.from(document.querySelectorAll('.slot.external'));
  if (!slots.length) return null;

  let best = null;
  let bestScore = Infinity;

  for (const slotEl of slots) {
    const rect = slotEl.getBoundingClientRect();
    if (!rect.width || !rect.height) continue;

    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    const dx = Math.abs(x - cx);
    const dy = Math.abs(y - cy);

    // Accept drops inside the slot and also inside the normal gap between slots.
    // This is important in FiveM NUI because transparent text/vehicle overlay can
    // make the cursor feel like it is on a slot while elementFromPoint says it is not.
    const allowX = rect.width * 0.68;
    const allowY = rect.height * 0.68;
    if (dx <= allowX && dy <= allowY) {
      const score = (dx * dx) + (dy * dy);
      if (score < bestScore) {
        bestScore = score;
        best = normalizeSlot(slotEl.dataset.slot || '');
      }
    }
  }

  if (best) return best;

  // Final fallback: if the cursor is anywhere inside the external 6x5 grid box,
  // calculate the closest cell from the grid position instead of depending on DOM hit testing.
  const grid = document.querySelector('.external-grid');
  if (!grid) return null;
  const gridRect = grid.getBoundingClientRect();
  const pad = 16;
  if (x < gridRect.left - pad || x > gridRect.right + pad || y < gridRect.top - pad || y > gridRect.bottom + pad) return null;

  const first = slots[0].getBoundingClientRect();
  const second = slots[1] ? slots[1].getBoundingClientRect() : null;
  const seventh = slots[6] ? slots[6].getBoundingClientRect() : null;
  const stepX = second ? Math.max(1, second.left - first.left) : Math.max(1, first.width);
  const stepY = seventh ? Math.max(1, seventh.top - first.top) : Math.max(1, first.height);
  const col = Math.max(0, Math.min(5, Math.floor((x - first.left + stepX / 2) / stepX)));
  const row = Math.max(0, Math.min(4, Math.floor((y - first.top + stepY / 2) / stepY)));
  const idx = row * 6 + col + 1;
  return `external-${idx}`;
}

function getSlotUnderCursor(x, y) {
  // External storage must win every time. In this mode the right board replaces
  // equipment, so a drop over that area should never be sent as bodyarmor/weapon/etc.
  if (state.external?.active) {
    const exactExternalSlot = findSlotByRect(x, y, '.slot.external', 2);
    if (exactExternalSlot) return exactExternalSlot;

    const nearestExternalSlot = getExternalSlotByNearest(x, y);
    if (nearestExternalSlot) return nearestExternalSlot;
  }

  const el = document.elementFromPoint(x, y);
  const directSlot = slotFromElement(el);
  if (directSlot) return directSlot;

  return findSlotByRect(x, y, '.slot', 2);
}

function moveGhost(x, y) {
  if (!activeDrag || !activeDrag.ghost) return;
  activeDrag.ghost.style.left = `${x - activeDrag.offsetX}px`;
  activeDrag.ghost.style.top = `${y - activeDrag.offsetY}px`;
}

function updateDropTarget(x, y) {
  clearDropTargets();
  if (!activeDrag) return;
  if (isGiveZone(x, y)) {
    if (giveDropZone) giveDropZone.classList.add('active');
    return;
  }
  const slot = getSlotUnderCursor(x, y);
  if (!slot) return;
  const slotEl = document.querySelector(`.slot[data-slot="${slot}"]`);
  if (!slotEl || slot === activeDrag.fromSlot) return;
  if (isLockedSlot(slot) || isExternalLockedSlot(slot)) slotEl.classList.add('invalid-target');
  else slotEl.classList.add('drop-target');
}

function finishDrag(x, y) {
  if (!activeDrag) return;

  const dragItem = activeDrag.item;
  const fromSlotRaw = activeDrag.fromSlot;
  const detectedSlotRaw = getSlotUnderCursor(x, y);
  const fromSlot = normalizeSlot(fromSlotRaw);
  const toSlot = normalizeSlot(detectedSlotRaw);
  const wantsGive = isGiveZone(x, y);
  const debugPayload = {
    fromSlotRaw,
    detectedSlotRaw,
    fromSlot,
    toSlot,
    fromIndex: externalSlotIndex(fromSlot),
    toIndex: externalSlotIndex(toSlot),
    externalActive: !!state.external?.active,
    external: state.external ? {
      ownerType: state.external.ownerType,
      ownerId: state.external.ownerId,
      slotPrefix: state.external.slotPrefix,
      slotCount: state.external.slotCount || state.external.slots,
      displaySlots: state.external.displaySlots || state.external.display_slots,
      label: state.external.label
    } : null,
    item: dragItem ? {
      name: dragItem.name || dragItem.item_name,
      label: dragItem.label,
      slot: dragItem.slot,
      external: !!dragItem.external
    } : null,
    element: elementDebugAt(x, y)
  };
  debugLog('finishDrag', debugPayload);

  if (activeDrag.ghost) activeDrag.ghost.remove();
  if (activeDrag.sourceEl) activeDrag.sourceEl.classList.remove('dragging-source');
  clearDropTargets();
  hideGiveDropZone();

  activeDrag = null;

  if (wantsGive && dragItem) {
    openGive(dragItem);
    return;
  }

  if (!toSlot || !fromSlot || fromSlot === toSlot) return;
  if (isLockedSlot(toSlot)) { showToast('That backpack slot is locked by your bag level.', 'error'); return; }
  if (isExternalLockedSlot(toSlot)) { showToast(`This storage only has ${externalSlotLimit()} usable slots.`, 'error'); return; }

  const fromIndex = externalSlotIndex(fromSlot);
  const toIndex = externalSlotIndex(toSlot);
  const movePayload = {
    fromSlot,
    toSlot,
    fromExternal: fromIndex !== null,
    toExternal: toIndex !== null,
    fromIndex,
    toIndex,
    uiDebug: debugPayload
  };
  debugLog('postMoveItem', movePayload);
  post('moveItem', movePayload).catch(() => {
    showToast('Move request failed.', 'error');
  });
}

function makeItem(item) {
  const el = document.createElement('div');
  el.className = `item rarity-${rarityOf(item)}${item?.external ? ' external-item' : ''}`;
  el.draggable = false;
  el.dataset.slot = item.slot;

  if ((item.quantity || 1) > 1) {
    const qty = document.createElement('div');
    qty.className = 'qty';
    qty.textContent = item.quantity;
    el.appendChild(qty);
  }

  const img = document.createElement('img');
  img.src = imgSrc(item);
  img.alt = itemLabel(item);
  img.onerror = () => { img.style.display = 'none'; };
  el.appendChild(img);

  const info = document.createElement('div');
  info.className = 'item-info';
  const label = document.createElement('div');
  label.className = 'item-name';
  label.textContent = itemLabel(item);
  const weight = document.createElement('div');
  weight.className = 'item-weight';
  weight.textContent = itemSubtitle(item);
  info.appendChild(label);
  info.appendChild(weight);
  el.appendChild(info);

  const level = bagLevelOf(item);
  if (isBagItem(item) && level) {
    const badge = document.createElement('div');
    badge.className = 'item-badge bag-badge';
    badge.textContent = `LVL ${level}`;
    el.appendChild(badge);
  } else if (isClothingItem(item)) {
    const badge = document.createElement('div');
    badge.className = 'item-badge clothing-badge';
    badge.textContent = 'FIT';
    el.appendChild(badge);
  }

  const durability = itemDurability(item);
  if (durability !== null) {
    const dur = document.createElement('div');
    dur.className = 'durability';
    dur.innerHTML = `<span style="width:${durability}%"></span>`;
    el.appendChild(dur);
  }

  el.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    closeContext();
    closeTooltip();

    const rect = el.getBoundingClientRect();
    const ghost = el.cloneNode(true);
    ghost.classList.add('drag-ghost');
    ghost.style.width = `${rect.width}px`;
    ghost.style.height = `${rect.height}px`;
    document.body.appendChild(ghost);

    activeDrag = {
      item,
      fromSlot: item.slot,
      ghost,
      sourceEl: el,
      offsetX: e.clientX - rect.left,
      offsetY: e.clientY - rect.top
    };

    showGiveDropZone();
    el.classList.add('dragging-source');
    moveGhost(e.clientX, e.clientY);
    updateDropTarget(e.clientX, e.clientY);
  });

  el.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    if (activeDrag) return;
    showContext(item, e.clientX, e.clientY);
  });

  el.addEventListener('mouseenter', (e) => {
    if (!activeDrag && !state.contextOpen) showTooltip(item, e.clientX, e.clientY);
  });
  el.addEventListener('mousemove', (e) => {
    if (!activeDrag && !state.contextOpen) positionTooltip(e.clientX, e.clientY);
  });
  el.addEventListener('mouseleave', closeTooltip);

  return el;
}

document.addEventListener('mousemove', (e) => {
  if (!activeDrag) return;
  e.preventDefault();
  moveGhost(e.clientX, e.clientY);
  updateDropTarget(e.clientX, e.clientY);
});

document.addEventListener('mouseup', (e) => {
  if (!activeDrag) return;
  e.preventDefault();
  finishDrag(e.clientX, e.clientY);
});

function showTooltip(item, x, y) {
  if (state.contextOpen || !contextEl.classList.contains('hidden')) return;
  const rows = tooltipRows(item).map(([k, v]) => `<div><b>${escapeHtml(k)}</b><span>${escapeHtml(v)}</span></div>`).join('');
  const src = escapeHtml(imgSrc(item));
  tooltipEl.innerHTML = `
    <div class="tooltip-header">
      <img class="tooltip-img" src="${src}" alt="" onerror="this.style.display='none'" />
      <div class="tooltip-title">
        <strong>${escapeHtml(itemLabel(item))}</strong>
        <p>${escapeHtml(itemSubtitle(item))}</p>
      </div>
    </div>
    <div class="tooltip-meta">${rows}</div>`;
  tooltipEl.classList.remove('hidden');
  positionTooltip(x, y);
}

function positionTooltip(x, y) {
  if (state.contextOpen || !contextEl.classList.contains('hidden')) return;
  const margin = 18;
  const rect = tooltipEl.getBoundingClientRect();
  const left = Math.min(x + 14, window.innerWidth - rect.width - margin);
  const top = Math.min(y + 14, window.innerHeight - rect.height - margin);
  tooltipEl.style.left = `${Math.max(margin, left)}px`;
  tooltipEl.style.top = `${Math.max(margin, top)}px`;
}

function showContext(item, x, y) {
  closeTooltip();
  state.contextItem = item;
  state.contextOpen = true;

  if (item?.external || isExternalSlot(item?.slot)) {
    const target = firstEmptyMainSlot();
    const details = metadataRows(item).map(([k, v]) => `<div class="detail-row"><span>${escapeHtml(k)}</span><b>${escapeHtml(v)}</b></div>`).join('');
    contextEl.innerHTML = `
      <div class="context-head rarity-${escapeHtml(rarityOf(item))}">
        <div class="context-title">${escapeHtml(itemLabel(item))}</div>
        <div class="context-meta">${escapeHtml(Number(item.quantity || 1))} UNITS / ${escapeHtml(kg((item.weight || 0) * (item.quantity || 1)))} KG<br>${escapeHtml((state.external?.label || 'STORAGE').toUpperCase())}</div>
        <div class="context-desc">${escapeHtml(item.description || itemSubtitle(item) || 'Storage item.')}</div>
        <div class="details-list">${details || '<div class="detail-row"><span>Info</span><b>Stored Item</b></div>'}</div>
      </div>
      <div class="context-actions compact">
        <button data-action="take"><span class="icon">⇦</span>TAKE TO INVENTORY</button>
      </div>
    `;
    const takeBtn = contextEl.querySelector('[data-action="take"]');
    if (takeBtn) takeBtn.onclick = () => {
      const slot = firstEmptyMainSlot();
      if (!slot) { showToast('No empty pocket/backpack slot.', 'error'); closeContext(); return; }
      post('moveItem', {
        fromSlot: item.slot,
        toSlot: slot,
        fromExternal: true,
        toExternal: false,
        fromIndex: externalSlotIndex(item.slot),
        toIndex: null
      });
      closeContext();
    };
    contextEl.classList.remove('hidden');
    const rectW = 430;
    const rectH = 390;
    contextEl.style.left = `${Math.min(x, window.innerWidth - rectW - 20)}px`;
    contextEl.style.top = `${Math.min(y, window.innerHeight - rectH - 20)}px`;
    return;
  }

  const totalWeight = kg((item.weight || 0) * (item.quantity || 1));
  const rarity = rarityOf(item);
  const details = metadataRows(item).map(([k, v]) => `<div class="detail-row"><span>${escapeHtml(k)}</span><b>${escapeHtml(v)}</b></div>`).join('');
  const category = String(item.category || 'misc').toUpperCase();
  const qty = Number(item.quantity || 1);
  const splitButton = qty > 1 ? '<button data-action="split"><span class="icon">↔</span>DIVIDE</button>' : '';
  contextEl.innerHTML = `
    <div class="context-head rarity-${escapeHtml(rarity)}">
      <div class="context-title">${escapeHtml(itemLabel(item))}</div>
      <div class="context-meta">${escapeHtml(qty)} UNITS / ${escapeHtml(totalWeight)} KG<br>${escapeHtml(rarity.toUpperCase())} • ${escapeHtml(category)}</div>
      <div class="context-desc">${escapeHtml(item.description || itemSubtitle(item) || 'No item description available.')}</div>
      <div class="details-list">${details || '<div class="detail-row"><span>Info</span><b>Standard Item</b></div>'}</div>
    </div>
    <div class="context-actions compact">
      <button data-action="use"><span class="icon">↩</span>USE</button>
      ${splitButton}
      <button data-action="give"><span class="icon">⇢</span>GIVE</button>
      <button data-action="drop"><span class="icon">⌄</span>DROP</button>
    </div>
  `;
  contextEl.querySelector('[data-action="use"]').onclick = () => { post('useItem', { slot: item.slot }); closeContext(); };
  contextEl.querySelector('[data-action="give"]').onclick = () => openGive(item);
  contextEl.querySelector('[data-action="drop"]').onclick = () => openDrop(item);
  const split = contextEl.querySelector('[data-action="split"]');
  if (split) split.onclick = () => openSplit(item);

  contextEl.classList.remove('hidden');
  const rectW = 430;
  const rectH = 390;
  contextEl.style.left = `${Math.min(x, window.innerWidth - rectW - 20)}px`;
  contextEl.style.top = `${Math.min(y, window.innerHeight - rectH - 20)}px`;
}

function openSplit(item) {
  if ((item.quantity || 1) <= 1) {
    showToast('This item cannot be divided.', 'error');
    return;
  }
  state.splitSource = item;
  state.splitTarget = findEmptySlot();
  if (!state.splitTarget) {
    showToast('No empty slot to split into.', 'error');
    return;
  }
  splitLabel.textContent = `${item.label || item.item_name} → ${state.splitTarget}`;
  splitAmount.max = Math.max(1, (item.quantity || 1) - 1);
  splitAmount.value = 1;
  splitModal.classList.remove('hidden');
  closeContext();
}

function openGive(item) {
  state.giveSource = item;
  giveLabel.textContent = `${item.label || item.item_name} • give to nearest player`;
  giveAmount.max = Math.max(1, item.quantity || 1);
  giveAmount.value = 1;
  giveModal.classList.remove('hidden');
  closeContext();
}

function openDrop(item) {
  state.dropSource = item;
  dropLabel.textContent = `${itemLabel(item)} • choose amount to drop`;
  dropAmount.max = Math.max(1, item.quantity || 1);
  dropAmount.value = 1;
  dropModal.classList.remove('hidden');
  closeContext();
}

function findEmptySlot() {
  const all = [];
  for (let i = 1; i <= 6; i++) all.push(`pocket-${i}`);
  for (let i = 1; i <= 30; i++) all.push(`backpack-${i}`);
  for (const slot of all) if (!isLockedSlot(slot) && !itemBySlot(slot)) return slot;
  return null;
}

function updateBackpackHint() {
  const section = document.querySelector('.backpack-section');
  if (!section) return;
  let hint = document.getElementById('backpack-unlock-hint');
  if (!hint) {
    hint = document.createElement('div');
    hint.id = 'backpack-unlock-hint';
    hint.className = 'bag-unlock-hint hidden';
    const title = document.getElementById('backpack-title');
    if (title && title.parentNode === section) title.insertAdjacentElement('afterend', hint);
    else section.insertBefore(hint, section.firstChild);
  }

  const lvl = Number(state.bag?.level || 0);
  const openSlots = Number(state.bag?.backpackSlots || 0);
  let text = '';
  if (openSlots <= 0 || lvl <= 0) text = 'Get backpack from 24/7 to unlock slots.';
  else if (lvl === 1) text = 'Get Level 2 backpack to unlock more slots.';
  else if (lvl === 2) text = 'Get Level 3 backpack to unlock more slots.';

  if (text) {
    hint.textContent = text;
    hint.classList.remove('hidden');
  } else {
    hint.textContent = '';
    hint.classList.add('hidden');
  }
}

function render() {
  setWeight();
  const bagLabel = document.getElementById('bag-level-label');
  if (bagLabel) {
    const lvl = Number(state.bag?.level || 0);
    const maxWeight = kg(state.bag?.maxWeight || state.weight?.max || 0);
    bagLabel.textContent = `${state.bag?.label || 'No Bag'} • Level ${lvl} • ${state.bag?.backpackSlots || 0}/30 slots • ${maxWeight} KG`;
  }
  updateBackpackHint();
  quickEl.innerHTML = '';
  pocketEl.innerHTML = '';
  backpackEl.innerHTML = '';
  gearEl.innerHTML = '';

  for (let i = 1; i <= 5; i++) quickEl.appendChild(makeSlot(`quickaccess-${i}`, 'quick'));
  for (let i = 1; i <= 6; i++) pocketEl.appendChild(makeSlot(`pocket-${i}`, 'pocket'));
  for (let i = 1; i <= 30; i++) backpackEl.appendChild(makeSlot(`backpack-${i}`, 'backpack'));

  const titleRow = document.querySelector('.equipment-column .section-title-row h3');
  const characterWrap = document.querySelector('.equipment-column .character-wrap');

  if (state.external?.active) {
    const slots = externalDisplaySlots();
    if (titleRow) titleRow.innerHTML = `${escapeHtml(externalLabel())} <span>ANY ITEM STORAGE • 6×5 BOARD</span>`;
    if (characterWrap) characterWrap.classList.add('external-wrap');
    gearEl.classList.add('external-grid');
    gearEl.classList.remove('gear-grid');
    for (let i = 1; i <= slots; i++) gearEl.appendChild(makeSlot(`external-${i}`, 'external'));
  } else {
    if (titleRow) titleRow.innerHTML = 'EQUIPMENT <span>WEAR / DRAG HERE</span>';
    if (characterWrap) characterWrap.classList.remove('external-wrap');
    gearEl.classList.remove('external-grid');
    gearEl.classList.add('gear-grid');
    const gear = ['mask', 'glasses', 'headwear', 'earrings', 'outerwear', 'shirt', 'bodyarmor', 'bag', 'accessory', 'weapon', 'ammo', 'watch', 'pants', 'shoes'];
    gear.forEach(slot => gearEl.appendChild(makeSlot(slot, 'equipment')));
  }
}

function applyInventoryPayload(payload) {
  const playerItems = Array.isArray(payload.items) ? payload.items : [];
  state.external = payload.external && payload.external.active ? payload.external : null;
  const externalItems = state.external && Array.isArray(state.external.items) ? state.external.items.map(item => ({ ...item, external: true })) : [];
  state.items = [...playerItems, ...externalItems];
  state.weight = payload.weight || { current: 0, max: 25000 };
  state.bag = payload.bag || { level: 0, backpackSlots: 0, maxWeight: state.weight.max || 25000 };
  state.slots = payload.slots || null;
  render();
}

function openInventory(payload) {
  state.open = true;
  if (dropPickupPanel) dropPickupPanel.classList.add('hidden');

  // Build all slots/items before the NUI becomes visible.
  // This avoids the short empty/black flash when the inventory opens.
  applyInventoryPayload(payload || {});

  requestAnimationFrame(() => {
    root.classList.remove('hidden');
  });
}

function updateInventory(payload) {
  if (!state.open) return;
  applyInventoryPayload(payload || {});
}


function showNearbyDrops(payload) {
  if (!dropPickupPanel || !dropPickupList) return;
  const visible = payload?.visible === true && Array.isArray(payload.drops) && payload.drops.length > 0 && !state.open;
  if (!visible) {
    dropPickupPanel.classList.add('hidden');
    dropPickupList.innerHTML = '';
    return;
  }

  const drops = payload.drops.slice(0, 6);
  dropPickupList.innerHTML = drops.map((drop, index) => {
    const selected = drop.selected === true || Number(payload.selected || 1) === index + 1;
    const qty = Math.max(1, Number(drop.quantity || 1));
    const image = escapeHtml(drop.image || 'images/placeholder.png');
    const label = escapeHtml(drop.label || 'Item');
    return `
      <div class="drop-pickup-row${selected ? ' selected' : ''}">
        <div class="drop-pickup-img"><img src="${image}" onerror="this.style.display='none'" /></div>
        <div class="drop-pickup-text"><strong>${label}</strong><span>${qty}x</span></div>
      </div>`;
  }).join('');

  const help = dropPickupPanel.querySelector('.drop-pickup-help');
  if (help) {
    help.innerHTML = drops.length > 1
      ? '<b>E</b> Pick selected <span>•</span> <b>↑/↓</b> Select'
      : '<b>E</b> Pick up';
  }
  dropPickupPanel.classList.remove('hidden');
}

function closeInventory() {
  state.open = false;
  state.external = null;
  root.classList.add('hidden');
  closeContext();
  closeTooltip();
  splitModal.classList.add('hidden');
  if (giveModal) giveModal.classList.add('hidden');
  if (dropModal) dropModal.classList.add('hidden');
  hideGiveDropZone();
  if (progressOverlay) progressOverlay.classList.add('hidden');
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') openInventory(data);
  if (data.action === 'update') updateInventory(data);
  if (data.action === 'close') closeInventory();
  if (data.action === 'notify') showToast(data.message, data.type || 'info');
  if (data.action === 'progress') showProgress(data.label || 'Using item...', Number(data.ms) || 1000);
  if (data.action === 'nearDrops') showNearbyDrops(data);
});

function showProgress(label, ms) {
  progressLabel.textContent = label;
  progressFill.style.transition = 'none';
  progressFill.style.width = '0%';
  progressOverlay.classList.remove('hidden');
  requestAnimationFrame(() => {
    progressFill.style.transition = `width ${ms}ms linear`;
    progressFill.style.width = '100%';
  });
  clearTimeout(showProgress.timer);
  showProgress.timer = setTimeout(() => progressOverlay.classList.add('hidden'), ms + 150);
}


document.addEventListener('click', (e) => {
  if (!contextEl.contains(e.target)) closeContext();
});

document.addEventListener('keydown', (e) => {
  const key = String(e.key || '').toLowerCase();
  if (key === 'escape' || key === 'i') post('close', {});
});


function readModalAmount(inputEl) {
  const max = Math.max(1, Number(inputEl?.max || 1) || 1);
  let amount = Math.floor(Number(inputEl?.value || 1) || 1);
  if (amount < 1) amount = 1;
  if (amount > max) amount = max;
  if (inputEl) inputEl.value = amount;
  return amount;
}

document.getElementById('close-btn').onclick = () => post('close', {});
document.getElementById('split-cancel').onclick = () => splitModal.classList.add('hidden');
document.getElementById('split-confirm').onclick = () => {
  if (!state.splitSource || !state.splitTarget) return;
  post('splitItem', {
    fromSlot: state.splitSource.slot,
    toSlot: state.splitTarget,
    amount: readModalAmount(splitAmount)
  });
  splitModal.classList.add('hidden');
};

document.getElementById('give-cancel').onclick = () => giveModal.classList.add('hidden');
document.getElementById('give-confirm').onclick = () => {
  if (!state.giveSource) return;
  post('giveItem', {
    slot: state.giveSource.slot,
    amount: readModalAmount(giveAmount)
  });
  giveModal.classList.add('hidden');
};


document.getElementById('drop-cancel').onclick = () => dropModal.classList.add('hidden');
document.getElementById('drop-confirm').onclick = () => {
  if (!state.dropSource) return;
  post('dropItem', {
    slot: state.dropSource.slot,
    amount: readModalAmount(dropAmount)
  });
  dropModal.classList.add('hidden');
};
