-- Apagar contrato de plano passa a ser so do admin.
--
-- Ate aqui a `plano_contratos` tinha uma unica policy `pc_all` com comando
-- ALL e `is_autorizado()`. Enquanto eram 53 cortesias de R$ 0,00 isso nao
-- pesava. Agora a tabela guarda dinheiro: valor, forma de cobranca, para quem
-- a nota e emitida e a data do primeiro pagamento.
--
-- ARMADILHA 8: nao basta acrescentar uma policy de DELETE com is_admin() ao
-- lado da ALL. Policies permissivas SOMAM: valeria
-- `is_autorizado() OR is_admin()`, e o delete continuaria aberto. A ALL tem
-- de sair e dar lugar a comandos explicitos -- foi assim que a `obras` e as
-- outras cinco foram corrigidas em 12/09.
--
-- O formato abaixo e o mesmo que `clientes` e `usinas` ja usam.
--
-- ⚠️ Isto conserta UMA tabela. Outras 49 tem o mesmo formato ALL, varias
-- delas com dinheiro dentro: dre_lancamentos, obra_parcelas,
-- extrato_movimentos, obra_financeiro, cartao_faturas. Nao e o normal do
-- sistema estar errado -- e o normal do sistema ser permissivo, e a decisao
-- de apertar cada uma e do Vitor.

drop policy if exists pc_all on plano_contratos;

create policy pc_sel on plano_contratos
  for select using (is_autorizado());

create policy pc_ins on plano_contratos
  for insert with check (is_autorizado());

create policy pc_upd on plano_contratos
  for update using (is_autorizado()) with check (is_autorizado());

-- encerrar e cancelar continuam sendo update, que qualquer autorizado faz.
-- apagar de vez, nao: o historico do que foi cobrado nao se apaga (regra 3.6).
create policy pc_del on plano_contratos
  for delete using (is_admin());
