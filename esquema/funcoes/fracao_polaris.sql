CREATE OR REPLACE FUNCTION public.fracao_polaris(p_obra uuid, p_usina uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select case
    when ou.papel = 'herdada' then 0
    when ou.medicao = 'inversor_proprio' then 1
    else least(1, coalesce(ou.kwp_parte,0) / nullif(u.potencia_kwp,0))
  end
  from obra_usina ou join usinas u on u.id = ou.usina_id
  where ou.obra_id = p_obra and ou.usina_id = p_usina;
$function$
