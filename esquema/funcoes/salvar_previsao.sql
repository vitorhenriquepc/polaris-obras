CREATE OR REPLACE FUNCTION public.salvar_previsao(p_usina uuid, p_mes integer, p_kwh numeric)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  if p_mes < 1 or p_mes > 12 then return json_build_object('erro','mes invalido'); end if;
  if p_kwh is null or p_kwh < 0 then return json_build_object('erro','valor invalido'); end if;
  insert into usina_previsao (usina_id, mes, kwh_previsto, fonte, atualizado_por)
  values (p_usina, p_mes, round(p_kwh), 'proposta', coalesce(auth.email(),'equipe'))
  on conflict (usina_id, mes) do update
    set kwh_previsto=excluded.kwh_previsto, fonte='proposta',
        atualizado_em=now(), atualizado_por=excluded.atualizado_por;
  return json_build_object('ok', true);
end $function$
