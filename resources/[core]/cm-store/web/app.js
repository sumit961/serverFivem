// cm-store/web/app.js - Strict System Design Directive Store NUI for FiveM

const $ = (id) => document.getElementById(id);
const resourceName = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-store';

const post = (endpoint, payload = {}) => fetch(`https://${resourceName()}/${endpoint}`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=UTF-8' },
  body: JSON.stringify(payload),
}).then(r => r.json().catch(() => ({}))).catch(() => ({}));

const formatNumber = (value) => Math.max(0, Number(value) || 0).toLocaleString('en-US');
const formatMoney = (value) => '$' + formatNumber(value);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (m) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[m]));

let context = {
  storeId: 1,
  storeName: 'Strawberry 24/7',
  storeLabel: '24/7 Supermarket',
  owned: false,
  isOwner: false,
  ownerName: 'City of Los Santos',
  priceTier: 'normal',
  priceMultiplier: 1.0,
  stock: 1000,
  maxStock: 5000,
  overstockLimit: 8000,
  businessBalance: 0,
  dailyIncome: 0,
  weeklyIncome: 0,
  taxDaysLeft: 0,
  purchasePrice: 200000,
  taxAmount: 12000,
  restockBatch: 500,
  restockUnitPrice: 6,
  overstockUnitPrice: 8,
  cashBalance: 0,
  bankBalance: 0,
  catalog: [],
  categories: [],
};

let totalItems = 0;
let totalPrice = 0;
let cartData = {}; // itemId -> { id, name, price, imgSrc, imgHtml, qty }
let pileItems = {}; // itemId -> [DOMElement, DOMElement...]

let activeCategory = 'all';
let searchQuery = '';
let paymentMethod = 'cash';
let activeView = 'catalog';
let submitting = false;
let toastTimer = null;

// ============================================================
// Text Scrambler & UI Feedback
// ============================================================

function scrambleText(element, targetText, duration = 240) {
  if (!element) return;
  const chars = "0123456789$ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const start = Date.now();
  const currentWidth = element.offsetWidth;
  if (currentWidth > 0) element.style.minWidth = currentWidth + 'px';

  const timer = setInterval(() => {
    const now = Date.now();
    if (now - start >= duration) {
      clearInterval(timer);
      element.innerText = targetText;
      element.style.minWidth = 'auto';
    } else {
      const scrambled = targetText.toString().split('').map(char => {
        if (char === ' ' || char === '$' || char === ',') return char;
        return chars[Math.floor(Math.random() * chars.length)];
      }).join('');
      element.innerText = scrambled;
    }
  }, 35);
}

function showToast(message, type = 'success') {
  const toast = $('toast');
  if (!toast) return;
  $('toastMessage').textContent = String(message || '');
  toast.classList.toggle('error', type === 'error');
  toast.classList.remove('hidden');
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.add('hidden'), 3500);
}

function resolveImage(item) {
  const s = String(item.image || '').trim();
  if (s && (s.startsWith('nui://') || s.startsWith('http') || s.startsWith('data:'))) {
    return s;
  }
  const name = String(item.item_name || item.name || '').toLowerCase();
  if (name === 'water') return 'nui://cm-inventory/ui/images/water.png';
  if (name === 'sandwich') return 'nui://cm-inventory/ui/images/sandwich.png';
  if (name.includes('rod') || name.includes('bait') || name === 'worms') {
    return `nui://cm-fishing/ui/images/${name}.png`;
  }
  if (s) return `nui://cm-items/ui/images/catalog/${s}`;
  return 'nui://cm-inventory/ui/images/placeholder.png';
}

