const resource = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'cm-store';
const post = (name, data = {}) => fetch(`https://${resource}/${name}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data)
}).then(r => r.json().catch(() => ({}))).catch(() => ({}));

const app = document.getElementById('app');
const grid = document.getElementById('grid');
const tabs = document.getElementById('tabs');
const methodEl = document.getElementById('method');

let state = { catalog: [], categories: [] };
let activeCat = 'all';

const esc = v => String(v ?? '').replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[m]));

function imgSrc(image) {
  const s = String(image || '');
  if (!s) return `nui://cm-items/ui/images/default.png`;
  if (s.startsWith('nui://') || s.startsWith('http') || s.startsWith('data:')) return s;
  return `nui://cm-items/ui/images/catalog/${s}`;
}

function categoriesList() {
  const set = new Set();
  state.catalog.forEach(r => set.add(String(r.category || 'misc').toLowerCase()));
  (state.categories || []).forEach(c => set.add(String(c.id).toLowerCase()));
  return ['all', ...[...set].sort()];
}

function renderTabs() {
  const cats = categoriesList();
  if (!cats.includes(activeCat)) activeCat = 'all';
  const labelFor = id => {
    if (id === 'all') return 'All';
    const c = (state.categories || []).find(x => String(x.id).toLowerCase() === id);
    return c ? c.label : id.charAt(0).toUpperCase() + id.slice(1);
  };
  tabs.innerHTML = cats.map(c => `<button class="tab ${c === activeCat ? 'active' : ''}" data-cat="${esc(c)}">${esc(labelFor(c))}</button>`).join('');
  tabs.querySelectorAll('.tab').forEach(b => b.onclick = () => { activeCat = b.dataset.cat; render(); });
}

function render() {
  renderTabs();
  const rows = state.catalog.filter(r => activeCat === 'all' || String(r.category || 'misc').toLowerCase() === activeCat);
  window.__rows = rows;
  grid.innerHTML = rows.map((r, i) => {
    const price = `$${(Number(r.price) || 0).toLocaleString()}`;
    const soldOut = (r.stock !== undefined && Number(r.stock) === 0);
    const stock = (Number(r.stock) < 0 || r.stock === undefined) ? '' : `<span class="stock">${Number(r.stock)} left</span>`;
    const btn = soldOut
      ? `<button class="primary" disabled>Sold out</button>`
      : `<button class="primary" onclick="buyRow(${i})">Buy ${price}</button>`;
    return `<article class="card">
      <div class="thumb"><img src="${esc(imgSrc(r.image))}" onerror="this.style.opacity=.2"></div>
      <div class="body">
        <div class="name">${esc(r.label || r.item_name)}</div>
        <div class="meta">${esc(r.category || 'misc')} ${stock}</div>
        ${r.description ? `<div class="desc">${esc(r.description)}</div>` : ''}
        <div class="price">${price}</div>
        <div class="row-actions">${btn}</div>
      </div>
    </article>`;
  }).join('') || `<p class="empty">No items available right now.</p>`;
}

function buyRow(i) {
  const r = (window.__rows || [])[i]; if (!r) return;
  post('buy', { item_name: r.item_name, method: methodEl.value || 'bank' });
}
window.buyRow = buyRow;

document.getElementById('close').onclick = () => post('close');

window.addEventListener('message', e => {
  const d = e.data || {};
  if (d.action === 'open') {
    state = { catalog: d.catalog || [], categories: d.categories || [] };
    app.classList.remove('hidden');
    render();
  } else if (d.action === 'close') {
    app.classList.add('hidden');
  }
});

document.addEventListener('keydown', e => { if (e.key === 'Escape') post('close'); });
