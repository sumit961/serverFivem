// cm-hud/ui/app.js

// ========== EXTENSIBLE HUD MODULES ==========
// Add new modules here in the future
const HUD_MODULES = {
    topRight: {
        id: 'hud-top-right',
        render: renderTopRight
    },
    bottomLeft: {
        id: 'hud-bottom-left', 
        render: renderBottomLeft
    },
    bottomRight: {
        id: 'hud-bottom-right',
        render: renderBottomRight
    },
    leftKeys: {
        id: 'hud-left-keys',
        render: renderLeftKeys
    },
    death: {
        id: 'hud-death',
        render: renderDeath
    },
    vehicle: {
        id: 'hud-vehicle',
        render: renderVehicle
    }
};

// ========== STATE ==========
let state = {
    hudVisible: false,
    // Server / Identity
    serverName: 'CM-RP',
    serverId: '',
    characterName: 'Unknown',
    level: 1,
    onlinePlayers: 0,
    
    // Money
    cash: 0,
    bank: 0,
    
    // Health / Armor
    health: 200,
    maxHealth: 200,
    armor: 0,
    maxArmor: 100,
    
    // Location
    area: 'Unknown',
    street: 'Unknown',
    
    // Time
    clock: '00:00',
    date: '01.01.2025',
    
    // Death
    isDead: false,
    deathTime: 30,

    // Vehicle
    vehicle: {
        visible: false,
        speed: 0,
        unit: 'KM/H',
        rpm: 0,
        gear: 'N',
        fuel: 0,
        engine: 0,
        locked: false,
        seatbelt: false,
        cruise: false
    },
    
    // Keys (for visual feedback)
    keys: {
        N: false, M: false, K: false, I: false,
        L: false, SIX: false, CURSOR: false
    },

    mouseOpen: false,
    adminOpen: false,
    externalHidden: false,
    hudSettings: null,
    
    // Notifications queue
    notifications: [],

};

let deathInterval = null;


// ========== HUD ADMIN SETTINGS ==========
const HUD_DEFAULT_SETTINGS = {
    speedoStyle: 1,
    speedUnit: 'KM/H',
    theme: 'cyan',
    uiScale: 1,
    speedoScale: 1,
    locationOffsetX: 0,
    locationOffsetY: 0,
    speedoOffsetX: 0,
    speedoOffsetY: 0,
    showTopRight: true,
    showLocation: true,
    showLeftKeys: true,
    showTime: true,
    showSpeedometer: true,
    compactMode: false,
    previewVehicle: false
};

const HUD_SPEEDO_STYLES = [
    { id: 1, name: 'Fast V2 Cyan', desc: 'Imported Fast HUD V2 base' },
    { id: 2, name: 'Fast V2 Dark', desc: 'Darker glow' },
    { id: 3, name: 'Classic Ring', desc: 'Round clean' },
    { id: 4, name: 'Digital Block', desc: 'Simple RP' },
    { id: 5, name: 'Neon Arc', desc: 'Cyan racing' },
    { id: 6, name: 'Split RPM/Fuel', desc: 'Two side bars' },
    { id: 7, name: 'Bike Compact', desc: 'Small road UI' },
    { id: 8, name: 'Racing Dial', desc: 'Large tach' },
    { id: 9, name: 'Electric Segments', desc: 'EV style' },
    { id: 10, name: 'Boat Gauge', desc: 'Marine style' },
    { id: 11, name: 'Aircraft Stack', desc: 'Pilot style' },
    { id: 12, name: 'Box Digital', desc: 'Modern boxed' },
    { id: 13, name: 'Thin Arc', desc: 'Minimal' },
    { id: 14, name: 'Clean Text', desc: 'Lowest clutter' },
    { id: 15, name: 'AK4Y Speedo V1', desc: 'Imported AK4Y car style', image: 'assets/huds/ak4y_spev1.png', group: 'AK4Y' },
    { id: 16, name: 'AK4Y Speedo V2', desc: 'Imported AK4Y round dial', image: 'assets/huds/ak4y_spev2.png', group: 'AK4Y' },
    { id: 17, name: 'AK4Y Speedo V3', desc: 'Imported AK4Y bar tach', image: 'assets/huds/ak4y_spev3.png', group: 'AK4Y' },
    { id: 18, name: 'AK4Y Speedo V4', desc: 'Imported AK4Y hex style', image: 'assets/huds/ak4y_spev4.png', group: 'AK4Y' },
    { id: 19, name: 'AK4Y Speedo V5', desc: 'Imported AK4Y minimal digital', image: 'assets/huds/ak4y_spev5.png', group: 'AK4Y' },
    { id: 20, name: 'AK4Y Speedo V6', desc: 'Imported AK4Y dual cluster', image: 'assets/huds/ak4y_spev6.png', group: 'AK4Y' },
    { id: 21, name: 'AK4Y Bike', desc: 'Imported bike speedometer', group: 'AK4Y' },
    { id: 22, name: 'AK4Y Boat', desc: 'Imported boat speedometer', group: 'AK4Y' },
    { id: 23, name: 'AK4Y Plane', desc: 'Imported plane speedometer', group: 'AK4Y' },
    { id: 24, name: 'JG Modern', desc: 'JG HUD land style', group: 'JG' },
    { id: 25, name: 'JG Modern Pro', desc: 'JG HUD pro land style', group: 'JG' },
    { id: 26, name: 'JG Futuristic', desc: 'JG HUD futuristic style', group: 'JG' },
    { id: 27, name: 'JG Analogue', desc: 'JG HUD round analogue style', group: 'JG' },
    { id: 28, name: 'JG Bold', desc: 'JG HUD bold digital style', group: 'JG' },
    { id: 29, name: 'JG Minimal', desc: 'JG HUD minimal style', group: 'JG' },
    { id: 30, name: 'Black Circle MPH', desc: 'Same style as requested screenshot', group: 'Requested' }
];

const HUD_THEMES = {
    cyan:   { label: 'Blue Cyan', color: '#31e6ff', rgb: '49,230,255' },
    blue:   { label: 'Blue',      color: '#3d7dff', rgb: '61,125,255' },
    green:  { label: 'Green',     color: '#3df71f', rgb: '61,247,31' },
    purple: { label: 'Purple',    color: '#b05cff', rgb: '176,92,255' },
    yellow: { label: 'Yellow',    color: '#ffd54a', rgb: '255,213,74' },
    red:    { label: 'Red',       color: '#ff4d4d', rgb: '255,77,77' }
};

function nuiFetch(name, payload = {}) {
    const resource = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'cm-hud';
    return fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload)
    }).catch(() => null);
}

function sanitizeHudSettings(settings) {
    const next = { ...HUD_DEFAULT_SETTINGS, ...(settings || {}) };
    next.speedoStyle = Math.max(1, Math.min(HUD_SPEEDO_STYLES.length, parseInt(next.speedoStyle, 10) || 1));
    next.speedUnit = String(next.speedUnit || 'KM/H').toUpperCase() === 'MPH' ? 'MPH' : 'KM/H';
    next.theme = HUD_THEMES[next.theme] ? next.theme : 'cyan';
    next.uiScale = Math.max(0.75, Math.min(1.35, Number(next.uiScale) || 1));
    next.speedoScale = Math.max(0.70, Math.min(1.40, Number(next.speedoScale) || 1));
    next.locationOffsetX = Math.max(-500, Math.min(500, parseInt(next.locationOffsetX, 10) || 0));
    next.locationOffsetY = Math.max(-300, Math.min(300, parseInt(next.locationOffsetY, 10) || 0));
    next.speedoOffsetX = Math.max(-500, Math.min(500, parseInt(next.speedoOffsetX, 10) || 0));
    next.speedoOffsetY = Math.max(-300, Math.min(300, parseInt(next.speedoOffsetY, 10) || 0));
    ['showTopRight','showLocation','showLeftKeys','showTime','showSpeedometer','compactMode','previewVehicle'].forEach(k => {
        next[k] = next[k] === true;
    });
    return next;
}

function getHudSettings() {
    state.hudSettings = sanitizeHudSettings(state.hudSettings);
    return state.hudSettings;
}

function setHudSettings(settings, persist = false) {
    state.hudSettings = sanitizeHudSettings({ ...getHudSettings(), ...(settings || {}) });
    applyHudSettings();
    updateAll();
    if (persist) nuiFetch('hudAdminSave', { settings: state.hudSettings });
}

function applyHudSettings() {
    const cfg = getHudSettings();
    const root = document.documentElement;
    const body = document.body;
    const theme = HUD_THEMES[cfg.theme] || HUD_THEMES.cyan;

    root.style.setProperty('--cm-accent', theme.color);
    root.style.setProperty('--cm-accent-rgb', theme.rgb || '49,230,255');
    root.style.setProperty('--cm-user-scale', cfg.uiScale.toFixed(2));
    root.style.setProperty('--cm-speedo-user-scale', cfg.speedoScale.toFixed(2));
    root.style.setProperty('--cm-location-offset-x', `${cfg.locationOffsetX}px`);
    root.style.setProperty('--cm-location-offset-y', `${cfg.locationOffsetY}px`);
    root.style.setProperty('--cm-speedo-offset-x', `${cfg.speedoOffsetX}px`);
    root.style.setProperty('--cm-speedo-offset-y', `${cfg.speedoOffsetY}px`);

    body.classList.toggle('cm-hide-top-right', !cfg.showTopRight);
    body.classList.toggle('cm-hide-location', !cfg.showLocation);
    body.classList.toggle('cm-hide-left-keys', !cfg.showLeftKeys);
    body.classList.toggle('cm-hide-time', !cfg.showTime);
    body.classList.toggle('cm-hide-speedo', !cfg.showSpeedometer);
    body.classList.toggle('cm-compact-mode', !!cfg.compactMode);
    body.classList.toggle('cm-hud-admin-open', !!state.adminOpen);
    Object.keys(HUD_THEMES).forEach(t => body.classList.toggle(`cm-theme-${t}`, cfg.theme === t));
}

