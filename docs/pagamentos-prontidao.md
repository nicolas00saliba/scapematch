# Prontidão dos pagamentos no Asaas de produção

O cron `venue-withdrawals` dispara todo dia às 08:20 em Brasília (`20 11 * * *` em UTC). Ele chama `private.invoke_venue_withdrawals()`, que lê dois itens do Vault e faz `POST` na Edge Function `schedule-venue-withdrawals` com o header `x-venue-withdrawals-secret`.

Sem `venue_withdrawals_url` ou sem `venue_withdrawals_secret`, a função levanta `venue_withdrawals_config_ausente` e cita só o nome do item que falta. O pg_cron grava o job como `failed` em `cron.job_run_details`. A mensagem não leva o valor.

Se a função chega a rodar sem a env `VENUE_WITHDRAWALS_SECRET`, ela registra o mesmo código no log. Com a env `SENTRY_DSN` apontando para um host `*.ingest.sentry.io` (ou `ingest.us` / `ingest.de`), o mesmo código segue para o Sentry. O DSN não entra no corpo do evento. A resposta HTTP continua `401`, para não contar para fora se o segredo existe.

Nada abaixo foi aplicado neste repositório no projeto remoto. Quem aplica é o Nícolas, no projeto de produção, depois de revisar.

## O que a prontidão responde

`public.admin_payments_readiness()` exige admin com sessão `aal2`. A Edge Function `payments-readiness` usa o JWT de quem chama, confirma esse RPC e junta as envs. A resposta é só sim ou não, mais `cron_last_failed` e `cron_failure_code` (`config_ausente` ou `cron_failed`).

| Campo | Onde olha |
| --- | --- |
| `asaas_api_key` | env `ASAAS_API_KEY` não vazia |
| `asaas_base_url_production` | env `ASAAS_BASE_URL` é exatamente `https://api.asaas.com/v3` |
| `asaas_webhook_token` | env `ASAAS_WEBHOOK_TOKEN` não vazia |
| `asaas_webhook_email` | env `ASAAS_WEBHOOK_EMAIL` não vazia |
| `venue_withdrawals_secret` | env `VENUE_WITHDRAWALS_SECRET` não vazia |
| `vault_venue_withdrawals_url` | Vault `venue_withdrawals_url` não vazio |
| `vault_venue_withdrawals_secret` | Vault `venue_withdrawals_secret` não vazio |
| `venue_payouts_enabled` | `venue_payouts_settings.enabled` |

Sandbox (`https://api-sandbox.asaas.com/v3`), URL vazia e qualquer outro host contam como não.

## Migration

Arquivo: `supabase/migrations/20261113160000_payments_readiness.sql`.

Aplicar no projeto antes de publicar a função `payments-readiness` e antes de contar com o cron novo. Este agente não roda `supabase db push` nem cola SQL no banco remoto.

## Envs da Edge Function

Trocar os placeholders. Não gravar os valores no git. `ASAAS_BASE_URL` de produção é a URL pública abaixo, não um segredo.

```bash
supabase secrets set --project-ref <project-ref> \
  ASAAS_API_KEY='<chave da conta Asaas de produção>' \
  ASAAS_BASE_URL='https://api.asaas.com/v3' \
  ASAAS_WEBHOOK_TOKEN='<token de 32 a 255 caracteres, sem espaço>' \
  ASAAS_WEBHOOK_EMAIL='<email que o Asaas usa no webhook>' \
  VENUE_WITHDRAWALS_SECRET='<segredo longo, o mesmo do Vault>' \
  SENTRY_DSN='<DSN https do ingest do Sentry; opcional>'
```

`VENUE_WITHDRAWALS_SECRET` e o item `venue_withdrawals_secret` do Vault têm de ser o mesmo texto. `ASAAS_WEBHOOK_TOKEN` não é a chave da API.

Publicar as funções, sem fazer isso daqui:

```bash
supabase functions deploy schedule-venue-withdrawals --project-ref <project-ref>
supabase functions deploy payments-readiness --project-ref <project-ref>
```

## Vault

Rodar no SQL Editor do projeto, com um papel que possa criar segredo no Vault. Não selecionar `vault.decrypted_secrets`.

Criar quando o nome ainda não existe:

```sql
select vault.create_secret(
  new_secret := '<o mesmo valor de VENUE_WITHDRAWALS_SECRET>',
  new_name := 'venue_withdrawals_secret',
  new_description := 'Header x-venue-withdrawals-secret do cron de saques'
);

select vault.create_secret(
  new_secret := 'https://<project-ref>.supabase.co/functions/v1/schedule-venue-withdrawals',
  new_name := 'venue_withdrawals_url',
  new_description := 'URL da Edge Function schedule-venue-withdrawals'
);
```

Se o nome já existe, atualizar pelo id. O `select` em `vault.secrets` devolve o id, não o valor:

```sql
select vault.update_secret(
  secret_id := (select id from vault.secrets where name = 'venue_withdrawals_secret'),
  new_secret := '<o mesmo valor de VENUE_WITHDRAWALS_SECRET>'
);

select vault.update_secret(
  secret_id := (select id from vault.secrets where name = 'venue_withdrawals_url'),
  new_secret := 'https://<project-ref>.supabase.co/functions/v1/schedule-venue-withdrawals'
);
```

Conferir sem abrir o valor: chamar `admin_payments_readiness` no painel, ou no SQL Editor já autenticado como admin `aal2`. Os dois campos do Vault têm de vir `true`.
