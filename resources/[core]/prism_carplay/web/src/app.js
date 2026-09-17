import { listen, nui } from "./nui.js";
import { createState, updateState } from "./state.js";
import { render } from "./views.js";
import { AudioManager } from "./audio.js";

const root = document.getElementById("app");
new AudioManager();
let state = createState();
let noticeTimer;

function repaint() {
  root.innerHTML = render(state);
  document.documentElement.style.setProperty(
    "--cp-primary",
    state.primaryColor || "#00d1ff",
  );
}

function setState(patch) {
  state = updateState(state, patch);
  repaint();
}

function notice(message) {
  clearTimeout(noticeTimer);
  setState({ notice: message });
  noticeTimer = setTimeout(() => setState({ notice: null }), 2600);
}

function valueFromButton(button) {
  if (button.dataset.value === "true") return true;
  if (button.dataset.value === "false") return false;
  return undefined;
}

function recordingList(data) {
  if (Array.isArray(data)) return data;
  if (Array.isArray(data?.recordings)) return data.recordings;
  return [];
}

function hslFromHex(hex) {
  const value = String(hex || "#00d1ff").replace("#", "");
  const number = Number.parseInt(
    value.length === 3
      ? value
          .split("")
          .map((part) => part + part)
          .join("")
      : value,
    16,
  );
  const r = ((number >> 16) & 255) / 255;
  const g = ((number >> 8) & 255) / 255;
  const b = (number & 255) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const lightness = (max + min) / 2;
  const delta = max - min;
  if (!delta) return { h: 0, s: 0, l: Math.round(lightness * 100) };
  const saturation = delta / (1 - Math.abs(2 * lightness - 1));
  let hue =
    max === r
      ? ((g - b) / delta) % 6
      : max === g
        ? (b - r) / delta + 2
        : (r - g) / delta + 4;
  hue = Math.round(hue * 60);
  if (hue < 0) hue += 360;
  return {
    h: hue,
    s: Math.round(saturation * 100),
    l: Math.round(lightness * 100),
  };
}

function modificationsFrom(data, current) {
  const value = data || {};
  const patterns = Array.isArray(value.neonPatterns) ? value.neonPatterns : [];
  const locations = Array.isArray(value.neonLocations)
    ? value.neonLocations
    : [];
  const enabledPattern = patterns.find((pattern) => pattern.enabled)?.id || 1;
  return {
    ...current,
    neonPatterns: patterns.length
      ? patterns
      : [1, 2, 3, 4].map((id) => ({ id, enabled: id === enabledPattern })),
    neonLocations: locations.length
      ? locations
      : [1, 2, 3, 4].map((id) => ({ id, enabled: false })),
    neonHue: Number(value.neonHue ?? 190),
    neonSaturation: Number(value.neonSaturation ?? 100),
    neonBrightness: Number(value.neonBrightness ?? 50),
    driveMode: value.driveMode || current.driveMode || "normal",
  };
}

function handleMessage(message) {
  const data = message.data ?? message.payload;
  switch (message.action || message.type) {
    case "setVisible":
      setState({ visible: Boolean(data) });
      break;
    case "updatePrimaryColor":
      setState({ primaryColor: String(data || "#00d1ff") });
      break;
    case "setLocale":
      setState({ locale: data || {} });
      break;
    case "updatePlayerPosition":
      setState({ position: data || {} });
      break;
    case "updateGameTime":
      setState({ time: data || {} });
      break;
    case "updateWeather":
      setState({ weather: data || {} });
      break;
    case "updatePlayerProfile":
      setState({
        player: data || {},
        plate: data?.vehiclePlate || state.plate,
      });
      break;
    case "updateVehiclePlate":
      setState({ plate: data || "—" });
      break;
    case "updateWaypoint":
      setState({ waypoint: data || null });
      break;
    case "navigateHome":
      setState({ activeTab: "home" });
      break;
    case "updateTunerChip":
      setState({ tunerChip: Boolean(data) });
      break;
    case "musicStarted":
      setState({ music: { song: data?.song || data, playing: true } });
      break;
    case "musicStopped":
    case "trackEnded":
      setState({ music: { playing: false, currentTime: 0 } });
      break;
    case "updatePlaybackStatus":
    case "syncMusicState":
      setState({ music: data || {} });
      break;
    case "receiveRecordings":
      setState({ recordings: recordingList(data) });
      break;
    case "recordingSaved":
      setState({ recordings: [...state.recordings, data].filter(Boolean) });
      notice("Recording saved");
      break;
    case "uploadComplete":
      notice("Recording uploaded");
      break;
    case "uploadFailed":
      notice("Recording upload failed");
      break;
    case "dashcamStopped":
      setState({ camera: { recording: false, active: false } });
      break;
    case "updateVehicleSpeaker":
    case "updateSpeakerConfig":
      // Audio filtering is handled by the original sound runtime. Keep the
      // latest payload available for future editable audio controls.
      setState({ speaker: message });
      break;
    default:
      break;
  }
}

