(() => {
  const map = document.getElementById('liveOpsMap');
  if (!map) return;
  const unitsBox = document.getElementById('liveOpsUnits');
  const count = document.getElementById('liveOpsUnitCount');
  const status = document.getElementById('liveOpsStatus');
  const callsign = document.getElementById('liveOpsCallsign');
  const assignment = document.getElementById('liveOpsAssignment');
  const callSelect = document.getElementById('liveOpsCallSelect');
  const unitSelect = document.getElementById('liveOpsUnitSelect');
  const prioritySelect = document.getElementById('liveOpsPriority');
  let live = { units: [], canCommand: false, selfCharacterId: null };
  let loading = false;
  const liveNotice = (message, kind) => {
    if (typeof notice === 'function') notice(message, kind);
    else if (typeof showToast === 'function') showToast('Live Operations', message, kind);
  };

  const dispatchVisible = () => {
    const view = document.getElementById('dispatchView') || document.querySelector('[data-view="dispatch"]');
    return view && !view.classList.contains('hidden') && !view.hidden && (view.classList.contains('active') || view.id === 'dispatchView');
  };
  const pct = (value, min, max) => Math.max(3, Math.min(97, ((Number(value || 0) - min) / (max - min)) * 100));
  const label = value => String(value || 'available').replaceAll('_', ' ').replace(/\b\w/g, c => c.toUpperCase());
  const selectedCall = () => (dispatchActiveCalls || []).find(call => Number(call.id) === Number(callSelect.value));
  const distanceToCall = (unit, call = selectedCall()) => {
    if (!call?.coords || !Number.isFinite(Number(unit.x)) || !Number.isFinite(Number(unit.y))) return null;
    return Math.hypot(Number(unit.x) - Number(call.coords.x), Number(unit.y) - Number(call.coords.y));
  };
  const distanceLabel = distance => distance == null ? 'DISTANCE UNKNOWN' : distance < 1000 ? `${Math.round(distance)} M` : `${(distance / 1000).toFixed(1)} KM`;

  function renderMap() {
    map.querySelectorAll('.liveops-dot,.liveops-empty').forEach(node => node.remove());
    const located = (live.units || []).filter(unit => Number.isFinite(Number(unit.x)) && Number.isFinite(Number(unit.y)));
    if (!located.length) {
      map.insertAdjacentHTML('beforeend', '<div class="liveops-empty">NO VERIFIED UNIT POSITIONS</div>');
      return;
    }
    located.forEach(unit => {
      const dot = document.createElement('button');
      dot.type = 'button';
      dot.className = `liveops-dot ${unit.status || 'available'}${unit.characterId === live.selfCharacterId ? ' self' : ''}`;
      dot.style.left = `${pct(unit.x, -4000, 4500)}%`;
      dot.style.top = `${100 - pct(unit.y, -4000, 8000)}%`;
      dot.dataset.liveopsRoute = unit.characterId;
      dot.title = `${unit.callsign} · ${unit.name} · ${label(unit.status)}`;
      dot.innerHTML = `<span>${esc(unit.callsign)}</span>`;
      map.appendChild(dot);
    });
  }

  function renderUnits() {
    count.textContent = String((live.units || []).length);
    const ranked = [...(live.units || [])].map(unit => ({ ...unit, distance: distanceToCall(unit) })).sort((a, b) => (a.distance ?? Infinity) - (b.distance ?? Infinity));
    const nearestCid = ranked.find(unit => unit.status === 'available' && !unit.assignedCallId && unit.distance != null)?.characterId;
    unitsBox.innerHTML = ranked.map(unit => `<article class="liveops-unit ${esc(unit.status)}${unit.characterId === nearestCid ? ' liveops-nearest' : ''}">
      <i></i><div><strong>${esc(unit.callsign)} · ${esc(unit.name)}</strong><small>${esc(unit.organizationLabel)} · ${esc(unit.rankName || 'Member')} · ${label(unit.status)}${unit.assignedCallId ? ` · CALL #${Number(unit.assignedCallId)}` : ''}</small>${unit.distance != null ? `<small class="liveops-unit-distance">${unit.characterId === nearestCid ? 'NEAREST · ' : ''}${distanceLabel(unit.distance)}</small>` : ''}</div>
      <div class="liveops-unit-actions"><button data-liveops-route="${esc(unit.characterId)}">ROUTE</button>${unit.characterId === live.selfCharacterId && unit.assignedCallId && unit.status !== 'on_scene' ? `<button class="scene" data-liveops-scene="${Number(unit.assignedCallId)}">ON SCENE</button>` : ''}${unit.assignedCallId && (live.canCommand || unit.characterId === live.selfCharacterId) ? `<button class="release" data-liveops-release="${esc(unit.characterId)}" data-liveops-call="${Number(unit.assignedCallId)}">${unit.characterId === live.selfCharacterId ? 'CLEAR' : 'RELEASE'}</button>` : ''}</div>
    </article>`).join('') || '<div class="liveops-empty">NO UNITS ON DUTY</div>';
  }

  function renderUnitOptions() {
    const available = (live.units || []).filter(unit => unit.status === 'available' && !unit.assignedCallId).map(unit => ({ ...unit, distance: distanceToCall(unit) })).sort((a, b) => (a.distance ?? Infinity) - (b.distance ?? Infinity));
    unitSelect.innerHTML = available.map((unit, index) => `<option value="${esc(unit.characterId)}">${index === 0 && unit.distance != null ? 'NEAREST · ' : ''}${esc(unit.callsign)} · ${esc(unit.name)} · ${distanceLabel(unit.distance)}</option>`).join('') || '<option value="">No available units</option>';
    const call = selectedCall();
    if (call && prioritySelect) prioritySelect.value = String(Number(call.priority || 1));
  }

  function renderAssignment() {
    assignment.classList.toggle('hidden', live.canCommand !== true);
    if (!live.canCommand) return;
    const previousCall = callSelect.value;
    callSelect.innerHTML = (dispatchActiveCalls || []).map(call => `<option value="${Number(call.id)}">P${Number(call.priority || 1)} · #${Number(call.id)} · ${esc(call.location || call.details)}</option>`).join('') || '<option value="">No active calls</option>';
    if ([...callSelect.options].some(option => option.value === previousCall)) callSelect.value = previousCall;
    renderUnitOptions();
  }

  function renderLive() {
    if (document.activeElement !== callsign) callsign.value = live.selfCallsign || '';
    status.value = ['available', 'busy', 'unavailable', 'en_route', 'on_scene'].includes(live.selfStatus) ? live.selfStatus : 'available';
    document.getElementById('liveOpsRefreshed').textContent = `LIVE · ${new Date().toLocaleTimeString([], {hour:'2-digit', minute:'2-digit', second:'2-digit'})}`;
    renderMap(); renderAssignment(); renderUnits();
  }

  async function loadLiveOperations() {
    if (loading || !dispatchVisible()) return;
    loading = true;
    try {
      const result = await post('dispatchLiveOperations');
      if (result?.ok) { live = result; renderLive(); }
    } finally { loading = false; }
  }

  async function action(name, payload) {
    const result = await post(name, payload);
    liveNotice(result?.message || result?.error || 'Live operations request failed.', result?.ok ? 'success' : 'error');
    if (result?.ok) { if (typeof loadDispatchActiveCalls === 'function') await loadDispatchActiveCalls(); await loadLiveOperations(); }
  }

  status.addEventListener('change', () => action('setUnitStatus', { status: status.value }));
  document.getElementById('liveOpsCallsignSave').addEventListener('click', () => action('setUnitCallsign', { callsign: callsign.value }));
  document.getElementById('liveOpsAssign').addEventListener('click', () => {
    if (!callSelect.value || !unitSelect.value) return liveNotice('Select an active call and available unit.', 'error');
    action('dispatchAssignUnit', { callId: Number(callSelect.value), characterId: unitSelect.value });
  });
  callSelect.addEventListener('change', () => { renderUnitOptions(); renderUnits(); });
  document.getElementById('liveOpsSetPriority')?.addEventListener('click', () => {
    if (!callSelect.value) return liveNotice('Select an active call.', 'error');
    action('dispatchSetPriority', { callId: Number(callSelect.value), priority: Number(prioritySelect.value) });
  });
  document.getElementById('liveOpsCloseCall')?.addEventListener('click', async () => {
    if (!callSelect.value) return liveNotice('Select an active call.', 'error');
    const confirmed = typeof showConfirmOverlay === 'function'
      ? await showConfirmOverlay('Command Close', `Close call #${callSelect.value} and release every assigned unit?`, 'Close Call', 'Cancel')
      : window.confirm(`Close call #${callSelect.value} and release every assigned unit?`);
    if (confirmed) action('dispatchResolve', { callId: Number(callSelect.value), resolution: 'Closed by incident command' });
  });
  document.addEventListener('click', async event => {
    const route = event.target.closest('[data-liveops-route]');
    const scene = event.target.closest('[data-liveops-scene]');
    const release = event.target.closest('[data-liveops-release]');
    if (route) action('dispatchRouteUnit', { characterId: route.dataset.liveopsRoute });
    if (scene) action('dispatchOnScene', { callId: Number(scene.dataset.liveopsScene) });
    if (release) {
      const isSelf = release.dataset.liveopsRelease === live.selfCharacterId;
      const confirmed = isSelf || (typeof showConfirmOverlay === 'function'
        ? await showConfirmOverlay('Release Unit', 'Release this unit from its active call?', 'Release', 'Cancel')
        : window.confirm('Release this unit from its active call?'));
      if (confirmed) action('dispatchReleaseUnit', { callId: Number(release.dataset.liveopsCall), characterId: release.dataset.liveopsRelease });
    }
    const tab = event.target.closest('[data-tab="dispatch"],[data-page="dispatch"]');
    if (tab) setTimeout(loadLiveOperations, 50);
  });
  window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'liveOperationsRefresh' || data.action === 'dispatchRefresh') loadLiveOperations();
    if (data.action === 'open' && (data.initialTab === 'dispatch' || data.initialPage === 'dispatch')) setTimeout(loadLiveOperations, 50);
  });
  setInterval(loadLiveOperations, 3500);
})();
