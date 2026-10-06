// cm-courier/ui/app.js
// NUI HUD Controller for Municipal Courier & Parcel Delivery Operations

(function () {
    const hud = document.getElementById('courier-hud');
    const stopStep = document.getElementById('stop-step');
    const manifestTitle = document.getElementById('manifest-title');
    const stopName = document.getElementById('stop-name');
    const recipientName = document.getElementById('recipient-name');
    const progressStatusLabel = document.getElementById('progress-status-label');
    const progressPercent = document.getElementById('progress-percent');
    const progressFill = document.getElementById('progress-fill');
    const instructionText = document.getElementById('instruction-text');
    const payoutText = document.getElementById('payout-text');

    let activeProgressTimer = null;

    window.addEventListener('message', function (event) {
        const data = event.data;
        if (!data || !data.action) return;

        if (data.action === 'show' || data.action === 'update') {
            if (data.onRoute) {
                hud.style.display = 'block';

                if (data.parcelsTotal !== undefined && data.parcelsDelivered !== undefined) {
                    if (data.allDelivered) {
                        stopStep.textContent = 'ALL DELIVERED';
                    } else if (!data.isLoaded) {
                        stopStep.textContent = `PARCELS 0 / ${data.parcelsTotal}`;
                    } else {
                        stopStep.textContent = `DROP ${data.stopIndex || 1} / ${data.totalStops || data.parcelsTotal}`;
                    }
                }

                if (data.routeTitle) {
                    manifestTitle.textContent = data.routeTitle;
                }

                if (data.stopLabel) {
                    stopName.textContent = data.stopLabel;
                }

                if (data.recipient) {
                    recipientName.textContent = `Consignee: ${data.recipient}`;
                }

                const percent = Math.min(100, Math.max(0, data.percent !== undefined ? data.percent : 0));
                progressPercent.textContent = `${percent}%`;
                progressFill.style.width = `${percent}%`;

                if (data.progressLabel) {
                    progressStatusLabel.textContent = data.progressLabel;
                } else {
                    progressStatusLabel.textContent = 'ROUTE PROGRESS';
                }

                if (data.payoutStatus) {
                    payoutText.textContent = data.payoutStatus;
                }

                if (data.instruction) {
                    instructionText.textContent = data.instruction;
                }
            } else {
                hud.style.display = 'none';
            }
        } else if (data.action === 'progress_start') {
            const durationMs = data.durationMs || 3500;
            const startTime = Date.now();
            const originalLabel = progressStatusLabel.textContent;

            progressStatusLabel.textContent = data.label || 'PROCESSING PARCEL...';

            if (activeProgressTimer) {
                clearInterval(activeProgressTimer);
            }

            activeProgressTimer = setInterval(() => {
                const elapsed = Date.now() - startTime;
                const ratio = Math.min(1, elapsed / durationMs);
                const percent = Math.floor(ratio * 100);

                progressPercent.textContent = `${percent}%`;
                progressFill.style.width = `${percent}%`;

                if (ratio >= 1) {
                    clearInterval(activeProgressTimer);
                    activeProgressTimer = null;
                    progressStatusLabel.textContent = originalLabel;
                }
            }, 50);
        } else if (data.action === 'hide') {
            hud.style.display = 'none';
            if (activeProgressTimer) {
                clearInterval(activeProgressTimer);
                activeProgressTimer = null;
            }
        }
    });
})();

