(function () {
  var rotas = {
    "#casas": "/para-casas",
    "#como-funciona": "/como-funciona",
    "#perguntas": "/ajuda",
    "#contato": "/contato",
    "#topo": "/",
  };
  var destino = rotas[location.hash];
  if (destino) location.replace(destino);
})();
