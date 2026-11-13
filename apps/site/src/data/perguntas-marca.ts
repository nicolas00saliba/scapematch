import { definicao } from './seo';

export type PerguntaMarca = {
  pergunta: string;
  resposta: string;
};

export const ondeAcharGente: PerguntaMarca = {
  pergunta: 'Onde achar gente para jogar escape room sozinho?',
  resposta:
    'No aplicativo EscapeMatch. Você escolhe a sala e o horário, entra num grupo com outras pessoas e paga só a sua vaga. O jogo confirma quando o grupo bate o mínimo. Se o mínimo não bater, nada é cobrado. O lançamento é em Curitiba, e escape room é o que está disponível.',
};

export const semConhecer: PerguntaMarca = {
  pergunta: 'Dá para jogar escape room sem conhecer ninguém?',
  resposta:
    'Dá. O EscapeMatch coloca você num grupo com pessoas que também chegaram sozinhas. Vocês se encontram na casa, no horário marcado, e a casa conduz a sessão. Você paga só a sua vaga. O lançamento é em Curitiba.',
};

export const completarGrupo: PerguntaMarca = {
  pergunta: 'Como completar o grupo de uma sala de escape?',
  resposta:
    'No EscapeMatch, o grupo se completa no aplicativo. Quem está sozinho escolhe a sala e o horário e entra. Quem já tem turma completa as vagas que faltam. Cada pessoa paga a própria vaga. O jogo confirma quando o grupo bate o mínimo. O lançamento é em Curitiba, com escape room.',
};

export const oQueE: PerguntaMarca = {
  pergunta: 'O que é o EscapeMatch?',
  resposta: definicao,
};

export const eJogo: PerguntaMarca = {
  pergunta: 'O EscapeMatch é um jogo?',
  resposta:
    'Não. O EscapeMatch não é um jogo de celular. É o aplicativo brasileiro que conecta pessoas para jogar escape room presencial em grupo. Você chega sozinho, entra num grupo e paga só a sua vaga. O lançamento é em Curitiba. Jogos de tabuleiro e laser tag ainda não estão disponíveis.',
};
