# Pagamentos PagBank

O EscapeMatch cobra só pela PagBank, em produção (`https://api.pagseguro.com`). Sandbox só existe se `PAGBANK_ENV=sandbox`.

## O que o dinheiro faz

O pagamento fica retido até o grupo confirmar. Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado. A custódia (`custody.apply`, status HELD) segura a casa e a EscapeMatch. A confirmação chama `POST /splits/{id}/release-custody`. O Pix estornado pode sair do saldo HELD. O cartão nasce com `capture: false` e só é capturado na confirmação (até 29 dias).

A casa recebe a parte dela sobre o valor bruto, em centavos fixos. A taxa da PagBank sai só da comissão da conta primária (EscapeMatch). A comissão continua o campo por casa no Admin. Não há percentual fixo no código. Se a comissão for menor que a taxa, o saldo da conta primária cobre a diferença. A casa não é reduzida.

Cartão até 3x sem juros (a EscapeMatch absorve). De 4x a 12x o juros vai para o jogador, cotado em `GET /charges/fees/calculate`. Abaixo de R$ 150 (`minInstallmentAmountCents = 15000`) só cabe 1x. Pontos, indicação e cashback não mudam com o meio nem com as parcelas.

A PagBank não emite NFS-e. As linhas fiscais continuam `scheduled`. Nada chama a rede para nota.

## Segredos

Só por ambiente. Não commitar e não logar.

- `PAGBANK_TOKEN`: token da conta primária.
- `PAGBANK_ENV=production`.
- `PAGBANK_ACCOUNT_ID`: `ACCO_` da EscapeMatch. É quem paga as taxas.
- `PAGBANK_WEBHOOK_SECRET`: se vazio, a assinatura usa `PAGBANK_TOKEN`. Header `x-authenticity-token` = SHA-256 hex de `{segredo}-{corpo cru}`.
- `PAGBANK_CONNECT_CLIENT_ID`, `PAGBANK_CONNECT_CLIENT_SECRET`.
- `PAGBANK_CONNECT_REDIRECT_URI`: `https://parceiro.escapematch.com.br/pagbank/retorno`. O host tem de servir o `index.html` do Parceiro nesse caminho.
- `PAGBANK_CONNECT_ADMIN_REDIRECT_URI`: `https://admin.escapematch.com.br/pagbank/retorno`, se o Admin também abre o Connect. Sem ela, o Admin usa a URI do Parceiro.
- `PAGBANK_POINTS_RESERVE_ACCOUNT_ID` e `PAGBANK_POINTS_RESERVE_TOKEN`, se a reserva de pontos tiver conta própria.

Transferência Pix em produção pode exigir mTLS. O certificado não entra no repositório.

## Ordem para publicar

Não aplicar isto daqui. O dono aprova.

1. Migration `20261123190000_pagbank.sql` no projeto `eujlhicairvksvmssruz`. Ela só adiciona colunas, gatilhos e funções. Não apaga coluna nem tabela.
2. Segredos acima.
3. Funções, nesta ordem: `pagbank-webhook`, `pagbank-connect`, `create-charge`, `settle-charges`, `tokenize-card`, `provision-venue-wallet`, `venue-payouts`, `payments-readiness`, `reconcile-payments`, `ledger-reconcile`.
4. Cadastrar a URL do `pagbank-webhook` no painel. Só então despublicar `asaas-webhook` e `asaas-transfer-webhook`.

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

A migration nova ainda cita os nomes antigos porque o gatilho copia os dois lados e as funções históricas leem a coluna antiga. Um drop fica para uma migration seguinte, depois que produção estiver estável na PagBank. Não entra neste PR.

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
