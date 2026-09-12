CREATE OR REPLACE FUNCTION public.get_usina_detalhe(p_usina uuid, p_dias integer DEFAULT 30)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json; v_tarifa numeric;
begin
  if not is_autorizado() then return null; end if;
  select coalesce((select valor::numeric from config where chave='economia_por_kwh'),0.73) into v_tarifa;
  select json_build_object(
    'usina', json_build_object(
       'id', u.id, 'apelido', u.apelido, 'kwp', u.potencia_kwp,
       'instalada', u.data_instalacao, 'cidade', u.cidade,
       'status', u.status_atual, 'fator', u.fator_local,
       'fator_origem', u.fator_origem, 'nota', u.nota_geracao),
    'cliente', json_build_object('id', c.id, 'nome', c.nome, 'cidade', c.cidade),
    'estado', (select json_build_object('estado', e.estado, 'motivo', e.motivo, 'gravidade', e.gravidade)
               from usina_estado(u.id) e),
    'causa', get_usina_causa(u.id),
    'obra', (select json_build_object('id', o.id, 'contrato', o.contrato, 'papel', ou.papel,
                     'conta_retorno', (fracao_polaris(o.id,u.id) > 0),
                     'saiu', (o.optout_em is not null))
             from obra_usina ou join obras o on o.id=ou.obra_id
             where ou.usina_id=u.id and ou.saiu_em is null order by ou.principal desc limit 1),
    'janela', p_dias,
    'resumo', json_build_object(
       'kwh', (select round(coalesce(sum(d.kwh),0)) from usina_dia d
                where d.usina_id=u.id and d.dia >= current_date - p_dias and d.dia < current_date),
       'economia', (select round(coalesce(sum(d.kwh),0) * v_tarifa) from usina_dia d
                where d.usina_id=u.id and d.dia >= current_date - p_dias and d.dia < current_date),
       'pct_1d', (select round(x.razao*100) from usina_dias(u.id, 3) x
                  where x.dia < current_date order by x.dia desc limit 1),
       'pct_7d', (select round(avg(x.razao)*100) from usina_dias(u.id, 7) x where x.razao is not null),
       'pct_30d', (select round(avg(x.razao)*100) from usina_dias(u.id, 30) x where x.razao is not null),
       'pct_mes', (select x.pct from usina_meses(u.id) x
                   where x.kwh>0 and x.completo and x.referencia < date_trunc('month', current_date)
                   order by x.referencia desc limit 1)),
    'meses', (select coalesce(json_agg(json_build_object(
                 'mes', m.mes, 'previsto', m.kwh_previsto, 'fonte', m.fonte,
                 'ajustado', round(m.kwh_previsto * coalesce(u.fator_local,1)),
                 'real', (select round(g.kwh) from usina_geracao g
                          where g.usina_id=u.id and extract(month from g.referencia)=m.mes
                            and g.referencia >= date_trunc('year', current_date) limit 1)
               ) order by m.mes),'[]'::json)
              from usina_previsao m where m.usina_id=u.id),
    'historico', (select coalesce(json_agg(json_build_object(
                 'ref', to_char(x.referencia,'MM/YYYY'), 'kwh', round(x.kwh),
                 'previsto', x.previsto_ajustado, 'pct', x.pct, 'completo', x.completo
               ) order by x.referencia desc),'[]'::json)
              from usina_meses(u.id) x where x.kwh > 0),
    'dias_serie', (select coalesce(json_agg(json_build_object(
                 'dia', d.dia, 'kwh', round(d.kwh,1), 'razao', d.razao,
                 'anormal', d.anormal, 'tempo', d.tempo, 'chuva', d.chuva_mm, 'sol', d.sol_horas,
                 'esperado', round(d.esperado * coalesce(u.potencia_kwp,0), 1)
               ) order by d.dia),'[]'::json)
              from usina_dias(u.id, p_dias) d where d.dia < current_date),
    'mensagens', (select coalesce(json_agg(json_build_object(
                 'quando', t.quando, 'tipo', t.tipo) order by t.quando desc),'[]'::json)
              from (
                select o2.nps_enviado_em as quando, 'Pedido de nota' as tipo
                  from obra_usina ou2 join obras o2 on o2.id=ou2.obra_id
                 where ou2.usina_id=u.id and o2.nps_enviado_em is not null
                union all
                select n.agradecido_em, 'Agradecimento pela nota'
                  from obra_usina ou2 join nps n on n.obra_id=ou2.obra_id
                 where ou2.usina_id=u.id and n.agradecido_em is not null
                union all
                select n.lembrete_google_em, 'Pedido de avaliação'
                  from obra_usina ou2 join nps n on n.obra_id=ou2.obra_id
                 where ou2.usina_id=u.id and n.lembrete_google_em is not null
              ) t)
  ) into v
  from usinas u join clientes c on c.id=u.cliente_id
  where u.id=p_usina;
  return v;
end $function$
