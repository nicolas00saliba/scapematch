'use strict';

// Leva https://demo.escapematch.com.br/parceiro/… para o host próprio,
// com path, query e hash. index.html e 404.html não são rota do app.
var PARTNER_DEMO_ORIGIN = 'https://parceiro-demo.escapematch.com.br';

function partnerDemoRedirectTarget(pageUrl) {
  var current = new URL(pageUrl);
  var marker = '/parceiro';
  var path = current.pathname;
  var at = path.indexOf(marker);
  var rest = '/';
  if (at >= 0) {
    var tail = path.slice(at + marker.length);
    if (
      tail === '' ||
      tail === '/' ||
      tail === '/index.html' ||
      tail === '/404.html'
    ) {
      rest = '/';
    } else if (tail.charAt(0) === '/') {
      rest = tail;
    }
  }
  return PARTNER_DEMO_ORIGIN + rest + current.search + current.hash;
}

function leave(dest) {
  try {
    if (window.top && window.top !== window.self) {
      window.top.location.replace(dest);
      return;
    }
  } catch (error) {
    // Pai de outra origem: segue neste quadro.
  }
  location.replace(dest);
}

function boot() {
  var dest = partnerDemoRedirectTarget(location.href);
  var link = document.getElementById('parceiro-demo-link');
  if (link) link.setAttribute('href', dest);
  var go = function () {
    leave(dest);
  };
  if (!('serviceWorker' in navigator)) {
    go();
    return;
  }
  navigator.serviceWorker.getRegistrations().then(function (regs) {
    return Promise.all(regs.map(function (reg) {
      if (reg.scope.indexOf('/parceiro/') !== -1) return reg.unregister();
    }));
  }).then(go, go);
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  boot();
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { partnerDemoRedirectTarget: partnerDemoRedirectTarget };
}
