// cm-carplay web UI -- Manage screen.
//
// Vehicle controls: doors (per-door via the diagram + all-at-once via the
// "Doors" card), trunk (diagram), seatbelt, windows, engine, lights, lock,
// seat selection, and a read-only Vehicle Info section.
//
// Real NUI contract (see client/main.lua):
//   NUI.post('toggleDoors',  { open })         -- open: 0-3 (SetVehicleDoorOpen loop); !open: SetVehicleDoorsShut (ALL doors incl. hood/trunk)
//   NUI.post('toggleDoor',   { door, open })    -- single door by GTA door index
//   NUI.post('toggleTrunk',  { open })          -- dedicated trunk handler (index computed server-side from GetNumberOfVehicleDoors)
//   NUI.post('toggleSeatbelt', { on })
//   NUI.post('toggleWindows', { down })
//   NUI.post('toggleLock',   { locked })
//   NUI.post('toggleEngine', { on })
//   NUI.post('toggleLights', { on })
//   NUI.post('selectSeat',   { seat })          -- 1-based; Lua does seatIndex = seat - 1
//   NUI.post('getVehicleInfo') -> { drivetrain, driveBias, fuelLevel, engineHealth, bodyHealth, tireHealth, engineTemp }
//
// IMPORTANT judgment call: getVehicleInfo does NOT return door/window/lock/
// engine/light state (only health/fuel/drivetrain numbers) and there is no
// other NUI callback that queries current door/lock/engine/light/seatbelt/
// window state. So every toggle below is tracked as LOCAL optimistic state,
// defaulted to a closed/off/unlocked baseline on each onShow -- it reflects
// what this screen has told the vehicle to do, not a verified live read of
// the vehicle. See the final report for more detail.
//
// Door/seat count: GTA's generic SetVehicleDoorOpen/Shut natives address
// doors 0=FL, 1=FR, 2=RL, 3=RR, 4=hood, 5=trunk -- toggleDoors' own loop
// (0 to 3) plus the dedicated toggleTrunk handler confirm this 6-part
// layout, which is exactly the 6 lock-btn-wrapper hotspots the CSS defines
// on the vehicle diagram. Seats: selectSeat does `seatIndex = data.seat - 1`
// with no native seat-count query available, so this mirrors the standard
// 4-seat layout (driver/front passenger/rear left/rear right).

