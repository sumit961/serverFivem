(function () {
  'use strict';

  const root = document.getElementById('root');
  const createRoot = document.getElementById('create');
  const content = document.getElementById('content');
  const createContent = document.getElementById('create-content');
  const toast = document.getElementById('invite-toast');
  const adminRoot = document.getElementById('family-admin');
  let adminState = null;

  let state = null;          // last menu snapshot
  let activeTab = 'overview';
  let createSelection = null;

  const RES = (function () {
    // Resource name for NUI fetch. GetParentResourceName is provided by CEF.
    if (typeof GetParentResourceName === 'function') return GetParentResourceName();
    return 'cm-family';
  })();

  function post(cb, data) {
    return fetch(`https://${RES}/${cb}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then(r => r.json()).catch(() => ({ ok: false }));
  }

  const money = n => '$' + (Number(n) || 0).toLocaleString('en-US');
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const formatTimestamp = (value, length = 19) => {
    if (value == null || value === '') return '';
    if (typeof value === 'number' || /^\d{10,13}$/.test(String(value))) {
      const raw = Number(value);
      const date = new Date(raw < 1e12 ? raw * 1000 : raw);
      if (!Number.isNaN(date.getTime())) {
        const pad = n => String(n).padStart(2, '0');
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`.slice(0, length);
      }
    }
    return String(value).replace('T', ' ').slice(0, length);
  };

  const FAMILY_SYMBOLS = {
    crown: '<svg viewBox="0 0 64 64" aria-hidden="true"><path d="M8 47 6 18l14 14 12-23 12 23 14-14-2 29H8Z"/><path d="M10 47h44v9H10z"/></svg>',
    flower: '<svg viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="15" r="12"/><circle cx="47" cy="24" r="12"/><circle cx="47" cy="41" r="12"/><circle cx="32" cy="49" r="12"/><circle cx="17" cy="41" r="12"/><circle cx="17" cy="24" r="12"/><circle cx="32" cy="32" r="10"/></svg>',
    star: '<svg viewBox="0 0 64 64" aria-hidden="true"><path d="m32 5 8 17 19 2-14 13 4 19-17-9-17 9 4-19L5 24l19-2 8-17Z"/></svg>',
    shield: '<svg viewBox="0 0 64 64" aria-hidden="true"><path d="M32 5 55 13v18c0 14-8 23-23 29C17 54 9 45 9 31V13l23-8Z"/></svg>',
    diamond: '<svg viewBox="0 0 64 64" aria-hidden="true"><path d="m32 4 27 28-27 28L5 32 32 4Z"/></svg>',
    skull: '<svg viewBox="0 0 64 64"><path d="M12 29a20 20 0 1 1 40 0c0 10-5 16-12 19v10H24V48c-7-3-12-9-12-19Z"/></svg>',
    heart: '<svg viewBox="0 0 64 64"><path d="M32 57 8 35C-7 18 17 1 32 17 47 1 71 18 56 35L32 57Z"/></svg>',
    bolt: '<svg viewBox="0 0 64 64"><path d="M37 3 13 37h17l-4 24 25-36H34l3-22Z"/></svg>',
    moon: '<svg viewBox="0 0 64 64"><path d="M48 51A27 27 0 0 1 30 4a25 25 0 1 0 18 47Z"/></svg>',
    sun: '<svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="14"/><path d="M32 3v10M32 51v10M3 32h10M51 32h10M12 12l7 7M45 45l7 7M52 12l-7 7M19 45l-7 7" stroke="currentColor" stroke-width="6"/></svg>',
  };
  const symbolSvg = key => FAMILY_SYMBOLS[key] || FAMILY_SYMBOLS.shield;

  // ---------------- open / close ----------------
  function openMenu(snapshot) {
    state = snapshot;
    createRoot.classList.remove('is-open');
    root.classList.add('is-open');
    root.setAttribute('aria-hidden', 'false');
    renderHeader();
    renderTab(activeTab);
  }

  function openCreate(res) {
    root.classList.remove('is-open');
    createRoot.classList.add('is-open');
    createSelection = null;
    renderCreate(res);
  }

  function closeAll() {
    if (adminRoot.classList.contains('is-open')) {
      adminRoot.classList.remove('is-open');
      post('familyAdminClose', {});
      return;
    }
    root.classList.remove('is-open');
    createRoot.classList.remove('is-open');
    post('close', {});
  }

  // ---------------- header ----------------
  function renderHeader() {
    const f = state.family;
    document.getElementById('family-name').textContent = f.name;
    document.getElementById('family-sub').textContent =
      (f.tag ? '[' + f.tag + ']  ' : '') + state.members.length + ' member' + (state.members.length === 1 ? '' : 's');
    document.getElementById('crest').style.background = f.color || '#00f0ff22';
    document.getElementById('crest').style.borderColor = f.color || '#00f0ff';
  }

  // ---------------- tabs ----------------
  document.getElementById('tabs').addEventListener('click', e => {
    const tab = e.target.closest('.tab');
    if (!tab) return;
    activeTab = tab.dataset.tab;
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t === tab));
    renderTab(activeTab);
  });

  function renderTab(tab) {
    if (!state) return;
    document.body.classList.toggle('armory-mode', tab === 'armory');
    if (tab !== 'armory') armoryManaging = false;
    const titles = { overview: 'Family information', manage: 'Management', members: 'Members', ranks: 'Ranks & access', vehicles: 'Family vehicles', armory: 'Armory', logs: 'Activity logs' };
    const heading = document.getElementById('workspace-title');
    if (heading) heading.textContent = titles[tab] || titles.overview;
    ({
      overview: renderInformation, manage: renderManagementHub, members: renderMembers, ranks: renderRanks,
      vehicles: renderVehicles, armory: renderArmory, logs: renderLogs,
    }[tab] || renderInformation)();
  }

  const can = key => state.viewer.permissions[key] === true;
  const isFounder = () => state.viewer.isFounder === true;
  const myTier = () => state.viewer.tier;

  function goTab(tab) {
    activeTab = tab;
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
    renderTab(tab);
  }

  function renderManagementHub() {
    const f = state.family;
    const online = state.members.filter(member => member.online).length;
    const rank = (state.ranks.find(item => item.id === state.viewer.rankId) || {}).name || 'Member';
    const symbol = f.symbol || state.viewer.symbol || 'shield';
    const color = f.color || state.viewer.symbolColor || '#00f0ff';
    const tile = (group, title, description, action, enabled, danger) => enabled ? `
      <button class="hub-action ${danger ? 'hub-action--danger' : ''}" data-hub-action="${esc(action)}">
        <span class="hub-action__group">${esc(group)}</span><strong>${esc(title)}</strong>
        <small>${esc(description)}</small><span class="hub-action__arrow">›</span>
      </button>` : '';

    content.innerHTML = `
      <section class="hub-hero">
        <div><span class="hub-eyebrow">FAMILY MANAGEMENT</span><h2>${esc(f.name)}</h2>
          <p>${state.members.length} members · ${online} online · ${esc(rank)} · ${f.houseId ? 'House #' + f.houseId : 'No linked house'}</p></div>
        <div class="hub-symbol" style="color:${esc(color)}">${symbolSvg(symbol)}</div>
      </section>
      <div class="hub-grid">
        <section class="hub-group"><h3>Garage</h3>
          ${tile('GARAGE', 'Manage family transport', 'Shared vehicles and minimum rank tiers.', 'vehicles', can('garage.access') || can('family.manage_vehicles'))}
          ${tile('GARAGE', 'Recall family transport', 'Return available vehicles to their assigned garage slots.', 'recall', can('family.manage_vehicles'))}
        </section>
        <section class="hub-group"><h3>Control</h3>
          ${tile('CONTROL', 'Online family', `${online} of ${state.members.length} members online.`, 'members', true)}
          ${tile('CONTROL', 'Display family on map', 'Toggle nearby family-member minimap markers.', 'tracking', true)}
          ${tile('CONTROL', 'Set meeting point', 'Send your position to every online member.', 'meeting', can('family.set_meeting'))}
          ${tile('CONTROL', 'Manage ranks', 'Configure tiers and exact house permissions.', 'ranks', can('family.manage_ranks') || can('family.manage_perms'))}
        </section>
        <section class="hub-group"><h3>Family</h3>
          ${tile('FAMILY', 'Manage members', 'Invite, promote, demote, title, or remove members.', 'members', can('family.invite') || can('family.promote') || can('family.demote') || can('family.kick'))}
          ${tile('FAMILY', 'Customize family identity', 'Change the shared overhead icon and colour.', 'identity', can('family.manage_tags'))}
          ${tile('FAMILY', 'Rename family', 'Change the family display name.', 'rename', can('family.rename'))}
        </section>
        <section class="hub-group"><h3>Other</h3>
          ${tile('OTHER', 'Activity logs', 'Review membership, house, vehicle, and security events.', 'logs', can('family.view_logs'))}
          ${tile('OTHER', 'Leave family', 'Leave your current family membership.', 'leave', !isFounder(), true)}
          ${tile('OTHER', 'Delete family', 'Permanently disband this family.', 'disband', isFounder(), true)}
        </section>
      </div>`;

    document.querySelectorAll('[data-hub-action]').forEach(button => button.onclick = () => {
      const action = button.dataset.hubAction;
      if (['members', 'ranks', 'vehicles', 'logs'].includes(action)) return goTab(action);
      if (action === 'recall') return confirmAct('Recall every available outside car into the family garage?', 'recallAllFamilyCars', {});
      if (action === 'meeting') return confirmAct('Send your current location to all online family members?', 'setMeetingPoint', {});
      if (action === 'tracking') {
        const next = !(state.clientTracking && state.clientTracking.memberBlipsEnabled);
        return post('setMemberTracking', { enabled: next }).then(result => {
          if (!result.ok) return flash('Could not update member tracking.', 'error');
          state.clientTracking = state.clientTracking || {};
          state.clientTracking.memberBlipsEnabled = result.enabled === true;
          flash(result.enabled ? 'Nearby family markers enabled.' : 'Nearby family markers disabled.', 'ok');
          renderManagementHub();
        });
      }
      if (action === 'identity') return renderIdentityManager();
      if (action === 'rename') return renderRenameManager();
      if (action === 'leave') return confirmAct('Leave this family?', 'leave', {});
      if (action === 'disband') return confirmAct('Disband the whole family? This cannot be undone.', 'disband', {});
    });
  }

  function renderInformation() {
    const f = state.family;
    const online = state.members.filter(member => member.online).length;
    const week = state.weeklyStats || {};
    const rank = (state.ranks.find(item => item.id === state.viewer.rankId) || {}).name || 'Member';
    const founder = state.members.find(member => String(member.cid) === String(f.founderCid));
    const symbol = f.symbol || state.viewer.symbol || 'shield';
    const color = f.color || state.viewer.symbolColor || '#00f0ff';
    content.innerHTML = `
      <section class="family-info-hero">
        <div class="family-info-hero__copy"><span class="hub-eyebrow">FAMILY INFORMATION</span><h2>${esc(f.name)}</h2><p>${f.tag ? `[${esc(f.tag)}] ` : ''}Your family home, members, shared transport, and access in one place.</p></div>
        <div class="family-info-emblem" style="color:${esc(color)}">${symbolSvg(symbol)}</div>
      </section>
      <section class="family-facts">
        <div class="family-fact"><span>Head of family</span><strong>${esc(founder ? founder.name : 'Character ' + f.founderCid)}</strong><small>CID ${esc(f.founderCid)}</small></div>
        <div class="family-fact"><span>Family members</span><strong>${state.members.length}</strong><small>${online} online now</small></div>
        <div class="family-fact"><span>Your access level</span><strong>${esc(rank)}</strong><small>Rank tier ${Number(state.viewer.tier) || 0}</small></div>
        <div class="family-fact"><span>Family home</span><strong>${f.houseId ? 'House #' + f.houseId : 'Not linked'}</strong><small>${f.houseId ? 'Property access active' : 'No family property'}</small></div>
      </section>
      <section class="family-dashboard-grid">
        <article class="family-status-card"><div><span class="hub-eyebrow">THIS WEEK</span><h3>Family activity</h3><p>${Number(week.actions) || 0} recorded actions across ${Number(week.activeMembers) || 0} active members.</p></div><div class="family-status-stats"><span><strong>${Number(week.newMembers) || 0}</strong> new members</span><span><strong>${online}</strong> online</span></div></article>
        <article class="family-status-card"><div><span class="hub-eyebrow">QUICK STATUS</span><h3>Family network</h3><p>Nearby member markers are ${(state.clientTracking && state.clientTracking.memberBlipsEnabled) ? 'enabled' : 'disabled'} for this character.</p></div><button class="btn ghost" id="open-management-btn">Open management</button></article>
      </section>
      <section class="family-announcement">
        <div class="family-announcement__head"><div><span class="hub-eyebrow">MESSAGE FROM THE FAMILY</span><h3>${f.announcement ? 'Latest announcement' : 'No announcement yet'}</h3></div>${can('family.manage_announcement') ? '<button class="btn ghost sm" id="announcement-edit">Edit message</button>' : ''}</div>
        <p class="family-announcement__message">${esc(f.announcement || 'The family leadership has not posted a message.')}</p>
        ${f.announcement ? `<small>${esc(f.announcementByName || 'Family leadership')} · ${esc(formatTimestamp(f.announcementAt, 16))}</small>` : ''}
        <div class="family-announcement__editor" id="announcement-editor" hidden><textarea class="input" id="announcement-message" maxlength="280" rows="4" placeholder="Write a short message for your family...">${esc(f.announcement || '')}</textarea><div class="family-announcement__actions"><span id="announcement-count">${String(f.announcement || '').length}/280</span><button class="btn ghost sm" id="announcement-cancel">Cancel</button><button class="btn sm" id="announcement-save">Save message</button></div></div>
      </section>`;
    document.getElementById('open-management-btn').onclick = () => goTab('manage');
    const editAnnouncement = document.getElementById('announcement-edit');
    if (editAnnouncement) editAnnouncement.onclick = () => {
      const editor = document.getElementById('announcement-editor');
      editor.hidden = false;
      editAnnouncement.hidden = true;
      document.getElementById('announcement-message').focus();
    };
    const messageInput = document.getElementById('announcement-message');
    if (messageInput) messageInput.oninput = () => { document.getElementById('announcement-count').textContent = `${messageInput.value.length}/280`; };
    const cancelAnnouncement = document.getElementById('announcement-cancel');
    if (cancelAnnouncement) cancelAnnouncement.onclick = renderInformation;
    const saveAnnouncement = document.getElementById('announcement-save');
    if (saveAnnouncement) saveAnnouncement.onclick = () => act('setFamilyAnnouncement', { message: messageInput.value });
  }

  function renderIdentityManager() {
    const symbol = state.family.symbol || 'shield';
    const color = state.family.color || '#00f0ff';
    content.innerHTML = `<button class="btn ghost hub-back" id="hub-back">← Management</button>
      <div class="section-title">Family identity</div><div class="card">
      <div class="symbol-picker">${(state.symbolCatalog || []).map(item => `<button type="button" class="symbol-choice ${symbol === item.key ? 'selected' : ''}" title="${esc(item.label)}" data-family-symbol="${esc(item.key)}" style="color:${esc(color)}">${symbolSvg(item.key)}</button>`).join('')}</div>
      <div class="inline" style="margin-top:14px"><label>Colour</label><input id="family-symbol-color" class="input symbol-color-input" type="color" value="${esc(color)}"><button class="btn" id="family-symbol-save">Save identity</button></div></div>`;
    document.getElementById('hub-back').onclick = renderManagementHub;
    document.querySelectorAll('[data-family-symbol]').forEach(button => button.onclick = () => document.querySelectorAll('[data-family-symbol]').forEach(item => item.classList.toggle('selected', item === button)));
    const colorInput = document.getElementById('family-symbol-color');
    colorInput.oninput = () => document.querySelectorAll('[data-family-symbol]').forEach(item => { item.style.color = colorInput.value; });
    document.getElementById('family-symbol-save').onclick = () => {
      const selected = document.querySelector('[data-family-symbol].selected');
      act('setFamilySymbol', { symbol: selected ? selected.dataset.familySymbol : 'shield', color: colorInput.value });
    };
  }

  function renderRenameManager() {
    content.innerHTML = `<button class="btn ghost hub-back" id="hub-back">← Management</button>
      <div class="section-title">Rename family</div><div class="card"><div class="inline">
      <input class="input" id="rename-input" maxlength="32" value="${esc(state.family.name)}"><button class="btn" id="rename-btn">Save name</button></div></div>`;
    document.getElementById('hub-back').onclick = renderManagementHub;
    document.getElementById('rename-btn').onclick = () => act('rename', { name: document.getElementById('rename-input').value });
  }

  // ---------------- overview ----------------
  function renderOverview() {
    const f = state.family, online = state.members.filter(m => m.online).length;
    const week = state.weeklyStats || {};
    const myRank = (state.ranks.find(r => r.id === state.viewer.rankId) || {}).name || '—';
    const mySymbol = f.symbol || state.viewer.symbol || 'shield';
    const mySymbolColor = f.color || state.viewer.symbolColor || '#00f0ff';
    content.innerHTML = `
      <div class="grid grid--3" style="margin-bottom:18px">
        <div class="card"><h3>Members</h3><div class="big">${state.members.length}</div></div>
        <div class="card"><h3>Online now</h3><div class="big">${online}</div></div>
        <div class="card"><h3>Your rank</h3><div class="big" style="font-size:19px">${esc(myRank)}</div></div>
      </div>
      <div class="grid grid--2">
        <div class="card"><h3>Family house</h3><div style="font-size:15px;color:var(--text)">${f.houseId ? 'Linked (house #' + f.houseId + ')' : 'None'}</div></div>
        <div class="card"><h3>Family overhead symbol</h3><div class="symbol-preview" style="color:${esc(mySymbolColor)}">${symbolSvg(mySymbol)}</div><div class="row__sub">Every member uses the same family symbol.</div></div>
      </div>
      ${can('family.set_meeting') ? `
      <div class="card" style="margin-top:18px">
        <h3>Family meeting point</h3>
        <div class="row__sub">Send your current location to every online family member and set their GPS waypoint.</div>
        <button class="btn" id="meeting-point-btn" style="margin-top:10px">Set meeting point here</button>
      </div>` : ''}
      <div class="card" style="margin-top:18px">
        <h3>Family garage</h3>
        <div class="row__sub">Recall every unoccupied outside vehicle assigned to the family garage. Cars being driven or occupied are skipped.</div>
        <button class="btn" id="recall-all-cars-btn" style="margin-top:10px">Recall all family cars</button>
      </div>
      <div class="section-title" style="margin-top:22px">Last 7 days</div>
      <div class="grid grid--3" style="margin-bottom:12px">
        <div class="card"><h3>Contributed</h3><div class="big">${money(week.deposits)}</div><div class="row__sub">Family-bank deposits</div></div>
        <div class="card"><h3>Spent</h3><div class="big">${money(week.withdrawals)}</div><div class="row__sub">Family-bank withdrawals</div></div>
        <div class="card"><h3>Transactions</h3><div class="big">${Number(week.transactions) || 0}</div><div class="row__sub">Bank activity</div></div>
      </div>
      <div class="grid grid--3">
        <div class="card"><h3>Family actions</h3><div class="big">${Number(week.actions) || 0}</div><div class="row__sub">Recorded activity</div></div>
        <div class="card"><h3>Active members</h3><div class="big">${Number(week.activeMembers) || 0}</div><div class="row__sub">Members with recorded actions</div></div>
        <div class="card"><h3>New members</h3><div class="big">${Number(week.newMembers) || 0}</div><div class="row__sub">Joined this week</div></div>
      </div>
      ${can('family.manage_tags') ? `
      <div class="card" style="margin-top:18px">
        <h3>Family overhead symbol</h3>
        <div class="symbol-picker" id="family-symbol-picker" style="margin-top:12px">${(state.symbolCatalog || []).map(item => `<button type="button" class="symbol-choice ${mySymbol === item.key ? 'selected' : ''}" title="${esc(item.label)}" data-family-symbol="${esc(item.key)}" style="color:${esc(mySymbolColor)}">${symbolSvg(item.key)}</button>`).join('')}</div>
        <div class="inline" style="margin-top:10px"><label>Colour</label><input id="family-symbol-color" class="input symbol-color-input" type="color" value="${esc(mySymbolColor)}"><button class="btn" id="family-symbol-save">Save family symbol</button></div>
      </div>` : ''}
      <div class="card" style="margin-top:18px">
        <h3>Nearby family members on minimap</h3>
        <div class="row__sub">Shows only nearby online members of your family. This is a local preference and does not create global GPS tracking.</div>
        <div class="inline" style="margin-top:8px">
          <label class="inline"><input id="member-map-enabled" type="checkbox" ${(state.clientTracking && state.clientTracking.memberBlipsEnabled) ? 'checked' : ''}> Enable nearby family-member blips</label>
          <button class="btn ghost" id="member-map-save">Save</button>
        </div>
      </div>
      ${can('family.rename') ? `
      <div class="card" style="margin-top:18px">
        <h3>Rename family</h3>
        <div class="inline" style="margin-top:8px">
          <input class="input" id="rename-input" maxlength="32" value="${esc(f.name)}">
          <button class="btn" id="rename-btn">Save</button>
        </div>
      </div>` : ''}
      <div style="margin-top:22px" class="inline">
        <button class="btn danger" id="leave-btn">Leave family</button>
        ${isFounder() ? '<button class="btn danger" id="disband-btn">Disband family</button>' : ''}
      </div>`;

    document.querySelectorAll('[data-family-symbol]').forEach(btn => btn.onclick = () => document.querySelectorAll('[data-family-symbol]').forEach(x => x.classList.toggle('selected', x === btn)));
    const meetingButton = document.getElementById('meeting-point-btn');
    if (meetingButton) meetingButton.onclick = () => confirmAct('Send your current location to all online family members?', 'setMeetingPoint', {});
    const recallAllButton = document.getElementById('recall-all-cars-btn');
    if (recallAllButton) recallAllButton.onclick = () => confirmAct('Recall every available outside car into the family garage?', 'recallAllFamilyCars', {});
    const familyColor = document.getElementById('family-symbol-color');
    if (familyColor) familyColor.oninput = () => document.querySelectorAll('[data-family-symbol]').forEach(x => { x.style.color = familyColor.value; });
    const familySave = document.getElementById('family-symbol-save');
    if (familySave) familySave.onclick = () => {
      const selected = document.querySelector('[data-family-symbol].selected');
      act('setFamilySymbol', { symbol: selected ? selected.dataset.familySymbol : 'shield', color: familyColor.value });
    };
    document.getElementById('member-map-save').onclick = () => post('setMemberTracking', { enabled: document.getElementById('member-map-enabled').checked }).then(r => { if (!r.ok) flash('Could not update member tracking.', 'error'); else flash(r.enabled ? 'Nearby family member blips enabled.' : 'Nearby family member blips disabled.', 'ok'); });
    const rn = document.getElementById('rename-btn');
    if (rn) rn.onclick = () => act('rename', { name: document.getElementById('rename-input').value });
    document.getElementById('leave-btn').onclick = () => confirmAct('Leave this family?', 'leave', {});
    const db = document.getElementById('disband-btn');
    if (db) db.onclick = () => confirmAct('Disband the whole family? This cannot be undone.', 'disband', {});
  }

  // ---------------- members ----------------
  function renderMembers() {
    const rankOpts = state.ranks.filter(r => !r.isFounder).map(r =>
      `<option value="${r.id}">${esc(r.name)} (T${r.tier})</option>`).join('');

    const rows = state.members.map(m => {
      const canManage = !m.isFounder && (isFounder() || m.tier < myTier());
      const actions = [];
      if (canManage && can('family.promote')) actions.push(`<button class="btn ghost sm" data-promote="${esc(m.cid)}">Increase rank</button>`);
      if (canManage && can('family.demote')) actions.push(`<button class="btn ghost sm" data-demote="${esc(m.cid)}">Decrease rank</button>`);
      if (canManage && can('family.kick')) actions.push(`<button class="btn danger sm" data-kick="${esc(m.cid)}">Kick</button>`);
      if (can('family.manage_titles') && (isFounder() || m.tier < myTier() || String(m.cid) === String(state.viewer.cid))) {
        actions.push(`<input class="input" maxlength="24" placeholder="Member title" value="${esc(m.customTitle || '')}" data-title="${esc(m.cid)}" style="width:145px">`);
      }
      return `<div class="row">
        <span class="dot ${m.online ? 'on' : 'off'}"></span>
        <div class="row__main">
          <div class="row__title">${esc(m.name)} ${m.isFounder ? '<span class="badge founder">Head</span>' : ''}</div>
          <div class="row__sub">${esc(m.customTitle || m.rankName)} · tier ${m.tier} · ${m.online ? 'online now' : 'last seen ' + (formatTimestamp(m.lastSeen, 16) || 'unknown')}</div>
          <div class="member-metrics">
            <span>Contributed: <strong>${money(m.totalContribution)}</strong></span>
            <span>This week: <strong>${money(m.weeklyContribution)}</strong></span>
            <span>Weekly actions: <strong>${Number(m.weeklyActions) || 0}</strong></span>
            <span>Joined: <strong>${esc(formatTimestamp(m.joinedAt, 10) || 'unknown')}</strong></span>
          </div>
        </div>
        <div class="row__actions">${actions.join('')}</div>
      </div>`;
    }).join('');

    content.innerHTML = `
      ${can('family.invite') ? `
      <div class="card" style="margin-bottom:18px">
        <h3>Invite a player</h3>
        <div class="row__sub" style="margin-top:6px">Use the G menu while looking at a player. Character-ID invitation remains available here for offline/admin workflows.</div>
        <div class="inline" style="margin-top:8px">
          <input class="input" id="invite-cid" placeholder="Character ID" style="width:180px">
          <select class="input" id="invite-rank" style="width:180px">${rankOpts}</select>
          <button class="btn" id="invite-btn">Send invite</button>
        </div>
      </div>` : ''}
      <div class="section-title">Members (${state.members.length})</div>
      <div class="list">${rows}</div>`;

    const ib = document.getElementById('invite-btn');
    if (ib) ib.onclick = () => act('invite', {
      targetCid: document.getElementById('invite-cid').value.trim(),
      rankId: Number(document.getElementById('invite-rank').value),
    });
    content.querySelectorAll('[data-promote]').forEach(b => b.onclick = () => act('promote', { targetCid: b.dataset.promote }));
    content.querySelectorAll('[data-demote]').forEach(b => b.onclick = () => act('demote', { targetCid: b.dataset.demote }));
    content.querySelectorAll('[data-kick]').forEach(b => b.onclick = () => confirmAct('Kick this member?', 'kick', { targetCid: b.dataset.kick }));
    content.querySelectorAll('[data-title]').forEach(inp => inp.onchange = () => act('setMemberTitle', { targetCid: inp.dataset.title, title: inp.value.trim() }, true));
  }

  // ---------------- ranks ----------------
  function renderRanks() {
    const catalog = state.permissionCatalog;
    const groups = {};
    catalog.forEach(p => { (groups[p.group] = groups[p.group] || []).push(p); });

    const rankBlocks = state.ranks.map(r => {
      const editable = !r.isFounder && (isFounder() || r.tier < myTier());
      const permHtml = Object.keys(groups).map(g => `
        <div>
          <div class="perm-group__title">${g}</div>
          <div class="perm-list">
            ${groups[g].map(p => {
              const on = r.permissions[p.key] === true;
              const canToggle = editable && can('family.manage_perms') && (isFounder() || can(p.key));
              return `<div class="perm ${canToggle ? '' : 'disabled'}">
                <span>${esc(p.label)}</span>
                <label class="switch">
                  <input type="checkbox" ${on ? 'checked' : ''} ${(canToggle && !r.isFounder) ? '' : 'disabled'}
                    data-perm="${r.id}" data-key="${p.key}">
                  <span class="slider"></span>
                </label>
              </div>`;
            }).join('')}
          </div>
        </div>`).join('');

      return `<div class="card" style="margin-bottom:16px">
        <div class="inline" style="justify-content:space-between;margin-bottom:12px">
          <div class="inline">
            <span class="tier">${r.tier}</span>
            <input class="input" style="width:200px" value="${esc(r.name)}" ${editable && can('family.manage_ranks') ? '' : 'disabled'} data-rankname="${r.id}">
            ${r.isFounder ? '<span class="badge founder">Head</span>' : ''}
          </div>
          <div class="inline">
            ${editable && can('family.manage_ranks') && !r.isFounder ? `<button class="btn danger sm" data-delrank="${r.id}">Delete</button>` : ''}
          </div>
        </div>
        <div class="perm-groups"><div class="perm-list" style="grid-template-columns:1fr;gap:18px">${permHtml}</div></div>
      </div>`;
    }).join('');

    content.innerHTML = `
      ${can('family.manage_ranks') && state.ranks.length < state.maxRanks ? `
      <div class="card" style="margin-bottom:18px">
        <h3>Create a rank</h3>
        <div class="inline" style="margin-top:8px">
          <input class="input" id="new-rank-name" placeholder="Rank name" style="width:200px">
          <input class="input" id="new-rank-tier" type="number" min="1" max="${state.maxRanks}" placeholder="Tier" style="width:100px">
          <button class="btn" id="new-rank-btn">Create</button>
        </div>
        <div class="row__sub" style="margin-top:6px">New ranks start with no permissions. You can only grant permissions you hold, below your own tier.</div>
      </div>` : ''}
      <div class="section-title">Ranks (${state.ranks.length} / ${state.maxRanks})</div>
      ${rankBlocks}`;

    const nb = document.getElementById('new-rank-btn');
    if (nb) nb.onclick = () => act('createRank', {
      name: document.getElementById('new-rank-name').value.trim(),
      tier: Number(document.getElementById('new-rank-tier').value),
      permissions: [],
    });
    content.querySelectorAll('[data-perm]').forEach(cb => cb.onchange = () =>
      act('setRankPermission', { rankId: Number(cb.dataset.perm), key: cb.dataset.key, enabled: cb.checked }, true));
    content.querySelectorAll('[data-rankname]').forEach(inp => inp.onchange = () =>
      act('renameRank', { rankId: Number(inp.dataset.rankname), name: inp.value.trim() }, true));
    content.querySelectorAll('[data-delrank]').forEach(b => b.onclick = () =>
      confirmAct('Delete this rank? Members on it drop to the lowest rank.', 'deleteRank', { rankId: Number(b.dataset.delrank) }));
  }

  // ---------------- vehicles ----------------
  function renderVehicles() {
    const canManageLevels = can('family.manage_vehicles');
    const rows = state.vehicles.map(v => {
      const shareControl = v.isOwner && v.eligible
        ? `<label class="inline" style="font-size:12px"><input type="checkbox" data-share="${v.id}" ${v.shared ? 'checked' : ''}> Shared</label>`
        : `<span class="badge">${v.shared ? 'Family' : 'Private'}</span>`;
      const levelDisabled = (!canManageLevels && !v.isOwner) ? 'disabled' : '';
      const image = v.image
        ? `<img class="vehicle-thumb" src="${esc(v.image)}" alt="${esc(v.label || v.model || 'Vehicle')}">`
        : `<div class="vehicle-thumb vehicle-thumb--empty">NO IMAGE</div>`;
      return `<div class="row vehicle-row">
        ${image}
        <div class="row__main">
          <div class="row__title">${esc(v.label || v.model || v.plate || 'Vehicle')} ${v.isOwner ? '<span class="badge founder">Your car</span>' : ''}</div>
          <div class="row__sub">${esc(v.plate || '')} · ${v.eligible ? esc(v.house_label || 'family house') + ' · slot ' + v.slot_index : 'Park in the family garage before sharing'}</div>
        </div>
        <div class="row__actions">
          ${shareControl}
          <div class="level-ctl">
            <label style="font-size:12px;color:var(--text-dim)">Minimum rank tier</label>
            <input class="input" type="number" min="1" max="${state.maxRanks}" value="${v.level}" ${levelDisabled} data-veh="${v.id}">
          </div>
          ${v.shared && v.canTrack ? `<button class="btn ghost sm" data-track="${v.id}" ${Number(v.trackCooldownSeconds) > 0 ? 'disabled' : ''}>${Number(v.trackCooldownSeconds) > 0 ? 'Track in ' + Math.ceil(Number(v.trackCooldownSeconds) / 60) + 'm' : 'Track car'}</button>` : ''}
        </div>
      </div>`;
    }).join('');

    content.innerHTML = `
      <div class="section-title">Family vehicle access</div>
      <div class="row__sub" style="margin-bottom:14px">Your cars parked at the family house appear here. Only the owner can share or unshare a car. Authorized ranks can set the minimum tier for shared cars.</div>
      ${state.vehicles.length ? `<div class="list">${rows}</div>` :
        '<div class="empty"><h2>No vehicles at the family house</h2><div>Park an owned car in the family garage first.</div></div>'}`;

    content.querySelectorAll('[data-share]').forEach(box => box.onchange = () => {
      const levelInput = content.querySelector(`[data-veh="${box.dataset.share}"]`);
      act('setVehicleShared', { vehicleId: Number(box.dataset.share), shared: box.checked, level: Number(levelInput && levelInput.value) || 1 });
    });
    content.querySelectorAll('[data-track]').forEach(btn => btn.onclick = () => {
      btn.disabled = true;
      btn.textContent = 'Locating…';
      act('trackVehicle', { vehicleId: Number(btn.dataset.track) }, true).then(res => {
        if (!res.ok) { btn.disabled = false; btn.textContent = 'Track car'; }
      });
    });
    content.querySelectorAll('[data-veh]').forEach(inp => inp.onchange = () => {
      const id = Number(inp.dataset.veh);
      const vehicle = state.vehicles.find(v => Number(v.id) === id);
      const level = Number(inp.value) || 1;
      // Setting a rank on your own private car is the explicit share action the
      // owner expects. Non-owners can edit levels only after a car is shared.
      if (vehicle && vehicle.isOwner) {
        act('setVehicleShared', { vehicleId: id, shared: true, level }, true);
      } else {
        act('setVehicleLevel', { vehicleId: id, level }, true);
      }
    });
  }

  // ---------------- bank ----------------
  function renderBank() {
    const f = state.family;
    const log = (state.bankLog || []).map(l => `
      <div class="log-row">
        <span class="when">${esc(formatTimestamp(l.created_at, 16))}</span>
        <span class="what">${l.direction === 'deposit' ? '+' : '−'} ${money(l.amount)} · ${esc(l.reason || l.direction)} ${l.character_id ? '· by ' + esc(l.character_id) : ''}</span>
      </div>`).join('');

    content.innerHTML = `
      <div class="grid grid--2" style="margin-bottom:18px">
        <div class="card"><h3>Balance</h3><div class="big">${money(f.bankBalance)}</div></div>
        <div class="card">
          <h3>Move money</h3>
          <div class="inline" style="margin-top:8px">
            <input class="input" id="bank-amount" type="number" min="1" placeholder="Amount" style="width:150px">
            ${can('bank.deposit') ? '<button class="btn" id="deposit-btn">Deposit</button>' : ''}
            ${can('bank.withdraw') ? '<button class="btn" id="withdraw-btn">Withdraw</button>' : ''}
          </div>
        </div>
      </div>
      <div class="section-title">Recent movements</div>
      ${log ? `<div class="list">${log}</div>` : '<div class="empty">No transactions yet.</div>'}`;

    const amt = () => Math.floor(Number(document.getElementById('bank-amount').value) || 0);
    const d = document.getElementById('deposit-btn');
    if (d) d.onclick = () => act('bankDeposit', { amount: amt() });
    const w = document.getElementById('withdraw-btn');
    if (w) w.onclick = () => act('bankWithdraw', { amount: amt() });
  }

  // ---------------- logs ----------------
  function renderLogs() {
    if (state.activityLog === false) {
      content.innerHTML = `<div class="empty"><h2>Activity</h2><div>Your rank cannot view family activity history.</div></div>`;
      return;
    }
    const rows = Array.isArray(state.activityLog) ? state.activityLog : [];
    const categories = [...new Set(rows.map(x => x.category || 'family'))].sort();
    const actionLabel = value => String(value || 'activity').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    const detailText = row => {
      const d = row.detail || {};
      const parts = [];
      if (row.target_name || row.target_cid) parts.push(`Target: ${esc(row.target_name || ('CID ' + row.target_cid))}`);
      if (d.oldRankName && d.rankName) parts.push(`${esc(d.oldRankName)} → ${esc(d.rankName)}`);
      if (row.vehicle_id || d.vehicle) parts.push(`Vehicle #${esc(row.vehicle_id || d.vehicle)}`);
      if (d.plate) parts.push(esc(d.plate));
      if (row.house_id) parts.push(`House #${esc(row.house_id)}`);
      if (row.amount != null) parts.push(money(row.amount));
      if (d.item) parts.push(`${esc(d.item)} × ${esc(d.quantity || 1)}`);
      if (d.reason) parts.push(esc(d.reason));
      return parts.join(' · ');
    };
    const renderRows = filter => rows.filter(r => !filter || filter === 'all' || r.category === filter).map(r => `
      <div class="activity-row ${r.high_risk ? 'activity-row--risk' : ''}">
        <div class="activity-row__head">
          <div class="inline">
            <span class="audit-severity audit-severity--${esc(r.severity || 'info')}">${r.high_risk ? 'HIGH RISK' : esc((r.severity || 'info').toUpperCase())}</span>
            <strong>${esc(actionLabel(r.action))}</strong>
          </div>
          <span class="when">${esc(formatTimestamp(r.created_at, 19))}</span>
        </div>
        <div class="activity-row__meta">${esc(r.actor_name || (r.actor_cid ? 'CID ' + r.actor_cid : 'System'))} · ${esc(r.category || 'family')} · ${esc(r.source_resource || 'cm-family')}</div>
        ${detailText(r) ? `<div class="activity-row__detail">${detailText(r)}</div>` : ''}
      </div>`).join('');

    content.innerHTML = `
      <div class="inline" style="justify-content:space-between;margin-bottom:14px">
        <div><div class="section-title" style="margin:0">Family activity</div><div class="row__sub">Durable audit history. High-risk entries are also exposed to cm-admin.</div></div>
        <select class="input" id="activity-filter" style="width:180px">
          <option value="all">All categories</option>
          ${categories.map(c => `<option value="${esc(c)}">${esc(actionLabel(c))}</option>`).join('')}
        </select>
      </div>
      <div class="list" id="activity-list">${renderRows('all') || '<div class="empty">No family activity yet.</div>'}</div>`;
    const filter = document.getElementById('activity-filter');
    if (filter) filter.onchange = () => {
      const list = document.getElementById('activity-list');
      if (list) list.innerHTML = renderRows(filter.value) || '<div class="empty">No activity in this category.</div>';
    };
  }

  // ---------------- armory ----------------
  let armoryItems = [];
  let armoryFilter = 'all';
  let armoryManaging = false;
  let armoryManageItems = null;

  function armoryImage(value) {
    const image = String(value || '');
    if (!image) return '';
    if (/^https?:|^data:/.test(image)) return image;
    if (image.startsWith('nui://')) return image.replace(/^nui:\/\/([^/]+)\//, 'https://cfx-nui-$1/');
    return image;
  }

  function armoryTakeBtn(i, available, label) {
    return can('family.armory')
      ? `<button class="primary" data-armory-take="${esc(i.itemId)}" ${available ? '' : 'disabled'}>${available ? label : 'OUT OF STOCK'}</button>`
      : '';
  }

  function armoryPutBtn(i) {
    return can('family.armory_deposit')
      ? `<input type="number" min="1" max="1000" value="${Number(i.quantity || 1)}" data-armory-qty="${esc(i.itemId)}">
         <button class="tertiary" data-armory-put="${esc(i.itemId)}" title="Return to armory">↩</button>`
      : '';
  }

  function armoryCard(i, allItems) {
    const image = armoryImage(i.image);
    const imageBlock = `
      <div class="armory-item-image">
        ${image ? `<img src="${esc(image)}" alt="${esc(i.label)}" onerror="this.hidden=true">` : `<span>${esc(String(i.group || i.itemType).toUpperCase())}</span>`}
        <small><i></i>${esc(i.label)}</small>
      </div>`;

    if (i.itemType === 'armor') {
      const stock = Number(i.stockQuantity || 0);
      const available = stock > 0;
      return `
        <article class="armory-item ${available ? '' : 'empty'}">
          ${imageBlock}
          <div class="armory-item-data">
            <em>ARMOR</em>
            <div class="armory-item-stats-row">
              <div class="armory-item-stat"><label>STRENGTH</label><strong>${Number(i.armorValue || 0)}<small>%</small></strong></div>
              <div class="armory-item-stat"><label>IN STOCK</label><strong>${stock}<small>PCS</small></strong></div>
            </div>
            <div class="armory-item-name">${esc(i.label)}</div>
            <div class="armory-item-actions">${armoryTakeBtn(i, available, 'TAKE')}${armoryPutBtn(i)}</div>
          </div>
        </article>`;
    }

    if (i.itemType === 'ammo') {
      const stock = Number(i.stockQuantity || 0);
      const available = stock >= Number(i.quantity || 1);
      return `
        <article class="armory-item ${available ? '' : 'empty'}">
          ${imageBlock}
          <div class="armory-item-data">
            <em>AMMO</em>
            <div class="armory-item-stat">
              <label>IN VAULT</label>
              <strong>${stock.toLocaleString()} <small>ROUNDS</small></strong>
              <div class="armory-stock-line"><i style="width:${Math.min(100, stock)}%"></i></div>
            </div>
            <div class="armory-item-actions">${armoryTakeBtn(i, available, 'TAKE AMMO')}${armoryPutBtn(i)}</div>
          </div>
        </article>`;
    }

    const stock = Number(i.stockQuantity || 0);
    const available = stock >= Number(i.quantity || 1);
    const ammo = i.ammoItem ? (allItems || []).find(x => x.itemId === i.ammoItem && x.itemType === 'ammo') : null;
    const ammoStock = ammo ? Number(ammo.stockQuantity || 0) : 0;
    const ammoAvailable = ammo ? ammoStock >= Number(ammo.quantity || 1) : false;
    return `
      <article class="armory-item ${available ? '' : 'empty'}">
        ${imageBlock}
        <div class="armory-item-data">
          <em>WEAPON</em>
          <div class="armory-item-stat">
            <label>WEAPON IN VAULT</label>
            <strong>${stock.toLocaleString()} <small>PCS</small></strong>
          </div>
          ${ammo ? `
          <div class="armory-item-stat">
            <label>AMMO <span>${esc(ammo.label)}</span></label>
            <strong>${ammoStock.toLocaleString()} <small>ROUNDS</small></strong>
            <div class="armory-stock-line"><i style="width:${Math.min(100, ammoStock)}%"></i></div>
          </div>` : ''}
          <div class="armory-item-actions">
            ${armoryTakeBtn(i, available, 'TAKE GUN')}
            ${ammo ? `<button class="secondary" data-armory-take="${esc(ammo.itemId)}" ${ammoAvailable ? '' : 'disabled'}>${ammoAvailable ? `+${Number(ammo.quantity || 1)} AMMO` : 'NO AMMO'}</button>` : ''}
            ${armoryPutBtn(i)}
          </div>
        </div>
      </article>`;
  }

  function bindArmoryCardActions(root) {
    root.querySelectorAll('[data-armory-take]:not(:disabled)').forEach(b => b.onclick = async () => {
      b.disabled = true;
      const res = await post('armoryCheckout', { itemId: b.dataset.armoryTake });
      flash(res.ok ? 'Issued from the family armory.' : (res.reason || 'Checkout failed.'), res.ok ? 'ok' : 'error');
      if (res.ok) loadArmory(); else b.disabled = false;
    });
    root.querySelectorAll('[data-armory-put]').forEach(b => b.onclick = async () => {
      const qty = Math.floor(Number(root.querySelector(`[data-armory-qty="${b.dataset.armoryPut}"]`)?.value) || 1);
      if (qty < 1) return;
      b.disabled = true;
      const res = await post('armoryDeposit', { itemId: b.dataset.armoryPut, quantity: qty });
      flash(res.ok ? 'Returned to the family armory.' : (res.reason || 'Deposit failed.'), res.ok ? 'ok' : 'error');
      if (res.ok) loadArmory(); else b.disabled = false;
    });
  }

  function renderArmoryItems() {
    const box = document.getElementById('armory-grid');
    if (!box) return;
    const items = armoryItems.filter(item => armoryFilter === 'all' || item.itemType === armoryFilter);
    box.innerHTML = items.map(i => armoryCard(i, armoryItems)).join('') || '<div class="armory-loading">No equipment is available in this category.</div>';
    bindArmoryCardActions(box);
    const armor = armoryItems.filter(item => item.itemType === 'armor');
    const armorBox = document.getElementById('armory-armor-list');
    const armorCount = document.getElementById('armory-armor-count');
    if (armorCount) armorCount.textContent = `${armor.length} MODELS`;
    if (armorBox) {
      armorBox.innerHTML = armor.map(i => armoryCard(i, armoryItems)).join('') ||
        '<div class="armory-armor-empty"><strong>NO ARMOR CONFIGURED</strong><span>Protective equipment will appear here when enabled.</span></div>';
      bindArmoryCardActions(armorBox);
    }
  }

  async function loadArmory() {
    const box = document.getElementById('armory-grid');
    if (!box) return;
    const res = await post('getArmory', {});
    if (!res.ok) {
      box.innerHTML = `<div class="armory-loading error">${esc(res.reason || 'Armory unavailable.')}</div>`;
      return;
    }
    armoryItems = res.items || [];
    const stocked = armoryItems.filter(item => Number(item.stockQuantity || 0) > 0).length;
    const modelStock = document.getElementById('armory-model-stock');
    if (modelStock) modelStock.textContent = `${stocked} OF ${armoryItems.length} MODELS IN STOCK`;
    for (const type of ['all', 'weapon', 'ammo', 'armor']) {
      const count = type === 'all' ? armoryItems.length : armoryItems.filter(item => item.itemType === type).length;
      const el = document.getElementById(`armory-count-${type}`);
      if (el) el.textContent = count;
    }
    renderArmoryItems();
  }

  function renderArmoryCatalog() {
    const f = state.family;
    const rankName = (state.ranks.find(r => r.id === state.viewer.rankId) || {}).name || 'Member';
    content.innerHTML = `
      <section class="armory-catalog armory-catalog-v4">
        <aside class="armory-sidebar">
          <div class="armory-vertical">ARMOR</div>
          <div class="armory-sidebar-head"><span>PROTECTIVE EQUIPMENT</span><strong id="armory-armor-count">0 MODELS</strong></div>
          <div id="armory-armor-list" class="armory-armor-list"><div class="armory-loading">Loading armor…</div></div>
          <button id="armory-exit" class="quiet">← BACK TO FAMILY</button>
        </aside>
        <main class="armory-main-panel">
          <header class="armory-title">
            <div><small>${esc(f.name.toUpperCase())} QUARTERMASTER</small><h2><i></i> CONTROL</h2><span id="armory-model-stock">0 MODELS IN STOCK</span></div>
            <nav class="armory-category-tabs" aria-label="Armory categories">
              <button class="active" data-armory-filter="all">ALL <b id="armory-count-all">0</b></button>
              <button data-armory-filter="weapon">WEAPONS <b id="armory-count-weapon">0</b></button>
              <button data-armory-filter="ammo">AMMO <b id="armory-count-ammo">0</b></button>
              <button data-armory-filter="armor">ARMOR <b id="armory-count-armor">0</b></button>
            </nav>
            ${can('family.manage_armory') ? '<button id="armory-manage-toggle">MANAGE CATALOG</button>' : ''}
          </header>
          <div class="armory-toolbar"><span><i></i> LIVE SHARED STOCK</span><small>AUTHORIZED FOR ${esc(rankName)}</small></div>
          <div id="armory-grid" class="armory-catalog-grid"><div class="armory-loading">Loading armory stock…</div></div>
        </main>
      </section>`;

    document.querySelectorAll('[data-armory-filter]').forEach(button => button.addEventListener('click', () => {
      armoryFilter = button.dataset.armoryFilter;
      document.querySelectorAll('[data-armory-filter]').forEach(item => item.classList.toggle('active', item === button));
      renderArmoryItems();
    }));
    document.getElementById('armory-exit').onclick = () => goTab('overview');
    const manageBtn = document.getElementById('armory-manage-toggle');
    if (manageBtn) manageBtn.onclick = () => { armoryManaging = true; renderArmory(); };
    loadArmory();
  }

  function renderArmoryManage() {
    content.innerHTML = `
      <div class="inline" style="justify-content:space-between;margin-bottom:14px">
        <div><div class="section-title" style="margin:0">Armory catalog</div><div class="row__sub">Choose what's stocked, the minimum rank tier, and how much is issued per checkout.</div></div>
        <div class="inline">
          <button class="btn" id="armory-load-stock">Load stock</button>
          <button id="armory-manage-back">← Back to armory</button>
        </div>
      </div>
      <div class="list" id="armory-manage-list"><div class="armory-loading">Loading catalog…</div></div>`;

    document.getElementById('armory-manage-back').onclick = () => { armoryManaging = false; renderArmory(); };
    document.getElementById('armory-load-stock').onclick = async () => {
      const res = await post('armoryLoadStock', {});
      flash(res.ok ? (res.message || 'Stock loaded.') : (res.reason || 'Failed to load stock.'), res.ok ? 'ok' : 'error');
    };

    (armoryManageItems ? Promise.resolve({ ok: true, items: armoryManageItems }) : post('armoryManagement', {})).then(res => {
      const list = document.getElementById('armory-manage-list');
      if (!res.ok) { list.innerHTML = `<div class="empty">${esc(res.reason || 'Armory unavailable.')}</div>`; return; }
      armoryManageItems = res.items || [];
      list.innerHTML = armoryManageItems.map(i => `
        <div class="row" data-manage-row="${esc(i.itemId)}">
          <div class="row__main">
            <label class="permission-check"><input type="checkbox" data-manage-enabled ${i.enabled ? 'checked' : ''}>${esc(i.label)}</label>
            <span class="row__sub">${esc(String(i.itemType).toUpperCase())} · Currently ${Number(i.stock || 0)} in stock</span>
          </div>
          <div class="inline">
            <input class="input" type="number" min="0" max="1000" data-manage-tier value="${Number(i.minTier || 0)}" style="width:90px" title="Minimum tier">
            <input class="input" type="number" min="1" max="1000" data-manage-issue value="${Number(i.issueAmount || 1)}" style="width:90px" title="Issue amount">
            <button data-manage-save="${esc(i.itemId)}">Save</button>
          </div>
        </div>`).join('') || '<div class="empty">No catalog items available.</div>';

      list.querySelectorAll('[data-manage-save]').forEach(btn => btn.onclick = async () => {
        const row = btn.closest('[data-manage-row]');
        const itemId = row.dataset.manageRow;
        const enabled = row.querySelector('[data-manage-enabled]').checked;
        const minTier = Number(row.querySelector('[data-manage-tier]').value) || 0;
        const issueAmount = Number(row.querySelector('[data-manage-issue]').value) || 1;
        btn.disabled = true;
        const res = await post('armorySave', { itemId, enabled, minTier, issueAmount });
        flash(res.ok ? 'Armory item saved.' : (res.reason || 'Save failed.'), res.ok ? 'ok' : 'error');
        armoryManageItems = null;
        btn.disabled = false;
      });
    });
  }

  function renderArmory() {
    if (armoryManaging && can('family.manage_armory')) renderArmoryManage();
    else renderArmoryCatalog();
  }

  // ---------------- action helper ----------------
  function flash(msg, kind) {
    const el = document.createElement('div');
    el.className = 'msg ' + (kind || 'ok');
    el.textContent = msg;
    content.prepend(el);
    setTimeout(() => el.remove(), 3200);
  }

  function act(action, data, silent) {
    return post('action', { action, data }).then(res => {
      if (!res.ok) {
        flash(typeof res.result === 'string' ? res.result : 'Action failed.', 'error');
      } else if (!silent) {
        flash('Done.', 'ok');
      }
      // The client bridge refreshes the snapshot on success; it re-pushes
      // family:open which re-renders. For silent inline edits we still get a
      // refresh so values stay authoritative.
      return res;
    });
  }

  function confirmAct(question, action, data) {
    if (window.confirm(question)) act(action, data);
  }

  // ---------------- create screen ----------------
  function renderCreate(res) {
    if (!res || !res.ok) {
      const reason = res && res.message ? res.message :
        (res && res.reason === 'already_in_family' ? 'You are already in a family.' :
         'You don\'t own any house eligible to become a family house.');
      createContent.innerHTML = `
        <div class="empty">
          <h2>Can't start a family yet</h2>
          <div>${esc(reason)}</div>
          <div style="margin-top:18px"><button class="btn ghost" id="create-cancel">Close</button></div>
        </div>`;
      document.getElementById('create-cancel').onclick = closeAll;
      return;
    }

    const cards = res.houses.map(h => `
      <div class="house-card" data-house="${h.id}">
        <div class="house-card__img" ${h.image ? `style="background-image:url('nui://cm-house/html/img/houses/${esc((h.image||'').split('/').pop())}')"` : ''}>${h.image ? '' : 'No photo'}</div>
        <div class="house-card__body">
          <div class="house-card__title">${esc(h.label)}</div>
          <div class="house-card__sub">${esc(h.type || 'house')}${h.number ? ' · #' + esc(h.number) : ''}</div>
        </div>
      </div>`).join('');

    createContent.innerHTML = `
      <div class="field">
        <label>Family name</label>
        <input class="input" id="cf-name" maxlength="32" placeholder="e.g. The Morettis">
      </div>
      <div class="inline">
        <div class="field" style="flex:1"><label>Tag (optional)</label><input class="input" id="cf-tag" maxlength="5" placeholder="MOR"></div>
        <div class="field" style="width:120px"><label>Color</label><input class="input" id="cf-color" type="color" value="#00f0ff" style="height:40px;padding:4px"></div>
      </div>
      <div class="section-title" style="margin-top:8px">Choose the family house</div>
      <div class="house-grid" id="house-grid">${cards}</div>
      <div class="inline" style="margin-top:22px;justify-content:flex-end">
        <button class="btn ghost" id="cf-cancel">Cancel</button>
        <button class="btn" id="cf-submit" disabled>Create family</button>
      </div>`;

    createContent.querySelectorAll('.house-card').forEach(c => c.onclick = () => {
      createContent.querySelectorAll('.house-card').forEach(x => x.classList.remove('selected'));
      c.classList.add('selected');
      createSelection = Number(c.dataset.house);
      document.getElementById('cf-submit').disabled = false;
    });
    document.getElementById('cf-cancel').onclick = closeAll;
    document.getElementById('cf-submit').onclick = () => {
      const name = document.getElementById('cf-name').value.trim();
      if (name.length < 3) { flashCreate('Name must be at least 3 characters.'); return; }
      if (!createSelection) { flashCreate('Pick a house.'); return; }
      post('createFamily', {
        name, houseId: createSelection,
        tag: document.getElementById('cf-tag').value.trim() || null,
        color: document.getElementById('cf-color').value,
      }).then(r => {
        if (!r.ok) flashCreate(typeof r.result === 'string' ? r.result : 'Could not create family.');
        // On success the client bridge refreshes and pushes family:open.
      });
    };
  }

  function flashCreate(msg) {
    const el = document.createElement('div');
    el.className = 'msg error';
    el.textContent = msg;
    createContent.prepend(el);
    setTimeout(() => el.remove(), 3200);
  }

  // ---------------- invite prompt / toast ----------------
  function openInvitePrompt(invite) {
    root.classList.remove('is-open');
    createRoot.classList.add('is-open');
    createContent.innerHTML = `
      <div class="empty">
        <h2>Family invitation</h2>
        <div>You've been invited to <b>${esc(invite.familyName || invite.family_name || 'a family')}</b>.</div>
        <div class="inline" style="justify-content:center;margin-top:22px">
          <button class="btn" id="inv-accept">Accept</button>
          <button class="btn ghost" id="inv-decline">Decline</button>
        </div>
      </div>`;
    document.getElementById('inv-accept').onclick = () =>
      post('action', { action: 'respondInvite', data: { accept: true } }).then(closeAll);
    document.getElementById('inv-decline').onclick = () =>
      post('action', { action: 'respondInvite', data: { accept: false } }).then(closeAll);
  }

  function showToast(data) {
    document.getElementById('toast-body').textContent =
      `${data.invitedBy || 'Someone'} invited you to "${data.familyName || 'a family'}".`;
    toast.classList.add('is-open');
    setTimeout(() => toast.classList.remove('is-open'), 6000);
  }

  function renderFamilyAdmin() {
    if (!adminState) return;
    const query = String(document.getElementById('family-admin-search').value || '').toLowerCase();
    const families = (adminState.families || []).filter(family => !query ||
      [family.id, family.name, family.tag, family.founderCid, family.founderName, family.houseId].join(' ').toLowerCase().includes(query));
    document.getElementById('family-admin-count').textContent = `${families.length} famil${families.length === 1 ? 'y' : 'ies'}`;
    document.getElementById('family-admin-list').innerHTML = families.map(family => `
      <article class="family-admin-card ${family.healthy ? '' : 'family-admin-card--issue'}" data-admin-family="${family.id}">
        <div class="family-admin-card__head"><div><span class="hub-eyebrow">FAMILY #${family.id}</span><h3>${esc(family.name)} ${family.tag ? `[${esc(family.tag)}]` : ''}</h3></div><span class="badge ${family.healthy ? '' : 'founder'}">${family.healthy ? 'Healthy' : `${family.issues.length} issue${family.issues.length === 1 ? '' : 's'}`}</span></div>
        <div class="family-admin-metrics"><span>Founder <strong>${esc(family.founderName)}</strong> · CID ${esc(family.founderCid)}</span><span>House <strong>${family.houseId || 'none'}</strong></span><span>${family.memberCount} members · ${family.rankCount} ranks · ${family.pendingInvites} pending invites</span></div>
        ${family.issues.length ? `<ul class="family-admin-issues">${family.issues.map(issue => `<li>${esc(issue)}</li>`).join('')}</ul>` : ''}
        ${adminState.canRecover ? `<div class="row__actions family-admin-actions"><button class="btn sm" data-family-recovery="refresh">Refresh state</button>${family.issues.some(issue => issue.includes('Founder membership')) ? '<button class="btn sm" data-family-recovery="repair_founder">Repair founder</button>' : ''}${family.expiredInvites > 0 ? '<button class="btn ghost sm" data-family-recovery="clear_expired_invites">Clear expired invites</button>' : ''}</div>` : ''}
      </article>`).join('') || '<div class="empty">No families match this search.</div>';
    document.getElementById('family-admin-logs').innerHTML = (adminState.highRisk || []).map(row => `
      <div class="activity-row activity-row--risk"><div class="activity-row__head"><strong>${esc(row.action)}</strong><span class="audit-severity audit-severity--${esc(row.severity || 'critical')}">${esc(row.severity || 'critical')}</span></div><div class="activity-row__meta">Family #${esc(row.family_id)} · ${esc(row.actor_name || row.actor_cid || 'System')} · ${esc(formatTimestamp(row.created_at))}</div></div>`).join('') || '<div class="empty">No high-risk activity available for your admin rank.</div>';
  }

  document.getElementById('family-admin-search').addEventListener('input', renderFamilyAdmin);
  document.getElementById('family-admin-close').addEventListener('click', () => post('familyAdminClose').then(() => adminRoot.classList.remove('is-open')));
  adminRoot.addEventListener('click', event => {
    const button = event.target.closest('[data-family-recovery]');
    if (!button) return;
    const familyId = Number(button.closest('[data-admin-family]').dataset.adminFamily);
    const action = button.dataset.familyRecovery;
    if (action === 'repair_founder' && !window.confirm(`Repair verified founder membership for family ${familyId}?`)) return;
    button.disabled = true;
    post('familyAdminAction', { action, familyId }).then(result => {
      if (!result.ok) flash(result.message || 'Family recovery failed.', 'error');
      button.disabled = false;
    });
  });

  // ---------------- message bus ----------------
  window.addEventListener('message', e => {
    const m = e.data || {};
    if (m.action === 'family:open') openMenu(m.data);
    else if (m.action === 'family:adminOpen' || m.action === 'family:adminRefresh') {
      adminState = m.data || {};
      root.classList.remove('is-open'); createRoot.classList.remove('is-open');
      adminRoot.classList.add('is-open'); adminRoot.setAttribute('aria-hidden', 'false');
      renderFamilyAdmin();
    }
    else if (m.action === 'family:adminClose') adminRoot.classList.remove('is-open');
    else if (m.action === 'family:create') openCreate(m.data);
    else if (m.action === 'family:invite') openInvitePrompt(m.data);
    else if (m.action === 'family:inviteToast') showToast(m.data);
    else if (m.action === 'family:close') { root.classList.remove('is-open'); createRoot.classList.remove('is-open'); adminRoot.classList.remove('is-open'); }
  });

  document.getElementById('btn-close').onclick = closeAll;
  document.getElementById('btn-create-close').onclick = closeAll;
  document.addEventListener('keyup', e => { if (e.key === 'Escape') closeAll(); });
})();