function renderHudAdmin() {
    const el = document.getElementById('hud-admin');
    if (!el) return;
    const cfg = getHudSettings();
    const makeSpeedoCard = (item) => {
        const isAk4y = item.group === 'AK4Y' || item.id >= 15 && item.id <= 23;
        const isJg = item.group === 'JG' || item.id >= 24;
        const preview = item.image
            ? `<span class="ak4y-card-img"><img src="${escapeHtml(item.image)}" alt="${escapeHtml(item.name)}"></span>`
            : isJg
                ? `<span class="mini-speedo mini-jg mini-${item.id}"><i></i><b>${item.id}</b><em></em></span>`
                : `<span class="mini-speedo mini-${item.id}"><i></i><b>${item.id}</b><em></em></span>`;
        return `
            <button class="hud-admin-speedo-card ${cfg.speedoStyle === item.id ? 'active' : ''} ${isAk4y ? 'ak4y-imported' : ''} ${isJg ? 'jg-imported' : ''}" data-speedo="${item.id}">
                ${preview}
                <strong>${escapeHtml(item.name)}</strong>
                <small>${escapeHtml(item.desc)}</small>
            </button>
        `;
    };
    const makeSpeedoGroup = (title, subtitle, ids) => {
        const cards = HUD_SPEEDO_STYLES.filter(item => ids.includes(item.id)).map(makeSpeedoCard).join('');
        return `<div class="speedo-admin-group"><div class="speedo-group-title"><b>${title}</b><span>${subtitle}</span></div><div class="speedo-card-grid">${cards}</div></div>`;
    };
    const styleCards = [
        makeSpeedoGroup('CM / Fast Speedometers', 'Selectable car speedos #1 - #14', Array.from({ length: 14 }, (_, i) => i + 1)),
        makeSpeedoGroup('AK4Y Speedometers', 'Imported styles #15 - #23', Array.from({ length: 9 }, (_, i) => i + 15)),
        makeSpeedoGroup('JG HUD Speedometers', 'New JG land styles #24 - #29', Array.from({ length: 6 }, (_, i) => i + 24)),
        makeSpeedoGroup('Requested Speedometer', 'Black circular RPM style #30', [30])
    ].join('');

    el.classList.toggle('hidden', !state.adminOpen);
    el.innerHTML = `
        <div class="hud-admin-shell">
            <div class="hud-admin-sidebar">
                <div class="hud-admin-logo">CM</div>
                <div class="hud-admin-title">HUD ADMIN</div>
                <div class="hud-admin-sub">/hud admin</div>
                <button class="hud-admin-close" data-admin-action="close">×</button>
            </div>

            <div class="hud-admin-content">
                <div class="hud-admin-header">
                    <div>
                        <h2>HUD Customiser</h2>
                        <p>Change speedometer, scale, modules and colours. Settings save locally for this player.</p>
                    </div>
                    <div class="hud-admin-header-actions">
                        <button class="hud-admin-pill ${cfg.previewVehicle ? 'active' : ''}" data-admin-action="preview">${cfg.previewVehicle ? 'Preview On' : 'Preview Speedo'}</button>
                        <button class="hud-admin-pill danger" data-admin-action="reset">Reset</button>
                    </div>
                </div>

                <div class="hud-admin-grid">
                    <section class="hud-admin-panel wide">
                        <div class="panel-head"><h3>Speedometer</h3><span>circular · cyan</span></div>
                        <p style="color:rgba(185,222,234,.7);font-size:13px;line-height:1.5;padding:6px 2px;">
                          Cars use the circular gauge. Aircraft, boats and bikes automatically switch to their own dedicated displays.
                        </p>
                    </section>

                    <section class="hud-admin-panel">
                        <div class="panel-head"><h3>Display</h3><span>modules</span></div>
                        ${adminToggle('showTopRight', 'Top-right money / ID', cfg.showTopRight)}
                        ${adminToggle('showLocation', 'Location near minimap', cfg.showLocation)}
                        ${adminToggle('showLeftKeys', 'Left quick keys', cfg.showLeftKeys)}
                        ${adminToggle('showTime', 'Time / date', cfg.showTime)}
                        ${adminToggle('showSpeedometer', 'Vehicle speedometer', cfg.showSpeedometer)}
                        ${adminToggle('compactMode', 'Compact mode', cfg.compactMode)}
                    </section>

                    <section class="hud-admin-panel">
                        <div class="panel-head"><h3>Theme</h3><span>${escapeHtml(HUD_THEMES[cfg.theme].label)}</span></div>
                        <div class="theme-dots">
                            ${Object.entries(HUD_THEMES).map(([key, val]) => `<button class="theme-dot ${cfg.theme === key ? 'active' : ''}" data-theme="${key}" style="--dot:${val.color}" title="${escapeHtml(val.label)}"></button>`).join('')}
                        </div>
                        <div class="unit-row">
                            <button class="unit-btn ${cfg.speedUnit === 'KM/H' ? 'active' : ''}" data-unit="KM/H">KM/H</button>
                            <button class="unit-btn ${cfg.speedUnit === 'MPH' ? 'active' : ''}" data-unit="MPH">MPH</button>
                        </div>
                    </section>

                    <section class="hud-admin-panel wide">
                        <div class="panel-head"><h3>Scale & Position</h3><span>responsive safe-zone</span></div>
                        ${adminRange('uiScale', 'HUD scale', cfg.uiScale, 0.75, 1.35, 0.01)}
                        ${adminRange('speedoScale', 'Speedometer scale', cfg.speedoScale, 0.70, 1.40, 0.01)}
                        ${adminRange('locationOffsetX', 'Location X offset', cfg.locationOffsetX, -500, 500, 1)}
                        ${adminRange('locationOffsetY', 'Location Y offset', cfg.locationOffsetY, -300, 300, 1)}
                        ${adminRange('speedoOffsetX', 'Speedometer X offset', cfg.speedoOffsetX, -500, 500, 1)}
                        ${adminRange('speedoOffsetY', 'Speedometer Y offset', cfg.speedoOffsetY, -300, 300, 1)}
                    </section>
                </div>
            </div>
        </div>`;

    bindHudAdminEvents();
}

function adminToggle(key, label, checked) {
    return `
        <label class="admin-toggle">
            <span>${escapeHtml(label)}</span>
            <input type="checkbox" data-setting="${key}" ${checked ? 'checked' : ''}>
            <i></i>
        </label>`;
}

function adminRange(key, label, value, min, max, step) {
    return `
        <label class="admin-range">
            <span>${escapeHtml(label)} <b>${value}</b></span>
            <input type="range" min="${min}" max="${max}" step="${step}" value="${value}" data-setting="${key}">
        </label>`;
}

function bindHudAdminEvents() {
    const el = document.getElementById('hud-admin');
    if (!el) return;

    el.querySelectorAll('[data-speedo]').forEach(btn => {
        btn.addEventListener('click', () => {
            setHudSettings({ speedoStyle: Number(btn.dataset.speedo) }, true);
            renderHudAdmin();
        });
    });

    el.querySelectorAll('[data-theme]').forEach(btn => {
        btn.addEventListener('click', () => {
            setHudSettings({ theme: btn.dataset.theme }, true);
            renderHudAdmin();
        });
    });

    el.querySelectorAll('[data-unit]').forEach(btn => {
        btn.addEventListener('click', () => {
            setHudSettings({ speedUnit: btn.dataset.unit }, true);
            renderHudAdmin();
        });
    });

    el.querySelectorAll('input[data-setting]').forEach(input => {
        const handler = () => {
            const key = input.dataset.setting;
            const value = input.type === 'checkbox' ? input.checked : Number(input.value);
            setHudSettings({ [key]: value }, true);
            const labelVal = input.closest('.admin-range')?.querySelector('b');
            if (labelVal) labelVal.textContent = value;
        };
        input.addEventListener(input.type === 'range' ? 'input' : 'change', handler);
    });

    el.querySelectorAll('[data-admin-action]').forEach(btn => {
        btn.addEventListener('click', () => {
            const action = btn.dataset.adminAction;
            if (action === 'close') {
                state.adminOpen = false;
                applyHudSettings();
                el.classList.add('hidden');
                nuiFetch('hudAdminClose', {});
            } else if (action === 'reset') {
                state.hudSettings = sanitizeHudSettings({});
                applyHudSettings();
                updateAll();
                nuiFetch('hudAdminReset', {});
                renderHudAdmin();
            } else if (action === 'preview') {
                const next = !getHudSettings().previewVehicle;
                setHudSettings({ previewVehicle: next }, true);
                nuiFetch('hudAdminPreview', { enabled: next });
                renderHudAdmin();
            }
        });
    });
}

// ========== RENDER FUNCTIONS ==========

