# Decisões provisórias

Decisões do dono do produto que o código segue agora. Cada uma pode mudar. A data é o dia em que ela foi registrada neste arquivo.

## Conta: carteira, cartões e saldo

- **Data:** 2026-10-28
- **Decisão:** a lista da Conta é Perfil, Meus parceiros de jogo, Indique e ganhe, Cartões cadastrados e Ajuda. “Resgatar vale-presente” saiu. Cartões cadastrados abre uma lista vazia, “Nenhum cartão cadastrado”, e o botão Adicionar cartão só avisa que o cadastro chega em breve. Não há campo de número, validade nem código de segurança. No quadro verde da Carteira ScapeMatch há o botão Adicionar saldo, em branco com texto verde. Ele abre uma tela de preparativos com R$ 20, R$ 50, R$ 100 e outro valor, e as formas Cartão cadastrado e Pix desligadas, com “Em breve”. Confirmar fica desligado. Nada é cobrado e o saldo não muda. O saldo da carteira é o do `WalletRepository` (hoje R$ 40,00, a soma de um crédito de exemplo). Os cartões vêm do `PaymentMethodsRepository`, hoje vazio. Um método de pagamento só guarda bandeira, quatro últimos dígitos e apelido. O plano do que falta está em [PAGAMENTOS_PLANO.md](PAGAMENTOS_PLANO.md).
- **Motivo:** o dono quer o lugar da carteira e dos cartões antes do pagamento de verdade, sem coletar dado de cartão nesta versão.
- **Onde está no código:** `AccountScreen`, `PaymentMethodsBody`, `AddBalanceScreen`, `WalletRepository`, `PaymentMethodsRepository` e os providers em `lib/providers/repositories.dart`.
- **Como trocar depois:** o provider aponta para a implementação do Supabase e do gateway. A tela de confirmar passa a chamar `addBalance` com uma chave de idempotência. O cadastro de cartão passa a guardar o token do provedor, não o número.

## Ordem da Home e quadros inteiros

- **Data:** 2026-10-28
- **Decisão:** a Home, de cima para baixo, é o seletor de cidade e de jogo, a janela de grupos quase cheios (como já estava), Promoções, o carrossel de Novidades e um único carrossel de Salas. Não há mais um carrossel por tema nem a seção “Salas mais procuradas” na Home: ela repetia as salas. As rotas `/rooms/category/:category` e `/rooms/popular` continuam, para um link antigo não quebrar; a Home não aponta para elas. Cada seta (promoções, novidades e salas) anda um quadro e descansa com os quadros inteiros. A largura do quadro sai da largura visível: se só cabe um na largura desejada de 250 px, ele preenche a faixa e o vão fica fora da borda; se cabem dois, os dois dividem a faixa. Soltar o dedo alinha no quadro mais próximo. A seta some na ponta. A coluna da página continua limitada a 560 px, então numa janela de 1280 a faixa útil é cerca de 528 px e mostra dois quadros; no celular de 390, um. As promoções ganharam o título “Promoções”. O cartaz continua sem desconto de verdade.
- **Motivo:** o dono pediu essa ordem e reclamou que o quadro ficava cortado tanto na posição A quanto na B.
- **Onde está no código:** `HomeScreen`, `PromoCarousel`, `NewsSection`, `RoomsCarousel` e `ArrowCarousel` (`CarouselLayout` e a física de snap).
- **Como trocar depois:** outra ordem é a sequência em `HomeScreen`. Outra largura de quadro é `carouselPreferredItemWidth`. Se a Home passar a usar a largura inteira do desktop, o mesmo cálculo cabe mais quadros inteiros.

## Tipo de jogo no topo

- **Data:** 2026-10-28
- **Decisão:** ao lado da cidade há um seletor de tipo de jogo: Todos, Escape room, RPG, Jogos de tabuleiro, Laser tag e Imersivo. A escolha fica no aparelho, na chave `selected_game_type`, do mesmo jeito que a cidade. Ela filtra a janela de grupos, o carrossel de novidades e o carrossel de salas. O catálogo de exemplo segue em maior parte escape room. Curitiba tem, além disso, uma sala e uma notícia de cada um dos outros tipos, para o filtro mostrar um resultado. Nas outras cidades o filtro desses tipos fica vazio até existir uma fonte real. Os grupos extras de Curitiba incluem escape room, RPG, tabuleiro, laser tag e imersivo, com nome da atividade (não o da sala de escape). No seletor fechado os rótulos são Todos, Escape, RPG, Tabuleiro, Laser e Imersivo; a folha mantém o nome completo. A cidade é que encolhe com reticências, para o jogo não cortar.
- **Motivo:** o dono quer o mesmo filtro na janela de grupos e nas salas, e notícias dos outros gêneros no carrossel.
- **Onde está no código:** `GameTypeSelector`, `SelectedGameTypeStore`, `filterGroupsByGameType`, `filterNewsByGameType` e `filterRoomsByGameType`. O `main` lê o store antes do primeiro frame. O tipo da sala é `EscapeRoom.gameType`. O da notícia é `NewsItem.gameType`.
- **Como trocar depois:** uma fonte real preenche o mesmo id. Mudar a lista é editar `GameTypes.choices`.

