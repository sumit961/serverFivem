// cm-characters/ui/app.js
// GTA-style selector UI with details panel and background music mute option.

const app = document.getElementById('app');
const slotsScreen = document.getElementById('slots-screen');
const creatorScreen = document.getElementById('creator-screen');
const characterList = document.getElementById('character-list');
const characterCount = document.getElementById('character-count');
const errorMsg = document.getElementById('error-msg');
const creatorError = document.getElementById('creator-error');
const creatorForm = document.getElementById('creator-form');
const creatorContinueBtn = document.getElementById('creator-continue-btn');
const creatorBackBtn = document.getElementById('creator-back-btn');
const dobInput = document.getElementById('dob');
if (dobInput) {
    // UX only — prevents picking a future date in the native picker. The
    // server independently re-validates age against Config.MinCharacterAge/
    // Config.MaxCharacterAge regardless of this attribute.
    dobInput.max = new Date().toISOString().slice(0, 10);
}
const playBtn = document.getElementById('play-btn');
const musicToggle = document.getElementById('music-toggle');
const appearanceMusicToggle = document.getElementById('appearance-music-toggle');
const bgm = document.getElementById('character-bgm');
const creationLoading = document.getElementById('creation-loading');
const creationLoadingText = document.getElementById('creation-loading-text');
const creationLoadingPercent = document.getElementById('creation-loading-percent');
const creationLoadingBar = document.getElementById('creation-loading-bar');
const creationLoadingBrand = document.getElementById('creation-loading-brand');

// Single shared branding source (loaded from cm-auth, a hard dependency —
// see fxmanifest.lua). Never hardcode the server name independently here.
// Note: the visible selector screen intentionally shows NO brand/build/
// version text anywhere (including top-right) — only the loading overlay
// (a separate, momentary screen) uses this branding string.
if (creationLoadingBrand) {
    creationLoadingBrand.textContent = (window.CMBranding && window.CMBranding.serverName) || 'CM ROLEPLAY';
}

// CHARACTER CREATION REPAIR PASS: setCreationLoading is now the ONE
// authoritative owner of the creation-loading overlay's visible/hidden state.
// It used to gate HIDE behind a "finish the progress bar to 100%, then wait
// 450ms" timer chain, and a new SHOW request never cancelled that chain --
// two calls in quick succession (exactly what a Back-then-Continue produces)
// could race and leave the overlay's actual hide fighting a stale timer.
// Hide is now immediate and authoritative: the overlay disappears the moment
// a caller says the real screen is ready, never after a fake animation
// finishes. A generation counter cancels any in-flight cosmetic ramp from a
// superseded call.
let loadingRampInterval = null;
let creationLoadingGeneration = 0;
let loadingPercentValue = 0;
let loaderHoldingSelector = false;
let spawnFlowActive = false;

function forceHideCharacterLoader() {
    creationLoadingGeneration += 1;
    if (loadingRampInterval) { clearInterval(loadingRampInterval); loadingRampInterval = null; }
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
    rank: document.getElementById('details-rank')
};

