# Woovi e Mercado Pago

O provedor anterior saiu do código em 20/11/2026. Não há flag e não há reserva. Pix novo vai para a Woovi. Cartão novo vai para o Mercado Pago. Este agente não aplica migration no projeto remoto, não publica Edge Function, não apaga segredo e não cria conta na Woovi nem no Mercado Pago.

Cobrança antiga com `payment_charges.provider = 'asaas'` fica só leitura. O código não captura, não estorna e não muda o status dela. Dinheiro ainda preso na conta antiga precisa de ação manual no painel daquele provedor.

Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.

A NFS-e continua pendente. Nenhuma função emite nota em provedor de pagamento.

## Janela de 5 dias do cartão

A reserva do Mercado Pago (`POST /v1/payments` com `capture=false`) dura 5 dias. A escolha é só reservar perto da decisão do grupo, sem reautorizar.

Reautorizar abriria uma segunda reserva. Se o cancelamento da primeira falhasse, o jogador ficaria com dois bloqueios. O token nasce no aparelho (MercadoPago.js ou SDK) e o número do cartão não passa pelo servidor, então não há token guardado para uma segunda tentativa silenciosa.

A autorização só é pedida quando falta no máximo 4 dias e 12 horas para `closes_at` (ou `starts_at`, se o grupo não tem `closes_at`). A margem de 12 horas deixa a captura, na hora da decisão, ainda dentro dos 5 dias. Antes disso `create-charge` responde `card_hold_deferred` com `authorize_at` e não chama o Mercado Pago.

## O que cada provedor faz

Woovi, header `Authorization` com o APP_ID, sem `Bearer`. Base de sandbox: `https://api.woovi-sandbox.com`.

| Ação | Chamada |
| --- | --- |
| Cobrança com split | `POST /api/v1/charge`. `splits[].splitType` é `SPLIT_SUB_ACCOUNT` e `pixKey` é a subconta da casa. A diferença fica na conta principal. |
| Subconta | `POST /api/v1/subaccount` com `name` e `pixKey` |
| Saldo | `GET /api/v1/subaccount/{pixKey}` |
| Saque | `POST /api/v1/subaccount/{pixKey}/withdraw` |
| Estorno | `POST /api/v1/refund` com `transactionEndToEndId` |
| Débito da casa | `POST /api/v1/subaccount/{pixKey}/debit` depois do estorno, porque o reembolso sai da conta principal |

O saldo que a Woovi devolve é tratado como centavos, no mesmo contrato de `value` da cobrança. Confirmar com a conta sandbox.

Mercado Pago, mesma API de sandbox e produção (`https://api.mercadopago.com`). O ambiente é `MP_ENV=sandbox` ou `MP_ENV=production`. Sem a variável, ou com outro valor, vale produção. A aplicação de teste do painel entrega o access token com prefixo `APP_USR-`. `TEST-` continua sinal de sandbox quando `MP_ENV` não está definida.

| Ação | Chamada |
| --- | --- |
| Reserva | `POST /v1/payments` com `capture=false`, `application_fee` em reais e o `access_token` OAuth da casa |
| Captura | `PUT /v1/payments/{id}` com `capture=true` |
| Cancelamento da reserva | `PUT /v1/payments/{id}` com `status=cancelled` |
| Estorno | `POST /v1/payments/{id}/refunds`. Parcial manda `amount` em reais |
| Renovação | `POST /oauth/token` com `grant_type=refresh_token`, quando faltam menos de 30 dias para os 180 |

O webhook da Woovi aceita `x-openpix-signature` (HMAC SHA-256 do corpo cru, segredo `WOOVI_WEBHOOK_SECRET`) ou `x-webhook-signature` (RSA SHA-256 com a chave pública). Sem uma das duas, a função responde 401. O webhook do Mercado Pago exige `x-signature` e `x-request-id`. O manifest é `id:<data.id em minúsculas>;request-id:<x-request-id>;ts:<ts>;`, HMAC SHA-256 com `MP_WEBHOOK_SECRET`.

Os dois gravam o evento em `provider_webhook_events` só quando o processamento termina. Se a função responde 500, a linha do evento é apagada e o reenvio entra de novo. A segunda entrega de um evento já processado responde ok e não mexe no livro. `in_process` e `pending` do Mercado Pago ficam pendentes. Chargeback grava `charged_back`, sem `refunded_at`.