const itemSvgs = {
  water: `<svg viewBox="0 0 24 24" fill="#00E5FF"><path d="M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z"/></svg>`,
  sandwich: `<svg viewBox="0 0 24 24" fill="#FF8C00"><path d="M3 11l9-7 9 7v2H3v-2zm0 4h18v2a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4v-2z"/></svg>`,
  cigarettes: `<svg viewBox="0 0 24 24" fill="#FFFFFF"><rect x="6" y="4" width="12" height="16" rx="1"/><rect x="6" y="4" width="12" height="6" fill="#FF8C00"/></svg>`,
  crowbar: `<svg viewBox="0 0 24 24" fill="#829DAE" transform="rotate(45)"><rect x="10" y="2" width="4" height="20" rx="1"/></svg>`,
  pickaxe_1: `<svg viewBox="0 0 24 24" fill="#C2D2DC"><path d="M12 2L4 10l8 8 8-8-8-8zm0 4.83L15.17 10 12 13.17 8.83 10 12 6.83z"/></svg>`,
  pickaxe_2: `<svg viewBox="0 0 24 24" fill="#00E5FF"><path d="M12 2L4 10l8 8 8-8-8-8zm0 4.83L15.17 10 12 13.17 8.83 10 12 6.83z"/></svg>`,
  tent: `<svg viewBox="0 0 24 24" fill="#FF8C00"><path d="M12 4L2 20h20L12 4zm0 4.3L16.4 18H7.6L12 8.3z"/></svg>`,
  campfire: `<svg viewBox="0 0 24 24" fill="#FF8C00"><path d="M12 2C9 7 4 11 4 16a8 8 0 0 0 16 0c0-5-5-9-8-14zm0 18a4 4 0 0 1-4-4c0-2.2 1.8-4 4-6 2.2 2 4 3.8 4 6a4 4 0 0 1-4 4z"/></svg>`,
  fabric_red: `<svg viewBox="0 0 24 24" fill="#E74C3C"><path d="M4 14l8-8 8 8-8-8-8-8z"/></svg>`,
  fabric_blue: `<svg viewBox="0 0 24 24" fill="#00E5FF"><path d="M4 14l8-8 8 8-8-8-8-8z"/></svg>`,
  fabric_yellow: `<svg viewBox="0 0 24 24" fill="#FFC700"><path d="M4 14l8-8 8 8-8-8-8-8z"/></svg>`,
  fabric_green: `<svg viewBox="0 0 24 24" fill="#2ECC71"><path d="M4 14l8-8 8 8-8-8-8-8z"/></svg>`,
  fabric_purple: `<svg viewBox="0 0 24 24" fill="#9B59B6"><path d="M4 14l8-8 8 8-8-8-8-8z"/></svg>`,
  simcard: `<svg viewBox="0 0 24 24" fill="#FFFFFF"><rect x="4" y="2" width="16" height="20" rx="2"/><path d="M14 2v6h6" stroke="#829DAE" stroke-width="2"/><circle cx="10" cy="14" r="2" fill="#829DAE"/></svg>`,
  map: `<svg viewBox="0 0 24 24" fill="#00E5FF"><path d="M3 6l6-4 6 4 6-4v16l-6 4-6-4-6 4V6z"/></svg>`,
  lottery_ticket: `<svg viewBox="0 0 24 24" fill="#2ECC71"><rect x="2" y="6" width="20" height="12" rx="2" stroke="#FFFFFF" stroke-width="2"/><circle cx="6" cy="12" r="2" fill="#FFFFFF"/><circle cx="12" cy="12" r="2" fill="#FFFFFF"/><circle cx="18" cy="12" r="2" fill="#FFFFFF"/></svg>`,
  firework_1: `<svg viewBox="0 0 24 24" fill="#E74C3C"><path d="M12 2l4 8H8l4-8zm-2 8v10h4V10h-4z"/></svg>`,
  firework_2: `<svg viewBox="0 0 24 24" fill="#FFC700"><path d="M12 2l4 8H8l4-8zm-2 8v10h4V10h-4z"/></svg>`
};

function getItemVisual(item) {
  const name = String(item.item_name || item.name || '').toLowerCase();
  if (name.includes('rod') || name.includes('bait') || name === 'worms') {
    const imgSrc = `nui://cm-fishing/ui/images/${name}.png`;
    return {
      type: 'img',
      content: `<img src="${esc(imgSrc)}" alt="${esc(item.label || name)}" onerror="this.onerror=null;this.src='nui://cm-inventory/ui/images/placeholder.png';">`,
      src: imgSrc
    };
  }

  if (itemSvgs[name]) {
    return { type: 'svg', content: itemSvgs[name], src: '' };
  }

  const imgSrc = resolveImage(item);
  return {
    type: 'img',
    content: `<img src="${esc(imgSrc)}" alt="${esc(item.label || name)}" onerror="this.onerror=null;this.src='nui://cm-inventory/ui/images/placeholder.png';">`,
    src: imgSrc
  };
}