// playBtn's label lives inside a skewed-shape wrapper (see cm-aaa.css
// .cm-action-skew) — never set playBtn.textContent directly, that would
// destroy the wrapper/icon markup.
function setPlayBtnLabel(text) {
    const label = playBtn && playBtn.querySelector('.btn-label');
    if (label) label.textContent = text;
}

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

    // Every call gets its own generation. Any cosmetic ramp interval started
    // by an OLDER call checks this and stops itself instead of continuing to
    // write frames after a newer call has taken over -- this is what stops a
    // stale Continue's loading-show from fighting a later Back's hide (or
    // vice versa).
    creationLoadingGeneration += 1;
    const myGeneration = creationLoadingGeneration;

    if (loadingRampInterval) { clearInterval(loadingRampInterval); loadingRampInterval = null; }
    if (message && creationLoadingText) creationLoadingText.textContent = message;

    const setPercent = (value) => {
        loadingPercentValue = Math.max(0, Math.min(100, Math.floor(value)));
        if (creationLoadingPercent) creationLoadingPercent.textContent = `${loadingPercentValue}%`;
        if (creationLoadingBar) creationLoadingBar.style.width = `${loadingPercentValue}%`;
    };

    if (show) {
        if (spawnFlowActive) {
            forceHideCharacterLoader();
            return;
        }

        creationLoading.classList.remove('hidden', 'finishing');
        creationLoading.style.display = 'flex';
        setPercent(targetPercent || 0);

        // Cosmetic-only ramp toward a cap below 100 while the real screen is
        // still being prepared. This NEVER drives visibility -- only an
        // explicit setCreationLoading(false, ...) call (readiness, not a
        // fake timer) hides the overlay.
        loadingRampInterval = setInterval(() => {
            if (myGeneration !== creationLoadingGeneration) {
                clearInterval(loadingRampInterval);
                loadingRampInterval = null;
                return;
            }
            const cap = targetPercent && targetPercent >= 100 ? 100 : 94;
            if (loadingPercentValue < cap) {
                setPercent(loadingPercentValue + Math.max(1, Math.floor((cap - loadingPercentValue) / 10)));
            }
        }, 110);
        return;
    }

    // HIDE is immediate and authoritative. The caller only reaches here once
    // the real screen (Selector/Identity/Appearance) is actually ready, so
    // readiness -- not a progress animation reaching 100 -- is what removes
    // the overlay from view.
    setPercent(100);
    creationLoading.classList.add('hidden');
    creationLoading.classList.remove('finishing');
    creationLoading.style.display = 'none';

    if (loaderHoldingSelector) {
        loaderHoldingSelector = false;
        forceSelectorVisible();
    }

    // Purely cosmetic reset for the next time the overlay shows; happens
    // after the overlay is already hidden, so it can never delay or race the
    // actual state change above.
    setTimeout(() => {
        if (myGeneration === creationLoadingGeneration) setPercent(0);
    }, 200);
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
    try {
        localStorage.setItem('cm_char_music_muted', muted ? '1' : '0');
    } catch (e) {
        // Private-mode/blocked storage: remembering the mute preference is a convenience only.
    }
    [musicToggle, appearanceMusicToggle].forEach((button) => {
        if (!button) return;
        button.setAttribute('aria-pressed', muted ? 'true' : 'false');
        button.setAttribute('aria-label', muted ? 'Unmute character music' : 'Mute character music');
        if (button === musicToggle) button.textContent = muted ? '♯' : '♫';
        else button.textContent = muted ? 'Music: Off' : 'Music: On';
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

        const title = document.createElement('h3');
        title.textContent = char.name || 'Unknown Character';
        const meta = document.createElement('p');
        meta.textContent = `${titleCase(char.gender)} · ${titleCase(char.rank || 'Civilian')}`;

        card.append(top, title, meta);
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
                <span>Empty slot</span>
                <strong>+</strong>
            </div>
            <h3>New character</h3>
            <p>Start a new story in slot ${emptySlot}.</p>
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
    detailEls.id.textContent = 'Pick one of your saved characters to preview.';
    detailEls.cash.textContent = '$0';
    detailEls.bank.textContent = '$0';
    detailEls.rank.textContent = 'Civilian';
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
    detailEls.id.textContent = `Character ID: ${char.uniqueId || 'N/A'}`;
    detailEls.cash.textContent = money(char.cash);
    detailEls.bank.textContent = money(char.bank);
    detailEls.rank.textContent = String(char.rank || 'Civilian');
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
    setPlayBtnLabel('Entering...');
    post('selectSlot', { charId: selectedCharacter.uniqueId }).catch(() => {
        playBtn.disabled = false;
        setPlayBtnLabel('Enter city');
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
        // FULLSCREEN LOADING SAFETY: defensive cleanup only -- the real fix is
        // appearance.lua's own creationLoading:false message sent right after
        // this one. If that message were ever lost/reordered, Appearance would
        // otherwise be ready underneath a stuck full-screen loader.
        loaderHoldingSelector = false;
        forceHideCharacterLoader();
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
        //
        // CHARACTER CREATION REPAIR PASS: this used to return here without
        // touching the loader/selector visibility at all. That was fine as
        // long as something else had already revealed the selector and hidden
        // the loader moments earlier (the normal case) -- but it violated the
        // "visible interactive screen -> creationLoading hidden" invariant on
        // its own, so any earlier state corruption (see the hideAll fix below)
        // had no safety net here. Enforce the invariant unconditionally on
        // every showSlots, including this fast/cached path.
        if (duplicateSlots) {
            currentSlots = newSlots;
            maxCharacters = newMaxCharacters;
            loaderHoldingSelector = false;
            forceHideCharacterLoader();
            forceSelectorVisible();
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
                setPlayBtnLabel('Enter city');
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
        if (creatorContinueBtn) creatorContinueBtn.disabled = false;
        selectedSlot = data.slot;
        isCreatingChar = false;
        clearCreator();
    }

    // PHASE 4C: returning from Appearance's Back button for a brand-new
    // character. Unlike showCreator, this must NOT call clearCreator() —
    // the player's typed name/DOB and chosen gender must survive the trip,
    // since the already-prepared preview ped matches whatever gender is
    // still selected in the (untouched) <select> element.
    if (data.action === 'showCreatorAgain') {
        // Being back on Identity means we are definitively NOT mid-spawn,
        // even if an earlier hideAll (this transition's own) set the flag.
        spawnFlowActive = false;
        loaderHoldingSelector = false;
        forceHideCharacterLoader();
        app.style.display = 'block';
        app.style.visibility = 'visible';
        app.style.opacity = '1';
        app.classList.remove('hidden');
        slotsScreen.classList.add('hidden');
        creatorScreen.classList.remove('hidden');
        if (creatorContinueBtn) creatorContinueBtn.disabled = false;
        selectedSlot = data.slot;
        isCreatingChar = false;
    }

    if (data.action === 'hideCreator') {
        creatorScreen.classList.add('hidden');
    }

    if (data.action === 'hideAll') {
        // CHARACTER CREATION REPAIR PASS: hideAll is sent for two very
        // different reasons -- (a) the real hand-off to cm-spawn (gameplay is
        // about to begin, the whole character-selection UI's cached state is
        // now irrelevant), and (b) purely internal transitions that just need
        // every NUI panel cleared for a moment (Appearance's Back-to-Identity,
        // a barber/service session finishing). Only (a) may set
        // spawnFlowActive/clear the slots cache -- doing it unconditionally
        // used to permanently wedge spawnFlowActive=true after a single
        // Appearance Back, silently suppressing every later creationLoading
        // show, AND force a full "Loading character preview..." restart on a
        // later real backout to the selector even though nothing changed
        // (violates "do not restart selector loading unnecessarily").
        const isRealSpawnHandoff = data.spawning === true;
        if (isRealSpawnHandoff) {
            spawnFlowActive = true;
            slotsAlreadyRendered = false;
            lastSlotsSignature = '';
        }
        loaderHoldingSelector = false;
        forceHideCharacterLoader();
        app.classList.add('hidden');
        slotsScreen.classList.add('hidden');
        creatorScreen.classList.add('hidden');
        stopMusic();
    }

    if (data.action === 'error') {
        isCreatingChar = false;
        playBtn.disabled = !selectedCharacter;
        setPlayBtnLabel('Enter city');
        if (!creatorScreen.classList.contains('hidden')) {
            if (creatorContinueBtn) creatorContinueBtn.disabled = false;
            showCreatorError(data.message);
        } else {
            showError(data.message);
        }
    }
});

// Client-side checks here are UX only — presence/shape, not the authoritative
// rule. The server independently re-validates name charset/length and DOB/age
// against Config.MinCharacterAge/MaxCharacterAge and returns a readable error
// (shown via showCreatorError) regardless of what passes here.
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
    if (!dob) {
        showCreatorError('Select a date of birth.');
        return;
    }

    isCreatingChar = true;
    if (creatorContinueBtn) creatorContinueBtn.disabled = true;
    post('createCharacter', { firstName, lastName, dob, gender }).catch(() => {
        isCreatingChar = false;
        if (creatorContinueBtn) creatorContinueBtn.disabled = false;
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
    if (window.CMUI && typeof window.CMUI.toast === 'function') window.CMUI.toast(msg || 'Something went wrong.', 'error');
    if (!errorMsg) return;
    errorMsg.textContent = msg || 'Something went wrong.';
    errorMsg.classList.add('show');
    setTimeout(() => errorMsg.classList.remove('show'), 3500);
}

function showCreatorError(msg) {
    if (window.CMUI && typeof window.CMUI.toast === 'function') window.CMUI.toast(msg || 'Something went wrong.', 'error');
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

if (creatorForm) {
    creatorForm.addEventListener('submit', (event) => {
        event.preventDefault();
        createCharacter();
    });
}
if (creatorBackBtn) creatorBackBtn.addEventListener('click', showSlots);

// PHASE 4C: live gender preview. client/appearance.lua owns the actual
// ped/model swap (token-guarded against rapid switching) — this just
// forwards the selection every time it changes.
const genderSelect = document.getElementById('gender');
if (genderSelect) {
    genderSelect.addEventListener('change', () => {
        post('creatorGenderChanged', { gender: genderSelect.value }).catch(() => {});
    });
}

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
    if (window.CMUI && typeof window.CMUI.toast === 'function') window.CMUI.toast(message || '', type === 'error' ? 'error' : 'success');
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
    if (window.CMUI && typeof window.CMUI.toast === 'function') window.CMUI.toast(message || '', type === 'error' ? 'error' : 'success');
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
        empty.className = 'admin-row cm-card';
        empty.textContent = 'No characters found.';
        adminResults.appendChild(empty);
        selectAdminCharacter(null);
        return;
    }

    adminCharacters.forEach(char => {
        const row = document.createElement('button');
        row.type = 'button';
        row.className = 'admin-row cm-card';
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

// ═══ Barber Shop / Hair Salon Commercial Ownership Management ═══
const barberOwnerPanel = document.getElementById('barber-owner-panel');
const barberStoreTitle = document.getElementById('barberStoreTitle');
const barberStoreSub = document.getElementById('barberStoreSub');
const barberBalance = document.getElementById('barberBalance');
const barberTaxCoverage = document.getElementById('barberTaxCoverage');
const barberTaxDueHint = document.getElementById('barberTaxDueHint');
const barberStock = document.getElementById('barberStock');
const barberStockCap = document.getElementById('barberStockCap');
const barberDailyIncome = document.getElementById('barberDailyIncome');
const barberWeeklyIncome = document.getElementById('barberWeeklyIncome');
const barberActiveTierPill = document.getElementById('barberActiveTierPill');
const barberCloseBtn = document.getElementById('barberCloseBtn');
const barberWithdrawBtn = document.getElementById('barberWithdrawBtn');
const barberPayTaxBtn = document.getElementById('barberPayTaxBtn');
const barberRestockBtn = document.getElementById('barberRestockBtn');
const barberSaveSettingsBtn = document.getElementById('barberSaveSettingsBtn');

const barberBuyPanel = document.getElementById('barber-buy-panel');
const barberBuyName = document.getElementById('barberBuyName');
const barberBuyOwnerName = document.getElementById('barberBuyOwnerName');
const barberBuyTier = document.getElementById('barberBuyTier');
const barberBuyStock = document.getElementById('barberBuyStock');
const barberBuyStatus = document.getElementById('barberBuyStatus');
const barberBuyConfirmBtn = document.getElementById('barberBuyConfirmBtn');
const barberBuyCloseBtn = document.getElementById('barberBuyCloseBtn');

let currentBarberData = null;
let currentBarberTier = 'normal';
let currentBarberBuyData = null;

function formatCurrency(amount) {
    return '$' + Math.floor(Number(amount) || 0).toLocaleString();
}

function renderBarberOwner(data) {
    if (!data) return;
    currentBarberData = data;
    currentBarberTier = data.priceTier || 'normal';

    if (barberStoreTitle) barberStoreTitle.textContent = (data.shopId ? data.shopId.toUpperCase().replace(/_/g, ' ') : 'HAIR SALON') + ' SALON';
    if (barberStoreSub) barberStoreSub.textContent = `OPERATOR: ${data.ownerName || 'City Commercial Property'} | ID: ${data.shopId || 'N/A'}`;
    if (barberBalance) barberBalance.textContent = formatCurrency(data.businessBalance);
    if (barberTaxCoverage) barberTaxCoverage.textContent = `${data.taxDueDays || 0} DAYS`;
    if (barberTaxDueHint) barberTaxDueHint.textContent = `${formatCurrency(data.taxAmount || 12000)} / 7 DAYS`;
    if (barberStock) barberStock.textContent = (Number(data.stock) || 0).toLocaleString();
    if (barberStockCap) barberStockCap.textContent = `CAPACITY: ${(Number(data.maxStock) || 5000).toLocaleString()} UNITS`;
    if (barberDailyIncome) barberDailyIncome.textContent = formatCurrency(data.dailyIncome);
    if (barberWeeklyIncome) barberWeeklyIncome.textContent = formatCurrency(data.weeklyIncome);

    // Update tier buttons
    const multText = currentBarberTier === 'low' ? '0.80x ($80)' : (currentBarberTier === 'high' ? '1.50x ($150)' : '1.00x ($100)');
    if (barberActiveTierPill) barberActiveTierPill.textContent = `${currentBarberTier.toUpperCase()} (${multText})`;

    if (barberPayTaxBtn) {
        const isMaxPaid = data.canPayTax === false || Number(data.taxDueDays) >= 7;
        barberPayTaxBtn.disabled = isMaxPaid;
        barberPayTaxBtn.textContent = isMaxPaid
            ? 'TAX PAID (MAX 7 DAYS)'
            : `PAY 7-DAY TAX (${formatCurrency(data.taxAmount || 12000)})`;
        barberPayTaxBtn.style.opacity = isMaxPaid ? '0.5' : '1';
        barberPayTaxBtn.style.cursor = isMaxPaid ? 'not-allowed' : 'pointer';
    }

    document.querySelectorAll('.barber-tier-btn').forEach(btn => {
        btn.classList.toggle('selected', btn.dataset.tier === currentBarberTier);
    });
}

function openBarberOwner(data) {
    renderBarberOwner(data);
    if (barberOwnerPanel) barberOwnerPanel.classList.remove('hidden');
}

function closeBarberOwner() {
    if (barberOwnerPanel) barberOwnerPanel.classList.add('hidden');
    currentBarberData = null;
    post('closeBarberOwner', {}).catch(() => {});
}

if (barberCloseBtn) barberCloseBtn.addEventListener('click', closeBarberOwner);

document.querySelectorAll('.barber-tier-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.barber-tier-btn').forEach(b => b.classList.remove('selected'));
        btn.classList.add('selected');
        currentBarberTier = btn.dataset.tier || 'normal';
        const multText = currentBarberTier === 'low' ? '0.80x ($80)' : (currentBarberTier === 'high' ? '1.50x ($150)' : '1.00x ($100)');
        if (barberActiveTierPill) barberActiveTierPill.textContent = `${currentBarberTier.toUpperCase()} (${multText})`;
    });
});

if (barberWithdrawBtn) {
    barberWithdrawBtn.addEventListener('click', () => {
        if (!currentBarberData || !currentBarberData.shopId) return;
        post('withdrawBarberBalance', { shopId: currentBarberData.shopId }).catch(() => {});
    });
}

if (barberPayTaxBtn) {
    barberPayTaxBtn.addEventListener('click', () => {
        if (barberPayTaxBtn.disabled) return;
        if (!currentBarberData || !currentBarberData.shopId) return;
        post('payBarberShopTax', { shopId: currentBarberData.shopId }).catch(() => {});
    });
}

if (barberRestockBtn) {
    barberRestockBtn.addEventListener('click', () => {
        if (!currentBarberData || !currentBarberData.shopId) return;
        post('manageBarberShop', { shopId: currentBarberData.shopId, restock: true, priceTier: currentBarberTier }).catch(() => {});
    });
}

if (barberSaveSettingsBtn) {
    barberSaveSettingsBtn.addEventListener('click', () => {
        if (!currentBarberData || !currentBarberData.shopId) return;
        post('manageBarberShop', { shopId: currentBarberData.shopId, priceTier: currentBarberTier }).catch(() => {});
    });
}

// ═══ Barber Shop / Hair Salon Public Buy / Info Panel ═══
const BARBER_TIER_LABELS = { low: 'DISCOUNT', normal: 'STANDARD', high: 'LUXURY' };

function renderBarberBuyInfo(data) {
    if (!data) return;
    currentBarberBuyData = data;

    if (barberBuyName) barberBuyName.textContent = data.shopName || 'Hair Salon';
    if (barberBuyOwnerName) barberBuyOwnerName.textContent = data.ownerName || 'City Commercial Property';

    const tier = data.priceTier || 'normal';
    const mult = Number(data.priceMultiplier || 1).toFixed(2);
    if (barberBuyTier) barberBuyTier.textContent = `${BARBER_TIER_LABELS[tier] || 'STANDARD'} (${mult}x)`;

    if (barberBuyStock) barberBuyStock.textContent = `${(Number(data.stock) || 0).toLocaleString()} UNITS`;

    if (barberBuyStatus) {
        barberBuyStatus.textContent = data.isOwned ? 'PRIVATELY OWNED' : 'AVAILABLE FOR PURCHASE';
    }

    if (barberBuyConfirmBtn) {
        barberBuyConfirmBtn.textContent = `BUY THIS SALON (${formatCurrency(data.purchasePrice || 200000)} - BANK)`;
        barberBuyConfirmBtn.disabled = data.isOwned === true;
    }
}

function openBarberBuyInfo(data) {
    renderBarberBuyInfo(data);
    if (barberBuyPanel) barberBuyPanel.classList.remove('hidden');
}

function closeBarberBuyInfo() {
    if (barberBuyPanel) barberBuyPanel.classList.add('hidden');
    currentBarberBuyData = null;
    post('closeBarberBuyInfo', {}).catch(() => {});
}

if (barberBuyCloseBtn) barberBuyCloseBtn.addEventListener('click', closeBarberBuyInfo);

if (barberBuyConfirmBtn) {
    barberBuyConfirmBtn.addEventListener('click', () => {
        if (barberBuyConfirmBtn.disabled) return;
        if (!currentBarberBuyData || !currentBarberBuyData.shopId) return;
        post('buyBarberShop', { shopId: currentBarberBuyData.shopId }).catch(() => {});
        if (barberBuyPanel) barberBuyPanel.classList.add('hidden');
        currentBarberBuyData = null;
    });
}

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        if (barberOwnerPanel && !barberOwnerPanel.classList.contains('hidden')) {
            closeBarberOwner();
        }
        if (barberBuyPanel && !barberBuyPanel.classList.contains('hidden')) {
            closeBarberBuyInfo();
        }
    }
});

window.addEventListener('message', function(event) {
    const data = event.data || {};
    if (data.type === 'openBarberOwner') openBarberOwner(data.data);
    if (data.type === 'updateBarberOwner') renderBarberOwner(data.data);
    if (data.type === 'closeBarberOwner') closeBarberOwner();
    if (data.type === 'openBarberBuyInfo') openBarberBuyInfo(data.data);
    if (data.type === 'closeBarberBuyInfo') {
        if (barberBuyPanel) barberBuyPanel.classList.add('hidden');
        currentBarberBuyData = null;
    }
    if (data.action === 'openCharacterAdmin') openCharacterAdminPanel();
    if (data.action === 'characterAdminResults') renderAdminResults(data.results || []);
    if (data.action === 'characterAdminStatus') showAdminToast(data.message, data.ok === false ? 'error' : 'success');
    if (data.action === 'hideAll' || data.action === 'spawnStarted' || data.action === 'showApp' || data.action === 'showSlots' || data.action === 'showCreator' || data.action === 'openSceneEditor') {
        if (adminScreen) adminScreen.classList.add('hidden');
    }
});
