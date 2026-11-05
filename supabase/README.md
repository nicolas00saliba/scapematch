# Supabase do ScapeMatch

O app não aplica estas migrações sozinho. A ordem é a do nome do arquivo. No SQL Editor do projeto `eujlhicairvksvmssruz` (região sa-east-1), rode um arquivo por vez, de cima para baixo, ou use a CLI com a sua conta:

```bash
supabase link --project-ref eujlhicairvksvmssruz
supabase db push
```

## Ordem

1. `migrations/20261104120000_init.sql` — tabelas, cinco cidades e a comissão inicial de 10% (1000 bps).
2. `migrations/20261104120100_helpers.sql` — `is_admin`, perfil criado no cadastro, casa que nasce `pending`.
3. `migrations/20261104120200_rls.sql` — RLS, bucket `room-photos` e o canal Realtime de `group_members`.
4. `migrations/20261104120300_group_functions.sql` — criar, entrar, sair, excluir, fechar com menos gente, fila e falta.
5. `migrations/20261104120400_asaas.sql` — cobranças Pix e cartão. O app não insere nelas.
6. `migrations/20261104120500_privacy.sql` — anon sem documento, telefone e renda; bucket `room-photos` privado; falta só por `mark_absence`.
7. `migrations/20261104120600_fiscal_terms.sql` — notas fiscais, dados fiscais da casa, chave da subconta fora do app, e o aceite dos termos.
8. `migrations/20261104120700_friends_crews.sql` — amigos, turmas, avisos no app e entrada em grupo com várias vagas. Vem depois de `20261104120600_fiscal_terms.sql` e não usa tabela de nota fiscal. Não foi aplicada no projeto.
9. `migrations/20261104130000_venue_duplicates.sql` — documento normalizado com índice único, nome com `pg_trgm`, `check_venue_duplicates`, reivindicação e a fila de aprovar, recusar ou mesclar.
10. `migrations/20261104140000_house_cancel_group.sql` — a casa cancela o grupo dela e deixa o estorno `pending`. O botão chama `cancel-house-group`. Não foi aplicada no projeto.
11. `migrations/20261104150000_refund_fix.sql` — `delete_group` também deixa `pending` em vez de `refunded`, avisa os jogadores e tira privilégios extras de `venues` e `profiles`. Não foi aplicada no projeto.

`seed_demo.sql` fica **fora** dessa lista. É opcional e cria a casa real ScapeMatch Demo (Curitiba, três salas, horários e duas promoções). Não é dado de exemplo do app.

Não há `service_role`, chave do Asaas nem chave da Stability nestes arquivos. As funções leem o gateway só de `Deno.env`.

## O que você faz depois de aplicar

1. Authentication → Providers → Email. Deixe e-mail e senha ligados. Para a demonstração de sábado, desligue **Confirm email**. Com a confirmação ligada, o app avisa para abrir o e-mail e a casa só consegue gravar a venue depois que a sessão existe.
2. Crie a sua conta de admin no app do jogador (ou no Parceiro) e pegue o UUID em Authentication → Users.
3. Rode no SQL Editor, trocando o UUID:

```sql
insert into public.admins (user_id) values ('00000000-0000-0000-0000-000000000000');
```

4. No Parceiro, entre com essa conta. A fila **Aprovar casas** lista as venues `pending`. Aprovar grava `approved`. Só então o jogador vê a casa, as salas e as notícias.
5. Storage: o bucket `room-photos` é privado. Não há URL pública. O caminho é `{venue_id}/{room_id}/{arquivo}`. O app pede uma signed URL (`createSignedUrl`). A leitura passa por `room_photo_object_allowed`: casa aprovada, o dono ou um admin. Foto de casa pendente não abre para anônimo. Quem envia, troca e apaga é o dono da casa. Não coloque documento privado nesse bucket.

## Regras que o banco segura

