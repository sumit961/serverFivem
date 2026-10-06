// CM Garbage Job HUD
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    const hud = document.getElementById('garbage-hud');
    if (!hud) return;

    if (data.action === 'show') {
        hud.style.display = 'block';
    } else if (data.action === 'hide') {
        hud.style.display = 'none';
    } else if (data.action === 'update') {
        hud.style.display = 'block';

        const routeStep = document.getElementById('route-step');
        if (routeStep) {
            routeStep.textContent = `STOP ${data.stopIndex || 1} / ${data.totalStops || 8}`;
        }

        const stopName = document.getElementById('stop-name');
        if (stopName) {
            stopName.textContent = data.stopLabel || 'Curbside Collection';
        }

        const capacityText = document.getElementById('capacity-text');
        if (capacityText) {
            capacityText.textContent = `${data.bagsInTruck || 0} / ${data.maxCapacity || 16} (${data.percent || 0}%)`;
        }

        const progressFill = document.getElementById('progress-fill');
        if (progressFill) {
            progressFill.style.width = `${Math.min(100, Math.max(0, data.percent || 0))}%`;
            if (data.truckFull) {
                progressFill.classList.add('full');
            } else {
                progressFill.classList.remove('full');
            }
        }

        const instructionText = document.getElementById('instruction-text');
        if (instructionText) {
            instructionText.textContent = data.instruction || 'PROCEED TO COLLECTION STOP';
        }
    }
});

