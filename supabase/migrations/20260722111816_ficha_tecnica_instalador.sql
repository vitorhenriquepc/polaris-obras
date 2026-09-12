-- Ficha técnica da obra para o instalador
alter table public.obras
  add column if not exists tipo_telhado text,
  add column if not exists endereco text,
  add column if not exists tem_estrutura boolean,
  add column if not exists tem_cabo boolean;

-- RPC do instalador: incluir a ficha técnica
create or replace function public.get_obra_instalador(p_slug text, p_token text)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
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
      'tipo_telhado', v_obra.tipo_telhado, 'endereco', v_obra.endereco,
      'tem_estrutura', v_obra.tem_estrutura, 'tem_cabo', v_obra.tem_cabo,
      'qtd_modulos', v_obra.qtd_modulos, 'modelo_modulo', v_obra.modelo_modulo,
      'inversor_descricao', v_obra.inversor_descricao
    ),
    'itens', (select coalesce(json_agg(json_build_object('id', c.id, 'titulo', c.titulo, 'descricao', c.descricao, 'obrigatorio', c.obrigatorio) order by c.ordem), '[]'::json) from checklist_itens c),
    'fotos', (select coalesce(json_agg(json_build_object('id', f.id, 'item_id', f.item_id, 'url', f.url, 'legenda', f.legenda) order by f.criado_em), '[]'::json) from fotos f where f.obra_id = v_obra.id)
  ) into v_result;
  return v_result;
end;
$$;
grant execute on function public.get_obra_instalador(text, text) to anon, authenticated;

-- Agenda: incluir resumo técnico
create or replace function public.get_agenda(p_token text)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not exists (select 1 from config where chave = 'agenda_token' and valor = p_token) then
    return null;
  end if;
  return (
    select coalesce(json_agg(json_build_object(
      'cliente', o.cliente, 'contrato', o.contrato, 'potencia_kwp', o.potencia_kwp,
      'data_instalacao', o.data_instalacao, 'slug', o.slug, 'token', o.instalador_token,
      'etapa_numero', o.etapa_numero,
      'instalador', (select e.nome from equipe e where e.id = o.instalador_id),
      'tipo_telhado', o.tipo_telhado, 'endereco', o.endereco,
      'qtd_modulos', o.qtd_modulos, 'inversor_descricao', o.inversor_descricao,
      'tem_estrutura', o.tem_estrutura, 'tem_cabo', o.tem_cabo
    ) order by o.data_instalacao), '[]'::json)
    from obras o
    where o.data_instalacao is not null
      and o.data_instalacao >= current_date - interval '30 days'
  );
end;
$$;
grant execute on function public.get_agenda(text) to anon, authenticated;
