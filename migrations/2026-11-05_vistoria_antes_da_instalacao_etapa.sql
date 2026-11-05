-- 05/11, depois das 18h, junto do painel: a vistoria pedida antes da instalação
-- não leva mais a obra para a Vistoria. A obra fica onde está (na Execução) até o
-- relatório do instalador, que é quem a leva para a 7 (foto-obra). Decisão do
-- Vitor em 05/11; o texto e o resto estão em 2026-11-05_vistoria_antes_da_instalacao.sql.
--
-- Vai junto do painel porque o painel de antes só manda o aviso da vistoria com a
-- obra na 7: com este gatilho e o painel velho, a obra que ficasse na 6 não teria
-- aviso nenhum, e a tela diria "Obra salva ✓" (armadilha 11).
--
-- Só muda a condição de levar para a 7: o prazo e o "avisado" zerado continuam
-- iguais. Quem escolhe a 7 de propósito (kanban, card) continua podendo -- o
-- gatilho nunca abaixa a etapa, só deixa de subir. Sem data de instalação a
-- obra vai para a 7, como antes (o painel pergunta se a instalação já foi feita).
-- Rodar de novo não muda nada.

create or replace function public.trg_cpfl_prazo()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if new.cpfl_solicitado_em is distinct from old.cpfl_solicitado_em then
    new.cpfl_prazo_em := case when new.cpfl_solicitado_em is null then null
                              else soma_dias_uteis(new.cpfl_solicitado_em, 5) end;
    new.cpfl_avisado_em := null;
    -- vistoria pedida ANTES da instalação (Vitor, 05/11): a obra fica onde está
    -- até o relatório do instalador, que é quem a leva para a Vistoria
    if new.cpfl_solicitado_em is not null
       and coalesce(new.trilha, 'padrao') = 'padrao'
       and coalesce(new.etapa_numero, 0) < 7
       and not public.instalacao_pendente(new.relatorio_enviado_em, new.data_instalacao, new.data_fim) then
      new.etapa_numero := 7;
    end if;
  end if;
  return new;
end; $function$;
