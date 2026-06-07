// cm-characters/ui/app.js

console.log('[CM-CHARACTERS-UI] app.js loaded!');

const app = document.getElementById('app');
const slotsScreen = document.getElementById('slots-screen');
const creatorScreen = document.getElementById('creator-screen');
const errorMsg = document.getElementById('error-msg');
const creatorError = document.getElementById('creator-error');

let currentSlots = {};
let selectedSlot = null;
let isCreatingChar = false;



window.addEventListener('message', function(event) {
    const data = event.data;
    console.log('[CM-CHARACTERS-UI] Message received: ' + JSON.stringify(data));
    
    if (data.action === "closeAppearance") {
        document.body.style.display = 'none';
        document.getElementById('appearance-ui').style.display = 'none';
    }

    if (data.action === 'showApp') {
        console.log('[CM-CHARACTERS-UI] Showing app container');
        if (app) app.style.display = 'flex';
    }
    
    if (data.action === 'showSlots') {
        console.log('[CM-CHARACTERS-UI] showSlots received');
        
        if (app) app.style.display = 'flex';
        if (slotsScreen) slotsScreen.style.display = 'block';
        if (creatorScreen) creatorScreen.style.display = 'none';
        
        // Convert array to object with proper keys
        currentSlots = {};
        if (data.slots) {
            if (Array.isArray(data.slots)) {
                for (let i = 0; i < data.slots.length; i++) {
                    if (data.slots[i]) {
                        currentSlots[i + 1] = data.slots[i];
                    }
                }
            } else {
                currentSlots = data.slots;
            }
        }
        
        console.log('[CM-CHARACTERS-UI] currentSlots keys: ' + Object.keys(currentSlots).join(', '));
        
        renderSlots();
    }
    
    if (data.action === 'showCreator') {
        console.log('[CM-CHARACTERS-UI] showCreator received');
        if (slotsScreen) slotsScreen.style.display = 'none';
        if (creatorScreen) creatorScreen.style.display = 'block';
        selectedSlot = data.slot;
        isCreatingChar = false;
        clearCreator();
    }
    
    if (data.action === 'hideCreator') {
        console.log('[CM-CHARACTERS-UI] hideCreator received');
        if (creatorScreen) creatorScreen.style.display = 'none';
    }
    
    // FIX: Hide everything when spawning
    if (data.action === 'hideAll') {
        console.log('[CM-CHARACTERS-UI] hideAll received - hiding everything');
        if (app) app.style.display = 'none';
        if (slotsScreen) slotsScreen.style.display = 'none';
        if (creatorScreen) creatorScreen.style.display = 'none';
    }
    
    if (data.action === 'error') {
        console.log('[CM-CHARACTERS-UI] error received: ' + data.message);
        isCreatingChar = false;
        if (creatorScreen && creatorScreen.style.display === 'block') {
            showCreatorError(data.message);
        } else {
            showError(data.message);
        }
    }
});

function renderSlots() {
    console.log('[CM-CHARACTERS-UI] renderSlots called');
    
    const slotElements = document.querySelectorAll('.slot');
    console.log('[CM-CHARACTERS-UI] Found ' + slotElements.length + ' slot elements');
    
    slotElements.forEach(slotEl => {
        const slotNum = parseInt(slotEl.dataset.slot);
        console.log('[CM-CHARACTERS-UI] Processing slot ' + slotNum);
        
        const char = currentSlots[slotNum];
        console.log('[CM-CHARACTERS-UI] char for slot ' + slotNum + ': ' + JSON.stringify(char));
        
        const emptyDiv = slotEl.querySelector('.slot-empty');
        const infoDiv = slotEl.querySelector('.slot-info');
        
        if (!emptyDiv || !infoDiv) {
            console.error('[CM-CHARACTERS-UI] Missing empty or info div!');
            return;
        }
        
        if (char) {
            console.log('[CM-CHARACTERS-UI] Slot ' + slotNum + ' has character: ' + char.name);
            emptyDiv.style.display = 'none';
            infoDiv.style.display = 'block';
            
            // FIX: Add face preview placeholder (we'll improve this later)
            const genderIcon = char.gender === 'female' ? 'fa-person-dress' : 'fa-person';
            
            infoDiv.innerHTML = `
                <div class="char-face-preview">
                    <i class="fa-solid ${genderIcon} face-icon"></i>
                </div>
                <div class="unique-id">ID: #${char.uniqueId || 'N/A'}</div>
                <div class="name">${char.name || 'Unknown'}</div>
                <div class="detail">Gender: ${char.gender || 'N/A'}</div>
                <div class="detail">Cash: $${char.cash || 0}</div>
                <div class="detail">Bank: $${char.bank || 0}</div>
                <div class="detail">Rank: ${char.rank || 'N/A'}</div>
                <div class="permanent-tag">PERMANENT</div>
            `;
        } else {
            console.log('[CM-CHARACTERS-UI] Slot ' + slotNum + ' is empty');
            emptyDiv.style.display = 'block';
            infoDiv.style.display = 'none';
            infoDiv.innerHTML = '';
        }
    });
}

