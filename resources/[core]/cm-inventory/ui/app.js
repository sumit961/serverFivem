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

let state = {
  open: false,
  items: [],
  slots: null,
  weight: { current: 0, max: 82000 },
  dragged: null,
  contextItem: null,
  splitSource: null,
  splitTarget: null,
  giveSource: null,
  dropSource: null,
  bag: { level: 0, backpackSlots: 0, maxWeight: 25000 }
};

const equipmentLabels = {
  mask: 'Mask', glasses: 'Glasses', headwear: 'Headwear', earrings: 'Earrings',
  outerwear: 'Outerwear', shirt: 'Shirt', bodyarmor: 'Body Armor', bag: 'Bag', accessory: 'Accessories',
  weapon: 'Weapon', ammo: 'Ammo', watch: 'Watch', pants: 'Pants', shoes: 'Shoes'
};

const equipmentIcons = {
  mask: '🎭', glasses: '👓', headwear: '👒', earrings: '💎', outerwear: '🧥',
  shirt: '👕', bodyarmor: '🛡', bag: '🎒', accessory: '🎀', weapon: '🔫', ammo: '➤', watch: '⌚', pants: '👖', shoes: '👟'
};


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

function imgSrc(item) {
  const meta = item?.metadata || {};
  const icon = meta.image || meta.icon || item?.image || item?.icon || 'placeholder.png';

  if (typeof icon === 'string' && (
    icon.startsWith('nui://') ||
    icon.startsWith('https://') ||
    icon.startsWith('http://') ||
    icon.startsWith('data:')
  )) {
    return icon;
  }

  return `images/${icon}`;
}

function itemBySlot(slot) {
  return state.items.find(i => i.slot === slot);
}

function kg(grams) {
  return ((Number(grams) || 0) / 1000).toFixed(1);
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
  if (meta.serial) rows.push(['Serial', meta.serial]);
  if (meta.bagLevel) rows.push(['Bag Level', meta.bagLevel]);
  if (meta.createdAt) rows.push(['Created', String(meta.createdAt).replace('T', ' ').replace('Z', '')]);
  if (meta.owner || meta.registeredTo) rows.push(['Owner', meta.owner || meta.registeredTo]);
  Object.entries(meta).forEach(([k, v]) => {
    if (['durability','serial','bagLevel','createdAt','owner','registeredTo','rarity','itemType','label','description'].includes(k)) return;
    if (typeof v === 'object') return;
    rows.push([k, String(v)]);
  });
  return rows;
}

function closeContext() {
  contextEl.classList.add('hidden');
  state.contextItem = null;
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
  el.dataset.slot = slot;
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
    icon.innerHTML = `${equipmentIcons[slot] || '◇'}<br>${equipmentLabels[slot] || slot}`;
    el.appendChild(icon);
  }

  if (item) el.appendChild(makeItem(item));
  return el;
}

let activeDrag = null;

function clearDropTargets() {
  document.querySelectorAll('.drop-target').forEach(x => x.classList.remove('drop-target'));
}

function getSlotUnderCursor(x, y) {
  const el = document.elementFromPoint(x, y);
  if (!el) return null;
  const slotEl = el.closest('.slot');
  return slotEl ? slotEl.dataset.slot : null;
}

function moveGhost(x, y) {
  if (!activeDrag || !activeDrag.ghost) return;
  activeDrag.ghost.style.left = `${x - activeDrag.offsetX}px`;
  activeDrag.ghost.style.top = `${y - activeDrag.offsetY}px`;
}

function updateDropTarget(x, y) {
  clearDropTargets();
  const slot = getSlotUnderCursor(x, y);
  if (!slot || !activeDrag) return;
  const slotEl = document.querySelector(`.slot[data-slot="${slot}"]`);
  if (!slotEl || slot === activeDrag.fromSlot) return;
  if (isLockedSlot(slot)) slotEl.classList.add('invalid-target');
  else slotEl.classList.add('drop-target');
}

