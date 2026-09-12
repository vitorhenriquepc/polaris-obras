-- APLICADA em 12/09/2026 (migração `delete_so_admin_de_verdade`).
--
-- O QUE ESTÁ ERRADO
--
-- Cinco tabelas têm duas policies permissivas cada:
--
--   <tabela>_auth  ALL     using (is_autorizado())
--   <tabela>_del   DELETE  using (is_admin())
--
-- A intenção da segunda é clara: "só admin apaga". Mas policy permissiva
-- se SOMA, não se subtrai. Num delete o Postgres avalia as duas e aceita se
-- QUALQUER uma passar:
--
--   is_autorizado() OR is_admin()
--
-- Ou seja, qualquer pessoa autorizada apaga. A policy `_del` não restringe
-- nada — ela só alarga.
--
-- POR QUE NÃO ESTOUROU AINDA
--
-- Hoje as três pessoas em `usuarios_autorizados` são todas `is_admin = true`.
-- Os dois lados do OR dão o mesmo resultado, então na prática ninguém notou.
-- No dia em que entrar um vendedor (não-admin), ele passa a poder apagar
-- cliente, usina, vínculo obra-usina e relatório de obra.
--
-- Isso conversa direto com a regra 3.6 do CLAUDE.md: não apagar histórico.
--
-- A CORREÇÃO
--
-- Tirar o DELETE da policy larga e deixar o delete só na policy de admin.
-- Aplicar isto HOJE não muda nada para ninguém — as três pessoas são admin.
-- O ganho é no dia em que não forem.

do $$
declare t text;
begin
  foreach t in array array['clientes','obra_relatorios','obra_usina',
                           'usinas','usina_monitoramento']
  loop
    -- Troca o ALL por três comandos explícitos, sem DELETE.
    execute format('drop policy if exists %I on public.%I', t||'_auth', t);
    execute format('create policy %I on public.%I for select using (public.is_autorizado())', t||'_auth_sel', t);
    execute format('create policy %I on public.%I for insert with check (public.is_autorizado())', t||'_auth_ins', t);
    execute format('create policy %I on public.%I for update using (public.is_autorizado()) with check (public.is_autorizado())', t||'_auth_upd', t);
    -- A policy <tabela>_del continua como está: delete só com is_admin().
  end loop;
end $$;

-- CONFERIDO DEPOIS DE APLICAR
--
--   delete ainda aberto a qualquer autorizado ....... NENHUMA (correto)
--   leitura como authenticated ...................... clientes 68, usinas 56,
--                                                     obra_usina 56,
--                                                     obra_relatorios 37,
--                                                     usina_monitoramento 56
--   update como authenticated ....................... funciona nas tres testadas
--   delete como admin ............................... continua funcionando
--
-- Ou seja: a tela nao perdeu nada, e o delete deixou de ser de todo mundo.
