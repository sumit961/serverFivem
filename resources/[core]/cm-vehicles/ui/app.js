let vehicle = null;
let trunk = null;
let featuresOpen = false;
let infoOpen = false;
let activeDrag = null;
let pendingMove = null;
const $ = (id) => document.getElementById(id);

const actions = [
  { id: 1, key: 'repair', icon: '🔧', title: 'Transportation', sub: 'repair', x: 0, y: -198 },
  { id: 2, key: 'refuel', icon: '⛽', title: 'Refuel the', sub: 'vehicle', x: -148, y: -105 },
  { id: 3, key: 'info', icon: 'ℹ️', title: 'View transport', sub: 'information', x: 148, y: -105 },
  { id: 4, key: 'trunk', icon: '🚗', title: 'Open / Close', sub: 'the trunk', x: -205, y: 33 },
  { id: 5, key: 'enterTrunk', icon: '🚙', title: 'Get in the', sub: 'trunk', x: 0, y: 33 },
  { id: 6, key: 'features', icon: '🛞', title: 'Transportation', sub: 'Features', x: 205, y: 33 },
  { id: 7, key: 'passengers', icon: '👥', title: 'Passengers', sub: '', x: -148, y: 170 },
  { id: 8, key: 'charge', icon: '⚡', title: 'Charge transport', sub: '', x: 148, y: 170 },
  { id: 9, key: 'getOutTrunk', icon: '🚗', title: 'Get the player', sub: 'out of the trunk', x: 0, y: 307 }
];

function post(name, data = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data)
  }).catch(() => {});
}

function showToast(message, type = 'info') {
  const t = $('toast');
  t.textContent = message || '';
  t.className = `toast ${type || 'info'}`;
  t.classList.remove('hidden');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => t.classList.add('hidden'), 2500);
}

function kg(grams) { return ((Number(grams) || 0) / 1000).toFixed(1); }
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
function imgSrc(item) {
  const icon = item?.image || item?.icon || 'placeholder.png';
  return `nui://cm-inventory/ui/images/${icon}`;
}

function closeAll() {
  $('vehicleMenu').classList.add('hidden');
  $('trunkInventory').classList.add('hidden');
  $('featuresPanel').classList.add('hidden');
  $('infoPanel').classList.add('hidden');
  $('tooltip').classList.add('hidden');
  $('amountModal').classList.add('hidden');
  featuresOpen = false;
  infoOpen = false;
  activeDrag = null;
  pendingMove = null;
  post('close');
}

document.querySelectorAll('[data-close]').forEach(btn => btn.addEventListener('click', closeAll));
$('trunkClose').addEventListener('click', closeAll);
document.addEventListener('keydown', (e) => {
  const key = String(e.key || '').toLowerCase();
  if (key === 'escape' || key === 'i') closeAll();
});

document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-action]');
  if (!btn) return;
  const action = btn.dataset.action;
  if (btn.classList.contains('disabled')) {
    const reason = disabledReason(action);
    if (reason) showToast(reason, 'error');
    return;
  }
  runAction(action);
});

function ctx() { return vehicle?.context || {}; }
function hasAccess() { return vehicle?.access === true; }
function isLocked() { return vehicle?.locked === true || vehicle?.locked === 1; }

function actionDisabled(key) {
  const c = ctx();
  const inVehicle = c.inVehicle === true;
  const isDriver = c.isDriver === true;
  const locked = isLocked();
  const trunkSlots = Number(vehicle?.trunkSlots || 0);

  if (key === 'info') return false;
  if (key === 'features') return !hasAccess();
  if (key === 'trunk') return inVehicle || !hasAccess() || locked || trunkSlots <= 0;
  if (key === 'enterTrunk') return inVehicle || locked || trunkSlots <= 0;
  if (key === 'repair' || key === 'refuel' || key === 'charge' || key === 'getOutTrunk') return inVehicle;
  if (key === 'passengers') return !inVehicle;
  if (key === 'engine') return !hasAccess() || !isDriver;
  if (key === 'lock' || key === 'key') return !hasAccess();
  return false;
}

function disabledReason(key) {
  const c = ctx();
  const inVehicle = c.inVehicle === true;
  const locked = isLocked();
  const trunkSlots = Number(vehicle?.trunkSlots || 0);
  if (key === 'features' && !hasAccess()) return 'No key';
  if ((key === 'trunk' || key === 'enterTrunk') && inVehicle) return 'Exit vehicle first';
  if ((key === 'trunk' || key === 'enterTrunk') && locked) return 'Unlock vehicle first with L';
  if ((key === 'trunk' || key === 'enterTrunk') && trunkSlots <= 0) return 'No trunk';
  if ((key === 'repair' || key === 'refuel' || key === 'charge' || key === 'getOutTrunk') && inVehicle) return 'Outside only';
  if (key === 'passengers' && !inVehicle) return 'Inside only';
  return '';
}

