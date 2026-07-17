/* ============================================================
   cm-house | custom interior / garage door UI v1.1.0
   Independent from the property deed and admin/wizard scripts.
   ============================================================ */
(function () {
  'use strict';

  var RES = typeof GetParentResourceName === 'function'
    ? GetParentResourceName()
    : 'cm-house';
  var root = document.getElementById('interior-door');
  var current = null;

  function el(id) { return document.getElementById(id); }

  function post(name, body, done) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', 'https://' + RES + '/' + name, true);
    xhr.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      var response = {};
      try { response = xhr.responseText ? JSON.parse(xhr.responseText) : {}; }
      catch (_) { response = {}; }
      if (typeof done === 'function') done(response);
    };
    xhr.onerror = function () {
      if (typeof done === 'function') done({});
    };
    try { xhr.send(JSON.stringify(body || {})); }
    catch (_) { if (typeof done === 'function') done({}); }
  }

  function setText(id, value) {
    var node = el(id);
    if (node) node.textContent = value === undefined || value === null ? '' : String(value);
  }

  function setButton(button, action, label, description, icon, visible) {
    if (!button) return;
    button.hidden = visible === false;
    button.setAttribute('data-interior-act', action);
    if (button.id === 'id-primary') {
      setText('id-primary-label', label);
      setText('id-primary-description', description);
      setText('id-primary-icon', icon);
    } else {
      setText('id-secondary-label', label);
      setText('id-secondary-description', description);
      setText('id-secondary-icon', icon);
    }
  }

  function closeLocal(sendCallback) {
    if (root) {
      root.classList.remove('on');
      root.style.display = 'none';
      root.setAttribute('aria-hidden', 'true');
    }
    current = null;
    if (sendCallback) post('interiorDoor:close', {});
  }

  function render(data) {
    if (!root) throw new Error('Missing #interior-door root');
    current = data || {};

    var primary = el('id-primary');
    var secondary = el('id-secondary');
    var kind = current.kind === 'garage' ? 'garage' : 'house';

    if (kind === 'garage') {
      setText('id-eyebrow', 'GARAGE ACCESS');
      setText('id-title', 'Garage door');
      setText('id-subtitle', 'Return inside or leave the property.');
      setButton(primary, 'house', 'Return to house', 'Walk back into the house interior.', '⌂', true);
      setButton(secondary, 'exit', 'Go outside', 'Leave the property and return to the street.', '➜', true);
    } else {
      setText('id-eyebrow', 'PROPERTY ACCESS');
      setText('id-title', 'House door');
      setText('id-subtitle', current.hasGarage ? 'Choose the house exit or garage.' : 'Leave the property through this door.');
      setButton(primary, 'exit', 'Go outside', 'Leave the property and return to the street.', '➜', true);
      setButton(secondary, 'garage', 'Enter garage', 'Walk into the property garage.', '▣', current.hasGarage === true);
    }

    root.style.display = 'grid';
    root.classList.add('on');
    root.setAttribute('aria-hidden', 'false');

    var token = current.requestId === undefined || current.requestId === null
      ? '' : String(current.requestId);
    window.setTimeout(function () {
      if (!root || !root.classList.contains('on')) return;
      var rect = root.getBoundingClientRect();
      post('interiorDoor:rendered', {
        requestId: token,
        visible: rect.width > 0 && rect.height > 0,
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      });
    }, 35);
  }

  if (root) {
    root.addEventListener('click', function (event) {
      var node = event.target;
      while (node && node !== root && !(node.getAttribute && node.getAttribute('data-interior-act'))) {
        node = node.parentNode;
      }
      if (!node || !node.getAttribute) return;

      var action = node.getAttribute('data-interior-act');
      if (!action) return;
      if (action === 'close') {
        closeLocal(true);
        return;
      }

      node.disabled = true;
      post('interiorDoor:select', { action: action }, function (response) {
        if (response && response.ok) closeLocal(false);
        node.disabled = false;
      });
    });
  }

  window.addEventListener('message', function (event) {
    var message = event.data || {};
    try {
      if (message.action === 'openInteriorDoor') render(message.data || {});
      else if (message.action === 'closeInteriorDoor') closeLocal(false);
    } catch (error) {
      post('interiorDoor:error', {
        message: error && error.message ? error.message : String(error)
      });
    }
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && root && root.classList.contains('on')) {
      closeLocal(true);
    }
  });

  post('interiorDoor:ready', { version: '1.1.0', rootFound: !!root });
}());
