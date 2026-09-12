CREATE OR REPLACE FUNCTION public.get_relatorios_painel()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select coalesce(json_agg(x order by x->>'cliente'),'[]'::json) into v from (
    select json_build_object(
      'obra_id', o.id, 'cliente', o.cliente, 'contrato', o.contrato,
      'cidade', o.cidade, 'slug', o.slug, 'status', o.status,
      'etapa', o.etapa_numero, 'trilha', coalesce(o.trilha,'padrao'),
      'concluida', o.data_conclusao,
      'assinado', (o.aceite_em is not null),
      'obrig', (select count(*) from checklist_itens ci
                left join obra_itens_relatorio ov on ov.item_id=ci.id and ov.obra_id=o.id
                where ci.obrigatorio and coalesce(ci.trilha,'padrao')=coalesce(o.trilha,'padrao')
                  and not coalesce(ov.oculto,false)),
      'feitos', (select count(distinct f.item_id) from fotos f
                 join checklist_itens ci on ci.id=f.item_id
                 left join obra_itens_relatorio ov on ov.item_id=ci.id and ov.obra_id=o.id
                 where f.obra_id=o.id and ci.obrigatorio
                   and coalesce(ci.trilha,'padrao')=coalesce(o.trilha,'padrao')
                   and not coalesce(ov.oculto,false)),
      'fotos_total', (select count(*) from fotos f where f.obra_id=o.id),
      'anexos', (select count(*) from obra_relatorios r where r.obra_id=o.id),
      'arquivos', (select coalesce(json_agg(json_build_object(
            'id', r.id, 'titulo', r.titulo, 'url', r.url, 'origem', r.origem,
            'data', r.data_referencia, 'tamanho', r.tamanho_bytes,
            'criado', r.criado_em
          ) order by r.criado_em desc),'[]'::json)
        from obra_relatorios r where r.obra_id=o.id)
    ) as x
    from obras o
    where o.status <> 'Cancelado'
      and ((coalesce(o.trilha,'padrao')='manutencao' and o.etapa_numero>=2)
        or (coalesce(o.trilha,'padrao')<>'manutencao' and o.etapa_numero>=6))
  ) t;
  return v;
end $function$
