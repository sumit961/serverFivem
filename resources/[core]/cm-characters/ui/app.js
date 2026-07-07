// cm-characters/ui/app.js
// GTA-style selector UI with details panel and background music mute option.

const app = document.getElementById('app');
const slotsScreen = document.getElementById('slots-screen');
const creatorScreen = document.getElementById('creator-screen');
const characterList = document.getElementById('character-list');
const characterCount = document.getElementById('character-count');
const errorMsg = document.getElementById('error-msg');
const creatorError = document.getElementById('creator-error');
const playBtn = document.getElementById('play-btn');
const musicToggle = document.getElementById('music-toggle');
const appearanceMusicToggle = document.getElementById('appearance-music-toggle');
const bgm = document.getElementById('character-bgm');
const creationLoading = document.getElementById('creation-loading');
const creationLoadingText = document.getElementById('creation-loading-text');
const creationLoadingPercent = document.getElementById('creation-loading-percent');
const creationLoadingBar = document.getElementById('creation-loading-bar');
let loadingTimer = null;
let finishingTimer = null;
let finishingTimeout = null;
let loadingPercentValue = 0;
let loaderHoldingSelector = false;
let spawnFlowActive = false;

function forceHideCharacterLoader() {
    if (loadingTimer) { clearInterval(loadingTimer); loadingTimer = null; }
    if (finishingTimer) { clearInterval(finishingTimer); finishingTimer = null; }
    if (finishingTimeout) { clearTimeout(finishingTimeout); finishingTimeout = null; }
    loadingPercentValue = 0;
    if (creationLoadingPercent) creationLoadingPercent.textContent = '0%';
    if (creationLoadingBar) creationLoadingBar.style.width = '0%';
    if (creationLoading) {
        creationLoading.classList.add('hidden');
        creationLoading.classList.remove('finishing');
        creationLoading.style.display = 'none';
    }
}

function hideSelectorBehindLoader() {
    if (!app) return;
    app.style.display = 'none';
    app.style.visibility = 'hidden';
    app.style.opacity = '0';
}

const detailEls = {
    name: document.getElementById('details-name'),
    id: document.getElementById('details-id'),
    cash: document.getElementById('details-cash'),
    bank: document.getElementById('details-bank'),
    level: document.getElementById('details-level'),
    rank: document.getElementById('details-rank'),
    gender: document.getElementById('details-gender'),
    playtime: document.getElementById('details-playtime'),
    created: document.getElementById('details-created')
};

let currentSlots = {};
let lastSlotsSignature = '';
let slotsAlreadyRendered = false;
let selectedCharacter = null;
let selectedSlot = null;
let isCreatingChar = false;
let lastExistingSlot = null;
let maxCharacters = 2;

function resourceUrl(path) {
    return `https://${GetParentResourceName()}/${path}`;
}

function post(path, payload) {
    return fetch(resourceUrl(path), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
    });
}

function makeSlotsSignature(slots, max) {
    const safeSlots = slots || {};
    const count = Number(max || 2);
    const parts = [];
    for (let i = 1; i <= count; i += 1) {
        const ch = safeSlots[String(i)] || safeSlots[i];
        if (ch) {
            parts.push([
                i,
                ch.uniqueId || ch.charId || '',
                ch.name || '',
                ch.firstName || '',
                ch.lastName || '',
                ch.gender || ''
            ].join(':'));
        } else {
            parts.push(`${i}:empty`);
        }
    }
    return parts.join('|');
}

