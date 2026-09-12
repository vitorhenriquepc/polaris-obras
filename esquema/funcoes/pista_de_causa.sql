CREATE OR REPLACE FUNCTION public.pista_de_causa(p_obra uuid, p_dias integer DEFAULT 45)
 RETURNS TABLE(causa text, trecho text, quando timestamp with time zone, de_quem text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with txt as (
    select m.recebida_em, m.da_equipe,
           coalesce(m.transcricao, m.texto) as t,
           lower(translate(coalesce(m.transcricao, m.texto),
             'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
             'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc')) as n
    from mensagens_recebidas m
    where m.obra_id = p_obra
      and m.recebida_em >= now() - make_interval(days => p_dias)
      and coalesce(m.transcricao, m.texto) is not null
  )
  select case
      when n ~ '(wi-?fi|wifi|internet|roteador|modem|senha da rede|trocou.*rede|sem sinal)' then 'wifi'
      when n ~ '(faltou (luz|energia)|sem (luz|energia)|queda de energia|apagao)' then 'sem_energia'
      when n ~ '(desliguei|desligamos|desligado|desligar o (sistema|inversor)|deixei desligado)' then 'desligado_pelo_cliente'
      when n ~ '(obra|reforma|pintura|telhado|pedreiro|mexendo no telhado)' then 'obra_no_local'
      when n ~ '(cpfl|concessionaria|vistoria|troca do (relogio|medidor)|padrao)' then 'aguardando_concessionaria'
      when n ~ '(inversor.*(erro|falha|apagado|piscando|vermelho)|erro no inversor|deu erro)' then 'defeito_inversor'
    end as causa,
    left(t, 160), recebida_em,
    case when da_equipe then 'equipe' else 'cliente' end
  from txt
  where n ~ '(wi-?fi|wifi|internet|roteador|modem|faltou (luz|energia)|sem (luz|energia)|apagao|desliguei|desligado|obra|reforma|telhado|cpfl|concessionaria|vistoria|inversor)'
  order by recebida_em desc;
$function$
