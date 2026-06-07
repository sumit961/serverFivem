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
    death: {
        id: 'hud-death',
        render: renderDeath
    },
    vehicle: {
        id: 'hud-vehicle',
        render: null // Future
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
    
    // Keys (for visual feedback)
    keys: {
        N: false, M: false, U: false, I: false,
        L: false, Z: false, X: false
    },
    
    // Notifications queue
    notifications: []
};

let deathInterval = null;

// ========== RENDER FUNCTIONS ==========

function renderTopRight() {
    const el = document.getElementById(HUD_MODULES.topRight.id);
    if (!el) return;

    el.innerHTML = `
        <div class="server-badge">
            <span class="server-name">${state.serverName}</span>
            <span class="level-tag">${state.level}</span>
        </div>
        <div class="id-badge">
            <span class="id-text">ID: <span>${state.serverId}</span></span>
        </div>
        <div class="players-count">
            <span class="icon">👤</span>
            <span>${state.onlinePlayers} online</span>
        </div>
        <div class="money-block">
            <div class="money-cash">$${formatMoney(state.cash)}</div>
            <div class="money-bank">$${formatMoney(state.bank)} (Bank)</div>
        </div>
    `;
}

function renderBottomLeft() {
    const el = document.getElementById(HUD_MODULES.bottomLeft.id);
    if (!el) return;

    const healthPct = Math.max(0, Math.min(100, (state.health / state.maxHealth) * 100));
    const armorPct = Math.max(0, Math.min(100, (state.armor / state.maxArmor) * 100));
    
    let healthClass = '';
    if (healthPct < 25) healthClass = 'critical';
    else if (healthPct < 50) healthClass = 'low';

    el.innerHTML = `
        <div class="minimap-container">
            <div class="minimap-slot">
                <div class="compass-n">N</div>
                <!-- GTA minimap renders natively in this area -->
            </div>
        </div>
        <div class="bars-container">
            <div class="bar-track">
                <div class="bar-fill health ${healthClass}" style="width:${healthPct}%"></div>
            </div>
            <div class="bar-track">
                <div class="bar-fill armor" style="width:${armorPct}%"></div>
            </div>
        </div>
        <div class="location-box">
            <div class="location-area">
                <span class="location-divider"></span>${state.area}
            </div>
            <div class="location-street">${state.street}</div>
        </div>
    `;
}

function renderBottomRight() {
    const el = document.getElementById(HUD_MODULES.bottomRight.id);
    if (!el) return;

    const keyList = ['N', 'M', 'U', 'I', 'L', 'Z', 'X'];
    
    el.innerHTML = `
        <div class="time-block">
            <span class="time-icon">🕐</span>
            <span class="time-text">${state.clock}</span>
        </div>
        <div class="date-text">${state.date}</div>
        <div class="keys-column">
            ${keyList.map(k => `
                <div class="key-icon ${state.keys[k] ? 'active' : ''}">${k}</div>
            `).join('')}
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
            updateModule('bottomLeft');
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
function addNotification(text, type = 'info') {
    const container = document.getElementById('hud-notify');
    if (!container) return;
    
    const item = document.createElement('div');
    item.className = 'notify-item';
    item.textContent = text;
    container.appendChild(item);
    
    setTimeout(() => {
        item.style.opacity = '0';
        item.style.transform = 'translateX(100%)';
        setTimeout(() => item.remove(), 300);
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