function runAction(action) {
  if (actionDisabled(action)) {
    const reason = disabledReason(action);
    if (reason) showToast(reason, 'error');
    return;
  }
  if (action === 'info') {
    infoOpen = !infoOpen;
    $('infoPanel').classList.toggle('hidden', !infoOpen);
    return;
  }
  if (action === 'features') {
    featuresOpen = !featuresOpen;
    $('featuresPanel').classList.toggle('hidden', !featuresOpen);
    return;
  }
  if (['repair','refuel','charge','passengers','getOutTrunk'].includes(action)) {
    post('vehicleAction', { action, plate: vehicle?.plate });
    showToast('This RP option is coming soon.');
    return;
  }
  const target = $('targetId')?.value;
  post('vehicleAction', { action, plate: vehicle?.plate, target });
  if (action === 'trunk') { showToast('Trunk toggled. If open, press I near the trunk.'); return; }
  if (['lock','engine','key'].includes(action)) { showToast('Request sent.'); return; }
  closeAll();
}

function renderRadial() {
  const wrap = $('radialActions');
  wrap.innerHTML = '';
  actions.forEach(a => {
    const div = document.createElement('button');
    const disabled = actionDisabled(a.key);
    div.className = `radial-action ${disabled ? 'disabled' : ''}`;
    div.dataset.action = a.key;
    div.style.setProperty('--x', `${a.x}px`);
    div.style.setProperty('--y', `${a.y}px`);
    const reason = disabled ? `<em>${disabledReason(a.key)}</em>` : '';
    div.innerHTML = `<span class="num">${a.id}</span><span class="r-icon">${a.icon}</span><b>${a.title}</b><small>${a.sub}</small>${reason}`;
    wrap.appendChild(div);
  });
}

function openMenu(data) {
  vehicle = data.vehicle || data || {};
  const c = ctx();
  $('vehicleTitle').textContent = vehicle.label || vehicle.model || 'Vehicle';
  $('vehiclePlate').textContent = 'Plate hidden · number plate coming later';
  $('vehAccess').textContent = vehicle.access ? (vehicle.owner ? 'Owner' : 'Temporary key') : 'No key';
  $('infoAccess').textContent = $('vehAccess').textContent;
  $('vehTrunk').textContent = `${vehicle.trunkSlots || 0} trunk slots`;
  $('infoTrunk').textContent = `${vehicle.trunkSlots || 0} slots`;
  $('vehLock').textContent = isLocked() ? 'Locked' : 'Unlocked';
  $('vehFuel').textContent = `${vehicle.fuel ?? 100}%`;
  const body = Number(vehicle.bodyHealth || 1000);
  $('vehBody').textContent = `${Math.max(0, Math.min(100, Math.round(body / 10)))}%`;
  $('vehContext').textContent = c.inVehicle ? (c.isDriver ? 'Inside vehicle · driver seat' : 'Inside vehicle · passenger seat') : 'Outside vehicle · looking at vehicle';
  featuresOpen = false; infoOpen = false;
  $('featuresPanel').classList.add('hidden');
  $('infoPanel').classList.add('hidden');
  $('trunkInventory').classList.add('hidden');
  renderRadial();
  $('vehicleMenu').classList.remove('hidden');
}

