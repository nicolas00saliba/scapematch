# Prontidão dos pagamentos no Asaas de produção

O cron `venue-withdrawals` dispara todo dia às 08:20 em Brasília (`20 11 * * *` em UTC). Ele chama `private.invoke_venue_withdrawals()`, que lê dois itens do Vault e faz `POST` na Edge Function `schedule-venue-withdrawals` com o header `x-venue-withdrawals-secret`.

Sem `venue_withdrawals_url` ou sem `venue_withdrawals_secret`, a função levanta `venue_withdrawals_config_ausente` e cita só o nome do item que falta. O pg_cron grava o job como `failed` em `cron.job_run_details`. A mensagem não leva o valor.

`schedule-venue-withdrawals` não verifica JWT. Sem a env `VENUE_WITHDRAWALS_SECRET` e sem o item `venue_withdrawals_secret` no Vault, a função responde `503` e não envia evento ao Sentry, nem por chamada anônima. Com um dos dois preenchido e o header errado ou vazio, a resposta é `401`, também sem evento. A env tem prioridade. O valor do Vault fica em cache na memória por um minuto e não entra em log.

O alerta de configuração sai só do cron `venue-withdrawals-config`, uma vez por execução (`20 11 * * *`). Ele lê o item opcional `sentry_dsn` no Vault e manda um único POST quando falta `venue_withdrawals_url` ou `venue_withdrawals_secret`. O evento usa o fingerprint fixo `venue_withdrawals_config_ausente` e cita só o nome do item. Sem `sentry_dsn`, ou com um host que não seja `*.ingest.sentry.io` (nem `ingest.us` / `ingest.de`), não há POST. O job `venue-withdrawals` continua falhando e gravando o erro. O DSN não entra no corpo.

Nada abaixo foi aplicado neste repositório no projeto remoto. Quem aplica é o Nícolas, no projeto de produção, depois de revisar.

## O que a prontidão responde

`public.admin_payments_readiness()` exige admin com sessão `aal2`. A Edge Function `payments-readiness` usa o JWT de quem chama, confirma esse RPC e junta as envs. A resposta é só sim ou não, mais `cron_last_failed` e `cron_failure_code` (`config_ausente` ou `cron_failed`).

| Campo | Onde olha |
| --- | --- |
| `asaas_api_key` | env `ASAAS_API_KEY` não vazia |
| `asaas_base_url_production` | env `ASAAS_BASE_URL` é exatamente `https://api.asaas.com/v3` |
| `asaas_webhook_token` | env `ASAAS_WEBHOOK_TOKEN` não vazia |
| `asaas_webhook_email` | env `ASAAS_WEBHOOK_EMAIL` não vazia |
| `venue_withdrawals_secret` | env `VENUE_WITHDRAWALS_SECRET` não vazia, ou Vault `venue_withdrawals_secret` não vazio |
| `ledger_reconcile_secret` | env `LEDGER_RECONCILE_SECRET` não vazia, ou Vault `ledger_reconcile_secret` não vazio |
| `vault_venue_withdrawals_url` | Vault `venue_withdrawals_url` não vazio |
| `vault_venue_withdrawals_secret` | Vault `venue_withdrawals_secret` não vazio |
| `vault_ledger_reconcile_secret` | Vault `ledger_reconcile_secret` não vazio |
| `venue_payouts_enabled` | `venue_payouts_settings.enabled` |

Sandbox (`https://api-sandbox.asaas.com/v3`), URL vazia e qualquer outro host contam como não.

## Migration

Arquivo: `supabase/migrations/20261113160000_payments_readiness.sql`. O fallback do Vault está em `supabase/migrations/20261113210000_cron_vault_secret.sql`.

Aplicar no projeto antes de publicar a função `payments-readiness` e antes de contar com o cron novo. Este agente não roda `supabase db push` nem cola SQL no banco remoto.

## Envs da Edge Function

Trocar os placeholders. Não gravar os valores no git. `ASAAS_BASE_URL` de produção é a URL pública abaixo, não um segredo.

```bash
supabase secrets set --project-ref <project-ref> \
  ASAAS_API_KEY='<chave da conta Asaas de produção>' \
  ASAAS_BASE_URL='https://api.asaas.com/v3' \
  ASAAS_WEBHOOK_TOKEN='<token de 32 a 255 caracteres, sem espaço>' \
  ASAAS_WEBHOOK_EMAIL='<email que o Asaas usa no webhook>' \
  VENUE_WITHDRAWALS_SECRET='<segredo longo, o mesmo do Vault>'
```

`VENUE_WITHDRAWALS_SECRET` é opcional. Sem ela, a função usa o item `venue_withdrawals_secret` do Vault, o mesmo texto que o cron manda no header. Se a env existir, ela ganha e tem de ser esse texto. `ASAAS_WEBHOOK_TOKEN` não é a chave da API.

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

-- Opcional. Sem este item o cron de saques ainda falha alto, mas não há POST ao Sentry.
select vault.create_secret(
  new_secret := '<DSN https://<chave>@<host>.ingest.sentry.io/<projeto>>',
  new_name := 'sentry_dsn',
  new_description := 'DSN do Sentry para o alerta único do cron venue-withdrawals-config'
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

select vault.update_secret(
  secret_id := (select id from vault.secrets where name = 'sentry_dsn'),
  new_secret := '<DSN https://<chave>@<host>.ingest.sentry.io/<projeto>>'
);
```

Conferir sem abrir o valor: chamar `admin_payments_readiness` no painel, ou no SQL Editor já autenticado como admin `aal2`. Os dois campos do Vault têm de vir `true`.
