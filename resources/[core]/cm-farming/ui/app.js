(function () {
    const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-farming';

    function post(name, data) {
        return fetch(`https://${resourceName}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    const holdRoot = document.getElementById('hold-root');
    const holdFill = document.getElementById('holdFill');
    const holdLabel = document.getElementById('holdLabel');

    const chooseRoot = document.getElementById('choose-root');
    const chooseGrid = document.getElementById('chooseGrid');
    const chooseCancel = document.getElementById('chooseCancel');

    const menuRoot = document.getElementById('menu-root');
    const menuClose = document.getElementById('menuClose');
    const menuSubtitle = document.getElementById('menuSubtitle');
    const menuTabs = document.getElementById('menuTabs');
    const xpBar = document.getElementById('xpBar');
    const xpLabel = document.getElementById('xpLabel');
    const panelSeeds = document.getElementById('panelSeeds');
    const panelTools = document.getElementById('panelTools');
    const panelSell = document.getElementById('panelSell');

    function imgSrc(file) {
        return `images/${file || 'default.png'}`;
    }

    function renderSeeds(list) {
        panelSeeds.innerHTML = '';
        (list || []).forEach((item) => {
            const card = document.createElement('div');
            card.className = 'cm-card item-card' + (item.locked ? ' locked' : '');

            const badge = item.locked
                ? `<span class="cm-badge cm-badge-danger">LVL ${item.requiredLevel}</span>`
                : `<span class="cm-badge cm-badge-primary">$${item.price}</span>`;
            const buyBtn = item.locked ? '' : '<button class="cm-btn cm-btn-sm buy-btn">Buy</button>';

            card.innerHTML = `
                <img src="${imgSrc(item.image)}" onerror="this.style.visibility='hidden'">
                <div class="item-name">${item.label}</div>
                <div class="item-desc">${item.description || ''}</div>
                <div class="item-footer">${badge}${buyBtn}</div>
            `;

            if (!item.locked) {
                card.querySelector('.buy-btn').addEventListener('click', () => {
                    post('buyItem', { kind: 'seed', name: item.name, qty: 1 });
                });
            }

            panelSeeds.appendChild(card);
        });
    }

    function renderTools(list) {
        panelTools.innerHTML = '';
        (list || []).forEach((item) => {
            const card = document.createElement('div');
            card.className = 'cm-card item-card';
            card.innerHTML = `
                <img src="${imgSrc(item.image)}" onerror="this.style.visibility='hidden'">
                <div class="item-name">${item.label}</div>
                <div class="item-desc">${item.description || ''}</div>
                <div class="item-footer">
                    <span class="cm-badge cm-badge-primary">$${item.price}</span>
                    <button class="cm-btn cm-btn-sm buy-btn">Buy</button>
                </div>
            `;
            card.querySelector('.buy-btn').addEventListener('click', () => {
                post('buyItem', { kind: 'tool', name: item.name, qty: 1 });
            });
            panelTools.appendChild(card);
        });
    }

    function renderSell(list) {
        panelSell.innerHTML = '';
        if (!list || list.length === 0) {
            panelSell.innerHTML = '<div class="cm-empty">You have no crops to sell.</div>';
            return;
        }
        list.forEach((item) => {
            const card = document.createElement('div');
            card.className = 'cm-card item-card';
            card.innerHTML = `
                <img src="${imgSrc(item.image)}" onerror="this.style.visibility='hidden'">
                <div class="item-name">${item.label}</div>
                <div class="item-desc">Owned: ${item.count} &middot; $${item.price} each</div>
                <div class="item-footer">
                    <input class="cm-input qty-input" type="number" min="1" max="${item.count}" value="${item.count}">
                    <button class="cm-btn cm-btn-sm cm-btn-success sell-btn">Sell</button>
                </div>
            `;
            card.querySelector('.sell-btn').addEventListener('click', () => {
                const input = card.querySelector('.qty-input');
                let amount = parseInt(input.value, 10);
                if (!amount || amount < 1) amount = 1;
                if (amount > item.count) amount = item.count;
                post('sellItem', { name: item.name, amount });
            });
            panelSell.appendChild(card);
        });
    }

    function applyMenuPayload(payload) {
        if (!payload) return;
        const status = payload.status || { level: 0, xp: 0, xpForNext: 80, maxLevel: false };
        menuSubtitle.textContent = `Level ${status.level} · $${payload.cash || 0} cash`;

        const percent = status.maxLevel ? 100 : Math.max(0, Math.min(100, Math.floor(((status.xp || 0) / (status.xpForNext || 1)) * 100)));
        xpBar.style.width = percent + '%';
        xpLabel.textContent = status.maxLevel ? 'Max level reached' : `${status.xp} / ${status.xpForNext} XP to next level`;

        renderSeeds(payload.seeds);
        renderTools(payload.tools);
        renderSell(payload.sellable);
    }

    menuTabs.querySelectorAll('.cm-tab').forEach((tab) => {
        tab.addEventListener('click', () => {
            menuTabs.querySelectorAll('.cm-tab').forEach((t) => t.classList.remove('cm-active'));
            tab.classList.add('cm-active');
            panelSeeds.classList.toggle('hidden', tab.dataset.tab !== 'seeds');
            panelTools.classList.toggle('hidden', tab.dataset.tab !== 'tools');
            panelSell.classList.toggle('hidden', tab.dataset.tab !== 'sell');
        });
    });

    menuClose.addEventListener('click', () => post('closeMenu'));

    function renderChoose(options, fieldKey, index) {
        chooseGrid.innerHTML = '';
        (options || []).forEach((opt) => {
            const card = document.createElement('div');
            card.className = 'cm-card choose-card';
            card.innerHTML = `
                <img src="${imgSrc(opt.image)}" onerror="this.style.visibility='hidden'">
                <div class="item-name">${opt.label}</div>
            `;
            card.addEventListener('click', () => {
                post('choosePlantSeed', { fieldKey, index, cropName: opt.name });
            });
            chooseGrid.appendChild(card);
        });
    }

    chooseCancel.addEventListener('click', () => post('cancelChoosePlant'));

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        switch (data.action) {
            case 'hold':
                holdRoot.classList.toggle('hidden', !data.visible);
                holdFill.style.width = (data.progress || 0) + '%';
                holdLabel.textContent = data.label || '';
                break;
            case 'choosePlant':
                chooseRoot.classList.remove('hidden');
                renderChoose(data.options, data.fieldKey, data.index);
                break;
            case 'closeChoosePlant':
                chooseRoot.classList.add('hidden');
                break;
            case 'openMenu':
                menuRoot.classList.remove('hidden');
                applyMenuPayload(data.payload);
                break;
            case 'closeMenu':
                menuRoot.classList.add('hidden');
                break;
        }
    });

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') post('escape');
    });

    post('ready');
})();
