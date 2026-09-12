CREATE OR REPLACE FUNCTION public.get_posvenda_usinas()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json; v_boa numeric; v_at numeric;
begin
  if not is_autorizado() then return null; end if;
  select coalesce((select valor::numeric from config where chave='ger_faixa_boa'),0.85) into v_boa;
  select coalesce((select valor::numeric from config where chave='ger_faixa_atencao'),0.70) into v_at;
  with base as (
    select u.id as usina_id, u.apelido, u.potencia_kwp, u.cidade, u.fator_local,
           u.status_atual, u.nota_geracao, u.data_instalacao,
           u.causa, u.causa_nota, u.cliente_avisado_em,
           c.nome as cliente, o.id as obra_id, o.contrato,
           (o.optout_em is not null) as saiu, ou.papel,
           e.estado, e.motivo, e.gravidade, e.dias_sem_gerar,
           rotulo_usina(e.estado, u.causa) as rotulo,
           (select x.pct from usina_meses(u.id) x
             where x.kwh>0 and x.completo and x.referencia < date_trunc('month', current_date)
             order by x.referencia desc limit 1) as pct,
           (select to_char(x.referencia,'MM/YYYY') from usina_meses(u.id) x
             where x.kwh>0 and x.completo and x.referencia < date_trunc('month', current_date)
             order by x.referencia desc limit 1) as ref_pct,
           (select round(sum(d.kwh)) from usina_dia d
             where d.usina_id=u.id and d.dia >= current_date - 14) as kwh_14d
    from usinas u
    join clientes c on c.id=u.cliente_id
    join obra_usina ou on ou.usina_id=u.id and ou.saiu_em is null
    join obras o on o.id=ou.obra_id
    cross join lateral usina_estado(u.id) e
    where u.ativa
  ), marcado as (
    select *, case
        when pct is null then 'sem_base'
        when pct >= v_boa*100 then 'boa'
        when pct >= v_at*100 then 'atencao'
        else 'baixa' end as desempenho
    from base
  )
  select json_build_object(
    'resumo', (select json_build_object(
        'total', count(*),
        'normal', count(*) filter (where estado='normal'),
        'sem_comunicacao', count(*) filter (where estado='sem comunicação'),
        'parada', count(*) filter (where estado='parada'),
        'critico', count(*) filter (where estado='crítico'),
        'silencioso', count(*) filter (where estado='silencioso'),
        'nunca_gerou', count(*) filter (where estado='nunca gerou'),
        'sem_dado', count(*) filter (where estado='sem dado'),
        'alerta', count(*) filter (where estado='alerta'),
        'com_causa', count(*) filter (where causa is not null),
        'boa', count(*) filter (where desempenho='boa'),
        'atencao', count(*) filter (where desempenho='atencao'),
        'baixa', count(*) filter (where desempenho='baixa'),
        'sem_base', count(*) filter (where desempenho='sem_base'),
        'kwp', round(coalesce(sum(potencia_kwp),0)::numeric,2)) from marcado),
    'usinas', (select coalesce(json_agg(json_build_object(
        'usina_id', usina_id, 'apelido', apelido, 'kwp', potencia_kwp, 'cidade', cidade,
        'cliente', cliente, 'contrato', contrato, 'obra_id', obra_id, 'papel', papel,
        'estado', estado, 'rotulo', rotulo, 'motivo', motivo, 'gravidade', gravidade,
        'zerado', dias_sem_gerar, 'causa', causa, 'avisado', (cliente_avisado_em is not null),
        'desempenho', desempenho, 'pct', pct, 'ref_pct', ref_pct, 'fator', fator_local,
        'kwh_14d', kwh_14d, 'nota', nota_geracao, 'saiu', saiu)
      order by (case when causa is not null then 1 else 0 end), gravidade,
               dias_sem_gerar desc, pct nulls last, cliente),'[]'::json) from marcado)
  ) into v;
  return v;
end $function$
