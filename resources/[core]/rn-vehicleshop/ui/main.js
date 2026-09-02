let data;
let vehiclesCategory = false;
let vehicleDisplay = false;
let onBuyPage = false;
let inspect = false;
let hideDisplay = false;
let details = {};
let adminSourceVehicles = [];
let adminCatalog = [];
let pendingSave = null; // set when a save is blocked waiting on an image capture
let cropPreviewState = null;
let cropDragState = null;
let cropHadAdminPanel = false;
let testTimerInterval = null;
let buyProcessing = false;
let testDriveProcessing = false;
let currentCategoryTitle = null;
let currentVehicleButtons = [];
let adminRenderedVehicles = [];
let adminPreviewedModel = '';
let adminDiscoveryInfo = {};
let adminSelectedModel = null;
let visualCatalog = {}; // cm-tuning's paint/livery/wheel/tyre/neon option catalog
let legalOrganizations = []; // cm-law's org list ({id,label}[]), for the admin-status-mode dropdown's legal:<id> options
let gangOrganizations = [];
let adminEmsMods = {};  // currently edited EMS vehicle's mods (mirrors client.lua currentAdminMods for display only)
let adminIntrospect = { liveries: 0, slots: {} }; // live per-vehicle option counts from client.lua introspectAdminVehicle
let adminMode = 'manage';
let favorites = loadJsonStore('rnVehicleShopFavorites', []);
let compareList = loadJsonStore('rnVehicleShopCompare', []);

function money(n){ return Number(n || 0).toLocaleString() + '$'; }
function safe(v){ return String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c])); }
function post(name, payload){ return $.post(`https://${GetParentResourceName()}/${name}`, JSON.stringify(payload || {})); }
function loadJsonStore(key, fallback){
  try {
    const parsed = JSON.parse(localStorage.getItem(key) || 'null');
    return Array.isArray(parsed) ? parsed : fallback;
  } catch(e){ return fallback; }
}
function saveJsonStore(key, value){
  try { localStorage.setItem(key, JSON.stringify(value || [])); } catch(e) {}
}
function modelKey(model){ return String(model || '').toLowerCase().trim(); }
function isFavorite(model){ return favorites.includes(modelKey(model)); }
function setFavorite(model, active){
  const m = modelKey(model); if(!m) return;
  favorites = favorites.filter(x => x !== m);
  if(active) favorites.unshift(m);
  favorites = favorites.slice(0, 100);
  saveJsonStore('rnVehicleShopFavorites', favorites);
}
function selectedVehicleSnapshot(){
  if(!details || !details.model) return null;
  return {
    model: details.model,
    name: details.vehicle || details.name || details.model,
    price: Number(details.numberprice || 0),
    buyable: details.buyable === true,
    owned: details.owned === true,
    category: details.category || currentCategoryTitle || 'Vehicle',
    trunkLevel: clampTrunkLevel(details.trunkLevel),
    speed: $('.num-speed').text() || '0',
    acceleration: $('.num-acceleration').text() || '0',
    braking: $('.num-braking').text() || '0',
    traction: $('.num-traction').text() || '0',
    testDriveEnabled: details.testDriveEnabled !== false,
  };
}
function updateFavoriteButton(){
  const active = details && isFavorite(details.model);
  $('#favorite-btn').toggleClass('active', !!active).html((active ? '<i class="fas fa-star"></i> Favorited' : '<i class="far fa-star"></i> Favorite'));
}
function updateCompareButton(){
  const m = modelKey(details && details.model);
  const active = m && compareList.some(v => modelKey(v.model) === m);
  $('#compare-btn').toggleClass('active', !!active).html((active ? '<i class="fas fa-balance-scale"></i> In Compare' : '<i class="fas fa-balance-scale"></i> Compare'));
}
function updateQuickButtons(){ updateFavoriteButton(); updateCompareButton(); }

function clampTrunkLevel(level){
  level = Math.floor(Number(level));
  if(Number.isNaN(level)) level = 1;
  return Math.max(0, Math.min(6, level));
}
function trunkCells(level){
  level = clampTrunkLevel(level);
  return level <= 0 ? 0 : Math.min(30, level * 6);
}
function trunkLabel(level){
  const cells = trunkCells(level);
  return cells <= 0 ? 'No trunk' : (cells + ' Cells');
}

function updateCinematicMeta(){
  const cat = String((details && details.category) || currentCategoryTitle || 'LOW');
  const model = modelKey(details && details.model);
  const idx = Math.max(0, currentVehicleButtons.findIndex(v => modelKey(v.model) === model));
  const total = currentVehicleButtons.length || 0;
  $('#cinema-counter').text(total ? ((idx >= 0 ? idx + 1 : 1) + ' / ' + total) : '0 / 0');
  $('#dock-count').text(total ? (total + ' vehicles') : '');
  $('#cinema-list-title').text(cat.toUpperCase());
  const trunkLevel = clampTrunkLevel(details && details.trunkLevel);
  $('#cinema-trunk-value').text(trunkLabel(trunkLevel).toUpperCase());
  const isHeavy = /truck|suv|off road|van/i.test(cat);
  const isFast = /super|sports/i.test(cat);
  $('#cinema-tank-value').text(isHeavy ? '85 LITERS' : isFast ? '70 LITERS' : '60 LITERS');
  $('#cinema-consumption-value').text(isFast ? 'MEDIUM' : isHeavy ? 'HIGH' : 'LOW');
}
function addToCompare(snapshot){
  if(!snapshot || !snapshot.model) return;
  const m = modelKey(snapshot.model);
  compareList = compareList.filter(v => modelKey(v.model) !== m);
  compareList.unshift(snapshot);
  compareList = compareList.slice(0, 3);
  saveJsonStore('rnVehicleShopCompare', compareList);
  updateCompareButton();
  renderComparePanel();
}
function renderComparePanel(){
  const list = $('#compare-list').html('');
  if(!compareList.length){
    list.html('<div class="compare-empty">No vehicles added yet. Select a vehicle and press Compare.</div>');
    return;
  }
  for(const v of compareList){
    list.append(`
      <div class="compare-card" data-model="${safe(v.model)}">
        <div class="compare-title"><b>${safe(v.name)}</b><span>${safe(v.category || 'Vehicle')}</span></div>
        <div class="compare-price">${v.buyable ? money(v.price) : 'Event / Task only'}${v.owned ? ' • Owned' : ''}</div>
        <div class="compare-grid">
          <span>Speed</span><b>${safe(v.speed)}</b>
          <span>Acceleration</span><b>${safe(v.acceleration)}</b>
          <span>Braking</span><b>${safe(v.braking)}</b>
          <span>Traction</span><b>${safe(v.traction)}</b>
          <span>Trunk</span><b>${safe(trunkLabel(v.trunkLevel))}</b>
        </div>
        <button class="compare-remove" data-model="${safe(v.model)}">Remove</button>
      </div>`);
  }
}
function ensureVisibleVehicleSelection(){
  const selected = $('#vehicle-warp .category.selected, #vehicle-warp .category5.selected').first();
  if(selected.length && selected.is(':visible')) return;
  const first = $('#vehicle-warp .category:visible, #vehicle-warp .category5:visible').first();
  if(first.length) first.trigger('click');
}

function applyStoreFilters(){
  const q = String($('#store-search').val() || '').toLowerCase();
  const filter = String($('#store-price-filter').val() || 'all');
  $('.category, .category5').each(function(){
    const el = $(this);
    const hay = String(el.data('search') || '').toLowerCase();
    const buyable = String(el.data('buyable')) === 'true';
    const owned = String(el.data('owned')) === 'true';
    const fav = isFavorite(el.data('model'));
    let show = !q || hay.includes(q);
    if(filter === 'buyable') show = show && buyable;
    else if(filter === 'event') show = show && !buyable;
    else if(filter === 'owned') show = show && owned;
    else if(filter === 'fav') show = show && fav;
    el.toggle(show);
  });
  setTimeout(ensureVisibleVehicleSelection, 25);
}

function requestPreviewSpawn(model){
  if(!model) return;
  vehicleDisplay = true;
  inspect = true;
  // Single spawn request. spawnPreviewVehicle() on the Lua side already deletes
  // the previous preview car first; posting selectVehicle too respawned the same
  // model twice (visible flicker + loadVeh busy race).
  setTimeout(() => { try { post('spawnVehicle', { model }); } catch(e) {} }, 30);
}
function adminVisibleModels(){ return adminRenderedVehicles.map(v => String(v.model).toLowerCase()); }
function selectAdminModel(model, preview = true){
  model = modelKey(model); if(!model) return;
  const changed = model !== adminSelectedModel;
  adminSelectedModel = model;
  $('#admin-source-select').val(model);
  $('.admin-car').removeClass('selected');
  const card = $(`.admin-car[data-model="${model.replace(/"/g, '\\"')}"]`);
  card.addClass('selected');
  if(card.length && changed){
    const list = $('#admin-list');
    const top = card.position().top + list.scrollTop() - 90;
    list.stop(true).animate({ scrollTop: Math.max(0, top) }, 110);
  }
  fillAdminForm(model, preview && model !== adminPreviewedModel);
}
function selectAdminRelative(delta){
  const models = adminVisibleModels();
  if(!models.length) return;
  let idx = models.indexOf(modelKey(adminSelectedModel || $('#admin-source-select').val()));
  if(idx < 0) idx = delta > 0 ? -1 : 0;
  idx = (idx + delta + models.length) % models.length;
  selectAdminModel(models[idx], true);
}
function setBuyProcessing(active){
  buyProcessing = active === true;
  $('#buy').prop('disabled', buyProcessing).toggleClass('is-processing', buyProcessing).text(buyProcessing ? 'Processing...' : 'Buy Vehicle');
}
function setTestDriveProcessing(active){
  testDriveProcessing = active === true;
  $('#test-accept').prop('disabled', testDriveProcessing).toggleClass('is-processing', testDriveProcessing).text(testDriveProcessing ? 'Processing...' : 'Start');
}
function resetActionProcessing(){ setBuyProcessing(false); setTestDriveProcessing(false); }
function stopTestTimer(){
  if(testTimerInterval){
    clearInterval(testTimerInterval);
    testTimerInterval = null;
  }
  $('body').removeClass('test-drive-active');
  $('#test-drive-timer').removeClass('force-show').hide();
  $('#timer').text('');
}
function showTestTimer(){
  $('body').addClass('test-drive-active');
  $('#test-drive-timer').addClass('force-show').show();
}
function setTimerValue(seconds, baseDuration){
  const total = Math.max(0, Number(seconds) || 0);
  const duration = Math.max(1, Number(baseDuration) || total || 60);
  const minutes = parseInt(total / 60, 10);
  const secs = parseInt(total % 60, 10);
  $('#timer').text((minutes < 10 ? '0' : '') + minutes + ':' + (secs < 10 ? '0' : '') + secs);
  if(total <= duration / 4) $('#timer').css('color', '#ff4d60');
  else if(total <= duration / 2) $('#timer').css('color', '#ffeb3b');
  else $('#timer').css('color', 'white');
  showTestTimer();
}
function catalogByModel(){ const m = {}; for (const row of adminCatalog || []) m[String(row.model).toLowerCase()] = row; return m; }
function renderLegalOrgOptions(){
  const select = $('#admin-status-mode');
  select.find('option[value^="legal:"]').remove();
  (legalOrganizations || []).forEach(org => {
    select.append($('<option>').attr('value', 'legal:' + org.id).text(org.label + ' fleet vehicle'));
  });
}
function renderGrantOrgOptions(){
  const select=$('#admin-grant-org').empty();
  const addGroup=(label,rows)=>{const group=$('<optgroup>').attr('label',label);rows.filter((org,index,all)=>org&&org.id&&all.findIndex(x=>x&&x.id===org.id)===index).forEach(org=>group.append($('<option>').attr('value',org.id).text(org.label||org.id)));if(group.children().length)select.append(group)};
  addGroup('GANGS',gangOrganizations||[]);
  addGroup('PUBLIC ORGANIZATIONS',[{id:'police',label:'Police'},{id:'ems',label:'EMS'}].concat(legalOrganizations||[]));
}
function legalOrgLabel(id){
  const org = (legalOrganizations || []).find(o => o.id === id);
  return org ? org.label : String(id || '').toUpperCase();
}
function statusFor(row){
  if(!row) return 'Not set';
  if(row.availableEms) return 'EMS fleet vehicle';
  if(row.availablePolice) return 'Police fleet vehicle';
  if(row.legalOrg) return legalOrgLabel(row.legalOrg) + ' fleet vehicle';
  if(row.gangId) return String(row.gangId).replace(/^./,c=>c.toUpperCase()) + ' gang vehicle';
  if(row.availableStore) return 'Store: buyable';
  if(row.availableServer) return 'Server only';
  return 'Disabled';
}
function statusClass(row){
  if(!row) return 'notset';
  if(row.availableEms) return 'ems';
  if(row.availablePolice) return 'police';
  if(row.legalOrg) return 'legal-org';
  if(row.gangId) return 'gang';
  if(row.availableStore) return 'store';
  if(row.availableServer) return 'server';
  return 'disabled';
}

