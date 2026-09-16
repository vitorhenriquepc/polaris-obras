-- 2026-09-16 — Contrato que nasce ativo também gera as visitas
--
-- O QUE ACONTECEU
-- O primeiro contrato Completo ativo da casa foi fechado em 16/09: UNI AUTO
-- POSTO DE ARACATUBA LTDA, completo_especial, cortesia de 6 meses,
-- 16/09/2026 a 16/03/2027. O plano tem inclui_visita = true.
--
-- Zero visita prevista. Medido: plano_visita tinha 0 linhas no sistema inteiro.
--
-- A causa: plano_visitas_gerar() so era chamada de dentro da
-- plano_registrar_pagamento(), que e o caminho de quem PAGA. Um contrato que
-- nasce 'ativo' -- cortesia, ou pago com data de inicio informada -- pulava a
-- geracao e ficava prometendo uma visita tecnica que ninguem marcou.
--
-- POR QUE NUNCA TINHA APARECIDO
-- As 54 cortesias antigas sao todas 'essencial', e essencial tem
-- inclui_visita = false. O buraco so podia aparecer no dia em que existisse um
-- Completo ativo -- e esse dia foi hoje.
--
-- A CORRECAO
-- plano_contrato_criar() chama plano_visitas_gerar() quando o contrato nao
-- fica aguardando pagamento, e devolve `visitas` na resposta. Quem nasce
-- aguardando continua ganhando as dele na plano_registrar_pagamento, como
-- antes -- ali o inicio so existe depois da baixa.
--
-- Chamar e seguro porque plano_visitas_gerar ja se protege sozinha:
--   - checa inclui_visita e devolve 'Este plano nao inclui visita.'
--   - checa inicio e devolve 'O contrato ainda nao comecou.'
--   - e idempotente: nao duplica endereco que ja tem visita prevista.
--
-- Aplicado por replace() sobre pg_get_functiondef. Armadilha 2: conferido num
-- comando SEPARADO depois -- o trecho novo esta la, a trava da cortesia
-- sobreviveu, e a ACL continua
-- {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
--
-- ⚠️ PENDENCIA QUE ISTO NAO RESOLVE
-- Rodar a geracao para o contrato do UNI AUTO criaria DUAS visitas, para
-- 16/12/2026, porque as duas usinas tem o endereco escrito diferente:
-- 'AREA RURAL CLEMENTINA' (105,40 kWp, 2022) e 'CLEMENTINA' (129,60 kWp, 2024).
-- Os dois sao vagos e podem ser o mesmo lugar. Se forem, e uma visita so -- e
-- duas mandariam a equipe a Clementina duas vezes. Decisao do Vitor; a geracao
-- ficou de fora desta migracao de proposito.
do $do$
declare d text;
begin
  select pg_get_functiondef(oid) into d from pg_proc where proname='plano_contrato_criar';
  execute replace(d,
$old$  return json_build_object('ok', true, 'simulado', false,
    'contrato_id', v_id, 'cliente', v_cliente, 'plano', v_plano_nome,
    'status', case when v_aguardando then 'aguardando_pagamento' else 'ativo' end);$old$,
$new$  if not v_aguardando then
    perform public.plano_visitas_gerar(v_id);
  end if;

  return json_build_object('ok', true, 'simulado', false,
    'contrato_id', v_id, 'cliente', v_cliente, 'plano', v_plano_nome,
    'status', case when v_aguardando then 'aguardando_pagamento' else 'ativo' end,
    'visitas', (select count(*) from plano_visita
                 where contrato_id = v_id and status = 'prevista'));$new$);
end $do$;