function setCreationLoading(show, message, targetPercent) {
    if (!creationLoading) return;
    if (creationLoadingText && message) creationLoadingText.textContent = message;

    const setPercent = (value) => {
        loadingPercentValue = Math.max(0, Math.min(100, Math.floor(value)));
        if (creationLoadingPercent) creationLoadingPercent.textContent = `${loadingPercentValue}%`;
        if (creationLoadingBar) creationLoadingBar.style.width = `${loadingPercentValue}%`;
    };

    const clearLoadingTimer = () => {
        if (loadingTimer) {
            clearInterval(loadingTimer);
            loadingTimer = null;
        }
    };

    if (show) {
        if (spawnFlowActive) {
            forceHideCharacterLoader();
            return;
        }
        clearLoadingTimer();
        creationLoading.classList.remove('hidden', 'finishing');
        creationLoading.style.display = 'flex';
        setPercent(targetPercent || 0);

        // Do not reach 100 until Lua says the preview is actually ready.
        // This stops the loading UI from closing/breaking before the bar finishes.
        loadingTimer = setInterval(() => {
            const cap = targetPercent && targetPercent >= 100 ? 100 : 94;
            if (loadingPercentValue < cap) {
                setPercent(loadingPercentValue + Math.max(1, Math.floor((cap - loadingPercentValue) / 10)));
            }
        }, 110);
    } else {
        clearLoadingTimer();
        if (finishingTimer) { clearInterval(finishingTimer); finishingTimer = null; }
        if (finishingTimeout) { clearTimeout(finishingTimeout); finishingTimeout = null; }
        creationLoading.classList.remove('hidden');
        creationLoading.classList.add('finishing');
        creationLoading.style.display = 'flex';

        // Always visually complete to 100 first, then close smoothly.
        finishingTimer = setInterval(() => {
            if (loadingPercentValue < 100) {
                setPercent(Math.min(100, loadingPercentValue + Math.max(2, Math.floor((100 - loadingPercentValue) / 4))));
                return;
            }

            clearInterval(finishingTimer);
            finishingTimer = null;
            finishingTimeout = setTimeout(() => {
                finishingTimeout = null;
                creationLoading.classList.add('hidden');
                creationLoading.classList.remove('finishing');
                creationLoading.style.display = '';
                setPercent(0);

                if (loaderHoldingSelector) {
                    loaderHoldingSelector = false;
                    forceSelectorVisible();
                }
            }, 450);
        }, 45);
    }
}

function forceSelectorVisible() {
    if (!app || !slotsScreen || !creatorScreen) return;
    app.style.display = 'block';
    app.style.visibility = 'visible';
    app.style.opacity = '1';
    app.classList.remove('hidden');
    slotsScreen.classList.remove('hidden');
    creatorScreen.classList.add('hidden');
}

function money(value) {
    const num = Number(value || 0);
    return '$' + num.toLocaleString('en-US');
}

function titleCase(value) {
    value = String(value || 'N/A');
    return value.charAt(0).toUpperCase() + value.slice(1);
}

function formatPlaytime(minutes) {
    const total = Number(minutes || 0);
    if (total <= 0) return '0h';
    const hours = Math.floor(total / 60);
    const mins = total % 60;
    if (hours <= 0) return `${mins}m`;
    return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
}

function formatDate(value) {
    if (!value) return 'N/A';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value).split('T')[0];
    return date.toLocaleDateString('en-AU', { year: 'numeric', month: 'short', day: 'numeric' });
}

function slotValue(slot) {
    return currentSlots[String(slot)] || currentSlots[slot] || null;
}

function getExistingCharacters() {
    const chars = [];
    for (let slot = 1; slot <= maxCharacters; slot++) {
        const char = slotValue(slot);
        if (char && char.uniqueId) chars.push({ slot, char });
    }
    return chars;
}

function getFirstEmptySlot() {
    for (let slot = 1; slot <= maxCharacters; slot++) {
        if (!slotValue(slot)) return slot;
    }
    return null;
}

function setMusicState(muted) {
    if (!bgm) return;
    bgm.muted = muted;
    localStorage.setItem('cm_char_music_muted', muted ? '1' : '0');
    [musicToggle, appearanceMusicToggle].forEach((button) => {
        if (button) button.textContent = muted ? 'Music: Off' : 'Music: On';
    });
}

function startMusic() {
    if (!bgm) return;
    bgm.volume = 0.32;
    const mutedPref = localStorage.getItem('cm_char_music_muted');
    const muted = mutedPref === null ? true : mutedPref === '1';
    setMusicState(muted);
    if (muted) return;
    const attempt = bgm.play();
    if (attempt && typeof attempt.catch === 'function') attempt.catch(() => {});
}

