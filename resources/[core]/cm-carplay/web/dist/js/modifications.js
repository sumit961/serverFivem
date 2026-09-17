// cm-carplay web UI -- modifications screen: drive mode selector plus neon
// color / pattern / location controls. Gated behind the tuner chip, exactly
// like the statistics screen.
//
// NUI contract (see client/main.lua):
//   NUI.on('updateTunerChip', boolean)
//     -- pushed whenever chip install state changes (and on menu open/vehicle
//        enter/exit); drives the tunerChipRequired empty state.
//   NUI.post('getModificationsData')
//     -> { driveMode, neonPatterns:[{id,enabled}], neonLocations:[{id,enabled}],
//          neonHue, neonSaturation, neonBrightness } | {}
//     -- Lua returns {} when nothing has been saved yet for this vehicle.
//   NUI.post('saveModificationsData', fullModificationsObject)
//     -- Lua does `vehicleModificationsData[plate] = data` -- a FULL REPLACE,
//        not a merge -- so every call must send the complete object (drive
//        mode + all neon fields), never a partial patch.
//   NUI.post('setDriveMode', { mode })
//     -- Lua merges this into the existing stored modifications (safe to send
//        alone), so drive-mode clicks go through this callback instead of
//        saveModificationsData.
//
// Judgment calls (see final report to the user for the full list):
//   - UI.modifications.title/subtitle/driveMode/engineTuning/transmission/
//     suspension/brakes have no matching CSS in the modifications-panel
//     (verified against the recovered style.css) and are not rendered --
//     same "leftover copy" situation as the eco/normal/sport/race set.
//   - Neon pattern labels: Config.NeonPatterns is Solid/Pulse/Flash/Fade but
//     locale only has static/pulse/chase/off. Mapped static->Solid,
//     pulse->Pulse, and hardcoded "Flash"/"Fade" (no matching locale keys).
//   - UI.modifications.neons/neonColor/neonPattern are unused; the specific
//     colorPicker/colorPickerDesc/lightPatterns/lightLocations keys are used
//     instead since they match the actual CSS section structure.
//   - Neon location titles (Front/Rear/Left/Right) come straight from
//     Config.NeonLocations (itself hardcoded English in Lua, not localized).
//   - Location "On" label has no locale key (only "off" exists in this
//     section); hardcoded "On" rather than reaching into another screen's
//     locale section.
//   - Clear-locations button reuses UI.music.clear ("Clear") since
//     modifications has no equivalent key.