function renderTopRight() {
    const el = document.getElementById(HUD_MODULES.topRight.id);
    if (!el) return;

    // Grand RP style top right
    el.innerHTML = `
        <div class="server-header-container">
            <div class="server-info-col">
                <div class="server-brand">${state.serverName}</div>
                <div class="server-stats">
                    <span class="stat-id">ID: ${state.serverId || '-'}</span>
                    <span class="stat-players">👤 ${state.onlinePlayers}</span>
                </div>
            </div>
            <div class="level-ribbon">
                <span>${state.level}</span>
            </div>
        </div>
        
        <div class="money-block-new">
            <div class="money-cash-new">$${formatMoney(state.cash)}</div>
            <div class="money-bank-new">🏦 $${formatMoney(state.bank)}</div>
        </div>

        <div class="voice-radio-keys">
            <div class="vr-key"><span class="key-circle">N</span> 🎤</div>
            <div class="vr-key"><span class="key-circle">O</span> 📻</div>
        </div>
    `;
}

function renderBottomLeft() {
    const el = document.getElementById(HUD_MODULES.bottomLeft.id);
    if (!el) return;

    // Location only. No health/armor bars and no black background.
    el.innerHTML = `
        <div class="location-box location-no-bg" data-dir="${escapeHtml(state.dir || 'N')}">
            <div class="location-lines">
                <div class="location-area">${escapeHtml(state.area)}</div>
                <div class="location-street">${escapeHtml(state.street)}</div>
            </div>
        </div>
    `;
}

function renderLeftKeys() {
    const el = document.getElementById(HUD_MODULES.leftKeys.id);
    if (!el) return;

    const items = [
        { key: 'K', label: 'Phone', action: 'phone', icon: '▯' },
        { key: 'M', label: 'Menu', action: 'menu', icon: '▦' },
        { key: 'I', label: 'Inventory', action: 'inventory', icon: '▣' },
        { key: '6', label: 'Emote', action: 'emote', icon: '♞' },
        { key: 'L', label: 'Lock Car', action: 'lock', icon: '🔒' },
        { key: '~', label: 'Mouse', action: 'close', icon: '➤' }
    ];

    el.classList.toggle('mouse-open', !!state.mouseOpen);
    el.innerHTML = `
        <div class="left-key-guide">
            ${items.map(item => `
                <button class="left-key-item" data-action="${item.action}" title="${item.label}">
                    <span class="left-key-icon">${item.icon}</span>
                    <span class="left-key-circle">${item.key}</span>
                    <span class="left-key-label">${item.label}</span>
                </button>
            `).join('')}
        </div>
    `;

    el.querySelectorAll('.left-key-item').forEach(btn => {
        btn.addEventListener('click', () => {
            const action = btn.getAttribute('data-action');
            fetch(`https://${GetParentResourceName()}/hudQuickAction`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ action })
            });
        });
    });
}
function renderBottomRight() {
    const el = document.getElementById(HUD_MODULES.bottomRight.id);
    if (!el) return;

    // Horizontal layout under the speedometer
    el.innerHTML = `
        <div class="bottom-status-row">
            <div class="status-time-box">
                <span class="icon">🕐</span> ${state.clock}
            </div>
            <div class="status-date-box">${state.date}</div>
        </div>
    `;
}

function renderDeath() {
    const el = document.getElementById(HUD_MODULES.death.id);
    if (!el) return;

    if (!state.isDead) {
        el.classList.add('hidden');
        return;
    }

    el.classList.remove('hidden');
    el.innerHTML = `
        <div class="death-content">
            <div class="death-skull">💀</div>
            <div class="death-title">YOU ARE UNCONSCIOUS</div>
            <div class="death-subtitle" id="death-timer-text">
                ${state.deathTime > 0 ? `Respawn available in ${state.deathTime}s` : 'Press E to respawn'}
            </div>
            ${state.deathTime <= 0 ? '<div class="death-key">PRESS E</div>' : ''}
        </div>
    `;
}

const vehicleEls = {
    container: null, speed: null, unit: null, fuel: null, fuelRing: null, rpmRing: null,
    seatbelt: null, cruise: null, gear: null, lock: null, ready: false
};

// ===================== VEHICLE HUD (5 renderers) =====================
const IND_ICONS = {
    left:  '<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    right: '<svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    hazard:'<svg viewBox="0 0 24 24"><path d="M12 4L3 19h18L12 4z" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
    low:   '<svg viewBox="0 0 24 24"><path d="M10 7c3 0 5 2.2 5 5s-2 5-5 5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M3 9l5 1M3 12.5l5 0M3 16l5-1" stroke="currentColor" stroke-width="1.6"/></svg>',
    high:  '<svg viewBox="0 0 24 24"><path d="M10 7c3 0 5 2.2 5 5s-2 5-5 5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M2 9h6M2 12.5h6M2 16h6" stroke="currentColor" stroke-width="1.6"/></svg>',
    cruise:'<svg viewBox="0 0 24 24"><circle cx="12" cy="13" r="7.4" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 13l3.4-3.4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    belt:  '<svg viewBox="0 0 24 24"><circle cx="12" cy="6" r="2.4" fill="none" stroke="currentColor" stroke-width="2"/><path d="M7 21L18 9M8.5 12.5L15 19" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    engine:'<svg viewBox="0 0 24 24"><path d="M7 8h4l1.6 2H17a1.6 1.6 0 011.6 1.6V16a1.6 1.6 0 01-1.6 1.6H8.4L6 15H4v-4h2.4L7 8z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M9 5.5h4" stroke="currentColor" stroke-width="1.8"/></svg>',
    fuel:  '<svg viewBox="0 0 24 24"><rect x="5" y="5" width="9" height="14" rx="1.4" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M7.5 8h4M16 9l2.4 2.4V17a1.6 1.6 0 01-3.2 0v-6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    anchor:'<svg viewBox="0 0 24 24"><circle cx="12" cy="6" r="2.2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 8.5V20M5 14c0 3.6 3 6 7 6s7-2.4 7-6M4 13.5l2.4 2.2M20 13.5l-2.4 2.2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>'
};

function indicatorBar(v) {
    const items = [
        { icon: 'left',  on: false },
        { icon: 'hazard', on: false },
        { icon: 'low',   on: v.lights === 1, color: '#38e659' },
        { icon: 'high',  on: v.lights === 2, color: '#31a8ff' },
        { icon: 'cruise', on: !!v.cruise, color: '#31e6ff' },
        { icon: 'belt',  on: !v.seatbelt, color: '#ff5b5b', hideOn: v.vehType !== 'car' && v.vehType !== 'electric' },
        { icon: 'right', on: false }
    ];
    return `<div class="veh-ind-bar">${items.filter(i => !i.hideOn).map(i =>
        `<span class="veh-ind ${i.on ? 'on' : ''}" style="${i.on && i.color ? `color:${i.color}` : ''}">${IND_ICONS[i.icon]}</span>`).join('')}</div>`;
}

function arcPath(cx, cy, r, a0, a1) {
    const rad = a => (a - 90) * Math.PI / 180;
    const x0 = cx + r * Math.cos(rad(a0)), y0 = cy + r * Math.sin(rad(a0));
    const x1 = cx + r * Math.cos(rad(a1)), y1 = cy + r * Math.sin(rad(a1));
    return `M ${x0.toFixed(1)} ${y0.toFixed(1)} A ${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`;
}


function renderVehSelectable(v, styleId) {
    styleId = Math.max(2, Math.min(14, parseInt(styleId, 10) || 2));
    const speed = Math.max(0, Math.min(999, Math.floor(Number(v.speed) || 0)));
    const rpm = Math.max(0, Math.min(100, Number(v.rpm) || 0));
    const fuel = Math.max(0, Math.min(100, Number(v.fuel ?? 0) || 0));
    const engine = Math.max(0, Math.min(100, Number(v.engine ?? 100) || 0));
    const unit = escapeHtml(v.unit || getHudSettings().speedUnit || 'KM/H');
    const gear = escapeHtml(String(v.gear ?? 'N'));
    const speedText = String(speed).padStart(3, '0');
    const rpmDeg = Math.round((rpm / 100) * 270);
    const fuelDeg = Math.round((fuel / 100) * 270);
    const mainPercent = Math.min(100, Math.max(0, speed / (unit === 'MPH' ? 180 : 280) * 100));

    const ticks = Array.from({ length: 18 }, (_, i) => `<span style="--i:${i};--on:${i <= Math.round(rpm / 100 * 17) ? 1 : 0}"></span>`).join('');
    const bars = Array.from({ length: 22 }, (_, i) => `<span style="--n:${i}" class="${i < Math.round(fuel / 100 * 22) ? 'on' : ''}"></span>`).join('');
    const mini = `
        <div class="cm-sel-info">
            <span class="${v.seatbelt ? 'ok' : 'warn'}">BELT</span>
            <span class="${v.locked ? 'ok' : ''}">LOCK</span>
            <span class="${engine < 30 ? 'warn' : ''}">ENG ${engine}%</span>
            <span class="${fuel < 15 ? 'warn' : ''}">FUEL ${fuel}%</span>
        </div>`;

    return `
    <div class="cm-speedo-select style-${styleId}" style="--speed:${mainPercent};--rpm:${rpm};--rpmDeg:${rpmDeg}deg;--fuel:${fuel};--fuelDeg:${fuelDeg}deg">
        <div class="cm-sel-bg"></div>
        <div class="cm-sel-ring"><i></i><b></b><em></em></div>
        <div class="cm-sel-ticks">${ticks}</div>
        <div class="cm-sel-speed"><small>${speedText.slice(0, 3 - String(speed).length)}</small>${speed}</div>
        <div class="cm-sel-unit">${unit}</div>
        <div class="cm-sel-gear">${gear}</div>
        <div class="cm-sel-bars">${bars}</div>
        <div class="cm-sel-side left"><strong>${fuel}</strong><small>FUEL</small></div>
        <div class="cm-sel-side right"><strong>${rpm}</strong><small>RPM</small></div>
        ${mini}
        ${indicatorBar(v)}
    </div>`;
}


