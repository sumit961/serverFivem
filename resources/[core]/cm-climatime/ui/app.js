const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-climatime';

let state = null;
let weatherTypes = [];
let ui = { Accent: '#00e5ff', Brand: 'Climatime' };
let receivedAt = Date.now();
let localScheduleItems = [];
let editingZoneId = null;
let selectedZonePool = ['CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN'];
const DEFAULT_WEATHER_VALUES = ['EXTRASUNNY', 'CLEAR', 'NEUTRAL', 'CLOUDS', 'OVERCAST', 'CLEARING', 'RAIN', 'THUNDER', 'FOGGY', 'SMOG', 'SNOW', 'SNOWLIGHT', 'BLIZZARD', 'XMAS', 'HALLOWEEN'];

// Local/offline GTA map coordinate system.
// NUI cannot read GTA V's pause-map texture directly, so this uses local image layers.
// It will use the stitched custom GTA map first, then fallback to gta-map-local.png.
const GTA_MAP = {
    MIN_X: -3900,
    MAX_X: 4619,
    MIN_Y: -4764,
    MAX_Y: 7510,
    DEFAULT_CENTER: [1500, 0], // [Y, X]
    DEFAULT_ZOOM: -2,
    MIN_ZOOM: -4,
    MAX_ZOOM: 1,

    // GTA-style tiled minimap layer. NUI cannot scan folders, so tile names are listed here.
    // Your requested layout is 2 columns x 3 rows:
    // top row    = 00, 01
    // middle row = 10, 11
    // bottom row = 20, 21
    TILE_COLUMNS: 2,
    TILE_ROWS: 3,
    TILES: [
        { x: 0, y: 0, src: 'assets/map_tiles/minimap_sea_0_0.png' },
        { x: 1, y: 0, src: 'assets/map_tiles/minimap_sea_0_1.png' },
        { x: 0, y: 1, src: 'assets/map_tiles/minimap_sea_1_0.png' },
        { x: 1, y: 1, src: 'assets/map_tiles/minimap_sea_1_1.png' },
        { x: 0, y: 2, src: 'assets/map_tiles/minimap_sea_2_0.png' },
        { x: 1, y: 2, src: 'assets/map_tiles/minimap_sea_2_1.png' }
    ],

    // Fallback only if no tiles load.
    IMAGE_SOURCES: ['assets/gta-map-local.png']
};


function applyMapConfig(mapConfig = {}) {
    const bounds = mapConfig.Bounds || mapConfig.bounds || {};
    const minX = Number(bounds.minX ?? bounds.MinX);
    const maxX = Number(bounds.maxX ?? bounds.MaxX);
    const minY = Number(bounds.minY ?? bounds.MinY);
    const maxY = Number(bounds.maxY ?? bounds.MaxY);
    if (Number.isFinite(minX)) GTA_MAP.MIN_X = minX;
    if (Number.isFinite(maxX)) GTA_MAP.MAX_X = maxX;
    if (Number.isFinite(minY)) GTA_MAP.MIN_Y = minY;
    if (Number.isFinite(maxY)) GTA_MAP.MAX_Y = maxY;
    if (zoneMap && window.L) {
        const boundsArray = getZoneMapBounds();
        zoneMap.setMaxBounds(boundsArray);
    }
}

let zoneMap = null;
let zoneMapLayer = null;
let zoneSelectedLayer = null;
let zoneMapReady = false;
let zoneMapUpdateQueued = false;
let lastMapMoveAt = 0;

const $ = (id) => document.getElementById(id);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

