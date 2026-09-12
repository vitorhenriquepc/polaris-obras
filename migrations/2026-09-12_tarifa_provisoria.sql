-- APLICADA em 12/09/2026, em duas migrações:
--   `tarifa_provisoria_pos_reajuste_abril`
--   `tarifa_status_distingue_derivado_de_calibrado`

-- ============================================================
-- 1. economia_por_kwh: 0,73 → 0,7968 (PROVISÓRIO)
-- ============================================================
-- DE ONDE VEM O NÚMERO
--   0,73     calibrado com a conta real da Eloana, vigente desde 01/01/2026
--   × 1,0915 reajuste da CPFL de 22/04/2026, +9,15% residencial — já estava
--            registrado em tarifa_status() como "último reajuste conhecido"
--   = 0,7968
--
-- Os dois são dados que já estavam no sistema. A multiplicação é aritmética,
-- não palpite — e cai dentro da faixa 0,78–0,82 que o CLAUDE.md estimava.
--
-- ISTO NÃO É CALIBRAÇÃO. Por isso a origem gravada é 'derivado do reajuste
-- registrado', e não 'calibrado com conta real'. O que a derivação não pega:
--   · bandeira tarifária do mês
--   · ICMS, PIS/COFINS e iluminação pública, que não seguem o mesmo percentual
--   · clientes comerciais, cujo reajuste foi diferente do residencial
--   · se a conta da Eloana já fugia da média, o desvio vem junto
--
-- SUBSTITUIR assim que houver uma conta de luz pós-abril na mão:
--   select calibrar_tarifa(<valor>, 'calibrado com a conta de <cliente>');
--
-- Por que não chamei calibrar_tarifa() aqui: ela confere is_admin(), que lê
-- auth.jwt(). Migração roda sem JWT, então a função recusaria. Faço o mesmo
-- que ela faz.
--
-- EFEITO, medido antes de aplicar (simulado em transação com rollback):
--   103.300 kWh em 12 meses (set/2025 a ago/2026, 55 usinas, mês corrente fora)
--   economia informada antes .... R$ 75.409,33
--   economia informada depois ... R$ 82.309,80
--   diferença ................... R$ 6.900,47 que o sistema deixava de mostrar

insert into public.tarifa_historico (valor, vigente_desde, origem, observacao)
values (0.7968, current_date, 'derivado do reajuste registrado',
        'PROVISORIO — 0,73 (conta da Eloana, jan/2026) x 1,0915 (reajuste CPFL de 22/04/2026, residencial). NAO veio de conta de luz. Substituir quando houver uma conta real pos-abril.');

update public.config set valor = '0.7968' where chave = 'economia_por_kwh';

-- ============================================================
-- 2. Consertando o efeito colateral que o item 1 causou
-- ============================================================
-- Gravar a linha provisória zerou o `meses_sem_calibrar`, porque ele contava
-- desde a última linha QUALQUER do histórico. Dois estragos:
--   · a rede de segurança "meses >= 12" do tarifa-lembrete reiniciou
--   · a mensagem diria "calibrado há 0 meses", que é falso
--
-- Agora o campo conta desde a última calibração COM CONTA REAL — que é o que
-- o nome sempre prometeu e o que o lembrete quer saber. Voltou a marcar 8
-- meses (conta da Eloana, jan/2026): verdadeiro, e reacende a rede de
-- segurança em vez de apagá-la.
--
-- Os gatilhos de calendário do tarifa-lembrete (maio, quando a conta com
-- tarifa nova chega; fevereiro, degrau do Fio B) nunca dependeram disto e
-- seguem iguais.
--
-- Campos novos, informativos:
--   provisorio ......... true quando o valor em uso não veio de conta real
--   desde_conta_real ... data da última calibração de verdade

create or replace function public.tarifa_status()
 returns json
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select json_build_object(
    'valor_atual', (select valor::numeric from config where chave='economia_por_kwh'),
    'desde', (select max(vigente_desde) from tarifa_historico),
    'provisorio', (select origem is distinct from 'calibrado com conta real'
                     from tarifa_historico
                    order by vigente_desde desc, id desc limit 1),
    'desde_conta_real', (select max(vigente_desde) from tarifa_historico
                          where origem = 'calibrado com conta real'),
    'meses_sem_calibrar', (select (extract(year from age(current_date, max(vigente_desde)))*12
                                 + extract(month from age(current_date, max(vigente_desde))))::int
                            from tarifa_historico
                           where origem = 'calibrado com conta real'),
    'reajuste_cpfl', 'todo ano em abril (aniversario contratual dia 8)',
    'ultimo_reajuste_conhecido', '22/04/2026 — +9,15% para residencial',
    'historico', (select coalesce(json_agg(json_build_object(
        'valor', h.valor, 'desde', h.vigente_desde, 'origem', h.origem, 'obs', h.observacao)
        order by h.vigente_desde desc),'[]'::json) from tarifa_historico h)
  );
$function$;

-- CONFERIDO depois de aplicar:
--   valor_atual ......... 0.7968
--   provisorio .......... true
--   desde_conta_real .... 2026-01-01
--   meses_sem_calibrar .. 8
