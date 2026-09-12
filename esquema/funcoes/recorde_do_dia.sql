CREATE OR REPLACE FUNCTION public.recorde_do_dia(p_usina uuid)
 RETURNS TABLE(elegivel boolean, motivo text, dia_recorde date, kwh_recorde numeric, recorde_anterior numeric, ganho_pct numeric, dias_historico integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_min int; v_margem numeric; v_meses int;
begin
  select coalesce((select valor::int from config where chave='recorde_min_dias'),90) into v_min;
  select coalesce((select valor::numeric from config where chave='recorde_margem'),0.08) into v_margem;
  select coalesce((select valor::int from config where chave='recorde_intervalo_meses'),6) into v_meses;

  return query
  with hist as (
    select d.dia as d_dia, d.kwh as d_kwh from usina_dia d
    where d.usina_id=p_usina and d.dia < current_date and d.kwh > 0
  ), tot as (select count(*)::int as n from hist),
  ultimo as (select h.d_dia, h.d_kwh from hist h order by h.d_dia desc limit 1),
  antes as (select max(h.d_kwh) as pico from hist h
            where h.d_dia < (select u2.d_dia from ultimo u2)),
  ja as (select count(*)::int as n from regua_contatos rc
         where rc.usina_id=p_usina and rc.modelo='geracao_recorde'
           and rc.data_programada >= current_date - (v_meses||' months')::interval)
  select
    (t.n >= v_min and a.pico is not null and u.d_kwh > a.pico*(1+v_margem)
       and j.n = 0 and u.d_dia >= current_date - 3),
    case
      when t.n < v_min then 'histórico curto: '||t.n||' de '||v_min||' dias'
      when a.pico is null then 'sem base de comparação'
      when j.n > 0 then 'já avisamos nos últimos '||v_meses||' meses'
      when u.d_kwh <= a.pico*(1+v_margem) then 'não superou em '||round(v_margem*100)||'%'
      when u.d_dia < current_date - 3 then 'recorde antigo'
      else 'recorde novo'
    end,
    u.d_dia, round(u.d_kwh,1), round(a.pico,1),
    case when a.pico > 0 then round((u.d_kwh/a.pico - 1)*100) end,
    t.n
  from tot t, ultimo u, antes a, ja j;
end $function$
