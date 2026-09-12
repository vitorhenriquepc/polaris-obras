alter table public.obras add column if not exists relatorio_enviado_em timestamptz;

-- Marca como já enviado as obras que receberam relatório antes desta trava
update public.obras o
set relatorio_enviado_em = now()
where relatorio_enviado_em is null
  and exists (select 1 from fotos f where f.obra_id = o.id)
  and o.etapa_numero >= 7;

create or replace function public.get_obra_instalador(p_slug text, p_token text)
returns json language plpgsql security definer set search_path to 'public' as $$
declare v_obra record; v_result json;
begin
  select * into v_obra from obras where slug = p_slug and instalador_token = p_token;
  if not found then return null; end if;
  select json_build_object(
    'obra', json_build_object(
      'id', v_obra.id, 'cliente', v_obra.cliente, 'contrato', v_obra.contrato,
      'potencia_kwp', v_obra.potencia_kwp, 'etapa_numero', v_obra.etapa_numero,
      'data_instalacao', v_obra.data_instalacao, 'tem_grupo', v_obra.whatsapp_grupo_id is not null,
      'aceite_em', v_obra.aceite_em, 'aceite_nome', v_obra.aceite_nome,
      'relatorio_enviado_em', v_obra.relatorio_enviado_em,
      'tipo_telhado', v_obra.tipo_telhado, 'endereco', v_obra.endereco,
      'tem_estrutura', v_obra.tem_estrutura, 'tem_cabo', v_obra.tem_cabo,
      'qtd_modulos', v_obra.qtd_modulos, 'modelo_modulo', v_obra.modelo_modulo,
      'inversor_descricao', v_obra.inversor_descricao
    ),
    'itens', (select coalesce(json_agg(json_build_object('id', c.id, 'titulo', c.titulo, 'descricao', c.descricao, 'obrigatorio', c.obrigatorio) order by c.ordem), '[]'::json) from checklist_itens c),
    'fotos', (select coalesce(json_agg(json_build_object('id', f.id, 'item_id', f.item_id, 'url', f.url, 'legenda', f.legenda) order by f.criado_em), '[]'::json) from fotos f where f.obra_id = v_obra.id)
  ) into v_result;
  return v_result;
end; $$;
grant execute on function public.get_obra_instalador(text, text) to anon, authenticated;
