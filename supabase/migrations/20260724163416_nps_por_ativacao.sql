-- NPS passa a considerar TAMBÉM a ativação do sistema (etapa 8)
create or replace function public.obras_para_nps()
returns table (id uuid, cliente text, slug text, nps_token text, whatsapp_grupo_id text)
language sql security definer set search_path to 'public' as $$
  select o.id, o.cliente, o.slug, o.nps_token, o.whatsapp_grupo_id
  from obras o
  where o.nps_enviado_em is null
    and o.whatsapp_grupo_id is not null
    and (
      -- 1 dia após a ativação do sistema
      (o.etapa_numero >= 8 and coalesce(o.data_conclusao, current_date) <= current_date - 1)
      or
      -- ou 2 dias após o termo assinado (obras que assinam mas ainda não ativaram)
      (o.aceite_em is not null and o.aceite_em <= now() - interval '2 days')
    )
  limit 20;
$$;
revoke execute on function public.obras_para_nps() from public, anon, authenticated;

-- Marcar envio manual da pesquisa (pelo painel)
create or replace function public.marcar_nps_enviado(p_obra uuid)
returns json language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.is_autorizado() then return json_build_object('erro','Não autorizado'); end if;
  update obras set nps_enviado_em = now() where id = p_obra;
  return json_build_object('ok', true);
end; $$;
grant execute on function public.marcar_nps_enviado(uuid) to authenticated;
