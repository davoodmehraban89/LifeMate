import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';

const source = await fs.readFile(new URL('../web/lifeguide-sw.js', import.meta.url), 'utf8');
function worker({offline=false}={}) {
  const handlers={},stored=new Map(),requests=[];
  const response=new Response('synthetic public document',{status:200});
  const cache={async put(key,value){stored.set(typeof key==='string'?key:key.url,value);},
    async match(key){return stored.get(typeof key==='string'?key:key.url);}};
  const context={URL,Request,Response,
    self:{location:{href:'https://offline.example.test/lifeguide-sw.js',origin:'https://offline.example.test'},
      addEventListener(name,handler){handlers[name]=handler;},async skipWaiting(){},clients:{async claim(){}}},
    caches:{async open(){return cache;},async keys(){return[];},async delete(){}},
    async fetch(request,options){requests.push({request,options});if(offline)throw new Error('synthetic network down');return response.clone();}};
  vm.runInNewContext(source,context);
  return {handlers,cache,stored,requests,setOffline(value){offline=value;},
    async install(){let done;handlers.install({waitUntil(value){done=value;}});await done;},
    async fetch(path,{mode='navigate',authorization=false,method='GET'}={}) {
      let result;
      const request={url:'https://offline.example.test'+path,mode,method,
        headers:new Headers(authorization?{authorization:'synthetic'}:{})};
      handlers.fetch({request,respondWith(value){result=value;}});
      return result===undefined?undefined:await result;
    }};
}

test('installation caches only a credential-free public offline notice and retry script',async()=>{
  const w=worker();await w.install();
  assert.equal(w.stored.size,2);
  for(const call of w.requests){assert.equal(call.request.credentials,'omit');assert.equal(call.options.cache,'no-store');}
});
test('cold offline navigation receives public notice; online navigation prefers network',async()=>{
  const w=worker();await w.install();w.setOffline(true);
  assert.equal((await w.fetch('/')).status,200);
  w.setOffline(false);const before=w.requests.length;
  assert.equal((await w.fetch('/')).status,200);
  assert.equal(w.requests.length,before+1);
});
test('API, runtime configuration, auth paths and authenticated requests never receive fallback',async()=>{
  const w=worker();await w.install();w.setOffline(true);
  for(const path of ['/api/health','/api/v1/profile','/config.json','/verify-email?token=synthetic','/accept-invitation?token=synthetic','/unknown']) {
    assert.equal(await w.fetch(path),undefined,path);
  }
  assert.equal(await w.fetch('/',{authorization:true}),undefined);
  assert.equal(await w.fetch('/',{method:'POST'}),undefined);
});
test('uncached private content is never created by offline navigation',async()=>{
  const w=worker();await w.install();const keys=[...w.stored.keys()];w.setOffline(true);
  await w.fetch('/index.html');assert.deepEqual([...w.stored.keys()],keys);
});
