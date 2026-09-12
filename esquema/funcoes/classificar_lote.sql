CREATE OR REPLACE FUNCTION public.classificar_lote(p_itens jsonb)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_financeiro() then return null; end if;
  select coalesce(json_agg(classificar_movimento(
           x->>'memo', coalesce((x->>'valor')::numeric, 0)
         ) order by ord), '[]'::json)
    into v
  from jsonb_array_elements(p_itens) with ordinality t(x, ord);
  return v;
end; $function$
