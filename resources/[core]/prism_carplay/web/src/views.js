import { clockLabel, formatDuration, weatherLabel } from "./state.js";

const esc = (value) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");

const icon = (name) => {
  const icons = {
    home: "⌂",
    car: "▣",
    map: "⌖",
    music: "♫",
    tune: "⚙",
    neon: "✦",
    camera: "◉",
    record: "●",
    close: "×",
    lock: "▣",
    engine: "◈",
    light: "☼",
    window: "▤",
    door: "□",
    seat: "♙",
    arrow: "›",
    play: "▶",
    pause: "Ⅱ",
  };
  return `<span class="icon" aria-hidden="true">${icons[name] || "•"}</span>`;
};

function tabButton(tab, label, symbol, active) {
  return `<button class="nav-button ${active === tab ? "is-active" : ""}" data-tab="${tab}" aria-label="${label}" aria-current="${active === tab ? "page" : "false"}">${icon(symbol)}<span>${label}</span></button>`;
}

function actionButton(action, label, symbol, extra = "") {
  return `<button class="control-button ${extra}" data-action="${action}">${icon(symbol)}<span>${label}</span></button>`;
}

function toggleButton(action, label, enabled, symbol, extra = "") {
  return `<button class="toggle-button ${enabled ? "is-on" : ""} ${extra}" data-action="${action}" data-value="${enabled ? "false" : "true"}"><span class="toggle-icon">${icon(symbol)}</span><span>${label}</span><span class="toggle-state">${enabled ? "On" : "Off"}</span></button>`;
}

function header(state) {
  const player = state.player || {};
  return `<header class="topbar">
    <div class="brand"><span class="brand-mark">CP</span><div><strong>CarPlay</strong><small>Vehicle command centre</small></div></div>
    <div class="topbar-status"><span class="status-dot"></span><span>Connected</span><span class="topbar-divider"></span><span>${clockLabel(state.time)}</span></div>
    <div class="profile"><div class="profile-copy"><strong>${esc(player.name || "Driver")}</strong><small>${esc(state.plate || "No plate")}</small></div><div class="avatar">${player.mugshot ? `<img src="${esc(player.mugshot)}" alt="" />` : icon("seat")}</div></div>
    <button class="close-button" data-action="closeMenu" aria-label="Close CarPlay">${icon("close")}</button>
  </header>`;
}

function navigation(state) {
  return `<aside class="sidebar">
    <div class="nav-section-label">CONTROL</div>
    ${tabButton("home", "Overview", "home", state.activeTab)}
    ${tabButton("vehicle", "Vehicle", "car", state.activeTab)}
    ${tabButton("map", "Navigation", "map", state.activeTab)}
    ${tabButton("music", "Media", "music", state.activeTab)}
    <div class="nav-section-label">CUSTOMISE</div>
    ${tabButton("tuning", "Tuning", "tune", state.activeTab)}
    ${tabButton("neon", "Neon", "neon", state.activeTab)}
    <div class="nav-section-label">CAPTURE</div>
    ${tabButton("camera", "Dashcam", "camera", state.activeTab)}
    ${tabButton("recordings", "Recordings", "record", state.activeTab)}
    <div class="sidebar-footer"><span class="keyboard-key">ESC</span><span>Close tablet</span></div>
  </aside>`;
}

