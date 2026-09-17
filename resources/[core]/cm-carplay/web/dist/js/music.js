// cm-carplay web UI -- music player screen (search, library, queue, now
// playing, transport controls).
//
// Ownership split (see also js/sound-engine.js, built separately):
//   - This file owns the music PLAYER SCREEN: search/library UI, the local
//     queue/recent lists, now-playing display, transport controls, and all
//     NUI traffic for the `*Music*` callbacks/actions in client/main.lua.
//   - For local-file/direct-URL tracks, actual <audio> playback (per-speaker
//     volume, 3D distance attenuation, the real play/pause/seek at the audio
//     node level) is sound-engine.js's job, driven by client/sound.lua's
//     `type`-keyed NUI messages (addAudioSource, playAudioSource, ...) which
//     this file never touches directly. We only reflect state: play/pause
//     icon, elapsed time, progress bar.
//   - For YouTube tracks we do own real audio+video: a genuine YouTube
//     IFrame Player embedded in `.music-player`, per the task brief. See the
//     "YouTube player" section below.
//
// NUI callbacks used (names cross-checked against client/main.lua):
//   getMusicLibrary, fetchYouTubeData, playMusic, getMusicTime, toggleMusic,
//   stopMusic, seekMusic, setMusicVolume, getMusicState
// NUI incoming actions used:
//   musicStarted, updatePlaybackStatus, musicStopped, trackEnded,
//   syncMusicState

