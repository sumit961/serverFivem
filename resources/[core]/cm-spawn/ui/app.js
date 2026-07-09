// cm-spawn/ui/app.js
// Lightweight NUI controller. Uses cm-ui helpers when available and keeps DOM work small.

const spawnSelector = document.getElementById('spawn-selector');
const spawnGrid = document.getElementById('spawn-grid');
const tutorial = document.getElementById('tutorial');
const tutorialTitle = document.getElementById('tutorial-title');
const tutorialText = document.getElementById('tutorial-text');
const stepCurrent = document.getElementById('step-current');
const stepTotal = document.getElementById('step-total');
const progressBar = document.getElementById('progress-bar');
const deadNotice = document.getElementById('dead-spawn-notice');
const deadNoticeText = document.getElementById('dead-spawn-text');
const playerName = document.getElementById('player-name');
const playerCash = document.getElementById('player-cash');
const playerOrg = document.getElementById('player-org');

let selecting = false;
let closeTimer = null;

function nui(path, payload) {
    if (window.CMUI && typeof window.CMUI.postNui === 'function') {
        return window.CMUI.postNui(path, payload);
    }

    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-spawn';
    return fetch(`https://${resource}/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
    }).catch(() => null);
}

function escapeHtml(value) {
    if (window.CMUI && typeof window.CMUI.safeText === 'function') {
        return window.CMUI.safeText(value);
    }

    return String(value ?? '').replace(/[&<>'"]/g, ch => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
    }[ch]));
}

function formatMoney(value) {
    if (window.CMUI && typeof window.CMUI.formatMoney === 'function') {
        return window.CMUI.formatMoney(value);
    }
    return '$' + Number(value || 0).toLocaleString('en-US');
}

function iconGlyph(icon, groupType) {
    const key = String(icon || '').toLowerCase();
    if (groupType === 'organization' || key.includes('building')) return '◆';
    if (key.includes('hotel')) return '⌂';
    if (key.includes('house') || key.includes('home')) return '⌂';
    if (key.includes('lock')) return '×';
    if (key.includes('location') || key.includes('map')) return '⌖';
    if (key.includes('shield')) return '◇';
    return '•';
}

window.addEventListener('message', function(event) {
    const data = event.data || {};

    if (data.action === 'openSelector') {
        selecting = false;
        document.body.classList.remove('is-spawning');
        spawnSelector.style.display = 'flex';
        if (closeTimer) {
            clearTimeout(closeTimer);
            closeTimer = null;
        }
        requestAnimationFrame(() => spawnSelector.classList.add('visible'));

        if (data.player) {
            playerName.textContent = data.player.name || 'PLAYER';
            playerCash.textContent = formatMoney(data.player.cash || 0);
            const orgLabel = data.player.organization && data.player.organization.label
                ? data.player.organization.label
                : 'NO ORGANIZATION';
            playerOrg.textContent = orgLabel;

            if (deadNotice) {
                if (data.player.deadMode) {
                    deadNotice.style.display = 'flex';
                    deadNoticeText.textContent = data.player.deadNotice || 'You are still down. Any spawn choice will return you to your last body location.';
                } else {
                    deadNotice.style.display = 'none';
                }
            }
        }

        renderSpawns(data.spawns || []);
        return;
    }

    if (data.action === 'closeSelector') {
        closeSelectorUi();
        return;
    }

    if (data.action === 'showTutorial') {
        tutorial.style.display = 'flex';
        updateTutorial(data.step, data.total, data.title, data.text);
        return;
    }

    if (data.action === 'updateTutorial') {
        updateTutorial(data.step, data.total, data.title, data.text);
        return;
    }

    if (data.action === 'hideTutorial') {
        tutorial.style.display = 'none';
    }
});

function closeSelectorUi() {
    spawnSelector.classList.remove('visible');
    if (deadNotice) deadNotice.style.display = 'none';
    if (closeTimer) clearTimeout(closeTimer);
    closeTimer = setTimeout(() => {
        spawnSelector.style.display = 'none';
        closeTimer = null;
    }, 220);
}

function renderSpawns(spawns) {
    spawnGrid.textContent = '';

    if (!spawns.length) {
        const empty = document.createElement('div');
        empty.className = 'empty-state cm-card';
        empty.textContent = 'No spawn locations available. Please contact staff.';
        spawnGrid.appendChild(empty);
        return;
    }

    const fragment = document.createDocumentFragment();

    spawns.forEach((spawn, index) => {
        const card = document.createElement('button');
        const colorClass = String(spawn.color || 'blue').replace(/[^a-z0-9_-]/gi, '').toLowerCase() || 'blue';
        card.type = 'button';
        card.className = `spawn-card cm-card ${colorClass}${spawn.locked ? ' locked' : ''}`;
        card.style.setProperty('--delay', `${Math.min(index, 8) * 55}ms`);

        if (spawn.image) {
            const imagePath = String(spawn.image).replace(/["'\\<>]/g, '');
            card.style.backgroundImage = `url('${imagePath}')`;
        }

        const tag = spawn.groupType === 'organization'
            ? `<div class="spawn-tag cm-badge cm-badge-primary"><span class="cm-dot"></span>${escapeHtml(spawn.orgType || 'Organization')}</div>`
            : '';

        const glyph = escapeHtml(iconGlyph(spawn.icon, spawn.groupType));

        card.innerHTML = `
            <div class="spawn-card-overlay"></div>
            <div class="spawn-content">
                <div class="spawn-topline">
                    <div class="spawn-icon"><span class="cm-spawn-symbol">${glyph}</span></div>
                    ${tag}
                </div>
                <div class="spawn-label-row">
                    <span class="spawn-number">${String(index + 1).padStart(2, '0')}</span>
                    <h2>${escapeHtml(spawn.label || spawn.key)}</h2>
                </div>
                <p>${escapeHtml(spawn.description || '')}</p>
                ${spawn.locked ? `<div class="locked-badge cm-badge cm-badge-danger"><span class="cm-spawn-symbol">×</span>${escapeHtml(spawn.lockedReason || 'Locked')}</div>` : '<div class="spawn-button cm-btn cm-btn-sm">Spawn Here</div>'}
            </div>
        `;

        if (!spawn.locked) {
            card.addEventListener('click', () => selectSpawn(spawn.key), { once: true });
        } else {
            card.disabled = true;
        }

        fragment.appendChild(card);
    });

    spawnGrid.appendChild(fragment);
}

function selectSpawn(key) {
    if (selecting) return;
    selecting = true;
    document.body.classList.add('is-spawning');
    nui('selectSpawn', { spawnKey: key });
    closeSelectorUi();
}

function updateTutorial(step, total, title, text) {
    const current = Number(step || 1);
    const max = Math.max(Number(total || 1), 1);
    stepCurrent.textContent = current;
    stepTotal.textContent = max;
    tutorialTitle.textContent = title || 'Welcome';
    tutorialText.textContent = text || '';
    progressBar.style.width = Math.max(0, Math.min(100, (current / max) * 100)) + '%';
}

document.addEventListener('keydown', function(e) {
    if (e.code === 'Escape' && spawnSelector.style.display !== 'none') return;
    if (e.code === 'Space' && tutorial.style.display !== 'none') {
        nui('closeSpawn', {});
        tutorial.style.display = 'none';
    }
});
