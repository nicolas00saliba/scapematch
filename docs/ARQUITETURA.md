# Arquitetura do ScapeMatch

Este texto é para ler o código com calma. A primeira versão é de propósito pequena: dá para seguir uma tela do botão até o dado fictício sem atravessar dez camadas.

## A ideia em uma frase

A tela não busca dados. Ela observa um **view model**. O view model chama um **repositório**. O repositório, hoje, lê uma lista na memória. Amanhã o repositório pode ler o Supabase. A tela continua igual.

```text
Tela  ->  view model  ->  repositório (interface)  ->  fonte de dados
 ^                                                      |
 +---------------- estado (carregando, lista, erro) ---+
```

## As três pastas de cada feature

| Pasta | O que mora ali | Pode importar Flutter? |
| --- | --- | --- |
| `domain/` | Modelos e regras (`Group`, `GroupRules`) | Não |
| `data/` | Contrato do repositório e a versão fictícia | Não |
| `presentation/` | Tela e view model (Riverpod) | Sim |

`lib/core/` guarda o que mais de uma feature usa: o banco em memória, o banner de dados de exemplo, a formatação de data.

`asset_experience_source.dart` é o único arquivo de `data/` que importa o Flutter, e só para ler um JSON que já vem no app (`rootBundle`). O parse em si fica em `json_experience_source.dart`, sem Flutter.

`lib/providers/repositories.dart` é a única costura entre “o app quer um `GroupRepository`” e “hoje isso é o `FakeGroupRepository`”. O feed usa a mesma costura: `newsRepositoryProvider` aponta para o `FakeNewsRepository`. Quando o Supabase entrar, a mudança principal é esse arquivo, mais uma classe nova em `data/`.

## Como a Home funciona

1. O app abre em `/`, a Home. A barra inferior é Home, Meus grupos, Conta. As três abas são ramos de um `StatefulShellRoute`, então cada uma guarda o próprio scroll.
2. A cidade começa em Curitiba quando não há escolha salva. O `main` lê `SelectedCityStore` (shared_preferences; na web, localStorage) antes do primeiro frame e o seletor já mostra essa cidade. Trocar grava o id. A escolha salva prevalece. A mesma cidade filtra os grupos, as salas e o feed.
3. O topo é `FindGroupsSection`: busca com o hint inteiro e Criar grupo na mesma linha quando cabe; em tela estreita o botão vira só o ícone +, com o nome “Criar grupo”. O chip Quase cheios fica abaixo. O aviso de dados de exemplo é um chip pequeno, não uma barra. A lista de grupos só é desenhada com texto na busca ou com o chip ligado. O texto filtra em memória (`filterGroupsByText`). Criar grupo abre `/groups/new`.
4. O `FakeGroupRepository` filtra `FakeDatabase.groups`. Esses grupos foram montados em `sample_data.dart`.
5. Quando a lista aparece, os estados continuam carregando, erro ou os cartões. Sem texto e sem o chip, ela não é desenhada.
6. Em seguida, `NewsSection` lê `homeNewsProvider` (cidade, sem chip) e desenha o carrossel primário. “Ver tudo” abre `/news`, onde os chips filtram `newsFeedViewModelProvider`.
7. `RoomThemeSpan` desenha os temas. Os dois primeiros ficam antes de `PromoCarousel`. O resto fica depois. `PopularRoomsSection` fecha a página. As setas estão em `ArrowCarousel`. Nas promoções, `pageExtent` faz cada toque andar um flyer. “Achar grupo” abre `/rooms/:roomId/groups`. “Criar grupo” do cartão abre `/groups/new?roomId=`.
8. A aba Conta (`/account`) lê `currentUserProvider` para a saudação. Os destinos (`/account/:destination`) são placeholders. O nome de exemplo é Nícolas.

A rota antiga `/groups` redireciona para `/`. Meus grupos continua em `/groups/mine`.

Entrar num grupo é o mesmo desenho, com um passo a mais: `GroupDetailViewModel.join` chama `GroupRepository.join`. O repositório devolve sucesso ou um motivo (`cheio`, `já entrou`, `não achou`). Não usa exceção para um grupo cheio, porque isso é uma resposta normal. A lista é atualizada na memória. Criar, entrar, sair, excluir, confirmar presença, remover participante e editar invalidam a busca e Meus grupos. A aba fica montada no shell, então ela não recarrega sozinha.

