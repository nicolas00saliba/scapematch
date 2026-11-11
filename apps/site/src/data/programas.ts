export const regrasVersao = '2026-11-11';

export const comissaoPadrao = {
  percentual: 25,
  exemploReais: 100,
  nota: 'Casas podem ter condição combinada.',
} as const;

export type Icone =
  | 'presente'
  | 'moeda'
  | 'pessoas'
  | 'casa'
  | 'niveis'
  | 'relogio';

export type Programa = {
  id: string;
  rota: string;
  publico: 'jogador' | 'casa';
  icone: Icone;
  titulo: string;
  beneficio: string;
  apoio: string;
  passos: [string, string, string];
  regras: string;
  seoTitulo: string;
  seoDescricao: string;
  og: string;
  cta: { rotulo: string; href: string; externo?: boolean };
};

export const programas: Programa[] = [
  {
    id: 'boas-vindas',
    rota: '/vantagens',
    publico: 'jogador',
    icone: 'presente',
    titulo: 'Boas-vindas',
    beneficio: '100 pontos',
    apoio: 'Só por criar a sua conta.',
    passos: ['Crie a conta', 'Ganhe 100 pontos', 'Junte e use'],
    regras:
      'Uma vez por conta. Os pontos podem ser usados quando o saldo chegar a 1.000. Uma barra no app mostra quanto falta.',
    seoTitulo: 'Vantagens e pontos | EscapeMatch',
    seoDescricao:
      'Ganhe pontos ao criar a conta, em toda reserva e indicando amigos. Use os pontos na próxima sala.',
    og: '/assets/og/vantagens.png',
    cta: {
      rotulo: 'Criar conta e ganhar 100 pontos',
      href: 'https://app.escapematch.com.br/cadastro',
      externo: true,
    },
  },
  {
    id: 'pontos-de-volta',
    rota: '/vantagens',
    publico: 'jogador',
    icone: 'moeda',
    titulo: 'Pontos de volta',
    beneficio: 'Pontos em toda reserva',
    apoio: 'De 50 a 500 pontos a cada R$ 100, por sorteio. Em horário vazio, em dobro.',
    passos: ['Reserve', 'Pague sua vaga', 'Ganhe pontos'],
    regras:
      'O sorteio acontece no pagamento de cada reserva. Vale em toda reserva paga, com ou sem indicação.',
    seoTitulo: 'Vantagens e pontos | EscapeMatch',
    seoDescricao:
      'Ganhe pontos ao criar a conta, em toda reserva e indicando amigos. Use os pontos na próxima sala.',
    og: '/assets/og/vantagens.png',
    cta: {
      rotulo: 'Criar conta e ganhar 100 pontos',
      href: 'https://app.escapematch.com.br/cadastro',
      externo: true,
    },
  },
  {
    id: 'indique-amigos',
    rota: '/vantagens/indique-amigos',
    publico: 'jogador',
    icone: 'pessoas',
    titulo: 'Indique amigos',
    beneficio: '20% para ele, pontos para você',
    apoio:
      'Seu amigo ganha 20% na primeira reserva. Você ganha 250 pontos a cada R$ 100 que ele pagar, por 1 ano.',
    passos: ['Mande seu código', 'Amigo entra e joga', 'Vocês ganham'],
    regras:
      'O amigo usa o seu código no cadastro. Conta da mesma pessoa não vale: mesmo CPF, telefone ou cartão.',
    seoTitulo: 'Indique amigos e ganhe pontos | EscapeMatch',
    seoDescricao:
      'Seu amigo ganha desconto na primeira reserva e você ganha pontos sempre que ele jogar, por 1 ano.',
    og: '/assets/og/indique-amigos.png',
    cta: {
      rotulo: 'Pegar meu código no app',
      href: 'https://app.escapematch.com.br/login',
      externo: true,
    },
  },
  {
    id: 'indique-uma-casa',
    rota: '/vantagens/indique-uma-casa',
    publico: 'jogador',
    icone: 'casa',
    titulo: 'Indique uma casa',
    beneficio: '250 pontos a cada R$ 100',
    apoio: 'Que a casa indicada vender pelo app, por 1 ano.',
    passos: ['Indique a casa', 'A casa entra', 'Você ganha'],
    regras:
      'A casa usa o seu código no cadastro. Dono ou sócio não indica a própria casa.',
    seoTitulo: 'Indique uma casa e ganhe pontos | EscapeMatch',
    seoDescricao:
      'Conhece uma casa de jogos? Indique e ganhe pontos sobre o que ela vender pelo app, por 1 ano.',
    og: '/assets/og/indique-uma-casa.png',
    cta: {
      rotulo: 'Pegar meu código no app',
      href: 'https://app.escapematch.com.br/login',
      externo: true,
    },
  },
  {
    id: 'niveis',
    rota: '/vantagens/niveis',
    publico: 'jogador',
    icone: 'niveis',
    titulo: 'Bronze, Prata e Ouro',
    beneficio: 'Indique mais, ganhe mais',
    apoio:
      'Prata com 5 indicados jogando: +50 pontos a cada R$ 100 que eles pagarem. Ouro com 15: +100.',
    passos: ['Indique', 'Eles jogam', 'Você sobe'],
    regras:
      'Conta como jogando quem pagou uma reserva nos últimos 90 dias. O extra vale para amigos e casas indicados.',
    seoTitulo: 'Níveis Bronze, Prata e Ouro | EscapeMatch',
    seoDescricao:
      'Quanto mais amigos jogando, mais pontos você ganha em cada indicação.',
    og: '/assets/og/niveis.png',
    cta: {
      rotulo: 'Ver meu nível no app',
      href: 'https://app.escapematch.com.br/login',
      externo: true,
    },
  },
  {
    id: 'casa-indique-casa',
    rota: '/para-casas/indique-uma-casa',
    publico: 'casa',
    icone: 'casa',
    titulo: 'Indique uma casa',
    beneficio: '5% em crédito',
    apoio:
      'De tudo que a casa indicada vender pelo app, por 1 ano. Seus clientes ganham 20% na primeira visita a ela.',
    passos: ['Mande seu código', 'A casa entra', 'Vocês ganham'],
    regras:
      'A reserva que teve os 20% de desconto não gera crédito. O crédito sai da comissão do EscapeMatch, não da casa indicada. Dono ou sócio não indica a própria casa.',
    seoTitulo: 'Indique uma casa parceira | EscapeMatch',
    seoDescricao:
      'Indique outra casa e ganhe crédito sobre o que ela vender pelo app, por 1 ano.',
    og: '/assets/og/casa-indique-uma-casa.png',
    cta: {
      rotulo: 'Pegar meu código no Parceiro',
      href: 'https://parceiro.escapematch.com.br/',
      externo: true,
    },
  },
  {
    id: 'casa-indique-jogadores',
    rota: '/para-casas/indique-jogadores',
    publico: 'casa',
    icone: 'pessoas',
    titulo: 'Indique jogadores',
    beneficio: '2,5% em crédito',
    apoio:
      'Do que o seu cliente pagar em outras casas, por 1 ano. Ele ganha 20% na primeira reserva.',
    passos: ['Mostre seu código', 'Cliente entra', 'Vocês ganham'],
    regras:
      'Reservas na sua própria casa não geram crédito. O cliente usa o seu código no cadastro.',
    seoTitulo: 'Indique jogadores | EscapeMatch',
    seoDescricao:
      'Seus clientes ganham desconto e você ganha crédito quando eles jogam em outras casas.',
    og: '/assets/og/indique-jogadores.png',
    cta: {
      rotulo: 'Pegar meu código no Parceiro',
      href: 'https://parceiro.escapematch.com.br/',
      externo: true,
    },
  },
  {
    id: 'horario-vazio',
    rota: '/para-casas/horario-vazio',
    publico: 'casa',
    icone: 'relogio',
    titulo: 'Horário vazio',
    beneficio: 'Pontos em dobro',
    apoio: 'Para quem reservar nos horários que você marcar como vazios.',
    passos: ['Marque o horário', 'Jogador vê o dobro', 'Horário enche'],
    regras:
      'Você marca os horários no Parceiro. O custo do dobro é dividido: metade fica com a casa e metade com o EscapeMatch.',
    seoTitulo: 'Encha seus horários vazios | EscapeMatch',
    seoDescricao:
      'Marque horários vazios e o jogador ganha pontos em dobro para reservar neles.',
    og: '/assets/og/horario-vazio.png',
    cta: {
      rotulo: 'Marcar no Parceiro',
      href: 'https://parceiro.escapematch.com.br/',
      externo: true,
    },
  },
];