## Janela de grupos na Home

- **Data:** 2026-10-28
- **Decisão:** os grupos formados voltam para a abertura, numa janela que encolhe até o conteúdo e no máximo cabe cerca de um cartão e o começo do seguinte. A barra de rolagem vertical só aparece quando os cartões não cabem. Um arrasto que passa do fim ou do começo da janela continua na página. Curitiba tem grupos quase cheios a mais, de exemplo, para essa barra existir no protótipo. As promoções ficam logo abaixo dessa janela — ver “Ordem da Home e quadros inteiros”.
- **Motivo:** a compressão tinha tirado os grupos e empurrado as promoções para fora da vista. A janela devolve os grupos sem ocupar a página inteira.
- **Onde está no código:** `FindGroupsSection` (`groupWindowMaxHeight`) e os grupos extras em `sample_data.dart`.
- **Como trocar depois:** o teto da janela é a constante `groupWindowMaxHeight`. Um feed real substitui os grupos extras.

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
- **Onde está no código:** `CurrentUser` em `lib/features/account/domain/current_user.dart` e o provider em `lib/features/account/presentation/current_user_provider.dart`. O valor de exemplo é `sampleCurrentUser` (id `user-local`). Em 2026-10-28 o nome de exemplo passou de “Você” para “Nícolas”, para a aba Conta cumprimentar a pessoa. Criar grupo e entrar no grupo leem esse provider e mandam o id e o nome para o repositório. O id do participante (a cadeira) continua separado do id do usuário. A frase “Você está neste grupo” continua sendo texto da interface, não o nome.
- **Como trocar depois:** o provider passa a ler a sessão de verdade (Supabase Auth ou outro) e devolve o mesmo `CurrentUser`, com o id da conta e o nome do perfil. As telas e o `FakeGroupRepository` não precisam conhecer o login. No banco, `group_members.user_id` guarda esse id. A frase “Você está neste grupo” é texto da interface, não o nome da pessoa, e pode continuar.

## O criador exclui o grupo, não sai dele

- **Data:** 2026-10-27
- **Decisão:** quem criou o grupo não tem “sair”. Para desfazer a própria presença, exclui o grupo, e só enquanto a sessão não começou. Não há transferência de organizador nesta versão. Excluir cancela o evento para todo mundo que ainda está no grupo e devolve o pagamento simulado integral, mesmo que falte menos de 2 horas, porque o cancelamento é do organizador. O grupo some da busca e continua em Meus grupos, na aba Cancelados, com o reembolso. O horário da sala volta a ficar livre.
- **Motivo:** um grupo sem organizador fica sem ninguém para excluir ou editar. Transferir a cadeira de criador pede uma escolha de sucessor que esta versão não tem. O reembolso integral evita punir quem só entrou porque o organizador marcou o jogo.
- **Onde está no código:** `GroupRules.refundForOrganizer`, `FakeGroupRepository.deleteGroup` e `LeaveGroupFailureReason.creatorMustDelete`. O botão “Excluir grupo” só aparece para o criador. A frase do diálogo está em `GroupMessages.deleteBody`.
- **Como trocar depois:** para permitir transferência, o `leave` do criador passa a exigir um `newCreatorUserId` e só então tira a cadeira antiga. A função SQL `delete_group` do rascunho ganharia uma irmã `transfer_group`. Até lá, o criador exclui.

## Reembolso simulado na saída voluntária

- **Data:** 2026-10-27
- **Decisão:** sair com 2 horas ou mais de antecedência devolve o pagamento simulado. Sair com menos de 2 horas não devolve. Exatamente 2 horas ainda devolve. Entrar numa sessão que começa em menos de 2 horas e depois sair também não devolve: a conta é o instante da saída contra o início, não o instante da entrada. O limite é `GroupRules.refundDeadline`. O “agora” vem de um `Clock` injetável (`clockProvider`). Não há `DateTime.now` espalhado; só `SystemClock` lê o relógio do aparelho. O diálogo lê o relógio na hora em que abre. Quem decide o reembolso é o repositório, de novo, na confirmação. Se o relógio andou com o diálogo aberto e o resultado for outro, a tela avisa que o horário mudou e diz o que foi registrado.
- **Motivo:** o dono pediu um aviso antes de confirmar, e testes que não dependem do minuto em que a suíte roda. Uma constante única deixa o texto da tela e a regra no mesmo número. O diálogo não pode travar o resultado, senão um aviso de reembolso vira mentira quando o prazo vence com ele aberto.
- **Onde está no código:** `GroupRules.refundsOnParticipantCancel` e `refundForParticipantCancel`. O diálogo está em `GroupDetailScreen._leave`. O repositório calcula de novo na hora da saída. A frase de divergência é `GroupMessages.leavePreviewChanged`.
- **Como trocar depois:** mudar `refundDeadline`. Os testes que fixam 2 horas, 1 minuto a mais e 1 minuto a menos falham de propósito. Se a casa passar a reembolsar por percentual, a função devolve um valor em centavos em vez de sim ou não, e o diálogo mostra esse valor.

