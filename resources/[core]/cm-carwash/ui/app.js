(function () {
  'use strict';

  var root = document.getElementById('wash-root');
  var interaction = document.getElementById('interaction');

  function el(id) {
    return document.getElementById(id);
  }

  function resourceName() {
    return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-carwash';
  }

  function post(endpoint, payload) {
    payload = payload || {};
    return fetch('https://' + resourceName() + '/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload)
    }).then(function (response) {
      return response.text().then(function (text) {
        if (!text) return { ok: response.ok };
        try { return JSON.parse(text); } catch (_) { return { ok: response.ok }; }
      });
    }).catch(function () {
      return null;
    });
  }

  function formatMoney(value) {
    return Math.max(0, Number(value) || 0).toLocaleString('en-US');
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, Number(value) || 0));
  }

  var context = {
    stationName: 'CM Auto Spa',
    sessionToken: '',
    vehicle: null,
    dirt: 0,
    maxDirt: 15,
    minDirt: 0.5,
    price: 0,
    cash: 0,
    durationMs: 7000
  };

  var submitting = false;
  var washing = false;
  var toastTimer = null;
  var readyConfirmed = false;
  var readyTimer = null;

  function cleanliness() {
    var maximum = Math.max(0.1, Number(context.maxDirt) || 15);
    return Math.round(clamp(100 - ((Number(context.dirt) || 0) / maximum) * 100, 0, 100));
  }

  function showToast(message, type) {
    type = type || 'success';
    el('toastMessage').textContent = String(message || '');
    el('toast').classList.toggle('error', type === 'error');
    el('toast').classList.remove('hidden');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      el('toast').classList.add('hidden');
    }, 4200);
  }

  function setSteps(progress) {
    var steps = Array.prototype.slice.call(document.querySelectorAll('.wash-step'));
    var activeIndex = progress < 22 ? 0 : progress < 65 ? 1 : progress < 88 ? 2 : 3;
    steps.forEach(function (step, index) {
      step.classList.toggle('active', index === activeIndex && progress < 100);
      step.classList.toggle('complete', index < activeIndex || progress >= 100);
    });
  }

  function render() {
    var clean = cleanliness();
    var insufficient = Number(context.cash || 0) < Number(context.price || 0);
    var alreadyClean = Number(context.dirt || 0) < Number(context.minDirt || 0.5);
    var vehicle = context.vehicle || {};

    el('stationName').textContent = String(context.stationName || 'CM Auto Spa');
    el('vehicleName').textContent = String(vehicle.label || 'Vehicle');
    el('vehiclePlate').textContent = String(vehicle.plate || 'NO PLATE');
    el('cleanValue').textContent = clean;
    el('cleanRing').style.setProperty('--clean-angle', String(clean * 3.6) + 'deg');
    el('dirtValue').textContent = Number(context.dirt || 0).toFixed(1);
    el('maxDirtValue').textContent = String(Number(context.maxDirt || 15));
    el('durationValue').textContent = String(Math.max(1, Math.round(Number(context.durationMs || 7000) / 1000)));
    el('cashValue').textContent = formatMoney(context.cash);
    el('servicePrice').textContent = formatMoney(context.price);
    el('grandTotal').textContent = formatMoney(context.price);

    var button = el('btnWash');
    button.disabled = submitting || washing || insufficient || alreadyClean;
    el('btnClose').disabled = washing || submitting;

    if (washing) {
      el('washButtonText').textContent = 'Wash in progress';
      el('checkoutHint').textContent = 'Vehicle controls are secured';
      el('keyHintText').textContent = 'Wash cannot be closed early';
    } else if (submitting) {
      el('washButtonText').textContent = 'Processing cash';
      el('checkoutHint').textContent = 'Verifying vehicle and payment';
    } else if (alreadyClean) {
      el('washButtonText').textContent = 'Vehicle already clean';
      el('checkoutHint').textContent = 'No wash is required';
    } else if (insufficient) {
      el('washButtonText').textContent = 'Not enough cash';
      el('checkoutHint').textContent = 'Need $' + formatMoney(Number(context.price) - Number(context.cash)) + ' more';
    } else {
      el('washButtonText').textContent = 'Start wash';
      el('checkoutHint').textContent = 'Cash payment only';
      el('keyHintText').textContent = 'Close car wash';
    }
  }

  function mergeContext(newContext) {
    var merged = {};
    var key;
    for (key in context) {
      if (Object.prototype.hasOwnProperty.call(context, key)) merged[key] = context[key];
    }
    newContext = newContext || {};
    for (key in newContext) {
      if (Object.prototype.hasOwnProperty.call(newContext, key)) merged[key] = newContext[key];
    }
    return merged;
  }

  function setRootVisible(visible) {
    if (visible) {
      root.classList.remove('hidden');
      root.setAttribute('aria-hidden', 'false');
      root.style.display = 'block';
      root.style.visibility = 'visible';
      root.style.opacity = '1';
    } else {
      root.classList.add('hidden');
      root.setAttribute('aria-hidden', 'true');
      root.style.display = 'none';
      root.style.visibility = 'hidden';
      root.style.opacity = '0';
    }
  }

  function openPanel(newContext) {
    context = mergeContext(newContext);
    context.cash = Number(context.cash) || 0;
    context.price = Number(context.price) || 0;
    context.dirt = Number(context.dirt) || 0;
    context.maxDirt = Number(context.maxDirt) || 15;
    context.minDirt = Number(context.minDirt) || 0.5;
    context.durationMs = Number(context.durationMs) || 7000;
    submitting = false;
    washing = false;

    el('toast').classList.add('hidden');
    el('progressCard').classList.add('hidden');
    el('progressFill').style.width = '0%';
    el('progressValue').textContent = '0';
    setSteps(0);
    render();

    interaction.classList.add('hidden');
    interaction.setAttribute('aria-hidden', 'true');
    setRootVisible(true);

    // Tell Lua that the panel really rendered. This prevents invisible focus locks.
    post('uiOpened', { sessionToken: String(context.sessionToken || '') });
  }

  function closePanel(sendClose) {
    if (washing || submitting) return;
    setRootVisible(false);
    submitting = false;
    if (sendClose) post('close');
  }

  function updateInteraction(data) {
    var visible = data.visible === true;
    if (!visible) {
      interaction.classList.add('hidden');
      interaction.setAttribute('aria-hidden', 'true');
      return;
    }

    el('interactionKey').textContent = String(data.key || 'E');
    el('interactionTitle').textContent = String(data.title || 'CAR WASH');
    el('interactionLabel').textContent = String(data.label || 'Open automatic car wash');
    el('interactionHint').textContent = String(data.hint || 'Cash payment');
    interaction.classList.toggle('disabled', data.enabled === false);
    interaction.classList.toggle('clean', data.clean === true);
    interaction.classList.remove('hidden');
    interaction.setAttribute('aria-hidden', 'false');
  }

  el('btnWash').addEventListener('click', function () {
    if (submitting || washing || el('btnWash').disabled) return;
    submitting = true;
    render();
    post('startWash').then(function (response) {
      if (!response) {
        submitting = false;
        render();
        showToast('Could not contact the car wash.', 'error');
      }
    });
  });

  el('btnClose').addEventListener('click', function () {
    closePanel(true);
  });

  document.addEventListener('keydown', function (event) {
    if ((event.key === 'Escape' || event.key === 'Backspace') && !root.classList.contains('hidden')) {
      event.preventDefault();
      if (washing || submitting) return;
      closePanel(false);
      post('escape');
    }
  });

  window.addEventListener('message', function (event) {
    var data = event.data || {};

    if (data.action === 'interaction') updateInteraction(data);
    if (data.action === 'open') openPanel(data.ctx || {});
    if (data.action === 'close') closePanel(false);

    if (data.action === 'washResult') {
      var result = data.result || {};
      submitting = false;
      if (typeof result.cash === 'number') context.cash = result.cash;
      render();
      showToast(result.message || 'The wash could not be started.', result.ok ? 'success' : 'error');
    }

    if (data.action === 'washStarted') {
      submitting = false;
      washing = true;
      if (typeof data.cash === 'number') context.cash = data.cash;
      el('progressCard').classList.remove('hidden');
      showToast(data.message || 'Cash accepted. Wash started.', 'success');
      render();
    }

    if (data.action === 'washProgress') {
      var progress = clamp(data.progress, 0, 100);
      el('progressValue').textContent = String(Math.round(progress));
      el('progressFill').style.width = String(progress) + '%';
      el('progressStage').textContent = String(data.stage || 'Washing vehicle');
      setSteps(progress);
    }

    if (data.action === 'washComplete') {
      washing = false;
      context.dirt = 0;
      el('progressValue').textContent = '100';
      el('progressFill').style.width = '100%';
      el('progressStage').textContent = 'Vehicle ready';
      setSteps(100);
      render();
      showToast(data.message || 'Wash complete.', 'success');
    }
  });

  function announceReady() {
    if (readyConfirmed) return;
    post('ready').then(function (response) {
      if (response && response.ok !== false) {
        readyConfirmed = true;
        if (readyTimer) {
          clearInterval(readyTimer);
          readyTimer = null;
        }
      }
    });
  }

  // Keep retrying until the Lua callback exists. On some clients the NUI page
  // loads before the client script has finished registering callbacks.
  announceReady();
  setTimeout(announceReady, 250);
  readyTimer = setInterval(announceReady, 1000);

  setRootVisible(false);

  // Browser-only preview for design checks: index.html?preview=1
  try {
    if (new URLSearchParams(window.location.search).get('preview') === '1') {
      openPanel({
        stationName: 'CM Auto Spa',
        vehicle: { label: 'Benefactor Dubsta', plate: 'CM 2048' },
        dirt: 9.4,
        maxDirt: 15,
        minDirt: 0.5,
        price: 150,
        cash: 2480,
        durationMs: 7000
      });
    }
  } catch (_) {}
})();
