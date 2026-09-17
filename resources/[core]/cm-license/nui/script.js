const App = {
    currentDialog: null,
    selectedLicense: null,
    adminLicenses: [],
    editingId: null,
    routeContext: null,
    loadingTimer: null,
    resultTimer: null
};

const post = (name, body = {}) => fetch(`https://cm-license/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
}).catch(() => {});

const el = id => document.getElementById(id);
const value = id => (el(id)?.value || '').trim();
const formatNumber = n => Number(n || 0).toLocaleString();

// Labels and route names come from the database, so never inject them as HTML.
const escapeHtml = text => String(text ?? '').replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));

// Both the category ('ground'/'boat'/'air') and the license type ('driver'/…)
// resolve to the same three art sets.
function artKind(...candidates) {
    const raw = String(candidates.find(Boolean) || 'ground').toLowerCase();
    if (raw === 'boat') return 'boat';
    if (raw === 'air' || raw === 'helicopter' || raw === 'airplane' || raw === 'plane') return 'air';
    return 'ground';
}

const KIND_LABEL = { ground: 'Ground Vehicle', boat: 'Watercraft', air: 'Aircraft' };

/* ============================================================ hero artwork
 * Placeholder scenes drawn as SVG so the resource ships with no image assets.
 * Swap in a photo by setting --art-image on the hero element (see style.css).
 */

function heroScene(kind, uid) {
    const id = suffix => `${uid}-${suffix}`;
    const sky = {
        ground: ['#0a2c3d', '#123f52', '#2b6274'],
        boat: ['#062231', '#0d4257', '#1d6f7f'],
        air: ['#08283a', '#175066', '#3a8296']
    }[kind];

    const common = `
        <defs>
            <linearGradient id="${id('sky')}" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="${sky[0]}"/>
                <stop offset="55%" stop-color="${sky[1]}"/>
                <stop offset="100%" stop-color="${sky[2]}"/>
            </linearGradient>
            <radialGradient id="${id('sun')}" cx="0.5" cy="0.5" r="0.5">
                <stop offset="0%" stop-color="#9ff6ff" stop-opacity="0.95"/>
                <stop offset="45%" stop-color="#00e5ff" stop-opacity="0.42"/>
                <stop offset="100%" stop-color="#00e5ff" stop-opacity="0"/>
            </radialGradient>
            <linearGradient id="${id('fg')}" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stop-color="#03121b"/>
                <stop offset="100%" stop-color="#01080d"/>
            </linearGradient>
            <filter id="${id('soft')}" x="-30%" y="-30%" width="160%" height="160%">
                <feGaussianBlur stdDeviation="14"/>
            </filter>
        </defs>
        <rect width="1200" height="514" fill="url(#${id('sky')})"/>
        <circle cx="880" cy="215" r="190" fill="url(#${id('sun')})"/>`;

    const scenes = {
        ground: `
            <g opacity="0.55" fill="#04161f">
                <rect x="60" y="180" width="70" height="150"/><rect x="145" y="140" width="52" height="190"/>
                <rect x="210" y="205" width="86" height="125"/><rect x="315" y="120" width="60" height="210"/>
                <rect x="392" y="188" width="44" height="142"/><rect x="960" y="165" width="66" height="165"/>
                <rect x="1042" y="205" width="52" height="125"/><rect x="1108" y="150" width="58" height="180"/>
            </g>
            <path d="M0 330 H1200 V514 H0 Z" fill="url(#${id('fg')})"/>
            <path d="M516 330 L232 514 H968 L684 330 Z" fill="#0a2230"/>
            <g stroke="#9ff6ff" stroke-opacity="0.20" stroke-width="3">
                <path d="M516 330 L232 514"/><path d="M684 330 L968 514"/>
            </g>
            <g fill="#9ff6ff" fill-opacity="0.30">
                <rect x="597" y="336" width="6" height="16"/><rect x="596" y="366" width="8" height="22"/>
                <rect x="594" y="406" width="11" height="30"/><rect x="592" y="458" width="15" height="44"/>
            </g>
            <g transform="translate(600 348) scale(0.6)">
                <ellipse cx="0" cy="150" rx="330" ry="30" fill="#000" opacity="0.6" filter="url(#${id('soft')})"/>
                <path d="M-250 60 L-205 60 C-186 18 -150 -4 -84 -8 L74 -8 C142 -4 182 20 214 62 L262 70
                         C286 74 296 86 296 104 L296 130 C296 141 288 148 276 148 L-268 148
                         C-280 148 -288 140 -288 128 L-288 96 C-288 76 -274 66 -250 60 Z" fill="#061c26"/>
                <path d="M-196 58 C-178 22 -146 4 -88 1 L66 1 C124 4 158 24 186 58 Z" fill="#12475c" opacity="0.95"/>
                <rect x="-288" y="94" width="586" height="10" fill="#00e5ff" opacity="0.22"/>
                <circle cx="-168" cy="146" r="46" fill="#020c12"/><circle cx="-168" cy="146" r="20" fill="#0d3a4b"/>
                <circle cx="182" cy="146" r="46" fill="#020c12"/><circle cx="182" cy="146" r="20" fill="#0d3a4b"/>
                <rect x="268" y="58" width="34" height="18" rx="8" fill="#ffe3a6"/>
                <ellipse cx="300" cy="68" rx="150" ry="52" fill="#ffd27a" opacity="0.16" filter="url(#${id('soft')})"/>
                <rect x="-302" y="58" width="26" height="16" rx="7" fill="#ff8f6b" opacity="0.85"/>
            </g>`,
        boat: `
            <path d="M0 300 H1200 V514 H0 Z" fill="#05202e"/>
            <g stroke="#00e5ff" stroke-opacity="0.16" stroke-width="3" stroke-linecap="round">
                <path d="M60 344 H340"/><path d="M760 336 H1140"/><path d="M120 396 H420"/>
                <path d="M700 404 H1080"/><path d="M180 452 H520"/><path d="M660 466 H1020"/>
            </g>
            <ellipse cx="880" cy="300" rx="150" ry="16" fill="#9ff6ff" opacity="0.14"/>
            <g transform="translate(560 250)">
                <path d="M-70 -132 L-64 -18 L-8 -18 Z" fill="#0d3a4b"/>
                <rect x="-72" y="-134" width="7" height="118" fill="#0a2b38"/>
                <path d="M-250 -18 H250 L188 66 C168 90 136 102 96 102 H-150
                         C-190 102 -224 86 -244 54 Z" fill="#061c26"/>
                <path d="M-118 -74 H60 C82 -74 96 -62 100 -44 L106 -18 H-140 L-132 -56
                         C-129 -68 -128 -74 -118 -74 Z" fill="#0d3a4b"/>
                <g fill="#9ff6ff" opacity="0.55">
                    <rect x="-104" y="-58" width="34" height="22" rx="4"/>
                    <rect x="-56" y="-58" width="34" height="22" rx="4"/>
                    <rect x="-8" y="-58" width="34" height="22" rx="4"/>
                </g>
                <rect x="-250" y="-22" width="500" height="8" fill="#00e5ff" opacity="0.2"/>
            </g>
            <g stroke="#9ff6ff" stroke-opacity="0.30" stroke-width="4" fill="none" stroke-linecap="round">
                <path d="M300 356 C420 342 500 348 596 360"/>
                <path d="M270 392 C420 374 540 382 660 398"/>
            </g>`,
        air: `
            <g fill="#9ff6ff" opacity="0.10">
                <ellipse cx="230" cy="150" rx="150" ry="34"/><ellipse cx="330" cy="128" rx="96" ry="26"/>
                <ellipse cx="980" cy="112" rx="128" ry="28"/><ellipse cx="700" cy="196" rx="110" ry="22"/>
            </g>
            <path d="M0 372 L150 300 L268 348 L392 268 L520 340 L640 292 L784 356 L910 300 L1040 350 L1200 296 V514 H0 Z"
                  fill="#062130" opacity="0.9"/>
            <path d="M0 430 L180 376 L340 424 L520 380 L700 436 L880 388 L1060 438 L1200 402 V514 H0 Z"
                  fill="#03131c"/>
            <g transform="translate(600 250)">
                <ellipse cx="0" cy="150" rx="190" ry="20" fill="#000" opacity="0.4" filter="url(#${id('soft')})"/>
                <path d="M-92 -6 C-92 -52 -54 -78 4 -78 C64 -78 104 -50 118 -10 L128 18
                         C132 30 126 40 112 40 H-84 C-102 40 -112 28 -112 12 Z" fill="#061c26"/>
                <path d="M-78 -14 C-74 -50 -44 -66 4 -66 C50 -66 82 -46 94 -16 Z" fill="#0d3a4b" opacity="0.92"/>
                <path d="M112 6 H268 C280 6 286 12 286 22 C286 32 280 38 268 38 H120 Z" fill="#061c26"/>
                <path d="M252 -34 H266 C274 -34 278 -28 278 -20 V22 H252 Z" fill="#0a2b38"/>
                <circle cx="266" cy="-6" r="22" fill="none" stroke="#0d3a4b" stroke-width="7"/>
                <g stroke="#9ff6ff" stroke-opacity="0.45" stroke-width="5" stroke-linecap="round">
                    <path d="M-300 -96 H300"/>
                </g>
                <ellipse cx="0" cy="-96" rx="300" ry="12" fill="#9ff6ff" opacity="0.07"/>
                <rect x="-6" y="-96" width="12" height="24" fill="#0a2b38"/>
                <g stroke="#061c26" stroke-width="8" stroke-linecap="round" fill="none">
                    <path d="M-86 40 V70 M74 40 V70"/><path d="M-120 74 H120"/>
                </g>
            </g>`
    };

    return `<svg viewBox="0 0 1200 514" preserveAspectRatio="xMidYMid slice"
                 xmlns="http://www.w3.org/2000/svg">${common}${scenes[kind]}</svg>`;
}

function kindIcon(kind) {
    const paths = {
        ground: '<path d="M3 13l1.6-4.2A2 2 0 0 1 6.5 7.5h11a2 2 0 0 1 1.9 1.3L21 13v5h-2.5v-1.5h-13V18H3z" fill="currentColor"/><circle cx="7" cy="15" r="1.3" fill="#04202a"/><circle cx="17" cy="15" r="1.3" fill="#04202a"/>',
        boat: '<path d="M3 16h18l-2.2 3.4A3 3 0 0 1 16.3 21H7.7a3 3 0 0 1-2.5-1.4z" fill="currentColor"/><path d="M6 14V9h7l4 5z" fill="currentColor"/><path d="M11 8V3l4 5z" fill="currentColor"/>',
        air: '<rect x="2" y="6" width="20" height="1.6" rx="0.8" fill="currentColor"/><path d="M7 10h6.5l2.5 3h5v2h-6l-2-2H8a1 1 0 0 1-1-1z" fill="currentColor"/><path d="M11 7.6v2.4M6 18h9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>'
    };
    return `<svg viewBox="0 0 24 24" style="color: var(--accent)">${paths[kind]}</svg>`;
}

function paintHero(sceneId, kind) {
    el(sceneId).innerHTML = heroScene(kind, sceneId);
}

/* ============================================================ dialog shell */

window.addEventListener('message', ({ data }) => {
    if (!data || !data.type) return;
    switch (data.type) {
        case 'showMyLicenses': return showMyLicenses(data);
        case 'showTestConfirmation': return showTestConfirmation(data);
        case 'testResult': return showTestResult(data);
        case 'openAdminMenu': return openAdminMenu(data);
        case 'openRouteManager': return openRouteManager(data);
        case 'routesUpdated': return updateRoutes(data);
        case 'adminSaved': return closeDialog('licenseEditor');
        case 'routeSaved': return closeDialog('adminMenu');
        case 'hideLoading': return hideLoadingScreen();
        case 'builderHint': {
            const hint = el('builderHint');
            hint.textContent = data.message || '';
            hint.classList.toggle('hidden', !data.message);
            return;
        }
    }
});

function closeDialog(id) {
    el(id)?.classList.add('hidden');
    if (App.currentDialog === id) App.currentDialog = null;
}

function show(id) {
    document.querySelectorAll('.dialog').forEach(node => node.classList.add('hidden'));
    el(id).classList.remove('hidden');
    App.currentDialog = id;
}

function showLoadingScreen() {
    show('loadingScreen');
    // A dropped response must never leave the player staring at a spinner.
    clearTimeout(App.loadingTimer);
    App.loadingTimer = setTimeout(hideLoadingScreen, 15000);
}

function hideLoadingScreen() {
    clearTimeout(App.loadingTimer);
    el('loadingScreen').classList.add('hidden');
    if (App.currentDialog === 'loadingScreen') App.currentDialog = null;
}

function closeMenu() {
    if (App.currentDialog) closeDialog(App.currentDialog);
    post('closeMenu');
}

/* ============================================================ player UI */

function showTestConfirmation(data) {
    const kind = artKind(data.category, data.license_type || data.licenseType);
    App.selectedLicense = data.license_type || data.licenseType;

    paintHero('testHeroScene', kind);
    el('testEyebrow').textContent = `Department of Transport · ${KIND_LABEL[kind]}`;
    el('testTitle').textContent = `${data.label || App.selectedLicense} Test`;

    const specs = [
        { label: 'Test Fee', value: `$${formatNumber(data.price)}` },
        { label: 'Time Limit', value: `${data.durationMinutes || 20} minutes` },
        { label: 'Examination Vehicle', value: data.vehicleModel || '—', plain: true },
        { label: 'License Validity', value: `${data.validDays || 30} days`, plain: true }
    ];
    if (Number(data.maxMistakes) > 0) {
        specs.push({ label: 'Mistakes Allowed', value: `${data.maxMistakes} before failure`, plain: true });
    }
    specs.push({ label: 'Requirements', value: 'Complete every checkpoint in order', plain: true, wide: true });

    el('testSpecs').innerHTML = specs.map(spec => `
        <div class="spec${spec.wide ? ' spec-wide' : ''}">
            <span class="spec-label">${escapeHtml(spec.label)}</span>
            <span class="spec-value${spec.plain ? ' plain' : ''}">${escapeHtml(spec.value)}</span>
        </div>`).join('');

    el('startTestBtn').onclick = () => startTest(App.selectedLicense);
    show('testConfirmation');
}

function startTest(licenseType) {
    showLoadingScreen();
    post('startTest', { licenseType });
}

function cancelTest() {
    closeMenu();
}

function showMyLicenses(data) {
    const list = el('licensesList');
    list.innerHTML = '';

    (data.licenses || []).forEach(license => {
        const status = license.isExpired ? 'expired' : String(license.status || '');
        const kind = artKind(license.license_type);
        const days = Number(license.remainingDays || 0);
        const pct = Math.max(0, Math.min(100, (days / Math.max(1, Number(license.valid_days || 30))) * 100));
        const meterClass = days === 0 ? 'empty' : days <= 5 ? 'low' : '';

        const card = document.createElement('div');
        card.className = 'card';
        card.innerHTML = `
            <div class="card-top">
                <div class="card-icon">${kindIcon(kind)}</div>
                <div class="card-body">
                    <div class="card-title">${escapeHtml(license.label)}
                        <span class="pill ${escapeHtml(status)}">${escapeHtml(status.toUpperCase())}</span>
                    </div>
                    <div class="card-meta">Expires ${escapeHtml(license.expiresAtDate || 'N/A')}
                        · ${days} day${days === 1 ? '' : 's'} remaining</div>
                </div>
            </div>
            <div class="meter"><div class="meter-fill ${meterClass}" style="width:${pct}%"></div></div>`;
        list.appendChild(card);
    });

    show('myLicensesDialog');
}

function showTestResult(data) {
    const kind = artKind(data.category, data.licenseType);
    const passed = Boolean(data.passed);

    paintHero('resultHeroScene', kind);
    el('resultEyebrow').textContent = `Examination Result · ${KIND_LABEL[kind]}`;
    el('resultVerdict').textContent = passed ? 'Test Passed' : 'Test Failed';

    const stamp = el('resultStamp');
    stamp.textContent = passed ? 'PASS' : 'FAIL';
    stamp.classList.toggle('fail', !passed);

    el('resultMessage').textContent = passed
        ? `You passed the ${data.licenseLabel || 'license'} examination.`
        : (data.failReason || 'Test failed');
    el('resultDetails').textContent = data.message
        || (passed ? `Valid for ${data.validDays} days.` : 'Please try again.');

    show('testResult');
    clearTimeout(App.resultTimer);
    App.resultTimer = setTimeout(closeResult, 10000);
}

// The result screen holds a cursor (with game input kept alive) so this button
// works; closing must hand focus back to the game.
function closeResult() {
    clearTimeout(App.resultTimer);
    closeDialog('testResult');
    post('closeResult');
}

/* ============================================================ admin UI */

function openAdminMenu(data) {
    App.adminLicenses = data.licenses || [];
    const list = el('adminLicensesList');
    list.innerHTML = '';

    App.adminLicenses.forEach(license => {
        const id = Number(license.id);
        const kind = artKind(license.vehicle_category, license.license_type);
        const routes = Number(license.active_route_count ?? license.route_count ?? 0);
        const total = Number(license.route_count ?? routes);
        const routePill = routes > 0
            ? `<span class="pill active">${routes} route${routes === 1 ? '' : 's'}</span>`
            : '<span class="pill expired">No route</span>';

        const card = document.createElement('div');
        card.className = 'card';
        card.innerHTML = `
            <div class="card-top">
                <div class="card-icon">${kindIcon(kind)}</div>
                <div class="card-body">
                    <div class="card-title">${escapeHtml(license.label)} ${routePill}
                        ${Number(license.enabled) ? '' : '<span class="pill">disabled</span>'}</div>
                    <div class="card-meta">${escapeHtml(license.vehicle_model || '—')}
                        · $${formatNumber(license.price)}
                        · ${Number(license.valid_days || 0)} days
                        · ${Number(license.checkpoint_count || 0)} checkpoints
                        ${total > routes ? `· ${total - routes} disabled` : ''}</div>
                </div>
            </div>
            <div class="card-actions">
                <button class="btn btn-primary btn-sm" data-action="routes" data-id="${id}">Manage Routes</button>
                <button class="btn btn-sm" data-action="record" data-id="${id}">Record Route</button>
                <button class="btn btn-sm" data-action="edit" data-id="${id}">Edit</button>
                <button class="btn btn-sm" data-action="npc" data-id="${id}">Move Instructor Here</button>
                <button class="btn btn-sm" data-action="delete" data-id="${id}">Delete</button>
            </div>`;
        list.appendChild(card);
    });

    show('adminMenu');
}

function backToAdminMenu() {
    openAdminMenu({ licenses: App.adminLicenses });
}

function openRouteManager(data) {
    App.routeContext = {
        licenseTypeId: Number(data.licenseTypeId),
        licenseLabel: data.licenseLabel,
        licenseType: data.licenseType
    };
    el('routeManagerTitle').textContent = `${data.licenseLabel || 'License'} — Routes`;
    el('recordRouteBtn').onclick = () => recordRoute(App.routeContext.licenseTypeId);
    renderRoutes(data.routes || []);
    show('routeManager');
}

function updateRoutes(data) {
    // Keep the cached list fresh so "Back" shows the new route counts.
    if (data.tests) App.adminLicenses = data.tests;
    if (!App.routeContext || Number(data.licenseTypeId) !== App.routeContext.licenseTypeId) return;
    renderRoutes(data.routes || []);
}

function renderRoutes(routes) {
    const list = el('routeList');
    list.innerHTML = '';

    routes.forEach((route, index) => {
        const id = Number(route.id);
        const enabled = Boolean(Number(route.enabled));
        const checkpoints = Number(route.checkpoint_count || 0);
        const usable = enabled && checkpoints >= 2;

        const card = document.createElement('div');
        card.className = 'card';
        card.innerHTML = `
            <div class="card-top">
                <div class="card-icon"><span style="font-weight:800;color:var(--accent)">${index + 1}</span></div>
                <div class="card-body">
                    <div class="card-title">${escapeHtml(route.label || `Route ${id}`)}
                        <span class="pill ${usable ? 'active' : enabled ? 'warn' : 'expired'}">
                            ${usable ? 'In rotation' : enabled ? 'Too short' : 'Disabled'}</span>
                    </div>
                    <div class="card-meta">${checkpoints} checkpoint${checkpoints === 1 ? '' : 's'} · route #${id}</div>
                </div>
            </div>
            <div class="card-actions">
                <button class="btn btn-sm" data-action="route-toggle" data-route-id="${id}"
                        data-enabled="${enabled ? '0' : '1'}">${enabled ? 'Disable' : 'Enable'}</button>
                <button class="btn btn-sm" data-action="route-rerecord" data-route-id="${id}"
                        data-id="${App.routeContext?.licenseTypeId ?? ''}">Re-record</button>
                <button class="btn btn-sm" data-action="route-delete" data-route-id="${id}">Delete</button>
            </div>`;
        list.appendChild(card);
    });
}

// One delegated handler: every list is rebuilt on each server response.
document.addEventListener('click', event => {
    const button = event.target.closest('[data-action]');
    if (!button) return;

    const id = Number(button.dataset.id);
    const routeId = Number(button.dataset.routeId);

    switch (button.dataset.action) {
        case 'routes': return post('adminListRoutes', { id });
        case 'record': return recordRoute(id);
        case 'edit': return editLicense(id);
        case 'npc': return setNpc(id);
        case 'delete': return armOrRun(button, 'Delete', () => post('adminDeleteType', { id }));
        case 'route-toggle': return post('adminToggleRoute', { routeId, enabled: button.dataset.enabled === '1' });
        case 'route-rerecord': return recordRoute(id || App.routeContext?.licenseTypeId, routeId);
        case 'route-delete': return armOrRun(button, 'Delete', () => post('adminDeleteRoute', { routeId }));
    }
});

// window.confirm is unreliable inside CEF, so destructive actions arm first.
function armOrRun(button, label, action) {
    if (button.dataset.armed === '1') return action();

    button.dataset.armed = '1';
    button.textContent = 'Confirm?';
    button.classList.add('danger');
    setTimeout(() => {
        delete button.dataset.armed;
        button.textContent = label;
        button.classList.remove('danger');
    }, 4000);
}

const findLicense = id => App.adminLicenses.find(entry => Number(entry.id) === Number(id));

function recordRoute(id, routeId) {
    closeDialog(App.currentDialog || 'adminMenu');
    post('adminBeginBuilder', { id, routeId });
}

function editLicense(id) {
    const license = findLicense(id);
    if (!license) return;

    App.editingId = Number(id);
    el('editorTitle').textContent = 'Edit License Test';

    const fields = {
        licenseName: license.label,
        licenseType: license.license_type,
        licensePrice: license.price,
        licenseValidity: license.valid_days,
        vehicleModel: license.vehicle_model,
        vehicleCategory: license.vehicle_category || 'ground',
        itemName: license.item_name,
        npcModel: license.npc_model,
        npcScenario: license.npc_scenario
    };
    Object.entries(fields).forEach(([key, val]) => { el(key).value = val ?? ''; });
    el('licenseEnabled').checked = Boolean(Number(license.enabled));

    show('licenseEditor');
}

function createNewLicense() {
    App.editingId = null;
    el('licenseForm').reset();
    el('editorTitle').textContent = 'Create License Test';
    el('licenseEnabled').checked = true;
    show('licenseEditor');
}

function saveLicense() {
    post('adminSaveType', {
        id: App.editingId,
        label: value('licenseName'),
        licenseType: value('licenseType'),
        price: Number(value('licensePrice')),
        validDays: Number(value('licenseValidity')),
        vehicleModel: value('vehicleModel'),
        vehicleCategory: value('vehicleCategory'),
        itemName: value('itemName'),
        npcModel: value('npcModel'),
        npcScenario: value('npcScenario'),
        enabled: el('licenseEnabled').checked
    });
}

function setNpc(id) {
    const license = findLicense(id);
    post('adminSetNpc', { id, npcModel: license?.npc_model, npcScenario: license?.npc_scenario });
}

document.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    if (App.currentDialog === 'testResult') return closeResult();
    if (App.currentDialog === 'routeManager' || App.currentDialog === 'licenseEditor') return backToAdminMenu();
    if (App.currentDialog) closeMenu();
});
