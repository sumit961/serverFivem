(function () {
  'use strict';

  var interaction = document.getElementById('interaction');
  var holdRoot = document.getElementById('hold-root');
  var menuRoot = document.getElementById('menu-root');
  var jobHud = document.getElementById('job-hud');

  function el(id) {
    return document.getElementById(id);
  }

  function resourceName() {
    return typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-electrician';
  }

  function post(endpoint, payload) {
    return fetch('https://' + resourceName() + '/' + endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload || {})
    }).catch(function () { return null; });
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, Number(value) || 0));
  }

  var ctx = {
    title: 'Electrician',
    description: '',
    requirements: [],
    employed: false,
    level: 1,
    panels: 0,
    plates: 0,
    panelGoal: 50,
    plateGoal: 500,
    perPanel: 30,
    perPlate: 300,
    perOutage: 1000,
  };

  var LEVEL_TITLES = {
    1: { title: 'Switchboard Technician', subtitle: 'Repair panels at the power plant to advance.' },
    2: { title: 'Field Electrician', subtitle: 'Rent the service truck and repair deposit plates around the city.' },
    3: { title: 'Senior Electrician', subtitle: 'You are certified to respond to city-wide power outages.' },
  };

  function render() {
    el('jobTitle').textContent = String(ctx.title || 'Electrician');
    el('jobDescription').textContent = String(ctx.description || '');

    var list = el('requirementsList');
    list.innerHTML = '';
    (ctx.requirements || []).forEach(function (req) {
      var li = document.createElement('li');
      li.textContent = String(req);
      list.appendChild(li);
    });

    var badge = el('statusBadge');
    badge.classList.toggle('on', ctx.employed === true);
    badge.innerHTML = '<i></i> ' + (ctx.employed ? 'ON DUTY' : 'OFF DUTY');

    var level = clamp(ctx.level, 1, 3);
    el('levelValue').textContent = String(level);
    var info = LEVEL_TITLES[level] || LEVEL_TITLES[1];
    el('levelTitle').textContent = info.title;
    el('levelSubtitle').textContent = info.subtitle;

    el('panelsValue').textContent = String(ctx.panels || 0);
    el('panelGoalValue').textContent = String(ctx.panelGoal || 50);
    var panelPct = level >= 2 ? 100 : clamp(((ctx.panels || 0) / (ctx.panelGoal || 50)) * 100, 0, 100);
    el('panelsFill').style.width = panelPct + '%';

    var platesProgress = el('platesProgress');
    platesProgress.classList.toggle('hidden', level < 2);
    el('platesValue').textContent = String(ctx.plates || 0);
    el('plateGoalValue').textContent = String(ctx.plateGoal || 500);
    var platePct = level >= 3 ? 100 : clamp(((ctx.plates || 0) / (ctx.plateGoal || 500)) * 100, 0, 100);
    el('platesFill').style.width = platePct + '%';

    el('perPanelValue').textContent = String(ctx.perPanel || 0);
    el('perPlateValue').textContent = String(ctx.perPlate || 0);
    el('perOutageValue').textContent = String(ctx.perOutage || 0);
    el('perPlateCard').classList.toggle('locked', level < 2);
    el('perOutageCard').classList.toggle('locked', level < 3);

    var button = el('btnToggle');
    el('toggleButtonText').textContent = ctx.employed ? 'Resign' : 'Get employed';
    button.classList.toggle('leave', ctx.employed === true);
  }

  function setRootVisible(root, visible) {
    root.classList.toggle('hidden', !visible);
    root.setAttribute('aria-hidden', visible ? 'false' : 'true');
  }

  function openMenu(newCtx) {
    ctx = Object.assign({}, ctx, newCtx || {});
    render();
    setRootVisible(menuRoot, true);
  }

  function closeMenu(sendClose) {
    setRootVisible(menuRoot, false);
    if (sendClose) post('close');
  }

  function updateJobHud(data) {
    if (!data.visible) {
      setRootVisible(jobHud, false);
      return;
    }
    el('hudLevel').textContent = String(data.level || 1);
    el('hudPanels').textContent = String(data.panels || 0);
    el('hudPlates').textContent = String(data.plates || 0);
    el('hudPlatesRow').classList.toggle('hidden', !data.showPlates);
    setRootVisible(jobHud, true);
  }

  function updateInteraction(data) {
    if (!data.visible) {
      setRootVisible(interaction, false);
      return;
    }
    el('interactionKey').textContent = String(data.key || 'E');
    el('interactionTitle').textContent = String(data.title || 'ELECTRICIAN').toUpperCase();
    el('interactionLabel').textContent = String(data.label || '');
    el('interactionHint').textContent = String(data.hint || '');
    setRootVisible(interaction, true);
  }

  el('btnToggle').addEventListener('click', function () {
    post('toggleEmployment');
  });

  el('btnClose').addEventListener('click', function () {
    closeMenu(true);
  });

  document.addEventListener('keydown', function (event) {
    if ((event.key === 'Escape' || event.key === 'Backspace') && !menuRoot.classList.contains('hidden')) {
      event.preventDefault();
      closeMenu(false);
      post('escape');
    }
  });

  window.addEventListener('message', function (event) {
    var data = event.data || {};

    if (data.action === 'interaction') updateInteraction(data);
    if (data.action === 'openMenu') openMenu(data.ctx || {});
    if (data.action === 'closeMenu') closeMenu(false);
    if (data.action === 'jobHud') updateJobHud(data);

    if (data.action === 'updateStatus') {
      ctx = Object.assign({}, ctx, {
        level: data.level, panels: data.panels, plates: data.plates, employed: data.employed,
      });
      render();
    }

    if (data.action === 'employmentResult') {
      ctx.employed = data.employed === true;
      render();
    }

    if (data.action === 'holdStart') {
      el('holdFill').style.width = '0%';
      setRootVisible(holdRoot, true);
    }

    if (data.action === 'holdProgress') {
      el('holdFill').style.width = clamp(data.progress, 0, 100) + '%';
    }

    if (data.action === 'holdEnd') {
      setRootVisible(holdRoot, false);
    }
  });

  setRootVisible(interaction, false);
  setRootVisible(holdRoot, false);
  setRootVisible(menuRoot, false);
  setRootVisible(jobHud, false);
  render();

  var readyConfirmed = false;
  function announceReady() {
    if (readyConfirmed) return;
    post('ready').then(function () { readyConfirmed = true; });
  }
  announceReady();
  setTimeout(announceReady, 250);
  setInterval(announceReady, 1500);

  // Browser-only preview for design checks: index.html?preview=1
  try {
    if (new URLSearchParams(window.location.search).get('preview') === '1') {
      openMenu({
        title: 'Electrician',
        description: 'Report to the power plant switchboard to start troubleshooting. Repairing panels builds your skill.',
        requirements: ['No licence required', 'Government-inspected job site', 'Payroll paid directly in cash'],
        employed: true,
        level: 2,
        panels: 50,
        plates: 120,
        panelGoal: 50,
        plateGoal: 500,
        perPanel: 30,
        perPlate: 300,
        perOutage: 1000,
      });
      updateJobHud({ visible: true, level: 2, panels: 50, plates: 120, showPlates: true });
    }
  } catch (_) {}
})();
