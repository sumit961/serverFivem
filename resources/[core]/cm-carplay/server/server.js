console.log('[cm-carplay] server.js: starting load');

const fs = require('fs');
const path = require('path');
const https = require('https');

// Server-side YouTube stream extraction is intentionally disabled. The
// archived extractor requires a newer Node version than FiveM's Yarn build
// worker and no longer follows YouTube player changes reliably. Client Lua
// routes YouTube tracks through the supported IFrame player instead.
const ytdl = null;
const ytdlLoadError = new Error('Server-side YouTube caching is disabled');

// YouTube -> local audio-only file, so it can be played through the same
// HTML5 <audio> + Web Audio pipeline as local tracks (real PannerNode/
// BiquadFilter positional audio) instead of the YouTube iframe, whose audio
// a cross-origin page can never route through Web Audio at all.
//
// Downloads once per video id into cache/youtube/ and reuses the cached
// file for every later play -- exported for Lua to call from playMusic.
// The cache name is versioned because older builds wrote every format as
// `.m4a`; a cached WebM/Opus stream with an MP4 extension cannot be decoded
// by the NUI audio element and must never be reused.
const YOUTUBE_CACHE_DIR = path.join(GetResourcePath(GetCurrentResourceName()), 'cache', 'youtube');
const YOUTUBE_CACHE_VERSION = 'v2';
const YOUTUBE_RESOLVE_TIMEOUT_MS = 30000;
const YOUTUBE_DOWNLOAD_TIMEOUT_MS = 45000;
const YOUTUBE_MAX_DOWNLOAD_BYTES = 128 * 1024 * 1024;
const YOUTUBE_MAX_CACHE_BYTES = 1024 * 1024 * 1024;
const YOUTUBE_CACHE_MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000;
const YOUTUBE_MAX_ACTIVE_DOWNLOADS = 2;
const youtubeResolveWaiters = new Map();
const youtubeResolveActive = new Set();
let activeYoutubeDownloads = 0;

function finishYoutubeResolve(videoId, result) {
    if (youtubeResolveActive.delete(videoId)) {
        activeYoutubeDownloads = Math.max(0, activeYoutubeDownloads - 1);
    }
    const waiters = youtubeResolveWaiters.get(videoId) || [];
    youtubeResolveWaiters.delete(videoId);
    for (const waiter of waiters) {
        try {
            waiter(result);
        } catch (err) {
            console.error('[cm-carplay] YouTube resolve callback failed:', err && err.stack || err);
        }
    }
}

let youtubeAgent = null;
function loadYoutubeAgent() {
    if (!ytdl) return;
    try {
        let rawCookies = '';
        try { rawCookies = GetConvar('cm_carplay_youtube_cookies', ''); } catch { /* convar unavailable */ }
        if (!rawCookies) {
            const cookiesPath = path.join(GetResourcePath(GetCurrentResourceName()), 'server', 'youtube-cookies.json');
            if (fs.existsSync(cookiesPath)) rawCookies = fs.readFileSync(cookiesPath, 'utf8');
        }
        const cookies = rawCookies ? JSON.parse(rawCookies) : [];
        if (Array.isArray(cookies) && cookies.length > 0) {
            youtubeAgent = ytdl.createAgent(cookies);
            console.log('[cm-carplay] YouTube cookie agent enabled');
        }
    } catch (err) {
        console.error('[cm-carplay] YouTube cookie agent could not be loaded:', err && err.message || err);
    }
}
loadYoutubeAgent();

function withTimeout(promise, timeoutMs, message) {
    let timer;
    const timeout = new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(message)), timeoutMs);
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function cleanupYoutubeCache() {
    try {
        fs.mkdirSync(YOUTUBE_CACHE_DIR, { recursive: true });
        const now = Date.now();
        const entries = fs.readdirSync(YOUTUBE_CACHE_DIR)
            .filter((name) => /^[a-zA-Z0-9_-]+\.v2\.(?:m4a|webm)(?:\.part)?$/.test(name))
            .map((name) => {
                const filePath = path.join(YOUTUBE_CACHE_DIR, name);
                try {
                    const stat = fs.statSync(filePath);
                    return { name, filePath, size: stat.size, mtimeMs: stat.mtimeMs };
                } catch {
                    return null;
                }
            })
            .filter(Boolean);

        for (const entry of entries) {
            if (entry.name.endsWith('.part') || now - entry.mtimeMs > YOUTUBE_CACHE_MAX_AGE_MS) {
                try { fs.unlinkSync(entry.filePath); } catch { /* best effort */ }
            }
        }

        const cached = entries
            .filter((entry) => !entry.name.endsWith('.part') && fs.existsSync(entry.filePath))
            .sort((a, b) => a.mtimeMs - b.mtimeMs);
        let total = cached.reduce((sum, entry) => sum + entry.size, 0);
        for (const entry of cached) {
            if (total <= YOUTUBE_MAX_CACHE_BYTES) break;
            try {
                fs.unlinkSync(entry.filePath);
                total -= entry.size;
            } catch { /* best effort */ }
        }
    } catch (err) {
        console.error('[cm-carplay] YouTube cache cleanup failed:', err && err.message || err);
    }
}