## Onde estão as regras

`lib/features/groups/domain/group_rules.dart` não conhece widget nem banco.

- **Entrar:** só se `preenchidas < total`, o grupo não foi cancelado, a sessão não começou e a pessoa não está em outro grupo no mesmo intervalo. Sair do mesmo grupo é definitivo.
- **Presença:** entrou, presença confirmada ou cancelou. Confirmar não trava o jogo. O criador confirma a própria cadeira.
- **Reembolso simulado:** sair com `GroupRules.refundDeadline` (2 horas) ou mais de antecedência devolve o valor. Menos que isso não devolve. Exatamente 2 horas devolve. O organizador excluir o grupo, ou remover uma pessoa, devolve sempre, mesmo dentro das 2 horas. O “agora” é o `Clock` de `clockProvider`.
- **Excluir:** só o criador. Cancela para todo mundo, reembolsa quem ainda está, tira o grupo da busca e libera a sala naquele horário. O criador não tem botão de sair.
- **Editar:** o criador muda o tamanho desejado (sem ficar abaixo de quem já entrou, sem ficar abaixo de 2, sem passar da sala) e uma observação de até 280 caracteres.
- **Listas:** `listByCity` esconde grupo cancelado e sessão já encerrada. `listForUser` devolve o histórico para Meus grupos.
- **Quase cheios:** ainda há vaga, e as vagas abertas cabem em `GroupRules.almostFullMaxOpenSeats` (hoje 2, ou seja, faltam 1 ou 2). Grupo cheio fica de fora. Mudar o filtro é mudar essa constante. O texto da tela lê o mesmo número.
- **Criar:** `1 (quem cria) + vagas pedidas <= capacidade da sala`. A capacidade da sala e o tamanho do grupo são números diferentes. Um grupo pode querer 4 pessoas numa sala que comporta 6. O formulário não trava mais num teto fixo de 12: o mínimo e o máximo vêm de `GroupRules` (`minExtraSpots` e `maxExtraSpots`). Sem sala escolhida, não há teto.
- **Uma sala, um horário:** não nascem dois grupos na mesma sala com o mesmo horário de início. A comparação é o relógio, não o id do slot. A tela diz: “Já existe um grupo nessa sala nesse horário. Escolha outro horário.”
- **Entrar é livre.** Não há aprovação do organizador. Quem toca em entrar ocupa a vaga na hora, se ela existir.

O repositório e a tela chamam as mesmas funções. O botão desliga quando a conta não fecha, e o repositório recusa de novo se alguém chamar direto. Os testes em `test/group_rules_test.dart` e `test/fake_repositories_test.dart` travam esse comportamento.

## Estado com Riverpod

Usamos Riverpod 3, sem gerador de código, para o arquivo continuar legível.

- `Notifier` guarda um valor simples que muda na hora (cidade escolhida, filtro, formulário).
- `AsyncNotifier` guarda algo que vem de um `Future` (a lista, o detalhe). O widget usa `when` para carregando, erro e dado.
- O retry automático do Riverpod 3 está desligado em `lib/app/retry.dart`. Quem tenta de novo é a pessoa, no botão.

A navegação é o `go_router` em `lib/app/router.dart`. A barra é um `StatefulShellRoute.indexedStack`: o primeiro ramo é `/` (Home) e o segundo é `/groups/mine` (Meus grupos). Por cima da barra ficam `/groups/new`, `/groups/:groupId` e `/news/:newsId`. A palavra `new` continua registrada antes de `:groupId`. `/groups/mine` é a tela Meus grupos, com as abas Próximos, Passados e Cancelados. `/groups` sem sufixo volta para a Home.

## O que é fictício, no código

`buildSampleDatabase()` em `lib/core/data/sample_data.dart` cria tudo. `FakeDatabase` segura as listas. Casas, salas e horários não mudam. A lista de grupos muda quando alguém entra ou cria um grupo, e só até o app fechar.

