/* cm-house v1.5.0 — secure weapon storage UI */
(() => {
  const root = document.getElementById('weapon-storage');
  if (!root) return;

  const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  const el = (id) => document.getElementById(id);
  const state = { data: null, filter: 'weapon', search: '', busy: false };

  const chooseAmount = (item, direction) => new Promise((resolve) => {
    const available = Math.max(1, Number(item.quantity) || 1);
    const isFamily = Boolean(state.data?.isFamily);
    const policy = !isFamily
      ? available
      : (item.itemType === 'ammo'
          ? Number(state.data?.settings?.ammoLimit || 1000)
          : Number(state.data?.settings?.weaponLimit || 10));
    const max = direction === 'withdraw' ? Math.min(available, policy) : available;
    const overlay = document.createElement('div');
    overlay.className = 'ws-checkout';
    const action = direction === 'deposit' ? 'STORE' : 'TAKE';
    const unit = item.itemType === 'ammo' ? 'ROUNDS' : 'ITEMS';
    overlay.innerHTML = `<section class="ws-checkout__card" role="dialog" aria-modal="true" aria-labelledby="ws-checkout-title">
      <small>SECURE TRANSFER</small><h2 id="ws-checkout-title">${action} ${String(item.label || item.itemName || 'EQUIPMENT')}</h2>
      <p>Choose how many ${unit.toLowerCase()} to ${direction === 'deposit' ? 'place in' : 'take from'} this locker. <b>${max}</b> available.</p>
      <div class="ws-checkout__label"><span>QUANTITY</span><strong>MAX ${max}</strong></div>
      <div class="ws-stepper"><button type="button" data-step="-1">−</button><output>1</output><button type="button" data-step="1">+</button></div>
      <div class="ws-checkout__actions"><button type="button" data-cancel>CANCEL</button><button type="button" data-confirm>${action} ${unit}</button></div>
    </section>`;
    document.body.appendChild(overlay);
    let amount = 1;
    const output = overlay.querySelector('output');
    const finish = (value) => { overlay.remove(); resolve(value); };
    overlay.querySelectorAll('[data-step]').forEach((button) => button.onclick = () => {
      amount = Math.max(1, Math.min(max, amount + Number(button.dataset.step)));
      output.textContent = String(amount);
    });
    overlay.querySelector('[data-cancel]').onclick = () => finish(0);
    overlay.querySelector('[data-confirm]').onclick = () => finish(amount);
    overlay.onclick = (event) => { if (event.target === overlay) finish(0); };
  });

  const formatRelativeTime = (dateStr) => {
    if (!dateStr) return '';
    try {
      const date = new Date(dateStr);
      const diff = Math.floor((Date.now() - date.getTime()) / 1000);
      if (isNaN(diff)) return String(dateStr);
      if (diff < 60) return 'Just now';
      if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
      if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
      return `${Math.floor(diff / 86400)}d ago`;
    } catch (_) {
      return String(dateStr);
    }
  };

  const loadLogs = async () => {
    const listEl = el('ws-logs-list');
    const emptyEl = el('ws-logs-empty');
    if (!listEl) return;
    listEl.innerHTML = '<div style="color:#72f4fb;padding:20px;text-align:center;">Loading audit logs...</div>';
    if (emptyEl) emptyEl.hidden = true;
    const res = await post('weaponStorage:getLogs', { limit: 50 });
    listEl.innerHTML = '';
    const logs = Array.isArray(res?.logs) ? res.logs : [];
    if (!logs.length) {
      if (emptyEl) emptyEl.hidden = false;
      return;
    }
    if (emptyEl) emptyEl.hidden = true;
    for (const log of logs) {
      const row = document.createElement('div');
      row.className = 'gang-control__log-row';
      const isWithdraw = log.direction === 'withdraw';
      const badge = document.createElement('span');
      badge.className = `gang-control__log-badge gang-control__log-badge--${isWithdraw ? 'withdraw' : 'deposit'}`;
      badge.textContent = isWithdraw ? 'WITHDREW' : 'DEPOSITED';

      const actor = document.createElement('span');
      actor.className = 'gang-control__log-actor';
      actor.textContent = `[${log.characterName || 'Unknown'}]`;

      const desc = document.createElement('span');
      desc.className = 'gang-control__log-desc';
      const itemName = log.itemName || 'Item';
      const qty = Number(log.quantity) || 1;
      const serialInfo = log.details?.serialRemoved ? ' (Serial: Free)' : (log.details?.serial ? ` (Serial: ${log.details.serial})` : '');
      desc.innerHTML = `${isWithdraw ? 'withdrew' : 'deposited'} <strong>${qty}x ${itemName}</strong>${serialInfo}`;

      const time = document.createElement('span');
      time.className = 'gang-control__log-time';
      time.textContent = formatRelativeTime(log.createdAt);

      row.appendChild(badge);
      row.appendChild(actor);
      row.appendChild(desc);
      row.appendChild(time);
      listEl.appendChild(row);
    }
  };

  const openSettings = () => {
    if (!state.data || !state.data.isFamily || state.data.canManage !== true) return;
    const overlay = document.createElement('div');
    overlay.className = 'ws-checkout';
    const isOpen = state.data.settings?.open !== false;
    const ammoLimits = state.data.settings?.ammoLimits || {};
    overlay.innerHTML = `<section class="ws-checkout__card ws-settings" role="dialog" aria-modal="true" style="width:min(580px,94vw);">
      <small>ARMORY MANAGEMENT</small><h2>HOUSE ARMORY SETTINGS</h2>
      <p>Control whether members can take weapons and ammunition. Equipment can still be returned while closed.</p>
      <div class="ws-checkout__label"><span>ARMORY ACCESS</span><strong>${isOpen ? 'OPEN' : 'CLOSED'}</strong></div>
      <div class="ws-state-options"><button type="button" data-open="true" class="${isOpen ? 'is-active' : ''}"><i></i>OPEN</button><button type="button" data-open="false" class="${isOpen ? '' : 'is-active'}"><i></i>CLOSED</button></div>
      <div class="ws-settings-grid">
        <label>MAX GUNS / VESTS PER CHECKOUT<input id="ws-setting-weapons" type="number" min="1" max="10" value="${Number(state.data.settings?.weaponLimit || 10)}"></label>
        <label>CHECKOUT COOLDOWN (MINUTES)<input id="ws-setting-cooldown" type="number" min="0" max="60" value="${Number(state.data.settings?.cooldownMinutes || 0)}"></label>
      </div>
      <div class="ws-settings-subtitle">AMMO CHECKOUT QUOTAS BY TYPE</div>
      <div class="ws-settings-ammo-grid">
        <label>5.56 RIFLE ROUNDS<input id="ws-ammo-556" type="number" min="1" max="500" value="${ammoLimits.ammo_556nato || 100}"></label>
        <label>9x19 SMG ROUNDS<input id="ws-ammo-smg" type="number" min="1" max="500" value="${ammoLimits.ammo_9x19_smg || 60}"></label>
        <label>9mm PISTOL ROUNDS<input id="ws-ammo-9mm" type="number" min="1" max="500" value="${ammoLimits.ammo_9mm || 50}"></label>
        <label>12GA SHOTGUN SHELLS<input id="ws-ammo-shotgun" type="number" min="1" max="500" value="${ammoLimits.ammo_12gauge || 30}"></label>
        <label>.44 REVOLVER ROUNDS<input id="ws-ammo-revolver" type="number" min="1" max="500" value="${ammoLimits.ammo_44magnum || 24}"></label>
        <label>.308 SNIPER ROUNDS<input id="ws-ammo-sniper" type="number" min="1" max="500" value="${ammoLimits.ammo_308win || 20}"></label>
        <label>7.62 MG BELT ROUNDS<input id="ws-ammo-mg" type="number" min="1" max="500" value="${ammoLimits.ammo_762nato || 100}"></label>
      </div>
      <div class="ws-checkout__actions"><button type="button" data-cancel>CANCEL</button><button type="button" data-confirm>SAVE SETTINGS</button></div>
    </section>`;
    document.body.appendChild(overlay);
    let nextOpen = isOpen;
    overlay.querySelectorAll('[data-open]').forEach(button => button.onclick = () => {
      nextOpen = button.dataset.open === 'true';
      overlay.querySelectorAll('[data-open]').forEach(option => option.classList.toggle('is-active', option === button));
      overlay.querySelector('.ws-checkout__label strong').textContent = nextOpen ? 'OPEN' : 'CLOSED';
    });
    const close = () => overlay.remove();
    overlay.querySelector('[data-cancel]').onclick = close;
    overlay.querySelector('[data-confirm]').onclick = async () => {
      const button = overlay.querySelector('[data-confirm]');
      button.disabled = true;
      const response = await post('weaponStorage:saveSettings', {
        open: nextOpen,
        weaponLimit: Number(overlay.querySelector('#ws-setting-weapons').value),
        cooldownMinutes: Number(overlay.querySelector('#ws-setting-cooldown').value),
        ammoLimits: {
          ammo_556nato: Number(overlay.querySelector('#ws-ammo-556').value) || 100,
          ammo_9x19_smg: Number(overlay.querySelector('#ws-ammo-smg').value) || 60,
          ammo_9mm: Number(overlay.querySelector('#ws-ammo-9mm').value) || 50,
          ammo_12gauge: Number(overlay.querySelector('#ws-ammo-shotgun').value) || 30,
          ammo_44magnum: Number(overlay.querySelector('#ws-ammo-revolver').value) || 24,
          ammo_308win: Number(overlay.querySelector('#ws-ammo-sniper').value) || 20,
          ammo_762nato: Number(overlay.querySelector('#ws-ammo-mg').value) || 100,
        }
      });
      if (response?.ok) close(); else button.disabled = false;
    };
    overlay.onclick = event => { if (event.target === overlay) close(); };
  };

  const post = (name, body = {}) => fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body),
  }).then((r) => r.json()).catch(() => ({ ok: false }));

  const imageSource = (raw, item) => {
    let src = String(raw || '').trim();
    if (!src) {
      if (item && item.itemType === 'weapon' && item.weaponHash) {
        src = `https://docs-backend.fivem.net/weapons/${String(item.weaponHash).toUpperCase()}.png`;
      } else {
        src = 'img/weapons/ammo_default.svg';
      }
    }
    if (src.startsWith('nui://')) {
      const parts = src.slice(6).split('/');
      const resource = parts.shift();
      return `https://cfx-nui-${resource}/${parts.join('/')}`;
    }
    return src;
  };

  const matches = (item) => {
    if (state.filter !== 'all' && item.itemType !== state.filter) return false;
    const q = state.search.trim().toLowerCase();
    if (!q) return true;
    return [item.label, item.itemName, item.group, item.serial, item.description,
      item.ammoItem, item.sharedAmmo?.label, item.sharedAmmo?.itemName]
      .some((v) => String(v || '').toLowerCase().includes(q));
  };

  const clampAmount = (value, item) => {
    const max = Math.max(1, Number(item.quantity) || 1);
    return Math.max(1, Math.min(max, Math.floor(Number(value) || 1)));
  };

  const itemCard = (item, armorCard = false) => {
    const card = document.createElement('article');
    card.className = armorCard ? 'gang-control__armor' : 'gang-control__card';
    const stockQuantity = Math.max(0, Number(item.stockQuantity) || 0);
    const playerQuantity = Math.max(0, Number(item.playerQuantity) || 0);
    card.dataset.itemType = item.itemType || 'item';
    card.classList.toggle('is-empty', stockQuantity <= 0 && playerQuantity <= 0);

    const imageWrap = document.createElement('div');
    imageWrap.className = 'gang-control__image';
    const image = document.createElement('img');
    image.loading = 'lazy';
    image.alt = '';
    image.src = imageSource(item.image, item);
    image.onerror = () => {
      const fallback = imageSource(item.fallbackImage, item);
      if (fallback && image.dataset.fallbackTried !== '1') {
        image.dataset.fallbackTried = '1';
        image.src = fallback;
        return;
      }
      image.onerror = null;
      image.src = item.itemType === 'weapon'
        ? 'img/weapons/weapon_default.svg'
        : item.itemType === 'armor'
          ? 'img/weapons/armor_light.svg'
          : 'img/weapons/ammo_default.svg';
    };
    const caption = document.createElement('small');
    caption.className = 'gang-control__item-title';
    const bullet = document.createElement('i');
    bullet.className = 'gang-control__item-bullet';
    caption.append(bullet, document.createTextNode(item.label || item.itemName || 'Unknown item'));
    imageWrap.append(image, caption);

    const info = document.createElement('div');
    info.className = armorCard ? 'gang-control__armor-data' : 'gang-control__data';
    const stat = document.createElement('div');
    stat.className = 'gang-control__stat';
    const label = document.createElement('label');
    label.textContent = item.itemType === 'ammo' ? 'AMMO IN VAULT' : item.itemType === 'armor' ? 'IN STOCK' : 'WEAPON IN VAULT';
    const quantity = document.createElement('strong');
    quantity.textContent = `${stockQuantity} `;
    const unit = document.createElement('small');
    unit.textContent = item.itemType === 'ammo' ? 'ROUNDS' : 'PCS';
    quantity.appendChild(unit);
    stat.append(label, quantity);
    const meta = document.createElement('p');
    meta.textContent = item.itemType === 'armor'
      ? `Strength ${Number(item.armorValue || 0)}%`
      : `In inventory ${playerQuantity}`;
    info.append(stat, meta);

    if (item.itemType === 'weapon') {
      const ammo = item.sharedAmmo;
      const ammoStock = ammo ? Math.max(0, Number(ammo.stockQuantity) || 0) : 0;
      const ammoStat = document.createElement('div');
      ammoStat.className = 'gang-control__stat gang-control__ammo';
      const ammoLabel = document.createElement('label');
      ammoLabel.append(document.createTextNode('AMMO'));
      const ammoName = document.createElement('span');
      ammoName.textContent = ammo ? (ammo.label || ammo.itemName) : 'Not configured';
      ammoLabel.append(ammoName);
      const ammoQuantity = document.createElement('strong');
      ammoQuantity.textContent = `${ammoStock} `;
      const ammoUnit = document.createElement('small');
      ammoUnit.textContent = 'ROUNDS';
      ammoQuantity.append(ammoUnit);
      const meter = document.createElement('div');
      meter.className = 'gang-control__meter';
      const fill = document.createElement('i');
      fill.style.width = `${Math.min(100, ammoStock / 5)}%`;
      meter.append(fill);
      ammoStat.append(ammoLabel, ammoQuantity, meter);
      info.append(ammoStat);
    }

    const action = document.createElement('div');
    action.className = 'gang-control__actions';
    const addTransferButton = (direction, row, allowed, idleText, className) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = className;
      button.textContent = idleText;
      const itemAllowed = allowed && row && !(direction === 'deposit' && row.canStore === false);
      button.disabled = !itemAllowed;
      button.addEventListener('click', async () => {
        if (state.busy || !itemAllowed) return;
        const amount = await chooseAmount(row, direction);
        if (!amount) return;
        state.busy = true;
        button.disabled = true;
        button.textContent = 'WORKING...';
        const response = await post('weaponStorage:transfer', {
          direction,
          rowId: Number(row.id),
          amount: clampAmount(amount, row),
        });
        state.busy = false;
        if (!response || response.ok !== true) {
          button.disabled = !itemAllowed;
          button.textContent = idleText;
        }
      });
      action.append(button);
    };
    const isFamily = Boolean(state.data?.isFamily);
    const armoryOpen = (!isFamily) || state.data?.settings?.open !== false;
    const withdrawText = armoryOpen
      ? (item.itemType === 'ammo' ? 'TAKE AMMO' : item.itemType === 'armor' ? 'TAKE VEST' : 'TAKE GUN')
      : 'ARMORY CLOSED';
    addTransferButton('withdraw', item.storageRow, state.data?.canWithdraw === true && armoryOpen, withdrawText, 'gang-control__take');
    if (item.itemType === 'weapon') {
      const ammo = item.sharedAmmo;
      addTransferButton('withdraw', ammo?.storageRow, state.data?.canWithdraw === true && armoryOpen,
        ammo ? (armoryOpen ? 'TAKE AMMO' : 'ARMORY CLOSED') : 'NO AMMO', 'gang-control__ammo-button');
    }
    addTransferButton('deposit', item.playerRow, state.data?.canDeposit === true, 'PUT BACK', 'gang-control__return');
    info.append(action);
    card.append(imageWrap, info);
    return card;
  };

  const renderList = (id, emptyId, items, armorCard = false) => {
    const list = el(id);
    const empty = el(emptyId);
    const filtered = (Array.isArray(items) ? items : []).filter(item => armorCard || matches(item));
    while (list.firstChild) list.removeChild(list.firstChild);
    filtered.forEach((item) => list.appendChild(itemCard(item, armorCard)));
    empty.hidden = filtered.length !== 0;
    return filtered.length;
  };

  const modelRows = () => {
    const data = state.data || {};
    const catalog = Array.isArray(data.catalog) ? data.catalog : [];
    const stored = Array.isArray(data.storage) ? data.storage : [];
    const player = Array.isArray(data.player) ? data.player : [];
    const definitions = new Map(catalog.map(item => [String(item.itemName || '').toLowerCase(), item]));
    [...stored, ...player].forEach(item => {
      const key = String(item.itemName || '').toLowerCase();
      if (key && !definitions.has(key)) definitions.set(key, item);
    });
    const rows = [...definitions.values()].map(def => {
      const key = String(def.itemName || '').toLowerCase();
      const storageRows = stored.filter(row => String(row.itemName || '').toLowerCase() === key);
      const playerRows = player.filter(row => String(row.itemName || '').toLowerCase() === key);
      return {
        ...def,
        stockQuantity: storageRows.reduce((sum, row) => sum + Math.max(1, Number(row.quantity) || 1), 0),
        playerQuantity: playerRows.reduce((sum, row) => sum + Math.max(1, Number(row.quantity) || 1), 0),
        storageRow: storageRows[0] || null,
        playerRow: playerRows.find(row => row.canStore !== false) || playerRows[0] || null,
      };
    });
    const byName = new Map(rows.map(item => [String(item.itemName || '').toLowerCase(), item]));
    rows.forEach(item => {
      if (item.itemType !== 'weapon') return;
      const group = String(item.group || '').toLowerCase();
      const ammoKey = String(item.ammoItem || (group.startsWith('ammo_') ? group : '')).toLowerCase();
      item.sharedAmmo = ammoKey ? (byName.get(ammoKey) || null) : null;
    });
    return rows;
  };

  const render = () => {
    const data = state.data || {};
    const isFamily = Boolean(data.isFamily);
    el('ws-subtitle').textContent = data.subtitle || 'Property';
    const models = modelRows();
    const armorModels = models.filter(item => item.itemType === 'armor');
    const playerCount = renderList('ws-player-list', 'ws-player-empty', armorModels, true);
    const armoryOpen = (!isFamily) || data.settings?.open !== false;
    const mainModels = state.filter === 'armor' ? armorModels : models.filter(item => item.itemType !== 'armor');
    const storageCount = renderList('ws-storage-list', 'ws-storage-empty', mainModels);
    el('ws-result-count').textContent = `${storageCount} shown`;
    el('ws-player-count').textContent = `${playerCount} MODELS`;
    el('ws-storage-count').textContent = String(models.length);
    el('ws-count-weapon').textContent = String(models.filter(item => item.itemType === 'weapon').length);
    el('ws-count-ammo').textContent = String(models.filter(item => item.itemType === 'ammo').length);
    el('ws-count-armor').textContent = String(armorModels.length);
    const used = Array.isArray(data.storage) ? data.storage.length : 0;
    el('ws-capacity').textContent = `${used} / ${Number(data.capacity) || 60} storage slots`;
    const status = el('armory-operating-state');
    if (status) {
      if (!isFamily) {
        status.hidden = true;
        status.style.display = 'none';
      } else {
        status.hidden = false;
        status.style.display = '';
        status.textContent = armoryOpen ? '● ARMORY OPEN' : '● ARMORY CLOSED';
        status.className = armoryOpen ? 'is-open' : 'is-closed';
      }
    }
    const isLogs = state.filter === 'logs';
    const storageList = el('ws-storage-list');
    const storageEmpty = el('ws-storage-empty');
    const logsPanel = el('ws-logs-panel');
    const toolbar = el('ws-toolbar');

    if (logsPanel) logsPanel.hidden = !isLogs;
    if (storageList) storageList.hidden = isLogs;
    if (storageEmpty) storageEmpty.hidden = isLogs ? true : storageEmpty.hidden;
    if (toolbar) toolbar.hidden = isLogs;

    if (el('ws-tab-logs')) el('ws-tab-logs').hidden = (!isFamily) || data.canManage !== true;
    if (el('ws-settings')) el('ws-settings').hidden = (!isFamily) || data.canManage !== true;
    if (el('ws-order-stock')) el('ws-order-stock').hidden = (!isFamily) || data.canManage !== true;

    if (isLogs) {
      loadLogs();
      return;
    }
  };

  const open = (data) => {
    state.data = data || {};
    state.busy = false;
    state.search = '';
    state.filter = 'weapon';
    el('ws-search').value = '';
    root.querySelectorAll('[data-ws-filter]').forEach((b) => b.classList.toggle('active', b.dataset.wsFilter === 'weapon'));
    root.classList.add('is-open');
    document.body.classList.add('armory-mode');
    root.setAttribute('aria-hidden', 'false');
    render();
  };

  const closeVisual = () => {
    document.querySelector('.ws-checkout')?.remove();
    root.classList.remove('is-open');
    document.body.classList.remove('armory-mode');
    root.setAttribute('aria-hidden', 'true');
    state.data = null;
    state.busy = false;
  };

  root.querySelectorAll('[data-ws-close]').forEach((button) => {
    button.addEventListener('click', () => post('weaponStorage:close'));
  });
  root.querySelectorAll('[data-ws-filter]').forEach((button) => {
    button.addEventListener('click', () => {
      state.filter = button.dataset.wsFilter || 'all';
      root.querySelectorAll('[data-ws-filter]').forEach((b) => b.classList.toggle('active', b === button));
      render();
    });
  });
  el('ws-search').addEventListener('input', (event) => {
    state.search = event.target.value || '';
    render();
  });
  root.querySelector('[data-ws-refresh]').addEventListener('click', async () => {
    if (state.busy) return;
    state.busy = true;
    await post('weaponStorage:refresh');
    state.busy = false;
  });
  if (el('ws-logs-refresh')) el('ws-logs-refresh').addEventListener('click', loadLogs);
  el('ws-settings').addEventListener('click', openSettings);
  el('ws-order-stock').addEventListener('click', () => post('weaponStorage:orderStock'));

  window.addEventListener('message', (event) => {
    const message = event.data || {};
    if (message.action === 'weaponStorage:open') open(message.data);
    if (message.action === 'weaponStorage:update') {
      state.data = message.data || {};
      state.busy = false;
      render();
    }
    if (message.action === 'weaponStorage:close') closeVisual();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && root.classList.contains('is-open')) {
      event.preventDefault();
      post('weaponStorage:close');
    }
  });
})();
