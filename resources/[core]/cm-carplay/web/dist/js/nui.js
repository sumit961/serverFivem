// cm-carplay web UI -- NUI transport layer.
//
// Two directions of traffic:
//  - Lua -> page:  SendNUIMessage({ action, data })  ->  window "message" events.
//    Handlers register with NUI.on(action, handler).
//  - page -> Lua:  RegisterNUICallback(name, ...)     ->  fetch() POST to the
//    resource's NUI callback URL. Call with NUI.post(name, data).
//
// This file has no knowledge of what any action/callback MEANS -- it's pure
// transport. Screen modules (home.js, manage.js, ...) own the meaning.

const NUI = (() => {
    const resourceName = typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'cm-carplay';

    const listeners = new Map(); // action -> Set<handler>

    window.addEventListener('message', (event) => {
        const { action, type, data } = event.data || {};
        // main.lua messages use `action`; sound.lua's audio-engine messages
        // use `type` for the same purpose. Normalize to one dispatch key.
        const key = action || type;
        if (!key) return;

        const handlers = listeners.get(key);
        if (!handlers) return;
        for (const handler of handlers) {
            try {
                handler(data, event.data);
            } catch (err) {
                console.error(`[cm-carplay] handler for "${key}" threw:`, err);
            }
        }
    });

    function on(action, handler) {
        if (!listeners.has(action)) listeners.set(action, new Set());
        listeners.get(action).add(handler);
        return () => listeners.get(action).delete(handler);
    }

    async function post(callbackName, data = {}) {
        try {
            const response = await fetch(`https://${resourceName}/${callbackName}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            const text = await response.text();
            return text ? JSON.parse(text) : null;
        } catch (err) {
            console.error(`[cm-carplay] post("${callbackName}") failed:`, err);
            return null;
        }
    }

    return { on, post, resourceName };
})();