// ============================================================
// 2D Physics Engine (Item Pile Dropping & Settling)
// ============================================================

function dropItemIntoPile(itemId, sourceElement = null) {
  const itemData = cartData[itemId];
  const bgPile = $('bgPile');
  const footer = $('cartFooter');
  if (!itemData || !bgPile) return;

  const itemNode = document.createElement('div');
  itemNode.className = 'pile-item';
  itemNode.innerHTML = itemData.imgHtml;

  const hud = document.querySelector('.hud-container') || document.querySelector('.main-content');
  const hudRect = hud ? hud.getBoundingClientRect() : { left: 240, right: window.innerWidth - 240, width: 1200 };

  // Determine whether to send the item to the left or right of the store frame
  let isLeft = true;
  if (sourceElement) {
    const startRect = sourceElement.getBoundingClientRect();
    const centerX = startRect.left + (startRect.width / 2);
    isLeft = centerX < (window.innerWidth / 2);
  } else {
    isLeft = Math.random() < 0.5;
  }

  let posX, posY, vx, vy;
  if (sourceElement) {
    const startRect = sourceElement.getBoundingClientRect();
    posX = startRect.left + (startRect.width / 2) - 26;
    posY = startRect.top + (startRect.height / 2) - 26;
    // Launch outward OUT of the store frame / main div into the side gutters
    const targetGutterX = isLeft
      ? Math.max(16, hudRect.left - 75 - (Math.random() * 50))
      : Math.min(window.innerWidth - 68, hudRect.right + 25 + (Math.random() * 50));
    const dist = targetGutterX - posX;
    vx = dist * 0.08 + (isLeft ? -3.5 : 3.5);
    vy = -(Math.random() * 6 + 5);
  } else {
    posX = isLeft
      ? Math.max(16, hudRect.left - 75 - (Math.random() * 50))
      : Math.min(window.innerWidth - 68, hudRect.right + 25 + (Math.random() * 50));
    posY = -60;
    vx = (Math.random() - 0.5) * 4;
    vy = Math.random() * 4 + 2;
  }

  itemNode.style.transform = `translate(${posX}px, ${posY}px) rotate(0deg)`;
  bgPile.appendChild(itemNode);

  let gravity = 0.76;
  let rotation = Math.random() * 360;
  let rotSpeed = (Math.random() - 0.5) * 16;

  // Floor is near bottom of the screen outside the store frame
  const floorY = window.innerHeight - 85 - (Math.random() * 90);

  // Outer gutters boundaries
  const minX = 10;
  const maxX = window.innerWidth - 62;

  function animate() {
    vy += gravity;
    posX += vx;
    posY += vy;
    rotation += rotSpeed;

    // Bounce on outer walls
    if (posX < minX) {
      posX = minX;
      vx *= -0.55;
      rotSpeed *= -1;
    } else if (posX > maxX) {
      posX = maxX;
      vx *= -0.55;
      rotSpeed *= -1;
    }

    // Floor collision & settle
    if (posY >= floorY) {
      posY = floorY;
      if (vy > 3.2) {
        vy *= -0.36;
        vx *= 0.72;
        rotSpeed *= 0.5;
        itemNode.style.transform = `translate(${posX}px, ${posY}px) rotate(${rotation}deg)`;
        requestAnimationFrame(animate);
      } else {
        itemNode.style.transform = `translate(${posX}px, ${posY}px) rotate(${rotation}deg)`;
        if (!pileItems[itemId]) pileItems[itemId] = [];
        pileItems[itemId].push(itemNode);

        if (footer) {
          footer.classList.remove('cart-bounce');
          void footer.offsetWidth;
          footer.classList.add('cart-bounce');
        }
      }
    } else {
      itemNode.style.transform = `translate(${posX}px, ${posY}px) rotate(${rotation}deg)`;
      requestAnimationFrame(animate);
    }
  }

  requestAnimationFrame(animate);
}

