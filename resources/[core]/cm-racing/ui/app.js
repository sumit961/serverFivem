// CM Racing Frontend Application

let menuData = null;

function formatTime(ms) {
    if (!ms || isNaN(ms)) return '--:--.--';
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const centiseconds = Math.floor((ms % 1000) / 10);
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}.${String(centiseconds).padStart(2, '0')}`;
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    switch (data.action) {
        case 'showHud':
            document.getElementById('hud-route-name').textContent = data.routeName || 'SANCTIONED TIME TRIAL';
            document.getElementById('hud-checkpoints').textContent = `${data.currentCheckpoint || 0} / ${data.totalCheckpoints || 0}`;
            document.getElementById('hud-timer').textContent = '00:00.00';
            document.getElementById('hud-speed').innerHTML = `0 <small>KM/H</small>`;
            document.getElementById('race-hud').classList.remove('hidden');
            break;

        case 'hideHud':
            document.getElementById('race-hud').classList.add('hidden');
            break;

        case 'updateHud':
            document.getElementById('hud-checkpoints').textContent = `${data.currentCheckpoint || 0} / ${data.totalCheckpoints || 0}`;
            break;

        case 'tickHud':
            document.getElementById('hud-timer').textContent = formatTime(data.elapsedMs);
            document.getElementById('hud-speed').innerHTML = `${data.speed || 0} <small>KM/H</small>`;
            break;

        case 'startCountdown':
            handleCountdown(data.count || 3);
            break;

        case 'showResults':
            handleResults(data.results);
            break;

        case 'openMenu':
            menuData = data.data;
            renderMenu(data.data);
            document.getElementById('race-tablet').classList.remove('hidden');
            break;

        case 'closeMenu':
            document.getElementById('race-tablet').classList.add('hidden');
            break;
    }
});

function handleCountdown(count) {
    const modal = document.getElementById('countdown-modal');
    const text = document.getElementById('countdown-text');
    modal.classList.remove('hidden');

    let remaining = count;
    text.textContent = remaining;

    const interval = setInterval(() => {
        remaining--;
        if (remaining > 0) {
            text.textContent = remaining;
            // Restart pulse animation
            text.style.animation = 'none';
            text.offsetHeight; /* trigger reflow */
            text.style.animation = 'countdownPulse 0.9s cubic-bezier(0.18, 0.89, 0.32, 1.28)';
        } else if (remaining === 0) {
            text.textContent = 'GO!';
            text.style.color = '#00e676';
            text.style.textShadow = '0 0 30px rgba(0, 230, 118, 0.8), 0 4px 15px rgba(0, 0, 0, 0.9)';
        } else {
            clearInterval(interval);
            modal.classList.add('hidden');
            text.style.color = '#00e5ff';
            text.style.textShadow = '0 0 30px rgba(0, 229, 255, 0.8), 0 4px 15px rgba(0, 0, 0, 0.9)';
        }
    }, 1000);
}

function handleResults(results) {
    if (!results) return;

    document.getElementById('results-route').textContent = results.routeName || 'Circuit Run';
    document.getElementById('results-time').textContent = formatTime(results.finalTimeMs);
    document.getElementById('results-reward').textContent = `$${(results.reward || 0).toLocaleString()} HELD`;
    document.getElementById('results-reward-sub').textContent = 'Stored in Racing Records // Cannot Be Collected In-Game';
    document.getElementById('results-xp').textContent = `+${results.xpGained || 0} XP`;
    document.getElementById('results-level').textContent = `Tier ${results.newLevel || 1} Driver`;

    const pbBadge = document.getElementById('results-pb-badge');
    if (results.isPersonalBest) {
        pbBadge.classList.remove('hidden');
    } else {
        pbBadge.classList.add('hidden');
    }

    document.getElementById('results-modal').classList.remove('hidden');
}

document.getElementById('btn-close-results').addEventListener('click', () => {
    document.getElementById('results-modal').classList.add('hidden');
});

// Tablet Tabs
const tabs = document.querySelectorAll('.nav-tab');
tabs.forEach(tab => {
    tab.addEventListener('click', () => {
        tabs.forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));

        tab.classList.add('active');
        const targetId = tab.getAttribute('data-tab');
        const panel = document.getElementById(targetId);
        if (panel) panel.classList.add('active');
    });
});

// Close Tablet
document.getElementById('btn-close-tablet').addEventListener('click', () => {
    fetch(`https://${GetParentResourceName()}/close`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
});

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        const tablet = document.getElementById('race-tablet');
        if (!tablet.classList.contains('hidden')) {
            fetch(`https://${GetParentResourceName()}/close`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
        }
        const results = document.getElementById('results-modal');
        if (!results.classList.contains('hidden')) {
            results.classList.add('hidden');
        }
    }
});

function renderMenu(data) {
    if (!data) return;

    renderTracks(data.routes || [], data.vehicle);
    renderVehicleScrutineering(data.vehicle);
    renderProfile(data.profile);
}

