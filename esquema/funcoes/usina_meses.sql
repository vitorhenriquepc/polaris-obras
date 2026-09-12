CREATE OR REPLACE FUNCTION public.usina_meses(p_usina uuid)
 RETURNS TABLE(referencia date, kwh numeric, dias_ativos integer, dias_mes integer, previsto numeric, previsto_ajustado numeric, completo boolean, pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select g.referencia,
         g.kwh,
         greatest(0, least(
           extract(day from (date_trunc('month',g.referencia) + interval '1 month - 1 day'))::int,
           (date_trunc('month',g.referencia) + interval '1 month - 1 day')::date
             - greatest(u.data_instalacao, date_trunc('month',g.referencia)::date) + 1
         ))::int as dias_ativos,
         extract(day from (date_trunc('month',g.referencia) + interval '1 month - 1 day'))::int as dias_mes,
         p.kwh_previsto,
         round(p.kwh_previsto * coalesce(u.fator_local,1), 0) as previsto_ajustado,
         (u.data_instalacao is not null
           and u.data_instalacao <= date_trunc('month',g.referencia)::date) as completo,
         case when coalesce(p.kwh_previsto,0) > 0
              then round((g.kwh / (p.kwh_previsto * coalesce(u.fator_local,1)) * 100)::numeric, 0) end as pct
  from usina_geracao g
  join usinas u on u.id = g.usina_id
  left join usina_previsao p on p.usina_id = u.id and p.mes = extract(month from g.referencia)
  where g.usina_id = p_usina
  order by g.referencia;
$function$
