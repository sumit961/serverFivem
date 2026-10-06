(() => {
    'use strict';

    const app = document.getElementById('app');
    const list = document.getElementById('list');
    const category = document.getElementById('category');
    let state = { events: [], categories: [] };
    let statusFilter = 'all';

    const setDocumentState = (open) => {
        const value = open ? 'open' : 'closed';
        document.documentElement.dataset.cmUi = value;
        document.body.dataset.cmUi = value;
    };

    const closeUi = () => {
        app.classList.remove('open');
        app.hidden = true;
        app.setAttribute('aria-hidden', 'true');
        setDocumentState(false);
    };

    const openUi = (data) => {
        if (!data || data.ok !== true) {
            closeUi();
            return;
        }
        setDocumentState(true);
        app.hidden = false;
        app.classList.add('open');
        app.setAttribute('aria-hidden', 'false');
        apply(data);
    };

    closeUi();

    const post = (name, body = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
    });

    const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, (char) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
    }[char]));

    const formatTime = (timestamp) => {
        if (!timestamp) return 'Time unavailable';
        return new Date(Number(timestamp) * 1000).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
    };

    const renderFilters = () => {
        const current = category.value;
        category.innerHTML = '<option value="all">All categories</option>';
        (state.categories || []).forEach((item) => {
            const option = document.createElement('option');
            option.value = item; option.textContent = item;
            category.appendChild(option);
        });
        category.value = [...category.options].some((option) => option.value === current) ? current : 'all';
    };

    const actionButton = (item) => {
        if (item.status === 'cancelled' || item.status === 'past') return '';
        if (item.rsvpStatus === 'active') {
            return `<button class="action secondary" data-action="cancel" data-id="${escapeHtml(item.id)}">CANCEL RSVP</button>`;
        }
        if (item.remainingCapacity === 0) return '<span class="full">FULL</span>';
        return `<button class="action" data-action="rsvp" data-id="${escapeHtml(item.id)}">RSVP</button>`;
    };

    const render = () => {
        const selected = category.value || 'all';
        const rows = (state.events || []).filter((item) =>
            (statusFilter === 'all' || item.status === statusFilter) &&
            (selected === 'all' || item.category === selected));
        list.innerHTML = rows.length ? rows.map((item) => {
            const capacity = item.capacity == null ? 'Open capacity' : `${item.remainingCapacity} spots left`;
            const location = item.hasLocation ? 'Physical attendance available' : 'Listing only';
            return `<article class="event ${item.status}">
                <div class="event-head"><div><div class="meta"><span>${escapeHtml(item.category)}</span><span class="status">${escapeHtml(item.status)}</span></div>
                    <h2>${escapeHtml(item.title)}</h2></div><span class="date">${escapeHtml(formatTime(item.startAt))}</span></div>
                <p>${escapeHtml(item.description || 'No additional details provided.')}</p>
                <div class="details"><span>${escapeHtml(formatTime(item.startAt))} — ${escapeHtml(formatTime(item.endAt))}</span><span>${escapeHtml(capacity)}</span><span>${escapeHtml(location)}</span></div>
                ${item.cancelled ? `<div class="cancel-note">${escapeHtml(item.cancellationReason || 'This event was cancelled.')}</div>` : ''}
                <div class="event-foot"><span>${item.checkedIn ? 'Attendance recorded' : item.rsvpStatus === 'active' ? 'RSVP confirmed' : ''}</span>${actionButton(item)}</div>
            </article>`;
        }).join('') : '<div class="empty">No events match this view.</div>';
    };

    const apply = (data) => {
        if (!data || data.ok !== true) return;
        state = data;
        renderFilters();
        render();
    };

    document.getElementById('close').addEventListener('click', () => post('close'));
    category.addEventListener('change', render);
    document.querySelectorAll('.tab').forEach((button) => button.addEventListener('click', () => {
        statusFilter = button.dataset.filter || 'all';
        document.querySelectorAll('.tab').forEach((item) => item.classList.toggle('active', item === button));
        render();
    }));
    list.addEventListener('click', (event) => {
        const button = event.target.closest('[data-action]');
        if (button) post('eventAction', { action: button.dataset.action, eventId: button.dataset.id });
    });
    window.addEventListener('message', (event) => {
        const message = event.data || {};
        if (message.action === 'open') {
            openUi(message.data);
        } else if (message.action === 'data') {
            apply(message.data);
        } else if (message.action === 'close') {
            closeUi();
        }
    });
    document.addEventListener('keydown', (event) => { if (event.key === 'Escape') post('close'); });
})();
