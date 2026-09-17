import { nui } from "./nui.js";

let youtubeApiPromise;

function youtubeId(value) {
  const text = String(value || "");
  if (/^[a-zA-Z0-9_-]{11}$/.test(text)) return text;
  return (
    text.match(
      /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})/,
    )?.[1] || null
  );
}

function loadYouTubeApi() {
  if (window.YT?.Player) return Promise.resolve(window.YT);
  if (youtubeApiPromise) return youtubeApiPromise;
  youtubeApiPromise = new Promise((resolve, reject) => {
    const previous = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      previous?.();
      resolve(window.YT);
    };
    const script = document.createElement("script");
    script.src = "https://www.youtube.com/iframe_api";
    script.onerror = reject;
    document.head.appendChild(script);
  });
  return youtubeApiPromise;
}

/** Keeps the original Lua sound runtime contract with editable playback code. */
export class AudioManager {
  constructor() {
    this.sources = new Map();
    this.speakers = new Map();
    this.listener = this.handleMessage.bind(this);
    window.addEventListener("message", this.listener);
    window.addEventListener("pointerdown", () => this.unlock(), { once: true });
    window.addEventListener("keydown", () => this.unlock(), { once: true });
  }

  unlock() {
    for (const source of this.sources.values()) {
      if (!source.wantsPlay) continue;
      if (source.kind === "youtube") source.player?.playVideo();
      else source.audio.play().catch(() => {});
    }
  }

  addSource(id, url, config = {}) {
    if (!id || !url) return;
    const videoId = youtubeId(url);
    if (videoId) return this.addYouTubeSource(String(id), videoId, config);
    this.removeSource(id);
    const audio = new Audio(url);
    audio.preload = "auto";
    audio.loop = Boolean(config.loop);
    audio.volume = Math.min(1, Math.max(0, Number(config.volume ?? 1)));
    const source = { id: String(id), kind: "audio", audio, wantsPlay: false };
    this.sources.set(source.id, source);
    audio.addEventListener("canplay", () => this.emit(source.id, "ready"));
    audio.addEventListener("play", () =>
      this.emit(source.id, "playbackStarted"),
    );
    audio.addEventListener("pause", () =>
      this.emit(source.id, "playbackPaused"),
    );
    audio.addEventListener("ended", () => this.emit(source.id, "ended"));
    audio.addEventListener("error", () => this.emit(source.id, "error"));
  }

  addYouTubeSource(id, videoId, config = {}) {
    this.removeSource(id);
    const container = document.createElement("div");
    container.id = `youtube-audio-${id}`;
    container.className = "youtube-audio-source";
    document.getElementById("youtube-container")?.appendChild(container);
    const source = {
      id,
      kind: "youtube",
      videoId,
      container,
      player: null,
      wantsPlay: false,
      config,
    };
    this.sources.set(id, source);
    loadYouTubeApi()
      .then((YT) => {
        source.player = new YT.Player(container, {
          videoId,
          height: "1",
          width: "1",
          playerVars: {
            autoplay: 0,
            controls: 0,
            playsinline: 1,
            origin: window.location.origin,
          },
          events: {
            onReady: () => {
              source.player.setVolume(
                Math.min(100, Math.max(0, Number(config.volume ?? 1) * 100)),
              );
              this.emit(id, "ready");
              if (source.wantsPlay) source.player.playVideo();
            },
            onStateChange: (event) => {
              if (event.data === YT.PlayerState.PLAYING)
                this.emit(id, "playbackStarted");
              if (event.data === YT.PlayerState.PAUSED)
                this.emit(id, "playbackPaused");
              if (event.data === YT.PlayerState.ENDED) this.emit(id, "ended");
            },
            onError: () => this.emit(id, "error"),
          },
        });
      })
      .catch(() => this.emit(id, "error"));
  }

  source(id) {
    return this.sources.get(String(id));
  }

