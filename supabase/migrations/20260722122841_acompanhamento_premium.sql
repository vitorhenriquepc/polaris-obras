-- RPC rica para o novo tracker do cliente (mantém get_obra_publica intacta)
create or replace function public.get_acompanhamento(p_slug text)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_obra record;
begin
  select * into v_obra from obras where slug = p_slug;
  if not found then return null; end if;
  return json_build_object(
    'obra', json_build_object(
      'cliente', v_obra.cliente, 'contrato', v_obra.contrato,
      'potencia_kwp', v_obra.potencia_kwp, 'etapa_numero', v_obra.etapa_numero,
      'status', v_obra.status,
      'data_fechamento', v_obra.data_fechamento, 'data_conclusao', v_obra.data_conclusao,
      'data_instalacao', v_obra.data_instalacao,
      'qtd_modulos', v_obra.qtd_modulos, 'modelo_modulo', v_obra.modelo_modulo,
      'inversor_descricao', v_obra.inversor_descricao,
      'aceite_em', v_obra.aceite_em,
      'tem_fotos', exists(select 1 from fotos f where f.obra_id = v_obra.id)
    ),
    'etapas', (select coalesce(json_agg(json_build_object(
        'numero', e.numero, 'nome', e.nome, 'icone', e.icone,
        'descricao', e.descricao, 'prazo_texto', e.prazo_texto
      ) order by e.ordem), '[]'::json) from etapas e),
    'historico', (select coalesce(json_agg(json_build_object(
        'etapa_numero', h.etapa_numero, 'entrou_em', h.entrou_em
      ) order by h.entrou_em), '[]'::json) from etapas_historico h where h.obra_id = v_obra.id),
    'fotos_destaque', (select coalesce(json_agg(t.url), '[]'::json) from (
        select f.url from fotos f where f.obra_id = v_obra.id and f.item_id in (3,5,9)
        order by f.item_id, f.criado_em limit 6
      ) t)
  );
end;
$$;
grant execute on function public.get_acompanhamento(text) to anon, authenticated;