function overview(state) {
  const info = state.vehicle.info || {};
  return `<section class="page overview-page">
    <div class="page-heading"><div><p class="eyebrow">LIVE VEHICLE STATUS</p><h1>Good to see you, ${esc((state.player.name || "Driver").split(" ")[0])}</h1><p class="muted">Everything you need while you are on the road.</p></div><div class="weather-card"><span class="weather-icon">${state.weather.type === "RAIN" ? "☂" : "☀"}</span><div><strong>${weatherLabel(state.weather)}</strong><small>${Number(state.weather.temperature || 0)}°C outside</small></div></div></div>
    <div class="hero-grid">
      <article class="hero-card vehicle-hero"><div class="hero-card-copy"><p class="eyebrow">CURRENT VEHICLE</p><h2>${esc(info.model || "Vehicle")}</h2><p class="plate-chip">${esc(state.plate || "NO PLATE")}</p><button class="text-button" data-tab="vehicle">Open vehicle controls ${icon("arrow")}</button></div><div class="vehicle-art">${icon("car")}<span>${esc(info.driveType || "Road ready")}</span></div></article>
      <article class="metric-card"><span class="metric-label">FUEL</span><strong>${Math.round(Number(info.fuel || 0))}%</strong><div class="progress"><span style="width:${Math.min(100, Math.max(0, Number(info.fuel || 0)))}%"></span></div><small>Estimated remaining</small></article>
      <article class="metric-card"><span class="metric-label">ENGINE</span><strong>${Math.round(Number(info.engineHealth || 100))}%</strong><div class="progress progress-green"><span style="width:${Math.min(100, Math.max(0, Number(info.engineHealth || 100)))}%"></span></div><small>System condition</small></article>
    </div>
    <div class="section-heading"><div><p class="eyebrow">QUICK ACTIONS</p><h2>Vehicle controls</h2></div><button class="text-button" data-tab="vehicle">View all ${icon("arrow")}</button></div>
    <div class="quick-grid">
      ${toggleButton("toggleEngine", "Engine", state.vehicle.engine, "engine")}
      ${toggleButton("toggleLock", "Doors", state.vehicle.locked, "lock")}
      ${toggleButton("toggleLights", "Lights", state.vehicle.lights, "light")}
      ${toggleButton("toggleSeatbelt", "Seatbelt", state.vehicle.seatbelt, "seat")}
    </div>
    <div class="lower-grid"><article class="panel-card mini-map"><div class="panel-heading"><div><p class="eyebrow">NAVIGATION</p><h3>${state.waypoint ? "Destination set" : "No destination"}</h3></div><button class="icon-button" data-tab="map">${icon("arrow")}</button></div><div class="map-preview"><span class="map-road road-a"></span><span class="map-road road-b"></span><span class="map-pin">⌖</span><small>${state.waypoint ? `${Number(state.waypoint.x || 0).toFixed(1)}, ${Number(state.waypoint.y || 0).toFixed(1)}` : "Set a waypoint from Navigation"}</small></div></article><article class="panel-card music-mini"><div class="panel-heading"><div><p class="eyebrow">NOW PLAYING</p><h3>${esc(state.music.song?.title || "Nothing playing")}</h3><small>${esc(state.music.song?.artist || "Choose a track from Media")}</small></div>${icon("music")}</div><div class="mini-player"><button class="play-button" data-action="toggleMusic" data-value="${!state.music.playing}">${icon(state.music.playing ? "pause" : "play")}</button><div class="player-progress"><span style="width:${state.music.duration ? Math.min(100, (state.music.currentTime / state.music.duration) * 100) : 0}%"></span></div><span>${formatDuration(state.music.currentTime)}</span></div></article></div>
  </section>`;
}

function vehiclePage(state) {
  return `<section class="page"><div class="page-heading"><div><p class="eyebrow">VEHICLE COMMAND</p><h1>Control centre</h1><p class="muted">Manage the systems inside your current vehicle.</p></div><span class="plate-chip">${esc(state.plate || "NO PLATE")}</span></div><div class="control-layout"><article class="panel-card"><div class="panel-heading"><div><p class="eyebrow">SYSTEMS</p><h2>Vehicle controls</h2></div></div><div class="control-list">${toggleButton("toggleEngine", "Engine", state.vehicle.engine, "engine")}${toggleButton("toggleLock", "Central locking", state.vehicle.locked, "lock")}${toggleButton("toggleLights", "Headlights", state.vehicle.lights, "light")}${toggleButton("toggleWindows", "Windows", state.vehicle.windowsOpen, "window")}${toggleButton("toggleSeatbelt", "Seatbelt", state.vehicle.seatbelt, "seat")}${toggleButton("toggleTrunk", "Trunk", state.vehicle.trunkOpen, "door")}</div></article><article class="panel-card"><div class="panel-heading"><div><p class="eyebrow">ACCESS</p><h2>Doors & seats</h2></div></div><div class="door-grid">${[0, 1, 2, 3].map((door) => `<button class="door-button" data-action="toggleDoor" data-door="${door}" data-open="true">${icon("door")}<span>Door ${door + 1}</span><small>Open / close</small></button>`).join("")}</div><div class="seat-row"><label>Move to seat<select data-action="selectSeat"><option value="1">Driver</option><option value="2">Passenger</option><option value="3">Rear left</option><option value="4">Rear right</option></select></label><button class="control-button" data-action="selectSeat" data-seat="1">Move</button></div></article></div><div class="stats-grid"><div class="stat-tile"><span>Fuel</span><strong>${Math.round(Number(state.vehicle.info?.fuel || 0))}%</strong></div><div class="stat-tile"><span>Engine health</span><strong>${Math.round(Number(state.vehicle.info?.engineHealth || 100))}%</strong></div><div class="stat-tile"><span>Body health</span><strong>${Math.round(Number(state.vehicle.info?.bodyHealth || 100))}%</strong></div><div class="stat-tile"><span>Drive type</span><strong>${esc(state.vehicle.info?.driveType || "—")}</strong></div></div></section>`;
}

