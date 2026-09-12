CREATE OR REPLACE FUNCTION public.zz_det(p_usina uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  
  select json_build_object(
    'usina', json_build_object(
       'id', u.id, 'apelido', u.apelido, 'kwp', u.potencia_kwp,
       'instalada', u.data_instalacao, 'data_estimada', u.data_estimada,
       'cidade', u.cidade, 'status', u.status_atual, 'status_desde', u.status_desde,
       'fator', u.fator_local, 'fator_origem', u.fator_origem, 'nota', u.nota_geracao,
       'instalador_terceiro', u.instalador_terceiro),
    'cliente', json_build_object('id', c.id, 'nome', c.nome, 'cidade', c.cidade),
    'obra', (select json_build_object('id', o.id, 'contrato', o.contrato, 'papel', ou.papel,
                     'conta_retorno', (fracao_polaris(o.id,u.id) > 0),
                     'grupo', (o.whatsapp_grupo_id is not null), 'saiu', (o.optout_em is not null))
             from obra_usina ou join obras o on o.id=ou.obra_id
             where ou.usina_id=u.id and ou.saiu_em is null order by ou.principal desc limit 1),
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
