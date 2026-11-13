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
  | 'relogio'
  | 'carimbo'
  | 'estrela';

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
      'Seu amigo ganha 20% na primeira reserva. Você ganha 2,5% em pontos de cada reserva dele, por 1 ano.',
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
    beneficio: '2,5% em pontos',
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
      'Quem mais indica, mais joga de graça. A base é 2,5% em pontos. Prata soma 0,5%. Ouro soma 1%.',
    passos: ['Indique', 'Eles jogam', 'Você sobe'],
    regras:
      'Conta como jogando quem pagou uma reserva nos últimos 90 dias. O extra vale para amigos e casas indicados.',
    seoTitulo: 'Níveis para jogar de graça | EscapeMatch',
    seoDescricao:
      'Quem mais indica, mais joga de graça. A base é 2,5% em pontos. 1 ponto vale R$ 0,01.',
    og: '/assets/og/niveis.png',
    cta: {
      rotulo: 'Ver meu nível no app',
      href: 'https://app.escapematch.com.br/login',
      externo: true,
    },
  },
  {
    id: 'passaporte',
    rota: '/vantagens/passaporte',
    publico: 'jogador',
    icone: 'carimbo',
    titulo: 'Passaporte de salas',
    beneficio: 'Um carimbo por sala',
    apoio: 'Cada sala confirmada pela casa ganha um carimbo. Nos marcos, entram pontos bônus.',
    passos: ['Jogue a sala', 'A casa confirma', 'Feche os marcos'],
    regras:
      'O carimbo entra quando a casa confirma o comparecimento da reserva paga, a partir do horário da sessão. Sem essa confirmação não há carimbo. Jogar de novo conta a visita, sem um segundo carimbo. Os pontos do marco são desconto, até o teto, e não pagam a vaga inteira. Se a reserva for estornada, o carimbo sai. Enquanto o passaporte estiver desligado, não há carimbo.',
    seoTitulo: 'Passaporte de salas | EscapeMatch',
    seoDescricao:
      'Um carimbo para cada sala que você joga e pontos bônus nos marcos. O carimbo não se repete.',
    og: '/assets/og/vantagens.png',
    cta: {
      rotulo: 'Ver o passaporte no app',
      href: 'https://app.escapematch.com.br/login',
      externo: true,
    },
  },
  {
    id: 'avaliacoes',
    rota: '/vantagens/avaliacoes',
    publico: 'jogador',
    icone: 'estrela',
    titulo: 'Avalie a sala',
    beneficio: 'Um toque por item',
    apoio:
      'História, enigmas, cenário, atendimento, limpeza e custo-benefício. As melhores casas aparecem nos rankings.',
    passos: ['Termine o jogo', 'Toque em cada item', 'Veja os rankings'],
    regras:
      'Avaliar é rápido: um toque por item. Os itens são História, Enigmas, Cenário e imersão, Atendimento, Limpeza e conforto e Custo-benefício. Os rankings de cidade, país e mundo reúnem as casas mais bem avaliadas. Sem avaliação de verdade, não há nota.',
    seoTitulo: 'Avalie a sala em um toque | EscapeMatch',
    seoDescricao:
      'Depois do jogo, um toque por item. Os rankings mostram as casas mais bem avaliadas na cidade, no país e no mundo.',
    og: '/assets/og/vantagens.png',
    cta: {
      rotulo: 'Avaliar no app',
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
  {
    id: 'avaliacoes-casa',
    rota: '/para-casas/avaliacoes',
    publico: 'casa',
    icone: 'estrela',
    titulo: 'Avaliações e insights',
    beneficio: 'Nota por categoria',
    apoio:
      'O que a cidade acha da sua casa, em tempo real, e os rankings de cidade, país e mundo.',
    passos: ['Jogador avalia', 'Você vê os pontos', 'Compare com a cidade'],
    regras:
      'As categorias são História, Enigmas, Cenário e imersão, Atendimento, Limpeza e conforto e Custo-benefício. O painel mostra pontos fortes e fracos em relação à cidade. A nota só existe quando há avaliações recebidas.',
    seoTitulo: 'Avaliações e insights da casa | EscapeMatch',
    seoDescricao:
      'Nota por categoria e comparação com a cidade, em tempo real. Rankings de cidade, país e mundo, sem número inventado.',
    og: '/assets/og/para-casas.png',
    cta: {
      rotulo: 'Ver no Parceiro',
      href: 'https://parceiro.escapematch.com.br/',
      externo: true,
    },
  },
  {
    id: 'mimos',
    rota: '/para-casas/mimos',
    publico: 'casa',
    icone: 'presente',
    titulo: 'Mimos do passaporte',
    beneficio: 'Opcional, por sua conta',
    apoio: 'Um brinde, uma foto ou um desconto seu, para o cliente voltar.',
    passos: ['Cadastre o mimo', 'Jogador ganha o código', 'Você marca a entrega'],
    regras:
      'Nada é obrigatório. Você liga e desliga no Parceiro. O mimo pode valer ao carimbar uma sala ou ao fechar a casa. O custo é da casa.',
    seoTitulo: 'Mimos do passaporte | EscapeMatch',
    seoDescricao:
      'A casa cadastra um mimo opcional no passaporte. O jogador mostra o código e a casa marca a entrega.',
    og: '/assets/og/para-casas.png',
    cta: {
      rotulo: 'Cadastrar no Parceiro',
      href: 'https://parceiro.escapematch.com.br/',
      externo: true,
    },
  },
  {
    id: 'passaporte-casa',
    rota: '/para-casas/passaporte',
    publico: 'casa',
    icone: 'carimbo',
    titulo: 'Passaporte de salas',
    beneficio: 'O jogador volta',
    apoio: 'Quem começou a carimbar tende a voltar até fechar todas as salas da casa.',
    passos: ['Ele joga a sala', 'A casa confirma', 'Ele volta pelas outras'],
    regras:
      'A casa confirma o comparecimento no Parceiro, a partir do horário da sessão. O carimbo e os pontos são do EscapeMatch. Fechar a casa, quando ela tem mais de uma sala, rende pontos de desconto para o jogador. A casa não paga esses pontos.',
    seoTitulo: 'O passaporte traz o jogador de volta | EscapeMatch',
    seoDescricao:
      'Cada sala jogada vira um carimbo. O jogador tem motivo para voltar até fechar a casa.',
    og: '/assets/og/para-casas.png',
    cta: {
      rotulo: 'Abrir o Parceiro',
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
  'Dá para usar a partir de 1.000 pontos.',
  'Se a reserva for cancelada, os pontos usados são devolvidos.',
];

export const regrasJogador = [
  '1 ponto vale R$ 0,01. Cashback e indicação se somam e pagam a vaga inteira. Boas-vindas e passaporte dão desconto, até o teto. Não viram dinheiro para saque.',
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
  'O cashback é sorteado a cada reserva paga, sobre o valor pago. As faixas são 0,5% (70% das vezes), 1% (17%), 2% (9%) e 5% (4%). A média desta tabela é 0,9%. Em horário vazio, o resultado vale em dobro.';
