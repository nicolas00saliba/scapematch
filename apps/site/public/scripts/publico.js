(function () {
  var root = document.querySelector("[data-publico]");
  if (!root) return;
  var tabs = Array.prototype.slice.call(root.querySelectorAll('[role="tab"]'));
  var panels = Array.prototype.slice.call(root.querySelectorAll('[role="tabpanel"]'));
  var chave = "em_publico";

  function select(id, save) {
    for (var i = 0; i < tabs.length; i += 1) {
      var on = tabs[i].getAttribute("aria-controls") === id;
      tabs[i].setAttribute("aria-selected", on ? "true" : "false");
      tabs[i].tabIndex = on ? 0 : -1;
    }
    for (var j = 0; j < panels.length; j += 1) {
      panels[j].hidden = panels[j].id !== id;
    }
    if (save) {
      try {
        localStorage.setItem(chave, id);
      } catch (e) {}
    }
  }

  var inicial = "painel-jogar";
  try {
    var salvo = localStorage.getItem(chave);
    if (salvo && document.getElementById(salvo)) inicial = salvo;
  } catch (e) {}

  root.classList.add("is-ready");
  select(inicial, false);

  tabs.forEach(function (tab, index) {
    tab.addEventListener("click", function () {
      select(tab.getAttribute("aria-controls"), true);
    });
    tab.addEventListener("keydown", function (event) {
      var next = null;
      if (event.key === "ArrowRight" || event.key === "ArrowDown") {
        next = tabs[(index + 1) % tabs.length];
      }
      if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
        next = tabs[(index - 1 + tabs.length) % tabs.length];
      }
      if (event.key === "Home") next = tabs[0];
      if (event.key === "End") next = tabs[tabs.length - 1];
      if (!next) return;
      event.preventDefault();
      next.focus();
      select(next.getAttribute("aria-controls"), true);
    });
  });
})();
