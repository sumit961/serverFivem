// cm-carplay web UI -- locale lookup.
//
// Mirrors locales/locales.lua's _L(key): dot-path lookup into whatever
// table the "setLocale" NUI message last delivered (see locales/en.lua for
// the full shape -- UI.*, notifications.*, commands.*).

const Locale = (() => {
    let table = {};

    NUI.on('setLocale', (data) => {
        table = data || {};
        document.dispatchEvent(new CustomEvent('localechange'));
    });

    function L(path, vars) {
        let value = table;
        for (const key of path.split('.')) {
            value = value ? value[key] : undefined;
        }
        if (typeof value !== 'string') return path;
        if (!vars) return value;
        // Printf-style %s substitution, matching the Lua notification strings
        // (e.g. notifications.music.nowPlaying = "Now playing: %s").
        let i = 0;
        return value.replace(/%s/g, () => (vars[i++] ?? ''));
    }

    return { L };
})();
