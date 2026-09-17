// cm-carplay web UI -- Home screen.
//
// Landing screen: a static overview map, a climate/weather widget, a quick
// "vehicle options" card that jumps to Manage, and a "now playing" mini
// music widget.
//
// Real data sources (see client/main.lua):
//   NUI.on('updateWeather')   -> { type: "CLEAR", temperature: 24 }   (GTA weather hash name + °C)
//   NUI.on('updateWaypoint')  -> { active, x, y, z, distance, streetName } | null
//   NUI.on('musicStarted')    -> { song, audioSourceId }
//   NUI.on('musicStopped')    -> true
//   NUI.on('trackEnded')      -> true
//   NUI.on('syncMusicState')  -> { song, isPlaying, volume, currentTime, audioSourceId }
//   NUI.on('updatePlaybackStatus') -> { isPlaying }
//   NUI.post('toggleMusic')   -- play/pause the current song
//   NUI.post('seekMusic', { time })
//   NUI.post('getMusicTime')  -- fire-and-forget; server doesn't reply to this
//                                 poller directly, it just keeps GetCurrentTime
//                                 flowing through syncMusicState on request.
//   NUI.post('getMusicState') -- asks Lua to broadcast a fresh 'syncMusicState'
//
// Note: app.js's own 'updateWeather' handler (header pill) reads
// `data.temp` / `data.condition`, but main.lua actually sends
// `data.temperature` / `data.type` (a GTA weather hash name, e.g. "CLEAR").
// That mismatch lives in app.js (out of scope here -- see report), so this
// file registers its own 'updateWeather' listener using the real field names.