## Sair do grupo é definitivo

- **Data:** 2026-10-27
- **Decisão:** quem saiu, ou foi removido, não entra de novo naquele grupo. A vaga abre para outra pessoa. O histórico da saída (reembolsado ou sem reembolso) fica na cadeira, para Meus grupos.
- **Motivo:** reentrar apagaria o reembolso que a pessoa acabou de ver, ou criaria duas cadeiras da mesma conta. Uma cadeira só, fechada, é mais simples de explicar.
- **Onde está no código:** `JoinFailureReason.membershipClosed`. A frase é “Você já saiu deste grupo e não pode entrar de novo.”
- **Como trocar depois:** o `join` reabre a cadeira cancelada, zera o reembolso e marca o pagamento simulado de novo. A frase sai da tela.

## Não entrar em grupo que já começou

- **Data:** 2026-10-27
- **Decisão:** no instante do início, ou depois, ninguém novo entra e ninguém cria grupo naquele horário. A sessão que já terminou sai da busca e vai para Passados. Uma sessão em andamento continua visível, sem o botão de entrar. Confirmar presença ainda pode, até a sessão terminar, inclusive depois de começar. Sair depois de começar não reembolsa. O criador não exclui nem remove ninguém depois que a sessão começou.
- **Motivo:** chegar no meio do jogo não cabe numa sala que já fechou a porta. Esconder o grupo no minuto em que começa tiraria a tela de quem já está nele.
- **Onde está no código:** `GroupRules.hasStarted` e `hasEnded`. `listByCity` esconde cancelados e encerrados. Criar num horário passado devolve “Esse horário já passou. Escolha um horário que ainda não começou.”
- **Como trocar depois:** se a casa aceitar entrada atrasada, `hasStarted` deixa de bloquear o `join` e o botão volta. O encerramento pode passar a usar só a data, sem a duração.

## Depois que a sessão começou, o criador não desfaz o grupo

- **Data:** 2026-10-27
- **Decisão:** no instante do início, ou depois, o criador não exclui o grupo e não remove participante. A tela mostra “A sessão já começou.” e esconde esses botões. O repositório recusa mesmo assim, com `sessionStarted`. Sessão já encerrada continua recusada com `sessionEnded`. Antes do início, excluir e remover seguem com reembolso integral do organizador.
- **Motivo:** com a sessão em andamento, cancelar a sala ou tirar alguém no meio do jogo apaga o que já está acontecendo. O plano se desfaz antes de começar; depois disso o grupo fica até terminar.
- **Onde está no código:** `FakeGroupRepository.deleteGroup` e `removeMember`, `GroupMessages.sessionAlreadyStarted`, e a barra do detalhe.
- **Como trocar depois:** tirar a checagem `hasStarted` desses dois métodos e voltar a mostrar Excluir e Remover até a sessão terminar. A frase sai da tela.

## Uma pessoa, um horário

- **Data:** 2026-10-27
- **Decisão:** a mesma conta não fica em dois grupos cujos intervalos se cruzam. O intervalo é `[início, início + duração)`. Encerrar exatamente quando o outro começa não conta como cruzamento. Cadeira cancelada e sessão já encerrada não bloqueiam. Vale para entrar e para criar.
- **Motivo:** a pessoa não joga duas salas ao mesmo tempo. O limite é dela, não da sala: salas diferentes no mesmo minuto continuam podendo ter grupos de gente diferente.
- **Onde está no código:** `GroupRules.sessionsOverlap`. A frase ao entrar é “Você já está em outro grupo nesse horário. Saia dele ou escolha outro horário.” Ao criar, “Escolha um horário que não se sobreponha.”
- **Como trocar depois:** se o produto passar a permitir lista de espera ou dois papéis, a checagem sai do `join` e do `create`. O teste de sobreposição deixa de esperar recusa.

## Presença, pagamento e reembolso são simulados

