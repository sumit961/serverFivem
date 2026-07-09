// cm-playerdata NUI — overhead labels + hex interaction menu.
// No NUI focus is used; all input is handled in Lua (number keys / RMB / ESC / G).

const labelsRoot = document.getElementById('labels');
const gPrompt = document.getElementById('gprompt');
const hexMenu = document.getElementById('hexmenu');
const hexGrid = document.getElementById('hex-grid');
const hintText = document.getElementById('hint-text');
const titleName = document.getElementById('title-name');
const titleId = document.getElementById('title-id');

const LABEL_BASE_PX = 17; // scaled per-label by distance factor from Lua

// Minimal line-icon set (stroke = currentColor, cyan via CSS).
const ICONS = {
    people: '<svg viewBox="0 0 24 24"><circle cx="9" cy="8" r="3"/><path d="M3.5 19c.6-3 2.8-4.5 5.5-4.5S13.9 16 14.5 19"/><circle cx="17" cy="9" r="2.4"/><path d="M15.5 14.6c2.4.1 4.2 1.5 4.9 4.4"/></svg>',
    documents: '<svg viewBox="0 0 24 24"><rect x="5" y="3.5" width="12" height="16" rx="1.6"/><path d="M8.5 8h5.5M8.5 11.5h5.5M8.5 15h3.5"/><path d="M19 7v11.5a1.8 1.8 0 0 1-1.8 1.8H8"/></svg>',
    organization: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.2"/><path d="M3.8 12h16.4M12 3.8c-2.6 2.3-3.7 5-3.7 8.2s1.1 5.9 3.7 8.2c2.6-2.3 3.7-5 3.7-8.2S14.6 6.1 12 3.8z"/></svg>',
    family: '<svg viewBox="0 0 24 24"><path d="M4 11.5 12 5l8 6.5"/><path d="M6 10.5V19h12v-8.5"/><circle cx="10" cy="14" r="1.5"/><circle cx="14" cy="14" r="1.5"/><path d="M8.5 19c.3-1.6 1.7-2.4 3.5-2.4s3.2.8 3.5 2.4"/></svg>',
    status: '<svg viewBox="0 0 24 24"><path d="M3.5 12h4l2-4.5 3 9 2.2-4.5h5.8"/></svg>',
    close: '<svg viewBox="0 0 24 24"><path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/></svg>',
    handshake: '<svg viewBox="0 0 24 24"><path d="M3 9.5 7.5 6l4 1.5L16 5l5 4.5"/><path d="M3 9.5l5 6.5c.9 1 2.2 1 3 .2l.6-.6"/><path d="M21 9.5l-5.5 6.7c-.8 1-2.1 1.1-3 .3l-2.4-2.2"/><path d="M11.5 7.5 8.6 10c-.7.6-.6 1.6.1 2.1.7.5 1.6.4 2.2-.2l1.6-1.6"/></svg>',
    id: '<svg viewBox="0 0 24 24"><rect x="3" y="5.5" width="18" height="13" rx="2"/><circle cx="8.4" cy="11" r="1.9"/><path d="M5.6 15.8c.5-1.5 1.6-2.2 2.8-2.2s2.3.7 2.8 2.2"/><path d="M14 9.8h4.5M14 13h4.5"/></svg>',
    cash: '<svg viewBox="0 0 24 24"><rect x="3" y="7" width="18" height="10" rx="1.6"/><circle cx="12" cy="12" r="2.6"/><path d="M6 10v4M18 10v4"/></svg>',
    search: '<svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="5.5"/><path d="M14.8 14.8 20 20"/></svg>',
    escort: '<svg viewBox="0 0 24 24"><circle cx="9" cy="6" r="2.4"/><path d="M9 9v6l-2 5M9 15l2.5 5M9 10.5 13 12"/><path d="M15.5 12H21m0 0-2.4-2.4M21 12l-2.4 2.4"/></svg>',
    back: '<svg viewBox="0 0 24 24"><path d="M14.5 6 8 12l6.5 6"/></svg>',
    hello: '<svg viewBox="0 0 24 24"><path d="M8 12V5.8a1.3 1.3 0 0 1 2.6 0V11M10.6 11V4.8a1.3 1.3 0 0 1 2.6 0V11M13.2 11V6a1.3 1.3 0 0 1 2.6 0v7.5"/><path d="M8 12l-1.6-1.8a1.4 1.4 0 0 0-2.1 1.8l3.5 5.5A5.5 5.5 0 0 0 12.5 20c3 0 3.9-1.9 3.9-4.5"/></svg>',
    license: '<svg viewBox="0 0 24 24"><rect x="3" y="5.5" width="18" height="13" rx="2"/><path d="M6.5 9.5h5M6.5 12.5h4M6.5 15.5h5.5"/><circle cx="16.8" cy="11" r="1.8"/><path d="M14.8 15.6c.4-1.2 1.2-1.7 2-1.7s1.6.5 2 1.7"/></svg>',
    shield: '<svg viewBox="0 0 24 24"><path d="M12 3.5 19 6v5.4c0 4.2-2.6 7.5-7 9.1-4.4-1.6-7-4.9-7-9.1V6l7-2.5z"/><path d="M9 12l2 2 4-5"/></svg>',
    admin: '<svg viewBox="0 0 24 24"><path d="M12 3.5 19 6v5.4c0 4.2-2.6 7.5-7 9.1-4.4-1.6-7-4.9-7-9.1V6l7-2.5z"/><path d="M9 12l2 2 4-5"/></svg>',
    radio: '<svg viewBox="0 0 24 24"><rect x="7" y="8" width="10" height="12" rx="2"/><path d="M10 8V5h4v3M10 12h4M10 15h2"/><circle cx="14.5" cy="16" r="1"/></svg>',
    vehicle: '<svg viewBox="0 0 24 24"><path d="M5 14l1.4-4.2A2.6 2.6 0 0 1 8.9 8h6.2a2.6 2.6 0 0 1 2.5 1.8L19 14"/><rect x="4" y="13" width="16" height="5" rx="1.6"/><circle cx="7.5" cy="18" r="1.5"/><circle cx="16.5" cy="18" r="1.5"/></svg>',
    house: '<svg viewBox="0 0 24 24"><path d="M4 11.5 12 5l8 6.5"/><path d="M6.5 10.5V19h11v-8.5"/><path d="M10 19v-5h4v5"/></svg>',
    key: '<svg viewBox="0 0 24 24"><circle cx="8" cy="12" r="3.5"/><path d="M11.5 12H21l-2 2 2 2"/></svg>',
    dot: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="2.5"/></svg>'
};

