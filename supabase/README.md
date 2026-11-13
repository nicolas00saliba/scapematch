# Supabase do EscapeMatch

O app não aplica estas migrações sozinho. A ordem é a do nome do arquivo. No SQL Editor do projeto `eujlhicairvksvmssruz` (região sa-east-1), rode um arquivo por vez, de cima para baixo, ou use a CLI com a sua conta:

```bash
supabase link --project-ref eujlhicairvksvmssruz
supabase db push
```

## Ordem

1. `migrations/20261104120000_init.sql` — tabelas, cinco cidades e a comissão inicial. `20261111163545_commission_default_25.sql` leva o padrão intocado para 25% (2500 bps).
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

`seed_demo.sql` fica **fora** dessa lista. É opcional e cria a casa real EscapeMatch Demo (Curitiba, três salas, horários e duas promoções). Não é dado de exemplo do app.

Não há `service_role`, chave do Asaas nem chave da Stability nestes arquivos. As funções leem o gateway só de `Deno.env`.

## O que você faz depois de aplicar

1. Authentication → Providers → Email. Deixe e-mail e senha ligados. Para a demonstração de sábado, desligue **Confirm email**. Com a confirmação ligada, o cadastro do jogador e o da casa abrem a tela de sucesso (check verde, o e-mail e os botões de ir ao login ou reenviar). A casa só grava a venue depois que a sessão existe.
2. Crie a sua conta de admin no app do jogador (ou no Parceiro) e pegue o UUID em Authentication → Users.
3. Rode no SQL Editor, trocando o UUID:

```sql
insert into public.admins (user_id) values ('00000000-0000-0000-0000-000000000000');
```

4. No Parceiro, entre com essa conta. A fila **Aprovar casas** lista as venues `pending`. Aprovar grava `approved`. Só então o jogador vê a casa, as salas e as notícias.
5. Storage: o bucket `room-photos` é privado. Não há URL pública. O caminho é `{venue_id}/{room_id}/{arquivo}`. O app pede uma signed URL (`createSignedUrl`). A leitura passa por `room_photo_object_allowed`: casa aprovada, o dono ou um admin. Foto de casa pendente não abre para anônimo. Quem envia, troca e apaga é o dono da casa. Não coloque documento privado nesse bucket.

## E-mails de autenticação

Os HTML ficam em `supabase/templates/` e os assuntos em `supabase/config.toml` (`[auth.email.template.*]`). São cinco: confirmação de cadastro, redefinição de senha, magic link, troca de e-mail e convite. O desenho usa a paleta do app (verde-petróleo `#0F4C4A`, cobre `#9A4F24`, fundo `#F5F1EA`), tabelas e CSS inline. A marca é texto, sem imagem nem outro recurso remoto. Cada mensagem tem um botão, o mesmo link em texto e a linha de que o link leva a `app.escapematch.com.br`. As variáveis são as do Supabase (`{{ .ConfirmationURL }}`, `{{ .Email }}`, `{{ .SiteURL }}` e, na troca, `{{ .NewEmail }}`).

Nada disso foi aplicado no projeto remoto por este repositório. Duas formas de publicar:

1. Painel: Authentication > Email Templates. Em cada tipo (Confirm signup, Reset password, Magic Link, Change Email, Invite user), cole o assunto do `config.toml` e o HTML do arquivo correspondente.
2. API, na sua máquina, com um token seu (não grave o token no repositório):

```bash
export SUPABASE_ACCESS_TOKEN="..."
tool/apply_auth_email_templates.sh
```

`tool/apply_auth_email_templates.sh --dry-run` só mostra os assuntos e o tamanho de cada HTML. O PATCH vai para `https://api.supabase.com/v1/projects/eujlhicairvksvmssruz/config/auth`, nos campos `mailer_subjects_*` e `mailer_templates_*_content`.

## Regras que o banco segura

