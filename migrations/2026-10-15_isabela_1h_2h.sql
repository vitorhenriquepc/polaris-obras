-- APLICADA em 15/10 (o arquivo foi escrito em 16/10, na revisão antes de
-- publicar: a mudança estava no banco e faltava aqui — §11 do CLAUDE.md).
--
-- A escada da Isabela passa a avisar o vendedor com 1 h útil sem resposta (era
-- 2 h) e o pós-venda com 2 h (era 4 h). Pergunta do Vitor em 15/10: "avisar o
-- vendedor com 2 horas é muito tempo? 1 hora o vendedor e depois 2 horas a
-- Lívia" — aprovado por ele no plano das abas do Pós-venda.
--
-- Não muda código: a edge function isabela-atendimento lê as duas chaves em toda
-- rodada, e a aba Isabela do posvenda.html mostra o valor que estiver aqui.
-- "Hora útil" continua seg–sex, 8h–18h, fora dos feriados (minutos_uteis).
--
-- Medido em 14/10 (armadilha 33): em 30 dias, 223 perguntas de verdade, 76%
-- respondidas em até 15 min, mediana de 2 min — 1 h útil sem resposta já é
-- exceção, não rotina.

do $x$
begin
  update config set valor = '60'  where chave = 'atendimento_vendedor_min';
  update config set valor = '120' where chave = 'atendimento_posvenda_min';
end $x$;
