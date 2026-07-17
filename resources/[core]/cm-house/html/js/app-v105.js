/* ============================================================
   cm-house | NUI logic
   The menu renders what the server sent. It never decides who may
   do what -- `can` comes down resolved, and every click round-trips.
   ============================================================ */

const $ = (id) => document.getElementById(id);

// Keep the NUI compatible with older FiveM CEF builds.
const replaceChildrenSafe = (element, nodes) => {
  while (element.firstChild) element.removeChild(element.firstChild);
  nodes.forEach((node) => element.appendChild(node));
};

window.CM_HOUSE_UI_VERSION = '1.7.0';
document.documentElement.setAttribute('data-cm-house-ui', window.CM_HOUSE_UI_VERSION);
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';

const post = (name, body = {}) =>
  fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(body),
  }).then((r) => r.json()).catch(() => ({}));

const money = (n) =>
  n === null || n === undefined ? '—' : '$' + Number(n).toLocaleString('en-US');

const SEAL_CIRC = 327; // 2 * pi * 52

/* ------------------------------------------------------------
   WIZARD
   Features drive everything. Every toggle asks the SERVER to re-derive the
   price, the stars and the garage size -- the UI never computes money.
   ------------------------------------------------------------ */
let W = {
  opts: null,
  f: { houseType: null, hasGarden: false, hasPool: false, hasHelipad: false, garageTemplateId: null, garageCapacity: 0 },
  plan: null,
  phase: 'features',
  ctx: null,
};

const SEAL_C = 327;

function paneShow(id) {
  ['w-features', 'w-pick', 'w-rooms', 'w-name', 'w-publish']
    .forEach((p) => { $(p).hidden = p !== id; });
}

function bump(el, val) {
  if (el.textContent === val) return;
  el.textContent = val;
  el.classList.remove('bump');
  void el.offsetWidth;      // restart the animation
  el.classList.add('bump');
}

function paintRail(d) {
  if (!d) return;
  bump($('w-price'), money(d.price));
  bump($('w-gov'),   money(d.govValue));
  bump($('w-ins'),   money(d.insurance));
  bump($('w-daily'), money(d.dailyCost));
  bump($('w-cap'),   d.garageCapacity ? `${d.garageCapacity} cars` : 'None');

  const seal = $('w-seal');
  seal.dataset.stars = String(d.stars);
  $('w-stars').textContent = '★'.repeat(d.stars) + '☆'.repeat(5 - d.stars);

  const fill = seal.querySelector('.seal__fill');
  requestAnimationFrame(() => {
    fill.style.strokeDashoffset = String(SEAL_C * (1 - d.stars / 5));
  });
}

async function replan() {
  if (!W.f.houseType) return;
  const plan = await post('wizard:replan', W.f);
  if (!plan || !plan.derived) return;
  W.plan = plan;
  paintRail(plan.derived);
  paintGarages();
}

/* ---- features ---- */
function openWizard(opts) {
  W.opts = opts;
  W.f = { houseType: (opts.types[0] && opts.types[0].key) || null, hasGarden: false, hasPool: false, hasHelipad: false, garageTemplateId: null, garageCapacity: 0 };
  W.phase = 'features';

  $('w-step').textContent  = 'Step 1 — What is this property?';
  $('w-title').textContent = 'Declare the property';
  $('w-sub').textContent   = 'Everything else — the layout, the garage, the price — follows from this.';
  $('w-next').textContent  = 'Continue';
  $('w-err').textContent   = '';

  replaceChildrenSafe($('w-types'), opts.types.map((t) => {
    const b = document.createElement('button');
    b.className = 'tile' + (t.key === W.f.houseType ? ' on' : '');
    b.dataset.type = t.key;
    b.innerHTML = `<span class="tile__name"></span><span class="tile__cost"></span>`;
    b.querySelector('.tile__name').textContent = t.label;
    b.querySelector('.tile__cost').textContent = money(t.priceAdd);
    return b;
  }));

  replaceChildrenSafe($('w-feats'), opts.features.map((f) => {
    const b = document.createElement('button');
    b.className = 'tog';
    b.dataset.feat = f.key;
    b.innerHTML = `<span class="tog__dot"></span><span></span><span class="tog__cost"></span>`;
    b.querySelectorAll('span')[1].textContent = f.label;
    b.querySelector('.tog__cost').textContent = '+' + money(f.priceAdd);
    return b;
  }));

  paneShow('w-features');
  $('wiz').classList.add('on');
  replan();
}

