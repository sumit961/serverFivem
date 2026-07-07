// cm-chat/ui/app.js
// Always-visible modular RP chat UI. Only the input/tabs/actions hide when chat is closed.

let MAX_CHAT_MESSAGES = 45;

let state = {
    open: false,
    activeChannel: 'rp',
    channels: [
        { id: 'rp', label: 'RP', color: '#31e6ff', format: 'rp' },
        { id: 'nonrp', label: 'NON-RP', color: '#9bb8c8', format: 'nonrp' }
    ],
    actions: [
        { id: 'me', label: 'ME', command: '/me ' },
        { id: 'do', label: 'DO', command: '/do ' },
        { id: 'try', label: 'TRY', command: '/try ' }
    ],
    messages: [],
    actionsOpen: false
};

let els = {};
let history = [];
let historyIndex = -1;
let seq = 0;
let suppressOpenKey = false;

const COLOR_NAMES = {
    cyan: '#31e6ff', blue: '#188cff', green: '#72ff8c', lime: '#72ff8c',
    red: '#ff5b5b', orange: '#ffad4d', yellow: '#ffe35b', purple: '#b889ff',
    pink: '#ff5cf7', white: '#ffffff', grey: '#9bb8c8', gray: '#9bb8c8'
};

function cacheEls() {
    if (els.ready) return;
    els.root = document.getElementById('chat-root');
    els.messages = document.getElementById('chat-messages');
    els.controls = document.getElementById('chat-controls');
    els.tabs = document.getElementById('chat-tabs');
    els.input = document.getElementById('chat-input');
    els.submit = document.getElementById('chat-submit');
    els.actionsToggle = document.getElementById('actions-toggle');
    els.actions = document.getElementById('chat-actions');
    els.ready = true;
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, (char) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
    }[char]));
}

function sanitizeText(value) {
    return String(value ?? '')
        .replace(/[\r\n\t]+/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 180);
}