- A casa só lê e escreve salas, fotos, horários, notícias e promoções dela. Falta não tem insert direto: entra por `mark_absence`. O gatilho `venues_guard` impede a casa de se aprovar.
- Documento repetido (só os dígitos) não entra de novo enquanto a casa não foi recusada nem mesclada. `check_venue_duplicates` devolve o tipo do conflito e, se a casa já foi aprovada, o id e o nome público. Não devolve documento, telefone nem dados de casa pendente de outra pessoa. CEP + número, ou nome parecido na mesma cidade, não bloqueia: o cadastro segue com `possible_duplicate_of`.
- "Esta casa é minha?" grava `venue_claims`. Anon não lê essa tabela. A pessoa vê o próprio pedido; o admin vê a fila, aprova, recusa ou mescla. Aprovar a reivindicação passa a casa aprovada para quem pediu. A prova de posse do perfil que já existe está em `20261113200000_venue_claim_official.sql`: o código sai do contato oficial, e a aprovação só liga a casa se ela estiver aprovada, com `claimed_at` nulo e dono diferente de quem pediu.
- O jogador anônimo lê cidade e o que é de casa aprovada. Em `venues`, não lê `document_number`, `phone`, `income_value`, `asaas_wallet_id`, `referred_by`, `reviewed_by`, `invite_id` nem `owner_id`. O catálogo usa a view `venues_vitrine` (o `select *` na tabela falha para o anon). Grupo, cadeira e falta não têm `insert` direto.
- Quem está logado também não lê documento, telefone, renda, wallet nem quem indicou. O dono ou um admin lê isso em `venue_private`. A Edge Function lê a tabela com `service_role`. O logado continua vendo `owner_id`.
- `delete_group` recusa quando falta menos de 2 horas para o início. No instante exato das 2 horas ainda exclui.
- `close_group_with_fewer` não encolhe mais o grupo. A confirmação é automática no mínimo do host e o grupo segue aberto até o máximo.
- O Pix é cobrado na hora (`billingType PIX`) e estornado se o grupo não confirmar. O cartão nasce com `authorizeOnly` e só é capturado quando o grupo atinge o mínimo; se o prazo vence sem o mínimo, a reserva é estornada. Quem entra depois do mínimo paga a própria parte na hora.
- O split manda `(100% − comissão)` para `venues.asaas_wallet_id`. A comissão é `platform_settings.commission_bps` (padrão 2500, 25%, se o Admin não tiver gravado outra) e fica na conta Asaas que cria a cobrança. Uma casa com linha em `venue_commissions` fica na taxa dela.
- Scape Points (`20261108140000_scape_points.sql`, `20261108150000_payer_cpf_gate.sql`, `20261108160000_referral_payer_antifraud.sql` e `20261108170000_modelo2_complete.sql`) lançam a indicação quando a cobrança fica paga. Pagamento por terceiro libera. O pagador que é o próprio indicador não gera a indicação dele. O mesmo pagador premia no máximo 3 contas. Contas do mesmo indicador no mesmo aparelho ficam `em_revisao`. O desconto de 20% da primeira reserva qualificada sai da comissão e abaixa só a parte do jogador. O crédito B2C/B2B libera em 30 dias e entra no split da próxima cobrança da casa. O cashback de 1% (`cashback_bps`) entra em toda reserva paga, sem as travas do pagador, e também sai da comissão. A casa não perde líquido. O cron de reconcile libera o que completou 30 dias e não está em revisão. O app não escreve no ledger.

## Asaas (sandbox na demo)

A implementação é `AsaasProvider` em `supabase/functions/_shared/asaas_provider.ts`. O app não chama `api-sandbox.asaas.com`. Quem chama é a Edge Function.

| Função | JWT | O que faz |
| --- | --- | --- |
| `provision-venue-wallet` | admin | Cria a subconta (`POST /v3/accounts`) e grava só o `walletId`. A `apiKey` da subconta não é salva. |
| `tokenize-card` | jogador autenticado | Única função que recebe número, CVV e validade. O IP sai do header da borda, nunca do body. Antes do Asaas, `private.claim_card_tokenize_attempt` (só service role) registra a tentativa e recusa com 429 no 6º cartão ou na 6ª tentativa da hora. Grava o token cifrado por `insert_saved_card` e devolve só `saved_card_id`, `last4` e a bandeira. |
| `create-charge` | jogador do grupo | Pix com QR, ou cartão com `authorizeOnly` a partir de `saved_card_id`. O token é lido por `load_owned_card`. Recusa número, CVV e validade. O percentual do split sai da tabela de comissão, não do celular. `points` opcional abate a parte do jogador e reserva o saldo antes do Asaas. |
| `settle-charges` | host, casa ou admin | Grupo confirmado no mínimo: captura o cartão e lança o extrato. Prazo sem o mínimo: estorna Pix pago e cancela a autorização do cartão. |
| `cancel-house-group` | dono da casa ou admin | Cancela o grupo (`house_cancel_group`) e, com a service role, estorna o Pix ou cancela a autorização. `refunded` só depois da resposta da API ou do webhook. |
| `asaas-webhook` | não | Exige o header `asaas-access-token` igual a `ASAAS_WEBHOOK_TOKEN`. Quando a cobrança fica paga e o grupo já confirmou, emite as NFS-e. |
| `configure-venue-fiscal` | dono ou admin | Grava inscrição municipal, código de serviço e alíquota. Casa com CPF fica `sem_emissao`. Com a chave da subconta, chama `POST /v3/fiscalInfo`. A senha da prefeitura não é gravada. |
| `invoice-document` | dono, jogador ou admin | Baixa PDF ou XML da nota que o RLS deixa ver. No sandbox o arquivo é de teste. Não usa service role. |
| `venue-documents` | dono ou sócio | `GET /v3/myAccount/documents` e `GET /v3/myAccount/status` com a chave da subconta. Se o grupo traz `onboardingUrl`, a tela abre esse link (cadastro.io) e não faz upload. Sem o link, `POST /v3/myAccount/documents/{id}` manda o arquivo. A chave não volta na resposta. |

