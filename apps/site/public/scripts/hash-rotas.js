(function () {
  var rotas = {
    "#casas": "/para-casas",
    "#como-funciona": "/como-funciona",
    "#perguntas": "/ajuda",
    "#topo": "/",
  };
  var destino = rotas[location.hash];
  if (destino) location.replace(destino);
})();
