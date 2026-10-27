# Decisões provisórias

Decisões do dono do produto que o código segue agora. Cada uma pode mudar. A data é o dia em que ela foi registrada neste arquivo.

## Entrada livre no grupo

- **Data:** 2026-10-27
- **Decisão:** entrar num grupo é imediato. O organizador não aprova nem recusa a pessoa. Se há vaga e a pessoa ainda não está no grupo, a vaga é dela.
- **Motivo:** a dor desta versão é achar gente para jogar, não administrar um convite. Uma fila de aprovação atrasaria o único gesto da tela de detalhe.
- **Onde está no código:** `GroupRepository.join` insere o participante na hora. Não existe estado “pendente”.
- **Como trocar depois:** se um grupo passar a pedir aprovação, o `join` deixa de inserir o membro e passa a gravar um pedido. A função `join_group` do rascunho em [SUPABASE_ESQUEMA.md](SUPABASE_ESQUEMA.md) teria de criar esse pedido em vez do membro, e a tela precisaria de um estado “aguardando”. Até lá, a função insere direto.

## Quase cheios

- **Data:** 2026-10-27
- **Decisão:** “Quase cheios” significa que ainda dá para entrar e faltam 1 ou 2 vagas. O 2 não fica espalhado pelo código: é a constante `GroupRules.almostFullMaxOpenSeats`.
- **Motivo:** o filtro é para quem quer um grupo que está perto de fechar, não para listar todo mundo. O dono pediu 1 ou 2, com a porta aberta para mudar o número sem reescrever a regra.
- **Onde está no código:** `lib/features/groups/domain/group_rules.dart`. O texto do filtro na lista lê essa constante.
- **Como trocar depois:** alterar `almostFullMaxOpenSeats`. Os testes que fixam o valor 2 vão falhar de propósito, para a mudança ser vista. O texto “1 ou N” acompanha a constante. Um limite diferente de 2 pode pedir uma frase melhor (por exemplo “até N vagas”).

## Um grupo por sala e horário

- **Data:** 2026-10-27
- **Decisão:** não podem existir dois grupos na mesma sala com o mesmo horário de início. A pessoa vê a frase: “Já existe um grupo nessa sala nesse horário. Escolha outro horário.”
- **Motivo:** duas turmas na mesma sala no mesmo minuto não têm onde jogar. O horário é o relógio da sessão, não um id interno de slot, para dois registros com a mesma hora também conflitarem.
- **Onde está no código:** `GroupRules.roomAndTimeTaken`, recusado de novo em `FakeGroupRepository.create` com `CreateGroupFailureReason.duplicateSession`. A frase fica em `CreateGroupScreen`.
- **Como trocar depois:** se a casa passar a aceitar mais de um grupo no mesmo horário (duas salas físicas com o mesmo nome, ou uma lista de espera), a regra sai de `GroupRules` e do índice único `(room_id, starts_at)` do rascunho Supabase. A mensagem da tela sai junto.

## Usuário atual fictício

- **Data:** 2026-10-27
- **Decisão:** o nome “Você” não está escrito dentro do repositório de grupos. Ele é o usuário atual fictício devolvido por `currentUserProvider`, pronto para ser trocado por login.
- **Motivo:** o app ainda não tem conta, mas o lugar do usuário precisa existir antes, senão o nome fica cravado em cada chamada de entrar e de criar.
- **Onde está no código:** `CurrentUser` em `lib/features/account/domain/current_user.dart` e o provider em `lib/features/account/presentation/current_user_provider.dart`. O valor de exemplo é `sampleCurrentUser` (id `user-local`, nome Você). Criar grupo e entrar no grupo leem esse provider e mandam o id e o nome para o repositório. O id do participante (a cadeira) continua separado do id do usuário.
- **Como trocar depois:** o provider passa a ler a sessão de verdade (Supabase Auth ou outro) e devolve o mesmo `CurrentUser`, com o id da conta e o nome do perfil. As telas e o `FakeGroupRepository` não precisam conhecer o login. No banco, `group_members.user_id` guarda esse id. A frase “Você está neste grupo” é texto da interface, não o nome da pessoa, e pode continuar.
