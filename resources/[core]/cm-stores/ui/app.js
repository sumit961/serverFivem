const app = document.getElementById('app');
const grid = document.getElementById('grid');
const closeBtn = document.getElementById('closeBtn');
const storeName = document.getElementById('storeName');
const title = document.getElementById('title');
const subtitle = document.getElementById('subtitle');
const balanceEl = document.getElementById('balance');
const notice = document.getElementById('notice');

const modal = document.getElementById('modal');
const modalTitle = document.getElementById('modalTitle');
const modalDesc = document.getElementById('modalDesc');
const qtyInput = document.getElementById('qty');
const minus = document.getElementById('minus');
const plus = document.getElementById('plus');
const totalPrice = document.getElementById('totalPrice');
const totalWeight = document.getElementById('totalWeight');
const cancelBuy = document.getElementById('cancelBuy');
const confirmBuy = document.getElementById('confirmBuy');

let currentStore = null;
let selectedItem = null;
let busy = false;

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

function money(value) {
    return '$' + Number(value || 0).toLocaleString();
}

function kg(grams) {
    const v = (Number(grams || 0) / 1000);
    return `${v.toFixed(v >= 10 ? 1 : 2)} kg`;
}

function showNotice(type, message) {
    if (!message) {
        notice.className = 'notice hidden';
        notice.textContent = '';
        return;
    }
    notice.className = `notice ${type || ''}`;
    notice.textContent = message;
    setTimeout(() => showNotice(null, null), 3500);
}

function imagePath(item) {
    return `../cm-items/ui/images/${item.image || (item.name + '.png')}`;
}

function renderItems() {
    grid.innerHTML = '';
    if (!currentStore) return;

    for (const item of currentStore.items || []) {
        const card = document.createElement('div');
        card.className = `item-card ${item.buyable === false ? 'disabled' : ''}`;
        card.innerHTML = `
            <div class="item-img-wrap"><img src="${imagePath(item)}" onerror="this.style.display='none'" /></div>
            <div class="item-name">${item.label || item.name}</div>
            <div class="item-price">${money(item.price)}</div>
            <div class="item-meta">${kg(item.weight)} • max ${item.max || 99}</div>
            <div class="buy-hover"><button>${item.buyable === false ? 'Unavailable' : 'Buy'}</button></div>
        `;
        const btn = card.querySelector('button');
        btn.addEventListener('click', () => {
            if (item.buyable === false) return showNotice('error', 'This item cannot go in inventory.');
            openModal(item);
        });
        grid.appendChild(card);
    }
}

function openModal(item) {
    selectedItem = item;
    modalTitle.textContent = `Buy ${item.label || item.name}`;
    modalDesc.textContent = item.description || 'Choose quantity to buy.';
    qtyInput.value = '1';
    qtyInput.max = String(item.max || 99);
    updateTotals();
    modal.classList.remove('hidden');
}

function closeModal() {
    selectedItem = null;
    modal.classList.add('hidden');
    busy = false;
}

function clampQty() {
    if (!selectedItem) return 1;
    const max = Number(selectedItem.max || 99);
    let qty = Math.floor(Number(qtyInput.value || 1));
    if (qty < 1) qty = 1;
    if (qty > max) qty = max;
    qtyInput.value = String(qty);
    return qty;
}

function updateTotals() {
    if (!selectedItem) return;
    const qty = clampQty();
    totalPrice.textContent = money(qty * Number(selectedItem.price || 0));
    totalWeight.textContent = kg(qty * Number(selectedItem.weight || 0));
}

function openStore(payload) {
    currentStore = payload.store;
    app.classList.remove('hidden');
    storeName.textContent = currentStore?.name || '24/7 Store';
    title.textContent = payload.title || '24/7 Service';
    subtitle.textContent = payload.subtitle || 'Everyday essentials';
    balanceEl.textContent = money(currentStore?.balance || 0);
    showNotice(null, null);
    renderItems();
}

function closeStore() {
    app.classList.add('hidden');
    closeModal();
    currentStore = null;
}

minus.addEventListener('click', () => { qtyInput.value = String(clampQty() - 1); updateTotals(); });
plus.addEventListener('click', () => { qtyInput.value = String(clampQty() + 1); updateTotals(); });
qtyInput.addEventListener('input', updateTotals);
cancelBuy.addEventListener('click', closeModal);
confirmBuy.addEventListener('click', () => {
    if (!selectedItem || busy) return;
    busy = true;
    confirmBuy.textContent = 'Buying...';
    post('buyItem', { itemName: selectedItem.name, amount: clampQty() }).then(() => {
        confirmBuy.textContent = 'Buy';
    }).catch(() => {
        busy = false;
        confirmBuy.textContent = 'Buy';
        showNotice('error', 'Could not contact server.');
    });
});
closeBtn.addEventListener('click', () => post('close', {}));

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (!modal.classList.contains('hidden')) closeModal();
        else post('close', {});
    }
});

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') openStore(data);
    if (data.action === 'close') closeStore();
    if (data.action === 'buyResult') {
        busy = false;
        confirmBuy.textContent = 'Buy';
        if (data.ok) {
            showNotice('success', data.message);
            if (data.extra && data.extra.balance !== undefined) {
                balanceEl.textContent = money(data.extra.balance);
                if (currentStore) currentStore.balance = data.extra.balance;
            }
            closeModal();
        } else {
            showNotice('error', data.message || 'Purchase failed.');
        }
    }
});
