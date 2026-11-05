# Revisão das funções SECURITY DEFINER em `public`

Inventário do estado **depois** de aplicar as migrations, no Postgres 16 do CI.
Nada aqui foi alterado: é a proposta para uma revisão seguinte.

Saíram de `public` em `20261105113000_private_security_definer.sql` e não
entram nesta lista: `is_admin`, `owns_venue`, `venue_is_visible`,
`room_photo_object_allowed`, `is_group_member`, `group_is_readable`.
Elas estão em `private` e são o que as policies chamam.

Nenhuma policy RLS cita função de `public`. O app Flutter e as Edge
Functions também não chamam `private` pelo nome. Chamam RPC de `public`.

`anon` e `PUBLIC` ficam sem `USAGE` em `private`
(`20261105170000_revoke_private_schema_usage.sql`). `authenticated` e
`service_role` mantêm o `USAGE`. O motivo está naquela migration: quatro
wrappers `SECURITY INVOKER` (`check_venue_duplicates`,
`request_venue_claim`, `review_venue`, `review_venue_claim`) resolvem
`private.*` com o papel de quem chama. Eles não são `SECURITY DEFINER`
e por isso não estão na tabela abaixo.

Várias funções ainda usam `search_path = public`. Isso fica fora desta
proposta.

## Manter DEFINER em `public`

O corpo lê ou grava o que o RLS do chamador não deixa. O RPC precisa
continuar no schema exposto, senão o `/rest/v1/rpc` deixa de publicá-lo.
Virar `INVOKER` faria a mesma chamada passar a obedecer o RLS e falhar,
ou devolver menos linhas.

| Função | Quem chama | Por quê continua DEFINER |
| --- | --- | --- |
| `accept_terms(text, uuid)` | App jogador e app Parceiro | Insere em `terms_acceptances`. `authenticated` só tem `SELECT`. No aceite da casa consulta `private.owns_venue`. |
| `block_user(uuid)` | App jogador (`supabase_social_repository`) | Confere o perfil da outra pessoa, que `profiles_select` esconde, e grava `friendships` sem policy de escrita. |
| `close_group_with_fewer(uuid)` | App jogador | Atualiza `groups`. Só existe policy de `SELECT`. |
| `confirm_attendance(uuid)` | App jogador | Atualiza `group_members`. Só existe policy de `SELECT`. |
| `create_crew(text, text, uuid[])` | App jogador | Insere `crews` e `crew_members` e chama `users_are_friends` / `post_app_notice`. |
| `create_group(uuid, integer, text)` | App jogador | Cria grupo e membro. As tabelas não têm policy de escrita para o jogador. |
| `create_group_with_party(uuid, integer, text, uuid[])` | App jogador | O mesmo, para o criador e os acompanhantes. |
| `decline_waitlist(uuid)` | App jogador | Apaga a própria linha em `waitlist`. O papel não tem `DELETE` na tabela. |
| `delete_crew(uuid)` | App jogador | Marca a turma como apagada e os membros como saíram. Sem policy de escrita. |
| `delete_group(uuid)` | App jogador | Cancela o grupo e avisa. Sem policy de escrita. |
| `edit_group(uuid, integer, text)` | App jogador | Atualiza vagas e nota. Sem policy de escrita. |
| `house_cancel_group(uuid, text)` | Edge Function `cancel-house-group`, com o JWT de quem chama | Cancela o grupo da casa. Checa `private.owns_venue` e grava o que o dono não atualiza direto. |
| `join_group(uuid)` | App jogador | Entra no grupo, conta vagas e vê sobreposição fora do RLS. |
| `join_group_with_party(uuid, uuid[])` | App jogador | O mesmo, com acompanhantes. |
| `join_waitlist(uuid)` | App jogador | Insere em `waitlist` sem policy de `INSERT`. |
| `leave_crew(uuid)` | App jogador | Sai da turma. Sem policy de escrita. |
| `leave_group(uuid)` | App jogador | Sai do grupo e pode oferecer a vaga. Sem policy de escrita. |
| `list_my_crews()` | App jogador | Lista turmas e nomes. `profiles_select` não mostra o perfil dos outros. |
| `list_my_friends()` | App jogador | Junta `friendships` com `profiles` de outras pessoas. |
| `mark_absence(uuid, uuid)` | App Parceiro | Insere em `absences` depois de `private.owns_venue`. Sem policy de `INSERT`. |
| `mark_notice_read(uuid)` | Ninguém no app nem nas Edge Functions. `EXECUTE` está concedido a `authenticated` | Atualiza `app_notices`. O papel só tem `SELECT`. Enquanto o grant existir, o RPC fica em `public`. |
| `my_friend_invite()` | App jogador | Lê ou cria o código em `friend_invites`. Sem policy de `INSERT`. |
| `my_saved_cards()` | App jogador | `saved_cards` não tem grant para `authenticated`. Devolve id, final e bandeira, sem o token. |
| `remove_friend(uuid)` | App jogador | Apaga amizade. Sem policy de `DELETE`. |
| `remove_member(uuid, uuid)` | App jogador | Tira membro. Sem policy de escrita. |
| `request_friend_by_invite(text)` | App jogador | Acha o convite e cria o pedido. O código de outra pessoa não aparece no RLS. |
| `request_friend_by_username(text)` | App jogador | Acha o perfil pelo username. `profiles_select` só mostra o próprio. |
| `respond_crew(uuid, boolean)` | App jogador | Aceita ou recusa a turma. Sem policy de escrita. |
| `respond_friendship(uuid, boolean)` | App jogador | Aceita ou recusa o pedido. Sem policy de escrita. |
| `unblock_user(uuid)` | App jogador | Apaga o bloqueio. Sem policy de `DELETE`. |
| `venue_private(uuid)` | App Parceiro | Devolve documento, telefone, renda, wallet e indicação. Essas colunas não têm `SELECT` para `authenticated`. |

