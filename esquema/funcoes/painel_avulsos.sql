CREATE OR REPLACE FUNCTION public.painel_avulsos(p_ini date, p_fim date)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_financeiro() then return null; end if;
  select json_build_object(
    'receita', coalesce(sum(valor) filter (where natureza='receita'),0),
    'despesa', coalesce(sum(valor) filter (where natureza='despesa'),0),
    'qtd', count(*),
    'por_tipo', (select coalesce(json_agg(json_build_object(
        'tipo',t.nome,'icone',t.icone,'qtd',x.q,'valor',x.v) order by x.v desc),'[]'::json)
      from (select tipo, count(*) q, sum(valor) v from servicos_avulsos
            where data_servico between p_ini and p_fim and natureza='receita'
            group by tipo) x join tipos_avulso t on t.codigo=x.tipo),
    'clientes_recorrentes', (select coalesce(json_agg(json_build_object(
        'cliente',c.cliente,'vezes',c.n,'total',c.t) order by c.n desc),'[]'::json)
      from (select cliente, count(*) n, sum(valor) t from servicos_avulsos
            where natureza='receita' group by lower(cliente), cliente
            having count(*) > 1 limit 10) c)
  ) into v from servicos_avulsos where data_servico between p_ini and p_fim;
  return v;
end; $function$
