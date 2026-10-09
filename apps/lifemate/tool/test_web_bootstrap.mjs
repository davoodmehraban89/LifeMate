import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const script = (await readFile(new URL('../web/flutter_bootstrap.js', import.meta.url), 'utf8'))
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');
let engineConfig;
let removed = false;
const status = {remove() { removed = true; }};
let ready;
const started = new Promise(resolve => { ready = resolve; });
const window = {isSecureContext:true,addEventListener() {}};
vm.runInNewContext(script, {
  URL,
  window,
  navigator: {locks: {request(name, options, callback) {
    assert.equal(name,'lifeguide.active-instance.v1');
    assert.equal(options.mode,'exclusive');
    assert.equal(options.ifAvailable,true);
    callback({name});
    return new Promise(() => {});
  }}},
  document: {baseURI: 'https://family.example.test/',
    getElementById: id => id === 'startup-status' ? status : null},
  _flutter: {loader: {async load(options) {
    assert.equal(options.config.canvasKitBaseUrl, 'https://family.example.test/canvaskit/');
    await options.onEntrypointLoaded({async initializeEngine(config) {
      engineConfig = config;
      return {async runApp() {}};
    }});
    ready();
  }}},
});
await started;
assert.equal(window.lifeguideInstanceOwned,true);
assert.equal(engineConfig?.fontFallbackBaseUrl, 'https://family.example.test/assets/fonts/fallback/');
assert.equal(removed, true);
console.log('Custom bootstrap passes the local font configuration to the Flutter engine.');
