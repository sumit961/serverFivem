// cm-hub/web/app.js
// Client NUI interaction controller for CM Bento Hub
// Client NUI interaction controller for CM Bento Hub & Job Center
// Client NUI interaction controller for CM Bento Hub, Job Center & Tactical Statistics Dashboard

let currentData = null;
let currentConfig = null;
let selectedJobId = 'electrician';
let vehicleRegistryPending = null;
let vehicleRegistryBusy = false;

// Default registered civilian jobs (mirrored from Config.Jobs)
const defaultJobs = [
  {
    id: 'electrician',
    title: 'Electrician',
    category: 'Infrastructure & Power',
    salary: '$5,000 / Task',
    badge: 'HIGH VOLTAGE',
    shortDesc: 'Maintain city power grids, diagnose switchboards, and respond to blackout emergencies.',
    description: 'Report to the Palmer-Taylor Power Plant to troubleshoot high-voltage switchboards. As your skill increases, rent the official company service truck to repair citywide junction boxes and restore power during blackout emergencies for major corporate payouts.',
    locationName: 'Palmer-Taylor Power Plant',
    coords: { x: 718.72, y: 152.38, z: 80.74 },
    npcName: 'Frank Delgado (Chief Electrician)',
    image: 'images/jobs/electrician.jpg',
    levels: 'Level 1 - 3 (Switchboard -> Service Truck -> City Outages)',
    requirements: [
      'No prior license or experience required',
      'Government-inspected industrial job site',
      'Cash payroll paid directly upon task completion'
    ],
    perks: [
      'Company Service Truck Rental',
      'Instant Cash Pay per Repair',
      'Skill Progression Tiers'
    ]
  },
  {
    id: 'fishing',
    title: 'Commercial Fisher',
    category: 'Maritime & Aquaculture',
    salary: '$1,000 - $10,000+ / Haul',
    badge: 'OFFSHORE / COASTAL',
    shortDesc: 'Cast lines off piers or rent boats into deep ocean waters to harvest rare fish and sea life.',
    description: 'Visit the Vespucci Beach Marina tackle shop to equip specialized rods and bait. Catch common to legendary ocean species from the shore or rent speedboats and dinghies to venture into offshore channels for high-value trophy fish.',
    locationName: 'Vespucci Beach Pier & Marina',
    coords: { x: -1827.38, y: -1246.18, z: 13.02 },
    npcName: 'Vespucci Harbor Tackle Master',
    image: 'images/jobs/fishing.jpg',
    levels: 'Level 0 - 5 (Pier Angler -> Coastal -> Deep Ocean Hunter)',
    requirements: [
      'Fishing rod & bait (available at the tackle shop)',
      'Vespucci Beach dock access',
      'Civilian identification'
    ],
    perks: [
      'Dockside Boat Rentals (Seashark / Dinghy)',
      'Sell Catches on the Spot for Clean Cash',
      'Trophy Catch Multipliers (Common up to Legend)'
    ]
  }
];

function getJobs() {
  if (currentConfig && Array.isArray(currentConfig.Jobs) && currentConfig.Jobs.length > 0) {
    return currentConfig.Jobs;
  }
  return defaultJobs;
}

