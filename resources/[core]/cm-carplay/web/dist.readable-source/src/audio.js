// cm-carplay web UI -- audio playback engine. Classic script (no
// import/export); depends on window.NUI (nui.js, loaded before this file);
// exposes window.AudioManager (instantiated once from app.js).
//
// Turns the low-level positional-audio commands sent by client/sound.lua
// into real sound via HTML5 <audio> elements (direct/local URLs) and the
// YouTube IFrame Player API (YouTube URLs / bare 11-char video IDs), wired
// through the Web Audio API for real 3D panner-based positional attenuation
// -- this is what makes music sound like it's actually coming from the
// vehicle (direction + distance falloff + muffling), rather than playing at
// a flat constant volume no matter where the listener is.
//
// client/sound.lua's messages are flat (audioSourceId/url/config/etc. sit
// directly alongside `type`, no nested `data` wrapper), so every handler
// here reads the raw message object directly off the "message" event.

(function () {
  const { nui } = window.NUI;

  // Stepping outside the vehicle should read as an immediate, obvious drop
  // (like a car radio heard through a closed door), not just whatever the
  // PannerNode's own distance falloff happens to produce at close range --
  // so cap it at a flat fraction of full volume the moment pannerDisabled
  // goes false, on top of the normal distance/lowpass falloff as you walk
  // further away.
  const OUTSIDE_VEHICLE_VOLUME_FACTOR = 0.15;

  function numberOr(value, fallback) {
    return typeof value === "number" && !Number.isNaN(value) ? value : fallback;
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  // Mirrors client/sound.lua's isYoutubeUrl(): a bare 11-char video id, or
  // one of the standard YouTube URL shapes.
  function isYoutubeUrl(url) {
    if (typeof url !== "string") return false;
    if (/^[a-zA-Z0-9_-]{11}$/.test(url)) return true;
    return /youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\//.test(url);
  }

  function extractYoutubeVideoId(url) {
    if (/^[a-zA-Z0-9_-]{11}$/.test(url)) return url;
    const patterns = [
      /[?&]v=([a-zA-Z0-9_-]{11})/,
      /youtu\.be\/([a-zA-Z0-9_-]{11})/,
      /youtube\.com\/embed\/([a-zA-Z0-9_-]{11})/,
    ];
    for (const pattern of patterns) {
      const match = url.match(pattern);
      if (match) return match[1];
    }
    return null;
  }

  // Best-effort "title" for a raw, non-YouTube URL (no reliable metadata
  // source exists for arbitrary mp3/local-file URLs without reading tags).
  function deriveTitleFromUrl(url) {
    try {
      const withoutQuery = url.split(/[?#]/)[0];
      const segments = withoutQuery.split("/").filter(Boolean);
      const last = segments[segments.length - 1] || url;
      const withoutExtension = last.replace(/\.[a-zA-Z0-9]{1,5}$/, "");
      const decoded = decodeURIComponent(withoutExtension)
        .replace(/[_-]+/g, " ")
        .trim();
      return decoded || url;
    } catch {
      return url;
    }
  }

  function normalizeSourceConfig(config) {
    config = config || {};
    return {
      loop: config.loop === true,
      volume: numberOr(config.volume, 1.0),
      playbackRate: numberOr(config.playbackRate, 1.0),
      fadeInDuration: numberOr(config.fadeInDuration, 0),
      fadeOutDuration: numberOr(config.fadeOutDuration, 0),
    };
  }

  function normalizeSpeakerConfig(config) {
    config = config || {};
    return {
      refDistance: numberOr(config.refDistance, 1.0),
      maxDistance: numberOr(config.maxDistance, 50.0),
      rolloffFactor: numberOr(config.rolloffFactor, 1.0),
      coneInnerAngle: numberOr(config.coneInnerAngle, 360),
      coneOuterAngle: numberOr(config.coneOuterAngle, 360),
      coneOuterGain: numberOr(config.coneOuterGain, 0.0),
      fadeDurationMs: numberOr(config.fadeDurationMs, 1000),
      volumeMultiplier: numberOr(config.volumeMultiplier, 1.0),
      lowPassGainReductionPercent: numberOr(config.lowPassGainReductionPercent, 0),
      lowPassFrequency: numberOr(config.lowPassFrequency, 0),
      attachedEntity: config.attachedEntity ?? null,
      attachedOffset: config.attachedOffset ?? null,
      isInVehicle: config.isInVehicle === true,
      pannerDisabled: config.pannerDisabled === true,
      pannerManuallySet: config.pannerManuallySet === true,
    };
  }

  // Manual falloff replicated for the YouTube path, where no PannerNode is
  // reachable (cross-origin iframe audio isn't capturable by Web Audio).
  // Mirrors the Web Audio 'inverse' distanceModel formula, using the exact
  // refDistance/maxDistance/rolloffFactor fields client/sound.lua sends --
  // these are literally the PannerNode's own property names.
  function computeManualDistanceGain(distance, config) {
    const refDistance = Math.max(0, numberOr(config.refDistance, 1.0));
    const maxDistance = Math.max(refDistance + 0.01, numberOr(config.maxDistance, 50.0));
    const rolloffFactor = Math.max(0, numberOr(config.rolloffFactor, 1.0));
    if (!(distance >= 0)) return 1;
    if (distance >= maxDistance) return 0;
    const clampedDistance = Math.max(distance, refDistance);
    const gain = refDistance / (refDistance + rolloffFactor * (clampedDistance - refDistance));
    return clamp(gain, 0, 1);
  }

  class AudioManager {
    constructor() {
      this.audioSources = new Map(); // audioSourceId (string) -> source entry
      this.speakers = new Map(); // speakerId (string) -> speaker entry
      this.audioCtx = null;
      this.youtubeHostEl = null;
      this.youtubeApiPromise = null;
      this.lastApplyLowPassFilterGlobal = true;
      this.lastListenerPosition = [0, 0, 0];

      this.handleMessage = this.handleMessage.bind(this);
      window.addEventListener("message", this.handleMessage);
      window.addEventListener("pointerdown", () => this.ensureAudioContext(), { once: true });
      window.addEventListener("keydown", () => this.ensureAudioContext(), { once: true });
    }

    // --- Web Audio graph helpers ------------------------------------------

    ensureAudioContext() {
      if (!this.audioCtx) {
        this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (this.audioCtx.state === "suspended") {
        this.audioCtx.resume().catch(() => {});
      }
      return this.audioCtx;
    }

    connectDirect(sourceEntry) {
      if (sourceEntry.directlyConnected) return;
      sourceEntry.fanoutGain.connect(this.audioCtx.destination);
      sourceEntry.directlyConnected = true;
    }

    disconnectDirect(sourceEntry) {
      if (!sourceEntry.directlyConnected) return;
      try {
        sourceEntry.fanoutGain.disconnect(this.audioCtx.destination);
      } catch {
        /* already disconnected */
      }
      sourceEntry.directlyConnected = false;
    }

    setListenerTransform(position, forward, up) {
      const ctx = this.ensureAudioContext();
      const listener = ctx.listener;
      if (!position || !forward || !up) return;
      const now = ctx.currentTime;
      if (listener.positionX) {
        listener.positionX.setTargetAtTime(position[0], now, 0.01);
        listener.positionY.setTargetAtTime(position[1], now, 0.01);
        listener.positionZ.setTargetAtTime(position[2], now, 0.01);
        listener.forwardX.setTargetAtTime(forward[0], now, 0.01);
        listener.forwardY.setTargetAtTime(forward[1], now, 0.01);
        listener.forwardZ.setTargetAtTime(forward[2], now, 0.01);
        listener.upX.setTargetAtTime(up[0], now, 0.01);
        listener.upY.setTargetAtTime(up[1], now, 0.01);
        listener.upZ.setTargetAtTime(up[2], now, 0.01);
      } else if (listener.setPosition) {
        listener.setPosition(position[0], position[1], position[2]);
        listener.setOrientation(forward[0], forward[1], forward[2], up[0], up[1], up[2]);
      }
    }

    setPannerPosition(panner, ctx, position) {
      if (!position) return;
      if (panner.positionX) {
        const now = ctx.currentTime;
        panner.positionX.setTargetAtTime(position[0], now, 0.01);
        panner.positionY.setTargetAtTime(position[1], now, 0.01);
        panner.positionZ.setTargetAtTime(position[2], now, 0.01);
      } else if (panner.setPosition) {
        panner.setPosition(position[0], position[1], position[2]);
      }
    }

    fadeTrackGain(entry, targetVolume, durationMs) {
      const ctx = this.ensureAudioContext();
      const gainParam = entry.trackGain.gain;
      gainParam.cancelScheduledValues(ctx.currentTime);
      gainParam.setValueAtTime(gainParam.value, ctx.currentTime);
      if (!durationMs || durationMs <= 0) {
        gainParam.setValueAtTime(targetVolume, ctx.currentTime);
      } else {
        gainParam.linearRampToValueAtTime(targetVolume, ctx.currentTime + durationMs / 1000);
      }
    }

    getEntryCurrentTime(entry) {
      if (entry.kind === "html5") return entry.element.currentTime || 0;
      if (entry.kind === "youtube" && entry.player && entry.isReady) {
        try {
          return entry.player.getCurrentTime() || 0;
        } catch {
          return 0;
        }
      }
      return 0;
    }

    // --- Callback reporting to Lua (audioEvent) ---------------------------

    // eventType values are the SHORT names client/sound.lua's `audioEvent`
    // NUI callback maps to the CALLBACK_NAMES list -- NOT the "on..." names
    // themselves: playbackStarted -> onPlaybackStarted, ready ->
    // onAudioReady, playbackPaused -> onPlaybackPaused, error ->
    // onAudioError, playbackResumed -> onPlaybackResumed, ended ->
    // onAudioEnded.
    reportAudioEvent(audioSourceId, eventType, data) {
      nui("audioEvent", { audioSourceId, eventType, data: data || {} });
    }

    // --- YouTube IFrame Player API integration ----------------------------

    getYoutubeHost() {
      if (!this.youtubeHostEl) {
        this.youtubeHostEl = document.createElement("div");
        this.youtubeHostEl.style.position = "absolute";
        this.youtubeHostEl.style.left = "-10000px";
        this.youtubeHostEl.style.top = "-10000px";
        this.youtubeHostEl.style.width = "200px";
        this.youtubeHostEl.style.height = "200px";
        this.youtubeHostEl.style.opacity = "0.01";
        this.youtubeHostEl.style.overflow = "hidden";
        this.youtubeHostEl.style.pointerEvents = "none";
        document.body.appendChild(this.youtubeHostEl);
      }
      return this.youtubeHostEl;
    }

    loadYoutubeApi() {
      if (this.youtubeApiPromise) return this.youtubeApiPromise;
      this.youtubeApiPromise = new Promise((resolve) => {
        if (window.YT && window.YT.Player) {
          resolve(window.YT);
          return;
        }
        const previous = window.onYouTubeIframeAPIReady;
        window.onYouTubeIframeAPIReady = () => {
          if (typeof previous === "function") previous();
          resolve(window.YT);
        };
        const script = document.createElement("script");
        script.src = "https://www.youtube.com/iframe_api";
        document.head.appendChild(script);
      });
      return this.youtubeApiPromise;
    }

    // --- Audio source lifecycle --------------------------------------------

    createHtml5Source(audioSourceId, url, config) {
      const ctx = this.ensureAudioContext();

      const element = new Audio();
      element.crossOrigin = "anonymous";
      element.loop = config.loop;
      element.playbackRate = config.playbackRate;
      element.preload = "auto";
      element.src = url;

      const sourceNode = ctx.createMediaElementSource(element);
      const trackGain = ctx.createGain();
      trackGain.gain.value = config.volume;
      const fanoutGain = ctx.createGain();
      fanoutGain.gain.value = 1;

      sourceNode.connect(trackGain);
      trackGain.connect(fanoutGain);

      const entry = {
        kind: "html5",
        audioSourceId,
        url,
        config,
        element,
        sourceNode,
        trackGain,
        fanoutGain,
        directlyConnected: false,
        isReady: false,
        isPlaying: false,
        duration: 0,
        speakerIds: new Set(),
      };
      this.audioSources.set(audioSourceId, entry);
      this.connectDirect(entry); // dry passthrough until a speaker takes over routing

      element.addEventListener("loadedmetadata", () => {
        entry.duration = element.duration || 0;
        if (!entry.isReady) {
          entry.isReady = true;
          this.reportAudioEvent(audioSourceId, "ready", { duration: entry.duration });
        }
      });
      element.addEventListener("ended", () => {
        entry.isPlaying = false;
        if (!entry.config.loop) this.reportAudioEvent(audioSourceId, "ended", {});
      });
      element.addEventListener("error", () => {
        const mediaError = element.error;
        this.reportAudioEvent(audioSourceId, "error", {
          message: mediaError ? `media error code ${mediaError.code}` : "unknown media error",
        });
      });
      element.addEventListener("play", () => {
        entry.isPlaying = true;
      });
      element.addEventListener("pause", () => {
        entry.isPlaying = false;
      });
    }

    createYoutubeSource(audioSourceId, url, config) {
      const videoId = extractYoutubeVideoId(url) || url;

      const entry = {
        kind: "youtube",
        audioSourceId,
        url,
        videoId,
        config,
        player: null,
        containerEl: null,
        isReady: false,
        isPlaying: false,
        pendingPlay: false,
        duration: 0,
        speakerIds: new Set(),
      };
      this.audioSources.set(audioSourceId, entry);

      this.loadYoutubeApi().then((YT) => {
        if (!this.audioSources.has(audioSourceId) || this.audioSources.get(audioSourceId) !== entry) return;

        const container = document.createElement("div");
        container.id = `sound-engine-yt-${audioSourceId}`;
        this.getYoutubeHost().appendChild(container);
        entry.containerEl = container;

        entry.player = new YT.Player(container.id, {
          height: "200",
          width: "200",
          videoId,
          playerVars: { autoplay: 0, controls: 0, disablekb: 1, fs: 0, modestbranding: 1, playsinline: 1 },
          events: {
            onReady: () => {
              entry.isReady = true;
              try {
                entry.player.setVolume(Math.round(clamp(entry.config.volume, 0, 1) * 100));
                entry.player.setPlaybackRate(entry.config.playbackRate || 1);
              } catch {
                /* ignore */
              }
              entry.duration = entry.player.getDuration() || 0;
              this.reportAudioEvent(audioSourceId, "ready", { duration: entry.duration });

              if (entry.pendingPlay) {
                entry.pendingPlay = false;
                entry.player.playVideo();
                this.reportAudioEvent(audioSourceId, "playbackStarted", { currentTime: 0 });
              }
            },
            onStateChange: (event) => {
              if (event.data === YT.PlayerState.PLAYING) {
                entry.isPlaying = true;
              } else if (event.data === YT.PlayerState.PAUSED) {
                entry.isPlaying = false;
              } else if (event.data === YT.PlayerState.ENDED) {
                if (entry.config.loop) {
                  entry.player.seekTo(0, true);
                  entry.player.playVideo();
                } else {
                  entry.isPlaying = false;
                  this.reportAudioEvent(audioSourceId, "ended", {});
                }
              }
            },
            onError: (event) => {
              this.reportAudioEvent(audioSourceId, "error", { message: `youtube player error code ${event.data}` });
            },
          },
        });
      });
    }

    handleAddAudioSource(message) {
      const audioSourceId = String(message.audioSourceId);
      if (this.audioSources.has(audioSourceId)) {
        this.handleRemoveAudioSource({ audioSourceId });
      }

      const config = normalizeSourceConfig(message.config);
      const url = message.url;
      if (!url) return;

      if (isYoutubeUrl(url)) {
        this.createYoutubeSource(audioSourceId, url, config);
      } else {
        this.createHtml5Source(audioSourceId, url, config);
      }
    }

    handleRemoveAudioSource(message) {
      const audioSourceId = String(message.audioSourceId);
      const entry = this.audioSources.get(audioSourceId);
      if (!entry) return;

      for (const speakerId of Array.from(entry.speakerIds)) {
        this.handleRemoveSpeaker({ speakerId });
      }

      if (entry.kind === "html5") {
        try {
          entry.element.pause();
          entry.element.removeAttribute("src");
          entry.element.load();
          entry.trackGain.disconnect();
          entry.fanoutGain.disconnect();
          entry.sourceNode.disconnect();
        } catch {
          /* best effort teardown */
        }
      } else if (entry.kind === "youtube") {
        try {
          entry.player && entry.player.destroy();
        } catch {
          /* ignore */
        }
        if (entry.containerEl && entry.containerEl.parentNode) {
          entry.containerEl.parentNode.removeChild(entry.containerEl);
        }
      }

      this.audioSources.delete(audioSourceId);
    }

    handleSetLoop(message) {
      const entry = this.audioSources.get(String(message.audioSourceId));
      if (!entry) return;
      entry.config.loop = message.loop === true;
      if (entry.kind === "html5") entry.element.loop = entry.config.loop;
    }

    // --- Playback transport --------------------------------------------------

    handlePlayAudioSource(message) {
      const audioSourceId = String(message.audioSourceId);
      const entry = this.audioSources.get(audioSourceId);
      if (!entry) return;

      if (entry.kind === "html5") {
        this.fadeTrackGain(entry, entry.config.volume, entry.config.fadeInDuration);
        const playResult = entry.element.play();
        const report = () =>
          this.reportAudioEvent(audioSourceId, "playbackStarted", { currentTime: entry.element.currentTime });
        if (playResult && typeof playResult.then === "function") {
          playResult.then(report).catch((err) => {
            this.reportAudioEvent(audioSourceId, "error", { message: err && err.message ? err.message : String(err) });
          });
        } else {
          report();
        }
      } else if (entry.kind === "youtube") {
        if (entry.isReady && entry.player) {
          entry.player.playVideo();
          this.reportAudioEvent(audioSourceId, "playbackStarted", { currentTime: this.getEntryCurrentTime(entry) });
        } else {
          entry.pendingPlay = true; // fired from onReady once the player exists
        }
      }
    }

    handleStopAudioSource(message) {
      const audioSourceId = String(message.audioSourceId);
      const entry = this.audioSources.get(audioSourceId);
      if (!entry) return;

      // No audioEvent is fired here: client/sound.lua's audioEvent handler
      // has no mapping for a "stopped" eventType (only started/paused/
      // resumed/ready/error/ended), so stop is a silent, fire-and-forget
      // command from Lua's point of view.
      if (entry.kind === "html5") {
        entry.element.pause();
        entry.element.currentTime = 0;
        const ctx = this.ensureAudioContext();
        entry.trackGain.gain.cancelScheduledValues(ctx.currentTime);
        entry.trackGain.gain.setValueAtTime(entry.config.volume, ctx.currentTime);
      } else if (entry.kind === "youtube" && entry.player) {
        try {
          entry.player.stopVideo();
        } catch {
          /* ignore */
        }
      }
      entry.isPlaying = false;
    }

    handlePauseAudioSource(message) {
      const audioSourceId = String(message.audioSourceId);
      const entry = this.audioSources.get(audioSourceId);
      if (!entry) return;

      const finish = () => {
        if (entry.kind === "html5") entry.element.pause();
        else if (entry.kind === "youtube" && entry.player) entry.player.pauseVideo();
        this.reportAudioEvent(audioSourceId, "playbackPaused", { currentTime: this.getEntryCurrentTime(entry) });
      };

      if (entry.kind === "html5" && entry.config.fadeOutDuration > 0) {
        this.fadeTrackGain(entry, 0, entry.config.fadeOutDuration);
        setTimeout(finish, entry.config.fadeOutDuration);
      } else {
        finish();
      }
    }

    handleResumeAudioSource(message) {
      const audioSourceId = String(message.audioSourceId);
      const entry = this.audioSources.get(audioSourceId);
      if (!entry) return;

      if (entry.kind === "html5") {
        this.fadeTrackGain(entry, entry.config.volume, entry.config.fadeInDuration);
        const playResult = entry.element.play();
        const report = () =>
          this.reportAudioEvent(audioSourceId, "playbackResumed", { currentTime: entry.element.currentTime });
        if (playResult && typeof playResult.then === "function") {
          playResult.then(report).catch((err) => {
            this.reportAudioEvent(audioSourceId, "error", { message: err && err.message ? err.message : String(err) });
          });
        } else {
          report();
        }
      } else if (entry.kind === "youtube" && entry.player) {
        entry.player.playVideo();
        this.reportAudioEvent(audioSourceId, "playbackResumed", { currentTime: this.getEntryCurrentTime(entry) });
      }
    }

    handleSeekAudioSource(message) {
      const entry = this.audioSources.get(String(message.audioSourceId));
      if (!entry) return;
      const seconds = numberOr(message.position, 0);
      if (entry.kind === "html5") entry.element.currentTime = seconds;
      else if (entry.kind === "youtube" && entry.player) entry.player.seekTo(seconds, true);
    }

    // --- Speakers / positional audio ---------------------------------------
    //
    // client/sound.lua's speaker config field names (refDistance,
    // maxDistance, rolloffFactor, coneInnerAngle, coneOuterAngle,
    // coneOuterGain) are exactly the Web Audio PannerNode's own property
    // names -- a real PannerNode owns the distance/panning math for HTML5
    // sources, fed each tick with the raw positions the `update` message
    // provides. The YouTube path can't reach a PannerNode (cross-origin
    // iframe audio isn't capturable by Web Audio), so it falls back to a
    // manual replica of the same 'inverse' distanceModel formula, driving
    // the IFrame player's own setVolume().
    //
    // "pannerDisabled" (set when the listening player is inside the same
    // vehicle as the attached speaker) is implemented by feeding the
    // PannerNode the *listener's own* position instead of the speaker's
    // real world position -- collapsing distance to ~0 so panning/falloff
    // become inert without needing to rewire the audio graph. That's also
    // why music keeps sounding like it's "in the car" once you step out:
    // pannerDisabled turns off and the speaker's real (vehicle) position
    // takes over, so distance/direction start applying again immediately.

    applySpeakerConfigToNodes(speaker, immediate) {
      if (!speaker.panner) return;
      const ctx = this.ensureAudioContext();
      const panner = speaker.panner;
      const config = speaker.config;

      panner.refDistance = Math.max(0, numberOr(config.refDistance, 1.0));
      panner.maxDistance = Math.max(panner.refDistance + 0.01, numberOr(config.maxDistance, 50.0));
      panner.rolloffFactor = Math.max(0, numberOr(config.rolloffFactor, 1.0));
      panner.coneInnerAngle = numberOr(config.coneInnerAngle, 360);
      panner.coneOuterAngle = numberOr(config.coneOuterAngle, 360);
      panner.coneOuterGain = clamp(numberOr(config.coneOuterGain, 0), 0, 1);

      const outsideFactor = config.pannerDisabled ? 1 : OUTSIDE_VEHICLE_VOLUME_FACTOR;
      const targetVolume = numberOr(config.volumeMultiplier, 1.0) * outsideFactor;
      if (immediate) {
        speaker.volumeGain.gain.setValueAtTime(targetVolume, ctx.currentTime);
      } else {
        speaker.volumeGain.gain.setTargetAtTime(targetVolume, ctx.currentTime, 0.05);
      }
    }

    applyFilterState(speaker, globalEnabled, immediate) {
      const effective = globalEnabled !== false && speaker.filterEnabled !== false;
      const freq = effective && speaker.config.lowPassFrequency > 0 ? speaker.config.lowPassFrequency : 22050;
      const reduction = effective ? 1 - clamp((speaker.config.lowPassGainReductionPercent || 0) / 100, 0, 1) : 1;

      speaker.effectiveReduction = reduction; // cached for the YouTube manual-gain path

      if (speaker.filter) {
        const ctx = this.ensureAudioContext();
        if (immediate) speaker.filter.frequency.setValueAtTime(freq, ctx.currentTime);
        else speaker.filter.frequency.setTargetAtTime(freq, ctx.currentTime, 0.05);
      }
      if (speaker.reductionGain) {
        const ctx = this.ensureAudioContext();
        if (immediate) speaker.reductionGain.gain.setValueAtTime(reduction, ctx.currentTime);
        else speaker.reductionGain.gain.setTargetAtTime(reduction, ctx.currentTime, 0.05);
      }
    }

    handleAddSpeaker(message) {
      const speakerId = String(message.speakerId);
      const audioSourceId = String(message.audioSourceId);
      const sourceEntry = this.audioSources.get(audioSourceId);
      if (!sourceEntry) return; // Lua already validated the source exists before sending this

      const config = normalizeSpeakerConfig(message.config);
      const speaker = {
        speakerId,
        audioSourceId,
        position: message.position || [0, 0, 0],
        config,
        filterEnabled: true,
        panner: null,
        filter: null,
        reductionGain: null,
        volumeGain: null,
        effectiveReduction: 1,
      };
      this.speakers.set(speakerId, speaker);
      sourceEntry.speakerIds.add(speakerId);

      if (sourceEntry.kind === "html5") {
        const ctx = this.ensureAudioContext();

        const panner = ctx.createPanner();
        // HRTF gives real front/back/up/down directional cues (closer to
        // how the native in-game radio's own 3D audio sounds); equalpower
        // only blends left/right and reads much flatter/less "real".
        panner.panningModel = "HRTF";
        panner.distanceModel = "inverse";

        const filter = ctx.createBiquadFilter();
        filter.type = "lowpass";

        const reductionGain = ctx.createGain();
        const volumeGain = ctx.createGain();

        sourceEntry.fanoutGain.connect(panner);
        panner.connect(filter);
        filter.connect(reductionGain);
        reductionGain.connect(volumeGain);
        volumeGain.connect(ctx.destination);

        speaker.panner = panner;
        speaker.filter = filter;
        speaker.reductionGain = reductionGain;
        speaker.volumeGain = volumeGain;

        this.applySpeakerConfigToNodes(speaker, true);
        this.setPannerPosition(panner, ctx, speaker.position);

        // A positional path now exists for this source -- stop the dry
        // passthrough so the source isn't audible twice.
        this.disconnectDirect(sourceEntry);
      }

      this.applyFilterState(speaker, this.lastApplyLowPassFilterGlobal, true);
    }

    handleRemoveSpeaker(message) {
      const speakerId = String(message.speakerId);
      const speaker = this.speakers.get(speakerId);
      if (!speaker) return;
      this.speakers.delete(speakerId);

      const sourceEntry = this.audioSources.get(speaker.audioSourceId);
      if (!sourceEntry) return;

      sourceEntry.speakerIds.delete(speakerId);

      if (sourceEntry.kind === "html5") {
        try {
          speaker.panner && speaker.panner.disconnect();
        } catch {
          /* ignore */
        }
        try {
          speaker.filter && speaker.filter.disconnect();
        } catch {
          /* ignore */
        }
        try {
          speaker.reductionGain && speaker.reductionGain.disconnect();
        } catch {
          /* ignore */
        }
        try {
          speaker.volumeGain && speaker.volumeGain.disconnect();
        } catch {
          /* ignore */
        }

        if (sourceEntry.speakerIds.size === 0) this.connectDirect(sourceEntry);
      }
    }

    // Shared by updateSpeakerConfig and updateVehicleSpeaker: both send a
    // `config` object that may be a full config or a partial patch, so
    // fields are merged into the stored config rather than replacing it
    // wholesale (mirrors how the Lua side itself patches speaker.config).
    handleSpeakerConfigPatch(message, immediate) {
      const speaker = this.speakers.get(String(message.speakerId));
      if (!speaker) return;
      Object.assign(speaker.config, message.config || {});
      if (message.type === "updateVehicleSpeaker") {
        console.debug(
          `[CarPlay audio debug] speaker=${message.speakerId} pannerDisabled=${speaker.config.pannerDisabled} lowPassFrequency=${speaker.config.lowPassFrequency} lowPassGainReductionPercent=${speaker.config.lowPassGainReductionPercent} hasPanner=${!!speaker.panner}`,
        );
      }
      this.applySpeakerConfigToNodes(speaker, immediate);
      this.applyFilterState(speaker, this.lastApplyLowPassFilterGlobal, immediate);
    }

    handleSetSpeakerFilter(message) {
      const speaker = this.speakers.get(String(message.speakerId));
      if (!speaker) return;
      speaker.filterEnabled = message.enabled !== false;
      this.applyFilterState(speaker, this.lastApplyLowPassFilterGlobal, false);
    }

    // Per-tick listener + speaker position/orientation broadcast.
    handleUpdate(message) {
      this.lastApplyLowPassFilterGlobal = message.applyLowPassFilter !== false;

      if (message.listener) {
        if (message.listener.position) this.lastListenerPosition = message.listener.position;
        this.setListenerTransform(message.listener.position, message.listener.forward, message.listener.up);
      }

      // Throttled (once every ~2s) diagnostic for whether panning is being
      // fed real, distinct listener/panner data -- and whether this CEF
      // build even exposes the modern AudioParam-based AudioListener API
      // (positionX/forwardX/etc.) versus only the legacy setPosition().
      const now = Date.now();
      if (!this._lastPanDebugAt || now - this._lastPanDebugAt > 2000) {
        this._lastPanDebugAt = now;
        const ctx = this.ensureAudioContext();
        const listener = ctx.listener;
        for (const [speakerId, speaker] of this.speakers) {
          if (!speaker.panner) continue;
          console.debug(
            `[CarPlay pan debug] speaker=${speakerId} listenerAudioParamAPI=${!!listener.positionX} pannerAudioParamAPI=${!!speaker.panner.positionX} ` +
              `listenerPos=${JSON.stringify(message.listener?.position)} listenerForward=${JSON.stringify(message.listener?.forward)} ` +
              `speakerPos=${JSON.stringify(speaker.position)} pannerDisabled=${speaker.config.pannerDisabled}`,
          );
        }
      }

      const youtubeGainBySource = new Map();

      for (const speakerUpdate of message.speakers || []) {
        const speaker = this.speakers.get(String(speakerUpdate.id));
        if (!speaker) continue;

        speaker.position = speakerUpdate.position;
        this.applyFilterState(speaker, this.lastApplyLowPassFilterGlobal, false);

        const sourceEntry = this.audioSources.get(speaker.audioSourceId);
        if (!sourceEntry) continue;

        if (sourceEntry.kind === "html5" && speaker.panner) {
          const ctx = this.ensureAudioContext();
          const effectivePosition = speaker.config.pannerDisabled ? this.lastListenerPosition : speakerUpdate.position;
          this.setPannerPosition(speaker.panner, ctx, effectivePosition);
        } else if (sourceEntry.kind === "youtube") {
          const gain = speaker.config.pannerDisabled
            ? numberOr(speaker.config.volumeMultiplier, 1)
            : computeManualDistanceGain(speakerUpdate.distance, speaker.config) *
              numberOr(speaker.config.volumeMultiplier, 1) *
              (speaker.effectiveReduction ?? 1) *
              OUTSIDE_VEHICLE_VOLUME_FACTOR;
          const previous = youtubeGainBySource.get(speaker.audioSourceId) || 0;
          youtubeGainBySource.set(speaker.audioSourceId, Math.max(previous, gain));
        }
      }

      for (const [audioSourceId, gain] of youtubeGainBySource) {
        const entry = this.audioSources.get(audioSourceId);
        if (entry && entry.player && entry.isReady) {
          try {
            entry.player.setVolume(Math.round(clamp(gain, 0, 1) * 100));
          } catch {
            /* ignore */
          }
        }
      }
    }

    // --- NUI round trips (fetchData / getCurrentTime) -----------------------

    async handleFetchData(message) {
      const url = message.url;
      let payload = { url };

      try {
        if (isYoutubeUrl(url)) {
          const videoId = extractYoutubeVideoId(url) || url;
          const oembedUrl = `https://www.youtube.com/oembed?url=${encodeURIComponent(`https://www.youtube.com/watch?v=${videoId}`)}&format=json`;
          const response = await fetch(oembedUrl);
          if (response.ok) {
            const info = await response.json();
            payload = {
              url,
              title: info.title,
              author: info.author_name,
              thumbnail: info.thumbnail_url,
              videoId,
              status: "success",
            };
          } else {
            // oEmbed lookup failed (private/deleted/age-restricted video),
            // but the video id itself is valid -- still let the import go
            // through with that as the title instead of failing outright.
            payload = { url, title: videoId, videoId, status: "success" };
          }
        } else {
          payload = { url, title: deriveTitleFromUrl(url), status: "success" };
        }
      } catch (err) {
        // The Lua side has a pending, un-timed-out callback waiting on
        // receiveTitle for this exact url -- always answer it, even on
        // failure, or that callback leaks forever. client/main.lua's
        // fetchYouTubeData callback specifically checks result.status ==
        // "success" to decide whether to report success -- status must be
        // set explicitly here, or every lookup (even ones that genuinely
        // worked) gets reported as "Failed to fetch video data".
        payload = {
          url,
          title: deriveTitleFromUrl(url),
          error: err && err.message ? err.message : String(err),
          status: "error",
        };
      }

      nui("receiveTitle", payload);
    }

    handleGetCurrentTime(message) {
      const entry = this.audioSources.get(String(message.audioSourceId));
      const currentTime = entry ? this.getEntryCurrentTime(entry) : 0;
      // Lua's GetCurrentTime export blocks on this promise resolving, so
      // this must always be answered, even when the source is unknown.
      nui("currentTime", { audioSourceId: message.audioSourceId, currentTime });
    }

    // --- Dispatch ------------------------------------------------------------

    handleMessage(event) {
      const message = event?.data;
      if (!message || typeof message !== "object" || !message.type) return;
      switch (message.type) {
        case "addAudioSource":
          return this.handleAddAudioSource(message);
        case "removeAudioSource":
          return this.handleRemoveAudioSource(message);
        case "setLoop":
          return this.handleSetLoop(message);
        case "playAudioSource":
          return this.handlePlayAudioSource(message);
        case "stopAudioSource":
          return this.handleStopAudioSource(message);
        case "addSpeaker":
          return this.handleAddSpeaker(message);
        case "removeSpeaker":
          return this.handleRemoveSpeaker(message);
        case "updateSpeakerConfig":
          return this.handleSpeakerConfigPatch(message, false);
        case "update":
          return this.handleUpdate(message);
        case "seekAudioSource":
          return this.handleSeekAudioSource(message);
        case "setSpeakerFilter":
          return this.handleSetSpeakerFilter(message);
        case "updateVehicleSpeaker":
          return this.handleSpeakerConfigPatch(message, message.priority === true);
        case "pauseAudioSource":
          return this.handlePauseAudioSource(message);
        case "resumeAudioSource":
          return this.handleResumeAudioSource(message);
        case "fetchData":
          return this.handleFetchData(message);
        case "getCurrentTime":
          return this.handleGetCurrentTime(message);
        default:
          return;
      }
    }

    // Read-only snapshot for UI purposes, keyed by audioSourceId. Returns
    // { isPlaying, currentTime, duration } or null if the source doesn't
    // exist (removed, never added, etc).
    getState(audioSourceId) {
      const entry = this.audioSources.get(String(audioSourceId));
      if (!entry) return null;
      return {
        isPlaying: !!entry.isPlaying,
        currentTime: this.getEntryCurrentTime(entry),
        duration: entry.duration || 0,
      };
    }
  }

  window.AudioManager = AudioManager;
})();
