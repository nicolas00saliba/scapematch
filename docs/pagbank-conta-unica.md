# Conta PagBank única por casa

A conta PagBank é da casa e fica no servidor (`venues.pagbank_account_id` e o
token em `venue_pagbank_tokens`). Nada dela fica no aparelho, no
`localStorage` ou na sessão. Qualquer login do dono, em qualquer aparelho, lê a
mesma conta pelo RPC `venue_pagbank_account_view`.

## Regras

- Uma conta por casa. Conectar outra conta com uma já ligada devolve **409**
  (`pagbank_account_exists`) e não muda nada.
- A mesma conta não liga a duas casas reais. Conectar uma conta que já é de
  outra casa devolve **409** (`pagbank_account_in_use`) e não grava nada. Vale
  também para duas conexões ao mesmo tempo (o índice único
  `venues_pagbank_account_real_uidx` decide). Casas de teste ficam de fora.
- A mesma conta não liga a duas casas reais. Conectar uma conta que já é de
  outra casa devolve **409** (`pagbank_account_in_use`) e não grava nada. Vale
  também para duas conexões ao mesmo tempo (o índice único
  `venues_pagbank_account_real_uidx` decide). Casas de teste ficam de fora.
- Trocar de conta é o Admin desconectar (`pagbank-disconnect`) e o dono
  conectar de novo. A desconexão recusa (409 `pagbank_in_flight`) se houver
  saque pendente ou cobrança a caminho para a conta atual. "A caminho" é:
  reserva `creating` ou `pending` com menos de 1 dia, `authorized` com menos de
  7 dias, ou `paid` **com split**, custódia ainda não solta, sem estorno e sem
  estorno pedido. Cobrança paga sem split, já liquidada, estornada ou velha
  não trava a troca.
- Desconectar e reservar não se atropelam. A reserva (`payment_charges` com
  status `creating` e conta `ACCO_...`) lê a casa com `FOR SHARE` e é
  recusada com 409 (`pagbank_account_changed`) se a conta mudou ou saiu; o
  disconnect trava a casa com `FOR UPDATE`. Nenhum split sai para a conta
  antiga depois do disconnect.
- A criação de cobrança falha fechada: erro ou resposta ilegível na checagem
  da conta também devolvem 409 e não cobram.
- Ao desconectar, e ao recusar uma conexão (409), as funções revogam no
  PagBank o token que a casa deixa de usar (`POST /oauth2/revoke`), em melhor
  esforço: se o PagBank recusar, só registram um aviso sem token, e o fluxo
  segue. O script SQL da Ninja não consegue chamar a API: o token dela é
  apagado sem revogar. Quem quiser cortar o acesso de verdade revoga no app do
  PagBank.
- A tela mostra o nome da casa, o banco (PagBank), o final da conta e o
  CPF/CNPJ **da casa** (cadastro do EscapeMatch, mascarado). O PagBank só
  devolve o id da conta na conexão, então não há "titular" verificado e a tela
  não usa esse rótulo.
- Conectar a mesma conta de novo só renova o token (botão "Renovar
  autorização").
- O token guarda a conta a que pertence (`venue_pagbank_tokens.account_id`). Se
  a conta da casa e a do token divergirem, `venue_pagbank_binding` devolve
  `ambiguous`: o repasse (`venue-payouts`, `schedule-venue-withdrawals`), a
  liberação de custódia (`settle-charges`) e a criação de cobrança param e
  alertam (`pagbank-payout` / `pagbank-custody`, códigos `conta_ambigua`,
  `token_sem_conta`, `conta_ilegivel`). Não escolhem conta.
- **Só o Admin (com MFA) desconecta** (decisão do Nícolas, 26/11 16:20 BRT):
  `ownerMayDisconnect = false` em `_shared/pagbank_binding.ts`, espelhado em
  `partnerOwnerMayDisconnect` no Parceiro. O dono não vê botão de trocar; a
  tela diz "Para trocar a conta PagBank, fale com o suporte". A função
  `pagbank-disconnect` devolve 403 ao dono antes de ler token ou chamar o RPC.
  O Admin ainda não tem botão: a troca é chamando `pagbank-disconnect` com a
  sessão do Admin (MFA) ou com um script SQL como o da Ninja.
- Auditoria em `admin_audit_log` (`connect_pagbank`, `disconnect_pagbank`), só
  com os 4 últimos caracteres da conta.

## Ordem do deploy (produção)

Só com o ok do Nícolas, passo a passo.

1. Merge do PR. Merge não aplica nada no banco.
2. `supabase/ops/20261126_desativar_pagbank_ninja.sql`: desconecta a Ninja
   (conta final 13CA) e grava o histórico na auditoria (só os 4 últimos
   dígitos, nunca a conta inteira).
3. Migration `20261126170000_pagbank_conta_unica.sql`. Ela falha, sem alterar
   nada, se achar conta repetida entre casas ou token sem conta na casa.
4. Functions, todas do mesmo commit (as que importam os módulos alterados):
   `pagbank-connect`, `pagbank-disconnect` (nova), `provision-venue-wallet`,
   `create-charge`, `settle-charges`, `reconcile-payments`, `pagbank-webhook`,
   `venue-payouts`, `schedule-venue-withdrawals`, `pagbank-transfer-webhook`,
   `venue-documents`, `venue-pagbank-balance`, `pagbank-signup`,
   `pagbank-signup-probe`.
5. Deploy web do Parceiro e do Admin (reais e demos).
6. O dono conecta a conta pelo Parceiro (Saques > Entrar com PagBank). Conferir
   a tela e rodar o roteiro abaixo.

**A migration vem antes das functions**: as functions novas chamam RPCs que a
migration cria (`connect_venue_pagbank`, `disconnect_venue_pagbank`,
`venue_pagbank_binding`), e a trava de reserva também mora nela. A desativação antes da migration: a casa fica sem conta e sem token, e a
migration não encontra nada para recusar.

## Roteiro: reserva simulada (sem cobrança real)

Local, sem tocar produção:

1. `bash supabase/tests/run_local.sh` (com `DATABASE_URL`). O teste
   `tests/pagbank_conta_unica.sql` conecta, mostra a conta nos dois logins,
   recusa a segunda, desconecta, conecta outra e confere que
   `venue_payout_wallet` (a conta do repasse) é a nova.
2. `deno test --allow-read supabase/functions`. O teste "reserva simulada"
   monta o split de R$ 100,00 e mostra o recebedor "Repasse da casa" na conta
   da casa, nunca na antiga.

Demo ou sandbox, com conta de teste:

1. Na demo (ou no projeto `escapematch-sandbox`), com a casa de teste
   desconectada, tente reservar: a cobrança é recusada ("A casa ainda não tem
   subconta PagBank").
2. Conecte a conta de teste da casa. Abra o Parceiro por outro aparelho ou
   janela anônima, entre na mesma conta: a mesma conta aparece, sem botão de
   conectar.
3. Tente conectar outra conta: o retorno mostra a mensagem do 409.
4. Faça a reserva de teste (conta PagBank sandbox, nada real). Confira em
   `payment_charges.wallet_id` e no corpo do split enviado ao sandbox que o
   recebedor da casa é a conta conectada no passo 2.
