CREATE OR REPLACE FUNCTION public.get_cliente_ficha(p_cliente uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select json_build_object(
    'cliente', json_build_object('id',c.id,'nome',c.nome,'cidade',c.cidade,'telefone',c.telefone),
    'kwp_total', (select coalesce(sum(u.potencia_kwp),0) from usinas u where u.cliente_id=c.id and u.ativa),
    'kwp_polaris', (select coalesce(sum(u.potencia_kwp * fracao_polaris(ou.obra_id, u.id)),0)
                    from usinas u join obra_usina ou on ou.usina_id=u.id where u.cliente_id=c.id and u.ativa),
    'obras', (select coalesce(json_agg(json_build_object(
        'contrato',o.contrato,'status',o.status,'concluida',o.data_conclusao,
        'usinas',(select coalesce(json_agg(json_build_object(
            'apelido',u.apelido,'kwp',u.potencia_kwp,'papel',ou.papel,'medicao',ou.medicao,
            'conta_retorno',(fracao_polaris(o.id,u.id) > 0),
            'monitoramento',(select coalesce(json_agg(json_build_object('plataforma',mm.plataforma,'id',mm.id_externo)),'[]'::json)
                             from usina_monitoramento mm where mm.usina_id=u.id and mm.ativo)
          ) order by ou.papel, u.apelido),'[]'::json)
          from obra_usina ou join usinas u on u.id=ou.usina_id where ou.obra_id=o.id and ou.saiu_em is null),
        'relatorios',(select coalesce(json_agg(json_build_object(
            'titulo',r.titulo,'origem',r.origem,'url',r.url,'data',r.data_referencia) order by r.data_referencia desc),'[]'::json)
          from obra_relatorios r where r.obra_id=o.id)
      ) order by o.data_conclusao desc nulls last),'[]'::json)
      from obras o where o.cliente_id=c.id)
  ) into v from clientes c where c.id=p_cliente;
  return v;
end $function$
