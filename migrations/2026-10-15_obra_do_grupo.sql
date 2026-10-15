-- APLICADA em 15/10, antes do webhook-whatsapp-v2 v4 (publicado às 18:49, que
-- passa a chamar esta função). Conferido como service_role: grupo da Tays → a
-- obra dela; grupo do Júnior → o 4674.
--
-- Grupo de WhatsApp ligado a mais de uma obra (15/10, achado da autoanálise).
--
-- O webhook-whatsapp-v2 achava a obra da mensagem com
--   from obras where whatsapp_grupo_id = <grupo> ... maybeSingle()
-- e, com DUAS obras no mesmo grupo, o maybeSingle() devolve erro, a obra vem
-- nula e a mensagem é descartada como "grupo interno" — sem gravar nada. Desde
-- 26/09 (Tays: a obra dela + a da visita do plano, que herda o grupo) e 02/10
-- (Júnior: o posto + o eletroposto 4674, quando o grupo do posto passou a ser o
-- "#POSTO UNI 4674"), nada do que os dois escrevem entra no sistema — nem na
-- escada da Isabela. A manutenção nova que "puxa o cadastro" também herda o
-- grupo, então isso ia se repetir com qualquer cliente antigo.
--
-- obra_do_grupo(grupo) escolhe a obra DONA da conversa, sempre uma só:
--   1) obra de visita do plano (plano_visita.obra_id) nunca é dona — é filha;
--   2) entre as outras, a que ainda está em andamento (not obra_ativa) primeiro —
--      é dela que o cliente costuma estar falando;
--   3) empate: a mais antiga (o cliente de sempre).
-- Hoje: Tays → a obra principal dela (15/09); Júnior → o eletroposto 4674
-- (etapa 7, em andamento; vendedor Vitor). Quando o 4674 concluir, o posto e o
-- 4674 ficam ativos e ganha o mais antigo (o 4674, 28/07).
--
-- Só o envio NÃO muda: cada obra continua mandando para o grupo dela.

create or replace function public.obra_do_grupo(p_grupo text)
 returns uuid
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select o.id
  from obras o
  where o.whatsapp_grupo_id = p_grupo
  order by exists (select 1 from plano_visita pv where pv.obra_id = o.id),
           coalesce(public.obra_ativa(o.id), false),
           o.criado_em
  limit 1;
$function$;

comment on function public.obra_do_grupo(text) is
  'A obra dona de um grupo de WhatsApp quando o grupo está em mais de uma obra: visita do plano nunca, em andamento primeiro, depois a mais antiga. Usada pelo webhook-whatsapp-v2 (15/10).';

revoke execute on function public.obra_do_grupo(text) from public;
revoke execute on function public.obra_do_grupo(text) from anon;
grant  execute on function public.obra_do_grupo(text) to authenticated;
grant  execute on function public.obra_do_grupo(text) to service_role;