// -------------------------------------------------------------------------
// Overhead labels — element pool so per-frame updates never re-create DOM.
// -------------------------------------------------------------------------
const pool = [];

function getLabelEl(i) {
    if (pool[i]) return pool[i];
    const el = document.createElement('div');
    el.className = 'plabel';
    el.innerHTML = '<div class="pstatus"></div><div class="pname"></div><div class="pid"></div>';
    el._status = el.querySelector('.pstatus');
    el._name = el.querySelector('.pname');
    el._id = el.querySelector('.pid');
    labelsRoot.appendChild(el);
    pool[i] = el;
    return el;
}

function renderLabels(labels) {
    const count = labels ? labels.length : 0;

    for (let i = 0; i < count; i++) {
        const data = labels[i];
        const el = getLabelEl(i);

        el.style.display = 'block';
        el.style.left = (data.x * 100) + '%';
        el.style.top = (data.y * 100) + '%';
        el.style.fontSize = (LABEL_BASE_PX * (data.s || 1)) + 'px';

        const status = data.status || '';
        if (el._lastStatus !== status) {
            el._status.textContent = status;
            el._status.style.display = status ? 'block' : 'none';
            el._lastStatus = status;
        }

        if (el._lastName !== data.name) { el._name.textContent = data.name; el._lastName = data.name; }
        if (el._lastId !== data.id) { el._id.textContent = data.id; el._lastId = data.id; }

        const isTarget = !!data.t;
        if (el._lastTarget !== isTarget) {
            el.classList.toggle('target', isTarget);
            el._lastTarget = isTarget;
        }

        const isAdmin = !!data.admin;
        if (el._lastAdmin !== isAdmin) {
            el.classList.toggle('admin', isAdmin);
            el._lastAdmin = isAdmin;
        }
    }

    for (let i = count; i < pool.length; i++) {
        if (pool[i]) pool[i].style.display = 'none';
    }
}

