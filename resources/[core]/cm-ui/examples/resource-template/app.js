/*
    CM Resource Template Controller
    Demonstrates usage of CMUI.confirm, CMUI.toast, CMUI.bindTabs, and ESC handling.
*/
(function () {
    'use strict';

    // 1. Initialize tabs
    CMUI.bindTabs(document, {
        initial: 'overview',
        onChange: function (tabName) {
            console.log('[Template] Active tab changed to:', tabName);
        }
    });

    // 2. Demonstration toast
    const btnToast = document.getElementById('btnTestToast');
    if (btnToast) {
        btnToast.addEventListener('click', function () {
            CMUI.toast('Notification test dispatched successfully!', 'info');
        });
    }

    // 3. Normal confirmation action
    const btnSubmit = document.getElementById('btnSubmit');
    if (btnSubmit) {
        btnSubmit.addEventListener('click', async function () {
            const confirmed = await CMUI.confirm({
                title: 'CONFIRM TRANSFER',
                message: 'Authorize transfer of funds to the specified character account?',
                confirmText: 'AUTHORIZE',
                cancelText: 'CANCEL',
                danger: false
            });

            if (confirmed) {
                CMUI.toast('Transfer successfully processed.', 'success');
            }
        });
    }

    // 4. Destructive confirmation action
    const btnDestructive = document.getElementById('btnDestructive');
    if (btnDestructive) {
        btnDestructive.addEventListener('click', async function () {
            const confirmed = await CMUI.confirm({
                title: 'RESET FACILITY?',
                message: 'This action will completely wipe all facility storage and slot allocations.\n\nTHIS ACTION CANNOT BE UNDONE.',
                confirmText: 'RESET NOW',
                cancelText: 'ABORT',
                danger: true
            });

            if (confirmed) {
                CMUI.toast('Facility configuration was reset.', 'error');
            }
        });
    }

    // 5. ESC Contract: When no modal is open, ESC closes the screen
    window.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') {
            // If a modal is open, CMUI.confirm intercepts ESC during capture phase.
            // If we reach here, no modal was active:
            if (!document.querySelector('.cm-modal-backdrop')) {
                CMUI.postNui('close');
            }
        }
    });

    const btnClose = document.getElementById('btnClose');
    if (btnClose) {
        btnClose.addEventListener('click', function () {
            CMUI.postNui('close');
        });
    }
})();
