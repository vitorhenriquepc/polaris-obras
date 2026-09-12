CREATE OR REPLACE FUNCTION public.get_posvenda_mensagens(p_dias integer DEFAULT 14)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select json_build_object(
    'enviadas', (select coalesce(json_agg(x order by (x->>'quando') desc),'[]'::json) from (
        select json_build_object('quando', o.nps_enviado_em, 'tipo','Pedido de nota',
               'cliente', c.nome, 'contrato', o.contrato) as x
          from obras o join clientes c on c.id=o.cliente_id
         where o.nps_enviado_em >= now() - make_interval(days => p_dias)
        union all
        select json_build_object('quando', n.agradecido_em, 'tipo','Agradecimento pela nota '||n.nota,
               'cliente', c.nome, 'contrato', o.contrato)
          from nps n join obras o on o.id=n.obra_id join clientes c on c.id=o.cliente_id
         where n.agradecido_em >= now() - make_interval(days => p_dias)
        union all
        select json_build_object('quando', n.lembrete_google_em, 'tipo','Pedido de avaliação no Google',
               'cliente', c.nome, 'contrato', o.contrato)
          from nps n join obras o on o.id=n.obra_id join clientes c on c.id=o.cliente_id
         where n.lembrete_google_em >= now() - make_interval(days => p_dias)
        union all
        select json_build_object('quando', n.lembrete_brinde_em, 'tipo','Lembrete de brinde',
               'cliente', c.nome, 'contrato', o.contrato)
          from nps n join obras o on o.id=n.obra_id join clientes c on c.id=o.cliente_id
         where n.lembrete_brinde_em >= now() - make_interval(days => p_dias)
      ) t),
    'esperando', coalesce(clientes_esperando(60),'[]'::json),
    'usinas_paradas', (select coalesce(json_agg(json_build_object(
        'cliente', c.nome, 'contrato', o.contrato, 'usina', u.apelido,
        'status', u.status_atual, 'desde', u.status_desde,
        'horas', case when u.status_desde is null then null
                 else round(extract(epoch from (now()-u.status_desde))/3600) end,
        'avisado', (u.alerta_parada_em is not null and u.status_desde is not null
                    and u.alerta_parada_em > u.status_desde)
      ) order by u.status_desde),'[]'::json)
      from usinas u join clientes c on c.id=u.cliente_id
      join obra_usina ou on ou.usina_id=u.id and ou.saiu_em is null
      join obras o on o.id=ou.obra_id
      where u.ativa and u.status_atual is not null and u.status_atual <> 'operando'),
    'ligado', json_build_object(
      'nps', (select valor from config where chave='nps_auto_ativo'),
      'espera', (select valor from config where chave='alerta_espera_ativo'),
      'usina', (select valor from config where chave='usina_alerta_ativo'),
      'transcricao', (select valor from config where chave='transcricao_ativa'))
  ) into v;
  return v;
end $function$