- **Data:** 2026-10-27
- **Decisão:** cada cadeira tem um estado: entrou, presença confirmada ou cancelou. Confirmar presença não é obrigatório para jogar; é um registro. O criador também confirma a própria. Todo mundo que entra fica com pagamento simulado “pago”. O preço é fictício, por pessoa, copiado da sala no momento do grupo, em centavos. Não há cobrança real. O reembolso é “reembolsado” ou “sem reembolso”, com o motivo. Remover um participante é decisão do organizador e reembolsa integral, com a mesma regra da exclusão do grupo.
- **Motivo:** o dono quer o fluxo logístico completo antes de ligar um provedor de pagamento. O preço na sala, copiado para o grupo, evita que uma mudança futura de tabela reescreva o que a pessoa “pagou”.
- **Onde está no código:** `AttendanceStatus`, `PaymentStatus`, `RefundStatus`, `RefundReason`. O preço nasce em `EscapeRoom.priceCents` e vai para `Group.priceCents`. A contagem de presenças confirmadas aparece no cartão e no detalhe.
- **Como trocar depois:** o `join` deixa de marcar `paid` na hora e passa a esperar a confirmação de um provedor. Os estados de reembolso continuam os mesmos; muda quem os grava. Se confirmar presença passar a ser obrigatório, o detalhe esconde o jogo até `confirmed`.

## Meus grupos

- **Data:** 2026-10-27
- **Decisão:** Meus grupos é a aba da direita na barra inferior, não um cartão da Home. Dentro dela ficam três abas: Próximos, Passados e Cancelados. Entram grupos criados e grupos em que a pessoa entrou. Próximos são cadeiras ainda ativas cuja sessão não terminou, inclusive a que já começou. Passados são sessões que já terminaram e não foram canceladas, com a pessoa ainda na cadeira. Cancelados são grupo excluído, saída voluntária ou remoção pelo organizador, mesmo que a sessão também já tenha acabado. Cada aba tem a própria lista e o próprio texto de vazio.
- **Motivo:** a busca é para achar vaga. O histórico da pessoa, inclusive o reembolso, não pode sumir quando o grupo sai da lista da cidade. Misturar sessão encerrada com cancelamento na mesma aba escondia o motivo de cada linha.
- **Onde está no código:** rota `/groups/mine`, segundo ramo do `StatefulShellRoute`, `MyGroupsScreen`, `splitMyGroups` e `GroupRules.bucketForMember`. A separação das três listas não mudou.
- **Como trocar depois:** uma aba “Em andamento” usaria `hasStarted` sem `hasEnded` e sairia de Próximos. Voltar a juntar Passados e Cancelados é desfazer `bucketForMember` num único “não é próximo”.

## Editar o grupo

- **Data:** 2026-10-27
- **Decisão:** o criador edita o número de pessoas desejado e uma observação. O número não fica abaixo das vagas ocupadas, não fica abaixo de 2 e não passa da capacidade da sala. Ocupadas é um número só, `Group.occupiedSpots`: o maior entre `filledSpots` e as cadeiras que ainda ocupam lugar. A tela e o repositório leem esse número. A observação tem no máximo 280 caracteres, já sem espaços nas pontas. Não se edita grupo cancelado nem sessão encerrada.
- **Motivo:** o tamanho pedido na criação erra, e o grupo precisa de um lugar curto para “chegar 15 minutos antes” sem virar um chat. Dois cálculos de “quem já entrou” fariam o stepper aceitar um tamanho que o repositório recusa.
- **Onde está no código:** `Group.occupiedSpots`, `GroupRules.validateTotalSpots`, `GroupRules.maxNoteLength` e `FakeGroupRepository.edit`.
- **Como trocar depois:** se a observação virar mensagem para cada pessoa, ela sai do grupo e vira uma tabela de avisos. O teto de 280 caracteres muda na constante.

## Link do grupo

- **Data:** 2026-10-27
- **Decisão:** o detalhe copia o link da rota go_router `/groups/:id`. No navegador, o link inclui o prefixo da página (por exemplo `/scapematch/`). Não há serviço de compartilhamento do sistema além da área de transferência.
- **Motivo:** a rota já existe. Copiar é o bastante para mandar o grupo no chat, sem pedir permissão de compartilhamento nativo.
- **Onde está no código:** `groupLink` em `lib/core/sharing/group_link.dart`.
- **Como trocar depois:** trocar a função por `Share.share` quando o app for para as lojas. A rota continua a mesma.

## Horários de exemplo relativos a agora

- **Data:** 2026-10-27
- **Decisão:** os dois grupos de exemplo de cada cidade não usam mais uma data fixa de novembro. O quase cheio começa 90 minutos depois do “agora” do app, para o dono testar a saída sem reembolso. O outro começa 3 dias e 6 horas depois, para testar a saída com reembolso. Cada sala continua com pelo menos quatro horários futuros livres o bastante para criar grupo, mais um horário já passado. Os dois grupos de uma cidade não se sobrepõem e não ocupam a mesma sala.
- **Motivo:** uma data fixa em novembro fica o tempo todo fora da janela de 2 horas, e o dono não consegue ver o aviso de sem reembolso. Voltar a ocupar todos os horários impediria criar grupo.
- **Onde está no código:** `buildSampleDatabase({required DateTime now})`, chamado com `clockProvider` em `fakeDatabaseProvider`.
- **Como trocar depois:** quando o catálogo for real, esta função sai. O `Clock` fica, porque a regra de 2 horas continua.

