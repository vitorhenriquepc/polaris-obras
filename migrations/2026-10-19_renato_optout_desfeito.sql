-- NÃO RODAR — SUBSTITUÍDA EM 23/10 pelo botão "desfazer saída" da ficha
-- (registrar_optin_manual, migrations/2026-10-23_optout_so_com_a_equipe.sql).
-- O Vitor rodou este script no painel em 19/10 e em 21/10 e nada gravou neste
-- banco: nenhum erro no log, nenhum registro em pg_stat_statements, nenhuma
-- transação aberta (onde rodou não se sabe). Fica aqui pelo histórico. Se alguém
-- rodar mesmo assim depois do botão, ele para no "já foi desfeito".
--
-- (texto original)
-- AINDA NÃO APLICADA. Rodar no painel do Supabase (SQL Editor), uma vez.
-- A ferramenta do chat segura este comando esperando uma confirmação que não
-- chega (armadilha 34) — quem roda é quem tem o painel.
--
-- RENATO WATANABE (4582): desfaz o opt-out falso, a pedido do Vitor em 19/10
-- ("pode desfazer o renato saiu").
--
-- O que aconteceu: em 14/08 ele escreveu "Vou sair daqui a pouco" (mensagem 732)
-- e em 18/09 "Hoje vou sair" (3306) — avisava que não estaria em casa quando a
-- equipe fosse. A IA do webhook leu as duas como pedido para sair das mensagens
-- (contexto 'sair') e o registrar_optout rodou sozinho, sem ninguém confirmar.
-- Desde 14/08: a régua dele foi cancelada (7 mensagens, na limpeza de 12/09) e a
-- escada da Isabela o ignorava (atendimento_candidatos corta optout_em).
--
-- O que este script faz, numa transação só (se uma conferência falhar, nada fica):
--   1. limpa optout_em/optout_origem — o termo de 10/08 (optin_em) fica como está;
--   2. registra em consentimentos (acao 'optout_desfeito'); os dois 'optout' continuam lá;
--   3. as mensagens 732 e 3306 passam de 'sair' para 'agendamento', e o resumo da IA
--      fica guardado dentro do resumo novo;
--   4. ensina a IA do webhook: 2 exemplos em classificacoes_exemplo (entram no prompt);
--   5. régua: voltam d75_conta2 (26/10), d90_indica2 (10/11), d150_conta3 (09/01),
--      d180_manutencao (08/02) e d365_aniversario (12/08/2027). Ficam canceladas, com a
--      explicação no motivo: d30_conta1 (o prazo venceu em 01/10) e d45_indica1 (sairia
--      às 17h do dia em que o script rodar, e o d90 pede indicação de novo em 10/11).
--
-- Simulado em 19/10 pelo chat, com rollback (só a parte que a ferramenta deixa rodar):
-- sem o opt-out, os 7 modelos da régua ficam livres no regua_bloqueio, nenhum vence
-- hoje (a fila das 17h não pega nada dele) e a escada da Isabela não avisa ninguém
-- agora — a última mensagem dele é "Ok", depois da resposta do Vitor das 11h12.
--
-- Trava: se o opt-out não for mais o de 18/09 (ele pediu de novo, ou já foi desfeito),
-- o script para sem mexer em nada.

do $x$
declare
  v_obra uuid; v_quem text; n int;
begin
  select id into v_obra from obras where contrato = '4582';
  if v_obra is null then raise exception 'obra 4582 não encontrada'; end if;
  if (select optout_em from obras where id = v_obra) is null then
    raise exception 'o opt-out do 4582 já foi desfeito — nada a fazer';
  end if;
  if (select optout_em from obras where id = v_obra) <> '2026-09-18 13:34:44.198092+00'::timestamptz then
    raise exception 'o opt-out do 4582 mudou depois de 19/10 — confira a conversa antes de desfazer';
  end if;
  v_quem := (select email from usuarios_autorizados where nivel = 'admin' and email ilike 'vitor%' limit 1);

  -- 1. o opt-out sai; o termo de 10/08 fica
  update obras set optout_em = null, optout_origem = null where id = v_obra;

  -- 2. o registro do que aconteceu
  insert into consentimentos (obra_id, acao, texto, origem)
  values (v_obra, 'optout_desfeito',
    'Os dois opt-outs (14/08 e 18/09) foram a IA do webhook lendo "Vou sair daqui a pouco" e '
    || '"Hoje vou sair" (o cliente avisava que não estaria em casa para a equipe) como pedido para '
    || 'sair das mensagens. Desfeito a pedido do Vitor em 19/10. O consentimento do termo de 10/08 '
    || 'continua valendo.', 'manual');

  -- 3. as duas mensagens com o contexto certo; o que a IA tinha dito fica no resumo
  update mensagens_recebidas
     set contexto = 'agendamento',
         resumo = 'Avisa que vai sair de casa, não pede para sair das mensagens (a IA tinha lido: "'
                  || coalesce(resumo, '') || '"; corrigido em 19/10)'
   where obra_id = v_obra and id in (732, 3306) and contexto = 'sair';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'esperava 2 mensagens em "sair", achei %', n; end if;

  -- 4. a IA do webhook aprende
  insert into classificacoes_exemplo (texto, contexto, corrigido_por)
  select m.texto, 'agendamento', v_quem from mensagens_recebidas m
   where m.id in (732, 3306)
     and not exists (select 1 from classificacoes_exemplo e where e.texto = m.texto);

  -- 5. a régua que ainda cabe volta
  update regua_contatos set status = 'pendente', bloqueio_motivo = null
   where obra_id = v_obra
     and modelo in ('d75_conta2', 'd90_indica2', 'd150_conta3', 'd180_manutencao', 'd365_aniversario')
     and status = 'cancelado' and bloqueio_motivo = 'cliente pediu para sair da regua';
  get diagnostics n = row_count;
  if n <> 5 then raise exception 'esperava reativar 5 mensagens da régua, achei %', n; end if;

  update regua_contatos
     set bloqueio_motivo = bloqueio_motivo || ' · opt-out desfeito em 19/10 (era a IA lendo "vou sair"); '
         || case modelo when 'd30_conta1' then 'o prazo venceu em 01/10'
                        else 'não reativada, para não pedir indicação duas vezes em três semanas (o d90 sai em 10/11)' end
   where obra_id = v_obra and modelo in ('d30_conta1', 'd45_indica1')
     and status = 'cancelado' and bloqueio_motivo = 'cliente pediu para sair da regua';
  get diagnostics n = row_count;
  if n <> 2 then raise exception 'esperava anotar 2 mensagens canceladas, achei %', n; end if;
end $x$;

-- Conferência: d75, d90, d150, d180 e d365 em 'pendente' e livres; d30 e d45 em
-- 'cancelado' com a explicação; o d2 de boas-vindas já tinha saído em 14/08.
select c.modelo, c.status, c.data_programada,
       coalesce(public.regua_bloqueio(c.obra_id, c.modelo), 'livre') as bloqueio_hoje,
       c.bloqueio_motivo
  from regua_contatos c join obras o on o.id = c.obra_id
 where o.contrato = '4582'
 order by c.data_programada;
