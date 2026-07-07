// Leaflet is bundled inside Senor Airdrops' map vendor as an ES module export.
// Expose it as window.L so the plain Climatime app.js can use it without React.
import { l as Leaflet } from './assets/map-vendor-Ig5MRTue.js';

window.L = Leaflet;
window.dispatchEvent(new Event('cm-leaflet-ready'));
