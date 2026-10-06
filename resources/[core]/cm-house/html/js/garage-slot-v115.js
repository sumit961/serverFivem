/*
   cm-house | garage parking-slot UI v1.3.0
   Visual redesign only: all actions still use the existing NUI callbacks.
*/
(function () {
  'use strict';

  var RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  var root = document.getElementById('garage-slot');
  var current = null;
  var selectedId = null;
  var busy = false;
  var rankBusy = false;
  var activeFilter = 'all';
  var searchQuery = '';
  var confirmRoot = document.getElementById('garage-confirm');
  var confirmOpen = false;

  function el(id) { return document.getElementById(id); }
  function setText(id, value) { var node = el(id); if (node) node.textContent = value == null ? '' : String(value); }
  function clean(value) {
    var normalized = String(value == null ? '' : value).toLowerCase();
    if (typeof normalized.normalize === 'function') normalized = normalized.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    return normalized.replace(/[^a-z0-9]+/g, ' ').trim();
  }
  function post(name, body, done) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', 'https://' + RES + '/' + name, true);
    xhr.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      var response = {};
      try { response = xhr.responseText ? JSON.parse(xhr.responseText) : {}; } catch (_) {}
      if (typeof done === 'function') done(response);
    };
    xhr.onerror = function () { if (typeof done === 'function') done({}); };
    try { xhr.send(JSON.stringify(body || {})); } catch (_) { if (typeof done === 'function') done({}); }
  }
  function closeConfirm(send, confirmed) {
    if (!confirmRoot || !confirmOpen) return;
    confirmOpen = false;
    confirmRoot.hidden = true;
    confirmRoot.style.display = 'none';
    confirmRoot.setAttribute('aria-hidden', 'true');
    if (send) post('garageSlot:confirm', { confirmed: confirmed === true });
  }
  function closeLocal(send) {
    closeConfirm(false);
    if (root) { root.classList.remove('on'); root.style.display = 'none'; root.setAttribute('aria-hidden', 'true'); }
    current = null;
    selectedId = null;
    busy = false;
    if (send) post('garageSlot:close', {});
  }
  function openConfirm(data) {
    data = data || {};
    if (window.CMUI && typeof window.CMUI.confirm === 'function') {
      window.CMUI.confirm({
        title: data.title || 'Confirm action',
        message: data.content || 'Are you sure?',
        confirmText: data.confirmLabel || 'Confirm',
        cancelText: data.cancelLabel || 'Cancel',
        danger: data.tone === 'danger'
      }).then(function (confirmed) { post('garageSlot:confirm', { confirmed: confirmed === true }); });
      return;
    }
    if (!confirmRoot) return;
    setText('gc-title', data.title || 'Confirm action');
    setText('gc-text', data.content || 'Are you sure?');
    setText('gc-ok', data.confirmLabel || 'Confirm');
    setText('gc-cancel', data.cancelLabel || 'Cancel');
    confirmRoot.setAttribute('data-tone', data.tone === 'danger' ? 'danger' : 'cyan');
    confirmRoot.hidden = false;
    confirmRoot.style.display = 'grid';
    confirmRoot.setAttribute('aria-hidden', 'false');
    confirmOpen = true;
    var cancel = el('gc-cancel');
    if (cancel) cancel.focus();
  }
  function imageAllowed(image) { return !!(image && /^(nui|https?):\/\//i.test(String(image))); }
  function vehicleState(vehicle) {
    if (!vehicle) return { key: 'blocked', label: 'UNAVAILABLE', tone: 'blocked' };
    if (vehicle.rankAllowed === false) return { key: 'blocked', label: 'ACCESS RESTRICTED', tone: 'blocked' };
    var code = String(vehicle.statusCode || '').toUpperCase();
    if (code === 'PUBLIC_PARKING') return { key: 'blocked', label: 'PUBLIC PARKING', tone: 'blocked' };
    if (vehicle.canPark) return { key: 'available', label: 'AVAILABLE', tone: 'available', action: 'park', actionLabel: 'ASSIGN HERE' };
    if (vehicle.canCall) return { key: 'assigned', label: vehicle.inGarage ? 'PARKED' : 'ASSIGNED', tone: 'assigned', action: 'call', actionLabel: 'MOVE HERE' };
    var danger = code === 'IMPOUNDED' || code === 'POLICE_SEIZED';
    return { key: vehicle.assigned || vehicle.parked ? 'assigned' : 'blocked', label: vehicle.statusLabel || 'UNAVAILABLE', tone: danger ? 'danger' : 'blocked' };
  }
  function vehicleLocation(vehicle) {
    if (!vehicle) return 'NO VEHICLE SELECTED';
    if (String(vehicle.statusCode || '').toUpperCase() === 'PUBLIC_PARKING') return 'PUBLIC PARKING';
    if (vehicle.parkedHouseLabel) return String(vehicle.parkedHouseLabel) + (vehicle.parkedSlotIndex ? ' · SPACE ' + String(vehicle.parkedSlotIndex) : '');
    if (vehicle.canPark) return 'READY TO ASSIGN';
    return vehicle.unavailableReason || 'NOT AVAILABLE FOR THIS SPACE';
  }
  function humanizeLocationState(value) {
    var code = String(value || '').toUpperCase();
    var labels = {
      HOUSE_GARAGE: 'HOUSE GARAGE',
      PUBLIC_PARKING: 'PUBLIC PARKING',
      IN_WORLD: 'IN WORLD',
      OUTSIDE: 'IN WORLD',
      STORED: 'STORED',
      STORED_ELSEWHERE: 'STORED ELSEWHERE',
      RESERVED_OUTSIDE: 'IN WORLD'
    };
    return labels[code] || code.replace(/_/g, ' ');
  }
  function accessRequirement(vehicle) {
    if (!vehicle || vehicle.isFamilyVehicle !== true) return null;
    var name = String(vehicle.requiredRankName || '').trim();
    var tier = Number(vehicle.requiredTier);
    if (!name && !tier) return null;
    var label = name || ('TIER ' + String(tier));
    return { value: label.toUpperCase() + '+', compact: 'ACCESS · ' + label.toUpperCase() + '+' };
  }
  function vehicleById(id) {
    var vehicles = current && Array.isArray(current.vehicles) ? current.vehicles : [];
    for (var i = 0; i < vehicles.length; i += 1) if (Number(vehicles[i].id) === Number(id)) return vehicles[i];
    return current && current.current && Number(current.current.id) === Number(id) ? current.current : null;
  }
  function rankControl(vehicle) {
    if (!vehicle || vehicle.showFamilyRank !== true) return null;
    var wrap = document.createElement('label');
    wrap.className = 'garage-vehicle-rank';
    var caption = document.createElement('span');
    caption.className = 'garage-vehicle-rank__label';
    caption.textContent = 'DRIVER ACCESS';
    var select = document.createElement('select');
    select.className = 'garage-vehicle-rank__select';
    select.setAttribute('data-family-rank', '1');
    select.setAttribute('data-vehicle-id', String(vehicle.id));
    select.disabled = vehicle.canManageVehicleRank !== true;
    select.title = select.disabled ? 'Your family rank cannot change vehicle access' : 'Minimum family rank';
    var options = Array.isArray(vehicle.rankOptions) ? vehicle.rankOptions.slice() : [];
    options.sort(function (a, b) { return Number(b.tier || 0) - Number(a.tier || 0); });
    for (var i = 0; i < options.length; i += 1) {
      var option = document.createElement('option');
      option.value = String(options[i].tier);
      option.textContent = String(options[i].name || ('Tier ' + options[i].tier));
      option.selected = Number(options[i].tier) === Number(vehicle.requiredTier);
      select.appendChild(option);
    }
    if (!options.length) {
      var fallback = document.createElement('option');
      fallback.value = String(vehicle.requiredTier || '');
      fallback.textContent = vehicle.requiredRankName || ('Tier ' + String(vehicle.requiredTier || '?'));
      fallback.selected = true;
      select.appendChild(fallback);
    }
    wrap.appendChild(caption); wrap.appendChild(select);
    return wrap;
  }
  function actionButton(label, action, vehicle, extraClass) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'garage-slot-detail__action' + (extraClass ? ' ' + extraClass : '');
    button.setAttribute('data-garage-act', action);
    button.setAttribute('data-vehicle-id', String(vehicle.id));
    button.setAttribute('data-vehicle-label', vehicle.label || vehicle.model || 'Vehicle');
    button.setAttribute('data-parking-label', vehicleLocation(vehicle));
    button.textContent = label;
    return button;
  }
  function renderCard(vehicle) {
    var state = vehicleState(vehicle);
    var card = document.createElement('button');
    card.type = 'button';
    card.className = 'garage-vehicle-row garage-vehicle-row--' + state.tone;
    card.setAttribute('data-vehicle-id', String(vehicle.id));
    card.setAttribute('data-filter-state', state.key);
    card.setAttribute('aria-pressed', Number(vehicle.id) === Number(selectedId) ? 'true' : 'false');
    if (Number(vehicle.id) === Number(selectedId)) card.classList.add('is-selected');

    var top = document.createElement('span'); top.className = 'garage-vehicle-row__top';
    var status = document.createElement('span'); status.className = 'garage-vehicle-row__status garage-vehicle-row__status--' + state.tone; status.textContent = state.label;
    var plate = document.createElement('span'); plate.className = 'garage-vehicle-row__plate'; plate.textContent = vehicle.licenseNumber || vehicle.plate || 'NO PLATE';
    top.appendChild(status); top.appendChild(plate); card.appendChild(top);

    var media = document.createElement('span'); media.className = 'garage-vehicle-row__media';
    if (imageAllowed(vehicle.image)) {
      var image = document.createElement('img'); image.className = 'garage-vehicle-image'; image.src = String(vehicle.image); image.alt = vehicle.label || vehicle.model || 'Vehicle'; image.loading = 'lazy';
      image.onerror = function () { media.classList.add('is-missing'); image.remove(); };
      media.appendChild(image);
    } else media.classList.add('is-missing');
    var fallback = document.createElement('span'); fallback.className = 'garage-vehicle-row__fallback'; fallback.textContent = 'CM'; media.appendChild(fallback); card.appendChild(media);

    var copy = document.createElement('span'); copy.className = 'garage-vehicle-row__copy';
    var name = document.createElement('strong'); name.textContent = (vehicle.label || vehicle.model || 'Vehicle').toUpperCase(); name.title = name.textContent;
    var model = document.createElement('span'); model.className = 'garage-vehicle-row__model'; model.textContent = vehicle.model || 'ROAD VEHICLE';
    var location = document.createElement('span'); location.className = 'garage-vehicle-row__location'; location.textContent = vehicleLocation(vehicle); location.title = location.textContent;
    copy.appendChild(name); copy.appendChild(model); copy.appendChild(location);
    var access = accessRequirement(vehicle);
    if (access) { var accessLine = document.createElement('span'); accessLine.className = 'garage-vehicle-row__access' + (vehicle.rankAllowed === false ? ' garage-vehicle-row__access--restricted' : ''); accessLine.textContent = access.compact; copy.appendChild(accessLine); }
    card.appendChild(copy);
    var marker = document.createElement('span'); marker.className = 'garage-vehicle-row__select-mark'; marker.textContent = '›'; card.appendChild(marker);
    return card;
  }
  function visibleVehicles() {
    var vehicles = current && Array.isArray(current.vehicles) ? current.vehicles : [];
    var result = [];
    for (var i = 0; i < vehicles.length; i += 1) {
      var state = vehicleState(vehicles[i]);
      var haystack = clean([vehicles[i].label, vehicles[i].model, vehicles[i].plate, vehicles[i].licenseNumber].join(' '));
      if (activeFilter !== 'all' && state.key !== activeFilter) continue;
      if (searchQuery && haystack.indexOf(searchQuery) === -1 && haystack.replace(/\s/g, '').indexOf(searchQuery.replace(/\s/g, '')) === -1) continue;
      result.push(vehicles[i]);
    }
    return result;
  }
  function syncSearchUi() { var input = el('gs-search'); var clear = el('gs-search-clear'); if (clear) clear.hidden = !input || !input.value.length; }
  function renderVehicleList() {
    var list = el('gs-list'); if (!list) return;
    while (list.firstChild) list.removeChild(list.firstChild);
    var all = current && Array.isArray(current.vehicles) ? current.vehicles : [];
    var shown = visibleVehicles();
    for (var i = 0; i < shown.length; i += 1) list.appendChild(renderCard(shown[i]));
    setText('gs-count', shown.length === all.length ? shown.length : shown.length + '/' + all.length);
    var empty = el('gs-empty'); if (empty) empty.hidden = shown.length !== 0;
  }
  function renderDetail(vehicle) {
    var detail = el('gs-detail');
    if (!detail) return;
    var state = vehicleState(vehicle);
    var occupied = current && current.occupied === true;
    var isCurrent = !!(current && current.current && vehicle && Number(current.current.id) === Number(vehicle.id));
    setText('gs-detail-status', vehicle ? state.label : 'SELECT A VEHICLE');
    setText('gs-detail-class', vehicle && vehicle.isFamilyVehicle ? 'FAMILY VEHICLE' : 'ROAD VEHICLE');
    setText('gs-detail-plate', vehicle ? (vehicle.licenseNumber || vehicle.plate || 'NO PLATE') : '—');
    setText('gs-detail-name', vehicle ? (vehicle.label || vehicle.model || 'Vehicle').toUpperCase() : 'No vehicle selected');
    setText('gs-detail-location', vehicle ? vehicleLocation(vehicle) : 'Select a vehicle card to inspect its real garage status.');
    setText('gs-detail-state', vehicle ? state.label : '—');
    setText('gs-detail-location-state', vehicle ? humanizeLocationState(vehicle.locationState || (vehicle.inGarage ? 'HOUSE_GARAGE' : 'OUTSIDE')) : '—');
    var access = accessRequirement(vehicle);
    var accessNode = el('gs-detail-access');
    if (accessNode) accessNode.setAttribute('data-restricted', vehicle && vehicle.rankAllowed === false ? '1' : '0');
    setText('gs-detail-access', vehicle ? (access ? access.value : (vehicle.isFamilyVehicle ? 'FAMILY ACCESS' : 'PERSONAL')) : '—');
    var image = el('gs-detail-image'); var fallback = el('gs-detail-fallback');
    if (image) {
      image.hidden = true; image.removeAttribute('src');
      image.onerror = function () { image.hidden = true; if (fallback) fallback.hidden = false; };
      if (vehicle && imageAllowed(vehicle.image)) { image.src = String(vehicle.image); image.alt = vehicle.label || vehicle.model || 'Selected vehicle'; image.hidden = false; if (fallback) fallback.hidden = true; }
      else if (fallback) fallback.hidden = false;
    }
    var rank = el('gs-detail-rank');
    if (rank) { while (rank.firstChild) rank.removeChild(rank.firstChild); var control = rankControl(vehicle); rank.hidden = !control; if (control) rank.appendChild(control); }
    var actions = el('gs-detail-actions');
    if (!actions) return;
    while (actions.firstChild) actions.removeChild(actions.firstChild);
    if (!vehicle) return;
    if (occupied) {
      if (isCurrent) {
        actions.appendChild(actionButton('RECALL VEHICLE', 'recall', vehicle, 'garage-slot-detail__action--cyan'));
        actions.appendChild(actionButton('REMOVE ASSIGNMENT', 'remove', vehicle, 'garage-slot-detail__action--danger'));
      } else {
        var occupiedNote = document.createElement('span'); occupiedNote.className = 'garage-slot-detail__notice'; occupiedNote.textContent = 'PARKING SPACE OCCUPIED · INSPECT ONLY'; actions.appendChild(occupiedNote);
      }
      return;
    }
    if (state.action) actions.appendChild(actionButton(String(current && current.slotIndex ? state.actionLabel + ' · SPACE ' + current.slotIndex : state.actionLabel), state.action, vehicle, 'garage-slot-detail__action--primary'));
    else {
      var note = document.createElement('span'); note.className = 'garage-slot-detail__notice';
      note.textContent = state.label === 'PUBLIC PARKING' ? 'PUBLIC PARKING · NOT ELIGIBLE' : (vehicle.rankAllowed === false ? 'FAMILY ACCESS TIER REQUIRED' : (vehicle.unavailableReason || 'ACTION UNAVAILABLE'));
      actions.appendChild(note);
    }
  }
  function selectVehicle(id, focus) {
    var vehicle = vehicleById(id);
    if (!vehicle) return;
    selectedId = Number(vehicle.id);
    renderVehicleList();
    renderDetail(vehicle);
    if (focus) {
      var selected = root && root.querySelector('[data-vehicle-id="' + String(selectedId) + '"]');
      if (selected) selected.focus();
    }
  }
  function render(data) {
    if (!root) throw new Error('Missing #garage-slot root');
    current = data || {};
    var occupied = current.occupied === true;
    var vehicles = Array.isArray(current.vehicles) ? current.vehicles : [];
    setText('gs-eyebrow', 'ASSIGNMENT & GARAGE MANAGEMENT');
    setText('gs-title', ('PARKING SPACE ' + String(current.slotIndex || '?')).toUpperCase());
    setText('gs-zone', current.isFamilyGarage ? (current.familyName || 'FAMILY GARAGE') : (current.garageLabel || 'GARAGE'));
    setText('gs-capacity', String(current.occupiedCount || 0) + ' / ' + String(current.capacity || 0) + ' OCCUPIED');
    setText('gs-subtitle', occupied ? 'Review the assigned vehicle or inspect your eligible fleet.' : 'Choose an eligible vehicle for this parking space.');
    var symbol = el('gs-symbol'); if (symbol) { symbol.setAttribute('data-occupied', occupied ? '1' : '0'); symbol.textContent = occupied ? '!' : 'P'; }
    setText('gs-list-title', current.isFamilyGarage ? 'FAMILY ROAD VEHICLES' : 'YOUR ROAD VEHICLES');
    activeFilter = 'all'; searchQuery = ''; selectedId = current.current && current.current.id ? Number(current.current.id) : (vehicles[0] ? Number(vehicles[0].id) : null);
    var search = el('gs-search'); if (search) search.value = '';
    syncSearchUi();
    var filters = root.querySelectorAll('[data-garage-filter]');
    for (var i = 0; i < filters.length; i += 1) filters[i].classList.toggle('is-active', filters[i].getAttribute('data-garage-filter') === 'all');
    renderVehicleList();
    renderDetail(vehicleById(selectedId));
    root.style.display = 'grid'; root.classList.add('on'); root.setAttribute('aria-hidden', 'false');
    var token = current.requestId == null ? '' : String(current.requestId);
    window.setTimeout(function () { var rect = root.getBoundingClientRect(); post('garageSlot:rendered', { requestId: token, visible: rect.width > 0 && rect.height > 0 }); }, 35);
  }
  function dispatchAction(node) {
    var action = node && node.getAttribute('data-garage-act');
    if (!action || action === 'close' || busy) return;
    busy = true;
    var actionNodes = root.querySelectorAll('[data-garage-act]');
    for (var i = 0; i < actionNodes.length; i += 1) actionNodes[i].disabled = true;
    var body = { action: action };
    var id = node.getAttribute('data-vehicle-id'); if (id) body.vehicleId = Number(id);
    var label = node.getAttribute('data-vehicle-label'); if (label) body.vehicleLabel = label;
    var parking = node.getAttribute('data-parking-label'); if (parking) body.parkingLabel = parking;
    if (action === 'recall' && current && current.current) body.vehicleId = Number(current.current.id);
    post('garageSlot:action', body, function (response) {
      if (response && response.ok) closeLocal(false);
      busy = false;
      for (var j = 0; j < actionNodes.length; j += 1) actionNodes[j].disabled = false;
    });
  }
  if (root) root.addEventListener('click', function (event) {
    var confirmButton = event.target.closest && event.target.closest('[data-confirm]');
    if (confirmButton) { closeConfirm(true, confirmButton.getAttribute('data-confirm') === 'ok'); return; }
    if (confirmOpen) return;
    var clear = event.target.closest && event.target.closest('#gs-search-clear');
    if (clear) { var input = el('gs-search'); if (input) { input.value = ''; input.focus(); } searchQuery = ''; syncSearchUi(); renderVehicleList(); return; }
    var filter = event.target.closest && event.target.closest('[data-garage-filter]');
    if (filter) {
      activeFilter = filter.getAttribute('data-garage-filter') || 'all';
      var nodes = root.querySelectorAll('[data-garage-filter]'); for (var f = 0; f < nodes.length; f += 1) nodes[f].classList.toggle('is-active', nodes[f] === filter);
      renderVehicleList(); return;
    }
    var actionNode = event.target.closest && event.target.closest('[data-garage-act]');
    if (actionNode) { if (actionNode.getAttribute('data-garage-act') === 'close') closeLocal(true); else dispatchAction(actionNode); return; }
    var card = event.target.closest && event.target.closest('[data-vehicle-id]');
    if (card && card.classList.contains('garage-vehicle-row')) selectVehicle(card.getAttribute('data-vehicle-id'), false);
  });
  if (root) root.addEventListener('change', function (event) {
    var select = event.target.closest && event.target.closest('[data-family-rank]');
    if (!select || rankBusy || select.disabled) return;
    var vehicleId = Number(select.getAttribute('data-vehicle-id')); var level = Number(select.value); if (!vehicleId || !level) return;
    rankBusy = true; select.disabled = true;
    post('garageSlot:setRank', { vehicleId: vehicleId, level: level }, function (response) {
      if (response && response.ok && current) {
        var updated = Number(response.requiredTier || level);
        if (current.current && Number(current.current.id) === vehicleId) current.current.requiredTier = updated;
        if (response.requiredRankName) {
          if (current.current && Number(current.current.id) === vehicleId) current.current.requiredRankName = String(response.requiredRankName);
        }
        var fleet = Array.isArray(current.vehicles) ? current.vehicles : [];
        for (var i = 0; i < fleet.length; i += 1) if (Number(fleet[i].id) === vehicleId) {
          fleet[i].requiredTier = updated;
          if (response.requiredRankName) fleet[i].requiredRankName = String(response.requiredRankName);
        }
      }
      rankBusy = false; renderDetail(vehicleById(selectedId));
    });
  });
  if (confirmRoot) confirmRoot.addEventListener('click', function (event) { var button = event.target.closest && event.target.closest('[data-confirm]'); if (button) closeConfirm(true, button.getAttribute('data-confirm') === 'ok'); });
  var searchInput = el('gs-search');
  if (searchInput) searchInput.addEventListener('input', function () { searchQuery = clean(searchInput.value); syncSearchUi(); renderVehicleList(); });
  window.addEventListener('message', function (event) {
    var message = event.data || {};
    try { if (message.action === 'openGarageSlot') render(message.data || {}); else if (message.action === 'closeGarageSlot') closeLocal(false); else if (message.action === 'openGarageConfirm') openConfirm(message.data || {}); }
    catch (error) { post('garageSlot:error', { message: error && error.message ? error.message : String(error) }); }
  });
  document.addEventListener('keydown', function (event) {
    if (document.querySelector('.cm-modal-backdrop')) return;
    var open = root && root.classList.contains('on');
    if (event.key === '/' && open && document.activeElement !== searchInput) { event.preventDefault(); if (searchInput) searchInput.focus(); }
    else if (event.key === 'Escape' && confirmOpen) closeConfirm(true, false);
    else if (event.key === 'Escape' && open && searchInput && searchInput.value) { searchInput.value = ''; searchQuery = ''; syncSearchUi(); renderVehicleList(); searchInput.focus(); }
    else if (event.key === 'Escape' && open) closeLocal(true);
    else if (event.key === 'Enter' && open && document.activeElement !== searchInput && !confirmOpen) {
      var primary = el('gs-detail-actions') && el('gs-detail-actions').querySelector('[data-garage-act]:not(:disabled)');
      if (primary) { event.preventDefault(); dispatchAction(primary); }
    }
  });
  post('garageSlot:ready', { version: '3.3.0', rootFound: !!root });
}());
