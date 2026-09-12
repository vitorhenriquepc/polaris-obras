CREATE OR REPLACE FUNCTION public.mensagem_sem_acao(p_texto text, p_tipo text, p_contexto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  with lim as (
    select trim(regexp_replace(
             regexp_replace(
               translate(lower(coalesce(p_texto,'')),
                 'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc'),
               '[^a-z0-9]',' ','g'),
             '\s+',' ','g')) as t
  )
  select
    coalesce(p_tipo,'') in ('figurinha','reacao','outro')
    or (coalesce(p_contexto,'geral') = 'geral' and (
        (select t from lim) = ''
        or (select t from lim) ~
        '^(ok|okay|okk|blz|beleza|valeu|vlw|obrigado|obrigada|obg|obrigadao|obrigadaa|bom dia|boa tarde|boa noite|otima semana|boa semana|bom final de semana|otimo final de semana|amem|certo|isso|sim|nao|ta bom|tudo bem|tudo certo|tudo otimo|combinado|perfeito|show|top|joia|vou ver|ja vi|entendi|de nada|igualmente|so isso|nada|estamos juntos|abraco|abracos|parabens|muito|obrigado|obrigada)( (ok|blz|beleza|valeu|obrigado|obrigada|obrigadaa|obg|muito|mesmo|viu|entao|gente|pessoal|amigo|amiga|tchau|abraco|abracos|para|pra|voces|todos|tambem|a|o|de|nada|bom|dia|tarde|noite|certo|bem|sim|isso|ta))*$'
    ));
$function$