function selectSlot(slot) {
    console.log('[CM-CHARACTERS-UI] selectSlot called: ' + slot);
    const char = currentSlots[slot];
    if (char) {
        console.log('[CM-CHARACTERS-UI] Selecting existing character: ' + char.uniqueId);
        // FIX: Show loading state
        const slotEl = document.querySelector('.slot[data-slot="' + slot + '"]');
        if (slotEl) {
            slotEl.style.opacity = '0.5';
        }
        
        fetch(`https://${GetParentResourceName()}/selectSlot`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ charId: char.uniqueId })
        });
    } else {
        console.log('[CM-CHARACTERS-UI] Opening creator for slot: ' + slot);
        fetch(`https://${GetParentResourceName()}/selectSlot`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ slot: slot })
        });
    }
}

function createCharacter() {
    console.log('[CM-CHARACTERS-UI] createCharacter called');
    if (isCreatingChar) {
        console.log('[CM-CHARACTERS-UI] Already creating, ignored');
        return;
    }
    
    const firstName = document.getElementById('first-name').value.trim();
    const lastName = document.getElementById('last-name').value.trim();
    const dob = document.getElementById('dob').value;
    const gender = document.getElementById('gender').value;
    
    console.log('[CM-CHARACTERS-UI] Form data: ' + firstName + ' ' + lastName + ', ' + gender);
    
    if (!firstName || !lastName) {
        showCreatorError('Enter first and last name');
        return;
    }
    
    isCreatingChar = true;
    
    fetch(`https://${GetParentResourceName()}/createCharacter`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            firstName: firstName,
            lastName: lastName,
            dob: dob,
            gender: gender
        })
    }).then(r => r.text()).then(t => {
        console.log('[CM-CHARACTERS-UI] createCharacter response: ' + t);
    });
}

function showSlots() {
    console.log('[CM-CHARACTERS-UI] showSlots called');
    if (slotsScreen) slotsScreen.style.display = 'block';
    if (creatorScreen) creatorScreen.style.display = 'none';
    isCreatingChar = false;
    fetch(`https://${GetParentResourceName()}/closeCreator`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

function showError(msg) {
    console.log('[CM-CHARACTERS-UI] showError: ' + msg);
    if (errorMsg) {
        errorMsg.textContent = msg;
        errorMsg.className = 'show';
        setTimeout(() => errorMsg.className = '', 3000);
    }
}

function showCreatorError(msg) {
    console.log('[CM-CHARACTERS-UI] showCreatorError: ' + msg);
    if (creatorError) {
        creatorError.textContent = msg;
        creatorError.className = 'show';
        setTimeout(() => creatorError.className = '', 3000);
    }
}

function clearCreator() {
    const fn = document.getElementById('first-name');
    const ln = document.getElementById('last-name');
    const dob = document.getElementById('dob');
    const gen = document.getElementById('gender');
    if (fn) fn.value = '';
    if (ln) ln.value = '';
    if (dob) dob.value = '';
    if (gen) gen.value = 'male';
    if (creatorError) creatorError.className = '';
}

window.selectSlot = selectSlot;
window.createCharacter = createCharacter;
window.showSlots = showSlots;

console.log('[CM-CHARACTERS-UI] app.js ready');