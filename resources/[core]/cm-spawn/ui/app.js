// cm-spawn/ui/app.js
// SPAWN SELECTOR VISUAL REDESIGN: full-screen card grid. Card artwork/color is
// the visual focus now -- there is no live GTA world behind this page and no
// per-hover camera movement (see client/main.lua: the old previewSpawn camera
// chain was removed as a confirmed-dead consumer of this UI). Selecting a
// card only sets local UI state; a spawn is never requested until the
// explicit SPAWN HERE confirm, which still goes through the exact same
// server-authoritative selectSpawn NUI callback/event chain as before.

const spawnSelector = document.getElementById('spawn-selector');
const spawnCardsEl = document.getElementById('spawn-cards');
const spawnFooterStatus = document.getElementById('spawn-footer-status');
const spawnCta = document.getElementById('spawn-cta');
const spawnCtaText = document.getElementById('spawn-cta-text');
const deadNotice = document.getElementById('dead-spawn-notice');
const deadNoticeText = document.getElementById('dead-spawn-text');
const playerSummary = document.getElementById('player-summary');
const playerSummaryName = document.getElementById('player-summary-name');
const playerSummaryCash = document.getElementById('player-summary-cash');
const playerSummaryAvatar = document.getElementById('player-summary-avatar');
const tutorial = document.getElementById('tutorial');
const tutorialTitle = document.getElementById('tutorial-title');
const tutorialText = document.getElementById('tutorial-text');
const stepCurrent = document.getElementById('step-current');
const stepTotal = document.getElementById('step-total');
const progressBar = document.getElementById('progress-bar');

let spawns = [];
let selectedKey = null;
let confirming = false;
let closeTimer = null;
let debugMode = false;

// CLICK DEBUGGING: gated by Config.Debug (passed through openSelector's
// payload from server/main.lua), never on for normal players. console.debug
// only reaches a devtools console a player would have to deliberately open --
// this is not on-screen UI and is never shown/left visible in production.
function dbg(...args) {
    if (debugMode) console.debug('[CM-SPAWN DEBUG]', ...args);
}

// Local-asset-only visual identity per spawn type (see brief: dynamic image
// config in JS, never hardcoded only in CSS). `image` reuses the existing
// local gradient-art SVGs already shipped in ui/assets/ -- no external URL,
// no downloaded photography. A key with no entry here (a genuinely new/
// future dynamic spawn type) falls back to DEFAULT_VISUAL: solid gradient
// only, cyan accent (never purple -- see brief: card tint colors are a
// per-type exception, not a general theme change).
const SPAWN_VISUALS = {
    last: { accent: '#e6550f', image: 'assets/last.svg' },
    home: { accent: '#27ae60', image: null },
    family: { accent: '#2980b9', image: 'assets/family.svg' },
    organization: { accent: '#f1c40f', image: 'assets/organization.svg' },
    hotel: { accent: '#c0392b', image: 'assets/hotel.svg' },
    club: { accent: '#8e44ad', image: null }
};
const DEFAULT_VISUAL = { accent: '#00E5FF', image: null };

