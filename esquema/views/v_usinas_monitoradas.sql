create or replace view public.v_usinas_monitoradas as
 SELECT u.id AS usina_id,
    u.apelido,
    u.potencia_kwp,
    u.cliente_id,
    c.nome AS cliente,
    o.id AS obra_id,
    o.contrato,
    o.whatsapp_grupo_id,
    o.optout_em,
    ou.papel,
    m.plataforma,
    m.id_externo,
    u.status_atual,
    u.status_desde,
    u.alerta_parada_em
   FROM usinas u
     JOIN clientes c ON c.id = u.cliente_id
     JOIN obra_usina ou ON ou.usina_id = u.id AND ou.saiu_em IS NULL
     JOIN obras o ON o.id = ou.obra_id
     JOIN usina_monitoramento m ON m.usina_id = u.id AND m.ativo
  WHERE u.ativa;

alter view public.v_usinas_monitoradas set (security_invoker = true);

grant select on public.v_usinas_monitoradas to authenticated;