const Modifications = (() => {
    const panel = document.getElementById('modifications-panel');

    // Single-path (no <circle>/<rect>) icon shapes so the existing
    // ".mode svg path { fill: var(--color-primary) }" / equivalent rules
    // actually color them.
    const ICON_BOLT = 'M11 2 3 13h6l-1 9 9-13h-6l2-7z';
    const ICON_LEAF = 'M12 21C7 21 3 17 3 12 8 12 12 8 12 3c5 0 9 4 9 9 0 5-4 9-9 9z';
    const ICON_RING = 'M12 3a9 9 0 1 1 0 18 9 9 0 1 1 0-18zM12 7.5a4.5 4.5 0 1 0 0 9 4.5 4.5 0 1 0 0-9z';
    const ICON_DISC = 'M12 2a10 10 0 1 1 0 20 10 10 0 1 1 0-20z';
    const ICON_CLOSE = 'M6 6l2-2 4 4 4-4 2 2-4 4 4 4-2 2-4-4-4 4-2-2 4-4z';

    // Matches Config.DriveModes keys exactly (sports/drift/eco/normal) --
    // NOT the locale's leftover eco/normal/sport/race set.
    const DRIVE_MODES = [
        { mode: 'sports', icon: ICON_BOLT, titleKey: 'sportsMode', descKey: 'sportsModeDesc' },
        { mode: 'drift', icon: ICON_RING, evenodd: true, titleKey: 'driftMode', descKey: 'driftModeDesc' },
        { mode: 'eco', icon: ICON_LEAF, titleKey: 'ecoMode', descKey: 'ecoModeDesc' },
        { mode: 'normal', icon: ICON_DISC, titleKey: 'normal', descKey: null },
    ];

    // Matches Config.NeonPatterns ids exactly (1 Solid, 2 Pulse, 3 Flash, 4 Fade).
    const NEON_PATTERNS = [
        { id: 1, localeKey: 'static', fallback: 'Solid' },
        { id: 2, localeKey: 'pulse', fallback: 'Pulse' },
        { id: 3, localeKey: null, fallback: 'Flash' },
        { id: 4, localeKey: null, fallback: 'Fade' },
    ];

    // Matches Config.NeonLocations ids exactly (Front/Rear/Left/Right).
    const NEON_LOCATIONS = [
        { id: 1, title: 'Front' },
        { id: 2, title: 'Rear' },
        { id: 3, title: 'Left' },
        { id: 4, title: 'Right' },
    ];

    let tunerChipInstalled = false;
    let screenVisible = false;
    let data = defaultModifications();
    let contentEls = {};
    let saveTimer = null;
    let loadToken = 0;

    // --- data shape -------------------------------------------------------

    function defaultModifications() {
        return {
            driveMode: 'normal',
            neonPatterns: NEON_PATTERNS.map((p, i) => ({ id: p.id, enabled: i === 0 })),
            neonLocations: NEON_LOCATIONS.map((l) => ({ id: l.id, enabled: false })),
            neonHue: 120,
            neonSaturation: 100,
            neonBrightness: 50,
        };
    }

    function clamp(value, min, max) {
        return Math.min(max, Math.max(min, value));
    }

    // Fills in any field Lua didn't send (e.g. {} for a vehicle with no
    // saved modifications yet) with the same fallbacks client/main.lua uses
    // (modifications.neonHue or 120, etc.), so the UI always shows a value
    // that matches what would actually be applied to the vehicle.
    function normalize(raw) {
        const base = defaultModifications();
        if (!raw || typeof raw !== 'object') return base;

        const neonPatterns = Array.isArray(raw.neonPatterns) && raw.neonPatterns.length
            ? NEON_PATTERNS.map((p) => {
                const found = raw.neonPatterns.find((x) => x && x.id === p.id);
                return { id: p.id, enabled: !!(found && found.enabled) };
            })
            : base.neonPatterns;

        const neonLocations = Array.isArray(raw.neonLocations) && raw.neonLocations.length
            ? NEON_LOCATIONS.map((l) => {
                const found = raw.neonLocations.find((x) => x && x.id === l.id);
                return { id: l.id, enabled: !!(found && found.enabled) };
            })
            : base.neonLocations;

        return {
            driveMode: typeof raw.driveMode === 'string' ? raw.driveMode : base.driveMode,
            neonPatterns,
            neonLocations,
            neonHue: typeof raw.neonHue === 'number' ? clamp(raw.neonHue, 0, 360) : base.neonHue,
            neonSaturation: typeof raw.neonSaturation === 'number' ? clamp(raw.neonSaturation, 0, 100) : base.neonSaturation,
            neonBrightness: typeof raw.neonBrightness === 'number' ? clamp(raw.neonBrightness, 0, 100) : base.neonBrightness,
        };
    }

    // Mirrors client/main.lua's hsbToRgb (hue 0-360, saturation/brightness
    // 0-100 -> rgb 0-255) so the color-picker preview matches what the
    // vehicle's neons will actually show.
    function hsbToRgb(hue, saturation, brightness) {
        const h = ((hue % 360) + 360) % 360 / 360;
        const s = saturation / 100;
        const v = brightness / 100;

        const i = Math.floor(h * 6);
        const f = h * 6 - i;
        const p = v * (1 - s);
        const q = v * (1 - f * s);
        const t = v * (1 - (1 - f) * s);

        let r, g, b;
        switch (i % 6) {
            case 0: r = v; g = t; b = p; break;
            case 1: r = q; g = v; b = p; break;
            case 2: r = p; g = v; b = t; break;
            case 3: r = p; g = q; b = v; break;
            case 4: r = t; g = p; b = v; break;
            default: r = v; g = p; b = q; break;
        }
        return [Math.floor(r * 255), Math.floor(g * 255), Math.floor(b * 255)];
    }

    // --- label helpers ------------------------------------------------------

    function patternLabel(patternDef) {
        if (!patternDef.localeKey) return patternDef.fallback;
        return Locale.L(`UI.modifications.${patternDef.localeKey}`);
    }

    // --- markup -------------------------------------------------------------

    function emptyStateHtml() {
        return `
            <div class="tuner-required">
                <svg width="48" height="48" viewBox="0 0 24 24"><path d="${ICON_DISC}"/></svg>
                <div class="tuner-required-title">${Locale.L('UI.modifications.tunerChipRequired')}</div>
                <div class="tuner-required-subtitle">${Locale.L('UI.modifications.tunerChipDescription')}</div>
            </div>`;
    }

    function modesHtml() {
        const items = DRIVE_MODES.map((m) => `
            <div class="mode${m.mode === data.driveMode ? ' active' : ''}" data-mode="${m.mode}">
                <svg width="28" height="28" viewBox="0 0 24 24"><path${m.evenodd ? ' fill-rule="evenodd"' : ''} d="${m.icon}"/></svg>
                <div class="mode-label">
                    <div class="title">${Locale.L(`UI.modifications.${m.titleKey}`)}</div>
                    <div class="subtitle">${m.descKey ? Locale.L(`UI.modifications.${m.descKey}`) : Locale.L('UI.modifications.off')}</div>
                </div>
            </div>`).join('');
        return `<div class="modes-container">${items}</div>`;
    }

    function neonPanelHtml() {
        const patternItems = NEON_PATTERNS.map((p) => {
            const enabled = data.neonPatterns.some((x) => x.id === p.id && x.enabled);
            return `
                <div class="pattern-item" data-pattern-id="${p.id}">
                    <span class="pattern-name">${patternLabel(p)}</span>
                    <div class="toggle-switch${enabled ? ' active' : ''}">
                        <div class="toggle-thumb"></div>
                    </div>
                </div>`;
        }).join('');

        return `
            <div class="neon-panel">
                <div class="colorpicker">
                    <div class="colorpicker-header">
                        <div class="title">${Locale.L('UI.modifications.colorPicker')}</div>
                        <div class="subtitle">${Locale.L('UI.modifications.colorPickerDesc')}</div>
                    </div>
                    <div class="color-picker-area">
                        <div class="gradient-picker">
                            <div class="picker-cursor"></div>
                        </div>
                        <div class="hue-slider-container">
                            <input type="range" class="hue-slider" min="0" max="360" step="1" value="${data.neonHue}">
                        </div>
                    </div>
                </div>
                <div class="light-patterns">
                    <div class="patterns-header">
                        <div class="title">${Locale.L('UI.modifications.lightPatterns')}</div>
                    </div>
                    <div class="patterns-list">${patternItems}</div>
                </div>
            </div>`;
    }

    function lightLocationsHtml() {
        const items = NEON_LOCATIONS.map((l) => {
            const found = data.neonLocations.find((x) => x.id === l.id);
            const enabled = !!(found && found.enabled);
            return `
                <div class="location-item" data-location-id="${l.id}">
                    <div class="location-label">
                        <div class="location-title">${l.title}</div>
                        <div class="location-subtitle">${enabled ? 'On' : Locale.L('UI.modifications.off')}</div>
                    </div>
                    <div class="toggle-switch${enabled ? ' active' : ''}">
                        <div class="toggle-thumb"></div>
                    </div>
                </div>`;
        }).join('');

        return `
            <div class="light-locations">
                <div class="header">
                    <div class="title">${Locale.L('UI.modifications.lightLocations')}</div>
                    <div class="clear-btn" id="mods-clear-locations">
                        <svg width="14" height="14" viewBox="0 0 24 24"><path d="${ICON_CLOSE}"/></svg>
                        <span>${Locale.L('UI.music.clear')}</span>
                    </div>
                </div>
                <div class="locations-list">${items}</div>
            </div>`;
    }

    // --- render / sync --------------------------------------------------

    function cacheContentEls() {
        contentEls = {
            modeButtons: Array.from(panel.querySelectorAll('.modes-container .mode')),
            patternItems: Array.from(panel.querySelectorAll('.pattern-item')),
            locationItems: Array.from(panel.querySelectorAll('.location-item')),
            gradientPicker: panel.querySelector('.gradient-picker'),
            pickerCursor: panel.querySelector('.picker-cursor'),
            hueSlider: panel.querySelector('.hue-slider'),
            clearLocationsBtn: panel.querySelector('#mods-clear-locations'),
        };
    }

    function bindContentEvents() {
        contentEls.modeButtons.forEach((el) => {
            el.addEventListener('click', () => selectDriveMode(el.dataset.mode));
        });
        contentEls.patternItems.forEach((el) => {
            el.addEventListener('click', () => selectPattern(Number(el.dataset.patternId)));
        });
        contentEls.locationItems.forEach((el) => {
            el.addEventListener('click', () => toggleLocation(Number(el.dataset.locationId)));
        });
        if (contentEls.clearLocationsBtn) {
            contentEls.clearLocationsBtn.addEventListener('click', (evt) => {
                evt.stopPropagation();
                clearAllLocations();
            });
        }
        if (contentEls.hueSlider) {
            contentEls.hueSlider.addEventListener('input', () => {
                data.neonHue = Number(contentEls.hueSlider.value);
                updateColorPreview();
                scheduleSave(false);
            });
            contentEls.hueSlider.addEventListener('change', () => scheduleSave(true));
        }
        if (contentEls.gradientPicker) {
            let dragging = false;
            const pickFromEvent = (evt) => {
                const rect = contentEls.gradientPicker.getBoundingClientRect();
                const x = clamp((evt.clientX - rect.left) / rect.width, 0, 1);
                const y = clamp((evt.clientY - rect.top) / rect.height, 0, 1);
                data.neonSaturation = Math.round(x * 100);
                data.neonBrightness = Math.round((1 - y) * 100);
                updateColorPreview();
                scheduleSave(false);
            };
            contentEls.gradientPicker.addEventListener('pointerdown', (evt) => {
                dragging = true;
                contentEls.gradientPicker.setPointerCapture(evt.pointerId);
                pickFromEvent(evt);
            });
            contentEls.gradientPicker.addEventListener('pointermove', (evt) => {
                if (dragging) pickFromEvent(evt);
            });
            contentEls.gradientPicker.addEventListener('pointerup', () => {
                dragging = false;
                scheduleSave(true);
            });
            contentEls.gradientPicker.addEventListener('pointercancel', () => {
                dragging = false;
            });
        }
    }

    function updateColorPreview() {
        if (!contentEls.gradientPicker) return;
        const hue = data.neonHue;
        contentEls.gradientPicker.style.background =
            `linear-gradient(to top, #000, transparent), linear-gradient(to right, #fff, transparent), hsl(${hue}, 100%, 50%)`;

        if (contentEls.pickerCursor) {
            contentEls.pickerCursor.style.left = `${data.neonSaturation}%`;
            contentEls.pickerCursor.style.top = `${100 - data.neonBrightness}%`;
            const [r, g, b] = hsbToRgb(hue, data.neonSaturation, data.neonBrightness);
            contentEls.pickerCursor.style.background = `rgb(${r}, ${g}, ${b})`;
        }
    }

    function applyDataToDom() {
        if (!contentEls.modeButtons) return; // empty state currently shown

        contentEls.modeButtons.forEach((el) => {
            el.classList.toggle('active', el.dataset.mode === data.driveMode);
        });

        contentEls.patternItems.forEach((el) => {
            const id = Number(el.dataset.patternId);
            const enabled = data.neonPatterns.some((p) => p.id === id && p.enabled);
            const toggle = el.querySelector('.toggle-switch');
            if (toggle) toggle.classList.toggle('active', enabled);
        });

        contentEls.locationItems.forEach((el) => {
            const id = Number(el.dataset.locationId);
            const loc = data.neonLocations.find((l) => l.id === id);
            const enabled = !!(loc && loc.enabled);
            const toggle = el.querySelector('.toggle-switch');
            if (toggle) toggle.classList.toggle('active', enabled);
            const subtitle = el.querySelector('.location-subtitle');
            if (subtitle) subtitle.textContent = enabled ? 'On' : Locale.L('UI.modifications.off');
        });

        if (contentEls.hueSlider) contentEls.hueSlider.value = data.neonHue;
        updateColorPreview();
    }

    function renderShell() {
        if (!tunerChipInstalled) {
            panel.innerHTML = emptyStateHtml();
            contentEls = {};
            return;
        }
        panel.innerHTML = modesHtml() + neonPanelHtml() + lightLocationsHtml();
        cacheContentEls();
        bindContentEvents();
        applyDataToDom();
    }

    // --- mutations (data -> DOM -> save) -------------------------------

    function selectDriveMode(mode) {
        if (!mode || data.driveMode === mode) return;
        data.driveMode = mode;
        applyDataToDom();
        NUI.post('setDriveMode', { mode });
    }

    function selectPattern(id) {
        data.neonPatterns = data.neonPatterns.map((p) => ({ id: p.id, enabled: p.id === id }));
        applyDataToDom();
        scheduleSave(true);
    }

    function toggleLocation(id) {
        data.neonLocations = data.neonLocations.map((l) => (
            l.id === id ? { id: l.id, enabled: !l.enabled } : l
        ));
        applyDataToDom();
        scheduleSave(true);
    }

    function clearAllLocations() {
        data.neonLocations = data.neonLocations.map((l) => ({ id: l.id, enabled: false }));
        applyDataToDom();
        scheduleSave(true);
    }

    // --- NUI I/O -----------------------------------------------------------

    function scheduleSave(immediate) {
        if (saveTimer) {
            clearTimeout(saveTimer);
            saveTimer = null;
        }
        if (immediate) {
            commitSave();
            return;
        }
        saveTimer = setTimeout(commitSave, 200);
    }

    function commitSave() {
        saveTimer = null;
        NUI.post('saveModificationsData', data);
    }

    async function loadData() {
        const token = ++loadToken;
        const raw = await NUI.post('getModificationsData');
        if (token !== loadToken || !screenVisible) return; // superseded by a newer show/hide
        data = normalize(raw);
        applyDataToDom();
    }

    // --- reactive wiring -----------------------------------------------

    NUI.on('updateTunerChip', (installed) => {
        tunerChipInstalled = !!installed;
        if (!screenVisible) return;
        renderShell();
        if (tunerChipInstalled) loadData();
    });

    document.addEventListener('localechange', () => {
        if (screenVisible) renderShell();
    });

    App.registerScreen('modifications', {
        el: panel,
        onShow() {
            screenVisible = true;
            renderShell();
            if (tunerChipInstalled) loadData();
        },
        onHide() {
            screenVisible = false;
            if (saveTimer) {
                clearTimeout(saveTimer);
                commitSave();
            }
        },
    });

    return {};
})();