function hexToRgba(hex, alpha) {
    const clean = String(hex || '').replace('#', '');
    const bigint = parseInt(clean.length === 3
        ? clean.split('').map(c => c + c).join('')
        : clean, 16);
    if (Number.isNaN(bigint)) return `rgba(0, 229, 255, ${alpha})`;
    const r = (bigint >> 16) & 255;
    const g = (bigint >> 8) & 255;
    const b = bigint & 255;
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function visualFor(key) {
    return SPAWN_VISUALS[String(key || '').toLowerCase()] || DEFAULT_VISUAL;
}

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

function withBrand(text) {
    const brand = (window.CMBranding && window.CMBranding.serverName) || 'CM ROLEPLAY';
    return String(text || '').replace(/\{BRAND\}/g, brand);
}

function initialsFor(name) {
    const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return '?';
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function formatCash(value) {
    const n = Math.max(0, Math.floor(Number(value) || 0));
    return '$' + n.toLocaleString('en-US');
}

// NUI READY HANDSHAKE: tells client/main.lua this page is actually mounted
// and listening. If openSelector arrived before this (e.g. right after a
// cm-spawn resource restart while the page was still loading), Lua holds it
// as pendingSelectorPayload and replays it the moment this callback resolves.
nui('uiReady', {});

window.addEventListener('message', function(event) {
    const data = event.data || {};

    if (data.action === 'openSelector') {
        debugMode = data.debug === true;
        confirming = false;
        selectedKey = null;
        document.body.classList.remove('is-spawning');
        spawnFooterStatus.textContent = '';
        if (closeTimer) {
            clearTimeout(closeTimer);
            closeTimer = null;
        }
        // ROOT STATE: .is-open drives display, .visible (added next frame so
        // the opacity transition actually plays) drives opacity AND
        // pointer-events together -- see style.css. Never touch
        // style.display directly anywhere else in this file.
        spawnSelector.classList.add('is-open');
        requestAnimationFrame(() => spawnSelector.classList.add('visible'));

        renderPlayerSummary(data.player || {});

        if (deadNotice) {
            if (data.player && data.player.deadMode) {
                deadNotice.style.display = 'flex';
                deadNoticeText.textContent = data.player.deadNotice || 'You are still down. Any spawn choice will return you to your last body location.';
            } else {
                deadNotice.style.display = 'none';
            }
        }

        spawns = data.spawns || [];
        renderCards();
        updateCta();

        // BLACK SCREEN FIX: confirm to Lua that the card grid is actually
        // VISIBLE, not just that this handler ran. A prior bug proved rAF
        // timing alone is a false positive: rAF fires every frame regardless
        // of whether #spawn-selector itself is display:none (an inline
        // style="display:none" in index.html was silently winning over the
        // .is-open CSS class the whole time -- render logic executed fine,
        // the ack fired fine, and the player still saw pure black). Check
        // the actual rendered box before ever reporting success.
        requestAnimationFrame(() => requestAnimationFrame(() => {
            const rect = spawnSelector.getBoundingClientRect();
            const visible = rect.width > 0 && rect.height > 0 && getComputedStyle(spawnSelector).display !== 'none';
            dbg('selectorRendered check: visible=' + visible + ' rect=' + rect.width + 'x' + rect.height);
            if (!visible) {
                console.error('[CM-SPAWN] selector root is not actually visible after render -- not sending a false selectorRendered ack');
                return;
            }
            nui('selectorRendered', {});
        }));
        return;
    }

    if (data.action === 'closeSelector') {
        closeSelectorUi();
        return;
    }

    if (data.action === 'spawnRejected') {
        confirming = false;
        updateCta();
        spawnFooterStatus.textContent = data.reason || 'Unable to spawn there.';
        if (window.CMUI && typeof window.CMUI.toast === 'function') {
            window.CMUI.toast(data.reason || 'Unable to spawn there.', 'error');
        }
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
    // Removing .visible drops pointer-events to none IMMEDIATELY (see
    // style.css), before the opacity fade-out even starts, so a closing
    // selector can never still eat a click. .is-open (display) is only
    // dropped after the fade finishes.
    spawnSelector.classList.remove('visible');
    if (deadNotice) deadNotice.style.display = 'none';
    if (closeTimer) clearTimeout(closeTimer);
    closeTimer = setTimeout(() => {
        spawnSelector.classList.remove('is-open');
        closeTimer = null;
    }, 220);
}

// Top-right player identity. Only real server-provided values (name/cash) --
// never a server/source id, account id, or invented avatar photo.
function renderPlayerSummary(player) {
    const name = String(player.name || '').trim();
    if (!name) {
        playerSummary.style.display = 'none';
        return;
    }

    playerSummary.style.display = 'flex';
    playerSummaryName.textContent = name.toUpperCase();
    playerSummaryCash.textContent = formatCash(player.cash);
    playerSummaryAvatar.textContent = initialsFor(name);
}

function renderCards() {
    spawnCardsEl.textContent = '';

    if (!spawns.length) {
        const empty = document.createElement('div');
        empty.className = 'spawn-empty-state';
        empty.textContent = 'No spawn locations available. Please contact staff.';
        spawnCardsEl.appendChild(empty);
        return;
    }

    const fragment = document.createDocumentFragment();

    spawns.forEach((spawn) => {
        const visual = visualFor(spawn.key);
        const locked = spawn.locked === true;

        const card = document.createElement('div');
        card.className = `spawn-card${locked ? ' locked' : ''}${spawn.key === selectedKey ? ' selected' : ''}`;
        card.dataset.spawnKey = spawn.key;
        card.tabIndex = 0;
        card.setAttribute('role', 'button');
        card.setAttribute('aria-pressed', spawn.key === selectedKey ? 'true' : 'false');
        card.style.setProperty('--card-accent', visual.accent);
        card.style.setProperty('--card-accent-soft', hexToRgba(visual.accent, 0.55));
        if (visual.image) card.style.backgroundImage = `url('${visual.image}')`;

        const overlay = document.createElement('div');
        overlay.className = 'card-overlay';
        card.appendChild(overlay);

        const content = document.createElement('div');
        content.className = 'card-content';

        const title = document.createElement('h2');
        title.className = 'card-title';
        title.textContent = spawn.label || spawn.key || '';
        content.appendChild(title);

        const desc = document.createElement('p');
        desc.className = 'card-desc';
        desc.textContent = spawn.description || '';
        content.appendChild(desc);

        if (locked) {
            if (spawn.lockedReason) {
                const reason = document.createElement('p');
                reason.className = 'card-locked-reason';
                reason.textContent = spawn.lockedReason;
                content.appendChild(reason);
            }

            content.appendChild(buildLockIcon());
        }

        card.appendChild(content);
        card.addEventListener('click', () => selectCard(spawn.key));
        card.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                selectCard(spawn.key);
            }
        });

        fragment.appendChild(card);
    });

    spawnCardsEl.appendChild(fragment);
}

function buildLockIcon() {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'card-lock-icon');
    svg.setAttribute('viewBox', '0 0 24 24');

    const body = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    body.setAttribute('x', '5');
    body.setAttribute('y', '11');
    body.setAttribute('width', '14');
    body.setAttribute('height', '10');
    body.setAttribute('rx', '2');
    body.setAttribute('ry', '2');
    svg.appendChild(body);

    const shackle = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    shackle.setAttribute('d', 'M7 11V7a5 5 0 0 1 10 0v4');
    svg.appendChild(shackle);

    return svg;
}

