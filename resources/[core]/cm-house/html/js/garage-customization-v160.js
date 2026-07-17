(() => {
  const root = document.getElementById('garage-customization');
  if (!root) return;
  const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  const post = (name, body = {}) => fetch(`https://${RES}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body),
  }).then((r) => r.json()).catch(() => ({ ok: false }));

  let catalog = {};
  let selected = {};
  const groups = { themes:'gc-themes', floors:'gc-floors', walls:'gc-walls', lights:'gc-lights', decor:'gc-decor', accents:'gc-accents' };
  const keyFor = { themes:'theme', floors:'floor', walls:'wall', lights:'light', decor:'decor', accents:'accent' };
  const tuning = {
    floorOpacity: ['gc-floor-opacity', 'gc-floor-opacity-value', 100],
    wallIntensity: ['gc-wall-intensity', 'gc-wall-intensity-value', 100],
    lightIntensity: ['gc-light-intensity', 'gc-light-intensity-value', 100],
    decorDensity: ['gc-decor-density', 'gc-decor-density-value', 100],
  };

  function entries(group) { return Object.entries(catalog[group] || {}).sort((a,b) => String(a[1].label).localeCompare(String(b[1].label))); }
  function renderGroup(group) {
    const host = document.getElementById(groups[group]);
    if (!host) return;
    host.replaceChildren(...entries(group).map(([key, item]) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'gc-option' + (selected[keyFor[group]] === key ? ' is-active' : '') + (group === 'accents' ? ' gc-option--accent' : '');
      button.textContent = item.label || key;
      button.dataset.gcGroup = group;
      button.dataset.gcKey = key;
      if (group === 'accents' && item.rgb) button.style.setProperty('--swatch', `rgb(${item.rgb.join(',')})`);
      return button;
    }));
  }
  function renderTuning() {
    selected.settings = selected.settings || {};
    Object.entries(tuning).forEach(([key, [inputId, outputId, fallback]]) => {
      const input = document.getElementById(inputId);
      const output = document.getElementById(outputId);
      const value = Number.isFinite(Number(selected.settings[key])) ? Number(selected.settings[key]) : fallback;
      selected.settings[key] = value;
      if (input) input.value = String(value);
      if (output) output.textContent = `${value}%`;
    });
  }
  function render() { Object.keys(groups).forEach(renderGroup); renderTuning(); }
  function close() { root.classList.remove('is-open'); root.setAttribute('aria-hidden','true'); post('garageCustomize:close'); }
  function open(data) {
    catalog = data.catalog || {};
    selected = { ...(data.current || {}) };
    render();
    root.classList.add('is-open'); root.setAttribute('aria-hidden','false');
  }

  Object.entries(tuning).forEach(([key, [inputId, outputId, fallback]]) => {
    const input = document.getElementById(inputId);
    input?.addEventListener('input', () => {
      selected.settings = selected.settings || {};
      const value = Number(input.value || fallback);
      selected.settings[key] = value;
      const output = document.getElementById(outputId);
      if (output) output.textContent = `${value}%`;
    });
  });

  root.addEventListener('click', (event) => {
    const option = event.target.closest('[data-gc-group]');
    if (option) {
      const group = option.dataset.gcGroup;
      const key = option.dataset.gcKey;
      selected[keyFor[group]] = key;
      if (group === 'themes') {
        const preset = catalog.themes && catalog.themes[key];
        if (preset) ['floor','wall','light','decor','accent'].forEach((name) => { if (preset[name]) selected[name] = preset[name]; });
      }
      render();
      return;
    }
    if (event.target.closest('[data-gc-close]')) close();
  });
  document.getElementById('gc-save')?.addEventListener('click', async () => {
    const response = await post('garageCustomize:save', selected);
    if (response && response.ok) root.classList.remove('is-open');
  });
  window.addEventListener('keydown', (event) => { if (event.key === 'Escape' && root.classList.contains('is-open')) close(); });
  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'openGarageCustomization') open(msg.data || {});
    if (msg.action === 'closeGarageCustomization') { root.classList.remove('is-open'); root.setAttribute('aria-hidden','true'); }
  });
})();
