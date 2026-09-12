CREATE OR REPLACE FUNCTION public.tarifa_status()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select json_build_object(
    'valor_atual', (select valor::numeric from config where chave='economia_por_kwh'),
    'desde', (select max(vigente_desde) from tarifa_historico),
    'meses_sem_calibrar', (select (extract(year from age(current_date, max(vigente_desde)))*12
                                 + extract(month from age(current_date, max(vigente_desde))))::int
                           from tarifa_historico),
    'reajuste_cpfl', 'todo ano em abril (aniversario contratual dia 8)',
    'ultimo_reajuste_conhecido', '22/04/2026 — +9,15% para residencial',
    'historico', (select coalesce(json_agg(json_build_object(
        'valor', h.valor, 'desde', h.vigente_desde, 'obs', h.observacao)
        order by h.vigente_desde desc),'[]'::json) from tarifa_historico h)
  );
$function$
