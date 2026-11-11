(function () {
  var bloco = document.querySelector("[data-codigo]");
  if (!bloco) return;
  var params = new URLSearchParams(location.search);
  var codigo = (params.get("codigo") || "").trim().toUpperCase();
  if (!/^[A-Z0-9]{8}$/.test(codigo)) return;
  bloco.hidden = false;
  var valor = bloco.querySelector("[data-codigo-valor]");
  if (valor) valor.textContent = codigo;
  var botao = bloco.querySelector("[data-copiar]");
  var aviso = bloco.querySelector("[data-codigo-aviso]");
  if (!botao) return;
  botao.addEventListener("click", function () {
    function ok() {
      if (aviso) aviso.textContent = "Código copiado.";
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(codigo).then(ok).catch(function () {
        if (aviso) aviso.textContent = "Selecione o código e copie.";
      });
      return;
    }
    if (aviso) aviso.textContent = "Selecione o código e copie.";
  });
})();
