console.log('[nodetest] server.js is executing, typeof require = ' + typeof require);

try {
    var fs = require('fs');
    console.log('[nodetest] require("fs") succeeded, typeof fs.readFileSync = ' + typeof fs.readFileSync);
} catch (e) {
    console.log('[nodetest] require("fs") FAILED: ' + (e && e.message));
}

try {
    exports('ping', function (cb) {
        cb('pong');
    });
    console.log('[nodetest] exports("ping", ...) call completed without throwing');
} catch (e) {
    console.log('[nodetest] exports("ping", ...) FAILED: ' + (e && e.message));
}

console.log('[nodetest] reached end of file');
