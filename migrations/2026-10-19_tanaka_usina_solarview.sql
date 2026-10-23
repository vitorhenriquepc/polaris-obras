-- APLICADA em 19/10 (dados), a pedido do Vitor.
--
-- TANAKA CENTRO DE ABASTECIMENTO (4745): a usina foi cadastrada no SolarView
-- como "Posto Araçatuba 4745 | 4829" (id 984512, 25 kWp, instalada 16/10,
-- Araçatuba) depois da rodada das 10h40 do solarview-vincular. A simulação do
-- vinculador casava pelo "contrato no nome" (nota máxima); o vínculo foi feito na
-- hora, com o que o vinculador gravaria, em vez de esperar o dia seguinte.
--
-- Decisões do Vitor em 19/10:
--   · o 4829 no nome é o contrato das 10 placas a mais do mesmo posto — não
--     existe obra 4829 no sistema, e a usina é uma só;
--   · a potência que vale é a da obra, 22,32 kWp (36 módulos), não os 25 kWp do
--     SolarView. Se as placas a mais estiverem nesta usina, o desempenho dela vai
--     aparecer acima do normal; corrigir é usina_editar.
--
-- Simulado antes em begin … rollback: a usina entra como "recém-ligada" e a
-- conferir_saude_base() não acusa "usina sem obra".

do $x$
declare o record; v_uid uuid;
begin
  select id, cliente_id, cidade, data_instalacao into o from obras where contrato = '4745';
  if exists (select 1 from obra_usina where obra_id = o.id) then raise exception 'a TANAKA ja tem usina'; end if;
  if exists (select 1 from usina_monitoramento where plataforma = 'solarview' and id_externo = '984512') then
    raise exception 'a usina 984512 do SolarView ja esta ligada a outra';
  end if;
  insert into usinas (cliente_id, apelido, potencia_kwp, data_instalacao, data_estimada, cidade, ativa)
  values (o.cliente_id, o.cidade, 22.32, o.data_instalacao, false, o.cidade, true)
  returning id into v_uid;
  insert into obra_usina (obra_id, usina_id, papel, medicao, entrou_em, principal)
  values (o.id, v_uid, 'propria', 'inversor_proprio', o.data_instalacao, true);
  insert into usina_monitoramento (usina_id, plataforma, id_externo, ativo)
  values (v_uid, 'solarview', '984512', true);
end $x$;
