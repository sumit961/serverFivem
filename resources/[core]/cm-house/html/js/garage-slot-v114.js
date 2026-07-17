/* ============================================================
   cm-house | garage parking-slot UI v1.1.4
   ============================================================ */
(function () {
  'use strict';
  var RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  var root = document.getElementById('garage-slot');
  var current = null;
  var busy = false;

  function el(id) { return document.getElementById(id); }
  function text(id, value) { var n = el(id); if (n) n.textContent = value == null ? '' : String(value); }
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
    if (root) { root.classList.remove('on'); root.style.display = 'none'; root.setAttribute('aria-hidden', 'true'); }
    current = null;
    busy = false;
    if (send) post('garageSlot:close', {});
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

  function row(vehicle, replacing) {
    var item = document.createElement('div');
    item.className = 'garage-vehicle-row';

    var copy = document.createElement('span');
    copy.className = 'garage-vehicle-row__copy';
    var name = document.createElement('strong');
    name.textContent = vehicle.label || vehicle.model || 'Vehicle';
    var plate = document.createElement('small');
    var status = vehicle.plate || 'NO PLATE';
    if (vehicle.statusLabel) {
      status += ' · ' + String(vehicle.statusLabel).toUpperCase();
    } else if (vehicle.assigned || vehicle.parked) {
      status += vehicle.inGarage ? ' · PARKED HERE' : ' · RESERVED / OUTSIDE';
    } else if (vehicle.canPark) {
      status += ' · AVAILABLE';
    } else if (vehicle.unavailableReason) {
      status += ' · ' + String(vehicle.unavailableReason).toUpperCase();
    }
    if (vehicle.parkedHouseLabel) status += ' · ' + vehicle.parkedHouseLabel;
    if (vehicle.parkedSlotIndex) status += ' · SPACE ' + String(vehicle.parkedSlotIndex);
    plate.textContent = status;
    copy.appendChild(name); copy.appendChild(plate);

    var actions = document.createElement('span');
    actions.className = 'garage-vehicle-row__actions';
    if (!replacing && vehicle.canCall) {
      actions.appendChild(actionButton('CALL HERE', 'call', vehicle, ''));
    } else if (!replacing && vehicle.canPark) {
      actions.appendChild(actionButton('CALL HERE', 'park', vehicle, ''));
    } else {
      var unavailable = document.createElement('span');
      unavailable.className = 'garage-vehicle-row__unavailable';
      unavailable.textContent = replacing
        ? 'CURRENT SPACE IS OCCUPIED'
        : (vehicle.statusLabel || (vehicle.assigned || vehicle.parked ? 'CANNOT MOVE THIS CAR' : 'UNAVAILABLE'));
      actions.appendChild(unavailable);
    }

    item.appendChild(copy); item.appendChild(actions);
    return item;
  }

  function render(data) {
    if (!root) throw new Error('Missing #garage-slot root');
    current = data || {};
    var occupied = current.occupied === true;
    var vehicle = current.current || null;
    var vehicles = Array.isArray(current.vehicles) ? current.vehicles : [];

    text('gs-eyebrow', occupied ? 'OCCUPIED PARKING' : 'AVAILABLE PARKING');
    text('gs-title', 'Parking space ' + String(current.slotIndex || '?'));
    text('gs-subtitle', occupied ? 'Recall the assigned vehicle, or cancel the car to clear this space.' : 'Choose any eligible owned vehicle. A car assigned elsewhere will move to this space.');
    var symbol = el('gs-symbol');
    if (symbol) { symbol.setAttribute('data-occupied', occupied ? '1' : '0'); symbol.textContent = occupied ? '!' : 'P'; }

    var currentBox = el('gs-current');
    var actions = el('gs-actions');
    if (currentBox) currentBox.hidden = !occupied;
    if (actions) actions.hidden = !occupied;
    if (occupied && vehicle) {
      text('gs-current-name', vehicle.label || vehicle.model || 'Vehicle');
      text('gs-current-plate', vehicle.plate || 'NO PLATE');
      var currentState = el('gs-current-state');
      text('gs-current-state', vehicle.statusLabel || (vehicle.inGarage ? 'PARKED HERE' : 'RESERVED · OUTSIDE'));
      if (currentState) currentState.setAttribute('data-status', vehicle.statusCode || '');
    }

    var vehicleSection = el('gs-vehicle-section');
    if (vehicleSection) vehicleSection.hidden = occupied;

    text('gs-list-title', 'ALL YOUR VEHICLES');
    text('gs-count', vehicles.length);
    var list = el('gs-list');
    if (list) {
      while (list.firstChild) list.removeChild(list.firstChild);
      for (var i = 0; i < vehicles.length; i += 1) list.appendChild(row(vehicles[i], occupied));
    }
    var empty = el('gs-empty');
    if (empty) empty.hidden = vehicles.length !== 0;

    root.style.display = 'grid'; root.classList.add('on'); root.setAttribute('aria-hidden', 'false');
    var token = current.requestId == null ? '' : String(current.requestId);
    window.setTimeout(function () {
      var rect = root.getBoundingClientRect();
      post('garageSlot:rendered', { requestId: token, visible: rect.width > 0 && rect.height > 0 });
    }, 35);
  }

  if (root) root.addEventListener('click', function (event) {
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

  window.addEventListener('message', function (event) {
    var m = event.data || {};
    try {
      if (m.action === 'openGarageSlot') render(m.data || {});
      else if (m.action === 'closeGarageSlot') closeLocal(false);
    } catch (error) {
      post('garageSlot:error', { message: error && error.message ? error.message : String(error) });
    }
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && root && root.classList.contains('on')) closeLocal(true);
  });
  post('garageSlot:ready', { version: '2.0.0', rootFound: !!root });
}());
