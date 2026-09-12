CREATE OR REPLACE FUNCTION public.calibrar_fatores(p_aplicar boolean DEFAULT false, p_min_meses integer DEFAULT 2)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  with completos as (
    select g.usina_id, g.referencia, g.kwh, p.kwh_previsto,
           (g.kwh / nullif(p.kwh_previsto,0)) as razao
    from usina_geracao g
    join usinas u on u.id=g.usina_id
    join usina_previsao p on p.usina_id=u.id and p.mes=extract(month from g.referencia)
    where g.kwh > 0 and u.data_instalacao is not null
      and u.data_instalacao <= date_trunc('month', g.referencia)::date
      and g.referencia < date_trunc('month', current_date)
  ), agrupado as (
    select usina_id, count(*) as meses,
           round(percentile_cont(0.5) within group (order by razao)::numeric, 3) as fator_sugerido,
           round(min(razao)::numeric,2) as pior, round(max(razao)::numeric,2) as melhor
    from completos group by usina_id having count(*) >= p_min_meses
  )
  select json_agg(json_build_object(
      'usina_id', a.usina_id, 'cliente', c.nome, 'apelido', u.apelido,
      'meses', a.meses, 'fator_atual', u.fator_local, 'fator_sugerido', a.fator_sugerido,
      'variacao', a.melhor - a.pior
    ) order by a.fator_sugerido)
  into v
  from agrupado a join usinas u on u.id=a.usina_id join clientes c on c.id=u.cliente_id;

  if p_aplicar then
    update usinas u set fator_local = a.fator_sugerido,
                        fator_origem = 'calibrado pelo histórico',
                        fator_em = now()
    from (
      select g.usina_id, round(percentile_cont(0.5) within group (order by (g.kwh/nullif(p.kwh_previsto,0)))::numeric,3) as fator_sugerido
      from usina_geracao g
      join usinas u2 on u2.id=g.usina_id
      join usina_previsao p on p.usina_id=u2.id and p.mes=extract(month from g.referencia)
      where g.kwh>0 and u2.data_instalacao is not null
        and u2.data_instalacao <= date_trunc('month',g.referencia)::date
        and g.referencia < date_trunc('month', current_date)
      group by g.usina_id having count(*) >= p_min_meses
    ) a
    where u.id=a.usina_id and u.fator_local is null;
  end if;

  return coalesce(v,'[]'::json);
end $function$
