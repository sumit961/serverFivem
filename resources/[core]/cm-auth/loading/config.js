// cm-auth loading screen config. Player-facing brand text now lives in
// ../shared/branding.js (window.CMBranding) — do not re-add serverName/kicker
// here, this file only holds this screen's own tunables.
window.loadingConfig = {
    slideDuration: 7000,
    // PNG/WebP only. If a file is missing, script.js falls back to a plain
    // dark-teal gradient for that slide instead of a broken image.
    slides: [
        { src: 'assets/slide-01.webp', position: 'center center' },
        { src: 'assets/slide-02.webp', position: 'center center' },
        { src: 'assets/slide-03.webp', position: 'center center' },
        { src: 'assets/slide-04.webp', position: 'center center' }
    ],
    tips: [
        "Trusted login never skips confirmation — you'll still see the login screen before entering the city.",
        'Saved login only works on this exact device with your Rockstar account.',
        'Lost access to your account? Ask a staff member in-game or on Discord for help.',
        'If saved login fails, sign in with your email and password to reconnect this device.'
    ]
};