- A casa só lê e escreve salas, fotos, horários, notícias e promoções dela. Falta não tem insert direto: entra por `mark_absence`. O gatilho `venues_guard` impede a casa de se aprovar.
- Documento repetido (só os dígitos) não entra de novo enquanto a casa não foi recusada nem mesclada. `check_venue_duplicates` devolve o tipo do conflito e, se a casa já foi aprovada, o id e o nome público. Não devolve documento, telefone nem dados de casa pendente de outra pessoa. CEP + número, ou nome parecido na mesma cidade, não bloqueia: o cadastro segue com `possible_duplicate_of`.
- "Esta casa é minha?" grava `venue_claims`. Anon não lê essa tabela. A pessoa vê o próprio pedido; o admin vê a fila, aprova, recusa ou mescla. Aprovar a reivindicação passa a casa aprovada para quem pediu.
- O jogador anônimo lê cidade e o que é de casa aprovada. Em `venues`, não lê `document_number`, `phone`, `income_value`, `asaas_wallet_id`, `referred_by`, `reviewed_by`, `invite_id` nem `owner_id`. O catálogo usa a view `venues_vitrine` (o `select *` na tabela falha para o anon). Grupo, cadeira e falta não têm `insert` direto.
- Quem está logado também não lê documento, telefone, renda, wallet nem quem indicou. O dono ou um admin lê isso em `venue_private`. A Edge Function lê a tabela com `service_role`. O logado continua vendo `owner_id`.
- `delete_group` recusa quando falta menos de 2 horas para o início. No instante exato das 2 horas ainda exclui.
- `close_group_with_fewer` só fecha se N ≥ mínimo da sala e N < tamanho planejado.
- O Pix é cobrado na hora (`billingType PIX`) e estornado se o grupo não fechar. O cartão nasce com `authorizeOnly` e só é capturado quando o grupo fecha; se não fechar, a reserva é estornada.
- O split manda `(100% − comissão)` para `venues.asaas_wallet_id`. A comissão é `platform_settings.commission_bps` (padrão 1000, 10%) e fica na conta Asaas que cria a cobrança.

## Asaas (sandbox na demo)

A implementação é `AsaasProvider` em `supabase/functions/_shared/asaas_provider.ts`. O app não chama `api-sandbox.asaas.com`. Quem chama é a Edge Function.

| Função | JWT | O que faz |
| --- | --- | --- |
| `provision-venue-wallet` | admin | Cria a subconta (`POST /v3/accounts`) e grava só o `walletId`. A `apiKey` da subconta não é salva. |
| `tokenize-card` | jogador autenticado | Única função que recebe número, CVV e validade. Antes do Asaas, `private.claim_card_tokenize_attempt` (só service role) registra a tentativa e recusa com 429 no 6º cartão ou na 6ª tentativa da hora. Grava em `saved_cards` e devolve só `saved_card_id`, `last4` e a bandeira. |
| `create-charge` | jogador do grupo | Pix com QR, ou cartão com `authorizeOnly` a partir de `saved_card_id`. Recusa número, CVV e validade. O percentual do split sai da tabela de comissão, não do celular. |
| `settle-charges` | host, casa ou admin | Grupo fechado: captura o cartão e lança o extrato. Grupo que não fechou: estorna Pix pago e cancela a autorização do cartão. |
| `cancel-house-group` | dono da casa ou admin | Cancela o grupo (`house_cancel_group`) e, com a service role, estorna o Pix ou cancela a autorização. `refunded` só depois da resposta da API ou do webhook. |
| `asaas-webhook` | não | Exige o header `asaas-access-token` igual a `ASAAS_WEBHOOK_TOKEN`. Quando a cobrança fica paga e o grupo está fechado, emite as NFS-e. |
| `configure-venue-fiscal` | dono ou admin | Grava inscrição municipal, código de serviço e alíquota. Casa com CPF fica `sem_emissao`. Com a chave da subconta, chama `POST /v3/fiscalInfo`. A senha da prefeitura não é gravada. |
| `invoice-document` | dono, jogador ou admin | Baixa PDF ou XML da nota que o RLS deixa ver. No sandbox o arquivo é de teste. |

Segredos, no painel da função (nunca no repositório):

