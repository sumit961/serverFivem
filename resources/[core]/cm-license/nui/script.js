/* CM License System — NUI Script */

const App = {
    currentDialog: null,
    licenses: [],
    selectedLicense: null
};

// Initialize
window.addEventListener('load', () => {
    console.log('[CM-License NUI] Initialized');
});

// Listen for messages from server
window.addEventListener('message', (event) => {
    const data = event.data;

    if (!data || !data.type) return;

    console.log('[CM-License] Message:', data.type);

    switch (data.type) {
        case 'openLicenseMenu':
            openLicenseMenu(data);
            break;
        case 'showTestConfirmation':
            showTestConfirmation(data);
            break;
        case 'showMyLicenses':
            showMyLicenses(data);
            break;
        case 'testResult':
            showTestResult(data);
            break;
        case 'openAdminMenu':
            openAdminMenu(data);
            break;
        case 'showRouteSummary':
            showRouteSummary(data);
            break;
    }
});

// Open license menu
function openLicenseMenu(data) {
    const menu = document.getElementById('licenseMenu');

    // Update prices from data if available
    if (data.licenses) {
        const buttons = menu.querySelectorAll('.option-btn[data-license]');
        buttons.forEach(btn => {
            const licenseType = btn.getAttribute('data-license');
            const license = data.licenses.find(l => l.license_type === licenseType);
            if (license) {
                const priceEl = btn.querySelector('.price');
                priceEl.textContent = '$' + formatNumber(license.price);
                priceEl.setAttribute('data-price', license.price);
            }
        });
    }

    menu.classList.remove('hidden');
    App.currentDialog = 'licenseMenu';

    // Setup event listeners
    setupLicenseMenuListeners();
}

// Setup license menu event listeners
function setupLicenseMenuListeners() {
    const buttons = document.querySelectorAll('#licenseMenu .option-btn[data-license]');
    buttons.forEach(btn => {
        btn.onclick = (e) => {
            const licenseType = btn.getAttribute('data-license');
            const price = btn.querySelector('.price').getAttribute('data-price');

            showTestConfirmation({
                licenseType: licenseType,
                price: price
            });
        };
    });

    document.getElementById('myLicensesBtn').onclick = () => {
        fetch('https://cm-license/requestMyLicenses', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    };

    document.getElementById('closeBtn').onclick = () => {
        closeDialog('licenseMenu');
        fetch('https://cm-license/closeMenu', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({})
        });
    };
}

// Show test confirmation
function showTestConfirmation(data) {
    closeDialog('licenseMenu');

    const dialog = document.getElementById('testConfirmation');
    document.getElementById('testTitle').textContent =
        (data.licenseType === 'driver' ? '🚗 ' : data.licenseType === 'boat' ? '🚤 ' : '✈️ ') +
        'License Test';
    document.getElementById('testFee').textContent = '$' + formatNumber(data.price);

    App.selectedLicense = data.licenseType;

    dialog.classList.remove('hidden');
    App.currentDialog = 'testConfirmation';

    document.getElementById('startTestBtn').onclick = () => {
        startTest(data.licenseType);
    };
}

// Start test
function startTest(licenseType) {
    closeDialog('testConfirmation');
    showLoadingScreen();

    fetch('https://cm-license/startTest', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ licenseType: licenseType })
    });
}

