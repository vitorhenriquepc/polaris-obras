-- APLICADA em 12/09/2026 (`obras_delete_so_admin_o_que_eu_esqueci`).
--
-- ISTO CORRIGE UM ERRO MEU, DO MESMO DIA.
--
-- A migração `2026-09-12_delete_so_admin.sql` fechou o padrão "ALL amplo +
-- DELETE de admin" em cinco tabelas — clientes, obra_relatorios, obra_usina,
-- usinas, usina_monitoramento — e deixou de fora a `obras`, que é a tabela
-- central do sistema e tinha exatamente o mesmo defeito:
--
--   obras_auth          ALL     using (is_autorizado())
--   obras_delete_admin  DELETE  using (is_admin())
--
-- Policy permissiva SOMA. Num delete valia `is_autorizado() OR is_admin()`,
-- então a policy de admin não restringia nada.
--
-- A `obras` apareceu na minha própria listagem de policies mais cedo naquele
-- dia e eu simplesmente não a incluí na lista de correção.
--
-- NÃO ERA TEORIA. Testei como a conta de nível `financeiro` (não-admin desde
-- aquele mesmo dia): apagou uma obra. 1 linha, desfeita com rollback.
--
-- SIMULADO ANTES DE APLICAR, com a mesma conta não-admin:
--   delete ....... 0 linhas  (era 1)
--   update ....... 1 linha   (continua funcionando)
--   select ....... 71 obras  (continua lendo tudo)
--
-- CONFERIDO DEPOIS: varredura de todas as tabelas de `public` procurando o
-- mesmo padrão — nenhuma sobrou.

drop policy if exists obras_auth on public.obras;

create policy obras_auth_sel on public.obras
  for select to authenticated
  using (public.is_autorizado());

create policy obras_auth_ins on public.obras
  for insert to authenticated
  with check (public.is_autorizado());

create policy obras_auth_upd on public.obras
  for update to authenticated
  using (public.is_autorizado())
  with check (public.is_autorizado());
