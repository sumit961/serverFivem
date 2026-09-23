(function () {
    'use strict';

    function isEnvBrowser() {
        return !window.invokeNative;
    }

    async function fetchNui(eventName, data) {
        const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'cm-taxi';
        if (isEnvBrowser()) return { success: true, ok: true };

        const resp = await fetch(`https://${resourceName}/${eventName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        try {
            return await resp.json();
        } catch (e) {
            return { success: false };
        }
    }

    // ============================================================
    // Meter tablet
    // ============================================================

    const meter = document.getElementById('meter');
    const hudHelp = document.getElementById('hud-help');
    const rentalTimer = document.getElementById('rental-timer');
    const rentalTimeLeft = document.getElementById('rental-time-left');
    let meterAvailable = false;

    function renderFares(fares, currentKeybind) {
        const list = document.getElementById('fares-list');
        const entries = Object.keys(fares || {})
            .map((id) => ({ id, ...fares[id] }))
            .filter((f) => f && f.name && !f.driver)
            .sort((a, b) => Number(b.playerRequested === true) - Number(a.playerRequested === true)
                || (Number.isFinite(Number(a.distance)) ? Number(a.distance) : Infinity)
                - (Number.isFinite(Number(b.distance)) ? Number(b.distance) : Infinity));

        document.getElementById('fares-count').textContent = entries.length;

        if (entries.length === 0) {
            list.innerHTML = '<div class="fares-empty">No fares queued right now</div>';
            return;
        }

        list.innerHTML = entries
            .map((f) => {
                const pickupDistance = f.distance !== undefined ? `${Math.round(f.distance)}m pickup` : '';
                const tripDistance = f.tripDistance !== undefined ? `${Math.round(f.tripDistance)}m trip` : '';
                const payout = f.fare !== undefined ? `$${Number(f.fare).toFixed(2)}` : '';
                const remaining = f.expiresAt ? Math.max(0, Number(f.expiresAt) - Math.floor(Date.now() / 1000)) : null;
                const expiry = remaining === null ? '' : `${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, '0')} left`;
                const nearby = f.nearby ? '<span class="fare-item-nearby">NEARBY</span>' : '';
                const playerCall = f.playerRequested ? '<span class="fare-item-call">PLAYER CALL</span>' : '';
                return `
                <article class="fare-item ${f.playerRequested ? 'player-call-card' : ''} ${f.nearby ? 'nearby-card' : ''}">
                    <div class="fare-item-main">
                        <div class="fare-item-title"><span class="fare-item-name">${escapeHtml(f.name)}</span>${playerCall}${nearby}</div>
                        <div class="fare-item-sub">${pickupDistance}${pickupDistance && tripDistance ? ' &middot; ' : ''}${tripDistance}</div>
                        ${expiry ? `<div class="fare-item-expiry">EXPIRES IN ${expiry}</div>` : ''}
                    </div>
                    <div class="fare-item-side">
                        <strong class="fare-item-pay">${payout}</strong>
                        <button class="fare-item-accept" data-id="${escapeHtml(f.id)}" ${remaining === 0 ? 'disabled' : ''}>${remaining === 0 ? '&times;' : '&#10148;'}</button>
                    </div>
                </article>`;
            })
            .join('');

        list.querySelectorAll('.fare-item-accept').forEach((btn) => {
            btn.addEventListener('click', async () => {
                btn.disabled = true;
                btn.classList.add('is-pending');
                const result = await fetchNui('takejob', { id: btn.dataset.id });
                if (!result || !result.success) {
                    btn.disabled = false;
                    btn.classList.remove('is-pending');
                }
            });
        });
    }

    function escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = String(str == null ? '' : str);
        return div.innerHTML;
    }

    function setData(data) {
        if (!data) return;

        if (data.speed) {
            const pct = Math.max(0, Math.min(100, (data.speed.velocity / 160) * 100));
            document.getElementById('speed-ring').style.setProperty('--pct', pct);
            document.getElementById('speed-num').textContent = data.speed.velocity;
        }

        if (data.currentfareinfo) {
            const info = data.currentfareinfo;
            document.getElementById('stat-current').textContent = `$${info.currentfare}`;
            document.getElementById('stat-base').textContent = `$${info.basefare}`;
            document.getElementById('stat-perminute').textContent = `$${info.perminute}`;
            document.getElementById('stat-customer').textContent = info.customer || '-';
            document.getElementById('stat-pickup').textContent = info.pickup || 'AWAITING DISPATCH';
            document.getElementById('stat-destination').textContent = info.destination || '-';
            const status = document.getElementById('stat-status');
            status.textContent = info.status || (info.active ? 'FARE ACTIVE' : 'NO ACTIVE FARE');
            status.classList.toggle('warning', info.playerRequested === true);
            status.classList.toggle('idle', info.active !== true);
        }

        if (data.shiftStats) {
            document.getElementById('shift-rides').textContent = Math.max(0, Number(data.shiftStats.completed) || 0);
            document.getElementById('shift-earnings').textContent = `$${Math.max(0, Number(data.shiftStats.earnings) || 0).toFixed(0)}`;
            document.getElementById('shift-tips').textContent = `$${Math.max(0, Number(data.shiftStats.tips) || 0).toFixed(0)}`;
        }

        if (data.keybind) {
            document.getElementById('meter-keybind').textContent = data.keybind;
        }

        if (data.fares !== undefined) renderFares(data.fares);
    }

    document.getElementById('btn-cancel-job').addEventListener('click', (event) => {
        const button = event.currentTarget;
        const passenger = document.getElementById('stat-customer').textContent || 'ACTIVE FARE';
        openConfirmation({
            title: 'CANCEL THIS FARE?',
            message: `END THE CURRENT FARE FOR ${passenger}?`,
            consequence: 'THE PASSENGER WILL BE RELEASED AND THE FARE WILL RETURN TO DISPATCH.',
            tone: 'danger',
            actionLabel: 'CANCEL FARE',
            run: async () => {
                const result = await fetchNui('canceljob');
                if (!result || result.success !== true) throw new Error('Fare cancellation failed');
                return result;
            },
        }, button);
    });

    // ============================================================
    // Office panel
    // ============================================================

    const office = document.getElementById('office');
    const gameHud = document.getElementById('game-hud');
    const confirmModal = document.getElementById('confirm-modal');
    const confirmPanel = confirmModal.querySelector('.cm-confirm-modal');
    const confirmTitle = document.getElementById('confirm-title');
    const confirmMessage = document.getElementById('confirm-message');
    const confirmConsequence = document.getElementById('confirm-consequence');
    const confirmStatus = document.getElementById('confirm-status');
    const confirmCancel = document.getElementById('confirm-cancel');
    const confirmAccept = document.getElementById('confirm-accept');
    let activeConfirmation = null;

    function closeConfirmation(restoreFocus) {
        const returnFocus = activeConfirmation && activeConfirmation.returnFocus;
        activeConfirmation = null;
        confirmModal.classList.add('hidden');
        confirmModal.setAttribute('aria-hidden', 'true');
        confirmStatus.className = 'confirm-modal__status hidden';
        confirmStatus.textContent = '';
        confirmCancel.disabled = false;
        confirmAccept.disabled = false;
        if (restoreFocus !== false && returnFocus && returnFocus.isConnected && !returnFocus.disabled) {
            returnFocus.focus();
        }
        syncGameHudVisibility();
    }

    function openConfirmation(options, returnFocus) {
        if (activeConfirmation && activeConfirmation.processing) return;
        const tone = options.tone === 'danger' ? 'danger' : 'warning';
        confirmPanel.classList.toggle('tone-danger', tone === 'danger');
        confirmPanel.classList.toggle('tone-warning', tone === 'warning');
        confirmPanel.classList.remove('tone-success');
        activeConfirmation = {
            run: options.run,
            returnFocus: returnFocus || document.activeElement,
            tone,
            actionLabel: options.actionLabel || 'CONFIRM',
            processing: false,
        };

        confirmTitle.textContent = options.title || 'CONFIRM ACTION';
        confirmMessage.textContent = options.message || '';
        confirmConsequence.textContent = options.consequence || '';
        confirmStatus.className = 'confirm-modal__status hidden';
        confirmStatus.textContent = '';
        confirmCancel.disabled = false;
        confirmAccept.disabled = false;
        confirmAccept.textContent = activeConfirmation.actionLabel;
        confirmAccept.className = `cm-confirm-modal__confirm tone-${tone}`;
        confirmModal.classList.remove('hidden');
        confirmModal.setAttribute('aria-hidden', 'false');
        syncGameHudVisibility();

        // Destructive actions default to the safe path.
        confirmCancel.focus();
    }

    async function submitConfirmation() {
        const pending = activeConfirmation;
        if (!pending || pending.processing) return;

        pending.processing = true;
        confirmCancel.disabled = true;
        confirmAccept.disabled = true;
        confirmAccept.textContent = 'PROCESSING';
        confirmStatus.className = 'confirm-modal__status is-loading';
        confirmStatus.textContent = 'SENDING REQUEST';
        confirmStatus.focus();

        try {
            const result = await pending.run();
            if (!result || result.success === false || result.ok === false) throw new Error('Request failed');
            if (activeConfirmation !== pending) return;

            confirmAccept.className = 'cm-confirm-modal__confirm tone-success is-success';
            confirmPanel.classList.remove('tone-warning', 'tone-danger');
            confirmPanel.classList.add('tone-success');
            confirmAccept.textContent = 'COMPLETE';
            confirmStatus.className = 'confirm-modal__status is-success';
            confirmStatus.textContent = 'ACTION CONFIRMED';
            setTimeout(() => {
                if (activeConfirmation === pending) closeConfirmation();
            }, 700);
        } catch (_) {
            if (activeConfirmation !== pending) return;
            pending.processing = false;
            confirmCancel.disabled = false;
            confirmAccept.disabled = false;
            confirmAccept.className = `cm-confirm-modal__confirm tone-${pending.tone}`;
            confirmPanel.classList.toggle('tone-danger', pending.tone === 'danger');
            confirmPanel.classList.toggle('tone-warning', pending.tone === 'warning');
            confirmPanel.classList.remove('tone-success');
            confirmAccept.textContent = pending.actionLabel;
            confirmStatus.className = 'confirm-modal__status is-error';
            confirmStatus.textContent = 'THE REQUEST COULD NOT BE COMPLETED. CHECK THE UPDATE AND TRY AGAIN.';
            confirmCancel.focus();
        }
    }

    confirmAccept.addEventListener('click', submitConfirmation);
    confirmCancel.addEventListener('click', () => {
        if (!activeConfirmation || activeConfirmation.processing) return;
        closeConfirmation();
    });
    confirmModal.addEventListener('click', (event) => {
        if (event.target === confirmModal && activeConfirmation && !activeConfirmation.processing) {
            closeConfirmation();
        }
    });

    function syncGameHudVisibility() {
        const shouldShow = !meter.classList.contains('hidden') ||
            !office.classList.contains('hidden') ||
            !hudHelp.classList.contains('hidden') ||
            !rentalTimer.classList.contains('hidden') ||
            !confirmModal.classList.contains('hidden');
        gameHud.style.display = shouldShow ? 'block' : 'none';
        gameHud.style.visibility = shouldShow ? 'visible' : 'hidden';
        gameHud.classList.toggle('is-visible', shouldShow);
        document.documentElement.classList.toggle('nui-visible', shouldShow);
    }

    let firstRideHintTimeout = null;
    function setFirstRideHint(data) {
        if (firstRideHintTimeout !== null) {
            clearTimeout(firstRideHintTimeout);
            firstRideHintTimeout = null;
        }

        const options = data && typeof data === 'object' ? data : { visible: data === true };
        const visible = options.visible === true;
        hudHelp.classList.toggle('hidden', !visible);
        if (visible && Number(options.durationMs) > 0) {
            firstRideHintTimeout = setTimeout(() => setFirstRideHint(false), Number(options.durationMs));
        }
        syncGameHudVisibility();
    }

    let rentalTimerInterval = null;
    let rentalIdleDeadline = 0;
    function setRentalIdleTimer(remainingMs) {
        if (rentalTimerInterval !== null) {
            clearInterval(rentalTimerInterval);
            rentalTimerInterval = null;
        }

        const duration = Number(remainingMs);
        if (!Number.isFinite(duration) || duration <= 0) {
            rentalIdleDeadline = 0;
            rentalTimer.classList.add('hidden');
            syncGameHudVisibility();
            return;
        }

        rentalIdleDeadline = Date.now() + duration;
        rentalTimer.classList.remove('hidden');
        const update = () => {
            const seconds = Math.max(0, Math.ceil((rentalIdleDeadline - Date.now()) / 1000));
            const minutes = Math.floor(seconds / 60).toString().padStart(2, '0');
            const remainder = (seconds % 60).toString().padStart(2, '0');
            rentalTimeLeft.textContent = `${minutes}:${remainder}`;
            if (seconds === 0 && rentalTimerInterval !== null) {
                clearInterval(rentalTimerInterval);
                rentalTimerInterval = null;
            }
        };
        update();
        rentalTimerInterval = setInterval(update, 250);
        syncGameHudVisibility();
    }

    syncGameHudVisibility();

    function renderOffice(ctx) {
        document.getElementById('office-name').textContent = ctx.officeName || 'LS Taxi';

        const dutyBtn = document.getElementById('office-duty');
        if (ctx.onDuty) {
            dutyBtn.textContent = 'GO OFF DUTY';
            dutyBtn.classList.add('on-duty');
        } else {
            dutyBtn.textContent = 'GO ON DUTY';
            dutyBtn.classList.remove('on-duty');
        }

        const prog = ctx.progression || { level: 1, xp: 0, xpNeeded: 100, percent: 1 };
        document.getElementById('prog-level').textContent = prog.level;
        document.getElementById('prog-xp').textContent = Math.floor(prog.xp);
        document.getElementById('prog-xp-needed').textContent = Math.floor(prog.xpNeeded);
        document.getElementById('prog-fill').style.width = `${prog.percent}%`;

        const returnSection = document.getElementById('rental-return-section');
        if (ctx.rental) {
            returnSection.style.display = '';
            document.getElementById('rental-plate').textContent = ctx.rental.plate || '-';
        } else {
            returnSection.style.display = 'none';
        }

        const currency = ctx.currency || '$';
        const list = document.getElementById('rental-list');
        const rentable = (ctx.levels || []).filter((l) => l.vehicleModel);

        list.innerHTML = rentable
            .map((level) => {
                const locked = !level.unlocked;
                const disabled = locked || !!ctx.rental || !ctx.onDuty;
                return `
                <div class="rental-item ${locked ? 'locked' : ''}">
                    <div class="rental-item-info">
                        <div class="rental-item-name">${escapeHtml(level.vehicleLabel)}</div>
                        ${locked
                            ? `<div class="rental-item-lock">Locked &middot; Level ${level.level}</div>`
                            : `<div class="rental-item-cost">${currency}${level.vehicleRentCost}</div>`}
                    </div>
                    <button data-model="${escapeHtml(level.vehicleModel)}" data-name="${escapeHtml(level.vehicleLabel)}" data-cost="${escapeHtml(level.vehicleRentCost)}" ${disabled ? 'disabled' : ''}>RENT</button>
                </div>`;
            })
            .join('');

        list.querySelectorAll('button[data-model]').forEach((btn) => {
            btn.addEventListener('click', () => {
                openConfirmation({
                    title: 'CONFIRM TAXI RENTAL',
                    message: `RENT ${btn.dataset.name} FOR ${currency}${Number(btn.dataset.cost || 0).toFixed(0)}?`,
                    consequence: 'THE RENTAL FEE WILL BE CHARGED AND THE VEHICLE WILL BE SPAWNED AT THIS OFFICE.',
                    tone: 'warning',
                    actionLabel: 'RENT TAXI',
                    run: async () => {
                        btn.disabled = true;
                        try {
                            const result = await fetchNui('office:rent', { model: btn.dataset.model });
                            if (!result || result.success !== true) {
                                btn.disabled = false;
                                throw new Error('Rental request failed');
                            }
                            return result;
                        } catch (error) {
                            btn.disabled = false;
                            throw error;
                        }
                    },
                }, btn);
            });
        });
    }

    document.getElementById('office-duty').addEventListener('click', (event) => {
        const button = event.currentTarget;
        if (!button.classList.contains('on-duty')) {
            fetchNui('office:toggleDuty');
            return;
        }
        openConfirmation({
            title: 'END TAXI SHIFT?',
            message: 'GO OFF DUTY AND CLOSE YOUR TAXI SHIFT?',
            consequence: 'THIS CAN RELEASE AN ACTIVE FARE AND REMOVE YOUR RENTED TAXI FROM THE WORLD.',
            tone: 'danger',
            actionLabel: 'GO OFF DUTY',
            run: async () => {
                const result = await fetchNui('office:toggleDuty');
                if (!result || result.ok !== true) throw new Error('Duty request failed');
                await new Promise((resolve) => setTimeout(resolve, 250));
                if (button.isConnected && button.classList.contains('on-duty')) {
                    throw new Error('Duty change was not confirmed');
                }
                return result;
            },
        }, button);
    });

    document.getElementById('office-return').addEventListener('click', (event) => {
        const button = event.currentTarget;
        const plate = document.getElementById('rental-plate').textContent || 'ACTIVE RENTAL';
        openConfirmation({
            title: 'RETURN RENTED TAXI?',
            message: `RETURN VEHICLE ${plate}?`,
            consequence: 'THE VEHICLE WILL BE REMOVED FROM THE WORLD AND THE RENTAL REFUND WILL BE PROCESSED.',
            tone: 'danger',
            actionLabel: 'RETURN TAXI',
            run: () => fetchNui('office:returnRental'),
        }, button);
    });

    document.getElementById('office-close').addEventListener('click', () => {
        if (activeConfirmation && !activeConfirmation.processing) closeConfirmation(false);
        office.classList.add('hidden');
        syncGameHudVisibility();
        fetchNui('office:close');
    });

    window.addEventListener('keydown', (e) => {
        if (activeConfirmation) {
            if (e.key === 'Escape' || e.key === 'Backspace') {
                e.preventDefault();
                e.stopImmediatePropagation();
                if (!activeConfirmation.processing) closeConfirmation();
                return;
            }
            if (e.key === 'Tab') {
                e.preventDefault();
                if (activeConfirmation.processing) {
                    confirmStatus.focus();
                } else if (document.activeElement === confirmCancel && !e.shiftKey) {
                    confirmAccept.focus();
                } else {
                    confirmCancel.focus();
                }
                return;
            }
            return;
        }
        if (e.code === 'Escape' || e.code === 'Backspace') {
            if (!office.classList.contains('hidden')) {
                office.classList.add('hidden');
            }
            syncGameHudVisibility();
            fetchNui('escape');
        }
    });

    // ============================================================
    // System decorator strip (real FPS via frame timing, real ping
    // via a lightweight server round-trip, in-game clock)
    // ============================================================

    let frames = 0;
    let fpsWindowStart = performance.now();
    function tickFps() {
        frames += 1;
        const now = performance.now();
        if (now - fpsWindowStart >= 1000) {
            document.getElementById('sys-fps').textContent = frames;
            frames = 0;
            fpsWindowStart = now;
        }
        requestAnimationFrame(tickFps);
    }
    requestAnimationFrame(tickFps);

    // ============================================================
    // NUI message router
    // ============================================================

    window.addEventListener('message', (event) => {
        const { action, data } = event.data || {};
        switch (action) {
            case 'setVisible':
                meter.classList.toggle('hidden', !data);
                if (data) setFirstRideHint(false);
                else if (activeConfirmation && !activeConfirmation.processing) closeConfirmation(false);
                syncGameHudVisibility();
                break;
            case 'meterAvailable':
                meterAvailable = data === true;
                if (!meterAvailable) setFirstRideHint(false);
                syncGameHudVisibility();
                break;
            case 'setData':
                setData(data);
                break;
            case 'openOffice':
                office.classList.remove('hidden');
                setFirstRideHint(false);
                renderOffice(data);
                syncGameHudVisibility();
                break;
            case 'closeOffice':
                if (activeConfirmation && !activeConfirmation.processing) closeConfirmation(false);
                office.classList.add('hidden');
                syncGameHudVisibility();
                break;
            case 'firstRideHint':
                setFirstRideHint(data);
                break;
            case 'rentalIdleTimer':
                setRentalIdleTimer(data);
                break;
            case 'sysinfo':
                if (data.ping !== undefined) document.getElementById('sys-ping').textContent = `${data.ping}ms`;
                if (data.clock) document.getElementById('sys-clock').textContent = data.clock;
                break;
        }
    });
})();