function setBodyMode(mode){
  $('body').removeClass('store-active admin-active dialog-active crop-review-open capture-hidden test-drive-active');
  if(mode) $('body').addClass(mode);
}

addEventListener('message', (e) => {
  const msg = e.data || {};
  if(msg.action === 'forceClose'){
    resetActionProcessing();
    forceCloseUi();
    return;
  }
  if(msg.action === 'interaction'){
    if(msg.show){
      $('#interaction-key').text(msg.key || 'E');
      $('#interaction-clerk').text(msg.clerkName || 'Dealer');
      $('#interaction-title').text(msg.title || 'Talk to Dealer');
      $('#interaction-subtitle').text(msg.subtitle || '');
      $('#interaction-prompt').css('display','flex').addClass('show');
    } else {
      $('#interaction-prompt').removeClass('show').hide();
    }
    return;
  } else if(msg.action === 'dealerDialog'){
    if(msg.close){
      $('body').removeClass('dialog-active');
      $('#dealer-dialog').removeClass('show').hide();
      return;
    }
    $('#dealer-dialog-clerk').text(msg.clerkName || 'Dealer');
    $('#dealer-dialog-title').text(msg.title || 'How can I help you today?');
    $('#dealer-dialog-line').text(msg.line || '');
    $('#dealer-dialog-store').text(msg.optionStore || 'Show me the catalog');
    $('#dealer-dialog-close').text(msg.optionClose || 'Maybe later');
    setBodyMode('dialog-active');
    $('#interaction-prompt').removeClass('show').hide();
    $('#dealer-dialog').css('display','flex').addClass('show');
    return;
  } else if(msg.action === 'open'){
    data = msg;
    $('body').removeClass('capture-hidden crop-review-open dialog-active');
    closeAdminPanel(false);
    $('#drawmarker-container').css('left', '-260px');
    hideAllElements();
    $('body').addClass('store-active').removeClass('admin-active dialog-active');
    window.__balance = (msg && msg.balance) || null;
    applyBalanceHud();
    renderCategories();
    autoStart();
  } else if(msg.action === 'balanceUpdate'){
    window.__balance = msg.balance || { cash: 0, bank: 0 };
    applyBalanceHud();
    if(details && details.numberprice != null) updateAfford(Number(details.numberprice || 0), details.buyable === true);
  } else if(msg.action === 'testDriveResult'){
    if(msg.success !== true){
      setTestDriveProcessing(false);
      showToast(msg.message || 'Test drive was rejected.');
      $('#test-text').addClass('purchase-error').text(msg.message || 'Test drive was rejected.');
      setTimeout(() => $('#test-text').removeClass('purchase-error').text('Are you sure you want to start the test drive?'), 2600);
    }
  } else if(msg.action === 'adminReturned'){
    setTestDriveProcessing(false);
    hideAllElements();
    $('body').addClass('admin-active').removeClass('store-active test-drive-active');
    $('#admin-panel').show();
    renderAdmin();
    showToast('Admin test drive finished.');
  } else if(msg.action === 'updateInfo'){
    const v = msg.vehicleInfo || {};
    const rawSpeed = Number(v.speed || 0);
    const rawAccel = Number(v.acceleration || 0);
    const rawBraking = Number(v.braking || 0);
    const rawTraction = Number(v.traction || 0);
    const score = (value, max) => Math.max(0, Math.min(10, Math.round((Number(value) || 0) / max * 10)));
    const speedScore = score(rawSpeed, 220);
    const accelScore = score(rawAccel, 10);
    const brakingScore = score(rawBraking, 10);
    const tractionScore = score(rawTraction, 30);
    $('.num-speed').text(speedScore + ' / 10');
    $('.num-acceleration').text(accelScore + ' / 10');
    $('.num-braking').text(brakingScore + ' / 10');
    $('.num-traction').text(tractionScore + ' / 10');
    $('.speed-line').css('width', (speedScore * 10) + '%');
    $('.acceleration-line').css('width', (accelScore * 10) + '%');
    $('.braking-line').css('width', (brakingScore * 10) + '%');
    $('.traction-line').css('width', (tractionScore * 10) + '%');
    drawPerfRadar(rawSpeed, rawAccel, rawBraking, rawTraction);
  } else if(msg.action === 'vehicleBought'){
    $('#buy-notify span').text('Vehicle purchased successfully.');
    $('#buy-notify div').text('Your vehicle has been added to your owned vehicles.');
    $('#buy-notify').fadeIn();
    setTimeout(() => $('#buy-notify').fadeOut(), 5000);
  } else if(msg.action === 'purchaseFailed'){
    setBuyProcessing(false);
    $('#buy-text').addClass('purchase-error').text(msg.message || 'Purchase failed.');
    setTimeout(() => {
      $('#buy-text').removeClass('purchase-error').text('Are you sure you want to buy this vehicle?');
      $('#buy-vehicle').css('top', '-600px');
    }, 2600);
  } else if(msg.action === 'draw'){
    $('#drawmarker-container').css('left', '1%');
  } else if(msg.action === 'undraw'){
    $('#drawmarker-container').css('left', '-260px');
  } else if(msg.action === 'hideTimer'){
    stopTestTimer();
  } else if(msg.action === 'testdriver'){
    setTestDriveProcessing(false);
    $('body').removeClass('store-active admin-active crop-review-open capture-hidden').addClass('test-drive-active');
    $('#test-drive-container').css('top', '-600px');
    $('#pointer').css('pointer-events', 'unset');
    hideAllElements();
    const duration = Number(msg.duration || (data && data.testDrive && data.testDrive.testDriveTimer) || 60);
    $('#timer').css('color', 'white');
    showTestTimer();
    startTimer(duration);
    onBuyPage = false;
  } else if(msg.action === 'testDriveTick'){
    setTimerValue(Number(msg.remaining || 0), Number(msg.duration || msg.total || 60));
  } else if(msg.action === 'testDriveReturned'){
    setTestDriveProcessing(false);
    const d = msg.details || details || {};
    details = { ...details, ...d };
    hideAllElements();
    $('body').addClass('store-active').removeClass('admin-active dialog-active');
    window.__selectedVehicleModel = details.model || window.__selectedVehicleModel;
    if(details.category || currentCategoryTitle){
      renderVehicleCategory(details.category || currentCategoryTitle);
    }
    $('#title-vehiclename').text(details.vehicle || details.name || details.model || 'Vehicle');
    $('#title-stock').text(details.owned ? 'You own this vehicle' : (details.buyable ? 'Available to purchase' : 'Event / task only'));
    $('#title-price').text(details.buyable ? money(details.numberprice || 0) : 'Not for sale');
    $('#title-trunk').text(trunkLabel(details.trunkLevel));
    $('#buy-btn').toggleClass('disabled-buy', !details.buyable).find('.btn-text').text(details.buyable ? (details.owned ? 'Buy Another' : 'Buy Vehicle') : 'Event / Task Only');
    updateAfford(Number(details.numberprice || 0), details.buyable);
    updateCinematicMeta();
    updateQuickButtons();
    renderColorPalette();
    $('#vehicle-container, #title-container, #statistics-container, #color-warp, #buy-btn, #test-btn, #btn-container').fadeIn();
    $('#test-btn').toggle(details.testDriveEnabled !== false);
    vehicleDisplay = true; inspect = true; onBuyPage = false;
  } else if(msg.action === 'buyvehicle'){
    setBuyProcessing(false);
    $('#buy-vehicle').css('top', '-600px');
    $('#pointer').css('pointer-events', 'unset');
    hideAllElements();
    onBuyPage = false;
  } else if(msg.action === 'adminOpen'){
    adminSourceVehicles = msg.sourceVehicles || [];
    adminCatalog = msg.catalog || [];
    adminDiscoveryInfo = msg.discovery || {};
    visualCatalog = (msg.discovery && msg.discovery.visualCatalog) || visualCatalog;
    legalOrganizations = (msg.discovery && msg.discovery.legalOrganizations) || legalOrganizations;
    gangOrganizations = (msg.discovery && msg.discovery.gangs) || gangOrganizations;
    renderLegalOrgOptions();
    renderGrantOrgOptions();
    adminMode = msg.mode === 'capture' ? 'capture' : 'manage';
    adminPreviewedModel = '';
    openAdminPanel();
  } else if(msg.action === 'adminData'){
    adminSourceVehicles = msg.sourceVehicles || [];
    adminCatalog = msg.catalog || [];
    adminDiscoveryInfo = msg.discovery || adminDiscoveryInfo || {};
    visualCatalog = (msg.discovery && msg.discovery.visualCatalog) || visualCatalog;
    legalOrganizations = (msg.discovery && msg.discovery.legalOrganizations) || legalOrganizations;
    gangOrganizations = (msg.discovery && msg.discovery.gangs) || gangOrganizations;
    renderLegalOrgOptions();
    renderGrantOrgOptions();
    renderAdmin();
  } else if(msg.action === 'closeAdmin'){
    closeAdminPanel(false);
  } else if(msg.action === 'toast'){
    showToast(msg.message || '');
  } else if(msg.action === 'organizationGrantResult'){
    const result=msg.result||{},box=$('#admin-grant-result');
    if(result.ok){const warning=result.status==='needs_home_location'?'⚠ Gang home location not configured':result.partial?`⚠ Fleet link failed: ${safe(result.reason||'unknown')}`:'';box.attr('data-state',result.partial?'warning':'success').html(`<strong>✓ ORGANIZATION VEHICLE CREATED</strong><span>${safe(result.label||result.model||'Vehicle')} · ${safe(result.organization||'')}</span><b>vehicle_id: ${safe(result.vehicleId||'')}</b>${warning?`<small>${warning}</small>`:''}`)}
    else box.attr('data-state','error').html(`<strong>ORGANIZATION VEHICLE FAILED</strong><small>${safe(result.stage||'creation')}: ${safe(result.reason||'unknown error')}</small>`);
  } else if(msg.action === 'prepareVehicleCapture'){
    // Hide all NUI while screenshot-basic captures, so no UI bleeds into the PNG.
    $('body').toggleClass('capture-hidden', msg.value === true);
  } else if(msg.action === 'adminFocus'){
    if(msg.value === false){
      cropHadAdminPanel = cropHadAdminPanel || $('body').hasClass('admin-active') || $('#admin-panel').is(':visible');
      $('#admin-panel').hide();
    } else if(!$('body').hasClass('crop-review-open') && (cropHadAdminPanel || $('body').hasClass('admin-active'))){
      $('#admin-panel').show();
    }
  } else if(msg.action === 'processVehicleImage'){
    removeBackgroundAndCrop(msg.image, msg.payload || {})
      .then(result => openCropModal({ ...result, payload: msg.payload || {} }))
      .catch(err => { post('vehicleImageProcessed', { error: String(err && err.message || err), payload: msg.payload || {} }); });
  } else if(msg.action === 'vehicleImageResult'){
    closeCropModal();
    if(msg.success){
      showToast('Vehicle image saved.');
      if(msg.model && msg.image){
        const m = String(msg.model).toLowerCase();
        const row = adminCatalog.find(r => String(r.model).toLowerCase() === m);
        if(row) row.image = msg.image; else adminCatalog.push({ model: msg.model, image: msg.image });
        // Reflect the new image in the form preview immediately.
        if(String($('#admin-model').val() || '').toLowerCase() === m){
          $('#admin-image-preview').attr('src', msg.image).show();
        }
        renderAdmin();
      }
      // If this capture was triggered by a blocked Save, finish that Save now
      // that the image exists.
      if(pendingSave && String(pendingSave.model).toLowerCase() === String(msg.model).toLowerCase()){
        const save = pendingSave; pendingSave = null;
        showToast('Image ready — enabling vehicle…');
        post('adminSaveVehicle', save);
      }
    } else {
      pendingSave = null;
      showToast('Image capture failed: ' + (msg.error || 'unknown'));
    }
    $('#admin-capture').prop('disabled', false).text('Recapture Image');
  } else if(msg.action === 'adminNeedsImage'){
    // Server blocked enabling this car until it has an image. Capture now, then
    // the vehicleImageResult handler re-submits the pending save.
    pendingSave = msg.pendingSave || null;
    if(pendingSave){ pendingSave.model = msg.model; }
    showToast('No image yet — capturing before enabling…');
    $('#admin-capture').prop('disabled', true).text('Capturing…');
    post('captureVehicleImage', {
      model: msg.model,
      label: (msg.pendingSave && msg.pendingSave.label) || $('#admin-label').val(),
      category: (msg.pendingSave && msg.pendingSave.category) || $('#admin-category').val()
    });
  }
});