function removePhysicalItem(itemId) {
  if (pileItems[itemId] && pileItems[itemId].length > 0) {
    const elToRemove = pileItems[itemId].pop();
    if (elToRemove) {
      elToRemove.style.opacity = '0';
      setTimeout(() => elToRemove.remove(), 250);
    }
  }
}

function clearAllPhysicalItems() {
  const bgPile = $('bgPile');
  if (bgPile) bgPile.innerHTML = '';
  pileItems = {};
}

// ============================================================
// Footer Cart Tray Rendering
// ============================================================

function renderCartList() {
  const cartList = $('cartList');
  if (!cartList) return;

  cartList.innerHTML = '';
  let hasItems = false;

  Object.keys(cartData).forEach((id) => {
    const item = cartData[id];
    if (item && item.qty > 0) {
      hasItems = true;

      const cartItem = document.createElement('div');
      cartItem.className = 'cart-item';
      cartItem.innerHTML = `
        <div class="ci-icon">
          ${item.imgHtml}
        </div>
        <div class="ci-details">
          <span class="ci-name" title="${esc(item.name)}">${esc(item.name)}</span>
          <span class="ci-cost">${formatMoney(item.price * item.qty)}</span>
        </div>
        <div class="ci-stepper">
          <button type="button" class="btn-step-dec" data-id="${esc(id)}" aria-label="Decrease">−</button>
          <span class="ci-qty">${item.qty}</span>
          <button type="button" class="btn-step-inc" data-id="${esc(id)}" aria-label="Increase">+</button>
        </div>
      `;
      cartList.appendChild(cartItem);
    }
  });

  if (!hasItems) {
    const emptyDiv = document.createElement('div');
    emptyDiv.className = 'empty-text';
    emptyDiv.id = 'emptyText';
    emptyDiv.textContent = 'Cargo bay empty. Click cards to load items.';
    cartList.appendChild(emptyDiv);
  }

  // Stepper handlers inside cart
  cartList.querySelectorAll('.btn-step-dec').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      updateItemQty(btn.dataset.id, -1);
    });
  });
  cartList.querySelectorAll('.btn-step-inc').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      updateItemQty(btn.dataset.id, 1);
    });
  });
}

function updateItemQty(itemId, change, sourceImgElement = null) {
  const item = cartData[itemId];
  if (!item) return;

  if (change > 0) {
    item.qty++;
    totalItems++;
    totalPrice += item.price;
    dropItemIntoPile(itemId, sourceImgElement);
    updateGlobalUI();
  } else if (change < 0 && item.qty > 0) {
    item.qty--;
    totalItems--;
    totalPrice -= item.price;
    removePhysicalItem(itemId);
    updateGlobalUI();
  }
}

function updateGlobalUI() {
  const badge = $('cartBadge');
  if (badge) {
    if (totalItems > 0) {
      badge.style.display = 'flex';
      badge.textContent = String(totalItems);
    } else {
      badge.style.display = 'none';
    }
  }

  const priceDisplay = $('totalPrice');
  if (priceDisplay) scrambleText(priceDisplay, formatMoney(totalPrice));

  // Available balance
  const balDisplay = $('playerBalanceDisplay');
  const availableFunds = paymentMethod === 'cash' ? Number(context.cashBalance || 0) : Number(context.bankBalance || 0);
  if (balDisplay) balDisplay.textContent = formatMoney(availableFunds);

  renderCartList();

  // Checkout button state
  const btn = $('btnCheckout');
  const btnText = $('orderButtonText');

  if (totalItems <= 0) {
    btn.classList.add('empty-state');
    btn.disabled = true;
    if (btnText) btnText.textContent = 'CART EMPTY';
  } else if (totalPrice > availableFunds) {
    btn.classList.add('empty-state');
    btn.disabled = true;
    if (btnText) btnText.textContent = 'INSUFFICIENT FUNDS';
  } else if (context.stock < totalItems) {
    btn.classList.add('empty-state');
    btn.disabled = true;
    if (btnText) btnText.textContent = 'STORE OUT OF STOCK';
  } else {
    btn.classList.remove('empty-state');
    btn.disabled = submitting;
    if (btnText) btnText.textContent = submitting ? 'PROCESSING...' : 'PURCHASE ITEMS ›';
  }
}

