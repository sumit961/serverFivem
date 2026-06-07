// cm-spawn/ui/app.js

const spawnSelector = document.getElementById('spawn-selector');
const spawnGrid = document.getElementById('spawn-grid');
const tutorial = document.getElementById('tutorial');
const tutorialTitle = document.getElementById('tutorial-title');
const tutorialText = document.getElementById('tutorial-text');
const stepCurrent = document.getElementById('step-current');
const stepTotal = document.getElementById('step-total');
const progressBar = document.getElementById('progress-bar');

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'openSelector') {
        spawnSelector.style.display = 'flex';
        
        if (data.player) {
            document.getElementById('player-name').textContent = data.player.name || 'PLAYER';
            document.getElementById('player-cash').textContent = '$' + (data.player.cash || 0);
        }
        
        renderSpawns(data.spawns);
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

function renderSpawns(spawns) {
    spawnGrid.innerHTML = '';
    
    spawns.forEach(spawn => {
        const card = document.createElement('div');
        const colorClass = spawn.color || 'blue';
        card.className = 'spawn-card ' + colorClass + (spawn.locked ? ' locked' : '');
        
        let html = `
            <h2>${spawn.label}</h2>
            <p>${spawn.description}</p>
        `;
        
        if (spawn.locked) {
            html += `<div class="lock-icon"><i class="fa-solid fa-lock"></i></div>`;
        }
        
        card.innerHTML = html;
        
        if (!spawn.locked) {
            card.onclick = () => selectSpawn(spawn.key);
        }
        
        spawnGrid.appendChild(card);
    });
}

function selectSpawn(key) {
    fetch(`https://${GetParentResourceName()}/selectSpawn`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ spawnKey: key })
    });
    spawnSelector.style.display = 'none';
}

function updateTutorial(step, total, title, text) {
    stepCurrent.textContent = step;
    stepTotal.textContent = total;
    tutorialTitle.textContent = title;
    tutorialText.textContent = text;
    progressBar.style.width = ((step / total) * 100) + '%';
}

// Skip tutorial on space
document.addEventListener('keydown', function(e) {
    if (e.code === 'Space' && tutorial.style.display !== 'none') {
        fetch(`https://${GetParentResourceName()}/closeSpawn`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
        tutorial.style.display = 'none';
    }
});