const MusicScreen = (() => {
    // --- shared "now playing" surface for other screens (e.g. the home
    // mini-widget) ---------------------------------------------------------
    // app.js/home.js don't define a contract for this (home.js didn't exist
    // yet at the time this file was written), so this is a small ad-hoc
    // surface: CarPlayMusic.getState() for a one-shot read, and a
    // 'carplaymusicstate' CustomEvent on `document` for live updates. See
    // this file's report for details -- whoever builds home.js's widget
    // should reconcile with this rather than re-deriving state independently.
    const sharedState = {
        song: null,       // current track object (see normalizeTrack), or null
        isPlaying: false,
        currentTime: 0,
        duration: 0,
    };

    function publishSharedState() {
        document.dispatchEvent(new CustomEvent('carplaymusicstate', { detail: { ...sharedState } }));
    }

    window.CarPlayMusic = {
        getState: () => ({ ...sharedState }),
    };

    // --- utils ---------------------------------------------------------------

    function escapeHtml(value) {
        const div = document.createElement('div');
        div.textContent = value == null ? '' : String(value);
        return div.innerHTML;
    }

    function formatTime(totalSeconds) {
        const seconds = Math.max(0, Math.floor(Number(totalSeconds) || 0));
        const minutes = Math.floor(seconds / 60);
        const remainder = seconds % 60;
        return `${minutes}:${String(remainder).padStart(2, '0')}`;
    }

    function debounce(fn, delayMs) {
        let timer = null;
        return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => fn(...args), delayMs);
        };
    }

    // Mirrors client/sound.lua's isYoutubeUrl(): a youtube.com/youtu.be URL,
    // or a bare 11-char video id typed directly.
    function extractYoutubeVideoId(input) {
        if (!input) return null;
        const text = input.trim();

        if (/^[a-zA-Z0-9_-]{11}$/.test(text)) return text;

        const patterns = [
            /(?:youtube\.com\/watch\?v=|youtube\.com\/embed\/|youtube\.com\/(?:shorts|live)\/|youtu\.be\/)([a-zA-Z0-9_-]{11})/,
        ];
        for (const pattern of patterns) {
            const match = pattern.exec(text);
            if (match) return match[1];
        }
        return null;
    }

    function youtubeThumbnail(videoId) {
        return `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`;
    }

    // Normalizes any source (library entry, youtube preview, queue/recent
    // entry) into the track shape server/main.lua's sanitizeMusicTrackData
    // expects: { id, title, artist, filePath, url, thumbnail, isYouTube,
    // videoId, duration }.
    function normalizeTrack(partial) {
        return {
            id: partial.id != null ? String(partial.id) : `track-${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
            title: partial.title || 'Unknown',
            artist: partial.artist || 'Unknown',
            filePath: partial.filePath || undefined,
            url: partial.url || undefined,
            thumbnail: partial.thumbnail || undefined,
            isYouTube: partial.isYouTube === true,
            videoId: partial.videoId || undefined,
            duration: typeof partial.duration === 'number' ? partial.duration : 0,
        };
    }

    function trackKey(track) {
        if (!track) return '';
        return track.isYouTube ? `yt:${track.videoId || track.id}` : `local:${track.id || track.filePath || track.url}`;
    }

    // --- module state ----------------------------------------------------

    let musicLibrary = [];         // cached Config.MusicLibrary entries
    let libraryLoaded = false;
    let youtubePreview = null;     // { state: 'loading'|'ready'|'error', track } for the pasted-URL row
    let queue = [];                // local-only queue of track objects
    let recent = [];                // local-only recently-played history
    let currentTrack = null;       // normalized track currently playing (or null)
    let isPlaying = false;
    let loadingTrack = null;        // request accepted, waiting for actual playback
    let playRequestSerial = 0;
    let currentTime = 0;
    let activeTab = 'queue';       // 'queue' | 'recent'
    let volume = 0.75;
    let pollTimer = null;
    let screenVisible = false;

    // --- persistence (recent list + volume are purely client-side; nothing
    // in Lua tracks them) --------------------------------------------------

    const STORAGE_RECENT_KEY = 'cm-carplay:music:recent';
    const STORAGE_VOLUME_KEY = 'cm-carplay:music:volume';

    function loadPersisted() {
        try {
            const rawRecent = localStorage.getItem(STORAGE_RECENT_KEY);
            if (rawRecent) recent = JSON.parse(rawRecent).slice(0, 20);
        } catch (err) { /* ignore -- private browsing, disabled storage, etc. */ }

        try {
            const rawVolume = localStorage.getItem(STORAGE_VOLUME_KEY);
            if (rawVolume !== null) {
                const parsed = parseFloat(rawVolume);
                if (!Number.isNaN(parsed)) volume = Math.min(1, Math.max(0, parsed));
            }
        } catch (err) { /* ignore */ }
    }

    function persistRecent() {
        try {
            localStorage.setItem(STORAGE_RECENT_KEY, JSON.stringify(recent.slice(0, 20)));
        } catch (err) { /* ignore */ }
    }

    function persistVolume() {
        try {
            localStorage.setItem(STORAGE_VOLUME_KEY, String(volume));
        } catch (err) { /* ignore */ }
    }

    function pushRecent(track) {
        recent = recent.filter((entry) => trackKey(entry) !== trackKey(track));
        recent.unshift(track);
        recent = recent.slice(0, 20);
        persistRecent();
        if (activeTab === 'recent') renderQueueList();
    }

    // --- DOM ---------------------------------------------------------------

    const els = {};

    const ICONS = {
        search: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 2a8 8 0 1 0 4.9 14.32l5.39 5.39 1.41-1.42-5.39-5.38A8 8 0 0 0 10 2Zm0 2a6 6 0 1 1 0 12 6 6 0 0 1 0-12Z"/></svg>',
        play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.5v15l13-7.5-13-7.5Z"/></svg>',
        pause: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4h4v16H7V4Zm6 0h4v16h-4V4Z"/></svg>',
        queueAdd: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 6h13M3 12h13M3 18h7M18 14v8M14 18h8"/></svg>',
        trash: '<svg viewBox="0 0 24 24"><path d="M6 7h12l-1 13H7L6 7Zm3-3h6l1 2H8l1-2ZM4 7h16"/></svg>',
        prevTrack: '<svg viewBox="0 0 24 24"><path d="M6 5v14h2V5H6Zm12 0-9 7 9 7V5Z"/></svg>',
        nextTrack: '<svg viewBox="0 0 24 24"><path d="M16 5v14h2V5h-2ZM6 5l9 7-9 7V5Z"/></svg>',
        seekBack: '<svg viewBox="0 0 24 24"><path d="M12 5V1L6 6l6 5V7a5 5 0 1 1-5 5H5a7 7 0 1 0 7-7Z"/></svg>',
        seekForward: '<svg viewBox="0 0 24 24"><path d="M12 5V1l6 5-6 5V7a5 5 0 1 0 5 5h2a7 7 0 1 1-7-7Z"/></svg>',
        volume: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M4 9v6h4l5 5V4L8 9H4Zm11.5 3a3.5 3.5 0 0 0-2-3.16v6.32A3.5 3.5 0 0 0 15.5 12Z"/></svg>',
        videoPlaceholder: '<svg viewBox="0 0 24 24" fill="currentColor" width="32" height="32"><path d="M4 5h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Zm2 3v8h2V8H6Zm10 4-6-3.5v7L16 12Z"/></svg>',
        songPlaceholder: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 17V5l11-2v12M9 17a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm11-2a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"/></svg>',
    };

    function buildSkeleton() {
        const panel = document.getElementById('music-panel');
        els['music-panel'] = panel;
        panel.innerHTML = `
            <div class="music-header">
                <div class="search-bar" id="music-search-bar">
                    ${ICONS.search}
                    <input type="text" id="music-search-input" autocomplete="off" spellcheck="false" />
                    <div class="search-dropdown" id="music-search-dropdown" hidden></div>
                </div>
                <button class="play-btn" id="music-header-play-btn" type="button"></button>
                <button class="queue-btn" id="music-header-queue-btn" type="button"></button>
            </div>

            <div class="music-content">
                <div class="music-player-container">
                    <div class="title" id="music-nowplaying-title" data-i18n="UI.music.nowPlaying"></div>

                    <div class="music-player">
                        <div class="video-placeholder" id="music-video-placeholder">
                            ${ICONS.videoPlaceholder}
                            <span id="music-video-placeholder-title" data-i18n="UI.music.videoPlayer"></span>
                            <span id="music-video-placeholder-subtitle" data-i18n="UI.music.noVideo"></span>
                        </div>
                        <div class="youtube-embed" id="music-youtube-embed" hidden>
                            <div id="music-youtube-target"></div>
                        </div>

                        <div class="music-controls">
                            <div class="music-header">
                                <div class="music-name">
                                    <div class="title" id="music-current-title">--</div>
                                    <div class="author" id="music-current-author">--</div>
                                </div>

                                <div class="right-container">
                                    <div class="buttons-container">
                                        <div class="prev-track" id="music-prev-track" title="">${ICONS.prevTrack}</div>
                                        <div class="seek-prev" id="music-seek-prev" title="-10s">${ICONS.seekBack}</div>
                                        <button class="toggle-music" id="music-toggle" type="button">${ICONS.play}</button>
                                        <div class="seek-next" id="music-seek-next" title="+10s">${ICONS.seekForward}</div>
                                        <div class="next-track" id="music-next-track" title="">${ICONS.nextTrack}</div>
                                    </div>

                                    <div class="volume-container">
                                        ${ICONS.volume}
                                        <div class="volume-slider" id="music-volume-slider">
                                            <div class="volume-progress" id="music-volume-progress">
                                                <div class="volume-thumb"></div>
                                            </div>
                                            <input type="range" class="volume-input" id="music-volume-input" min="0" max="1" step="0.01" />
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <div class="music-seek">
                                <span class="current-time" id="music-current-time">0:00</span>
                                <div class="timer-progress" id="music-timer-progress">
                                    <div class="timer-progress-filled" id="music-timer-progress-filled">
                                        <div class="timer-progress-thumb"></div>
                                    </div>
                                </div>
                                <span class="duration" id="music-duration">0:00</span>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="music-queue-container">
                    <div class="queue-header">
                        <div class="title" id="music-queue-title" data-i18n="UI.music.recentAndQueue"></div>
                        <div class="clear-btn" id="music-clear-btn">
                            ${ICONS.trash}
                            <span id="music-clear-label" data-i18n="UI.music.clear"></span>
                        </div>
                    </div>

                    <div class="queue-list-container" id="music-queue-list-container">
                        <div class="queue-empty" id="music-queue-empty" hidden>
                            <div class="queue-empty-title" id="music-queue-empty-title"></div>
                            <div class="queue-empty-subtitle" id="music-queue-empty-subtitle"></div>
                        </div>
                        <div class="queue" id="music-queue-list" hidden></div>
                        <div class="queue-tabs" id="music-queue-tabs">
                            <div class="tab" id="music-tab-queue" data-tab="queue"></div>
                            <div class="tab" id="music-tab-recent" data-tab="recent"></div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        [
            'music-search-bar', 'music-search-input', 'music-search-dropdown',
            'music-header-play-btn', 'music-header-queue-btn',
            'music-video-placeholder', 'music-video-placeholder-title', 'music-video-placeholder-subtitle',
            'music-youtube-embed', 'music-youtube-target',
            'music-current-title', 'music-current-author',
            'music-prev-track', 'music-seek-prev', 'music-toggle', 'music-seek-next', 'music-next-track',
            'music-volume-slider', 'music-volume-progress', 'music-volume-input',
            'music-current-time', 'music-timer-progress', 'music-timer-progress-filled', 'music-duration',
            'music-queue-title', 'music-clear-btn', 'music-clear-label',
            'music-queue-list-container', 'music-queue-empty', 'music-queue-empty-title', 'music-queue-empty-subtitle',
            'music-queue-list', 'music-queue-tabs', 'music-tab-queue', 'music-tab-recent',
        ].forEach((id) => { els[id] = document.getElementById(id); });
    }

    function renderStaticText() {
        els['music-search-input'].placeholder = Locale.L('UI.music.searchPlaceholder');
        els['music-header-play-btn'].textContent = Locale.L('UI.music.play');
        els['music-header-queue-btn'].textContent = Locale.L('UI.music.addToQueue');
        els['music-video-placeholder-title'].textContent = Locale.L('UI.music.videoPlayer');
        els['music-video-placeholder-subtitle'].textContent = Locale.L('UI.music.noVideo');
        els['music-clear-label'].textContent = Locale.L('UI.music.clear');
        els['music-queue-empty-title'].textContent = Locale.L('UI.music.noMusic');
        els['music-queue-empty-subtitle'].textContent = Locale.L('UI.music.noMusicSubtitle');
        els['music-tab-queue'].textContent = Locale.L('UI.music.queue');
        els['music-tab-recent'].textContent = Locale.L('UI.music.recent');
        els['music-prev-track'].title = Locale.L('UI.common.previous');
        els['music-next-track'].title = Locale.L('UI.common.next');
        renderSearchDropdown();
        renderQueueList();
        renderNowPlaying();
    }

    // --- library / search --------------------------------------------------

    async function ensureLibraryLoaded() {
        if (libraryLoaded) return;
        const result = await NUI.post('getMusicLibrary', {});
        musicLibrary = Array.isArray(result) ? result.map((entry) => normalizeTrack(entry)) : [];
        libraryLoaded = true;
    }

    function filterLibrary(query) {
        const text = query.trim().toLowerCase();
        if (!text) return musicLibrary.slice(0, 8);
        return musicLibrary
            .filter((track) => track.title.toLowerCase().includes(text) || track.artist.toLowerCase().includes(text))
            .slice(0, 8);
    }

    function currentSearchResults() {
        const results = [];
        if (youtubePreview && youtubePreview.state !== 'idle') results.push(youtubePreview);
        for (const track of filterLibrary(els['music-search-input'].value)) {
            results.push({ state: 'ready', track });
        }
        return results;
    }

    function renderSearchDropdown() {
        const dropdown = els['music-search-dropdown'];
        const results = currentSearchResults();

        if (results.length === 0) {
            dropdown.hidden = true;
            dropdown.innerHTML = '';
            return;
        }

        dropdown.innerHTML = results.map((entry, index) => {
            if (entry.state === 'loading') {
                return `<div class="search-result-item youtube" data-index="${index}">
                    <div class="song-info"><div class="song-title">${escapeHtml(Locale.L('UI.common.loading'))}</div></div>
                </div>`;
            }
            if (entry.state === 'error') {
                return `<div class="search-result-item youtube" data-index="${index}">
                    <div class="song-info"><div class="song-title">${escapeHtml(Locale.L('UI.common.error'))}</div></div>
                </div>`;
            }

            const track = entry.track;
            const youtubeClass = track.isYouTube ? ' youtube' : '';
            const thumb = track.isYouTube
                ? `<img class="youtube-thumb" src="${escapeHtml(track.thumbnail || '')}" alt="" />`
                : '';
            const badge = track.isYouTube ? `<span class="youtube-badge">YouTube</span>` : '';

            return `<div class="search-result-item${youtubeClass}" data-index="${index}">
                ${thumb}
                <div class="song-info">
                    <div class="song-title">${badge}${escapeHtml(track.title)}</div>
                    <div class="song-artist">${escapeHtml(track.artist)}</div>
                </div>
                <div class="song-actions">
                    <button class="action-btn play" data-action="play" data-index="${index}" title="${escapeHtml(Locale.L('UI.music.play'))}">${ICONS.play}</button>
                    <button class="action-btn queue" data-action="queue" data-index="${index}" title="${escapeHtml(Locale.L('UI.music.addToQueue'))}">${ICONS.queueAdd}</button>
                </div>
            </div>`;
        }).join('');

        dropdown.hidden = false;

        dropdown.querySelectorAll('.action-btn').forEach((btn) => {
            btn.addEventListener('click', (event) => {
                event.stopPropagation();
                const index = Number(btn.dataset.index);
                const entry = results[index];
                if (!entry || entry.state !== 'ready') return;
                if (btn.dataset.action === 'play') {
                    playTrack(entry.track);
                    closeDropdown();
                } else {
                    addToQueue(entry.track);
                }
            });
        });

        dropdown.querySelectorAll('.search-result-item').forEach((row) => {
            row.addEventListener('click', () => {
                const index = Number(row.dataset.index);
                const entry = results[index];
                if (!entry || entry.state !== 'ready') return;
                playTrack(entry.track);
                closeDropdown();
            });
        });
    }

    function topSearchResult() {
        const results = currentSearchResults();
        const readyEntry = results.find((entry) => entry.state === 'ready');
        return readyEntry ? readyEntry.track : null;
    }

    function closeDropdown() {
        els['music-search-dropdown'].hidden = true;
    }

    const requestYoutubePreview = debounce(async (rawUrl, videoId) => {
        youtubePreview = { state: 'loading' };
        renderSearchDropdown();

        const result = await NUI.post('fetchYouTubeData', { url: rawUrl });

        // Stale response for a query the user has since changed/cleared.
        if (!youtubePreview || extractYoutubeVideoId(els['music-search-input'].value) !== videoId) return;

        if (result && result.success) {
            youtubePreview = {
                state: 'ready',
                track: normalizeTrack({
                    id: `yt:${videoId}`,
                    title: result.title || 'YouTube Video',
                    artist: 'YouTube',
                    url: rawUrl,
                    thumbnail: youtubeThumbnail(videoId),
                    isYouTube: true,
                    videoId,
                    duration: result.duration || 0,
                }),
            };
        } else {
            youtubePreview = { state: 'error' };
        }
        renderSearchDropdown();
    }, 450);

    function handleSearchInput() {
        const raw = els['music-search-input'].value;
        const videoId = extractYoutubeVideoId(raw);

        if (videoId) {
            requestYoutubePreview(raw, videoId);
        } else {
            youtubePreview = null;
        }
        renderSearchDropdown();
    }

    // --- queue / recent ------------------------------------------------------

    function addToQueue(track) {
        queue.push(track);
        if (activeTab === 'queue') renderQueueList();
    }

    function removeFromQueueAt(index) {
        queue.splice(index, 1);
        renderQueueList();
    }

    function playQueueItemAt(index) {
        const [track] = queue.splice(index, 1);
        if (track) playTrack(track);
        renderQueueList();
    }

    function advanceQueue() {
        if (queue.length === 0) {
            currentTrack = null;
            isPlaying = false;
            renderNowPlaying();
            return;
        }
        const [next] = queue.splice(0, 1);
        playTrack(next);
    }

    function renderQueueList() {
        const list = activeTab === 'queue' ? queue : recent;

        els['music-tab-queue'].classList.toggle('active', activeTab === 'queue');
        els['music-tab-recent'].classList.toggle('active', activeTab === 'recent');

        if (list.length === 0) {
            els['music-queue-empty'].hidden = false;
            els['music-queue-list'].hidden = true;
            els['music-queue-list'].innerHTML = '';
            return;
        }

        els['music-queue-empty'].hidden = true;
        els['music-queue-list'].hidden = false;

        els['music-queue-list'].innerHTML = list.map((track, index) => {
            const active = currentTrack && trackKey(currentTrack) === trackKey(track) ? ' active' : '';
            const img = track.thumbnail || 'assets/songimg.png';
            return `<div class="queue-item${active}" data-index="${index}">
                <img src="${escapeHtml(img)}" alt="" />
                <div class="music-name">
                    <div class="title">${escapeHtml(track.title)}</div>
                    <div class="author">${escapeHtml(track.artist)}</div>
                </div>
                <span class="duration">${track.duration ? formatTime(track.duration) : ''}</span>
                <div class="play-btn" data-index="${index}">${ICONS.play}</div>
            </div>`;
        }).join('');

        els['music-queue-list'].querySelectorAll('.queue-item, .play-btn').forEach((node) => {
            node.addEventListener('click', (event) => {
                event.stopPropagation();
                const index = Number(node.dataset.index);
                if (activeTab === 'queue') {
                    playQueueItemAt(index);
                } else {
                    playTrack(recent[index]);
                }
            });
        });
    }

    // --- YouTube IFrame Player -----------------------------------------------
    // Loaded lazily on first use; the player DOM node is created once and
    // reused (loadVideoById) rather than destroyed/rebuilt on every track
    // change, since YT.Player takes ownership of its target element.

    let youtubeApiReadyPromise = null;
    let youtubePlayer = null;
    let renderedVisualTrackKey = null;

    function loadYoutubeApi() {
        if (youtubeApiReadyPromise) return youtubeApiReadyPromise;

        youtubeApiReadyPromise = new Promise((resolve, reject) => {
            if (window.YT && window.YT.Player) {
                resolve(window.YT);
                return;
            }
            const previousCallback = window.onYouTubeIframeAPIReady;
            window.onYouTubeIframeAPIReady = () => {
                if (typeof previousCallback === 'function') previousCallback();
                resolve(window.YT);
            };
            const script = document.createElement('script');
            script.src = 'https://www.youtube.com/iframe_api';
            script.onerror = () => reject(new Error('Could not load the YouTube IFrame API'));
            document.head.appendChild(script);
            setTimeout(() => {
                if (!(window.YT && window.YT.Player)) reject(new Error('YouTube IFrame API timed out'));
            }, 12000);
        });

        return youtubeApiReadyPromise;
    }

    async function ensureYoutubePlayer() {
        if (youtubePlayer) return youtubePlayer;

        await loadYoutubeApi();
        youtubePlayer = await new Promise((resolve) => {
            const player = new YT.Player('music-youtube-target', {
                width: '100%',
                height: '100%',
                playerVars: {
                    autoplay: 0,
                    controls: 0,
                    enablejsapi: 1,
                    rel: 0,
                    modestbranding: 1,
                    playsinline: 1,
                    origin: window.location.origin,
                    widget_referrer: window.location.href,
                },
                events: {
                    // Muted: this player is for VISUALS only. sound-engine.js
                    // (js/sound-engine.js) loads the same video into its own
                    // hidden YouTube player and is the real, positional audio
                    // source -- Lua's play/pause/volume/lifecycle state machine
                    // is built around that one. Two unmuted players for the
                    // same video would play the audio twice.
                    onReady: (event) => { event.target.mute(); resolve(player); },
                    onStateChange: (event) => {
                        if (event.data === YT.PlayerState.ENDED) handleLocalPlaybackEnded();
                    },
                },
            });
        });
        return youtubePlayer;
    }

    async function playYoutubeTrack(track) {
        const key = trackKey(track);
        try {
            const player = await ensureYoutubePlayer();
            if (!currentTrack || trackKey(currentTrack) !== key || loadingTrack) return;
            player.mute();
            if (track.videoId) {
                player.loadVideoById(track.videoId);
            } else if (track.url) {
                player.loadVideoById(extractYoutubeVideoId(track.url) || '');
            }
            player.playVideo();
            showYoutubeEmbed();
            renderedVisualTrackKey = key;
        } catch (err) {
            if (currentTrack && trackKey(currentTrack) === key) {
                showVideoPlaceholder();
            }
        }
    }

    function showYoutubeEmbed() {
        els['music-video-placeholder'].hidden = true;
        els['music-youtube-embed'].hidden = false;
    }

    function showVideoPlaceholder() {
        renderedVisualTrackKey = null;
        els['music-youtube-embed'].hidden = true;
        if (youtubePlayer) {
            try { youtubePlayer.stopVideo(); } catch (err) { /* player not ready yet */ }
        }
        els['music-video-placeholder'].hidden = false;
    }

    function handleLocalPlaybackEnded() {
        // The visual YouTube iframe is muted and is not the authoritative
        // player. The positional sound engine reports the real end event;
        // advancing here creates a stop/new-track race.
        return;
    }

    // --- transport / now playing ---------------------------------------------

    async function playTrack(track) {
        if (!track) return;
        const requestSerial = ++playRequestSerial;
        currentTrack = track;
        loadingTrack = track;
        isPlaying = false;
        currentTime = 0;
        renderNowPlaying();

        const result = await NUI.post('playMusic', { song: track });
        if (requestSerial !== playRequestSerial) return;
        if (!result || result.success === false) {
            loadingTrack = null;
            currentTrack = null;
            isPlaying = false;
            renderNowPlaying();
            App.addNotification(Locale.L('UI.common.error'), result && result.error ? result.error : Locale.L('UI.common.error'));
        }
    }

    function renderNowPlaying() {
        if (!currentTrack) {
            loadingTrack = null;
            els['music-panel'].dataset.playbackState = 'idle';
            els['music-current-title'].textContent = '--';
            els['music-current-author'].textContent = '--';
            els['music-current-time'].textContent = '0:00';
            els['music-duration'].textContent = '0:00';
            els['music-timer-progress-filled'].style.width = '0%';
            els['music-toggle'].disabled = false;
            setToggleIcon(false);
            showVideoPlaceholder();
        } else {
            els['music-panel'].dataset.playbackState = loadingTrack ? 'loading' : (isPlaying ? 'playing' : 'paused');
            els['music-current-title'].textContent = currentTrack.title;
            els['music-current-author'].textContent = currentTrack.artist;
            els['music-duration'].textContent = formatTime(currentTrack.duration);
            els['music-toggle'].disabled = !!loadingTrack;
            setToggleIcon(loadingTrack ? false : isPlaying);

            if (currentTrack.isYouTube && !loadingTrack && renderedVisualTrackKey !== trackKey(currentTrack)) {
                playYoutubeTrack(currentTrack);
            } else {
                if (!currentTrack.isYouTube || loadingTrack) showVideoPlaceholder();
            }
        }

        renderQueueList();

        sharedState.song = currentTrack;
        sharedState.isPlaying = isPlaying;
        sharedState.currentTime = currentTime;
        sharedState.duration = currentTrack ? currentTrack.duration : 0;
        publishSharedState();
    }

    function setToggleIcon(playing) {
        els['music-toggle'].innerHTML = playing ? ICONS.pause : ICONS.play;
    }

    function updateElapsed(seconds) {
        currentTime = seconds;
        els['music-current-time'].textContent = formatTime(currentTime);
        const duration = currentTrack ? currentTrack.duration : 0;
        const fraction = duration > 0 ? Math.min(1, currentTime / duration) : 0;
        els['music-timer-progress-filled'].style.width = `${fraction * 100}%`;

        sharedState.currentTime = currentTime;
        publishSharedState();
    }

    async function pollElapsed() {
        if (!currentTrack || !isPlaying) return;

        if (currentTrack.isYouTube) {
            if (youtubePlayer && typeof youtubePlayer.getCurrentTime === 'function') {
                updateElapsed(youtubePlayer.getCurrentTime());
            }
            return;
        }

        const result = await NUI.post('getMusicTime', {});
        if (result && typeof result.currentTime === 'number') updateElapsed(result.currentTime);
    }

    function startPolling() {
        if (pollTimer) return;
        pollTimer = setInterval(pollElapsed, 1000);
    }

    function stopPolling() {
        if (!pollTimer) return;
        clearInterval(pollTimer);
        pollTimer = null;
    }

    function togglePlayback() {
        if (!currentTrack || loadingTrack) return;
        NUI.post('toggleMusic', {});
        if (currentTrack.isYouTube && youtubePlayer) {
            if (isPlaying) youtubePlayer.pauseVideo(); else youtubePlayer.playVideo();
        }
        // Optimistic flip; the authoritative state arrives via
        // 'updatePlaybackStatus' and will correct this if it mismatches.
        isPlaying = !isPlaying;
        setToggleIcon(isPlaying);
        sharedState.isPlaying = isPlaying;
        publishSharedState();
    }

    function seekBy(deltaSeconds) {
        if (!currentTrack) return;
        const duration = currentTrack.duration || Infinity;
        const target = Math.min(duration, Math.max(0, currentTime + deltaSeconds));
        seekTo(target);
    }

    function seekTo(seconds) {
        if (!currentTrack) return;
        NUI.post('seekMusic', { time: seconds });
        if (currentTrack.isYouTube && youtubePlayer) {
            youtubePlayer.seekTo(seconds, true);
        }
        updateElapsed(seconds);
    }

    function setVolume(next) {
        volume = Math.min(1, Math.max(0, next));
        els['music-volume-progress'].style.width = `${volume * 100}%`;
        els['music-volume-input'].value = String(volume);
        persistVolume();
        NUI.post('setMusicVolume', { volume });
        if (currentTrack && currentTrack.isYouTube && youtubePlayer) {
            youtubePlayer.setVolume(Math.round(volume * 100));
        }
    }

    // --- NUI incoming handlers -----------------------------------------------

    NUI.on('musicStarted', (data) => {
        if (!data || !data.song) return;
        currentTrack = normalizeTrack(data.song);
        loadingTrack = null;
        isPlaying = true;
        currentTime = 0;
        pushRecent(currentTrack);
        renderNowPlaying();
        if (screenVisible) startPolling();
    });

    NUI.on('updatePlaybackStatus', (data) => {
        if (!data) return;
        isPlaying = !!data.isPlaying;
        setToggleIcon(isPlaying);
        sharedState.isPlaying = isPlaying;
        publishSharedState();
        if (isPlaying && screenVisible) startPolling(); else if (!isPlaying) stopPolling();
    });

    NUI.on('musicError', (data) => {
        playRequestSerial += 1;
        loadingTrack = null;
        currentTrack = null;
        isPlaying = false;
        currentTime = 0;
        stopPolling();
        renderNowPlaying();
        App.addNotification(Locale.L('UI.common.error'), data && data.message ? data.message : Locale.L('UI.common.error'));
    });

    NUI.on('musicStopped', () => {
        playRequestSerial += 1;
        loadingTrack = null;
        currentTrack = null;
        isPlaying = false;
        currentTime = 0;
        stopPolling();
        renderNowPlaying();
    });

    NUI.on('trackEnded', () => {
        stopPolling();
        // The positional sound engine is authoritative for every format.
        // Keeping one end-event path prevents a muted visual YouTube iframe
        // from racing the real audio source.
        advanceQueue();
    });

    NUI.on('syncMusicState', (data) => {
        if (!data || !data.song) return;
        currentTrack = normalizeTrack(data.song);
        loadingTrack = null;
        isPlaying = !!data.isPlaying;
        currentTime = data.currentTime || 0;
        if (typeof data.volume === 'number') {
            volume = Math.min(1, Math.max(0, data.volume / 100));
            els['music-volume-progress'].style.width = `${volume * 100}%`;
            els['music-volume-input'].value = String(volume);
        }
        renderNowPlaying();
        updateElapsed(currentTime);
        if (isPlaying && screenVisible) startPolling();
    });

    // --- wiring ---------------------------------------------------------------

    function wireEvents() {
        const searchInput = els['music-search-input'];
        searchInput.addEventListener('input', handleSearchInput);
        searchInput.addEventListener('focus', () => renderSearchDropdown());
        searchInput.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') { closeDropdown(); searchInput.blur(); }
            if (event.key === 'Enter') {
                const top = topSearchResult();
                if (top) { playTrack(top); closeDropdown(); }
            }
        });

        document.addEventListener('click', (event) => {
            if (!els['music-search-bar'].contains(event.target)) closeDropdown();
        });

        els['music-header-play-btn'].addEventListener('click', () => {
            const top = topSearchResult();
            if (top) { playTrack(top); closeDropdown(); }
        });
        els['music-header-queue-btn'].addEventListener('click', () => {
            const top = topSearchResult();
            if (top) addToQueue(top);
        });

        els['music-toggle'].addEventListener('click', togglePlayback);
        els['music-seek-prev'].addEventListener('click', () => seekBy(-10));
        els['music-seek-next'].addEventListener('click', () => seekBy(10));
        els['music-next-track'].addEventListener('click', () => advanceQueue());
        els['music-prev-track'].addEventListener('click', () => {
            if (currentTime > 3) { seekTo(0); return; }
            const previous = recent[1]; // recent[0] is the current track itself
            if (previous) playTrack(previous); else seekTo(0);
        });

        els['music-volume-input'].addEventListener('input', (event) => {
            setVolume(parseFloat(event.target.value));
        });

        els['music-timer-progress'].addEventListener('click', (event) => {
            if (!currentTrack || !currentTrack.duration) return;
            const rect = event.currentTarget.getBoundingClientRect();
            const fraction = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width));
            seekTo(fraction * currentTrack.duration);
        });

        els['music-tab-queue'].addEventListener('click', () => { activeTab = 'queue'; renderQueueList(); });
        els['music-tab-recent'].addEventListener('click', () => { activeTab = 'recent'; renderQueueList(); });

        els['music-clear-btn'].addEventListener('click', () => {
            if (activeTab === 'queue') queue = []; else { recent = []; persistRecent(); }
            renderQueueList();
        });

        document.addEventListener('localechange', renderStaticText);
    }

    // --- screen lifecycle ------------------------------------------------

    function onShow() {
        screenVisible = true;
        els['music-volume-progress'].style.width = `${volume * 100}%`;
        els['music-volume-input'].value = String(volume);
        ensureLibraryLoaded().then(() => renderSearchDropdown());
        NUI.post('getMusicState', {});
        if (currentTrack && isPlaying) startPolling();
    }

    function onHide() {
        screenVisible = false;
        stopPolling();
        closeDropdown();
    }

    function init() {
        buildSkeleton();
        loadPersisted();
        wireEvents();
        renderStaticText();
        App.registerScreen('music', {
            el: document.getElementById('music-panel'),
            onShow,
            onHide,
        });
    }

    init();

    return { getState: () => ({ ...sharedState }) };
})();
