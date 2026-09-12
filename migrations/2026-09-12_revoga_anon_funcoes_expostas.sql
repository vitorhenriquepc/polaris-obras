-- =====================================================================
-- 2026-09-12 — Fecha três funções security definer abertas ao anon
--
-- JÁ APLICADO no projeto dakubhcgohiwzyqiegqf, e registrado no histórico
-- do Supabase como 'revoga_anon_funcoes_expostas'.
-- =====================================================================

-- Achado ao levantar as permissões das funções para esquema/funcoes/.
-- As três são security definer — passam por cima da RLS — e nenhuma confere
-- permissão por dentro. O anon é o papel de quem não fez login, e a chave
-- dele está no código das páginas, à vista de qualquer um.
--
--   _t_pend            devolvia o extrato bancário: até 400 movimentos com
--                      valor, memo, banco e conta
--   zz_det             devolvia dados da usina com nome do cliente e contrato
--   manutencao_usinas  escreve: cria previsões e altera fator_local
--
-- ATENÇÃO: manutencao_usinas NÃO é sobra de teste, apesar de estar na mesma
-- lista. É o cron 'manutencao-usinas' (jobid 30, 0 12 * * *, a automação das
-- 9h), que roda como postgres e portanto não é afetado por este revoke.
-- _t_pend e zz_det têm cara de rascunho e nenhuma tela do repositório chama
-- as três — conferido por busca nos HTML.

revoke all on function public._t_pend(p_conta uuid)          from public, anon;
revoke all on function public.zz_det(p_usina uuid)           from public, anon;
revoke all on function public.manutencao_usinas()            from public, anon;

-- Conferido depois de aplicar:
--   anon         false   (era true)
--   authenticated true   grant próprio, intacto
--   service_role  true   grant próprio, intacto
--   postgres      true   é quem o cron usa, intacto

-- ---------------------------------------------------------------------
-- Varredura geral feita na mesma hora, para registro
-- ---------------------------------------------------------------------
-- Sobraram 10 funções security definer que o anon executa. Nenhuma é buraco:
--
--   6 são fluxo público protegido por slug + token secreto da obra:
--     get_nps, salvar_nps, salvar_brinde, declarar_avaliacao_google,
--     get_obra_instalador, get_agenda
--   2 são o relatório público por slug, que é o que o relatorio.html serve
--     de propósito: get_obra_publica, get_relatorio_publico
--   2 têm guarda própria: get_ficha_cliente chama pode_ver_posvenda() e
--     indicacao_status chama pode_agir_posvenda()
--
-- Para refazer a varredura:
--
--   select p.proname, pg_get_function_identity_arguments(p.oid)
--   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--   where n.nspname='public' and p.prokind='f' and p.prosecdef
--     and has_function_privilege('anon', p.oid,'EXECUTE')
--   order by 1;
