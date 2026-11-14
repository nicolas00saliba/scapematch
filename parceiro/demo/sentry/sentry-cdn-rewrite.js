// O sentry_flutter 10.3.0 injeta o SDK JS a partir de
// browser.sentry-cdn.com/<versão>/bundle.tracing(.min).js e confere o
// SHA-384. A CSP só permite script de 'self'. Este gancho troca o
// endereço pelo arquivo em sentry/<versão>/, com os mesmos bytes, antes
// do navegador buscar. O init do Dart segue igual.
(function () {
  var cdn = 'https://browser.sentry-cdn.com/';
  var arquivo = /^[0-9]+\.[0-9]+\.[0-9]+\/[A-Za-z0-9._-]+$/;

  function localDe(url) {
    if (typeof url !== 'string') return null;
    var i = url.indexOf(cdn);
    if (i === -1) return null;
    var rest = url.slice(i + cdn.length);
    if (!arquivo.test(rest)) return null;
    return 'sentry/' + rest;
  }

  function redirecionar(node) {
    if (!node || node.tagName !== 'SCRIPT') return;
    var bruto = node.getAttribute('src') || '';
    var local = localDe(bruto);
    if (!local && typeof node.src === 'string') local = localDe(node.src);
    if (!local) return;
    node.setAttribute('src', local);
  }

  function enrolar(proto, nome) {
    var original = proto[nome];
    if (typeof original !== 'function') return;
    proto[nome] = function () {
      for (var i = 0; i < arguments.length; i++) redirecionar(arguments[i]);
      return original.apply(this, arguments);
    };
  }

  enrolar(Node.prototype, 'insertBefore');
  enrolar(Node.prototype, 'appendChild');
  if (typeof Element !== 'undefined') enrolar(Element.prototype, 'append');

  var desc = Object.getOwnPropertyDescriptor(HTMLScriptElement.prototype, 'src');
  if (desc && desc.set && desc.configurable) {
    Object.defineProperty(HTMLScriptElement.prototype, 'src', {
      configurable: true,
      enumerable: desc.enumerable,
      get: desc.get,
      set: function (value) {
        var local = localDe(String(value));
        return desc.set.call(this, local || value);
      },
    });
  }
})();
