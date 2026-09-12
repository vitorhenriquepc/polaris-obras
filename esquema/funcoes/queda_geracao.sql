CREATE OR REPLACE FUNCTION public.queda_geracao(p_usina uuid)
 RETURNS TABLE(caiu boolean, motivo text, razao_recente numeric, dias_bons integer, pct_mes numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (
    select coalesce((select valor::numeric from config where chave='ger_desvio_alerta'),0.25) as desvio,
           coalesce((select valor::int from config where chave='ger_queda_min_dias'),5) as min_dias
  ),
  -- so dias com sol de verdade e com medicao confiavel
  d as (
    select x.razao, x.dia
    from usina_dias(p_usina, 21) x
    where x.razao is not null and not x.sem_medicao
      and coalesce(x.indice,0) > 1.5
    order by x.dia desc limit 10
  ),
  agg as (select count(*)::int as n, round(avg(razao),2) as media from d),
  mes as (select m.pct from usina_meses(p_usina) m
          where m.completo and m.kwh>0 and m.referencia < date_trunc('month',current_date)
          order by m.referencia desc limit 1),
  est as (select e.estado from usina_estado(p_usina) e)
  select
    (a.n >= c.min_dias and a.media < (1 - c.desvio) and e.estado = 'normal'),
    case
      when e.estado <> 'normal' then 'usina em '||e.estado||' — outro tipo de aviso'
      when a.n < c.min_dias then 'poucos dias de sol para comparar ('||a.n||')'
      when a.media >= (1 - c.desvio) then 'dentro do padrao dela ('||round(a.media*100)||'%)'
      else 'gerando '||round(a.media*100)||'% do padrao dela nos ultimos '||a.n||' dias de sol'
    end,
    a.media, a.n, mes.pct
  from cfg c, agg a, est e left join mes on true;
$function$