  async play(id) {
    const source = this.source(id);
    if (!source) return;
    source.wantsPlay = true;
    if (source.kind === "youtube") return source.player?.playVideo();
    try {
      await source.audio.play();
    } catch {
      /* unlocked after player input */
    }
  }

  pause(id) {
    const source = this.source(id);
    if (!source) return;
    source.wantsPlay = false;
    source.kind === "youtube"
      ? source.player?.pauseVideo()
      : source.audio.pause();
  }

  resume(id) {
    const source = this.source(id);
    if (!source) return;
    source.wantsPlay = true;
    source.kind === "youtube"
      ? source.player?.playVideo()
      : source.audio.play().catch(() => {});
  }

  stop(id) {
    const source = this.source(id);
    if (!source) return;
    source.wantsPlay = false;
    if (source.kind === "youtube") source.player?.stopVideo();
    else {
      source.audio.pause();
      source.audio.currentTime = 0;
    }
  }

  seek(id, position) {
    const source = this.source(id);
    const time = Number(position);
    if (!source || !Number.isFinite(time)) return;
    source.kind === "youtube"
      ? source.player?.seekTo(Math.max(0, time), true)
      : (source.audio.currentTime = Math.max(0, time));
  }

  removeSource(id) {
    const source = this.source(id);
    if (!source) return;
    if (source.kind === "youtube") {
      source.player?.destroy();
      source.container?.remove();
    } else {
      source.audio.pause();
      source.audio.removeAttribute("src");
      source.audio.load();
    }
    this.sources.delete(String(id));
  }

  emit(audioSourceId, eventType, data = null) {
    nui("audioEvent", { audioSourceId, eventType, data });
  }

  fetchData(url) {
    const videoId = youtubeId(url);
    if (videoId) return this.addYouTubeSource("fetchTitle", videoId);
    const audio = new Audio(url);
    audio.preload = "metadata";
    const finish = (payload) => nui("receiveTitle", { url, ...payload });
    audio.addEventListener(
      "loadedmetadata",
      () =>
        finish({
          status: "success",
          duration: Math.floor(audio.duration || 0),
        }),
      { once: true },
    );
    audio.addEventListener(
      "error",
      () => finish({ status: "error", duration: 0 }),
      { once: true },
    );
    audio.load();
  }

  handleMessage(event) {
    const message = event?.data || {};
    const id = message.audioSourceId;
    switch (message.type) {
      case "addAudioSource":
        return this.addSource(id, message.url, message.config);
      case "playAudioSource":
        return this.play(id);
      case "pauseAudioSource":
        return this.pause(id);
      case "resumeAudioSource":
        return this.resume(id);
      case "stopAudioSource":
        return this.stop(id);
      case "removeAudioSource":
        return this.removeSource(id);
      case "seekAudioSource":
        return this.seek(id, message.position);
      case "getCurrentTime": {
        const source = this.source(id);
        const currentTime =
          source?.kind === "youtube"
            ? source.player?.getCurrentTime?.() || 0
            : source?.audio.currentTime || 0;
        return nui("currentTime", { audioSourceId: id, currentTime });
      }
      case "setLoop": {
        const source = this.source(id);
        if (source?.kind === "audio") source.audio.loop = Boolean(message.loop);
        return;
      }
      case "fetchData":
        return this.fetchData(message.url);
      case "addSpeaker":
        this.speakers.set(String(message.speakerId), message);
        return;
      case "removeSpeaker":
        this.speakers.delete(String(message.speakerId));
        return;
      case "updateSpeakerConfig":
      case "updateVehicleSpeaker": {
        const speaker = this.speakers.get(String(message.speakerId));
        if (speaker)
          speaker.config = { ...speaker.config, ...(message.config || {}) };
        return;
      }
      case "forcePlayAudio":
        for (const source of this.sources.values()) this.play(source.id);
        return;
      default:
        return;
    }
  }
}
