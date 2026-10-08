// Fresh application code/settings always come from the network. Cache only
// public static resources; no API, authentication, navigation or personal data.
const CACHE = 'lifeguide-static-v0.5.0-3';
const BASE_PATH = new URL('.', self.location.href).pathname;
const STATIC_PATH = /^(?:assets|canvaskit|icons)\//;
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if ((key.startsWith('lifeguide-static-') && key !== CACHE) || key.startsWith('flutter-')) {
        await caches.delete(key);
      }
    }
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin ||
      url.search || request.headers.has('authorization') ||
      !url.pathname.startsWith(BASE_PATH) ||
      !STATIC_PATH.test(url.pathname.slice(BASE_PATH.length))) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const response = await fetch(request, {cache: 'no-store'});
      if (response.ok) await cache.put(request, response.clone());
      return response;
    } catch (error) {
      const stored = await cache.match(request);
      if (stored) return stored;
      throw error;
    }
  })());
});