| Nome | Valor na demo |
| --- | --- |
| `ASAAS_API_KEY` | chave da conta raiz do sandbox |
| `ASAAS_BASE_URL` | `https://api-sandbox.asaas.com/v3` |
| `ASAAS_WEBHOOK_TOKEN` | string sua, de 32 a 255 caracteres, sem espaço. Não use a API key. |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` a plataforma já injeta na função.

Deploy, na sua máquina, depois da revisão:

```bash
supabase functions deploy provision-venue-wallet
supabase functions deploy tokenize-card
supabase functions deploy create-charge
supabase functions deploy settle-charges
supabase functions deploy cancel-house-group
supabase functions deploy asaas-webhook --no-verify-jwt
supabase functions deploy configure-venue-fiscal
supabase functions deploy invoice-document
supabase secrets set ASAAS_API_KEY=… ASAAS_BASE_URL=https://api-sandbox.asaas.com/v3 ASAAS_WEBHOOK_TOKEN=…
```

No painel do Asaas sandbox, o webhook aponta para `https://eujlhicairvksvmssruz.supabase.co/functions/v1/asaas-webhook` com o mesmo token. Eventos: `PAYMENT_RECEIVED`, `PAYMENT_CONFIRMED`, `PAYMENT_REFUNDED` e `PAYMENT_AUTHORIZED`.

A ScapeMatch Demo não recebe `walletId` no SQL. Com a chave já gravada, entre como admin e chame `provision-venue-wallet` sem `venue_id` (ou com o id da demo). Ela cria a subconta sandbox. O sandbox limita 20 subcontas por dia. Estornar um Pix logo depois de pago pode falhar se a taxa do Asaas deixar o saldo insuficiente: deixe saldo na conta raiz do sandbox.

O Asaas não oferece SDK de navegador para tokenizar o cartão. Quem recebe número, CVV e validade é só `tokenize-card`: ela autentica o JWT, chama `POST /v3/creditCard/tokenizeCreditCard` e grava o token em `saved_cards`, ligado ao `user_id` e ao customer Asaas dele. A resposta leva só `saved_card_id`, `last4` e a bandeira. O app chama essa função primeiro e, em seguida, `create-charge` só com `saved_card_id`. A cobrança (`authorizeOnly` e o split) usa o token salvo dessa pessoa. Se o body da cobrança trouxer número, CVV ou validade, a função responde 400 e não chama o Asaas. O token não volta para o app. `my_saved_cards()` devolve só o id interno, os 4 últimos dígitos e a bandeira. A chave da API também não volta na resposta. Erro de tokenização volta genérico, sem o corpo do Asaas. O teto é 5 cartões por jogador e 5 tentativas por hora, contando as que falham. Estourar qualquer um responde 429 e não chama o Asaas.

## NFS-e

Por reserva paga e com o grupo fechado, nascem duas linhas em `fiscal_invoices`. A subconta da casa emite a NFS-e do serviço para o jogador (`POST /v3/invoices` e em seguida `/authorize`). A conta raiz emite só a NFS-e da comissão, contra a casa. Casa com CPF recebe o split e a nota de serviço fica `sem_emissao`. CNPJ ou MEI sem inscrição municipal, código de serviço ou alíquota de ISS também fica sem emissão.

No sandbox (`ASAAS_BASE_URL` com `api-sandbox.asaas.com`) a função não chama `/v3/invoices`. Ela grava status `simulated`, um número `TESTE-…` e links de PDF e XML. Em produção, troque `ASAAS_API_KEY` e `ASAAS_BASE_URL` para `https://api.asaas.com/v3`. A configuração fiscal da plataforma, se quiser outra que não o padrão, entra em `ASAAS_FISCAL_SERVICE_CODE`, `ASAAS_FISCAL_SERVICE_NAME` e `ASAAS_FISCAL_ISS`.

A `apiKey` da subconta volta só na criação da conta Asaas. `provision-venue-wallet` grava em `venue_asaas_keys`. Essa tabela não tem política de leitura para o app. A resposta da função continua só com `wallet_id`.

O jogador lê a nota de serviço em que `player_user_id` é ele. O dono da casa lê as notas da casa, inclusive a comissão. Admin lê tudo. Não há `insert` para `anon` nem `authenticated`.

O aceite chama `accept_terms('player')` ou `accept_terms('partner', venue_id)`. A função grava a versão `2026-11-06` e `now()`. O app não escolhe a data.
