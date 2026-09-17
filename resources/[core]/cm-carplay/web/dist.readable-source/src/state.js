// cm-carplay web UI -- shared state shape + helpers. Classic script (no
// import/export) so it loads reliably in FiveM's NUI browser; exposes
// window.CarPlayState for the other scripts.

(function () {
  const initialState = {
    visible: false,
    activeTab: "home",
    primaryColor: "#00d1ff",
    locale: {},
    player: { name: "Driver", mugshot: null },
    plate: "—",
    position: { x: 0, y: 0, z: 0, heading: 0 },
    time: { hour: 12, minute: 0 },
    weather: { type: "CLEAR", temperature: 22 },
    waypoint: null,
    tunerChip: false,
    vehicle: {
      engine: false,
      locked: false,
      lights: false,
      doorsOpen: false,
      trunkOpen: false,
      windowsOpen: false,
      seatbelt: false,
      doors: [false, false, false, false],
      info: {},
    },
    music: {
      library: [],
      song: null,
      playing: false,
      currentTime: 0,
      duration: 0,
      volume: 0.8,
    },
    tuning: {
      values: {},
      driveMode: "normal",
      modifications: {},
    },
    neon: { enabled: false, color: "#00d1ff", pattern: 1, locations: [] },
    recordings: [],
    camera: { active: false, recording: false, elapsed: 0, rotation: 0 },
    notice: null,
  };

  function createState() {
    return typeof structuredClone === "function"
      ? structuredClone(initialState)
      : JSON.parse(JSON.stringify(initialState));
  }

  function updateState(state, patch) {
    return {
      ...state,
      ...patch,
      vehicle: { ...state.vehicle, ...(patch.vehicle || {}) },
      music: { ...state.music, ...(patch.music || {}) },
      tuning: { ...state.tuning, ...(patch.tuning || {}) },
      camera: { ...state.camera, ...(patch.camera || {}) },
    };
  }

  function clockLabel({ hour = 12, minute = 0 }) {
    const h = Number(hour) || 0;
    const suffix = h >= 12 ? "PM" : "AM";
    return `${h % 12 || 12}:${String(minute).padStart(2, "0")} ${suffix}`;
  }

  function formatDuration(seconds = 0) {
    const value = Math.max(0, Math.floor(Number(seconds) || 0));
    return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, "0")}`;
  }

  function weatherLabel(weather = {}) {
    return String(weather.type || "CLEAR")
      .toLowerCase()
      .replace(
        /(^|_)([a-z])/g,
        (_, start, letter) => `${start}${letter.toUpperCase()}`,
      )
      .replace("Extrasunny", "Sunny");
  }

  window.CarPlayState = {
    initialState,
    createState,
    updateState,
    clockLabel,
    formatDuration,
    weatherLabel,
  };
})();