// ============================================================
// Catalog & Categories Rendering
// ============================================================

function renderCategories() {
  const pillsContainer = $('categoryPills');
  if (!pillsContainer) return;

  const cats = [{ id: 'all', label: 'ALL ITEMS' }, ...(context.categories || [])];

  pillsContainer.innerHTML = cats.map((c) => `
    <button class="tab-btn ${c.id === activeCategory ? 'active' : ''}" data-cat="${esc(c.id)}" type="button">
      ${esc(c.label)}
    </button>
  `).join('');

  pillsContainer.querySelectorAll('.tab-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      activeCategory = btn.dataset.cat;
      renderCategories();
      renderCatalogGrid();
    });
  });
}

function renderCatalogGrid() {
  const grid = $('productsGrid');
  if (!grid) return;

  const query = searchQuery.trim().toLowerCase();

  const filtered = (context.catalog || []).filter((item) => {
    const matchCategory = activeCategory === 'all' || String(item.category || 'misc').toLowerCase() === activeCategory;
    if (!matchCategory) return false;
    if (!query) return true;
    const label = String(item.label || item.item_name || '').toLowerCase();
    const desc = String(item.description || '').toLowerCase();
    return label.includes(query) || desc.includes(query);
  });

  if (filtered.length === 0) {
    grid.innerHTML = '<div class="empty-state">No matching supplies found in catalog.</div>';
    return;
  }

  const accents = ['accent-cyan', 'accent-orange', 'accent-green'];

  grid.innerHTML = filtered.map((item, index) => {
    const itemName = String(item.item_name || item.name);
    const price = Number(item.price) || 0;
    const priceFormatted = formatMoney(price);
    const label = item.label || itemName;
    const visual = getItemVisual(item);

    if (!cartData[itemName]) {
      cartData[itemName] = {
        id: itemName,
        name: label,
        price: price,
        imgSrc: visual.src,
        imgHtml: visual.content,
        qty: 0,
      };
    } else {
      cartData[itemName].price = price;
      cartData[itemName].name = label;
      cartData[itemName].imgSrc = visual.src;
      cartData[itemName].imgHtml = visual.content;
    }

    // Category accent logic
    const catLower = String(item.category || '').toLowerCase();
    let accent = accents[index % accents.length];
    if (catLower.includes('food') || catLower.includes('consumable')) accent = 'accent-cyan';
    else if (catLower.includes('fish') || catLower.includes('weapon') || catLower.includes('ammo')) accent = 'accent-green';
    else if (catLower.includes('tool') || catLower.includes('gear') || catLower.includes('hardware')) accent = 'accent-orange';

    return `
      <div class="item-card ${accent}" id="card-${esc(itemName)}" data-id="${esc(itemName)}">
        <div class="item-img-wrap">
          <div class="item-img" id="img-${esc(itemName)}">
            ${visual.content}
          </div>
        </div>
        <div class="item-info">
          <div class="item-name" title="${esc(label)}">${esc(label)}</div>
          <div class="item-price" id="price-${esc(itemName)}" data-val="${price}">${priceFormatted}</div>
        </div>
        <div class="hover-add-btn">+ ADD</div>
      </div>
    `;
  }).join('');

  // Card click adds item to cargo bay with visual flash & physics drop
  grid.querySelectorAll('.item-card').forEach((card) => {
    card.addEventListener('click', () => {
      const id = card.dataset.id;
      card.classList.remove('clicked-flash');
      void card.offsetWidth;
      card.classList.add('clicked-flash');

      const sourceImg = card.querySelector('.item-img');
      updateItemQty(id, 1, sourceImg);
    });
  });
}

function renderCatalog() {
  renderCategories();
  renderCatalogGrid();
  updateGlobalUI();
}

// ============================================================
// View Navigation
// ============================================================

