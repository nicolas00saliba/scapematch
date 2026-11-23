# Pagamentos PagBank

O EscapeMatch cobra só pela PagBank, em produção (`https://api.pagseguro.com`). Sandbox só existe se `PAGBANK_ENV=sandbox`.

## O que o dinheiro faz

O Pix interbancário nasce em `charges[].payment_method.type = PIX`, com `pix.expiration_date` e split FIXED em custódia HELD. O objeto `qr_codes` do pedido é o QR da carteira PagBank (`arrangements: PAGBANK`), não o copia-e-cola. A cobrança guarda o id do pedido (`ORDE_`) e o texto do QR (`charges[].qr_code.text`). O status sai de `GET /orders/{id}`. O webhook casa o id do pedido e lê `charges[]` do pedido pago. A custódia solta pelo `splits.id` desse charge. Captura e cancelamento mandam `amount.value`. Pix que passa de `expiration_date` ainda em `WAITING` sai da fila como cancelado, para não travar a consulta.

O pagamento fica retido até o grupo confirmar. Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado. A custódia (`custody.apply`, status HELD) segura a casa e a EscapeMatch. A confirmação chama `POST /splits/{id}/release-custody`. O cartão grava o `splitId` da autorização e solta a custódia também na captura imediata, quando o grupo já confirmou. Se a liberação falha, a cobrança guarda `custody_release_failed_at` e soma `custody_release_attempts`. `settle-charges` e `reconcile-payments` tentam de novo, do mais antigo, só com o grupo já confirmado, e param depois de 8 falhas com o alerta `custody_release_exhausted`. Pix pago depois da confirmação solta a custódia no webhook. Cada pedido manda `notification_urls` com a URL do `pagbank-webhook`. A consulta periódica relê o Pix pendente na PagBank e aplica o mesmo caminho. O Pix estornado pode sair do saldo HELD. O cartão nasce com `capture: false` e só é capturado na confirmação (até 29 dias).

A casa recebe a parte dela sobre o valor bruto, em centavos fixos. A taxa da PagBank sai só da comissão da conta primária (EscapeMatch). A comissão continua o campo por casa no Admin. Não há percentual fixo no código. Se a comissão for menor que a taxa, o saldo da conta primária cobre a diferença. A casa não é reduzida.

Cartão até 3x sem juros (a EscapeMatch absorve). De 4x a 12x o juros vai para o jogador, cotado em `GET /charges/fees/calculate`. Abaixo de R$ 150 (`minInstallmentAmountCents = 15000`) só cabe 1x. Pontos, indicação e cashback não mudam com o meio nem com as parcelas.

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

O saque da casa fica desligado no código (`venue_payouts_enabled` não liga transferência) até um PR próprio. No Parceiro, a aba Saques explica que o dinheiro cai na conta PagBank da casa e pode ser sacado pelo aplicativo do PagBank. A doc de transferência pede liberação comercial, mTLS e `notification_urls` no próprio POST. O cadastro antigo, com `authToken`, e-mail e `TRANSFER_*`, não é usado.

## Ordem para publicar

Não aplicar isto daqui. O dono aprova.

1. Migration `20261123190000_pagbank.sql` no projeto `eujlhicairvksvmssruz`. Ela só adiciona colunas, gatilhos e funções. Não apaga coluna nem tabela.
2. Segredos acima.
3. As 17 funções do mesmo commit: `pagbank-webhook`, `pagbank-transfer-webhook`, `pagbank-connect`, `create-charge`, `settle-charges`, `tokenize-card`, `provision-venue-wallet`, `venue-payouts`, `payments-readiness`, `reconcile-payments`, `ledger-reconcile`, `cancel-house-group`, `configure-venue-fiscal`, `schedule-venue-withdrawals`, `venue-documents`, `invoice-document`, `venue-claim`. `invoice-document` importa `_shared/pagbank_client_error.ts` e `_shared/http.ts`. `venue-claim` importa `_shared/http.ts` e `_shared/venue_claim.ts`.
4. Não depende do painel. Cada pedido já manda `notification_urls` para `pagbank-webhook`, e `reconcile-payments` relê o Pix pendente. Só então despublicar `asaas-webhook` e `asaas-transfer-webhook`.

## Connect da casa

`provision-venue-wallet` devolve `connect_url`. A casa autoriza em `https://connect.pagbank.com.br/oauth2/authorize` com os escopos `payments.read payments.create payments.refund accounts.read`. O `state` é aleatório, vale 10 minutos, só serve uma vez e fica preso ao usuário que pediu o link. O Parceiro e o Admin leem `code` e `state` em `/pagbank/retorno` e chamam `pagbank-connect`. A função confere o state, grava `pagbank_account_id` e cifra o access token e o refresh token. Não cria subconta. Casa que já tinha carteira antiga fica sem conta PagBank até passar por esse fluxo.

O access token é renovado quando falta menos de dois minutos para vencer, e de novo se a PagBank responde 401.

## Primeira cobrança de R$ 5

1. Casa com Connect ligado e comissão digitada no Admin.
2. Grupo de teste. Pix de R$ 5. Conferir QR, split fixo da casa sobre o bruto e custódia HELD.
3. Confirmar o grupo. A custódia libera. A casa recebe os centavos combinados.
4. Outro grupo. Não confirmar. O Pix é estornado. O cartão autorizado não é capturado.
5. Cartão de R$ 5 em 1x. Sem juros no pagador.
6. Valor acima de R$ 150: 3x sem juros do pagador; 4x mostra juros.

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

E a própria `20261123190000_pagbank.sql`.