const Home = (() => {
    const el = document.getElementById('home-panel');

    // GTA weather hash name -> UI.weather.* locale key.
    const WEATHER_LOCALE_KEY = {
        EXTRASUNNY: 'sunny',
        CLEAR: 'clear',
        CLOUDS: 'cloudy',
        SMOG: 'smog',
        FOGGY: 'foggy',
        OVERCAST: 'overcast',
        RAIN: 'rain',
        THUNDER: 'thunder',
        CLEARING: 'clearing',
        NEUTRAL: 'neutral',
        SNOW: 'snow',
        BLIZZARD: 'blizzard',
        SNOWLIGHT: 'lightSnow',
        XMAS: 'xmas',
    };

    // Small icon set, bucketed by weather hash name. Purely decorative --
    // no icon assets ship for weather, so these are simple inline shapes.
    const WEATHER_ICON_BUCKET = {
        EXTRASUNNY: 'sun', CLEAR: 'sun', NEUTRAL: 'sun',
        CLOUDS: 'cloud', SMOG: 'cloud', FOGGY: 'cloud', OVERCAST: 'cloud', CLEARING: 'cloud',
        RAIN: 'rain', THUNDER: 'storm',
        SNOW: 'snow', BLIZZARD: 'snow', SNOWLIGHT: 'snow', XMAS: 'snow',
    };

    const ICONS = {
        sun: '<circle cx="12" cy="12" r="5"/><path d="M12 1v3M12 20v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M1 12h3M20 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/>',
        cloud: '<path d="M7 18a4.5 4.5 0 0 1-.6-8.96A5.5 5.5 0 0 1 17.2 8.1 4 4 0 0 1 17 18H7z"/>',
        rain: '<path d="M7 15a4.5 4.5 0 0 1-.6-8.96A5.5 5.5 0 0 1 17.2 5.1 4 4 0 0 1 17 15H7z"/><path d="M8 18l-1 3M12 18l-1 3M16 18l-1 3" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/>',
        storm: '<path d="M7 13a4.5 4.5 0 0 1-.6-8.96A5.5 5.5 0 0 1 17.2 3.1 4 4 0 0 1 17 13H7z"/><path d="M13 13l-3 5h3l-2 4" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linejoin="round" stroke-linecap="round"/>',
        snow: '<path d="M7 13a4.5 4.5 0 0 1-.6-8.96A5.5 5.5 0 0 1 17.2 3.1 4 4 0 0 1 17 13H7z"/><path d="M9 17v5M7 19l2-1 2 1M15 17v5M13 19l2-1 2 1" stroke="currentColor" stroke-width="1.3" fill="none" stroke-linecap="round"/>',
    };

    function weatherIconSvg(weatherType) {
        const bucket = WEATHER_ICON_BUCKET[weatherType] || 'sun';
        return `<svg viewBox="0 0 24 24">${ICONS[bucket]}</svg>`;
    }

    // --- state -------------------------------------------------------------

    let lastWeather = null; // { type, temperature }
    let currentSong = null; // song object from Lua, or null
    let isMusicPlaying = false;
    let currentTime = 0;
    let musicPollHandle = null;

    // --- build DOM (once) ----------------------------------------------------

    el.innerHTML = `
        <div class="map-container">
            <div class="map-view-container" id="home-map"></div>
            <button class="map-recenter-button" id="home-map-recenter" type="button" title="Recenter on vehicle" aria-label="Recenter map on vehicle">
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2 5 20l7-3 7 3-7-18z"/></svg>
            </button>
            <div class="overlay" id="home-map-overlay" hidden>
                <div class="navigation-info">
                    <svg viewBox="0 0 24 24" width="16" height="16"><path d="M12 2 4 20l8-4 8 4-8-18z"/></svg>
                    <span class="street-name" id="home-street-name">--</span>
                    <div class="distance-container">
                        <span data-i18n="UI.home.distance">Distance</span>
                        <span class="distance" id="home-distance">--</span>
                    </div>
                </div>
                <div class="progress-container"><div class="progress"></div></div>
            </div>
        </div>

        <div class="middle-section">
            <div class="climate-container">
                <div class="header">
                    <div class="title" data-i18n="UI.home.climate">Climate</div>
                    <div class="location" data-i18n="UI.home.location">Los Santos</div>
                </div>
                <div class="weather-container">
                    <span class="temp" id="home-weather-temp">--&deg;</span>
                    <span id="home-weather-icon">${weatherIconSvg('CLEAR')}</span>
                </div>
                <div class="weather-forecast">
                    <div class="title" data-i18n="UI.home.forecast">Forecast</div>
                    <div class="subtitle" id="home-weather-condition">--</div>
                    <div class="forecasts">
                        <div class="forecast-card now">
                            <span class="time" data-i18n="UI.home.now">NOW</span>
                            <span id="home-forecast-icon">${weatherIconSvg('CLEAR')}</span>
                            <span class="temp" id="home-forecast-temp">--&deg;</span>
                        </div>
                    </div>
                </div>
            </div>

            <div class="manage-container">
                <div class="title" data-i18n="UI.home.manage">Manage</div>
                <div class="subtitle" data-i18n="UI.home.vehicleOptions">Vehicle Options</div>
                <div class="actions-container">
                    <div class="action-card" id="home-manage-card">
                        <svg viewBox="0 0 24 24" width="22" height="22"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l2.8-2.8a5 5 0 0 1-6.9 6.9L6.7 20.3a2 2 0 1 1-2.8-2.8l6.9-6.9a5 5 0 0 1 6.9-6.9l-2.8 2.8z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>
                        <div class="indicator" id="home-manage-indicator"></div>
                    </div>
                </div>
            </div>
        </div>

        <div class="music-section">
            <div class="no-music" id="home-no-music">
                <svg class="no-music-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>
                <div class="no-music-title" data-i18n="UI.home.noSong">No Song</div>
                <div class="no-music-subtitle" data-i18n="UI.home.emptyTrack">Empty track</div>
            </div>
            <img class="song-image" id="home-song-image" src="assets/songimg.png" alt="" hidden />
            <div class="song-details" id="home-song-details">
                <div class="title" id="home-song-title"></div>
                <div class="artist" id="home-song-artist"></div>
            </div>
            <div class="song-controls" id="home-song-controls" hidden>
                <div class="song-progress">
                    <div class="time-labels">
                        <span class="current-time" id="home-current-time">0:00</span>
                        <span class="total-time" id="home-total-time">0:00</span>
                    </div>
                    <div class="progress-bar" id="home-progress-bar">
                        <div class="progress" id="home-progress-fill">
                            <span class="progress-thumb"></span>
                        </div>
                    </div>
                </div>
                <div class="buttons-container">
                    <button class="seek-prev" id="home-seek-prev" type="button" aria-label="Seek back 10s">
                        <svg viewBox="0 0 24 24" width="20" height="20"><path d="M11 5V1L5 7l6 6V9c3.3 0 6 2.7 6 6s-2.7 6-6 6-6-2.7-6-6H3c0 4.4 3.6 8 8 8s8-3.6 8-8-3.6-8-8-8z" fill="currentColor"/></svg>
                    </button>
                    <button class="toggle-music" id="home-toggle-music" type="button" aria-label="Play/Pause">
                        <svg id="home-toggle-icon" viewBox="0 0 24 24" width="16" height="16"><path d="M8 5v14l11-7z" fill="currentColor"/></svg>
                    </button>
                    <button class="seek-next" id="home-seek-next" type="button" aria-label="Seek forward 10s">
                        <svg viewBox="0 0 24 24" width="20" height="20"><path d="M13 5V1l6 6-6 6V9c-3.3 0-6 2.7-6 6s2.7 6 6 6 6-2.7 6-6h2c0 4.4-3.6 8-8 8s-8-3.6-8-8 3.6-8 8-8z" fill="currentColor"/></svg>
                    </button>
                </div>
            </div>
        </div>
    `;

    const els = {
        map: document.getElementById('home-map'),
        mapRecenter: document.getElementById('home-map-recenter'),
        mapOverlay: document.getElementById('home-map-overlay'),
        streetName: document.getElementById('home-street-name'),
        distance: document.getElementById('home-distance'),
        weatherTemp: document.getElementById('home-weather-temp'),
        weatherIcon: document.getElementById('home-weather-icon'),
        weatherCondition: document.getElementById('home-weather-condition'),
        forecastTemp: document.getElementById('home-forecast-temp'),
        forecastIcon: document.getElementById('home-forecast-icon'),
        manageCard: document.getElementById('home-manage-card'),
        noMusic: document.getElementById('home-no-music'),
        songImage: document.getElementById('home-song-image'),
        songDetails: document.getElementById('home-song-details'),
        songTitle: document.getElementById('home-song-title'),
        songArtist: document.getElementById('home-song-artist'),
        songControls: document.getElementById('home-song-controls'),
        currentTime: document.getElementById('home-current-time'),
        totalTime: document.getElementById('home-total-time'),
        progressBar: document.getElementById('home-progress-bar'),
        progressFill: document.getElementById('home-progress-fill'),
        seekPrev: document.getElementById('home-seek-prev'),
        seekNext: document.getElementById('home-seek-next'),
        toggleMusicBtn: document.getElementById('home-toggle-music'),
        toggleIcon: document.getElementById('home-toggle-icon'),
    };

    els.manageCard.addEventListener('click', () => App.switchScreen('manage'));

    // --- overview map ----------------------------------------------------
    // Reuse cm-admin's exact stitched atlas and effective calibrated bounds.
    // CRS.Simple treats longitude as world X and latitude as world Y, so a
    // GTA coordinate maps directly to [worldY, worldX].
    const ADMIN_MAP_IMAGE_URL = 'https://cfx-nui-cm-admin/ui/assets/gta-map-local.png';
    const DEFAULT_MAP_BOUNDS = { minX: -4000, maxX: 4500, minY: -4300, maxY: 8000 };
    const DEFAULT_NAVIGATION_ZOOM = -1.5;
    let leafletMap = null;
    let mapImageLayer = null;
    let playerMarker = null;
    let waypointMarker = null;
    let mapBounds = { ...DEFAULT_MAP_BOUNDS };
    let lastPosition = null; // { x, y, z, heading } from updatePlayerPosition
    let mapResizeObserver = null;
    let followPlayer = true;
    let hasNavigationView = false;

    function cleanMapBounds(input) {
        if (!input || typeof input !== 'object') return { ...DEFAULT_MAP_BOUNDS };
        const minX = Number(input.minX);
        const maxX = Number(input.maxX);
        const minY = Number(input.minY);
        const maxY = Number(input.maxY);
        const values = [minX, maxX, minY, maxY];
        if (!values.every(Number.isFinite)
            || maxX <= minX || maxY <= minY
            || values.some((value) => Math.abs(value) > 20000)) {
            return { ...DEFAULT_MAP_BOUNDS };
        }
        return { minX, maxX, minY, maxY };
    }

    function leafletImageBounds() {
        return [[mapBounds.minY, mapBounds.minX], [mapBounds.maxY, mapBounds.maxX]];
    }

    function playerLatLng() {
        if (!lastPosition) return null;
        const x = Number(lastPosition.x);
        const y = Number(lastPosition.y);
        return Number.isFinite(x) && Number.isFinite(y) ? [y, x] : null;
    }

    function setFollowPlayer(enabled) {
        followPlayer = enabled;
        els.mapRecenter.classList.toggle('is-following', enabled);
    }

    function centerMapOnPlayer(resetZoom = false) {
        const position = playerLatLng();
        if (!leafletMap || !position) return false;
        const zoom = resetZoom || !hasNavigationView
            ? DEFAULT_NAVIGATION_ZOOM
            : leafletMap.getZoom();
        leafletMap.setView(position, zoom, { animate: false });
        hasNavigationView = true;
        return true;
    }

    function refitMapToPanel() {
        if (!leafletMap || els.map.offsetWidth < 1 || els.map.offsetHeight < 1) return;

        leafletMap.invalidateSize({ animate: false, pan: false });
        if (followPlayer && centerMapOnPlayer(!hasNavigationView)) return;
        if (hasNavigationView) return;

        const size = leafletMap.getSize();
        const worldWidth = mapBounds.maxX - mapBounds.minX;
        const worldHeight = mapBounds.maxY - mapBounds.minY;

        // Use a fractional CRS.Simple zoom that covers the whole CarPlay map
        // panel. The narrower panel crops only the outside edges of the atlas;
        // the world-coordinate projection itself remains unchanged.
        const coverZoom = Math.max(
            Math.log2(size.x / worldWidth),
            Math.log2(size.y / worldHeight),
        );
        const zoom = Math.min(2, Math.max(-5, coverZoom));
        const center = [
            (mapBounds.minY + mapBounds.maxY) / 2,
            (mapBounds.minX + mapBounds.maxX) / 2,
        ];
        leafletMap.setView(center, zoom, { animate: false });
    }

    function scheduleMapRefit() {
        requestAnimationFrame(() => requestAnimationFrame(refitMapToPanel));
    }

    function installMapImage() {
        if (!leafletMap) return;
        if (mapImageLayer) mapImageLayer.remove();
        const bounds = leafletImageBounds();
        mapImageLayer = L.imageOverlay(ADMIN_MAP_IMAGE_URL, bounds, {
            interactive: false,
            opacity: 0.96,
        }).addTo(leafletMap);
        leafletMap.setMaxBounds(bounds);
        scheduleMapRefit();
    }

    function initMap() {
        if (leafletMap || typeof L === 'undefined') return;
        leafletMap = L.map(els.map, {
            crs: L.CRS.Simple,
            zoomControl: false,
            attributionControl: false,
            dragging: true,
            scrollWheelZoom: true,
            doubleClickZoom: false,
            boxZoom: false,
            keyboard: false,
            touchZoom: true,
            minZoom: -5,
            maxZoom: 2,
            zoomSnap: 0.25,
            zoomDelta: 0.5,
            maxBoundsViscosity: 1,
        });
        installMapImage();
        renderPlayerMarker();

        leafletMap.on('dragstart', () => setFollowPlayer(false));
        leafletMap.on('click', (event) => {
            const x = Number(event.latlng.lng);
            const y = Number(event.latlng.lat);
            if (!Number.isFinite(x) || !Number.isFinite(y)
                || x < mapBounds.minX || x > mapBounds.maxX
                || y < mapBounds.minY || y > mapBounds.maxY) return;

            setFollowPlayer(false);
            renderWaypointMarker({ active: true, x, y });
            NUI.post('setWaypoint', { x, y });
        });
        els.map.addEventListener('wheel', () => setFollowPlayer(false), { passive: true });

        if (typeof ResizeObserver === 'function') {
            mapResizeObserver = new ResizeObserver(scheduleMapRefit);
            mapResizeObserver.observe(els.map);
        }
        scheduleMapRefit();
    }

    function renderPlayerMarker() {
        if (!leafletMap) return;
        const position = playerLatLng();
        if (!position) return;
        if (!playerMarker) {
            const icon = L.divIcon({
                className: 'carplay-map-player-icon',
                html: '<span class="carplay-map-player-arrow"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1 21 22 12 18 3 22z"/></svg></span>',
                iconSize: [24, 24],
                iconAnchor: [12, 12],
            });
            playerMarker = L.marker(position, {
                icon,
                interactive: false,
                zIndexOffset: 1000,
            }).addTo(leafletMap);
        } else {
            playerMarker.setLatLng(position);
        }

        const heading = Number(lastPosition.heading);
        requestAnimationFrame(() => {
            const arrow = playerMarker?.getElement()?.querySelector('.carplay-map-player-arrow');
            if (arrow) arrow.style.transform = `rotate(${Number.isFinite(heading) ? heading : 0}deg)`;
        });

        if (followPlayer && els.map.offsetWidth > 0) {
            centerMapOnPlayer(!hasNavigationView);
        }
    }

    function renderWaypointMarker(data) {
        const x = Number(data && data.x);
        const y = Number(data && data.y);
        if (!data || !data.active || !Number.isFinite(x) || !Number.isFinite(y)) {
            if (waypointMarker) {
                waypointMarker.remove();
                waypointMarker = null;
            }
            return;
        }

        const position = [y, x];
        if (!waypointMarker) {
            const icon = L.divIcon({
                className: 'carplay-map-waypoint-icon',
                html: '<span class="carplay-map-waypoint-pin"><svg viewBox="0 0 24 30" aria-hidden="true"><path d="M12 1C5.9 1 1 5.9 1 12c0 8.1 11 17 11 17s11-8.9 11-17C23 5.9 18.1 1 12 1z"/><circle cx="12" cy="12" r="4"/></svg></span>',
                iconSize: [24, 30],
                iconAnchor: [12, 29],
            });
            waypointMarker = L.marker(position, {
                icon,
                interactive: false,
                zIndexOffset: 900,
            }).addTo(leafletMap);
        } else {
            waypointMarker.setLatLng(position);
        }
    }

    NUI.on('updatePlayerPosition', (data) => {
        if (!data) return;
        lastPosition = data;
        renderPlayerMarker();
    });

    NUI.on('updateMapBounds', (data) => {
        mapBounds = cleanMapBounds(data);
        installMapImage();
        renderPlayerMarker();
    });

    // The initial locale message can select Home while its parent is still
    // display:none. Refit after CarPlay becomes visible so Leaflet never keeps
    // the zero-size initialization zoom seen as a tiny top-left map image.
    NUI.on('setVisible', (visible) => {
        if (visible) {
            hasNavigationView = false;
            setFollowPlayer(true);
            scheduleMapRefit();
        }
    });

    els.mapRecenter.addEventListener('click', () => {
        setFollowPlayer(true);
        centerMapOnPlayer(true);
    });

    // --- weather -----------------------------------------------------------

    NUI.on('updateWeather', (data) => {
        if (!data) return;
        lastWeather = data;
        renderWeather();
    });

    function renderWeather() {
        if (!lastWeather) return;
        const temp = Math.round(lastWeather.temperature ?? 0);
        els.weatherTemp.textContent = `${temp}°`;
        els.forecastTemp.textContent = `${temp}°`;
        const icon = weatherIconSvg(lastWeather.type);
        els.weatherIcon.innerHTML = icon;
        els.forecastIcon.innerHTML = icon;
        const localeKey = WEATHER_LOCALE_KEY[lastWeather.type] || 'clear';
        els.weatherCondition.textContent = Locale.L(`UI.weather.${localeKey}`);
    }

    // --- waypoint / distance -------------------------------------------------

    NUI.on('updateWaypoint', (data) => {
        renderWaypointMarker(data);
        if (!data || !data.active) {
            els.mapOverlay.hidden = true;
            return;
        }
        els.mapOverlay.hidden = false;
        els.streetName.textContent = data.streetName || '--';
        els.distance.textContent = `${Math.max(0, Math.round(data.distance || 0))}m`;
    });

    // --- music mini-widget ---------------------------------------------------

    function formatTime(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return `${m}:${String(r).padStart(2, '0')}`;
    }

    function renderMusic() {
        const hasSong = !!currentSong;
        els.noMusic.hidden = hasSong;
        els.songImage.hidden = !hasSong;
        els.songControls.hidden = !hasSong;
        els.songDetails.classList.toggle('player-info', hasSong);

        if (!hasSong) return;

        els.songTitle.textContent = currentSong.title || Locale.L('UI.home.noSong');
        els.songArtist.textContent = currentSong.artist || '';

        const duration = currentSong.duration || 0;
        els.currentTime.textContent = formatTime(currentTime);
        els.totalTime.textContent = duration > 0 ? formatTime(duration) : '--:--';
        const pct = duration > 0 ? Math.min(100, (currentTime / duration) * 100) : 0;
        els.progressFill.style.width = `${pct}%`;

        els.toggleIcon.innerHTML = isMusicPlaying
            ? '<path d="M6 5h4v14H6zM14 5h4v14h-4z" fill="currentColor"/>'
            : '<path d="M8 5v14l11-7z" fill="currentColor"/>';
    }

    function stopMusicPolling() {
        if (musicPollHandle) {
            clearInterval(musicPollHandle);
            musicPollHandle = null;
        }
    }

    function startMusicPolling() {
        stopMusicPolling();
        musicPollHandle = setInterval(async () => {
            if (!currentSong) return;
            const result = await NUI.post('getMusicTime');
            if (result && typeof result.currentTime === 'number') {
                currentTime = result.currentTime;
                renderMusic();
            }
        }, 1000);
    }

    NUI.on('musicStarted', (data) => {
        currentSong = (data && data.song) || null;
        isMusicPlaying = true;
        currentTime = 0;
        renderMusic();
    });

    NUI.on('musicStopped', () => {
        currentSong = null;
        isMusicPlaying = false;
        currentTime = 0;
        renderMusic();
    });

    NUI.on('trackEnded', () => {
        currentSong = null;
        isMusicPlaying = false;
        currentTime = 0;
        renderMusic();
    });

    NUI.on('updatePlaybackStatus', (data) => {
        isMusicPlaying = !!(data && data.isPlaying);
        renderMusic();
    });

    NUI.on('syncMusicState', (data) => {
        if (!data) return;
        currentSong = data.song || currentSong;
        isMusicPlaying = !!data.isPlaying;
        if (typeof data.currentTime === 'number') currentTime = data.currentTime;
        renderMusic();
    });

    els.toggleMusicBtn.addEventListener('click', () => {
        NUI.post('toggleMusic');
    });

    els.seekPrev.addEventListener('click', () => {
        if (!currentSong) return;
        currentTime = Math.max(0, currentTime - 10);
        NUI.post('seekMusic', { time: currentTime });
        renderMusic();
    });

    els.seekNext.addEventListener('click', () => {
        if (!currentSong) return;
        currentTime = currentTime + 10;
        NUI.post('seekMusic', { time: currentTime });
        renderMusic();
    });

    els.progressBar.addEventListener('click', (event) => {
        if (!currentSong || !currentSong.duration) return;
        const rect = els.progressBar.getBoundingClientRect();
        const ratio = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width));
        currentTime = ratio * currentSong.duration;
        NUI.post('seekMusic', { time: currentTime });
        renderMusic();
    });

    document.addEventListener('localechange', () => {
        renderWeather();
        renderMusic();
    });

    // --- screen registration -------------------------------------------------

    App.registerScreen('home', {
        el,
        onShow() {
            initMap();
            setFollowPlayer(true);
            scheduleMapRefit();
            renderWeather();
            renderMusic();
            NUI.post('getMusicState');
            startMusicPolling();
        },
        onHide() {
            stopMusicPolling();
        },
    });

    return {};
})();
