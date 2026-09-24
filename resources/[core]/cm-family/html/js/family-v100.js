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
    }).then(async r => {
      if (!r.ok) return { ok: false };
      const text = await r.text();
      if (!text) return { ok: true };
      try { return JSON.parse(text); } catch (_) { return { ok: true }; }
    }).catch(() => ({ ok: false }));
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
    const nameEl = document.getElementById('family-name');
    if (nameEl) nameEl.textContent = f.name || 'CM FAMILY';
    const subEl = document.getElementById('family-sub');
    if (subEl) subEl.textContent = 'COMMAND SYSTEM';
    const crest = document.getElementById('crest');
    if (crest) crest.textContent = String(f.name || 'CM').slice(0, 2).toUpperCase();
  }
  // ---------------- tabs ----------------
  document.getElementById('tabs').addEventListener('click', e => {
    const tab = e.target.closest('.tab, .nav-link');
    if (!tab) return;
    activeTab = tab.dataset.tab;
    document.querySelectorAll('.tab, .nav-link').forEach(t => t.classList.toggle('active', t === tab));
    renderTab(activeTab);
  });

  function renderTab(tab) {
    if (!state) return;
    const titles = {
      overview: 'Family information',
      manage: 'Management',
      members: 'Members',
      ranks: 'Ranks & access',
      vehicles: 'Family vehicles',
      operations: 'Tactical Operations',
      hq: 'Headquarters',
      treasury: 'Family treasury',
      progression: 'Family progression',
      events: 'Tactical Operations',
      logs: 'Activity logs'
    };
    const heading = document.getElementById('workspace-title');
    if (heading) heading.textContent = (titles[tab] || titles.overview).toUpperCase();
    const subtitle = document.getElementById('workspace-subtitle');
    if (subtitle) {
      const subtitles = {
        overview: '// FAMILY CONTROL',
        manage: '// FAMILY MANAGEMENT',
        members: '// ROSTER & MEMBERS',
        ranks: '// ROLES & PERMISSIONS',
        vehicles: '// FLEET & GARAGE',
        operations: '// TACTICAL OPERATIONS',
        hq: '// HEADQUARTERS & PROPERTY',
        treasury: '// FINANCIAL CONTROL',
        progression: '// REPUTATION & MILESTONES',
        events: '// TACTICAL OPERATIONS',
        logs: '// AUDIT & ACTIVITY',
      };
      subtitle.textContent = subtitles[tab] || '// FAMILY CONTROL';
    }
    const levelBadge = document.getElementById('family-level-badge');
    if (levelBadge) {
      const level = Math.max(1, Number((state.progression && state.progression.level) || state.viewer.tier) || 1);
      levelBadge.textContent = `LEVEL ${level} FAMILY`;
    }
    ({
      overview: renderInformation,
      manage: renderManagementHub,
      members: renderMembers,
      ranks: renderRanks,
      vehicles: renderVehicles,
      operations: renderOperations,
      hq: renderHeadquarters,
      treasury: renderBank,
      progression: renderProgression,
      events: renderOperations,
      logs: renderEvents,
    }[tab] || renderInformation)();
  }

  const can = key => state.viewer.permissions[key] === true;
  const isFounder = () => state.viewer.isFounder === true;
  const myTier = () => state.viewer.tier;

  function goTab(tab) {
    activeTab = tab;
    document.querySelectorAll('.tab, .nav-link').forEach(t => t.classList.toggle('active', t.dataset.tab === tab));
    renderTab(tab);
  }

  function renderManagementHub() {
    const f = state.family;
    const online = state.members.filter(member => member.online).length;
    const rank = (state.ranks.find(item => item.id === state.viewer.rankId) || {}).name || 'Member';
    const symbol = f.symbol || state.viewer.symbol || 'shield';
    const color = f.color || state.viewer.symbolColor || '#00f0ff';
    const tile = (title, description, action, enabled, danger) => enabled ? `
      <button class="hub-action ${danger ? 'hub-action--danger' : ''}" data-hub-action="${esc(action)}">
        <div class="hub-action__content">
          <strong>${esc(title)}</strong>
          <small>${esc(description)}</small>
        </div>
        <span class="hub-action__arrow">›</span>
      </button>` : '';

    content.innerHTML = `
      <section class="glass-card hub-hero">
        <div style="z-index: 2;">
          <div class="card-desc" style="color: var(--accent-primary); margin-bottom: 6px;">FAMILY COMMAND &middot; OPERATIONS HUB</div>
          <h2 class="page-title" style="font-size: 32px; margin-bottom: 14px;">${esc(f.name)}</h2>
          <div class="tag-group-row" style="gap: 28px;">
            <div class="tag-block">
              <span class="tag-lbl">ROSTER</span>
              <span class="tag-val">${state.members.length} MEMBERS</span>
            </div>
            <div class="tag-block">
              <span class="tag-lbl">ACTIVE ONLINE</span>
              <span class="tag-val" style="color: var(--accent-primary);">${online} ONLINE</span>
            </div>
            <div class="tag-block">
              <span class="tag-lbl">YOUR RANK</span>
              <span class="tag-val" style="color: var(--accent-warning);">${esc(rank)}</span>
            </div>
            <div class="tag-block">
              <span class="tag-lbl">HEADQUARTERS</span>
              <span class="tag-val">${f.houseId ? 'HOUSE #' + esc(String(f.houseId).replace(/#/g, '')) : 'NO LINKED HOUSE'}</span>
            </div>
          </div>
        </div>
        <div class="hub-symbol" style="color:${esc(color)}; border-color:${esc(color)}">${symbolSvg(symbol)}</div>
      </section>

      <div class="hub-grid">
        <section class="glass-card hub-group">
          <div class="hub-group__head">
            <span class="tag-lbl" style="color: var(--accent-primary);">// FLEET &amp; TRANSPORT</span>
            <h3>Garage Operations</h3>
          </div>
          <div class="hub-group__actions">
            ${tile('Manage family transport', 'Shared vehicles and minimum rank tiers.', 'vehicles', can('garage.access') || can('family.manage_vehicles'))}
            ${tile('Recall family transport', 'Return available vehicles to their assigned garage slots.', 'recall', can('family.manage_vehicles'))}
          </div>
        </section>

        <section class="glass-card hub-group">
          <div class="hub-group__head">
            <span class="tag-lbl" style="color: var(--accent-primary);">// OPERATIONS &amp; CONTROLS</span>
            <h3>Tactical Controls</h3>
          </div>
          <div class="hub-group__actions">
            ${tile('Online family', `${online} of ${state.members.length} members online.`, 'members', true)}
            ${tile('Display family on map', 'Toggle nearby family-member minimap markers.', 'tracking', true)}
            ${tile('Set meeting point', 'Send your position to every online member.', 'meeting', can('family.set_meeting'))}
            ${tile('Manage ranks & access', 'Configure tiers and exact house permissions.', 'ranks', can('family.manage_ranks') || can('family.manage_perms'))}
            ${tile('Open family treasury', 'Review the balance, shared expenses, and contribution history.', 'treasury', can('bank.view') || can('bank.deposit') || can('bank.withdraw'))}
          </div>
        </section>

        <section class="glass-card hub-group">
          <div class="hub-group__head">
            <span class="tag-lbl" style="color: var(--accent-primary);">// ROSTER &amp; IDENTITY</span>
            <h3>Family Management</h3>
          </div>
          <div class="hub-group__actions">
            ${tile('Manage members', 'Invite, promote, demote, title, or remove members.', 'members', can('family.invite') || can('family.promote') || can('family.demote') || can('family.kick'))}
            ${tile('Customize family identity', 'Change the shared overhead icon and colour.', 'identity', can('family.manage_tags'))}
            ${tile('Rename family', 'Change the family display name.', 'rename', can('family.rename'))}
          </div>
        </section>

        <section class="glass-card hub-group warning-accent">
          <div class="hub-group__head">
            <span class="tag-lbl" style="color: var(--accent-warning);">// SECURITY &amp; ARCHIVE</span>
            <h3>Operations &amp; Recovery</h3>
          </div>
          <div class="hub-group__actions">
            ${tile('Activity logs', 'Review membership, house, vehicle, and security events.', 'logs', can('family.view_logs'))}
            ${tile('Leave family', 'Leave your current family membership.', 'leave', !isFounder(), true)}
            ${tile('Delete family', 'Permanently disband this family.', 'disband', isFounder(), true)}
          </div>
        </section>
      </div>`;

    document.querySelectorAll('[data-hub-action]').forEach(button => button.onclick = () => {
      const action = button.dataset.hubAction;
      if (['members', 'ranks', 'vehicles', 'treasury', 'logs'].includes(action)) return goTab(action);
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
    const progression = state.progression || {};
    const house = state.familyHouse || (f.houseId ? { id: f.houseId, label: `House ${String(f.houseId).replace(/#/g, '')}` } : null);
    const houseNumberClean = house ? String(house.houseNumber || house.id || '').replace(/[#\s]+/g, '') : (f.houseId ? String(f.houseId).replace(/[#\s]+/g, '') : '');
    const houseLabelClean = house ? (house.label ? String(house.label).replace(/#/g, '').trim() : (houseNumberClean ? `House ${houseNumberClean}` : 'Family House')) : 'NO LINKED HQ';
    const safeCssUrl = value => {
      const raw = String(value || '');
      if (/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(raw)) return raw;
      if (!/^https?:\/\//i.test(raw)) return '';
      return encodeURI(raw).replace(/['"()\\]/g, char => '%' + char.charCodeAt(0).toString(16).toUpperCase());
    };
    const houseImage = safeCssUrl(house && (house.imageData || house.image));
    const houseStyle = houseImage ? `style="background-image:linear-gradient(0deg,rgba(15,23,34,0.95) 0%,rgba(15,23,34,0.6) 100%),url('${esc(houseImage)}')"` : '';

    const currentXp = Number(progression.currentXp) || 0;
    const nextLevelXp = Number(progression.nextLevelXp) || 1000;
    const xpPercent = Math.min(100, Math.max(0, Math.round((currentXp / nextLevelXp) * 100)));
    const progressionLevel = Number(progression.level) || 1;
    const rank = (state.ranks.find(item => item.id === state.viewer.rankId) || {}).name || 'Member';
    const symbol = f.symbol || state.viewer.symbol || 'shield';
    const color = f.color || state.viewer.symbolColor || '#00E5FF';

    const hqLevel = (state.hqUpgrades && state.hqUpgrades.level) || (house && house.hqLevel) || 1;
    const objectives = Array.isArray(state.objectives) ? state.objectives : [];
    const activeObjective = objectives.find(o => !o.is_completed) || objectives[0];

    const leaderboard = Array.isArray(state.contributionLeaderboard) ? state.contributionLeaderboard : [];
    const topContributors = leaderboard.slice(0, 3);
    const logs = Array.isArray(state.activityLog) ? state.activityLog.slice(0, 4) : [];

    const activeOp = (state.operations && state.operations.active) || null;
    const activeOpStrip = activeOp ? `
      <div class="glass-card active-op-strip" style="display:flex; justify-content:space-between; align-items:center; padding:12px 20px; margin-bottom:14px; border-left:3px solid var(--cyan); background:rgba(0,229,255,0.06);">
        <div style="display:flex; align-items:center; gap:12px;">
          <span class="status-badge primary" style="font-size:10px; padding:3px 8px; font-weight:800;">OPERATION IN PROGRESS</span>
          <strong style="color:#fff; font-size:13px; text-transform:uppercase;">${esc(activeOp.label || activeOp.eventKey)}</strong>
          <span style="color:var(--text-muted); font-size:12px;">Phase: <b style="color:var(--cyan); text-transform:uppercase;">${esc(activeOp.state)}</b></span>
          <span style="color:var(--text-muted); font-size:12px;">Opponent: <b style="color:#fff;">${esc(activeOp.opponentName)}</b></span>
        </div>
        <div style="display:flex; align-items:center; gap:14px;">
          <span style="color:var(--text-muted); font-size:12px;">Participants: <b style="color:var(--cyan);">${activeOp.participantCount} Active</b></span>
          <button class="btn-primary" id="btn-info-goto-op" style="padding:6px 14px; font-size:11px;">VIEW OPERATION &rsaquo;</button>
        </div>
      </div>` : '';

    content.innerHTML = `
      ${activeOpStrip}
      <div class="bento-grid">
        <!-- ROW 1: Hero + HQ preview -->
        <div class="glass-card span-2-col image-card hero-bg">
          <div style="z-index: 2;">
            <div class="card-desc" style="color: var(--accent-primary); margin-bottom: 5px;">AUTHORITATIVE FAMILY COMMAND</div>
            <h2 class="page-title" style="font-size: 38px; margin-bottom: 8px;">${esc(f.name)}</h2>
            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
              <span class="status-badge warning">${esc(rank)}</span>
              <span class="status-badge primary">TIER ${state.viewer.tier || 1}</span>
            </div>
          </div>
          <div style="z-index: 2; display: flex; justify-content: space-between; align-items: flex-end;">
            <div style="width: 100%; max-width: 480px;">
              <div class="card-desc" style="margin-bottom: 6px;">REPUTATION PROGRESS &middot; LEVEL ${progressionLevel}</div>
              <div class="progress-block" style="margin-bottom: 12px;">
                <div class="progress-track" style="height: 10px;">
                  <div class="progress-fill" style="width: ${xpPercent}%;"></div>
                </div>
                <div class="progress-header" style="margin-top: 5px; font-size: 11px;">
                  <span>${currentXp.toLocaleString()} / ${nextLevelXp.toLocaleString()} XP (${xpPercent}%)</span>
                  <span>${Number(progression.lifetimeReputation || progression.reputation || 0).toLocaleString()} LIFETIME XP</span>
                </div>
              </div>
              <button class="btn-primary" id="btn-goto-progression" style="padding: 10px 18px; font-size: 11px;">VIEW PROGRESSION ROADMAP &#10142;</button>
            </div>
            <div class="hub-symbol" style="color:${esc(color)}; border-color:${esc(color)}; width: 70px; height: 70px; margin-left: 20px;">${symbolSvg(symbol)}</div>
          </div>
        </div>

        <div class="glass-card span-2-col image-card house-bg warning-accent" ${houseStyle}>
          <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 10px; z-index: 2;">
            <div class="card-desc" style="color: var(--accent-warning);">FAMILY HEADQUARTERS</div>
            <span class="badge ${house ? '' : 'founder'}">${house ? 'ACTIVE HQ' : 'NO HQ LINKED'}</span>
          </div>
          <div style="display: flex; flex-direction: column; justify-content: space-between; height: 100%; z-index: 2;">
            <div>
              <h2 class="card-title" style="font-size: 24px; margin-bottom: 4px;">${esc(houseLabelClean)}</h2>
              <div class="card-desc">${houseNumberClean ? 'HOUSE #' + esc(houseNumberClean) : 'LINK A RESIDENCE TO EXPAND HQ'}</div>
            </div>
            <div style="display: flex; justify-content: space-between; align-items: flex-end; margin-top: auto;">
              <div class="tag-group-row" style="gap: 16px;">
                <div class="tag-block">
                  <span class="tag-lbl">HQ LEVEL</span>
                  <span class="tag-val" style="color: var(--accent-primary);">LEVEL ${hqLevel}</span>
                </div>
                <div class="tag-block">
                  <span class="tag-lbl">GARAGE</span>
                  <span class="tag-val">${Array.isArray(state.vehicles) ? state.vehicles.length : 0} / ${Number(house && house.garageCapacity) || 10}</span>
                </div>
              </div>
              <div style="display: flex; gap: 8px;">
                ${house ? '<button class="btn ghost sm" id="overview-house-route-btn">GPS ROUTE &#10142;</button>' : ''}
                <button class="btn sm" id="overview-hq-btn">HQ DETAILS &#10142;</button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ROW 2: Four Compact Stats -->
      <div class="compact-stat-grid">
        <div class="compact-stat-pill pill-cyan">
          <span class="stat-label">Members Online</span>
          <span class="stat-value">${online} <span style="font-size: 14px; color: var(--text-dim);">/ ${state.members.length}</span></span>
        </div>
        <div class="compact-stat-pill pill-green">
          <span class="stat-label">Treasury Balance</span>
          <span class="stat-value">${money(f.bankBalance)}</span>
        </div>
        <div class="compact-stat-pill pill-amber">
          <span class="stat-label">Family Reputation</span>
          <span class="stat-value">${Number(progression.reputation || 0).toLocaleString()} <span style="font-size: 12px; color: var(--text-dim);">XP</span></span>
        </div>
        <div class="compact-stat-pill pill-blue">
          <span class="stat-label">HQ Upgrade Level</span>
          <span class="stat-value">LEVEL ${hqLevel}</span>
        </div>
      </div>

      <!-- ROW 3: Weekly Objective, Top Contributors, Recent Activity -->
      <div class="overview-lower-grid">
        <!-- Current Weekly Objective -->
        <div class="glass-card">
          <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 12px;">
            <div>
              <div class="card-desc" style="color: var(--accent-primary); margin-bottom: 4px;">CURRENT WEEKLY OBJECTIVE</div>
              <h3 class="card-title" style="font-size: 18px;">${esc(activeObjective ? activeObjective.label : 'WEEKLY OPERATIONS')}</h3>
            </div>
            <span class="badge ${activeObjective && activeObjective.is_completed ? 'success' : ''}">${activeObjective && activeObjective.is_completed ? 'COMPLETED' : 'ACTIVE'}</span>
          </div>
          <div>
            <p class="card-desc" style="margin-bottom: 12px; text-transform: none;">${esc(activeObjective ? activeObjective.description : 'Contribute to family goals to earn reputation and rewards.')}</p>
            <div class="progress-block">
              <div class="progress-header">
                <span>PROGRESS</span>
                <span style="color: var(--text-main); font-weight: 800;">${Number(activeObjective ? activeObjective.current_value : 0).toLocaleString()} / ${Number(activeObjective ? activeObjective.target_value : 1).toLocaleString()}</span>
              </div>
              <div class="progress-track">
                <div class="progress-fill ${activeObjective && activeObjective.is_completed ? 'success' : ''}" style="width: ${Math.min(100, Math.round(((activeObjective ? activeObjective.current_value : 0) / (activeObjective ? activeObjective.target_value : 1)) * 100))}%;"></div>
              </div>
            </div>
            ${activeObjective ? `
            <div style="display: flex; gap: 8px; margin-top: 14px;">
              <span class="reward-pill">+${activeObjective.reward_reputation} XP</span>
              <span class="reward-pill">+${activeObjective.reward_contribution} PTS</span>
              ${activeObjective.reward_money ? `<span class="reward-pill">+${money(activeObjective.reward_money)}</span>` : ''}
            </div>` : ''}
          </div>
          <div style="margin-top: 14px;">
            <button class="btn ghost sm" id="overview-more-objectives-btn" style="width: 100%;">VIEW ALL OBJECTIVES &#10142;</button>
          </div>
        </div>

        <!-- Top Contributors -->
        <div class="glass-card">
          <div style="margin-bottom: 10px;">
            <div class="card-desc" style="color: var(--accent-primary); margin-bottom: 4px;">CONTRIBUTIONS</div>
            <h3 class="card-title" style="font-size: 18px;">TOP 3 MEMBERS</h3>
          </div>
          <div style="display: flex; flex-direction: column; gap: 8px;">
            ${topContributors.length ? topContributors.map((c, i) => `
              <div class="list-row" style="padding: 6px 10px;">
                <div class="user-info">
                  <div class="user-avatar ${i === 0 ? 'warning' : ''}">${i + 1}</div>
                  <span class="user-name" style="font-size: 12px;">${esc(c.name)}</span>
                </div>
                <span style="font-size: 10px; font-weight: 800; color: var(--accent-success);">${Number(c.weeklyPoints != null ? c.weeklyPoints : c.weeklyContribution).toLocaleString()} PTS</span>
              </div>
            `).join('') : '<p class="card-desc" style="margin-top:14px">NO CONTRIBUTIONS YET</p>'}
          </div>
          <div style="margin-top: auto; padding-top: 14px;">
            <button class="btn ghost sm" id="overview-leaderboard-btn" style="width: 100%;">LEADERBOARD &#10142;</button>
          </div>
        </div>

        <!-- Compact Recent Activity -->
        <div class="glass-card">
          <div style="margin-bottom: 10px;">
            <div class="card-desc" style="color: var(--accent-primary); margin-bottom: 4px;">AUDIT TRAIL</div>
            <h3 class="card-title" style="font-size: 18px;">RECENT ACTIVITY</h3>
          </div>
          <div class="compact-activity-list">
            ${logs.length ? logs.map(l => `
              <div class="compact-activity-item">
                <div>
                  <strong>${esc(String(l.action || 'Action').replace(/_/g, ' '))}</strong>
                  <div style="font-size: 10px; color: var(--text-dim);">${esc(l.actor_name || 'System')}</div>
                </div>
                <span class="time">${esc(formatTimestamp(l.created_at, 16))}</span>
              </div>
            `).join('') : '<p class="card-desc" style="margin-top:14px">NO RECENT LOGS</p>'}
          </div>
          <div style="margin-top: auto; padding-top: 14px;">
            <button class="btn ghost sm" id="overview-logs-btn" style="width: 100%;">VIEW ALL LOGS &#10142;</button>
          </div>
        </div>
      </div>

      <!-- Family Announcement -->
      <section class="family-announcement" style="margin-top: 4px;">
        <div class="family-announcement__head">
          <div><span class="card-desc" style="color: var(--accent-primary);">LEADERSHIP ANNOUNCEMENT</span><h3>${f.announcement ? 'Broadcast' : 'No announcement'}</h3></div>
          ${can('family.manage_announcement') ? '<button class="btn ghost sm" id="announcement-edit">Edit message</button>' : ''}
        </div>
        <p class="family-announcement__message">${esc(f.announcement || 'No active announcement from family leadership.')}</p>
        ${f.announcement ? `<small>${esc(f.announcementByName || 'Family leadership')} &bull; ${esc(formatTimestamp(f.announcementAt, 16))}</small>` : ''}
        <div class="family-announcement__editor" id="announcement-editor" hidden>
          <textarea class="input" id="announcement-message" maxlength="280" rows="3" placeholder="Write a broadcast message for your family...">${esc(f.announcement || '')}</textarea>
          <div class="family-announcement__actions">
            <span id="announcement-count">${String(f.announcement || '').length}/280</span>
            <button class="btn ghost sm" id="announcement-cancel">Cancel</button>
            <button class="btn sm" id="announcement-save">Save message</button>
          </div>
        </div>
      </section>
    `;

    const gotoOpBtn = document.getElementById('btn-info-goto-op');
    if (gotoOpBtn) gotoOpBtn.onclick = () => goTab('operations');
    const gotoProgression = document.getElementById('btn-goto-progression');
    if (gotoProgression) gotoProgression.onclick = () => goTab('progression');
    const gotoHq = document.getElementById('overview-hq-btn');
    if (gotoHq) gotoHq.onclick = () => goTab('hq');
    const moreObj = document.getElementById('overview-more-objectives-btn');
    if (moreObj) moreObj.onclick = () => goTab('progression');
    const lbBtn = document.getElementById('overview-leaderboard-btn');
    if (lbBtn) lbBtn.onclick = () => goTab('progression');
    const logsBtn = document.getElementById('overview-logs-btn');
    if (logsBtn) logsBtn.onclick = () => goTab('logs');

    const routeBtn = document.getElementById('overview-house-route-btn');
    if (routeBtn) {
      routeBtn.onclick = () => {
        if (!house) { flash('No family house is assigned.', 'error'); return; }
        const coords = house.doorCoords || house.coords || house.door;
        post('routeToHouse', { houseId: house.id, coords }).then(res => {
          if (res && res.ok) flash(houseNumberClean ? `GPS route marked to Family House (${houseNumberClean}).` : 'GPS route marked to Family House.', 'ok');
          else flash('Could not mark GPS route to family house.', 'error');
        });
      };
    }

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

  // ---------------- headquarters ----------------
  function renderHeadquarters() {
    const f = state.family;
    const house = state.familyHouse || (f.houseId ? { id: f.houseId, label: `House ${String(f.houseId).replace(/#/g, '')}` } : null);
    const houseNumberClean = house ? String(house.houseNumber || house.id || '').replace(/[#\s]+/g, '') : (f.houseId ? String(f.houseId).replace(/[#\s]+/g, '') : '');
    const houseLabelClean = house ? (house.label ? String(house.label).replace(/#/g, '').trim() : (houseNumberClean ? `House ${houseNumberClean}` : 'Family House')) : 'NO ASSIGNED HOUSE';
    const safeCssUrl = value => {
      const raw = String(value || '');
      if (/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(raw)) return raw;
      if (!/^https?:\/\//i.test(raw)) return '';
      return encodeURI(raw).replace(/['"()\\]/g, char => '%' + char.charCodeAt(0).toString(16).toUpperCase());
    };
    const houseImage = safeCssUrl(house && (house.imageData || house.image));
    const houseStyle = houseImage ? `style="background-image:linear-gradient(0deg,rgba(15,23,34,0.95) 0%,rgba(15,23,34,0.6) 100%),url('${esc(houseImage)}')"` : '';

    const garageUsed = Array.isArray(state.vehicles) ? state.vehicles.length : 0;
    const garageCapacity = Number(house && (house.garageCapacity || house.garageSlots)) || 10;
    const hqUpgrades = state.hqUpgrades || {};
    const hqLevel = Number(hqUpgrades.level || (house && house.hqLevel) || 1);
    const canUpgrade = isFounder() || can('house.upgrade') || can('family.manage_house');

    const UPGRADE_SPECS = [
      { key: 'storage', name: 'Storage Allowance', desc: 'Increases shared HQ stash item capacity.', max: 3, unit: '+10 / +20 / +35 Stash Slots', baseCost: 50000, mult: 75000 },
      { key: 'armory', name: 'Armory Storage Space', desc: 'Increases weapon rack and secure armory allowance.', max: 3, unit: '+10 / +20 / +35 Armory Slots', baseCost: 75000, mult: 100000 },
      { key: 'garage_slots', name: 'Garage Fleet Slots', desc: 'Expands maximum stored family vehicles at the property.', max: 3, unit: '+2 / +4 / +6 Fleet Slots', baseCost: 100000, mult: 125000 },
      { key: 'command_room', name: 'Command & Briefing Room', desc: 'Enables high-tier tactical coordination, map tracking, and planning features.', max: 1, unit: 'UNLOCKED / FUTURE CAPABILITY', baseCost: 150000, mult: 0 }
    ];

    content.innerHTML = `
      <section class="hq-hero" ${houseStyle}>
        <div>
          <span class="card-desc" style="color: var(--accent-primary); margin-bottom: 6px;">FAMILY HEADQUARTERS &middot; AUTHORITATIVE PROPERTY</span>
          <h2 class="page-title" style="font-size: 36px; margin-bottom: 6px;">${esc(houseLabelClean)}</h2>
          <div class="card-desc" style="font-size: 13px; color: var(--text-main); margin-bottom: 16px;">
            ${house ? 'HOUSE #' + esc(houseNumberClean) + ' &bull; AUTHORITATIVE cm-house PROPERTY INTEGRATION' : 'NO LINKED PROPERTY'}
          </div>
          <div class="tag-group-row" style="gap: 20px;">
            <div class="tag-block">
              <span class="tag-lbl">HEADQUARTERS TIER</span>
              <span class="tag-val" style="color: var(--accent-primary);">LEVEL ${hqLevel}</span>
            </div>
            <div class="tag-block">
              <span class="tag-lbl">GARAGE USAGE</span>
              <span class="tag-val">${garageUsed} / ${garageCapacity} SLOTS</span>
            </div>
            <div class="tag-block">
              <span class="tag-lbl">TREASURY FUNDING</span>
              <span class="tag-val" style="color: var(--accent-success);">${money(f.bankBalance)}</span>
            </div>
          </div>
        </div>
        <div>
          ${house ? '<button class="btn-primary" id="btn-hq-route" style="padding: 12px 24px;">GPS ROUTE TO HQ &#10142;</button>' : ''}
        </div>
      </section>

      <div class="section-title">Headquarters Features</div>
      <div class="hq-specs-grid">
        <div class="hq-spec-card">
          <span class="spec-title">GARAGE &amp; FLEET</span>
          <span class="spec-status">${garageUsed} / ${garageCapacity}</span>
          <span class="spec-detail">Shared family vehicle slots managed by cm-house.</span>
        </div>
        <div class="hq-spec-card">
          <span class="spec-title">ARMORY / WEAPON STASH</span>
          <span class="spec-status" style="color: var(--accent-warning);">${(house && house.armoryCapacity) ? house.armoryCapacity + ' SLOTS' : 'AVAILABLE'}</span>
          <span class="spec-detail">Authoritative weapon locker with tier-restricted access.</span>
        </div>
        <div class="hq-spec-card">
          <span class="spec-title">STORAGE &amp; WARDROBE</span>
          <span class="spec-status" style="color: var(--accent-success);">${(house && house.storageCapacity) ? house.storageCapacity + ' SLOTS' : 'AVAILABLE'}</span>
          <span class="spec-detail">Family shared stash and wardrobe dressing points.</span>
        </div>
        <div class="hq-spec-card">
          <span class="spec-title">HELIPAD AVAILABILITY</span>
          <span class="spec-status">${(house && house.hasHelipad) ? 'AVAILABLE' : 'NONE'}</span>
          <span class="spec-detail">${(house && house.hasHelipad) ? 'Property includes dedicated rooftop/ground helipad.' : 'No helipad registered at this property.'}</span>
        </div>
      </div>

      <div class="section-title" style="margin-top: 14px;">
        Headquarters Upgrades
        <span class="card-desc" style="font-weight: normal; margin-left: 10px;">(FUNDED VIA FAMILY TREASURY)</span>
      </div>
      <div class="hq-upgrades-grid">
        ${UPGRADE_SPECS.map(spec => {
          const currentTier = Number(hqUpgrades[spec.key] || 0);
          const isMaxed = currentTier >= spec.max;
          const nextCost = spec.baseCost + (currentTier * spec.mult);
          const canAfford = Number(f.bankBalance || 0) >= nextCost;
          return `
            <div class="hq-upgrade-card">
              <div>
                <div class="upgrade-header">
                  <h4 style="font-size: 16px; font-weight: 800; color: var(--text-main);">${esc(spec.name)}</h4>
                  <span class="upgrade-tier-pill ${isMaxed ? 'maxed' : ''}">${isMaxed ? 'MAX TIER' : 'TIER ' + currentTier + ' / ' + spec.max}</span>
                </div>
                <p class="card-desc" style="text-transform: none; margin-top: 8px; font-size: 12px;">${esc(spec.desc)}</p>
                <div style="margin-top: 12px; font-size: 11px; font-weight: 800; color: var(--accent-primary);">
                  BENEFIT: ${esc(spec.unit)}
                </div>
              </div>
              <div style="margin-top: 16px;">
                ${isMaxed ? `
                  <button class="btn ghost sm" disabled style="width: 100%;">MAXIMUM LEVEL REACHED</button>
                ` : `
                  <button class="btn sm ${canAfford ? '' : 'danger'}" data-upgrade-key="${esc(spec.key)}" ${(!canUpgrade || !canAfford) ? 'disabled' : ''} style="width: 100%;">
                    ${!canUpgrade ? 'PERMISSIONS REQUIRED' : (!canAfford ? 'INSUFFICIENT FUNDS (' + money(nextCost) + ')' : 'PURCHASE UPGRADE (' + money(nextCost) + ')')}
                  </button>
                `}
              </div>
            </div>
          `;
        }).join('')}
      </div>
    `;

    const routeBtn = document.getElementById('btn-hq-route');
    if (routeBtn) {
      routeBtn.onclick = () => {
        if (!house) return flash('No family house linked.', 'error');
        const coords = house.doorCoords || house.coords || house.door;
        post('routeToHouse', { houseId: house.id, coords }).then(res => {
          if (res && res.ok) flash('GPS route marked to Family HQ.', 'ok');
          else flash('Could not mark GPS route.', 'error');
        });
      };
    }

    content.querySelectorAll('[data-upgrade-key]').forEach(btn => {
      btn.onclick = () => {
        const key = btn.dataset.upgradeKey;
        confirmAct(`Purchase this HQ upgrade from the family treasury?`, 'purchaseHQUpgrade', { upgradeKey: key });
      };
    });
  }

  // ---------------- progression ----------------
  let progressionLeaderboardTab = 'this_week';
  function renderProgression() {
    const f = state.family;
    const progression = state.progression || {};
    const currentXp = Number(progression.currentXp) || 0;
    const nextLevelXp = Number(progression.nextLevelXp) || 1000;
    const xpPercent = Math.min(100, Math.max(0, Math.round((currentXp / nextLevelXp) * 100)));
    const progressionLevel = Number(progression.level) || 1;
    const lifetimeRep = Number(progression.lifetimeReputation || progression.reputation || 0);

    const objectives = Array.isArray(state.objectives) ? state.objectives : [];
    const allUnlocks = (state.allLevelUnlocks && typeof state.allLevelUnlocks === 'object') ? state.allLevelUnlocks : {};

    const weeklyLb = Array.isArray(state.contributionLeaderboard) ? state.contributionLeaderboard : [];
    const allTimeLb = Array.isArray(state.allTimeLeaderboard) ? state.allTimeLeaderboard : [];
    const activeLb = progressionLeaderboardTab === 'this_week' ? weeklyLb : allTimeLb;

    content.innerHTML = `
      <section class="progression-hero">
        <div style="display: flex; justify-content: space-between; align-items: flex-start;">
          <div>
            <span class="card-desc" style="color: var(--accent-primary); margin-bottom: 4px;">FAMILY PROGRESSION &middot; LEVEL ${progressionLevel}</span>
            <h2 class="page-title" style="font-size: 34px; margin-bottom: 6px;">REPUTATION &amp; MILESTONES</h2>
            <div class="card-desc" style="font-size: 12px; text-transform: none;">Level up your family by completing weekly objectives, raids, and collaborative work.</div>
          </div>
          <div style="display: flex; gap: 14px; align-items: center;">
            <div class="tag-block" style="text-align: right;">
              <span class="tag-lbl">LIFETIME REP</span>
              <span class="tag-val" style="color: var(--accent-warning);">${lifetimeRep.toLocaleString()} XP</span>
            </div>
            <div class="status-badge primary" style="font-size: 16px; padding: 10px 18px;">LEVEL ${progressionLevel}</div>
          </div>
        </div>

        <div class="progression-bar-container" style="margin-top: 10px;">
          <div class="progression-bar-track">
            <div class="progression-bar-fill" style="width: ${xpPercent}%;"></div>
          </div>
          <div style="display: flex; justify-content: space-between; font-size: 12px; font-weight: 800; color: var(--text-dim);">
            <span>CURRENT XP: <strong style="color: var(--text-main);">${currentXp.toLocaleString()}</strong></span>
            <span>NEXT LEVEL: <strong style="color: var(--accent-primary);">${nextLevelXp.toLocaleString()} XP</strong> (${xpPercent}%)</span>
          </div>
        </div>
      </section>

      <!-- Weekly Objectives Section -->
      <div class="section-title">Weekly Family Objectives</div>
      <div class="objectives-grid">
        ${objectives.length ? objectives.map(obj => {
          const target = Number(obj.target_value) || 1;
          const current = Number(obj.current_value) || 0;
          const pct = Math.min(100, Math.round((current / target) * 100));
          return `
            <div class="objective-card ${obj.is_completed ? 'completed' : ''}">
              <div>
                <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 6px;">
                  <h4 style="font-size: 16px; font-weight: 800; color: var(--text-main);">${esc(obj.label || 'Objective')}</h4>
                  <span class="badge ${obj.is_completed ? 'success' : ''}">${obj.is_completed ? 'COMPLETED' : 'IN PROGRESS'}</span>
                </div>
                <p class="card-desc" style="text-transform: none; font-size: 12px; margin-bottom: 12px;">${esc(obj.description || '')}</p>
                <div class="progress-block">
                  <div class="progress-header">
                    <span>PROGRESS</span>
                    <span style="font-weight: 800; color: var(--text-main);">${current.toLocaleString()} / ${target.toLocaleString()} (${pct}%)</span>
                  </div>
                  <div class="progress-track" style="height: 8px;">
                    <div class="progress-fill ${obj.is_completed ? 'success' : ''}" style="width: ${pct}%;"></div>
                  </div>
                </div>
              </div>
              <div class="objective-reward-pills">
                <span class="reward-pill">+${obj.reward_reputation} Family XP</span>
                <span class="reward-pill">+${obj.reward_contribution} Member Pts</span>
                ${obj.reward_money ? `<span class="reward-pill">+${money(obj.reward_money)} Treasury</span>` : ''}
              </div>
            </div>
          `;
        }).join('') : '<div class="empty">No weekly objectives assigned.</div>'}
      </div>

      <!-- Level Unlocks Roadmap -->
      <div class="section-title" style="margin-top: 14px;">Family Level Unlocks (Levels 1 &ndash; 25)</div>
      <div class="milestones-scroll-list">
        ${Array.from({ length: 25 }, (_, i) => i + 1).map(lvl => {
          const unlock = allUnlocks[lvl] || {};
          const isUnlocked = progressionLevel >= lvl;
          const isCurrent = progressionLevel === lvl;
          return `
            <div class="milestone-card ${isUnlocked ? 'unlocked' : 'locked'} ${isCurrent ? 'current' : ''}">
              <div style="display: flex; justify-content: space-between; align-items: center;">
                <span style="font-size: 16px; font-weight: 900; color: ${isUnlocked ? 'var(--accent-primary)' : 'var(--text-dim)'};">LVL ${lvl}</span>
                <span class="badge ${isUnlocked ? 'success' : ''}" style="font-size: 9px;">${isUnlocked ? (isCurrent ? 'CURRENT' : 'UNLOCKED') : 'LOCKED'}</span>
              </div>
              <div style="font-size: 11px; font-weight: 700; color: var(--text-main); margin-top: 4px;">
                ${esc(unlock.title || ('Level ' + lvl + ' Perks'))}
              </div>
              <div class="card-desc" style="text-transform: none; font-size: 10px; line-height: 1.4;">
                ${esc(unlock.description || (unlock.maxMembers ? `${unlock.maxMembers} members, ${unlock.maxVehicles || 5} vehicles` : 'Expanded family capabilities.'))}
              </div>
            </div>
          `;
        }).join('')}
      </div>

      <!-- Member Contribution Leaderboard -->
      <div class="section-title" style="margin-top: 14px;">Member Contribution Leaderboard</div>
      <div class="glass-card" style="padding: 20px;">
        <div class="leaderboard-toggle">
          <button class="leaderboard-toggle-btn ${progressionLeaderboardTab === 'this_week' ? 'active' : ''}" id="btn-lb-week">THIS WEEK</button>
          <button class="leaderboard-toggle-btn ${progressionLeaderboardTab === 'all_time' ? 'active' : ''}" id="btn-lb-all">ALL TIME</button>
        </div>
        <div class="list">
          ${activeLb.length ? activeLb.map((m, idx) => `
            <div class="row" style="padding: 10px 14px;">
              <div style="font-size: 18px; font-weight: 900; color: ${idx === 0 ? 'var(--accent-warning)' : 'var(--text-dim)'}; width: 32px;">#${idx + 1}</div>
              <div class="row__main">
                <div class="row__title">${esc(m.name)}</div>
                <div class="row__sub">CID ${esc(m.characterId || m.character_id || m.cid || '?')} &bull; Financial: ${money(m.moneyContributed != null ? m.moneyContributed : m.totalContribution || 0)}</div>
              </div>
              <div style="text-align: right;">
                <div style="font-size: 16px; font-weight: 900; color: var(--accent-success);">${Number(progressionLeaderboardTab === 'this_week' ? (m.weeklyPoints != null ? m.weeklyPoints : m.weeklyContribution) : (m.totalPoints != null ? m.totalPoints : m.totalContribution)).toLocaleString()} PTS</div>
                <div style="font-size: 10px; color: var(--text-dim);">${progressionLeaderboardTab === 'this_week' ? 'Weekly Contribution' : 'Lifetime Contribution'}</div>
              </div>
            </div>
          `).join('') : '<div class="empty">No contributions recorded for this period.</div>'}
        </div>
      </div>
    `;

    const weekBtn = document.getElementById('btn-lb-week');
    if (weekBtn) weekBtn.onclick = () => { progressionLeaderboardTab = 'this_week'; renderProgression(); };
    const allBtn = document.getElementById('btn-lb-all');
    if (allBtn) allBtn.onclick = () => { progressionLeaderboardTab = 'all_time'; renderProgression(); };
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
        actions.push(`<input class="input" maxlength="24" placeholder="Member title" value="${esc(m.customTitle || '')}" data-title="${esc(m.cid)}" style="width:130px">`);
      }
      return `<div class="row">
        <span class="dot ${m.online ? 'on' : 'off'}"></span>
        <div class="row__main">
          <div class="row__title">${esc(m.name)} ${m.isFounder ? '<span class="badge founder">Head</span>' : ''} <span style="font-size: 11px; color: var(--text-dim); font-weight: normal;">(CID ${esc(m.cid)})</span></div>
          <div class="row__sub">${esc(m.customTitle || m.rankName)} · Tier ${m.tier} · ${m.online ? '<span style="color:var(--accent-success)">online now</span>' : 'last seen ' + (formatTimestamp(m.lastSeen, 16) || 'unknown')}</div>
          <div class="member-metrics" style="margin-top: 6px;">
            <span>Contribution: <strong>${Number(m.totalPoints != null ? m.totalPoints : m.totalContribution).toLocaleString()} pts</strong></span>
            <span>This week: <strong>${Number(m.weeklyPoints != null ? m.weeklyPoints : m.weeklyContribution).toLocaleString()} pts</strong></span>
            <span>Financial: <strong>${money(m.moneyContributed != null ? m.moneyContributed : m.totalContribution)}</strong></span>
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
        <div class="row__sub" style="margin-top:6px">Use the G menu while looking at a player, or invite via character ID below:</div>
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
  // ---------------- bank / treasury ----------------
  function renderBank() {
    const f = state.family;
    const treasury = state.treasury || {};
    const leaderboard = Array.isArray(state.contributionLeaderboard) ? state.contributionLeaderboard : [];
    const log = (state.bankLog || []).map(l => {
      const cat = String(l.category || l.reason || l.direction || 'default').toLowerCase();
      const badgeClass = cat.includes('deposit') ? 'tx-category--deposit' : (cat.includes('withdraw') ? 'tx-category--withdraw' : (cat.includes('upgrade') ? 'tx-category--hq_upgrade' : (cat.includes('event') ? 'tx-category--event_reward' : 'tx-category--default')));
      return `
        <div class="log-row" style="display:flex; justify-content:space-between; align-items:center; padding: 10px 14px;">
          <div>
            <span class="tx-category-badge ${badgeClass}">${esc(l.category || l.direction)}</span>
            <span class="what" style="margin-left: 8px; font-weight: 700; color: ${l.direction === 'deposit' ? 'var(--accent-success)' : 'var(--text-main)'};">${l.direction === 'deposit' ? '+' : '−'} ${money(l.amount)}</span>
            <div style="font-size: 11px; color: var(--text-dim); margin-top: 4px;">
              ${esc(l.reason || l.direction)} ${l.character_id ? '· CID ' + esc(l.character_id) : ''}
            </div>
          </div>
          <span class="when" style="font-size: 11px; color: var(--text-dim);">${esc(formatTimestamp(l.created_at, 16))}</span>
        </div>`;
    }).join('');

    content.innerHTML = `
      <div class="grid grid--3" style="margin-bottom:18px">
        <div class="card treasury-balance-card">
          <h3>Available treasury</h3>
          <div class="big" style="color: var(--accent-success);">${money(f.bankBalance)}</div>
          <div class="row__sub">Shared family funds</div>
        </div>
        <div class="card">
          <h3>Income last 7 days</h3>
          <div class="big treasury-positive" style="color: var(--accent-success);">${money(treasury.income7d || 0)}</div>
          <div class="row__sub">Deposits and rewards</div>
        </div>
        <div class="card">
          <h3>Expenses last 7 days</h3>
          <div class="big treasury-expense" style="color: var(--accent-danger);">${money(treasury.expenses7d || 0)}</div>
          <div class="row__sub">Withdrawals and HQ upgrades</div>
        </div>
      </div>
      <div class="grid grid--2" style="margin-bottom:18px">
        <div class="card">
          <h3>Move money</h3>
          <div class="row__sub" style="margin-bottom: 10px;">Deposit to family funds or withdraw if authorized by rank permissions.</div>
          <div class="inline" style="margin-top:8px">
            <input class="input" id="bank-amount" type="number" min="1" placeholder="Amount ($)" style="width:180px">
            ${can('bank.deposit') ? '<button class="btn" id="deposit-btn">Deposit</button>' : ''}
            ${can('bank.withdraw') ? '<button class="btn ghost danger" id="withdraw-btn">Withdraw</button>' : ''}
          </div>
        </div>
        <div class="card">
          <h3>Top Financial Contributors</h3>
          <div class="contribution-leaderboard contribution-leaderboard--dark">
            ${leaderboard.slice(0, 5).map((member, index) => `
              <div>
                <i>${index + 1}</i>
                <strong>${esc(member.name)}</strong>
                <small>${money(member.moneyContributed != null ? member.moneyContributed : member.totalContribution)} total financial</small>
              </div>
            `).join('') || '<p>No financial contributions recorded yet.</p>'}
          </div>
        </div>
      </div>
      <div class="section-title">Treasury Movements &amp; Activity</div>
      ${log ? `<div class="list">${log}</div>` : '<div class="empty">No transactions yet.</div>'}
    `;

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

  // ---------------- tactical operations (phase 1) ----------------
  function renderOperations() {
    const ops = state.operations || {};
    const activeOp = ops.active || null;
    const available = Array.isArray(ops.available) ? ops.available : (Array.isArray(state.familyEvents) ? state.familyEvents : []);
    const recent = Array.isArray(ops.recent) ? ops.recent : [];

    // 1. ACTIVE OPERATION SECTION
    let activeHtml = '';
    if (activeOp) {
      const remainingMin = Math.ceil((activeOp.timeRemainingSeconds || 0) / 60);
      const phaseBadge = `<span class="status-badge ${activeOp.state === 'active' ? 'primary' : 'warning'}" style="font-weight:900; letter-spacing:0.08em;">${esc(activeOp.state.toUpperCase())}</span>`;
      activeHtml = `
        <section class="glass-card" style="border-left: 4px solid var(--cyan); background: rgba(0, 229, 255, 0.05); margin-bottom: 22px;">
          <div style="display:flex; justify-content:space-between; align-items:flex-start; margin-bottom: 14px;">
            <div>
              <span class="tag-lbl" style="color:var(--cyan); letter-spacing:0.12em;">// ACTIVE TACTICAL OPERATION</span>
              <h2 style="font-size: 26px; color:#fff; margin: 4px 0 0 0; text-transform:uppercase;">${esc(activeOp.label || activeOp.eventKey)}</h2>
            </div>
            <div>${phaseBadge}</div>
          </div>
          <div class="gameplay-event-stats" style="grid-template-columns: repeat(5, 1fr); margin-bottom: 16px;">
            <div><span>Opponent</span><strong style="color:#fff;">${esc(activeOp.opponentName)}</strong></div>
            <div><span>Participants</span><strong style="color:var(--cyan);">${activeOp.participantCount} Active</strong></div>
            <div><span>Location</span><strong>${esc(activeOp.location || 'Designated Area')}</strong></div>
            <div><span>Time Remaining</span><strong>${remainingMin} min</strong></div>
            <div><span>Objective</span><strong style="color:var(--accent-warning);">${activeOp.state === 'forming' ? 'Awaiting Opponent' : (activeOp.state === 'countdown' ? 'Countdown Phase' : 'Hold Circle')}</strong></div>
          </div>
          <div style="display:flex; justify-content:space-between; align-items:center;">
            <p style="margin:0; font-size:12.5px; color:var(--text-muted);">
              ${activeOp.state === 'forming' ? 'Waiting for opposing family members to enter the raid circle.' : (activeOp.state === 'countdown' ? 'Countdown initiated. Stand ground inside the perimeter wall.' : 'Combat active. Eliminate opponents or hold the circle until time expires.')}
            </p>
            <button class="btn-primary" id="btn-close-to-operation" style="padding: 9px 20px; font-size: 11px;">CLOSE &amp; RETURN TO WORLD &#10142;</button>
          </div>
        </section>`;
    } else {
      activeHtml = `
        <div class="glass-card" style="padding: 16px 20px; margin-bottom: 22px; display:flex; justify-content:space-between; align-items:center;">
          <div>
            <span class="tag-lbl" style="color:var(--text-muted);">// CURRENT STATUS</span>
            <div style="color:var(--text-white); font-weight:700; font-size:14px; margin-top:2px;">NO ACTIVE OPERATIONS UNDERWAY</div>
            <div style="color:var(--text-muted); font-size:12px; margin-top:2px;">Your family is not currently engaged in any tactical operation. Review eligible operations below.</div>
          </div>
          <span class="badge" style="background:rgba(255,255,255,0.06); color:var(--text-muted); border:1px solid rgba(255,255,255,0.1);">STANDBY</span>
        </div>`;
    }

    // 2. AVAILABLE OPERATIONS SECTION (Phase 1: family_raid)
    const availableCards = available.map(op => {
      let badgeHtml = '';
      if (op.status === 'ready') {
        badgeHtml = `<span class="badge" style="background:rgba(0,229,255,0.15); color:var(--cyan); border:1px solid var(--cyan); font-weight:800;">READY</span>`;
      } else if (op.status === 'cooldown') {
        const cdMin = Math.ceil((op.cooldownRemainingSeconds || 0) / 60);
        badgeHtml = `<span class="badge warning">COOLDOWN (${cdMin}M)</span>`;
      } else {
        badgeHtml = `<span class="badge danger">LOCKED (REQ. LVL ${op.minFamilyLevel || 1})</span>`;
      }

      const rewardPreview = op.rewards ? `
        <div style="margin-top: 10px; padding: 8px 12px; background:#10222B; border:1px solid var(--border-dim); border-radius:4px; font-size:11.5px; display:flex; gap:16px;">
          <span>Treasury: <b style="color:var(--cyan);">${money(op.rewards.treasury || 50000)}</b></span>
          <span>Reputation: <b style="color:var(--cyan);">+${Number(op.rewards.reputation || 750).toLocaleString()} XP</b></span>
          <span>Contribution: <b style="color:var(--accent-warning);">+${op.rewards.contribution || 150} PTS</b></span>
        </div>` : '';

      return `
        <div class="glass-card" style="padding: 20px 22px; border:1px solid var(--border-dim); border-bottom:3px solid var(--cyan);">
          <div style="display:flex; justify-content:space-between; align-items:flex-start; margin-bottom: 8px;">
            <div>
              <span class="tag-lbl" style="color:var(--cyan); letter-spacing:0.12em;">${esc(op.category || 'COMPETITIVE').toUpperCase()}</span>
              <h3 style="font-size: 20px; color:#fff; margin: 3px 0 0 0; text-transform:uppercase;">${esc(op.label || op.name || 'Family Operation')}</h3>
            </div>
            <div>${badgeHtml}</div>
          </div>
          <p style="color:var(--text-body); font-size:12.5px; line-height:1.45; margin: 4px 0 14px 0;">${esc(op.description || '')}</p>
          <div class="gameplay-event-stats">
            <div><span>Required Level</span><strong>Level ${op.minFamilyLevel || 1}</strong></div>
            <div><span>Team Requirement</span><strong>${op.minParticipants || 2}&ndash;${op.maxParticipants || 8} Members</strong></div>
            <div><span>Duration</span><strong>${op.durationMinutes || 15} min</strong></div>
            <div><span>Cooldown</span><strong>${op.cooldownMinutes || 180} min</strong></div>
          </div>
          ${rewardPreview}
          <div style="margin-top: 14px; font-size: 11px; color:var(--text-muted); display:flex; justify-content:space-between; align-items:center;">
            <span>Initiation: Travel to an opposing family's linked headquarters door.</span>
            <span style="color:var(--cyan); font-weight:700;">PHASE 1 OPERATIONAL</span>
          </div>
        </div>`;
    }).join('') || '<div class="empty">No family operations configured.</div>';

    // 3. RECENT OPERATIONS SECTION (~10)
    let recentRows = '';
    if (recent.length > 0) {
      recentRows = `
        <div class="table-wrap" style="margin-top: 10px;">
          <table class="table" style="width:100%; border-collapse:collapse; font-size:12px;">
            <thead>
              <tr style="text-align:left; border-bottom:1px solid var(--border-dim); color:var(--text-muted);">
                <th style="padding:10px 12px;">OPERATION</th>
                <th style="padding:10px 12px;">OPPONENT</th>
                <th style="padding:10px 12px;">RESULT</th>
                <th style="padding:10px 12px;">REASON</th>
                <th style="padding:10px 12px;">DURATION</th>
                <th style="padding:10px 12px;">REWARD</th>
                <th style="padding:10px 12px;">DATE</th>
              </tr>
            </thead>
            <tbody>
              ${recent.map(r => {
                let resBadge = '';
                if (r.state === 'completed') {
                  resBadge = r.won
                    ? '<span class="status-badge primary" style="padding:2px 8px; font-size:10px;">VICTORY</span>'
                    : '<span class="status-badge danger" style="padding:2px 8px; font-size:10px;">DEFEAT</span>';
                } else if (r.state === 'cancelled') {
                  resBadge = '<span class="status-badge" style="padding:2px 8px; font-size:10px; background:rgba(255,255,255,0.06); color:var(--text-muted);">CANCELLED</span>';
                } else if (r.state === 'failed') {
                  resBadge = '<span class="status-badge danger" style="padding:2px 8px; font-size:10px; background:rgba(255,80,80,0.1); color:#ff6b6b;">FAILED</span>';
                } else if (r.state === 'expired') {
                  resBadge = '<span class="status-badge warning" style="padding:2px 8px; font-size:10px;">EXPIRED</span>';
                } else {
                  resBadge = `<span class="status-badge" style="padding:2px 8px; font-size:10px;">${esc((r.state || 'UNKNOWN').toUpperCase())}</span>`;
                }
                const reasonLabel = String(r.resultReason || 'complete').replace(/_/g, ' ');
                const actualCredited = r.treasuryCredited != null ? r.treasuryCredited : (r.rewardCredited || 0);
                return `
                  <tr style="border-bottom:1px solid rgba(255,255,255,0.04);">
                    <td style="padding:10px 12px; font-weight:700; color:#fff;">${esc(r.label || r.eventKey)}</td>
                    <td style="padding:10px 12px;">${esc(r.opponentName || 'Unknown')}</td>
                    <td style="padding:10px 12px;">${resBadge}</td>
                    <td style="padding:10px 12px; color:var(--text-muted); text-transform:capitalize;">${esc(reasonLabel)}</td>
                    <td style="padding:10px 12px;">${r.durationMinutes || 0}m</td>
                    <td style="padding:10px 12px; color:${r.won ? 'var(--cyan)' : 'var(--text-muted)'}; font-weight:700;">${r.won ? money(actualCredited) : '$0'}</td>
                    <td style="padding:10px 12px; color:var(--text-muted); font-size:11px;">${formatTimestamp(r.completedAt, 16)}</td>
                  </tr>`;
              }).join('')}
            </tbody>
          </table>
        </div>`;
    } else {
      recentRows = '<div class="empty" style="padding: 24px 0; text-align:center; color:var(--text-muted); font-size:12.5px;">No recent tactical operations on record.</div>';
    }

    content.innerHTML = `
      <div style="display:flex; flex-direction:column; gap:4px;">
        ${activeHtml}

        <div style="margin-top: 6px; margin-bottom: 22px;">
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom: 12px;">
            <div class="section-title" style="margin:0;">Available Operations</div>
            <span class="tag-lbl" style="color:var(--text-muted);">PHASE 1 ENGINE</span>
          </div>
          <div style="display:grid; grid-template-columns: 1fr; gap:14px;">
            ${availableCards}
          </div>
        </div>

        <section class="glass-card" style="padding: 20px 22px;">
          <div class="section-title" style="margin:0 0 4px 0;">Recent Operations History</div>
          <div style="font-size:12px; color:var(--text-muted); margin-bottom:12px;">Durable operational record of recent battles and raid results.</div>
          ${recentRows}
        </section>
      </div>`;

    const closeBtn = document.getElementById('btn-close-to-operation');
    if (closeBtn) {
      closeBtn.onclick = () => closeMenu();
    }
  }

  const renderGameplayEvents = renderOperations;
  // ---------------- activity event timeline ----------------
  function renderEvents() {
    if (state.activityLog === false) {
      content.innerHTML = `<div class="empty"><h2>Events</h2><div>Your rank cannot view the family event history.</div></div>`;
      return;
    }
    const rows = Array.isArray(state.activityLog) ? state.activityLog : [];
    const categories = [...new Set(rows.map(row => row.category || 'family'))].sort();
    const actionLabel = value => String(value || 'activity').replace(/_/g, ' ').replace(/\b\w/g, char => char.toUpperCase());
    const valueText = value => {
      if (value == null || value === '') return 'Not recorded';
      if (typeof value === 'boolean') return value ? 'Yes' : 'No';
      if (typeof value === 'object') {
        try { return JSON.stringify(value); } catch (_) { return String(value); }
      }
      return String(value);
    };
    const summaryText = row => {
      const detail = row.detail && typeof row.detail === 'object' ? row.detail : {};
      const parts = [];
      if (row.target_name || row.target_cid) parts.push(`Target: ${row.target_name || ('CID ' + row.target_cid)}`);
      if (row.house_id) parts.push(`House #${row.house_id}`);
      if (row.vehicle_id) parts.push(`Vehicle #${row.vehicle_id}`);
      if (row.amount != null) parts.push(money(row.amount));
      if (detail.reason) parts.push(detail.reason);
      return parts.join(' - ');
    };
    const eventFields = row => {
      const detail = row.detail && typeof row.detail === 'object' ? row.detail : {};
      const fields = [
        ['Event ID', row.id],
        ['Action', actionLabel(row.action)],
        ['Category', actionLabel(row.category || 'family')],
        ['Severity', String(row.severity || 'info').toUpperCase()],
        ['Status', actionLabel(row.status || 'recorded')],
        ['Occurred', formatTimestamp(row.created_at, 19)],
        ['Actor', row.actor_name || (row.actor_cid ? 'CID ' + row.actor_cid : 'System')],
        ['Actor CID', row.actor_cid],
        ['Target', row.target_name || (row.target_cid ? 'CID ' + row.target_cid : null)],
        ['Target CID', row.target_cid],
        ['Source', row.source_resource || 'cm-family'],
        ['Entity type', row.entity_type],
        ['Entity ID', row.entity_id],
        ['House ID', row.house_id],
        ['Vehicle ID', row.vehicle_id],
        ['Amount', row.amount != null ? money(row.amount) : null],
      ];
      Object.keys(detail).sort().forEach(key => fields.push([actionLabel(key), detail[key]]));
      return fields.filter(([, value]) => value != null && value !== '');
    };
    const renderPreview = row => row ? `
      <section class="event-preview ${row.high_risk ? 'event-preview--risk' : ''}" aria-live="polite">
        <div class="event-preview__hero">
          <div><span class="hub-eyebrow">EVENT DETAILS</span><h3>${esc(actionLabel(row.action))}</h3></div>
          <span class="audit-severity audit-severity--${esc(row.severity || 'info')}">${row.high_risk ? 'HIGH RISK' : esc(String(row.severity || 'info').toUpperCase())}</span>
        </div>
        <div class="event-preview__grid">${eventFields(row).map(([label, value]) => `
          <div class="event-detail"><span>${esc(label)}</span><strong>${esc(valueText(value))}</strong></div>`).join('')}</div>
      </section>` : `<section class="event-preview event-preview--empty"><div><span class="event-preview__mark">06</span><h3>Select an event</h3><p>Choose an event from the timeline to preview every recorded detail.</p></div></section>`;
    const filteredRows = filter => rows.filter(row => filter === 'all' || row.category === filter);
    const renderRows = (filter, selectedId) => filteredRows(filter).map(row => `
      <button type="button" class="activity-row event-row ${row.high_risk ? 'activity-row--risk' : ''} ${String(row.id) === String(selectedId) ? 'is-selected' : ''}" data-event-id="${esc(row.id)}">
        <div class="activity-row__head"><div class="inline"><span class="audit-severity audit-severity--${esc(row.severity || 'info')}">${row.high_risk ? 'HIGH RISK' : esc(String(row.severity || 'info').toUpperCase())}</span><strong>${esc(actionLabel(row.action))}</strong></div><span class="when">${esc(formatTimestamp(row.created_at, 19))}</span></div>
        <div class="activity-row__meta">${esc(row.actor_name || (row.actor_cid ? 'CID ' + row.actor_cid : 'System'))} - ${esc(actionLabel(row.category || 'family'))}</div>
        ${summaryText(row) ? `<div class="activity-row__detail">${esc(summaryText(row))}</div>` : ''}
        <span class="event-row__action">Preview details <b>&rsaquo;</b></span>
      </button>`).join('');
    let selectedId = rows[0] ? rows[0].id : null;
    content.innerHTML = `
      <div class="events-toolbar"><div><div class="section-title" style="margin:0">Family events</div><div class="row__sub">Review the complete timeline and preview every recorded event detail.</div></div>
        <select class="input" id="activity-filter" style="width:190px"><option value="all">All categories</option>${categories.map(category => `<option value="${esc(category)}">${esc(actionLabel(category))}</option>`).join('')}</select></div>
      <div class="events-layout">
        <div class="event-timeline"><div class="event-timeline__head"><span>EVENT TIMELINE</span><strong id="event-count">${rows.length} event${rows.length === 1 ? '' : 's'}</strong></div><div class="list" id="activity-list">${renderRows('all', selectedId) || '<div class="empty">No family events yet.</div>'}</div></div>
        <div id="event-preview">${renderPreview(rows[0])}</div>
      </div>`;
    document.getElementById('activity-filter').onchange = event => {
      const filtered = filteredRows(event.target.value);
      selectedId = filtered[0] ? filtered[0].id : null;
      document.getElementById('activity-list').innerHTML = renderRows(event.target.value, selectedId) || '<div class="empty">No events in this category.</div>';
      document.getElementById('event-preview').innerHTML = renderPreview(filtered[0]);
      document.getElementById('event-count').textContent = `${filtered.length} event${filtered.length === 1 ? '' : 's'}`;
    };
    content.onclick = event => {
      const button = event.target.closest('[data-event-id]');
      if (!button) return;
      selectedId = button.dataset.eventId;
      document.querySelectorAll('[data-event-id]').forEach(item => item.classList.toggle('is-selected', item === button));
      document.getElementById('event-preview').innerHTML = renderPreview(rows.find(row => String(row.id) === String(selectedId)));
    };
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

  // ---------------- top nav controls ----------------
  function updateSysClock() {
    const el = document.getElementById('sys-clock');
    if (!el) return;
    const now = new Date();
    let hours = now.getHours();
    const minutes = String(now.getMinutes()).padStart(2, '0');
    const ampm = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12 || 12;
    el.textContent = `SYS: ${String(hours).padStart(2, '0')}:${minutes} ${ampm}`;
  }
  setInterval(updateSysClock, 1000);
  updateSysClock();

  let isOnDuty = false;
  const dutyBtn = document.getElementById('btn-duty');
  if (dutyBtn) {
    dutyBtn.onclick = () => {
      isOnDuty = !isOnDuty;
      dutyBtn.textContent = isOnDuty ? 'ON DUTY' : 'OFF DUTY';
      dutyBtn.classList.toggle('active', isOnDuty);
      flash(isOnDuty ? 'Family status set to ON DUTY.' : 'Family status set to OFF DUTY.', 'ok');
    };
  }

  const refreshBtn = document.getElementById('btn-refresh');
  if (refreshBtn) {
    refreshBtn.onclick = () => {
      post('refresh', {}).then(res => {
        if (res && res.snapshot) {
          openMenu(res.snapshot);
          flash('Family command system updated.', 'ok');
        } else {
          flash('Refreshed.', 'ok');
        }
      });
    };
  }

  document.getElementById('btn-close').onclick = closeAll;
  document.getElementById('btn-create-close').onclick = closeAll;
  document.addEventListener('keyup', e => { if (e.key === 'Escape') closeAll(); });
})();
