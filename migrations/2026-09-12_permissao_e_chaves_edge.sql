-- APLICADA em 12/09/2026, em duas migrações:
--   `conta_financeiro_deixa_de_ser_admin` e `remove_solarview_ativo_e_cria_hsp`

-- ============================================================
-- 1. A conta de nível 'financeiro' deixa de ser admin
-- ============================================================
-- Estava com is_admin = true, igual às duas contas de nível 'admin'. Depois
-- da correção das policies de delete, is_admin é justamente quem pode apagar
-- cliente, usina, obra, vínculo obra-usina e relatório de obra — além de
-- mexer em usuarios_autorizados, feriados, regua_modelos e trilha_campos_fin,
-- e de ligar/desligar a régua.
--
-- SIMULADO ANTES (update dentro de transação + rollback). O que ela perde:
--   get_metricas ......... passa a devolver null. É o painel de GESTÃO:
--                          carteira, kWp, módulos, obras agendadas.
-- O que ela MANTÉM, conferido um por um:
--   is_autorizado() ...... true
--   meu_nivel() .......... 'financeiro'
--   get_resumo_financeiro, get_dre_mensal, get_dre_obras, get_fluxo_caixa,
--   get_fila_financeiro .. todos respondem
--   extrato_movimentos ... lê as 231 linhas
--   dre_lancamentos ...... lê as 477 linhas
--
-- Ou seja: o trabalho financeiro inteiro continua. O que sai é a visão de
-- diretoria — que é exatamente o que is_admin deve guardar.
--
-- DESFAZER, se ela usar o painel de gestão:
--   update public.usuarios_autorizados set is_admin = true
--    where nivel = 'financeiro';

update public.usuarios_autorizados
   set is_admin = false
 where nivel = 'financeiro' and is_admin;

-- ============================================================
-- 2. solarview_ativo sai
-- ============================================================
-- Estava em 0 e dizia, para quem lesse a config, que o monitoramento estava
-- desligado — enquanto ele entregava dado todo dia.
--
-- A primeira varredura (cron + funções do banco + telas) deu 13 chaves "sem
-- leitor", e isso era FALSO: as edge functions leem a config pelo service
-- role. A `regua_ativa` caía nesse caso e é a trava mais importante que
-- existe. Então, para esta, abri a superfície SolarView inteira, função por
-- função: solarview-diario, solarview-geracao, solarview-usinas,
-- solarview-vincular, usina-status e conferencia-geracao. Nenhuma lê.
--
-- A chave que de fato liga/desliga o vínculo automático é outra e existe:
-- solarview_vincular_ativo (= 1).

delete from public.config where chave = 'solarview_ativo';

-- ============================================================
-- 3. hsp entra
-- ============================================================
-- conferencia-geracao lê `C.hsp` com fallback '4.9' chumbado no código. A
-- chave nunca existiu, então valia o fallback. Mesmo caso das chaves do
-- recorde. Gravo o mesmo 4.9 — não muda nada hoje, só passa a ser ajustável
-- sem mexer em código, como manda o §7.
--
-- ⚠️ hsp e perf_ratio entram no MESMO cálculo de economia que o cliente lê,
-- junto com economia_por_kwh:
--     economia  = gerado * economia_por_kwh
--     esperado  = kwp * hsp * perf_ratio * dias
-- O perf_ratio já está calibrado (0,78). O economia_por_kwh não (0,73,
-- estimativa 0,78–0,82). Calibrar um sem os outros desloca o número.

insert into public.config (chave, valor)
values ('hsp', '4.9')
on conflict (chave) do nothing;