## service role

A service role ignora o RLS. Cada função abaixo chama `getUser()` com a chave anônima e o JWT do pedido antes de abrir o cliente de service role, e só age para esse usuário.

| Função | Por que a service role | O que confere antes |
| --- | --- | --- |
| `tokenize-card` | Grava o token cifrado e a tentativa. O jogador não tem grant na tabela nem nas funções de cifra. | JWT. O `user_id` gravado é o do `getUser()`. |
| `create-charge` | Lê o token com `load_owned_card` e grava a cobrança. O jogador não lê a coluna. | JWT e, em seguida, a vaga dele em `group_members`. |
| `settle-charges` | Captura, estorna e lança o extrato de grupos que o cliente não pode varrer. | JWT. `canSettle`: admin, quem criou o grupo ou o dono da casa. A varredura `sweep` exige admin. |
| `cancel-house-group` | Estorna as cobranças depois do cancelamento. | JWT. O cancelamento passa por `house_cancel_group` no cliente do usuário. Liberar um grupo já cancelado exige admin, criador ou dono da casa. |
| `provision-venue-wallet` | Cria a subconta e grava `walletId` e a chave da subconta, que o app não lê. | JWT. Admin pode provisionar em lote. O dono provisiona só a casa dele, e só quando `asaas_wallet_id` está vazio. |
| `venue-claim` | Emite e confirma o código de reivindicação. O código e o contato oficial não voltam na resposta. | JWT. O usuário do código é o `getUser()`, nunca o body. |
| `configure-venue-fiscal` | Grava a configuração fiscal e chama o Asaas com a chave da subconta. | JWT e dono da casa ou admin. |
| `asaas-webhook` | Atualiza cobrança, extrato e nota a partir do evento do Asaas. Não há JWT de usuário: é servidor a servidor, com `verify_jwt = false`. | Header `asaas-access-token` comparado com `ASAAS_WEBHOOK_TOKEN` (`tokensMatch`) antes de criar o cliente. |

`invoice-document` fica de fora: usa só o cliente do usuário, e o RLS da nota decide o que ele baixa.

Segredos, no painel da função (nunca no repositório):

| Nome | Valor na demo |
| --- | --- |
| `ASAAS_API_KEY` | chave da conta raiz do sandbox |
| `ASAAS_BASE_URL` | `https://api-sandbox.asaas.com/v3` |
| `ASAAS_WEBHOOK_TOKEN` | string sua, de 32 a 255 caracteres, sem espaço. Não use a API key. |
| `ASAAS_SUBACCOUNT_EMAIL_DOMAIN` | opcional. Domínio do alias da subconta (`parceiros+<venue_id>@domínio`). Sem a variável, usa `escapematch.com.br` e registra um aviso no log. Um valor que não é domínio também cai nesse fallback, com aviso. |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` a plataforma já injeta na função.

`ALLOWED_ORIGINS` é opcional. Lista de origens exatas separadas por vírgula; o espaço ao redor da vírgula é ignorado. Sem essa variável, o CORS aceita `https://nicolas00saliba.github.io` e os subdomínios `app`, `parceiro`, `demo`, `parceiro-demo`, `www` e o apex de `escapematch.com.br` e de `scapematch.com.br`. O domínio antigo fica na lista enquanto o 301 da virada estiver no ar. `*` não é aceito. `http://localhost` e `http://127.0.0.1` (com porta) só entram quando `SUPABASE_URL` aponta para o Supabase local. Pedido sem `Origin` (webhook e app nativo) continua recebendo JSON, sem `Access-Control-Allow-Origin`.

