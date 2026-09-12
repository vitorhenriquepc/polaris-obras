CREATE OR REPLACE FUNCTION public.previsao_estimada(p_usina uuid, p_sobrescrever boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_kwp numeric; v_hsp jsonb; v_pr numeric; v_dias int; m int; n int := 0;
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  select potencia_kwp into v_kwp from usinas where id = p_usina;
  if coalesce(v_kwp,0) <= 0 then return json_build_object('erro','usina sem potencia cadastrada'); end if;
  select valor::jsonb into v_hsp from config where chave='hsp_mensal';
  select valor::numeric into v_pr from config where chave='perf_ratio';
  for m in 1..12 loop
    v_dias := extract(day from (date_trunc('month', make_date(2026,m,1)) + interval '1 month - 1 day'));
    insert into usina_previsao (usina_id, mes, kwh_previsto, fonte, atualizado_por)
    values (p_usina, m,
            round((v_kwp * (v_hsp->>m::text)::numeric * v_pr * v_dias)::numeric, 0),
            'estimado', 'cálculo automático')
    on conflict (usina_id, mes) do update
      set kwh_previsto = case when p_sobrescrever or usina_previsao.fonte='estimado'
                              then excluded.kwh_previsto else usina_previsao.kwh_previsto end,
          fonte = case when p_sobrescrever or usina_previsao.fonte='estimado'
                       then 'estimado' else usina_previsao.fonte end,
          atualizado_em = now();
    n := n + 1;
  end loop;
  return json_build_object('ok', true, 'meses', n, 'kwp', v_kwp);
end $function$
