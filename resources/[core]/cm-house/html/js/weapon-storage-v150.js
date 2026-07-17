/* cm-house v1.5.0 — secure weapon storage UI */
(() => {
  const root = document.getElementById('weapon-storage');
  if (!root) return;

  const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  const el = (id) => document.getElementById(id);
  const state = { data: null, filter: 'all', search: '', busy: false };

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
    return [item.label, item.itemName, item.group, item.serial, item.description]
      .some((v) => String(v || '').toLowerCase().includes(q));
  };

  const clampAmount = (value, item) => {
    const max = Math.max(1, Number(item.quantity) || 1);
    if (item.itemType === 'weapon') return 1;
    return Math.max(1, Math.min(max, Math.floor(Number(value) || 1)));
  };

  const itemCard = (item, direction, allowed) => {
    const card = document.createElement('article');
    card.className = 'ws-item';

    const imageWrap = document.createElement('div');
    imageWrap.className = 'ws-item__image';
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
        : 'img/weapons/ammo_default.svg';
    };
    imageWrap.appendChild(image);

    const info = document.createElement('div');
    info.className = 'ws-item__info';
    const type = document.createElement('span');
    type.className = 'ws-item__type';
    type.textContent = `${item.itemType === 'ammo' ? 'Ammunition' : 'Weapon'} · ${item.group || 'General'}`;
    const name = document.createElement('strong');
    name.className = 'ws-item__name';
    name.textContent = item.label || item.itemName || 'Unknown item';
    const meta = document.createElement('span');
    meta.className = 'ws-item__meta';
    const pieces = [`Qty ${Math.max(1, Number(item.quantity) || 1)}`];
    if (item.itemType === 'weapon' && item.durability !== null && item.durability !== undefined) pieces.push(`Durability ${Math.round(Number(item.durability) || 0)}%`);
    if (item.serial) pieces.push(`Serial ${item.serial}`);
    if (direction === 'deposit' && item.itemType === 'weapon' && item.canStore === false) pieces.push('Requires 100% durability');
    meta.textContent = pieces.join(' · ');
    info.append(type, name, meta);

    const action = document.createElement('div');
    action.className = 'ws-item__action';
    const qty = document.createElement('input');
    qty.className = 'ws-item__qty';
    qty.type = 'number';
    qty.min = '1';
    qty.max = String(Math.max(1, Number(item.quantity) || 1));
    qty.value = '1';
    qty.disabled = item.itemType === 'weapon' || !allowed;
    qty.setAttribute('aria-label', 'Quantity');

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'ws-item__button';
    button.dataset.direction = direction;
    button.textContent = direction === 'deposit' ? 'Store' : 'Take';
    const itemAllowed = allowed && !(direction === 'deposit' && item.itemType === 'weapon' && item.canStore === false);
    button.disabled = !itemAllowed;
    button.addEventListener('click', async () => {
      if (state.busy || !itemAllowed) return;
      state.busy = true;
      button.disabled = true;
      button.textContent = 'Working…';
      const response = await post('weaponStorage:transfer', {
        direction,
        rowId: Number(item.id),
        amount: clampAmount(qty.value, item),
      });
      state.busy = false;
      if (!response || response.ok !== true) {
        button.disabled = !itemAllowed;
        button.textContent = direction === 'deposit' ? 'Store' : 'Take';
      }
    });

    action.append(qty, button);
    card.append(imageWrap, info, action);
    return card;
  };

  const renderList = (id, emptyId, items, direction, allowed) => {
    const list = el(id);
    const empty = el(emptyId);
    const filtered = (Array.isArray(items) ? items : []).filter(matches);
    while (list.firstChild) list.removeChild(list.firstChild);
    filtered.forEach((item) => list.appendChild(itemCard(item, direction, allowed)));
    empty.hidden = filtered.length !== 0;
    return filtered.length;
  };

  const render = () => {
    const data = state.data || {};
    el('ws-title').textContent = data.title || 'Weapon Storage';
    el('ws-subtitle').textContent = data.subtitle || 'Property';
    const playerCount = renderList('ws-player-list', 'ws-player-empty', data.player, 'deposit', data.canDeposit === true);
    const storageCount = renderList('ws-storage-list', 'ws-storage-empty', data.storage, 'withdraw', data.canWithdraw === true);
    el('ws-player-count').textContent = String(playerCount);
    el('ws-storage-count').textContent = String(storageCount);
    const used = Array.isArray(data.storage) ? data.storage.length : 0;
    el('ws-capacity').textContent = `${used} / ${Number(data.capacity) || 60} storage slots`;
  };

  const open = (data) => {
    state.data = data || {};
    state.busy = false;
    state.search = '';
    state.filter = 'all';
    el('ws-search').value = '';
    root.querySelectorAll('[data-ws-filter]').forEach((b) => b.classList.toggle('is-active', b.dataset.wsFilter === 'all'));
    root.classList.add('is-open');
    root.setAttribute('aria-hidden', 'false');
    render();
  };

  const closeVisual = () => {
    root.classList.remove('is-open');
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
      root.querySelectorAll('[data-ws-filter]').forEach((b) => b.classList.toggle('is-active', b === button));
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
