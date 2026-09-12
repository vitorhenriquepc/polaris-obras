CREATE OR REPLACE FUNCTION public.valida_obra_usina()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_kwp numeric; v_soma numeric;
begin
  select potencia_kwp into v_kwp from usinas where id = new.usina_id;
  if new.medicao='compartilhado' and v_kwp is not null and coalesce(new.kwp_parte,0) > v_kwp then
    raise exception 'A parte informada (% kWp) e maior que a usina inteira (% kWp).', new.kwp_parte, v_kwp;
  end if;
  select coalesce(sum(kwp_parte),0) into v_soma from obra_usina
   where usina_id=new.usina_id and medicao='compartilhado' and id <> coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid);
  if new.medicao='compartilhado' and v_kwp is not null and v_soma + coalesce(new.kwp_parte,0) > v_kwp + 0.01 then
    raise exception 'A soma das partes (% kWp) passa a potencia da usina (% kWp).', v_soma+new.kwp_parte, v_kwp;
  end if;
  if new.papel <> 'herdada' and exists (
      select 1 from usinas u where u.id=new.usina_id and u.instalador_terceiro is not null) then
    raise notice 'Atencao: usina marcada como instalada por terceiro esta sendo ligada como %', new.papel;
  end if;
  return new;
end $function$
