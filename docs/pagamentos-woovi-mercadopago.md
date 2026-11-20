# Woovi e Mercado Pago, em sandbox

O Asaas continua funcionando e é o provedor padrão. Nada desta troca vai para produção enquanto `PAYMENTS_PROVIDER` não for `woovi`. Este agente não aplica a migration no projeto remoto, não publica Edge Function e não cria conta na Woovi nem no Mercado Pago.

Pix novo usa a Woovi. Cartão novo usa o Mercado Pago. A cobrança já gravada segue `payment_charges.provider`: uma cobrança Asaas não muda de trilho.

Se o grupo não confirmar, o Pix é estornado e o cartão não é capturado.

A NFS-e fica fora deste PR. Continua no Asaas e está pendente para Woovi e Mercado Pago.

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

Mercado Pago, mesma API de sandbox e produção (`https://api.mercadopago.com`). O que separa o teste é o access token da casa, obtido por OAuth, com prefixo `TEST-`.

| Ação | Chamada |
| --- | --- |
| Reserva | `POST /v1/payments` com `capture=false`, `application_fee` em reais e o `access_token` OAuth da casa |
| Captura | `PUT /v1/payments/{id}` com `capture=true` |
| Cancelamento da reserva | `PUT /v1/payments/{id}` com `status=cancelled` |
| Estorno | `POST /v1/payments/{id}/refunds`. Parcial manda `amount` em reais |
| Renovação | `POST /oauth/token` com `grant_type=refresh_token`, quando faltam menos de 30 dias para os 180 |

O webhook da Woovi aceita `x-openpix-signature` (HMAC SHA-256 do corpo cru, segredo `WOOVI_WEBHOOK_SECRET`) ou `x-webhook-signature` (RSA SHA-256 com a chave pública). Sem uma das duas, a função responde 401. O webhook do Mercado Pago exige `x-signature` e `x-request-id`. O manifest é `id:<data.id em minúsculas>;request-id:<x-request-id>;ts:<ts>;`, HMAC SHA-256 com `MP_WEBHOOK_SECRET`.

Os dois gravam o evento em `provider_webhook_events`. A segunda entrega responde ok e não mexe no livro.

## Saque da casa

O saldo da subconta aparece no EscapeMatch Parceiro quando `PAYMENTS_PROVIDER=woovi`. A casa não abre a Woovi. O botão saca para a chave Pix da subconta. O saque automático, com `auto_withdraw` na conta de repasse, dispara quando o grupo confirma, no valor da parte da casa. O cron diário não varre o saldo: o Pix já caiu na subconta antes da confirmação, e varrer esse saldo pagaria a casa cedo demais.

## Migration

Arquivo: `supabase/migrations/20261120140000_provider_payout_accounts.sql`.

Cria `provider_payout_accounts`, `provider_webhook_events` e `private.provider_oauth_tokens`. O token do Mercado Pago fica cifrado com uma chave gerada no Vault (`provider_token_key`). A migration não contém credencial de provedor.

Aplicar no projeto só depois da revisão, junto com as funções novas. Este agente não roda `supabase db push`.

## Variáveis

Nenhum valor entra no git. Trocar os placeholders. Sandbox primeiro.

```bash
supabase secrets set --project-ref <project-ref> \
  PAYMENTS_PROVIDER='asaas' \
  WOOVI_APP_ID='<AppID da conta sandbox Woovi>' \
  WOOVI_BASE_URL='https://api.woovi-sandbox.com' \
  WOOVI_WEBHOOK_SECRET='<segredo HMAC do webhook Woovi, 16 caracteres ou mais>' \
  WOOVI_WEBHOOK_PUBLIC_KEY='<PEM público da Woovi, opcional se o HMAC estiver ativo>' \
  WOOVI_POINTS_RESERVE_PIX_KEY='<pixKey da subconta de reserva de pontos, opcional>' \
  MP_CLIENT_ID='<client id da aplicação Mercado Pago>' \
  MP_CLIENT_SECRET='<client secret da aplicação>' \
  MP_OAUTH_STATE_SECRET='<segredo do state OAuth, 16 caracteres ou mais; se vazio, usa MP_CLIENT_SECRET>' \
  MP_OAUTH_REDIRECT_URI='<URL de retorno cadastrada na aplicação>' \
  MP_WEBHOOK_SECRET='<assinatura secreta do webhook Mercado Pago>' \
  MP_ACCESS_TOKEN='<access token TEST- da plataforma, só se a casa ainda não conectou>'
```

`PAYMENTS_PROVIDER=asaas` é o padrão e pode ficar ausente. `woovi` (ou `woovi_mp`) liga o trilho novo. O app Parceiro lê a mesma flag em compilação: `--dart-define=PAYMENTS_PROVIDER=woovi`. Sem isso, o saldo Woovi e o botão de conexão não aparecem.

`WOOVI_BASE_URL` de produção, quando a troca for aprovada, é `https://api.woovi.com`. Não é segredo. Enquanto a revisão não termina, deixe a URL de sandbox.

O access token OAuth da casa não é variável de ambiente. A função grava o par cifrado e renova antes de 180 dias.

## Prontidão

`payments-readiness` continua respondendo só sim ou não, mais `payments_provider` (`asaas` ou `woovi`). Os campos novos:

| Campo | Onde olha |
| --- | --- |
| `payments_provider` | `PAYMENTS_PROVIDER`. Vazio e qualquer outro valor contam como `asaas` |
| `woovi_app_id` | `WOOVI_APP_ID` não vazia |
| `woovi_base_url_sandbox` | `WOOVI_BASE_URL` vazia ou exatamente `https://api.woovi-sandbox.com` |
| `woovi_webhook_secret` | `WOOVI_WEBHOOK_SECRET` não vazia |
| `woovi_webhook_public_key` | `WOOVI_WEBHOOK_PUBLIC_KEY` não vazia |
| `mp_client_id` | `MP_CLIENT_ID` não vazia |
| `mp_client_secret` | `MP_CLIENT_SECRET` não vazia |
| `mp_webhook_secret` | `MP_WEBHOOK_SECRET` não vazia |
| `mp_oauth_redirect_uri` | `MP_OAUTH_REDIRECT_URI` não vazia |
| `mp_access_token_test` | `MP_ACCESS_TOKEN` começa com `TEST-` e tem pelo menos 20 caracteres |

O valor não sai na resposta.

## O que só a conta sandbox confirma

- O saldo da subconta vem em centavos.
- O `endToEndId` do Pix pago chega no webhook `OPENPIX:CHARGE_COMPLETED` e o estorno parcial debita a subconta de verdade.
- O access token OAuth da casa, com `TEST-`, autoriza com `capture=false` e a comissão cai em `application_fee`.
- A assinatura real da Woovi com a chave publicada em `/api/v1/webhook/public-keys`, se o HMAC do painel não for usado.