// Selecting a card is a local UI choice only -- it never contacts the server
// and never moves any camera (see header comment). The server only ever
// hears about a choice via the explicit SPAWN HERE confirm below.
function selectCard(key) {
    if (confirming) return;
    dbg('card selected:', key);
    selectedKey = key;
    spawnFooterStatus.textContent = '';

    Array.from(spawnCardsEl.querySelectorAll('.spawn-card')).forEach(card => {
        const isSelected = card.dataset.spawnKey === key;
        card.classList.toggle('selected', isSelected);
        card.setAttribute('aria-pressed', isSelected ? 'true' : 'false');
    });

    updateCta();
}

function updateCta() {
    const spawn = spawns.find(s => s.key === selectedKey);
    spawnCta.disabled = !spawn || spawn.locked === true || confirming;
    if (!confirming) {
        spawnCtaText.textContent = selectedKey === 'last' ? 'CONTINUE HERE' : 'SPAWN HERE';
    }
}

function confirmSelection() {
    if (confirming || !selectedKey) return;
    const spawn = spawns.find(s => s.key === selectedKey);
    if (!spawn || spawn.locked) return;

    dbg('confirm:', selectedKey);
    confirming = true;
    spawnCta.disabled = true;
    spawnCtaText.textContent = 'CHECKING...';
    nui('selectSpawn', { spawnKey: selectedKey }).then(() => {
        dbg('selectSpawn NUI callback resolved for', selectedKey);
    });
}

spawnCta.addEventListener('click', confirmSelection);

function updateTutorial(step, total, title, text) {
    const current = Number(step || 1);
    const max = Math.max(Number(total || 1), 1);
    stepCurrent.textContent = current;
    stepTotal.textContent = max;
    tutorialTitle.textContent = withBrand(title) || 'Welcome';
    tutorialText.textContent = withBrand(text) || '';
    progressBar.style.width = Math.max(0, Math.min(100, (current / max) * 100)) + '%';
}

document.addEventListener('keydown', function(e) {
    if (tutorial.style.display !== 'none') {
        if (e.code === 'Space') {
            nui('tutorialSkip', {});
            tutorial.style.display = 'none';
        }
        return;
    }

    if (spawnSelector.style.display === 'none') return;

    if (e.key === 'Escape') {
        // Do NOT bypass the spawn lifecycle -- ESC has no effect here on
        // purpose (see brief: never let ESC trigger the old unsafe
        // closeSpawn behavior).
        e.preventDefault();
        return;
    }

    if (!spawns.length) return;

    if (e.key === 'ArrowLeft' || e.key === 'a' || e.key === 'A') {
        e.preventDefault();
        moveSelection(-1);
    } else if (e.key === 'ArrowRight' || e.key === 'd' || e.key === 'D') {
        e.preventDefault();
        moveSelection(1);
    } else if (e.key === 'Enter') {
        e.preventDefault();
        confirmSelection();
    }
});

function moveSelection(direction) {
    if (confirming) return;
    const currentIndex = spawns.findIndex(s => s.key === selectedKey);
    let nextIndex = currentIndex + direction;
    if (nextIndex < 0) nextIndex = spawns.length - 1;
    if (nextIndex >= spawns.length) nextIndex = 0;
    selectCard(spawns[nextIndex].key);

    const card = spawnCardsEl.querySelector(`.spawn-card[data-spawn-key="${CSS.escape(spawns[nextIndex].key)}"]`);
    if (card) card.scrollIntoView({ behavior: 'smooth', inline: 'nearest', block: 'nearest' });
}

// Once cm-spawn actually starts a transition, the CTA reflects "SPAWNING..."
// until the page is torn down by closeSelector.
window.addEventListener('message', function(event) {
    if (event.data && event.data.action === 'closeSelector' && confirming) {
        spawnCta.disabled = true;
        spawnCtaText.textContent = 'SPAWNING...';
    }
});