// Chroma-key background removal + auto crop (ported from nv_cloth clothing capture),
// but now we also return a full processed preview so the admin can manually review
// and adjust the crop before saving.
function clamp01(n, fb){ n = Number(n); return Number.isFinite(n) ? Math.max(0, Math.min(1, n)) : fb; }
function clamp(n, min, max){ n = Number(n); if(!Number.isFinite(n)) return min; return Math.max(min, Math.min(max, n)); }
function uiYield(){
  return new Promise(resolve => {
    if(typeof requestAnimationFrame === 'function') requestAnimationFrame(() => resolve());
    else setTimeout(resolve, 0);
  });
}

function removeBackgroundAndCrop(dataUrl, payload = {}){
  return new Promise((resolve, reject) => {
    const img = new Image();

    img.onload = async () => {
      let src = null;
      let out = null;

      try {
        src = document.createElement('canvas');
        src.width = img.naturalWidth || img.width;
        src.height = img.naturalHeight || img.height;

        const sctx = src.getContext('2d', { willReadFrequently: true });
        sctx.drawImage(img, 0, 0);

        const imageData = sctx.getImageData(0, 0, src.width, src.height);
        const d = imageData.data;
        const ch = payload.chroma || {};
        const bg = String(payload.background || 'green').toLowerCase();

        // Defaults must match config.lua. The old fallbacks (90/1.28/28) only
        // removed BRIGHT green and would silently reintroduce the dark-green band
        // if the config ever failed to reach the NUI.
        const minGreen = Number(ch.minGreen ?? 18);
        const dominance = Number(ch.dominance ?? 1.06);
        const greenMargin = Number(ch.greenMargin ?? 6);
        const maxRed = Number(ch.maxRed ?? 210);
        const maxBlue = Number(ch.maxBlue ?? 210);
        const soften = ch.soften !== false;

        const crop = payload.crop || {};
        const rx = clamp01(crop.x, 0.00), ry = clamp01(crop.y, 0.00), rw = clamp01(crop.w, 1.00), rh = clamp01(crop.h, 1.00);
        const minX = Math.max(0, Math.floor(src.width * rx));
        const minY = Math.max(0, Math.floor(src.height * ry));
        const maxX = Math.min(src.width - 1, Math.ceil(src.width * Math.min(1, rx + rw)));
        const maxY = Math.min(src.height - 1, Math.ceil(src.height * Math.min(1, ry + rh)));

        const idx = (x, y) => (y * src.width + x) * 4;
        const isTransparent = (x, y) => d[idx(x, y) + 3] <= 10;
        const yieldEvery = (src.width * src.height) > (1920 * 1080) ? 12 : 32;

        // Green-screen key.
        //
        // The old test was purely RGB-threshold based (g >= minGreen && ...), so
        // it only removed BRIGHT green. On a large backdrop the upper area sits
        // in shadow and renders dark, those pixels fell under the threshold, and
        // a solid dark-green band survived into the final image.
        //
        // This version keys on HUE + SATURATION instead, which is independent of
        // brightness: a dark green pixel and a bright green pixel have the same
        // hue, so both are removed. A grey/white/silver car body has almost no
        // saturation and is never touched.
        function isGreenScreen(r, g, b){
          const max = Math.max(r, g, b);
          const min = Math.min(r, g, b);
          const delta = max - min;

          // Green must be the dominant channel at all.
          if(g !== max) return false;
          // Near-grey pixels (car paint, chrome, glass) have tiny delta -> keep.
          if(delta < greenMargin) return false;

          // Saturation relative to the brightest channel. Screen green is a
          // strongly saturated colour even when it is in shadow.
          const sat = delta / (max || 1);
          if(sat < 0.16) return false;

          // Hue in degrees. Pure green is 120. Allow a generous band so lighting
          // shifts (yellow-green in light, blue-green in shade) are still keyed.
          let hue;
          if(delta === 0) return false;
          if(max === r)      hue = 60 * (((g - b) / delta) % 6);
          else if(max === g) hue = 60 * (((b - r) / delta) + 2);
          else               hue = 60 * (((r - g) / delta) + 4);
          if(hue < 0) hue += 360;

          if(hue < 70 || hue > 175) return false;

          // Very dark pixels are shadow/ambient occlusion under the car, not the
          // screen itself. minGreen is now a floor for "is there any green left".
          if(max < minGreen) return false;

          // Keep the explicit dominance/limit knobs working.
          if(g <= Math.max(r, b) * dominance) return false;
          if(r > maxRed || b > maxBlue) return false;

          return true;
        }

        function isKey(i){
          const r = d[i], g = d[i+1], b = d[i+2];
          if(bg === 'blue')  return b >= 110 && b >= r*1.25 && b >= g*1.15 && (b - Math.max(r,g)) >= 25 && r <= 165 && g <= 190;
          if(bg === 'white') return r >= 225 && g >= 225 && b >= 225 && Math.abs(r-g) <= 18 && Math.abs(r-b) <= 18 && Math.abs(g-b) <= 18;
          if(bg === 'black') return r <= 25 && g <= 25 && b <= 25;
          return isGreenScreen(r, g, b);
        }

        function nearTransparent(x, y, radius = 1){
          for(let yy = Math.max(minY, y-radius); yy <= Math.min(maxY, y+radius); yy++){
            for(let xx = Math.max(minX, x-radius); xx <= Math.min(maxX, x+radius); xx++){
              if(isTransparent(xx, yy)) return true;
            }
          }
          return false;
        }

        let removed = 0;

        // Outside-crop transparent pass. Yield every few rows so 4K captures do
        // not freeze the whole NUI while the admin tool processes pixels.
        for(let y = 0; y < src.height; y++){
          for(let x = 0; x < src.width; x++){
            if(x < minX || x > maxX || y < minY || y > maxY) d[idx(x, y) + 3] = 0;
          }
          if((y % yieldEvery) === 0) await uiYield();
        }

        for(let y = minY; y <= maxY; y++){
          for(let x = minX; x <= maxX; x++){
            const i = idx(x, y);
            if(d[i+3] > 10 && isKey(i)){ d[i+3] = 0; removed++; }
          }
          if((y % yieldEvery) === 0) await uiYield();
        }

        if(soften && bg === 'green'){
          for(let y = minY; y <= maxY; y++){
            for(let x = minX; x <= maxX; x++){
              const i = idx(x, y);
              if(d[i+3] > 10 && nearTransparent(x, y, 1) && d[i+1] > d[i]*1.08 && d[i+1] > d[i+2]*1.08){
                d[i+1] = Math.max(d[i], d[i+2]);
              }
            }
            if((y % yieldEvery) === 0) await uiYield();
          }

          // Stronger cleanup pass for leftover green spill under tyres / lower body.
          // NOTE: this used to require g >= 35. The real spill under the car
          // measured g = 34, so it fell one point short and survived. Keyed on
          // dominance now instead of an absolute brightness floor.
          for(let y = minY; y <= maxY; y++){
            for(let x = minX; x <= maxX; x++){
              const i = idx(x, y);
              if(d[i+3] <= 10) continue;
              const r = d[i], g = d[i+1], b = d[i+2];
              if(nearTransparent(x, y, 2) && g >= 12 && g > Math.max(r,b) * 1.03 && (g-r) >= 4 && (g-b) >= 4){
                d[i+3] = 0; removed++;
              } else if(nearTransparent(x, y, 2) && g > r * 1.04 && g > b * 1.04) {
                d[i+1] = Math.max(r, b);
              }
            }
            if((y % yieldEvery) === 0) await uiYield();
          }

          // FINAL SWEEP: catch any residual screen-green anywhere in the frame,
          // not just next to already-transparent pixels. A large shadowed
          // backdrop can leave whole regions of dark green that never touch an
          // edge, which is what produced the solid dark band.
          for(let y = minY; y <= maxY; y++){
            for(let x = minX; x <= maxX; x++){
              const i = idx(x, y);
              if(d[i+3] <= 10) continue;
              if(isGreenScreen(d[i], d[i+1], d[i+2])){
                d[i+3] = 0; removed++;
              }
            }
            if((y % yieldEvery) === 0) await uiYield();
          }
        }

        // Auto-crop around the actual car, not random green spill, shadows, or noise.
        const alphaThreshold = 24;
        const colCounts = new Array(src.width).fill(0);
        const rowCounts = new Array(src.height).fill(0);
        let totalOpaque = 0;

        for(let y = minY; y <= maxY; y++){
          for(let x = minX; x <= maxX; x++){
            if(d[idx(x, y) + 3] > alphaThreshold){
              colCounts[x]++;
              rowCounts[y]++;
              totalOpaque++;
            }
          }
          if((y % yieldEvery) === 0) await uiYield();
        }

        const minColCount = Math.max(3, Math.floor((maxY - minY + 1) * 0.004));
        const minRowCount = Math.max(3, Math.floor((maxX - minX + 1) * 0.004));
        let bMinX = src.width, bMinY = src.height, bMaxX = 0, bMaxY = 0;

        for(let x = minX; x <= maxX; x++){ if(colCounts[x] >= minColCount){ bMinX = x; break; } }
        for(let x = maxX; x >= minX; x--){ if(colCounts[x] >= minColCount){ bMaxX = x; break; } }
        for(let y = minY; y <= maxY; y++){ if(rowCounts[y] >= minRowCount){ bMinY = y; break; } }
        for(let y = maxY; y >= minY; y--){ if(rowCounts[y] >= minRowCount){ bMaxY = y; break; } }

        // Fallback to raw alpha bounds if a thin bike/vehicle was filtered too hard.
        if(bMaxX <= bMinX || bMaxY <= bMinY){
          bMinX = src.width; bMinY = src.height; bMaxX = 0; bMaxY = 0;
          for(let y = minY; y <= maxY; y++){
            for(let x = minX; x <= maxX; x++){
              if(d[idx(x, y) + 3] > 10){
                if(x < bMinX) bMinX = x;
                if(y < bMinY) bMinY = y;
                if(x > bMaxX) bMaxX = x;
                if(y > bMaxY) bMaxY = y;
              }
            }
            if((y % yieldEvery) === 0) await uiYield();
          }
        }

        if(bMaxX <= bMinX || bMaxY <= bMinY){
          throw new Error('No pixels after BG removal');
        }

        const basePad = Number(payload.padding ?? 12);
        const smartPad = Math.max(basePad, Math.round(Math.max(bMaxX - bMinX, bMaxY - bMinY) * 0.025));
        const fMinX = Math.max(0, bMinX - smartPad);
        const fMinY = Math.max(0, bMinY - smartPad);
        const fMaxX = Math.min(src.width - 1, bMaxX + smartPad);
        const fMaxY = Math.min(src.height - 1, bMaxY + smartPad);
        const fW = fMaxX - fMinX + 1;
        const fH = fMaxY - fMinY + 1;

        sctx.putImageData(imageData, 0, 0);

        out = document.createElement('canvas');
        out.width = fW;
        out.height = fH;
        out.getContext('2d').drawImage(src, fMinX, fMinY, fW, fH, 0, 0, fW, fH);

        const png = out.toDataURL('image/png');
        const fullPng = src.toDataURL('image/png');
        const result = {
          dataUrl: png,
          imageBase64: png.split(',')[1],
          fullDataUrl: fullPng,
          autoBounds: { x: fMinX, y: fMinY, w: fW, h: fH },
          naturalWidth: src.width,
          naturalHeight: src.height,
          meta: { removedPixels: removed, width: fW, height: fH, chunked: true }
        };

        resolve(result);
      } catch(err) {
        reject(err);
      } finally {
        if(out){ out.width = 0; out.height = 0; }
        if(src){ src.width = 0; src.height = 0; }
        img.onload = null;
        img.onerror = null;
        img.src = '';
      }
    };

    img.onerror = () => {
      img.onload = null;
      img.onerror = null;
      img.src = '';
      reject(new Error('Unable to load screenshot'));
    };

    img.src = dataUrl;
  });
}

