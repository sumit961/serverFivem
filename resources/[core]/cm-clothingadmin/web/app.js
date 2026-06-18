const app = document.getElementById('app');
const resName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-clothingadmin';
let currentEntry = null;
let catalogRows = [];
let config = { categories: [], shops: [] };

const $ = (id) => document.getElementById(id);

function post(name, data = {}) {
  return fetch(`https://${resName}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data)
  }).then(r => r.json()).catch(err => ({ ok: false, error: String(err) }));
}

function setStatus(msg) { $('status').textContent = msg || 'Ready.'; }

function fillDatalists() {
  const cat = $('categoryList');
  const shops = $('shopList');
  cat.innerHTML = (config.categories || []).map(v => `<option value="${escapeHtml(v)}"></option>`).join('');
  shops.innerHTML = (config.shops || []).map(v => `<option value="${escapeHtml(v)}"></option>`).join('');
}

function escapeHtml(v) {
  return String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function summarize(entry) {
  if (!entry) return 'No clothing captured yet.';
  return [
    `${entry.gender} ${entry.componentType} component=${entry.componentIndex}`,
    `drawable=${entry.drawableId} texture=${entry.textureId}`,
    `label="${entry.label || ''}" price=${entry.price || 0}`,
    `category=${entry.category || ''} shop=${entry.shop || ''}`,
    `arms=${entry.arms ?? ''}:${entry.armsTexture ?? 0} undershirt=${entry.undershirt ?? ''}:${entry.undershirtTexture ?? 0}`,
    `enabled=${entry.enabled !== false}`
  ].join('\n');
}

function setCurrent(entry, fillForm = true) {
  currentEntry = entry;
  $('currentInfo').textContent = summarize(entry);
  if (!entry || !fillForm) return;
  $('labelInput').value = entry.label || '';
  $('priceInput').value = Number(entry.price || 0);
  $('categoryInput').value = entry.category || config.defaultCategory || '';
  $('shopInput').value = entry.shop || config.defaultShop || '';
  $('sleeveInput').value = entry.sleeveStyle || '';
  $('enabledInput').value = entry.enabled === false ? 'false' : 'true';
  $('imageInput').value = entry.image || '';
  $('jobInput').value = entry.job || '';
  $('gangInput').value = entry.gang || '';
  $('notesInput').value = entry.notes || '';
  $('armsInput').value = entry.arms ?? '';
  $('armsTextureInput').value = entry.armsTexture ?? 0;
  $('undershirtInput').value = entry.undershirt ?? '';
  $('undershirtTextureInput').value = entry.undershirtTexture ?? 0;
}

function buildEntryFromForm() {
  const base = currentEntry || {};
  const mode = $('textureMode').value;
  return {
    ...base,
    textureId: mode === 'all' ? -1 : Number(base.textureId ?? 0),
    label: $('labelInput').value.trim() || base.label || 'Clothing Item',
    price: Number($('priceInput').value || 0),
    category: $('categoryInput').value.trim(),
    shop: $('shopInput').value.trim(),
    sleeveStyle: $('sleeveInput').value || null,
    enabled: $('enabledInput').value === 'true',
    image: $('imageInput').value.trim() || null,
    job: $('jobInput').value.trim() || null,
    gang: $('gangInput').value.trim() || null,
    notes: $('notesInput').value.trim() || null,
    arms: $('armsInput').value === '' ? null : Number($('armsInput').value),
    armsTexture: Number($('armsTextureInput').value || 0),
    undershirt: $('undershirtInput').value === '' ? null : Number($('undershirtInput').value),
    undershirtTexture: Number($('undershirtTextureInput').value || 0),
  };
}

function renderCatalog() {
  const q = $('searchInput').value.toLowerCase().trim();
  const box = $('catalogList');
  const rows = catalogRows.filter(row => {
    if (!q) return true;
    const hay = `${row.label || ''} ${row.gender || ''} ${row.componentIndex} ${row.drawableId} ${row.textureId} ${row.category || ''} ${row.shop || ''}`.toLowerCase();
    return hay.includes(q);
  }).slice(0, 200);
  if (!rows.length) {
    box.innerHTML = '<div class="info">No catalog entries found.</div>';
    return;
  }
  box.innerHTML = rows.map((row, i) => `
    <div class="catalogItem" data-index="${i}">
      <strong>${escapeHtml(row.label || 'Unnamed clothing')}</strong>
      <span>${escapeHtml(row.gender)} comp ${row.componentIndex} drawable ${row.drawableId} texture ${row.textureId} • $${row.price || 0}</span>
      <span>${escapeHtml(row.category || 'no category')} / ${escapeHtml(row.shop || 'no shop')} • ${row.enabled === false ? 'disabled' : 'enabled'}</span>
    </div>
  `).join('');
  [...box.querySelectorAll('.catalogItem')].forEach((el, idx) => {
    el.onclick = () => setCurrent(rows[idx], true);
  });
}

async function refreshCatalog() {
  const res = await post('getCatalogItems', {});
  if (res.ok) {
    catalogRows = res.items || [];
    renderCatalog();
    setStatus(`Loaded ${catalogRows.length} catalog rows from server cache.`);
  } else {
    setStatus(`Catalog load failed: ${res.error || 'unknown error'}`);
  }
}

async function captureCurrent() {
  const res = await post('getCurrentClothing', { category: $('captureType').value });
  if (res.ok && res.entry) {
    setCurrent(res.entry, true);
    setStatus('Captured current clothing.');
  } else {
    setStatus(`Capture failed: ${res.error || 'unknown error'}`);
  }
}

async function captureFit() {
  const res = await post('getCurrentFit', {});
  if (res.ok && currentEntry) {
    currentEntry.arms = res.fit.arms;
    currentEntry.armsTexture = res.fit.armsTexture;
    currentEntry.undershirt = res.fit.undershirt;
    currentEntry.undershirtTexture = res.fit.undershirtTexture;
    $('armsInput').value = currentEntry.arms ?? '';
    $('armsTextureInput').value = currentEntry.armsTexture ?? 0;
    $('undershirtInput').value = currentEntry.undershirt ?? '';
    $('undershirtTextureInput').value = currentEntry.undershirtTexture ?? 0;
    $('currentInfo').textContent = summarize(currentEntry);
    setStatus('Captured current arms/body and undershirt fit.');
  } else {
    setStatus(`Fit capture failed: ${res.error || 'unknown error'}`);
  }
}

async function saveEntry() {
  if (!currentEntry) { setStatus('Capture or select clothing first.'); return; }
  const entry = buildEntryFromForm();
  const res = await post('saveCatalogItem', { entry });
  if (res.ok) {
    setStatus('Saved to catalog and updated server cache.');
    await refreshCatalog();
  } else {
    setStatus(`Save failed: ${res.error || 'unknown error'}`);
  }
}

async function deleteEntry() {
  if (!currentEntry) { setStatus('Select an entry first.'); return; }
  const entry = buildEntryFromForm();
  const res = await post('deleteCatalogItem', { entry });
  if (res.ok) {
    setStatus('Deleted catalog entry and updated cache.');
    await refreshCatalog();
  } else {
    setStatus(`Delete failed: ${res.error || 'unknown error'}`);
  }
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') {
    app.classList.remove('hidden');
    config = data.config || config;
    fillDatalists();
    if (data.current) setCurrent(data.current, true);
    refreshCatalog();
  }
  if (data.action === 'close') {
    app.classList.add('hidden');
  }
});

$('closeBtn').onclick = () => post('close').then(() => app.classList.add('hidden'));
$('captureBtn').onclick = captureCurrent;
$('captureFitBtn').onclick = captureFit;
$('saveBtn').onclick = saveEntry;
$('deleteCurrentBtn').onclick = deleteEntry;
$('reloadBtn').onclick = async () => {
  const res = await post('reloadCatalog', {});
  if (!res.ok) setStatus(`Reload failed: ${res.error || 'unknown error'}`);
  await refreshCatalog();
};
$('previewBtn').onclick = async () => {
  if (!currentEntry) return setStatus('Capture or select clothing first.');
  const res = await post('previewClothing', { entry: buildEntryFromForm() });
  setStatus(res.ok ? 'Preview applied.' : `Preview failed: ${res.error || 'unknown error'}`);
};
$('searchInput').oninput = renderCatalog;

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') $('closeBtn').click();
});