Cada cidade nasce com dois grupos: um quase cheio e outro com mais vagas abertas, os dois dentro da capacidade da sala e em salas diferentes. O quase cheio começa 90 minutos depois do relógio do app. O outro começa 3 dias e 6 horas depois. Eles não se sobrepõem. Os outros horários futuros ficam livres, e cada sala também tem um horário que já passou. A tela de criar grupo não pede data e hora soltas: o seletor mostra os horários da sala. Há pelo menos quatro horários futuros por sala.

O preço por pessoa é fictício e fica na sala, em centavos. O grupo copia esse número quando nasce. O pagamento marcado como pago, e o reembolso, também são simulados.

O feed de exemplo nasce em `buildSampleNews`, com a mesma hora do `clockProvider`. São dez notícias em Curitiba e mais algumas nas outras cidades. Texto, link e ilustração são inventados. A grade de sexta não tem arquivo e o app desenha um degradê. O combo de café também não usa a foto da biblioteca: o degradê traz um ícone de xícara. Os JPEG do feed têm cerca de 800 px de largura. O banner laranja nas telas repete o aviso para quem está usando, não só para quem lê o código. Ele também cita as notícias.

Quem usa o app não está escrito como um nome fixo dentro do repositório. O nome vem de `currentUserProvider` (`lib/features/account/`). Hoje esse provider devolve um usuário fictício chamado Nícolas. Quando houver login, a troca é a implementação desse provider. A frase “Você está neste grupo” é texto da tela.

## Entrar no grupo no Supabase tem de ser atômico

Dois celulares podem ver a última vaga ao mesmo tempo. Se cada um fizer “ler quantos já entraram, e se couber, inserir”, os dois passam e o grupo estoura. Política de RLS sozinha não resolve: ela autoriza a linha, mas não segura a contagem e a inserção na mesma transação.

Por isso a entrada não pode ser um `insert` solto vindo do app. Ela precisa de uma função SQL (`join_group`) chamada por RPC, que:

1. recusa quem não está autenticado;
2. trava a linha do grupo (`select ... for update`);
3. conta os membros de verdade, sem confiar num número que o cliente mandou;
4. insere o membro ou devolve “cheio” / “já entrou”;
5. faz isso tudo numa transação só.

A função roda com `security definer`, então ela atravessa o RLS. As checagens têm de estar dentro dela. O cliente não ganha `insert` direto em `group_members`. O mesmo cuidado vale para criar o grupo: a vaga da sala e o criador entram juntos, e o índice único `(room_id, starts_at)` impede o grupo duplicado mesmo com duas requisições ao mesmo tempo.

O rascunho das tabelas, das políticas e da função está em [SUPABASE_ESQUEMA.md](SUPABASE_ESQUEMA.md). Nada disso está ligado ao app ainda.

## Como trocar por dados reais depois

1. Criar tabelas (cidade, casa, sala, horário, grupo, participante). O rascunho está em [SUPABASE_ESQUEMA.md](SUPABASE_ESQUEMA.md). A entrada no grupo usa a função atômica, não um insert do cliente.
2. Escrever `SupabaseGroupRepository implements GroupRepository` com os mesmos métodos: `listByCity`, `listForUser`, `getById`, `join`, `create`, `confirmAttendance`, `leave`, `deleteGroup`, `removeMember`, `edit`. O `join`, a saída, a exclusão e a remoção chamam RPC. O repositório recebe o mesmo `Clock` para as regras que comparam com agora, ou usa o `now()` do banco dentro da função.
3. Apontar `groupRepositoryProvider` para essa classe.
4. Repetir a ideia para cidades, para o catálogo e para o feed. O feed troca `newsRepositoryProvider` por uma classe que implementa `NewsRepository` (`list` e `getById`). A Home não ganha HTTP por causa disso. O catálogo é separado de propósito, e o feed também: notícia não é horário de jogo. Cada casa entra no catálogo por um `ExperienceSource` (salas e sessões, com o tipo de disponibilidade). O exemplo que existe hoje só lê um JSON local. Como uma integração futura entra, inclusive a notícia vinda de site ou de Instagram, e quando um site não pode ser coletado, está em [DADOS_REAIS.md](DADOS_REAIS.md).

As telas não devem ganhar `http` nem SQL. Se a tela precisar de um campo novo, ele entra no modelo `Group` e o repositório passa a preenchê-lo.
