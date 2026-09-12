-- =====================================================================
-- 2026-09-12 — search_path fixo em duas funções
--
-- JÁ APLICADO em dakubhcgohiwzyqiegqf, registrado no histórico do
-- Supabase como 'fixa_search_path_duas_funcoes'.
-- =====================================================================

-- Apontado pelo linter do Supabase (function_search_path_mutable).
-- Sem search_path fixo, quem chama pode trocar o schema por baixo e a função
-- passa a enxergar tabelas falsas. Nenhuma das duas é security definer, então
-- o estrago ficaria limitado ao próprio chamador — mas trg_valida_lancamento
-- é o trigger que confere a conta no DRE, e validar contra um
-- dre_plano_contas falso não é aceitável.

alter function public.trg_valida_lancamento()  set search_path to 'public';
alter function public.gerar_codigo_indicacao() set search_path to 'public';

-- esquema/funcoes/trg_valida_lancamento.sql foi reexportado depois disto.