function switchView(view) {
  activeView = view;
  document.querySelectorAll('.nav-tab').forEach((tab) => {
    tab.classList.toggle('active', tab.dataset.view === view);
  });

  $('publicView').classList.toggle('hidden', view !== 'public');
  $('catalogView').classList.toggle('hidden', view !== 'catalog');
  $('ownerView').classList.toggle('hidden', view !== 'owner');
  $('cartFooter').classList.toggle('hidden', view !== 'catalog');

  if (view === 'public') renderPublicView();
  if (view === 'catalog') renderCatalog();
  if (view === 'owner') renderOwnerConsole();
}

function renderPublicView() {
  $('publicStatus').textContent = context.owned ? 'PRIVATELY OPERATED' : 'AVAILABLE FOR PURCHASE';
  $('publicOwner').textContent = context.owned
    ? `Operated by ${context.ownerName || 'store owner'}.`
    : 'This 24/7 store is currently operated by the city.';

  $('publicTier').textContent = String(context.priceTier || 'normal').toUpperCase();
  $('publicMultiplier').textContent = `${Number(context.priceMultiplier || 1).toFixed(2)}x BASE`;
  $('publicStock').textContent = `${formatNumber(context.stock)} UNITS`;
  $('publicPurchase').textContent = formatMoney(context.purchasePrice);
  $('publicTax').textContent = formatMoney(context.taxAmount);

  $('buyStoreContainer').classList.toggle('hidden', context.owned === true);
}

function renderOwnerConsole() {
  $('ownerBalance').textContent = formatNumber(context.businessBalance);
  $('ownerTaxDays').textContent = `${Math.max(0, context.taxDaysLeft || 0)} DAYS`;
  $('ownerDailyIncome').textContent = formatMoney(context.dailyIncome);
  $('ownerWeeklyIncome').textContent = formatMoney(context.weeklyIncome);

  const maxStock = Number(context.maxStock) || 5000;
  const overstockLimit = Number(context.overstockLimit) || 8000;
  const currentStock = Number(context.stock) || 0;

  $('ownerStockUnits').textContent = `${formatNumber(currentStock)} / ${formatNumber(maxStock)}`;
  $('ownerStockSub').textContent = currentStock > maxStock
    ? `OVERSTOCK ACTIVE (${formatNumber(currentStock)} / ${formatNumber(overstockLimit)})`
    : `STANDARD CAPACITY (${formatNumber(maxStock)})`;

  $('lblMaxStock').textContent = formatNumber(maxStock);
  $('lblOverstock').textContent = formatNumber(overstockLimit);

  const normalPercent = Math.min(100, Math.max(0, (Math.min(currentStock, maxStock) / maxStock) * 100));
  $('stockBarFill').style.width = `${normalPercent}%`;

  if (currentStock > maxStock) {
    const overstockRange = overstockLimit - maxStock;
    const overstockAmount = currentStock - maxStock;
    const overstockPercent = Math.min(100, Math.max(0, (overstockAmount / overstockRange) * 100));
    $('stockBarOverstock').style.width = `${overstockPercent * 0.4}%`;
  } else {
    $('stockBarOverstock').style.width = '0%';
  }

  document.querySelectorAll('.tier-btn').forEach((btn) => {
    btn.classList.toggle('selected', btn.dataset.tier === (context.priceTier || 'normal'));
  });

  const batch = Number(context.restockBatch) || 500;
  const restockCost = batch * (Number(context.restockUnitPrice) || 6);
  const overstockCost = batch * (Number(context.overstockUnitPrice) || 8);

  $('btnRestockBatch').textContent = `ORDER BATCH (+${batch} - ${formatMoney(restockCost)})`;
  $('btnOverstockBatch').textContent = `OVERSTOCK SHIPMENT (+${batch} - ${formatMoney(overstockCost)})`;
  $('btnPayTax').textContent = `PAY 7-DAY TAX (${formatMoney(context.taxAmount)})`;
}

// ============================================================
// Store Lifecycle & NUI Messaging
// ============================================================

