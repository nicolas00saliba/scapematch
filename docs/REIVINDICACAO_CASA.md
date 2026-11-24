# Reivindicar uma casa que já tem perfil

O cadastro do Parceiro, ao receber o CNPJ, procura uma casa existente. Se achar um perfil ainda não reivindicado, a tela oferece **Esta é a sua casa? Reivindicar**. O cadastro não abre outra casa. Fotos, salas e avaliações ficam no mesmo perfil.

O caso da Ninja Escape Room é esse: o perfil com fotos já existe. Enquanto o contato oficial estiver vazio, o pedido cai na fila manual do Admin.

## O que conta como casa reivindicável

`claimed_at` nulo e status `approved`. Um cadastro novo feito pelo próprio dono no Parceiro grava `claimed_at` na hora, então essa casa não entra na oferta.

Casas que já estavam no catálogo (criadas sem JWT de parceiro, como o perfil da Ninja) continuam com `claimed_at` nulo. Não há backfill. Elas só mudam de dono com o código ou com a aprovação do admin.

## Prova de posse

O código de 6 dígitos sai só para `venues.official_email` e `venues.official_phone`. O telefone operacional da casa e o que a pessoa digita no cadastro não recebem o código.

- Hash bcrypt, validade de 10 minutos, 5 tentativas.
- No máximo 5 envios da mesma casa por hora, 3 do mesmo usuário em 15 minutos e 60 segundos entre envios do mesmo par.
- A busca por CNPJ reusa o limite de `private.venue_duplicate_attempts` (10 por hora).
- A Edge Function `venue-claim` exige JWT (`verify_jwt = true`), chama `getUser()` e só então a service role. A resposta pública não leva o código nem o contato.
- As tabelas `private.venue_claim_codes` e `private.venue_claim_audit` não têm policy e o privilégio está revogado para `anon` e `authenticated`.
- Sem e-mail oficial e sem telefone oficial, a função abre `venue_claims` pendente. O admin aprova ou recusa. Aprovar passa `owner_id` e grava `claimed_at`.

O envio usa Resend (`RESEND_API_KEY` e `CLAIM_MAIL_FROM` ou `PAYOUT_MAIL_FROM`). SMS só entra se `VENUE_CLAIM_SMS_URL` for `https` e `VENUE_CLAIM_SMS_TOKEN` existir. Sem entrega, o código é consumido e o pedido vai para a fila manual.

## Subconta PagBank

O checklist segue nesta ordem: conta PagBank (`provision-venue-wallet`, também para o dono da própria casa quando `pagbank_account_id` está vazio), documentos da conta (`VenueDocumentsCard`, função `venue-documents`) e o recebimento. O status da conta usa `receives_payments` (coluna gerada: `pagbank_account_id` preenchido, sem entregar a wallet). Os documentos carregam quando essa coluna é verdadeira. A casa pronta é `venue_finance_ready`: aprovada, não suspensa e com `pagbank_account_id`. Não exige linha em `venue_bank_accounts`. O valor fica disponível na conta PagBank da casa. O Pix para outro banco é manual. A tela do Parceiro explica isso e não pede dados bancários.

A vitrine expõe `finance_ready`. `create-charge` chama essa função e responde 409 sem conta PagBank. A casa continua na vitrine: o catálogo não some só porque o recebimento está desligado.

## Admin

Na lista de casas, **Reivindicações pendentes** aprova ou recusa (`admin_list_venue_claims` e `admin_review_venue_claim`). Aprovar só segue se a casa está aprovada, `claimed_at` está nulo e o dono não é quem pediu. Se o update não pega uma linha, o erro é `already_claimed` e o pedido continua pendente. Os outros pedidos pendentes da mesma casa são recusados. Na ficha da casa, **Gravar contato oficial** chama `admin_set_venue_contacts`. A auditoria guarda só se havia e-mail e telefone, não o valor. As três funções exigem admin com `aal2`.

`authenticated` tem `INSERT` e `UPDATE` na tabela `venues`. O revoke dessas colunas não vale por cima do privilégio da tabela. Quem trava `official_email`, `official_phone` e `claimed_at` é o trigger `private.venues_guard`.

## Ordem

Este PR entra no `main` depois de #133, #134, #135, #136, #137 e #139. A migration é `supabase/migrations/20261113200000_venue_claim_official.sql`, depois de `20261113180000_points_reserve_outbox.sql` (#134) e de `20261113190000` da conciliação (#139). #135 usa `20261113181000`. #133 não tem migration.

No rebase, os arquivos em comum são `create-charge/index.ts` (#134), `admin_api.dart` (#137 e #139), `run_local.sh` (#136, #137 e #139), `config.toml` e `supabase/README.md`, e no Parceiro `partner_messages.dart` e `partner_keys.dart` (#133).

## Publicar

Esta migration não foi aplicada no projeto remoto. Nenhuma função foi publicada. O PagBank de produção não foi chamado.

1. Aplicar `supabase/migrations/20261113200000_venue_claim_official.sql`.
2. Publicar `venue-claim` (nova), `provision-venue-wallet` e `create-charge` (as duas já existiam e mudaram).
3. Publicar os apps Parceiro, jogador e Admin.

Segredos da função nova, no painel, nunca no repositório: `RESEND_API_KEY`, `CLAIM_MAIL_FROM` ou `PAYOUT_MAIL_FROM`. SMS é opcional (`VENUE_CLAIM_SMS_URL` em `https` e `VENUE_CLAIM_SMS_TOKEN`).
