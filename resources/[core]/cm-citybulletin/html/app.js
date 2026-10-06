const app = document.querySelector('#app');
const list = document.querySelector('#noticeList');
const status = document.querySelector('#status');
const categoryFilter = document.querySelector('#categoryFilter');
const readFilter = document.querySelector('#readFilter');
const currentCount = document.querySelector('#currentCount');
const archiveCount = document.querySelector('#archiveCount');
let dashboard = { current: [], archived: [], categories: [] };
let view = 'current';
let busy = false;

function post(endpoint, payload = {}) {
    return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
    }).then(response => response.json());
}

function esc(value) {
    return String(value ?? '').replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));
}

function date(value) {
    if (!Number.isFinite(Number(value))) return 'No date';
    return new Date(Number(value) * 1000).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
}

function setStatus(message = '', error = false) {
    status.textContent = message;
    status.classList.toggle('is-error', error);
}

function filteredNotices() {
    const category = categoryFilter.value;
    const readState = readFilter.value;
    return (dashboard[view] || []).filter(notice =>
        (category === 'all' || notice.category === category) &&
        (readState === 'all' || (readState === 'read' ? notice.read : !notice.read))
    );
}

function render() {
    currentCount.textContent = String(dashboard.current.length);
    archiveCount.textContent = String(dashboard.archived.length);
    const notices = filteredNotices();
    if (!notices.length) {
        list.innerHTML = `<div class="empty">${view === 'archived' ? 'No archived notices.' : 'No current notices match these filters.'}</div>`;
        return;
    }
    list.innerHTML = notices.map(notice => `
        <article class="notice ${notice.read ? 'is-read' : ''} is-${esc(notice.priority)}" data-notice-id="${esc(notice.id)}">
            <div class="notice__top">
                <div>
                    <div class="notice__badges">
                        <span class="tag">${esc(notice.category)}</span>
                        ${notice.pinned ? '<span class="tag tag--pinned">Pinned</span>' : ''}
                        ${notice.archived ? '<span class="tag tag--archive">Archived</span>' : ''}
                        ${notice.read ? '<span class="tag tag--read">Read</span>' : '<span class="tag">Unread</span>'}
                    </div>
                    <h2 class="notice__title">${esc(notice.title)}</h2>
                </div>
                ${notice.read ? '' : `<button class="button button--quiet" type="button" data-mark-read="${esc(notice.id)}">Mark read</button>`}
            </div>
            <p class="notice__summary">${esc(notice.summary)}</p>
            <p class="notice__body">${esc(notice.body)}</p>
            <div class="notice__meta">
                <span>Published ${esc(date(notice.publishedAt))}</span>
                ${notice.expiresAt ? `<span>Expires ${esc(date(notice.expiresAt))}</span>` : ''}
                ${notice.archivedAt ? `<span>Archived ${esc(date(notice.archivedAt))}</span>` : ''}
            </div>
        </article>`).join('');
}

function setDashboard(next) {
    if (!next || next.ok !== true) throw new Error(next?.reason || 'bulletin_unavailable');
    dashboard = next;
    const categories = [...new Set(next.categories || [])].sort();
    const selected = categoryFilter.value;
    categoryFilter.innerHTML = '<option value="all">All categories</option>' + categories.map(category => `<option value="${esc(category)}">${esc(category)}</option>`).join('');
    categoryFilter.value = categories.includes(selected) ? selected : 'all';
    render();
}

async function refresh() {
    if (busy) return;
    busy = true;
    setStatus('Refreshing…');
    try { setDashboard(await post('refresh')); setStatus(''); }
    catch (_) { setStatus('The city bulletin could not be refreshed.', true); }
    finally { busy = false; }
}

document.querySelector('#closeButton').addEventListener('click', () => post('close'));
document.querySelector('#refreshButton').addEventListener('click', refresh);
categoryFilter.addEventListener('change', render);
readFilter.addEventListener('change', render);
document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click', () => {
    view = button.dataset.view;
    document.querySelectorAll('[data-view]').forEach(item => item.classList.toggle('is-active', item === button));
    render();
}));
list.addEventListener('click', async event => {
    const button = event.target.closest('[data-mark-read]');
    if (!button) return;
    button.disabled = true;
    try {
        const response = await post('markRead', { noticeId: button.dataset.markRead });
        if (!response?.ok) throw new Error(response?.reason || 'read_state_failed');
        [...dashboard.current, ...dashboard.archived].forEach(notice => {
            if (notice.id === button.dataset.markRead) notice.read = true;
        });
        render();
    } catch (_) {
        button.disabled = false;
        setStatus('This notice could not be marked as read.', true);
    }
});

window.addEventListener('keydown', event => {
    if (event.key === 'Escape') post('close');
});
window.addEventListener('message', event => {
    if (event.data?.action === 'open') {
        document.body.classList.add('is-open');
        app.hidden = false;
        try { setDashboard(event.data.data); setStatus(''); }
        catch (_) { setStatus('The city bulletin is unavailable.', true); }
    }
    if (event.data?.action === 'close') {
        document.body.classList.remove('is-open');
        app.hidden = true;
        busy = false;
        setStatus('');
    }
});