function mapPage(state) {
  return `<section class="page"><div class="page-heading"><div><p class="eyebrow">NAVIGATION</p><h1>Map & destination</h1><p class="muted">Set a waypoint using coordinates from your current map.</p></div><button class="control-button" data-action="setWaypointFromCurrent">Use current position</button></div><div class="map-large"><div class="map-grid-lines"></div><span class="map-road road-a"></span><span class="map-road road-b"></span><span class="map-road road-c"></span><div class="player-pin" style="left:50%;top:52%">⌖<small>You</small></div>${state.waypoint ? `<div class="destination-pin" style="left:68%;top:32%">◆<small>Destination</small></div>` : ""}<div class="map-overlay"><span class="map-coordinates">${Number(state.position.x || 0).toFixed(2)}, ${Number(state.position.y || 0).toFixed(2)}</span><span>${state.waypoint ? "Waypoint active" : "No waypoint set"}</span></div></div><div class="coordinate-form panel-card"><label>X<input id="waypoint-x" type="number" step="0.01" value="${state.waypoint?.x ?? state.position.x ?? 0}" /></label><label>Y<input id="waypoint-y" type="number" step="0.01" value="${state.waypoint?.y ?? state.position.y ?? 0}" /></label><button class="control-button" data-action="setWaypointFromInputs">Set waypoint</button><button class="ghost-button" data-action="clearWaypoint">Clear</button></div></section>`;
}

function musicPage(state) {
  const library = Array.isArray(state.music.library) ? state.music.library : [];
  return `<section class="page"><div class="page-heading"><div><p class="eyebrow">MEDIA CONSOLE</p><h1>Music</h1><p class="muted">Control audio for the current vehicle.</p></div><button class="control-button" data-action="getMusicLibrary">Refresh library</button></div><div class="music-layout"><article class="player-card"><div class="album-art">♫</div><p class="eyebrow">NOW PLAYING</p><h2>${esc(state.music.song?.title || "Nothing selected")}</h2><p class="muted">${esc(state.music.song?.artist || "Select a track from the library")}</p><div class="range-line"><span>${formatDuration(state.music.currentTime)}</span><input type="range" min="0" max="${Math.max(1, state.music.duration)}" value="${state.music.currentTime}" data-action="seekMusic" /><span>${formatDuration(state.music.duration)}</span></div><div class="player-controls"><button class="round-button" data-action="stopMusic">■</button><button class="play-button large" data-action="toggleMusic" data-value="${!state.music.playing}">${icon(state.music.playing ? "pause" : "play")}</button><label class="volume-control">VOL <input type="range" min="0" max="1" step="0.01" value="${state.music.volume}" data-action="setMusicVolume" /></label></div></article><article class="panel-card library-card"><div class="panel-heading"><div><p class="eyebrow">LIBRARY</p><h2>Available tracks</h2></div><span class="count-badge">${library.length}</span></div><div class="track-list">${library.length ? library.map((song, index) => `<button class="track-row ${state.music.song?.id === song.id ? "is-active" : ""}" data-action="playMusic" data-song-index="${index}"><span class="track-number">${String(index + 1).padStart(2, "0")}</span><span class="track-art">♫</span><span class="track-copy"><strong>${esc(song.title || song.name || "Untitled")}</strong><small>${esc(song.artist || "CarPlay library")}</small></span><span class="track-duration">${state.music.song?.id === song.id && state.music.playing ? "Playing" : icon("play")}</span></button>`).join("") : `<div class="empty-state">${icon("music")}<h3>No music loaded</h3><p>Use refresh library to request the configured songs.</p></div>`}</div><div class="custom-track"><input id="youtube-url" class="text-input" placeholder="YouTube URL" /><button class="control-button" data-action="fetchYouTubeData">Import</button></div></article></div></section>`;
}

