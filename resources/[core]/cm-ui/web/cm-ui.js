/*
    CM Framework UI Kernel Helper v2.0.1
    Authoritative shared UI runtime logic for all CM FiveM NUI resources.
*/
(function () {
    'use strict';

    const CMUI = window.CMUI || {};

    CMUI.version = '2.0.1';

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

    /* ── Authoritative Toast System (Bottom-Left) ────────── */
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
        toast.textContent = String(message || '');
        stack.appendChild(toast);

        setTimeout(function () {
            toast.style.opacity = '0';
            toast.style.transform = 'translateY(10px)';
            setTimeout(function () {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
            }, 180);
        }, timeout);

        return toast;
    };

    /* ── Authoritative Confirmation Modal System (v2.0.1) ─────────── */
    const confirmQueue = [];
    let activeConfirm = null;

    function processConfirmQueue() {
        if (activeConfirm || confirmQueue.length === 0) {
            return;
        }

        const item = confirmQueue.shift();
        const options = item.options || {};
        const resolve = item.resolve;

        const backdrop = document.createElement('div');
        backdrop.className = 'cm-modal-backdrop cm-style-modal-backdrop';

        const title = CMUI.safeText(options.title || options.header || 'CONFIRM ACTION');
        const safeBodyHtml = CMUI.safeText(options.message || options.content || 'Are you sure you want to proceed?').replace(/\n/g, '<br>');
        const confirmText = CMUI.safeText(options.confirmText || (options.labels && options.labels.confirm) || 'CONFIRM');
        const cancelText = CMUI.safeText(options.cancelText || (options.labels && options.labels.cancel) || 'CANCEL');
        const isDanger = options.danger === true || options.destructive === true || (options.tone === 'danger');
        const confirmClass = isDanger ? 'cm-btn-danger cm-style-btn--danger' : 'cm-btn-yellow cm-style-btn--yellow';
        const dismissOnBackdrop = options.dismissOnBackdrop !== false;

        backdrop.innerHTML = `
            <div class="cm-modal cm-style-modal" role="dialog" aria-modal="true">
                <div class="cm-modal-header cm-style-modal__title">${title}</div>
                <div class="cm-modal-body cm-style-modal__body">${safeBodyHtml}</div>
                <div class="cm-modal-actions cm-style-actions">
                    <button type="button" class="cm-btn cm-btn-secondary cm-style-btn cm-style-btn--secondary" data-cm-cancel>${cancelText}</button>
                    <button type="button" class="cm-btn ${confirmClass} cm-style-btn" data-cm-confirm>${confirmText}</button>
                </div>
            </div>
        `;

        document.body.appendChild(backdrop);

        let settled = false;

        function finish(result) {
            if (settled) return;
            settled = true;

            // Clean up event listeners
            window.removeEventListener('keydown', onKeyDown, true);
            backdrop.removeEventListener('click', onBackdropClick);

            // Clean up DOM
            if (backdrop.parentNode) {
                backdrop.parentNode.removeChild(backdrop);
            }

            activeConfirm = null;

            // Resolve Promise exactly once, then advance queued confirmations
            try {
                resolve(result === true);
            } finally {
                processConfirmQueue();
            }
        }

        function onKeyDown(event) {
            if (event.key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                finish(false);
            }
        }

        function onBackdropClick(event) {
            // Dismiss only when clicking directly on the backdrop, not inside .cm-modal
            if (event.target === backdrop) {
                event.preventDefault();
                event.stopPropagation();
                if (dismissOnBackdrop) {
                    finish(false);
                }
            }
        }

        // Capture phase ensures we intercept Escape before parent screens close
        window.addEventListener('keydown', onKeyDown, true);
        backdrop.addEventListener('click', onBackdropClick);

        const cancelBtn = backdrop.querySelector('[data-cm-cancel]');
        const confirmBtn = backdrop.querySelector('[data-cm-confirm]');

        if (cancelBtn) {
            cancelBtn.addEventListener('click', function (e) {
                e.stopPropagation();
                finish(false);
            });
            // Crucial usability contract: Cancel receives default focus!
            cancelBtn.focus();
        }

        if (confirmBtn) {
            confirmBtn.addEventListener('click', function (e) {
                e.stopPropagation();
                finish(true);
            });
        }

        activeConfirm = {
            backdrop: backdrop,
            resolve: resolve,
            settled: function () { return settled; },
            finish: finish
        };
    }

    CMUI.confirm = function (options) {
        return new Promise(function (resolve) {
            confirmQueue.push({
                options: options || {},
                resolve: resolve
            });
            processConfirmQueue();
        });
    };

    CMUI.cancelAllConfirms = function () {
        while (confirmQueue.length > 0) {
            const queued = confirmQueue.shift();
            try {
                queued.resolve(false);
            } catch (e) {}
        }
        if (activeConfirm) {
            activeConfirm.finish(false);
        }
    };

    /* ── Tab Binding Utility ─────────────────────────────── */
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

    /* ── cm-interact: "Press [key]" prompt ────────────────── */
    function ensureInteract() {
        let el = document.querySelector('.cm-interact');
        if (el) return el;
        el = document.createElement('aside');
        el.className = 'cm-interact';
        el.hidden = true;
        el.innerHTML =
            '<span class="cm-interact__key"></span>' +
            '<span class="cm-interact__line"></span>' +
            '<span class="cm-interact__copy"><b class="cm-interact__label"></b><small class="cm-interact__identity"></small></span>';
        document.body.appendChild(el);
        return el;
    }

    function isDialogueOpen() {
        const el = document.querySelector('.cm-dialogue');
        return !!(el && !el.hidden);
    }

    CMUI.showInteract = function (options) {
        if (isDialogueOpen()) return;
        options = options || {};
        const el = ensureInteract();
        el.querySelector('.cm-interact__key').textContent = options.key || 'E';
        el.querySelector('.cm-interact__label').textContent = options.label || 'INTERACTION';
        el.querySelector('.cm-interact__identity').textContent = [options.name, options.role].filter(Boolean).join(' · ');
        el.hidden = false;
    };

    CMUI.hideInteract = function () {
        const el = document.querySelector('.cm-interact');
        if (el) el.hidden = true;
    };

    /* ── cm-dialogue: cinematic NPC dialogue ─────────────── */
    let dialogueState = { choices: [], deferChoices: false, serviceLabel: '' };

    function ensureDialogue() {
        let el = document.querySelector('.cm-dialogue');
        if (el) return el;
        el = document.createElement('section');
        el.className = 'cm-dialogue';
        el.hidden = true;
        el.innerHTML =
            '<div class="cm-dialogue__identity"><small class="cm-dialogue__role"></small><h1 class="cm-dialogue__name"></h1></div>' +
            '<div class="cm-dialogue__choices">' +
            '<div class="cm-dialogue__quote"><p class="cm-dialogue__text"></p><span class="cm-dialogue__signature"></span></div>' +
            '<div class="cm-dialogue__service-options" hidden></div>' +
            '<button type="button" class="cm-dialogue__option cm-dialogue__option--primary cm-dialogue__continue">Continue</button>' +
            '<button type="button" class="cm-dialogue__option cm-dialogue__close">I’m not interested right now</button>' +
            '</div>';
        document.body.appendChild(el);

        el.querySelector('.cm-dialogue__continue').addEventListener('click', function () {
            const optionsBox = el.querySelector('.cm-dialogue__service-options');
            if (dialogueState.deferChoices && optionsBox.hidden) {
                optionsBox.hidden = false;
                el.querySelector('.cm-dialogue__text').textContent = dialogueState.serviceLabel || 'Please choose an option.';
                CMUI.postNui('cmDialogueStage', { stage: 'services' });
                return;
            }
            CMUI.postNui('cmDialogueContinue');
        });

        el.querySelector('.cm-dialogue__close').addEventListener('click', function () {
            CMUI.closeDialogue();
            CMUI.postNui('cmDialogueClose');
        });

        el.querySelector('.cm-dialogue__service-options').addEventListener('click', function (event) {
            const button = event.target.closest('[data-cm-dialogue-choice]');
            if (!button) return;
            CMUI.postNui('cmDialogueChoice', { choice: button.dataset.cmDialogueChoice });
        });

        return el;
    }

    CMUI.openDialogue = function (options) {
        options = options || {};
        CMUI.hideInteract();
        const el = ensureDialogue();
        el.className = 'cm-dialogue';
        el.querySelector('.cm-dialogue__role').textContent = options.role || 'CM FRAMEWORK';
        el.querySelector('.cm-dialogue__name').textContent = options.name || 'NPC';
        el.querySelector('.cm-dialogue__text').textContent = options.quote || 'How can I help you?';
        el.querySelector('.cm-dialogue__signature').textContent = '— ' + (options.name || 'NPC');

        const continueBtn = el.querySelector('.cm-dialogue__continue');
        continueBtn.textContent = options.continueLabel || 'Continue';

        const choices = Array.isArray(options.choices) ? options.choices : [];
        dialogueState = {
            choices: choices,
            deferChoices: options.deferChoices === true,
            serviceLabel: options.serviceLabel || 'Please choose an option.'
        };

        const optionsBox = el.querySelector('.cm-dialogue__service-options');
        if (choices.length > 0) {
            optionsBox.innerHTML = choices.map(function (choice) {
                return '<button type="button" class="cm-dialogue__option" data-cm-dialogue-choice="' + CMUI.safeText(choice.id) + '">' +
                    '<b>' + CMUI.safeText(choice.label || choice.id) + '</b>' +
                    (choice.description ? '<small>' + CMUI.safeText(choice.description) + '</small>' : '') +
                    '</button>';
            }).join('');
            optionsBox.hidden = dialogueState.deferChoices;
        } else {
            optionsBox.innerHTML = '';
            optionsBox.hidden = true;
        }

        continueBtn.hidden = choices.length > 0 && !dialogueState.deferChoices;
        el.querySelector('.cm-dialogue__close').hidden = false;
        el.hidden = false;
    };

    CMUI.dialogueResponse = function (options) {
        options = options || {};
        const el = document.querySelector('.cm-dialogue');
        if (!el) return;
        el.className = 'cm-dialogue cm-dialogue--response' + (options.tone ? ' cm-dialogue--' + options.tone : '');
        el.querySelector('.cm-dialogue__text').textContent = options.message || '';
    };

    CMUI.dialogueRestoreChoices = function (options) {
        options = options || {};
        const el = document.querySelector('.cm-dialogue');
        if (!el) return;
        el.className = 'cm-dialogue';
        el.querySelector('.cm-dialogue__service-options').hidden = false;
        el.querySelector('.cm-dialogue__close').hidden = false;
        el.querySelector('.cm-dialogue__text').textContent = options.quote || dialogueState.serviceLabel || 'Please choose an option.';
    };

    CMUI.closeDialogue = function () {
        const el = document.querySelector('.cm-dialogue');
        if (el) el.hidden = true;
    };

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        if (!isDialogueOpen()) return;
        CMUI.closeDialogue();
        CMUI.postNui('cmDialogueClose');
    });

    window.CMUI = CMUI;
})();