const Manage = (() => {
    const el = document.getElementById('manage-panel');

    const DOOR_ICON = 'assets/doorFrontLeft.png';
    const HOOD_ICON = 'assets/rearHood.png';
    const WINDOW_ICON = 'assets/windowFrontLeft.png';
    const SEAT_ICON = 'assets/seatFrontLeft.png';

    // svg icon fragments (fill inherited via `.card svg path{fill:var(--color-primary)}`)
    const SVG = {
        lock: '<path d="M6 10V8a6 6 0 0 1 12 0v2h1a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-9a1 1 0 0 1 1-1h1zm2 0h8V8a4 4 0 0 0-8 0v2z"/>',
        seatbelt: '<path d="M12 2 4 6v6c0 5 3.4 8.7 8 10 4.6-1.3 8-5 8-10V6l-8-4zm0 3.2 5.5 2.7v3.1L12 8.3 6.5 11V8.9L12 5.2zM12 11l4.3 6.3A9 9 0 0 1 12 20a9 9 0 0 1-4.3-2.7L12 11z"/>',
        engine: '<path d="M4 12a1 1 0 0 1 1-1h1V9a1 1 0 0 1 1-1h2V6h2v2h2V6h2v2h2a1 1 0 0 1 1 1v2h1a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-1v1a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-1H4a1 1 0 0 1-1-1v-2h1v-1z"/>',
        lights: '<path d="M3 11l9-6 9 6-9 6-9-6zm9 8-9-5.2V15l9 5.2 9-5.2v-1.2L12 19z"/>',
        arrow: '<path d="M9 6l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
        gas: '<path d="M14 3H6a1 1 0 0 0-1 1v16h10V4a1 1 0 0 0-1-1zM7 6h6v5H7V6zm11.8 2.6-2.3-2.3-1.1 1 1.9 1.9v6.3a1.2 1.2 0 0 0 2.4 0V9a2 2 0 0 0-.9-1.4z"/>',
        body: '<path d="M4 15l1.5-5.5A2 2 0 0 1 7.4 8h9.2a2 2 0 0 1 1.9 1.5L20 15v4a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-1H7v1a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-4zm2.6-.5h10.8l-1-3.7a.5.5 0 0 0-.5-.4H8.1a.5.5 0 0 0-.5.4l-1 3.7zM7 17a1 1 0 1 0 0-2 1 1 0 0 0 0 2zm10 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2z"/>',
        tires: '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 4a6 6 0 1 1 0 12 6 6 0 0 1 0-12zm0 2.5A3.5 3.5 0 1 0 12 15.5 3.5 3.5 0 0 0 12 8.5z"/>',
        temperature: '<path d="M12 2a2 2 0 0 0-2 2v9.3a4 4 0 1 0 4 0V4a2 2 0 0 0-2-2zm0 14a2 2 0 1 1 0 4 2 2 0 0 1 0-4z"/>',
        drivetrain: '<path d="M12 2 8 6h3v4H6V7L2 12l4 5v-3h5v4H8l4 4 4-4h-3v-4h5v3l4-5-4-5v3h-5V6h3z"/>',
    };

    // --- state (optimistic; see file header note) -----------------------------

    const state = {
        doors: [false, false, false, false], // FL, FR, RL, RR -- open?
        hood: false,
        trunk: false,
        locked: false,
        seatbeltOn: false,
        windowsDown: false,
        engineOn: false,
        lightsOn: false,
        seatPickerOpen: false,
    };

    // --- DOM ---------------------------------------------------------------

    function doorWrapper(positionClass, part, iconSrc, mirror) {
        const mirrorStyle = mirror ? ' style="transform:scaleX(-1)"' : '';
        return `
            <div class="lock-btn-wrapper ${positionClass}" data-part="${part}">
                <div class="lock-btn"><img src="${iconSrc}" alt=""${mirrorStyle} width="18" height="18" /></div>
            </div>`;
    }

    // `iconHtml` is a complete, ready-to-insert element (either an <svg>...
    // </svg> built from one of the SVG.* path fragments, or a standalone
    // <img>) -- NOT wrapped further here, since <img> is not a valid child
    // of <svg> and would silently fail to render if it were.
    function card(id, iconHtml, titleKey, hasArrow) {
        const right = hasArrow
            ? '<svg class="arrow" viewBox="0 0 24 24" width="18" height="18">' + SVG.arrow + '</svg>'
            : `<span class="status-indicator" id="${id}-badge"></span>`;
        return `
            <div class="card" id="${id}-card">
                ${iconHtml}
                <div class="card-label">
                    <div class="title" data-i18n="UI.manage.${titleKey}"></div>
                    <div class="subtitle" id="${id}-subtitle"></div>
                </div>
                ${right}
            </div>`;
    }

    function cardSvg(pathFragment) {
        return `<svg viewBox="0 0 24 24" width="22" height="22">${pathFragment}</svg>`;
    }

    el.innerHTML = `
        <div class="vehicle-container">
            ${doorWrapper('top-center', 'hood', HOOD_ICON, false)}
            ${doorWrapper('middle-left', 'door-0', DOOR_ICON, false)}
            ${doorWrapper('middle-right', 'door-1', DOOR_ICON, true)}
            ${doorWrapper('bottom-left', 'door-2', DOOR_ICON, false)}
            ${doorWrapper('bottom-right', 'door-3', DOOR_ICON, true)}
            ${doorWrapper('bottom-center', 'trunk', HOOD_ICON, false)}
        </div>

        <div class="manage-container">
            <div class="title" data-i18n="UI.manage.title"></div>
            <div class="subtitle" data-i18n="UI.manage.subtitle"></div>
            <div class="cards-container">
                ${card('doors', `<img src="${DOOR_ICON}" width="22" height="22" alt=""/>`, 'doors', false)}
                ${card('lock', cardSvg(SVG.lock), 'lock', false)}
                ${card('seatbelt', cardSvg(SVG.seatbelt), 'seatbelt', false)}
                ${card('windows', `<img src="${WINDOW_ICON}" width="22" height="22" alt=""/>`, 'windows', false)}
                ${card('engine', cardSvg(SVG.engine), 'engine', false)}
                ${card('lights', cardSvg(SVG.lights), 'lights', false)}
                ${card('seat', `<img src="${SEAT_ICON}" width="22" height="22" alt=""/>`, 'seat', true)}
                <div class="seat-picker" id="seat-picker" hidden></div>
            </div>
        </div>

        <div class="vehicle-info-container">
            <div class="title" data-i18n="UI.manage.vehicleInfo"></div>
            <div class="subtitle" data-i18n="UI.manage.vehicleInformation"></div>
            <div class="stats-gauges">
                <div class="gauge-item">
                    <svg viewBox="0 0 24 24" width="20" height="20">${SVG.gas}</svg>
                    <div class="gauge-bar"><div class="gauge-fill" id="gauge-gas" style="height:0%"></div></div>
                    <div class="gauge-label" data-i18n="UI.manage.gas"></div>
                </div>
                <div class="gauge-item">
                    <svg viewBox="0 0 24 24" width="20" height="20">${SVG.body}</svg>
                    <div class="gauge-bar"><div class="gauge-fill" id="gauge-body" style="height:0%"></div></div>
                    <div class="gauge-label" data-i18n="UI.manage.body"></div>
                </div>
                <div class="gauge-item">
                    <svg viewBox="0 0 24 24" width="20" height="20">${SVG.tires}</svg>
                    <div class="gauge-bar"><div class="gauge-fill" id="gauge-tires" style="height:0%"></div></div>
                    <div class="gauge-label" data-i18n="UI.manage.tires"></div>
                </div>
            </div>
            <div class="info-cards">
                <div class="info-card">
                    <div class="info-icon temperature"><svg viewBox="0 0 24 24" width="24" height="24">${SVG.temperature}</svg></div>
                    <div class="info-details">
                        <div class="info-title" data-i18n="UI.manage.temperature"></div>
                        <div class="info-subtitle" id="info-temperature-subtitle"></div>
                    </div>
                    <div class="info-value" id="info-temperature-value">--</div>
                </div>
                <div class="info-card">
                    <div class="info-icon drivetrain"><svg viewBox="0 0 24 24" width="24" height="24">${SVG.drivetrain}</svg></div>
                    <div class="info-details">
                        <div class="info-title" data-i18n="UI.manage.drivetrain"></div>
                        <div class="info-subtitle" id="info-drivetrain-subtitle"></div>
                    </div>
                    <div class="info-value" id="info-drivetrain-value">--</div>
                </div>
            </div>
        </div>
    `;

    // --- door diagram --------------------------------------------------------

    const doorParts = ['door-0', 'door-1', 'door-2', 'door-3'];

    function setDoorActive(part, active) {
        const wrapper = el.querySelector(`.lock-btn-wrapper[data-part="${part}"]`);
        if (wrapper) wrapper.classList.toggle('active', active);
    }

    function renderDiagram() {
        doorParts.forEach((part, index) => setDoorActive(part, state.doors[index]));
        setDoorActive('hood', state.hood);
        setDoorActive('trunk', state.trunk);
    }

    el.querySelectorAll('.lock-btn-wrapper').forEach((wrapper) => {
        wrapper.addEventListener('click', () => {
            const part = wrapper.dataset.part;
            if (part === 'trunk') {
                state.trunk = !state.trunk;
                NUI.post('toggleTrunk', { open: state.trunk });
                renderDiagram();
                return;
            }
            if (part === 'hood') {
                state.hood = !state.hood;
                NUI.post('toggleDoor', { door: 4, open: state.hood });
                renderDiagram();
                return;
            }
            const index = doorParts.indexOf(part);
            if (index === -1) return;
            state.doors[index] = !state.doors[index];
            NUI.post('toggleDoor', { door: index, open: state.doors[index] });
            renderDiagram();
        });
    });

    // --- cards ---------------------------------------------------------------

    const badges = {
        doors: document.getElementById('doors-badge'),
        lock: document.getElementById('lock-badge'),
        seatbelt: document.getElementById('seatbelt-badge'),
        windows: document.getElementById('windows-badge'),
        engine: document.getElementById('engine-badge'),
        lights: document.getElementById('lights-badge'),
    };
    const subtitles = {
        doors: document.getElementById('doors-subtitle'),
        lock: document.getElementById('lock-subtitle'),
        seatbelt: document.getElementById('seatbelt-subtitle'),
        windows: document.getElementById('windows-subtitle'),
        engine: document.getElementById('engine-subtitle'),
        lights: document.getElementById('lights-subtitle'),
        seat: document.getElementById('seat-subtitle'),
    };
    const cards = {
        doors: document.getElementById('doors-card'),
        lock: document.getElementById('lock-card'),
        seatbelt: document.getElementById('seatbelt-card'),
        windows: document.getElementById('windows-card'),
        engine: document.getElementById('engine-card'),
        lights: document.getElementById('lights-card'),
        seat: document.getElementById('seat-card'),
    };

    function renderCards() {
        badges.doors.textContent = Locale.L(state.doors.every(Boolean) ? 'UI.manage.open' : 'UI.manage.closed');
        badges.doors.classList.toggle('active', state.doors.every(Boolean));
        subtitles.doors.textContent = Locale.L('UI.manage.toggleDoors');

        badges.lock.textContent = Locale.L(state.locked ? 'UI.manage.on' : 'UI.manage.off');
        badges.lock.classList.toggle('active', state.locked);
        subtitles.lock.textContent = Locale.L(state.locked ? 'UI.manage.doorsLocked' : 'UI.manage.doorsUnlocked');

        badges.seatbelt.textContent = Locale.L(state.seatbeltOn ? 'UI.manage.on' : 'UI.manage.off');
        badges.seatbelt.classList.toggle('active', state.seatbeltOn);
        subtitles.seatbelt.textContent = Locale.L(state.seatbeltOn ? 'notifications.vehicle.seatbeltOn' : 'notifications.vehicle.seatbeltOff');

        badges.windows.textContent = Locale.L(state.windowsDown ? 'UI.manage.down' : 'UI.manage.up');
        badges.windows.classList.toggle('active', state.windowsDown);
        subtitles.windows.textContent = Locale.L(state.windowsDown ? 'notifications.vehicle.windowsDown' : 'notifications.vehicle.windowsUp');

        badges.engine.textContent = Locale.L(state.engineOn ? 'UI.manage.on' : 'UI.manage.off');
        badges.engine.classList.toggle('active', state.engineOn);
        subtitles.engine.textContent = Locale.L(state.engineOn ? 'UI.manage.engineRunning' : 'UI.manage.engineOff');

        badges.lights.textContent = Locale.L(state.lightsOn ? 'UI.manage.on' : 'UI.manage.off');
        badges.lights.classList.toggle('active', state.lightsOn);
        subtitles.lights.textContent = Locale.L(state.lightsOn ? 'UI.manage.lightsOn' : 'UI.manage.lightsOff');

        subtitles.seat.textContent = Locale.L('UI.manage.selectSeat');
        cards.seat.classList.toggle('active', state.seatPickerOpen);
    }

    cards.doors.addEventListener('click', () => {
        const nextOpen = !state.doors.every(Boolean);
        if (nextOpen) {
            // Lua's toggleDoors(open=true) only opens doors 0-3.
            state.doors = [true, true, true, true];
        } else {
            // Lua's toggleDoors(open=false) calls SetVehicleDoorsShut, which
            // closes every door on the vehicle including hood/trunk.
            state.doors = [false, false, false, false];
            state.hood = false;
            state.trunk = false;
        }
        NUI.post('toggleDoors', { open: nextOpen });
        renderDiagram();
        renderCards();
    });

    cards.lock.addEventListener('click', () => {
        state.locked = !state.locked;
        NUI.post('toggleLock', { locked: state.locked });
        renderCards();
    });

    cards.seatbelt.addEventListener('click', () => {
        state.seatbeltOn = !state.seatbeltOn;
        NUI.post('toggleSeatbelt', { on: state.seatbeltOn });
        renderCards();
    });

    cards.windows.addEventListener('click', () => {
        state.windowsDown = !state.windowsDown;
        NUI.post('toggleWindows', { down: state.windowsDown });
        renderCards();
    });

    cards.engine.addEventListener('click', () => {
        state.engineOn = !state.engineOn;
        NUI.post('toggleEngine', { on: state.engineOn });
        renderCards();
    });

    cards.lights.addEventListener('click', () => {
        state.lightsOn = !state.lightsOn;
        NUI.post('toggleLights', { on: state.lightsOn });
        renderCards();
    });

    // --- seat picker -----------------------------------------------------

    const seatPicker = document.getElementById('seat-picker');
    const SEAT_LABELS = ['1', '2', '3', '4'];

    function buildSeatPicker() {
        seatPicker.innerHTML = SEAT_LABELS.map((label, i) => `
            <button type="button" data-seat="${i + 1}">
                <img src="${SEAT_ICON}" width="18" height="18" alt="" />
                <span>${Locale.L('UI.manage.seat')} ${label}</span>
            </button>`).join('');
        seatPicker.querySelectorAll('button').forEach((btn) => {
            btn.addEventListener('click', () => {
                const seat = Number(btn.dataset.seat);
                NUI.post('selectSeat', { seat });
                state.seatPickerOpen = false;
                seatPicker.hidden = true;
                renderCards();
            });
        });
    }
    buildSeatPicker();

    cards.seat.addEventListener('click', () => {
        state.seatPickerOpen = !state.seatPickerOpen;
        seatPicker.hidden = !state.seatPickerOpen;
        renderCards();
    });

    // --- vehicle info ----------------------------------------------------

    const gaugeEls = {
        gas: document.getElementById('gauge-gas'),
        body: document.getElementById('gauge-body'),
        tires: document.getElementById('gauge-tires'),
    };
    const infoTempValue = document.getElementById('info-temperature-value');
    const infoTempSubtitle = document.getElementById('info-temperature-subtitle');
    const infoDrivetrainValue = document.getElementById('info-drivetrain-value');
    const infoDrivetrainSubtitle = document.getElementById('info-drivetrain-subtitle');

    let lastVehicleInfo = null;

    function renderVehicleInfo() {
        if (!lastVehicleInfo) return;
        const info = lastVehicleInfo;
        const clampPct = (n) => `${Math.max(0, Math.min(100, Math.round(n || 0)))}%`;
        gaugeEls.gas.style.height = clampPct(info.fuelLevel);
        gaugeEls.body.style.height = clampPct(info.bodyHealth);
        gaugeEls.tires.style.height = clampPct(info.tireHealth);

        infoTempValue.innerHTML = `${Math.round(info.engineTemp || 0)}<sup>&deg;C</sup>`;
        infoTempSubtitle.textContent = Locale.L('UI.manage.vehicle');

        infoDrivetrainValue.textContent = info.drivetrain || 'N/A';
        const biasPct = Math.round((info.driveBias ?? 0.5) * 100);
        infoDrivetrainSubtitle.textContent = `${biasPct}% ${Locale.L('UI.manage.vehicle')}`;
    }

    async function refreshVehicleInfo() {
        const info = await NUI.post('getVehicleInfo');
        if (info) {
            lastVehicleInfo = info;
            renderVehicleInfo();
        }
    }

    document.addEventListener('localechange', () => {
        renderCards();
        buildSeatPicker();
        renderVehicleInfo();
    });

    App.registerScreen('manage', {
        el,
        onShow() {
            renderDiagram();
            renderCards();
            refreshVehicleInfo();
        },
    });

    return {};
})();
