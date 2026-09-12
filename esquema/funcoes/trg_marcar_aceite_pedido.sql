CREATE OR REPLACE FUNCTION public.trg_marcar_aceite_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.etapa_numero >= 8 and coalesce(old.etapa_numero,0) < 8
     and new.aceite_pedido_em is null and new.aceite_em is null then
    new.aceite_pedido_em := current_date;
  end if;
  return new;
end; $function$
