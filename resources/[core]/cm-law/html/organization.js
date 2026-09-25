/* F6 Organization Hub. Layout is owned by cm-ui; mutations remain server-authoritative. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const esc = value => window.CMUI.safeText(value);
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-law';
  const preview = typeof GetParentResourceName !== 'function'
    && ['http:', 'https:', 'file:'].includes(location.protocol)
    && !location.hostname.startsWith('cfx-nui-') && new URLSearchParams(location.search).has('preview');
  let state = null, currentTab = 'dashboard', selectedRank = null, editingMember = null, editingRank = null, rankDraft = null;
  let actionPending = false, epoch = 0, noticeTimer, lastEscape = 0;

  async function post(name, data = {}) {
    if (preview) return { ok: false, error: 'Design preview is read-only.' };
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(`https://${resource}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data), signal: controller.signal,
      });
      if (!response.ok) return { ok: false, error: 'The organization service did not respond.' };
      return await response.json();
    } catch (_) { return { ok: false, error: 'The request timed out. Refresh before trying again.' }; }
    finally { clearTimeout(timeout); }
  }
  function notice(message, error = false) {
    $('hub-notice').textContent = message || '';
    $('hub-notice').classList.toggle('is-error', error);
    $('hub-notice').hidden = !message;
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => { $('hub-notice').hidden = true; }, 5000);
  }
  const ranks = () => [...(state?.ranks || [])].sort((a, b) => Number(b.tier) - Number(a.tier));
  const isPolice = () => state?.source === 'cm-police';
  const actorHas = permission => state?.member?.isLeader === true || state?.member?.permissions?.[permission] === true;
  const ownId = () => String(state?.characterId || state?.member?.characterId || '');
  const canManageMember = member => !!member && !member.is_leader && String(member.character_id) !== ownId()
    && !state?.member?.suspended && Number(member.tier) < Number(state?.member?.tier)
    && state?.canManage === true;
  function editableRanks(member) {
    const all = ranks().filter(rank => !rank.is_leader && Number(rank.tier) < Number(state?.member?.tier));
    if (!isPolice()) return all;
    const higher = all.filter(rank => Number(rank.tier) > Number(member.tier)).at(-1);
    const lower = all.find(rank => Number(rank.tier) < Number(member.tier));
    return all.filter(rank => Number(rank.id) === Number(member.rank_id)
      || (actorHas('police.promote') && rank === higher) || (actorHas('police.demote') && rank === lower));
  }
  function render(data) {
    if (!data?.ok) { notice(data?.error || 'Organization access is unavailable.', true); return; }
    state = data;
    const org = data.organization || {}, summary = data.summary || {}, members = data.roster || [];
    const details = org.hub || {}, leader = members.find(member => member.is_leader);
    $('org-subtitle').textContent = `${org.label || 'Organization'} • Personnel Portal`;
    $('org-name').textContent = org.label || 'Organization';
    $('org-tagline').textContent = details.tagline || org.jurisdiction || 'Law Enforcement & Tactical Response Command';
    $('total-count').textContent = `${Number(summary.memberCount ?? members.length)} Members`;
    const online = summary.onlineCount ?? (data.canViewMembers ? members.filter(member => member.online === true).length : null);
    $('active-count').textContent = online == null ? 'Restricted' : `${online} Online`;
    $('org-balance').textContent = summary.balance == null ? 'Not set' : `$${Number(summary.balance).toLocaleString('en-US')}`;
    $('org-personnel').textContent = `${Number(summary.onDutyCount || 0)} Active`;
    $('org-fleet').textContent = `${Number(summary.fleetConfigured || 0)} Vehicles`;
    $('org-rating').textContent = details.rating || 'Not set';
    $('org-announcement').textContent = details.announcement || 'No announcement has been published.';
    $('org-leader').textContent = summary.leaderName || org.leaderName || leader?.name || 'Not assigned';
    $('org-leader-rank').textContent = leader?.rank_name ? `${leader.rank_name} (Leader)` : 'Organization Leader';
    $('org-founded').textContent = details.founded || 'Not set';
    $('org-hq').textContent = details.headquarters || 'Not set';
    $('org-radio').textContent = details.radioFrequency || org.radioChannel || 'Not set';
    $('org-recruiter').textContent = details.primaryRecruiter || 'Not set';
    const previousFilter = $('rank-filter').value;
    $('rank-filter').innerHTML = '<option value="ALL">All Ranks</option>' + ranks().map(rank => `<option value="${esc(rank.id)}">${esc(rank.name)}</option>`).join('');
    $('rank-filter').value = [...$('rank-filter').options].some(option => option.value === previousFilter) ? previousFilter : 'ALL';
    $('recruit-button').disabled = data.canInvite !== true || actionPending;
    renderRoster(); renderRanks();
    if (currentTab === 'logs') renderLogs(data.recentActivity || []);
    if (editingMember && !members.some(member => String(member.character_id) === editingMember)) closeModal('edit-modal');
  }
  function renderRoster() {
    if (!state) return;
    const query = $('roster-search').value.trim().toLowerCase();
    const rankFilter = $('rank-filter').value, statusFilter = $('status-filter').value;
    const members = (state.roster || []).filter(member => {
      const matches = `${member.name || ''} ${member.character_id} ${member.callsign || ''}`.toLowerCase().includes(query);
      return matches && (rankFilter === 'ALL' || String(member.rank_id) === rankFilter)
        && (statusFilter !== 'ONLINE' || member.online === true)
        && (statusFilter !== 'OFFDUTY' || !member.on_duty);
    });
    $('roster-table-body').innerHTML = members.map(member => {
      const name = member.name || `Character #${member.character_id}`;
      const duty = member.suspended ? 'SUSPENDED' : member.on_duty ? 'ON DUTY' : 'OFF DUTY';
      const onlineKnown = typeof member.online === 'boolean';
      return `<tr><td><div class="player-cell"><div class="avatar">${esc(name.slice(0, 2).toUpperCase())}</div><div><div class="player-name">${esc(name)}</div><div class="player-id">Character ID: #${esc(member.character_id)}</div></div></div></td><td><span class="rank-badge ${member.is_leader ? 'leader' : ''}">${esc(member.rank_name)}</span></td><td><strong>${esc(member.callsign || 'UNASSIGNED')}</strong></td><td><span class="duty-tag ${member.on_duty && !member.suspended ? 'on' : 'off'}">${duty}</span></td><td><span class="status-badge ${member.online ? 'online' : 'offline'}"><span class="status-dot"></span>${onlineKnown ? (member.online ? 'ONLINE' : 'OFFLINE') : 'UNKNOWN'}</span></td><td><div class="action-cell"><button class="btn-icon" type="button" title="Edit Member" aria-label="Edit ${esc(name)}" data-edit-member="${esc(member.character_id)}" ${canManageMember(member) && !actionPending ? '' : 'disabled'}><i class="fa-solid fa-pen-to-square"></i></button></div></td></tr>`;
    }).join('') || `<tr><td class="hub-empty" colspan="6">${state.canViewMembers ? 'No members match your filters.' : 'Your rank does not have roster access.'}</td></tr>`;
  }
  function renderRanks() {
    const available = ranks();
    if (!available.some(rank => String(rank.id) === selectedRank)) selectedRank = String((available[1] || available[0])?.id || '');
    $('rank-selector-list').innerHTML = available.map(rank => `<button type="button" class="rank-item ${String(rank.id) === selectedRank ? 'active' : ''}" data-select-rank="${esc(rank.id)}"><div><div class="rank-item-title">${esc(rank.name)}</div><div class="rank-item-level">Tier ${Number(rank.tier)} Authority</div></div><i class="fa-solid fa-chevron-right" aria-hidden="true"></i></button>`).join('');
    const canCreate = state?.canManageRanks && !state?.member?.suspended && available.length < 12;
    $('add-rank-button').disabled = !canCreate || actionPending;
    renderPermissions();
  }
  function permissionEditable(rank) {
    return rankEditable(rank) && state?.canManagePermissions
      && Object.entries(permissionMap(rank)).every(([key, value]) => value !== true || actorHas(key));
  }
  function rankEditable(rank) {
    return state?.canManageRanks && !state.member?.suspended
      && !rank?.is_leader && Number(rank?.tier) < Number(state.member?.tier)
      && rank?.id != null;
  }
  function permissionMap(rank) {
    const source = rank?.permissions;
    if (Array.isArray(source)) return source.reduce((result, key) => { result[String(key)] = true; return result; }, {});
    return source && typeof source === 'object' ? { ...source } : {};
  }
  function permissionDefinitions() {
    return state?.permissions && typeof state.permissions === 'object' ? state.permissions : {};
  }
  function permissionLabel(key, definition) {
    return typeof definition === 'string' ? definition : definition?.label || key;
  }
  function permissionDescription(key, definition) {
    return typeof definition === 'object' && definition?.description
      ? definition.description
      : `Allow members of this rank to ${String(permissionLabel(key, definition)).toLowerCase()}.`;
  }
  function renderPermissions() {
    const rank = ranks().find(row => String(row.id) === selectedRank);
    $('selected-rank-title').textContent = rank ? `${rank.name} Access Level` : 'Rank Access';
    const editable = !!rank && rankEditable(rank);
    $('edit-rank-button').disabled = !editable || actionPending;
    if (!rank || state.canInspectRankPermissions !== true) {
      $('permission-grid').innerHTML = '<p class="hub-permission-hint">Permission details are restricted to authorized command staff.</p>';
      return;
    }
    const definitions = permissionDefinitions(), assigned = Object.keys(permissionMap(rank)).filter(key => permissionMap(rank)[key] === true);
    $('permission-grid').innerHTML = assigned.length
      ? `<div class="perm-summary">${assigned.map(key => `<span class="perm-summary-chip">${esc(permissionLabel(key, definitions[key]) || key)}</span>`).join('')}</div>`
      : '<p class="hub-permission-hint">No permissions assigned to this rank.</p>';
    if (!editable && editingRank) closeRankEditor();
    if (editingRank) renderRankEditor();
  }
  function rankTierOptions(selected) {
    return Array.from({ length: 12 }, (_, index) => index + 1).map(tier => `<option value="${tier}" ${Number(selected) === tier ? 'selected' : ''}>${tier}</option>`).join('');
  }
  function renderRankEditor() {
    const editor = $('rank-editor');
    if (!editingRank || !rankDraft) { editor.hidden = true; return; }
    editor.hidden = false;
    $('rank-editor-name').value = rankDraft.name || '';
    $('rank-editor-tier').innerHTML = rankTierOptions(rankDraft.tier);
    const definitions = permissionDefinitions();
    const assigned = new Set(rankDraft.permissions || []);
    const available = Object.keys(definitions).filter(key => !assigned.has(key));
    const canEditPermissions = state?.canManagePermissions === true;
    const chip = (key, remove) => `<div class="permission-chip ${actorHas(key) && canEditPermissions ? '' : 'is-locked'}" draggable="${actorHas(key) && canEditPermissions}" data-permission-chip="${esc(key)}"><i class="fa-solid fa-grip-vertical" aria-hidden="true"></i><span><strong>${esc(permissionLabel(key, definitions[key]))}</strong><small>${esc(permissionDescription(key, definitions[key]))}</small></span>${remove && actorHas(key) && canEditPermissions ? `<button type="button" class="permission-chip-remove" title="Remove permission" aria-label="Remove ${esc(permissionLabel(key, definitions[key]))}" data-remove-permission="${esc(key)}">×</button>` : ''}</div>`;
    $('permission-pool').innerHTML = available.map(key => chip(key, false)).join('') || '<div class="permission-empty">All available permissions are assigned.</div>';
    $('permission-assigned').innerHTML = (rankDraft.permissions || []).map(key => chip(key, true)).join('') || '<div class="permission-empty">Drop permissions here.</div>';
    const target = ranks().find(row => String(row.id) === String(editingRank));
    $('save-rank-button').disabled = actionPending || !(editingRank === 'new'
      ? state?.canManageRanks && !state?.member?.suspended
      : rankEditable(target));
    const deleteBtn = $('delete-rank-button');
    if (deleteBtn) {
      deleteBtn.hidden = editingRank === 'new' || !target || target.is_leader;
      deleteBtn.disabled = actionPending || !rankEditable(target);
    }
    bindPermissionDnD();
  }
  function openRankEditor() {
    const rank = ranks().find(row => String(row.id) === selectedRank);
    if (!rank || !rankEditable(rank) || actionPending) return;
    editingRank = String(rank.id);
    rankDraft = { id: rank.id, name: rank.name, tier: Number(rank.tier), permissions: Object.keys(permissionMap(rank)).filter(key => permissionMap(rank)[key] === true) };
    renderRankEditor(); $('rank-editor-name').focus();
  }
  function newRank() {
    if (!state?.canManageRanks || state.member?.suspended || ranks().length >= 12 || actionPending) return;
    editingRank = 'new';
    rankDraft = { id: null, name: 'New Rank', tier: 1, permissions: [] };
    renderRankEditor(); $('rank-editor-name').focus();
  }
  function closeRankEditor() { editingRank = null; rankDraft = null; $('rank-editor').hidden = true; }
  function addDraftPermission(key) {
    if (!rankDraft || !state?.canManagePermissions || !actorHas(key)) return;
    if (!rankDraft.permissions.includes(key)) rankDraft.permissions.push(key);
    renderRankEditor();
  }
  function removeDraftPermission(key) {
    if (!rankDraft) return;
    rankDraft.permissions = rankDraft.permissions.filter(item => item !== key);
    renderRankEditor();
  }
  function bindPermissionDnD() {
    document.querySelectorAll('[data-permission-chip]').forEach(chip => {
      chip.addEventListener('dragstart', event => { event.dataTransfer.setData('text/plain', chip.dataset.permissionChip); chip.classList.add('is-dragging'); });
      chip.addEventListener('dragend', () => chip.classList.remove('is-dragging'));
      chip.addEventListener('click', event => { if (event.target.closest('[data-remove-permission]')) return; if (chip.closest('#permission-pool')) addDraftPermission(chip.dataset.permissionChip); });
    });
    document.querySelectorAll('[data-drop-zone]').forEach(zone => {
      if (zone.dataset.bound === 'true') return;
      zone.dataset.bound = 'true';
      zone.addEventListener('dragover', event => { event.preventDefault(); zone.classList.add('is-over'); });
      zone.addEventListener('dragleave', () => zone.classList.remove('is-over'));
      zone.addEventListener('drop', event => { event.preventDefault(); zone.classList.remove('is-over'); const key = event.dataTransfer.getData('text/plain'); if (zone.dataset.dropZone === 'assigned') addDraftPermission(key); else removeDraftPermission(key); });
    });
    document.querySelectorAll('[data-remove-permission]').forEach(button => button.addEventListener('click', () => removeDraftPermission(button.dataset.removePermission)));
  }
  function renderLogs(rows) {
    if (state?.canViewActivity !== true) {
      $('audit-body').innerHTML = '<tr><td colspan="4" class="hub-empty">Audit logs are restricted to authorized command staff.</td></tr>'; return;
    }
    const labels = { member_promoted: 'PROMOTED', member_demoted: 'DEMOTED', member_rank: 'RANK CHANGED', member_fire: 'REMOVED', member_removed: 'REMOVED', invite_sent: 'INVITED', invite_accepted: 'RECRUITED', rank_edited: 'RANK UPDATED', rank_updated: 'RANK UPDATED' };
    $('audit-body').innerHTML = rows.map(row => {
      const detail = row.detail && typeof row.detail === 'object' ? row.detail : {};
      const target = (state.roster || []).find(member => String(member.character_id) === String(detail.targetCid));
      const rank = ranks().find(item => Number(item.id) === Number(detail.rankId));
      const name = detail.targetName || target?.name || (detail.targetCid ? `Character #${detail.targetCid}` : detail.name || '—');
      const targetText = `${name}${detail.rank || rank?.name ? ` → ${detail.rank || rank.name}` : ''}`;
      const action = labels[row.action] || String(row.action || 'Activity').replaceAll('_', ' ').toUpperCase();
      let timestamp = String(row.createdAt || '');
      if (/^\d{10,13}$/.test(timestamp)) timestamp = new Date(Number(timestamp) * (timestamp.length === 10 ? 1000 : 1)).toLocaleString();
      return `<tr><td>${esc(timestamp)}</td><td class="player-name">${esc(row.actorName || 'System')}</td><td><span class="status-badge ${['member_promoted', 'invite_accepted'].includes(row.action) ? 'online' : 'offline'}">${esc(action)}</span></td><td>${esc(targetText)}</td></tr>`;
    }).join('') || '<tr><td colspan="4" class="hub-empty">No organization activity recorded yet.</td></tr>';
  }
  async function loadLogs() {
    if (!state?.canViewActivity) return renderLogs([]);
    if (preview || isPolice()) return renderLogs(state.recentActivity || []);
    const generation = epoch;
    const result = await post('activityLog');
    if (generation !== epoch || document.body.hidden) return;
    if (result?.ok === false) notice(result.error, true);
    else renderLogs(result.list || []);
  }
  function switchTab(tab, button) {
    if (!['dashboard', 'roster', 'ranks', 'logs'].includes(tab)) return;
    currentTab = tab;
    document.querySelectorAll('.nav-tab').forEach(node => node.classList.toggle('active', node.dataset.tab === tab));
    document.querySelectorAll('.tab-panel').forEach(node => node.classList.toggle('active', node.id === `panel-${tab}`));
    if (tab === 'logs') loadLogs();
  }
  function closeModal(id) {
    $(id)?.classList.remove('active');
    if (id === 'edit-modal') editingMember = null;
    if (!document.body.hidden) document.querySelector(`.nav-tab[data-tab="${currentTab}"]`)?.focus();
  }
  function openEditModal(id) {
    const member = (state?.roster || []).find(row => String(row.character_id) === String(id));
    if (!canManageMember(member) || actionPending) return;
    editingMember = String(id);
    $('modal-name').value = member.name || `Character #${id}`;
    $('modal-rank').innerHTML = editableRanks(member).map(rank => `<option value="${esc(rank.id)}" ${Number(rank.id) === Number(member.rank_id) ? 'selected' : ''}>${esc(rank.name)}</option>`).join('');
    $('modal-callsign').value = member.callsign || 'UNASSIGNED';
    $('kick-member').disabled = isPolice() && !actorHas('police.kick');
    $('save-member').disabled = $('modal-rank').options.length < 2;
    $('edit-modal').classList.add('active'); $('modal-rank').focus();
  }
  async function mutate(name, payload) {
    if (actionPending) return { ok: false, error: 'An organization request is already in progress.' };
    actionPending = true;
    const generation = epoch;
    try {
      const result = await post(name, payload);
      if (result?.ok && generation === epoch && !document.body.hidden) {
        const fresh = await post('refresh');
        if (fresh?.ok && generation === epoch && !document.body.hidden) render(fresh);
      }
      return result;
    } finally {
      actionPending = false;
      if (!document.body.hidden && state) { renderRoster(); $('recruit-button').disabled = state.canInvite !== true; renderPermissions(); }
    }
  }
  async function saveMemberEdit() {
    const member = (state?.roster || []).find(row => String(row.character_id) === editingMember);
    if (!canManageMember(member) || actionPending) return;
    const rank = editableRanks(member).find(row => String(row.id) === $('modal-rank').value);
    if (!rank || Number(rank.id) === Number(member.rank_id)) return closeModal('edit-modal');
    const policeAction = Number(rank.tier) > Number(member.tier) ? 'promote' : 'demote';
    const success = await CMUI.confirmOrganizationAction({
      title: 'CONFIRM RANK CHANGE', message: `Assign ${member.name} to ${rank.name}?`,
      consequence: 'Their rank access will change immediately.',
      submit: () => isPolice() ? mutate('police_action', { action: policeAction, payload: { characterId: member.character_id } })
        : mutate('staffAction', { action: 'rank', characterId: member.character_id, rankId: Number(rank.id) }),
    });
    if (success) closeModal('edit-modal');
  }
  async function kickMember() {
    const member = (state?.roster || []).find(row => String(row.character_id) === editingMember);
    if (!canManageMember(member) || actionPending || (isPolice() && !actorHas('police.kick'))) return;
    const success = await CMUI.confirmOrganizationAction({
      title: 'REMOVE MEMBER', message: `Remove ${member.name} (Character #${member.character_id}) from ${state.organization.label}?`,
      consequence: 'Membership and organization access will be revoked. A new invitation will be required to rejoin.', danger: true,
      submit: () => isPolice() ? mutate('police_action', { action: 'kick', payload: { characterId: member.character_id } })
        : mutate('staffAction', { action: 'fire', characterId: member.character_id }),
    });
    if (success) closeModal('edit-modal');
  }
  function openInviteModal() {
    if (!state?.canInvite || actionPending) return;
    const entry = ranks().filter(rank => !rank.is_leader).at(-1);
    $('recruit-rank').innerHTML = entry ? `<option value="${esc(entry.id)}">${esc(entry.name)}</option>` : '<option>No entry rank configured</option>';
    $('send-invite').disabled = !entry;
    $('recruit-id').value = '';
    $('invite-modal').classList.add('active'); $('recruit-id').focus();
  }
  async function confirmRecruit() {
    if (!state?.canInvite || actionPending) return;
    const id = $('recruit-id').value.trim();
    if (!/^[a-zA-Z0-9_-]{1,64}$/.test(id)) return notice('Enter a valid character ID.', true);
    const entry = ranks().filter(rank => !rank.is_leader).at(-1);
    if (!entry) return;
    const success = await CMUI.confirmOrganizationAction({
      title: 'SEND RECRUITMENT OFFER', message: `Invite Character #${id} to ${state.organization.label} as ${entry.name}?`,
      consequence: 'The player must be nearby and must accept before joining.',
      submit: () => mutate('hubInvite', { characterId: id }),
    });
    if (success) closeModal('invite-modal');
  }
  async function saveRankEditor() {
    if (!rankDraft || actionPending) return;
    const rank = ranks().find(row => String(row.id) === String(editingRank));
    const canEdit = editingRank === 'new'
      ? state?.canManageRanks && !state?.member?.suspended
      : rankEditable(rank);
    if (!canEdit) return;
    const name = $('rank-editor-name').value.trim();
    const tier = Number($('rank-editor-tier').value);
    if (!name || !Number.isInteger(tier) || tier < 1 || tier > 12) return notice('Enter a rank name and choose a tier from 1 to 12.', true);
    const payload = { rankId: rankDraft.id, name, tier };
    if (state?.canManagePermissions) {
      payload.permissions = {};
      (rankDraft.permissions || []).forEach(key => { payload.permissions[key] = true; });
    }
    const success = await CMUI.confirmOrganizationAction({
      title: editingRank === 'new' ? 'CREATE RANK' : 'SAVE RANK',
      message: `${editingRank === 'new' ? 'Create' : 'Save'} ${name} at Tier ${tier}?`,
      consequence: 'The rank name, tier, and permissions will apply immediately to members assigned to it.',
      submit: () => isPolice() ? mutate('police_action', { action: 'save_rank', payload }) : mutate('saveRank', payload),
    });
    if (success) closeRankEditor();
  }
  async function deleteRankEditor() {
    if (!editingRank || editingRank === 'new' || actionPending) return;
    const rank = ranks().find(row => String(row.id) === String(editingRank));
    if (!rank || !rankEditable(rank) || rank.is_leader) return;
    const success = await CMUI.confirmOrganizationAction({
      title: 'DELETE RANK',
      message: `Permanently delete ${rank.name}?`,
      consequence: 'Any members assigned to this rank must be reassigned first.',
      danger: true,
      submit: () => isPolice()
        ? mutate('police_action', { action: 'delete_rank', payload: { rankId: rank.id } })
        : mutate('deleteRank', { rankId: rank.id }),
    });
    if (success) closeRankEditor();
  }
  function hide() {
    epoch++;
    document.body.hidden = true;
    CMUI.cancelOrganizationConfirm();
    document.querySelectorAll('.modal-overlay').forEach(node => node.classList.remove('active'));
    editingMember = null; $('hub-notice').hidden = true;
  }
  function handleEscape() {
    const now = Date.now();
    if (now - lastEscape < 180 || document.body.hidden) return;
    lastEscape = now;
    if (CMUI.cancelOrganizationConfirm()) return;
    const modal = document.querySelector('.modal-overlay.active');
    if (modal) return closeModal(modal.id);
    hide(); post('close');
  }
  window.cmHandleEscape = handleEscape;
  Object.assign(window, { switchTab, filterRoster: renderRoster, closeModal, openEditModal, saveMemberEdit, kickMember, openInviteModal, confirmRecruit, openRankEditor, newRank, closeRankEditor, saveRankEditor, deleteRankEditor });
  $('roster-table-body').addEventListener('click', event => {
    const button = event.target.closest('[data-edit-member]');
    if (button) openEditModal(button.dataset.editMember);
  });
  $('rank-selector-list').addEventListener('click', event => {
    const button = event.target.closest('[data-select-rank]');
    if (!button || actionPending) return;
    selectedRank = button.dataset.selectRank; renderRanks();
  });
  document.querySelectorAll('.modal-overlay').forEach(modal => modal.addEventListener('click', event => { if (event.target === modal && !actionPending) closeModal(modal.id); }));
  window.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !event.repeat) { event.preventDefault(); handleEscape(); }
  });
  window.addEventListener('message', event => {
    const message = event.data || {};
    if (message.action === 'open') {
      if (!message.data?.ok) { hide(); post('close'); return; }
      epoch++; document.body.hidden = false; render(message.data);
      const tab = message.initialTab === 'overview' ? 'dashboard' : message.initialTab || 'dashboard';
      switchTab(tab);
    } else if (message.action === 'dashboard') {
      if (message.data?.ok === false) { hide(); post('close'); } else render(message.data);
    } else if (message.action === 'close') hide();
    else if (message.action === 'escape') handleEscape();
    else if (message.action === 'notice' && !document.body.hidden) notice(message.message, message.kind === 'error');
  });
  if (preview) {
    const script = document.createElement('script');
    script.src = 'organization-preview.js'; document.head.append(script);
  }
})();
