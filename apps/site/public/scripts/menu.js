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

  function closeDetails(except) {
    var abertos = menu.querySelectorAll("details[open]");
    for (var i = 0; i < abertos.length; i += 1) {
      if (abertos[i] !== except) abertos[i].open = false;
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
        if (details.open) closeDetails(details);
      });
      details.addEventListener("mouseenter", function () {
        if (!desktop() || !window.matchMedia("(hover: hover)").matches) return;
        details.open = true;
      });
      details.addEventListener("mouseleave", function () {
        if (!desktop()) return;
        if (details.contains(document.activeElement)) return;
        details.open = false;
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
        aberto.open = false;
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
})();