## A Home é a busca, com o feed embaixo

- **Data:** 2026-10-27
- **Decisão:** a tela inicial deixa de ser três cartões grandes. Em cima fica a busca de grupo, mais curta: cidade bem visível, campo “Buscar sala ou casa”, filtro Quase cheios, atalho Criar grupo e cartões de grupo com menos linhas. Logo abaixo, o feed de novidades. Os dois seguem a mesma cidade. A cidade inicial, quando não há escolha salva, é Curitiba — ver “Sem cidade salva, a Home abre em Curitiba”. A lista nunca junta o Brasil inteiro. A rota antiga `/groups` volta para `/`.
- **Motivo:** o dono pediu a busca na própria Home, comprimida, e o feed no mesmo scroll. Um destino separado para “encontrar grupo” repetiria a tela.
- **Onde está no código:** `HomeScreen`, `FindGroupsSection`, `NewsSection`. O texto da busca filtra em memória (`filterGroupsByText`); não cria outro método no `GroupRepository`. O cartão da lista não mostra mais preço, presenças confirmadas nem a barra de progresso. Isso continua no detalhe e em Meus grupos.
- **Como trocar depois:** se a busca voltar a ser uma tela só dela, a seção sai da Home e a rota `/groups` deixa de redirecionar. Se o preço precisar aparecer no cartão, ele volta para `GroupCard`. O atalho Criar grupo pode sair se a barra ganhar um botão de criar.

## Barra inferior: Home à esquerda, Meus grupos à direita

- **Data:** 2026-10-27
- **Decisão:** a barra começou com dois destinos, nesta ordem: Home, Meus grupos. A ordem final daquele dia foi Home à esquerda e Meus grupos à direita. O dono mudou de ideia no mesmo dia: a primeira versão desta decisão punha Meus grupos à esquerda. O app continua abrindo na Home. Cada aba guarda o próprio scroll. Criar grupo, o detalhe do grupo e o detalhe da notícia abrem por cima da barra, com voltar. O rótulo da aba é “Home”, a palavra que o dono usou. A terceira aba, Conta, entrou em 2026-10-28 — ver “Aba Conta”.
- **Motivo:** Meus grupos precisava de um lugar fixo, sem misturar o histórico com a busca. Duas abas bastam para o que existe hoje. A posição à direita foi o pedido final do dono.
- **Onde está no código:** `StatefulShellRoute.indexedStack` em `lib/app/router.dart` e `AppShell`. O ramo 0 é `/` (Home). O ramo 1 é `/groups/mine`.
- **Como trocar depois:** uma aba nova entra como outro `StatefulShellBranch`, na posição em que deve aparecer. Se o nome da aba passar a ser “Início”, muda o `label` da `NavigationDestination`.

## Novidades com gênero

- **Data:** 2026-10-28
- **Decisão:** o cartão de novidade da Home mostra título, resumo curto, etiqueta de gênero e data. A data é o relativo que o app já usava (“há 2 h”) mais o dia e o mês (“27 out”). O gênero usa o mesmo id do seletor de jogo. O chip mostra o nome completo (Escape room, RPG, Jogos de tabuleiro, Laser tag, Imersivo). Há uma notícia fictícia de cada gênero em Curitiba, além das dez de escape room que já existiam. As outras cidades continuam só com escape room. A tela “Ver tudo” segue filtrando por cidade e pela categoria (novas salas, horários, promoções, eventos), não pelo tipo de jogo. Uma fonte real preenche o mesmo `NewsItem`, inclusive `gameType`.
- **Motivo:** o dono pediu notícias do escape room, do RPG e dos outros gêneros, com cara de que podem vir de fora depois.
- **Onde está no código:** `NewsItem.gameType`, `buildSampleNews`, `homeNewsProvider` e `_NewsStripCard`.
- **Como trocar depois:** apontar `newsRepositoryProvider` para a fonte real. Se “Ver tudo” também passar a respeitar o jogo, o filtro entra em `NewsFeedViewModel`.

## Feed de notícias fictícias

