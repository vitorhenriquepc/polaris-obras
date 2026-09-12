CREATE OR REPLACE FUNCTION public.manutencao_usinas()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_prev int := 0; v_cal int := 0; r record; v_hsp jsonb; v_pr numeric; v_dias int; m int;
begin
  select valor::jsonb into v_hsp from config where chave='hsp_mensal';
  select valor::numeric into v_pr from config where chave='perf_ratio';

  for r in select id as uid, potencia_kwp as kwp from usinas
           where ativa and coalesce(potencia_kwp,0) > 0
             and not exists (select 1 from usina_previsao p where p.usina_id = usinas.id)
  loop
    for m in 1..12 loop
      v_dias := extract(day from (date_trunc('month', make_date(2026,m,1)) + interval '1 month - 1 day'));
      insert into usina_previsao (usina_id, mes, kwh_previsto, fonte, atualizado_por)
      values (r.uid, m, round((r.kwp * (v_hsp->>m::text)::numeric * v_pr * v_dias)::numeric, 0),
              'estimado', 'cálculo automático')
      on conflict (usina_id, mes) do nothing;
    end loop;
    v_prev := v_prev + 1;
  end loop;

  if coalesce((select valor from config where chave='ger_calibra_auto'),'1') = '1' then
    with completos as (
      select g.usina_id as uid,
             round(percentile_cont(0.5) within group
                   (order by (g.kwh / nullif(p.kwh_previsto,0)))::numeric, 3) as fator
      from usina_geracao g
      join usinas x on x.id = g.usina_id and x.ativa
      join usina_previsao p on p.usina_id = x.id and p.mes = extract(month from g.referencia)
      where g.kwh > 0 and x.data_instalacao is not null
        and x.data_instalacao <= date_trunc('month', g.referencia)::date
        and g.referencia < date_trunc('month', current_date)
      group by g.usina_id
      having count(*) >= coalesce((select valor::int from config where chave='ger_calibra_min_meses'),2)
    )
    update usinas set fator_local = c.fator,
                      fator_origem = 'calibrado pelo histórico',
                      fator_em = now()
    from completos c
    where usinas.id = c.uid
      and coalesce(usinas.fator_origem,'') <> 'ajustado à mão'
      and (usinas.fator_local is null or abs(usinas.fator_local - c.fator) > 0.05);
    get diagnostics v_cal = row_count;
  end if;

  return json_build_object('ok', true, 'previsoes_criadas', v_prev, 'fatores_calibrados', v_cal,
    'sem_fator', (select count(*) from usinas where ativa and fator_local is null));
end $function$
