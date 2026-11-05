-- Wrappers do Parceiro viram SECURITY DEFINER para o authenticated
-- perder USAGE em private. O corpo em private continua checando
-- auth.uid(), admin e dono. Nada aqui é aplicado no banco remoto.
--
-- Inventário de docs/security/security-definer-review.md:
-- accept_waitlist e set_my_username ficam em public e viram INVOKER.
-- Dez auxiliares vão para private e continuam DEFINER.
-- profiles_guard e users_are_friends vão para private e viram INVOKER.
-- venue_claims_guard e venues_guard vão para private e continuam
-- DEFINER. INVOKER fica para outro PR: sem USAGE, o gatilho do
-- authenticated não resolve private.is_admin() e a gravação da casa
-- falha com 42501.
-- As SECURITY DEFINER que ainda usavam search_path = public passam a
-- search_path vazio. Os nomes no corpo já eram qualificados; as
-- chamadas das funções movidas passam a private.*.

alter function public.check_venue_duplicates(text, text, text, text, text)
  security definer;
alter function public.request_venue_claim(uuid, text, uuid)
  security definer;
alter function public.review_venue(uuid, text, uuid)
  security definer;
alter function public.review_venue_claim(uuid, text)
  security definer;

alter function public.group_filled_spots(uuid) set schema private;
alter function public.handle_new_user() set schema private;
alter function public.offer_waitlist(uuid) set schema private;
alter function public.post_app_notice(uuid, text, text, text, uuid, text)
  set schema private;
alter function public.profile_display_name(uuid) set schema private;
alter function public.saved_cards_guard() set schema private;
alter function public.saved_cards_limit() set schema private;
alter function public.user_has_overlap(uuid, timestamp with time zone, integer, uuid)
  set schema private;
alter function public.venue_link_status(uuid) set schema private;
alter function public.venues_normalize() set schema private;
alter function public.venue_claims_guard() set schema private;
alter function public.venues_guard() set schema private;
alter function public.profiles_guard() set schema private;
alter function public.users_are_friends(uuid, uuid) set schema private;

alter function public.accept_waitlist(uuid) security invoker;
alter function public.set_my_username(text) security invoker;
alter function private.profiles_guard() security invoker;
alter function private.users_are_friends(uuid, uuid) security invoker;

-- Reescreve só o search_path e o schema das chamadas internas.
-- O restante do corpo, inclusive as checagens, permanece o que já
-- estava gravado.
do $rewrite$
declare
  r record;
  def text;
  original text;
  fname text;
  names text[] := array[
    'group_filled_spots',
    'handle_new_user',
    'offer_waitlist',
    'post_app_notice',
    'profile_display_name',
    'saved_cards_guard',
    'saved_cards_limit',
    'user_has_overlap',
    'venue_link_status',
    'venues_normalize',
    'profiles_guard',
    'users_are_friends',
    'venue_claims_guard',
    'venues_guard'
  ];