function ak4yPct(value, max) {
    const n = Number(value) || 0;
    const m = Number(max) || 100;
    return Math.max(0, Math.min(100, (n / m) * 100));
}

function ak4ySmallIcons(v) {
    const engineOk = Number(v.engine ?? 100) > 30;
    const fuelOk = Number(v.fuel ?? 100) > 15;
    return `
        <div class="ak4y-icons">
            <span class="${v.seatbelt ? 'on' : 'warn'}">${IND_ICONS.belt}</span>
            <span class="${engineOk ? 'on' : 'warn'}">${IND_ICONS.engine}</span>
            <span class="${fuelOk ? 'on' : 'warn'}">${IND_ICONS.fuel}</span>
            <span class="${v.lights ? 'on' : ''}">${IND_ICONS.low}</span>
        </div>`;
}

function renderVehAk4y(v, styleId) {
    styleId = Math.max(15, Math.min(23, parseInt(styleId, 10) || 15));
    const speed = Math.max(0, Math.min(999, Math.floor(Number(v.speed) || 0)));
    const speedText = String(speed).padStart(3, '0');
    const unit = escapeHtml(v.unit || getHudSettings().speedUnit || 'KM/H');
    const rpm = Math.max(0, Math.min(100, Number(v.rpm) || 0));
    const fuel = Math.max(0, Math.min(100, Number(v.fuel ?? 0) || 0));
    const engine = Math.max(0, Math.min(100, Number(v.engine ?? 100) || 0));
    const gear = escapeHtml(String(v.gear ?? 'N'));
    const speedPct = ak4yPct(speed, unit === 'MPH' ? 180 : 280);
    const rpmBars = Array.from({ length: 18 }, (_, i) => `<span class="${i < Math.round(rpm / 100 * 18) ? 'on' : ''} ${i > 13 ? 'hot' : ''}"></span>`).join('');
    const roundTicks = Array.from({ length: 42 }, (_, i) => `<span style="--i:${i};--on:${i <= Math.round(speedPct / 100 * 42) ? 1 : 0}"></span>`).join('');
    const dualBars = Array.from({ length: 14 }, (_, i) => `<span class="${i < Math.round(fuel / 100 * 14) ? 'on' : ''}"></span>`).join('');
    const baseStyle = `--ak-speed:${speedPct};--ak-rpm:${rpm};--ak-fuel:${fuel};--ak-engine:${engine};`;

    if (styleId === 15) {
        return `<div class="ak4y-speedo ak4y-v1" style="${baseStyle}">
            <div class="ak-panel"></div>
            <div class="ak-v1-left"><b>${speedText}</b><small>${unit}</small></div>
            <div class="ak-v1-bars">${rpmBars}</div>
            <div class="ak-v1-bottom"><span style="width:${fuel}%"></span></div>
            <div class="ak-v1-gear">${gear}</div>
            ${ak4ySmallIcons(v)}
        </div>`;
    }

    if (styleId === 16) {
        return `<div class="ak4y-speedo ak4y-v2" style="${baseStyle}">
            <div class="ak-round-ticks">${roundTicks}</div>
            <div class="ak-round-core"><b>${speedText}</b><small>${unit}</small><em>${gear}</em></div>
            <div class="ak-round-fuel"><span style="height:${fuel}%"></span></div>
            ${ak4ySmallIcons(v)}
        </div>`;
    }

    if (styleId === 17) {
        return `<div class="ak4y-speedo ak4y-v3" style="${baseStyle}">
            <div class="ak-rpm-label">RPM</div>
            <div class="ak-bars-big">${rpmBars}</div>
            <div class="ak-v3-speed"><i>${gear}</i><b>${speedText}</b><small>${unit}</small></div>
            <div class="ak-v3-fuel"><span style="width:${fuel}%"></span></div>
            ${ak4ySmallIcons(v)}
        </div>`;
    }

    if (styleId === 18) {
        return `<div class="ak4y-speedo ak4y-v4" style="${baseStyle}">
            <div class="ak-hex"><i></i><b>${speedText}</b><small>${unit}</small><em>${gear}</em></div>
            <div class="ak-sidebar left"><span style="height:${fuel}%"></span></div>
            <div class="ak-sidebar right"><span style="height:${rpm}%"></span></div>
            ${ak4ySmallIcons(v)}
        </div>`;
    }

    if (styleId === 19) {
        return `<div class="ak4y-speedo ak4y-v5" style="${baseStyle}">
            <div class="ak-min-line"><span style="width:${speedPct}%"></span></div>
            <div class="ak-min-number"><b>${speedText}</b><small>${unit}</small></div>
            <div class="ak-min-sub"><span>FUEL ${fuel}%</span><span>ENG ${engine}%</span><span>G ${gear}</span></div>
            ${ak4ySmallIcons(v)}
        </div>`;
    }

    if (styleId === 20) {
        return `<div class="ak4y-speedo ak4y-v6" style="${baseStyle}">
            <div class="ak-cluster left"><div class="ak-dual-bars">${dualBars}</div><b>${speedText}</b><small>${unit}</small></div>
            <div class="ak-cluster-screen"><span>${gear}</span><em>CM</em><small>HUD</small></div>
            <div class="ak-cluster right"><div class="ak-dual-bars reverse">${dualBars}</div><b>${fuel}L</b><small>FUEL</small></div>
            ${ak4ySmallIcons(v)}
        </div>`;
    }

    if (styleId === 21) {
        return `<div class="ak4y-speedo ak4y-bike" style="${baseStyle}">
            <div class="bike-bg">☵</div><div class="bike-icon">♢</div>
            <div class="bike-speed"><span>${speedText}</span><small>${unit}</small></div>
            <div class="bike-line"><span style="width:${speedPct}%"></span></div>
        </div>`;
    }

    if (styleId === 22) {
        const deg = -18 + (216 * Math.min(1, speed / 180));
        return `<div class="ak4y-speedo ak4y-boat" style="${baseStyle}">
            <div class="boat-ring"></div><div class="boat-needle" style="transform:rotate(${deg}deg)"></div>
            <div class="boat-center">⚓</div><div class="boat-digital"><b>${speed}</b> ${unit}</div>
            <div class="boat-fuel"><span style="width:${fuel}%"></span></div>
        </div>`;
    }

    return `<div class="ak4y-speedo ak4y-plane" style="${baseStyle}">
        <div class="plane-dial plane-alt"><span>ALT</span><b>${Math.round(Number(v.altitude ?? 0))}</b></div>
        <div class="plane-main"><div class="plane-wings">✈</div><b>${speedText}</b><small>${unit}</small></div>
        <div class="plane-dial plane-fuel"><span>FUEL</span><b>${fuel}%</b></div>
        <div class="plane-strip"><span style="width:${engine}%"></span></div>
    </div>`;
}

