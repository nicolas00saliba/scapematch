export type Pergunta = {
  pergunta: string;
  resposta: string;
};

export type Tema = {
  slug: string;
  nome: string;
  frase: string;
  seoTitulo: string;
  seoDescricao: string;
  perguntas: Pergunta[];
  relacionados: string[];
  saibaMais?: { rotulo: string; href: string };
};

export const temas: Tema[] = [
  {
    slug: 'grupo',
    nome: 'Grupo',
    frase: 'Como o time se forma e quando o jogo confirma.',
    seoTitulo: 'Grupo para quem está sozinho | EscapeMatch',
    seoDescricao: 'Dá para jogar escape room sozinho. O app te coloca num grupo e o jogo confirma no mínimo.',
    saibaMais: { rotulo: 'Guia: escape room sozinho', href: '/guia/escape-room-sozinho' },
    relacionados: ['pagamento', 'cancelamento'],
    perguntas: [
      {
        pergunta: 'Posso ir sozinho?',
        resposta:
          'Sim. Você escolhe a sala e o horário. O app te coloca num grupo com outros jogadores.',
      },
      {
        pergunta: 'Quando o jogo confirma?',
        resposta:
          'Quando o grupo bate o mínimo. A partir daí o jogo está confirmado e o grupo segue aberto até lotar.',
      },
      {
        pergunta: 'Quem chega depois do mínimo paga como?',
        resposta: 'Paga a própria vaga na hora, até o grupo lotar.',
      },
      {
        pergunta: 'Já tenho turma. Dá para usar o app?',
        resposta:
          'Dá. Você completa as vagas que faltam. Cada pessoa paga a própria vaga.',
      },
      {
        pergunta: 'E se o grupo não bater o mínimo?',
        resposta:
          'O jogo não confirma. Nada é cobrado: o Pix é estornado e o cartão não é capturado.',
      },
      {
        pergunta: 'Como achar gente para jogar escape room sozinho?',
        resposta:
          'Pelo app: escolha a sala e o horário e entre no grupo. O guia de escape room sozinho descreve o caminho.',
      },
    ],
  },
  {
    slug: 'pagamento',
    nome: 'Pagamento',
    frase: 'Quando cobra, quanto e por onde o pagamento passa.',
    seoTitulo: 'Pagamento: dúvidas frequentes | EscapeMatch',
    seoDescricao: 'Você paga só a sua vaga, por Pix ou cartão, quando o grupo confirma.',
    relacionados: ['grupo', 'cancelamento'],
    perguntas: [
      {
        pergunta: 'Eu pago a reserva inteira?',
        resposta: 'Não. O preço é por pessoa. Você paga só a sua vaga.',
      },
      {
        pergunta: 'Quais formas de pagamento existem?',
        resposta:
          'Pix e cartão, processados pela Asaas. O app não guarda o número do cartão.',
      },
      {
        pergunta: 'Quando a cobrança acontece?',
        resposta:
          'Quando o grupo bate o mínimo e o jogo confirma. Quem entra depois paga a própria vaga na hora.',
      },
      {
        pergunta: 'O app guarda o meu cartão?',
        resposta: 'Não. O app não guarda o número do cartão.',
      },
    ],
  },
  {
    slug: 'cancelamento',
    nome: 'Cancelamento',
    frase: 'O que acontece se você, o grupo ou a casa cancelar.',
    seoTitulo: 'Cancelamento: dúvidas frequentes | EscapeMatch',
    seoDescricao: 'Antes da confirmação nada é cobrado. Depois dela não há reembolso.',
    relacionados: ['pagamento', 'grupo'],
    perguntas: [
      {
        pergunta: 'E se o grupo não confirmar?',
        resposta:
          'Nada é cobrado. O Pix é estornado e o cartão não é capturado.',
      },
      {
        pergunta: 'Tem reembolso depois que o grupo confirma?',
        resposta: 'Não. Depois da confirmação não há reembolso.',
      },
      {
        pergunta: 'E se a casa cancelar?',
        resposta: 'O valor é devolvido integralmente.',
      },
    ],
  },
  {
    slug: 'conta',
    nome: 'Conta',
    frase: 'Cadastro, entrada e o código de quem te indicou.',
    seoTitulo: 'Conta: dúvidas frequentes | EscapeMatch',
    seoDescricao: 'Crie a conta no app e cole o código de indicação no cadastro ou nas primeiras 24 horas.',
    relacionados: ['pontos', 'grupo'],
    perguntas: [
      {
        pergunta: 'Onde crio a conta?',
        resposta: 'No app. A página Baixar o app explica como abrir no navegador e instalar no celular.',
      },
      {
        pergunta: 'Onde entra o código de quem me indicou?',
        resposta: 'No cadastro ou nas primeiras 24 horas.',
      },
      {
        pergunta: 'O desconto de 20% vale para quem já tem conta?',
        resposta: 'Não. O desconto da primeira reserva é só para conta nova.',
      },
    ],
  },
  {
    slug: 'pontos',
    nome: 'Pontos',
    frase: 'Como ganhar, quando liberam e como usar.',
    seoTitulo: 'Pontos para jogar de graça | EscapeMatch',
    seoDescricao: '1 ponto vale R$ 0,01. A indicação paga a vaga inteira. Boas-vindas e cashback dão desconto.',
    relacionados: ['conta', 'pagamento'],
    perguntas: [
      {
        pergunta: 'Quanto vale 1 ponto?',
        resposta:
          'R$ 0,01. Os pontos de indicação pagam a vaga inteira. Os de boas-vindas e de cashback dão desconto. Não viram dinheiro para saque.',
      },
      {
        pergunta: 'Quando os pontos liberam?',
        resposta: '30 dias depois do pagamento.',
      },
      {
        pergunta: 'A partir de quando dá para usar?',
        resposta:
          'A partir de 1.000 pontos. O limite mensal de vagas grátis é definido pela plataforma. Se a reserva for cancelada, os pontos usados são devolvidos.',
      },
      {
        pergunta: 'Quantos pontos eu ganho ao criar a conta?',
        resposta: '100 pontos, uma vez por conta.',
      },
    ],
  },
  {
    slug: 'casas',
    nome: 'Casas',
    frase: 'Para quem tem uma casa parceira ou quer ser.',
    seoTitulo: 'Casas: dúvidas frequentes | EscapeMatch',
    seoDescricao: 'Como a casa recebe, o que entra na conta e como marcar um horário vazio.',
    relacionados: ['pagamento', 'cancelamento'],
    perguntas: [
      {
        pergunta: 'A casa paga sobre a agenda inteira?',
        resposta:
          'Não. A comissão incide só sobre o que o app vender. O padrão é 25%. Casas podem ter condição combinada.',
      },
      {
        pergunta: 'Quando o crédito de indicação entra?',
        resposta:
          'Fica 30 dias pendente e depois entra no repasse das próximas reservas pelo app.',
      },
      {
        pergunta: 'Quem paga o ponto em dobro do horário vazio?',
        resposta:
          'O custo é dividido: metade fica com a casa e metade com o EscapeMatch.',
      },
    ],
  },
];

export function temaPorSlug(slug: string): Tema {
  const achado = temas.find((item) => item.slug === slug);
  if (!achado) throw new Error(`tema ausente: ${slug}`);
  return achado;
}

export const perguntasVistas: { tema: string; pergunta: Pergunta }[] = [
  { tema: 'grupo', pergunta: temas[0].perguntas[1] },
  { tema: 'pagamento', pergunta: temas[1].perguntas[2] },
  { tema: 'cancelamento', pergunta: temas[2].perguntas[0] },
  { tema: 'pontos', pergunta: temas[4].perguntas[0] },
  { tema: 'conta', pergunta: temas[3].perguntas[1] },
  { tema: 'casas', pergunta: temas[5].perguntas[0] },
];
