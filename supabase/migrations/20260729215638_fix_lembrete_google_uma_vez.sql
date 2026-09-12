-- 1. Apenas UM lembrete por cliente
update public.config set valor = '1' where chave = 'lembrete_google_max';

-- 2. Parar imediatamente os envios pendentes (marca como já avisado)
update public.nps
set lembretes_google = 1,
    lembrete_google_em = coalesce(lembrete_google_em, now())
where nota >= 9 and avaliou_google_em is null and lembretes_google = 0;

-- 3. RPC retorna também se já tem voucher, para adaptar a mensagem
drop function if exists public.nps_para_lembrete_google();
create function public.nps_para_lembrete_google()
returns table (obra_id uuid, cliente text, slug text, nps_token text, whatsapp_grupo_id text,
               brinde text, voucher text, lembretes smallint)
language sql security definer set search_path to 'public' as $$
  select o.id, o.cliente, o.slug, o.nps_token, o.whatsapp_grupo_id,
         n.brinde, n.voucher, n.lembretes_google
  from nps n
  join obras o on o.id = n.obra_id
  where n.nota >= 9
    and n.avaliou_google_em is null
    and o.whatsapp_grupo_id is not null
    and n.lembretes_google < (select valor::int from config where chave = 'lembrete_google_max')
    and coalesce(n.lembrete_google_em, n.criado_em)
        <= now() - ((select valor::int from config where chave = 'lembrete_google_dias') || ' days')::interval
  limit 20;
$$;
revoke execute on function public.nps_para_lembrete_google() from public, anon, authenticated;

-- 4. Registrar o lembrete pelo obra_id (não pelo voucher, que pode ser nulo)
create or replace function public.registrar_lembrete_google(p_obra uuid)
returns json language plpgsql security definer set search_path to 'public' as $$
begin
  update nps
  set lembretes_google = coalesce(lembretes_google, 0) + 1,
      lembrete_google_em = now()
  where obra_id = p_obra;
  return json_build_object('ok', found);
end; $$;
revoke execute on function public.registrar_lembrete_google(uuid) from public, anon, authenticated;