function post(name, data = {}) {
    return fetch(`https://${resourceName}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).then(r => r.json()).catch(() => ({}));
}

function isAppVisible() {
    const app = $('app');
    return !!app && !app.classList.contains('hidden');
}

function canEdit() {
    return !ui.Permissions || ui.Permissions.edit !== false;
}

function adminAction(action, data = {}) {
    if (!canEdit()) {
        showToast('View-only access: you can inspect climate but cannot edit.');
        return Promise.resolve({ ok: false });
    }
    return post('adminAction', { action, data });
}

function fmtTime(h, m) {
    h = Number(h || 0); m = Number(m || 0);
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

function timePartsFromMinutes(total) {
    total = ((Number(total) || 0) % 1440 + 1440) % 1440;
    return [Math.floor(total / 60), total % 60];
}

function minutesFromTimeString(v) {
    const [h, m] = String(v || '00:00').split(':').map(Number);
    return (h * 60) + m;
}

function currentMinutesFromState() {
    if (!state || !state.time) return 720;
    const base = (Number(state.time.displayHour ?? state.time.hour ?? 0) * 60) + Number(state.time.displayMinute ?? state.time.minute ?? 0);
    if (state.time.freeze) return base % 1440;
    const elapsed = Math.floor((Date.now() - receivedAt) / 60000);
    return (base + elapsed) % 1440;
}

function weatherMeta(value) {
    return weatherTypes.find(w => w.value === value) || { value, label: value || 'Unknown', icon: '☁' };
}

function isValidWeather(value) {
    value = String(value || '').toUpperCase().trim();
    if (!value) return false;
    if (weatherTypes.length) return weatherTypes.some(w => w.value === value);
    return DEFAULT_WEATHER_VALUES.includes(value);
}

function normalizeWeatherPool(input, fallback = ['CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN']) {
    const raw = Array.isArray(input)
        ? input
        : String(input || '').split(',');
    const out = [];
    raw.forEach(item => {
        const weather = String(item || '').toUpperCase().trim();
        if (weather && isValidWeather(weather) && !out.includes(weather)) out.push(weather);
    });
    if (!out.length && fallback) return normalizeWeatherPool(fallback, null);
    return out;
}

function syncZonePoolInput() {
    const input = $('zonePool');
    if (input) input.value = selectedZonePool.join(', ');
    const count = $('zonePoolCount');
    if (count) count.textContent = `${selectedZonePool.length} selected`;
}


function showZoneForm(open = true) {
    const form = $('zoneForm');
    if (form) form.classList.toggle('hidden', open !== true);
}

function updateSelectedZoneWeatherDisplay() {
    const selected = $('zoneSelectedWeather');
    const select = $('zoneWeather');
    if (!selected || !select) return;
    const weather = String(select.value || selectedZonePool[0] || 'CLEAR').toUpperCase();
    const meta = weatherMeta(weather);
    selected.innerHTML = `<span>${meta.icon || '☁'}</span><b>All-time weather</b><strong>${escapeHtml(meta.label || weather)}</strong><small>Click a chip below to change this weather.</small>`;
}

function setZoneWeather(weather) {
    weather = String(weather || '').toUpperCase().trim();
    if (!isValidWeather(weather)) return;
    const select = $('zoneWeather');
    if (select) select.value = weather;
    if (($('zoneMode')?.value || 'static') === 'static') {
        selectedZonePool = [weather];
        syncZonePoolInput();
    }
    renderWeatherPalette();
    renderMixPool();
    updateSelectedZoneWeatherDisplay();
    scheduleZoneMapUpdate();
}

function beginNewZoneAt(x, y) {
    const form = $('zoneForm');
    if (!form || form.classList.contains('hidden')) {
        clearZoneForm({ keepOpen: true });
    }
    showZoneForm(true);
    setZoneFormCoords(x, y);
    centerZoneMap(x, y, { keepZoom: true });
    scheduleZoneMapUpdate();
}

function setZonePool(pool, options = {}) {
    selectedZonePool = normalizeWeatherPool(pool, options.allowEmpty ? null : ['CLEAR']);
    syncZonePoolInput();
    renderMixPool();
    renderWeatherPalette();
}

function addZonePoolWeather(weather) {
    weather = String(weather || '').toUpperCase().trim();
    if (!isValidWeather(weather)) return;
    if (!selectedZonePool.includes(weather)) selectedZonePool.push(weather);
    if ($('zoneMode') && $('zoneMode').value === 'static') $('zoneMode').value = 'mix';
    syncZonePoolInput();
    renderMixPool();
    renderWeatherPalette();
    syncZoneModeUI();
}

function removeZonePoolWeather(weather) {
    weather = String(weather || '').toUpperCase().trim();
    selectedZonePool = selectedZonePool.filter(w => w !== weather);
    syncZonePoolInput();
    renderMixPool();
    renderWeatherPalette();
}

function createWeatherChip(weather, selected = false) {
    const meta = weatherMeta(weather);
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = `weatherChip ${selected ? 'selected' : ''}`;
    btn.draggable = true;
    btn.dataset.weather = meta.value;
    btn.innerHTML = `<span>${meta.icon || '☁'}</span><b>${escapeHtml(meta.label || meta.value)}</b>`;
    btn.addEventListener('click', () => {
        if (($('zoneMode')?.value || 'static') === 'static') setZoneWeather(meta.value);
        else addZonePoolWeather(meta.value);
    });
    btn.addEventListener('dragstart', (event) => {
        event.dataTransfer.setData('text/weather', meta.value);
        event.dataTransfer.setData('text/plain', meta.value);
        btn.classList.add('dragging');
    });
    btn.addEventListener('dragend', () => btn.classList.remove('dragging'));
    return btn;
}

function renderWeatherPalette() {
    const wrap = $('zoneWeatherPalette');
    if (!wrap) return;
    wrap.innerHTML = '';
    const activeWeather = $('zoneWeather')?.value;
    const staticMode = ($('zoneMode')?.value || 'static') === 'static';
    weatherTypes.forEach(w => wrap.appendChild(createWeatherChip(w.value, staticMode ? activeWeather === w.value : selectedZonePool.includes(w.value))));
}

function renderMixPool() {
    const drop = $('zonePoolDrop');
    if (!drop) return;
    drop.innerHTML = '';
    if (!selectedZonePool.length) {
        const empty = document.createElement('span');
        empty.className = 'dropHint';
        empty.textContent = 'Drop weather here or click chips above';
        drop.appendChild(empty);
        drop.classList.add('empty');
        syncZonePoolInput();
        return;
    }
    drop.classList.remove('empty');
    selectedZonePool.forEach(weather => {
        const meta = weatherMeta(weather);
        const chip = document.createElement('div');
        chip.className = 'poolChip';
        chip.dataset.weather = weather;
        chip.innerHTML = `<span>${meta.icon || '☁'}</span><b>${escapeHtml(meta.label || weather)}</b><button type="button" aria-label="Remove ${escapeHtml(weather)}">×</button>`;
        chip.querySelector('button').addEventListener('click', () => removeZonePoolWeather(weather));
        drop.appendChild(chip);
    });
    syncZonePoolInput();
}

function setupMixDropZone() {
    const drop = $('zonePoolDrop');
    if (!drop || drop.dataset.ready === 'true') return;
    drop.dataset.ready = 'true';
    ['dragenter', 'dragover'].forEach(name => {
        drop.addEventListener(name, (event) => {
            event.preventDefault();
            drop.classList.add('dragOver');
        });
    });
    ['dragleave', 'drop'].forEach(name => {
        drop.addEventListener(name, () => drop.classList.remove('dragOver'));
    });
    drop.addEventListener('drop', (event) => {
        event.preventDefault();
        const weather = event.dataTransfer.getData('text/weather') || event.dataTransfer.getData('text/plain');
        addZonePoolWeather(weather);
    });
}

function syncZoneModeUI() {
    const mode = $('zoneMode')?.value || 'static';
    const builder = $('zoneMixBuilder');
    if (builder) builder.classList.toggle('disabled', mode === 'static');
    const duration = $('zoneDurationWrap');
    if (duration) duration.classList.toggle('hidden', mode === 'static');
    updateSelectedZoneWeatherDisplay();
    renderWeatherPalette();
    return mode;
}

function buildMixWeatherUI() {
    setupMixDropZone();
    renderWeatherPalette();
    renderMixPool();
    syncZoneModeUI();
}

function fillProfileSelect() {
    const select = $('weatherProfile');
    if (!select) return;
    const profiles = ui.WeatherProfiles || {};
    const current = state?.weather?.profile || 'normal';
    select.innerHTML = '';
    Object.entries(profiles).forEach(([key, profile]) => {
        const opt = document.createElement('option');
        opt.value = key;
        opt.textContent = profile.label || key;
        select.appendChild(opt);
    });
    if (!select.children.length) {
        const opt = document.createElement('option'); opt.value = 'normal'; opt.textContent = 'Normal'; select.appendChild(opt);
    }
    if ([...select.options].some(o => o.value === current)) select.value = current;
}

function secondsToText(unix) {
    if (!unix) return '--';
    const diff = Math.max(0, Number(unix) - Math.floor(Date.now() / 1000));
    if (diff <= 0) return 'now';
    const m = Math.floor(diff / 60);
    const s = diff % 60;
    if (m <= 0) return `${s}s`;
    return `${m}m ${s}s`;
}

function setAccent() {
    document.documentElement.style.setProperty('--accent', ui.Accent || '#00e5ff');
    document.documentElement.style.setProperty('--accent-soft', hexToRgba(ui.Accent || '#00e5ff', 0.14));
    document.documentElement.style.setProperty('--accent-border', hexToRgba(ui.Accent || '#00e5ff', 0.46));
    const brand = document.querySelector('.brandName');
    if (brand) brand.textContent = ui.Brand || 'Climatime';
}

function hexToRgba(hex, alpha) {
    const h = String(hex || '#00e5ff').replace('#', '');
    const normalized = h.length === 3 ? h.split('').map(c => c + c).join('') : h.padEnd(6, '0').slice(0, 6);
    const bigint = parseInt(normalized, 16);
    const r = (bigint >> 16) & 255;
    const g = (bigint >> 8) & 255;
    const b = bigint & 255;
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function fillWeatherSelect(select) {
    if (!select) return;
    const previous = select.value;
    select.innerHTML = '';
    weatherTypes.forEach(w => {
        const opt = document.createElement('option');
        opt.value = w.value;
        opt.textContent = `${w.icon || '☁'} ${w.label || w.value}`;
        select.appendChild(opt);
    });
    if (previous && weatherTypes.some(w => w.value === previous)) select.value = previous;
}

function fillPresetSelect() {
    const select = $('eventPreset');
    if (!select) return;
    const presets = ui.EventPresets || {};
    select.innerHTML = '';
    Object.entries(presets).forEach(([key, preset]) => {
        const opt = document.createElement('option');
        opt.value = key;
        opt.textContent = preset.label || key;
        select.appendChild(opt);
    });
    if (!select.children.length) {
        const opt = document.createElement('option'); opt.value = ''; opt.textContent = 'No presets configured'; select.appendChild(opt);
    }
}

function fillAllSelects() {
    ['scheduleWeather', 'zoneWeather'].forEach(id => fillWeatherSelect($(id)));
    fillPresetSelect();
    fillProfileSelect();
}

function buildWeatherGrid() {
    const grid = $('weatherGrid');
    if (!grid) return;
    grid.innerHTML = '';
    const current = state?.weather?.current;
    weatherTypes.forEach(w => {
        const btn = document.createElement('button');
        btn.className = `weatherBtn ${current === w.value ? 'active' : ''}`;
        btn.innerHTML = `<span class="ico">${w.icon || '☁'}</span><small>Weather</small><strong>${w.label || w.value}</strong>`;
        btn.addEventListener('click', () => adminAction('setWeather', { weather: w.value }));
        grid.appendChild(btn);
    });
}

function setTab(tab) {
    $$('.nav').forEach(n => n.classList.toggle('active', n.dataset.tab === tab));
    $$('.tab').forEach(t => t.classList.toggle('active', t.id === `tab-${tab}`));
    const titles = {
        weather: ['Forecast', 'Current conditions and weather management controls.'],
        time: ['Time Manager', 'Configure the in-game time using real-life time or a custom value.'],
        schedule: ['Schedule Presets', 'Create weather rotation presets with custom durations.'],
        zones: ['Weather Zones', 'Create local weather with visual static, dynamic, or mixed pools.']
    };
    $('breadcrumb').textContent = `Climatime › ${tab[0].toUpperCase()}${tab.slice(1)}`;
    $('pageTitle').textContent = titles[tab][0];
    $('pageDesc').textContent = titles[tab][1];

    if (tab === 'zones') {
        setTimeout(() => {
            initZoneMap();
            updateZoneMap();
            invalidateZoneMap();
        }, 80);
    }
}

function dayPart(hour) {
    if (hour >= 5 && hour < 12) return 'Morning';
    if (hour >= 12 && hour < 17) return 'Afternoon';
    if (hour >= 17 && hour < 20) return 'Evening';
    return 'Night';
}

function updateTimeUI() {
    const total = currentMinutesFromState();
    const [h, m] = timePartsFromMinutes(total);
    const text = fmtTime(h, m);
    $('topTime').textContent = text;
    $('weatherTime').textContent = text;
    $('currentTimeBig').textContent = text;
    $('dayPart').textContent = dayPart(h);
}

function renderHistory() {
    const wrap = $('historyList');
    if (!wrap) return;
    const items = state?.historyPublic || [];
    if (!items.length) { wrap.innerHTML = '<small class="muted">No admin history yet.</small>'; return; }
    wrap.innerHTML = items.slice(0, 6).map(item => {
        const time = item.at ? new Date(item.at * 1000).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) : '--';
        return `<div class="historyItem"><b>${escapeHtml(item.action || 'action')}</b><small>${escapeHtml(item.admin || '')} • ${time}</small></div>`;
    }).join('');
}

function updateWeatherUI() {
    if (!state || !state.weather) return;
    const w = weatherMeta(state.weather.current);
    $('weatherIcon').textContent = w.icon || '☁';
    $('weatherName').textContent = w.label || w.value;
    $('weatherMode').textContent = state.schedule?.active ? 'Schedule' : (state.weather.dynamic ? 'Dynamic' : 'Manual');
    $('nextChange').textContent = state.schedule?.active ? secondsToText(state.schedule.nextChangeAt) : secondsToText(state.weather.nextChangeAt);
    $('transitionRead').textContent = `${state.weather.transitionSeconds || 0}s`;

    $('dynamicToggle').checked = !!state.weather.dynamic;
    $('freezeWeather').checked = !!state.weather.freeze;
    if ($('smoothToggle')) $('smoothToggle').checked = state.weather.smooth !== false && !state.weather.instant;
    $('instantToggle').checked = !!state.weather.instant;
    $('blackoutToggle').checked = !!state.weather.blackout;
    $('snowToggle').checked = !!state.weather.snow;
    $('weatherDuration').value = state.weather.durationMinutes || 30;
    $('transitionSeconds').value = state.weather.transitionSeconds || 20;

    buildWeatherGrid();
    renderHistory();
}

function updateTimeForm() {
    if (!state || !state.time) return;
    const total = currentMinutesFromState();
    const [h, m] = timePartsFromMinutes(total);
    $('timeRange').value = total;
    $('customTime').value = fmtTime(h, m);
    $('freezeTime').checked = !!state.time.freeze;
}

function updateScheduleUI() {
    localScheduleItems = (state?.schedule?.items || []).map(x => ({ ...x }));
    $('scheduleActive').checked = !!state?.schedule?.active;
    $('scheduleBadge').textContent = state?.schedule?.active ? 'ACTIVE' : 'INACTIVE';
    renderScheduleList();
}

function renderScheduleList() {
    const wrap = $('scheduleList');
    wrap.innerHTML = '';
    localScheduleItems.forEach((item, index) => {
        const meta = weatherMeta(item.weather);
        const el = document.createElement('div');
        el.className = `schedItem ${state?.schedule?.active && (state.schedule.index - 1) === index ? 'active' : ''}`;
        const mode = item.mode || 'sequence';
        const startLabel = mode === 'delay'
            ? `Starts after ${item.delayMinutes || '--'} min`
            : (mode === 'time'
                ? `Starts at ${fmtTime(Math.floor((item.startMinutes || 0) / 60), (item.startMinutes || 0) % 60)}${item.repeatDaily ? ' daily' : ''}`
                : 'Weather rotation item');
        el.innerHTML = `
            <small>${String(item.durationMinutes).padStart(2, '0')}:00 ◷ • ${mode}</small>
            <div class="schedWeather">${meta.icon || '☁'} ${meta.label || item.weather}</div>
            <small>${startLabel}</small>
            <button class="trash">🗑</button>
        `;
        el.querySelector('.trash').addEventListener('click', () => {
            localScheduleItems.splice(index, 1);
            renderScheduleList();
        });
        wrap.appendChild(el);
    });
}

function updateZonesUI() {
    if (!state || !state.zones) return;
    $('zonesEnabled').checked = !!state.zones.enabled;
    renderZones();
    updateZoneMap();
}

function renderZones() {
    const wrap = $('zoneList');
    wrap.innerHTML = '';
    const zones = state?.zones?.items || [];
    if (!zones.length) {
        wrap.innerHTML = '<p class="muted">No weather zones yet. Click the map or use Get Current Position, choose weather, then Save Zone.</p>';
        return;
    }

    zones.forEach(zone => {
        const meta = weatherMeta(zone.currentWeather || zone.weather);
        const players = state?.zoneDebug?.counts?.[zone.id] || 0;
        const pool = normalizeWeatherPool(zone.pool || [], null);
        const poolText = pool.length ? ` • Pool ${pool.slice(0, 4).join(', ')}${pool.length > 4 ? ' +' + (pool.length - 4) : ''}` : '';
        const el = document.createElement('div');
        el.className = `zoneItem ${editingZoneId === zone.id ? 'active' : ''}`;
        el.innerHTML = `
            <div class="zoneItemTop">
                <strong>${escapeHtml(zone.name || zone.id)}</strong>
                <small>${zone.enabled === false ? 'OFF' : 'ON'} • ${zone.mode === 'static' ? 'all-time' : (zone.mode || 'static')}</small>
            </div>
            <small>${meta.icon || '☁'} ${meta.label || zone.weather}${poolText} • Radius ${Math.round(zone.radius || 0)} • Priority ${zone.priority || 0} • Players ${players} • X ${Number(zone.x).toFixed(1)} Y ${Number(zone.y).toFixed(1)}</small>
            <div class="zoneActions">
                <button class="ghost focus">Map</button>
                <button class="ghost edit">Edit</button>
                <button class="danger delete">Delete</button>
            </div>
        `;
        el.querySelector('.focus').addEventListener('click', () => centerZoneMap(zone.x, zone.y));
        el.querySelector('.edit').addEventListener('click', () => fillZoneForm(zone));
        el.querySelector('.delete').addEventListener('click', () => adminAction('deleteZone', { id: zone.id }));
        wrap.appendChild(el);
    });
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, ch => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
    }[ch]));
}

function fillZoneForm(zone) {
    showZoneForm(true);
    editingZoneId = zone.id;
    $('zoneId').value = zone.id || '#auto';
    $('zoneName').value = zone.name || '';
    $('zoneMode').value = zone.mode || 'static';
    $('zoneWeather').value = zone.weather || zone.currentWeather || 'CLEAR';
    setZonePool(zone.mode === 'static' ? [($('zoneWeather').value || 'CLEAR')] : (zone.pool || ['CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN']));
    $('zoneX').value = Number(zone.x || 0).toFixed(2);
    $('zoneY').value = Number(zone.y || 0).toFixed(2);
    $('zoneZ').value = Number(zone.z || 0).toFixed(2);
    $('zoneRadius').value = zone.radius || 200;
    $('zoneDuration').value = zone.durationMinutes || 20;
    if ($('zonePriority')) $('zonePriority').value = zone.priority || 0;
    buildMixWeatherUI();
    setTab('zones');
    setTimeout(() => {
        centerZoneMap(zone.x, zone.y);
        updateZoneMap();
    }, 100);
}

function clearZoneForm(options = {}) {
    editingZoneId = null;
    $('zoneId').value = '#auto';
    $('zoneName').value = '';
    $('zoneMode').value = 'static';
    $('zoneWeather').value = weatherTypes[0]?.value || 'CLEAR';
    setZonePool(['CLEAR', 'CLOUDS', 'OVERCAST', 'RAIN']);
    $('zoneX').value = 0;
    $('zoneY').value = 0;
    $('zoneZ').value = 0;
    $('zoneRadius').value = 200;
    $('zoneDuration').value = 20;
    if ($('zonePriority')) $('zonePriority').value = 0;
    buildMixWeatherUI();
    updateSelectedZoneWeatherDisplay();
    if (!options.keepOpen) showZoneForm(false);
    renderZones();
    updateZoneMap();
}

function readZoneForm() {
    const pool = normalizeWeatherPool(selectedZonePool, ['CLEAR']);
    return {
        id: $('zoneId').value.trim() || '#auto',
        name: $('zoneName').value.trim() || 'Weather Zone',
        mode: $('zoneMode').value,
        weather: $('zoneWeather').value || pool[0] || 'CLEAR',
        pool,
        x: Number($('zoneX').value || 0),
        y: Number($('zoneY').value || 0),
        z: Number($('zoneZ').value || 0),
        radius: Number($('zoneRadius').value || 200),
        durationMinutes: Number($('zoneDuration').value || 20),
        priority: Number($('zonePriority')?.value || 0),
        enabled: true
    };
}

function applyPermissions() {
    const editable = canEdit();
    document.body.classList.toggle('viewOnly', !editable);
    document.querySelectorAll('button, input, select').forEach(el => {
        const id = el.id || '';
        const safe = ['exitBtn'].includes(id) || el.classList.contains('nav');
        if (!editable && !safe) el.classList.add('lockedControl');
        else el.classList.remove('lockedControl');
    });
}

function updateUI() {
    setAccent();
    fillAllSelects();
    updateTimeUI();
    updateWeatherUI();
    updateTimeForm();
    updateScheduleUI();
    updateZonesUI();
    buildMixWeatherUI();
    applyPermissions();
}

function getZoneMapBounds() {
    return [
        [GTA_MAP.MIN_Y, GTA_MAP.MIN_X],
        [GTA_MAP.MAX_Y, GTA_MAP.MAX_X]
    ];
}

function loadFallbackMap(L, bounds, sourceIndex = 0) {
    const src = GTA_MAP.IMAGE_SOURCES[sourceIndex] || GTA_MAP.IMAGE_SOURCES[GTA_MAP.IMAGE_SOURCES.length - 1];
    const img = new Image();
    img.onload = () => {
        if (!zoneMap) return;
        L.imageOverlay(src, bounds, {
            interactive: false,
            className: 'gta-local-map-layer gta-map-fallback'
        }).addTo(zoneMap);
        const hint = $('zoneMapHint');
        if (hint) hint.textContent = 'Click map to set center • drag center • drag radius handle';
    };
    img.onerror = () => {
        if (sourceIndex + 1 < GTA_MAP.IMAGE_SOURCES.length) {
            loadFallbackMap(L, bounds, sourceIndex + 1);
            return;
        }
        const hint = $('zoneMapHint');
        if (hint) hint.textContent = 'Map image missing, but click/drag still works';
    };
    img.src = src;
}

function getTileBounds(tile) {
    const columns = Math.max(1, Number(GTA_MAP.TILE_COLUMNS || 1));
    const rows = Math.max(1, Number(GTA_MAP.TILE_ROWS || 1));
    const tileWidth = (GTA_MAP.MAX_X - GTA_MAP.MIN_X) / columns;
    const tileHeight = (GTA_MAP.MAX_Y - GTA_MAP.MIN_Y) / rows;

    const x1 = GTA_MAP.MIN_X + (Number(tile.x || 0) * tileWidth);
    const x2 = x1 + tileWidth;

    // GTA minimap tile rows start from the top. Leaflet bounds use bottom-to-top Y.
    const yTop = GTA_MAP.MAX_Y - (Number(tile.y || 0) * tileHeight);
    const yBottom = yTop - tileHeight;

    return [[yBottom, x1], [yTop, x2]];
}

function loadZoneBaseMap(L, bounds) {
    const tiles = Array.isArray(GTA_MAP.TILES) ? GTA_MAP.TILES : [];
    if (!tiles.length) {
        loadFallbackMap(L, bounds);
        return;
    }

    let loaded = 0;
    let failed = 0;
    tiles.forEach(tile => {
        const img = new Image();
        img.onload = () => {
            if (!zoneMap) return;
            loaded += 1;
            L.imageOverlay(tile.src, getTileBounds(tile), {
                interactive: false,
                className: 'gta-local-map-layer gta-map-tile-layer'
            }).addTo(zoneMap);

            const hint = $('zoneMapHint');
            if (hint) hint.textContent = `Map tiles ${loaded}/${tiles.length} loaded • click map • drag center • drag radius`;
        };
        img.onerror = () => {
            failed += 1;
            if (failed >= tiles.length && loaded === 0) loadFallbackMap(L, bounds);
        };
        img.src = tile.src;
    });
}

function toMapCoords(x, y) {
    // Leaflet Simple CRS works as [lat, lng] = [gameY, gameX].
    return [Number(y || 0), Number(x || 0)];
}

function toGameCoords(lat, lng) {
    return [Number(lng || 0), Number(lat || 0)];
}

function clampGameX(x) {
    return Math.max(GTA_MAP.MIN_X, Math.min(GTA_MAP.MAX_X, Number(x || 0)));
}

function clampGameY(y) {
    return Math.max(GTA_MAP.MIN_Y, Math.min(GTA_MAP.MAX_Y, Number(y || 0)));
}

function setZoneFormCoords(x, y) {
    const clampedX = clampGameX(x);
    const clampedY = clampGameY(y);
    $('zoneX').value = clampedX.toFixed(2);
    $('zoneY').value = clampedY.toFixed(2);
    if (!$('zoneName').value) $('zoneName').value = 'Map Weather Zone';
    $('zoneMapCoords').textContent = `X ${clampedX.toFixed(2)} Y ${clampedY.toFixed(2)}`;
}

function setZoneFormRadius(radius) {
    const clamped = Math.max(10, Math.min(5000, Number(radius || 10)));
    $('zoneRadius').value = Math.round(clamped);
    return clamped;
}

function initZoneMap() {
    const container = $('zoneMap');
    if (!container || zoneMap) return;

    if (!window.L) {
        const hint = $('zoneMapHint');
        if (hint) hint.textContent = 'Loading local map engine...';
        setTimeout(initZoneMap, 250);
        return;
    }

    const L = window.L;
    const bounds = getZoneMapBounds();
    zoneMap = L.map(container, {
        crs: L.CRS.Simple,
        minZoom: GTA_MAP.MIN_ZOOM,
        maxZoom: GTA_MAP.MAX_ZOOM,
        center: GTA_MAP.DEFAULT_CENTER,
        zoom: GTA_MAP.DEFAULT_ZOOM,
        zoomControl: true,
        attributionControl: false,
        maxBounds: bounds,
        maxBoundsViscosity: 0.7,
        preferCanvas: true,
        doubleClickZoom: true,
        boxZoom: false,
        scrollWheelZoom: true,
        wheelDebounceTime: 80,
        wheelPxPerZoomLevel: 90
    });

    loadZoneBaseMap(L, bounds);
    zoneMap.fitBounds(bounds, { animate: false, padding: [8, 8] });

    zoneMapLayer = L.layerGroup().addTo(zoneMap);
    zoneSelectedLayer = L.layerGroup().addTo(zoneMap);

    zoneMap.on('click', (event) => {
        const [x, y] = toGameCoords(event.latlng.lat, event.latlng.lng);
        beginNewZoneAt(x, y);
    });

    zoneMap.on('mousemove', (event) => {
        const now = Date.now();
        if (now - lastMapMoveAt < 120) return;
        lastMapMoveAt = now;
        const [x, y] = toGameCoords(event.latlng.lat, event.latlng.lng);
        const hint = $('zoneMapHint');
        if (hint) hint.textContent = `Map X ${x.toFixed(0)} Y ${y.toFixed(0)} • click to set center • drag ↔ for radius`;
    });

    zoneMapReady = true;
    const hint = $('zoneMapHint');
    if (hint) hint.textContent = 'Click map to set center • drag center • drag radius handle';
    updateZoneMap();
    invalidateZoneMap();
}

function invalidateZoneMap() {
    if (!zoneMap) return;
    setTimeout(() => zoneMap.invalidateSize(), 0);
    setTimeout(() => zoneMap.invalidateSize(), 220);
}

function getZoneFormCoords() {
    return {
        x: Number($('zoneX')?.value || 0),
        y: Number($('zoneY')?.value || 0),
        radius: Math.max(10, Number($('zoneRadius')?.value || 200))
    };
}

function getAccentColor() {
    return getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#00e5ff';
}

function createZoneIcon(zone, selected = false) {
    const L = window.L;
    const meta = weatherMeta(zone?.currentWeather || zone?.weather || $('zoneWeather')?.value || 'CLEAR');
    const name = escapeHtml(zone?.name || $('zoneName')?.value || 'Zone');
    const weather = escapeHtml(meta.label || meta.value || 'Weather');
    return L.divIcon({
        className: 'cm-zone-marker-wrap',
        html: `<div class="cm-zone-marker ${selected ? 'selected' : ''}"><span>${meta.icon || '☁'}</span></div><div class="cm-zone-label"><strong>${name}</strong><small>${weather}</small></div>`,
        iconSize: [30, 30],
        iconAnchor: [15, 15]
    });
}

function createRadiusHandleIcon() {
    const L = window.L;
    return L.divIcon({
        className: 'cm-zone-radius-handle-wrap',
        html: '<div class="cm-zone-radius-handle"><span>↔</span></div>',
        iconSize: [24, 24],
        iconAnchor: [12, 12]
    });
}

function distance2D(x1, y1, x2, y2) {
    const dx = Number(x2 || 0) - Number(x1 || 0);
    const dy = Number(y2 || 0) - Number(y1 || 0);
    return Math.sqrt((dx * dx) + (dy * dy));
}

function updateCoordsReadout(x, y, radius) {
    $('zoneMapCoords').textContent = `X ${Number(x).toFixed(2)} Y ${Number(y).toFixed(2)} • R ${Math.round(radius)}`;
}

function scheduleZoneMapUpdate() {
    if (zoneMapUpdateQueued) return;
    zoneMapUpdateQueued = true;
    requestAnimationFrame(() => {
        zoneMapUpdateQueued = false;
        updateZoneMap();
    });
}

function updateZoneMap() {
    zoneMapUpdateQueued = false;
    if (!zoneMapReady || !zoneMap || !window.L) {
        initZoneMap();
        return;
    }

    const L = window.L;
    const accent = getAccentColor();
    zoneMapLayer.clearLayers();
    zoneSelectedLayer.clearLayers();

    (state?.zones?.items || []).forEach(zone => {
        if (typeof zone.x === 'undefined' || typeof zone.y === 'undefined') return;
        const [lat, lng] = toMapCoords(zone.x, zone.y);
        const enabled = zone.enabled !== false;
        const color = enabled ? accent : 'rgba(255,255,255,0.35)';
        const circle = L.circle([lat, lng], {
            radius: Number(zone.radius || 200),
            color,
            fillColor: color,
            fillOpacity: enabled ? 0.18 : 0.08,
            weight: editingZoneId === zone.id ? 3 : 1.5
        }).addTo(zoneMapLayer);
        circle.on('click', () => fillZoneForm(zone));

        L.marker([lat, lng], { icon: createZoneIcon(zone, editingZoneId === zone.id) })
            .on('click', () => fillZoneForm(zone))
            .addTo(zoneMapLayer);
    });

    const form = getZoneFormCoords();
    let currentX = clampGameX(form.x);
    let currentY = clampGameY(form.y);
    let currentRadius = setZoneFormRadius(form.radius);
    const selectedLatLng = L.latLng(...toMapCoords(currentX, currentY));
    updateCoordsReadout(currentX, currentY, currentRadius);

    const previewCircle = L.circle(selectedLatLng, {
        radius: currentRadius,
        color: accent,
        fillColor: accent,
        fillOpacity: 0.26,
        weight: 2.5,
        dashArray: '6 6'
    }).addTo(zoneSelectedLayer);

    const guideLine = L.polyline([
        selectedLatLng,
        L.latLng(...toMapCoords(currentX + currentRadius, currentY))
    ], {
        color: accent,
        weight: 1.5,
        opacity: 0.9,
        dashArray: '4 6'
    }).addTo(zoneSelectedLayer);

    const centerMarker = L.marker(selectedLatLng, {
        icon: createZoneIcon({ name: $('zoneName').value || 'New Zone', weather: $('zoneWeather').value }, true),
        draggable: true,
        autoPan: true
    }).addTo(zoneSelectedLayer);

    const handleMarker = L.marker(L.latLng(...toMapCoords(currentX + currentRadius, currentY)), {
        icon: createRadiusHandleIcon(),
        draggable: true,
        autoPan: true,
        zIndexOffset: 1000
    }).addTo(zoneSelectedLayer);

    const syncPreview = (x, y, radius, keepHandlePosition = false, handleLatLng = null) => {
        currentX = clampGameX(x);
        currentY = clampGameY(y);
        currentRadius = setZoneFormRadius(radius);
        $('zoneX').value = currentX.toFixed(2);
        $('zoneY').value = currentY.toFixed(2);

        const center = L.latLng(...toMapCoords(currentX, currentY));
        previewCircle.setLatLng(center);
        previewCircle.setRadius(currentRadius);
        centerMarker.setLatLng(center);

        const handle = keepHandlePosition && handleLatLng
            ? handleLatLng
            : L.latLng(...toMapCoords(currentX + currentRadius, currentY));

        handleMarker.setLatLng(handle);
        guideLine.setLatLngs([center, handle]);
        updateCoordsReadout(currentX, currentY, currentRadius);
    };

    centerMarker.on('drag', (event) => {
        const p = event.target.getLatLng();
        const [x, y] = toGameCoords(p.lat, p.lng);
        syncPreview(x, y, currentRadius);
    });

    centerMarker.on('dragend', () => {
        updateZoneMap();
    });

    handleMarker.on('drag', (event) => {
        const p = event.target.getLatLng();
        const [handleX, handleY] = toGameCoords(p.lat, p.lng);
        const newRadius = distance2D(currentX, currentY, handleX, handleY);
        syncPreview(currentX, currentY, newRadius, true, p);
    });

    handleMarker.on('dragend', () => {
        updateZoneMap();
    });
}

function centerZoneMap(x, y, options = {}) {
    initZoneMap();
    if (!zoneMap) return;
    const [lat, lng] = toMapCoords(x, y);
    const zoom = options.keepZoom ? zoneMap.getZoom() : Math.max(zoneMap.getZoom(), GTA_MAP.DEFAULT_ZOOM + 1);
    zoneMap.setView([lat, lng], zoom, { animate: true });
    invalidateZoneMap();
}

window.addEventListener('cm-leaflet-ready', () => {
    initZoneMap();
    updateZoneMap();
});

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') {
        state = data.state;
        weatherTypes = data.weatherTypes || weatherTypes;
        ui = data.ui || ui;
        applyMapConfig(ui.Map || {});
        receivedAt = Date.now();
        $('app').classList.remove('hidden');
        updateUI();
        setTimeout(invalidateZoneMap, 120);
    }

    if (data.action === 'state') {
        state = data.state;
        weatherTypes = data.weatherTypes || weatherTypes;
        ui = data.ui || ui;
        applyMapConfig(ui.Map || {});
        receivedAt = Date.now();
        updateUI();
    }

    if (data.action === 'toast') showToast(data.message);
});

function showToast(message) {
    const t = $('toast');
    t.textContent = message || '';
    t.classList.remove('hidden');
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(() => t.classList.add('hidden'), 2500);
}

$$('.nav').forEach(btn => btn.addEventListener('click', () => setTab(btn.dataset.tab)));
$('exitBtn').addEventListener('click', () => { $('app').classList.add('hidden'); post('close'); });

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        $('app').classList.add('hidden');
        post('close');
    }
});

$('saveWeatherOptions').addEventListener('click', () => {
    adminAction('weatherOptions', {
        dynamic: $('dynamicToggle').checked,
        freeze: $('freezeWeather').checked,
        instant: $('instantToggle').checked,
        smoothChange: $('smoothToggle') ? $('smoothToggle').checked : !$('instantToggle').checked,
        blackout: $('blackoutToggle').checked,
        snow: $('snowToggle').checked,
        durationMinutes: Number($('weatherDuration').value || 30),
        transitionSeconds: Number($('transitionSeconds').value || 20)
    });
});
$('resetWeather').addEventListener('click', () => adminAction('resetWeather'));
if ($('applyProfile')) $('applyProfile').addEventListener('click', () => adminAction('setProfile', { profile: $('weatherProfile').value }));
if ($('applyPreset')) $('applyPreset').addEventListener('click', () => adminAction('applyPreset', { preset: $('eventPreset').value }));
if ($('undoWeather')) $('undoWeather').addEventListener('click', () => adminAction('undo'));
if ($('smoothToggle')) $('smoothToggle').addEventListener('change', () => { $('instantToggle').checked = !$('smoothToggle').checked; });
$('instantToggle').addEventListener('change', () => { if ($('smoothToggle')) $('smoothToggle').checked = !$('instantToggle').checked; });

$('timeRange').addEventListener('input', () => {
    const [h, m] = timePartsFromMinutes(Number($('timeRange').value));
    $('customTime').value = fmtTime(h, m);
    $('currentTimeBig').textContent = fmtTime(h, m);
    $('dayPart').textContent = dayPart(h);
});
$('customTime').addEventListener('input', () => {
    const minutes = minutesFromTimeString($('customTime').value);
    $('timeRange').value = minutes;
});
$('setDay').addEventListener('click', () => { $('timeRange').value = 720; $('customTime').value = '12:00'; $('currentTimeBig').textContent = '12:00'; $('dayPart').textContent = 'Afternoon'; });
$('setNight').addEventListener('click', () => { $('timeRange').value = 0; $('customTime').value = '00:00'; $('currentTimeBig').textContent = '00:00'; $('dayPart').textContent = 'Night'; });
$('applyTime').addEventListener('click', () => {
    const [h, m] = $('customTime').value.split(':').map(Number);
    adminAction('setTime', { hour: h, minute: m, freeze: $('freezeTime').checked });
});
$('resetTime').addEventListener('click', () => adminAction('resetTime'));
$('freezeTime').addEventListener('change', () => adminAction('freezeTime', { freeze: $('freezeTime').checked }));

$('addSchedule').addEventListener('click', () => {
    const mode = $('scheduleMode') ? $('scheduleMode').value : 'sequence';
    localScheduleItems.push({
        id: `ui_${Date.now()}`,
        mode,
        weather: $('scheduleWeather').value,
        durationMinutes: Number($('scheduleDuration').value || 30),
        delayMinutes: Number($('scheduleDelay')?.value || 30),
        startMinutes: minutesFromTimeString($('scheduleStartTime')?.value || '18:00'),
        repeatDaily: !!$('scheduleRepeat')?.checked
    });
    renderScheduleList();
});
$('saveSchedule').addEventListener('click', () => {
    adminAction('setSchedule', {
        active: $('scheduleActive').checked,
        items: localScheduleItems,
        index: 1
    });
});
$('scheduleActive').addEventListener('change', () => {
    $('scheduleBadge').textContent = $('scheduleActive').checked ? 'ACTIVE' : 'INACTIVE';
});

$('zonesEnabled').addEventListener('change', () => adminAction('toggleZones', { enabled: $('zonesEnabled').checked }));
$('getPos').addEventListener('click', async () => {
    showZoneForm(true);
    const pos = await post('getPosition');
    if (pos && pos.ok) {
        $('zoneX').value = pos.x;
        $('zoneY').value = pos.y;
        $('zoneZ').value = pos.z;
        if (!$('zoneName').value) $('zoneName').value = pos.street || 'Weather Zone';
        $('locStreet').textContent = pos.street || 'Current Position';
        $('locSub').textContent = `X ${pos.x} Y ${pos.y}`;
        centerZoneMap(pos.x, pos.y);
        updateZoneMap();
    }
});
$('saveZone').addEventListener('click', () => adminAction('saveZone', { zone: readZoneForm() }));
$('cancelZone').addEventListener('click', clearZoneForm);
if ($('poolNormal')) $('poolNormal').addEventListener('click', () => setZonePool(['CLEAR', 'CLOUDS', 'OVERCAST', 'FOGGY']));
if ($('poolRain')) $('poolRain').addEventListener('click', () => setZonePool(['CLOUDS', 'OVERCAST', 'RAIN', 'CLEARING']));
if ($('poolStorm')) $('poolStorm').addEventListener('click', () => setZonePool(['OVERCAST', 'RAIN', 'THUNDER', 'CLEARING']));
if ($('poolSnow')) $('poolSnow').addEventListener('click', () => setZonePool(['SNOWLIGHT', 'SNOW', 'BLIZZARD', 'XMAS']));
if ($('poolClear')) $('poolClear').addEventListener('click', () => setZonePool([], { allowEmpty: true }));
if ($('zoneMode')) $('zoneMode').addEventListener('change', syncZoneModeUI);


if ($('mapNewZone')) $('mapNewZone').addEventListener('click', () => {
    showZoneForm(true);
    const center = zoneMap ? zoneMap.getCenter() : { lat: 0, lng: 0 };
    const [x, y] = toGameCoords(center.lat, center.lng);
    beginNewZoneAt(x, y);
});
if ($('mapZoomIn')) $('mapZoomIn').addEventListener('click', () => { if (zoneMap) zoneMap.zoomIn(); });
if ($('mapZoomOut')) $('mapZoomOut').addEventListener('click', () => { if (zoneMap) zoneMap.zoomOut(); });
if ($('mapFocusForm')) $('mapFocusForm').addEventListener('click', () => centerZoneMap(Number($('zoneX').value || 0), Number($('zoneY').value || 0)));
if ($('mapUsePlayer')) $('mapUsePlayer').addEventListener('click', () => $('getPos').click());

['zoneX', 'zoneY', 'zoneRadius', 'zoneWeather', 'zoneName'].forEach(id => {
    const el = $(id);
    if (el) el.addEventListener('input', scheduleZoneMapUpdate);
    if (el) el.addEventListener('change', scheduleZoneMapUpdate);
});

setInterval(() => { if (isAppVisible()) updateTimeUI(); }, 1000);
setInterval(() => {
    if (isAppVisible() && state) {
        $('nextChange').textContent = state.schedule?.active ? secondsToText(state.schedule.nextChangeAt) : secondsToText(state.weather?.nextChangeAt);
    }
}, 1000);

clearZoneForm();
