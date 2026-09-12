CREATE OR REPLACE FUNCTION public.get_clientes_acervo()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select coalesce(json_agg(x order by x->>'nome'),'[]'::json) into v from (
    select json_build_object(
      'id', c.id,
      'nome', c.nome,
      'cidade', coalesce(c.cidade, (select o2.cidade from obras o2 where o2.cliente_id=c.id and o2.cidade is not null limit 1)),
      'telefone', c.telefone,
      'obras', (select count(*) from obras o where o.cliente_id=c.id),
      'contratos', (select string_agg(o.contrato,', ' order by o.contrato) from obras o where o.cliente_id=c.id and o.contrato is not null),
      'kwp_total', (select coalesce(sum(u.potencia_kwp),0) from usinas u where u.cliente_id=c.id and u.ativa),
      'usinas', (select count(*) from usinas u where u.cliente_id=c.id and u.ativa),
      'usinas_paradas', (select count(*) from usinas u where u.cliente_id=c.id and u.ativa
                          and u.status_atual is not null and u.status_atual <> 'operando'),
      'nota', (select max(n.nota) from nps n join obras o on o.id=n.obra_id where o.cliente_id=c.id),
      'relatorios', (select count(*) from obra_relatorios r join obras o on o.id=r.obra_id where o.cliente_id=c.id),
      'detalhe', (select coalesce(json_agg(json_build_object(
            'obra_id', o.id, 'contrato', o.contrato, 'status', o.status,
            'concluida', o.data_conclusao, 'slug', o.slug,
            'usinas', (select coalesce(json_agg(json_build_object(
                 'apelido', u.apelido, 'kwp', u.potencia_kwp, 'papel', ou.papel,
                 'status', u.status_atual, 'desde', u.status_desde,
                 'conta_retorno', (fracao_polaris(o.id,u.id) > 0)
               ) order by ou.papel, u.apelido),'[]'::json)
               from obra_usina ou join usinas u on u.id=ou.usina_id
               where ou.obra_id=o.id and ou.saiu_em is null),
            'relatorios', (select coalesce(json_agg(json_build_object(
                 'id', r.id, 'titulo', r.titulo, 'origem', r.origem, 'url', r.url, 'data', r.data_referencia
               ) order by r.data_referencia desc nulls last),'[]'::json)
               from obra_relatorios r where r.obra_id=o.id)
          ) order by o.data_conclusao desc nulls first),'[]'::json)
        from obras o where o.cliente_id=c.id)
    ) as x
    from clientes c
  ) t;
  return v;
end $function$