function paintGarages() {
  const selectedId = Number(W.f.garageTemplateId || 0);
  const templates = Array.isArray(W.opts && W.opts.garages) ? W.opts.garages : [];
  const rows = [];

  const none = document.createElement('button');
  none.className = 'tile tile--sm' + (!selectedId ? ' on' : '');
  none.dataset.garage = 'none';
  none.innerHTML = '<span class="tile__name">No garage</span><span class="tile__cost">$0</span>';
  rows.push(none);

  templates.forEach((g) => {
    const b = document.createElement('button');
    b.className = 'tile tile--sm' + (Number(g.id) === selectedId ? ' on' : '');
    b.dataset.garage = String(g.id);
    b.dataset.capacity = String(g.capacity || 0);
    b.innerHTML = `<span class="tile__name"></span><span class="tile__cost"></span>`;
    b.querySelector('.tile__name').textContent = `${g.label} · ${g.capacity} cars`;
    b.querySelector('.tile__cost').textContent = '+' + money(g.priceAdd || 0);
    rows.push(b);
  });

  replaceChildrenSafe($('w-garages'), rows);
  $('w-garage-note').textContent = templates.length
    ? 'Garage capacity comes from the number of placement cars saved in the selected cm-admin template.'
    : 'No garage templates exist. Create one from cm-admin first.';
}

$('w-types').addEventListener('click', (e) => {
  const b = e.target.closest('[data-type]');
  if (!b) return;
  W.f.houseType = b.dataset.type;
  [...$('w-types').children].forEach((c) => c.classList.toggle('on', c === b));

  // Apartments never get a helipad.
  const heli = $('w-feats').querySelector('[data-feat="helipad"]');
  if (heli) {
    const apt = W.f.houseType === 'apartment';
    heli.disabled = apt;
    if (apt && W.f.hasHelipad) {
      W.f.hasHelipad = false;
      heli.classList.remove('on');
    }
  }
  replan();
});

$('w-feats').addEventListener('click', (e) => {
  const b = e.target.closest('[data-feat]');
  if (!b || b.disabled) return;
  const k = { garden: 'hasGarden', pool: 'hasPool', helipad: 'hasHelipad' }[b.dataset.feat];
  W.f[k] = !W.f[k];
  b.classList.toggle('on', W.f[k]);
  replan();
});

$('w-garages').addEventListener('click', (e) => {
  const b = e.target.closest('[data-garage]');
  if (!b || b.disabled) return;
  if (b.dataset.garage === 'none') {
    W.f.garageTemplateId = null;
    W.f.garageCapacity = 0;
  } else {
    W.f.garageTemplateId = Number(b.dataset.garage);
    W.f.garageCapacity = Number(b.dataset.capacity) || 0;
  }
  replan();
});

/* ---- pick a saved layout ---- */
function wizPick(data, kind) {
  W.phase = kind === 'interior' ? 'pickInterior' : 'pickGarage';
  W.ctx = data;

  $('w-step').textContent  = kind === 'interior' ? 'Interior' : 'Garage';
  $('w-title').textContent = kind === 'interior' ? 'Which layout?' : 'Which garage?';
  $('w-sub').textContent   = 'Choose an existing reusable template created from cm-admin.';
  $('w-pick-note').textContent = '';

  const cards = data.templates.map((t) => {
    const b = document.createElement('button');
    b.className = 'card';
    b.dataset.tpl = String(t.id);
    const meta = kind === 'interior'
      ? `${t.weaponStorages ?? t.wardrobes ?? 0} weapon lockers · ${t.stashes} storage`
      : `${t.capacity} cars`;
    b.innerHTML = `<div class="card__body"><span class="card__name"></span><span class="card__meta"></span></div><span class="card__go">›</span>`;
    b.querySelector('.card__name').textContent = t.label;
    b.querySelector('.card__meta').textContent = meta;
    return b;
  });


  replaceChildrenSafe($('w-pick-list'), cards);
  paneShow('w-pick');
  $('w-next').textContent = 'Continue';
  $('wiz').classList.add('on');
}

$('w-pick-list').addEventListener('click', (e) => {
  const b = e.target.closest('[data-tpl]');
  if (!b) return;
  const id = b.dataset.tpl;
  $('wiz').classList.remove('on');
  post(W.phase === 'pickInterior' ? 'wizard:pickInterior' : 'wizard:pickGarage',
       { templateId: id });
});

