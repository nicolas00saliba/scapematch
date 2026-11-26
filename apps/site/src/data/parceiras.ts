// Casas que fecharam parceria com a EscapeMatch, na ordem do carrossel da home.
// Os arquivos ficam em public/assets/parceiras/ (WebP + PNG de reserva).
//
// Cada logo é o original da própria casa, sem redesenho e sem ampliação:
// só foram cortadas as margens transparentes e a altura foi reduzida para
// no máximo 3x o tamanho exibido. A faixa do carrossel é escura (--noite)
// porque a Fábrica só publica a versão branca e cobre, feita para fundo escuro.
//
// largura e altura são as do arquivo gravado (proporção usada no layout).
export interface CasaParceira {
  id: string;
  nome: string;
  largura: number;
  altura: number;
  // Origem do arquivo, para quem for atualizar o logo.
  fonte: string;
}

export const casasParceiras: CasaParceira[] = [
  {
    id: 'ninja',
    nome: 'Ninja Escape Room',
    largura: 503,
    altura: 192,
    // Versão branca do logo completo (símbolo e nome) do site da casa, em PNG de
    // 1600 px sobre azul chapado. O azul foi tirado pelo canal vermelho (o logo é
    // branco puro, então o alpha sai exato). A versão azul e dourada some no escuro.
    fonte: 'https://ninjaescaperoom.com.br/wp-content/uploads/2023/02/LOGO-COM-FUNDO-5.png',
  },
  {
    id: 'puzzle',
    nome: 'Puzzle Room Escape Game',
    largura: 225,
    altura: 224,
    fonte: 'https://www.puzzleroom.com.br/wp-content/uploads/2019/09/Logo-Manual-PRB-final-20193x.png',
  },
  {
    id: 'synapse',
    nome: 'Synapse Escape Room',
    largura: 420,
    altura: 112,
    // Maior arquivo que o site da casa publica (logo@2x do cabeçalho, 430x159).
    fonte: 'https://synapseescaperoom.com.br/assets/img/logo@2x.png',
  },
  {
    id: 'fabrica',
    nome: 'Fábrica Escape Room',
    largura: 340,
    altura: 256,
    fonte: 'https://drive.google.com/uc?export=download&id=1cXuM0gUizWfikK7YI3f9ue-fgf8GEHxJ',
  },
  {
    id: 'minos',
    nome: 'Minos Escape Room',
    largura: 666,
    altura: 216,
    fonte: 'https://static.wixstatic.com/media/8d75bb_fea6786118d5421fb3589705c857facf~mv2.png',
  },
];
