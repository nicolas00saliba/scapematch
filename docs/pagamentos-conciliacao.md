# Conciliação diária PagBank × livro

O cron `ledger-reconcile` dispara todo dia às 08:30 em Brasília (`30 11 * * *` em UTC). Ele chama `private.invoke_ledger_reconcile()`, que lê dois itens do Vault e faz `POST` na Edge Function `ledger-reconcile` com o header `x-ledger-reconcile-secret`.

A função só faz `GET` na base de `PAGBANK_ENV` (produção em `https://api.pagseguro.com` se a env estiver ausente ou valer `production`). Cobranças usam a chave da conta principal. Saques saem da subconta de cada casa, então as transferências são lidas com a chave dessa casa (`read_venue_provider_key`, a mesma fonte dos saques). Se essa chave não puder ser lida, o saque não entra como "ausente no PagBank".

A janela é o dia de ontem e o de hoje em `America/Sao_Paulo`, nos dois lados. `ledger_reconcile_snapshot` traz as cobranças PagBank criadas, pagas ou estornadas nessa janela. Cada `ORDE_` vai em `GET /orders/{id}` e cada `CHAR_` em `GET /orders?charge_id=`, com `Authorization: Bearer` e `Accept: application/json`, sem `Content-Type` no GET. A API de Pedidos não lista cobrança por `dateCreated` nem `paymentDate` (isso era o Asaas). `GET /charges` com esses filtros, e `GET /charges/{CHAR_}`, não são a consulta do pedido: o PagBank documenta 406 como método que o recurso não aceita. Saque da casa é `GET /transfers/{id}` com a chave dessa casa. Não cria cobrança, estorno nem transferência. As diferenças entram em `payment_divergences` e aparecem na tela Conciliação do Admin, com status em português.

406, timeout ou outro erro do provedor numa cobrança não derruba as outras: a falha entra como divergência `charge_status_unknown` com o status HTTP em `actual`, o log leva o status sem token e sem corpo, e a função responde `502` com `pagbank_unavailable` e `failures`. O cron das 08:40 continua tratando HTTP 400+ como `ledger_reconcile_http_erro`. 404 numa cobrança não alerta: a cobrança entra como ausência no PagBank. O `CHAR_` consultado é a cobrança daquele id dentro do pedido. Se o pedido tiver outra tentativa antes, o status e o valor dela não entram. Se o id não estiver no pedido, a consulta é 404.

Status do PagBank é traduzido para o vocabulário do livro (`authorized`, `paid`, `refunded` e os demais). Código que o livro não tem vira a divergência "Status desconhecido", não "status diferente".

O job `ledger-reconcile-result` (`40 11 * * *`) lê a resposta HTTP do pedido. Status ausente, timeout ou 400+ levanta `ledger_reconcile_http_erro` e o pg_cron marca o job como `failed`. A mensagem não inclui corpo, URL nem segredo.

Isso não substitui `reconcile-payments`. Aquela função, a cada 5 minutos, liquida grupo, cancela expirado, confirma cartão e libera ponto. Ela altera o livro. Esta daqui só compara e registra divergência.

Sem `ledger_reconcile_url` ou sem `ledger_reconcile_secret`, a função do cron levanta `ledger_reconcile_config_ausente` e cita só o nome do item. O pg_cron grava o job como `failed`. A mensagem não leva o valor.

Sem a env `LEDGER_RECONCILE_SECRET`, a função lê `ledger_reconcile_secret` no Vault. Sem os dois, responde `503` e não chama o PagBank. Com um dos dois preenchido e o header errado, a resposta é `401`, também sem chamada. A env tem prioridade. O valor não entra em log.

Nada abaixo foi aplicado neste repositório no projeto remoto.

## Migration

Arquivo: `supabase/migrations/20261113190000_ledger_reconcile.sql`. A leitura do segredo pela função está em `supabase/migrations/20261113210000_cron_vault_secret.sql`.

## Envs da Edge Function

```bash
supabase secrets set --project-ref <project-ref> \
  PAGBANK_TOKEN='<chave da conta PagBank>' \
  PAGBANK_ENV='production' \
  LEDGER_RECONCILE_SECRET='<segredo longo, o mesmo do Vault>'
```

`LEDGER_RECONCILE_SECRET` é opcional. Sem ela, a função usa o item `ledger_reconcile_secret` do Vault. Se a env existir, ela ganha e tem de ser o mesmo texto que o cron manda no header.

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
