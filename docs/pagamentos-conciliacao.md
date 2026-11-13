# Conciliação diária Asaas × livro

O cron `ledger-reconcile` dispara todo dia às 08:30 em Brasília (`30 11 * * *` em UTC). Ele chama `private.invoke_ledger_reconcile()`, que lê dois itens do Vault e faz `POST` na Edge Function `ledger-reconcile` com o header `x-ledger-reconcile-secret`.

A função só faz `GET /payments` e `GET /transfers` na base configurada em `ASAAS_BASE_URL`. Não cria cobrança, estorno nem transferência. As diferenças entram em `payment_divergences` e aparecem na tela Conciliação do Admin.

Sem `ledger_reconcile_url` ou sem `ledger_reconcile_secret`, a função do cron levanta `ledger_reconcile_config_ausente` e cita só o nome do item. O pg_cron grava o job como `failed`. A mensagem não leva o valor.

Sem a env `LEDGER_RECONCILE_SECRET`, a função responde `503` e não chama o Asaas. Com a env preenchida e o header errado, a resposta é `401`, também sem chamada.

Nada abaixo foi aplicado neste repositório no projeto remoto.

## Migration

Arquivo: `supabase/migrations/20261113180000_ledger_reconcile.sql`.

## Envs da Edge Function

```bash
supabase secrets set --project-ref <project-ref> \
  ASAAS_API_KEY='<chave da conta Asaas>' \
  ASAAS_BASE_URL='<https://api.asaas.com/v3 em produção, ou a URL de sandbox>' \
  LEDGER_RECONCILE_SECRET='<segredo longo, o mesmo do Vault>'
```

Publicar, sem fazer isso daqui:

```bash
supabase functions deploy ledger-reconcile --project-ref <project-ref>
```

## Vault

Rodar no SQL Editor. Não selecionar `vault.decrypted_secrets`.

```sql
select vault.create_secret(
  new_secret := '<o mesmo valor de LEDGER_RECONCILE_SECRET>',
  new_name := 'ledger_reconcile_secret',
  new_description := 'Header x-ledger-reconcile-secret do cron de conciliação'
);

select vault.create_secret(
  new_secret := 'https://<project-ref>.supabase.co/functions/v1/ledger-reconcile',
  new_name := 'ledger_reconcile_url',
  new_description := 'URL da Edge Function ledger-reconcile'
);
```

Se o nome já existe:

```sql
select vault.update_secret(
  secret_id := (select id from vault.secrets where name = 'ledger_reconcile_secret'),
  new_secret := '<o mesmo valor de LEDGER_RECONCILE_SECRET>'
);

select vault.update_secret(
  secret_id := (select id from vault.secrets where name = 'ledger_reconcile_url'),
  new_secret := 'https://<project-ref>.supabase.co/functions/v1/ledger-reconcile'
);
```
