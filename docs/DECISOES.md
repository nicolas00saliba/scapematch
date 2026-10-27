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
- **Decisão:** a tela inicial deixa de ser três cartões grandes. Em cima fica a busca de grupo, mais curta: cidade bem visível, campo “Buscar sala ou casa”, filtro Quase cheios, atalho Criar grupo e cartões de grupo com menos linhas. Logo abaixo, o feed de novidades. Os dois seguem a mesma cidade. Sem cidade, nenhum dos dois lista o Brasil inteiro. A rota antiga `/groups` volta para `/`.
- **Motivo:** o dono pediu a busca na própria Home, comprimida, e o feed no mesmo scroll. Um destino separado para “encontrar grupo” repetiria a tela.
- **Onde está no código:** `HomeScreen`, `FindGroupsSection`, `NewsSection`. O texto da busca filtra em memória (`filterGroupsByText`); não cria outro método no `GroupRepository`. O cartão da lista não mostra mais preço, presenças confirmadas nem a barra de progresso. Isso continua no detalhe e em Meus grupos.
- **Como trocar depois:** se a busca voltar a ser uma tela só dela, a seção sai da Home e a rota `/groups` deixa de redirecionar. Se o preço precisar aparecer no cartão, ele volta para `GroupCard`. O atalho Criar grupo pode sair se a barra ganhar um botão de criar.

## Barra inferior: Home à esquerda, Meus grupos à direita

- **Data:** 2026-10-27
- **Decisão:** a barra tem só dois destinos, nesta ordem: Home, Meus grupos. A ordem final é Home à esquerda e Meus grupos à direita. O dono mudou de ideia no mesmo dia: a primeira versão desta decisão punha Meus grupos à esquerda. O app continua abrindo na Home. Cada aba guarda o próprio scroll. Criar grupo, o detalhe do grupo e o detalhe da notícia abrem por cima da barra, com voltar. Não há terceira aba nesta versão. O rótulo da aba é “Home”, a palavra que o dono usou.
- **Motivo:** Meus grupos precisava de um lugar fixo, sem misturar o histórico com a busca. Duas abas bastam para o que existe hoje. A posição à direita foi o pedido final do dono.
- **Onde está no código:** `StatefulShellRoute.indexedStack` em `lib/app/router.dart` e `AppShell`. O ramo 0 é `/` (Home). O ramo 1 é `/groups/mine`.
- **Como trocar depois:** uma aba nova entra como outro `StatefulShellBranch`, na posição em que deve aparecer. Se o nome da aba passar a ser “Início”, muda o `label` da `NavigationDestination`.

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
