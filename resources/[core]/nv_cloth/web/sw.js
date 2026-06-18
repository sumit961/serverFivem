self.addEventListener('install', function(event) {
  self.skipWaiting()
})

self.addEventListener('activate', function(event) {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('fetch', function(event) {
  const url = new URL(event.request.url)
  const isClothingPng = url.pathname.includes('/clothing/') && url.pathname.endsWith('.png')
  if (isClothingPng) {
    const base64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMAAQAABQABDQottwAAAABJRU5ErkJggg=='
    event.respondWith(
      fetch(event.request).then(function(resp) {
        if (!resp || !resp.ok) {
          return fetch('./clothing/nonee.png').then(function(fb) {
            if (fb && fb.ok) return fb
            const bytes = Uint8Array.from(atob(base64), function(c) { return c.charCodeAt(0) })
            return new Response(bytes, { headers: { 'Content-Type': 'image/png' } })
          })
        }
        return resp
      }).catch(function() {
        return fetch('./clothing/nonee.png').then(function(fb) {
          if (fb && fb.ok) return fb
          const bytes = Uint8Array.from(atob(base64), function(c) { return c.charCodeAt(0) })
          return new Response(bytes, { headers: { 'Content-Type': 'image/png' } })
        })
      })
    )
  }
})