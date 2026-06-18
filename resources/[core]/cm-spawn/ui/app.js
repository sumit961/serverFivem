// cm-spawn/ui/app.js

const spawnSelector = document.getElementById('spawn-selector');
const spawnGrid = document.getElementById('spawn-grid');
const tutorial = document.getElementById('tutorial');
const tutorialTitle = document.getElementById('tutorial-title');
const tutorialText = document.getElementById('tutorial-text');
const stepCurrent = document.getElementById('step-current');
const stepTotal = document.getElementById('step-total');
const progressBar = document.getElementById('progress-bar');

let selecting = false;

function nui(path, payload) {
    return fetch(`https://${GetParentResourceName()}/${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
    });
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, ch => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
    }[ch]));
}

window.addEventListener('message', function(event) {
    const data = event.data || {};

    if (data.action === 'openSelector') {
        selecting = false;
        spawnSelector.style.display = 'flex';
        requestAnimationFrame(() => spawnSelector.classList.add('visible'));

        if (data.player) {
            document.getElementById('player-name').textContent = data.player.name || 'PLAYER';
            document.getElementById('player-cash').textContent = '$' + Number(data.player.cash || 0).toLocaleString('en-US');
        }

        renderSpawns(data.spawns || []);
    }

    if (data.action === 'closeSelector') {
        closeSelectorUi();
    }

    if (data.action === 'showTutorial') {
        tutorial.style.display = 'flex';
        updateTutorial(data.step, data.total, data.title, data.text);
    }

    if (data.action === 'updateTutorial') {
        updateTutorial(data.step, data.total, data.title, data.text);
    }

    if (data.action === 'hideTutorial') {
        tutorial.style.display = 'none';
    }
});

function closeSelectorUi() {
    spawnSelector.classList.remove('visible');
    setTimeout(() => { spawnSelector.style.display = 'none'; }, 250);
}

function renderSpawns(spawns) {
    spawnGrid.innerHTML = '';

    spawns.forEach((spawn, index) => {
        const card = document.createElement('button');
        const colorClass = spawn.color || 'blue';
        card.type = 'button';
        card.className = `spawn-card ${colorClass}${spawn.locked ? ' locked' : ''}`;
        card.style.setProperty('--delay', `${index * 70}ms`);

        if (spawn.image) {
            card.style.backgroundImage = `url('${escapeHtml(spawn.image)}')`;
        }

        card.innerHTML = `
            <div class="spawn-card-overlay"></div>
            <div class="spawn-content">
                <div class="spawn-icon"><i class="fa-solid ${escapeHtml(spawn.icon || 'fa-location-dot')}"></i></div>
                <div class="spawn-label-row">
                    <span class="spawn-number">${String(index + 1).padStart(2, '0')}</span>
                    <h2>${escapeHtml(spawn.label || spawn.key)}</h2>
                </div>
                <p>${escapeHtml(spawn.description || '')}</p>
                ${spawn.locked ? `<div class="locked-badge"><i class="fa-solid fa-lock"></i>${escapeHtml(spawn.lockedReason || 'Locked')}</div>` : '<div class="spawn-button">Spawn Here</div>'}
            </div>
        `;

        if (!spawn.locked) {
            card.addEventListener('click', () => selectSpawn(spawn.key));
        }

        spawnGrid.appendChild(card);
    });
}

function selectSpawn(key) {
    if (selecting) return;
    selecting = true;
    document.body.classList.add('is-spawning');
    nui('selectSpawn', { spawnKey: key });
    closeSelectorUi();
}

function updateTutorial(step, total, title, text) {
    stepCurrent.textContent = step;
    stepTotal.textContent = total;
    tutorialTitle.textContent = title;
    tutorialText.textContent = text;
    progressBar.style.width = ((step / total) * 100) + '%';
}

document.addEventListener('keydown', function(e) {
    if (e.code === 'Escape' && spawnSelector.style.display !== 'none') return;
    if (e.code === 'Space' && tutorial.style.display !== 'none') {
        nui('closeSpawn', {});
        tutorial.style.display = 'none';
    }
});