function stopMusic() {
    if (!bgm) return;
    bgm.pause();
    bgm.currentTime = 0;
}

function renderSlots(options) {
    options = options || {};
    if (!characterList) return;

    const previousCharId = selectedCharacter && (selectedCharacter.uniqueId || selectedCharacter.charId);
    const existing = getExistingCharacters();
    const emptySlot = getFirstEmptySlot();
    const total = existing.length;
    lastExistingSlot = existing[0] ? existing[0].slot : null;

    characterList.innerHTML = '';
    characterCount.textContent = total === 0
        ? 'No characters found. Create your first character.'
        : `${total} character${total === 1 ? '' : 's'} available. Select one to preview details.`;

    existing.forEach(({ slot, char }) => {
        const card = document.createElement('button');
        card.type = 'button';
        card.className = 'character-card';
        card.dataset.slot = String(slot);
        card.dataset.charId = String(char.uniqueId || '');

        const top = document.createElement('div');
        top.className = 'card-topline';
        const slotText = document.createElement('span');
        slotText.textContent = `Slot ${slot}`;
        const idText = document.createElement('strong');
        idText.textContent = `#${char.uniqueId || 'N/A'}`;
        top.append(slotText, idText);

        const badge = document.createElement('div');
        badge.className = `avatar-badge ${String(char.gender).toLowerCase() === 'female' ? 'female' : 'male'}`;
        badge.textContent = String(char.gender).toLowerCase() === 'female' ? 'F' : 'M';

        const title = document.createElement('h3');
        title.textContent = char.name || 'Unknown Character';
        const meta = document.createElement('p');
        meta.textContent = `${titleCase(char.gender)} · Level ${char.level || 1}`;

        const stats = document.createElement('div');
        stats.className = 'mini-stats';
        const cash = document.createElement('span');
        cash.textContent = money(char.cash);
        const bank = document.createElement('span');
        bank.textContent = `${money(char.bank)} bank`;
        stats.append(cash, bank);

        card.append(top, badge, title, meta, stats);
        card.addEventListener('click', () => selectCharacterCard(slot, char.uniqueId));
        characterList.appendChild(card);
    });

    if (emptySlot) {
        const createCard = document.createElement('button');
        createCard.type = 'button';
        createCard.className = 'character-card create-card';
        createCard.dataset.slot = String(emptySlot);
        createCard.innerHTML = `
            <div class="card-topline">
                <span>Slot ${emptySlot}</span>
                <strong>New</strong>
            </div>
            <div class="create-plus">+</div>
            <h3>Create Character</h3>
            <p>Start a new story in this slot.</p>
        `;
        createCard.addEventListener('click', () => openCreatorSlot(emptySlot));
        characterList.appendChild(createCard);
    }

    if (existing.length > 0) {
        let target = null;
        if (options.preserveSelection && previousCharId) {
            target = existing.find(({ char }) => String(char.uniqueId || char.charId) === String(previousCharId));
        }
        if (target) {
            selectCharacterCard(target.slot, target.char.uniqueId, options.skipPreview === true);
        } else if (options.noAutoSelect !== true) {
            selectCharacterCard(existing[0].slot, existing[0].char.uniqueId, options.skipPreview === true);
        } else {
            clearDetails();
        }
    } else {
        clearDetails();
    }
}

function clearDetails() {
    selectedCharacter = null;
    selectedSlot = null;
    detailEls.name.textContent = 'Select a character';
    detailEls.id.textContent = 'Pick one of your saved characters to view stats.';
    detailEls.cash.textContent = '$0';
    detailEls.bank.textContent = '$0';
    detailEls.level.textContent = '1';
    detailEls.rank.textContent = 'Civilian';
    detailEls.gender.textContent = 'N/A';
    detailEls.playtime.textContent = '0h';
    detailEls.created.textContent = 'N/A';
    playBtn.disabled = true;
}

