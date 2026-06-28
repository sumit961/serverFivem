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

function money(n){ return Number(n || 0).toLocaleString() + '$'; }
function safe(v){ return String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c])); }
function post(name, payload){ return $.post(`https://rn-vehicleshop/${name}`, JSON.stringify(payload || {})); }
function catalogByModel(){ const m = {}; for (const row of adminCatalog || []) m[String(row.model).toLowerCase()] = row; return m; }
function statusFor(row){
  if(!row) return 'Not set';
  if(row.availableStore) return 'Store: buyable';
  if(row.availableServer) return 'Server only';
  return 'Disabled';
}
function statusClass(row){
  if(!row) return 'notset';
  if(row.availableStore) return 'store';
  if(row.availableServer) return 'server';
  return 'disabled';
}

addEventListener('message', (e) => {
  const msg = e.data || {};
  if(msg.action === 'forceClose'){
    forceCloseUi();
    return;
  }
  if(msg.action === 'interaction'){
    if(msg.show){
      $('#interaction-key').text(msg.key || 'E');
      $('#interaction-clerk').text(msg.clerkName || 'Dealer');
      $('#interaction-title').text(msg.title || 'Talk to Dealer');
      $('#interaction-subtitle').text(msg.subtitle || '');
      $('#interaction-prompt').show().addClass('show');
    } else {
      $('#interaction-prompt').removeClass('show').hide();
    }
    return;
  } else if(msg.action === 'dealerDialog'){
    if(msg.close){
      $('#dealer-dialog').removeClass('show').hide();
      return;
    }
    $('#dealer-dialog-clerk').text(msg.clerkName || 'Dealer');
    $('#dealer-dialog-title').text(msg.title || 'How can I help you today?');
    $('#dealer-dialog-line').text(msg.line || '');
    $('#dealer-dialog-store').text(msg.optionStore || 'Show me the catalog');
    $('#dealer-dialog-close').text(msg.optionClose || 'Maybe later');
    $('#interaction-prompt').removeClass('show').hide();
    $('#dealer-dialog').show().addClass('show');
    return;
  } else if(msg.action === 'open'){
    data = msg;
    $('body').removeClass('capture-hidden crop-review-open');
    closeAdminPanel(false);
    $('#drawmarker-container').css('left', '-260px');
    hideAllElements();
    $('body').addClass('store-active').removeClass('admin-active');
    $('#vehicle-class-title-container').fadeIn();
    $('#vehicle-class-container').fadeIn();
    renderCategories();
  } else if(msg.action === 'updateInfo'){
    const v = msg.vehicleInfo || {};
    $('.num-speed').text(v.speed || '0');
    $('.num-acceleration').text(v.acceleration || '0');
    $('.num-braking').text(v.braking || '0');
    $('.num-traction').text(v.traction || '0');
    $('.speed-line').css('width', ((Number(v.speed || 0) / 200) * 100) + '%');
    $('.acceleration-line').css('width', ((Number(v.acceleration || 0)) * 10) + '%');
    $('.braking-line').css('width', ((Number(v.braking || 0) / 50) * 100) + '%');
    $('.traction-line').css('width', ((Number(v.traction || 0) / 50) * 100) + '%');
  } else if(msg.action === 'vehicleBought'){
    $('#buy-notify span').text('Vehicle purchased successfully.');
    $('#buy-notify div').text('Your vehicle has been added to your owned vehicles.');
    $('#buy-notify').fadeIn();
    setTimeout(() => $('#buy-notify').fadeOut(), 5000);
  } else if(msg.action === 'purchaseFailed'){
    $('#buy-text').text(msg.message || 'Purchase failed.');
    setTimeout(() => $('#buy-vehicle').css('top', '-600px'), 1500);
  } else if(msg.action === 'draw'){
    $('#drawmarker-container').css('left', '1%');
  } else if(msg.action === 'undraw'){
    $('#drawmarker-container').css('left', '-260px');
  } else if(msg.action === 'hideTimer'){
    if(testTimerInterval){ clearInterval(testTimerInterval); testTimerInterval = null; }
    $('#test-drive-timer').fadeOut();
  } else if(msg.action === 'testdriver'){
    $('body').removeClass('store-active admin-active crop-review-open');
    $('#test-drive-container').css('top', '-600px');
    $('#pointer').css('pointer-events', 'unset');
    hideAllElements();
    $('#timer').css('color', 'white');
    $('#test-drive-timer').fadeIn();
    startTimer(Number(msg.duration || (data && data.testDrive && data.testDrive.testDriveTimer) || 60));
    onBuyPage = false;
  } else if(msg.action === 'testDriveReturned'){
    const d = msg.details || details || {};
    details = { ...details, ...d };
    hideAllElements();
    $('body').addClass('store-active').removeClass('admin-active');
    $('#title-vehiclename').text(details.vehicle || details.name || details.model || 'Vehicle');
    $('#title-stock').text(details.buyable ? ('Status: Buyable | Trunk Level: ' + (details.trunkLevel || 1)) : ('Status: Event / Task only | Trunk Level: ' + (details.trunkLevel || 1)));
    $('#title-price').text(details.buyable ? ('Price: ' + (details.price || money(details.numberprice || 0))) : 'Price: Not for sale');
    $('#buy-btn').toggleClass('disabled-buy', !details.buyable).find('.btn-text').text(details.buyable ? 'Buy Vehicle' : 'Event / Task Only');
    $('#vehicle-container, #title-container, #statistics-container, #buy-btn, #test-btn, #hide-button, #slider-container, #btn-container').fadeIn();
    $('#test-btn').toggle(details.testDriveEnabled !== false);
    vehicleDisplay = true; inspect = true; onBuyPage = false;
  } else if(msg.action === 'buyvehicle'){
    $('#buy-vehicle').css('top', '-600px');
    $('#pointer').css('pointer-events', 'unset');
    hideAllElements();
    onBuyPage = false;
  } else if(msg.action === 'adminOpen'){
    adminSourceVehicles = msg.sourceVehicles || [];
    adminCatalog = msg.catalog || [];
    openAdminPanel();
  } else if(msg.action === 'adminData'){
    adminSourceVehicles = msg.sourceVehicles || [];
    adminCatalog = msg.catalog || [];
    renderAdmin();
  } else if(msg.action === 'closeAdmin'){
    closeAdminPanel(false);
  } else if(msg.action === 'toast'){
    showToast(msg.message || '');
  } else if(msg.action === 'prepareVehicleCapture'){
    // Hide all NUI while screenshot-basic captures, so no UI bleeds into the PNG.
    $('body').toggleClass('capture-hidden', msg.value === true);
  } else if(msg.action === 'adminFocus'){
    if(msg.value === false){
      if($('#admin-panel').is(':visible')) cropHadAdminPanel = true;
      $('#admin-panel').hide();
    } else if(!$('body').hasClass('crop-review-open') && cropHadAdminPanel){
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
function removeBackgroundAndCrop(dataUrl, payload = {}){
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const src = document.createElement('canvas');
      src.width = img.naturalWidth || img.width;
      src.height = img.naturalHeight || img.height;
      const sctx = src.getContext('2d', { willReadFrequently: true });
      sctx.drawImage(img, 0, 0);
      const imageData = sctx.getImageData(0, 0, src.width, src.height);
      const d = imageData.data;
      const ch = payload.chroma || {};
      const bg = String(payload.background || 'green').toLowerCase();
      const minGreen = Number(ch.minGreen ?? 90), dominance = Number(ch.dominance ?? 1.28);
      const greenMargin = Number(ch.greenMargin ?? 28), maxRed = Number(ch.maxRed ?? 150), maxBlue = Number(ch.maxBlue ?? 165);
      const soften = ch.soften !== false;
      const crop = payload.crop || {};
      const rx = clamp01(crop.x, 0.00), ry = clamp01(crop.y, 0.00), rw = clamp01(crop.w, 1.00), rh = clamp01(crop.h, 1.00);
      const minX = Math.max(0, Math.floor(src.width * rx)), minY = Math.max(0, Math.floor(src.height * ry));
      const maxX = Math.min(src.width - 1, Math.ceil(src.width * Math.min(1, rx + rw)));
      const maxY = Math.min(src.height - 1, Math.ceil(src.height * Math.min(1, ry + rh)));
      const idx = (x, y) => (y * src.width + x) * 4;
      const isTransparent = (x, y) => d[idx(x,y)+3] <= 10;
      function isKey(i){
        const r = d[i], g = d[i+1], b = d[i+2];
        if(bg === 'blue')  return b >= 110 && b >= r*1.25 && b >= g*1.15 && (b - Math.max(r,g)) >= 25 && r <= 165 && g <= 190;
        if(bg === 'white') return r >= 225 && g >= 225 && b >= 225 && Math.abs(r-g) <= 18 && Math.abs(r-b) <= 18 && Math.abs(g-b) <= 18;
        if(bg === 'black') return r <= 25 && g <= 25 && b <= 25;
        return g >= minGreen && g > Math.max(r,b)*dominance && (g-r) >= greenMargin && (g-b) >= greenMargin && r <= maxRed && b <= maxBlue;
      }
      function nearTransparent(x, y, radius = 1){
        for(let yy = Math.max(minY, y-radius); yy <= Math.min(maxY, y+radius); yy++)
          for(let xx = Math.max(minX, x-radius); xx <= Math.min(maxX, x+radius); xx++)
            if(isTransparent(xx, yy)) return true;
        return false;
      }
      let removed = 0;
      for(let y = 0; y < src.height; y++) for(let x = 0; x < src.width; x++)
        if(x < minX || x > maxX || y < minY || y > maxY) d[idx(x,y)+3] = 0;
      for(let y = minY; y <= maxY; y++) for(let x = minX; x <= maxX; x++){
        const i = idx(x, y); if(d[i+3] > 10 && isKey(i)){ d[i+3] = 0; removed++; }
      }
      if(soften && bg === 'green'){
        for(let y = minY; y <= maxY; y++) for(let x = minX; x <= maxX; x++){
          const i = idx(x, y);
          if(d[i+3] > 10 && nearTransparent(x, y, 1) && d[i+1] > d[i]*1.08 && d[i+1] > d[i+2]*1.08)
            d[i+1] = Math.max(d[i], d[i+2]);
        }
        // Stronger cleanup pass for leftover green spill under tyres / lower body.
        for(let y = minY; y <= maxY; y++) for(let x = minX; x <= maxX; x++){
          const i = idx(x, y);
          if(d[i+3] <= 10) continue;
          const r = d[i], g = d[i+1], b = d[i+2];
          if(nearTransparent(x, y, 2) && g >= 35 && g > Math.max(r,b) * 1.03 && (g-r) >= 6 && (g-b) >= 6){
            d[i+3] = 0; removed++;
          } else if(nearTransparent(x, y, 2) && g > r * 1.04 && g > b * 1.04) {
            d[i+1] = Math.max(r, b);
          }
        }
      }
      let bMinX = src.width, bMinY = src.height, bMaxX = 0, bMaxY = 0;
      for(let y = minY; y <= maxY; y++) for(let x = minX; x <= maxX; x++)
        if(d[idx(x,y)+3] > 10){ if(x<bMinX)bMinX=x; if(y<bMinY)bMinY=y; if(x>bMaxX)bMaxX=x; if(y>bMaxY)bMaxY=y; }
      if(bMaxX <= bMinX || bMaxY <= bMinY){ reject(new Error('No pixels after BG removal')); return; }
      const pad = Number(payload.padding ?? 12);
      const fMinX = Math.max(0, bMinX - pad), fMinY = Math.max(0, bMinY - pad);
      const fMaxX = Math.min(src.width-1, bMaxX + pad), fMaxY = Math.min(src.height-1, bMaxY + pad);
      const fW = fMaxX - fMinX + 1, fH = fMaxY - fMinY + 1;
      sctx.putImageData(imageData, 0, 0);
      const out = document.createElement('canvas'); out.width = fW; out.height = fH;
      out.getContext('2d').drawImage(src, fMinX, fMinY, fW, fH, 0, 0, fW, fH);
      const png = out.toDataURL('image/png');
      const fullPng = src.toDataURL('image/png');
      resolve({
        dataUrl: png,
        imageBase64: png.split(',')[1],
        fullDataUrl: fullPng,
        autoBounds: { x: fMinX, y: fMinY, w: fW, h: fH },
        naturalWidth: src.width,
        naturalHeight: src.height,
        meta: { removedPixels: removed, width: fW, height: fH }
      });
    };
    img.onerror = () => reject(new Error('Unable to load screenshot'));
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

function renderCategories(){
  $('#vehicle-class-warp').html('');
  try { $('#vehicle-class-carousel').slick('slickRemove', null, null, true); } catch(e) {}
  const vehicles = (data && data.vehicles) || [];
  if(!vehicles.length){
    $('#vehicle-class-warp').append(`<div class="empty-shop">No vehicles are enabled yet.<br>Use /vehicleadmin to add cars to the server catalog.</div>`);
    return;
  }
  for(const vehiclesInfo of vehicles){
    const cls = vehicles.length >= 8 ? 'vehicle-class' : 'vehicle-class5';
    const html = `<div class="${cls}" data-title="${safe(vehiclesInfo.title)}">${safe(vehiclesInfo.title)}</div>`;
    if(vehicles.length >= 8){ try { $('#vehicle-class-carousel').slick('slickAdd', html); } catch(e) { $('#vehicle-class-warp').append(html); } }
    else $('#vehicle-class-warp').append(html);
  }
}

function renderVehicleCategory(title){
  $('#vehicle-carousel').slick('slickRemove', null, null, true);
  $('#vehicle-warp').html('');
  $('#colors-container').html('');
  const vehiclesInfo = ((data && data.vehicles) || []).find(v => v.title === title);
  if(!vehiclesInfo) return;

  $('#vehicle-class-title-container, #vehicle-class-container').fadeOut();
  $('#vehicle-container, #title-container, #statistics-container').fadeIn();
  $('#vehicle-carousel').slick('refresh');
  $('#title-vehiclecategory').text(title);

  for(const vehicleBtn of vehiclesInfo.buttons || []){
    const buyable = vehicleBtn.buyable === true || vehicleBtn.buyable === 'true';
    const testEnabled = vehicleBtn.testDriveEnabled !== false && vehicleBtn.testDriveEnabled !== 'false';
    const status = buyable ? money(vehicleBtn.costs) : 'Event / Task only';
    const img = vehicleBtn.image
      ? `<img class="vehicle-card-img" src="${safe(vehicleBtn.image)}" alt="${safe(vehicleBtn.name)}" />`
      : `<div class="vehicle-card-img no-img">No Image</div>`;
    const item = `
      <div class="${(vehiclesInfo.buttons || []).length > 5 ? 'category' : 'category5'} ${buyable ? '' : 'server-only'}"
        data-name="${safe(vehicleBtn.name)}" data-model="${safe(vehicleBtn.model)}" data-costs="${Number(vehicleBtn.costs || 0)}"
        data-stock="${safe(vehicleBtn.maxStock || '')}" data-buyable="${buyable}" data-trunk="${Number(vehicleBtn.trunkLevel || 1)}"
        data-test-enabled="${testEnabled}" data-test-timer="${Number(vehicleBtn.testDriveTimer || (data && data.testDrive && data.testDrive.testDriveTimer) || 60)}"
        data-test-cost="${Number(vehicleBtn.testDriveCost || (data && data.testDrive && data.testDrive.testDriveCost) || 0)}">
        ${img}
        <span>${safe(vehicleBtn.name)}</span>
        <div class="category-price">${status}</div>
      </div>`;
    if((vehiclesInfo.buttons || []).length > 5){ try { $('#vehicle-carousel').slick('slickAdd', item); } catch(e) { $('#vehicle-warp').append(item); } }
    else $('#vehicle-warp').append(item);
  }

  for(const vehicleColor of (data.colors || [])){
    $('#colors-container').append(`
      <div class="color" data-gtacolor="${vehicleColor.gtaColor}" data-colorname="${safe(vehicleColor.colorName)}"
        data-colorr="${vehicleColor.r}" data-colorg="${vehicleColor.g}" data-colorb="${vehicleColor.b}"
        style="background-color: rgb(${vehicleColor.r},${vehicleColor.g},${vehicleColor.b})">
        <div class="color-icon"><i class="fas fa-check-circle"></i></div>
      </div>`);
  }
  vehiclesCategory = true;
}

$(document).on('click', '.vehicle-class,.vehicle-class5', function(){ renderVehicleCategory($(this).data('title')); });

$(document).on('click', '.color', function(){
  const colorR = $(this).data('colorr');
  const colorG = $(this).data('colorg');
  const colorB = $(this).data('colorb');
  const colorName = $(this).data('colorname');
  const gtaColor = $(this).data('gtacolor');
  details.color = colorName;
  details.r = colorR;
  details.g = colorG;
  details.b = colorB;
  details.gtaColor = gtaColor;
  $('.color-icon').fadeOut();
  $(this).children().fadeIn();
  post('changeColor', { colorR, colorG, colorB });
});

$(document).on('click', '.category, .category5', function(){
  $('.category, .category5').css('border-bottom', '3px solid #f0f0f0');
  $(this).css('border-bottom', '3px solid #f5c542');
  const model = String($(this).data('model'));
  const name = String($(this).data('name'));
  const costs = Number($(this).data('costs') || 0);
  const stock = String($(this).data('stock') || '');
  const buyable = String($(this).data('buyable')) === 'true';
  const trunkLevel = Number($(this).data('trunk') || 1);
  const testDriveEnabled = String($(this).data('test-enabled')) !== 'false';
  const testDriveTimer = Number($(this).data('test-timer') || (data && data.testDrive && data.testDrive.testDriveTimer) || 60);
  const testDriveCost = Number($(this).data('test-cost') || (data && data.testDrive && data.testDrive.testDriveCost) || 0);
  $('#title-vehiclename').text(name);
  $('#title-stock').text(buyable ? ('Status: Buyable | Trunk Level: ' + trunkLevel) : ('Status: Event / Task only | Trunk Level: ' + trunkLevel));
  $('#title-price').text(buyable ? ('Price: ' + money(costs)) : 'Price: Not for sale');
  $('#buy-btn').toggleClass('disabled-buy', !buyable).find('.btn-text').text(buyable ? 'Buy Vehicle' : 'Event / Task Only');
  $('#buy-btn, #hide-button, #slider-container, #btn-container').fadeIn();
  $('#test-btn').toggle(testDriveEnabled === true);
  vehicleDisplay = true;
  // Allow mouse orbit + scroll-zoom to inspect the car immediately, without
  // having to press the "Preview" button first.
  inspect = true;
  details = { buyer: data.buyer, price: money(costs), numberprice: costs, vehicle: name, model, color: 'White', r: 255, g: 255, b: 255, gtaColor: 111, stock, buyable, trunkLevel, testDriveEnabled, testDriveTimer, testDriveCost };
  post('spawnVehicle', { model });
});

$('#buy-btn').click(function(){
  if(!details.buyable){ showToast('This vehicle is event/task only.'); return; }
  onBuyPage = true;
  $('#buy-text').text('Are you sure you want to buy this vehicle?');
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
  onBuyPage = false;
  $('#buy-vehicle, #test-drive-container').css('top', '-600px');
  $('#pointer').css('pointer-events','unset');
  $('#main').hide();
  $('#buy-vehicle, #test-drive-container').css('top','-600px').hide();
});
$('#test-accept').click(function(){ post('testDrive', { timer: Number(details.testDriveTimer || (data && data.testDrive && data.testDrive.testDriveTimer) || 60), details }); });
$('#buy').click(function(){ if(details.gtaColor === undefined) details.gtaColor = 111; post('buyVehicle', { details }); });

$('#vehicle-carousel').slick({ slidesToShow: 5, dots:true, centerMode: true, centerPadding: '0px' });
$('#vehicle-class-carousel').slick({ slidesToShow: 7, dots:true, centerMode: true, centerPadding: '0px' });

document.onkeydown = (e) => {
  if(e.key !== 'Escape') return;
  if($('#crop-modal').is(':visible')){
    post('cancelVehicleImage');
    closeCropModal();
    return;
  }
  if($('#admin-panel').is(':visible')){ post('adminClose'); return; }
  if(onBuyPage){
    onBuyPage = false;
    $('#buy-vehicle, #test-drive-container').css('top', '-600px');
    $('#pointer').css('pointer-events','unset');
    $('#main').hide();
  $('#buy-vehicle, #test-drive-container').css('top','-600px').hide();
    return;
  }
  if(vehiclesCategory){ backToCategories(); }
  else { $('#vehicle-class-title-container, #vehicle-class-container').fadeOut(); post('closeVehicleShop'); }
};

function backToCategories(){
  vehiclesCategory = false;
  $('#hide-button').css('top','46%').text('Preview');
  try { $('#vehicle-carousel').slick('slickRemove', null, null, true); } catch(e) {}
  $('#vehicle-warp, #colors-container').html('');
  $('#vehicle-container, #title-container, #btn-container, #hide-button, #slider-container, #colors-button, #statistics-container').fadeOut();
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
document.onmousedown = function(e){ if(inspect && vehicleDisplay && !down && e.button === 0){ down = true; post('mousedown'); } };
document.onmouseup = function(){ if(inspect && down){ post('mouseup'); down = false; } };
window.onmousewheel = function(e){ if(inspect){ post(e.wheelDelta < 0 ? 'downscroll' : 'upscroll'); } };

function startTimer(duration){
  if(testTimerInterval){ clearInterval(testTimerInterval); testTimerInterval = null; }
  let timer = Math.max(1, Number(duration) || 60);
  const tick = function(){
    const minutes = parseInt(timer / 60, 10);
    const seconds = parseInt(timer % 60, 10);
    $('#timer').text((minutes < 10 ? '0' : '') + minutes + ':' + (seconds < 10 ? '0' : '') + seconds);
    if((timer < duration/2) && (timer > duration/4)) $('#timer').css('color', '#ffeb3b');
    else if(timer < duration/4) $('#timer').css('color', '#f44336');
    if(--timer < 0){ clearInterval(testTimerInterval); testTimerInterval = null; }
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
  stopAllAnimations();
  if(testTimerInterval){ clearInterval(testTimerInterval); testTimerInterval = null; }
  $('body').removeClass('store-active admin-active crop-review-open capture-hidden');
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
  $('#vehicle-container, #color-warp, #title-container, #btn-container, #hide-button, #slider-container, #colors-button, #statistics-container, #vehicle-class-title-container, #vehicle-class-container').hide();
  vehiclesCategory = false; vehicleDisplay = false; inspect = false; onBuyPage = false; hideDisplay = false;
}

function hideAllElements(){
  stopAllAnimations();
  if(testTimerInterval){ clearInterval(testTimerInterval); testTimerInterval = null; }
  $('body').removeClass('store-active admin-active');
  closeCropModal(false);
  $('#main').hide();
  $('#buy-vehicle, #test-drive-container').css('top','-600px').hide();
  $('#hide-button').css('top','46%').text('Preview');
  try { $('#vehicle-carousel').slick('slickRemove', null, null, true); } catch(e) {}
  $('#vehicle-warp, #colors-container').html('');
  $('#vehicle-container, #color-warp, #title-container, #btn-container, #hide-button, #slider-container, #colors-button, #statistics-container, #vehicle-class-title-container, #vehicle-class-container').fadeOut();
  vehiclesCategory = false; vehicleDisplay = false; inspect = false;
}

function openAdminPanel(){ hideAllElements(); $('body').addClass('admin-active').removeClass('store-active'); $('#admin-panel').fadeIn(); renderAdmin(); }
function closeAdminPanel(send){ $('body').removeClass('admin-active'); $('#admin-panel').hide(); if(send) post('adminClose'); }

function renderAdmin(){
  const byCatalog = catalogByModel();
  const filter = String($('#admin-search').val() || '').toLowerCase();
  $('#admin-source-select').html('');
  $('#admin-list').html('');
  const merged = [...adminSourceVehicles];
  for(const row of adminCatalog){ if(!merged.find(v => String(v.model).toLowerCase() === String(row.model).toLowerCase())) merged.push({ model: row.model, label: row.label, category: row.category, price: row.price, trunkLevel: row.trunkLevel }); }
  merged.sort((a,b) => String(a.label).localeCompare(String(b.label)));
  for(const v of merged){
    const row = byCatalog[String(v.model).toLowerCase()];
    const hay = `${v.model} ${v.label} ${v.category} ${statusFor(row)}`.toLowerCase();
    if(filter && !hay.includes(filter)) continue;
    $('#admin-source-select').append(`<option value="${safe(v.model)}">${safe(v.label)} (${safe(v.model)}) — ${safe(v.category || 'Custom')}</option>`);
    const img = row && row.image ? `<img class="admin-car-thumb" src="${safe(row.image)}" />` : `<div class="admin-car-thumb noimg">No img</div>`;
    $('#admin-list').append(`
      <div class="admin-car ${statusClass(row)}" data-model="${safe(v.model)}">
        ${img}
        <div class="admin-car-meta"><b>${safe(v.label)}</b><span>${safe(v.model)} • ${safe(v.category || 'Custom')}</span></div>
        <em>${statusFor(row)}</em>
      </div>`);
  }
  if(!$('#admin-source-select').val() && merged.length) $('#admin-source-select').val(merged[0].model);
  fillAdminForm($('#admin-source-select').val());
}

function fillAdminForm(model){
  model = String(model || '').toLowerCase();
  const source = adminSourceVehicles.find(v => String(v.model).toLowerCase() === model) || {};
  const row = catalogByModel()[model] || {};
  $('#admin-model').val(row.model || source.model || model);
  $('#admin-label').val(row.label || source.label || source.name || model);
  $('#admin-category').val(row.category || source.category || 'Custom');
  $('#admin-price').val(row.price ?? source.price ?? 0);
  $('#admin-trunk').val(row.trunkLevel ?? source.trunkLevel ?? 1);
  const statusMode = row.availableStore === true ? 'store' : (row.availableServer === true ? 'server' : 'hidden');
  $('#admin-status-mode').val(row.model ? statusMode : 'hidden');
  const td = (row.metadata && row.metadata.testDrive) || {};
  $('#admin-test-enabled').prop('checked', td.enabled !== false);
  $('#admin-test-duration').val(td.duration ?? (data && data.testDrive && data.testDrive.testDriveTimer) ?? 60);
  $('#admin-test-cost').val(td.cost ?? (data && data.testDrive && data.testDrive.testDriveCost) ?? 0);
  $('#admin-current-status').text(statusFor(row.model ? row : null));
  if((row.model || source.model || model) && $('#admin-panel').is(':visible')) post('adminPreviewVehicle', { model: row.model || source.model || model });
  const preview = $('#admin-image-preview');
  if(row.image){ preview.attr('src', row.image).show(); }
  else { preview.removeAttr('src').hide(); }
}

$(document).on('input', '#admin-search', renderAdmin);
$(document).on('change', '#admin-source-select', function(){ fillAdminForm($(this).val()); });
$(document).on('click', '.admin-car', function(){ $('#admin-source-select').val($(this).data('model')); fillAdminForm($(this).data('model')); });
$(document).on('click', '#admin-save', function(){
  const mode = String($('#admin-status-mode').val() || 'hidden');
  const availableStore = mode === 'store';
  const availableServer = mode === 'server' || availableStore;
  const payload = {
    model: $('#admin-model').val(), label: $('#admin-label').val(), category: $('#admin-category').val(),
    price: Number($('#admin-price').val() || 0), trunkLevel: Number($('#admin-trunk').val() || 1),
    availableServer, availableStore,
    testDriveEnabled: $('#admin-test-enabled').is(':checked'),
    testDriveTimer: Number($('#admin-test-duration').val() || 60),
    testDriveCost: Number($('#admin-test-cost').val() || 0)
  };
  post('adminSaveVehicle', payload);
});
$(document).on('click', '#dealer-dialog-store', function(){ post('dealerDialogStore'); });
$(document).on('click', '#dealer-dialog-close', function(){ post('dealerDialogClose'); });
$(document).on('click', '#admin-disable', function(){ post('adminDisableVehicle', { model: $('#admin-model').val() }); });
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
$(document).on('click', '#admin-refresh', function(){ post('adminRefresh'); });
$(document).on('click', '#admin-close', function(){ closeAdminPanel(true); });
