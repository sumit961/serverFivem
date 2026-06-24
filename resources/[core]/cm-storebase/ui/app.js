const app = document.getElementById('app');
const storeName = document.getElementById('storeName');
const storeInfo = document.getElementById('storeInfo');
const itemsContainer = document.getElementById('items');
const statusText = document.getElementById('statusText');
const closeBtn = document.getElementById('closeBtn');

let currentStore = null;

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
}

function postNui(name, data = {}) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).then(r => r.json()).catch(() => ({ success: false }));
}

function money(value) { return `$${Number(value || 0).toLocaleString()}`; }

function imagePath(item) {
    return item.image || item.icon || 'images/default.svg';
}

function renderStore(store) {
    currentStore = store;
    storeName.textContent = store.name || 'Store';

    const ownerText = store.owner ? `Owner: ${store.owner}` : 'Unowned';
    const tierText = `Tier: ${(store.effectivePriceTier || 'normal').toUpperCase()}`;
    storeInfo.textContent = `${ownerText} • ${tierText}`;

    const items = Array.isArray(store.items) ? store.items : [];
    itemsContainer.innerHTML = '';

    if (!items.length) {
        itemsContainer.innerHTML = '<div class="empty">No items available.</div>';
        return;
    }

    for (const item of items) {
        const stock = Number(item.stock || 0);
        const disabled = stock <= 0;
        const card = document.createElement('div');
        card.className = 'item-card';
        card.innerHTML = `
            <div class="item-image-wrap">
                <img class="item-image" src="${escapeHtml(imagePath(item))}" onerror="this.src='images/default.svg'" />
            </div>
            <p class="item-title">${escapeHtml(item.label || item.name)}</p>
            <div class="item-meta">
                <span>${money(item.price)}</span>
                <span>Stock: ${stock}</span>
            </div>
            <div class="item-actions">
                <input class="qty-input" type="number" min="1" max="${Math.max(stock, 1)}" value="1" ${disabled ? 'disabled' : ''}>
                <button class="buy-btn" ${disabled ? 'disabled' : ''}>Buy</button>
            </div>
        `;

        const qtyInput = card.querySelector('.qty-input');
        const buyBtn = card.querySelector('.buy-btn');

        buyBtn.addEventListener('click', async () => {
            const quantity = Math.max(1, Math.min(Number(qtyInput.value || 1), stock));
            buyBtn.disabled = true;
            statusText.textContent = 'Processing purchase...';

            const result = await postNui('buyItem', { itemName: item.name, quantity });
            if (result && result.success) {
                statusText.textContent = 'Purchase successful.';
            } else {
                statusText.textContent = result.error || 'Purchase failed.';
                buyBtn.disabled = false;
            }
        });

        itemsContainer.appendChild(card);
    }
}

function open(store) { app.classList.remove('hidden'); renderStore(store); }
function close() { app.classList.add('hidden'); currentStore = null; }

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') open(data.store);
    if (data.action === 'refresh' && data.store) renderStore(data.store);
    if (data.action === 'close') close();
});

closeBtn.addEventListener('click', () => { close(); postNui('close'); });
document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') { close(); postNui('close'); }
});