export const programasJogador = programas.filter((item) => item.publico === 'jogador');
export const programasCasa = programas.filter((item) => item.publico === 'casa');

export function programaPorId(id: string): Programa {
  const achado = programas.find((item) => item.id === id);
  if (!achado) throw new Error(`programa ausente: ${id}`);
  return achado;
}

export const regrasJogador = [
  '1 ponto vale R$ 0,01. Os pontos não vencem e não viram dinheiro: servem para pagar salas.',
  'Os pontos ganhos ficam disponíveis 30 dias depois do pagamento.',
  'Dá para usar a partir de 1.000 pontos, pagando até 30% de uma reserva.',
  'O código de quem indicou entra no cadastro ou nas primeiras 24 horas. Uma indicação vale por 1 ano.',
  'Se a reserva for cancelada ou estornada, os pontos dela saem da conta.',
];

export const regrasCasa = [
  'O crédito fica 30 dias pendente e depois entra no repasse das suas próximas reservas pelo app.',
  'Uma indicação vale por 1 ano a partir do cadastro de quem foi indicado.',
  'Se a reserva for cancelada ou estornada, o crédito dela é desfeito.',
];

export const regrasFraude = [
  {
    titulo: 'Contas da mesma pessoa',
    texto:
      'Mesmo CPF, mesmo telefone ou mesmo cartão entre quem indica e quem foi indicado não geram indicação.',
  },
  {
    titulo: 'Quem paga',
    texto:
      'Se quem paga é o próprio indicador, aquela indicação não vale. Um mesmo pagador gera prêmio para no máximo 3 contas indicadas.',
  },
  {
    titulo: 'Mesmo aparelho',
    texto:
      'Contas criadas no mesmo aparelho pelo mesmo indicador passam por revisão antes de liberar os pontos.',
  },
];

export const sorteioPontos =
  'O sorteio usa quatro faixas: 50, 100, 200 e 500 pontos a cada R$ 100. A média fica em até 100 pontos a cada R$ 100. Em horário vazio, o resultado vale em dobro.';