/* ---- pick a room ---- */
function wizRooms(data) {
  W.phase = data.forGarage ? 'garageRoom' : 'room';

  $('w-step').textContent  = data.forGarage ? 'Garage' : 'Interior';
  $('w-title').textContent = data.forGarage ? 'Which garage?' : 'Which room?';
  $('w-sub').textContent   = 'Templates are created from the cm-admin layout tools.';

  replaceChildrenSafe($('w-room-list'), data.rooms.map((r) => {
    const b = document.createElement('button');
    b.className = 'card';
    b.dataset.room = r.key;
    b.innerHTML = `<div class="card__body"><span class="card__name"></span><span class="card__meta"></span></div><span class="card__go">›</span>`;
    b.querySelector('.card__name').textContent = r.label;
    b.querySelector('.card__meta').textContent = r.ipl ? `IPL · ${r.ipl}` : 'World interior';
    return b;
  }));

  paneShow('w-rooms');
  $('wiz').classList.add('on');
}

$('w-room-list').addEventListener('click', (e) => {
  const b = e.target.closest('[data-room]');
  if (!b) return;
  $('wiz').classList.remove('on');
  post(W.phase === 'garageRoom' ? 'wizard:garageRoom' : 'wizard:room', { key: b.dataset.room });
});

/* ---- name a layout ---- */
function wizName(data) {
  W.phase = data.kind === 'interior' ? 'nameInterior' : 'nameGarage';
  W.ctx = data;

  $('w-step').textContent  = 'Save the layout';
  $('w-title').textContent = data.kind === 'interior' ? 'Name this interior' : 'Name this garage';
  $('w-sub').textContent   = 'Create and edit reusable templates from cm-admin.';

  $('w-name-note').textContent = data.kind === 'interior'
    ? `${data.weaponStorages ?? data.wardrobes ?? 0} weapon locker${(data.weaponStorages ?? data.wardrobes ?? 0) === 1 ? '' : 's'}, ${data.stashes} storage point${data.stashes === 1 ? '' : 's'} placed.`
    : `${data.capacity} car space${data.capacity === 1 ? '' : 's'} placed.`;

  $('w-name-in').value = data.suggested || '';
  paneShow('w-name');
  $('w-next').textContent = 'Save layout';
  $('wiz').classList.add('on');
  $('w-name-in').focus();
}

/* ---- publish ---- */

// Check the address as it is typed. Finding out it is taken AFTER parking
// seven cars would be a cruel way to learn it.
let addrTimer = null;
$('w-number').addEventListener('input', () => {
  clearTimeout(addrTimer);
  addrTimer = setTimeout(async () => {
    const num = $('w-number').value.trim();
    if (!num) { $('w-err').textContent = ''; return; }
    const r = await post('wizard:checkAddress', { number: num });
    $('w-err').textContent = (r && r.ok === false) ? (r.message || '') : '';
  }, 400);
});

function wizPublish(data) {
  W.phase = 'publish';
  paintRail(data.derived);

  $('w-step').textContent  = 'Final step';
  $('w-title').textContent = 'Publish the property';
  $('w-sub').textContent   = 'Give it an address and it goes on the market.';
  $('w-next').textContent  = 'Publish';

  paneShow('w-publish');
  $('wiz').classList.add('on');
  $('w-number').focus();
}