function selectCharacterCard(slot, charId, skipPreview) {
    const char = slotValue(slot);
    if (!char) return;

    selectedSlot = slot;
    selectedCharacter = char;

    document.querySelectorAll('.character-card').forEach(card => {
        card.classList.toggle('active', card.dataset.charId === String(charId));
    });

    detailEls.name.textContent = char.name || 'Unknown Character';
    detailEls.id.textContent = `Permanent ID #${char.uniqueId || 'N/A'}`;
    detailEls.cash.textContent = money(char.cash);
    detailEls.bank.textContent = money(char.bank);
    detailEls.level.textContent = String(char.level || 1);
    detailEls.rank.textContent = String(char.rank || 'Civilian');
    detailEls.gender.textContent = titleCase(char.gender);
    detailEls.playtime.textContent = formatPlaytime(char.playtime);
    detailEls.created.textContent = formatDate(char.created);
    playBtn.disabled = false;

    if (skipPreview !== true) {
        post('previewCharacter', { slot, charId: char.uniqueId }).catch(() => {});
    }
}

function selectCurrentCharacter() {
    if (!selectedCharacter || !selectedCharacter.uniqueId) {
        showError('Select a character first.');
        return;
    }

    playBtn.disabled = true;
    playBtn.textContent = 'Entering...';
    post('selectSlot', { charId: selectedCharacter.uniqueId }).catch(() => {
        playBtn.disabled = false;
        playBtn.textContent = 'Enter City';
        showError('Could not select character. Try again.');
    });
}

function openCreatorSlot(slot) {
    post('selectSlot', { slot }).catch(() => showError('Could not open creator.'));
}

window.addEventListener('message', function(event) {
    const data = event.data || {};

    if (data.action === 'spawnStarted') {
        spawnFlowActive = true;
        loaderHoldingSelector = false;
        forceHideCharacterLoader();
        if (app) app.classList.add('hidden');
        if (slotsScreen) slotsScreen.classList.add('hidden');
        if (creatorScreen) creatorScreen.classList.add('hidden');
        stopMusic();
        return;
    }

    if (data.action === 'forceHideLoading') {
        loaderHoldingSelector = false;
        forceHideCharacterLoader();
        return;
    }

    if (data.action === 'creationLoading') {
        setCreationLoading(data.show === true, data.message || 'Loading character creator...', data.percent);
    }

    if (data.action === 'closeAppearance') {
        document.getElementById('appearance-ui').style.display = 'none';
    }

    if (data.action === 'openAppearance') {
        startMusic();
    }

    if (data.action === 'showApp') {
        if (loaderHoldingSelector) {
            hideSelectorBehindLoader();
        } else {
            forceSelectorVisible();
        }
        startMusic();
    }

    if (data.action === 'showSlots') {
        spawnFlowActive = false;

        const newSlots = data.slots || {};
        const newMaxCharacters = Number(data.maxCharacters || 2);
        const signature = makeSlotsSignature(newSlots, newMaxCharacters);
        const duplicateSlots = slotsAlreadyRendered && signature === lastSlotsSignature;
        const firstSelectorRender = !slotsAlreadyRendered && data.replay !== true;

        // cm-auth/spawn fallback/uiReady can resend the same slot payload. Do not
        // restart the loading overlay or re-render cards for a duplicate replay,
        // because renderSlots auto-selects the first character and would ask Lua
        // to spawn the preview ped again.
        if (duplicateSlots) {
            currentSlots = newSlots;
            maxCharacters = newMaxCharacters;
            startMusic();
            return;
        }

        if (firstSelectorRender) {
            loaderHoldingSelector = true;
            hideSelectorBehindLoader();
            setCreationLoading(true, 'Loading character preview...', 35);
            selectedCharacter = null;
            selectedSlot = null;
            if (playBtn) {
                playBtn.textContent = 'Enter City';
                playBtn.disabled = true;
            }
        } else {
            loaderHoldingSelector = false;
            forceSelectorVisible();
        }

        isCreatingChar = false;
        currentSlots = newSlots;
        maxCharacters = newMaxCharacters;
        lastSlotsSignature = signature;
        slotsAlreadyRendered = true;
        renderSlots({ preserveSelection: !firstSelectorRender, skipPreview: !firstSelectorRender });
        startMusic();
    }

    if (data.action === 'showCreator') {
        loaderHoldingSelector = false;
        forceHideCharacterLoader();
        app.style.display = 'block';
        app.style.visibility = 'visible';
        app.style.opacity = '1';
        app.classList.remove('hidden');
        slotsScreen.classList.add('hidden');
        creatorScreen.classList.remove('hidden');
        selectedSlot = data.slot;
        isCreatingChar = false;
        clearCreator();
    }

    if (data.action === 'hideCreator') {
        creatorScreen.classList.add('hidden');
    }

    if (data.action === 'hideAll') {
        spawnFlowActive = true;
        loaderHoldingSelector = false;
        slotsAlreadyRendered = false;
        lastSlotsSignature = '';
        forceHideCharacterLoader();
        app.classList.add('hidden');
        slotsScreen.classList.add('hidden');
        creatorScreen.classList.add('hidden');
        stopMusic();
    }

    if (data.action === 'error') {
        isCreatingChar = false;
        playBtn.disabled = !selectedCharacter;
        playBtn.textContent = 'Enter City';
        if (!creatorScreen.classList.contains('hidden')) {
            showCreatorError(data.message);
        } else {
            showError(data.message);
        }
    }
});