- **Data:** 2026-10-27
- **Decisão:** o feed lê `NewsRepository`. Hoje isso é o `FakeNewsRepository`, com notícias inventadas e datas relativas ao `clockProvider`. O modelo é `NewsItem`: id, título, resumo, categoria, casa, cidade, imagem, data, link de origem opcional e tipo de fonte (site, Instagram ou curadoria). Há dez notícias em Curitiba e mais algumas em São Paulo, Rio de Janeiro, Belo Horizonte e Porto Alegre. O chip “Todas” começa selecionado. Os outros chips são Novas salas, Horários, Promoções e Eventos. Tocar de novo num chip de categoria não tira o filtro; “Todas” tira. A ordem é a mais recente primeiro. Ranking, nesta versão, entra como Evento, porque não há um quinto chip. Tocar no cartão abre um detalhe simples. O link de origem aparece como texto e o app não abre o navegador. Duas notícias de Curitiba não usam arquivo: a grade de sexta desenha o ícone da categoria, e o combo de café desenha um degradê com xícara (`NewsIllustration.coffee`), porque a foto da biblioteca não combina com essa história. As duas escrevem “Ilustração fictícia” na imagem. O rótulo de acessibilidade da figura é o título da notícia. Trocar cidade ou chip não pisca o spinner: `skipLoadingOnReload` mantém o que já estava na tela. O spinner aparece na primeira carga.
- **Motivo:** o dono pediu o feed agora, com dados caprichados, e a troca por uma fonte real sem mexer na tela. Abrir um link fictício levaria a um endereço que não existe. Um quinto chip de ranking esperaria uma categoria que ele não listou.
- **Onde está no código:** `lib/features/news/`. A lista passa por `filterNews`. As imagens ficam em `assets/images/news/`. O provider é `newsRepositoryProvider`.
- **Como trocar depois:** apontar `newsRepositoryProvider` para uma classe que implementa `NewsRepository`. A imagem pode ser um asset ou uma URL `http(s)`; o widget `NewsArtwork` já trata os dois, e o vazio continua no degradê. Se o link passar a abrir, a troca é no detalhe, não no modelo. Um chip de ranking seria um valor novo em `NewsCategory`.

## A imagem da notícia não prende a tela ao asset

- **Data:** 2026-10-27
- **Decisão:** o campo `image` é um texto opcional. Caminho `assets/...` desenha um asset. URL `http` ou `https` desenha a rede. Qualquer outro valor, ou vazio, vira a ilustração gerada. Os exemplos usam só assets e vazios. Nenhum exemplo chama a rede. Os JPEG de `assets/images/news/` têm cerca de 800 px de largura e qualidade perto de 75, cada um abaixo de 150 KB. `NewsArtwork` decodifica com `cacheWidth` 800. O `semanticLabel` é o título, não a frase “Ilustração fictícia”.
- **Motivo:** uma fonte real vai mandar URL. Se o campo se chamasse só “asset”, a tela teria de mudar no dia da troca. Arquivo grande demais pesa no repositório e na web sem ganho visível no cartão, que cabe em menos de 560 px.
- **Onde está no código:** `NewsItem.image`, `NewsIllustration` e `NewsArtwork`.
- **Como trocar depois:** o repositório real preenche `image` com a URL pública que a casa autorizou. Foto de marketing continua sujeita à seção de termos em [DADOS_REAIS.md](DADOS_REAIS.md). Um ícone novo entra em `NewsIllustration` e no `switch` de `NewsArtwork`.

## A busca da Home zera quando a Home sai da árvore

- **Data:** 2026-10-27
- **Decisão:** `groupSearchQueryProvider` é autoDispose. O provider da lista já filtrada (`filteredGroupsProvider`) também é, senão ele seguraria a busca viva para sempre e a Home recriada mostraria a lista filtrada com o campo vazio. Trocar para a aba Meus grupos não apaga o texto: o `IndexedStack` do shell mantém a Home montada, e o campo de texto vive nela. Preservar a busca ao trocar de aba é o comportamento desejado. Se a Home sair da árvore, a busca zera.
- **Motivo:** a busca é estado da tela, não um filtro global. AutoDispose acompanha os outros providers de tela. Deixar o provider comum faria o texto sobreviver a uma Home que já foi destruída, sem o campo mostrar esse texto.
- **Onde está no código:** `groupSearchQueryProvider` e `filteredGroupsProvider` em `find_groups_view_model.dart`.
- **Como trocar depois:** se a busca precisar sobreviver mesmo com a Home fora da árvore, os dois providers deixam de ser autoDispose e o campo passa a ler o texto guardado ao abrir.

## Criar grupo abre o detalhe no lugar do formulário

- **Data:** 2026-10-27
- **Decisão:** depois que o grupo nasce, o detalhe substitui o formulário. O voltar vai para a Home. O formulário preenchido não fica na pilha.
- **Motivo:** voltar para o formulário deixava o mesmo envio disponível, e a pessoa criava um grupo duplicado sem querer.
- **Onde está no código:** `CreateGroupScreen._submit`, com `pushReplacement`.
- **Como trocar depois:** se o formulário precisar continuar atrás do detalhe, a chamada volta a ser `push`.

## Criar grupo também atualiza Meus grupos