function itemBySlot(list, slot) { return (list || []).find(i => i.slot === slot); }
function isBackpackLocked(slot) {
  if (!slot || !slot.startsWith('backpack-')) return false;
  const idx = Number(slot.replace('backpack-', ''));
  const open = Number(trunk?.player?.bag?.backpackSlots || 0);
  return idx > open;
}
function allPlayerItems() { return trunk?.player?.items || []; }
function allTrunkItems() { return trunk?.trunk?.items || []; }
function makeSlot(side, slot, group) {
  const el = document.createElement('div');
  el.className = `slot ${group || ''}`;
  el.dataset.side = side;
  el.dataset.slot = slot;
  const item = side === 'player' ? itemBySlot(allPlayerItems(), slot) : itemBySlot(allTrunkItems(), slot);
  if (side === 'player' && isBackpackLocked(slot)) {
    el.classList.add('locked');
    const lock = document.createElement('div');
    lock.className = 'lock-label'; lock.textContent = 'LOCKED';
    el.appendChild(lock);
  }
  if (group === 'quick') {
    const hotkey = document.createElement('span');
    hotkey.className = 'hotkey'; hotkey.textContent = slot.split('-')[1];
    el.appendChild(hotkey);
  }
  if (item) el.appendChild(makeItem(item, side));
  return el;
}
function makeItem(item, side) {
  const el = document.createElement('div');
  el.className = `item rarity-${rarityOf(item)}`;
  el.dataset.side = side;
  el.dataset.slot = item.slot;
  const qty = Number(item.quantity || 1);
  if (qty > 1) {
    const q = document.createElement('div'); q.className = 'qty'; q.textContent = qty; el.appendChild(q);
  }
  const img = document.createElement('img');
  img.src = imgSrc(item);
  img.alt = item.label || item.item_name;
  img.onerror = () => { img.style.display = 'none'; };
  el.appendChild(img);
  const d = itemDurability(item);
  if (d !== null) {
    const dur = document.createElement('div'); dur.className = 'durability'; dur.innerHTML = `<span style="width:${d}%"></span>`; el.appendChild(dur);
  }
  el.addEventListener('mousedown', (e) => startDrag(e, item, side, el));
  // Click does not auto-transfer. Drag the item to the exact target slot.
  el.addEventListener('mouseenter', (e) => showTooltip(item, e.clientX, e.clientY));
  el.addEventListener('mousemove', (e) => positionTooltip(e.clientX, e.clientY));
  el.addEventListener('mouseleave', () => $('tooltip').classList.add('hidden'));
  return el;
}
function startDrag(e, item, side, el) {
  if (e.button !== 0) return;
  e.preventDefault(); e.stopPropagation();
  const rect = el.getBoundingClientRect();
  const ghost = el.cloneNode(true);
  ghost.classList.add('drag-ghost');
  ghost.style.width = `${rect.width}px`; ghost.style.height = `${rect.height}px`;
  document.body.appendChild(ghost);
  activeDrag = { item, side, fromSlot: item.slot, ghost, sourceEl: el, offsetX: e.clientX - rect.left, offsetY: e.clientY - rect.top };
  el.classList.add('dragging-source');
  moveGhost(e.clientX, e.clientY);
}
function getSlotUnderCursor(x, y) {
  const el = document.elementFromPoint(x, y);
  const slotEl = el && el.closest('.slot');
  return slotEl ? { side: slotEl.dataset.side, slot: slotEl.dataset.slot, el: slotEl } : null;
}
function moveGhost(x, y) {
  if (!activeDrag?.ghost) return;
  activeDrag.ghost.style.left = `${x - activeDrag.offsetX}px`;
  activeDrag.ghost.style.top = `${y - activeDrag.offsetY}px`;
}
function clearDropTargets() { document.querySelectorAll('.drop-target,.invalid-target').forEach(x => x.classList.remove('drop-target','invalid-target')); }
function updateDropTarget(x, y) {
  clearDropTargets();
  const target = getSlotUnderCursor(x, y);
  if (!target || !activeDrag || target.side === activeDrag.side) return;
  if (target.side === 'player' && isBackpackLocked(target.slot)) target.el.classList.add('invalid-target');
  else target.el.classList.add('drop-target');
}
document.addEventListener('mousemove', (e) => { if (!activeDrag) return; e.preventDefault(); moveGhost(e.clientX, e.clientY); updateDropTarget(e.clientX, e.clientY); });
document.addEventListener('mouseup', (e) => {
  if (!activeDrag) return;
  e.preventDefault();
  const target = getSlotUnderCursor(e.clientX, e.clientY);
  const drag = activeDrag;
  if (drag.ghost) drag.ghost.remove();
  if (drag.sourceEl) drag.sourceEl.classList.remove('dragging-source');
  activeDrag = null; clearDropTargets();
  if (!target || target.side === drag.side) return;
  if (target.side === 'player' && isBackpackLocked(target.slot)) { showToast('That backpack slot is locked.', 'error'); return; }
  quickTransfer(drag.item, drag.side, target.slot);
});
function quickTransfer(item, fromSide, targetSlot) {
  if (!trunk?.plate) return;
  const qty = Number(item.quantity || 1);
  const amount = qty > 1 ? null : 1;
  if (amount === null) return openAmountModal(item, fromSide, targetSlot);
  doTransfer(item, fromSide, targetSlot, amount);
}
function openAmountModal(item, fromSide, targetSlot) {
  pendingMove = { item, fromSide, targetSlot };
  $('amountTitle').textContent = fromSide === 'player' ? 'Move to Vehicle Trunk' : 'Move to Player Inventory';
  $('amountLabel').textContent = `${item.label || item.item_name} • max ${item.quantity || 1}`;
  $('amountInput').max = item.quantity || 1;
  $('amountInput').value = item.quantity || 1;
  $('amountModal').classList.remove('hidden');
}
$('amountCancel').onclick = () => { pendingMove = null; $('amountModal').classList.add('hidden'); };
$('amountConfirm').onclick = () => {
  if (!pendingMove) return;
  const max = Number(pendingMove.item.quantity || 1);
  const amount = Math.max(1, Math.min(max, Number($('amountInput').value) || 1));
  doTransfer(pendingMove.item, pendingMove.fromSide, pendingMove.targetSlot, amount);
  pendingMove = null; $('amountModal').classList.add('hidden');
};
function doTransfer(item, fromSide, targetSlot, amount) {
  if (fromSide === 'player') {
    post('moveToTrunk', { plate: trunk.plate, slot: item.slot, toSlot: targetSlot, amount });
    showToast('Moving to trunk...');
  } else {
    post('takeFromTrunk', { plate: trunk.plate, slot: item.slot, toSlot: targetSlot, amount });
    showToast('Taking from trunk...');
  }
}
function showTooltip(item, x, y) {
  const t = $('tooltip');
  const totalWeight = kg((item.weight || 0) * (item.quantity || 1));
  t.innerHTML = `<strong>${item.label || item.item_name}</strong><p>${item.description || 'No description.'}</p><div class="tooltip-meta"><div><b>Type</b><span>${rarityOf(item).toUpperCase()}</span></div><div><b>Weight</b><span>${totalWeight} KG</span></div></div>`;
  t.classList.remove('hidden'); positionTooltip(x, y);
}
function positionTooltip(x, y) { const t = $('tooltip'); t.style.left = `${x + 14}px`; t.style.top = `${y + 14}px`; }
function setWeight() {
  const current = Number(trunk?.player?.weight?.current || 0);
  const max = Number(trunk?.player?.weight?.max || 82000);
  $('weight-current').textContent = kg(current);
  $('weight-max').textContent = `/ ${kg(max)} KG`;
  $('weight-fill').style.width = `${Math.max(0, Math.min(100, (current / max) * 100))}%`;
}
function renderTrunkInventory() {
  if (!trunk) return;
  setWeight();
  $('trunkTitle').textContent = `${trunk.vehicleLabel || 'Vehicle'} Trunk`;
  $('trunkMeta').textContent = `Level ${trunk.trunkLevel || 0} · ${trunk.trunkSlots || 0} slots`;
  $('trunkCount').textContent = `${allTrunkItems().length}/${trunk.trunkSlots || 0}`;
  $('bagLevelLabel').textContent = `${trunk?.player?.bag?.label || 'No Bag'} • ${trunk?.player?.bag?.backpackSlots || 0}/30 slots`;

  $('quickSlots').innerHTML = '';
  for (let i = 1; i <= 5; i++) $('quickSlots').appendChild(makeSlot('player', `quickaccess-${i}`, 'quick'));
  $('pocketSlots').innerHTML = '';
  for (let i = 1; i <= 6; i++) $('pocketSlots').appendChild(makeSlot('player', `pocket-${i}`, 'pocket'));
  $('backpackSlots').innerHTML = '';
  for (let i = 1; i <= 30; i++) $('backpackSlots').appendChild(makeSlot('player', `backpack-${i}`, 'backpack'));
  $('vehicleSlots').innerHTML = '';
  for (let i = 1; i <= Number(trunk.trunkSlots || 0); i++) $('vehicleSlots').appendChild(makeSlot('trunk', `trunk-${i}`, 'trunkslot'));
}
function openTrunk(payload) {
  trunk = payload || {};
  $('vehicleMenu').classList.add('hidden');
  $('trunkInventory').classList.remove('hidden');
  renderTrunkInventory();
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'openMenu') openMenu(data);
  if (data.action === 'openTrunk') openTrunk(data);
  if (data.action === 'updateTrunk') { trunk = data; renderTrunkInventory(); }
  if (data.action === 'toast') showToast(data.message, data.type || 'info');
  if (data.action === 'close') {
    $('vehicleMenu').classList.add('hidden');
    $('trunkInventory').classList.add('hidden');
  }
});