function renderVehCar(v) {
    const chosenStyle = getHudSettings().speedoStyle;
    if (chosenStyle === 30) return renderVehExactCircle(v);
    if (chosenStyle >= 24) return renderVehJg(v, chosenStyle);
    if (chosenStyle >= 15) return renderVehAk4y(v, chosenStyle);
    if (chosenStyle !== 1) return renderVehSelectable(v, chosenStyle);

    const speed = Math.max(0, Math.min(999, Math.floor(Number(v.speed) || 0)));
    const speedText = String(speed);
    const pad = '0'.repeat(Math.max(0, 3 - speedText.length));
    const rpm = Math.max(0, Math.min(100, Number(v.rpm) || 0));
    const fuel = Math.max(0, Math.min(100, Number(v.fuel ?? 0) || 0));
    const engine = Math.max(0, Math.min(100, Number(v.engine ?? 100) || 0));
    const rpmDash = (rpm * 3.0).toFixed(1);
    const fuelDash = (fuel * 1.3).toFixed(1);
    const gear = escapeHtml(String(v.gear ?? 'N'));
    const lowFuel = fuel <= 15;
    const lowEngine = engine <= 30;

    // Fast HUD v2 inspired right-bottom speedometer, adapted to plain JS and CM HUD data.
    return `
    <div class="cm-fast-speedo ${lowFuel ? 'low-fuel' : ''} ${lowEngine ? 'low-engine' : ''}">
        <div class="fast-gear">${gear}</div>

        <div class="fast-fuels">
            <p class="fast-fuel">${fuel}%</p>
            <p class="fast-fuel-cap"><span>//</span> 100</p>
        </div>

        <div class="fast-speeds">
            <p class="fast-speed"><span class="dim">${pad}</span>${speedText}</p>
            <p class="fast-speed-unit">${escapeHtml(v.unit || 'KM/H')}</p>
        </div>

        <svg class="fast-speedometer-svg" width="326" height="201" viewBox="0 0 326 201" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <path d="M38.2304 160.707C28.9205 151.397 23.4888 138.902 23.0314 125.744C22.574 112.585 27.125 99.7434 35.7661 89.8095C44.4071 79.8756 56.4946 73.5893 69.5894 72.2194C82.6842 70.8494 95.8111 74.4978 106.321 82.4282L98.7578 92.4515C90.7857 86.4361 80.8286 83.6688 70.8959 84.7079C60.9632 85.747 51.7945 90.5153 45.2401 98.0504C38.6856 105.586 35.2336 115.326 35.5805 125.307C35.9274 135.288 40.0475 144.766 47.1094 151.828L38.2304 160.707Z" fill="url(#cmFastFuelBg)" fill-opacity="0.28"/>
            <path class="fast-fuel-ring" d="M39.5839 153.292C32.5944 144.859 28.8432 134.209 29.005 123.258C29.1668 112.306 33.2309 101.772 40.4664 93.5491C47.7019 85.3266 57.6339 79.9555 68.4759 78.4021C79.3179 76.8487 90.3585 79.2149 99.6117 85.075" style="stroke-dasharray:${fuelDash} 480" stroke="${lowFuel ? '#ffcc30' : '#3DF71F'}" stroke-width="4" fill="none"/>

            <path d="M115.939 167.67C104.667 142.664 102.918 114.402 111.023 88.1974C119.127 61.9931 136.525 39.6523 159.946 25.3762C183.367 11.1001 211.197 5.8722 238.202 10.6757C265.207 15.4792 289.526 29.9831 306.588 51.46L293.897 61.5414C279.294 43.1586 258.478 30.7442 235.363 26.6328C212.249 22.5213 188.429 26.996 168.382 39.2154C148.335 51.4348 133.443 70.5571 126.507 92.9862C119.57 115.415 121.066 139.606 130.715 161.009L115.939 167.67Z" fill="url(#cmFastRpmBg)" fill-opacity="0.24"/>
            <path d="M139.506 155.377C130.525 135.926 128.995 113.855 135.207 93.35C141.419 72.8455 154.941 55.3341 173.207 44.1376C191.474 32.9411 213.214 28.8384 234.305 32.6078C255.396 36.3771 274.369 47.7563 287.627 64.5867" stroke="rgba(255,255,255,0.42)" stroke-width="4" stroke-dasharray="0.94 5.61" fill="none"/>

            <g class="fast-state-icons">
                <text x="194" y="149" class="fast-icon ${v.seatbelt ? 'ok' : 'warn'}">BELT</text>
                <text x="230" y="149" class="fast-icon ${v.cruise ? 'ok' : ''}">CRZ</text>
                <text x="264" y="149" class="fast-icon ${v.locked ? 'ok' : ''}">LOCK</text>
            </g>

            <defs>
                <radialGradient id="cmFastFuelBg" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(41.5 95.4371) rotate(30.6773) scale(68.6003)">
                    <stop stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/>
                </radialGradient>
                <radialGradient id="cmFastRpmBg" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(128 31.4371) rotate(46.7427) scale(174.382)">
                    <stop stop-color="white"/><stop offset="1" stop-color="white" stop-opacity="0"/>
                </radialGradient>
            </defs>
        </svg>

        <svg class="fast-rpm-svg" width="189" height="151" viewBox="0 0 189 151" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
            <path class="fast-rpm-ring" style="stroke-dasharray:${rpmDash} 480" d="M11.059 149.983C0.986809 127.001 -0.500543 101.166 6.86753 77.1792C14.2356 53.1924 29.9695 32.6476 51.2068 19.2823C72.4441 5.91701 97.7736 0.619433 122.587 4.35333C147.401 8.08723 170.049 20.6045 186.413 39.6279" stroke="${rpm >= 88 ? '#ff4d4d' : '#ffffff'}" stroke-width="4.5"/>
        </svg>

        <div class="fast-engine-pill ${lowEngine ? 'warn' : ''}">${IND_ICONS.engine}<span>${engine}%</span></div>
        ${indicatorBar(v)}
    </div>`;
}

// ===================== CIRCULAR SPEEDOMETER (reference design) =====================
// Black dial, 1-8 tick numbers on the top arc, gear badge, big speed, unit,
// odometer, outer RPM arc (left) + fuel arc (right), fuel/engine icons.
// White dial elements; power/fuel/engine accents in cyan.
function renderVehCircle(v) {
    const speed = Math.max(0, Math.min(999, Math.floor(Number(v.speed) || 0)));
    const rpm = Math.max(0, Math.min(100, Number(v.rpm) || 0));
    const fuel = Math.max(0, Math.min(100, Number(v.fuel ?? 100) || 0));
    const engine = Math.max(0, Math.min(100, Number(v.engine ?? 100) || 0));
    const gear = escapeHtml(String(v.gear ?? 'N'));
    const unit = escapeHtml(v.unit || 'KM/H');
    const odoUnit = /MPH/i.test(unit) ? 'MI' : 'KM';
    const lowFuel = fuel <= 15;
    const lowEngine = engine <= 30;

    const CX = 150, CY = 150, R = 112;

    // JG layout: boundary ticks at segment edges (incl. 12 o'clock), numbers
    // centered between them; "1" slot holds the rotated x1000 RPM label.
    const A0 = -150, A1 = 150;
    let ticks = '';
    for (let i = 0; i <= 8; i++) {
        const deg = A0 + (A1 - A0) * (i / 8);
        const a = deg * Math.PI / 180;
        const sin = Math.sin(a), cos = -Math.cos(a);
        const t1r = R - 8, t2r = R - 17;
        ticks += `<line x1="${(CX + sin * t1r).toFixed(1)}" y1="${(CY + cos * t1r).toFixed(1)}" x2="${(CX + sin * t2r).toFixed(1)}" y2="${(CY + cos * t2r).toFixed(1)}" stroke="rgba(255,255,255,0.95)" stroke-width="2.4" stroke-linecap="round"/>`;
    }
    let numbers = '';
    let rpmLabel = '';
    for (let i = 1; i <= 8; i++) {
        const deg = A0 + (A1 - A0) * ((i - 0.5) / 8);
        const a = deg * Math.PI / 180;
        const sin = Math.sin(a), cos = -Math.cos(a);
        const nr = R - 34;
        if (i === 1) {
            rpmLabel = `<text x="${(CX + sin * nr).toFixed(1)}" y="${(CY + cos * nr + 4).toFixed(1)}" class="vcs-rpm-text" transform="rotate(${(deg + 90).toFixed(0)} ${(CX + sin * nr).toFixed(1)} ${(CY + cos * nr).toFixed(1)})">x1000 RPM</text>`;
        } else {
            numbers += `<text x="${(CX + sin * nr).toFixed(1)}" y="${(CY + cos * nr + 6).toFixed(1)}" class="vcs-tick-num">${i}</text>`;
        }
    }

    // THREE arcs, matching the reference:
    //  outer-left  = FUEL   (pump icon at its top tip), fills bottom -> up
    //  outer-right = ENGINE (engine icon at its top tip), fills bottom -> up
    //  inner-left  = RPM    (inside the dial, beside the x1000 RPM label)
    const AR = R + 22;
    const fuelTrack = describeArcTrack(CX, CY, AR, 210, 322);
    const fuelFill  = describeArc(CX, CY, AR, 210, 322, fuel / 100);
    const engTrack  = describeArcTrack(CX, CY, AR, 150, 38);
    const engFill   = describeArc(CX, CY, AR, 150, 38, engine / 100);
    const RIN = R - 6;
    const rpmTrack  = describeArcTrack(CX, CY, RIN, 214, 292);
    const rpmFill   = describeArc(CX, CY, RIN, 214, 292, rpm / 100);

    // Icon anchor points at the arc top tips (SVG coords == element px, 300x300)
    const fuelPos = polar(CX, CY, AR + 1, 330);
    const engPos  = polar(CX, CY, AR + 1, 30);

    return `
    <div class="veh-circle ${lowFuel ? 'low-fuel' : ''} ${lowEngine ? 'low-engine' : ''}">
        <svg class="vcs-svg" viewBox="0 0 300 300" xmlns="http://www.w3.org/2000/svg">
            <circle cx="${CX}" cy="${CY}" r="${R}" fill="rgba(8,11,14,0.78)"/>
            <g>${ticks}${numbers}${rpmLabel}</g>

            <path d="${fuelTrack}" stroke="rgba(255,255,255,0.13)" stroke-width="11" fill="none" stroke-linecap="round"/>
            <path d="${fuelFill}" stroke="${lowFuel ? '#ffcc30' : 'var(--vcs-accent)'}" stroke-width="11" fill="none" stroke-linecap="round"/>

            <path d="${engTrack}" stroke="rgba(255,255,255,0.13)" stroke-width="11" fill="none" stroke-linecap="round"/>
            <path d="${engFill}" stroke="${lowEngine ? '#ff4d4d' : 'var(--vcs-accent)'}" stroke-width="11" fill="none" stroke-linecap="round"/>

            <path d="${rpmTrack}" stroke="rgba(255,255,255,0.10)" stroke-width="9" fill="none" stroke-linecap="round"/>
            <path d="${rpmFill}" stroke="${rpm >= 88 ? '#ff4d4d' : 'var(--vcs-accent)'}" stroke-width="9" fill="none" stroke-linecap="round"/>
        </svg>

        <div class="vcs-icon vcs-fuel ${lowFuel ? 'warn' : ''}" style="left:${(fuelPos.x - 11).toFixed(0)}px;top:${(fuelPos.y - 26).toFixed(0)}px">${IND_ICONS.fuel}</div>
        <div class="vcs-icon vcs-engine ${lowEngine ? 'warn' : ''}" style="left:${(engPos.x - 11).toFixed(0)}px;top:${(engPos.y - 26).toFixed(0)}px">${IND_ICONS.engine}</div>

        <div class="vcs-center">
            <div class="vcs-gear">${gear}</div>
            <div class="vcs-speed">${speed}</div>
            <div class="vcs-unit">${unit}</div>
            <div class="vcs-odo"><span class="odo-num">000000</span> <span class="odo-unit">${odoUnit}</span></div>
        </div>

        <div class="vcs-status">
            <span class="${v.seatbelt ? '' : 'warn'}" title="Seatbelt">${IND_ICONS.belt}</span>
            <span class="${v.cruise ? 'on' : ''}" title="Cruise">${IND_ICONS.cruise}</span>
            <span class="${v.locked ? 'on' : ''}" title="Lock">${IND_ICONS.low}</span>
        </div>
    </div>`;
}