function createCharacter() {
    if (isCreatingChar) return;

    const firstName = document.getElementById('first-name').value.trim();
    const lastName = document.getElementById('last-name').value.trim();
    const dob = document.getElementById('dob').value;
    const gender = document.getElementById('gender').value;

    if (!firstName || !lastName) {
        showCreatorError('Enter first and last name.');
        return;
    }

    isCreatingChar = true;
    post('createCharacter', { firstName, lastName, dob, gender }).catch(() => {
        isCreatingChar = false;
        showCreatorError('Could not create character. Try again.');
    });
}

function showSlots() {
    slotsScreen.classList.remove('hidden');
    creatorScreen.classList.add('hidden');
    isCreatingChar = false;
    post('closeCreator', {}).catch(() => {});
}

function showError(msg) {
    if (!errorMsg) return;
    errorMsg.textContent = msg || 'Something went wrong.';
    errorMsg.classList.add('show');
    setTimeout(() => errorMsg.classList.remove('show'), 3500);
}

function showCreatorError(msg) {
    if (!creatorError) return;
    creatorError.textContent = msg || 'Something went wrong.';
    creatorError.classList.add('show');
    setTimeout(() => creatorError.classList.remove('show'), 3500);
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
    if (creatorError) creatorError.classList.remove('show');
}

playBtn.addEventListener('click', selectCurrentCharacter);

[musicToggle, appearanceMusicToggle].forEach((button) => {
    if (!button) return;
    button.addEventListener('click', () => {
        setMusicState(!bgm.muted);
        if (!bgm.muted) bgm.play().catch(() => {});
    });
});

window.selectSlot = function(slot) {
    const char = slotValue(slot);
    if (char) selectCharacterCard(slot, char.uniqueId);
    else openCreatorSlot(slot);
};
window.createCharacter = createCharacter;
window.showSlots = showSlots;

setMusicState(localStorage.getItem('cm_char_music_muted') !== '0');


window.addEventListener('DOMContentLoaded', () => {
    startMusic();
    post('uiReady', { reason: 'dom' }).catch(() => {});

    // Safety pings stay, but Lua now treats them as soft UI refresh only and will
    // not request slots/restart the preview loader again.
    setTimeout(() => post('uiReady', { reason: 'safety_500' }).catch(() => {}), 500);
    setTimeout(() => post('uiReady', { reason: 'safety_1500' }).catch(() => {}), 1500);
});

// v1.3.1 selector scene editor UI
const editorScreen = document.getElementById('editor-screen');
const editorCard = document.getElementById('editor-card');
const editorFreePreview = document.getElementById('editor-free-preview');
const editorClose = document.getElementById('editor-close');
const editorSave = document.getElementById('editor-save');
const editorToast = document.getElementById('editor-toast');
const editorJson = document.getElementById('editor-json');
const editorFov = document.getElementById('editor-fov');
const editorFovValue = document.getElementById('editor-fov-value');
const editorWeather = document.getElementById('editor-weather');
const editorHour = document.getElementById('editor-hour');
const editorMinute = document.getElementById('editor-minute');
const editorTimeValue = document.getElementById('editor-time-value');
const editorAnimPreset = document.getElementById('editor-anim-preset');
let editorScene = null;