O `state` do OAuth do Mercado Pago é `v1.<casa>.<expira>.<nonce>.<hmac>`, vale 10 minutos e é conferido no callback. Sem o token OAuth da casa, o webhook e a captura usam `MP_ACCESS_TOKEN` só quando `MP_ENV=sandbox`, ou quando a variável está vazia e o token começa com `TEST-`. Em produção a função responde 500 e registra `oauth_da_casa_ausente`.

O build real do Parceiro está em `https://parceiro.escapematch.com.br/`. O valor exato de `MP_OAUTH_REDIRECT_URI` é `https://parceiro.escapematch.com.br/mp-retorno`. Cadastre essa URL igual na aplicação do Mercado Pago, sem barra no fim e sem query. A rota `/mp-retorno` lê `code` e `state`, chama `mp-oauth` com `action` `callback` e grava o token da casa. `error=access_denied` não grava token. A demonstração em `parceiro-demo` não usa esse valor.

## Saque da casa

O EscapeMatch Parceiro mostra o líquido do livro da casa, não o saldo da subconta. O botão saca no máximo esse líquido menos saques pendentes e concluídos. O Pix de grupo ainda não confirmado não entra no livro, então não entra no saque. Dois saques ao mesmo tempo travam a conta da casa (`SELECT ... FOR UPDATE` e advisory lock). O saque automático, com `auto_withdraw` na conta de repasse, dispara quando o grupo confirma, no valor da parte da casa. O cron diário não varre o saldo.

O aviso Reservado diz: “Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.”

O estorno Woovi grava a devolução antes do débito da subconta. Se o débito falha, o Pix não é estornado de novo; a tentativa seguinte só debita.

## Migration

Arquivo: `supabase/migrations/20261120140000_provider_payout_accounts.sql`.

Cria `provider_payout_accounts`, `provider_webhook_events` e `private.provider_oauth_tokens`. O token do Mercado Pago fica cifrado com uma chave gerada no Vault (`provider_token_key`). A migration não contém credencial de provedor.

`supabase/migrations/20261120150000_asaas_columns_readonly.sql` só comenta colunas antigas e troca o default de `payment_charges.provider` para `woovi`. Não dá `DROP`, não apaga linha e não desliga cron. O `DROP` dessas colunas fica para um passo separado, depois que ninguém lê o histórico por elas.

Aplicar no projeto só depois da revisão, junto com as funções novas. Este agente não roda `supabase db push`.

## Variáveis

Nenhum valor entra no git. Trocar os placeholders. Sandbox primeiro.

```bash
supabase secrets set --project-ref <project-ref> \
  WOOVI_APP_ID='<AppID da conta sandbox Woovi>' \
  WOOVI_BASE_URL='https://api.woovi-sandbox.com' \
  WOOVI_WEBHOOK_SECRET='<segredo HMAC do webhook Woovi, 16 caracteres ou mais>' \
  WOOVI_WEBHOOK_PUBLIC_KEY='<PEM público da Woovi, opcional se o HMAC estiver ativo>' \
  WOOVI_POINTS_RESERVE_PIX_KEY='<pixKey da subconta de reserva de pontos, opcional>' \
  MP_ENV='sandbox' \
  MP_CLIENT_ID='<client id da aplicação Mercado Pago>' \
  MP_CLIENT_SECRET='<client secret da aplicação>' \
  MP_OAUTH_STATE_SECRET='<segredo do state OAuth, 16 caracteres ou mais; se vazio, usa MP_CLIENT_SECRET>' \
  MP_OAUTH_REDIRECT_URI='https://parceiro.escapematch.com.br/mp-retorno' \
  MP_WEBHOOK_SECRET='<assinatura secreta do webhook Mercado Pago>' \
  MP_ACCESS_TOKEN='<access token da aba Teste, prefixo APP_USR- ou TEST-, só com MP_ENV=sandbox e se a casa ainda não conectou>'
```

Não existe `PAYMENTS_PROVIDER`. O Parceiro mostra saldo e saque da Woovi sem `--dart-define`.

`WOOVI_BASE_URL` de produção é `https://api.woovi.com`. Não é segredo. Enquanto a revisão não termina, deixe a URL de sandbox.

O access token OAuth da casa não é variável de ambiente. A função grava o par cifrado e renova antes de 180 dias.