function safeColor(value, fallback = '#31e6ff') {
    const raw = String(value || '').trim().toLowerCase();
    if (COLOR_NAMES[raw]) return COLOR_NAMES[raw];
    if (/^#[0-9a-f]{3,8}$/i.test(raw)) return raw;
    if (/^rgba?\([0-9.,%\s]+\)$/i.test(raw)) return raw;
    return fallback;
}

function px(value, fallback) {
    if (value === undefined || value === null || value === '') return fallback;
    if (typeof value === 'number') return `${value}px`;
    const text = String(value).trim();
    if (/^-?\d+(\.\d+)?$/.test(text)) return `${text}px`;
    return text;
}

function applyUiConfig(ui) {
    cacheEls();
    if (!els.root || !ui || typeof ui !== 'object') return;
    const root = document.documentElement;
    if (ui.left !== undefined) root.style.setProperty('--chat-left', px(ui.left, '24px'));
    if (ui.top !== undefined) root.style.setProperty('--chat-top', px(ui.top, '26px'));
    if (ui.width !== undefined) root.style.setProperty('--chat-width', px(ui.width, '720px'));
    if (ui.height !== undefined) root.style.setProperty('--chat-height', px(ui.height, '430px'));
    if (ui.inputWidth !== undefined) root.style.setProperty('--chat-input-width', px(ui.inputWidth, '600px'));
    if (ui.fontSize !== undefined) root.style.setProperty('--chat-font-size', px(ui.fontSize, '18px'));
}

function getChannel(channelId) {
    return state.channels.find(ch => ch.id === channelId) || {
        id: channelId || 'rp', label: String(channelId || 'rp').toUpperCase(), color: '#31e6ff', format: 'rp'
    };
}

function renderTabs() {
    cacheEls();
    if (!els.tabs) return;
    els.tabs.innerHTML = state.channels.map(ch => {
        const color = safeColor(ch.color);
        return `
            <button class="chat-tab ${state.activeChannel === ch.id ? 'active' : ''}" data-channel="${escapeHtml(ch.id)}" style="--tab-color:${color}">
                ${escapeHtml(ch.label || ch.id.toUpperCase())}
            </button>
        `;
    }).join('');

    els.tabs.querySelectorAll('.chat-tab').forEach(btn => {
        btn.addEventListener('click', () => {
            state.activeChannel = btn.getAttribute('data-channel') || 'rp';
            renderTabs();
            setPlaceholder();
            els.input?.focus();
        });
    });
}

function renderActions() {
    cacheEls();
    if (!els.actions) return;
    els.actions.innerHTML = state.actions.map(action => `
        <button class="action-chip" data-command="${escapeHtml(action.command || '')}">${escapeHtml(action.label || action.id)}</button>
    `).join('');

    els.actions.querySelectorAll('.action-chip').forEach(btn => {
        btn.addEventListener('click', () => {
            const command = btn.getAttribute('data-command') || '';
            if (!els.input) return;
            els.input.value = command;
            els.input.focus();
            setTimeout(() => els.input.setSelectionRange(els.input.value.length, els.input.value.length), 0);
        });
    });
}

function setPlaceholder() {
    cacheEls();
    const ch = getChannel(state.activeChannel);
    if (els.input) els.input.placeholder = `Message ${ch.label || 'RP'}...`;
}

function channelClass(channel) {
    return String(channel || 'rp').replace(/[^a-z0-9_-]/gi, '').toLowerCase();
}

function shortLabel(label) {
    const clean = String(label || 'RP').replace(/[^a-z0-9]/gi, '').toUpperCase();
    return clean.length > 5 ? clean.slice(0, 5) : clean;
}

function addMessage(message) {
    cacheEls();
    const ch = getChannel(message.channel);
    const msg = {
        uid: ++seq,
        channel: message.channel || 'rp',
        channelLabel: message.channelLabel || ch.label || (message.channel || 'rp').toUpperCase(),
        channelColor: message.channelColor || ch.color || '#31e6ff',
        author: message.author || 'Unknown',
        id: message.id || 0,
        text: sanitizeText(message.text || ''),
        format: message.format || message.type || ch.format || 'rp',
        time: message.time || ''
    };

    state.messages.push(msg);
    while (state.messages.length > MAX_CHAT_MESSAGES) state.messages.shift();
    renderMessages();
}

function buildPrefix(msg) {
    const author = escapeHtml(msg.author);
    const id = escapeHtml(msg.id);
    if (msg.format === 'system') return 'Server:';
    if (msg.format === 'adminsys') return '';
    if (msg.format === 'announce') return `Administrator ${author}:`;
    if (msg.format === 'announce_anon') return 'Administrator:';
    if (msg.format === 'action') return `${author} (${id})`;
    if (msg.format === 'do') return 'Scene:';
    if (msg.format === 'me') return `${author} (${id})`;
    if (msg.format === 'try') return `${author} (${id}) tries:`;
    return `${author} (${id}) said:`;
}

function buildText(msg) {
    const text = escapeHtml(msg.text);
    if (msg.format === 'nonrp') return `(( ${text} ))`;
    if (msg.format === 'do') return text;
    if (msg.format === 'me') return `* ${text}`;
    if (msg.format === 'try') return text;
    return text;
}

function renderMessages(scrollToBottom = true) {
    cacheEls();
    if (!els.messages) return;
    els.messages.innerHTML = state.messages.map(msg => {
        const color = safeColor(msg.channelColor || getChannel(msg.channel).color || '#31e6ff');
        const label = shortLabel(msg.channelLabel || msg.channel);
        const cls = `chat-message chat-${channelClass(msg.channel)} chat-${channelClass(msg.format)}`;
        return `
            <div class="${cls}" style="--chat-color:${color}; --prefix-color:${color}">
                <div class="chat-mark" data-label="${escapeHtml(label)}"></div>
                <div class="chat-body">
                    <span class="chat-prefix">${buildPrefix(msg)}</span>
                    <span class="chat-text">${buildText(msg)}</span>
                </div>
            </div>
        `;
    }).join('');
    if (scrollToBottom) els.messages.scrollTop = els.messages.scrollHeight;
}

function setActionsOpen(open) {
    cacheEls();
    state.actionsOpen = !!open;
    els.actions?.classList.toggle('hidden', !state.actionsOpen);
    els.actionsToggle?.classList.toggle('active', state.actionsOpen);
}

function setOpen(open) {
    cacheEls();
    state.open = !!open;

    if (!els.root) return;
    els.root.classList.toggle('chat-open', state.open);
    els.root.classList.toggle('chat-closed', !state.open);
    els.controls?.classList.toggle('hidden', !state.open);

    if (state.open) {
        renderTabs();
        renderActions();
        renderMessages();
        setPlaceholder();
        setActionsOpen(false);
        historyIndex = history.length;
        suppressOpenKey = true;
        if (els.input) els.input.value = '';
        setTimeout(() => {
            if (els.input && state.open) {
                els.input.value = '';
                els.input.focus();
            }
            setTimeout(() => { suppressOpenKey = false; }, 150);
        }, 80);
    } else {
        setActionsOpen(false);
        if (els.input) {
            els.input.value = '';
            els.input.blur();
        }
        renderMessages(false);
    }
}

function closeChat() {
    fetch(`https://${GetParentResourceName()}/chatClose`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify({})
    });
}

