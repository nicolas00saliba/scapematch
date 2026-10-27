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
- **Quase cheios:** ainda há vaga, e faltam 1 ou 2. Grupo cheio fica de fora. O número 2 é uma escolha desta versão e pode mudar.
- **Criar:** `1 (quem cria) + vagas pedidas <= capacidade da sala`. A capacidade da sala e o tamanho do grupo são números diferentes. Um grupo pode querer 4 pessoas numa sala que comporta 6.

O repositório e a tela chamam as mesmas funções. O botão desliga quando a conta não fecha, e o repositório recusa de novo se alguém chamar direto. Os testes em `test/group_rules_test.dart` e `test/fake_repositories_test.dart` travam esse comportamento.

## Estado com Riverpod

Usamos Riverpod 3, sem gerador de código, para o arquivo continuar legível.

- `Notifier` guarda um valor simples que muda na hora (cidade escolhida, filtro, formulário).
- `AsyncNotifier` guarda algo que vem de um `Future` (a lista, o detalhe). O widget usa `when` para carregando, erro e dado.
- O retry automático do Riverpod 3 está desligado em `lib/app/retry.dart`. Quem tenta de novo é a pessoa, no botão.

A navegação é o `go_router` em `lib/app/router.dart`: `/`, `/groups`, `/groups/new`, `/groups/:groupId`. A rota `new` vem antes de `:groupId` para a palavra “new” não virar um id.

## O que é fictício, no código

`buildSampleDatabase()` em `lib/core/data/sample_data.dart` cria tudo. `FakeDatabase` segura as listas. Casas, salas e horários não mudam. A lista de grupos muda quando alguém entra ou cria um grupo, e só até o app fechar.

O banner laranja nas telas repete o aviso para quem está usando, não só para quem lê o código.

## Como trocar por dados reais depois

1. Criar tabelas (cidade, casa, sala, horário, grupo, participante).
2. Escrever `SupabaseGroupRepository implements GroupRepository` com os mesmos métodos: `listByCity`, `getById`, `join`, `create`.
3. Apontar `groupRepositoryProvider` para essa classe.
4. Repetir a ideia para cidades e para o catálogo. O catálogo é separado de propósito: no futuro ele pode ser preenchido com salas e agendas coletadas dos sites das casas, sem mexer na tela de grupo.

As telas não devem ganhar `http` nem SQL. Se a tela precisar de um campo novo, ele entra no modelo `Group` e o repositório passa a preenchê-lo.
