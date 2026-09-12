CREATE OR REPLACE FUNCTION public.get_usina_detalhe_svc(p_usina uuid, p_dias integer DEFAULT 30)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json; v_tarifa numeric;
begin
  select coalesce((select valor::numeric from config where chave='economia_por_kwh'),0.73) into v_tarifa;
  select json_build_object(
    'usina', json_build_object('id',u.id,'apelido',u.apelido,'kwp',u.potencia_kwp,
       'instalada',u.data_instalacao,'cidade',u.cidade,'status',u.status_atual,
       'fator',u.fator_local,'fator_origem',u.fator_origem,'nota',u.nota_geracao),
    'cliente', json_build_object('id',c.id,'nome',c.nome,'cidade',c.cidade),
    'estado', (select json_build_object('estado',e.estado,'motivo',e.motivo,'gravidade',e.gravidade)
               from usina_estado(u.id) e),
    'causa', get_usina_causa(u.id),
    'obra', (select json_build_object('id',o.id,'contrato',o.contrato,'papel',ou.papel,
                     'saiu',(o.optout_em is not null))
             from obra_usina ou join obras o on o.id=ou.obra_id
             where ou.usina_id=u.id and ou.saiu_em is null order by ou.principal desc limit 1),
    'resumo', json_build_object(
       'kwh', (select round(coalesce(sum(d.kwh),0)) from usina_dia d
                where d.usina_id=u.id and d.dia >= current_date - p_dias and d.dia < current_date),
       'economia', (select round(coalesce(sum(d.kwh),0) * v_tarifa) from usina_dia d
                where d.usina_id=u.id and d.dia >= current_date - p_dias and d.dia < current_date)),
    -- SO meses ja fechados, do mais recente para o mais antigo
    'historico', (select coalesce(json_agg(json_build_object(
                 'ref', to_char(x.referencia,'MM/YYYY'), 'kwh', round(x.kwh),
                 'previsto', x.previsto_ajustado, 'pct', x.pct, 'completo', x.completo
               ) order by x.referencia desc),'[]'::json)
              from usina_meses(u.id) x
              where x.kwh > 0 and x.referencia < date_trunc('month', current_date)),
    'dias_serie', (select coalesce(json_agg(json_build_object(
                 'dia',d.dia,'kwh',round(d.kwh,1),'razao',d.razao,'anormal',d.anormal,
                 'tempo',d.tempo,'chuva',d.chuva_mm,'sol',d.sol_horas,'sem_medicao',d.sem_medicao
               ) order by d.dia),'[]'::json)
              from usina_dias(u.id, p_dias) d where d.dia < current_date)
  ) into v
  from usinas u join clientes c on c.id=u.cliente_id
  where u.id=p_usina;
  return v;
end $function$