function post(endpoint, data = {}) {
  return fetch(`https://cm-hub/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  }).catch(() => {});
}

function postJson(endpoint, data = {}) {
  return fetch(`https://cm-hub/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  }).then((response) => response.json()).catch(() => null);
}

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function formatRegistryDate(value) {
  const timestamp = Number(value);
  if (!Number.isFinite(timestamp) || timestamp <= 0) return 'NOT SET';
  const date = new Date(timestamp * 1000);
  if (Number.isNaN(date.getTime())) return 'NOT SET';
  return date.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

function formatRegistryStatus(status) {
  return String(status || 'UNAVAILABLE').replace(/_/g, ' ').toUpperCase();
}

function registryStatusClass(status) {
  const normalized = String(status || '').toLowerCase();
  if (normalized === 'active') return 'registry-status-active';
  if (normalized === 'expired') return 'registry-status-expired';
  if (normalized === 'unregistered' || normalized === 'none') return 'registry-status-warning';
  if (normalized === 'revoked') return 'registry-status-danger';
  return 'registry-status-muted';
}

function registryReason(reason) {
  const reasons = {
    exempt: 'INELIGIBLE: this vehicle cannot use personal services.',
    registration_required: 'Registration is required before insurance can be purchased.',
    registration_revoked: 'Unavailable: registration has been revoked.',
    legacy_permanent: 'Already active: this registration has no expiry.',
    not_due: 'Already active: renewal is not available yet.',
    unavailable: 'Unavailable for this vehicle right now.',
    vehicle_busy: 'Unavailable while this vehicle is being sold.'
  };
  return reasons[reason] || (reason ? formatRegistryStatus(reason) : 'Unavailable for this vehicle right now.');
}

function serviceActionLabel(service, action) {
  if (service === 'registration') return action === 'renew' ? 'RENEW REGISTRATION' : 'REGISTER VEHICLE';
  return action === 'renew' ? 'RENEW INSURANCE' : 'PURCHASE INSURANCE';
}

function serviceCardMarkup(vehicle, service) {
  const quote = vehicle && vehicle[service];
  if (!quote || quote.available !== true || !quote.action) {
    return `<div class="registry-service-unavailable">${escapeHtml(registryReason(quote && quote.reason))}</div>`;
  }

  const price = Math.max(0, Math.floor(Number(quote.price) || 0));
  return `
    <button class="registry-service-btn heading" type="button"
      data-registry-service="${escapeHtml(service)}"
      data-registry-action="${escapeHtml(quote.action)}"
      data-registry-vehicle="${escapeHtml(vehicle.vehicleId)}"
      data-registry-price="${price}">
      <span>${escapeHtml(serviceActionLabel(service, quote.action))}</span>
      <strong>$${price.toLocaleString()}</strong>
    </button>`;
}

function registryErrorMessage(result) {
  if (result && result.message) return String(result.message);
  const messages = {
    no_character: 'Character data is not loaded. Please try again.',
    vehicle_services_unavailable: 'Vehicle registration services are unavailable right now.',
    not_owner: 'This vehicle is not owned by your current character.',
    vehicle_not_found: 'That vehicle could not be found.',
    exempt: 'This vehicle is not eligible for personal registration or insurance.',
    not_due: 'This service is already active and renewal is not available yet.',
    registration_required: 'Registration is required before insurance can be purchased.',
    price_changed: 'The price changed. Review the vehicle service and confirm again.',
    insufficient_funds: 'You do not have enough cash for this service.',
    payment_unavailable: 'Payment is unavailable right now.',
    apply_failed: 'The change could not be applied. You were not charged.',
    busy: 'This vehicle is already being processed. Please try again.',
    unavailable: 'This service is unavailable for the vehicle right now.'
  };
  return messages[result && result.error] || 'Vehicle service could not be completed.';
}

function toggleVehicleRegistry(show) {
  const modal = document.getElementById('vehicleRegistryModal');
  if (!modal) return;
  if (show) {
    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');
  } else {
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
    toggleVehicleRegistryConfirm(false);
  }
}

function toggleVehicleRegistryConfirm(show) {
  const modal = document.getElementById('vehicleRegistryConfirm');
  if (!modal) return;
  if (show) {
    modal.classList.remove('hidden');
    const cancel = document.getElementById('btnCancelVehicleService');
    if (cancel) cancel.focus();
  } else {
    modal.classList.add('hidden');
  }
}

function setRegistryNotice(message, kind = 'info') {
  const notice = document.getElementById('vehicleRegistryNotice');
  if (!notice) return;
  if (!message) {
    notice.textContent = '';
    notice.className = 'vehicle-registry-notice hidden';
    return;
  }
  notice.textContent = message;
  notice.className = `vehicle-registry-notice registry-notice-${kind}`;
}

function renderVehicleRegistry(result) {
  const list = document.getElementById('vehicleRegistryList');
  if (!list) return;
  setRegistryNotice('', 'info');

  if (!result || result.ok !== true) {
    list.innerHTML = `<div class="vehicle-registry-empty">${escapeHtml(registryErrorMessage(result))}</div>`;
    setRegistryNotice(registryErrorMessage(result), 'error');
    return;
  }

  const vehicles = Array.isArray(result.vehicles) ? result.vehicles : [];
  if (vehicles.length === 0) {
    list.innerHTML = '<div class="vehicle-registry-empty">No eligible vehicles are registered to this character.</div>';
    return;
  }

  list.innerHTML = vehicles.map((vehicle) => {
    const model = vehicle.label || vehicle.model || 'VEHICLE';
    const plate = vehicle.registrationNumber || 'UNREGISTERED';
    return `
      <article class="vehicle-registry-item">
        <div class="vehicle-registry-item-head">
          <div>
            <div class="vehicle-registry-item-kicker heading">${escapeHtml(plate)}</div>
            <h3>${escapeHtml(model)}</h3>
          </div>
          <span class="vehicle-registry-vehicle-tag heading">ELIGIBLE</span>
        </div>
        <div class="vehicle-registry-status-grid">
          <div class="vehicle-registry-status-block">
            <span class="vehicle-registry-label heading">REGISTRATION</span>
            <strong class="${registryStatusClass(vehicle.registrationStatus)}">${escapeHtml(formatRegistryStatus(vehicle.registrationStatus))}</strong>
            <small>EXPIRY: ${escapeHtml(formatRegistryDate(vehicle.registrationExpiresAt))}</small>
          </div>
          <div class="vehicle-registry-status-block">
            <span class="vehicle-registry-label heading">INSURANCE</span>
            <strong class="${registryStatusClass(vehicle.insuranceStatus)}">${escapeHtml(formatRegistryStatus(vehicle.insuranceStatus))}</strong>
            <small>EXPIRY: ${escapeHtml(formatRegistryDate(vehicle.insuranceExpiresAt))}</small>
          </div>
        </div>
        <div class="vehicle-registry-services">
          <div class="vehicle-registry-service-column">
            <span class="vehicle-registry-label heading">REGISTRATION SERVICE</span>
            ${serviceCardMarkup(vehicle, 'registration')}
          </div>
          <div class="vehicle-registry-service-column">
            <span class="vehicle-registry-label heading">INSURANCE SERVICE</span>
            ${serviceCardMarkup(vehicle, 'insurance')}
          </div>
        </div>
      </article>`;
  }).join('');

  list.querySelectorAll('[data-registry-service]').forEach((button) => {
    button.addEventListener('click', () => {
      openVehicleRegistryConfirm(button);
    });
  });
}

function renderVehicleRegistryLoading() {
  const list = document.getElementById('vehicleRegistryList');
  if (list) list.innerHTML = '<div class="vehicle-registry-loading">Loading vehicle records...</div>';
  setRegistryNotice('', 'info');
}

async function openVehicleRegistry() {
  toggleVehicleRegistry(true);
  renderVehicleRegistryLoading();
  const result = await postJson('get_vehicle_registry');
  renderVehicleRegistry(result);
}

function createVehicleRequestId() {
  if (window.crypto && typeof window.crypto.randomUUID === 'function') return window.crypto.randomUUID();
  return `hub-${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
}

function openVehicleRegistryConfirm(button) {
  const vehicleId = Number(button.getAttribute('data-registry-vehicle'));
  const service = button.getAttribute('data-registry-service');
  const action = button.getAttribute('data-registry-action');
  const price = Math.max(0, Math.floor(Number(button.getAttribute('data-registry-price')) || 0));
  const card = button.closest('.vehicle-registry-item');
  const model = card ? card.querySelector('h3') : null;
  if (!Number.isInteger(vehicleId) || vehicleId < 1 || !service) return;

  vehicleRegistryPending = { vehicleId, service, action, price };
  const title = document.getElementById('vehicleRegistryConfirmTitle');
  const message = document.getElementById('vehicleRegistryConfirmMessage');
  const confirm = document.getElementById('btnConfirmVehicleService');
  if (title) title.textContent = serviceActionLabel(service, action);
  if (message) message.textContent = `${serviceActionLabel(service, action)} for ${model ? model.textContent : 'this vehicle'} for $${price.toLocaleString()} cash?`;
  if (confirm) {
    confirm.disabled = false;
    confirm.textContent = 'CONFIRM';
  }
  toggleVehicleRegistryConfirm(true);
}

async function confirmVehicleRegistryService() {
  if (!vehicleRegistryPending || vehicleRegistryBusy) return;
  vehicleRegistryBusy = true;
  const confirm = document.getElementById('btnConfirmVehicleService');
  const cancel = document.getElementById('btnCancelVehicleService');
  if (confirm) {
    confirm.disabled = true;
    confirm.textContent = 'PROCESSING...';
  }
  if (cancel) cancel.disabled = true;

  const pending = vehicleRegistryPending;
  const result = await postJson('purchase_vehicle_service', {
    vehicleId: pending.vehicleId,
    service: pending.service,
    expectedPrice: pending.price,
    requestId: createVehicleRequestId()
  });

  vehicleRegistryBusy = false;
  vehicleRegistryPending = null;
  if (cancel) cancel.disabled = false;
  toggleVehicleRegistryConfirm(false);

  if (result && result.ok === true) {
    await openVehicleRegistry();
    setRegistryNotice(`${serviceActionLabel(pending.service, result.action)} completed. Charged $${Number(result.charged || 0).toLocaleString()}. Expires ${formatRegistryDate(result.expiresAt)}.`, 'success');
    return;
  }

  setRegistryNotice(registryErrorMessage(result), 'error');
  const refreshed = await postJson('get_vehicle_registry');
  renderVehicleRegistry(refreshed);
}

/* --- Live Diagnostics Counter (FPS) --- */
let lastFpsCheck = performance.now();
let frameCount = 0;
function runFpsLoop() {
  const now = performance.now();
  frameCount++;
  if (now - lastFpsCheck >= 1000) {
    const fps = Math.round((frameCount * 1000) / (now - lastFpsCheck));
    const fpsEl = document.getElementById('statSysFps');
    if (fpsEl) fpsEl.textContent = `${fps}`;
    frameCount = 0;
    lastFpsCheck = now;
  }
  requestAnimationFrame(runFpsLoop);
}
requestAnimationFrame(runFpsLoop);

/* --- Modals Management --- */
function toggleStats(show) {
  const modal = document.getElementById('statsModal');
  if (!modal) return;
  if (show === undefined) {
    modal.classList.toggle('hidden');
  } else if (show) {
    modal.classList.remove('hidden');
  } else {
    modal.classList.add('hidden');
    toggleSkillsModal(false);
  }
}

function toggleSkillsModal(show) {
  const modal = document.getElementById('skillsModal');
  if (!modal) return;
  if (show === undefined) {
    modal.classList.toggle('hidden');
  } else if (show) {
    modal.classList.remove('hidden');
  } else {
    modal.classList.add('hidden');
  }
}

function toggleJobModal(show) {
  const modal = document.getElementById('jobModal');
  if (!modal) return;
  if (show === undefined) {
    modal.classList.toggle('hidden');
  } else if (show) {
    modal.classList.remove('hidden');
    renderJobsList();
    selectJob(selectedJobId);
  } else {
    modal.classList.add('hidden');
  }
}

/* --- Job Center Rendering --- */
function renderJobsList() {
  const listEl = document.getElementById('jobCardsList');
  if (!listEl) return;

  const jobs = getJobs();
  listEl.innerHTML = '';

  jobs.forEach((job) => {
    const card = document.createElement('div');
    card.className = `job-card-item ${job.id === selectedJobId ? 'active' : ''}`;
    card.setAttribute('data-job-id', job.id);

    const imgPath = job.image || 'images/jobs/electrician.jpg';

    card.innerHTML = `
      <img class="job-thumb" src="${imgPath}" alt="${job.title}" />
      <div class="job-card-text">
        <div class="job-card-title heading">${job.title}</div>
        <div class="job-card-cat heading">${job.category || 'Civilian'}</div>
        <div class="job-card-pay">${job.salary || 'Competitive Pay'}</div>
      </div>
    `;

    card.addEventListener('click', () => {
      selectJob(job.id);
    });

    listEl.appendChild(card);
  });
}

function selectJob(jobId) {
  const jobs = getJobs();
  const job = jobs.find(j => j.id === jobId) || jobs[0];
  if (!job) return;

  selectedJobId = job.id;

  // Highlight selected card in list
  document.querySelectorAll('.job-card-item').forEach((el) => {
    if (el.getAttribute('data-job-id') === job.id) {
      el.classList.add('active');
    } else {
      el.classList.remove('active');
    }
  });

  // Update Detail Panel
  const imgEl = document.getElementById('jobDetailImg');
  const catEl = document.getElementById('jobDetailCategory');
  const titleEl = document.getElementById('jobDetailTitle');
  const salaryEl = document.getElementById('jobDetailSalary');
  const locEl = document.getElementById('jobDetailLocation');
  const contactEl = document.getElementById('jobDetailContact');
  const levelsEl = document.getElementById('jobDetailLevels');
  const descEl = document.getElementById('jobDetailDesc');
  const reqEl = document.getElementById('jobDetailRequirements');
  const perksEl = document.getElementById('jobDetailPerks');

  if (imgEl) imgEl.src = job.image || 'images/jobs/electrician.jpg';
  if (catEl) catEl.textContent = job.category || 'Civilian Employment';
  if (titleEl) titleEl.textContent = job.title;
  if (salaryEl) salaryEl.textContent = job.salary || 'Commission Paid';
  if (locEl) locEl.textContent = job.locationName || 'City Worksite';
  if (contactEl) contactEl.textContent = job.npcName || 'Job Supervisor';
  if (levelsEl) levelsEl.textContent = job.levels || 'Standard Progression';
  if (descEl) descEl.textContent = job.description || job.shortDesc || 'Work and earn income in Los Santos.';

  if (reqEl) {
    reqEl.innerHTML = '';
    const reqs = Array.isArray(job.requirements) ? job.requirements : ['Standard civilian registration'];
    reqs.forEach((r) => {
      const li = document.createElement('li');
      li.textContent = r;
      reqEl.appendChild(li);
    });
  }

  if (perksEl) {
    perksEl.innerHTML = '';
    const perks = Array.isArray(job.perks) ? job.perks : ['Immediate cash compensation'];
    perks.forEach((p) => {
      const li = document.createElement('li');
      li.textContent = p;
      perksEl.appendChild(li);
    });
  }
}

/* --- Profile Data Binding --- */
function updateProfile(data) {
  currentData = data || {};
  

  // 1. Bento Dashboard main cards
  const nameEl = document.getElementById('statsPlayerName');
  const idEl = document.getElementById('statsPlayerId');
  const cashEl = document.getElementById('statsCash');
  const bankEl = document.getElementById('statsBank');
  const famEl = document.getElementById('statsFamily');
  const orgEl = document.getElementById('statsOrg');

  if (nameEl) nameEl.textContent = currentData.fullName || 'Citizen';
  if (idEl) idEl.textContent = `#${currentData.charId || '----'}`;
  if (cashEl) cashEl.textContent = `$${Number(currentData.cash || 0).toLocaleString()}`;
  if (bankEl) bankEl.textContent = `$${Number(currentData.bank || 0).toLocaleString()}`;
  

  if (famEl) {
    let famText = currentData.family || 'None';
    if (currentData.familyRank && famText !== 'None') {
      famText += ` (${currentData.familyRank})`;
    }
    famEl.textContent = famText;
  }
  

  if (orgEl) orgEl.textContent = currentData.organization || 'Civilian';

  // 2. Full Tactical Statistics Dashboard Header
  const statAccId = document.getElementById('statAccountId');
  if (statAccId) statAccId.textContent = `#${currentData.charId || '----'}`;

  const statGender = document.getElementById('statGenderIcon');
  if (statGender) {
    const isFemale = String(currentData.gender || '').toLowerCase() === 'female';
    statGender.textContent = isFemale ? '♀' : '♂';
    statGender.className = `stats-gender-sym ${isFemale ? 'female' : 'male'}`;
  }

  const statLvlBadge = document.getElementById('statLevelBadge');
  if (statLvlBadge) statLvlBadge.textContent = `LVL ${currentData.level || 1}`;

  const curXp = currentData.currentXp !== undefined ? currentData.currentXp : 0;
  const maxXp = currentData.maxXp || 100;
  const xpPct = Math.min(100, Math.max(0, (curXp / maxXp) * 100));

  const statXpFill = document.getElementById('statXpFill');
  if (statXpFill) statXpFill.style.width = `${xpPct}%`;

  const statXpText = document.getElementById('statXpText');
  if (statXpText) statXpText.textContent = `${curXp} / ${maxXp}`;

  const statVip = document.getElementById('statVipStatus');
  if (statVip) {
    statVip.textContent = currentData.vip ? 'VIP ACTIVE' : 'VIP OFF';
  }

  // 3. Column 1: Vitals & Legal Records Strip
  const statRecord = document.getElementById('statRecord');
  if (statRecord) {
    if (currentData.criminalRecord) {
      statRecord.textContent = 'CRIMINAL RECORD';
      statRecord.className = 'vital-val heading val-record-bad';
    } else {
      statRecord.textContent = 'CLEAN CITIZEN';
      statRecord.className = 'vital-val heading val-record-good';
    }
  }

  const statFines = document.getElementById('statFines');
  if (statFines) {
    statFines.textContent = `$${Number(currentData.fines || 0).toLocaleString()}`;
  }

  const statDiseases = document.getElementById('statDiseases');
  if (statDiseases) statDiseases.textContent = currentData.diseases || 'N/A';

  const statImmunity = document.getElementById('statImmunity');
  if (statImmunity) statImmunity.textContent = currentData.immunity || '100%';

  const statPhone = document.getElementById('statPhone');
  if (statPhone) statPhone.textContent = currentData.phone || 'NOT AVAILABLE';

  const statOnline = document.getElementById('statOnline');
  if (statOnline) statOnline.textContent = currentData.onlineTime || '0 H. 2 M.';

  const statFamName = document.getElementById('statFamilyName');
  if (statFamName) {
    statFamName.textContent = (currentData.family && currentData.family !== 'None') ? currentData.family.toUpperCase() : 'NO FAMILY';
  }

  const statFamRank = document.getElementById('statFamilyRank');
  if (statFamRank) {
    statFamRank.textContent = (currentData.familyRank && currentData.family !== 'None') ? currentData.familyRank.toUpperCase() : 'NONE';
  }

  const statSpouse = document.getElementById('statSpouse');
  if (statSpouse) statSpouse.textContent = currentData.spouse || 'NOT AVAILABLE';

  // 4. Column 2: Center Feature (Business, Org, Collectibles)
  const statBiz = document.getElementById('statBusiness');
  if (statBiz) statBiz.textContent = currentData.business || 'NO BUSINESS';

  const statOrgCenter = document.getElementById('statOrganization');
  if (statOrgCenter) statOrgCenter.textContent = (currentData.organization || 'UNEMPLOYED CITIZEN').toUpperCase();

  const statFig = document.getElementById('statFigurines');
  if (statFig) statFig.textContent = `${currentData.figurines !== undefined ? currentData.figurines : 2} FIGURINES`;

  // 5. Column 3: Licenses Checklist
  const licMap = {
    licDriver: currentData.licenses && currentData.licenses.driver,
    licWater: currentData.licenses && currentData.licenses.water,
    licAir: currentData.licenses && currentData.licenses.air,
    licWeapon: currentData.licenses && currentData.licenses.weapon,
    licMilitary: currentData.licenses && currentData.licenses.military,
    licLawyer: currentData.licenses && currentData.licenses.lawyer,
    licInsurance: currentData.licenses && currentData.licenses.insurance,
  };

  for (const [id, active] of Object.entries(licMap)) {
    const licCard = document.getElementById(id);
    if (licCard) {
      const markEl = licCard.querySelector('.lic-mark');
      if (markEl) {
        if (active) {
          markEl.textContent = '✓';
          markEl.className = 'lic-mark lic-on';
        } else {
          markEl.textContent = '✕';
          markEl.className = 'lic-mark lic-off';
        }
      }
    }
  }

  // 6. Column 4: Warnings Counter, Autopark & Houses
  const statWarn = document.getElementById('statWarningsCount');
  if (statWarn) statWarn.textContent = String(currentData.warnings || 0);

  // Autopark List
  const autoList = document.getElementById('statsAutoparkList');
  if (autoList) {
    autoList.innerHTML = '';
    const vehicles = Array.isArray(currentData.vehicles) ? currentData.vehicles : [];
    const totalSlots = Math.max(5, vehicles.length);
    for (let i = 0; i < totalSlots; i++) {
      const row = document.createElement('div');
      row.className = 'prop-row';
      const v = vehicles[i];
      if (v) {
        row.innerHTML = `<span class="prop-num">${i + 1}</span><span class="prop-name">${(v.model || v.plate || 'VEHICLE').toUpperCase()}</span>`;
      } else {
        row.innerHTML = `<span class="prop-num">${i + 1}</span><span class="prop-name empty-slot">SLOT EMPTY</span>`;
      }
      autoList.appendChild(row);
    }
  }

  // Houses List
  const houseList = document.getElementById('statsHousesList');
  if (houseList) {
    houseList.innerHTML = '';
    const houses = Array.isArray(currentData.houses) ? currentData.houses : [];
    const totalHouseSlots = 3;
    for (let i = 0; i < totalHouseSlots; i++) {
      const row = document.createElement('div');
      row.className = 'prop-row';
      const h = houses[i];
      if (h) {
        row.innerHTML = `
          <span class="prop-num">${i + 1}</span>
          <span class="prop-name">${(h.label || `HOUSE #${h.id}`).toUpperCase()}</span>
          <svg class="prop-pin" data-coords='${JSON.stringify(h.coords || null)}' data-label="${h.label || `House #${h.id}`}" viewBox="0 0 24 24"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
        `;
      } else {
        row.innerHTML = `
          <span class="prop-num">${i + 1}</span>
          <span class="prop-name empty-slot">HOUSE IS MISSING</span>
          <svg class="prop-pin pin-disabled" viewBox="0 0 24 24"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
        `;
      }
      houseList.appendChild(row);
    }

    // Family house row
    const famRow = document.createElement('div');
    famRow.className = 'prop-row family-row';
    if (currentData.familyHouse) {
      const fh = currentData.familyHouse;
      famRow.innerHTML = `
        <span class="prop-num">-</span>
        <span class="prop-name">${(fh.label || 'FAMILY HOUSE').toUpperCase()}<br><span class="prop-sub">PAID FOR: ${fh.paid || '14 / 14'}</span></span>
        <svg class="prop-pin" data-coords='${JSON.stringify(fh.coords || null)}' data-label="${fh.label || 'Family House'}" viewBox="0 0 24 24"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
      `;
    } else {
      famRow.innerHTML = `
        <span class="prop-num">-</span>
        <span class="prop-name empty-slot">FAMILY HOUSE NOT LINKED<br><span class="prop-sub">PAID FOR: 0 / 14</span></span>
        <svg class="prop-pin pin-disabled" viewBox="0 0 24 24"><path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/></svg>
      `;
    }
    houseList.appendChild(famRow);

    // Attach GPS pin click handlers
    houseList.querySelectorAll('.prop-pin:not(.pin-disabled)').forEach((pin) => {
      pin.addEventListener('click', (e) => {
        e.stopPropagation();
        const coordsJson = pin.getAttribute('data-coords');
        const label = pin.getAttribute('data-label');
        let coords = null;
        try {
          coords = JSON.parse(coordsJson);
        } catch (err) {}
        post('set_waypoint', { coords: coords, label: label });
      });
    });
  }
}

/* --- Message Listener --- */
window.addEventListener('message', (event) => {
  const item = event.data;
  if (!item) return;

  if (item.action === 'open') {
    currentConfig = item.config || null;
    updateProfile(item.data);
    toggleStats(false);
    toggleJobModal(false);
    toggleSkillsModal(false);
    toggleVehicleRegistry(false);
    document.body.classList.add('active');
  } else if (item.action === 'close') {
    document.body.classList.remove('active');
    toggleStats(false);
    toggleJobModal(false);
    toggleSkillsModal(false);
    toggleVehicleRegistry(false);
  }
});

// Close when ESC or M is pressed
/* --- Keyboard Shortcuts --- */
window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    const vehicleConfirm = document.getElementById('vehicleRegistryConfirm');
    if (vehicleConfirm && !vehicleConfirm.classList.contains('hidden')) {
      toggleVehicleRegistryConfirm(false);
      vehicleRegistryPending = null;
      return;
    }

    const vehicleRegistry = document.getElementById('vehicleRegistryModal');
    if (vehicleRegistry && !vehicleRegistry.classList.contains('hidden')) {
      toggleVehicleRegistry(false);
      return;
    }

    // 1. Close skills modal if open
    const skillsModal = document.getElementById('skillsModal');
    if (skillsModal && !skillsModal.classList.contains('hidden')) {
      toggleSkillsModal(false);
      return;
    }

    // 2. Close stats modal if open
    const statsModal = document.getElementById('statsModal');
    if (statsModal && !statsModal.classList.contains('hidden')) {
      toggleStats(false);
      return;
    }

    // 3. Close job modal if open
    const jobModal = document.getElementById('jobModal');
    if (jobModal && !jobModal.classList.contains('hidden')) {
      toggleJobModal(false);
      return;
    }

    // 4. Otherwise close hub
    post('close');
  } else if (event.code === 'KeyM') {
    post('close');
  }
});

/* --- Button Click Listeners --- */
const closeButton = document.getElementById('closeButton');
if (closeButton) {
  closeButton.addEventListener('click', () => {
    post('close');
  });
}

const closeStatsEscBtn = document.getElementById('btnCloseStatsEsc');
if (closeStatsEscBtn) {
  closeStatsEscBtn.addEventListener('click', () => {
    toggleStats(false);
  });
}

const closeStatsBtn = document.getElementById('btnCloseStats');
if (closeStatsBtn) {
  closeStatsBtn.addEventListener('click', () => {
    toggleStats(false);
  });
}

const openVehicleRegistryBtn = document.getElementById('btnOpenVehicleRegistry');
if (openVehicleRegistryBtn) {
  openVehicleRegistryBtn.addEventListener('click', () => {
    openVehicleRegistry();
  });
}

const closeVehicleRegistryBtn = document.getElementById('btnCloseVehicleRegistry');
if (closeVehicleRegistryBtn) {
  closeVehicleRegistryBtn.addEventListener('click', () => {
    toggleVehicleRegistry(false);
  });
}

const confirmVehicleServiceBtn = document.getElementById('btnConfirmVehicleService');
if (confirmVehicleServiceBtn) {
  confirmVehicleServiceBtn.addEventListener('click', () => {
    confirmVehicleRegistryService();
  });
}

const cancelVehicleServiceBtn = document.getElementById('btnCancelVehicleService');
if (cancelVehicleServiceBtn) {
  cancelVehicleServiceBtn.addEventListener('click', () => {
    if (vehicleRegistryBusy) return;
    vehicleRegistryPending = null;
    toggleVehicleRegistryConfirm(false);
  });
}

const vehicleRegistryModal = document.getElementById('vehicleRegistryModal');
if (vehicleRegistryModal) {
  vehicleRegistryModal.addEventListener('click', (event) => {
    if (event.target === vehicleRegistryModal && !vehicleRegistryBusy) {
      vehicleRegistryPending = null;
      toggleVehicleRegistryConfirm(false);
    }
  });
}

// Bind all interactive cards and action pills
const showSkillsBtn = document.getElementById('btnShowSkills');
if (showSkillsBtn) {
  showSkillsBtn.addEventListener('click', () => {
    toggleSkillsModal(true);
  });
}

const closeSkillsBtn = document.getElementById('btnCloseSkills');
if (closeSkillsBtn) {
  closeSkillsBtn.addEventListener('click', () => {
    toggleSkillsModal(false);
  });
}

const backFromJobsBtn = document.getElementById('btnBackFromJobs');
if (backFromJobsBtn) {
  backFromJobsBtn.addEventListener('click', () => {
    toggleJobModal(false);
  });
}

const employBtn = document.getElementById('btnGetEmployed');
if (employBtn) {
  employBtn.addEventListener('click', () => {
    post('get_employed', { jobId: selectedJobId });
  });
}

/* --- Bind All Bento Cards and Bottom Pills --- */
document.querySelectorAll('[data-action]').forEach((element) => {
  element.addEventListener('click', () => {
    const action = element.getAttribute('data-action');
    const msg = element.getAttribute('data-msg');

    if (action === 'statistics') {
      toggleStats();
      toggleStats(true);
      return;
    }

    if (action === 'jobcenter' || action === 'job') {
      toggleJobModal(true);
      return;
    }

    post('action', { action: action, message: msg });
  });
});
