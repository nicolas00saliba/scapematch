# Conciliação diária Asaas × livro

O cron `ledger-reconcile` dispara todo dia às 08:30 em Brasília (`30 11 * * *` em UTC). Ele chama `private.invoke_ledger_reconcile()`, que lê dois itens do Vault e faz `POST` na Edge Function `ledger-reconcile` com o header `x-ledger-reconcile-secret`.

A função só faz `GET` na base configurada em `ASAAS_BASE_URL`. Cobranças usam a chave da conta principal. Saques saem da subconta de cada casa, então as transferências são lidas com a chave dessa casa (`read_venue_asaas_key`, a mesma fonte dos saques). Se essa chave não puder ser lida, o saque não entra como "ausente no Asaas".

A janela é o dia de ontem e o de hoje em `America/Sao_Paulo`, nos dois lados. No Asaas a busca usa `dateCreated` e `paymentDate`. Cobrança ou transferência do livro que não apareça nessa lista é consultada pelo id. Não cria cobrança, estorno nem transferência. As diferenças entram em `payment_divergences` e aparecem na tela Conciliação do Admin, com status em português.

Status do Asaas é traduzido para o vocabulário do livro (`authorized`, `paid`, `refunded` e os demais). Código que o livro não tem vira a divergência "Status desconhecido", não "status diferente".

O job `ledger-reconcile-result` (`40 11 * * *`) lê a resposta HTTP do pedido. Status ausente, timeout ou 400+ levanta `ledger_reconcile_http_erro` e o pg_cron marca o job como `failed`. A mensagem não inclui corpo, URL nem segredo.

Isso não substitui `reconcile-payments`. Aquela função, a cada 5 minutos, liquida grupo, cancela expirado, confirma cartão e libera ponto. Ela altera o livro. Esta daqui só compara e registra divergência.

Sem `ledger_reconcile_url` ou sem `ledger_reconcile_secret`, a função do cron levanta `ledger_reconcile_config_ausente` e cita só o nome do item. O pg_cron grava o job como `failed`. A mensagem não leva o valor.

Sem a env `LEDGER_RECONCILE_SECRET`, a função responde `503` e não chama o Asaas. Com a env preenchida e o header errado, a resposta é `401`, também sem chamada.

Nada abaixo foi aplicado neste repositório no projeto remoto.

## Migration

Arquivo: `supabase/migrations/20261113190000_ledger_reconcile.sql`.

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
