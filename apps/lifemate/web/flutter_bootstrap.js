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

// A document must own the origin-wide lock before Flutter can read credentials
// or personal caches. Keep the callback pending for the entire document lifetime.
// Browser teardown/crash releases the lock; backgrounding must not release it.
let instanceOwned = false;
let documentInvalidated = false;
let requestInFlight = false;
Object.defineProperty(window, 'lifeguideInstanceOwned', {get: () => instanceOwned});

window.addEventListener('pagehide', () => {
  documentInvalidated = true;
  instanceOwned = false;
});
window.addEventListener('pageshow', (event) => {
  // A cached engine must never resume with a stale ownership assertion. Keep
  // the old lock held until this document is replaced by a fresh bootstrap.
  if (event.persisted || documentInvalidated) window.location.reload();
});

function showInstanceNotice(unsupported) {
  const status = document.getElementById('startup-status');
  if (!status) return;
  status.setAttribute('role', 'alert');
  status.textContent = unsupported
    ? 'این مرورگر از اجرای امن لایف‌گاید پشتیبانی نمی‌کند. از یک مرورگر به‌روز و سازگار استفاده کنید.'
    : 'لایف‌گاید در پنجره دیگری باز است. برای ادامه، آن پنجره را ببندید و دوباره تلاش کنید.';
  let retry = document.getElementById('startup-retry');
  if (!retry) {
    retry = document.createElement('button');
    retry.id = 'startup-retry';
    retry.type = 'button';
    retry.textContent = 'تلاش دوباره';
    retry.style.cssText = 'display:block;margin:16px auto;padding:12px 24px;font:inherit;cursor:pointer';
    retry.addEventListener('click', startInstance);
    status.after(retry);
  }
}

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

async function startInstance() {
  if (requestInFlight) return;
  if (documentInvalidated) { window.location.reload(); return; }
  if (!window.isSecureContext || !navigator.locks?.request) {
    showInstanceNotice(true);
    return;
  }
  requestInFlight = true;
  document.getElementById('startup-retry')?.remove();
  try {
    await navigator.locks.request('lifeguide.active-instance.v1',
      {mode: 'exclusive', ifAvailable: true}, async (lock) => {
        if (!lock) { showInstanceNotice(false); return; }
        if (documentInvalidated) return;
        instanceOwned = true;
        prepareWorker();
        _flutter.loader.load({
          config: engineConfig,
          onEntrypointLoaded: async (initializer) => {
            try {
              if (!instanceOwned) return;
              const runner = await initializer.initializeEngine(engineConfig);
              if (!instanceOwned) return;
              await runner.runApp();
              document.getElementById('startup-status')?.remove();
            } catch (_) { showFailure(); }
          },
        }).catch(showFailure);
        await new Promise(() => {});
      });
  } catch (_) {
    instanceOwned = false;
    showInstanceNotice(true);
  } finally {
    requestInFlight = false;
  }
}

startInstance();
