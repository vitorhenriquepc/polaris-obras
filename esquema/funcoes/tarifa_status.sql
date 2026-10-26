CREATE OR REPLACE FUNCTION public.tarifa_status()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select json_build_object(
    'valor_atual', (select valor::numeric from config where chave='economia_por_kwh'),
    'desde', (select max(vigente_desde) from tarifa_historico),
    'provisorio', (select origem is distinct from 'calibrado com conta real'
                     from tarifa_historico
                    order by vigente_desde desc, id desc limit 1),
    'desde_conta_real', (select max(vigente_desde) from tarifa_historico
                          where origem = 'calibrado com conta real'),
    -- meses desde a ultima calibracao COM CONTA REAL, nao desde a ultima linha
    'meses_sem_calibrar', (select (extract(year from age(current_date, max(vigente_desde)))*12
                                 + extract(month from age(current_date, max(vigente_desde))))::int
                            from tarifa_historico
                           where origem = 'calibrado com conta real'),
    'reajuste_cpfl', 'todo ano em abril (aniversario contratual dia 8)',
    'ultimo_reajuste_conhecido', '22/04/2026 — +9,15% para residencial',
    'historico', (select coalesce(json_agg(json_build_object(
        'valor', h.valor, 'desde', h.vigente_desde, 'origem', h.origem, 'obs', h.observacao)
        order by h.vigente_desde desc),'[]'::json) from tarifa_historico h)
  );
$function$