// Cancel test
function cancelTest() {
    closeDialog('testConfirmation');

    fetch('https://cm-license/cancelTest', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

// Show my licenses
function showMyLicenses(data) {
    closeDialog('licenseMenu');

    const dialog = document.getElementById('myLicensesDialog');
    const list = document.getElementById('licensesList');

    list.innerHTML = '';

    if (data.licenses && data.licenses.length > 0) {
        data.licenses.forEach(license => {
            const item = document.createElement('div');
            item.className = 'license-item';

            const statusClass = license.status === 'active' ? 'active' : license.status === 'expired' ? 'expired' : 'revoked';
            const statusText = license.status === 'active' ? 'ACTIVE' : license.status === 'expired' ? 'EXPIRED' : 'REVOKED';
            const expireText = license.remainingDays ? license.remainingDays + ' days' : 'Expired';

            item.innerHTML = `
                <div class="license-item-title">${license.label}</div>
                <div class="license-item-status ${statusClass}">
                    Status: ${statusText} | Expires: ${license.expiresAtDate} (${expireText})
                </div>
            `;

            list.appendChild(item);
        });
    } else {
        list.innerHTML = '<div style="padding: 20px; text-align: center; color: #8aa4b8;">No licenses yet</div>';
    }

    dialog.classList.remove('hidden');
    App.currentDialog = 'myLicensesDialog';
}

// Show test result
function showTestResult(data) {
    const dialog = document.getElementById('testResult');
    const header = document.getElementById('resultHeader');
    const message = document.getElementById('resultMessage');
    const details = document.getElementById('resultDetails');

    if (data.passed) {
        header.classList.remove('error');
        header.innerHTML = '<h1>✅ TEST PASSED</h1>';
        message.classList.remove('error');
        message.textContent = 'Congratulations! You passed your ' + (data.licenseLabel || 'license') + ' examination.';
        details.innerHTML = `
            <div style="margin-bottom: 8px;">Your license is valid for <strong>${data.validDays}</strong> days.</div>
            <div>The license item has been added to your inventory.</div>
        `;
    } else {
        header.classList.add('error');
        header.innerHTML = '<h1>❌ TEST FAILED</h1>';
        message.classList.add('error');
        message.textContent = data.failReason || 'Your test failed';
        details.innerHTML = `<div>${data.message || 'Please try again.'}</div>`;
    }

    dialog.classList.remove('hidden');
    App.currentDialog = 'testResult';

    hideLoadingScreen();
}

// Open admin menu
function openAdminMenu(data) {
    const dialog = document.getElementById('adminMenu');
    const list = document.getElementById('adminLicensesList');

    list.innerHTML = '';

    if (data.licenses && data.licenses.length > 0) {
        data.licenses.forEach(license => {
            const item = document.createElement('div');
            item.className = 'license-item';

            const status = license.enabled ? '✓ Enabled' : '✗ Disabled';
            const route = license.route ? '✓ Configured' : '✗ Not configured';

            item.innerHTML = `
                <div class="license-item-title">${license.label}</div>
                <div class="license-item-status">
                    Status: ${status} | Route: ${route} | Price: $${formatNumber(license.price)}
                </div>
                <div style="margin-top: 8px; display: flex; gap: 8px;">
                    <button class="btn btn-sm btn-primary" onclick="editLicense(${license.id})">Edit</button>
                    <button class="btn btn-sm btn-secondary" onclick="previewRoute(${license.id})">Preview</button>
                    <button class="btn btn-sm btn-danger" onclick="deleteLicense(${license.id})">Delete</button>
                </div>
            `;

            list.appendChild(item);
        });
    }

    dialog.classList.remove('hidden');
    App.currentDialog = 'adminMenu';
}

// Show loading screen
function showLoadingScreen() {
    document.getElementById('loadingScreen').classList.remove('hidden');
}

// Hide loading screen
function hideLoadingScreen() {
    document.getElementById('loadingScreen').classList.add('hidden');
}

// Show route summary
function showRouteSummary(data) {
    showLoadingScreen();

    setTimeout(() => {
        hideLoadingScreen();

        if (data.checkpoints && data.checkpoints.length > 0) {
            alert(`Route created with ${data.checkpoints.length} checkpoints`);
        } else {
            alert('Route creation cancelled');
        }
    }, 1000);
}

// Close dialog
function closeDialog(dialogId) {
    const dialog = document.getElementById(dialogId);
    if (dialog) {
        dialog.classList.add('hidden');
    }
    App.currentDialog = null;
}

// Format number with commas
function formatNumber(num) {
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

// Admin functions (stubs for callbacks)
function editLicense(licenseId) {
    console.log('Edit license:', licenseId);
    // Send callback to server
}

function previewRoute(licenseId) {
    console.log('Preview route:', licenseId);
    // Send callback to server
}

function deleteLicense(licenseId) {
    if (confirm('Are you sure? This cannot be undone.')) {
        console.log('Delete license:', licenseId);
        // Send callback to server
    }
}

function createNewLicense() {
    document.getElementById('adminMenu').classList.add('hidden');
    document.getElementById('licenseEditor').classList.remove('hidden');
    App.currentDialog = 'licenseEditor';
}

function nextStep() {
    console.log('Next step in license creation');
    // Send to server
}

function previewVehicle() {
    console.log('Preview vehicle');
    // Send to server
}

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (App.currentDialog) {
            closeDialog(App.currentDialog);
            fetch('https://cm-license/closeMenu', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
        }
    }
});

console.log('[CM-License NUI] Script loaded');
