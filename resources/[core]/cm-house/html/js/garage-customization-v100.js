/* ============================================================
   cm-house | garage interior customization script v1.0.0
   ============================================================ */
(function () {
  'use strict';
  var RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  var root = document.getElementById('garage-customization');
  var currentWall = 1;
  var currentFloor = 1;
  var currentCeiling = 1;
  var isOpen = false;

  function post(endpoint, payload, callback) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', 'https://' + RES + '/' + endpoint, true);
    xhr.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      var resp = {};
      try { resp = xhr.responseText ? JSON.parse(xhr.responseText) : {}; } catch (_) {}
      if (typeof callback === 'function') callback(resp);
    };
    xhr.onerror = function () { if (typeof callback === 'function') callback({}); };
    try { xhr.send(JSON.stringify(payload || {})); } catch (_) { if (typeof callback === 'function') callback({}); }
  }

  function updateUi() {
    var wallLabel = document.getElementById('gc-wall-label');
    var floorLabel = document.getElementById('gc-floor-label');
    var ceilingLabel = document.getElementById('gc-ceiling-label');

    if (wallLabel) wallLabel.textContent = 'Style ' + currentWall;
    if (floorLabel) floorLabel.textContent = 'Style ' + currentFloor;
    if (ceilingLabel) ceilingLabel.textContent = 'Style ' + currentCeiling;

    var options = document.querySelectorAll('.garage-custom-option');
    options.forEach(function (opt) {
      var type = opt.getAttribute('data-type');
      var val = parseInt(opt.getAttribute('data-value'), 10);
      var active = false;
      if (type === 'wall' && val === currentWall) active = true;
      if (type === 'floor' && val === currentFloor) active = true;
      if (type === 'ceiling' && val === currentCeiling) active = true;

      if (active) {
        opt.classList.add('is-active');
        opt.setAttribute('aria-checked', 'true');
      } else {
        opt.classList.remove('is-active');
        opt.setAttribute('aria-checked', 'false');
      }
    });
  }

  function open(data) {
    if (!root) return;
    currentWall = Math.max(1, Math.min(5, parseInt(data && data.wall, 10) || 1));
    currentFloor = Math.max(1, Math.min(5, parseInt(data && data.floor, 10) || 1));
    currentCeiling = Math.max(1, Math.min(5, parseInt(data && data.ceiling, 10) || 1));

    updateUi();
    root.classList.add('on');
    root.style.display = 'grid';
    root.setAttribute('aria-hidden', 'false');
    isOpen = true;
  }

  function closeLocal() {
    if (!root || !isOpen) return;
    isOpen = false;
    root.classList.remove('on');
    root.style.display = 'none';
    root.setAttribute('aria-hidden', 'true');
  }

  function setupEvents() {
    if (!root) return;

    root.addEventListener('click', function (e) {
      var opt = e.target.closest('.garage-custom-option');
      if (opt) {
        var type = opt.getAttribute('data-type');
        var val = parseInt(opt.getAttribute('data-value'), 10);
        if (type === 'wall') currentWall = val;
        if (type === 'floor') currentFloor = val;
        if (type === 'ceiling') currentCeiling = val;

        updateUi();
        post('garageCustom:preview', {
          wall: currentWall,
          floor: currentFloor,
          ceiling: currentCeiling
        });
        return;
      }

      var actBtn = e.target.closest('[data-custom-act]');
      if (actBtn) {
        var act = actBtn.getAttribute('data-custom-act');
        if (act === 'close' || act === 'cancel') {
          closeLocal();
          post('garageCustom:close', {});
        } else if (act === 'save') {
          post('garageCustom:save', {
            wall: currentWall,
            floor: currentFloor,
            ceiling: currentCeiling
          }, function (resp) {
            if (resp && resp.ok) {
              closeLocal();
            }
          });
        }
      }
    });

    window.addEventListener('keydown', function (e) {
      if (!isOpen) return;
      if (e.key === 'Escape') {
        e.preventDefault();
        closeLocal();
        post('garageCustom:close', {});
      }
    });
  }

  window.addEventListener('message', function (e) {
    var item = e.data;
    if (!item) return;
    if (item.action === 'openGarageCustomization') {
      open(item.data || {});
    } else if (item.action === 'closeGarageCustomization') {
      closeLocal();
    }
  });

  document.addEventListener('DOMContentLoaded', function () {
    root = document.getElementById('garage-customization');
    setupEvents();
  });
})();