function showEditorToast(message, type = 'success') {
    if (!editorToast) return;
    editorToast.textContent = message || '';
    editorToast.classList.add('show');
    editorToast.classList.toggle('error', type === 'error');
    setTimeout(() => editorToast.classList.remove('show'), 3200);
}

function openSceneEditor(scene) {
    editorScene = scene || editorScene || {};
    app.classList.remove('hidden');
    if (editorScreen) editorScreen.classList.remove('hidden');
    if (editorCard) editorCard.classList.remove('is-hidden-for-preview');
    if (editorFreePreview) editorFreePreview.textContent = 'Hide editor / preview';
    renderSceneEditor();
}

function closeSceneEditor() {
    if (editorScreen) editorScreen.classList.add('hidden');
    post('editorClose', {}).catch(() => {});
}

function renderSceneEditor() {
    if (!editorScene) return;
    const time = editorScene.time || {};
    if (editorFov) editorFov.value = Number(editorScene.fov || 34);
    if (editorFovValue) editorFovValue.textContent = String(editorFov ? editorFov.value : editorScene.fov || 34);
    if (editorWeather) editorWeather.value = String(editorScene.weather || 'EXTRASUNNY').toUpperCase();
    if (editorHour) editorHour.value = Number(time.hours || 12);
    if (editorMinute) editorMinute.value = Number(time.minutes || 0);
    if (editorTimeValue) {
        const h = String(editorHour ? editorHour.value : time.hours || 12).padStart(2, '0');
        const m = String(editorMinute ? editorMinute.value : time.minutes || 0).padStart(2, '0');
        editorTimeValue.textContent = `${h}:${m}`;
    }
    if (editorJson) editorJson.textContent = JSON.stringify(editorScene, null, 2);
}

function updateEditorSceneLocal() {
    editorScene = editorScene || {};
    editorScene.fov = Number(editorFov ? editorFov.value : editorScene.fov || 34);
    editorScene.weather = String(editorWeather ? editorWeather.value : editorScene.weather || 'EXTRASUNNY').toUpperCase();
    editorScene.time = editorScene.time || {};
    editorScene.time.hours = Number(editorHour ? editorHour.value : editorScene.time.hours || 12);
    editorScene.time.minutes = Number(editorMinute ? editorMinute.value : editorScene.time.minutes || 0);
    editorScene.time.seconds = 0;
    renderSceneEditor();
}

function sendEditorAction(action, payload) {
    payload = payload || {};
    payload.actionName = action;
    return post('editorAction', payload).catch(() => showEditorToast('Editor action failed.', 'error'));
}

[editorFov, editorWeather, editorHour, editorMinute].forEach((input) => {
    if (!input) return;
    input.addEventListener('input', () => {
        updateEditorSceneLocal();
        sendEditorAction('updateBasic', {
            fov: editorScene.fov,
            weather: editorScene.weather,
            time: editorScene.time
        });
    });
});

document.querySelectorAll('.editor-action').forEach((button) => {
    button.addEventListener('click', () => {
        const action = button.dataset.action;
        const payload = {};
        if (action === 'applyAnimPreset') payload.preset = editorAnimPreset ? editorAnimPreset.value : 'idle';
        if (action === 'freeCamera' && editorCard) {
            editorCard.classList.add('is-hidden-for-preview');
            if (editorFreePreview) editorFreePreview.textContent = 'Show editor panel';
            showEditorToast('Free camera enabled. Use WASD/QE + mouse. ENTER saves camera, BACKSPACE cancels.', 'success');
        }
        sendEditorAction(action, payload);
    });
});

document.querySelectorAll('.nudge-row button').forEach((button) => {
    button.addEventListener('click', () => {
        const row = button.closest('.nudge-row');
        sendEditorAction('nudge', {
            target: row ? row.dataset.target : '',
            axis: button.dataset.axis,
            delta: Number(button.dataset.delta || 0)
        });
    });
});

