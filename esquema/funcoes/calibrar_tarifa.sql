CREATE OR REPLACE FUNCTION public.calibrar_tarifa(p_valor numeric, p_observacao text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_antes numeric;
begin
  if not is_admin() then return json_build_object('erro','so admin pode mudar a tarifa'); end if;
  if p_valor is null or p_valor <= 0 or p_valor > 3 then
    return json_build_object('erro','valor fora do razoavel (0 a 3 R$/kWh)');
  end if;
  select valor::numeric into v_antes from config where chave='economia_por_kwh';

  insert into tarifa_historico (valor, vigente_desde, origem, observacao)
  values (p_valor, current_date, 'calibrado com conta real', p_observacao);

  update config set valor = p_valor::text where chave='economia_por_kwh';

  return json_build_object('ok', true, 'antes', v_antes, 'agora', p_valor,
    'variacao_pct', case when v_antes>0 then round((p_valor/v_antes-1)*100,1) end);
end $function$