// G prompt is its own channel now, so nothing else can hide/flicker it.
function renderGPrompt(g) {
    if (g && typeof g.x === 'number') {
        gPrompt.style.left = (g.x * 100) + '%';
        gPrompt.style.top = (g.y * 100) + '%';
        gPrompt.classList.remove('hidden');
    } else {
        gPrompt.classList.add('hidden');
    }
}

// -------------------------------------------------------------------------
// Hex menu
// -------------------------------------------------------------------------
function buildHexMenu(data) {
    titleName.textContent = data.title || 'Stranger';
    titleId.textContent = data.subtitle || '';
    hintText.textContent = data.hint || '';

    hexGrid.innerHTML = '';

    const options = data.options || [];
    const perRow = 3;
    let row = null;
    let rowIndex = -1;

    options.forEach((opt, i) => {
        if (i % perRow === 0) {
            rowIndex++;
            row = document.createElement('div');
            row.className = 'hex-row' + (rowIndex % 2 === 1 ? ' offset' : '');
            hexGrid.appendChild(row);
        }

        const hex = document.createElement('div');
        hex.className = 'hex';
        hex.style.animationDelay = (i * 28) + 'ms';
        hex.innerHTML =
            '<div class="num">' + (i + 1) + '</div>' +
            '<div class="icon">' + (ICONS[opt.icon] || ICONS.dot) + '</div>' +
            '<div class="lbl">' + escapeHtml(opt.label || '') + '</div>';
        hex.addEventListener('click', () => post('selectOption', { index: i + 1 }));
        row.appendChild(hex);
    });

    menuVisible = true;
    hexMenu.classList.remove('hidden');
}

function closeHexMenu() {
    menuVisible = false;
    hexMenu.classList.add('hidden');
    hexGrid.innerHTML = '';
}

let menuVisible = false;

const RESOURCE = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'cm-playerdata';

function post(name, payload) {
    fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
    }).catch(() => {});
}

// Keyboard: 1-9 select, ESC close.
window.addEventListener('keydown', (e) => {
    if (!menuVisible) return;

    if (e.key === 'Escape') {
        e.preventDefault();
        post('closeMenu');
        return;
    }

    const num = parseInt(e.key, 10);
    if (num >= 1 && num <= 9) {
        e.preventDefault();
        post('selectOption', { index: num });
    }
});

// Right mouse button: back to the previous page.
window.addEventListener('mousedown', (e) => {
    if (!menuVisible) return;
    if (e.button === 2) {
        e.preventDefault();
        post('backMenu');
    }
});

// Never show the browser context menu inside the game.
window.addEventListener('contextmenu', (e) => e.preventDefault());

function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
}

// -------------------------------------------------------------------------
// Message router
// -------------------------------------------------------------------------
window.addEventListener('message', (event) => {
    const msg = event.data || {};

    switch (msg.action) {
        case 'labels':
            renderLabels(msg.labels);
            // Backward-compat: if an older push still bundles g on this channel, honor it.
            if (Object.prototype.hasOwnProperty.call(msg, 'g')) renderGPrompt(msg.g);
            break;
        case 'gprompt':
            renderGPrompt(msg.g);
            break;
        case 'openRadial':
            buildHexMenu(msg);
            break;
        case 'closeRadial':
            closeHexMenu();
            break;
    }
});

// -------------------------------------------------------------------------
// Death screen: countdown driven locally from remainingMs sent by Lua.
// -------------------------------------------------------------------------
const deathScreen = document.getElementById('deathscreen');
const deathMini = document.getElementById('deathmini');
const dsTimer = document.getElementById('ds-timer');
const dmTimer = document.getElementById('dm-timer');
const dsKilledBy = document.getElementById('ds-killedby');
const dsOptions = document.getElementById('ds-options');
const dsStatus = document.getElementById('ds-status');

