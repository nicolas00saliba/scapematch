# Pagamentos PagBank

O EscapeMatch cobra só pela PagBank, em produção (`https://api.pagseguro.com`). Sandbox só existe se `PAGBANK_ENV=sandbox`.

## O que o dinheiro faz

O Pix interbancário nasce em `charges[].payment_method.type = PIX`, com `pix.expiration_date` e split FIXED em custódia HELD. O objeto `qr_codes` do pedido é o QR da carteira PagBank (`arrangements: PAGBANK`), não o copia-e-cola. A cobrança guarda o id do pedido (`ORDE_`) e o texto do QR (`charges[].qr_code.text`). O status sai de `GET /orders/{id}`. O webhook casa o id do pedido e lê `charges[]` do pedido pago. A custódia solta pelo `splits.id` desse charge. Captura e cancelamento mandam `amount.value`. Pix que passa de `expiration_date` ainda em `WAITING` sai da fila como cancelado, para não travar a consulta.

O pagamento fica retido até o grupo confirmar. Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado. A captura do cartão continua na confirmação do grupo. A custódia (`custody.apply`, status HELD) segura a casa e a EscapeMatch até o horário da sessão. A liberação chama `POST /splits/{id}/custody/release` em `https://api.pagseguro.com`, com `receivers[].account.id` da casa e da EscapeMatch, só quando `now()` alcança o `starts_at` da sessão (`room_sessions.starts_at`; se a sessão não tem horário, `groups.starts_at`). O host não é o do Connect. A resposta vazia 200 encerra a liberação. Sem `release.scheduled`, a PagBank solta sozinha em 90 dias. Sessão cancelada ou cobrança estornada não chama o release; o estorno na PagBank precisa concluir antes desses 90 dias, senão o split cai nas contas mesmo assim. A soma dos `amount.value` do split FIXED é o valor cobrado. O detalhe das páginas da Priscila está em [pagbank-cadastro.md](pagbank-cadastro.md). O cartão grava o `splitId` na captura e não solta a custódia antes do horário. Se a liberação falha, a cobrança guarda `custody_release_failed_at` e soma `custody_release_attempts`. `reconcile-payments` (a cada 5 minutos) e `settle-charges` tentam de novo, do mais antigo, só com o grupo confirmado e a sessão já iniciada, e param depois de 8 falhas com o alerta `custody_release_exhausted`. Uma tentativa antes do horário não conta. Pix pago com o grupo confirmado também espera o horário. O estorno parcial (valor pago menos a taxa PagBank, no Pix e no cartão capturado; autorização não capturada cancelada por inteiro) e o bloqueio nas 2 horas anteriores ao início continuam iguais. Cada pedido manda `notification_urls` com a URL do `pagbank-webhook`. A consulta periódica relê o Pix pendente na PagBank e aplica o mesmo caminho. O Pix estornado pode sair do saldo HELD. O cartão nasce com `capture: false` e só é capturado na confirmação (até 29 dias).

