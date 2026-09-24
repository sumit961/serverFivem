/* ============================================================
   cm-house | garage parking-slot UI v1.2.0
   ============================================================ */
(function () {
  'use strict';
  var RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  var root = document.getElementById('garage-slot');
  var current = null;
  var busy = false;
  var rankBusy = false;
  var activeFilter = 'all';
  var searchQuery = '';
  var confirmRoot = document.getElementById('garage-confirm');
  var confirmOpen = false;

  function el(id) { return document.getElementById(id); }
  function text(id, value) { var n = el(id); if (n) n.textContent = value == null ? '' : String(value); }
  function searchable(value) {
    var normalized = String(value == null ? '' : value).toLowerCase();
    if (typeof normalized.normalize === 'function') normalized = normalized.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    return normalized.replace(/[^a-z0-9]+/g, ' ').trim();
  }
  function syncSearchUi() {
    var input = el('gs-search');
    var clear = el('gs-search-clear');
    if (clear) clear.hidden = !input || input.value.length === 0;
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

  function closeLocal(send) {
    closeConfirm(false);
    if (root) { root.classList.remove('on'); root.style.display = 'none'; root.setAttribute('aria-hidden', 'true'); }
    current = null;
    busy = false;
    if (send) post('garageSlot:close', {});
  }

  function closeConfirm(send, confirmed) {
    if (!confirmRoot || !confirmOpen) return;
    confirmOpen = false;
    confirmRoot.hidden = true;
    confirmRoot.style.display = 'none';
    confirmRoot.setAttribute('aria-hidden', 'true');
    if (send) post('garageSlot:confirm', { confirmed: confirmed === true });
  }

  function openConfirm(data) {
    if (window.CMUI && typeof window.CMUI.confirm === 'function') {
      data = data || {};
      window.CMUI.confirm({
        title: data.title || 'Confirm action',
        message: data.content || 'Are you sure?',
        confirmText: data.confirmLabel || 'Confirm',
        cancelText: data.cancelLabel || 'Cancel',
        danger: data.tone === 'danger'
      }).then(function (confirmed) {
        post('garageSlot:confirm', { confirmed: confirmed === true });
      });
      return;
    }
    if (!confirmRoot) return;
    data = data || {};
    text('gc-title', data.title || 'Confirm action');
    text('gc-text', data.content || 'Are you sure?');
    text('gc-ok', data.confirmLabel || 'Confirm');
    text('gc-cancel', data.cancelLabel || 'Cancel');
    confirmRoot.setAttribute('data-tone', data.tone === 'danger' ? 'danger' : 'cyan');
    confirmRoot.hidden = false;
    confirmRoot.style.display = 'grid';
    confirmRoot.setAttribute('aria-hidden', 'false');
    confirmOpen = true;
    var cancel = el('gc-cancel');
    if (cancel) cancel.focus();
  }

  function actionButton(label, action, vehicle, extraClass) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'garage-vehicle-row__button' + (extraClass ? ' ' + extraClass : '');
    button.setAttribute('data-garage-act', action);
    button.setAttribute('data-vehicle-id', String(vehicle.id));
    button.setAttribute('data-parked', vehicle.parked ? '1' : '0');
    button.setAttribute('data-vehicle-label', vehicle.label || vehicle.model || 'Vehicle');
    var parking = vehicle.parkedHouseLabel || 'garage';
    if (vehicle.parkedSlotIndex) parking += ' · space ' + String(vehicle.parkedSlotIndex);
    button.setAttribute('data-parking-label', parking);
    button.textContent = label;
    return button;
  }

  function rankControl(vehicle, compact) {
    if (!vehicle || vehicle.showFamilyRank !== true) return null;
    var wrap = document.createElement('label');
    wrap.className = 'garage-vehicle-rank' + (compact ? ' garage-vehicle-rank--compact' : '');
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
      if (Number(options[i].tier) === Number(vehicle.requiredTier)) option.selected = true;
      select.appendChild(option);
    }
    if (!options.length) {
      var fallback = document.createElement('option');
      fallback.value = String(vehicle.requiredTier || '');
      fallback.textContent = vehicle.requiredRankName || 'Top rank';
      fallback.selected = true;
      select.appendChild(fallback);
    }
    wrap.appendChild(caption); wrap.appendChild(select);
    return wrap;
  }

  function vehicleState(vehicle) {
    if (vehicle.rankAllowed === false) {
      return {
        key: 'blocked',
        label: vehicle.statusLabel || ('TIER ' + (vehicle.requiredTier || '') + ' REQUIRED'),
        tone: 'blocked'
      };
    }
    var code = String(vehicle.statusCode || '').toUpperCase();
    var loc = String(vehicle.locationState || '').toUpperCase();
    if (code === 'PUBLIC_PARKING' || loc === 'PUBLIC_GARAGE' || loc === 'PUBLIC_PARKING') {
      return {
        key: 'blocked',
        label: 'PUBLIC PARKING',
        tone: 'blocked'
      };
    }
    if (vehicle.canPark) return { key: 'available', label: 'AVAILABLE', tone: 'available', action: 'park', actionLabel: 'ASSIGN HERE' };
    if (vehicle.canCall) return { key: 'assigned', label: vehicle.inGarage ? 'PARKED' : 'ASSIGNED', tone: 'assigned', action: 'call', actionLabel: 'MOVE HERE' };
    var tone = code === 'IMPOUNDED' || code === 'POLICE_SEIZED' ? 'danger' : 'blocked';
    return { key: vehicle.assigned || vehicle.parked ? 'assigned' : 'blocked', label: vehicle.statusLabel || 'UNAVAILABLE', tone: tone };
  }

  function vehicleLocation(vehicle) {
    var code = String(vehicle.statusCode || '').toUpperCase();
    var loc = String(vehicle.locationState || '').toUpperCase();
    if (code === 'PUBLIC_PARKING' || loc === 'PUBLIC_GARAGE' || loc === 'PUBLIC_PARKING') {
      return 'PUBLIC PARKING';
    }
    if (vehicle.parkedHouseLabel) {
      return String(vehicle.parkedHouseLabel) + (vehicle.parkedSlotIndex ? ' · SPACE ' + String(vehicle.parkedSlotIndex) : '');
    }
    if (vehicle.canPark) return 'READY TO ASSIGN';
    return vehicle.unavailableReason || 'NOT AVAILABLE FOR THIS SPACE';
  }

  function row(vehicle, replacing) {
    var item = document.createElement('div');
    var hasImage = !!(vehicle.image && /^(nui|https?):\/\//i.test(String(vehicle.image)));
    var state = vehicleState(vehicle);
    item.className = 'garage-vehicle-row garage-vehicle-row--' + state.tone + (hasImage ? '' : ' garage-vehicle-row--no-image');
    item.setAttribute('data-filter-state', state.key);
    item.setAttribute('data-search', searchable([vehicle.label, vehicle.model, vehicle.plate].join(' ')));

    // Card header: plate badge + status badge
    var topRow = document.createElement('div');
    topRow.className = 'garage-vehicle-row__top';

    var plateBadge = document.createElement('span');
    plateBadge.className = 'garage-vehicle-row__plate';
    plateBadge.textContent = vehicle.licenseNumber || vehicle.plate || 'NO PLATE';

    var statusBadge = document.createElement('span');
    statusBadge.className = 'garage-vehicle-row__status garage-vehicle-row__status--' + state.tone;
    statusBadge.textContent = state.label;

    topRow.appendChild(plateBadge);
    topRow.appendChild(statusBadge);
    item.appendChild(topRow);

    // Vehicle image
    var media = document.createElement('div');
    media.className = 'garage-vehicle-row__media';
    if (hasImage) {
      var image = document.createElement('img');
      image.className = 'garage-vehicle-image';
      image.src = String(vehicle.image);
      image.alt = vehicle.label || vehicle.model || 'Vehicle';
      image.loading = 'lazy';
      image.onerror = function () { media.classList.add('is-missing'); image.remove(); };
      media.appendChild(image);
    } else {
      media.classList.add('is-missing');
    }
    var fallback = document.createElement('span');
    fallback.className = 'garage-vehicle-row__fallback';
    fallback.textContent = 'CM';
    media.appendChild(fallback);

    if (!replacing && state.key === 'available') {
      var suggested = document.createElement('span');
      suggested.className = 'garage-vehicle-row__suggested';
      suggested.textContent = 'SUGGESTED';
      media.appendChild(suggested);
    }
    item.appendChild(media);

    // Copy: name + location
    var copy = document.createElement('div');
    copy.className = 'garage-vehicle-row__copy';

    var nameEl = document.createElement('strong');
    nameEl.textContent = (vehicle.label || vehicle.model || 'Vehicle').toUpperCase();
    nameEl.title = nameEl.textContent;

    var locationEl = document.createElement('span');
    locationEl.className = 'garage-vehicle-row__location';
    locationEl.textContent = vehicleLocation(vehicle);
    locationEl.title = locationEl.textContent;

    copy.appendChild(nameEl);
    copy.appendChild(locationEl);
    item.appendChild(copy);

    // Actions
    var actions = document.createElement('span');
    actions.className = 'garage-vehicle-row__actions';
    var rank = rankControl(vehicle, false);
    if (rank) actions.appendChild(rank);
    if (!replacing && state.action) {
      actions.appendChild(actionButton(state.actionLabel, state.action, vehicle, 'garage-vehicle-row__button--cyan'));
    } else {
      var unavailable = document.createElement('span');
      unavailable.className = 'garage-vehicle-row__unavailable';
      var unavailText = 'ACTION UNAVAILABLE';
      if (replacing) {
        unavailText = 'CURRENT SPACE IS OCCUPIED';
      } else if (state.label === 'PUBLIC PARKING' || String(vehicle.statusCode || '').toUpperCase() === 'PUBLIC_PARKING') {
        unavailText = 'IN PUBLIC PARKING';
      } else if (vehicle.rankAllowed === false) {
        unavailText = 'REQUIRES TIER ' + (vehicle.requiredTier || '');
      }
      unavailable.textContent = unavailText;
      actions.appendChild(unavailable);
    }

    item.appendChild(actions);
    return item;
  }

  function renderVehicleList() {
    var vehicles = current && Array.isArray(current.vehicles) ? current.vehicles : [];
    var list = el('gs-list');
    if (!list) return;
    while (list.firstChild) list.removeChild(list.firstChild);
    var shown = 0;
    for (var i = 0; i < vehicles.length; i += 1) {
      var vehicle = vehicles[i];
      var state = vehicleState(vehicle);
      var vehicleSearch = searchable([vehicle.label, vehicle.model, vehicle.plate].join(' '));
      if (activeFilter !== 'all' && state.key !== activeFilter) continue;
      if (searchQuery && vehicleSearch.indexOf(searchQuery) === -1
          && vehicleSearch.replace(/\s/g, '').indexOf(searchQuery.replace(/\s/g, '')) === -1) continue;
      var card = row(vehicle, false);
      if (shown === 0 && activeFilter === 'all' && !searchQuery) {
        var suggested = document.createElement('span');
        suggested.className = 'garage-vehicle-row__suggested';
        suggested.textContent = 'SUGGESTED';
        var media = card.querySelector('.garage-vehicle-row__media');
        if (media) media.appendChild(suggested);
      }
      list.appendChild(card);
      shown += 1;
    }
    text('gs-count', shown === vehicles.length ? vehicles.length : shown + '/' + vehicles.length);
    var empty = el('gs-empty');
    if (empty) empty.hidden = shown !== 0;
  }

  function render(data) {
    if (!root) throw new Error('Missing #garage-slot root');
    current = data || {};
    var occupied = current.occupied === true;
    var vehicle = current.current || null;
    var vehicles = Array.isArray(current.vehicles) ? current.vehicles : [];

    text('gs-eyebrow', 'ASSIGNMENT & GARAGE MANAGEMENT');
    text('gs-title', ('PARKING SPACE ' + String(current.slotIndex || '?')).toUpperCase());
    text('gs-subtitle', occupied
      ? 'Recall the assigned vehicle, or cancel the car to clear this space.'
      : (current.isFamilyGarage
        ? 'Choose an eligible family vehicle. A car assigned elsewhere will move to this space.'
        : 'Choose any eligible owned vehicle. A car assigned elsewhere will move to this space.'));
    var symbol = el('gs-symbol');
    if (symbol) { symbol.setAttribute('data-occupied', occupied ? '1' : '0'); symbol.textContent = occupied ? '!' : '\uf5e7'; }

    var currentBox = el('gs-current');
    var actions = el('gs-actions');
    if (currentBox) currentBox.hidden = !occupied;
    if (actions) actions.hidden = !occupied;
    if (occupied && vehicle) {
      text('gs-current-name', vehicle.label || vehicle.model || 'Vehicle');
      text('gs-current-plate', vehicle.licenseNumber || 'NO PLATE');
      var currentState = el('gs-current-state');
      text('gs-current-state', vehicle.statusLabel || (vehicle.inGarage ? 'PARKED HERE' : 'RESERVED · OUTSIDE'));
      if (currentState) currentState.setAttribute('data-status', vehicle.statusCode || '');
      var currentImage = el('gs-current-image');
      if (currentImage) {
        if (vehicle.image && /^(nui|https?):\/\//i.test(String(vehicle.image))) {
          currentImage.src = String(vehicle.image);
          currentImage.alt = vehicle.label || vehicle.model || 'Current vehicle';
          currentImage.hidden = false;
        } else {
          currentImage.removeAttribute('src');
          currentImage.hidden = true;
        }
      }
      var currentRank = el('gs-current-rank');
      if (currentRank) {
        while (currentRank.firstChild) currentRank.removeChild(currentRank.firstChild);
        var currentControl = rankControl(vehicle, true);
        currentRank.hidden = !currentControl;
        if (currentControl) currentRank.appendChild(currentControl);
      }
    } else {
      var emptyRank = el('gs-current-rank');
      if (emptyRank) { emptyRank.hidden = true; while (emptyRank.firstChild) emptyRank.removeChild(emptyRank.firstChild); }
    }

    var vehicleSection = el('gs-vehicle-section');
    if (vehicleSection) vehicleSection.hidden = occupied;

    text('gs-list-title', current.isFamilyGarage ? 'FAMILY ROAD VEHICLES' : 'YOUR ROAD VEHICLES');
    activeFilter = 'all';
    searchQuery = '';
    var search = el('gs-search');
    if (search) search.value = '';
    syncSearchUi();
    var filters = root.querySelectorAll('[data-garage-filter]');
    for (var fi = 0; fi < filters.length; fi += 1) {
      filters[fi].classList.toggle('is-active', filters[fi].getAttribute('data-garage-filter') === 'all');
    }
    renderVehicleList();

    root.style.display = 'grid'; root.classList.add('on'); root.setAttribute('aria-hidden', 'false');
    var token = current.requestId == null ? '' : String(current.requestId);
    window.setTimeout(function () {
      var rect = root.getBoundingClientRect();
      post('garageSlot:rendered', { requestId: token, visible: rect.width > 0 && rect.height > 0 });
    }, 35);
  }

  if (root) root.addEventListener('click', function (event) {
    var confirmButton = event.target.closest && event.target.closest('[data-confirm]');
    if (confirmButton) {
      closeConfirm(true, confirmButton.getAttribute('data-confirm') === 'ok');
      return;
    }
    if (confirmOpen) return;
    var searchClear = event.target.closest && event.target.closest('#gs-search-clear');
    if (searchClear) {
      var searchField = el('gs-search');
      if (searchField) { searchField.value = ''; searchField.focus(); }
      searchQuery = '';
      syncSearchUi();
      renderVehicleList();
      return;
    }
    var filter = event.target.closest && event.target.closest('[data-garage-filter]');
    if (filter) {
      activeFilter = filter.getAttribute('data-garage-filter') || 'all';
      var filterNodes = root.querySelectorAll('[data-garage-filter]');
      for (var f = 0; f < filterNodes.length; f += 1) filterNodes[f].classList.toggle('is-active', filterNodes[f] === filter);
      renderVehicleList();
      return;
    }
    var node = event.target;
    while (node && node !== root && !(node.getAttribute && node.getAttribute('data-garage-act'))) node = node.parentNode;
    if (!node || !node.getAttribute) return;
    var action = node.getAttribute('data-garage-act');
    if (!action) return;
    if (action === 'close') { closeLocal(true); return; }
    if (busy) return;
    busy = true;

    var actionNodes = root.querySelectorAll('[data-garage-act]');
    for (var ai = 0; ai < actionNodes.length; ai += 1) actionNodes[ai].disabled = true;
    var body = { action: action };
    var id = node.getAttribute('data-vehicle-id');
    if (id) body.vehicleId = Number(id);
    var vLabel = node.getAttribute('data-vehicle-label');
    if (vLabel) body.vehicleLabel = vLabel;
    var pLabel = node.getAttribute('data-parking-label');
    if (pLabel) body.parkingLabel = pLabel;
    if (action === 'recall' && current && current.current) {
      body.vehicleId = Number(current.current.id);
    }
    if (action === 'share') body.share = node.getAttribute('data-share-next') === '1';
    post('garageSlot:action', body, function (response) {
      if (response && response.ok) closeLocal(false);
      busy = false;
      for (var ai = 0; ai < actionNodes.length; ai += 1) actionNodes[ai].disabled = false;
    });
  });

  if (root) root.addEventListener('change', function (event) {
    var select = event.target.closest && event.target.closest('[data-family-rank]');
    if (!select || rankBusy || select.disabled) return;
    var vehicleId = Number(select.getAttribute('data-vehicle-id'));
    var level = Number(select.value);
    if (!vehicleId || !level) return;
    rankBusy = true;
    select.disabled = true;
    post('garageSlot:setRank', { vehicleId: vehicleId, level: level }, function (response) {
      if (response && response.ok && current) {
        var updatedLevel = Number(response.requiredTier || level);
        if (current.current && Number(current.current.id) === vehicleId) current.current.requiredTier = updatedLevel;
        var fleet = Array.isArray(current.vehicles) ? current.vehicles : [];
        for (var i = 0; i < fleet.length; i += 1) if (Number(fleet[i].id) === vehicleId) fleet[i].requiredTier = updatedLevel;
      }
      rankBusy = false;
      select.disabled = current && current.current && Number(current.current.id) === vehicleId
        ? current.current.canManageVehicleRank !== true
        : false;
    });
  });

  if (confirmRoot) confirmRoot.addEventListener('click', function (event) {
    var confirmButton = event.target.closest && event.target.closest('[data-confirm]');
    if (!confirmButton) return;
    closeConfirm(true, confirmButton.getAttribute('data-confirm') === 'ok');
  });

  var searchInput = el('gs-search');
  if (searchInput) searchInput.addEventListener('input', function () {
    searchQuery = searchable(searchInput.value);
    syncSearchUi();
    renderVehicleList();
  });

  window.addEventListener('message', function (event) {
    var m = event.data || {};
    try {
      if (m.action === 'openGarageSlot') render(m.data || {});
      else if (m.action === 'closeGarageSlot') closeLocal(false);
      else if (m.action === 'openGarageConfirm') openConfirm(m.data || {});
    } catch (error) {
      post('garageSlot:error', { message: error && error.message ? error.message : String(error) });
    }
  });

  document.addEventListener('keydown', function (event) {
    if (document.querySelector('.cm-modal-backdrop')) {
      return;
    }
    var open = root && root.classList.contains('on');
    if (event.key === '/' && open && document.activeElement !== searchInput) {
      event.preventDefault();
      if (searchInput) searchInput.focus();
    } else if (event.key === 'Escape' && confirmOpen) {
      closeConfirm(true, false);
    } else if (event.key === 'Escape' && open && searchInput && searchInput.value) {
      searchInput.value = '';
      searchQuery = '';
      syncSearchUi();
      renderVehicleList();
      searchInput.focus();
    } else if (event.key === 'Escape' && open) {
      closeLocal(true);
    }
  });
  post('garageSlot:ready', { version: '3.2.0', rootFound: !!root });
}());