function tuningPage(state) {
  const values = state.tuning.values || {};
  const fields = [
    ["BoostPower", "Boost power", "Top speed improvement"],
    ["GearChange", "Gear change", "Shift response"],
    ["Acceleration", "Acceleration", "Launch response"],
    ["Brakes", "Brakes", "Stopping force"],
  ];
  return `<section class="page"><div class="page-heading"><div><p class="eyebrow">PERFORMANCE LAB</p><h1>Tuning</h1><p class="muted">Adjust the installed tuner chip within its configured limits.</p></div><span class="status-pill ${state.tunerChip ? "is-on" : ""}">${state.tunerChip ? "Chip installed" : "No chip installed"}</span></div>${state.tunerChip ? `<div class="tuning-layout"><article class="panel-card"><div class="panel-heading"><div><p class="eyebrow">DRIVE PROFILE</p><h2>Drive mode</h2></div></div><div class="mode-grid">${["normal", "sports", "eco", "drift"].map((mode) => `<button class="mode-button ${state.tuning.driveMode === mode ? "is-active" : ""}" data-action="setDriveMode" data-mode="${mode}"><strong>${mode}</strong><small>${mode === "sports" ? "Sharper response" : mode === "eco" ? "Save fuel" : mode === "drift" ? "Loose traction" : "Factory setup"}</small></button>`).join("")}</div></article><article class="panel-card"><div class="panel-heading"><div><p class="eyebrow">CHIP VALUES</p><h2>Performance controls</h2></div><button class="text-button" data-action="getTunerChipValues">Refresh</button></div><div class="slider-list">${fields.map(([key, label, description]) => `<label class="slider-row"><span><strong>${label}</strong><small>${description}</small></span><input type="range" min="0" max="100" value="${Number(values[key] || 0)}" data-action="setTunerChipValue" data-type="${key}" /><output>${Math.round(Number(values[key] || 0))}%</output></label>`).join("")}</div></article></div><button class="danger-button" data-action="removeTunerChip">Remove tuner chip</button>` : `<div class="empty-state large-empty">${icon("tune")}<h2>Tuner chip not installed</h2><p>Install a tuner chip in the vehicle to unlock performance controls.</p></div>`}</section>`;
}

function neonPage(state) {
  return `<section class="page"><div class="page-heading"><div><p class="eyebrow">EXTERIOR LIGHTING</p><h1>Neon studio</h1><p class="muted">Configure the vehicle's neon presentation.</p></div>${toggleButton("toggleNeon", "Neon system", state.neon.enabled, "neon")}</div><div class="neon-layout"><article class="neon-preview panel-card"><div class="neon-car">${icon("car")}<span style="background:${esc(state.neon.color)}"></span></div><div class="neon-glow" style="background:${esc(state.neon.color)}"></div></article><article class="panel-card"><div class="panel-heading"><div><p class="eyebrow">COLOUR</p><h2>Light colour</h2></div></div><div class="color-row"><input class="color-input" type="color" value="${esc(state.neon.color)}" data-action="setNeonColor" /><input class="text-input" value="${esc(state.neon.color)}" data-action="setNeonColorText" /></div><div class="panel-heading pattern-heading"><div><p class="eyebrow">PATTERN</p><h2>Animation</h2></div></div><div class="mode-grid">${["Solid", "Pulse", "Flash", "Fade"].map((name, index) => `<button class="mode-button ${state.neon.pattern === index + 1 ? "is-active" : ""}" data-action="setNeonPattern" data-pattern="${index + 1}"><strong>${name}</strong><small>Pattern ${index + 1}</small></button>`).join("")}</div><div class="location-list">${["Front", "Rear", "Left", "Right"].map((name, index) => `<label><span>${name}</span><input type="checkbox" data-action="toggleNeonLocation" data-location="${index}" ${state.neon.locations.includes(index) ? "checked" : ""} /></label>`).join("")}</div></article></div></section>`;
}