function showToast(message){

  if(!message) return;
  $('#admin-toast').text(message).fadeIn();
  setTimeout(() => $('#admin-toast').fadeOut(), 2500);
}


function closeCropModal(restoreAdmin = true){
  cropPreviewState = null;
  cropDragState = null;
  $('#crop-modal').removeClass('show').hide();
  $('body').removeClass('crop-review-open');
  $('#crop-preview-image').removeAttr('src');
  $('#crop-save').prop('disabled', false).text('Save Image');
  if(restoreAdmin && cropHadAdminPanel){
    $('#admin-panel').show();
    SetTimeoutSafe(() => $('#admin-capture').prop('disabled', false).text('Recapture Image'), 0);
  }
  cropHadAdminPanel = false;
}

function SetTimeoutSafe(fn, ms){ try { setTimeout(fn, ms || 0); } catch(e) { fn(); } }

function cropMetrics(){
  const img = document.getElementById('crop-preview-image');
  const wrap = document.getElementById('crop-image-wrap');
  if(!img || !wrap) return null;
  return {
    img,
    wrap,
    displayW: img.clientWidth || 1,
    displayH: img.clientHeight || 1,
    naturalW: img.naturalWidth || 1,
    naturalH: img.naturalHeight || 1,
  };
}

function setCropBoxDisplay(left, top, width, height){
  const m = cropMetrics(); if(!m) return;
  width = clamp(width, 36, m.displayW);
  height = clamp(height, 36, m.displayH);
  left = clamp(left, 0, m.displayW - width);
  top = clamp(top, 0, m.displayH - height);
  $('#crop-box').css({ left: left + 'px', top: top + 'px', width: width + 'px', height: height + 'px' }).show();
}

function applyCropBoxNatural(bounds){
  const m = cropMetrics(); if(!m) return;
  const b = bounds || { x: 0, y: 0, w: m.naturalW, h: m.naturalH };
  const left = (b.x / m.naturalW) * m.displayW;
  const top = (b.y / m.naturalH) * m.displayH;
  const width = (b.w / m.naturalW) * m.displayW;
  const height = (b.h / m.naturalH) * m.displayH;
  setCropBoxDisplay(left, top, width, height);
}

function getCropNaturalBounds(){
  const m = cropMetrics(); if(!m) return null;
  const box = document.getElementById('crop-box');
  const left = parseFloat(box.style.left || '0');
  const top = parseFloat(box.style.top || '0');
  const width = parseFloat(box.style.width || String(m.displayW));
  const height = parseFloat(box.style.height || String(m.displayH));
  return {
    x: Math.round((left / m.displayW) * m.naturalW),
    y: Math.round((top / m.displayH) * m.naturalH),
    w: Math.max(1, Math.round((width / m.displayW) * m.naturalW)),
    h: Math.max(1, Math.round((height / m.displayH) * m.naturalH)),
  };
}

function openCropModal(result){
  cropPreviewState = result || null;
  if(!cropPreviewState || !cropPreviewState.fullDataUrl) return;

  // Admin panel has a very high z-index. Hide it while reviewing crop so
  // the crop modal receives mouse clicks and the preview is not covered.
  cropHadAdminPanel = cropHadAdminPanel || $('#admin-panel').is(':visible');
  if(cropHadAdminPanel) $('#admin-panel').hide();
  $('body').addClass('crop-review-open');

  $('#crop-save').prop('disabled', false).text('Save Image');
  const img = document.getElementById('crop-preview-image');
  img.onload = () => {
    requestAnimationFrame(() => applyCropBoxNatural(cropPreviewState.autoBounds || { x: 0, y: 0, w: cropPreviewState.naturalWidth, h: cropPreviewState.naturalHeight }));
  };
  img.src = cropPreviewState.fullDataUrl;
  $('#crop-modal').addClass('show').css('display', 'flex');
  $('#admin-capture').prop('disabled', false).text('Recapture Image');
}

function saveCropSelection(){
  if(!cropPreviewState) return;
  const bounds = getCropNaturalBounds();
  if(!bounds) return;
  const img = document.getElementById('crop-preview-image');
  const out = document.createElement('canvas');
  out.width = Math.max(1, bounds.w);
  out.height = Math.max(1, bounds.h);
  const ctx = out.getContext('2d');
  ctx.drawImage(img, bounds.x, bounds.y, bounds.w, bounds.h, 0, 0, out.width, out.height);
  let mime = 'image/webp';
  let dataUrl = out.toDataURL(mime, 0.86);
  if(!dataUrl || !dataUrl.startsWith('data:image/webp')){
    mime = 'image/png';
    dataUrl = out.toDataURL(mime);
  }
  const ext = mime === 'image/webp' ? 'webp' : 'png';
  out.width = 0; out.height = 0;
  $('#crop-save').prop('disabled', true).text('Saving...');
  post('vehicleImageProcessed', {
    dataUrl,
    imageBase64: dataUrl.split(',')[1],
    mime,
    ext,
    payload: cropPreviewState.payload || {},
    meta: { crop: bounds, output: ext }
  });
}

$(document).on('mousedown', '#crop-box', function(e){
  if(e.target && e.target.id === 'crop-resize-handle') return;
  const m = cropMetrics(); if(!m) return;
  const box = document.getElementById('crop-box');
  cropDragState = {
    mode: 'move',
    startX: e.clientX,
    startY: e.clientY,
    left: parseFloat(box.style.left || '0'),
    top: parseFloat(box.style.top || '0'),
    width: parseFloat(box.style.width || '100'),
    height: parseFloat(box.style.height || '100')
  };
  e.preventDefault();
});

$(document).on('mousedown', '#crop-resize-handle', function(e){
  const m = cropMetrics(); if(!m) return;
  const box = document.getElementById('crop-box');
  cropDragState = {
    mode: 'resize',
    startX: e.clientX,
    startY: e.clientY,
    left: parseFloat(box.style.left || '0'),
    top: parseFloat(box.style.top || '0'),
    width: parseFloat(box.style.width || '100'),
    height: parseFloat(box.style.height || '100')
  };
  e.preventDefault();
  e.stopPropagation();
});

$(document).on('mousemove', function(e){
  if(!cropDragState) return;
  const m = cropMetrics(); if(!m) return;
  const dx = e.clientX - cropDragState.startX;
  const dy = e.clientY - cropDragState.startY;
  if(cropDragState.mode === 'move'){
    setCropBoxDisplay(cropDragState.left + dx, cropDragState.top + dy, cropDragState.width, cropDragState.height);
  } else {
    setCropBoxDisplay(cropDragState.left, cropDragState.top,
      clamp(cropDragState.width + dx, 36, m.displayW - cropDragState.left),
      clamp(cropDragState.height + dy, 36, m.displayH - cropDragState.top));
  }
});

$(document).on('mouseup', function(){ cropDragState = null; });
$(document).on('click', '#crop-auto', function(){ if(cropPreviewState) applyCropBoxNatural(cropPreviewState.autoBounds); });
$(document).on('click', '#crop-full', function(){ const m = cropMetrics(); if(m) applyCropBoxNatural({ x: 0, y: 0, w: m.naturalW, h: m.naturalH }); });
$(document).on('click', '#crop-cancel', function(){ post('cancelVehicleImage'); closeCropModal(); $('#admin-capture').prop('disabled', false).text('Recapture Image'); });
$(document).on('click', '#crop-recapture', function(){
  const model = String($('#admin-model').val() || '').trim();
  post('cancelVehicleImage');
  closeCropModal();
  if(!model){ showToast('Enter / select a model first.'); return; }
  $('#admin-capture').prop('disabled', true).text('Capturing...');
  post('adminPreviewVehicle', { model });
  setTimeout(() => post('captureVehicleImage', { model, label: $('#admin-label').val(), category: $('#admin-category').val() }), 250);
});
$(document).on('click', '#crop-save', saveCropSelection);

/* ---- Fixed vehicle categories (icon grid, like the reference dealership) ---- */
const FIXED_CATEGORIES = [
  { title: 'Sports',      icon: 'fa-car-side' },
  { title: 'Super',       icon: 'fa-gauge-high' },
  { title: 'Sedans',      icon: 'fa-car' },
  { title: 'Luxury',      icon: 'fa-gem' },
  { title: 'SUVs',        icon: 'fa-car-rear' },
  { title: 'Trucks',      icon: 'fa-truck' },
  { title: 'Motorcycles', icon: 'fa-motorcycle' },
  { title: 'Bikes',       icon: 'fa-bicycle' },
];
function normalizeCatKey(t){
  let s = String(t || '').toLowerCase().trim();
  if(s === 'suv') s = 'suvs';
  else if(s === 'sedan') s = 'sedans';
  else if(s === 'truck') s = 'trucks';
  else if(s === 'motorcycle' || s === 'moto' || s === 'motorbike' || s === 'motorbikes') s = 'motorcycles';
  else if(s === 'bike' || s === 'bicycle' || s === 'bicycles' || s === 'cycles' || s === 'pushbike') s = 'bikes';
  else if(s === 'supercar' || s === 'supers') s = 'super';
  else if(s === 'sport') s = 'sports';
  return s;
}
function catIconFor(title){
  const key = normalizeCatKey(title);
  const f = FIXED_CATEGORIES.find(c => normalizeCatKey(c.title) === key);
  return f ? f.icon : 'fa-car';
}
// Ordered category list: the fixed 8 first, then any extra categories that
// actually contain vehicles, so nothing is orphaned.
function getCategoryList(){
  const groups = (data && data.vehicles) || [];
  const byKey = {};
  for(const g of groups){ const k = normalizeCatKey(g.title); (byKey[k] = byKey[k] || []).push(g); }
  const out = [], used = {};
  for(const fc of FIXED_CATEGORIES){
    const k = normalizeCatKey(fc.title); used[k] = true;
    let count = 0; for(const g of (byKey[k] || [])) count += (g.buttons || []).length;
    out.push({ title: fc.title, icon: fc.icon, count });
  }
  for(const g of groups){
    const k = normalizeCatKey(g.title);
    if(used[k]) continue; used[k] = true;
    let count = 0; for(const gg of (byKey[k] || [])) count += (gg.buttons || []).length;
    out.push({ title: g.title, icon: catIconFor(g.title), count });
  }
  return out;
}
function buttonsForCategory(title){
  const key = normalizeCatKey(title);
  let buttons = [];
  for(const g of ((data && data.vehicles) || [])){ if(normalizeCatKey(g.title) === key) buttons = buttons.concat(g.buttons || []); }
  return buttons;
}
function renderCatGrid(activeTitle){
  const grid = $('#cat-grid').html('');
  for(const c of getCategoryList()){
    const active = normalizeCatKey(c.title) === normalizeCatKey(activeTitle);
    const dim = c.count === 0 ? ' cat-empty' : '';
    grid.append(`<div class="cat-item${active ? ' active' : ''}${dim}" data-title="${safe(c.title)}"><i class="fas ${c.icon}"></i><span>${safe(c.title)}</span></div>`);
  }
}
function renderCategories(){
  // Full-screen icon chooser (fixed tiles). Shown only when nothing is auto-selected.
  $('#vehicle-class-warp').html('');
  try { $('#vehicle-class-carousel').slick('slickRemove', null, null, true); } catch(e) {}
  const list = getCategoryList();
  if(!list.some(c => c.count > 0)){
    $('#vehicle-class-warp').append(`<div class="empty-shop">No vehicles are enabled yet.<br>Capture photos with /vehicleadmin, then publish them with /managevehicle.</div>`);
    renderCatGrid(null);
    return;
  }
  for(const c of list){
    const dim = c.count === 0 ? ' cat-empty' : '';
    $('#vehicle-class-warp').append(
      `<div class="vehicle-class5 cat-tile${dim}" data-title="${safe(c.title)}">
        <i class="fas ${c.icon} cat-tile-icon"></i>
        <span>${safe(c.title)}</span>
        <div class="category-price">${c.count} vehicle${c.count === 1 ? '' : 's'}</div>
      </div>`);
  }
  renderCatGrid(null);
}
// On open, drop the player straight into the first non-empty category with a car
// already selected, so the shop is never empty.
function autoStart(){
  const first = getCategoryList().find(c => c.count > 0);
  if(first){ renderVehicleCategory(first.title); }
  else { $('#vehicle-class-title-container, #vehicle-class-container').fadeIn(); }
}