Sair no prazo da sala (`cancel_window_minutes`, padrão 120) ou ser removido pelo organizador enfileira o estorno daquela cobrança. Cobrança paga que não entra na fila fica `refund_pending`, nunca `refunded`. O app chama `settle-charges` com `member_refund` em seguida. Esse caminho e o acerto de um grupo só processam a fila daquele ator: a cobrança dele, ou a do grupo se for o organizador e `maySettle` passar. O lote inteiro fica no cron `reconcile-payments` ou na varredura do admin com sessão aal2. `claim_member_refunds` pega a linha com `for update skip locked`, marca `processing` e segura um lease de 90 segundos. O prazo vencido volta para `queued`. O cliente corta a PagBank em 8 segundos, dentro do lease. Se o GET ainda mostrar a cobrança paga, o worker não manda outro cancelamento antes de um lease novo e de uma nova leitura. `refund_status` fica `refund_pending` e só vira `refunded` quando a PagBank confirma, pelo webhook ou pela reconciliação. A referência [Cancelar pagamento](https://developer.pagbank.com.br/reference/cancelar-pagamento) (`POST /charges/{id}/cancel`) não lista header de idempotência. `x-idempotency-key` está em [Criar estorno de pagamento](https://developer.pagbank.com.br/reference/criar-estorno-de-pagamento), o estorno de pagamento recorrente (`PAYM_`), não neste cancelamento. O catálogo de erros de Pedidos cita `40005 idempotency_key_in_use` sem nomear o header do cancelamento. O estorno individual não manda esse header. Pix pago usa estorno. Cartão autorizado e não capturado é cancelado por inteiro, sem captura. Pix pago e cartão capturado devolvem o valor pago menos a taxa PagBank; os juros, quando existem, já estão nesse valor pago. A fila é idempotente: a repetição relê a cobrança e não estorna de novo se ela já voltou. Com a custódia ainda HELD, `refund_requested_at` impede `custody/release`: a parte da casa e a da EscapeMatch não são liberadas, e o estorno devolve o saldo retido. Com a custódia já liberada, o mesmo cancelamento na PagBank desfaz as duas partes. Não há transferência extra da EscapeMatch para cobrir a casa. Se a PagBank recusar, a fila continua aberta e o membro não fica `refunded`. O mesmo caminho de estorno desfaz indicação, cashback e pontos daquela cobrança.

A casa recebe a parte dela sobre o valor bruto, em centavos fixos. A taxa da PagBank sai só da comissão da conta primária (EscapeMatch). A comissão continua o campo por casa no Admin. Não há percentual fixo no código. Se a comissão for menor que a taxa, o saldo da conta primária cobre a diferença. A casa não é reduzida.

O cron `ledger-reconcile` (08:30 em Brasília) lê `GET /accounts/balance` com o token da conta primária, a mesma leitura de `financeBalanceCents`. A página [Balance](https://developer.pagbank.com.br/v1/reference/balance) não diz se o número é real ou centavo; o pedido usa centavos só em `amount.value` de outra API. O saldo da conta é sempre real decimal: 12 e 12.50 viram 1200 e 1250 centavos. Fração de centavo ou o formato `amount.value` gera o aviso `balance_shape`, sem o valor no log. Saldo negativo também alerta. Se o saldo disponível fica abaixo de `platform_settings.low_balance_alert_cents` (padrão 100000 centavos, R$ 1.000), sai o alerta `pagbank-balance` / `low_balance` pelo canal operacional, só com escopo e código. No limite e acima, não alerta. Não há tela no Admin para esse número: a coluna é o controle. `PAGBANK_CAC_TRANSFERS` continua desligada. Esta consulta não pede transferência.

Cartão no máximo 3x, sempre sem juros (a EscapeMatch absorve), em qualquer valor. 4x ou mais é recusado no app e no `create-charge`. A PagBank exige pelo menos R$ 5 por parcela (`minInstallmentParcelCents = 500`); à vista não usa esse piso. A regra está em [Criar pedido com repasse de taxa ao comprador](https://developer.pagbank.com.br/reference/criar-transacao-com-repasse-de-taxa). Abaixo disso a opção fica desabilitada com "parcela mínima de R$ 5" e a cobrança responde `parcelas`. O app do jogador mostra a grade de 1x a 3x e manda `installments`. `create-charge` com `action: quote_installments` devolve o cardápio sem cobrar, só entre R$ 1 e R$ 5.000 e no máximo 20 cotações por usuário a cada 10 minutos (`cotacao_limite`). Na cobrança o servidor recusa 4x ou mais (`parcelas`) e grava `charged_amount_cents` e `buyer_interest_cents`. Se o valor reservado mudar no meio de um plano de 4x ou mais, a resposta é `valor_parcelas` e não há segunda autorização. Captura e cancelamento usam esse total, não só o principal. Pontos, indicação e cashback não mudam com o meio nem com as parcelas. O app Parceiro não guarda dados bancários: `save_bank` e `save_schedule` respondem `dados_bancarios_recusados`.

A PagBank não emite NFS-e. As linhas fiscais continuam `scheduled`. Nada chama a rede para nota.

## Segredos

Só por ambiente. Não commitar e não logar.

Obrigatórios:

- `PAGBANK_TOKEN`: token da conta primária. A assinatura do webhook é SHA-256 hex de `{token}-{corpo cru}`.
- `PAGBANK_ENV=production`. A base da API sai daqui: produção é `https://api.pagseguro.com`. Sandbox só com `PAGBANK_ENV=sandbox`.
- `PAGBANK_ACCOUNT_ID`: `ACCO_` da EscapeMatch. É quem paga as taxas.
- `PAGBANK_CONNECT_CLIENT_ID`, `PAGBANK_CONNECT_CLIENT_SECRET`.
- `PAGBANK_CONNECT_REDIRECT_URI`: `https://parceiro.escapematch.com.br/pagbank/retorno`. O host tem de servir o `index.html` do Parceiro nesse caminho.

Opcionais:

- `PAGBANK_WEBHOOK_SECRET`: só se a assinatura tiver de usar outro segredo no lugar do `PAGBANK_TOKEN`. Pode ser igual ao token.
- `PAGBANK_CONNECT_ADMIN_REDIRECT_URI`: `https://admin.escapematch.com.br/pagbank/retorno`, se o Admin também abre o Connect. Sem ela, o Admin usa a URI do Parceiro.
- `PAGBANK_POINTS_RESERVE_ACCOUNT_ID` e `PAGBANK_POINTS_RESERVE_TOKEN`, se a reserva de pontos tiver conta própria.
- `PAGBANK_ROOT_WALLET_ID`: conta que recebe a sobra da reserva de pontos. Sem ela, essa perna não sai.

Não gravar:

- `PAGBANK_BASE_URL`: não escolhe o host.
- `PAGBANK_WEBHOOK_EMAIL`: a PagBank não pede e-mail no webhook de Pedidos. O saque está desligado e não cadastra webhook.

O saque pelo EscapeMatch continua desligado (`venuePayoutsForcedOff`). A casa recebe na conta PagBank do Connect. O valor fica disponível na conta PagBank da casa. O Pix para outro banco é manual, no app do PagBank. A tela do Parceiro explica isso e não pede dados bancários. `venue_finance_ready` é aprovada, não suspensa e com `pagbank_account_id`. Não exige `venue_bank_accounts`.

O cadastro da conta da casa está em [pagbank-cadastro.md](pagbank-cadastro.md). Enquanto a API de Cadastro não estiver liberada, a casa cria a conta em `https://cadastro.pagbank.com.br/` e conecta pelo fluxo abaixo.

## Ordem para publicar

Não aplicar isto daqui. O dono aprova.

1. Migrations no projeto `eujlhicairvksvmssruz`, nesta ordem: `20261124124058_pagbank.sql` e `20261124124107_venue_ready_without_bank.sql`. As duas só substituem funções e acrescentam. Não apagam coluna nem tabela. A segunda tira `venue_bank_accounts` de `venue_finance_ready` e de `list_due_venue_payouts`.
2. Segredos acima.
3. As 17 funções do mesmo commit: `pagbank-webhook`, `pagbank-transfer-webhook`, `pagbank-connect`, `create-charge`, `settle-charges`, `tokenize-card`, `provision-venue-wallet`, `venue-payouts`, `payments-readiness`, `reconcile-payments`, `ledger-reconcile`, `cancel-house-group`, `configure-venue-fiscal`, `schedule-venue-withdrawals`, `venue-documents`, `invoice-document`, `venue-claim`. `invoice-document` importa `_shared/pagbank_client_error.ts` e `_shared/http.ts`. `venue-claim` importa `_shared/http.ts` e `_shared/venue_claim.ts`.
4. Não depende do painel. Cada pedido já manda `notification_urls` para `pagbank-webhook`, e `reconcile-payments` relê o Pix pendente. Só então despublicar `asaas-webhook` e `asaas-transfer-webhook`.

## Connect da casa

`provision-venue-wallet` devolve `connect_url`. A casa autoriza em `https://connect.pagbank.com.br/oauth2/authorize` com os escopos `payments.read payments.create payments.refund accounts.read`. O `state` é aleatório, vale 10 minutos, só serve uma vez e fica preso ao usuário que pediu o link. O Parceiro e o Admin leem `code` e `state` em `/pagbank/retorno` e chamam `pagbank-connect`. A função confere o state, grava `pagbank_account_id` e cifra o access token e o refresh token. Não cria subconta. Casa que já tinha carteira antiga fica sem conta PagBank até passar por esse fluxo.

O access token é renovado quando falta menos de dois minutos para vencer, e de novo se a PagBank responde 401.

## Primeira cobrança de R$ 5

1. Casa com Connect ligado e comissão digitada no Admin.
2. Grupo de teste. Pix de R$ 5. Conferir QR, split fixo da casa sobre o bruto e custódia HELD.
3. Confirmar o grupo. O cartão captura. A custódia continua HELD até o horário da sessão. O cron libera quando esse horário chega e a casa recebe os centavos combinados.
4. Outro grupo. Não confirmar. O Pix é estornado. O cartão autorizado não é capturado.
5. Cartão de R$ 5 em 1x. Sem juros no pagador.
6. Cartão de qualquer valor: 3x sem juros do pagador; 4x mostra o juro cotado. Parcela abaixo de R$ 5 fica desabilitada.

## Colunas antigas

A migration nova ainda cita os nomes antigos. Depois do Connect, o gatilho espelha a conta PagBank na coluna antiga, para o SQL que ainda a lê. Ela não copia id nem chave do Asaas para a PagBank. Casa que já existia fica desligada até passar pelo Connect. Um drop fica para uma migration seguinte, depois que produção estiver estável na PagBank. Não entra neste PR.

O harness local e o teste do allowlist do Vault continuam plantando o segredo `asaas_subaccount_key`. A migration `20261105220000` lê esse nome. Renomeá-lo no teste faria a cadeia histórica falhar.

Migrations históricas que continuam com o nome antigo, porque reescrevê-las quebra a cadeia:

- `20261104120000_init.sql`
- `20261104120100_helpers.sql`
- `20261104120400_asaas.sql`
- `20261104120500_privacy.sql`
- `20261104120600_fiscal_terms.sql`
- `20261105113000_private_security_definer.sql`
- `20261105140000_saved_cards.sql`
- `20261105160000_card_token_crypto.sql`
- `20261105190000_wallet_commission_payout.sql`
- `20261105191000_player_cpf.sql`
- `20261105210000_ledger_charge_kind_direction.sql`
- `20261105220000_subaccount_key_wallet.sql`
- `20261108140000_scape_points.sql`
- `20261108200000_split_fixed_value.sql`
- `20261109120000_rewards_rules.sql`
- `20261109160000_admin_console.sql`
- `20261111162429_admin_aal2_remaining.sql`
- `20261112133908_20261111183000_free_slot_points.sql`
- `20261112182929_venue_withdrawals.sql`
- `20261112182936_venue_payout_corrections.sql`
- `20261113170000_admin_payments.sql`
- `20261113190000_ledger_reconcile.sql`
- `20261113193000_customer_company_type.sql`
- `20261113194000_company_type_guard.sql`
- `20261113200000_venue_claim_official.sql`

E a própria `20261124124058_pagbank.sql`.