function finishDrag(x, y) {
  if (!activeDrag) return;

  const fromSlot = activeDrag.fromSlot;
  const toSlot = getSlotUnderCursor(x, y);

  if (activeDrag.ghost) activeDrag.ghost.remove();
  if (activeDrag.sourceEl) activeDrag.sourceEl.classList.remove('dragging-source');
  clearDropTargets();

  activeDrag = null;

  if (!toSlot || !fromSlot || fromSlot === toSlot) return;
  if (isLockedSlot(toSlot)) { showToast('That backpack slot is locked by your bag level.', 'error'); return; }

  showToast(`Moving ${fromSlot} → ${toSlot}...`, 'info');
  post('moveItem', { fromSlot, toSlot }).catch(() => {
    showToast('Move request failed.', 'error');
  });
}

function makeItem(item) {
  const el = document.createElement('div');
  el.className = `item rarity-${rarityOf(item)}`;
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
  img.alt = item.label || item.item_name;
  img.onerror = () => { img.style.display = 'none'; };
  el.appendChild(img);

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
    if (!activeDrag) showTooltip(item, e.clientX, e.clientY);
  });
  el.addEventListener('mousemove', (e) => {
    if (!activeDrag) positionTooltip(e.clientX, e.clientY);
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
  const totalWeight = kg((item.weight || 0) * (item.quantity || 1));
  const rows = metadataRows(item).slice(0, 5).map(([k, v]) => `<div><b>${k}</b><span>${v}</span></div>`).join('');
  tooltipEl.innerHTML = `
    <strong>${item.label || item.item_name}</strong>
    <p>${item.description || 'No description.'}</p>
    <div class="tooltip-meta">
      <div><b>Type</b><span>${rarityOf(item).toUpperCase()}</span></div>
      <div><b>Weight</b><span>${totalWeight} KG</span></div>
      ${rows}
    </div>`;
  tooltipEl.classList.remove('hidden');
  positionTooltip(x, y);
}

function positionTooltip(x, y) {
  tooltipEl.style.left = `${x + 14}px`;
  tooltipEl.style.top = `${y + 14}px`;
}

function showContext(item, x, y) {
  state.contextItem = item;
  const totalWeight = kg((item.weight || 0) * (item.quantity || 1));
  const rarity = rarityOf(item);
  const details = metadataRows(item).map(([k, v]) => `<div class="detail-row"><span>${k}</span><b>${v}</b></div>`).join('');
  contextEl.innerHTML = `
    <div class="context-head rarity-${rarity}">
      <div class="context-title">${item.label || item.item_name}</div>
      <div class="context-meta">${item.quantity || 1} UNITS / ${totalWeight} KG<br>${rarity.toUpperCase()} • ${String(item.category || 'misc').toUpperCase()}</div>
      <div class="context-desc">${item.description || 'No item description available.'}</div>
      <div class="details-list">${details || '<div class="detail-row"><span>Metadata</span><b>None</b></div>'}</div>
    </div>
    <div class="context-actions">
      <button data-action="use"><span class="icon">↩</span>USE</button>
      <button data-action="split"><span class="icon">↔</span>DIVIDE</button>
      <button data-action="give"><span class="icon">⇢</span>GIVE</button>
      <button data-action="drop"><span class="icon">⌄</span>DROP</button>
      <button data-action="dropall"><span class="icon">⇩</span>DROP ALL</button>
    </div>
  `;
  contextEl.querySelector('[data-action="use"]').onclick = () => { post('useItem', { slot: item.slot }); closeContext(); };
  contextEl.querySelector('[data-action="drop"]').onclick = () => openDrop(item);
  contextEl.querySelector('[data-action="dropall"]').onclick = () => { post('dropItem', { slot: item.slot, amount: item.quantity || 1 }); closeContext(); };
  contextEl.querySelector('[data-action="split"]').onclick = () => openSplit(item);
  contextEl.querySelector('[data-action="give"]').onclick = () => openGive(item);

  contextEl.classList.remove('hidden');
  const rectW = 420;
  const rectH = 420;
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
  dropLabel.textContent = `${item.label || item.item_name} • choose amount to drop`;
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

function render() {
  setWeight();
  const bagLabel = document.getElementById('bag-level-label');
  if (bagLabel) bagLabel.textContent = `${state.bag?.label || 'No Bag'} • ${state.bag?.backpackSlots || 0}/${30} slots`;
  quickEl.innerHTML = '';
  pocketEl.innerHTML = '';
  backpackEl.innerHTML = '';
  gearEl.innerHTML = '';

  for (let i = 1; i <= 5; i++) quickEl.appendChild(makeSlot(`quickaccess-${i}`, 'quick'));
  for (let i = 1; i <= 6; i++) pocketEl.appendChild(makeSlot(`pocket-${i}`, 'pocket'));
  for (let i = 1; i <= 30; i++) backpackEl.appendChild(makeSlot(`backpack-${i}`, 'backpack'));

  const gear = ['mask', 'glasses', 'headwear', 'earrings', 'outerwear', 'shirt', 'bodyarmor', 'bag', 'accessory', 'weapon', 'ammo', 'watch', 'pants', 'shoes'];
  gear.forEach(slot => gearEl.appendChild(makeSlot(slot, 'equipment')));
}

function applyInventoryPayload(payload) {
  state.items = Array.isArray(payload.items) ? payload.items : [];
  state.weight = payload.weight || { current: 0, max: 25000 };
  state.bag = payload.bag || { level: 0, backpackSlots: 0, maxWeight: state.weight.max || 25000 };
  state.slots = payload.slots || null;
  render();
}

function openInventory(payload) {
  state.open = true;
  root.classList.remove('hidden');
  applyInventoryPayload(payload || {});
}

function updateInventory(payload) {
  if (!state.open) return;
  applyInventoryPayload(payload || {});
}

function closeInventory() {
  state.open = false;
  root.classList.add('hidden');
  closeContext();
  closeTooltip();
  splitModal.classList.add('hidden');
  if (giveModal) giveModal.classList.add('hidden');
  if (dropModal) dropModal.classList.add('hidden');
  if (progressOverlay) progressOverlay.classList.add('hidden');
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') openInventory(data);
  if (data.action === 'update') updateInventory(data);
  if (data.action === 'close') closeInventory();
  if (data.action === 'notify') showToast(data.message, data.type || 'info');
  if (data.action === 'progress') showProgress(data.label || 'Using item...', Number(data.ms) || 1000);
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

document.getElementById('close-btn').onclick = () => post('close', {});
document.getElementById('split-cancel').onclick = () => splitModal.classList.add('hidden');
document.getElementById('split-confirm').onclick = () => {
  if (!state.splitSource || !state.splitTarget) return;
  post('splitItem', {
    fromSlot: state.splitSource.slot,
    toSlot: state.splitTarget,
    amount: Number(splitAmount.value) || 1
  });
  splitModal.classList.add('hidden');
};

document.getElementById('give-cancel').onclick = () => giveModal.classList.add('hidden');
document.getElementById('give-confirm').onclick = () => {
  if (!state.giveSource) return;
  post('giveItem', {
    slot: state.giveSource.slot,
    amount: Number(giveAmount.value) || 1
  });
  giveModal.classList.add('hidden');
};


document.getElementById('drop-cancel').onclick = () => dropModal.classList.add('hidden');
document.getElementById('drop-confirm').onclick = () => {
  if (!state.dropSource) return;
  post('dropItem', {
    slot: state.dropSource.slot,
    amount: Number(dropAmount.value) || 1
  });
  dropModal.classList.add('hidden');
};
