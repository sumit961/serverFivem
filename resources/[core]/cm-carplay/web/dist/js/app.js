// cm-carplay web UI -- shell: menu open/close, theme color, header (clock,
// weather, notifications, profile), bottom-nav / screen switching.
//
// Screen modules (home.js, manage.js, statistics.js, modifications.js,
// music.js) each call App.registerScreen(name, screen) once,
// where `screen` is:
//   {
//     el: HTMLElement,       // the <section class="X-panel"> to show/hide
//     onShow?: () => void,   // called every time this screen becomes visible
//     onHide?: () => void,   // called every time it's hidden
//   }
// `name` must match one of Locale's UI.navigation keys (home, music,
// manage, statistics, modifications) -- that's how the bottom
// nav label/order is derived.

const App = (() => {
    const screens = new Map(); // name -> { el, onShow, onHide }
    let activeScreen = null;
    let notifications = []; // { id, title, message, time, read }
    let notificationId = 0;

    const els = {
        container: document.getElementById('carplay-container'),
        tabletContainer: document.getElementById('tablet-container'),
        floatingDock: document.getElementById('floating-dock'),
        bottomNav: document.getElementById('bottom-nav'),
        headerTime: document.getElementById('header-time'),
        headerDate: document.getElementById('header-date'),
        weatherTemp: document.getElementById('header-weather-temp'),
        weatherCondition: document.getElementById('header-weather-condition'),
        notificationWrapper: document.getElementById('notification-wrapper'),
        notificationIcon: document.getElementById('notification-icon'),
        notificationDropdown: document.getElementById('notification-dropdown'),
        notificationList: document.getElementById('notification-list'),
        notificationsMarkRead: document.getElementById('notifications-mark-read'),
        profileWrapper: document.getElementById('profile-wrapper'),
        profileButton: document.getElementById('profile-button'),
        profileDropdown: document.getElementById('profile-dropdown'),
        profileName: document.getElementById('profile-name'),
        profilePlate: document.getElementById('profile-plate'),
        profileRemoveTunerChip: document.getElementById('profile-remove-tunerchip'),
        profileClose: document.getElementById('profile-close'),
    };

    // --- theme -----------------------------------------------------------

    function hexToRgb(hex) {
        const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || '');
        if (!match) return null;
        return [parseInt(match[1], 16), parseInt(match[2], 16), parseInt(match[3], 16)].join(', ');
    }

    NUI.on('updatePrimaryColor', (hex) => {
        if (!hex) return;
        document.documentElement.style.setProperty('--color-primary', hex);
        const rgb = hexToRgb(hex);
        if (rgb) document.documentElement.style.setProperty('--color-primary-rgb', rgb);
    });

    // --- open / close ------------------------------------------------------

    function hideFloatingDock() {
        els.floatingDock.hidden = true;
        els.floatingDock.innerHTML = '';
    }

    NUI.on('setVisible', (visible) => {
        if (visible) {
            els.container.hidden = false;
            els.tabletContainer.hidden = false;
            hideFloatingDock();
            return;
        }

        els.notificationDropdown.hidden = true;
        els.profileDropdown.hidden = true;

        els.container.hidden = true;
        els.tabletContainer.hidden = false;
    });

    NUI.on('navigateHome', () => switchScreen('home'));

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && !els.container.hidden) {
            NUI.post('closeMenu');
        }
    });

    // --- header: clock / date --------------------------------------------

    const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july',
        'august', 'september', 'october', 'november', 'december'];

    NUI.on('updateGameTime', (data) => {
        if (!data) return;
        const hours = String(data.hour ?? 0).padStart(2, '0');
        const minutes = String(data.minute ?? 0).padStart(2, '0');
        els.headerTime.textContent = `${hours}:${minutes}`;

        if (data.day && data.month) {
            const monthKey = MONTHS[(data.month - 1 + 12) % 12];
            els.headerDate.textContent = `${data.day} ${Locale.L(`UI.months.${monthKey}`)}`;
        }
    });

    // --- header: weather ---------------------------------------------------

    // getWeatherInfo() in client/main.lua sends { type: "CLEAR"|"EXTRASUNNY"|...,
    // temperature: number } -- GTA weather-type names, not locale keys directly.
    const WEATHER_TYPE_TO_LOCALE_KEY = {
        EXTRASUNNY: 'sunny', CLEAR: 'clear', CLOUDS: 'cloudy', SMOG: 'smog',
        FOGGY: 'foggy', OVERCAST: 'overcast', RAIN: 'rain', THUNDER: 'thunder',
        CLEARING: 'clearing', NEUTRAL: 'neutral', SNOW: 'snow', BLIZZARD: 'blizzard',
        SNOWLIGHT: 'lightSnow', XMAS: 'xmas',
    };

    NUI.on('updateWeather', (data) => {
        if (!data) return;
        if (data.temperature !== undefined) {
            els.weatherTemp.textContent = `${Math.round(data.temperature)}°`;
        }
        const localeKey = WEATHER_TYPE_TO_LOCALE_KEY[data.type];
        if (localeKey) {
            els.weatherCondition.textContent = Locale.L(`UI.weather.${localeKey}`);
        }
    });

    // --- header: player profile / plate ------------------------------------

    NUI.on('updatePlayerProfile', (data) => {
        if (!data) return;
        if (data.name) els.profileName.textContent = data.name;
    });

    NUI.on('updateVehiclePlate', (plate) => {
        els.profilePlate.textContent = plate || Locale.L('UI.header.noVehicle');
    });

    // --- notifications -------------------------------------------------------

    function renderNotifications() {
        els.notificationList.innerHTML = '';
        for (const note of notifications) {
            const item = document.createElement('div');
            item.className = 'notification-item' + (note.read ? '' : ' unread');
            item.innerHTML = `
                <div class="notification-content">
                    <div class="notification-title">${note.title}</div>
                    <div class="notification-message">${note.message}</div>
                </div>
                <div class="notification-meta">
                    ${note.read ? '' : '<span class="unread-dot"></span>'}
                    <span class="notification-time">${note.time}</span>
                </div>`;
            item.addEventListener('click', () => {
                note.read = true;
                renderNotifications();
            });
            els.notificationList.appendChild(item);
        }
    }

    function addNotification(title, message) {
        notifications.unshift({
            id: ++notificationId,
            title,
            message,
            time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
            read: false,
        });
        notifications = notifications.slice(0, 30);
        renderNotifications();
    }

    els.notificationIcon.addEventListener('click', () => {
        els.notificationDropdown.hidden = !els.notificationDropdown.hidden;
        els.profileDropdown.hidden = true;
    });

    els.notificationsMarkRead.addEventListener('click', () => {
        notifications.forEach((n) => { n.read = true; });
        renderNotifications();
    });

    // --- profile dropdown --------------------------------------------------

    els.profileButton.addEventListener('click', () => {
        els.profileDropdown.hidden = !els.profileDropdown.hidden;
        els.notificationDropdown.hidden = true;
    });

    els.profileRemoveTunerChip.addEventListener('click', () => {
        els.profileDropdown.hidden = true;
        NUI.post('removeTunerChip');
    });

    els.profileClose.addEventListener('click', () => {
        els.profileDropdown.hidden = true;
        NUI.post('closeMenu');
    });

    document.addEventListener('click', (event) => {
        if (!els.notificationWrapper.contains(event.target)) els.notificationDropdown.hidden = true;
        if (!els.profileWrapper.contains(event.target)) els.profileDropdown.hidden = true;
    });

    // --- screens / bottom nav ------------------------------------------------

    function registerScreen(name, screen) {
        screens.set(name, screen);
    }

    function switchScreen(name) {
        const next = screens.get(name);
        if (!next) return;

        els.tabletContainer.hidden = false;

        if (activeScreen && activeScreen !== next) {
            activeScreen.el.hidden = true;
            activeScreen.onHide?.();
        }
        next.el.hidden = false;
        activeScreen = next;
        next.onShow?.();

        for (const item of els.bottomNav.children) {
            item.classList.toggle('active', item.dataset.screen === name);
        }
    }

    function buildBottomNav() {
        els.bottomNav.innerHTML = '';
        const order = ['home', 'manage', 'statistics', 'modifications', 'music'];
        const icons = {
            home: 'M3 10.5 12 3l9 7.5M5 9.5V21h14V9.5M9 21v-6h6v6',
            manage: 'M4 6h16M4 12h16M4 18h16M8 6v0M15 12v0M11 18v0',
            statistics: 'M5 20V10M12 20V4M19 20v-7',
            modifications: 'm14.7 6.3 3 3M4.5 19.5l6.9-6.9M14 4a5 5 0 0 0 6 6l-4 4-2-2-4 4-2-2 4-4-2-2z',
            music: 'M9 18V5l12-2v13M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6M18 19a3 3 0 1 0 0-6 3 3 0 0 0 0 6',
        };
        for (const name of order) {
            const item = document.createElement('button');
            item.className = 'nav-item';
            item.type = 'button';
            item.dataset.screen = name;
            item.innerHTML = `<svg class="nav-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${icons[name] || icons.home}" /></svg><span data-i18n="UI.navigation.${name}">${Locale.L(`UI.navigation.${name}`)}</span>`;
            item.addEventListener('click', () => switchScreen(name));
            els.bottomNav.appendChild(item);
        }
    }

    document.addEventListener('localechange', () => {
        buildBottomNav();
        // Re-apply every data-i18n label now that the table changed.
        document.querySelectorAll('[data-i18n]').forEach((el) => {
            el.textContent = Locale.L(el.dataset.i18n);
        });
        if (!activeScreen) switchScreen('home');
    });

    return { registerScreen, switchScreen, addNotification };
})();
