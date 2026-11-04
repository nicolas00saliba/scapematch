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
5. Storage: o bucket `room-photos` é privado. Não há URL pública. O caminho é `{venue_id}/{room_id}/{arquivo}`. O app pede uma signed URL (`createSignedUrl`). A leitura passa por `room_photo_object_allowed`: casa aprovada, o dono ou um admin. Foto de casa pendente não abre para anônimo. Quem envia, troca e apaga é o dono (`room_photo_object_owned`). Não coloque documento privado nesse bucket.

## Regras que o banco segura

- A casa só lê e escreve salas, fotos, horários, notícias e promoções dela. Falta não tem insert direto: entra por `mark_absence`. O gatilho `venues_guard` impede a casa de se aprovar.
- O jogador anônimo lê cidade e o que é de casa aprovada. Em `venues`, não lê `document_number`, `phone` nem `income_value`. O catálogo usa a view `venues_vitrine` (o `select *` na tabela falha para o anon). Grupo, cadeira e falta não têm `insert` direto.
- Quem está logado ainda lê documento, telefone e renda nas casas que o RLS entrega, inclusive nas aprovadas. A Edge Function lê esses campos com `service_role`.
- `delete_group` recusa quando falta menos de 2 horas para o início. No instante exato das 2 horas ainda exclui.
- `close_group_with_fewer` só fecha se N ≥ mínimo da sala e N < tamanho planejado.
- O Pix é cobrado na hora (`billingType PIX`) e estornado se o grupo não fechar. O cartão nasce com `authorizeOnly` e só é capturado quando o grupo fecha; se não fechar, a reserva é estornada.
- O split manda `(100% − comissão)` para `venues.asaas_wallet_id`. A comissão é `platform_settings.commission_bps` (padrão 1000, 10%) e fica na conta Asaas que cria a cobrança.

## Asaas (sandbox na demo)

A implementação é `AsaasProvider` em `supabase/functions/_shared/asaas_provider.ts`. O app não chama `api-sandbox.asaas.com`. Quem chama é a Edge Function.

| Função | JWT | O que faz |
| --- | --- | --- |
| `provision-venue-wallet` | admin | Cria a subconta (`POST /v3/accounts`) e grava só o `walletId`. A `apiKey` da subconta não é salva. |
| `create-charge` | jogador do grupo | Pix com QR, ou cartão com `authorizeOnly`. O percentual do split sai da tabela de comissão, não do celular. |
| `settle-charges` | host, casa ou admin | Grupo fechado: captura o cartão e lança o extrato. Grupo que não fechou: estorna Pix pago e a reserva do cartão. |
| `asaas-webhook` | não | Exige o header `asaas-access-token` igual a `ASAAS_WEBHOOK_TOKEN`. |

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
supabase functions deploy create-charge
supabase functions deploy settle-charges
supabase functions deploy asaas-webhook --no-verify-jwt
supabase secrets set ASAAS_API_KEY=… ASAAS_BASE_URL=https://api-sandbox.asaas.com/v3 ASAAS_WEBHOOK_TOKEN=…
```

No painel do Asaas sandbox, o webhook aponta para `https://eujlhicairvksvmssruz.supabase.co/functions/v1/asaas-webhook` com o mesmo token. Eventos: `PAYMENT_RECEIVED`, `PAYMENT_CONFIRMED`, `PAYMENT_REFUNDED` e `PAYMENT_AUTHORIZED`.

A ScapeMatch Demo não recebe `walletId` no SQL. Com a chave já gravada, entre como admin e chame `provision-venue-wallet` sem `venue_id` (ou com o id da demo). Ela cria a subconta sandbox. O sandbox limita 20 subcontas por dia. Estornar um Pix logo depois de pago pode falhar se a taxa do Asaas deixar o saldo insuficiente: deixe saldo na conta raiz do sandbox.

O número do cartão atravessa a função `create-charge` e segue para o Asaas. Ele não é gravado no banco. A chave da API também não volta na resposta.