function openStore(ctx) {
  context = ctx || {};
  totalItems = 0;
  totalPrice = 0;
  cartData = {};
  clearAllPhysicalItems();
  searchQuery = '';
  submitting = false;

  const storeTitle = String(context.storeName || 'STRAWBERRY 24/7').toUpperCase();
  $('storeName').textContent = storeTitle;

  if ($('storeBadgeBox')) {
    $('storeBadgeBox').textContent = storeTitle.includes('24/7') ? '24/7' : 'MART';
  }

  $('ownerTab').classList.toggle('hidden', context.isOwner !== true);
  $('searchInput').value = '';

  $('toast').classList.add('hidden');
  $('store-root').classList.remove('hidden');
  $('store-root').setAttribute('aria-hidden', 'false');

  const targetView = (context.initialView === 'owner' && context.isOwner) ? 'owner' : (context.initialView || 'catalog');
  switchView(targetView);
}

function closeStore(sendClose = true) {
  $('store-root').classList.add('hidden');
  $('store-root').setAttribute('aria-hidden', 'true');
  totalItems = 0;
  totalPrice = 0;
  cartData = {};
  clearAllPhysicalItems();
  submitting = false;
  if (sendClose) post('close');
}

// ============================================================
// Event Listeners
// ============================================================

document.querySelectorAll('.nav-tab').forEach((tab) => {
  tab.addEventListener('click', () => switchView(tab.dataset.view));
});

$('searchInput').addEventListener('input', (e) => {
  searchQuery = e.target.value || '';
  renderCatalogGrid();
});

// Payment Method Toggle (Cash / Bank)
document.querySelectorAll('.pay-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.pay-btn').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    paymentMethod = btn.dataset.method || 'cash';
    updateGlobalUI();
  });
});

// Checkout Action
$('btnCheckout').addEventListener('click', async () => {
  if (totalItems <= 0 || submitting) return;

  const items = [];
  for (const [itemName, item] of Object.entries(cartData)) {
    if (item.qty > 0) {
      items.push({ item_name: itemName, count: item.qty });
    }
  }

  if (items.length === 0) return;

  submitting = true;
  updateGlobalUI();

  const res = await post('checkout', {
    items: items,
    method: paymentMethod,
  });

  if (!res) {
    submitting = false;
    updateGlobalUI();
    showToast('Could not contact the store server.', 'error');
  }
});

// Owner Action Listeners
document.querySelectorAll('.tier-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tier-btn').forEach((b) => b.classList.remove('selected'));
    btn.classList.add('selected');
  });
});

$('btnBuyStore').addEventListener('click', () => {
  post('buyStore');
});

$('btnSaveSettings').addEventListener('click', () => {
  const selectedTier = document.querySelector('.tier-btn.selected')?.dataset.tier || 'normal';
  post('manageStore', { priceTier: selectedTier });
});

$('btnRestockBatch').addEventListener('click', () => {
  const selectedTier = document.querySelector('.tier-btn.selected')?.dataset.tier || 'normal';
  post('manageStore', { priceTier: selectedTier, restock: true });
});

$('btnOverstockBatch').addEventListener('click', () => {
  const selectedTier = document.querySelector('.tier-btn.selected')?.dataset.tier || 'normal';
  post('manageStore', { priceTier: selectedTier, overstock: true });
});

$('btnPayTax').addEventListener('click', () => {
  post('payTax');
});

$('btnWithdraw').addEventListener('click', () => {
  post('withdrawBusiness');
});

$('btnClose').addEventListener('click', () => closeStore(true));

// Keyboard Listeners
document.addEventListener('keydown', (e) => {
  if ((e.key === 'Escape' || e.key === 'Backspace') && !$('store-root').classList.contains('hidden')) {
    if (e.key === 'Backspace' && document.activeElement === $('searchInput')) return;
    e.preventDefault();
    closeStore(true);
  }
});

// NUI Messages
window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') {
    openStore(data.ctx);
  } else if (data.action === 'close') {
    closeStore(false);
  } else if (data.action === 'orderResult') {
    const res = data.result || {};
    submitting = false;
    if (typeof res.cash === 'number') context.cashBalance = res.cash;
    if (typeof res.bank === 'number') context.bankBalance = res.bank;

    if (res.ok) {
      totalItems = 0;
      totalPrice = 0;
      cartData = {};
      clearAllPhysicalItems();
      renderCatalogGrid();
      showToast(res.message || 'Order completed successfully!', 'success');
    } else {
      showToast(res.message || 'Order could not be completed.', 'error');
    }
    updateGlobalUI();
  }
});