if (editorClose) editorClose.addEventListener('click', closeSceneEditor);
if (editorSave) editorSave.addEventListener('click', () => sendEditorAction('save'));
if (editorFreePreview) {
    editorFreePreview.addEventListener('click', () => {
        const hidden = editorCard && editorCard.classList.toggle('is-hidden-for-preview');
        editorFreePreview.textContent = hidden ? 'Show editor panel' : 'Hide editor / preview';
        sendEditorAction('showPlayerPreview', {});
    });
}

// Hook editor messages into existing message listener without replacing it.
window.addEventListener('message', function(event) {
    const data = event.data || {};
    if (data.action === 'openSceneEditor') {
        openSceneEditor(data.scene || {});
    }
    if (data.action === 'sceneEditorUpdate') {
        editorScene = data.scene || editorScene || {};
        renderSceneEditor();
        if (data.message) showEditorToast(data.message, data.ok === false ? 'error' : 'success');
    }
    if (data.action === 'sceneEditorClose') {
        if (editorScreen) editorScreen.classList.add('hidden');
    }
});

// Character admin panel
const adminScreen = document.getElementById('admin-screen');
const adminClose = document.getElementById('admin-close');
const adminSearchInput = document.getElementById('admin-search');
const adminSearchBtn = document.getElementById('admin-search-btn');
const adminResults = document.getElementById('admin-results');
const adminToast = document.getElementById('admin-toast');
const adminSelectedName = document.getElementById('admin-selected-name');
const adminSelectedMeta = document.getElementById('admin-selected-meta');
const adminFirstName = document.getElementById('admin-first-name');
const adminLastName = document.getElementById('admin-last-name');
const adminSlot = document.getElementById('admin-slot');
const adminAccountId = document.getElementById('admin-account-id');
const adminMaxSlots = document.getElementById('admin-max-slots');
let adminCharacters = [];
let adminSelectedCharacter = null;

function showAdminToast(message, type = 'success') {
    if (!adminToast) return;
    adminToast.textContent = message || '';
    adminToast.classList.add('show');
    adminToast.classList.toggle('error', type === 'error');
    setTimeout(() => adminToast.classList.remove('show'), 3600);
}

function openCharacterAdminPanel() {
    if (!app || !adminScreen) return;
    forceHideCharacterLoader();
    app.style.display = 'block';
    app.style.visibility = 'visible';
    app.style.opacity = '1';
    app.classList.remove('hidden');
    if (slotsScreen) slotsScreen.classList.add('hidden');
    if (creatorScreen) creatorScreen.classList.add('hidden');
    if (editorScreen) editorScreen.classList.add('hidden');
    adminScreen.classList.remove('hidden');
    stopMusic();
}

function closeCharacterAdminPanel() {
    if (adminScreen) adminScreen.classList.add('hidden');
    post('charAdminClose', {}).catch(() => {});
    if (app && (!slotsScreen || slotsScreen.classList.contains('hidden')) && (!creatorScreen || creatorScreen.classList.contains('hidden')) && (!editorScreen || editorScreen.classList.contains('hidden'))) {
        app.classList.add('hidden');
    }
}

function selectAdminCharacter(charId) {
    adminSelectedCharacter = adminCharacters.find(c => String(c.charId) === String(charId)) || null;
    document.querySelectorAll('.admin-row').forEach(row => row.classList.toggle('active', row.dataset.charId === String(charId)));

    if (!adminSelectedCharacter) {
        if (adminSelectedName) adminSelectedName.textContent = 'Select a character';
        if (adminSelectedMeta) adminSelectedMeta.textContent = 'No character selected.';
        return;
    }

    if (adminSelectedName) adminSelectedName.textContent = adminSelectedCharacter.name || 'Unknown Character';
    if (adminSelectedMeta) {
        adminSelectedMeta.textContent = `Character ID #${adminSelectedCharacter.charId} · Account ${adminSelectedCharacter.accountId} · Slot ${adminSelectedCharacter.slot} · ${adminSelectedCharacter.online ? 'Online' : 'Offline'}`;
    }
    if (adminFirstName) adminFirstName.value = adminSelectedCharacter.firstName || '';
    if (adminLastName) adminLastName.value = adminSelectedCharacter.lastName || '';
    if (adminSlot) adminSlot.value = adminSelectedCharacter.slot || 1;
    if (adminAccountId) adminAccountId.value = adminSelectedCharacter.accountId || '';
}

