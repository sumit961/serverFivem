const root = document.getElementById('gas-root');
const interaction = document.getElementById('interaction');

const $ = (id) => document.getElementById(id);
const resourceName = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-gasstations';
const post = (endpoint, payload = {}) => fetch(`https://${resourceName()}/${endpoint}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=UTF-8' },
  body: JSON.stringify(payload),
}).catch(() => null);

const formatMoney = (value) => Math.max(0, Number(value) || 0).toLocaleString('en-US');
const clamp = (value, min, max) => Math.min(max, Math.max(min, Number(value) || 0));

let context = {
  sessionToken: '',
  stationName: 'Gas Station',
  inCar: false,
  vehicle: null,
  fuel: 0,
  maxFuel: 100,
  pricePerPercent: 0,
  fuelCanPrice: 0,
  repairKitPrice: 0,
  washKitPrice: 0,
  maxItemQuantity: 10,
  cash: 0,
};

let order = { fuelTarget: 0, kits: 0, cans: 0, washes: 0 };
let submitting = false;
let toastTimer = null;

function fuelAdded() {
  if (!context.inCar) return 0;
  return Math.max(0, Math.round(order.fuelTarget) - Math.round(context.fuel));
}

function fuelCost() { return fuelAdded() * Number(context.pricePerPercent || 0); }
function itemCost() {
  return (order.kits * Number(context.repairKitPrice || 0))
    + (order.cans * Number(context.fuelCanPrice || 0))
    + (order.washes * Number(context.washKitPrice || 0));
}
function totalCost() { return fuelCost() + itemCost(); }

function showToast(message, type = 'success') {
  const toast = $('toast');
  $('toastMessage').textContent = String(message || '');
  toast.classList.toggle('error', type === 'error');
  toast.classList.remove('hidden');
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.add('hidden'), 4200);
}

let previousFuel = 0;

function spawnDroplets(intensity) {
  const panel = document.querySelector('.gas-panel');
  if (!panel) return;
  const dropCount = Math.min(Math.floor(intensity / 2) + 1, 15);
  for (let i = 0; i < dropCount; i++) {
    const drop = document.createElement('div');
    drop.className = 'droplet';
    drop.style.left = `${Math.random() * 80 + 10}%`;
    drop.style.height = `${Math.random() * 8 + 8}px`;
    drop.style.animationDuration = `${0.35 + Math.random() * 0.15}s`;
    panel.appendChild(drop);
    setTimeout(() => drop.remove(), 600);
  }
}

function updateFuelVisual() {
  const current = Math.round(Number(context.fuel) || 0);
  const target = context.inCar ? Math.round(order.fuelTarget) : 0;
  const maximum = Math.max(1, Number(context.maxFuel) || 100);
  const percentage = clamp((target / maximum) * 100, 0, 100);

  if (target > previousFuel && previousFuel > 0) {
    spawnDroplets(target - previousFuel);
  }
  previousFuel = target;

  $('currentFuelValue').textContent = current;
  $('targetFuelValue').textContent = target;
  $('fuelAddedValue').textContent = fuelAdded();
  $('fuelCost').textContent = formatMoney(fuelCost());
  $('rangeMinLabel').textContent = `${current}%`;
  $('fuelRange').min = String(current);
  $('fuelRange').max = String(maximum);
  $('fuelRange').value = String(target);
  $('fuelRange').style.setProperty('--range-fill', `${percentage}%`);
  $('fuelRing').style.setProperty('--fuel-angle', `${percentage * 3.6}deg`);
  const fluid = $('fluidTank');
  if (fluid) {
    fluid.style.setProperty('--fluid-level', `${context.inCar ? percentage : 35}%`);
    fluid.style.height = `${context.inCar ? percentage : 35}%`;
  }
}

function updateCheckout() {
  const total = totalCost();
  const insufficient = total > Number(context.cash || 0);
  const empty = total <= 0;
  const button = $('btnOrder');

  $('grandTotal').textContent = formatMoney(total);
  $('cashValue').textContent = formatMoney(context.cash);
  button.disabled = submitting || empty || insufficient;

  if (submitting) {
    $('orderButtonText').textContent = 'Processing order';
    $('checkoutHint').textContent = 'Verifying vehicle and payment';
  } else if (insufficient) {
    $('orderButtonText').textContent = 'Not enough cash';
    $('checkoutHint').textContent = `Need $${formatMoney(total - Number(context.cash || 0))} more`;
  } else {
    $('orderButtonText').textContent = 'Place order';
    $('checkoutHint').textContent = 'Cash payment';
  }
}

function render() {
  updateFuelVisual();
  $('kitsQuantity').textContent = order.kits;
  $('cansQuantity').textContent = order.cans;
  $('washesQuantity').textContent = order.washes;
  updateCheckout();
}

function setQuantity(product, direction) {
  if (submitting || !(product in order)) return;
  const maximum = Number(context.maxItemQuantity || 10);
  order[product] = clamp(order[product] + direction, 0, maximum);
  render();
}

function setFuelTarget(target) {
  if (!context.inCar || submitting) return;
  order.fuelTarget = clamp(Math.round(target), Math.round(context.fuel), Number(context.maxFuel || 100));
  render();
}

function openPanel(newContext) {
  context = { ...context, ...(newContext || {}) };
  context.fuel = Math.round(Number(context.fuel) || 0);
  context.maxFuel = Math.round(Number(context.maxFuel) || 100);
  context.cash = Number(context.cash) || 0;
  context.maxItemQuantity = Number(context.maxItemQuantity) || 10;
  submitting = false;
  previousFuel = context.inCar ? context.fuel : 0;
  order = {
    fuelTarget: context.inCar ? context.fuel : 0,
    kits: 0,
    cans: 0,
    washes: 0,
  };

  $('stationName').textContent = String(context.stationName || 'Gas Station');
  $('stationMode').textContent = context.inCar ? 'Vehicle secured - engine off - server-priced fuel' : 'Purchase vehicle supplies for your inventory';
  $('repairUnitPrice').textContent = formatMoney(context.repairKitPrice);
  $('fuelCanUnitPrice').textContent = formatMoney(context.fuelCanPrice);
  $('washUnitPrice').textContent = formatMoney(context.washKitPrice);

  $('vehicleCard').classList.toggle('hidden', !context.inCar);
  $('storeOnlyCard').classList.toggle('hidden', context.inCar);
  const station = context.station || {};
  $('ownerSection').classList.toggle('hidden', station.owned !== true);
  $('buySection').classList.toggle('hidden', station.owned === true);
  $('ownerTab').classList.toggle('hidden', station.owned !== true);
  $('publicStatus').textContent = station.owned === true ? 'PRIVATELY OPERATED' : 'AVAILABLE FOR PURCHASE';
  $('publicOwner').textContent = station.owned === true ? `Operated by ${station.ownerName || 'station owner'}.` : 'This station is currently operated by the city.';
  $('publicPrice').textContent = `$${formatMoney(context.pricePerPercent)}`;
  $('publicStock').textContent = formatMoney(station.stock);
  $('publicTier').textContent = String(station.priceTier || 'normal').toUpperCase();
  $('publicPurchase').textContent = `$${formatMoney(station.purchasePrice)}`;
  switchView('operate');
  $('businessBalance').textContent = formatMoney(station.businessBalance);
  $('purchasePrice').textContent = formatMoney(station.purchasePrice);
  $('taxPaidDays').textContent = `${Math.max(0, Math.ceil((new Date(station.taxDueAt || 0).getTime() - Date.now()) / 86400000))} DAYS`;
  $('dailyIncome').textContent = `$${formatMoney(station.dailyIncome)}`;
  $('weeklyIncome').textContent = `$${formatMoney(station.weeklyIncome)}`;
  $('ownerStock').textContent = formatMoney(station.stock);
  document.querySelectorAll('[data-price-tier]').forEach((button) => button.classList.toggle('selected', button.dataset.priceTier === (station.priceTier || 'normal')));

  if (context.inCar && context.vehicle) {
    $('vehicleName').textContent = String(context.vehicle.label || 'Vehicle');
    $('vehiclePlate').textContent = String(context.vehicle.plate || 'NO PLATE');
  }

  $('toast').classList.add('hidden');
  render();
  interaction.classList.add('hidden');
  root.classList.remove('hidden');
  root.setAttribute('aria-hidden', 'false');
}

function switchView(view) {
  const owner = (context.station || {}).owned === true;
  const isOwner = view === 'owner' && owner;
  const isOperate = view === 'operate' || isOwner;
  $('publicSection').classList.toggle('hidden', isOperate);
  $('operateView').classList.toggle('hidden', !isOperate);
  $('checkoutFooter').classList.toggle('hidden', view !== 'operate');
  $('vehicleCard').classList.toggle('hidden', view !== 'operate' || !context.inCar);
  $('storeOnlyCard').classList.toggle('hidden', view !== 'operate' || context.inCar);
  document.querySelectorAll('.station-tab').forEach((tab) => tab.classList.toggle('active', tab.dataset.view === view));
  $('ownerSection').classList.toggle('hidden', !isOwner);
  $('storeSection').classList.toggle('hidden', isOwner);
  $('buySection').classList.toggle('hidden', view !== 'public' || owner);
}

function closePanel(sendClose = false) {
  root.classList.add('hidden');
  root.setAttribute('aria-hidden', 'true');
  submitting = false;
  if (sendClose) post('close');
}

function updateInteraction(data) {
  const visible = data.visible === true;
  if (!visible) {
    interaction.classList.add('hidden');
    interaction.setAttribute('aria-hidden', 'true');
    return;
  }

  $('interactionKey').textContent = String(data.key || 'E');
  $('interactionTitle').textContent = String(data.title || 'FUEL STATION');
  $('interactionLabel').textContent = String(data.label || 'Open gas station');
  $('interactionHint').textContent = String(data.hint || 'Press to interact');
  interaction.classList.remove('hidden');
  interaction.setAttribute('aria-hidden', 'false');
}

document.querySelectorAll('.quantity').forEach((quantity) => {
  quantity.querySelectorAll('button').forEach((button) => {
    button.addEventListener('click', () => {
      setQuantity(quantity.dataset.product, Number(button.dataset.direction || 0));
    });
  });
});

document.querySelectorAll('.station-tab').forEach((tab) => tab.addEventListener('click', () => switchView(tab.dataset.view)));

document.querySelectorAll('[data-fuel-add]').forEach((button) => {
  button.addEventListener('click', () => setFuelTarget(Number(order.fuelTarget || context.fuel) + Number(button.dataset.fuelAdd || 0)));
});

document.querySelector('[data-fuel-full]').addEventListener('click', () => setFuelTarget(context.maxFuel));
$('fuelRange').addEventListener('input', (event) => setFuelTarget(event.target.value));

$('btnOrder').addEventListener('click', async () => {
  if (submitting || totalCost() <= 0 || totalCost() > Number(context.cash || 0)) return;
  submitting = true;
  render();
  const response = await post('placeOrder', {
    fuelTarget: order.fuelTarget,
    kits: order.kits,
    cans: order.cans,
    washes: order.washes,
  });
  if (!response) {
    submitting = false;
    render();
    showToast('Could not contact the gas station.', 'error');
  }
});

$('buyStation').addEventListener('click', () => post('buyStation'));
$('buyStationPublic').addEventListener('click', () => post('buyStation'));
$('saveStation').addEventListener('click', () => post('manageStation', { priceTier: document.querySelector('[data-price-tier].selected')?.dataset.priceTier || 'normal' }));
$('restockStation').addEventListener('click', () => post('manageStation', { priceTier: document.querySelector('[data-price-tier].selected')?.dataset.priceTier || 'normal', restock: true }));
$('payTax').addEventListener('click', () => post('payTax'));
$('withdrawBusiness').addEventListener('click', () => post('withdrawBusiness'));
document.querySelectorAll('[data-price-tier]').forEach((button) => button.addEventListener('click', () => {
  document.querySelectorAll('[data-price-tier]').forEach((item) => item.classList.remove('selected'));
  button.classList.add('selected');
}));

$('btnClose').addEventListener('click', () => closePanel(true));

document.addEventListener('keydown', (event) => {
  if ((event.key === 'Escape' || event.key === 'Backspace') && !root.classList.contains('hidden')) {
    event.preventDefault();
    closePanel(false);
    post('escape');
  }
});

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'interaction') updateInteraction(data);
  if (data.action === 'open') openPanel(data.ctx);
  if (data.action === 'close') closePanel(false);
  if (data.action === 'orderResult') {
    const result = data.result || {};
    submitting = false;
    if (typeof result.cash === 'number') context.cash = result.cash;
    render();
    showToast(result.message || (result.ok ? 'Order complete.' : 'Order failed.'), result.ok ? 'success' : 'error');
  }
});
