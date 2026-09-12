create or replace function public.get_agenda(p_token text)
returns json language plpgsql security definer set search_path to 'public' as $$
declare
  v_geral boolean := false;
  v_inst_id uuid := null;
  v_inst_nome text := null;
begin
  select exists(select 1 from config where chave = 'agenda_token' and valor = p_token)
    into v_geral;

  if not v_geral then
    select e.id, e.nome into v_inst_id, v_inst_nome
    from equipe e
    where e.agenda_token = p_token and coalesce(e.ativo, true)
    limit 1;
    if v_inst_id is null then
      return null;
    end if;
  end if;

  return json_build_object(
    'escopo', case when v_geral then 'geral' else 'instalador' end,
    'titulo', case when v_geral then 'Agenda geral' else coalesce(v_inst_nome, 'Agenda') end,
    'obras', (
      select coalesce(json_agg(json_build_object(
        'cliente', o.cliente, 'contrato', o.contrato, 'potencia_kwp', o.potencia_kwp,
        'data_instalacao', o.data_instalacao, 'slug', o.slug, 'token', o.instalador_token,
        'etapa_numero', o.etapa_numero, 'trilha', o.trilha,
        'instalador', (select e2.nome from equipe e2 where e2.id = o.instalador_id),
        'tipo_telhado', o.tipo_telhado, 'endereco', o.endereco,
        'qtd_modulos', o.qtd_modulos, 'inversor_descricao', o.inversor_descricao,
        'tem_estrutura', o.tem_estrutura, 'tem_cabo', o.tem_cabo
      ) order by o.data_instalacao), '[]'::json)
      from obras o
      where o.data_instalacao is not null
        and o.data_instalacao >= current_date - interval '30 days'
        and (v_geral or o.instalador_id = v_inst_id)
    )
  );
end; $$;
grant execute on function public.get_agenda(text) to anon, authenticated;
