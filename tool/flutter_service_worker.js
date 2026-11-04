'use strict';

// Substitui o service worker de cache do Flutter.
// O build usa --pwa-strategy=none, então uma visita nova não registra
// worker. Quem ainda tem o worker antigo baixa este arquivo na próxima
// atualização: ele apaga os caches, recarrega as abas pela rede e se remove.
self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(clearCachesAndReload());
});

// Não intercepta o próprio script: o navegador precisa compará-lo na rede.
// O resto, enquanto este worker ainda controla a página, ignora o cache HTTP.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') {
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

async function clearCachesAndReload() {
  await self.clients.claim();
  const keys = await caches.keys();
  await Promise.all(keys.map((key) => caches.delete(key)));
  const windows = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });
  // Não espera a navegação terminar. A página nova pode esperar este
  // activate, e esperar os dois lados trava o carregamento.
  for (const client of windows) {
    if (client.url && typeof client.navigate === 'function') {
      client.navigate(client.url);
    }
  }
  if (windows.length === 0) {
    await self.registration.unregister();
  }
}
