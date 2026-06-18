const serverName = document.getElementById('server-name');
const serverKicker = document.getElementById('server-kicker');
const serverDescription = document.getElementById('server-description');
const progressFill = document.getElementById('progress-fill');
const progressText = document.getElementById('progress-text');
const progressLabel = document.getElementById('progress-label');
const tipText = document.getElementById('tip-text');
const slideStack = document.getElementById('slide-stack');
const bgm = document.getElementById('bgm');

let currentProgress = 0;
let fakeProgress = 0;
let tipIndex = 0;
let currentSlideIndex = 0;
let slideTimer = null;
let tipTimer = null;

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
    progressFill.style.width = `${currentProgress}%`;
    progressText.textContent = `${currentProgress}%`;
    progressLabel.textContent = label || (currentProgress >= 100 ? 'Finalizing auth' : 'Loading resources');
}

function renderSlides() {
    const slides = (window.loadingConfig && Array.isArray(loadingConfig.slides) ? loadingConfig.slides : []).filter(Boolean);
    slideStack.innerHTML = '';

    slides.forEach((path, index) => {
        const slide = document.createElement('div');
        slide.className = `slide${index === 0 ? ' active animate-gta-zoom' : ''}`;
        slide.style.backgroundImage = `url(${path})`;
        slide.dataset.index = String(index);
        slideStack.appendChild(slide);
    });
}

function setActiveSlide(nextIndex) {
    const slides = Array.from(document.querySelectorAll('.slide'));
    if (!slides.length) return;

    slides.forEach((slide, index) => {
        slide.classList.remove('active', 'animate-gta-zoom');
        if (index === nextIndex) {
            slide.classList.add('active');
            // restart animation
            requestAnimationFrame(() => slide.classList.add('animate-gta-zoom'));
        }
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
    if (!window.loadingConfig || !Array.isArray(loadingConfig.tips) || loadingConfig.tips.length === 0) return;
    tipIndex = (tipIndex + 1) % loadingConfig.tips.length;
    tipText.textContent = loadingConfig.tips[tipIndex];
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

function skipIntro() {
    document.body.classList.add('skipped');
    postToResource('loadingSkip', { skipped: true }).catch(() => {});
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.eventName === 'loadProgress') {
        const percentage = (data.loadFraction || 0) * 100;
        fakeProgress = Math.max(fakeProgress, percentage);
        setProgress(fakeProgress, percentage >= 100 ? 'Finalizing auth' : 'Loading resources');
    }
});

document.addEventListener('keydown', (event) => {
    if (event.code === 'Space') {
        event.preventDefault();
        skipIntro();
    }
});

document.addEventListener('DOMContentLoaded', () => {
    if (window.loadingConfig) {
        serverName.textContent = loadingConfig.serverName || 'CM Roleplay';
        serverKicker.textContent = loadingConfig.kicker || 'CM ROLEPLAY';
        serverDescription.textContent = loadingConfig.description || 'Loading your city session.';
        if (loadingConfig.tips && loadingConfig.tips[0]) tipText.textContent = loadingConfig.tips[0];
    }

    renderSlides();
    startSlideShow();
    setProgress(0, 'Loading resources');

    tipTimer = window.setInterval(rotateTip, 5200);

    window.setInterval(() => {
        if (currentProgress < 92) {
            fakeProgress = Math.max(fakeProgress, currentProgress + Math.random() * 1.2);
            setProgress(fakeProgress);
        }
    }, 680);

    if (bgm) {
        const playAttempt = bgm.play();
        if (playAttempt && typeof playAttempt.catch === 'function') {
            playAttempt.catch(() => {});
        }
        bgm.volume = 0.35;
    }
});