## Prontidão

`payments-readiness` responde só sim ou não, mais `payments_provider` (`woovi`). Os campos:

| Campo | Onde olha |
| --- | --- |
| `payments_provider` | sempre `woovi` |
| `woovi_app_id` | `WOOVI_APP_ID` não vazia |
| `woovi_base_url_sandbox` | `WOOVI_BASE_URL` vazia ou exatamente `https://api.woovi-sandbox.com` |
| `woovi_webhook_secret` | `WOOVI_WEBHOOK_SECRET` não vazia |
| `woovi_webhook_public_key` | `WOOVI_WEBHOOK_PUBLIC_KEY` não vazia |
| `mp_client_id` | `MP_CLIENT_ID` não vazia |
| `mp_client_secret` | `MP_CLIENT_SECRET` não vazia |
| `mp_webhook_secret` | `MP_WEBHOOK_SECRET` não vazia |
| `mp_oauth_redirect_uri` | `MP_OAUTH_REDIRECT_URI` não vazia |
| `mp_env_sandbox` | `MP_ENV` é exatamente `sandbox` |
| `mp_access_token_test` | o token da plataforma pode entrar no lugar do OAuth: `MP_ENV=sandbox` e `MP_ACCESS_TOKEN` com pelo menos 20 caracteres, ou `MP_ENV` vazia e token começando com `TEST-`. `production` ou outro valor deixa o campo falso |

O valor não sai na resposta.

## Depois do merge, apagar estes segredos

Não apagar neste PR. Apagar no Supabase depois que as funções novas estiverem publicadas:

- `ASAAS_API_KEY`
- `ASAAS_BASE_URL`
- `ASAAS_WEBHOOK_TOKEN`
- `ASAAS_WEBHOOK_EMAIL`
- `ASAAS_SUBACCOUNT_EMAIL_DOMAIN`
- `ASAAS_POINTS_RESERVE_API_KEY`
- `ASAAS_POINTS_RESERVE_WALLET_ID`
- `ASAAS_ROOT_WALLET_ID`
- `ASAAS_INVOICE_EMISSION`
- `ASAAS_FISCAL_SERVICE_CODE`
- `ASAAS_FISCAL_SERVICE_NAME`
- `ASAAS_FISCAL_ISS`
- `ASAAS_TRANSFER_WEBHOOK_URL`
- `PAYMENTS_PROVIDER`, se existir
- Itens do Vault: `asaas_subaccount_key` e qualquer outro nome que comece com `asaas_`

Não apagar `WOOVI_*`, `MP_*`, `VENUE_WITHDRAWALS_SECRET` nem `LEDGER_RECONCILE_SECRET`.

## Depois do merge, despublicar ou desligar

Não fazer neste PR. A cópia publicada antiga continua chamando o provedor anterior até alguém agir.

Despublicar, porque o código saiu do repositório:

- `asaas-webhook`
- `asaas-transfer-webhook`

Republicar com o código novo antes de deixar o cron bater na versão antiga:

- `create-charge`
- `settle-charges`
- `provision-venue-wallet`
- `tokenize-card`
- `reconcile-payments`
- `ledger-reconcile`
- `venue-payouts`
- `schedule-venue-withdrawals`
- `venue-documents`
- `configure-venue-fiscal`
- `invoice-document`
- `payments-readiness`
- `cancel-house-group`

Crons para desligar depois que a função nova estiver no ar, ou assim que a versão antiga ainda estiver publicada:

- `reconcile-payments`, a cada 5 minutos
- `venue-withdrawals`, todo dia às 08:20 em Brasília
- `ledger-reconcile`, todo dia às 08:30 em Brasília

## O que só a conta sandbox confirma

- O saldo da subconta vem em centavos.
- O `endToEndId` do Pix pago chega no webhook `OPENPIX:CHARGE_COMPLETED` e o estorno parcial debita a subconta de verdade.
- O access token OAuth da casa, da aba Teste (`APP_USR-` ou `TEST-`), autoriza com `capture=false` e a comissão cai em `application_fee`. `MP_ENV=sandbox` precisa estar definido para o token `APP_USR-` da plataforma servir de fallback.
- A assinatura real da Woovi com a chave publicada em `/api/v1/webhook/public-keys`, se o HMAC do painel não for usado.