function polar(cx, cy, r, deg) {
    const a = (deg - 90) * Math.PI / 180;
    return { x: cx + r * Math.cos(a), y: cy + r * Math.sin(a) };
}
function describeArcTrack(cx, cy, r, startDeg, endDeg) {
    const s = polar(cx, cy, r, startDeg);
    const e = polar(cx, cy, r, endDeg);
    const large = Math.abs(endDeg - startDeg) > 180 ? 1 : 0;
    const sweep = endDeg > startDeg ? 1 : 0;
    return `M ${s.x.toFixed(1)} ${s.y.toFixed(1)} A ${r} ${r} 0 ${large} ${sweep} ${e.x.toFixed(1)} ${e.y.toFixed(1)}`;
}
function describeArc(cx, cy, r, startDeg, endDeg, frac) {
    frac = Math.max(0, Math.min(1, frac));
    const actualEnd = startDeg + (endDeg - startDeg) * frac;
    return describeArcTrack(cx, cy, r, startDeg, actualEnd);
}

function renderVehElectric(v) {
    const s = String(Math.min(999, v.speed ?? 0));
    const pad = '0'.repeat(Math.max(0, 3 - s.length));
    const segs = 34;
    const filled = Math.round(segs * Math.max(0, Math.min(100, v.rpm || 0)) / 100);
    const bars = Array.from({length: segs}, (_, i) =>
        `<span class="ve-seg ${i < filled ? 'on' : ''}"></span>`).join('');

    return `
    <div class="veh-electric">
        <div class="ve-top">
            <div class="ve-gear">${escapeHtml(String(v.gear ?? 'N'))}</div>
            <div class="ve-digits"><span class="dim">${pad}</span>${s}</div>
            <div class="ve-pills">
                <div class="ve-pill ${v.engine < 30 ? 'low' : ''}">${IND_ICONS.engine}<span>${v.engine ?? 100}%</span></div>
                <div class="ve-pill ${v.fuel < 15 ? 'low' : ''}">${IND_ICONS.fuel}<span>${v.fuel ?? 100}%</span></div>
            </div>
        </div>
        <div class="ve-segbar">${bars}</div>
        <div class="ve-odo">${escapeHtml(v.unit || 'KM/H')}</div>
        ${indicatorBar(v)}
    </div>`;
}

function renderVehAir(v) {
    const hdg = ((v.heading ?? 0) % 360 + 360) % 360;
    const roll = Math.max(-60, Math.min(60, v.roll ?? 0));
    const pitch = Math.max(-30, Math.min(30, v.pitch ?? 0));
    const altNeedle = ((v.altitude ?? 0) % 1000) / 1000 * 360;
    const spdNeedle = -120 + Math.min(240, (v.speed ?? 0) / 400 * 240);
    const leds = [
        { l: 'ENG', on: (v.engine ?? 100) > 30, bad: (v.engine ?? 100) <= 30 },
        { l: 'LIGHT', on: (v.lights ?? 0) > 0, bad: false },
        { l: 'FUEL', on: (v.fuel ?? 100) >= 15, bad: (v.fuel ?? 100) < 15 },
        { l: 'GEAR', on: v.gearDown !== false, bad: v.gearDown === false },
        { l: 'STALL', on: false, bad: !!v.stall }
    ];

    return `
    <div class="veh-air">
        <div class="va-row">
            <div class="va-gauge va-compass">
                <div class="va-compass-card" style="transform:rotate(${-hdg}deg)">
                    ${[0,45,90,135,180,225,270,315].map(a => `<span class="va-cdir" style="transform:rotate(${a}deg) translateY(-34px)">${{0:'N',90:'E',180:'S',270:'W'}[a] ?? ''}</span>`).join('')}
                </div>
                <svg viewBox="0 0 24 24" class="va-plane"><path d="M12 3l2 7h6l-6 3 1.6 6L12 16l-3.6 3L10 13 4 10h6l2-7z" fill="#fff"/></svg>
            </div>
            <div class="va-gauge va-att">
                <div class="va-horizon" style="transform:rotate(${roll}deg) translateY(${pitch * 1.1}px)"></div>
                <div class="va-att-ref"></div>
            </div>
            <div class="va-gauge va-alt">
                <div class="va-label">ALT</div>
                <div class="va-needle" style="transform:rotate(${altNeedle}deg)"></div>
            </div>
            <div class="va-gauge va-spd">
                <div class="va-label">AIR SPD<br><small>${escapeHtml(v.unit || 'KM/H')}</small></div>
                <div class="va-needle red" style="transform:rotate(${spdNeedle}deg)"></div>
                <div class="va-spd-val">${v.speed ?? 0}</div>
            </div>
        </div>
        <div class="va-leds">
            ${leds.map(x => `<div class="va-led"><span class="dot ${x.bad ? 'bad' : (x.on ? 'ok' : '')}"></span>${x.l}</div>`).join('')}
        </div>
    </div>`;
}

function renderVehBoat(v) {
    const sweepStart = -130, sweepEnd = 130;
    const spdAngle = sweepStart + (sweepEnd - sweepStart) * Math.min(1, (v.speed ?? 0) / 120);
    const leds = [
        { l: 'ENGINE', on: (v.engine ?? 100) > 30, bad: (v.engine ?? 100) <= 30 },
        { l: 'LIGHT', on: (v.lights ?? 0) > 0, bad: false },
        { l: 'ANCHOR', on: false, bad: !!v.anchor }
    ];
    return `
    <div class="veh-boat">
        <div class="vb-minis">
            <div class="vb-mini ${v.engine < 30 ? 'low' : ''}">
                <svg viewBox="0 0 80 80"><path d="${arcPath(40,40,32,-120,-120 + 240 * Math.min(1,(v.engine ?? 100)/100))}" stroke="currentColor" stroke-width="6" fill="none" stroke-linecap="round"/></svg>
                <span class="vb-mini-ic">${IND_ICONS.engine}</span>
            </div>
            <div class="vb-mini fuel ${v.fuel < 15 ? 'low' : ''}">
                <svg viewBox="0 0 80 80"><path d="${arcPath(40,40,32,-120,-120 + 240 * Math.min(1,(v.fuel ?? 100)/100))}" stroke="currentColor" stroke-width="6" fill="none" stroke-linecap="round"/></svg>
                <span class="vb-mini-ic">${IND_ICONS.fuel}</span>
            </div>
        </div>
        <div class="vb-main">
            <svg class="vb-ring" viewBox="0 0 220 220">
                <path d="${arcPath(110,110,96,sweepStart,sweepEnd)}" stroke="rgba(255,255,255,0.14)" stroke-width="9" fill="none" stroke-linecap="round"/>
                <path d="${arcPath(110,110,96,sweepStart,Math.max(sweepStart + 0.5, spdAngle))}" stroke="#ffffff" stroke-width="9" fill="none" stroke-linecap="round"/>
            </svg>
            <div class="vb-center">
                <div class="vb-gear">${escapeHtml(String(v.gear ?? 'N'))}</div>
                <div class="vb-speed">${v.speed ?? 0}</div>
                <div class="vb-unit">${escapeHtml(v.unit || 'KM/H')}</div>
            </div>
        </div>
        <div class="va-leds vb-leds">
            ${leds.map(x => `<div class="va-led"><span class="dot ${x.bad ? 'bad' : (x.on ? 'ok' : '')}"></span>${x.l}</div>`).join('')}
        </div>
    </div>`;
}

function renderVehBike(v) {
    return `
    <div class="veh-bike">
        <div class="vk-speed">${v.speed ?? 0}</div>
        <div class="vk-unit">${escapeHtml(v.unit || 'KM/H')}</div>
    </div>`;
}


