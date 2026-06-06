const app = document.getElementById('app');
const slotsScreen = document.getElementById('slots-screen');
const creatorScreen = document.getElementById('creator-screen');
const errorMsg = document.getElementById('error-msg');
const creatorError = document.getElementById('creator-error');

let currentSlots = {};
let selectedSlot = null;

window.addEventListener('message', function(event) {
    const data = event.data;
    
    if (data.action === 'showSlots') {
        app.style.display = 'flex';
        slotsScreen.style.display = 'block';
        creatorScreen.style.display = 'none';
        currentSlots = data.slots || {};
        renderSlots();
    }
    
    if (data.action === 'showCreator') {
        slotsScreen.style.display = 'none';
        creatorScreen.style.display = 'block';
        selectedSlot = data.slot;
        clearCreator();
    }
    
    if (data.action === 'error') {
        showError(data.message);
    }
});

function renderSlots() {
    document.querySelectorAll('.slot').forEach(slotEl => {
        const slotNum = parseInt(slotEl.dataset.slot);
        const char = currentSlots[slotNum];
        
        const emptyDiv = slotEl.querySelector('.slot-empty');
        const infoDiv = slotEl.querySelector('.slot-info');
        
        if (char) {
            emptyDiv.style.display = 'none';
            infoDiv.style.display = 'block';
            infoDiv.innerHTML = `
                <div class="unique-id">ID: #${char.uniqueId}</div>
                <div class="name">${char.name}</div>
                <div class="detail">Gender: ${char.gender}</div>
                <div class="detail">Cash: $${char.cash}</div>
                <div class="detail">Bank: $${char.bank}</div>
                <div class="detail">Rank: ${char.rank}</div>
                <div class="permanent-tag">PERMANENT</div>
            `;
            // NO DELETE BUTTON
        } else {
            emptyDiv.style.display = 'block';
            infoDiv.style.display = 'none';
            infoDiv.innerHTML = '';
        }
    });
}

function selectSlot(slot) {
    const char = currentSlots[slot];
    if (char) {
        // Select existing
        fetch(`https://${GetParentResourceName()}/selectSlot`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ charId: char.id })
        });
    } else {
        // Create new
        fetch(`https://${GetParentResourceName()}/selectSlot`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ slot: slot })
        });
    }
}

function deleteChar(charId, slot) {
    if (!confirm('Delete this character?')) return;
    fetch(`https://${GetParentResourceName()}/deleteCharacter`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ charId: charId })
    });
}

function createCharacter() {
    const firstName = document.getElementById('first-name').value.trim();
    const lastName = document.getElementById('last-name').value.trim();
    const dob = document.getElementById('dob').value;
    const gender = document.getElementById('gender').value;
    
    if (!firstName || !lastName) {
        showCreatorError('Enter first and last name');
        return;
    }
    
    fetch(`https://${GetParentResourceName()}/createCharacter`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            slot: selectedSlot,
            firstName: firstName,
            lastName: lastName,
            dob: dob,
            gender: gender,
            appearance: {}
        })
    });
}

function showSlots() {
    slotsScreen.style.display = 'block';
    creatorScreen.style.display = 'none';
}

function showError(msg) {
    errorMsg.textContent = msg;
    errorMsg.className = 'show';
    setTimeout(() => errorMsg.className = '', 3000);
}

function showCreatorError(msg) {
    creatorError.textContent = msg;
    creatorError.className = 'show';
    setTimeout(() => creatorError.className = '', 3000);
}

function clearCreator() {
    document.getElementById('first-name').value = '';
    document.getElementById('last-name').value = '';
    document.getElementById('dob').value = '';
    document.getElementById('gender').value = 'male';
    creatorError.className = '';
}