function renderAdminResults(results) {
    adminCharacters = Array.isArray(results) ? results : [];
    if (!adminResults) return;
    adminResults.textContent = '';

    if (adminCharacters.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'admin-row';
        empty.textContent = 'No characters found.';
        adminResults.appendChild(empty);
        selectAdminCharacter(null);
        return;
    }

    adminCharacters.forEach(char => {
        const row = document.createElement('button');
        row.type = 'button';
        row.className = 'admin-row';
        row.dataset.charId = String(char.charId);

        const id = document.createElement('div');
        id.className = 'admin-id';
        id.textContent = `#${char.charId}`;

        const name = document.createElement('div');
        name.className = 'admin-name';
        const strong = document.createElement('strong');
        strong.textContent = char.name || 'Unknown Character';
        const span = document.createElement('span');
        span.textContent = `Account ${char.accountId || 'N/A'} · Slot ${char.slot || 'N/A'} · ${titleCase(char.gender)}`;
        name.appendChild(strong);
        name.appendChild(span);

        const status = document.createElement('div');
        status.className = `admin-status ${char.online ? 'online' : 'offline'}`;
        status.textContent = char.online ? 'Online' : 'Offline';

        row.appendChild(id);
        row.appendChild(name);
        row.appendChild(status);
        row.addEventListener('click', () => selectAdminCharacter(char.charId));
        adminResults.appendChild(row);
    });

    selectAdminCharacter(adminCharacters[0].charId);
}

function runAdminSearch() {
    post('charAdminSearch', { query: adminSearchInput ? adminSearchInput.value.trim() : '' }).catch(() => showAdminToast('Search failed.', 'error'));
}

function runAdminAction(actionName) {
    const selected = adminSelectedCharacter;
    const payload = {};

    if (actionName === 'setAccountSlots') {
        payload.accountId = adminAccountId ? adminAccountId.value.trim() : '';
        payload.maxSlots = adminMaxSlots ? Number(adminMaxSlots.value) : 0;
    } else {
        if (!selected) {
            showAdminToast('Select a character first.', 'error');
            return;
        }
        payload.charId = selected.charId;
        if (actionName === 'rename') {
            payload.firstName = adminFirstName ? adminFirstName.value.trim() : '';
            payload.lastName = adminLastName ? adminLastName.value.trim() : '';
        }
        if (actionName === 'setSlot') {
            payload.slot = adminSlot ? Number(adminSlot.value) : 0;
        }
    }

    post('charAdminAction', { actionName, payload }).catch(() => showAdminToast('Admin action failed.', 'error'));
}

if (adminClose) adminClose.addEventListener('click', closeCharacterAdminPanel);
if (adminSearchBtn) adminSearchBtn.addEventListener('click', runAdminSearch);
if (adminSearchInput) {
    adminSearchInput.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') runAdminSearch();
    });
}
document.querySelectorAll('.admin-action').forEach(button => {
    button.addEventListener('click', () => runAdminAction(button.dataset.adminAction));
});

window.addEventListener('message', function(event) {
    const data = event.data || {};
    if (data.action === 'openCharacterAdmin') openCharacterAdminPanel();
    if (data.action === 'characterAdminResults') renderAdminResults(data.results || []);
    if (data.action === 'characterAdminStatus') showAdminToast(data.message, data.ok === false ? 'error' : 'success');
    if (data.action === 'hideAll' || data.action === 'spawnStarted' || data.action === 'showApp' || data.action === 'showSlots' || data.action === 'showCreator' || data.action === 'openSceneEditor') {
        if (adminScreen) adminScreen.classList.add('hidden');
    }
});
