// cm-ui canonical player-facing branding — single source of truth for every
// onboarding/NUI screen (cm-auth loading, cm-auth login, cm-characters,
// cm-spawn, ...). Change the server's player-facing name/tagline here only;
// every screen that reads window.CMBranding picks it up automatically.
// cm-ui is already a hard dependency of every consumer, so this is safe to
// load via `nui://cm-ui/web/cm-branding.js` before each screen's own script.
window.CMBranding = {
    serverName: 'CM ROLEPLAY',
    shortName: 'CM',
    tagline: 'ENTER THE CITY'
};
