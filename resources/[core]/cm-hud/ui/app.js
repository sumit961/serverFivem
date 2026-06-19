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
    // Server / Identity
    serverName: 'CM-RP',
    serverId: 0,
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
    
    // Notifications queue
    notifications: []
};

let deathInterval = null;

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
                    <span class="stat-id">ID: ${state.serverId}</span>
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
        <div class="location-box location-no-bg">
            <div class="location-area">${state.area}</div>
            <div class="location-street">${state.street}</div>
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

// Cache vehicle elements so renderVehicle() never rebuilds the SVG every 100ms.
const vehicleEls = {
    container: null, speed: null, unit: null, fuel: null, fuelRing: null, rpmRing: null,
    seatbelt: null, cruise: null, gear: null, lock: null, ready: false
};

function cacheVehicleEls() {
    if (vehicleEls.ready) return;
    vehicleEls.container = document.getElementById('hud-vehicle');
    vehicleEls.speed = document.getElementById('veh-speed');
    vehicleEls.unit = document.getElementById('veh-unit');
    vehicleEls.fuel = document.getElementById('veh-fuel');
    vehicleEls.fuelRing = document.getElementById('veh-fuel-ring');
    vehicleEls.rpmRing = document.getElementById('veh-rpm-ring');
    vehicleEls.seatbelt = document.getElementById('veh-seatbelt');
    vehicleEls.cruise = document.getElementById('veh-cruise');
    vehicleEls.gear = document.getElementById('veh-gear');
    vehicleEls.lock = document.getElementById('veh-lock');
    vehicleEls.ready = true;
}

function renderVehicle() {
    cacheVehicleEls();
    const els = vehicleEls;
    if (!els.container) return;

    if (!state.vehicle.visible) {
        els.container.classList.add('hidden');
        return;
    }

    els.container.classList.remove('hidden');

    const fuelPct = Math.round(Math.max(0, Math.min(100, state.vehicle.fuel || 0)));
    const rpmPct = Math.max(0, Math.min(100, state.vehicle.rpm || 0));
    const speed = Math.max(0, Number(state.vehicle.speed || 0));
    const total = 480;

    if (els.speed) els.speed.textContent = String(speed).padStart(3, '0');
    if (els.unit) els.unit.textContent = state.vehicle.unit || 'KM/H';
    if (els.fuel) els.fuel.textContent = fuelPct;
    if (els.fuelRing) els.fuelRing.style.strokeDashoffset = total - (total * (fuelPct / 100));
    if (els.rpmRing) els.rpmRing.style.strokeDashoffset = total - (total * (rpmPct / 100));
    if (els.seatbelt) {
        els.seatbelt.classList.toggle('active', !!state.vehicle.seatbelt);
        els.seatbelt.classList.toggle('warning', !state.vehicle.seatbelt && speed > 50);
    }
    if (els.cruise) els.cruise.classList.toggle('active', !!state.vehicle.cruise);
    if (els.gear) els.gear.textContent = state.vehicle.gear || 'N';
    if (els.lock) els.lock.textContent = state.vehicle.locked ? '🔒' : '🔓';
}

// ========== UTILITY ==========
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

// ========== MESSAGE HANDLER ==========
window.addEventListener('message', function(event) {
    const data = event.data;
    
    // Route actions to state updates
    switch(data.action) {
        case 'init':
            Object.assign(state, data.state || {});
            updateAll();
            break;
            
        case 'updateHealth':
            state.health = data.health;
            state.armor = data.armor;
            break;
            
        case 'updateMoney':
            state.cash = data.cash;
            state.bank = data.bank;
            updateModule('topRight');
            break;
            
        case 'updateLocation':
            state.area = data.area;
            state.street = data.street;
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
            state.serverId = data.id;
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
            document.body.classList.toggle('hud-hidden', data.visible === false);
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
    if (!container) return;

    if (container.children.length >= MAX_NOTIFICATIONS) {
        container.removeChild(container.firstChild);
    }

    const themes = {
        success: { icon: '✅', color: '#3DF71F' },
        error: { icon: '❌', color: '#ff3333' },
        warning: { icon: '⚠️', color: '#ffdf1b' },
        info: { icon: 'ℹ️', color: '#2196F3' }
    };
    const safeType = themes[type] ? type : 'info';
    const theme = themes[safeType];

    const item = document.createElement('div');
    item.className = `notify-item ${safeType}`;
    item.style.borderLeftColor = theme.color;
    item.innerHTML = `
        <div class="notify-content">
            <span class="notify-icon">${theme.icon}</span>
            <span class="notify-text"></span>
        </div>
        <div class="notify-progress-track">
            <div class="notify-progress-fill" style="background: ${theme.color};"></div>
        </div>
    `;
    item.querySelector('.notify-text').textContent = text || '';

    container.appendChild(item);

    setTimeout(() => {
        item.classList.add('hide');
        setTimeout(() => {
            if (container.contains(item)) item.remove();
        }, 300);
    }, 5000);
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
updateAll();
// Close HUD mouse from inside NUI when Escape/Backspace is pressed.
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || e.key === 'Backspace') {
        fetch(`https://${GetParentResourceName()}/closeHudMouse`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({})
        });
    }
});