- **Data:** 2026-10-27
- **Decisão:** toda mudança de grupo invalida a busca e Meus grupos. Criar, entrar, sair, cancelar (excluir o grupo), confirmar presença, remover participante e editar. O detalhe já fazia isso em `_publish`. Criar grupo passou a fazer o mesmo. A aba fica montada no `StatefulShellRoute`, então o provider não se recria sozinho.
- **Motivo:** abrir Meus grupos, voltar à Home e criar um grupo deixava a aba com a lista antiga. A pessoa só via o grupo novo se a aba tivesse sido descartada.
- **Onde está no código:** `CreateGroupViewModel.submit` e `GroupDetailViewModel._publish`.
- **Como trocar depois:** se Meus grupos deixar de ficar montada, a invalidação continua correta. Um provider que escuta o repositório no lugar de `invalidate` pode substituir as duas chamadas.

## Detalhe da notícia aberto direto tem volta para a Home

- **Data:** 2026-10-27
- **Decisão:** `/news/:id` aberto sem pilha (deep link, ou `go`) mostra um botão que leva para a Home. Se a pessoa chegou pelo cartão, o voltar normal continua, porque há pilha.
- **Motivo:** sem pilha o AppBar não desenha voltar, e a notícia ficava sem saída.
- **Onde está no código:** `NewsDetailScreen`, botão `AppKeys.newsBackHome`.
- **Como trocar depois:** se o detalhe passar a abrir dentro do shell, o botão sai e a barra inferior volta a ser o caminho.

## Sem cidade salva, a Home abre em Curitiba

- **Data:** 2026-10-27
- **Decisão:** quando não há cidade salva, a cidade padrão é Curitiba, a primeira cidade do produto. Ela já entra selecionada na primeira abertura. O seletor continua visível para trocar. Uma escolha salva prevalece sobre Curitiba. A escolha é gravada com `shared_preferences` (na web, o localStorage do navegador), na chave `selected_city_id`. A ausência da chave, ou um valor vazio, significa Curitiba. O padrão não é gravado sozinho: só a troca feita pela pessoa. O valor é lido antes do primeiro frame, para a Home não piscar o aviso de escolher cidade.
- **Motivo:** no site publicado, abrir o app no celular sem cidade escolhida mostrava só “Escolha a cidade acima para ver os grupos / as novidades”. O feed não aparecia. O dono esperava ver Curitiba, como nos prints.
- **Onde está no código:** `SelectedCityStore` e `SelectedCityController`. O `main` chama `load` e coloca o store no `selectedCityStoreProvider` antes do `runApp`. `FindGroupsSection` e `NewsSection` leem essa cidade e não têm mais o aviso de cidade vazia.
- **Como trocar depois:** outra cidade padrão é a constante usada em `SelectedCityStore.resolve` (`SampleIds.curitiba`). Se a escolha passar a viver na conta, o store lê o perfil em vez do `shared_preferences`. A chave antiga pode ser ignorada.

## Salas em carrosséis na Home

- **Data:** 2026-10-28
- **Decisão:** substituída no mesmo dia pela seção “Ordem da Home e quadros inteiros”. O texto abaixo descreve a versão anterior. A Home mostrava as salas de escape da cidade selecionada em carrosséis horizontais, um por tema: Terror, Mistério, Aventura, Sci-fi, Steampunk e Egito. Tema sem sala na cidade não aparece. Cada seção tem o título e “Ver tudo”. O cartão tem a foto do tema, o nome da sala, o nome da casa, um pino desenhado no app (verde e cobre, não um emoji) com o nome da cidade, e dois botões: “Achar grupo” e “Criar grupo”. Achar grupo abre a lista de grupos daquela sala na cidade atual. Criar grupo abre o formulário com a casa e a sala já preenchidas; o horário continua vazio. A ordem da Home é: cidade, busca compacta de grupos, carrosséis de salas, feed de novidades. A busca continua acima porque achar gente para jogar segue sendo o gesto principal. Os carrosséis ficam no meio, antes das notícias, para a pessoa ver salas e em seguida o que mudou na cidade. A faixa do carrossel tem a altura do cartão mais alto daquele tema, já com o tamanho da fonte, sem uma faixa vazia fixa. No cartão, o pino e a cidade ficam à esquerda e os botões à direita, com o texto no tamanho desenhado e alvo de toque de pelo menos 48 px de altura. Se pino, cidade e botões não couberem na mesma linha, os botões descem para a linha de baixo; se os dois botões também não couberem lado a lado, um fica embaixo do outro. Cada tema que aparece numa cidade tem pelo menos duas salas, para o carrossel rolar. O botão “Criar grupo” da lista da sala não reutiliza a chave do cartão. Os ícones da barra e da Conta não repetem o nome que o texto ao lado já anuncia.
- **Motivo:** o dono pediu a descoberta no estilo de carrosséis, sem tirar a busca nem o feed. As fotos reaproveitam as figuras fictícias do feed. Aventura ganhou um arquivo novo em `assets/images/rooms/`, porque não havia uma figura desse tema. Tudo continua inventado.
- **Onde está no código:** `RoomCategory` em cada `EscapeRoom` de `sample_data.dart`. A Home usa `RoomCarouselsSection` e `roomCardHeight`. “Ver tudo” é `/rooms/category/:category`. “Achar grupo” é `/rooms/:roomId/groups`. “Criar grupo” do cartão é `/groups/new?roomId=`. O da lista da sala usa `AppKeys.roomGroupsCreate`. O pino é `ScapePinIcon`.
- **Como trocar depois:** um tema novo entra no enum, na ordem, no rótulo e na foto. Se a busca passar a ficar abaixo dos carrosséis, a troca é a ordem dos widgets em `HomeScreen`. Se a foto passar a ser por sala, o cartão deixa de ler `roomCategoryImage`.

