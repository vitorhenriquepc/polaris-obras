CREATE OR REPLACE FUNCTION public.marcos_novos()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json; v_marcos int[]; r record; m int;
begin
  select array(select jsonb_array_elements_text(
    coalesce((select valor::jsonb from config where chave='marcos_retorno'),
             '[10,25,50,75,100]'::jsonb))::int)
    into v_marcos;

  for r in
    select u.id as usina_id, ret.pct_retornado as pct, ret.economizado
    from usinas u
    join obra_usina ou on ou.usina_id=u.id and ou.principal
    join obras o on o.id=ou.obra_id,
    lateral usina_retorno(u.id) ret
    where u.ativa and ret.pct_retornado is not null
  loop
    foreach m in array v_marcos loop
      if r.pct >= m then
        insert into usina_marco (usina_id, marco, pct_no_momento, economizado)
        values (r.usina_id, m, r.pct, r.economizado)
        on conflict (usina_id, marco) do nothing;
      end if;
    end loop;
  end loop;

  select coalesce(json_agg(json_build_object(
    'usina_id', mm.usina_id, 'marco', mm.marco, 'cliente', c.nome,
    'contrato', o.contrato, 'economizado', mm.economizado, 'quando', mm.atingido_em)
    order by mm.marco desc),'[]'::json) into v
  from usina_marco mm
  join usinas u on u.id=mm.usina_id
  join clientes c on c.id=u.cliente_id
  join obra_usina ou on ou.usina_id=u.id and ou.principal
  join obras o on o.id=ou.obra_id
  where mm.avisado_em is null;
  return v;
end $function$
