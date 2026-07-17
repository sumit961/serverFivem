/* ============================================================
   cm-house | isolated door/purchase UI v1.0.5
   This file intentionally owns only the property door panel.
   Admin and creation-wizard failures cannot prevent buying.
   ============================================================ */
(function () {
  'use strict';

  var RES = typeof GetParentResourceName === 'function'
    ? GetParentResourceName()
    : 'cm-house';
  var current = null;
  var currentRequestId = null;
  var root = document.getElementById('door');
  var photoDataCache = Object.create(null);
  var photoDataOrder = [];

  function el(id) {
    return document.getElementById(id);
  }

  function post(name, body, done) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', 'https://' + RES + '/' + name, true);
    xhr.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      var response = {};
      try {
        response = xhr.responseText ? JSON.parse(xhr.responseText) : {};
      } catch (_) {
        response = {};
      }
      if (typeof done === 'function') done(response);
    };
    xhr.onerror = function () {
      if (typeof done === 'function') done({});
    };
    try {
      xhr.send(JSON.stringify(body || {}));
    } catch (error) {
      if (typeof done === 'function') done({});
    }
  }

  function setText(id, value, fallback) {
    var node = el(id);
    if (!node) return;
    if (value === null || value === undefined || value === '') {
      node.textContent = fallback === undefined ? '' : String(fallback);
    } else {
      node.textContent = String(value);
    }
  }

  function money(value) {
    if (value === null || value === undefined || value === '') return '—';
    var n = Number(value);
    if (!isFinite(n)) return '—';
    try {
      return '$' + n.toLocaleString('en-US');
    } catch (_) {
      return '$' + String(Math.floor(n));
    }
  }

  function setOpen(open) {
    if (!root) return;
    if (open) {
      root.classList.add('on');
      root.style.display = 'grid';
      root.setAttribute('aria-hidden', 'false');
    } else {
      root.classList.remove('on');
      root.classList.remove('screen--live');
      root.style.display = 'none';
      root.setAttribute('aria-hidden', 'true');
    }
  }

  function paintLock(locked) {
    var button = el('d-lock');
    if (button) button.classList.toggle('is-locked', !!locked);
    setText('d-lock-icon', locked ? '🔒' : '🔓');
    setText('d-lock-label', locked ? 'Unlock' : 'Lock');
  }

  function paintPaid(view) {
    var paid = el('d-paid');
    if (!paid) return;
    paid.classList.remove('warn');
    paid.classList.remove('bad');

    var days = view.daysRemaining;
    if (!view.ownerName) {
      paid.textContent = '—';
    } else if (days === null || days === undefined) {
      paid.textContent = 'Not paid';
      paid.classList.add('bad');
    } else if (Number(days) < 0) {
      paid.textContent = Math.abs(Number(days)) + ' days late';
      paid.classList.add('bad');
    } else {
      days = Number(days);
      paid.textContent = days + ' day' + (days === 1 ? '' : 's');
      if (days <= 2) paid.classList.add('warn');
    }
  }

  function paintSeal(view) {
    var seal = el('d-seal');
    if (!seal) return;

    var vacant = !view.ownerName;
    var stars = vacant ? 0 : Number(view.stars || 0);
    if (!isFinite(stars)) stars = 0;
    stars = Math.max(0, Math.min(5, Math.floor(stars)));

    seal.setAttribute('data-stars', String(stars));
    seal.setAttribute('data-vacant', vacant ? '1' : '0');
    setText('d-stars', vacant ? '· · · · ·' : '★'.repeat(stars) + '☆'.repeat(5 - stars));

    var word = 'VACANT';
    var days = view.daysRemaining;
    if (!vacant) {
      if (days === null || days === undefined) word = 'UNPAID';
      else if (Number(days) < 0) word = Math.abs(Number(days)) + 'D OVERDUE';
      else if (Number(days) === 0) word = 'DUE TODAY';
      else word = Number(days) + 'D PAID';
    }
    setText('d-status', word);

    var fill = seal.querySelector('.seal__fill');
    if (fill) fill.style.strokeDashoffset = String(327 * (1 - stars / 5));
  }

  function paintButtons(view) {
    var can = view.can || {};
    var lock = el('d-lock');
    var home = el('d-home');
    var garage = el('d-garage');
    var buy = el('d-buy');
    var sell = el('d-sell');
    var foot = root ? root.querySelector('.deed__foot') : null;

    if (lock) lock.disabled = !can.lock;
    if (home) home.disabled = !can.enter;
    if (garage) {
      garage.disabled = !can.garage;
      garage.hidden = !view.hasGarage;
    }
    if (buy) {
      buy.hidden = !can.buy;
      buy.disabled = !can.buy;
    }
    if (sell) {
      sell.hidden = !can.sell;
      sell.disabled = !can.sell;
    }

    if (foot) {
      var visibleActions = (buy && !buy.hidden ? 1 : 0) + (sell && !sell.hidden ? 1 : 0);
      foot.classList.toggle('deed__foot--single', visibleActions <= 1);
    }
  }

  function rememberPhotoData(source, dataUri) {
    var existing = photoDataOrder.indexOf(source);
    if (existing !== -1) photoDataOrder.splice(existing, 1);
    photoDataCache[source] = dataUri;
    photoDataOrder.push(source);
    while (photoDataOrder.length > 8) {
      var oldest = photoDataOrder.shift();
      if (oldest) delete photoDataCache[oldest];
    }
  }

  function isLocalHousePhoto(source) {
    return typeof source === 'string' && /^img\/houses\/house_\d+\.jpg(?:\?v=\d+)?$/.test(source);
  }

  function clearPropertyPhoto(shot, image) {
    if (shot) {
      shot.setAttribute('data-has-image', '0');
      shot.removeAttribute('data-loading');
    }
    if (image) {
      image.onerror = null;
      image.onload = null;
      image.removeAttribute('src');
    }
  }

  function loadPropertyPhoto(view, shot, image) {
    if (!image) return;
    var source = view && view.image ? String(view.image) : '';
    var houseId = view ? Number(view.id) : 0;
    var requestId = view && view.requestId !== undefined ? String(view.requestId) : '';

    if (!source) {
      clearPropertyPhoto(shot, image);
      return;
    }

    function stillCurrent() {
      return !!current && Number(current.id) === houseId &&
        String(current.requestId === undefined ? '' : current.requestId) === requestId;
    }

    function showDataUri(dataUri) {
      if (!stillCurrent() || typeof dataUri !== 'string' || dataUri.indexOf('data:image/jpeg;base64,') !== 0) {
        clearPropertyPhoto(shot, image);
        return;
      }
      image.onerror = function () {
        if (stillCurrent()) clearPropertyPhoto(shot, image);
      };
      image.onload = function () {
        if (!stillCurrent()) return;
        if (shot) {
          shot.setAttribute('data-has-image', '1');
          shot.removeAttribute('data-loading');
        }
      };
      image.setAttribute('src', dataUri);
    }

    function requestLocalFallback() {
      if (!stillCurrent()) return;
      var cached = photoDataCache[source];
      if (cached) {
        showDataUri(cached);
        return;
      }
      if (shot) shot.setAttribute('data-loading', '1');
      post('door:getPhoto', { houseId: houseId }, function (response) {
        if (!stillCurrent()) return;
        if (response && response.ok && typeof response.dataUri === 'string') {
          rememberPhotoData(source, response.dataUri);
          showDataUri(response.dataUri);
        } else {
          clearPropertyPhoto(shot, image);
        }
      });
    }

    if (shot) shot.setAttribute('data-has-image', '1');
    image.onload = function () {
      if (!stillCurrent()) return;
      if (shot) {
        shot.setAttribute('data-has-image', '1');
        shot.removeAttribute('data-loading');
      }
    };
    image.onerror = function () {
      image.onerror = null;
      if (isLocalHousePhoto(source)) requestLocalFallback();
      else clearPropertyPhoto(shot, image);
    };
    image.setAttribute('src', source);
  }

  function render(view) {
    if (!root) throw new Error('Missing #door root element');

    current = view || {};
    currentRequestId = current.requestId === null || current.requestId === undefined
      ? ''
      : String(current.requestId);

    // Make the panel visible first. Optional fields can never block display.
    setOpen(true);

    var shot = el('d-shot');
    var image = el('d-img');
    if (shot) shot.setAttribute('data-live', current.liveView === true ? '1' : '0');
    root.classList.toggle('screen--live', current.liveView === true);
    loadPropertyPhoto(current, shot, image);

    setText('d-number', current.houseNumber, '000');
    setText('d-label', current.label, 'House');
    setText('d-type', current.houseType, '');
    setText('d-family', current.familyName, '');
    setText('d-owner', current.ownerName, 'For sale');
    setText('d-insurance', money(current.insurance));
    setText('d-price', money(current.price));
    setText('d-daily', money(current.dailyCost));
    setText('d-gov', money(current.govValue));

    paintPaid(current);
    paintSeal(current);
    paintLock(!!current.locked);
    paintButtons(current);

    // Use a unique request token rather than only the house ID. Repeated E
    // presses, cached messages and retries can no longer acknowledge the wrong
    // opening. The rectangle proves the panel is actually laid out.
    var renderedRequestId = currentRequestId;
    var renderedHouseId = current.id;
    window.setTimeout(function () {
      var rect = root.getBoundingClientRect();
      var style = window.getComputedStyle ? window.getComputedStyle(root) : null;
      var visible = root.classList.contains('on') &&
        root.style.display !== 'none' &&
        (!style || (style.display !== 'none' && style.visibility !== 'hidden')) &&
        rect.width > 0 && rect.height > 0;

      post('doorRendered', {
        requestId: renderedRequestId,
        houseId: renderedHouseId,
        visible: visible,
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      });
    }, 50);
  }

  function closeLocal(sendCallback) {
    setOpen(false);
    current = null;
    currentRequestId = null;
    if (sendCallback) post('door:close', {});
  }

  function actionButton(target) {
    var node = target;
    while (node && node !== root) {
      if (node.getAttribute && node.getAttribute('data-act')) return node;
      node = node.parentNode;
    }
    return null;
  }

  if (root) {
    root.addEventListener('click', function (event) {
      var button = actionButton(event.target);
      if (!button || button.disabled || !current) return;
      var action = button.getAttribute('data-act');
      var houseId = current.id;

      if (action === 'close') {
        closeLocal(true);
        return;
      }

      if (action === 'lock') {
        button.disabled = true;
        post('door:toggleLock', { houseId: houseId }, function (response) {
          if (response && response.ok) {
            current.locked = !!response.locked;
            paintLock(current.locked);
          }
          button.disabled = !(current && current.can && current.can.lock);
        });
        return;
      }

      if (action === 'home') {
        post('door:enterHome', { houseId: houseId });
        closeLocal(false);
        return;
      }

      if (action === 'garage') {
        post('door:openGarage', { houseId: houseId });
        closeLocal(false);
        return;
      }

      if (action === 'buy') {
        button.disabled = true;
        post('door:buy', { houseId: houseId }, function (response) {
          if (response && response.ok) closeLocal(false);
          else if (current) button.disabled = false;
        });
        return;
      }

      if (action === 'sell') {
        button.disabled = true;
        post('door:sell', { houseId: houseId }, function (response) {
          if (response && response.ok) closeLocal(false);
          else if (current) button.disabled = false;
        });
      }
    });
  }

  window.addEventListener('message', function (event) {
    var message = event.data || {};
    var data = message.data || {};

    try {
      if (message.action === 'openDoor') {
        render(data);
      } else if (message.action === 'closeDoor') {
        closeLocal(false);
      } else if (message.action === 'doorLiveStarted') {
        if (root) root.classList.add('screen--live');
        if (el('d-shot')) el('d-shot').setAttribute('data-live', '1');
      } else if (message.action === 'doorLiveUnavailable') {
        if (root) root.classList.remove('screen--live');
        if (el('d-shot')) el('d-shot').setAttribute('data-live', '0');
      } else if (message.action === 'updateLock' && current) {
        if (Number(current.id) === Number(data.houseId)) {
          current.locked = !!data.locked;
          paintLock(current.locked);
        }
      }
    } catch (error) {
      post('door:clientError', {
        phase: 'door-v105-message',
        requestId: currentRequestId,
        message: error && error.message ? error.message : String(error)
      });
    }
  });

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && root && root.classList.contains('on')) {
      closeLocal(true);
    }
  });

  post('doorUiReady', { version: '1.0.5', rootFound: !!root });
}());
