// cm-lumber/ui/app.js
// Shift HUD and Manifest Modal event controller for Paleto Forest Sawmill operations.

window.addEventListener('DOMContentLoaded', () => {
    const hudContainer = document.getElementById('lumber-hud');
    const haulLogsEl = document.getElementById('haul-logs');
    const totalFelledEl = document.getElementById('total-felled');
    const objectiveTextEl = document.getElementById('objective-text');

    // Summary Modal Elements
    const summaryModal = document.getElementById('shift-summary-modal');
    const summaryManifestId = document.getElementById('summary-manifest-id');
    const summaryLogs = document.getElementById('summary-logs');
    const summarySawingStatus = document.getElementById('summary-sawing-status');
    const summaryDuration = document.getElementById('summary-duration');
    const btnCloseSummary = document.getElementById('btn-close-summary');

    window.addEventListener('message', (event) => {
        const item = event.data;
        if (!item || !item.action) return;

        // 1. Shift HUD Update
        if (item.action === 'cmLumber:updateHud') {
            const data = item.data;
            if (!data || !data.visible || !data.onShift) {
                if (hudContainer) hudContainer.style.display = 'none';
                return;
            }

            if (hudContainer) hudContainer.style.display = 'block';

            if (haulLogsEl) {
                haulLogsEl.textContent = `${data.haulLogs || 0} / ${data.maxHaulLogs || 20}`;
            }

            if (totalFelledEl) {
                totalFelledEl.textContent = `${data.logsHarvested || 0}`;
            }

            if (objectiveTextEl && data.objective) {
                objectiveTextEl.textContent = data.objective;
            }
        }

        // 2. Shift Conclusion Summary Manifest
        if (item.action === 'cmLumber:shiftSummary') {
            const manifest = item.data || {};
            if (summaryModal) {
                if (summaryManifestId) {
                    summaryManifestId.textContent = manifest.manifestId || 'SHIFT MANIFEST RECORD';
                }
                if (summaryLogs) {
                    summaryLogs.textContent = `${manifest.logsHarvested || 0} Logs`;
                }
                if (summarySawingStatus) {
                    summarySawingStatus.textContent = 'HELD';
                }
                if (summaryDuration) {
                    const secs = Number(manifest.durationSeconds) || 0;
                    const mins = Math.floor(secs / 60);
                    const remSecs = secs % 60;
                    summaryDuration.textContent = mins > 0 ? `${mins}m ${remSecs}s` : `${remSecs}s`;
                }

                summaryModal.style.display = 'flex';
            }
        }
    });

    if (btnCloseSummary) {
        btnCloseSummary.addEventListener('click', () => {
            if (summaryModal) {
                summaryModal.style.display = 'none';
            }
            fetch(`https://${GetParentResourceName()}/closeSummary`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            }).catch(() => {});
        });
    }
});

