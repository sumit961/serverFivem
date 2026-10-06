// cm-warehouse/ui/app.js
// NUI HUD Controller for Port Logistics & Warehouse Operations

(function () {
    const hud = document.getElementById('warehouse-hud');
    const stageStep = document.getElementById('stage-step');
    const manifestTitle = document.getElementById('manifest-title');
    const stageName = document.getElementById('stage-name');
    const progressStatusLabel = document.getElementById('progress-status-label');
    const progressPercent = document.getElementById('progress-percent');
    const progressFill = document.getElementById('progress-fill');
    const instructionText = document.getElementById('instruction-text');

    let activeProgressTimer = null;

    window.addEventListener('message', function (event) {
        const data = event.data;
        if (!data || !data.action) return;

        if (data.action === 'show' || data.action === 'update') {
            if (data.onShift) {
                hud.style.display = 'block';

                if (data.stageIndex && data.totalStages) {
                    stageStep.textContent = `STAGE ${data.stageIndex} / ${data.totalStages}`;
                } else if (data.completed) {
                    stageStep.textContent = 'COMPLETE';
                }

                if (data.manifestTitle) {
                    manifestTitle.textContent = data.manifestTitle;
                }

                if (data.stageLabel) {
                    stageName.textContent = data.stageLabel;
                }

                const percent = Math.min(100, Math.max(0, data.percent !== undefined ? data.percent : 0));
                progressPercent.textContent = `${percent}%`;
                progressFill.style.width = `${percent}%`;

                if (data.progressLabel) {
                    progressStatusLabel.textContent = data.progressLabel;
                } else {
                    progressStatusLabel.textContent = 'MANIFEST PROGRESS';
                }

                if (data.instruction) {
                    instructionText.textContent = data.instruction;
                }
            } else {
                hud.style.display = 'none';
            }
        } else if (data.action === 'stage_progress') {
            const durationMs = data.durationMs || 5000;
            const startTime = Date.now();

            progressStatusLabel.textContent = 'PHYSICAL CARGO HANDLING';

            if (activeProgressTimer) {
                clearInterval(activeProgressTimer);
            }

            activeProgressTimer = setInterval(function () {
                const elapsed = Date.now() - startTime;
                const ratio = Math.min(1.0, elapsed / durationMs);
                const pct = Math.floor(ratio * 100);

                progressPercent.textContent = `${pct}%`;
                progressFill.style.width = `${pct}%`;

                if (ratio >= 1.0) {
                    clearInterval(activeProgressTimer);
                    activeProgressTimer = null;
                }
            }, 50);
        } else if (data.action === 'hide') {
            if (activeProgressTimer) {
                clearInterval(activeProgressTimer);
                activeProgressTimer = null;
            }
            hud.style.display = 'none';
        }
    });
})();

