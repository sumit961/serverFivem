(function () {
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-house';
  const post = (name, data) => fetch(`https://${resource}/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data || {}) });
  let active = null;

  function shell() {
    let root = document.getElementById('cm-ui-bridge');
    if (!root) {
      root = document.createElement('div');
      root.id = 'cm-ui-bridge';
      root.className = 'cm-bridge';
      root.setAttribute('aria-hidden', 'true');
      document.body.appendChild(root);
    }
    return root;
  }

  function clean(text) {
    return String(text == null ? '' : text).replace(/\*\*/g, '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
  }
  function close(report) {
    const root = shell();
    root.classList.remove('cm-bridge--open');
    root.setAttribute('aria-hidden', 'true');
    root.innerHTML = '';
    if (report && active) post('uiBridge:closed', { id: active.id });
    active = null;
  }

  function frame(title, subtitle) {
    const root = shell();
    root.innerHTML = `<section class="cm-bridge__panel"><header class="cm-bridge__head"><span class="cm-bridge__mark">CM</span><div><small>CM CONTROL</small><h2>${clean(title)}</h2>${subtitle ? `<p>${clean(subtitle)}</p>` : ''}</div><button class="cm-bridge__x" data-bridge-close>&times;</button></header><div class="cm-bridge__body"></div></section>`;
    root.classList.add('cm-bridge--open');
    root.setAttribute('aria-hidden', 'false');
    root.querySelector('[data-bridge-close]').onclick = () => close(true);
    return root.querySelector('.cm-bridge__body');
  }

  function renderAlert(message) {
    const c = active.content || {};
    if (window.CMUI && typeof window.CMUI.confirm === 'function') {
      window.CMUI.confirm({
        title: active.title || 'House Confirmation',
        message: c.message || '',
        confirmText: c.confirm || 'Confirm',
        cancelText: c.cancel || 'Cancel',
        danger: !!c.danger
      }).then(ok => {
        if (ok) {
          post('uiBridge:result', { id: active.id, value: 'confirm' }).then(() => close(false));
        } else {
          post('uiBridge:result', { id: active.id, cancelled: true }).then(() => close(false));
        }
      });
      return;
    }
    const body = frame(active.title, 'Confirm this action before continuing');
    body.innerHTML = `<p class="cm-bridge__message">${clean(c.message)}</p><div class="cm-bridge__actions"><button class="cm-bridge__btn cm-bridge__btn--ghost" data-no>${clean(c.cancel || 'Cancel')}</button><button class="cm-bridge__btn ${c.danger ? 'cm-bridge__btn--danger' : ''}" data-yes>${clean(c.confirm || 'Confirm')}</button></div>`;
    body.querySelector('[data-no]').onclick = () => post('uiBridge:result', { id: active.id, cancelled: true }).then(() => close(false));
    body.querySelector('[data-yes]').onclick = () => post('uiBridge:result', { id: active.id, value: 'confirm' }).then(() => close(false));
  }

  function renderInput() {
    const body = frame(active.title, 'Enter the required details');
    const form = document.createElement('form');
    form.className = 'cm-bridge__form';
    (active.content || []).forEach((field, index) => {
      const row = document.createElement('label'); row.className = 'cm-bridge__field';
      row.innerHTML = `<span>${clean(field.label || `Field ${index + 1}`)}</span>${field.description ? `<small>${clean(field.description)}</small>` : ''}`;
      let input;
      if (field.type === 'select') {
        input = document.createElement('select');
        (field.options || []).forEach(opt => { const el = document.createElement('option'); el.value = opt.value; el.textContent = opt.label || opt.value; if (String(field.default) === String(opt.value)) el.selected = true; input.appendChild(el); });
      } else {
        input = document.createElement('input'); input.type = field.type === 'number' ? 'number' : 'text'; input.value = field.default == null ? '' : field.default;
        if (field.min != null) input.min = field.min; if (field.max != null) input.max = field.max; if (field.max && field.type !== 'number') input.maxLength = field.max;
      }
      input.dataset.index = index; input.required = field.required === true; input.placeholder = field.placeholder || '';
      row.appendChild(input); form.appendChild(row);
    });
    form.insertAdjacentHTML('beforeend', '<div class="cm-bridge__actions"><button type="button" class="cm-bridge__btn cm-bridge__btn--ghost" data-no>Cancel</button><button type="submit" class="cm-bridge__btn">Continue</button></div>');
    body.appendChild(form);
    form.querySelector('[data-no]').onclick = () => post('uiBridge:result', { id: active.id, cancelled: true }).then(() => close(false));
    form.onsubmit = e => { e.preventDefault(); const values = [...form.querySelectorAll('[data-index]')].map(el => el.type === 'number' && el.value !== '' ? Number(el.value) : el.value); post('uiBridge:result', { id: active.id, value: values }).then(() => close(false)); };
    const first = form.querySelector('input,select'); if (first) first.focus();
  }

  function renderContext() {
    const body = frame(active.title, 'Information and available actions');
    body.classList.add('cm-bridge__list');
    (active.content || []).forEach(row => {
      const button = document.createElement('button'); button.className = 'cm-bridge__row'; button.disabled = row.disabled === true;
      if (row.iconColor) button.style.setProperty('--row-accent', row.iconColor);
      button.innerHTML = `<span class="cm-bridge__dot"></span><span><strong>${clean(row.title)}</strong>${row.description ? `<small>${clean(row.description)}</small>` : ''}</span>`;
      button.onclick = () => post('uiBridge:contextSelect', { id: active.id, index: row.index }).then(() => close(false)); body.appendChild(button);
    });
  }

  window.addEventListener('message', e => {
    const data = e.data || {};
    if (data.action === 'uiBridge:close') return close(false);
    if (data.action !== 'uiBridge:open') return;
    active = data;
    if (data.mode === 'alert') renderAlert(); else if (data.mode === 'input') renderInput(); else renderContext();
  });
  window.addEventListener('keydown', e => { if (e.key === 'Escape' && active) { e.preventDefault(); close(true); } });
})();
