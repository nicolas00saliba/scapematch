(function () {
  var root = document.documentElement;
  root.classList.add("js");
  var header = document.querySelector("[data-topo]");
  var button = document.querySelector("[data-menu-botao]");
  var menu = document.querySelector("[data-menu]");
  if (!header || !button || !menu) return;

  function desktop() {
    return window.matchMedia("(min-width: 1080px)").matches;
  }

  var fechos = new WeakMap();
  var ATRASO_FECHO = 200;

  function cancelarFecho(details) {
    var id = fechos.get(details);
    if (id) clearTimeout(id);
    fechos.delete(details);
  }

  function agendarFecho(details) {
    cancelarFecho(details);
    fechos.set(details, setTimeout(function () {
      fechos.delete(details);
      if (details.contains(document.activeElement)) return;
      details.open = false;
    }, ATRASO_FECHO));
  }

  function fechar(details) {
    cancelarFecho(details);
    details.open = false;
  }

  function alinharPainel(details) {
    var painel = details.querySelector(".mega");
    if (!painel || !desktop()) return;
    painel.classList.remove("mega-direita");
    painel.style.transform = "";
    var margem = 12;
    var limite = window.innerWidth - margem;
    var rect = painel.getBoundingClientRect();
    if (rect.right > limite) {
      painel.classList.add("mega-direita");
      rect = painel.getBoundingClientRect();
    }
    var shift = 0;
    if (rect.left < margem) shift = margem - rect.left;
    else if (rect.right > limite) shift = limite - rect.right;
    if (shift) painel.style.transform = "translateX(" + Math.round(shift) + "px)";
  }

  function closeDetails(except) {
    var abertos = menu.querySelectorAll("details[open]");
    for (var i = 0; i < abertos.length; i += 1) {
      if (abertos[i] !== except) fechar(abertos[i]);
    }
  }

  function closeMenu() {
    root.classList.remove("is-menu-open");
    button.setAttribute("aria-expanded", "false");
    closeDetails(null);
  }

  button.addEventListener("click", function () {
    var open = !root.classList.contains("is-menu-open");
    root.classList.toggle("is-menu-open", open);
    button.setAttribute("aria-expanded", open ? "true" : "false");
    if (!open) closeDetails(null);
  });

  var detalhes = menu.querySelectorAll("details");
  for (var i = 0; i < detalhes.length; i += 1) {
    (function (details) {
      var summary = details.querySelector("summary");
      summary.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " " || event.key === "ArrowDown") {
          details.setAttribute("data-trap", "teclado");
        }
      });
      summary.addEventListener("pointerdown", function () {
        details.setAttribute("data-trap", "");
      });
      details.addEventListener("toggle", function () {
        if (!details.open) return;
        closeDetails(details);
        alinharPainel(details);
      });
      var suprimirFecho = false;
      details.addEventListener("mouseenter", function () {
        if (!desktop() || !window.matchMedia("(hover: hover)").matches) return;
        cancelarFecho(details);
        var estavaAberto = details.open;
        details.open = true;
        alinharPainel(details);
        if (!estavaAberto) {
          suprimirFecho = true;
          setTimeout(function () { suprimirFecho = false; }, 0);
        }
      });
      summary.addEventListener("click", function (event) {
        if (!desktop() || !window.matchMedia("(hover: hover)").matches) return;
        if (!event.detail) return;
        event.preventDefault();
        if (suprimirFecho) {
          suprimirFecho = false;
          details.open = true;
          return;
        }
        if (details.open) fechar(details);
        else details.open = true;
      });
      details.addEventListener("mouseleave", function () {
        if (!desktop()) return;
        if (details.contains(document.activeElement)) return;
        agendarFecho(details);
      });
    })(detalhes[i]);
  }

  document.addEventListener("click", function (event) {
    if (!header.contains(event.target)) closeDetails(null);
  });

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
      var aberto = menu.querySelector("details[open]");
      if (aberto) {
        var summary = aberto.querySelector("summary");
        fechar(aberto);
        if (summary) summary.focus();
        return;
      }
      if (root.classList.contains("is-menu-open")) {
        closeMenu();
        button.focus();
      }
      return;
    }
    if (event.key !== "Tab") return;
    var trap = null;
    var teclado = menu.querySelector('details[open][data-trap="teclado"]');
    if (teclado) trap = teclado;
    else if (!desktop() && root.classList.contains("is-menu-open")) trap = menu;
    if (!trap) return;
    var itens = trap.querySelectorAll("a[href], button, summary");
    if (!itens.length) return;
    var primeiro = itens[0];
    var ultimo = itens[itens.length - 1];
    if (event.shiftKey && document.activeElement === primeiro) {
      event.preventDefault();
      ultimo.focus();
    } else if (!event.shiftKey && document.activeElement === ultimo) {
      event.preventDefault();
      primeiro.focus();
    }
  });

  function onScroll() {
    header.classList.toggle("is-scrolled", window.scrollY > 2);
  }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", function () {
    var abertos = menu.querySelectorAll("details[open]");
    for (var i = 0; i < abertos.length; i += 1) alinharPainel(abertos[i]);
  });
})();
