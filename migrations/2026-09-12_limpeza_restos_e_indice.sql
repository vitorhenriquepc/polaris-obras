-- APLICADA em 12/09/2026, em duas migrações:
--   `remove_indice_duplicado_geracao` e `remove_restos_de_prototipo`

-- ============================================================
-- 1. Índice duplicado em geracao
-- ============================================================
-- Havia dois índices idênticos em (obra_id, referencia):
--   geracao_obra_id_referencia_key  → lastro de uma constraint UNIQUE, fica
--   uq_geracao_obra_dia             → índice solto, idêntico, sai
-- A unicidade continua garantida pela constraint. Nenhuma função cita o
-- índice pelo nome, então nenhum `on conflict on constraint` quebra.

drop index if exists public.uq_geracao_obra_dia;

-- ============================================================
-- 2. Restos de protótipo
-- ============================================================
-- Antes de apagar, conferido que:
--   * nenhuma tela (HTML) cita
--   * nenhuma outra função do banco cita
--   * nenhuma aparece no log de /rest/v1/rpc/ das últimas 24h
--   * as versões finais existem e são chamadas de verdade:
--       get_posvenda_lista   no lugar de zz_lista
--       get_extrato_pendentes no lugar de _t_pend
--   * todas estão versionadas em esquema/funcoes/ — dá para restaurar
--
-- Estas três eram as que estavam abertas ao `anon` e foram revogadas mais
-- cedo hoje. Agora saíram de vez.

drop function if exists public.zz_lista();
drop function if exists public.zz_brindes();
drop function if exists public.zz_det(uuid);
drop function if exists public._t_pend(uuid);

-- NÃO entra aqui `manutencao_usinas`. Parece resto pelo nome, mas é o cron
-- job 30 — `select public.manutencao_usinas()`, roda às 9h. Fica.

-- ============================================================
-- 3. usina_status
-- ============================================================
-- Tabela do desenho antigo, de quando o status era por obra_id e não por
-- usina. Zero linhas, RLS ligada e nenhuma policy (ninguém lia nem escrevia),
-- nenhuma FK, view ou função apontando para ela. Não há histórico a
-- preservar — a regra 3.6 do CLAUDE.md não se aplica a tabela vazia.

drop table if exists public.usina_status;

-- ============================================================
-- O que deliberadamente NÃO foi feito
-- ============================================================
-- `solarview_ativo` está em 0 e não achei quem leia: conferi os comandos dos
-- 29 cron jobs, todas as funções de `public`, as telas, e os dois coletores
-- (solarview-diario e solarview-geracao). Mesmo assim NÃO apaguei a chave.
-- O padrão de leitura é `cfg('chave','0')` dentro da edge function, com
-- default que desliga. Se alguma das 51 edge functions que não abri ler essa
-- chave, apagar desligaria a coleta. O custo de errar é alto e o de deixar é
-- zero. Conferir e remover num momento de calma.
