CREATE OR REPLACE FUNCTION public.clientes_esperando(p_minutos integer DEFAULT 60)
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ultima as (
    select distinct on (m.obra_id) m.obra_id, m.da_equipe, m.recebida_em,
           coalesce(m.transcricao, m.texto,'') as conteudo, m.contexto,
           lower(regexp_replace(
             translate(coalesce(m.transcricao, m.texto,''),
                       'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
                       'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'),
             '[^[:alnum:][:space:]]','','g')) as limpo
    from mensagens_recebidas m
    where m.recebida_em >= now() - interval '5 days'
    order by m.obra_id, m.recebida_em desc
  )
  select coalesce(json_agg(json_build_object(
      'obra_id', o.id, 'cliente', o.cliente, 'contrato', o.contrato,
      'minutos', round(extract(epoch from (now()-u.recebida_em))/60),
      'trecho', left(u.conteudo,70)
    ) order by u.recebida_em), '[]'::json)
  from ultima u join obras o on o.id=u.obra_id
  where u.da_equipe = false
    and u.recebida_em <= now() - make_interval(mins => p_minutos)
    and (o.alerta_espera_em is null or o.alerta_espera_em < u.recebida_em)
    and o.optout_em is null
    and length(trim(u.limpo)) >= 12
    and trim(u.limpo) !~ '^(ok|okay|blz|beleza|valeu|vlw|obrigado|obrigada|obg|muito obrigado|muito obrigada|bom dia|boa tarde|boa noite|otima semana|boa semana|otimo final de semana|bom final de semana|amem|certo|isso|sim|nao|ta bom|tudo bem|tudo certo|combinado|perfeito|show|top|joia|vou ver|ja vi|entendi|de nada|eu que agradeco|nos que agradecemos|igualmente|pra voces tambem|para voces tambem)([[:space:]]+(mesmo|viu|entao|obrigado|obrigada|gente|pessoal|amigo|amiga|tchau|abraco|abracos|para|pra|voces|tambem|todos))*$';
$function$
