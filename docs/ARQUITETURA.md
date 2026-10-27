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

`lib/providers/repositories.dart` é a única costura entre “o app quer um `GroupRepository`” e “hoje isso é o `FakeGroupRepository`”. Quando o Supabase entrar, a mudança principal é esse arquivo, mais uma classe nova em `data/`.

## Como a tela “Encontrar grupo” funciona

1. A pessoa escolhe a cidade no `CitySelector`. Isso grava o id em `selectedCityIdProvider`. Nada fica fixo em Curitiba; o valor inicial é vazio.
2. A rota `/groups` abre `FindGroupsScreen`.
3. A tela observa `findGroupsViewModelProvider`.
4. O `FindGroupsViewModel` lê a cidade e o filtro “Quase cheios” e chama `GroupRepository.listByCity`.
5. O `FakeGroupRepository` filtra `FakeDatabase.groups`. Esses grupos foram montados em `sample_data.dart`.
6. A tela desenha um dos três estados:
   - carregando
   - erro, com “Tentar de novo”
   - lista, ou o vazio se a cidade não tem grupo naquele filtro

Entrar num grupo é o mesmo desenho, com um passo a mais: `GroupDetailViewModel.join` chama `GroupRepository.join`. O repositório devolve sucesso ou um motivo (`cheio`, `já entrou`, `não achou`). Não usa exceção para um grupo cheio, porque isso é uma resposta normal. A lista é atualizada na memória e a tela de baixo é invalidada para recarregar.

## Onde estão as regras

`lib/features/groups/domain/group_rules.dart` não conhece widget nem banco.

- **Entrar:** só se `preenchidas < total`.
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

A navegação é o `go_router` em `lib/app/router.dart`: `/`, `/groups`, `/groups/new`, `/groups/:groupId`. A rota `new` vem antes de `:groupId` para a palavra “new” não virar um id.

## O que é fictício, no código

`buildSampleDatabase()` em `lib/core/data/sample_data.dart` cria tudo. `FakeDatabase` segura as listas. Casas, salas e horários não mudam. A lista de grupos muda quando alguém entra ou cria um grupo, e só até o app fechar.

Cada cidade nasce com dois grupos: um quase cheio e outro com mais vagas abertas, os dois dentro da capacidade da sala e em salas diferentes. Os outros horários ficam livres. A tela de criar grupo não pede data e hora soltas: o seletor mostra os horários da sala. Há pelo menos quatro por sala, para caber vários grupos sem colidir no mesmo começo.

O banner laranja nas telas repete o aviso para quem está usando, não só para quem lê o código.

Quem usa o app não está escrito como o texto “Você” dentro do repositório. O nome vem de `currentUserProvider` (`lib/features/account/`). Hoje esse provider devolve um usuário fictício, ainda chamado Você. Quando houver login, a troca é a implementação desse provider.

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
2. Escrever `SupabaseGroupRepository implements GroupRepository` com os mesmos métodos: `listByCity`, `getById`, `join`, `create`. O `join` chama a RPC.
3. Apontar `groupRepositoryProvider` para essa classe.
4. Repetir a ideia para cidades e para o catálogo. O catálogo é separado de propósito. Cada casa entra por um `ExperienceSource` (salas e sessões, com o tipo de disponibilidade). O exemplo que existe hoje só lê um JSON local. Como uma integração futura entra, e quando um site não pode ser coletado, está em [DADOS_REAIS.md](DADOS_REAIS.md).

As telas não devem ganhar `http` nem SQL. Se a tela precisar de um campo novo, ele entra no modelo `Group` e o repositório passa a preenchê-lo.