/* ---- the one Continue button ---- */
$('wiz').addEventListener('click', async (e) => {
  const btn = e.target.closest('[data-act]');
  if (!btn) return;

  if (btn.dataset.act === 'w-cancel') {
    $('wiz').classList.remove('on');
    return post('wizard:cancel');
  }

  if (btn.dataset.act === 'w-custom') {
    const x = Number($('w-cx').value), y = Number($('w-cy').value), z = Number($('w-cz').value);
    if (!x || !y || !z) {
      $('w-err').textContent = 'Give all three coordinates.';
      return;
    }
    $('wiz').classList.remove('on');
    post(W.phase === 'garageRoom' ? 'wizard:garageRoom' : 'wizard:room',
         { key: 'custom', x, y, z });
    return;
  }

  if (btn.dataset.act !== 'w-next') return;

  if (W.phase === 'features') {
    if (!W.f.houseType) {
      $('w-err').textContent = 'Pick a property type.';
      return;
    }
    if (W.plan && Array.isArray(W.plan.interiors) && W.plan.interiors.length === 0) {
      $('w-err').textContent = 'Create an interior template from cm-admin before making this house.';
      return;
    }
    if (W.plan && W.plan.derived && W.plan.derived.garageTemplateMeetsMinimum === false) {
      $('w-err').textContent = `Select a garage template with at least ${Number(W.plan.derived.garageMinimum) || 0} car spaces.`;
      return;
    }
    $('wiz').classList.remove('on');
    return post('wizard:features', W.f);
  }

  if (W.phase === 'nameInterior' || W.phase === 'nameGarage') {
    const label = $('w-name-in').value.trim();
    if (!label) {
      $('w-err').textContent = 'Give the layout a name.';
      return;
    }
    btn.disabled = true;
    const r = await post(W.phase === 'nameInterior' ? 'wizard:nameInterior' : 'wizard:nameGarage',
                         { label });
    btn.disabled = false;
    if (r.ok) $('wiz').classList.remove('on');
    else $('w-err').textContent = r.message || 'The server refused it.';
    return;
  }

  if (W.phase === 'publish') {
    const num = $('w-number').value.trim();
    if (!num) {
      $('w-err').textContent = 'Give the property an address.';
      return;
    }
    btn.disabled = true;
    btn.textContent = 'Publishing…';
    const r = await post('wizard:publish', {
      houseNumber: num,
      label: $('w-label').value.trim(),
    });
    btn.disabled = false;
    btn.textContent = 'Publish';
    if (r.ok) $('wiz').classList.remove('on');
    else $('w-err').textContent = r.message || 'The server refused it.';
  }
});

/* ------------------------------------------------------------
   ADMIN
   ------------------------------------------------------------ */
let A = { data: null, tab: 'houses', sel: null };
const ADMIN_TAB_CAPABILITY = { houses: 'properties', interiors: 'interiors', garages: 'garages', recovery: 'recovery' };
const adminCan = (key) => Boolean(A.data && A.data.capabilities && A.data.capabilities[key] === true);
const firstAdminTab = (preferred) => {
  const choices = [preferred, 'houses', 'interiors', 'garages', 'recovery'];
  return choices.find((tab) => ADMIN_TAB_CAPABILITY[tab] && adminCan(ADMIN_TAB_CAPABILITY[tab])) || 'houses';
};

function openAdmin(data) {
  A.data = data || {};
  const requested = ['houses', 'interiors', 'garages', 'recovery'].includes(A.data.openTab) ? A.data.openTab : 'houses';
  A.tab = adminCan(ADMIN_TAB_CAPABILITY[requested]) ? requested : firstAdminTab(requested);
  A.sel = null;
  $('a-search').value = '';
  renderAdmin();
  $('admin').classList.add('on');
}