## Pode virar INVOKER, ainda em `public`

O app chama as duas. O corpo não atravessa o RLS.

| Função | Quem chama | Por quê pode virar INVOKER |
| --- | --- | --- |
| `accept_waitlist(uuid)` | App jogador | Só lê a própria linha de `waitlist` (a policy já permite) e delega a escrita a `join_group`, que continua DEFINER. |
| `set_my_username(text)` | Ninguém no app nem nas Edge Functions. `EXECUTE` está concedido a `authenticated` | Atualiza `profiles.username` da própria linha. A policy de update e o grant da coluna já cobrem isso. `profiles_guard` só trava `asaas_customer_id`. |

## Mover para `private` e manter DEFINER

Não são RPC de produto. `EXECUTE` de `anon` e `authenticated` já foi
revogado. Em `public` elas ainda nascem no schema da API. O corpo precisa
ver linhas ou colunas que o chamador não vê, então `INVOKER` mudaria o
resultado no dia em que o chamador deixasse de ser o dono.

| Função | Quem chama | Por quê fica DEFINER em `private` |
| --- | --- | --- |
| `group_filled_spots(uuid)` | Outras funções de grupo e `offer_waitlist` | Conta membros que `group_members_select` esconderia. A view `groups_with_counts` não a usa: ela conta em subquery. |
| `handle_new_user()` | Trigger `on_auth_user_created` em `auth.users` | Insere `profiles` quando o auth cria o usuário. O papel do auth não precisa ter `INSERT` em `profiles`. |
| `offer_waitlist(uuid)` | `leave_group`, `remove_member` e o fluxo de vaga | Atualiza `waitlist` de outras pessoas. |
| `post_app_notice(uuid, text, text, text, uuid, text)` | Funções de grupo, amigos, `house_cancel_group` e `delete_group` | Insere aviso para outro usuário. `app_notices` não tem policy de `INSERT`. |
| `profile_display_name(uuid)` | Funções de grupo | Lê o nome de qualquer perfil para gravar no membro. |
| `saved_cards_guard()` | Trigger `saved_cards_guard` em `saved_cards` | Confere o customer Asaas no perfil. Quem grava o cartão é a service role. |
| `saved_cards_limit()` | Trigger `saved_cards_limit` em `saved_cards` | Conta os cartões da pessoa antes de aceitar outro. |
| `user_has_overlap(uuid, timestamptz, integer, uuid)` | Funções de entrar e criar grupo | Vê grupos e membros que o RLS esconderia. Como `INVOKER`, uma sessão oculta deixaria de bloquear a sobreposição. |
| `venue_link_status(uuid)` | Ninguém no app nem nas Edge Functions. `EXECUTE` só de `service_role` | Lê `possible_duplicate_of` e `merged_into`, colunas sem `SELECT` para `authenticated`. |
| `venues_normalize()` | Trigger `venues_normalize` em `venues` | Normaliza o documento e enxerga `document_digits` de outras casas, coluna sem `SELECT` para o papel. |

## Pode virar INVOKER e ir para `private`

O trigger ou o helper não precisa do privilégio do dono. Fora de `public`
eles deixam de aparecer no schema da API.

| Função | Quem chama | Por quê |
| --- | --- | --- |
| `profiles_guard()` | Trigger `profiles_guard` em `profiles` | Só copia `asaas_customer_id` antigo para o novo. Não lê outra linha. |
| `users_are_friends(uuid, uuid)` | `create_crew` | Hoje roda dentro de uma função DEFINER, então como INVOKER ainda executa como o dono. Se `create_crew` também virar INVOKER, `friendships_select` já mostra a amizade de quem chama. |
| `venue_claims_guard()` | Trigger `venue_claims_guard` em `venue_claims` | Só força campos de `NEW` e lê casa aprovada ou a pendente do próprio dono, que as policies já mostram. `private.is_admin` segue DEFINER. |
| `venues_guard()` | Trigger `venues_guard` em `venues` | Força dono, status e wallet em `NEW`. Convite ativo e cidade são legíveis pelas policies. `private.is_admin` segue DEFINER. |
