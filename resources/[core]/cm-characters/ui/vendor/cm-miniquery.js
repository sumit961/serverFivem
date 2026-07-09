/* Lightweight local jQuery-compatible shim for cm-characters appearance UI.
   Supports only the methods used by ui/appearance/app.js. No external CDN needed. */
(function () {
    'use strict';

    function toNodes(input) {
        if (input === document || input === window) return [input];
        if (input instanceof MiniQuery) return input.nodes;
        if (input instanceof Element) return [input];
        if (Array.isArray(input)) return input.filter(Boolean);
        if (typeof input === 'string') return Array.from(document.querySelectorAll(input));
        return [];
    }

    function MiniQuery(input) {
        this.nodes = toNodes(input);
        this.length = this.nodes.length;
        for (var i = 0; i < this.nodes.length; i += 1) this[i] = this.nodes[i];
    }

    MiniQuery.prototype.each = function (fn) {
        this.nodes.forEach(function (node, index) { fn.call(node, index, node); });
        return this;
    };

    MiniQuery.prototype.empty = function () { return this.each(function () { this.textContent = ''; }); };
    MiniQuery.prototype.show = function () { return this.each(function () { this.style.display = ''; }); };
    MiniQuery.prototype.hide = function () { return this.each(function () { this.style.display = 'none'; }); };
    MiniQuery.prototype.addClass = function (name) { return this.each(function () { this.classList.add(name); }); };
    MiniQuery.prototype.removeClass = function (name) { return this.each(function () { this.classList.remove(name); }); };
    MiniQuery.prototype.append = function (html) { return this.each(function () { this.insertAdjacentHTML('beforeend', html); }); };

    MiniQuery.prototype.text = function (value) {
        if (value === undefined) return this.nodes[0] ? this.nodes[0].textContent : undefined;
        return this.each(function () { this.textContent = value; });
    };

    MiniQuery.prototype.html = function (value) {
        if (value === undefined) return this.nodes[0] ? this.nodes[0].innerHTML : undefined;
        return this.each(function () { this.innerHTML = value; });
    };

    MiniQuery.prototype.val = function (value) {
        if (value === undefined) return this.nodes[0] ? this.nodes[0].value : undefined;
        return this.each(function () { this.value = value; });
    };

    MiniQuery.prototype.data = function (name) {
        var node = this.nodes[0];
        if (!node || !node.dataset) return undefined;
        return node.dataset[name];
    };

    MiniQuery.prototype.on = function (eventName, selector, handler) {
        if (typeof selector === 'function') {
            handler = selector;
            selector = null;
        }
        return this.each(function () {
            this.addEventListener(eventName, function (event) {
                if (!selector) return handler.call(this, event);
                var match = event.target && event.target.closest ? event.target.closest(selector) : null;
                if (match && (this === document || (this.contains && this.contains(match)))) handler.call(match, event);
            });
        });
    };

    window.$ = function (input) { return new MiniQuery(input); };
    window.jQuery = window.$;
})();