function renderVehJg(v, styleId) {
    styleId = Math.max(24, Math.min(29, parseInt(styleId, 10) || 24));
    const speed = Math.max(0, Math.min(999, Math.floor(Number(v.speed) || 0)));
    const unit = escapeHtml(v.unit || getHudSettings().speedUnit || 'KM/H');
    const rpm = Math.max(0, Math.min(100, Number(v.rpm) || 0));
    const fuel = Math.max(0, Math.min(100, Number(v.fuel ?? 0) || 0));
    const engine = Math.max(0, Math.min(100, Number(v.engine ?? 100) || 0));
    const gear = escapeHtml(String(v.gear ?? 'N'));
    const speedPct = Math.max(0, Math.min(100, speed / (unit === 'MPH' ? 180 : 300) * 100));
    const rpmPct = Math.max(0, Math.min(100, rpm));
    const speedText = String(speed).padStart(3, '0');
    const lights = indicatorBar(v);
    const style = `--jg-speed:${speedPct};--jg-rpm:${rpmPct};--jg-fuel:${fuel};--jg-engine:${engine};`;
    const bars = Array.from({ length: 22 }, (_, i) => `<span class="${i < Math.round(rpmPct / 100 * 22) ? 'on' : ''} ${i > 17 ? 'hot' : ''}"></span>`).join('');
    const ticks = Array.from({ length: 54 }, (_, i) => `<span style="--i:${i};--on:${i <= Math.round(speedPct / 100 * 54) ? 1 : 0}"></span>`).join('');

    if (styleId === 24) {
        return `<div class="jg-speedo jg-modern" style="${style}">
            <div class="jg-modern-card"><div class="jg-modern-rpm">${bars}</div><div class="jg-modern-speed"><b>${speedText}</b><small>${unit}</small></div><div class="jg-modern-gear">${gear}</div><div class="jg-modern-fuel"><span style="width:${fuel}%"></span></div><div class="jg-modern-meta"><span>ENG ${engine}%</span><span>FUEL ${fuel}%</span></div></div>${lights}
        </div>`;
    }
    if (styleId === 25) {
        return `<div class="jg-speedo jg-pro" style="${style}">
            <div class="jg-pro-left"><b>${speedText}</b><small>${unit}</small></div><div class="jg-pro-center"><span>${gear}</span><em>GEAR</em></div><div class="jg-pro-right"><b>${fuel}</b><small>FUEL</small></div><div class="jg-pro-rpm">${bars}</div>${lights}
        </div>`;
    }
    if (styleId === 26) {
        return `<div class="jg-speedo jg-future" style="${style}">
            <div class="jg-future-core"><div class="jg-future-num">${speedText}</div><div class="jg-future-unit">${unit}</div><div class="jg-future-gear">${gear}</div></div><div class="jg-future-ring">${ticks}</div><div class="jg-future-lines"><span style="width:${fuel}%"></span><i style="width:${engine}%"></i></div>${lights}
        </div>`;
    }
    if (styleId === 27) {
        const deg = -128 + (256 * speedPct / 100);
        return `<div class="jg-speedo jg-analogue" style="${style}">
            <div class="jg-dial"><div class="jg-dial-ticks">${ticks}</div><div class="jg-needle" style="transform:rotate(${deg}deg)"></div><div class="jg-dial-center"><b>${speed}</b><small>${unit}</small><em>${gear}</em></div></div><div class="jg-side-gauge fuel"><span style="height:${fuel}%"></span></div><div class="jg-side-gauge rpm"><span style="height:${rpmPct}%"></span></div>${lights}
        </div>`;
    }
    if (styleId === 28) {
        return `<div class="jg-speedo jg-bold" style="${style}">
            <div class="jg-bold-speed">${speedText}</div><div class="jg-bold-unit">${unit}</div><div class="jg-bold-rpm">${bars}</div><div class="jg-bold-row"><span>G ${gear}</span><span>F ${fuel}%</span><span>E ${engine}%</span></div>${lights}
        </div>`;
    }
    return `<div class="jg-speedo jg-minimal" style="${style}">
        <div class="jg-min-number"><b>${speedText}</b><small>${unit}</small></div><div class="jg-min-line"><span style="width:${speedPct}%"></span></div><div class="jg-min-details"><span>${gear}</span><span>${fuel}%</span><span>${engine}%</span></div>${lights}
    </div>`;
}


function renderVehExactCircle(v) {
    const speed = Math.max(0, Math.min(999, Math.floor(Number(v.speed) || 0)));
    const unit = escapeHtml(v.unit || getHudSettings().speedUnit || 'MPH');
    const rpm = Math.max(0, Math.min(100, Number(v.rpm) || 0));
    const fuel = Math.max(0, Math.min(100, Number(v.fuel ?? 0) || 0));
    const engine = Math.max(0, Math.min(100, Number(v.engine ?? 100) || 0));
    const gear = escapeHtml(String(v.gear ?? 'N'));
    const odometer = String(Math.max(0, Math.floor(Number(v.odometer ?? v.mileage ?? 0) || 0))).padStart(6, '0');
    const fuelEnd = 210 + (fuel / 100) * 76;
    const engineEnd = 25 + (engine / 100) * 98;
    const rpmEnd = 220 + (rpm / 100) * 122;
    const rpmHot = rpm >= 88;
    const nums = [
        { n: 2, a: 286 }, { n: 3, a: 322 }, { n: 4, a: 0 },
        { n: 5, a: 38 }, { n: 6, a: 74 }, { n: 7, a: 111 }, { n: 8, a: 146 }
    ].map(item => {
        const rad = (item.a - 90) * Math.PI / 180;
        const x = 130 + 72 * Math.cos(rad);
        const y = 130 + 72 * Math.sin(rad);
        return `<span class="exact-num" style="left:${x.toFixed(1)}px;top:${y.toFixed(1)}px">${item.n}</span>`;
    }).join('');
    const tickAngles = [286,304,322,341,0,19,38,56,74,92,111,128,146];
    const ticks = tickAngles.map(a => {
        const rad = (a - 90) * Math.PI / 180;
        const x = 130 + 89 * Math.cos(rad);
        const y = 130 + 89 * Math.sin(rad);
        return `<span class="exact-tick" style="left:${x.toFixed(1)}px;top:${y.toFixed(1)}px;transform:translate(-50%,-50%) rotate(${a}deg)"></span>`;
    }).join('');

    return `<div class="cm-exact-speedo ${rpmHot ? 'rpm-hot' : ''}" style="--exact-rpm:${rpm};--exact-fuel:${fuel};--exact-engine:${engine}">
        <div class="exact-glass"></div>
        <svg class="exact-svg" viewBox="0 0 260 260" aria-hidden="true">
            <circle cx="130" cy="130" r="92" fill="rgba(0,0,0,0.62)"/>
            <circle cx="130" cy="130" r="78" fill="rgba(0,0,0,0.18)"/>
            <path d="${arcPath(130,130,112,25,123)}" class="exact-arc-bg"/>
            <path d="${arcPath(130,130,112,25,Math.max(26, engineEnd))}" class="exact-arc exact-engine"/>
            <path d="${arcPath(130,130,112,210,286)}" class="exact-arc-bg exact-left-bg"/>
            <path d="${arcPath(130,130,112,210,Math.max(211, fuelEnd))}" class="exact-arc exact-fuel"/>
            <path d="${arcPath(130,130,78,220,342)}" class="exact-arc-bg exact-rpm-bg"/>
            <path d="${arcPath(130,130,78,220,Math.max(221, rpmEnd))}" class="exact-arc exact-rpm"/>
        </svg>
        <div class="exact-icon exact-fuel-icon">${IND_ICONS.fuel}</div>
        <div class="exact-icon exact-engine-icon">${IND_ICONS.engine}</div>
        ${nums}
        ${ticks}
        <div class="exact-rpm-text">x1000RPM</div>
        <div class="exact-gear">${gear}</div>
        <div class="exact-speed">${speed}</div>
        <div class="exact-unit">${unit}</div>
        <div class="exact-odo">${odometer} <span>${unit === 'MPH' ? 'MI' : 'KM'}</span></div>
        <div class="exact-status-row">
            <span class="${v.seatbelt ? 'ok' : 'warn'}">${IND_ICONS.belt}</span>
            <span class="${v.cruise ? 'ok' : ''}">${IND_ICONS.cruise}</span>
            <span class="${Number(v.fuel ?? 0) <= 15 ? 'warn' : ''}">${IND_ICONS.fuel}</span>
        </div>
    </div>`;
}

function renderVehTrain(v) {
    const speed = Math.max(0, Math.min(999, Math.floor(Number(v.speed) || 0)));
    const unit = escapeHtml(v.unit || getHudSettings().speedUnit || 'KM/H');
    const engine = Math.max(0, Math.min(100, Number(v.engine ?? 100) || 0));
    const fuel = Math.max(0, Math.min(100, Number(v.fuel ?? 0) || 0));
    return `<div class="jg-speedo jg-train" style="--jg-speed:${Math.min(100, speed / 180 * 100)};--jg-fuel:${fuel};--jg-engine:${engine};">
        <div class="train-card"><div class="train-label">TRAIN</div><div class="train-speed">${String(speed).padStart(3, '0')}</div><div class="train-unit">${unit}</div><div class="train-track"><span style="width:${Math.min(100, speed / 180 * 100)}%"></span></div><div class="train-row"><span>ENG ${engine}%</span><span>FUEL ${fuel}%</span></div></div>
    </div>`;
}