function sendInput() {
    cacheEls();
    const text = sanitizeText(els.input?.value || '');
    if (!text) { closeChat(); return; }

    history.push(text);
    if (history.length > 40) history.shift();
    historyIndex = history.length;

    fetch(`https://${GetParentResourceName()}/chatSend`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ channel: state.activeChannel, text })
    });

    if (els.input) els.input.value = '';
    setOpen(false);
}

function setup() {
    cacheEls();
    renderTabs();
    renderActions();
    setOpen(false);

    els.actionsToggle?.addEventListener('click', () => setActionsOpen(!state.actionsOpen));
    els.submit?.addEventListener('click', sendInput);

    document.addEventListener('mousedown', (e) => {
        if (state.open && els.root && !els.root.contains(e.target)) {
            e.preventDefault();
            closeChat();
        }
    }, true);

    els.input?.addEventListener('keydown', (e) => {
        if (suppressOpenKey && (e.key || '').toLowerCase() === 't') {
            e.preventDefault();
            e.stopPropagation();
            if (els.input) els.input.value = '';
            return;
        }

        if (e.key === 'Enter') {
            e.preventDefault();
            sendInput();
        } else if (e.key === 'Escape') {
            e.preventDefault();
            closeChat();
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            if (history.length > 0) {
                historyIndex = Math.max(0, historyIndex - 1);
                els.input.value = history[historyIndex] || '';
                setTimeout(() => els.input.setSelectionRange(els.input.value.length, els.input.value.length), 0);
            }
        } else if (e.key === 'ArrowDown') {
            e.preventDefault();
            if (history.length > 0) {
                historyIndex = Math.min(history.length, historyIndex + 1);
                els.input.value = history[historyIndex] || '';
                setTimeout(() => els.input.setSelectionRange(els.input.value.length, els.input.value.length), 0);
            }
        }
    });
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    switch (data.action) {
        case 'setChatConfig':
            if (Number(data.maxMessages) > 0) MAX_CHAT_MESSAGES = Number(data.maxMessages);
            if (Array.isArray(data.actions)) {
                state.actions = data.actions;
                renderActions();
            }
            applyUiConfig(data.ui);
            break;
        case 'setChatOpen':
            setOpen(data.open);
            break;
        case 'setChatChannels':
            if (Array.isArray(data.channels) && data.channels.length > 0) {
                state.channels = data.channels;
                if (!state.channels.find(ch => ch.id === state.activeChannel) && state.channels[0]) {
                    state.activeChannel = state.channels[0].id;
                }
                renderTabs();
                setPlaceholder();
            }
            if (Array.isArray(data.actions)) {
                state.actions = data.actions;
                renderActions();
            }
            break;
        case 'addChatMessage':
            addMessage(data.message || data);
            break;
        case 'clearChat':
            state.messages = [];
            renderMessages(false);
            break;
    }
});

setup();