function renderAdmin() {
  const q = $('a-search').value.trim().toLowerCase();
  const list = $('a-list');

  document.querySelectorAll('.tab').forEach((t) => {
    const capability = ADMIN_TAB_CAPABILITY[t.dataset.tab];
    t.hidden = !capability || !adminCan(capability);
    t.classList.toggle('tab--on', t.dataset.tab === A.tab);
  });

  let rows = [];

  if (A.tab === 'houses') {
    const items = A.data.houses.filter((h) =>
      !q || h.number.toLowerCase().includes(q) || (h.label || '').toLowerCase().includes(q)
         || (h.owner || '').toLowerCase().includes(q));

    $('a-count').textContent = `${items.length} of ${A.data.houses.length}`;

    rows = items.map((h) => {
      const r = document.createElement('div');
      r.className = 'row' + (A.sel === h.id ? ' on' : '');
      r.dataset.house = String(h.id);

      const feats = [h.garden && 'garden', h.pool && 'pool', h.helipad && 'helipad']
        .filter(Boolean).join(' · ');
      const owner = h.owner
        ? `<span class="owned">${h.owner}</span>`
        : `<span class="sale">For sale</span>`;

      // A real photo shows as a thumbnail; without one, the address plate.
      const plate = h.image
        ? `<div class="row__thumb"><img src="${h.image}" alt=""><span>${h.number}</span></div>`
        : `<div class="row__plate">${h.number}</div>`;

      r.innerHTML = `
        ${plate}
        <div>
          <div class="row__name"></div>
          <div class="row__meta">${owner} · ${money(h.price)} · ${h.interior}${h.capacity ? ' · ' + h.capacity + ' cars' : ''}${feats ? ' · ' + feats : ''}</div>
        </div>
        <div>
          <div class="row__stars">${'★'.repeat(h.stars)}${'☆'.repeat(5 - h.stars)}</div>
          <div class="row__acts">
            ${adminCan('properties') ? '<button class="mini" data-h="goto">Go</button>' : ''}
            ${adminCan('photos') ? '<button class="mini" data-h="retake">Photo</button>' : ''}
            ${h.owner && adminCan('properties') ? '<button class="mini mini--bad" data-h="evict">Evict</button>' : ''}
            ${adminCan('pricing') ? '<button class="mini" data-h="setPrice">Price</button>' : ''}
            ${!h.owner && adminCan('properties') ? '<button class="mini mini--bad" data-h="delete">Delete</button>' : ''}
          </div>
        </div>`;
      r.querySelector('.row__name').textContent = h.label || 'Property';
      return r;
    });

  } else if (A.tab === 'interiors') {
    const items = A.data.interiors.filter((t) => !q || t.label.toLowerCase().includes(q));
    $('a-count').textContent = `${items.length} layouts`;

    rows = items.map((t) => {
      const r = document.createElement('div');
      r.className = 'row' + (t.enabled ? '' : ' row--off');
      r.dataset.tpl = String(t.id);
      r.dataset.kind = 'interior';

      // A layout in use cannot be deleted -- doing so would strand whoever is
      // standing inside it. Say how many, so the block is explicable.
      const acts = ['<button class="mini" data-t="preview">Preview</button>',
                    '<button class="mini" data-t="rewalk">Re-walk</button>',
                    '<button class="mini" data-t="rename">Rename</button>'];
      if (!t.enabled) acts.push('<button class="mini" data-t="enable">Enable</button>');
      else if (t.usedBy === 0) acts.push('<button class="mini" data-t="disable">Disable</button>');
      if (t.usedBy === 0) acts.push('<button class="mini mini--bad" data-t="delete">Delete</button>');

      r.innerHTML = `
        <div class="row__plate">${t.weaponStorages ?? t.wardrobes ?? 0}L</div>
        <div>
          <div class="row__name"></div>
          <div class="row__meta">${t.signature || 'any'} · ${t.stashes} storage · used by ${t.usedBy}</div>
        </div>
        <div class="row__acts">${acts.join('')}</div>`;
      r.querySelector('.row__name').textContent = t.label;
      if (!t.enabled) {
        const tag = document.createElement('span');
        tag.className = 'tagx';
        tag.textContent = 'OFF';
        r.querySelector('.row__name').appendChild(tag);
      }
      return r;
    });

  } else if (A.tab === 'garages') {
    const items = A.data.garages.filter((t) => !q || t.label.toLowerCase().includes(q));
    $('a-count').textContent = `${items.length} garages`;

    rows = items.map((t) => {
      const r = document.createElement('div');
      r.className = 'row' + (t.enabled ? '' : ' row--off');
      r.dataset.tpl = String(t.id);
      r.dataset.kind = 'garage';
      const acts = ['<button class="mini" data-t="preview">Preview</button>',
                    '<button class="mini" data-t="rewalk">Re-walk</button>',
                    '<button class="mini" data-t="rename">Rename</button>'];
      if (!t.enabled) acts.push('<button class="mini" data-t="enable">Enable</button>');
      else if (t.usedBy === 0) acts.push('<button class="mini" data-t="disable">Disable</button>');
      if (t.usedBy === 0) acts.push('<button class="mini mini--bad" data-t="delete">Delete</button>');

      r.innerHTML = `
        <div class="row__plate">${t.capacity}</div>
        <div>
          <div class="row__name"></div>
          <div class="row__meta">${t.capacity} car spaces · ${t.exits || 0} exits · ${t.hasCustomization ? 'settings ready' : 'no settings point'} · ${t.wallAnchors || 0} wall / ${t.lightAnchors || 0} light / ${t.decorAnchors || 0} decor points · used by ${t.usedBy}</div>
        </div>
        <div class="row__acts">${acts.join('')}</div>`;
      r.querySelector('.row__name').textContent = t.label;
      if (!t.enabled) {
        const tag = document.createElement('span');
        tag.className = 'tagx';
        tag.textContent = 'OFF';
        r.querySelector('.row__name').appendChild(tag);
      }
      return r;
    });
  } else {
    const source = Array.isArray(A.data.recovery) ? A.data.recovery : [];
    const items = source.filter((v) => {
      const haystack = [v.id, v.plate, v.label, v.ownerCid, v.locationState,
        v.locationRef, v.assignedHouseId, v.assignedSlot].join(' ').toLowerCase();
      return !q || haystack.includes(q);
    });
    $('a-count').textContent = `${items.length} issue${items.length === 1 ? '' : 's'}`;
    rows = items.map((v) => {
      const r = document.createElement('div');
      r.className = 'row recovery-row';
      r.dataset.vehicleRecovery = String(v.id);
      const assignment = v.assignedHouseId
        ? `House ${v.assignedHouseId} · slot ${v.assignedSlot || '?'}`
        : 'No house assignment';
      const duplicate = Number(v.duplicateCount || 0) > 0 ? ` · ${v.duplicateCount} duplicate${v.duplicateCount === 1 ? '' : 's'}` : '';
      const location = `${v.locationState || 'UNKNOWN'}${v.locationRef ? ' · ' + v.locationRef : ''}${v.locationSlot ? ' · slot ' + v.locationSlot : ''}${duplicate}`;
      r.innerHTML = `
        <div class="row__plate">${String(v.id || '?')}</div>
        <div>
          <div class="row__name"></div>
          <div class="row__meta">${v.plate || 'NO PLATE'} · ${location} · ${assignment}</div>
        </div>
        <div class="row__acts recovery-actions">
          <button class="mini" data-vr="reconcile">Reconcile</button>
          <button class="mini" data-vr="duplicates">Duplicates</button>
          ${v.assignedHouseId ? '<button class="mini" data-vr="recall">Recall</button>' : ''}
          <button class="mini" data-vr="public">Public</button>
          <button class="mini mini--bad" data-vr="impound">Impound</button>
          ${v.assignedHouseId ? '<button class="mini mini--bad" data-vr="clear_assignment">Clear slot</button>' : ''}
          <button class="mini mini--bad" data-vr="delete_entity">Delete entity</button>
        </div>`;
      r.querySelector('.row__name').textContent = `${v.label || 'Vehicle'} · Owner ${v.ownerCid || 'unknown'}`;
      return r;
    });
  }

  $('a-add').style.display = A.tab === 'houses' && adminCan('create') ? '' : 'none';

  if (rows.length === 0) {
    const e = document.createElement('div');
    e.className = 'empty';
    e.textContent = q ? 'Nothing matches that.' : 'Nothing here yet.';
    rows = [e];
  }

  // Standalone template creation: stand anywhere in-game and walk the points.
  if ((A.tab === 'interiors' && adminCan('interiors')) || (A.tab === 'garages' && adminCan('garages'))) {
    const kind = A.tab === 'interiors' ? 'interior' : 'garage';
    const mk = document.createElement('div');
    mk.className = 'row';
    mk.dataset.newtpl = kind;
    mk.style.cursor = 'pointer';
    mk.innerHTML = `
      <div class="row__plate">+</div>
      <div>
        <div class="row__name">Create a new ${kind === 'garage' ? 'garage' : 'interior'} layout</div>
        <div class="row__meta">${kind === 'garage' ? 'Enter the garage GPS location, teleport there, then set every point.' : 'Enter the interior GPS location, teleport there, then set every point.'}</div>
      </div>`;
    rows.unshift(mk);
  }

  replaceChildrenSafe(list, rows);
}