setTimeout(cleanupYoutubeCache, 1000);
setInterval(cleanupYoutubeCache, 6 * 60 * 60 * 1000);

function audioFormatScore(format) {
    return Number(format.audioBitrate || format.bitrate || format.averageBitrate || 0);
}

function chooseYoutubeAudioFormat(formats) {
    const audioOnly = (formats || []).filter((format) =>
        format && format.hasAudio && !format.hasVideo && format.url
    );

    // Prefer AAC/MP4 because CEF can decode it consistently as an HTML5
    // audio source. WebM/Opus remains a valid fallback for videos that do
    // not expose an MP4 audio-only format.
    const mp4 = audioOnly
        .filter((format) => format.container === 'mp4' || /^audio\/mp4(?:;|$)/i.test(format.mimeType || ''))
        .sort((a, b) => audioFormatScore(b) - audioFormatScore(a));
    if (mp4[0]) return mp4[0];

    return audioOnly.sort((a, b) => audioFormatScore(b) - audioFormatScore(a))[0] || null;
}

function cacheDescriptor(videoId, extension) {
    const safeExtension = extension === 'webm' ? 'webm' : 'm4a';
    return {
        filename: `${videoId}.${YOUTUBE_CACHE_VERSION}.${safeExtension}`,
        path: path.join(YOUTUBE_CACHE_DIR, `${videoId}.${YOUTUBE_CACHE_VERSION}.${safeExtension}`),
    };
}

function requestYoutubeInfo(canonicalUrl) {
    const baseOptions = youtubeAgent ? { agent: youtubeAgent } : {};
    let firstAttempt;
    try {
        firstAttempt = ytdl.getInfo(canonicalUrl, baseOptions);
    } catch (err) {
        return Promise.reject(err);
    }

    return firstAttempt.catch((err) => {
        const message = String(err && err.message || err).toLowerCase();
        if (!message.includes('not a bot') && !message.includes('sign in to confirm')) {
            throw err;
        }

        // The latest ytdl-core supports alternate player clients. A second,
        // lower-request-profile attempt can work when only the WEB client is
        // challenged. If the server IP is globally challenged, the caller
        // still falls back to the browser player or configured cookies.
        return ytdl.getInfo(canonicalUrl, {
            ...baseOptions,
            playerClients: ['ANDROID', 'TV', 'IOS'],
        });
    });
}

function findCachedYoutubeAudio(videoId) {
    for (const extension of ['m4a', 'webm']) {
        const cached = cacheDescriptor(videoId, extension);
        try {
            if (fs.existsSync(cached.path) && fs.statSync(cached.path).size > 0) return cached;
        } catch (err) {
            console.error('[cm-carplay] YouTube cache stat failed:', err && err.message || err);
        }
    }
    return null;
}

