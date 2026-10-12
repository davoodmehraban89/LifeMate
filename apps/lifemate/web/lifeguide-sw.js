// Current code/settings use the network. A cold disconnected navigation may
// show only a public notice, never cached login, permissions or personal data.
const CACHE = 'lifeguide-static-v0.7.1-7';
const BASE_PATH = new URL('.', self.location.href).pathname;
const OFFLINE_URL = new URL('offline.html', self.location.href).href;
const RETRY_URL = new URL('offline-retry.js', self.location.href).href;
const STATIC_PATH = /^(?:(?:assets|canvaskit|icons)\/|offline-retry\.js$)/;
self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    for (const url of [OFFLINE_URL, RETRY_URL]) {
      const response = await fetch(new Request(url, {credentials: 'omit'}), {cache: 'no-store'});
      if (!response.ok) throw new Error('Offline notice unavailable');
      await cache.put(url, response);
    }
    await self.skipWaiting();
  })());
});
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
      !url.pathname.startsWith(BASE_PATH)) return;
  const relative = url.pathname.slice(BASE_PATH.length);
  if (request.mode === 'navigate' && (relative === '' || relative === 'index.html')) {
    event.respondWith((async () => {
      try { return await fetch(request, {cache: 'no-store'}); }
      catch (error) {
        const stored = await (await caches.open(CACHE)).match(OFFLINE_URL);
        if (stored) return stored;
        throw error;
      }
    })());
    return;
  }
  if (
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
