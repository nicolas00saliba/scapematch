// Confere se esta aba ainda roda a versão publicada. Vale para o jogador, o
// Parceiro e o Admin. stamp_web_build.sh injeta este arquivo no index.html.
// Sem service worker, um app aberto há horas continuaria com o bundle antigo:
// o Flutter web é uma página só e não recarrega sozinho.
(function () {
  var meta = document.querySelector('meta[name="scapematch-build"]');
  var current = meta && meta.getAttribute('content');
  if (!current || current === 'dev' || !window.fetch) return;
  var MIN_GAP_MS = 60 * 1000;
  var EVERY_MS = 10 * 60 * 1000;
  var last = 0;
  var busy = false;
  var pending = false;

  function typing() {
    var el = document.activeElement;
    if (!el) return false;
    var tag = (el.tagName || '').toLowerCase();
    return tag === 'input' || tag === 'textarea' || el.isContentEditable === true;
  }

  function reload(next) {
    try {
      // Uma recarga por versão. Se a rede devolver um index velho, não entra em laço.
      if (sessionStorage.getItem('scape-build-reload') === next) return;
      sessionStorage.setItem('scape-build-reload', next);
    } catch (e) {}
    window.location.reload();
  }

  function check(force) {
    var now = Date.now();
    if (busy || (!force && now - last < MIN_GAP_MS)) return;
    busy = true;
    last = now;
    fetch(new URL('./', document.baseURI).href, {
      cache: 'no-store',
      credentials: 'omit',
      headers: {Accept: 'text/html'}
    }).then(function (res) {
      return res.ok ? res.text() : '';
    }).then(function (html) {
      var found = /<meta[^>]+name="scapematch-build"[^>]+content="([^"]+)"/.exec(html);
      if (!found || found[1] === current) {
        pending = false;
        return;
      }
      // Não recarrega com um campo em foco: o teclado e o que a pessoa digitou ficam.
      if (typing()) {
        pending = found[1];
        return;
      }
      reload(found[1]);
    }).catch(function () {}).then(function () {
      busy = false;
    });
  }

  function visible() {
    if (document.visibilityState !== 'visible') return;
    if (pending && !typing()) {
      reload(pending);
      return;
    }
    check(false);
  }

  document.addEventListener('visibilitychange', visible);
  window.addEventListener('pageshow', function (event) {
    if (event.persisted) check(true);
  });
  window.addEventListener('online', function () { check(true); });
  window.addEventListener('focus', visible);
  setInterval(function () {
    if (document.visibilityState === 'visible') visible();
  }, EVERY_MS);
  // O index pode ter vindo do cache HTTP (até 10 min). Confere logo depois de abrir.
  setTimeout(function () { check(true); }, 4000);
})();