begin
  create temp table rewrite_funcs on commit drop as
  select p.oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and p.prokind = 'f';

  for r in
    select
      f.oid,
      p.prosecdef,
      n.nspname,
      p.proname
    from rewrite_funcs f
    join pg_proc p on p.oid = f.oid
    join pg_namespace n on n.oid = p.pronamespace
  loop
    original := pg_get_functiondef(r.oid);
    def := original;
    foreach fname in array names loop
      def := replace(
        def,
        'public.' || fname || '(',
        'private.' || fname || '('
      );
    end loop;
    if r.prosecdef
      or (r.nspname = 'public' and r.proname in ('accept_waitlist', 'set_my_username'))
      or (r.nspname = 'private' and r.proname in ('profiles_guard', 'users_are_friends'))
    then
      def := replace(
        def,
        'SET search_path TO ''public''',
        'SET search_path TO '''''
      );
    end if;
    if def is distinct from original then
      execute def;
    end if;
  end loop;
end
$rewrite$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function private.profiles_guard();

drop trigger if exists venues_guard on public.venues;
create trigger venues_guard
  before insert or update on public.venues
  for each row execute function private.venues_guard();

drop trigger if exists venues_normalize on public.venues;
create trigger venues_normalize
  before insert or update on public.venues
  for each row execute function private.venues_normalize();

drop trigger if exists venue_claims_guard on public.venue_claims;
create trigger venue_claims_guard
  before insert or update on public.venue_claims
  for each row execute function private.venue_claims_guard();

drop trigger if exists saved_cards_guard on public.saved_cards;
create trigger saved_cards_guard
  before insert or update on public.saved_cards
  for each row execute function private.saved_cards_guard();

drop trigger if exists saved_cards_limit on public.saved_cards;
create trigger saved_cards_limit
  before insert on public.saved_cards
  for each row execute function private.saved_cards_limit();

revoke all on function private.group_filled_spots(uuid)
  from public, anon, authenticated;
revoke all on function private.handle_new_user()
  from public, anon, authenticated;
revoke all on function private.offer_waitlist(uuid)
  from public, anon, authenticated;
revoke all on function private.post_app_notice(uuid, text, text, text, uuid, text)
  from public, anon, authenticated;
revoke all on function private.profile_display_name(uuid)
  from public, anon, authenticated;
revoke all on function private.saved_cards_guard()
  from public, anon, authenticated;
revoke all on function private.saved_cards_limit()
  from public, anon, authenticated;
revoke all on function private.user_has_overlap(uuid, timestamp with time zone, integer, uuid)
  from public, anon, authenticated;
revoke all on function private.venue_link_status(uuid)
  from public, anon, authenticated;
revoke all on function private.venues_normalize()
  from public, anon, authenticated;
revoke all on function private.venue_claims_guard()
  from public, anon, authenticated;
revoke all on function private.venues_guard()
  from public, anon, authenticated;
revoke all on function private.profiles_guard()
  from public, anon, authenticated;
revoke all on function private.users_are_friends(uuid, uuid)
  from public, anon, authenticated;

revoke usage on schema private from anon, public, authenticated;
grant usage on schema private to service_role;

do $check$
declare
  v_left text;
  v_name text;
  v_definer boolean;
begin
  foreach v_name in array array[
    'group_filled_spots(uuid)',
    'handle_new_user()',
    'offer_waitlist(uuid)',
    'post_app_notice(uuid, text, text, text, uuid, text)',
    'profile_display_name(uuid)',
    'saved_cards_guard()',
    'saved_cards_limit()',
    'user_has_overlap(uuid, timestamp with time zone, integer, uuid)',
    'venue_link_status(uuid)',
    'venues_normalize()',
    'venue_claims_guard()',
    'venues_guard()',
    'profiles_guard()',
    'users_are_friends(uuid, uuid)'
  ]
  loop
    if to_regprocedure('public.' || v_name) is not null
      or to_regprocedure('private.' || v_name) is null
    then
      raise exception 'função não saiu de public: %', v_name;
    end if;
  end loop;

  select p.prosecdef
    into v_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'profiles_guard';
  if v_definer then
    raise exception 'profiles_guard continua security definer';
  end if;
  select p.prosecdef
    into v_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'users_are_friends';
  if v_definer then
    raise exception 'users_are_friends continua security definer';
  end if;
  select p.prosecdef
    into v_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'accept_waitlist';
  if v_definer then
    raise exception 'accept_waitlist continua security definer';
  end if;
  select p.prosecdef
    into v_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'set_my_username';
  if v_definer then
    raise exception 'set_my_username continua security definer';
  end if;
  if not (
    select bool_and(p.prosecdef)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('venues_guard', 'venue_claims_guard')
  ) then
    raise exception 'gatilho da casa perdeu security definer';
  end if;

  select string_agg(n.nspname || '.' || p.proname, ', ')
    into v_left
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and p.prosecdef
    and not ('search_path=""' = any (coalesce(p.proconfig, array[]::text[])));
  if v_left is not null then
    raise exception 'security definer ainda sem search_path vazio: %', v_left;
  end if;

  select string_agg(n.nspname || '.' || p.proname, ', ')
    into v_left
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and p.prosrc ~ 'public\.(group_filled_spots|handle_new_user|offer_waitlist|post_app_notice|profile_display_name|saved_cards_guard|saved_cards_limit|user_has_overlap|venue_link_status|venues_normalize|profiles_guard|users_are_friends|venue_claims_guard|venues_guard)\(';
  if v_left is not null then
    raise exception 'chamada antiga em public: %', v_left;
  end if;

  if has_schema_privilege('authenticated', 'private', 'usage')
    or has_schema_privilege('anon', 'private', 'usage')
    or has_schema_privilege('public', 'private', 'usage')
    or not has_schema_privilege('service_role', 'private', 'usage')
  then
    raise exception 'usage de private não ficou só no service_role';
  end if;
end
$check$;
