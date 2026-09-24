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
            backdrop.className = 'cm-modal-backdrop cm-style-modal-backdrop';

            const safeBodyHtml = CMUI.safeText(options.message || 'Are you sure?').replace(/\n/g, '<br>');

            backdrop.innerHTML = `
                <div class="cm-modal cm-style-modal">
                    <div class="cm-modal-header cm-style-modal__title">${CMUI.safeText(options.title || 'Confirm')}</div>
                    <div class="cm-modal-body cm-style-modal__body">${safeBodyHtml}</div>
                    <div class="cm-modal-actions cm-style-actions">
                        <button type="button" class="cm-btn cm-btn-secondary cm-style-btn cm-style-btn--secondary" data-cancel>${CMUI.safeText(options.cancelText || 'Cancel')}</button>
                        <button type="button" class="cm-btn ${options.danger ? 'cm-btn-danger cm-style-btn--danger' : 'cm-btn-yellow cm-style-btn--yellow'} cm-style-btn" data-confirm>${CMUI.safeText(options.confirmText || 'Confirm')}</button>
                    </div>
                </div>
            `;

            document.body.appendChild(backdrop);

            let settled = false;
            function finish(result) {
                if (settled) return;
                settled = true;
                window.removeEventListener('keydown', onKeyDown, true);
                if (backdrop.parentNode) backdrop.remove();
                resolve(result);
            }

            function onKeyDown(event) {
                if (event.key === 'Escape') {
                    event.preventDefault();
                    event.stopPropagation();
                    finish(false);
                }
            }
            window.addEventListener('keydown', onKeyDown, true);

            const cancelBtn = backdrop.querySelector('[data-cancel]');
            const confirmBtn = backdrop.querySelector('[data-confirm]');

            if (cancelBtn) {
                cancelBtn.addEventListener('click', function () {
                    finish(false);
                });
                cancelBtn.focus();
            }

            if (confirmBtn) {
                confirmBtn.addEventListener('click', function () {
                    finish(true);
                });
            }
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

    // ── cm-interact: "Press [key]" prompt, reusable from any NUI page ──────
    // Backed by cm-ui/client/interact.lua (exports ShowInteract/HideInteract).
    function ensureInteract() {
        var el = document.querySelector('.cm-interact');
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
        var el = document.querySelector('.cm-dialogue');
        return !!(el && !el.hidden);
    }

    CMUI.showInteract = function (options) {
        // Never show the interact prompt while the cinematic dialogue is
        // open on top of it -- callers don't need to track dialogue state
        // themselves to avoid this, it's handled here in one place.
        if (isDialogueOpen()) return;
        options = options || {};
        var el = ensureInteract();
        el.querySelector('.cm-interact__key').textContent = options.key || 'E';
        el.querySelector('.cm-interact__label').textContent = options.label || 'INTERACTION';
        el.querySelector('.cm-interact__identity').textContent = [options.name, options.role].filter(Boolean).join(' · ');
        el.hidden = false;
    };

    CMUI.hideInteract = function () {
        var el = document.querySelector('.cm-interact');
        if (el) el.hidden = true;
    };

    // ── cm-dialogue: cinematic NPC dialogue, reusable from any NUI page ────
    // Backed by cm-ui/client/dialogue.lua (exports OpenNpcDialogue/
    // NpcDialogueRespond/NpcDialogueRestoreChoices/CancelNpcDialogue).
    // Choices carry an `event` name (TriggerEvent'd back on the caller's own
    // client) instead of a Lua function, so this stays safe to call from any
    // resource via exports (Lua closures do not marshal across resources).
    var dialogueState = { choices: [], deferChoices: false, serviceLabel: '' };

    function ensureDialogue() {
        var el = document.querySelector('.cm-dialogue');
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
            var optionsBox = el.querySelector('.cm-dialogue__service-options');
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
            var button = event.target.closest('[data-cm-dialogue-choice]');
            if (!button) return;
            CMUI.postNui('cmDialogueChoice', { choice: button.dataset.cmDialogueChoice });
        });

        return el;
    }

    CMUI.openDialogue = function (options) {
        options = options || {};
        CMUI.hideInteract();
        var el = ensureDialogue();
        el.className = 'cm-dialogue';
        el.querySelector('.cm-dialogue__role').textContent = options.role || 'CM FRAMEWORK';
        el.querySelector('.cm-dialogue__name').textContent = options.name || 'NPC';
        el.querySelector('.cm-dialogue__text').textContent = options.quote || 'How can I help you?';
        el.querySelector('.cm-dialogue__signature').textContent = '— ' + (options.name || 'NPC');

        var continueBtn = el.querySelector('.cm-dialogue__continue');
        continueBtn.textContent = options.continueLabel || 'Continue';

        var choices = Array.isArray(options.choices) ? options.choices : [];
        dialogueState = {
            choices: choices,
            deferChoices: options.deferChoices === true,
            serviceLabel: options.serviceLabel || 'Please choose an option.'
        };

        var optionsBox = el.querySelector('.cm-dialogue__service-options');
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
        var el = document.querySelector('.cm-dialogue');
        if (!el) return;
        el.className = 'cm-dialogue cm-dialogue--response' + (options.tone ? ' cm-dialogue--' + options.tone : '');
        el.querySelector('.cm-dialogue__text').textContent = options.message || '';
    };

    CMUI.dialogueRestoreChoices = function (options) {
        options = options || {};
        var el = document.querySelector('.cm-dialogue');
        if (!el) return;
        el.className = 'cm-dialogue';
        el.querySelector('.cm-dialogue__service-options').hidden = false;
        el.querySelector('.cm-dialogue__close').hidden = false;
        el.querySelector('.cm-dialogue__text').textContent = options.quote || dialogueState.serviceLabel || 'Please choose an option.';
    };

    CMUI.closeDialogue = function () {
        var el = document.querySelector('.cm-dialogue');
        if (el) el.hidden = true;
    };

    // Esc dismisses the open cinematic dialogue the same way the "I'm not
    // interested right now" button does (fires closeEvent, no choice/continue).
    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        if (!isDialogueOpen()) return;
        CMUI.closeDialogue();
        CMUI.postNui('cmDialogueClose');
    });

    window.CMUI = CMUI;
})();
