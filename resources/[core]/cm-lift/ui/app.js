(function () {
    'use strict';

    const app = document.getElementById('lift-app');
    const title = document.getElementById('lift-title');
    const subtitle = document.getElementById('lift-subtitle');
    const floorList = document.getElementById('floor-list');
    const closeButton = document.getElementById('close-button');
    const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'cm-lift';
    let sessionId = null;
    let activeFloors = [];
    let selectedFloor = null;
    let submitting = false;

    function post(name, body) {
        return fetch(`https://${resourceName}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {})
        }).catch(() => undefined);
    }

    function close(reason, notifyClient) {
        app.hidden = true;
        app.classList.remove('is-open');
        app.setAttribute('aria-hidden', 'true');
        floorList.replaceChildren();
        sessionId = null;
        activeFloors = [];
        selectedFloor = null;
        submitting = false;
        if (notifyClient !== false) post('closeLift', { reason: reason || 'escape' });
    }

    function validFloor(floor) {
        return floor && typeof floor === 'object'
            && typeof floor.id === 'string' && floor.id.length > 0
            && typeof floor.label === 'string' && floor.label.length > 0;
    }

    function createFloorButton(floor, index) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'floor-row';
        button.disabled = floor.disabled === true;
        button.setAttribute('role', 'listitem');

        const number = document.createElement('span');
        number.className = 'floor-number';
        number.textContent = String(index + 1).padStart(2, '0');

        const copy = document.createElement('span');
        copy.className = 'floor-copy';
        const label = document.createElement('strong');
        label.textContent = floor.label || 'FLOOR';
        copy.appendChild(label);
        if (floor.subtitle) {
            const small = document.createElement('small');
            small.textContent = floor.subtitle;
            copy.appendChild(small);
        }

        const status = document.createElement('span');
        status.className = 'floor-status';
        if (floor.current) {
            status.textContent = 'CURRENT';
            button.classList.add('is-current');
        } else if (floor.locked) {
            status.textContent = 'LOCKED';
            button.classList.add('is-locked');
            if (floor.lockedReason) button.title = floor.lockedReason;
        } else {
            status.textContent = 'SELECT';
        }

        button.append(number, copy, status);
        button.addEventListener('click', () => {
            if (submitting || button.disabled || !floor.id || !sessionId) return;
            submitting = true;
            selectedFloor = floor.id;
            document.querySelectorAll('.floor-row').forEach((row) => { row.disabled = true; });
            post('selectFloor', { sessionId, floorId: floor.id });
        });
        return button;
    }

    function open(payload) {
        close('new_open', false);
        payload = payload || {};
        sessionId = typeof payload.sessionId === 'string' ? payload.sessionId : null;
        if (!sessionId || payload.direct === true) return;

        const floors = Array.isArray(payload.floors) ? payload.floors.filter(validFloor) : [];
        const selectable = floors.filter((floor) => floor.current !== true && floor.locked !== true && floor.disabled !== true);
        if (selectable.length < 2) {
            close('invalid_payload', false);
            post('closeLift', { reason: 'invalid_payload' });
            return;
        }

        submitting = false;
        activeFloors = floors;
        selectedFloor = null;
        title.textContent = payload.label || 'ELEVATOR';
        subtitle.textContent = 'SELECT FLOOR';
        floorList.replaceChildren();
        activeFloors.forEach((floor, index) => {
            floorList.appendChild(createFloorButton(floor || {}, index));
        });
        app.hidden = false;
        app.classList.add('is-open');
        app.setAttribute('aria-hidden', 'false');
        const firstAvailable = floorList.querySelector('.floor-row:not(:disabled)');
        if (firstAvailable) firstAvailable.focus();
    }

    window.addEventListener('message', (event) => {
        const message = event.data || {};
        if (message.action === 'openLift') open(message.payload);
        if (message.action === 'selectionRejected') {
            submitting = false;
            document.querySelectorAll('.floor-row').forEach((row) => {
                row.disabled = row.classList.contains('is-current') || row.classList.contains('is-locked');
            });
        }
        if (message.action === 'close' || message.action === 'forceClose') close(message.reason || 'force_close', false);
    });

    closeButton.addEventListener('click', () => close('escape'));
    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && !app.hidden) close('escape');
    });

    post('uiReady');
}());
