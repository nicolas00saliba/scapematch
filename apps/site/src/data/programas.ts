export const regrasVersao = '2026-11-24';

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
      'Uma vez por conta. Só esses pontos dão desconto. Uma barra no app mostra quanto falta para usar.',
    seoTitulo: 'Vantagens e pontos | EscapeMatch',
    seoDescricao:
      'Ganhe pontos ao criar a conta, em toda reserva e indicando amigos. Use os pontos na próxima sala.',
    og: '/assets/og/vantagens.png',
    cta: {
      rotulo: 'Criar conta e ganhar 100 pontos',
      href: 'https://app.escapematch.com.br/',
      externo: true,
    },
  },
  {
    id: 'pontos-de-volta',
    rota: '/vantagens',
    publico: 'jogador',
    icone: 'moeda',
    titulo: 'Pontos de volta',
    beneficio: 'Até 5% em pontos',
    apoio: 'Cashback de até 5% em pontos a cada jogo.',
    passos: ['Reserve', 'Pague sua vaga', 'Ganhe pontos'],
    regras:
      'Vale em toda reserva paga. Esses pontos se somam aos de indicação e pagam a vaga inteira. O sorteio e as faixas estão no regulamento.',
    seoTitulo: 'Vantagens e pontos | EscapeMatch',
    seoDescricao:
      'Ganhe pontos ao criar a conta, em toda reserva e indicando amigos. Use os pontos na próxima sala.',
    og: '/assets/og/vantagens.png',
    cta: {
      rotulo: 'Criar conta e ganhar 100 pontos',
      href: 'https://app.escapematch.com.br/',
      externo: true,
    },
  },
  {
    id: 'indique-amigos',
    rota: '/vantagens/indique-amigos',
    publico: 'jogador',
    icone: 'pessoas',
    titulo: 'Indique amigos',
    beneficio: '20% de desconto para ele, pontos para você',
    apoio:
      'Seu amigo ganha 20% de desconto na primeira reserva. Você ganha 1% em pontos desde o primeiro indicado ativo, 2,5% a partir de 5 e 5% a partir de 8, por 1 ano.',
    passos: ['Mande seu código', 'Amigo entra e joga', 'Vocês ganham'],
    regras:
      'O amigo usa o seu código no cadastro. Conta da mesma pessoa não vale: mesmo CPF, telefone ou cartão.',
    seoTitulo: 'Indique amigos e ganhe pontos | EscapeMatch',
    seoDescricao:
      'Seu amigo ganha desconto na primeira reserva e você ganha pontos sempre que ele jogar, por 1 ano.',
    og: '/assets/og/indique-amigos.png',
    cta: {
      rotulo: 'Pegar meu código no app',
      href: 'https://app.escapematch.com.br/',
      externo: true,
    },
  },
  {
    id: 'indique-uma-casa',
    rota: '/vantagens/indique-uma-casa',
    publico: 'jogador',
    icone: 'casa',
    titulo: 'Indique uma casa',
    beneficio: '5% em pontos',
    apoio: 'Do que a casa indicada vender pelo app, por 1 ano.',
    passos: ['Indique a casa', 'A casa entra', 'Você ganha'],
    regras:
      'A casa usa o seu código no cadastro. Dono ou sócio não indica a própria casa.',
    seoTitulo: 'Indique uma casa e ganhe pontos | EscapeMatch',
    seoDescricao:
      'Conhece uma casa de jogos? Indique e ganhe pontos sobre o que ela vender pelo app, por 1 ano.',
    og: '/assets/og/indique-uma-casa.png',
    cta: {
      rotulo: 'Pegar meu código no app',
      href: 'https://app.escapematch.com.br/',
      externo: true,
    },
  },
  {
    id: 'niveis',
    rota: '/vantagens/niveis',
    publico: 'jogador',
    icone: 'niveis',
    titulo: 'Níveis de indicação',
    beneficio: '1%, 2,5% e 5%',
    apoio:
      '1% desde o primeiro indicado ativo, 2,5% a partir de 5 e 5% a partir de 8. Sem indicado ativo, a taxa é zero.',
    passos: ['Indique', 'Eles jogam', 'Você sobe'],
    regras:
      'Ativo é quem tem atribuição ativa e pagou uma reserva nos últimos 90 dias. Os níveis valem só para jogador que indica jogador. Casa indicada e casa que indica ficam em 5%, sem nível.',
    seoTitulo: 'Níveis para jogar de graça | EscapeMatch',
    seoDescricao:
      '1% desde o primeiro indicado ativo. 100 pontos valem R$ 1.',
    og: '/assets/og/niveis.png',
    cta: {
      rotulo: 'Ver meu nível no app',
      href: 'https://app.escapematch.com.br/',
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
    beneficio: '5% em crédito',
    apoio:
      'Do que o seu cliente pagar em outras casas, por 1 ano. Ele ganha 20% de desconto na primeira reserva.',
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
    beneficio: 'Sem pontos em dobro',
    apoio: 'Horário vazio não dobra cashback nem indicação, em nenhum programa.',
    passos: ['Sem faixa extra', 'O ponto não dobra', 'A casa não paga o dobro'],
    regras:
      'Desde 24/11/2026 nenhuma faixa de horário dobra pontos ou cashback. A casa não marca horário para isso e nada extra sai do repasse por causa do horário.',
    seoTitulo: 'Horário vazio não dobra pontos | EscapeMatch',
    seoDescricao:
      'Horário vazio não dobra cashback nem indicação. A casa não paga um extra por causa do horário.',
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

export const regrasVagaGratis = [
  'Dá para pagar em dinheiro, em pontos ou nos dois. Não há mínimo de pontos nem teto de 30%.',
  'Se a reserva for cancelada, os pontos usados são devolvidos.',
];

export const regrasJogador = [
  '100 pontos valem R$ 1. Não viram dinheiro para saque. Pontos de indicação e de cashback podem cobrir a vaga quando a reserva de pontos cobre a casa. Pontos de boas-vindas abatem até a comissão.',
  'Os pontos ganhos ficam disponíveis 30 dias depois do pagamento.',
  'O código de quem indicou entra no cadastro ou nas primeiras 24 horas. Uma indicação vale por 1 ano.',
  'Se a reserva for cancelada, os pontos ganhos nela também saem da conta.',
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
  'O cashback é sorteado a cada reserva paga, sobre o valor pago. As faixas são 0,5% (70% das vezes), 1% (17%), 2% (9%) e 5% (4%). A média desta tabela é 0,9%. Horário vazio não dobra o resultado.';
