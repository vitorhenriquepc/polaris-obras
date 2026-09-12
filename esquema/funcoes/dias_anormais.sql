CREATE OR REPLACE FUNCTION public.dias_anormais(p_dias integer DEFAULT 7)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  with fator as (
    select d.usina_id,
           percentile_cont(0.5) within group (order by d.kwh_kwp / nullif(i.mediana_kwh_kwp,0)) as f
    from usina_dia d join v_indice_dia i on i.dia=d.dia
    where d.dia >= current_date - 60 and d.kwh_kwp is not null and i.mediana_kwh_kwp > 0.5
    group by d.usina_id
  )
  select coalesce(json_agg(x order by (x->>'dia') desc, (x->>'razao')),'[]'::json) into v from (
    select json_build_object(
      'usina_id', u.id, 'usina', u.apelido, 'cliente', c.nome, 'contrato', o.contrato,
      'dia', d.dia, 'kwh', round(d.kwh,1),
      'razao', round((d.kwh_kwp / nullif(i.mediana_kwh_kwp * f.f,0))::numeric,2),
      'carteira', i.mediana_kwh_kwp) as x
    from usina_dia d
    join usinas u on u.id=d.usina_id and u.ativa
    join clientes c on c.id=u.cliente_id
    join obra_usina ou on ou.usina_id=u.id and ou.saiu_em is null
    join obras o on o.id=ou.obra_id
    join v_indice_dia i on i.dia=d.dia
    join fator f on f.usina_id=u.id
    where d.dia >= current_date - p_dias
      and d.dia < current_date
      and i.mediana_kwh_kwp > 1.5
      and f.f > 0
      and d.kwh_kwp < i.mediana_kwh_kwp * f.f * 0.5
  ) t;
  return v;
end $function$
