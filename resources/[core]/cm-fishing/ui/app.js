(function () {
    'use strict';

    const resourceName = 'cm-fishing';

    function post(endpoint, data) {
        return fetch(`https://${resourceName}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(() => {});
    }

    // -----------------------------------------------------------------
    // Elements
    // -----------------------------------------------------------------
    const interactionEl = document.getElementById('interaction');
    const interactionKeyEl = document.getElementById('interaction-key');
    const interactionTitleEl = document.getElementById('interaction-title');
    const interactionLabelEl = document.getElementById('interaction-label');
    const interactionHintEl = document.getElementById('interaction-hint');

    const minigameEl = document.getElementById('minigame');
    const minigameEyebrowEl = document.getElementById('minigame-eyebrow');
    const minigameTitleEl = document.getElementById('minigame-title');
    const minigameHintEl = document.getElementById('minigame-hint');
    const minigameTargetEl = document.getElementById('minigame-target');
    const minigameWindowEl = document.getElementById('minigame-window');
    const minigameProgressFillEl = document.getElementById('minigame-progress-fill');
    const minigameTimerFillEl = document.getElementById('minigame-timer-fill');

    const catchModalEl = document.getElementById('catch-modal');
    const catchBadgeEl = document.getElementById('catch-badge');
    const catchHeavyEl = document.getElementById('catch-heavy');
    const catchTitleEl = document.getElementById('catch-title');
    const catchSubEl = document.getElementById('catch-sub');
    const catchCloseEl = document.getElementById('catch-close');

    const storeEl = document.getElementById('store');
    const storeCashEl = document.getElementById('store-cash');
    const storeCloseEl = document.getElementById('store-close');

    const levelChipEl = document.getElementById('level-chip');
    const levelBadgeEl = document.getElementById('level-badge');
    const levelNameEl = document.getElementById('level-name');
    const levelXpEl = document.getElementById('level-xp');
    const levelXpFillEl = document.getElementById('level-xp-fill');

    const storeTabs = Array.from(document.querySelectorAll('.store-tab'));
    const storeGrids = {
        rods: document.getElementById('grid-rods'),
        bait: document.getElementById('grid-bait'),
        sell: document.getElementById('grid-sell'),
        boats: document.getElementById('grid-boats'),
        info: document.getElementById('grid-info'),
    };

    // -----------------------------------------------------------------
    // Interaction prompt
    // -----------------------------------------------------------------
    function setInteraction(visible, title, label, hint, key) {
        interactionEl.classList.toggle('hidden', !visible);
        if (!visible) return;
        interactionKeyEl.textContent = key || 'E';
        interactionTitleEl.textContent = title || '';
        interactionLabelEl.textContent = label || '';
        interactionHintEl.textContent = hint || '';
        interactionHintEl.classList.toggle('hidden', !hint);
    }

    // -----------------------------------------------------------------
    // Rarity helpers
    // -----------------------------------------------------------------
    function rarityClass(rarity) {
        switch ((rarity || '').toLowerCase()) {
            case 'rare': return 'rare';
            case 'epic': return 'epic';
            case 'mythic': return 'mythic';
            case 'legend': return 'legend';
            default: return '';
        }
    }

    // -----------------------------------------------------------------
    // Minigame
    // -----------------------------------------------------------------
    const keys = { left: false, right: false };
    let minigame = null;

    window.addEventListener('keydown', (e) => {
        if (!minigame) return;
        if (e.key === 'a' || e.key === 'A' || e.key === 'ArrowLeft') keys.left = true;
        if (e.key === 'd' || e.key === 'D' || e.key === 'ArrowRight') keys.right = true;
    });
    window.addEventListener('keyup', (e) => {
        if (e.key === 'a' || e.key === 'A' || e.key === 'ArrowLeft') keys.left = false;
        if (e.key === 'd' || e.key === 'D' || e.key === 'ArrowRight') keys.right = false;
    });

    function startMinigame(difficulty, settings, heavy) {
        settings = settings || {};

        if (heavy) {
            minigameEyebrowEl.textContent = 'HEAVY CATCH';
            minigameTitleEl.textContent = "It's Huge!";
            minigameHintEl.innerHTML = 'This one is fighting hard -- and your rod might not survive it.';
        } else {
            minigameEyebrowEl.textContent = 'Fish On';
            minigameTitleEl.textContent = 'Reel It In';
            minigameHintEl.innerHTML = 'Hold the window over the fish with <b class="text-[#F59E0B]">A</b> / <b class="text-[#F59E0B]">D</b>';
        }

        minigame = {
            windowWidth: settings.windowWidth || 24,
            targetSpeed: settings.targetSpeed || 45,
            moveSpeed: settings.moveSpeed || 60,
            gainRate: settings.gainRate || 45,
            lossRate: settings.lossRate || 40,
            timeLimitMs: settings.timeLimitMs || 12000,
            targetPos: Math.random() * 80 + 10,
            targetDir: Math.random() < 0.5 ? -1 : 1,
            windowPos: 50 - (settings.windowWidth || 24) / 2,
            progress: 30,
            remainingMs: settings.timeLimitMs || 12000,
            lastFrame: performance.now(),
            done: false,
        };
        minigameWindowEl.style.width = minigame.windowWidth + '%';
        minigameEl.classList.remove('hidden');
        requestAnimationFrame(minigameTick);
    }

    function finishMinigame(success) {
        if (!minigame || minigame.done) return;
        minigame.done = true;
        minigameEl.classList.add('hidden');
        keys.left = false;
        keys.right = false;
        post('minigameResult', { success: !!success });
        minigame = null;
    }

    function minigameTick(now) {
        if (!minigame || minigame.done) return;

        const dt = Math.min(0.05, (now - minigame.lastFrame) / 1000);
        minigame.lastFrame = now;

        minigame.targetPos += minigame.targetDir * minigame.targetSpeed * dt;
        if (minigame.targetPos <= 2) { minigame.targetPos = 2; minigame.targetDir = 1; }
        if (minigame.targetPos >= 98) { minigame.targetPos = 98; minigame.targetDir = -1; }

        if (keys.left) minigame.windowPos -= minigame.moveSpeed * dt;
        if (keys.right) minigame.windowPos += minigame.moveSpeed * dt;
        minigame.windowPos = Math.max(0, Math.min(100 - minigame.windowWidth, minigame.windowPos));

        const overlap = minigame.targetPos >= minigame.windowPos && minigame.targetPos <= (minigame.windowPos + minigame.windowWidth);
        minigame.progress += (overlap ? minigame.gainRate : -minigame.lossRate) * dt;
        minigame.progress = Math.max(0, Math.min(100, minigame.progress));

        minigame.remainingMs -= dt * 1000;

        minigameTargetEl.style.left = minigame.targetPos + '%';
        minigameWindowEl.style.left = minigame.windowPos + '%';
        minigameProgressFillEl.style.width = minigame.progress + '%';
        minigameTimerFillEl.style.width = Math.max(0, (minigame.remainingMs / minigame.timeLimitMs) * 100) + '%';

        if (minigame.progress >= 100) return finishMinigame(true);
        if (minigame.remainingMs <= 0) return finishMinigame(false);

        requestAnimationFrame(minigameTick);
    }

    // -----------------------------------------------------------------
    // Catch result modal
    // -----------------------------------------------------------------
    const RARITY_BADGE_BG = {
        common: '#819BB0', rare: '#00E5FF', epic: '#F59E0B', mythic: '#A855F7', legend: '#EF4444',
    };
    const RARITY_BADGE_DARK_TEXT = new Set(['common', 'rare', 'epic']);

    function showCatchResult(data) {
        if (data.success) {
            const key = (data.rarity || 'common').toLowerCase();
            catchBadgeEl.textContent = (data.rarity || 'Common').toUpperCase();
            catchBadgeEl.style.background = RARITY_BADGE_BG[key] || RARITY_BADGE_BG.common;
            catchBadgeEl.style.color = RARITY_BADGE_DARK_TEXT.has(key) ? '#0B171E' : '#ffffff';
            catchHeavyEl.classList.toggle('hidden', !data.heavy);
            catchHeavyEl.textContent = data.rodBroke ? '⚠ Heavy Catch -- Rod Snapped!' : '⚠ Heavy Catch -- Bigger Than Your Level!';
            catchTitleEl.textContent = `You caught a ${data.label}!`;
            catchSubEl.textContent = `+${data.xp} XP`;
            catchSubEl.className = 'text-sm font-semibold text-[#10B981] mb-5';
            catchCloseEl.textContent = 'NICE';
        } else {
            catchBadgeEl.textContent = 'NO LUCK';
            catchBadgeEl.style.background = RARITY_BADGE_BG.common;
            catchBadgeEl.style.color = '#0B171E';
            catchHeavyEl.classList.add('hidden');
            catchTitleEl.textContent = 'The fish got away';
            catchSubEl.textContent = 'Better luck next cast. Your rod is fine -- only bait is spent.';
            catchSubEl.className = 'text-sm font-semibold text-[#EF4444] mb-5';
            catchCloseEl.textContent = 'TRY AGAIN';
        }
        catchModalEl.classList.remove('hidden');
    }

    function closeCatchModal() {
        catchModalEl.classList.add('hidden');
        post('closeCatch');
    }

    catchCloseEl.addEventListener('click', closeCatchModal);

    // -----------------------------------------------------------------
    // Store: header / level info
    // -----------------------------------------------------------------
    function renderHeader(payload) {
        storeCashEl.textContent = `$${(payload.cash || 0).toLocaleString()}`;

        const status = payload.status || {};
        levelBadgeEl.textContent = status.level || 0;
        levelNameEl.textContent = status.maxLevel ? 'MAX LEVEL ANGLER' : `LEVEL ${status.level || 0} ANGLER`;

        if (status.maxLevel || !status.xpForNext) {
            levelXpEl.textContent = 'MAX LEVEL';
            levelXpFillEl.style.width = '100%';
        } else {
            levelXpEl.textContent = `${status.xp || 0} / ${status.xpForNext} XP`;
            const pct = Math.max(0, Math.min(100, ((status.xp || 0) / status.xpForNext) * 100));
            levelXpFillEl.style.width = pct + '%';
        }
    }

    // -----------------------------------------------------------------
    // Info tab: everything about the fishing system in one place
    // -----------------------------------------------------------------
    function infoSection(eyebrow, title, bodyHtml) {
        const section = document.createElement('div');
        section.className = 'bg-[#0B1824] border border-[#192E42] rounded-2xl p-5';
        section.innerHTML = `
            <div class="text-[10px] font-extrabold tracking-widest uppercase text-[#00E5FF] mb-1">${eyebrow}</div>
            <div class="text-lg font-black text-white uppercase mb-3">${title}</div>
            <div class="text-xs text-[#B7C6D3] leading-relaxed space-y-2">${bodyHtml}</div>
        `;
        return section;
    }

    function renderLevelsGrid(levels) {
        return (levels || []).map((entry) => {
            const hasUnlocks = entry.zones.length || entry.rods.length || entry.fish.length;
            return `
                <div class="bg-[#070F18] border border-[#192E42] rounded-xl p-3.5">
                    <div class="flex items-center justify-between mb-2">
                        <div class="text-xs font-black text-[#00E5FF] uppercase">Level ${entry.level}${entry.level === 0 ? ' (Start)' : ''}</div>
                        <div class="text-[9px] text-[#819BB0] uppercase font-bold">${entry.xpForNext ? `${entry.xpForNext} XP to next` : 'Max level'}</div>
                    </div>
                    ${entry.zones.length ? `<div class="text-[10px] text-white mb-1"><span class="text-[#10B981] font-bold">Zones:</span> ${entry.zones.join(', ')}</div>` : ''}
                    ${entry.rods.length ? `<div class="text-[10px] text-white mb-1"><span class="text-[#F59E0B] font-bold">Gear:</span> ${entry.rods.join(', ')}</div>` : ''}
                    ${entry.fish.length ? `<div class="text-[10px] text-white"><span class="text-[#A855F7] font-bold">Fish:</span> ${entry.fish.map((f) => f.label).join(', ')}</div>` : ''}
                    ${!hasUnlocks ? '<div class="text-[10px] text-[#819BB0] italic">No new unlocks</div>' : ''}
                </div>
            `;
        }).join('');
    }

    function renderZonesGrid(zones) {
        return (zones || []).map((zone) => `
            <div class="bg-[#070F18] border border-[#192E42] rounded-xl p-3.5">
                <div class="text-xs font-black text-white uppercase mb-1">${zone.label}</div>
                <div class="text-[10px] text-[#819BB0]">Requires level <b class="text-white">${zone.minLevel}</b> &middot; ${zone.fishCount} fish types</div>
                ${zone.shallowMax != null ? `<div class="text-[10px] text-[#819BB0] mt-1">Shallow &le;${zone.shallowMax}m &middot; Medium &le;${zone.mediumMax}m &middot; Deep beyond that</div>` : ''}
            </div>
        `).join('');
    }

    function renderInfoTab(payload) {
        const container = storeGrids.info;
        container.innerHTML = '';
        const m = payload.mechanics || {};

        container.appendChild(infoSection('The Basics', 'How Fishing Works', `
            <p>1. Own a fishing rod and bait, then face the water (close enough to actually reach it) to get the cast prompt.</p>
            <p>2. Press <b class="text-white">E</b> to cast. Wait for a bite -- press <b class="text-white">E</b> again any time to reel in and cancel.</p>
            <p>3. When something bites, slide the window over the moving target with <b class="text-white">A</b>/<b class="text-white">D</b> (or arrow keys) to fill the progress bar before the timer runs out.</p>
            <p>4. Land it and it goes straight to your inventory, plus XP toward your next fishing level.</p>
        `));

        container.appendChild(infoSection('Gear', 'Rods & Bait', `
            <p><b class="text-white">Rods</b> are a one-time purchase and never break on a normal catch -- better rods only shorten the wait for a bite. See the Rods tab for the full lineup.</p>
            <p><b class="text-white">Bait</b> is consumed per cast, but better bait has a chance to not be used up, and biases the catch roll toward rarer fish. See the Bait tab for exact numbers per type.</p>
        `));

        container.appendChild(infoSection('Go Deeper', 'Depth & Rare Fish', `
            <p>How far you are from shore matters. Every zone is split into <b class="text-[#00E5FF]">shallow</b>, <b class="text-[#F59E0B]">medium</b>, and <b class="text-[#EF4444]">deep</b> water based on distance from the dock -- fishing outside any named zone (open ocean) always counts as deep.</p>
            <p>Deeper water meaningfully biases the catch roll toward Rare, Epic, Mythic, and Legend fish. If you keep pulling Common fish, try heading further out.</p>
        `));

        container.appendChild(infoSection('Risk & Reward', 'Heavy Fish', `
            <p>Anglers at level <b class="text-white">${m.heavyMaxLevel != null ? m.heavyMaxLevel : 2}</b> or below have a chance to hook something above their normal tier entirely -- "something too big for your gear":</p>
            <p>&bull; <b class="text-white">${m.heavyChanceMedium != null ? m.heavyChanceMedium : 8}%</b> chance in medium water, <b class="text-white">${m.heavyChanceDeep != null ? m.heavyChanceDeep : 8}%</b> in deep water.</p>
            <p>&bull; The reel minigame is noticeably harder for a heavy catch.</p>
            <p>&bull; Landing it still counts as a normal catch -- but there's a <b class="text-[#EF4444]">${m.heavyRodBreakChance != null ? m.heavyRodBreakChance : 35}%</b> chance the rod snaps on the way in. This is the <i>only</i> way a rod can break.</p>
        `));

        container.appendChild(infoSection(m.sharkEnabled === false ? 'Currently Disabled' : 'Danger', 'Shark Encounters', `
            <p>Fishing in <b class="text-[#EF4444]">deep water</b> carries a <b class="text-white">${m.sharkChance != null ? m.sharkChance : 8}%</b> chance per bite that it's a shark instead of a fish.</p>
            <p>A shark encounter interrupts the cast (no catch) and puts a real hostile shark on you -- if it reaches you before it gives up, it deals up to <b class="text-white">${m.sharkDamage != null ? m.sharkDamage : 25}</b> damage.</p>
        `));

        const zonesGrid = document.createElement('div');
        zonesGrid.className = 'grid grid-cols-2 gap-3';
        zonesGrid.innerHTML = renderZonesGrid(payload.zones);
        const zonesSection = infoSection('Where to Fish', 'Fishing Zones', '');
        zonesSection.querySelector('.space-y-2').appendChild(zonesGrid);
        container.appendChild(zonesSection);

        const levelsGrid = document.createElement('div');
        levelsGrid.className = 'grid grid-cols-2 gap-3';
        levelsGrid.innerHTML = renderLevelsGrid(payload.levels);
        const levelsSection = infoSection('Angler Progress', 'What Unlocks At Each Level', '');
        levelsSection.querySelector('.space-y-2').appendChild(levelsGrid);
        container.appendChild(levelsSection);

        if (m.castCooldownSeconds) {
            container.appendChild(infoSection('Good To Know', 'Misc', `
                <p>There's a short cooldown of about <b class="text-white">${m.castCooldownSeconds}s</b> between casts.</p>
                <p>Selling fish and buying gear both happen at this same Fishing Store.</p>
            `));
        }
    }

    levelChipEl.addEventListener('click', () => {
        const infoTab = storeTabs.find((t) => t.dataset.tab === 'info');
        if (infoTab) infoTab.click();
    });

    // -----------------------------------------------------------------
    // Store: rods & bait
    // -----------------------------------------------------------------
    function renderRodOrBait(kind, list, container, playerLevel) {
        container.innerHTML = '';
        if (!list || list.length === 0) {
            container.innerHTML = '<div class="col-span-3 text-center py-10 text-[#819BB0] text-sm">Nothing available.</div>';
            return;
        }

        list.forEach((item) => {
            const locked = kind === 'rod' && item.requiredLevel > playerLevel;
            const card = document.createElement('div');
            card.className = 'item-card' + (locked ? ' locked' : '');

            const badgeRow = kind === 'rod' ? `
                <div class="p-4 flex items-center justify-between">
                    ${locked
                        ? `<span class="px-2.5 py-1 rounded-md bg-[#EF4444]/15 border border-[#EF4444]/40 text-[#EF4444] text-[10px] font-extrabold uppercase tracking-wider">LOCKED</span>`
                        : `<span class="px-2.5 py-1 rounded-md bg-[#10B981]/15 border border-[#10B981]/40 text-[#10B981] text-[10px] font-extrabold uppercase tracking-wider flex items-center gap-1"><span class="w-1.5 h-1.5 rounded-full bg-[#10B981]"></span>UNLOCKED</span>`}
                    <span class="text-[10px] font-mono ${locked ? 'text-[#EF4444] font-bold' : 'text-[#819BB0]'}">REQ: LVL ${item.requiredLevel || 0}</span>
                </div>
            ` : '';

            const lockOverlay = locked ? `
                <div class="lock-overlay">
                    <div class="w-9 h-9 rounded-full bg-[#17090B] border border-[#EF4444]/50 text-[#EF4444] flex items-center justify-center text-base">🔒</div>
                    <span class="text-[9px] font-black tracking-widest text-[#EF4444] uppercase">REQUIRES LEVEL ${item.requiredLevel}</span>
                </div>
            ` : '';

            const perks = (item.perks || []).map((p) => `<span class="perk-pill">${p}</span>`).join('');

            card.innerHTML = `
                ${badgeRow}
                <div class="item-card-image">
                    <img src="images/${item.image}" alt="${item.label}" />
                    ${lockOverlay}
                </div>
                <div class="p-5 space-y-3 flex-1 flex flex-col justify-between">
                    <div>
                        <h3 class="text-base font-black ${locked ? 'text-white/70' : 'text-white'} uppercase tracking-wide">${item.label}</h3>
                        ${item.description ? `<p class="text-xs text-[#819BB0] mt-1 leading-relaxed">${item.description}</p>` : ''}
                        <div class="flex flex-wrap gap-1.5 mt-3">${perks}</div>
                    </div>
                    <div class="pt-3 border-t border-[#122333] flex items-center justify-between">
                        <div>
                            <span class="text-[8px] font-black text-[#819BB0] uppercase tracking-widest block">Price</span>
                            <span class="text-lg font-extrabold text-[#10B981] ${locked ? 'opacity-60' : ''}">$${item.price}</span>
                        </div>
                        ${locked
                            ? `<button disabled class="px-5 py-2.5 bg-[#141F2B] border border-[#1E2E3E] text-[#819BB0]/50 font-black text-xs uppercase tracking-wider rounded-xl cursor-not-allowed">Locked</button>`
                            : `<button class="buy-btn px-6 py-2.5 bg-gradient-to-r from-[#F59E0B] to-[#D97706] hover:from-[#FFB020] hover:to-[#F59E0B] text-[#04080E] font-black text-xs uppercase tracking-wider rounded-xl transition-all active:scale-95">Buy</button>`}
                    </div>
                </div>
            `;

            const buyBtn = card.querySelector('.buy-btn');
            if (buyBtn) {
                buyBtn.addEventListener('click', () => post('buyItem', { kind, name: item.name, qty: 1 }));
            }
            container.appendChild(card);
        });
    }

    // -----------------------------------------------------------------
    // Store: bait (with a cart -- bait is stackable/consumable, so buying
    // several types/quantities in one trip is worth supporting properly,
    // unlike the one-time rod purchases above).
    // -----------------------------------------------------------------
    let baitCart = {};   // { [baitName]: qty }
    let baitCatalog = []; // last-rendered bait list, for label/price lookups

    function baitCartTotal() {
        return Object.keys(baitCart).reduce((sum, name) => {
            const item = baitCatalog.find((b) => b.name === name);
            return item ? sum + item.price * baitCart[name] : sum;
        }, 0);
    }

    function renderBaitCartPanel(container) {
        let panel = container.querySelector('#bait-cart-panel');
        const entries = Object.keys(baitCart).filter((name) => baitCart[name] > 0);

        if (!panel) {
            panel = document.createElement('div');
            panel.id = 'bait-cart-panel';
            panel.className = 'col-span-3 bg-[#0B1824] border border-[#F59E0B]/50 rounded-2xl p-5';
            container.appendChild(panel);
        }

        if (entries.length === 0) {
            panel.classList.add('hidden');
            return;
        }
        panel.classList.remove('hidden');

        const rows = entries.map((name) => {
            const item = baitCatalog.find((b) => b.name === name);
            if (!item) return '';
            return `
                <div class="flex items-center justify-between text-xs text-white py-1.5">
                    <span>${item.label} &times; ${baitCart[name]}</span>
                    <div class="flex items-center gap-3">
                        <span class="text-[#10B981] font-bold">$${item.price * baitCart[name]}</span>
                        <button class="cart-remove-btn text-[#EF4444] hover:text-white text-base leading-none" data-name="${name}">&times;</button>
                    </div>
                </div>
            `;
        }).join('');

        panel.innerHTML = `
            <div class="flex items-center justify-between mb-2">
                <div class="text-[10px] font-black uppercase text-[#F59E0B] tracking-widest">Bait Cart</div>
                <button id="cart-clear-btn" class="text-[10px] text-[#819BB0] hover:text-white uppercase font-bold">Clear</button>
            </div>
            <div class="divide-y divide-[#122333]">${rows}</div>
            <div class="flex items-center justify-between mt-3 pt-3 border-t border-[#122333]">
                <div>
                    <span class="text-[8px] font-black text-[#819BB0] uppercase tracking-widest block">Total</span>
                    <span class="text-xl font-extrabold text-[#10B981]">$${baitCartTotal()}</span>
                </div>
                <button id="cart-checkout-btn" class="px-6 py-2.5 bg-gradient-to-r from-[#F59E0B] to-[#D97706] hover:from-[#FFB020] hover:to-[#F59E0B] text-[#04080E] font-black text-xs uppercase tracking-wider rounded-xl transition-all active:scale-95">Checkout</button>
            </div>
        `;

        panel.querySelectorAll('.cart-remove-btn').forEach((btn) => {
            btn.addEventListener('click', () => {
                delete baitCart[btn.getAttribute('data-name')];
                renderBaitCartPanel(container);
            });
        });
        panel.querySelector('#cart-clear-btn').addEventListener('click', () => {
            baitCart = {};
            renderBaitCartPanel(container);
        });
        panel.querySelector('#cart-checkout-btn').addEventListener('click', () => {
            post('buyCart', { items: { ...baitCart } });
        });
    }

    function renderBait(list, container) {
        container.innerHTML = '';
        baitCatalog = list || [];
        baitCart = {};

        if (!list || list.length === 0) {
            container.innerHTML = '<div class="col-span-3 text-center py-10 text-[#819BB0] text-sm">Nothing available.</div>';
            return;
        }

        list.forEach((item) => {
            const card = document.createElement('div');
            card.className = 'item-card';
            const perks = (item.perks || []).map((p) => `<span class="perk-pill">${p}</span>`).join('');

            card.innerHTML = `
                <div class="item-card-image"><img src="images/${item.image}" alt="${item.label}" /></div>
                <div class="p-5 space-y-3 flex-1 flex flex-col justify-between">
                    <div>
                        <h3 class="text-base font-black text-white uppercase tracking-wide">${item.label}</h3>
                        ${item.description ? `<p class="text-xs text-[#819BB0] mt-1 leading-relaxed">${item.description}</p>` : ''}
                        <div class="flex flex-wrap gap-1.5 mt-3">${perks}</div>
                    </div>
                    <div class="pt-3 border-t border-[#122333]">
                        <div class="flex items-center justify-between mb-2.5">
                            <div>
                                <span class="text-[8px] font-black text-[#819BB0] uppercase tracking-widest block">Price</span>
                                <span class="text-lg font-extrabold text-[#10B981]">$${item.price}</span>
                            </div>
                            <div class="flex items-center gap-1.5">
                                <button class="qty-btn w-7 h-7 rounded-lg bg-[#142434] border border-[#1E364D] text-white font-black text-sm" data-dir="-1">-</button>
                                <span class="qty-value w-7 text-center text-sm font-black text-white">1</span>
                                <button class="qty-btn w-7 h-7 rounded-lg bg-[#142434] border border-[#1E364D] text-white font-black text-sm" data-dir="1">+</button>
                            </div>
                        </div>
                        <button class="add-cart-btn w-full py-2.5 bg-gradient-to-r from-[#F59E0B] to-[#D97706] hover:from-[#FFB020] hover:to-[#F59E0B] text-[#04080E] font-black text-xs uppercase tracking-wider rounded-xl transition-all active:scale-95">Add to Cart</button>
                    </div>
                </div>
            `;

            let qty = 1;
            const qtyEl = card.querySelector('.qty-value');
            card.querySelectorAll('.qty-btn').forEach((btn) => {
                btn.addEventListener('click', () => {
                    qty = Math.max(1, Math.min(20, qty + parseInt(btn.getAttribute('data-dir'), 10)));
                    qtyEl.textContent = qty;
                });
            });
            card.querySelector('.add-cart-btn').addEventListener('click', () => {
                baitCart[item.name] = Math.min(20, (baitCart[item.name] || 0) + qty);
                renderBaitCartPanel(container);
            });

            container.appendChild(card);
        });

        renderBaitCartPanel(container);
    }

    // -----------------------------------------------------------------
    // Store: sell fish
    // -----------------------------------------------------------------
    function renderSell(list, container) {
        container.innerHTML = '';
        if (!list || list.length === 0) {
            container.innerHTML = '<div class="col-span-3 text-center py-10 text-[#819BB0] text-sm">You have no fish to sell. Go catch some!</div>';
            return;
        }

        list.forEach((item) => {
            const card = document.createElement('div');
            card.className = 'item-card';
            card.innerHTML = `
                <div class="p-4"><span class="rarity-pill ${rarityClass(item.rarity)}">${item.rarity}</span></div>
                <div class="item-card-image"><img src="images/${item.image}" alt="${item.label}" /></div>
                <div class="p-5 space-y-3 flex-1 flex flex-col justify-between">
                    <div>
                        <h3 class="text-base font-black text-white uppercase tracking-wide">${item.label}</h3>
                        ${item.description ? `<p class="text-xs text-[#819BB0] mt-1 leading-relaxed">${item.description}</p>` : ''}
                        <div class="text-[10px] text-[#819BB0] mt-2">You have <b class="text-white">${item.count}</b> &middot; worth <b class="text-[#A855F7]">${item.xp} XP</b> each</div>
                    </div>
                    <div class="pt-3 border-t border-[#122333] flex items-center justify-between">
                        <div>
                            <span class="text-[8px] font-black text-[#819BB0] uppercase tracking-widest block">Price</span>
                            <span class="text-lg font-extrabold text-[#10B981]">$${item.price}<span class="text-[10px] text-[#819BB0] font-semibold">/ea</span></span>
                        </div>
                        <div class="flex gap-1.5">
                            <button data-amount="1" class="sell-btn px-3.5 py-2.5 bg-[#142434] border border-[#1E364D] hover:border-[#00E5FF]/60 text-white font-black text-[10px] uppercase tracking-wider rounded-xl transition-all active:scale-95">Sell 1</button>
                            <button data-amount="all" class="sell-btn px-3.5 py-2.5 bg-gradient-to-r from-[#F59E0B] to-[#D97706] hover:from-[#FFB020] hover:to-[#F59E0B] text-[#04080E] font-black text-[10px] uppercase tracking-wider rounded-xl transition-all active:scale-95">Sell All</button>
                        </div>
                    </div>
                </div>
            `;
            card.querySelectorAll('.sell-btn').forEach((btn) => {
                btn.addEventListener('click', () => {
                    const amount = btn.getAttribute('data-amount');
                    post('sellFish', { name: item.name, amount: amount === 'all' ? 'all' : 1 });
                });
            });
            container.appendChild(card);
        });
    }

    // -----------------------------------------------------------------
    // Store: boat rental
    // -----------------------------------------------------------------
    function renderBoatInfoBanner(rentedBoat, container) {
        if (!rentedBoat) return;
        const banner = document.createElement('div');
        banner.className = 'col-span-3 flex items-center justify-between bg-[#0B1824] border border-[#10B981]/40 rounded-xl px-5 py-4 mt-1';
        banner.innerHTML = `
            <div>
                <div class="text-[10px] font-black uppercase text-[#10B981] tracking-widest">Boat currently out</div>
                <div class="text-sm text-white font-bold mt-0.5">You have a boat rented. Return it to rent a different one.</div>
            </div>
            <button id="return-boat-btn" class="px-5 py-2.5 bg-[#142434] border border-[#EF4444]/50 hover:bg-[#EF4444] text-[#EF4444] hover:text-white font-black text-xs uppercase tracking-wider rounded-xl transition-all active:scale-95">Return Boat</button>
        `;
        banner.querySelector('#return-boat-btn').addEventListener('click', () => post('returnBoat'));
        container.appendChild(banner);
    }

    function renderBoats(list, rentedBoat, container) {
        container.innerHTML = '';

        if (!list || list.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'col-span-3 text-center py-10 text-[#819BB0] text-sm';
            empty.textContent = 'Boat rental is unavailable right now.';
            container.appendChild(empty);
            renderBoatInfoBanner(rentedBoat, container);
            return;
        }

        list.forEach((item) => {
            const disabled = !!rentedBoat;
            const card = document.createElement('div');
            card.className = 'item-card' + (disabled ? ' locked' : '');
            card.innerHTML = `
                <div class="item-card-image">
                    <img src="${item.image}" alt="${item.label}" onerror="this.style.display='none';" />
                </div>
                <div class="p-5 space-y-3 flex-1 flex flex-col justify-between">
                    <div>
                        <h3 class="text-base font-black ${disabled ? 'text-white/70' : 'text-white'} uppercase tracking-wide">${item.label}</h3>
                        <div class="flex flex-wrap gap-1.5 mt-3">
                            <span class="perk-pill">WATER VEHICLE</span>
                            <span class="perk-pill">OWNED WHILE RENTED</span>
                        </div>
                    </div>
                    <div class="pt-3 border-t border-[#122333] flex items-center justify-between">
                        <div>
                            <span class="text-[8px] font-black text-[#819BB0] uppercase tracking-widest block">Price</span>
                            <span class="text-lg font-extrabold text-[#10B981] ${disabled ? 'opacity-60' : ''}">$${item.price}</span>
                        </div>
                        ${disabled
                            ? `<button disabled class="px-5 py-2.5 bg-[#141F2B] border border-[#1E2E3E] text-[#819BB0]/50 font-black text-xs uppercase tracking-wider rounded-xl cursor-not-allowed">Unavailable</button>`
                            : `<button class="rent-btn px-6 py-2.5 bg-gradient-to-r from-[#F59E0B] to-[#D97706] hover:from-[#FFB020] hover:to-[#F59E0B] text-[#04080E] font-black text-xs uppercase tracking-wider rounded-xl transition-all active:scale-95">Rent</button>`}
                    </div>
                </div>
            `;
            const rentBtn = card.querySelector('.rent-btn');
            if (rentBtn) rentBtn.addEventListener('click', () => post('rentBoat', { name: item.name }));
            container.appendChild(card);
        });

        renderBoatInfoBanner(rentedBoat, container);
    }

    // -----------------------------------------------------------------
    // Store: assemble + tabs
    // -----------------------------------------------------------------
    function renderStore(payload) {
        renderHeader(payload);
        renderInfoTab(payload);

        const playerLevel = (payload.status && payload.status.level) || 0;
        renderRodOrBait('rod', payload.rods, storeGrids.rods, playerLevel);
        renderBait(payload.bait, storeGrids.bait);
        renderSell(payload.fish, storeGrids.sell);
        renderBoats(payload.boats, payload.rentedBoat, storeGrids.boats);
    }

    storeTabs.forEach((tab) => {
        tab.addEventListener('click', () => {
            storeTabs.forEach((t) => t.classList.remove('active'));
            tab.classList.add('active');
            Object.keys(storeGrids).forEach((key) => {
                storeGrids[key].classList.toggle('hidden', key !== tab.dataset.tab);
            });
        });
    });

    storeCloseEl.addEventListener('click', () => {
        storeEl.classList.add('hidden');
        post('closeStore');
    });

    window.addEventListener('keydown', (e) => {
        if (e.key !== 'Escape') return;
        if (!catchModalEl.classList.contains('hidden')) {
            closeCatchModal();
        } else if (!storeEl.classList.contains('hidden')) {
            storeEl.classList.add('hidden');
            post('escape');
        }
    });

    // -----------------------------------------------------------------
    // NUI message router
    // -----------------------------------------------------------------
    window.addEventListener('message', (event) => {
        const data = event.data || {};

        switch (data.action) {
            case 'interaction':
                setInteraction(data.visible, data.title, data.label, data.hint, data.key);
                break;

            case 'startMinigame':
                startMinigame(data.difficulty, data.settings, data.heavy);
                break;

            case 'catchResult':
                showCatchResult(data);
                break;

            case 'openStore':
                storeEl.classList.remove('hidden');
                renderStore(data.payload || {});
                break;

            case 'closeStore':
                storeEl.classList.add('hidden');
                break;

            default:
                break;
        }
    });

    post('ready');
})();
