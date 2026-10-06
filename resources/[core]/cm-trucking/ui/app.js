// CM Trucking Freight HUD Controller
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;

    const hud = document.getElementById('trucking-hud');
    if (!hud) return;

    if (data.action === 'show') {
        hud.style.display = 'block';
    } else if (data.action === 'hide') {
        hud.style.display = 'none';
    } else if (data.action === 'update') {
        hud.style.display = 'block';

        const contractTitle = document.getElementById('contract-title');
        if (contractTitle) {
            contractTitle.textContent = data.contractLabel || 'Commercial Freight Run';
        }

        const cargoDesc = document.getElementById('cargo-desc');
        if (cargoDesc) {
            cargoDesc.textContent = data.cargo || 'General Cargo';
        }

        const cargoClassTag = document.getElementById('cargo-class-tag');
        if (cargoClassTag) {
            const cls = (data.cargoClass || 'GENERAL').toUpperCase();
            cargoClassTag.textContent = cls;
            cargoClassTag.className = 'cargo-class-tag';
            if (cls === 'HAZARDOUS') {
                cargoClassTag.classList.add('hazardous');
            } else if (cls === 'HEAVY') {
                cargoClassTag.classList.add('heavy');
            }
        }

        const destDesc = document.getElementById('destination-desc');
        if (destDesc) {
            destDesc.textContent = data.destinationLabel || 'Distribution Depot';
        }

        const distVal = document.getElementById('distance-val');
        if (distVal) {
            distVal.textContent = `${data.distanceKm || 0.0} KM`;
        }

        const payoutVal = document.getElementById('payout-val');
        if (payoutVal) {
            const amount = Number(data.payout) || 0;
            payoutVal.textContent = `$${amount.toLocaleString()} (HELD)`;
        }

        const instructionBox = document.getElementById('instruction-box');
        const instructionText = document.getElementById('instruction-text');
        if (instructionText) {
            instructionText.textContent = data.instruction || 'PROCEED TO FREIGHT LOADING DOCK';
        }

        if (instructionBox) {
            if (data.payrollBlocked) {
                instructionBox.classList.add('blocked');
            } else {
                instructionBox.classList.remove('blocked');
            }
        }
    }
});

