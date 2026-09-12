CREATE OR REPLACE FUNCTION public.espelha_preco_na_ficha()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_valor numeric;
begin
  if coalesce(new.preco_negociado,0) <= 0 then
    select valor_projeto into v_valor from obras where id = new.obra_id;
    if coalesce(v_valor,0) > 0 then new.preco_negociado := v_valor; end if;
  end if;
  return new;
end $function$