function renderTracks(routes, vehicle) {
    const container = document.getElementById('tracks-container');
    container.innerHTML = '';

    routes.forEach(route => {
        const card = document.createElement('div');
        card.className = `track-card ${!route.unlocked ? 'locked' : ''}`;

        let statusBadge = '';
        let canEnter = route.unlocked && !route.cooldown;

        if (!route.unlocked) {
            statusBadge = `<span class="badge badge-locked">LOCKED (LVL ${route.requiredLevel})</span>`;
        } else if (route.cooldown) {
            statusBadge = `<span class="badge badge-cooldown">COOLDOWN (${route.cooldownSeconds}s)</span>`;
        }

        const pbTime = route.personalBest ? formatTime(route.personalBest) : 'None';

        card.innerHTML = `
            <div class="track-info">
                <div class="track-top">
                    <span class="track-name">${route.name}</span>
                    <span class="badge badge-class">${route.category}</span>
                    ${statusBadge}
                </div>
                <div class="track-desc">${route.description}</div>
                <div class="track-meta">
                    <span>Checkpoints: <strong>${route.checkpointCount}</strong></span>
                    <span>Reward: <strong>$${route.reward.toLocaleString()}</strong></span>
                    <span>XP: <strong>+${route.xp}</strong></span>
                </div>
            </div>
            <div class="track-actions">
                <div class="track-pb">Best Lap: <span>${pbTime}</span></div>
                <button class="cm-btn cm-btn-primary btn-enter-race" data-route="${route.id}" ${canEnter ? '' : 'disabled'}>
                    ${canEnter ? 'ENTER TIME TRIAL' : (route.cooldown ? 'COOLDOWN' : 'LOCKED')}
                </button>
            </div>
        `;

        container.appendChild(card);
    });

    // Wire enter buttons
    document.querySelectorAll('.btn-enter-race').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const routeId = e.target.getAttribute('data-route');
            if (routeId) {
                fetch(`https://${GetParentResourceName()}/startRace`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ routeId: routeId })
                });
            }
        });
    });
}

function renderVehicleScrutineering(vehicle) {
    const statusBadge = document.getElementById('veh-status-badge');
    const roleElem = document.getElementById('veh-role');
    const plateElem = document.getElementById('veh-plate');
    const classElem = document.getElementById('veh-class');
    const regElem = document.getElementById('veh-registration');
    const notesElem = document.getElementById('veh-notes');

    if (!vehicle || !vehicle.inVehicle) {
        statusBadge.className = 'badge badge-unverified';
        statusBadge.textContent = 'NOT IN VEHICLE';
        roleElem.textContent = 'Pedestrian';
        plateElem.textContent = 'NONE';
        classElem.textContent = 'N/A';
        regElem.textContent = 'N/A';
        notesElem.textContent = vehicle && vehicle.reason === 'must_be_driver'
            ? 'You are seated in a passenger seat. You must take the driver seat to participate.'
            : 'You are not in a vehicle. Enter an authorized, registered road vehicle to inspect and stage for races.';
        return;
    }

    const info = vehicle.info || {};
    statusBadge.className = 'badge badge-verified';
    statusBadge.textContent = 'VERIFIED ROAD LEGAL';
    roleElem.textContent = 'Driver';
    plateElem.textContent = info.plate || 'UNKNOWN';
    classElem.textContent = `Class ${info.class !== undefined ? info.class : 'N/A'}`;
    regElem.textContent = info.dbId ? `ID #${info.dbId} (cm-vehicles)` : 'Authorized';
    notesElem.textContent = 'Vehicle verified. Telemetry sensors and mechanical state meet Sanctioned Racing Commission regulations.';
}

function renderProfile(profile) {
    if (!profile) return;

    const rankTitles = {
        1: 'Amateur Street License',
        2: 'Club Sport License',
        3: 'Grand Prix Pro License'
    };

    const level = profile.level || 1;
    const xp = profile.xp || 0;
    const title = rankTitles[level] || 'Sanctioned Competitor';

    document.getElementById('prof-level-title').textContent = title;
    document.getElementById('prof-level-num').textContent = level;
    document.getElementById('prof-races-count').textContent = profile.racesCompleted || 0;
    document.getElementById('prof-retained-wages').textContent = `$${(profile.pendingWages || 0).toLocaleString()}`;

    // XP calculation
    let maxLvlXp = 500;
    if (level === 2) maxLvlXp = 1500;
    if (level >= 3) maxLvlXp = 3000;

    const pct = Math.min(100, Math.floor((xp / maxLvlXp) * 100));
    document.getElementById('prof-xp-text').textContent = `${xp} / ${maxLvlXp} XP`;
    document.getElementById('prof-xp-bar').style.width = `${pct}%`;

    // Personal bests
    const recordsList = document.getElementById('records-list');
    recordsList.innerHTML = '';

    const pbs = profile.personalBests || {};
    const keys = Object.keys(pbs);

    if (keys.length === 0) {
        recordsList.innerHTML = `<div class="record-row"><span class="record-track">No timed laps recorded yet.</span></div>`;
    } else {
        keys.forEach(k => {
            const row = document.createElement('div');
            row.className = 'record-row';
            row.innerHTML = `
                <span class="record-track">${k.replace(/_/g, ' ').toUpperCase()}</span>
                <span class="record-time">${formatTime(pbs[k])}</span>
            `;
            recordsList.appendChild(row);
        });
    }
}
