-- Quem entra com Google já tem perfil: o gatilho handle_new_user roda no
-- insert de auth.users e faz on conflict (id) do nothing. O telefone e o
-- aparelho, no cadastro por e-mail, só são copiados nesse insert. Esta
-- função repete essa cópia depois que a pessoa completa o cadastro.
-- Não mexe em nome, nascimento nem aceite: isso o app grava antes.

create or replace function public.apply_signup_meta()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_device text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select raw_user_meta_data ->> 'phone',
         raw_user_meta_data ->> 'device_install_id'
    into v_phone, v_device
  from auth.users
  where id = v_uid;

  v_device := private.normalize_install_id(v_device);
  if v_device is not null then
    update public.profiles
    set device_install_id = v_device
    where id = v_uid
      and device_install_id is null;
  end if;

  v_phone := pg_catalog.regexp_replace(coalesce(v_phone, ''), '\D', '', 'g');
  if v_phone ~ '^[0-9]{10,13}$' then
    update public.profiles
    set phone = v_phone
    where id = v_uid
      and phone is null;
  end if;
end;
$$;

revoke all on function public.apply_signup_meta() from public, anon;
grant execute on function public.apply_signup_meta() to authenticated;