Deploy, na sua máquina, depois da revisão:

```bash
supabase functions deploy provision-venue-wallet
supabase functions deploy venue-claim
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

A EscapeMatch Demo não recebe `walletId` no SQL. Com a chave já gravada, entre como admin e chame `provision-venue-wallet` sem `venue_id` (ou com o id da demo). Ela cria a subconta sandbox. O sandbox limita 20 subcontas por dia. Estornar um Pix logo depois de pago pode falhar se a taxa do Asaas deixar o saldo insuficiente: deixe saldo na conta raiz do sandbox.

O Asaas não oferece SDK de navegador para tokenizar o cartão. Quem recebe número, CVV e validade é só `tokenize-card`: ela autentica o JWT, chama `POST /v3/creditCard/tokenizeCreditCard` e grava o token em `saved_cards`, ligado ao `user_id` e ao customer Asaas dele. O `remoteIp` que o Asaas pede sai de `x-real-ip`, depois de `cf-connecting-ip`, e só então do último endereço de `x-forwarded-for`. Endereço vazio ou inválido é descartado. Sem header válido, o pedido segue sem `remoteIp`. Um `remote_ip` no body é ignorado. A resposta leva só `saved_card_id`, `last4` e a bandeira. O app chama essa função primeiro e, em seguida, `create-charge` só com `saved_card_id`. A cobrança (`authorizeOnly` e o split) usa o token salvo dessa pessoa, lido por `load_owned_card`. Se o body da cobrança trouxer número, CVV ou validade, a função responde 400 e não chama o Asaas. O token não volta para o app. `my_saved_cards()` devolve só o id interno, os 4 últimos dígitos e a bandeira. Em repouso a coluna é `bytea` cifrada com `pgp_sym_encrypt`; a chave fica no vault (`card_token_key`) e as funções de gravar e ler estão em `private`, com `execute` só para a service role. A chave da API também não volta na resposta. Erro de tokenização volta genérico, sem o corpo do Asaas. O teto é 5 cartões por jogador e 5 tentativas por hora, contando as que falham. Estourar qualquer um responde 429 e não chama o Asaas.

## NFS-e

Por reserva paga e com o grupo confirmado, nascem duas linhas em `fiscal_invoices`. A subconta da casa emite a NFS-e do serviço para o jogador (`POST /v3/invoices` e em seguida `/authorize`). A conta raiz emite só a NFS-e da comissão, contra a casa. Casa com CPF recebe o split e a nota de serviço fica `sem_emissao`. CNPJ ou MEI sem inscrição municipal, código de serviço ou alíquota de ISS também fica sem emissão.

No sandbox (`ASAAS_BASE_URL` com `api-sandbox.asaas.com`) a função não chama `/v3/invoices`. Ela grava status `simulated`, um número `TESTE-…` e links de PDF e XML. Em produção, troque `ASAAS_API_KEY` e `ASAAS_BASE_URL` para `https://api.asaas.com/v3`. A emissão fica desligada até `ASAAS_INVOICE_EMISSION=on`. Sem isso, a nota que seria enviada fica `scheduled`, sem chamar o Asaas, e a cobrança segue. Com a chave ligada, uma trava `processing` impede emissão dupla. Falha por certificado ou Asaas indisponível fica `error` e pode ser tentada de novo até 5 vezes. Uma linha `processing` parada há 15 minutos procura a nota existente antes de criar outra. A configuração fiscal da plataforma, se quiser outra que não o padrão, entra em `ASAAS_FISCAL_SERVICE_CODE`, `ASAAS_FISCAL_SERVICE_NAME` e `ASAAS_FISCAL_ISS`.

A `apiKey` da subconta volta só na criação da conta Asaas. `provision-venue-wallet` grava em `venue_asaas_keys`. Essa tabela não tem política de leitura para o app. A resposta da função continua só com `wallet_id`.

O jogador lê a nota de serviço em que `player_user_id` é ele. O dono da casa lê as notas da casa, inclusive a comissão. Admin lê tudo. Não há `insert` para `anon` nem `authenticated`.

O aceite chama `accept_terms('player')` ou `accept_terms('partner', venue_id)`. A função grava a versão `2026-11-06` e `now()`. O app não escolhe a data.
