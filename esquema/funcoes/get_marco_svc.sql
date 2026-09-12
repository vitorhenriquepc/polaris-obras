CREATE OR REPLACE FUNCTION public.get_marco_svc(p_usina uuid, p_marco integer)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json; v_pct numeric; v_estado text; v_motivo text;
begin
  select r.pct_retornado into v_pct
  from usinas u, lateral usina_retorno(u.id) r where u.id=p_usina;
  if v_pct is null then return json_build_object('erro','sem dados de retorno'); end if;
  if v_pct < p_marco then
    return json_build_object('erro','a usina esta em '||round(v_pct)||'%, ainda nao atingiu o marco de '||p_marco||'%');
  end if;

  -- so fala de retorno se a usina estiver de fato gerando e sendo medida
  select e.estado, e.motivo into v_estado, v_motivo from usina_estado(p_usina) e;
  if coalesce(v_estado,'') <> 'normal' then
    return json_build_object('erro','usina em "'||coalesce(v_estado,'sem estado')
      ||'" — nao e hora de falar de retorno', 'motivo', v_motivo);
  end if;

  select json_build_object(
    'cliente', split_part(c.nome,' ',1),
    'marco', p_marco,
    'investido', round(r.investido),
    'economizado', round(r.economizado),
    'pct', round(r.pct_retornado),
    'meses_ativa', r.meses_ativa,
    'media_mensal', round(r.media_mensal),
    'meses_restantes', r.meses_restantes,
    'obra_id', o.id,
    'exemplos', (select coalesce(string_agg(left(coalesce(m.transcricao,m.texto),200), E'\n---\n'),'')
                 from (select transcricao, texto from mensagens_recebidas mr
                       where mr.obra_id=o.id and mr.da_equipe
                         and length(coalesce(mr.transcricao,mr.texto))>25
                       order by mr.recebida_em desc limit 4) m)
  ) into v
  from usinas u
  join clientes c on c.id=u.cliente_id
  join obra_usina ou on ou.usina_id=u.id and ou.principal
  join obras o on o.id=ou.obra_id,
  lateral usina_retorno(u.id) r
  where u.id=p_usina;
  return v;
end $function$
