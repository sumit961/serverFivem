// CM Recycling & Salvage Operations HUD
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    const hud = document.getElementById('recycling-hud');
    if (!hud) return;

    if (data.action === 'show') {
        hud.style.display = 'block';
    } else if (data.action === 'hide') {
        hud.style.display = 'none';
    } else if (data.action === 'update') {
        hud.style.display = 'block';

        const cycleStep = document.getElementById('cycle-step');
        if (cycleStep) {
            if (data.sortingInProgress) {
                cycleStep.textContent = 'SORTING';
            } else if (data.unloadedAtFacility) {
                cycleStep.textContent = 'PROCESS';
            } else if (data.allPickupsComplete) {
                cycleStep.textContent = 'UNLOAD';
            } else {
                cycleStep.textContent = `SITE ${data.stopIndex || 1} / ${data.totalStops || 5}`;
            }
        }

        const siteName = document.getElementById('site-name');
        if (siteName) {
            if (data.sortingInProgress) {
                siteName.textContent = 'Material Separator & Hopper';
            } else if (data.unloadedAtFacility) {
                siteName.textContent = 'Rogers Salvage Sorting Station';
            } else if (data.allPickupsComplete) {
                siteName.textContent = 'Rogers Salvage Unloading Bay';
            } else {
                siteName.textContent = data.stopLabel || 'Salvage Location';
            }
        }

        const materialName = document.getElementById('material-name');
        if (materialName) {
            if (data.sortingInProgress) {
                materialName.textContent = 'Separating: Metal Scrap & Polymers';
            } else if (data.unloadedAtFacility) {
                materialName.textContent = 'Awaiting mechanical separation table';
            } else if (data.allPickupsComplete) {
                materialName.textContent = 'Full salvage load ready for intake hopper';
            } else {
                materialName.textContent = `Target: ${data.material || 'Scrap Material'}`;
            }
        }

        const capacityText = document.getElementById('capacity-text');
        if (capacityText) {
            if (data.unloadedAtFacility || data.sortingInProgress) {
                capacityText.textContent = `UNLOADED (IN HOPPER)`;
            } else {
                capacityText.textContent = `${data.bundlesInTruck || 0} / ${data.maxBundles || 10} (${data.percent || 0}%)`;
            }
        }

        const progressFill = document.getElementById('progress-fill');
        if (progressFill) {
            if (data.sortingInProgress) {
                progressFill.style.width = '100%';
                progressFill.classList.add('processing');
                progressFill.classList.remove('full');
            } else if (data.unloadedAtFacility) {
                progressFill.style.width = '100%';
                progressFill.classList.add('processing');
                progressFill.classList.remove('full');
            } else {
                const pct = Math.min(100, Math.max(0, data.percent || 0));
                progressFill.style.width = `${pct}%`;
                progressFill.classList.remove('processing');
                if (pct >= 100) {
                    progressFill.classList.add('full');
                } else {
                    progressFill.classList.remove('full');
                }
            }
        }

        const instructionText = document.getElementById('instruction-text');
        if (instructionText) {
            instructionText.textContent = data.instruction || 'PROCEED TO SALVAGE PICKUP POINT';
        }
    }
});

