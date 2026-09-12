CREATE OR REPLACE FUNCTION public.get_extrato_pendentes(p_conta uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_financeiro() then return null; end if;
  select json_build_object(
    'contas', (
      select coalesce(json_agg(x order by x->>'ultima' desc),'[]'::json) from (
        select json_build_object(
          'conta_id', cb.id, 'banco', cb.banco, 'apelido', cb.apelido,
          'pendentes', count(*) filter (where m.situacao='pendente'),
          'conciliados', count(*) filter (where m.situacao='conciliado'),
          'descartados', count(*) filter (where m.situacao='descartado'),
          'total', count(*),
          'periodo_ini', min(m.data_mov), 'periodo_fim', max(m.data_mov),
          'ultima', max(m.importado_em)
        ) as x
        from extrato_movimentos m join contas_bancarias cb on cb.id=m.conta_id
        group by cb.id, cb.banco, cb.apelido
      ) t
    ),
    'itens', (
      select coalesce(json_agg(json_build_object(
        'id', m.id, 'fitid', m.fitid, 'data', m.data_mov, 'valor', m.valor,
        'memo', m.memo, 'situacao', m.situacao, 'classificacao', m.classificacao,
        'conta_id', m.conta_id, 'banco', cb.apelido,
        'duplicata', case when m.duplicata_de is not null then
          json_build_object('id', l.id, 'data', l.data_competencia, 'valor', l.valor,
                            'descricao', l.descricao, 'por', l.criado_por) else null end,
        -- o que foi criado a partir deste movimento
        'destino', case when m.situacao='conciliado' then (
          select coalesce(json_agg(json_build_object(
            'valor', r.valor,
            'conta', (select c2.nome from dre_plano_contas c2 where c2.codigo=r.conta_codigo),
            'obra', (select ob.cliente from obras ob where ob.id=r.obra_id),
            'contrato', (select ob.contrato from obras ob where ob.id=r.obra_id)
          )),'[]'::json) from extrato_rateio r where r.movimento_id=m.id
        ) else null end
      ) order by m.situacao, m.data_mov, m.id), '[]'::json)
      from extrato_movimentos m
      join contas_bancarias cb on cb.id = m.conta_id
      left join dre_lancamentos l on l.id = m.duplicata_de
      where m.situacao in ('pendente','conciliado')
        and (p_conta is null or m.conta_id = p_conta)
      limit 500
    )
  ) into v;
  return v;
end; $function$