function cameraPage(state) {
  return `<section class="page camera-page"><div class="page-heading"><div><p class="eyebrow">CAPTURE SYSTEM</p><h1>Dashcam</h1><p class="muted">Record the road and manage the active camera feed.</p></div><span class="status-pill ${state.camera.recording ? "is-recording" : ""}">${state.camera.recording ? "Recording" : "Ready"}</span></div><div class="camera-stage"><div class="viewfinder"><span></span><span></span><span></span><span></span><i></i></div><div class="camera-hud"><span><b class="record-dot ${state.camera.recording ? "is-recording" : ""}"></b>${state.camera.recording ? "REC" : "STANDBY"}</span><span>${formatDuration(state.camera.elapsed)}</span></div><div class="camera-controls"><button class="round-button" data-action="rotateDashcam" data-direction="left">↶</button><button class="record-button ${state.camera.recording ? "is-recording" : ""}" data-action="${state.camera.recording ? "stopRecording" : "startRecording"}">${state.camera.recording ? "■" : "●"}</button><button class="round-button" data-action="rotateDashcam" data-direction="right">↷</button></div></div><div class="camera-actions"><button class="control-button" data-action="startDashcam">Open camera</button><button class="ghost-button" data-action="stopDashcam">Close camera</button><button class="text-button" data-tab="recordings">View recordings ${icon("arrow")}</button></div></section>`;
}

function recordingsPage(state) {
  const recordings = Array.isArray(state.recordings) ? state.recordings : [];
  return `<section class="page"><div class="page-heading"><div><p class="eyebrow">CAPTURE LIBRARY</p><h1>Recordings</h1><p class="muted">Review, upload or remove saved dashcam clips.</p></div><div class="heading-actions"><button class="control-button" data-action="getRecordings">Refresh</button><button class="ghost-button" data-action="clearAllRecordings">Clear all</button></div></div><div class="recording-grid">${
    recordings.length
      ? recordings
          .map((recording) => {
            const name =
              recording.filename ||
              recording.name ||
              recording.file ||
              "recording.webm";
            const id = recording.id || recording.filename || name;
            return `<article class="recording-card"><div class="recording-thumb">${icon("camera")}<span>${esc(recording.duration ? formatDuration(recording.duration) : "WEBM")}</span></div><div class="recording-copy"><strong>${esc(name)}</strong><small>${esc(recording.createdAt || recording.date || "Saved dashcam clip")}</small></div><div class="recording-actions"><button class="icon-button" data-action="uploadRecording" data-id="${esc(id)}" aria-label="Upload">↑</button><button class="icon-button danger-icon" data-action="deleteRecording" data-id="${esc(id)}" aria-label="Delete">×</button></div></article>`;
          })
          .join("")
      : `<div class="empty-state large-empty">${icon("record")}<h2>No recordings yet</h2><p>Start a dashcam recording and saved clips will appear here.</p></div>`
  }</div></section>`;
}

export function render(state) {
  const pages = {
    home: overview,
    vehicle: vehiclePage,
    map: mapPage,
    music: musicPage,
    tuning: tuningPage,
    neon: neonPage,
    camera: cameraPage,
    recordings: recordingsPage,
  };
  const page = pages[state.activeTab] || overview;
  return `<div class="tablet ${state.visible ? "is-visible" : ""}">${header(state)}<div class="tablet-body">${navigation(state)}<main class="content">${page(state)}</main></div>${state.notice ? `<div class="toast" role="status">${esc(state.notice)}</div>` : ""}</div>`;
}