function escapeHtml(str) {
    return String(str ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function renderVehicle() {
    const el = document.getElementById('hud-vehicle');
    if (!el) return;
    const v = state.vehicle || {};

    if (!v.visible || getHudSettings().showSpeedometer === false) { el.classList.add('hidden'); return; }
    el.classList.remove('hidden');

    const t = v.vehType || 'car';

    // Auto vehicle-type speedometers keep their dedicated gauges.
    if (t === 'air') el.innerHTML = renderVehAir(v);
    else if (t === 'boat') el.innerHTML = renderVehBoat(v);
    else if (t === 'bike' || t === 'bicycle') el.innerHTML = renderVehBike(v);
    // Everything else (car, electric, truck, etc.) uses the one circular gauge.
    else el.innerHTML = renderVehCircle(v);
}

function formatMoney(amount) {
    return amount.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

function updateModule(name) {
    const mod = HUD_MODULES[name];
    if (mod && mod.render) {
        mod.render();
    }
}

function updateAll() {
    Object.keys(HUD_MODULES).forEach(name => updateModule(name));
}

function applyResponsiveLayout(data) {
    const root = document.documentElement;
    const setPx = (name, value) => {
        const n = Number(value);
        if (Number.isFinite(n) && n >= 0) root.style.setProperty(name, `${Math.round(n)}px`);
    };

    setPx('--cm-minimap-left', data.minimapLeft);
    setPx('--cm-minimap-right', data.minimapRight);
    setPx('--cm-minimap-top', data.minimapTop);
    setPx('--cm-minimap-bottom', data.minimapBottom);
    setPx('--cm-location-left', data.locationLeft);
    setPx('--cm-location-bottom', data.locationBottom);

    const scale = Number(data.uiScale);
    if (Number.isFinite(scale) && scale > 0) {
        root.style.setProperty('--cm-ui-scale', scale.toFixed(3));
    }
}



// ========== CHAT ==========


// ========== HUD SOUND SUPPORT ==========
let cmHudAudioUnlocked = false;
const cmHudSoundCache = {};
function unlockHudAudio() {
    cmHudAudioUnlocked = true;
    window.removeEventListener('click', unlockHudAudio);
    window.removeEventListener('keydown', unlockHudAudio);
}
window.addEventListener('click', unlockHudAudio);
window.addEventListener('keydown', unlockHudAudio);

function playHudSound(name, volume = 0.55) {
    const allowed = {
        'seatbelt-on': 'assets/sfx/seatbelt-on.mp3',
        'seatbelt-off': 'assets/sfx/seatbelt-off.mp3',
        'seatbelt-alarm': 'assets/sfx/seatbelt-alarm.mp3'
    };
    const src = allowed[name];
    if (!src) return;
    try {
        const audio = cmHudSoundCache[name] || new Audio(src);
        cmHudSoundCache[name] = audio;
        audio.volume = Math.max(0, Math.min(1, Number(volume) || 0.55));
        audio.currentTime = 0;
        const p = audio.play();
        if (p && p.catch) p.catch(() => {});
    } catch (e) {}
}

// ========== MESSAGE HANDLER ==========
window.addEventListener('message', function(event) {
    const data = event.data;
    
    // Route actions to state updates
    switch(data.action) {
        case 'init':
            Object.assign(state, data.state || {});
            if (data.state && data.state.hudSettings) setHudSettings(data.state.hudSettings, false);
            else applyHudSettings();
            // Do not let a late init/update make the HUD visible while another UI is open.
            state.hudVisible = !state.externalHidden && ((data.state && data.state.hudVisible !== undefined) ? data.state.hudVisible !== false : state.hudVisible !== false);
            document.body.classList.toggle('hud-hidden', !state.hudVisible || state.externalHidden);
            updateAll();
            break;
            
        case 'setHudSettings':
            setHudSettings(data.settings || {}, false);
            if (state.adminOpen) renderHudAdmin();
            break;

        case 'openHudAdmin':
            state.adminOpen = true;
            setHudSettings(data.settings || {}, false);
            applyHudSettings();
            renderHudAdmin();
            break;

        case 'closeHudAdmin':
            state.adminOpen = false;
            applyHudSettings();
            document.getElementById('hud-admin')?.classList.add('hidden');
            break;

        case 'updateHealth':
            state.health = data.health;
            state.armor = data.armor;
            break;
            
        case 'updateMoney':
            state.cash = Number(data.cash ?? state.cash) || 0;
            state.bank = Number(data.bank ?? state.bank) || 0;
            updateModule('topRight');
            break;

        case 'updateCharacterHud':
            if (data.id !== undefined && String(data.id) !== '') state.serverId = data.id;
            if (data.name !== undefined && String(data.name) !== '') state.characterName = data.name;
            state.cash = Number(data.cash ?? state.cash) || 0;
            state.bank = Number(data.bank ?? state.bank) || 0;
            updateModule('topRight');
            break;
            
        case 'updateLayout':
            applyResponsiveLayout(data);
            break;
            
        case 'updateLocation':
            state.area = data.area;
            state.street = data.street;
            if (data.dir) state.dir = data.dir;
            updateModule('bottomLeft');
            break;
            
        case 'updateTime':
            state.clock = data.clock;
            state.date = data.date;
            updateModule('bottomRight');
            break;
            
        case 'updatePlayers':
            state.onlinePlayers = data.count;
            updateModule('topRight');
            break;
            
        case 'updateId':
            if (data.id !== undefined && String(data.id) !== '') state.serverId = data.id;
            updateModule('topRight');
            break;
            
        case 'showDeath':
            state.isDead = true;
            state.deathTime = data.time || 30;
            startDeathTimer();
            updateModule('death');
            break;
            
        case 'updateDeathTime':
            state.deathTime = data.time;
            updateModule('death');
            break;
            
        case 'showRespawn':
            state.deathTime = 0;
            updateModule('death');
            break;
            
        case 'hideDeath':
            state.isDead = false;
            state.deathTime = 0;
            stopDeathTimer();
            updateModule('death');
            break;
            
        case 'notify':
            addNotification(data.text, data.type);
            break;

        case 'playHudSound':
            playHudSound(data.sound, data.volume);
            break;

        case 'updateVehicle':
            state.vehicle = { ...state.vehicle, ...data, visible: data.visible !== false };
            updateModule('vehicle');
            break;

        case 'hideVehicle':
            state.vehicle.visible = false;
            updateModule('vehicle');
            break;

        case 'setMouseOpen':
            state.mouseOpen = !!data.open;
            updateModule('leftKeys');
            break;

        case 'setHudVisible':
            state.externalHidden = data.externalHidden === true;
            state.hudVisible = !state.externalHidden && data.visible !== false;
            document.body.classList.toggle('hud-hidden', !state.hudVisible || state.externalHidden);
            applyHudSettings();
            break;

            
        case 'keyState':
            if (data.key) state.keys[data.key] = data.active;
            updateModule('bottomRight');
            break;
            
        case 'showModule':
            document.getElementById(HUD_MODULES[data.module]?.id)?.classList.remove('hidden');
            break;
            
        case 'hideModule':
            document.getElementById(HUD_MODULES[data.module]?.id)?.classList.add('hidden');
            break;
    }
});

// ========== DEATH TIMER ==========
function startDeathTimer() {
    stopDeathTimer();
    deathInterval = setInterval(() => {
        if (state.deathTime > 0) {
            state.deathTime--;
            updateModule('death');
        } else {
            stopDeathTimer();
        }
    }, 1000);
}

function stopDeathTimer() {
    if (deathInterval) {
        clearInterval(deathInterval);
        deathInterval = null;
    }
}

// ========== NOTIFICATIONS ==========
const MAX_NOTIFICATIONS = 5;

function addNotification(text, type = 'info') {
    const container = document.getElementById('hud-notify');
    if (!container || !state.hudVisible) return;

    if (container.children.length >= MAX_NOTIFICATIONS) {
        container.removeChild(container.firstChild);
    }

    const themes = {
        success: { label: 'SUCCESS', color: '#2effa5', icon: '<svg viewBox="0 0 24 24"><path d="M5 12.5l4.2 4.3L19 7.5"/></svg>' },
        error:   { label: 'ERROR',   color: '#ff5b5b', icon: '<svg viewBox="0 0 24 24"><path d="M7 7l10 10M17 7L7 17"/></svg>' },
        warning: { label: 'WARNING', color: '#ffc02e', icon: '<svg viewBox="0 0 24 24"><path d="M12 4L2.8 19.5h18.4L12 4z"/><path d="M12 10v4.2M12 17.2v.1"/></svg>' },
        info:    { label: 'INFO',    color: '#31e6ff', icon: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.6"/><path d="M12 11v5M12 8v.1"/></svg>' }
    };
    const safeType = themes[type] ? type : 'info';
    const theme = themes[safeType];

    const item = document.createElement('div');
    item.className = `notify-item ${safeType}`;
    item.style.setProperty('--nt-color', theme.color);
    item.innerHTML = `
        <div class="notify-accent"></div>
        <div class="notify-icon">${theme.icon}</div>
        <div class="notify-content">
            <div class="notify-title">${theme.label}</div>
            <div class="notify-text"></div>
            <div class="notify-progress-track"><div class="notify-progress-fill"></div></div>
        </div>
    `;
    item.querySelector('.notify-text').textContent = text || '';

    container.appendChild(item);

    setTimeout(() => {
        item.classList.add('hide');
        setTimeout(() => {
            if (container.contains(item)) item.remove();
        }, 250);
    }, 4200);
}

// ========== CLOCK UPDATE ==========
setInterval(() => {
    const now = new Date();
    const h = String(now.getHours()).padStart(2, '0');
    const m = String(now.getMinutes()).padStart(2, '0');
    state.clock = `${h}:${m}`;
    state.date = `${String(now.getDate()).padStart(2, '0')}.${String(now.getMonth()+1).padStart(2, '0')}.${now.getFullYear()}`;
    updateModule('bottomRight');
}, 1000);

// ========== INIT ==========
applyHudSettings();
updateAll();
// Close HUD mouse from inside NUI when Escape/Backspace is pressed.
document.addEventListener('keydown', (e) => {
    const key = e.key || '';

    if (state.adminOpen && (key === 'Escape' || key === 'Backspace')) {
        e.preventDefault();
        state.adminOpen = false;
        applyHudSettings();
        document.getElementById('hud-admin')?.classList.add('hidden');
        nuiFetch('hudAdminClose', {});
        return;
    }

    // When HUD mouse is open, pressing ` / ~ again closes it from inside NUI focus.
    // FiveM keymapping cannot always receive the second key press while NUI owns focus.
    if (state.mouseOpen && (key === '`' || key === '~')) {
        e.preventDefault();
        fetch(`https://${GetParentResourceName()}/closeHudMouse`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({})
        });
        return;
    }

    if (state.mouseOpen && (key === 'Escape' || key === 'Backspace')) {
        e.preventDefault();
        fetch(`https://${GetParentResourceName()}/closeHudMouse`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({})
        });
    }
});
