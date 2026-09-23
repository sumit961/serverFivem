// nv_cloth/web/camera-controls.js
// Drag on the empty area over the character to orbit, scroll to zoom.
// Include after app.js:  <script src="camera-controls.js"></script>
// Set STAGE_ID to the element that covers the ped (the transparent part of the UI).

(() => {
  const STAGE_ID = 'preview-stage';
  const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nv_cloth';
  const post = (data) =>
    fetch(`https://${RES}/camera`, { method: 'POST', body: JSON.stringify(data) }).catch(() => {});

  let dragging = false, lastX = 0, lastY = 0;
  let accX = 0, accY = 0, queued = false;

  const flush = () => {
    queued = false;
    if (accX || accY) post({ rotate: accX, pitch: accY });
    accX = accY = 0;
  };

  const bind = () => {
    const stage = document.getElementById(STAGE_ID);
    if (!stage) return console.warn('[nv_cloth] camera stage element not found:', STAGE_ID);

    stage.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      dragging = true; lastX = e.clientX; lastY = e.clientY;
    });
    window.addEventListener('mouseup', () => (dragging = false));
    window.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      accX += (e.clientX - lastX) * 0.4;   // flip sign to invert
      accY += (e.clientY - lastY) * 0.2;
      lastX = e.clientX; lastY = e.clientY;
      if (!queued) { queued = true; requestAnimationFrame(flush); } // max one request per frame
    });
    stage.addEventListener('wheel', (e) => post({ zoom: e.deltaY > 0 ? 0.15 : -0.15 }), { passive: true });
    stage.addEventListener('dblclick', () => post({ reset: true }));
  };

  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', bind) : bind();

  // Call this from your category switch in app.js:  window.nvCloth.setCameraCategory('shoes')
  window.nvCloth = window.nvCloth || {};
  window.nvCloth.setCameraCategory = (category) => post({ category });
})();

