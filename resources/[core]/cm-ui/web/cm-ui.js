/* CM Framework UI helper v1.0.0 */
(function () {
    'use strict';

    const CMUI = window.CMUI || {};

    CMUI.version = '1.0.0';

    CMUI.qs = function (selector, root) {
        return (root || document).querySelector(selector);
    };

    CMUI.qsa = function (selector, root) {
        return Array.from((root || document).querySelectorAll(selector));
    };

    CMUI.el = function (tag, className, content) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (content !== undefined && content !== null) node.textContent = String(content);
        return node;
    };

    CMUI.safeText = function (value) {
        if (value === undefined || value === null) return '';
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    };

    CMUI.formatMoney = function (amount) {
        const value = Number(amount || 0);
        return '$' + value.toLocaleString('en-US');
    };

    CMUI.postNui = function (eventName, payload) {
        const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nui-resource';
        return fetch(`https://${resource}/${eventName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload || {})
        }).catch(function () { return null; });
    };

    CMUI.toast = function (message, type, timeout) {
        type = type || 'info';
        timeout = timeout || 3500;

        let stack = document.querySelector('.cm-toast-stack');
        if (!stack) {
            stack = document.createElement('div');
            stack.className = 'cm-toast-stack';
            document.body.appendChild(stack);
        }

        const toast = document.createElement('div');
        toast.className = `cm-toast cm-toast-${type}`;
        toast.textContent = message || '';
        stack.appendChild(toast);

        setTimeout(function () {
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(12px)';
            setTimeout(function () { toast.remove(); }, 180);
        }, timeout);

        return toast;
    };

    CMUI.confirm = function (options) {
        options = options || {};
        return new Promise(function (resolve) {
            const backdrop = document.createElement('div');
            backdrop.className = 'cm-modal-backdrop';

            backdrop.innerHTML = `
                <div class="cm-modal">
                    <div class="cm-modal-header">${CMUI.safeText(options.title || 'Confirm')}</div>
                    <div class="cm-modal-body">${CMUI.safeText(options.message || 'Are you sure?')}</div>
                    <div class="cm-modal-actions">
                        <button class="cm-btn cm-btn-secondary" data-cancel>${CMUI.safeText(options.cancelText || 'Cancel')}</button>
                        <button class="cm-btn ${options.danger ? 'cm-btn-danger' : ''}" data-confirm>${CMUI.safeText(options.confirmText || 'Confirm')}</button>
                    </div>
                </div>
            `;

            document.body.appendChild(backdrop);

            backdrop.querySelector('[data-cancel]').addEventListener('click', function () {
                backdrop.remove();
                resolve(false);
            });

            backdrop.querySelector('[data-confirm]').addEventListener('click', function () {
                backdrop.remove();
                resolve(true);
            });
        });
    };

    CMUI.bindTabs = function (root, options) {
        root = root || document;
        options = options || {};

        const tabs = Array.from(root.querySelectorAll('[data-cm-tab]'));
        const panels = Array.from(root.querySelectorAll('[data-cm-panel]'));

        function activate(name) {
            tabs.forEach(function (tab) {
                tab.classList.toggle('cm-active', tab.dataset.cmTab === name);
            });
            panels.forEach(function (panel) {
                panel.classList.toggle('cm-hidden', panel.dataset.cmPanel !== name);
            });
            if (typeof options.onChange === 'function') options.onChange(name);
        }

        tabs.forEach(function (tab) {
            tab.addEventListener('click', function () {
                activate(tab.dataset.cmTab);
            });
        });

        const active = options.initial || (tabs[0] && tabs[0].dataset.cmTab);
        if (active) activate(active);

        return { activate: activate };
    };

    CMUI.setVisible = function (visible, bodyBackground) {
        document.body.classList.toggle('cm-hidden', !visible);
        document.body.classList.toggle('cm-body-visible', !!bodyBackground);
    };

    CMUI.applyTheme = function (vars) {
        if (!vars || typeof vars !== 'object') return;
        Object.keys(vars).forEach(function (key) {
            document.documentElement.style.setProperty(key, vars[key]);
        });
    };

    window.CMUI = CMUI;
})();
