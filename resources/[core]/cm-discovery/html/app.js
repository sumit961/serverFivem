(() => {
    'use strict';

    const app = document.getElementById('app');
    const list = document.getElementById('list');
    const category = document.getElementById('category');
    const progressLabel = document.getElementById('progress-label');
    const progressPercent = document.getElementById('progress-percent');
    const progressBar = document.getElementById('progress-bar');
    let state = { landmarks: [], categories: [], progress: { discovered: 0, total: 0, percent: 0 } };

    const setDoc = (open) => {
        const value = open ? 'open' : 'closed';
        document.documentElement.dataset.cmUi = value;
        document.body.dataset.cmUi = value;
    };
    const closeUi = () => {
        app.setAttribute('aria-hidden', 'true'); app.classList.remove('open'); setDoc(false);
    };
    closeUi();

    const post = (name, body = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
    });

    const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
    }[char]));

    const renderFilters = () => {
        const current = category.value;
        category.innerHTML = '<option value="all">All landmarks</option>';
        (state.categories || []).forEach((item) => {
            const option = document.createElement('option');
            option.value = item; option.textContent = item;
            category.appendChild(option);
        });
        category.value = [...category.options].some((option) => option.value === current) ? current : 'all';
    };

    const render = () => {
        const progress = state.progress || {};
        const percent = Math.max(0, Math.min(100, Number(progress.percent) || 0));
        progressLabel.textContent = `${Number(progress.discovered) || 0} / ${Number(progress.total) || 0}`;
        progressPercent.textContent = `${percent}%`;
        progressBar.style.width = `${percent}%`;
        const selected = category.value || 'all';
        const rows = (state.landmarks || []).filter((item) => selected === 'all' || item.category === selected);
        list.innerHTML = rows.length ? rows.map((item) => {
            const discovered = item.discovered === true;
            const archived = item.enabled !== true;
            const date = item.discoveredAt ? new Date(item.discoveredAt).toLocaleDateString() : '';
            return `<article class="landmark ${discovered ? 'is-found' : ''}">
                <div class="state-dot" aria-hidden="true"></div>
                <div class="copy"><div class="meta"><span>${escapeHtml(item.category)}</span>${archived ? '<span class="archived">ARCHIVED</span>' : ''}</div>
                    <h2>${discovered ? escapeHtml(item.name) : 'Undiscovered landmark'}</h2>
                    <p>${discovered ? escapeHtml(item.description || 'Landmark discovered.') : 'Explore the city to reveal this entry.'}</p>
                </div>
                <div class="date">${discovered ? escapeHtml(date || 'Recorded') : 'UNKNOWN'}</div>
            </article>`;
        }).join('') : '<div class="empty">No configured landmarks are available.</div>';
    };

    const apply = (data) => {
        if (!data || data.ok !== true) return;
        state = data;
        renderFilters();
        render();
    };

    document.getElementById('close').addEventListener('click', () => post('close'));
    category.addEventListener('change', render);
    window.addEventListener('message', (event) => {
        const message = event.data || {};
        if (message.action === 'open') {
            if (!message.data || message.data.ok !== true) { closeUi(); return; }
            setDoc(true); app.setAttribute('aria-hidden', 'false'); app.classList.add('open');
            apply(message.data);
        } else if (message.action === 'data') {
            apply(message.data);
        } else if (message.action === 'close') {
            closeUi();
        }
    });
    document.addEventListener('keydown', (event) => { if (event.key === 'Escape') post('close'); });
})();