async function call(action, data = {}) {
  const result = await nui(action, data);
  if (result == null) return result;

  if (
    action === "getMusicLibrary" &&
    (Array.isArray(result) || Array.isArray(result.library))
  )
    setState({
      music: { library: Array.isArray(result) ? result : result.library },
    });
  if (action === "getMusicState" && result && typeof result === "object")
    setState({ music: result });
  if (action === "getRecordings" && Array.isArray(result))
    setState({ recordings: result });
  if (action === "getVehicleInfo" && result && typeof result === "object")
    setState({ vehicle: { info: result } });
  if (action === "getTunerChipValues" && result && typeof result === "object")
    setState({ tuning: { values: result } });
  if (action === "getModificationsData") {
    const modifications = modificationsFrom(result, state.tuning.modifications);
    const enabledPattern =
      modifications.neonPatterns.find((pattern) => pattern.enabled)?.id || 1;
    setState({
      tuning: { modifications, driveMode: modifications.driveMode },
      neon: {
        pattern: enabledPattern,
        locations: modifications.neonLocations
          .filter((location) => location.enabled)
          .map((location) => location.id),
        enabled: modifications.neonLocations.some(
          (location) => location.enabled,
        ),
      },
    });
  }
  return result;
}

function close() {
  call("closeMenu");
  setState({ visible: false });
}

async function handleAction(button) {
  const action = button.dataset.action;
  if (!action) return;

  if (action === "closeMenu") return close();
  if (action === "setWaypointFromCurrent") {
    return call("setWaypoint", { x: state.position.x, y: state.position.y });
  }
  if (action === "setWaypointFromInputs") {
    const x = Number(document.getElementById("waypoint-x")?.value);
    const y = Number(document.getElementById("waypoint-y")?.value);
    if (Number.isFinite(x) && Number.isFinite(y))
      return call("setWaypoint", { x, y });
    return notice("Enter valid coordinates");
  }
  if (action === "clearWaypoint") {
    setState({ waypoint: null });
    return;
  }
  if (action === "playMusic") {
    const song = state.music.library[Number(button.dataset.songIndex)];
    if (!song) return;
    setState({ music: { song, playing: true } });
    return call("playMusic", { song });
  }
  if (action === "fetchYouTubeData") {
    const url = document.getElementById("youtube-url")?.value?.trim();
    if (!url) return notice("Enter a YouTube URL");
    const result = await call(action, { url });
    if (result?.success) {
      const song = {
        id: url,
        title: result.title || "YouTube video",
        artist: "YouTube",
        duration: result.duration || 0,
        isYouTube: true,
        url,
      };
      setState({ music: { library: [...state.music.library, song] } });
      notice("YouTube track imported");
    } else if (result?.error) {
      notice(result.error);
    }
    return;
  }
  if (action === "toggleMusic") {
    const playing = valueFromButton(button);
    setState({ music: { playing } });
    return call("toggleMusic", { playing });
  }
  if (action === "setDriveMode") {
    setState({ tuning: { driveMode: button.dataset.mode } });
    return call(action, { mode: button.dataset.mode });
  }
  if (action === "setTunerChipValue") {
    const value = Number(button.value ?? button.dataset.value ?? 0);
    setState({ tuning: { values: { [button.dataset.type]: value } } });
    return call(action, { type: button.dataset.type, value });
  }
  if (action === "toggleNeon") {
    const enabled = valueFromButton(button);
    const locations = [1, 2, 3, 4].map((id) => ({ id, enabled }));
    const modifications = {
      ...state.tuning.modifications,
      neonLocations: locations,
    };
    setState({
      neon: { enabled, locations: enabled ? [1, 2, 3, 4] : [] },
      tuning: { modifications },
    });
    return call("saveModificationsData", modifications);
  }
  if (action === "toggleNeonLocation") {
    const index = Number(button.dataset.location);
    const locations = new Set(state.neon.locations);
    button.checked ? locations.add(index) : locations.delete(index);
    const locationData = [1, 2, 3, 4].map((id) => ({
      id,
      enabled: locations.has(id - 1),
    }));
    const modifications = {
      ...state.tuning.modifications,
      neonLocations: locationData,
    };
    setState({
      neon: { locations: [...locations], enabled: locations.size > 0 },
      tuning: { modifications },
    });
    return call("saveModificationsData", modifications);
  }
  if (action === "setNeonColor" || action === "setNeonColorText") {
    const color = button.value || "#00d1ff";
    const hsl = hslFromHex(color);
    const modifications = {
      ...state.tuning.modifications,
      neonHue: hsl.h,
      neonSaturation: hsl.s,
      neonBrightness: hsl.l,
    };
    setState({ neon: { color }, tuning: { modifications } });
    return call("saveModificationsData", modifications);
  }
  if (action === "setNeonPattern") {
    const pattern = Number(button.dataset.pattern);
    const neonPatterns = [1, 2, 3, 4].map((id) => ({
      id,
      enabled: id === pattern,
    }));
    const modifications = { ...state.tuning.modifications, neonPatterns };
    setState({ neon: { pattern }, tuning: { modifications } });
    return call("saveModificationsData", modifications);
  }

  let payload = {};
  if (action === "toggleDoor")
    payload = {
      door: Number(button.dataset.door),
      open: button.dataset.open === "true",
    };
  if (
    [
      "toggleEngine",
      "toggleLock",
      "toggleLights",
      "toggleWindows",
      "toggleSeatbelt",
      "toggleTrunk",
    ].includes(action)
  ) {
    const enabled = valueFromButton(button);
    const key = {
      toggleEngine: "engine",
      toggleLock: "locked",
      toggleLights: "lights",
      toggleWindows: "windowsOpen",
      toggleSeatbelt: "seatbelt",
      toggleTrunk: "trunkOpen",
    }[action];
    setState({ vehicle: { [key]: enabled } });
    payload = {
      [action === "toggleLock"
        ? "locked"
        : action === "toggleWindows"
          ? "down"
          : action === "toggleSeatbelt"
            ? "on"
            : "open"]: enabled,
    };
  }
  if (action === "selectSeat")
    payload = {
      seat: Number(
        button.dataset.seat ||
          document.querySelector("select[data-action=selectSeat]")?.value ||
          1,
      ),
    };
  if (action === "rotateDashcam")
    payload = { front: button.dataset.direction !== "right" };
  if (action === "uploadRecording" || action === "deleteRecording")
    payload = { id: button.dataset.id };
  if (action === "setMusicVolume") {
    const volume = Number(button.value);
    setState({ music: { volume } });
    payload = { volume };
  }
  if (action === "seekMusic") {
    const time = Number(button.value);
    setState({ music: { currentTime: time } });
    payload = { time };
  }

  if (action === "startRecording")
    setState({ camera: { recording: true, active: true } });
  if (action === "stopRecording") setState({ camera: { recording: false } });
  if (action === "startDashcam")
    setState({ activeTab: "camera", camera: { active: true } });
  if (action === "stopDashcam")
    setState({ camera: { active: false, recording: false } });
  return call(action, payload);
}

