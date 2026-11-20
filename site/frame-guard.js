// Esconde a landing quando outra origem coloca a página num iframe.
// O GitHub Pages não envia X-Frame-Options nem frame-ancestors.
// Sem script a página continua visível: o HTML estático não depende de JS.
(function () {
  if (window.top === window.self) return;
  document.documentElement.setAttribute("hidden", "");
  try {
    window.top.location = window.self.location;
  } catch (e) {}
})();
