CREATE OR REPLACE FUNCTION public.usina_retorno(p_usina uuid)
 RETURNS TABLE(investido numeric, economizado numeric, pct_retornado numeric, meses_ativa integer, media_mensal numeric, falta numeric, meses_restantes integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with u as (select * from usinas where id=p_usina),
  o as (select ob.valor_projeto, fracao_polaris(ob.id, p_usina) as fracao
        from obra_usina ou join obras ob on ob.id=ou.obra_id
        where ou.usina_id=p_usina and ou.saiu_em is null
        order by ou.principal desc limit 1),
  g as (select coalesce(sum(kwh),0) as kwh,
               count(*) filter (where kwh>0) as meses
        from usina_geracao where usina_id=p_usina),
  t as (select coalesce((select valor::numeric from config where chave='economia_por_kwh'),0.73) as tarifa)
  select
    round(o.valor_projeto,2),
    round(g.kwh * t.tarifa, 2),
    case when o.valor_projeto > 0
         then round((g.kwh * t.tarifa / o.valor_projeto * 100)::numeric, 1) end,
    g.meses::int,
    case when g.meses > 0 then round((g.kwh * t.tarifa / g.meses)::numeric, 2) end,
    round(greatest(o.valor_projeto - g.kwh * t.tarifa, 0), 2),
    case when g.meses > 0 and g.kwh > 0
         then ceil(greatest(o.valor_projeto - g.kwh*t.tarifa,0) / (g.kwh*t.tarifa/g.meses))::int end
  from u, o, g, t
  where o.fracao > 0;
$function$