root.addEventListener("click", (event) => {
  const tab = event.target.closest("[data-tab]");
  if (tab) {
    setState({ activeTab: tab.dataset.tab });
    return;
  }
  const button = event.target.closest("button[data-action]");
  if (button) handleAction(button);
});

root.addEventListener("input", (event) => {
  const control = event.target.closest("[data-action]");
  if (!control) return;
  const action = control.dataset.action;
  if (action === "setMusicVolume") {
    state.music.volume = Number(control.value);
    call(action, { volume: state.music.volume });
  }
  if (action === "seekMusic") {
    state.music.currentTime = Number(control.value);
    call(action, { time: state.music.currentTime });
  }
  if (action === "setTunerChipValue") {
    const value = Number(control.value);
    state.tuning.values[control.dataset.type] = value;
    const output = control.parentElement?.querySelector("output");
    if (output) output.textContent = `${Math.round(value)}%`;
    call(action, { type: control.dataset.type, value });
  }
  if (action === "setNeonColor" || action === "setNeonColorText") {
    const color = control.value || "#00d1ff";
    state.neon.color = color;
    const hsl = hslFromHex(color);
    state.tuning.modifications = {
      ...state.tuning.modifications,
      neonHue: hsl.h,
      neonSaturation: hsl.s,
      neonBrightness: hsl.l,
    };
    root
      .querySelectorAll(".neon-car span, .neon-glow")
      .forEach((element) => (element.style.background = color));
    call("saveModificationsData", state.tuning.modifications);
  }
});

root.addEventListener("change", (event) => {
  const control = event.target.closest("[data-action]");
  if (control?.dataset.action === "toggleNeonLocation") handleAction(control);
  if (control?.dataset.action === "selectSeat") handleAction(control);
});

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && state.visible) close();
});

listen(handleMessage);
repaint();

// Populate the UI immediately when opened and also make browser preview useful.
call("getMusicLibrary");
call("getMusicState");
call("getRecordings");
call("getVehicleInfo");
call("getTunerChipValues");
call("getModificationsData");