$('a-search').addEventListener('input', renderAdmin);

$('admin').addEventListener('click', async (e) => {
  if (e.target.closest('[data-act="a-close"]')) {
    $('admin').classList.remove('on');
    return post('admin:close');
  }

  if (e.target.closest('[data-act="a-add"]')) {
    if (!adminCan('create')) return;
    $('admin').classList.remove('on');
    return post('admin:add');
  }

  const tab = e.target.closest('[data-tab]');
  if (tab) {
    const capability = ADMIN_TAB_CAPABILITY[tab.dataset.tab];
    if (!capability || !adminCan(capability)) return;
    A.tab = tab.dataset.tab;
    A.sel = null;
    renderAdmin();
    return;
  }

  // Vehicle recovery actions
  const recoveryBtn = e.target.closest('[data-vr]');
  if (recoveryBtn) {
    e.stopPropagation();
    const row = recoveryBtn.closest('[data-vehicle-recovery]');
    const identity = Number(row.dataset.vehicleRecovery);
    const action = recoveryBtn.dataset.vr;
    const destructive = ['impound', 'clear_assignment', 'delete_entity', 'public'].includes(action);
    if (destructive && !window.confirm(`Run ${action.replace('_', ' ')} for vehicle ${identity}?`)) return;
    recoveryBtn.disabled = true;
    await post('admin:vehicleRecovery', { identity, action, data: {} });
    recoveryBtn.disabled = false;
    return;
  }

  // Property actions
  const hBtn = e.target.closest('[data-h]');
  if (hBtn) {
    e.stopPropagation();
    const row = hBtn.closest('[data-house]');
    const id = Number(row.dataset.house);
    const act = hBtn.dataset.h;

    // Retake leaves the panel entirely and hands control to the camera.
    if (act === 'retake') {
      $('admin').classList.remove('on');
      return post('admin:retake', { houseId: id });
    }

    let arg = null;
    if (act === 'setPrice') {
      arg = window.prompt('New price?');
      if (arg === null) return;
    }
    if (act === 'evict' || act === 'delete') {
      if (!window.confirm(`Really ${act} this property?`)) return;
    }

    const r = await post('admin:action', { action: act, houseId: id, arg });
    if (r.ok && A.data) {
      // the client re-sends fresh data via adminRefresh
    }
    return;
  }

  // Create a brand-new layout by walking it wherever the admin is standing.
  const newTpl = e.target.closest('[data-newtpl]');
  if (newTpl) {
    $('admin').classList.remove('on');
    return post('admin:template', { action: 'create', kind: newTpl.dataset.newtpl, id: 0 });
  }

  // Layout actions
  const tBtn = e.target.closest('[data-t]');
  if (tBtn) {
    e.stopPropagation();
    const row = tBtn.closest('[data-tpl]');
    const id = Number(row.dataset.tpl);
    const kind = row.dataset.kind;
    const act = tBtn.dataset.t;

    let arg = null;
    if (act === 'rename') {
      arg = window.prompt('New name?');
      if (!arg) return;
    }
    if (act === 'disable' && !window.confirm('Disable this layout? It stops being offered but stays in the database.')) return;
    if (act === 'delete' && !window.confirm('DELETE this layout permanently? This cannot be undone.')) return;

    await post('admin:template', { action: act, kind, id, arg });
    return;
  }

  // Selecting a house flies the camera to it -- THIS is the photo.
  const row = e.target.closest('[data-house]');
  if (row) {
    const id = Number(row.dataset.house);
    A.sel = id;
    const h = A.data.houses.find((x) => x.id === id);
    renderAdmin();
    post('admin:preview', { photoCam: (h && h.photoCam) || null });
  }
});