function resolveYoutubeAudio(url, videoId, callback) {
    const done = typeof callback === 'function' ? callback : () => {};
    if (!ytdl) {
        done({ success: false, error: 'YouTube resolver failed to load on the server: ' + (ytdlLoadError && ytdlLoadError.message || 'unknown error') });
        return;
    }
    if (!videoId || !ytdl.validateID(videoId)) {
        done({ success: false, error: 'Invalid YouTube video id' });
        return;
    }

    // The ID is the only trusted input needed here. Always resolve the
    // canonical YouTube URL so a client cannot turn this downloader into a
    // generic server-side URL fetcher.
    const canonicalUrl = `https://www.youtube.com/watch?v=${videoId}`;

    const cached = findCachedYoutubeAudio(videoId);
    if (cached) {
        done({ success: true, filename: cached.filename });
        return;
    }

    const pending = youtubeResolveWaiters.get(videoId);
    if (pending) {
        pending.push(done);
        return;
    }
    if (activeYoutubeDownloads >= YOUTUBE_MAX_ACTIVE_DOWNLOADS) {
        done({ success: false, error: 'The YouTube resolver is busy; please try again shortly' });
        return;
    }
    youtubeResolveWaiters.set(videoId, [done]);
    youtubeResolveActive.add(videoId);
    activeYoutubeDownloads += 1;

    try {
        fs.mkdirSync(YOUTUBE_CACHE_DIR, { recursive: true });
    } catch (err) {
        finishYoutubeResolve(videoId, { success: false, error: 'Could not create the YouTube cache directory: ' + (err.message || err) });
        return;
    }

    const infoPromise = requestYoutubeInfo(canonicalUrl);

    withTimeout(infoPromise, YOUTUBE_RESOLVE_TIMEOUT_MS, 'YouTube information request timed out').then((info) => {
        const format = chooseYoutubeAudioFormat(info.formats);
        if (!format) {
            finishYoutubeResolve(videoId, { success: false, error: 'No compatible audio-only format is available for this YouTube video' });
            return;
        }

        const extension = format.container === 'webm' || /^audio\/webm(?:;|$)/i.test(format.mimeType || '') ? 'webm' : 'm4a';
        const descriptor = cacheDescriptor(videoId, extension);
        const tempPath = descriptor.path + '.part';
        const contentType = extension === 'webm' ? 'audio/webm' : 'audio/mp4';
        let audioStream;
        try {
            audioStream = ytdl.downloadFromInfo(info, {
                format,
                ...(youtubeAgent ? { agent: youtubeAgent } : {}),
            });
        } catch (err) {
            finishYoutubeResolve(videoId, { success: false, error: err.message || 'Could not start the YouTube audio download' });
            return;
        }

        let fileStream;
        try {
            try { fs.unlinkSync(tempPath); } catch { /* no previous partial file */ }
            fileStream = fs.createWriteStream(tempPath);
        } catch (err) {
            finishYoutubeResolve(videoId, { success: false, error: err.message || 'Could not open the YouTube cache file' });
            return;
        }
        let settled = false;
        let bytesWritten = 0;
        const downloadTimer = setTimeout(() => {
            try { audioStream.destroy(new Error('YouTube audio download timed out')); } catch { /* best effort */ }
            fail('YouTube audio download timed out');
        }, YOUTUBE_DOWNLOAD_TIMEOUT_MS);

        const fail = (message) => {
            if (settled) return;
            settled = true;
            clearTimeout(downloadTimer);
            try { fileStream.destroy(); } catch (err) { /* best effort */ }
            try { audioStream.destroy(); } catch (err) { /* best effort */ }
            fs.unlink(tempPath, () => {});
            finishYoutubeResolve(videoId, { success: false, error: message || 'YouTube audio download failed' });
        };

        audioStream.on('error', (err) => {
            console.error('[cm-carplay] YouTube audio download failed:', err.message);
            fail(err.message || 'Download failed');
        });

        audioStream.on('data', (chunk) => {
            bytesWritten += chunk.length;
            if (bytesWritten > YOUTUBE_MAX_DOWNLOAD_BYTES) {
                fail('YouTube audio file is larger than the configured limit');
            }
        });

        fileStream.on('error', (err) => {
            console.error('[cm-carplay] YouTube audio cache write failed:', err.message);
            fail(err.message || 'Cache write failed');
        });

        fileStream.on('finish', () => {
            if (settled) return;
            settled = true;
            clearTimeout(downloadTimer);
            fs.rename(tempPath, descriptor.path, (err) => {
                if (err) {
                    console.error('[cm-carplay] YouTube audio cache rename failed:', err.message);
                    finishYoutubeResolve(videoId, { success: false, error: err.message });
                    return;
                }
                console.log(`[cm-carplay] Cached YouTube audio ${videoId} as ${descriptor.filename} (${contentType})`);
                finishYoutubeResolve(videoId, { success: true, filename: descriptor.filename });
            });
        });

        audioStream.pipe(fileStream);
    }).catch((err) => {
        console.error('[cm-carplay] YouTube audio resolve failed:', err.message);
        finishYoutubeResolve(videoId, { success: false, error: err.message || 'Failed to read video info' });
    });
}

exports('resolveYoutubeAudio', resolveYoutubeAudio);

console.log('[cm-carplay] server.js: finished loading, all exports registered (resolveYoutubeAudio)');
