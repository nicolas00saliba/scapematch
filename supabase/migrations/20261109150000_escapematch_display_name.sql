-- Rótulos visíveis da marca. A função e as tabelas não mudam de nome.
-- Bancos que já rodaram a migration antiga continuam com o texto antigo
-- até esta aqui.

create or replace function public.commission_board()
returns table (
  venue_id uuid,
  venue_name text,
  commission_bps integer,
  is_override boolean,
  updated_by uuid,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if not private.is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  return query
  select
    null::uuid,
    'EscapeMatch'::text,
    s.commission_bps,
    false,
    s.updated_by,
    s.updated_at
  from public.platform_settings s
  where s.id = 1;
  return query
  select
    v.id,
    v.name,
    coalesce(c.commission_bps, s.commission_bps),
    c.venue_id is not null,
    c.updated_by,
    c.updated_at
  from public.venues v
  cross join public.platform_settings s
  left join public.venue_commissions c on c.venue_id = v.id
  where s.id = 1
  order by v.name;
end;
$$;

update public.venues
set name = 'EscapeMatch Demo'
where name = 'ScapeMatch Demo';