let deathDeadline = 0;
let deathTick = null;
let deathMode = 'screen'; // 'screen' | 'mini'
let deathExpiredPosted = false;

function fmtTime(ms) {
    if (ms < 0) ms = 0;
    const total = Math.ceil(ms / 1000);
    const m = Math.floor(total / 60);
    const s = total % 60;
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
}

function tickDeath() {
    const remaining = deathDeadline - Date.now();
    const text = fmtTime(remaining);
    if (deathMode === 'mini') { dmTimer.textContent = text; }
    else { dsTimer.textContent = text; }
    if (remaining <= 0) {
        if (!deathExpiredPosted) {
            deathExpiredPosted = true;
            post('deathExpired');
        }
        if (deathTick) {
            clearInterval(deathTick);
            deathTick = null;
        }
    }
}

function openDeathScreen(msg) {
    deathMode = 'screen';
    deathExpiredPosted = false;
    deathDeadline = Date.now() + (msg.remainingMs || 120000);

    if (msg.killedBy && msg.killedBy.charId) {
        dsKilledBy.innerHTML = 'KILLED BY ' + escapeHtml(String(msg.killedBy.label || 'Stranger').toUpperCase()) +
            ' <span class="ds-kb-id">&bull; ID: ' + escapeHtml(String(msg.killedBy.charId)) + '</span>';
        dsKilledBy.classList.remove('hidden');
    } else {
        dsKilledBy.classList.add('hidden');
    }

    dsOptions.classList.remove('hidden');
    dsStatus.classList.add('hidden');
    deathMini.classList.add('hidden');
    deathScreen.classList.remove('hidden');

    if (deathTick) clearInterval(deathTick);
    deathTick = setInterval(tickDeath, 250);
    tickDeath();
}

function ambulanceMode(msg) {
    // Overlay goes away, mini pill takes over; player is still dead.
    deathMode = 'mini';
    deathExpiredPosted = false;
    deathDeadline = Date.now() + (msg.remainingMs || 0);
    deathScreen.classList.add('hidden');
    deathMini.classList.remove('hidden');
    tickDeath();
}

function deathChoice(msg) {
    if (msg.choice === 'die') {
        // No time change, screen stays: options are simply no longer available.
        dsOptions.classList.add('hidden');
        dsStatus.textContent = 'WAITING FOR BLEED OUT...';
        dsStatus.classList.remove('hidden');
    }
}

function closeDeathScreen() {
    deathScreen.classList.add('hidden');
    deathMini.classList.add('hidden');
    deathExpiredPosted = false;
    if (deathTick) { clearInterval(deathTick); deathTick = null; }
}

window.addEventListener('message', (event) => {
    const msg = event.data || {};
    switch (msg.action) {
        case 'openDeathScreen': openDeathScreen(msg); break;
        case 'ambulanceMode': ambulanceMode(msg); break;
        case 'deathChoice': deathChoice(msg); break;
        case 'closeDeathScreen': closeDeathScreen(); break;
    }
});

// -------------------------------------------------------------------------
// Passport-style ID card
// -------------------------------------------------------------------------
const idCard = document.getElementById('idcard');
let idCardTimer = null;

function showIdCard(msg) {
    const card = msg.card || {};
    document.getElementById('idc-name').textContent = card.name || '—';
    document.getElementById('idc-id').textContent = (card.charId !== undefined && card.charId !== null) ? String(card.charId) : '—';
    document.getElementById('idc-dob').textContent = card.dob || '—';

    let lic = 'NONE';
    if (Array.isArray(card.licenses) && card.licenses.length > 0) {
        lic = card.licenses.map(l => String(l).toUpperCase()).join(' • ');
    }
    document.getElementById('idc-lic').textContent = lic;

    idCard.classList.remove('hidden');
    if (idCardTimer) clearTimeout(idCardTimer);
    idCardTimer = setTimeout(() => idCard.classList.add('hidden'), msg.duration || 10000);
}

window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'showIdCard') showIdCard(msg);
});

// Death screen buttons (cursor is enabled while the screen is up)
document.getElementById('ds-ambulance').addEventListener('click', () => post('deathAmbulance'));
document.getElementById('ds-die').addEventListener('click', () => post('deathDie'));
