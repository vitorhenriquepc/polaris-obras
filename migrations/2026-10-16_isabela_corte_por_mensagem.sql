-- APLICADA em 16/10 (achado na conferência das 9h30 com tráfego real; simulada antes).
--
-- O corte de quando a escada ligou (config.atendimento_desde, 15/10 17:17)
-- valia pelo COMEÇO do bloco pendente: atendimento_candidatos montava o bloco
-- com todas as mensagens do cliente depois da última resposta de gente da
-- equipe (7 dias) e só então descartava o grupo se o bloco tinha começado antes
-- do corte. Quem tinha um recado antigo sem resposta ficava invisível para a
-- escada mesmo escrevendo de novo depois.
--
-- O caso que provou, 16/10: MARIA APARECIDA (4767) mandou às 7h24 a foto da
-- conta de luz ("esse é o valor da energia este mês") e às 9h30 já tinha 92
-- minutos úteis sem resposta — mas o bloco dela começava num recado de 12/10
-- ("assim que chegar manda uma foto"), e o grupo não entrava na lista.
--
-- Agora o corte vale por MENSAGEM: só conta o que chegou depois dele, e a espera
-- começa na primeira mensagem nova. O que ficou antes do corte continua fora (é o
-- passivo que não devia disparar de uma vez ao ligar). Simulado antes de gravar:
-- de 13 grupos com mensagem pendente, só o 4767 mudava; os outros 11 com recado
-- antigo seguem fora, e o 4810 igual. Sem corte (replay) nada muda.

create or replace function public.atendimento_candidatos(p_agora timestamp with time zone default now(),
  p_desde_min timestamp with time zone default null::timestamp with time zone)
 returns json
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with m as (
    select mr.id, mr.obra_id, mr.recebida_em, coalesce(mr.da_equipe, false) as eq, mr.contexto,
           mr.tipo, mr.metodo, coalesce(mr.transcricao, mr.texto) as conteudo, mr.remetente_nome
    from mensagens_recebidas mr
    where mr.recebida_em <= p_agora and mr.recebida_em > p_agora - interval '7 days'
  ), ult_eq as (
    select obra_id, max(recebida_em) as em,
           (array_agg(remetente_nome order by recebida_em desc))[1] as quem
    from m where eq and coalesce(contexto, '') <> 'automatica'
    group by obra_id
  ), pend as (
    select m.obra_id, min(m.recebida_em) as desde, max(m.recebida_em) as ultima, count(*) as n,
           (array_agg(left(m.conteudo, 160) order by m.recebida_em desc))[1] as trecho
    from m left join ult_eq u on u.obra_id = m.obra_id
    where not m.eq
      and m.recebida_em > coalesce(u.em, '-infinity'::timestamptz)
      -- o corte vale por mensagem (16/10): recado antigo sem resposta não esconde o novo
      and (p_desde_min is null or m.recebida_em >= p_desde_min)
      and m.tipo not in ('reacao', 'figurinha', 'outro')
      and coalesce(m.contexto, '') not in ('nps', 'autorizacao', 'sair', 'aceite_relatorio', 'automatica')
      and coalesce(m.metodo, '') not in ('aceite', 'optin', 'nps')
      and (m.tipo in ('imagem', 'documento', 'video', 'audio') or not public.msg_trivial(m.conteudo))
    group by m.obra_id
  )
  select coalesce(json_agg(json_build_object(
      'obra_id', o.id, 'cliente', o.cliente, 'contrato', o.contrato, 'grupo', o.whatsapp_grupo_id,
      'vendedor_id', o.vendedor_id, 'trilha', coalesce(o.trilha, 'padrao'), 'etapa', o.etapa_numero,
      'desde', p.desde, 'ultima', p.ultima, 'msgs', p.n, 'trecho', p.trecho,
      'ult_equipe_em', u.em, 'ult_equipe_quem', u.quem,
      'min_uteis', public.minutos_uteis(p.desde, p_agora),
      'min_corridos', floor(extract(epoch from (p_agora - p.desde)) / 60)::int
    ) order by p.desde), '[]'::json)
  from pend p
  join obras o on o.id = p.obra_id
  left join ult_eq u on u.obra_id = p.obra_id
  where o.whatsapp_grupo_id is not null
    and o.optout_em is null;
$function$;
