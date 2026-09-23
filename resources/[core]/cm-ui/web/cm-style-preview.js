/* Interactive showcase for the shared CM Style component language. */
(function () {
    'use strict';

    var CMUI = window.CMUI || {};

    var slots = [
        { name: 'SLOT 01', status: 'AVAILABLE', badge: 'green', icon: '[]', price: '$5,000', kind: '' },
        { name: 'SLOT 02', status: 'AVAILABLE', badge: 'green', icon: '[]', price: '$5,000', kind: '' },
        { name: 'SLOT 03', status: 'YOURS', badge: 'yellow', icon: '*', price: 'OWNED', kind: 'owned' },
        { name: 'SLOT 04', status: 'SELECTED', badge: 'cyan', icon: '+', price: '$5,000', kind: 'selected' },
        { name: 'SLOT 05', status: 'OCCUPIED', badge: 'gray', icon: 'x', price: 'OCCUPIED', kind: 'unavailable' },
        { name: 'SLOT 06', status: 'AVAILABLE', badge: 'green', icon: '[]', price: '$5,000', kind: '' }
    ];

    function esc(value) {
        return String(value).replace(/[&<>"']/g, function (character) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[character];
        });
    }

    function button(label, className, action) {
        return '<button type="button" class="cm-style-btn ' + className + '" data-cm-style-action="' + action + '">' + esc(label) + '</button>';
    }

    function render() {
        var root = document.createElement('section');
        root.className = 'cm-style-shell';
        root.id = 'cmStylePreview';
        root.innerHTML =
            '<button type="button" class="cm-style-btn cm-style-btn--secondary cm-style-close" data-cm-style-action="close">CLOSE PREVIEW</button>' +
            '<header class="cm-style-header">' +
                '<div><div class="cm-style-kicker">CM UI / SHARED STYLE LANGUAGE</div><h1 class="cm-style-title">Operations Console</h1><p class="cm-style-subtitle">Reusable tactical cards, actions, status, and modal patterns</p></div>' +
                '<div class="cm-style-header-stats">' +
                    '<div class="cm-style-stat"><span class="cm-style-label">FREE SPACES</span><span class="cm-style-value cm-style-value--cyan">08 / 12</span></div>' +
                    '<div class="cm-style-stat"><span class="cm-style-label">HOURLY RATE</span><span class="cm-style-value cm-style-value--yellow">$250</span></div>' +
                    '<div class="cm-style-stat"><span class="cm-style-label">BALANCE</span><span class="cm-style-value cm-style-value--green">$145,200</span></div>' +
                '</div>' +
            '</header>' +
            '<nav class="cm-style-nav" aria-label="CM Style preview sections">' +
                '<button class="cm-style-tab cm-active" data-cm-style-tab="slots">SLOT GRID</button>' +
                '<button class="cm-style-tab" data-cm-style-tab="components">COMPONENTS</button>' +
                '<button class="cm-style-tab" data-cm-style-tab="modals">MODALS</button>' +
                '<button class="cm-style-tab" data-cm-style-tab="events">EVENT CARD</button>' +
                '<button class="cm-style-tab" data-cm-style-tab="code">CODE</button>' +
            '</nav>' +
            '<div class="cm-style-view cm-active" data-cm-style-view="slots"><div class="cm-style-grid cm-style-grid--slots" id="cmStyleSlots"></div><div class="cm-style-action-row">' + button('REFRESH', 'cm-style-btn--secondary', 'toast-refresh') + button('CONFIRM SLOT', 'cm-style-btn--cyan', 'confirm') + '</div></div>' +
            '<div class="cm-style-view" data-cm-style-view="components"><div class="cm-style-grid cm-style-grid--showcase">' +
                '<article class="cm-style-card"><h2 class="cm-style-card__title">Status & badges</h2><div class="cm-style-action-row" style="justify-content:flex-start;margin-top:0"><span class="cm-style-badge cm-style-badge--green">AVAILABLE</span><span class="cm-style-badge cm-style-badge--cyan">ACTIVE</span><span class="cm-style-badge cm-style-badge--yellow">YOURS</span><span class="cm-style-badge cm-style-badge--gray">OCCUPIED</span></div><label class="cm-style-label" style="display:block;margin-top:18px">Search vehicle or spot</label><input class="cm-style-input" value="SLOT-004" /></article>' +
                '<article class="cm-style-card"><h2 class="cm-style-card__title">HUD progress</h2><div class="cm-style-row"><span class="cm-style-label">FUEL LEVEL</span><strong>85%</strong></div><div class="cm-style-progress"><div class="cm-style-progress__bar" style="width:85%"></div></div><div class="cm-style-row cm-style-row--orange" style="margin-top:14px"><span class="cm-style-label">ENGINE HEALTH</span><strong class="cm-style-value--orange">42%</strong></div><div class="cm-style-progress"><div class="cm-style-progress__bar" style="width:42%;background:var(--cm-style-orange)"></div></div></article>' +
                '<article class="cm-style-card"><h2 class="cm-style-card__title">Metric list</h2><div class="cm-style-row"><span class="cm-style-label">RESERVED UNTIL</span><strong>14:00 PM</strong></div><div class="cm-style-row cm-style-row--green" style="margin-top:8px"><span class="cm-style-label">SPOT PRICE</span><strong class="cm-style-value--green">$5,000</strong></div><div class="cm-style-row cm-style-row--orange" style="margin-top:8px"><span class="cm-style-label">DESPAWN TIMER</span><strong class="cm-style-value--orange">04:22 MIN</strong></div></article>' +
            '</div></div>' +
            '<div class="cm-style-view" data-cm-style-view="modals"><article class="cm-style-card" style="max-width:540px;margin:auto;text-align:center"><h2 class="cm-style-card__title" style="justify-content:center">Modal & confirmation system</h2><p style="color:var(--cm-style-text-secondary);line-height:1.5">Use the shared modal presentation for costly or world-changing actions. The owning resource still validates the operation server-side.</p><div class="cm-style-action-row" style="justify-content:center">' + button('ITEM PICKER', 'cm-style-btn--cyan', 'item-picker') + button('CONFIRM PURCHASE', 'cm-style-btn--danger', 'confirm') + '</div></article></div>' +
            '<div class="cm-style-view" data-cm-style-view="events"><div style="max-width:420px;margin:auto"><article class="cm-style-event"><div class="cm-style-event__banner"><span class="cm-style-badge cm-style-badge--red">RACE EVENT</span><span class="cm-style-badge cm-style-badge--yellow">02:45</span></div><div class="cm-style-event__body"><h2 class="cm-style-card__title" style="margin-bottom:0">Street Outlaws Drift</h2><p>Join the downtown illegal drift circuit. Win a $25,000 prize purse.</p><div class="cm-style-row"><span class="cm-style-label">LOCATION</span><strong>LEGION SQUARE</strong></div>' + button('SET GPS WAYPOINT', 'cm-style-btn--cyan cm-style-btn--wide', 'toast-gps') + '</div></article></div></div>' +
            '<div class="cm-style-view" data-cm-style-view="code"><article class="cm-style-card"><div class="cm-style-row"><span class="cm-style-card__title" style="margin:0">Reusable class contract</span>' + button('COPY CSS SNIPPET', 'cm-style-btn--cyan', 'copy-code') + '</div><pre class="cm-style-code" id="cmStyleCode">&lt;link rel="stylesheet" href="nui://cm-ui/web/cm-style.css"&gt;\n\n&lt;div class="cm-style-card"&gt;\n  &lt;span class="cm-style-badge cm-style-badge--cyan"&gt;ACTIVE&lt;/span&gt;\n  &lt;button class="cm-style-btn cm-style-btn--cyan"&gt;CONFIRM&lt;/button&gt;\n&lt;/div&gt;</pre></article></div>' +
            '<div class="cm-style-toast" id="cmStyleToast" role="status"></div>';

        document.body.appendChild(root);
        var slotRoot = root.querySelector('#cmStyleSlots');
        slots.forEach(function (slot, index) {
            var item = document.createElement('article');
            item.className = 'cm-style-slot' + (slot.kind ? ' cm-style-slot--' + slot.kind : '');
            item.dataset.cmStyleSlot = String(index);
            item.innerHTML = '<div class="cm-style-slot__head"><span class="cm-style-slot__name">' + esc(slot.name) + '</span><span class="cm-style-badge cm-style-badge--' + slot.badge + '">' + esc(slot.status) + '</span></div><div class="cm-style-slot__icon" aria-hidden="true">' + esc(slot.icon) + '</div><div class="cm-style-slot__foot"><span class="cm-style-slot__title">STANDARD ZONE</span><strong class="cm-style-slot__price">' + esc(slot.price) + '</strong></div>';
            slotRoot.appendChild(item);
        });

        root.addEventListener('click', handleClick);
        root.querySelectorAll('[data-cm-style-tab]').forEach(function (tab) {
            tab.addEventListener('click', function () { activate(tab.dataset.cmStyleTab); });
        });
        document.addEventListener('keydown', onEscape);
    }

    function activate(name) {
        var root = document.getElementById('cmStylePreview');
        if (!root) return;
        root.querySelectorAll('[data-cm-style-tab]').forEach(function (tab) { tab.classList.toggle('cm-active', tab.dataset.cmStyleTab === name); });
        root.querySelectorAll('[data-cm-style-view]').forEach(function (view) { view.classList.toggle('cm-active', view.dataset.cmStyleView === name); });
    }

    function toast(message) {
        var el = document.getElementById('cmStyleToast');
        if (!el) return;
        el.textContent = message;
        el.classList.add('cm-visible');
        clearTimeout(el._cmTimer);
        el._cmTimer = setTimeout(function () { el.classList.remove('cm-visible'); }, 2600);
    }

    function openModal(type) {
        var backdrop = document.createElement('div');
        backdrop.className = 'cm-style-modal-backdrop';
        backdrop.innerHTML = '<div class="cm-style-modal" role="dialog" aria-modal="true"><h2 class="cm-style-modal__title">' + (type === 'list' ? 'SELECT VEHICLE' : 'CONFIRM PURCHASE') + '</h2>' + (type === 'list' ? '<div class="cm-style-list"><button class="cm-style-list-item cm-active"><span>ELEGY RH8</span><span>#4021</span></button><button class="cm-style-list-item"><span>SULTAN RS</span><span>#1198</span></button><button class="cm-style-list-item"><span>SCHAFTER</span><span>#8802</span></button></div>' : '<p class="cm-style-modal__body">Purchase Parking Slot #04 for $5,000? Funds will be deducted from your bank balance.</p>') + '<div class="cm-style-action-row"><button type="button" class="cm-style-btn cm-style-btn--secondary" data-cm-modal="close">CANCEL</button><button type="button" class="cm-style-btn ' + (type === 'list' ? 'cm-style-btn--cyan' : '') + '" data-cm-modal="confirm">CONFIRM</button></div></div>';
        document.body.appendChild(backdrop);
        backdrop.addEventListener('click', function (event) { if (event.target === backdrop || event.target.dataset.cmModal === 'close') backdrop.remove(); if (event.target.dataset.cmModal === 'confirm') { backdrop.remove(); toast('Action confirmed in preview.'); } });
    }

    function handleClick(event) {
        var action = event.target.closest('[data-cm-style-action]');
        if (action) {
            var type = action.dataset.cmStyleAction;
            if (type === 'close') return CMUI.closeStylePreview();
            if (type === 'confirm') return openModal('confirm');
            if (type === 'item-picker') return openModal('list');
            if (type === 'toast-refresh') return toast('Preview components refreshed.');
            if (type === 'toast-gps') return toast('GPS waypoint set in preview.');
            if (type === 'copy-code') { toast('CSS snippet copied.'); return; }
        }
        var slot = event.target.closest('[data-cm-style-slot]');
        if (slot && !slot.classList.contains('cm-style-slot--unavailable')) {
            document.querySelectorAll('[data-cm-style-slot]').forEach(function (item) { item.classList.remove('cm-style-slot--selected'); });
            slot.classList.add('cm-style-slot--selected');
            toast('Selected ' + slot.querySelector('.cm-style-slot__name').textContent + '.');
        }
    }

    function onEscape(event) { if (event.key === 'Escape' && document.getElementById('cmStylePreview')) CMUI.closeStylePreview(); }

    CMUI.openStylePreview = function () { if (!document.getElementById('cmStylePreview')) render(); };
    CMUI.closeStylePreview = function (notify) {
        var root = document.getElementById('cmStylePreview');
        if (root) root.remove();
        document.removeEventListener('keydown', onEscape);
        if (notify !== false) CMUI.postNui('cmStylePreviewClose', {});
    };

    window.CMUI = CMUI;
})(window);