/* ------------------------------------------------------------
   Bus
   ------------------------------------------------------------ */
window.addEventListener('message', (ev) => {
  const { action, data } = ev.data || {};
  switch (action) {
    case 'wizardFeatures':     openWizard(data);            break;
    case 'wizardPickInterior': wizPick(data, 'interior');   break;
    case 'wizardPickGarage':   wizPick(data, 'garage');     break;
    case 'wizardRooms':        wizRooms(data);              break;
    case 'wizardNameLayout':   wizName(data);               break;
    case 'wizardPublish':      wizPublish(data);            break;
    case 'wizardClose':        $('wiz').classList.remove('on'); break;

    case 'adminOpen':    openAdmin(data);   break;
    case 'adminRefresh': A.data = data; renderAdmin(); break;
    case 'adminClose':   $('admin').classList.remove('on'); break;
  }
});

document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if ($('wiz').classList.contains('on')) {
    $('wiz').classList.remove('on'); post('wizard:cancel');
  } else if ($('admin').classList.contains('on')) {
    $('admin').classList.remove('on'); post('admin:close');
  }
});


window.addEventListener('error', (event) => {
  post('door:clientError', { phase: 'shared-ui-error', message: event.message || 'Unknown NUI error' });
});

window.addEventListener('unhandledrejection', (event) => {
  const reason = event.reason;
  post('door:clientError', {
    phase: 'shared-ui-promise',
    message: reason && reason.message ? reason.message : String(reason || 'Unhandled promise rejection'),
  });
});

// Tell Lua that the NUI page has finished installing its handlers.
post('nuiReady', { version: window.CM_HOUSE_UI_VERSION });