## A Home começa pelos carrosséis

- **Data:** 2026-10-28
- **Decisão:** a ordem desta seção foi substituída no mesmo dia por “Ordem da Home e quadros inteiros”. O que segue vale para o que não mudou: o topo da Home fica baixo: “ScapeMatch” e a cidade na mesma linha, o aviso de dados de exemplo é um chip pequeno alinhado à esquerda, e não uma barra da largura da tela. A busca fica larga o bastante para o texto “Buscar sala ou casa”; quando essa linha não cabe, Criar grupo vira um botão + com o nome acessível “Criar grupo”. O chip Quase cheios continua abaixo. O subtítulo longo sai. A lista de grupos fica numa janela de altura fixa logo abaixo da busca. A barra de rolagem só aparece quando os cartões passam dessa altura. A busca, o chip Quase cheios, a cidade e o tipo de jogo filtram essa lista. Logo abaixo vêm os carrosséis, nesta ordem: Novidades (primário, no lugar em que o primeiro tema ficava), os dois primeiros temas com sala (secundários; em Curitiba, Terror e Mistério), o carrossel de promoções sem título de seção (só o flyer, setas e pontos), os temas restantes (terciários) e Salas mais procuradas. A ordem fictícia de procura está em `popularRoomRank`. Todo carrossel tem setas Anterior e Próximo, que somem na ponta e avançam com animação, além do arraste. Novidades, temas e Salas mais procuradas avançam a largura visível. As promoções avançam um flyer por vez (o cartaz mais o vão), para não pular um cartaz. Os pontos são um por parada que a seta alcança, contados pela largura do flyer desde o primeiro frame, e o último acende quando a faixa chega ao fim. Setas e pontos se recalculam quando a tela ou a fonte mudam. Novidades, temas e Salas mais procuradas têm “Ver tudo”. As promoções são quatro flyers fictícios e não aplicam desconto. Na tela de 390×844, com a barra inferior e sem inset extra de status, a faixa de Novidades cabe inteira. O Terror entra cortado: a foto e o título da primeira sala já aparecem. Isso passa de um terço do bloco, porque os botões do cartão ficam abaixo do título.
- **Motivo:** o dono pediu a densidade de apps como o Sympla e a Buser: o que se descobre (novidades e salas) entra na primeira tela, e a busca não empurra isso para baixo com uma lista longa.
- **Onde está no código:** `HomeScreen`, `NewsSection`, `RoomThemeSpan`, `PromoCarousel`, `PopularRoomsSection`, `ArrowCarousel` e `FindGroupsSection`. “Ver tudo” de novidades é `/news`. O das salas mais procuradas é `/rooms/popular`.
- **Como trocar depois:** outra ordem é a sequência em `HomeScreen`. Um ranking real substitui `popularRoomRank`. Se a promoção passar a valer no preço, o flyer deixa de ser só imagem e o repositório de grupos aplica a regra.

## Aba Conta

- **Data:** 2026-10-28
- **Decisão:** a lista e a carteira desta seção foram atualizadas em “Conta: carteira, cartões e saldo”. O que segue vale para o resto: a barra fica Home, Meus grupos, Conta. A Conta cumprimenta com “Olá,” e o nome do usuário atual. O exemplo é “Olá, Nícolas”. A engrenagem no topo abre Configurações. Cada destino é uma tela curta que diz que o dado é de exemplo. Nada disso cobra, paga ou grava um perfil de verdade.
- **Motivo:** o dono pediu um lugar de conta no espírito de um app de passagens, com o visual do ScapeMatch e os nomes adaptados (viajantes viram parceiros de jogo).
- **Onde está no código:** ramo 2 do `StatefulShellRoute` (`/account`), `AccountScreen` e `AccountDestinationScreen`. O nome vem de `currentUserProvider`.
- **Como trocar depois:** login de verdade substitui o provider. O saldo e os cartões seguem o plano em [PAGAMENTOS_PLANO.md](PAGAMENTOS_PLANO.md). Os textos de “fictício” saem dessas telas.
