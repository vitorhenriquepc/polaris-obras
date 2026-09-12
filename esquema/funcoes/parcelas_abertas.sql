CREATE OR REPLACE FUNCTION public.parcelas_abertas(p_obra uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_financeiro() then return null; end if;
  select coalesce(json_agg(json_build_object(
    'id',id,'numero',numero,'valor',valor,'vencimento',vencimento) order by vencimento),'[]'::json)
   into v from obra_parcelas where obra_id=p_obra and not recebida;
  return v;
end; $function$
