(function () {
    const serverName = document.getElementById('server-name');
    const taglineText = document.getElementById('tagline-text');
    const progressFill = document.getElementById('progress-fill');
    const progressText = document.getElementById('progress-text');
    const progressLabel = document.getElementById('progress-label');
    const tipText = document.getElementById('tip-text');
    const continuePrompt = document.getElementById('continue-prompt');
    const slideStack = document.getElementById('slide-stack');
    const bgm = document.getElementById('bgm');
    const musicToggle = document.getElementById('music-toggle');

    let currentProgress = 0;
    let fakeProgress = 0;
    // Real FiveM loadProgress only — never the smoothed/synthetic value.
    // Only this is allowed to trigger the ready/continue state.
    let realProgress = 0;
    let ready = false;
    let tipIndex = 0;
    let currentSlideIndex = 0;
    let slideTimer = null;
    let tipTimer = null;
    let progressTimer = null;
    let continueRequested = false;

    function setText(el, text) {
        if (!el) return;
        el.textContent = text;
    }

    function resourceUrl(path) {
        try {
            return `https://${GetParentResourceName()}/${path}`;
        } catch (e) {
            return null;
        }
    }

    function clamp(value, min, max) {
        return Math.min(Math.max(value, min), max);
    }

    function setProgress(value, label) {
        currentProgress = clamp(Math.round(value || 0), 0, 100);
        if (progressFill) progressFill.style.width = `${currentProgress}%`;
        setText(progressText, `${currentProgress}%`);
        setText(progressLabel, label || 'Loading the city');
    }

    // Preloads each configured slide; only wires up the real image once it is
    // confirmed to load. Until then (or if it's missing) the slide keeps the
    // plain gradient that style.css's base .slide rule already provides —
    // never a broken-image icon.
    function preloadSlide(config, onResult) {
        if (!config || !config.src) {
            onResult(false);
            return;
        }
        const probe = new Image();
        probe.onload = () => onResult(true);
        probe.onerror = () => onResult(false);
        probe.src = config.src;
    }

    function renderSlides() {
        if (!slideStack) return;
        const slides = (window.loadingConfig && Array.isArray(window.loadingConfig.slides) ? window.loadingConfig.slides : []).filter(Boolean);
        slideStack.innerHTML = '';

        slides.forEach((config, index) => {
            const slide = document.createElement('div');
            slide.className = `slide${index === 0 ? ' active' : ''}`;
            slide.dataset.index = String(index);
            slideStack.appendChild(slide);

            preloadSlide(config, (ok) => {
                if (!ok) return;
                slide.style.backgroundImage = `url(${config.src})`;
                slide.style.backgroundPosition = config.position || 'center center';
            });
        });
    }

    function setActiveSlide(nextIndex) {
        const slides = Array.from(document.querySelectorAll('.slide'));
        if (!slides.length) return;

        slides.forEach((slide, index) => {
            slide.classList.remove('active');
            if (index === nextIndex) slide.classList.add('active');
        });

        currentSlideIndex = nextIndex;
    }

    function startSlideShow() {
        const slides = Array.from(document.querySelectorAll('.slide'));
        if (slides.length <= 1) return;

        const duration = Number(window.loadingConfig?.slideDuration || 7000);
        slideTimer = window.setInterval(() => {
            const next = (currentSlideIndex + 1) % slides.length;
            setActiveSlide(next);
        }, duration);
    }

    function rotateTip() {
        if (ready || !tipText || !window.loadingConfig || !Array.isArray(window.loadingConfig.tips) || window.loadingConfig.tips.length === 0) return;
        tipIndex = (tipIndex + 1) % window.loadingConfig.tips.length;
        tipText.textContent = window.loadingConfig.tips[tipIndex];
    }

    function postToResource(path, payload) {
        const url = resourceUrl(path);
        if (!url) return Promise.reject(new Error('no resource url'));

        return fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload || {})
        });
    }

    function stopTimers() {
        if (slideTimer) window.clearInterval(slideTimer);
        if (tipTimer) window.clearInterval(tipTimer);
        if (progressTimer) window.clearInterval(progressTimer);
        slideTimer = null;
        tipTimer = null;
        progressTimer = null;
    }

    // Real FiveM progress only. Fake/smoothed progress may visually approach
    // ~90-95% in the meantime but can never set ready itself.
    function enterReadyState() {
        if (ready) return;
        ready = true;

        fakeProgress = 100;
        setProgress(100, 'City ready');
        if (tipText) tipText.classList.add('hidden');
        if (continuePrompt) continuePrompt.classList.remove('hidden');
    }

    // Only does anything once ready (post-100%). Before that, Enter/Space are
    // inert — they must not open auth, preview a saved token, or shut down
    // the loading screen early.
    function continueToAuth() {
        if (!ready || continueRequested) return;
        continueRequested = true;

        document.body.classList.add('continuing');
        if (continuePrompt) continuePrompt.classList.add('acknowledged');
        postToResource('loadingContinue', {}).catch(() => {});
    }

    function setMusicMuted(muted) {
        if (!bgm) return;
        bgm.muted = muted;
        if (musicToggle) {
            musicToggle.setAttribute('aria-pressed', muted ? 'true' : 'false');
            musicToggle.setAttribute('aria-label', muted ? 'Unmute loading music' : 'Mute loading music');
            musicToggle.textContent = muted ? '♯' : '♫';
        }
    }

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        if (data.eventName === 'loadProgress') {
            const percentage = clamp((data.loadFraction || 0) * 100, 0, 100);
            realProgress = Math.max(realProgress, percentage);
            fakeProgress = Math.max(fakeProgress, percentage);

            if (realProgress >= 99.5) {
                enterReadyState();
            } else if (!ready) {
                setProgress(fakeProgress, 'Loading the city');
            }
        }
    });

    document.addEventListener('keydown', (event) => {
        if (event.code !== 'Space' && event.code !== 'Enter') return;
        event.preventDefault();
        continueToAuth();
    });

    window.addEventListener('pagehide', stopTimers);

    document.addEventListener('DOMContentLoaded', () => {
        const brand = window.CMBranding || {};
        setText(serverName, brand.serverName || 'CM ROLEPLAY');
        setText(taglineText, brand.tagline || 'ENTER THE CITY');
        if (window.loadingConfig?.tips?.[0]) setText(tipText, window.loadingConfig.tips[0]);

        renderSlides();
        startSlideShow();
        setProgress(0, 'Loading the city');

        tipTimer = window.setInterval(rotateTip, 5200);

        progressTimer = window.setInterval(() => {
            if (ready) return;
            if (currentProgress < 92) {
                fakeProgress = Math.max(fakeProgress, currentProgress + Math.random() * 1.2);
                setProgress(fakeProgress, 'Loading the city');
            }
        }, 680);

        if (musicToggle) {
            musicToggle.addEventListener('click', () => setMusicMuted(!bgm || !bgm.muted));
        }

        if (bgm) {
            bgm.volume = 0.35;
            const playAttempt = bgm.play();
            if (playAttempt && typeof playAttempt.catch === 'function') {
                playAttempt.catch(() => {});
            }
        }

        // Tells the Lua client this loadscreen NUI genuinely mounted, so its
        // auth gate knows to actually block until loadingContinue fires. On a
        // plain cm-auth restart while already connected, this file never
        // loads again, so the gate correctly stays inert instead of blocking
        // forever.
        postToResource('loadingMounted', {}).catch(() => {});
    });
})();