/* ---- Performance radar graph ---- */
function normStat(v, max){ v = Number(v) || 0; return Math.max(0, Math.min(1, v / max)); }
function drawPerfRadar(speed, accel, braking, traction){
  const cv = document.getElementById('perf-graph');
  if(!cv || !cv.getContext) return;
  const ctx = cv.getContext('2d');
  const W = cv.width, H = cv.height, cx = W / 2, cy = H / 2 + 4, R = Math.min(W, H) / 2 - 36;
  ctx.clearRect(0, 0, W, H);
  const axes = [
    { label: 'SPEED', val: normStat(speed, 200) },
    { label: 'ACCEL', val: normStat(accel, 15) },
    { label: 'BRAKE', val: normStat(braking, 1.5) },
    { label: 'GRIP',  val: normStat(traction, 3) },
  ];
  const n = axes.length;
  const ang = i => (-Math.PI / 2) + i * (2 * Math.PI / n);
  ctx.lineWidth = 1;
  for(let ring = 1; ring <= 4; ring++){
    const rr = R * ring / 4;
    ctx.strokeStyle = 'rgba(255,255,255,0.09)';
    ctx.beginPath();
    for(let i = 0; i <= n; i++){ const a = ang(i % n); const x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
    ctx.stroke();
  }
  ctx.fillStyle = 'rgba(231,237,245,0.62)';
  ctx.font = '700 11px Inter, Arial, sans-serif';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  for(let i = 0; i < n; i++){
    const a = ang(i), x = cx + Math.cos(a) * R, y = cy + Math.sin(a) * R;
    ctx.strokeStyle = 'rgba(255,255,255,0.09)';
    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(x, y); ctx.stroke();
    ctx.fillText(axes[i].label, cx + Math.cos(a) * (R + 18), cy + Math.sin(a) * (R + 15));
  }
  ctx.beginPath();
  for(let i = 0; i <= n; i++){ const j = i % n, a = ang(j), rr = R * Math.max(0.04, axes[j].val); const x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
  ctx.closePath();
  const grad = ctx.createLinearGradient(0, cy - R, 0, cy + R);
  grad.addColorStop(0, 'rgba(226,236,246,0.5)'); grad.addColorStop(1, 'rgba(205,216,227,0.1)');
  ctx.fillStyle = grad; ctx.fill();
  ctx.strokeStyle = '#dbe4ec'; ctx.lineWidth = 2; ctx.stroke();
  ctx.fillStyle = '#eef3f8';
  for(let i = 0; i < n; i++){ const a = ang(i), rr = R * Math.max(0.04, axes[i].val); const x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr; ctx.beginPath(); ctx.arc(x, y, 3, 0, Math.PI * 2); ctx.fill(); }
}


function getDisplayColors(colors){
  const list = Array.isArray(colors) ? colors : [];
  const byId = {};
  for(const c of list){
    const id = Number(c && c.gtaColor);
    if(!Number.isNaN(id) && byId[id] == null) byId[id] = c;
  }

  // Diverse, showroom-friendly palette first instead of the first 12 GTA colours,
  // because the normal GTA order starts with many similar black/grey shades.
  const preferredIds = [
    111, 0, 4, 8,      // white/black/silver/stone
    27, 38, 42, 55,    // red/orange/yellow/lime
    53, 64, 70, 73,    // green/blue/light blue/racing blue
    83, 89, 135, 145,  // purple/gold/hot pink/metallic purple style options
    12, 14, 36, 88     // matte black/light grey/sunrise/orange-yellow backup
  ];

  const out = [];
  for(const id of preferredIds){
    if(byId[id] && !out.includes(byId[id])) out.push(byId[id]);
  }

  // Fill with more unique-looking colours if a specific GTA id is missing.
  for(const c of list){
    if(out.length >= 20) break;
    if(!out.includes(c)) out.push(c);
  }

  return out.slice(0, 20);
}

function renderColorPalette(){
  $('#colors-container').html('');
  for(const vehicleColor of getDisplayColors((data && data.colors) || [])){
    $('#colors-container').append(`
      <div class="color" data-gtacolor="${vehicleColor.gtaColor}" data-colorname="${safe(vehicleColor.colorName)}"
        data-colorr="${vehicleColor.r}" data-colorg="${vehicleColor.g}" data-colorb="${vehicleColor.b}"
        style="background-color: rgb(${vehicleColor.r},${vehicleColor.g},${vehicleColor.b})">
        <div class="color-icon"><i class="fas fa-check-circle"></i></div>
      </div>`);
  }
  const selectedColor = details && details.gtaColor !== undefined ? Number(details.gtaColor) : 111;
  const selected = $(`#colors-container .color[data-gtacolor="${selectedColor}"]`).first();
  if(selected.length){
    selected.addClass('selected');
    selected.children('.color-icon').show();
  }
}

function renderVehicleCategory(title){
  currentCategoryTitle = title;
  try { $('#vehicle-carousel').slick('slickRemove', null, null, true); } catch(e) {}
  $('#vehicle-warp').html('');
  $('#colors-container').html('');
  $('#store-search').val('');
  $('#store-price-filter').val('all');
  const buttons = buttonsForCategory(title);
  currentVehicleButtons = buttons;
  updateCinematicMeta();

  $('#vehicle-class-title-container, #vehicle-class-container').fadeOut();
  $('#vehicle-container, #title-container, #statistics-container, #color-warp').fadeIn();
  try { $('#vehicle-carousel').slick('refresh'); } catch(e) {}
  $('#title-vehiclecategory').text(title);
  renderCatGrid(title);
  drawPerfRadar(0, 0, 0, 0);

  if(!buttons.length){
    $('#vehicle-warp').html('<div class="empty-shop">No vehicles in this category yet.</div>');
    vehiclesCategory = true;
    return;
  }

  for(const vehicleBtn of buttons){
    const buyable = vehicleBtn.buyable === true || vehicleBtn.buyable === 'true';
    const owned = vehicleBtn.owned === true || vehicleBtn.owned === 'true';
    const fav = isFavorite(vehicleBtn.model);
    const testEnabled = vehicleBtn.testDriveEnabled !== false && vehicleBtn.testDriveEnabled !== 'false';
    const status = buyable ? money(vehicleBtn.costs) : 'Event / Task only';
    const img = vehicleBtn.image
      ? `<img class="vehicle-card-img" src="${safe(vehicleBtn.image)}" alt="${safe(vehicleBtn.name)}" />`
      : `<div class="vehicle-card-img no-img">No Image</div>`;
    const search = `${vehicleBtn.name || ''} ${vehicleBtn.model || ''} ${title || ''} ${status}`;
    const item = `
      <div class="category ${buyable ? '' : 'server-only'} ${owned ? 'owned' : ''} ${fav ? 'favorited' : ''}"
        data-name="${safe(vehicleBtn.name)}" data-model="${safe(vehicleBtn.model)}" data-costs="${Number(vehicleBtn.costs || 0)}"
        data-status="${safe(status)}" data-buyable="${buyable}" data-owned="${owned}" data-trunk="${clampTrunkLevel(vehicleBtn.trunkLevel)}"
        data-search="${safe(search)}" data-test-enabled="${testEnabled}" data-test-timer="${Number(vehicleBtn.testDriveTimer || (data && data.testDrive && data.testDrive.testDriveTimer) || 60)}"
        data-test-cost="${Number(vehicleBtn.testDriveCost || (data && data.testDrive && data.testDrive.testDriveCost) || 0)}">
        <div class="card-badges">
          ${owned ? '<b class="badge owned-badge">OWNED</b>' : ''}
          ${fav ? '<b class="badge fav-badge">★</b>' : ''}
          ${!buyable && !owned ? '<b class="badge event-badge">EVENT</b>' : ''}
        </div>
        ${img}
        <div class="vehicle-card-info">
          <span class="vehicle-card-title">${safe(vehicleBtn.name)}</span>
          <small class="vehicle-card-model">${safe(vehicleBtn.model || '')}</small>
        </div>
        <div class="category-price">${status}</div>
      </div>`;
    $('#vehicle-warp').append(item);
  }
  setTimeout(() => { applyStoreFilters(); ensureVisibleVehicleSelection(); }, 50);


  renderColorPalette();
  vehiclesCategory = true;

  // Never leave the shop empty: auto-select the last selected vehicle if it still
  // exists, otherwise select the first visible vehicle.
  setTimeout(() => {
    const preferredModel = modelKey(window.__selectedVehicleModel || (details && details.model));
    const preferredCard = preferredModel ? $(`#vehicle-warp .category[data-model="${preferredModel}"], #vehicle-warp .category5[data-model="${preferredModel}"]`).filter(':visible').first() : $();
    if(preferredCard.length) preferredCard.trigger('click');
    else ensureVisibleVehicleSelection();
  }, 90);
}

$(document).on('click', '.vehicle-class,.vehicle-class5', function(){ renderVehicleCategory($(this).data('title')); });
$(document).on('click', '#cat-grid .cat-item', function(){ renderVehicleCategory($(this).data('title')); });

$(document).on('click', '.color', function(){
  const colorR = clamp(Number($(this).data('colorr')), 0, 255);
  const colorG = clamp(Number($(this).data('colorg')), 0, 255);
  const colorB = clamp(Number($(this).data('colorb')), 0, 255);
  const colorName = $(this).data('colorname');
  const gtaColor = clamp(Number($(this).data('gtacolor')), 0, 160);
  details.color = colorName;
  details.r = colorR;
  details.g = colorG;
  details.b = colorB;
  details.gtaColor = gtaColor;
  $('.color-icon').fadeOut();
  $('.color').removeClass('selected');
  $(this).addClass('selected');
  $(this).children().fadeIn();
  post('changeColor', { colorR, colorG, colorB });
});

$(document).on('click', '.category, .category5', function(){
  $('.category, .category5').removeClass('selected');
  $(this).addClass('selected');
  const model = String($(this).data('model'));
  const name = String($(this).data('name'));
  const costs = Number($(this).data('costs') || 0);
  const status = String($(this).data('status') || '');
  const buyable = String($(this).data('buyable')) === 'true';
  const owned = String($(this).data('owned')) === 'true';
  const trunkLevel = clampTrunkLevel($(this).data('trunk'));
  const testDriveEnabled = String($(this).data('test-enabled')) !== 'false';
  const testDriveTimer = Number($(this).data('test-timer') || (data && data.testDrive && data.testDrive.testDriveTimer) || 60);
  const testDriveCost = Number($(this).data('test-cost') || (data && data.testDrive && data.testDrive.testDriveCost) || 0);
  $('#title-vehiclename').text(name);
  $('#title-stock').text(owned ? 'You own this vehicle' : (buyable ? 'Available to purchase' : 'Event / task only'));
  $('#title-price').text(buyable ? money(costs) : 'Not for sale');
  $('#title-trunk').text(trunkLabel(trunkLevel));
  $('#buy-btn').toggleClass('disabled-buy', !buyable).find('.btn-text').text(buyable ? (owned ? 'Buy Another' : 'Buy Vehicle') : 'Event / Task Only');
  updateAfford(costs, buyable);
  $('#buy-btn, #btn-container, #color-warp').fadeIn();
  $('#test-btn').toggle(testDriveEnabled === true);
  vehicleDisplay = true;
  inspect = true;
  details = { buyer: data.buyer, price: money(costs), numberprice: costs, vehicle: name, model, color: 'White', r: 255, g: 255, b: 255, gtaColor: 111, status, buyable, owned, category: currentCategoryTitle, trunkLevel, testDriveEnabled, testDriveTimer, testDriveCost };
  renderColorPalette();
  updateCinematicMeta();
  updateQuickButtons();
  window.__selectedVehicleModel = model;
  requestPreviewSpawn(model);
});

$(document).on('input', '#store-search', applyStoreFilters);
$(document).on('change', '#store-price-filter', applyStoreFilters);
$(document).on('click', '#favorite-btn', function(){
  if(!details || !details.model){ showToast('Select a vehicle first.'); return; }
  setFavorite(details.model, !isFavorite(details.model));
  updateFavoriteButton();
  renderVehicleCategory(currentCategoryTitle);
  // Keep selected vehicle details visible after re-render.
  const card = $(`.category[data-model="${safe(details.model)}"], .category5[data-model="${safe(details.model)}"]`).first();
  if(card.length) card.addClass('selected');
});
$(document).on('click', '#compare-btn', function(){
  const snap = selectedVehicleSnapshot();
  if(!snap){ showToast('Select a vehicle first.'); return; }
  addToCompare(snap);
  $('#compare-panel').css('display','flex').hide().fadeIn().addClass('show');
});
$(document).on('click', '#compare-close', function(){ $('#compare-panel').fadeOut().removeClass('show'); });
$(document).on('click', '#compare-clear', function(){ compareList = []; saveJsonStore('rnVehicleShopCompare', compareList); renderComparePanel(); updateCompareButton(); });
$(document).on('click', '.compare-remove', function(){
  const m = modelKey($(this).data('model'));
  compareList = compareList.filter(v => modelKey(v.model) !== m);
  saveJsonStore('rnVehicleShopCompare', compareList);
  renderComparePanel(); updateCompareButton();
});

$('#buy-btn').click(function(){
  if(!details.buyable){ showToast('This vehicle is event/task only.'); return; }
  onBuyPage = true;
  $('#buy-text').removeClass('purchase-error').text('Are you sure you want to buy this vehicle?');
  $('#buy-vehicle').show().css('top', '50%');
  $('#detail-name').text(details.buyer);
  $('#detail-price').text(details.price);
  $('#detail-vehicle').text(details.vehicle);
  $('#detail-color').text(details.color);
  $('#pointer').css('pointer-events','none');
  $('#main').show();
});

$('#test-btn').click(function(){
  onBuyPage = true;
  $('#test-drive-container').show().css('top', '50%');
  $('#test-vehicle').text(details.vehicle);
  $('#test-price').text(Number(details.testDriveCost || 0) + '$');
  changeTime(Number(details.testDriveTimer || (data && data.testDrive && data.testDrive.testDriveTimer) || 60));
  $('#pointer').css('pointer-events','none');
  $('#main').show();
});

$('#back, #test-back').click(function(){
  resetActionProcessing();
  onBuyPage = false;
  $('#buy-vehicle, #test-drive-container').css('top', '-600px');
  $('#pointer').css('pointer-events','unset');
  $('#main').hide();
  $('#buy-vehicle, #test-drive-container').css('top','-600px').hide();
});
$('#test-accept').click(function(){
  if(testDriveProcessing) return;
  setTestDriveProcessing(true);
  post('testDrive', { timer: Number(details.testDriveTimer || (data && data.testDrive && data.testDrive.testDriveTimer) || 60), details })
    .fail(() => { showToast('Test drive request failed.'); setTestDriveProcessing(false); });

  // The server can reject using a HUD notification only. Re-enable the button if
  // the request did not transition to the test-drive screen shortly after.
  setTimeout(() => {
    if(testDriveProcessing && $('#test-drive-container').is(':visible')) setTestDriveProcessing(false);
  }, 3500);
});
$('#buy').click(function(){
  if(buyProcessing) return;
  if(details.gtaColor === undefined) details.gtaColor = 111;
  setBuyProcessing(true);
  post('buyVehicle', { details }).fail(() => {
    showToast('Purchase request failed.');
    setBuyProcessing(false);
  });
});

try { if($.fn && $.fn.slick){ $('#vehicle-carousel').slick({ slidesToShow: 5, dots:true, centerMode: true, centerPadding: '0px' }); $('#vehicle-class-carousel').slick({ slidesToShow: 7, dots:true, centerMode: true, centerPadding: '0px' }); } } catch(e) {}

document.onkeydown = (e) => {
  if($('body').hasClass('admin-active') && $('#admin-panel').is(':visible') && (e.key === 'ArrowUp' || e.key === 'ArrowDown')){
    const tag = String((document.activeElement && document.activeElement.tagName) || '').toLowerCase();
    if(tag !== 'input' && tag !== 'select' && tag !== 'textarea'){
      selectAdminRelative(e.key === 'ArrowDown' ? 1 : -1);
      e.preventDefault();
      return;
    }
  }
  if(e.key !== 'Escape') return;

  // Dealer dialog exists before the player enters the 3D showroom. Never call
  // closeVehicleShop here, because client.lua has not saved showroom return coords yet.
  if($('body').hasClass('dialog-active')){
    $('body').removeClass('dialog-active');
    $('#dealer-dialog').removeClass('show').hide();
    post('dealerDialogClose');
    return;
  }

  if($('#crop-modal').is(':visible')){
    post('cancelVehicleImage');
    closeCropModal();
    return;
  }
  if($('#admin-panel').is(':visible')){ post('adminClose'); return; }
  if(onBuyPage){
    onBuyPage = false;
    $('#buy-vehicle, #test-drive-container').css('top', '-600px').hide();
    $('#pointer').css('pointer-events','unset');
    $('#main').hide();
    return;
  }
  /* redesign: categories stay in the left panel; ESC closes the shop directly */

  // Only close the actual shop when the catalog/showroom is active. This avoids
  // accidental close callbacks from non-showroom UI states.
  if($('body').hasClass('store-active')){
    $('#vehicle-class-title-container, #vehicle-class-container').fadeOut();
    post('closeVehicleShop');
    return;
  }

  forceCloseUi();
};

function backToCategories(){
  vehiclesCategory = false;
  $('#hide-button').css('top','46%').text('Preview');
  try { $('#vehicle-carousel').slick('slickRemove', null, null, true); } catch(e) {}
  $('#vehicle-warp, #colors-container').html('');
  $('#vehicle-container, #title-container, #btn-container, #hide-button, #slider-container, #colors-button, #statistics-container, #store-tools').fadeOut();
  $('#vehicle-class-title-container, #vehicle-class-container').fadeIn();
  $('#vehicle-class-carousel').slick('refresh');
  vehicleDisplay = false; inspect = false;
  post('deletevehicle');
}
$('#back-btn').click(backToCategories);

$('#hide-button').click(function(){
  if(!hideDisplay){
    // "Preview" now just hides the side panels for a clean look. Mouse inspect
    // (rotate + zoom) is already active from the moment a vehicle is selected.
    inspect = true; hideDisplay = true;
    $('#colors-button').css('opacity','0');
    $('#vehicle-container, #title-container, #btn-container, #vehicle-class-title-container').fadeOut();
    $('#statistics-container').css('opacity','0');
    $('#hide-button').text('Back');
    setTimeout(() => $('#hide-button').css('margin-top','450px'), 200);
    post('zoomCam');
  } else {
    hideDisplay = false; inspect = true; // keep inspect on after returning
    $('#hide-button').css('margin-top','2px');
    post('returnCam');
    setTimeout(() => {
      $('#vehicle-container, #title-container, #btn-container').fadeIn();
      $('#statistics-container').css('opacity','1');
      $('#colors-button').css('opacity','1');
      $('#hide-button').text('Preview');
    }, 400);
  }
});
let down = false;

function postCameraControl(name, payload){
  try{ post(name, payload || {}); }catch(e){}
}
function startInspectRotate(e){
  if(!inspect || !vehicleDisplay || down) return;
  if(e && typeof e.button !== 'undefined' && e.button !== 0) return;
  down = true;
  postCameraControl('mousedown');
}
function stopInspectRotate(){
  if(!down) return;
  down = false;
  postCameraControl('mouseup');
}
function blockedInspectTarget(target){
  return $(target).closest('#btn-warp, #vehicle-container, #dealer-dialog, #buy-vehicle, #vehicleadmin, #confirm-buy, #compare-panel, #interaction-prompt').length;
}
document.addEventListener('mousedown', function(e){ if(blockedInspectTarget(e.target)) return; startInspectRotate(e); });
document.addEventListener('mouseup', stopInspectRotate);
document.addEventListener('mouseleave', stopInspectRotate);
window.onmousedown = function(e){ if(blockedInspectTarget(e.target)) return; startInspectRotate(e); };
window.onmouseup = stopInspectRotate;
function handleWheelInspect(ev){
  if(!inspect || !vehicleDisplay) return;
  if(blockedInspectTarget(ev.target)) return;
  if(ev.preventDefault) ev.preventDefault();
  const dy = (ev.deltaY != null ? ev.deltaY : (ev.wheelDelta != null ? -ev.wheelDelta : 0));
  postCameraControl(dy > 0 ? 'downscroll' : 'upscroll');
}
document.addEventListener('wheel', handleWheelInspect, { passive:false });
$('#center-panel, #title-container, body').on('mousedown', function(e){ if(blockedInspectTarget(e.target)) return; startInspectRotate(e); });

function startTimer(duration){
  stopTestTimer();
  const totalDuration = Math.max(1, Number(duration) || 60);
  let remaining = totalDuration;
  const tick = function(){
    setTimerValue(remaining, totalDuration);
    remaining -= 1;
    if(remaining < 0 && testTimerInterval){
      clearInterval(testTimerInterval);
      testTimerInterval = null;
    }
  };
  tick();
  testTimerInterval = setInterval(tick, 1000);
}
function changeTime(duration){
  const minutes = parseInt(duration / 60, 10);
  const seconds = parseInt(duration % 60, 10);
  $('#test-time').text((minutes < 10 ? '0' : '') + minutes + ':' + (seconds < 10 ? '0' : '') + seconds);
}

function stopAllAnimations(){
  $('#vehicle-container, #color-warp, #title-container, #btn-container, #hide-button, #slider-container, #colors-button, #statistics-container, #vehicle-class-title-container, #vehicle-class-container, #buy-vehicle, #test-drive-container, #dealer-dialog, #interaction-prompt, #admin-panel, #crop-modal').stop(true, true);
}

function forceCloseUi(){
  resetActionProcessing();
  stopAllAnimations();
  stopTestTimer();
  $('body').removeClass('store-active admin-active crop-review-open capture-hidden dialog-active test-drive-active');
  $('#main').hide();
  $('#buy-vehicle, #test-drive-container').css('top','-600px').hide();
  $('#dealer-dialog').removeClass('show').hide();
  $('#interaction-prompt').removeClass('show').hide();
  $('#buy-vehicle, #test-drive-container').css('top', '-600px').hide();
  $('#test-drive-timer').hide();
  $('#admin-panel').hide();
  $('#crop-modal').removeClass('show').hide();
  closeCropModal(false);
  $('#vehicle-warp, #colors-container').html('');
  $('#vehicle-container, #color-warp, #title-container, #btn-container, #hide-button, #slider-container, #colors-button, #statistics-container, #vehicle-class-title-container, #vehicle-class-container, #store-tools, #compare-panel').hide();
  vehiclesCategory = false; vehicleDisplay = false; inspect = false; onBuyPage = false; hideDisplay = false;
}

function hideAllElements(){
  stopAllAnimations();
  stopTestTimer();
  $('body').removeClass('store-active admin-active test-drive-active');
  closeCropModal(false);
  $('#main').hide();
  $('#buy-vehicle, #test-drive-container').css('top','-600px').hide();
  $('#hide-button').css('top','46%').text('Preview');
  try { $('#vehicle-carousel').slick('slickRemove', null, null, true); } catch(e) {}
  $('#vehicle-warp, #colors-container').html('');
  $('#vehicle-container, #color-warp, #title-container, #btn-container, #hide-button, #slider-container, #colors-button, #statistics-container, #vehicle-class-title-container, #vehicle-class-container, #store-tools, #compare-panel').fadeOut();
  vehiclesCategory = false; vehicleDisplay = false; inspect = false;
}

function openAdminPanel(){
  hideAllElements();
  $('body').addClass('admin-active').toggleClass('admin-capture-mode', adminMode === 'capture').removeClass('store-active');
  $('.admin-brand-copy h1').text(adminMode === 'capture' ? 'Vehicle Photo Studio' : 'Manage Vehicles');
  $('.admin-brand-copy .admin-kicker').text(adminMode === 'capture' ? 'Capture catalog images' : 'Catalog manager');
  $('.admin-list-heading strong').text(adminMode === 'capture' ? 'Discovered vehicles' : 'Photographed vehicles');
  $('#admin-panel').stop(true,true).show();
  renderAdmin();
}
function closeAdminPanel(send){ $('body').removeClass('admin-active admin-capture-mode'); $('#admin-panel').hide(); adminPreviewedModel = ''; if(send) post('adminClose'); }

function renderAdmin(){
  const byCatalog = catalogByModel();
  const filter = String($('#admin-search').val() || '').toLowerCase();
  $('#admin-source-select').html('');
  $('#admin-list').html('');
  adminRenderedVehicles = [];
  const merged = adminMode === 'capture' ? [...adminSourceVehicles] : adminCatalog.map(row => {
    const source = adminSourceVehicles.find(v => modelKey(v.model) === modelKey(row.model)) || {};
    return Object.assign({}, source, { model: row.model, label: row.label, category: row.category, price: row.price, speedKph: row.speedKph, trunkLevel: row.trunkLevel });
  });
  merged.sort((a,b) => String(a.label || a.model).localeCompare(String(b.label || b.model)));
  for(const v of merged){
    const row = byCatalog[String(v.model).toLowerCase()];
    const hay = `${v.model} ${v.label} ${v.category} ${v.resource || ''} ${statusFor(row)}`.toLowerCase();
    if(filter && !hay.includes(filter)) continue;
    adminRenderedVehicles.push(v);
    $('#admin-source-select').append(`<option value="${safe(v.model)}">${safe(v.label || v.model)} (${safe(v.model)}) — ${safe(v.category || 'Custom')}</option>`);
    const img = row && row.image ? `<img class="admin-car-thumb" src="${safe(row.image)}" />` : `<div class="admin-car-thumb noimg">No img</div>`;
    $('#admin-list').append(`
      <div class="admin-car ${statusClass(row)} ${v.autoDiscovered ? 'auto-detected' : ''} ${v.clientValid === false ? 'invalid-model' : ''}" data-model="${safe(String(v.model).toLowerCase())}">
        ${img}
        <div class="admin-car-meta"><b>${safe(v.label || v.model)}</b><span>${safe(v.model)} • ${safe(v.category || 'Custom')}${v.resource ? ` • ${safe(v.resource)}` : ''}</span></div>
        <em>${statusFor(row)}</em>
      </div>`);
  }
  const visibleModels = adminVisibleModels();
  $('#admin-count').text(`${visibleModels.length} ${visibleModels.length === 1 ? 'vehicle' : 'vehicles'}`);
  const autoCount = Number(adminDiscoveryInfo.autoDiscovered || adminSourceVehicles.filter(v => v.autoDiscovered).length || 0);
  const resourceCount = Number(adminDiscoveryInfo.scannedResources || 0);
  $('#admin-discovery-info').text(`${autoCount} auto-detected from ${resourceCount} started resource${resourceCount === 1 ? '' : 's'}`);
  let preferred = modelKey(adminSelectedModel || $('#admin-source-select').val());
  if(!preferred || !visibleModels.includes(preferred)) preferred = modelKey(adminRenderedVehicles[0] && adminRenderedVehicles[0].model);
  if(preferred) selectAdminModel(preferred, !adminPreviewedModel);
  else fillAdminForm('');
}


function setAdminCategory(cat){
  cat = String(cat || 'Custom');
  const sel = $('#admin-category'); if(!sel.length) return;
  let has = false;
  sel.find('option').each(function(){ if($(this).val() === cat || $(this).text() === cat) has = true; });
  if(!has) sel.append(`<option>${safe(cat)}</option>`);
  sel.val(cat);
}

// ── EMS appearance editor ────────────────────────────────────────────────
// Options come from cm-tuning's visual catalog (server pushed it in as
// discovery.visualCatalog). Live changes are sent to client.lua's
// adminModPatch, which merges + re-applies the whole mods table to the local
// admin preview vehicle via cm-vehicles' ApplyVehicleMods -- same reuse
// cm-ems's fleet configurator uses, just against this resource's own preview.
// Same nested merge as client.lua's mergeAdminMods (extras/mods/neons merge
// key-by-key). This copy is display-only -- client.lua's currentAdminMods is
// what actually gets applied/saved -- but without the same merge logic the
// UI would visually forget e.g. a spoiler choice the moment another body
// part changes, since a naive Object.assign replaces the whole sub-object.
function mergeEmsMods(base, patch){
  if(!patch || typeof patch !== 'object') return base;
  for(const key of Object.keys(patch)){
    const value = patch[key];
    if((key === 'extras' || key === 'mods') && value && typeof value === 'object'){
      base[key] = Object.assign(base[key] || {}, value);
    } else if(key === 'neons' && value && typeof value === 'object'){
      base.neons = Object.assign(base.neons || {}, value);
    } else {
      base[key] = value;
    }
  }
  return base;
}

function emsModPatch(patch){
  mergeEmsMods(adminEmsMods, patch); // display-only mirror; client.lua is authoritative
  post('adminModPatch', { patch });
}

function buildEmsSwatchRow($el, colors, currentValue){
  $el.empty();
  (colors || []).forEach(([value, label, hex]) => {
    const $btn = $('<button type="button" class="va-swatch"></button>')
      .css('background', hex).attr('title', label).attr('data-value', value)
      .toggleClass('active', Number(currentValue) === Number(value));
    $el.append($btn);
  });
}

function buildEmsSelect($el, count, currentValue){
  $el.empty().append('<option value="0">Stock</option>');
  for(let i = 0; i < count; i++){ $el.append(`<option value="${i}">Option ${i + 1}</option>`); }
  if(currentValue !== undefined) $el.val(String(currentValue));
}

function buildEmsLabeledSelect($el, options, currentValue){
  $el.empty();
  (options || []).forEach(([value, label]) => { $el.append(`<option value="${value}">${safe(label)}</option>`); });
  if(currentValue !== undefined) $el.val(String(currentValue));
}

function renderEmsSection(row){
  const mods = JSON.parse(JSON.stringify((row && row.mods) || {}));
  adminEmsMods = mods;

  const catalog = visualCatalog || {};
  buildEmsSwatchRow($('#admin-ems-primary'), catalog.colors, mods.primaryColor);
  buildEmsSwatchRow($('#admin-ems-secondary'), catalog.colors, mods.secondaryColor);
  buildEmsSwatchRow($('#admin-ems-neoncolor'), (catalog.neonColors || []).map(([label, r, g, b]) => [`${r},${g},${b}`, label, `rgb(${r},${g},${b})`]), null);
  buildEmsSelect($('#admin-ems-wheeltype'), 12, mods.wheelType);
  buildEmsLabeledSelect($('#admin-ems-tint'), (catalog.windowTints || []).map(([v, l]) => [v, l]), mods.windowTint);
  buildEmsLabeledSelect($('#admin-ems-plate'), (catalog.plateStyles || []).map(([v, l]) => [v, l]), mods.plateIndex);
  $('#admin-ems-tyrelevel').val(String(mods.tyreLevel ?? 0));

  const extras = mods.extras || {};
  $('#admin-ems-extras').empty();
  for(let id = 1; id <= 8; id++){
    const on = extras[String(id)] === true;
    $('#admin-ems-extras').append(`<label><input type="checkbox" data-extra="${id}" ${on ? 'checked' : ''}><span>Extra ${id}</span></label>`);
  }
  const neons = mods.neons || [];
  $('#admin-ems-neons').empty();
  for(let i = 1; i <= 4; i++){
    const on = neons[i - 1] === true;
    $('#admin-ems-neons').append(`<label><input type="checkbox" data-neon="${i}" ${on ? 'checked' : ''}><span>Neon ${i}</span></label>`);
  }

  // Livery + body-part selects need the vehicle's actual supported counts
  // (from client.lua's introspectAdminVehicle), not a guessed ceiling.
  renderEmsIntrospectControls(adminIntrospect);
}

// Populate the livery select and every "body part" select (spoiler, bumpers,
// hood, roof, wheels-visual, etc.) with ONLY the option counts this specific
// vehicle actually supports, and select whatever is already in adminEmsMods.
function renderEmsIntrospectControls(introspect){
  introspect = introspect || { liveries: 0, slots: {} };
  const liveries = Number(introspect.liveries) || 0;
  const $livery = $('#admin-ems-livery');
  $livery.empty().append('<option value="-1">None</option>');
  for(let i = 0; i < liveries; i++){ $livery.append(`<option value="${i}">Livery ${i + 1}</option>`); }
  $livery.val(String(adminEmsMods.livery ?? -1));

  const slotMods = adminEmsMods.mods || {};
  $('#admin-ems-parts [data-part]').each(function(){
    const key = $(this).data('part');
    const slot = (introspect.slots || {})[key] || { modType: null, count: 0 };
    const current = slot.modType !== null ? slotMods[String(slot.modType)] : undefined;
    $(this).empty().append('<option value="-1">Stock</option>');
    for(let i = 0; i < slot.count; i++){ $(this).append(`<option value="${i}">Option ${i + 1}</option>`); }
    $(this).val(String(current ?? -1)).data('mod-type', slot.modType);
    $(this).prop('disabled', slot.count === 0);
  });
}

$(document).on('change', '#admin-ems-parts [data-part]', function(){
  const modType = $(this).data('mod-type');
  if(modType === null || modType === undefined) return;
  emsModPatch({ mods: { [modType]: Number($(this).val()) } });
});

$(document).on('change', '#admin-ems-wheeltype', function(){ emsModPatch({ wheelType: Number($(this).val()) }); });
$(document).on('change', '#admin-ems-tyrelevel', function(){ emsModPatch({ tyreLevel: Number($(this).val()) }); });
$(document).on('change', '#admin-ems-tint', function(){ emsModPatch({ windowTint: Number($(this).val()) }); });
$(document).on('change', '#admin-ems-plate', function(){ emsModPatch({ plateIndex: Number($(this).val()) }); });
$(document).on('change', '#admin-ems-livery', function(){ emsModPatch({ livery: Number($(this).val()) }); });
$(document).on('click', '#admin-ems-primary .va-swatch, #admin-ems-secondary .va-swatch', function(){
  const $row = $(this).closest('.va-swatch-row');
  $row.find('.va-swatch').removeClass('active');
  $(this).addClass('active');
  emsModPatch({ [$row.data('target')]: Number($(this).data('value')) });
});
$(document).on('click', '#admin-ems-neoncolor .va-swatch', function(){
  const $row = $(this).closest('.va-swatch-row');
  $row.find('.va-swatch').removeClass('active');
  $(this).addClass('active');
  const [r, g, b] = String($(this).data('value')).split(',').map(Number);
  emsModPatch({ neonColor: { r, g, b } });
});
$(document).on('change', '#admin-ems-extras [data-extra]', function(){
  emsModPatch({ extras: { [$(this).data('extra')]: $(this).is(':checked') } });
});
$(document).on('change', '#admin-ems-neons [data-neon]', function(){
  const neons = [false, false, false, false];
  $('#admin-ems-neons [data-neon]').each(function(){ neons[Number($(this).data('neon')) - 1] = $(this).is(':checked'); });
  emsModPatch({ neons });
});
$(document).on('change', '#admin-status-mode', function(){
  const mode = String($(this).val());
  const showEms = mode === 'ems' || mode === 'police' || mode.indexOf('legal:') === 0;
  $('#admin-ems-section').toggle(showEms);
  if(showEms){
    const model = String($('#admin-model').val() || '').toLowerCase();
    renderEmsSection(catalogByModel()[model] || {});
  }
});

function fillAdminForm(model, preview = true){
  model = String(model || '').toLowerCase();
  const source = adminSourceVehicles.find(v => String(v.model).toLowerCase() === model) || {};
  const row = catalogByModel()[model] || {};
  $('#admin-model').val(row.model || source.model || model);
  $('#admin-label').val(row.label || source.label || source.name || model);
  setAdminCategory(row.category || source.category || 'Custom');
  $('#admin-price').val(row.price ?? source.price ?? 0);
  $('#admin-speed').val(row.speedKph ?? source.speedKph ?? 0);
  $('#admin-trunk').val(clampTrunkLevel(row.trunkLevel ?? source.trunkLevel ?? 1));
  const statusMode = row.availableEms === true ? 'ems'
    : row.availablePolice === true ? 'police'
    : row.legalOrg ? ('legal:' + row.legalOrg)
    : row.gangId ? ('gang:' + row.gangId)
    : row.availableStore === true ? 'store'
    : (row.availableServer === true ? 'server' : 'hidden');
  $('#admin-status-mode').val(row.model ? statusMode : 'hidden');
  const showEmsSection = statusMode === 'ems' || statusMode === 'police' || statusMode.indexOf('legal:') === 0;
  $('#admin-ems-section').toggle(showEmsSection);
  if(showEmsSection) renderEmsSection(row);
  const td = (row.metadata && row.metadata.testDrive) || {};
  $('#admin-test-enabled').prop('checked', td.enabled !== false);
  $('#admin-test-duration').val(td.duration ?? (data && data.testDrive && data.testDrive.testDriveTimer) ?? 60);
  $('#admin-test-cost').val(td.cost ?? (data && data.testDrive && data.testDrive.testDriveCost) ?? 0);
  $('#admin-current-status')
    .text(statusFor(row.model ? row : null))
    .attr('data-status', row.model ? statusMode : 'notset');
  $('#admin-selected-title').text(row.label || source.label || source.name || model || 'Vehicle settings');
  const sourceName = source.resource || (source.autoDiscovered ? 'Auto detected' : 'Config');
  $('#admin-current-resource').text(sourceName).toggleClass('auto', !!source.autoDiscovered);
  $('#admin-test, #admin-capture').prop('disabled', source.clientValid === false);
  if(preview && (row.model || source.model || model) && $('#admin-panel').is(':visible')){
    adminPreviewedModel = modelKey(row.model || source.model || model);
    post('adminPreviewVehicle', { model: row.model || source.model || model, mods: row.mods || null }).then((result) => {
      adminIntrospect = (result && result.introspect) || { liveries: 0, slots: {} };
      const mode = String($('#admin-status-mode').val() || '');
      if(mode === 'ems' || mode === 'police' || mode.indexOf('legal:') === 0) renderEmsIntrospectControls(adminIntrospect);
    });
  }
  const imagePreview = $('#admin-image-preview');
  if(row.image){ imagePreview.attr('src', row.image).show(); }
  else { imagePreview.removeAttr('src').hide(); }
  $('#admin-capture').text(row.image ? 'Retake Photo' : 'Take Photo');
}

$(document).on('input', '#admin-search', renderAdmin);
$(document).on('change', '#admin-source-select', function(){ selectAdminModel($(this).val(), true); });
$(document).on('click', '.admin-car', function(){ selectAdminModel($(this).data('model'), true); });
$(document).on('click', '#admin-prev', function(){ selectAdminRelative(-1); });
$(document).on('click', '#admin-next', function(){ selectAdminRelative(1); });
$(document).on('click', '#admin-save', function(){
  const mode = String($('#admin-status-mode').val() || 'hidden');
  const availableEms = mode === 'ems';
  const availablePolice = mode === 'police';
  const legalOrg = mode.indexOf('legal:') === 0 ? mode.slice(6) : null;
  const gangId = mode.indexOf('gang:') === 0 ? mode.slice(5) : null;
  const availableStore = mode === 'store';
  const availableServer = mode === 'server' || availableStore;
  const payload = {
    model: $('#admin-model').val(), label: $('#admin-label').val(), category: $('#admin-category').val(),
    price: Number($('#admin-price').val() || 0), speedKph: Number($('#admin-speed').val() || 0), trunkLevel: clampTrunkLevel($('#admin-trunk').val()),
    availableServer, availableStore, availableEms, availablePolice, legalOrg, gangId,
    testDriveEnabled: $('#admin-test-enabled').is(':checked'),
    testDriveTimer: Number($('#admin-test-duration').val() || 60),
    testDriveCost: Number($('#admin-test-cost').val() || 0)
  };
  // The actual mods payload is attached server-side by client.lua's
  // adminSaveVehicle NUI callback (currentAdminMods, kept in sync via
  // adminModPatch) -- it is authoritative over anything the NUI could claim.
  post('adminSaveVehicle', payload);
});
$(document).on('click', '#dealer-dialog-store', function(){ $('body').removeClass('dialog-active'); $('#dealer-dialog').removeClass('show').hide(); $('#interaction-prompt').removeClass('show').hide(); post('dealerDialogStore'); });
$(document).on('click', '#dealer-dialog-close', function(){ $('body').removeClass('dialog-active'); $('#dealer-dialog').removeClass('show').hide(); post('dealerDialogClose'); });
$(document).on('click', '#admin-test', function(){
  const model = String($('#admin-model').val() || '').trim();
  if(!model){ showToast('Select a vehicle first.'); return; }
  const payload = {
    model, vehicle: $('#admin-label').val() || model, label: $('#admin-label').val() || model,
    category: $('#admin-category').val() || 'Custom',
    testDriveTimer: Number($('#admin-test-duration').val() || 60),
    r: 255, g: 255, b: 255, gtaColor: 111, color: 'White'
  };
  setTestDriveProcessing(true);
  post('adminTestVehicle', payload).fail(() => { setTestDriveProcessing(false); showToast('Admin test request failed.'); });
});
$(document).on('click', '#admin-disable', function(){ post('adminDisableVehicle', { model: $('#admin-model').val() }); });
$(document).on('click', '#admin-grant-org-vehicle', function(){
  const model=String($('#admin-model').val()||'').trim(),organization=String($('#admin-grant-org').val()||'').trim();
  const minimumTier=Math.max(1,Math.min(100,Math.floor(Number($('#admin-grant-drive-tier').val())||1)));
  const trunkMinimumTier=Math.max(1,Math.min(100,Math.floor(Number($('#admin-grant-trunk-tier').val())||1)));
  if(!model||!organization){showToast('Select a vehicle and organization first.');return;}
  if(!confirm(`Give ${model} to ${organization}? This creates a new persistent vehicle.`))return;
  $('#admin-grant-result').attr('data-state','working').text('Creating organization vehicle…');
  post('adminGrantOrganizationVehicle',{model,organization,minimumTier,trunkMinimumTier});
});
$(document).on('click', '#admin-capture', function(){
  const model = String($('#admin-model').val() || '').trim();
  if(!model){ showToast('Enter / select a model first.'); return; }
  $(this).prop('disabled', true).text('Capturing…');
  post('adminPreviewVehicle', { model });
  setTimeout(() => post('captureVehicleImage', {
    model,
    label: $('#admin-label').val(),
    category: $('#admin-category').val()
  }), 250);
});
$(document).on('click', '#admin-rescan', function(){
  const btn = $(this); btn.prop('disabled', true).addClass('is-scanning');
  $('#admin-discovery-info').text('Scanning started vehicle resources…');
  post('adminRescanVehicles').always(() => setTimeout(() => btn.prop('disabled', false).removeClass('is-scanning'), 1200));
});
$(document).on('click', '#admin-refresh', function(){ post('adminRefresh'); });
$(document).on('click', '#admin-close', function(){ closeAdminPanel(true); });


/* ---- Redesign helpers: ESC panel, Cash/Bank HUD, Insufficient Funds ---- */
$(document).on('click', '#esc-close', function(){ post('closeVehicleShop'); });

function applyBalanceHud(){
  const b = window.__balance;
  if(b && (b.cash != null || b.bank != null)){
    $('#hud-bar').css('display','flex');
    $('#hud-cash').text(money(Number(b.cash || 0)));
    $('#hud-bank').text(money(Number(b.bank || 0)));
  } else {
    $('#hud-bar').hide();  // no balance from server -> hide HUD, never block buying
  }
}

function updateAfford(price, buyable){
  const b = window.__balance;
  const known = b && (b.cash != null || b.bank != null);
  const cannotAfford = !!(buyable && known && ((Number(b.cash||0) + Number(b.bank||0)) < Number(price||0)));

  // Keep the buy button clickable even when the local balance HUD says the
  // player cannot afford it. The real validation happens server-side after the
  // player confirms, so the confirm modal can show "You do not have enough money."
  $('#buy-warning').hide();
  $('#buy-btn').css('display', 'flex');
  $('#buy-btn')
    .toggleClass('disabled-buy', !buyable)
    .toggleClass('cannot-afford', cannotAfford)
    .attr('title', cannotAfford ? 'Not enough money. Confirm purchase to check with server.' : '');
}



/* Cinematic Cyan V2 category controls. This lets the visible right-side arrows
   replace the old left category panel without breaking the existing renderer. */
(function(){
  function availableCinematicCategories(){
    try { return getCategoryList().filter(c => Number(c.count || 0) > 0); } catch(e) { return []; }
  }
  function cycleCinematicCategory(dir){
    const list = availableCinematicCategories();
    if(!list.length) return;
    const current = normalizeCatKey(currentCategoryTitle || '');
    let idx = list.findIndex(c => normalizeCatKey(c.title) === current);
    if(idx < 0) idx = 0;
    idx = (idx + dir + list.length) % list.length;
    renderVehicleCategory(list[idx].title);
  }
  $(document).on('click', '#cinema-cat-up', function(e){ e.preventDefault(); e.stopPropagation(); cycleCinematicCategory(-1); });
  $(document).on('click', '#cinema-cat-down', function(e){ e.preventDefault(); e.stopPropagation(); cycleCinematicCategory(1); });
  function cycleVisibleVehicle(dir){
    const list = $('#vehicle-warp .category:visible, #vehicle-warp .category5:visible');
    if(!list.length) return;
    let idx = list.index($('#vehicle-warp .category.selected, #vehicle-warp .category5.selected').first());
    if(idx < 0) idx = 0;
    idx = (idx + dir + list.length) % list.length;
    list.eq(idx).trigger('click');
  }
  $(document).on('click', '#cinema-veh-prev', function(e){ e.preventDefault(); e.stopPropagation(); cycleVisibleVehicle(-1); });
  $(document).on('click', '#cinema-veh-next', function(e){ e.preventDefault(); e.stopPropagation(); cycleVisibleVehicle(1); });
  $(document).on('keydown', function(e){
    if(!$('body').hasClass('store-active')) return;
    if(e.key === 'ArrowUp') { e.preventDefault(); cycleCinematicCategory(-1); }
    if(e.key === 'ArrowDown') { e.preventDefault(); cycleCinematicCategory(1); }
    if(e.key === 'ArrowLeft') { e.preventDefault(); cycleVisibleVehicle(-1); }
    if(e.key === 'ArrowRight') { e.preventDefault(); cycleVisibleVehicle(1); }
  });
})();
