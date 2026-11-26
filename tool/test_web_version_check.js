// Roda web_version_check.js com um navegador falso e confere quando recarrega.
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const source = fs.readFileSync(path.join(__dirname, 'web_version_check.js'), 'utf8');

async function run({current, published, typing = false, stored = null, ok = true}) {
  const calls = {fetch: 0, reload: 0, fetchInit: null};
  const listeners = {};
  const store = new Map(stored ? [['scape-build-reload', stored]] : []);
  const timers = [];
  const doc = {
    visibilityState: 'visible',
    baseURI: 'https://parceiro.escapematch.com.br/',
    activeElement: typing ? {tagName: 'INPUT'} : null,
    querySelector: () => (current === null ? null : {getAttribute: () => current}),
    addEventListener: (name, fn) => { listeners['doc:' + name] = fn; },
  };
  const win = {
    fetch: true,
    location: {reload: () => { calls.reload += 1; }},
    addEventListener: (name, fn) => { listeners['win:' + name] = fn; },
  };
  const fakeFetch = (url, init) => {
    calls.fetch += 1;
    calls.fetchInit = {url, ...init};
    return Promise.resolve({
      ok,
      text: () => Promise.resolve(
        `<head><meta name="scapematch-build" content="${published}"></head>`),
    });
  };
  const fn = new Function(
    'document', 'window', 'fetch', 'URL', 'sessionStorage', 'setTimeout',
    'setInterval', 'Date', source);
  fn(doc, win, fakeFetch, URL, {
    getItem: (k) => store.get(k) ?? null,
    setItem: (k, v) => store.set(k, v),
  }, (cb) => { timers.push(cb); return 1; }, () => 1, Date);
  for (const cb of timers) cb();
  await new Promise((r) => setImmediate(r));
  await new Promise((r) => setImmediate(r));
  return {calls, listeners, doc, store};
}

(async () => {
  let r = await run({current: 'aaa', published: 'bbb'});
  assert.strictEqual(r.calls.reload, 1, 'versão nova recarrega');
  assert.strictEqual(r.calls.fetchInit.cache, 'no-store');
  assert.strictEqual(r.calls.fetchInit.url, 'https://parceiro.escapematch.com.br/');

  r = await run({current: 'aaa', published: 'aaa'});
  assert.strictEqual(r.calls.reload, 0, 'mesma versão não recarrega');

  r = await run({current: 'dev', published: 'bbb'});
  assert.strictEqual(r.calls.fetch, 0, 'build sem versão não confere');

  r = await run({current: null, published: 'bbb'});
  assert.strictEqual(r.calls.fetch, 0, 'sem meta não confere');

  r = await run({current: 'aaa', published: 'bbb', stored: 'bbb'});
  assert.strictEqual(r.calls.reload, 0, 'não recarrega duas vezes para a mesma versão');

  r = await run({current: 'aaa', published: 'bbb', typing: true});
  assert.strictEqual(r.calls.reload, 0, 'não recarrega com campo em foco');
  r.doc.activeElement = null;
  r.listeners['doc:visibilitychange']();
  assert.strictEqual(r.calls.reload, 1, 'recarrega quando o campo perde o foco');

  r = await run({current: 'aaa', published: 'bbb', ok: false});
  assert.strictEqual(r.calls.reload, 0, 'resposta de erro não recarrega');

  console.log('web_version_check ok');
})().catch((e) => { console.error(e); process.exit(1); });
