'use strict';

// Substitui o service worker de cache do Flutter.
// O build usa --pwa-strategy=none, então uma visita nova não registra
// worker. Quem ainda tem o worker antigo baixa este arquivo na próxima
// atualização: ele apaga só o cache deste app, recarrega as abas dele
// e se remove. stamp_web_manifest.sh grava INSTALL_ID com a URL do atalho.
const INSTALL_ID = "https://nicolas00saliba.github.io/scapematch/parceiro/";
const CACHE_PREFIX = "scapematch-cache:" + INSTALL_ID + "|";

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(clearCachesAndReload());
});

// Não intercepta o próprio script: o navegador precisa compará-lo na rede.
// Pedido de outro app no mesmo domínio (a demo e o Parceiro dela) segue
// sem este worker. O resto, enquanto ele controla a página, ignora o cache.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  if (!inThisInstall(event.request.url)) {
    return;
  }
  const path = new URL(event.request.url).pathname;
  if (path.endsWith('/flutter_service_worker.js')) {
    return;
  }
  const appScript = path.endsWith('/main.dart.js');
  event.respondWith(fetch(event.request, {cache: 'reload'}).then((response) => {
    if (appScript) {
      event.waitUntil(self.registration.unregister());
    }
    return response;
  }));
});

function inThisInstall(url) {
  if (!url.startsWith(INSTALL_ID)) {
    return false;
  }
  const rest = url.slice(INSTALL_ID.length);
  // No Pages antigo a demo fica embaixo do app real. No host da demo,
  // /parceiro/ só redireciona: o atalho da casa está em outro host.
  // Esses caminhos têm instalação própria e não são deste app.
  if (nestedInstall(rest, 'parceiro') || nestedInstall(rest, 'demo')) {
    return false;
  }
  return true;
}

function nestedInstall(rest, name) {
  if (INSTALL_ID.endsWith('/' + name + '/')) {
    return false;
  }
  return rest === name ||
    rest.startsWith(name + '/') ||
    rest.startsWith(name + '?') ||
    rest.startsWith(name + '#');
}

function ownsCache(key) {
  if (key.startsWith('scapematch-cache:') && !key.startsWith(CACHE_PREFIX)) {
    return false;
  }
  return key.startsWith(CACHE_PREFIX) || !key.startsWith('scapematch-cache:');
}

async function clearCachesAndReload() {
  if (self.registration.scope !== INSTALL_ID) {
    return;
  }
  await self.clients.claim();
  const keys = await caches.keys();
  await Promise.all(keys.filter(ownsCache).map((key) => caches.delete(key)));
  const windows = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });
  const mine = windows.filter((client) => client.url && inThisInstall(client.url));
  // Não espera a navegação terminar. A página nova pode esperar este
  // activate, e esperar os dois lados trava o carregamento.
  for (const client of mine) {
    if (typeof client.navigate === 'function') {
      client.navigate(client.url);
    }
  }
  if (mine.length === 0) {
    await self.registration.unregister();
  }
}
