// cm-carplay web UI -- Statistics screen.
//
// Gated by the tuner chip. When installed, this is the tuner chip's actual
// tuning panel: 4 adjustable 0-100% boost values.
//
// Real NUI contract (see client/main.lua + config.lua):
//   NUI.on('updateTunerChip', installed)              -- boolean, gates this whole screen
//   NUI.post('getTunerChipValues') -> { boostPower, gearChange, acceleration, brakes }  (each 0-100)
//   NUI.post('setTunerChipValue', { type, value })     -- type one of the 4 keys above
//
// IMPORTANT judgment call: the task brief guessed this screen would show
// read-only numbers like topSpeed/handling/power/torque/weight/gears/speed,
// but no NUI callback anywhere in client/main.lua or server/main.lua returns
// any of those -- the ONLY real data source for this screen is the 4 boost
// percentages above (each capped server-side against Config.TunerChip's
// maxPercent, applied to the vehicle's own cached base handling). The CSS
// backs this reading precisely: .statistic-card's .circular-slider/
// .arc-input/.reset-btn are a per-value dial+reset control, and exactly 4
// of them (217px each + 20px gaps) fit the 944px panel width. So this
// screen is built as 4 circular dial controls, not a read-only stat sheet.
// Rather than fabricate numbers with no backing data (topSpeed/power/
// torque/weight/gears/speed), those are simply not shown.
//
// The circular ".arc-input" in the original is presumably a true
// drag-around-the-ring input; that interaction is reimplemented here as a
// plain 0-100 <input type="range"> absolutely positioned over the ring
// (same opacity:0 / full-cover box the CSS already defines for .arc-input),
// which is a straight vertical/horizontal drag rather than an angular one.
// Functionally equivalent (same NUI wiring, same value range), just not a
// pixel-for-pixel recreation of the drag gesture.

const Statistics = (() => {
    const el = document.getElementById('statistics-panel');

    const FIELDS = [
        { type: 'boostPower', titleKey: 'topSpeed', labelKey: 'boostPower', descKey: 'boostPowerDesc' },
        { type: 'acceleration', titleKey: 'acceleration', labelKey: 'acceleration', descKey: 'accelerationDesc' },
        { type: 'brakes', titleKey: 'braking', labelKey: 'brakingSpeed', descKey: 'brakingSpeedDesc' },
        { type: 'gearChange', titleKey: 'gears', labelKey: 'gearChange', descKey: 'gearChangeDesc' },
    ];

    const RADIUS = 38;
    const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

    let tunerChipInstalled = false;
    let values = { boostPower: 0, gearChange: 0, acceleration: 0, brakes: 0 };
    let visible = false;

    function ringSvg() {
        return `
            <svg width="88" height="88" viewBox="0 0 88 88">
                <circle cx="44" cy="44" r="${RADIUS}" fill="none" stroke="#ffffff26" stroke-width="6" />
                <circle class="ring-fill" cx="44" cy="44" r="${RADIUS}" fill="none" stroke="var(--color-primary)"
                    stroke-width="6" stroke-linecap="round"
                    stroke-dasharray="${CIRCUMFERENCE}" stroke-dashoffset="${CIRCUMFERENCE}"
                    transform="rotate(-90 44 44)" />
            </svg>`;
    }

    function resetIconSvg() {
        return '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 1 3 6.7"/><path d="M3 20v-5h5"/></svg>';
    }

    function statisticCard(field) {
        return `
            <div class="statistic-card" data-type="${field.type}">
                <div class="title" data-i18n="UI.statistics.${field.titleKey}"></div>
                <div class="subtitle" data-i18n="UI.statistics.${field.descKey}"></div>
                <div class="circular-slider">
                    ${ringSvg()}
                    <div class="slider-value">
                        <span class="percentage" id="stat-${field.type}-pct">0%</span>
                        <span class="label" data-i18n="UI.statistics.${field.labelKey}"></span>
                    </div>
                    <input class="arc-input" type="range" min="0" max="100" step="1" value="0" id="stat-${field.type}-input" />
                </div>
                <button class="reset-btn" id="stat-${field.type}-reset" type="button" aria-label="Reset">${resetIconSvg()}</button>
            </div>`;
    }

    // Reuses the ".tuner-required" empty-state pattern modifications.js
    // already established (same gate, same shape) for the missing-tuner-chip
    // state, just scoped to .statistics-panel.
    function buildGate() {
        return `
            <div class="tuner-required">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" width="48" height="48">
                    <rect x="5" y="5" width="14" height="14" rx="2"/>
                    <rect x="9" y="9" width="6" height="6"/>
                    <path d="M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3" stroke-linecap="round"/>
                </svg>
                <div class="tuner-required-title" data-i18n="UI.statistics.tunerChipRequired"></div>
                <div class="tuner-required-subtitle" data-i18n="UI.statistics.tunerChipDescription"></div>
            </div>`;
    }

    function render() {
        if (!tunerChipInstalled) {
            el.innerHTML = buildGate();
            applyI18n();
            return;
        }
        el.innerHTML = FIELDS.map(statisticCard).join('');
        applyI18n();
        FIELDS.forEach((field) => bindField(field));
        updateAllRings();
    }

    function applyI18n() {
        el.querySelectorAll('[data-i18n]').forEach((node) => {
            node.textContent = Locale.L(node.dataset.i18n);
        });
    }

    function updateRing(type) {
        const value = values[type] || 0;
        const pctEl = document.getElementById(`stat-${type}-pct`);
        const input = document.getElementById(`stat-${type}-input`);
        const card = el.querySelector(`.statistic-card[data-type="${type}"]`);
        if (!pctEl || !input || !card) return;
        pctEl.textContent = `${Math.round(value)}%`;
        input.value = String(value);
        const fill = card.querySelector('.ring-fill');
        if (fill) fill.setAttribute('stroke-dashoffset', String(CIRCUMFERENCE * (1 - value / 100)));
    }

    function updateAllRings() {
        FIELDS.forEach((field) => updateRing(field.type));
    }

    function bindField(field) {
        const input = document.getElementById(`stat-${field.type}-input`);
        const resetBtn = document.getElementById(`stat-${field.type}-reset`);
        if (!input || !resetBtn) return;

        input.addEventListener('input', () => {
            values[field.type] = Number(input.value);
            updateRing(field.type);
        });
        input.addEventListener('change', () => {
            NUI.post('setTunerChipValue', { type: field.type, value: values[field.type] });
        });
        resetBtn.addEventListener('click', () => {
            values[field.type] = 0;
            updateRing(field.type);
            NUI.post('setTunerChipValue', { type: field.type, value: 0 });
        });
    }

    async function refreshValues() {
        const result = await NUI.post('getTunerChipValues');
        if (result) {
            values = {
                boostPower: result.boostPower || 0,
                gearChange: result.gearChange || 0,
                acceleration: result.acceleration || 0,
                brakes: result.brakes || 0,
            };
        }
        if (tunerChipInstalled) updateAllRings();
    }

    NUI.on('updateTunerChip', (installed) => {
        const next = !!installed;
        const changed = next !== tunerChipInstalled;
        tunerChipInstalled = next;
        if (visible && changed) {
            render();
            if (tunerChipInstalled) refreshValues();
        }
    });

    document.addEventListener('localechange', () => {
        if (visible) applyI18n();
    });

    App.registerScreen('statistics', {
        el,
        onShow() {
            visible = true;
            render();
            if (tunerChipInstalled) refreshValues();
        },
        onHide() {
            visible = false;
        },
    });

    return {};
})();
