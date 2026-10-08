{{flutter_js}}
{{flutter_build_config}}

const localBase = new URL('.', document.baseURI);
const engineConfig = {
  canvasKitBaseUrl: new URL('canvaskit/', localBase).href,
  fontFallbackBaseUrl: new URL('assets/fonts/fallback/', localBase).href,
};
const showFailure = () => {
  const status = document.getElementById('startup-status');
  if (status) status.textContent =
    'لایف‌گاید بارگذاری نشد. اتصال را بررسی کنید و صفحه را دوباره باز کنید.';
};

// Retire the legacy generated worker, which could serve stale runtime settings.
async function prepareWorker() {
  if (!('serviceWorker' in navigator)) return;
  try {
    const registrations = await navigator.serviceWorker.getRegistrations();
    for (const registration of registrations) {
      const script = (registration.active || registration.waiting || registration.installing)?.scriptURL;
      if (script && new URL(script).pathname.endsWith('/flutter_service_worker.js')) {
        await registration.unregister();
      }
    }
    await navigator.serviceWorker.register(new URL('lifeguide-sw.js', localBase), {updateViaCache: 'none'});
  } catch (_) { /* Network-only startup still works when worker setup fails. */ }
}

prepareWorker();
_flutter.loader.load({
  config: engineConfig,
  onEntrypointLoaded: async (initializer) => {
    try {
      const runner = await initializer.initializeEngine(engineConfig);
      await runner.runApp();
      document.getElementById('startup-status')?.remove();
    } catch (_) { showFailure(); }
  },
}).catch(showFailure);
