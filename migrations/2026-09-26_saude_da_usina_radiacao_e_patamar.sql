-- 26/09/2026 — Saúde da usina: sol do lugar, vizinhança do dia e o patamar da correção
--
-- O que o Vitor pediu: o % do card mentia em mês de instalação no meio, em mês
-- chuvoso e em usina de fora de Araçatuba. Pediu "saúde da usina num todo",
-- ponderando esses cenários. Decisões dele (26/09):
--   * "atenção" NÃO pode se confundir com falta de Wi-Fi → sem comunicação é
--     eixo próprio (nivel = 'sem_sinal'), nunca "atenção";
--   * abaixo de 70% = "geração muito abaixo do esperado";
--   * "crítico" só quando o sistema está comunicando e não gera em dia de sol;
--   * por enquanto só a equipe vê (nada vai para o cliente).
--
-- Conferido em modo simular antes de ligar qualquer coisa na tela: a função é
-- só leitura e ainda NÃO substitui o % do card — isso espera o Vitor aprovar
-- a tabela da simulação.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Radiação por usina (Open-Meteo, shortwave_radiation_sum MJ/m² ÷ 3,6)
--    Aplicada como migração `radiacao_por_usina_estrutura`.
-- ─────────────────────────────────────────────────────────────────────────────
alter table usinas add column if not exists latitude  numeric(9,6);
alter table usinas add column if not exists longitude numeric(9,6);

create table if not exists radiacao_dia (
  lat     numeric(5,1) not null,   -- arredondado a 0,1° (~11 km): usinas vizinhas dividem o ponto
  lon     numeric(5,1) not null,
  dia     date         not null,
  kwh_m2  numeric(6,3),
  lido_em timestamptz  default now(),
  primary key (lat, lon, dia)
);
alter table radiacao_dia enable row level security;   -- sem policy: só função security definer lê

-- Carga de 26/09: 63 usinas ganharam lat/lon do portfólio do SolarView
-- (consumerUnitLocation), 21 pontos de grade, 2.457 linhas de 01/06 a 25/09.
-- ⚠️ PENDENTE: ninguém atualiza a radiacao_dia sozinho ainda. Precisa entrar
-- no clima-diario (ou função própria) antes de a tela depender disso.

insert into config (chave, valor) values
  ('saude_janela_dias',      '30'),   -- dias fechados olhados
  ('saude_rad_min',          '2.5'),  -- kWh/m²/dia abaixo disso o dia é "nublado" e sai da conta
  ('saude_min_dias',         '10'),   -- dias de sol mínimos para dar veredito
  ('saude_atencao_pct',      '85'),   -- abaixo: "geração abaixo do esperado"
  ('saude_muito_abaixo_pct', '70'),   -- abaixo: "geração muito abaixo do esperado"
  ('saude_critico_dias',     '2')     -- dias de sol comunicando sem gerar = crítico
on conflict (chave) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. usina_editar: potência nova refaz o que dependia da antiga
--    (migração `usina_editar_potencia_refaz_previsao_e_kwh_kwp`)
--    Depois do `update usinas ... where id = v_id;`:
-- ─────────────────────────────────────────────────────────────────────────────
--  if p_json ? 'potencia_kwp' and coalesce(v_antes.potencia_kwp,0) > 0
--     and nullif(p_json->>'potencia_kwp','')::numeric > 0
--     and nullif(p_json->>'potencia_kwp','')::numeric <> v_antes.potencia_kwp then
--    update usina_dia set kwh_kwp = round(kwh / nullif(p_json->>'potencia_kwp','')::numeric, 3)
--     where usina_id = v_id and kwh is not null;
--    update usina_previsao set kwh_previsto = round(kwh_previsto * nullif(p_json->>'potencia_kwp','')::numeric / v_antes.potencia_kwp)
--     where usina_id = v_id and fonte = 'estimado';
--    update usinas set fator_local = null, fator_origem = null, fator_em = null
--     where id = v_id and coalesce(fator_origem,'') <> 'ajustado à mão';
--  end if;
--
-- Motivo: usina_previsao nasce UMA vez, pela potência da época
-- (manutencao_usinas só cria quando não existe). Fernando 4,44 → 2,48 kWp e a
-- Tays açougue 29,25 → 20 kWp ficaram com previsão 79% e 46% acima.

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Patamar: a visita que corrige a usina abre um "antes × depois"
--    (migrações `usina_saude_estrutura_patamar` e `fator_respeita_patamar`)
-- ─────────────────────────────────────────────────────────────────────────────
alter table plano_visita add column if not exists corrige_geracao boolean not null default false;
alter table usinas add column if not exists patamar_desde date;
alter table usinas add column if not exists patamar_motivo text;

create or replace function public.trg_visita_patamar() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.corrige_geracao and new.usina_id is not null and new.realizada_em is not null
     and (tg_op = 'INSERT' or old.realizada_em is distinct from new.realizada_em or not old.corrige_geracao) then
    update usinas
       set patamar_desde  = new.realizada_em,
           patamar_motivo = 'correção feita na visita de ' || to_char(new.realizada_em,'DD/MM/YYYY'),
           fator_local    = case when coalesce(fator_origem,'') = 'ajustado à mão' then fator_local end,
           fator_origem   = case when coalesce(fator_origem,'') = 'ajustado à mão' then fator_origem end,
           fator_em       = case when coalesce(fator_origem,'') = 'ajustado à mão' then fator_em end
     where id = new.usina_id;
  end if;
  return new;
end $$;
revoke execute on function public.trg_visita_patamar() from public;
revoke execute on function public.trg_visita_patamar() from anon;

drop trigger if exists trg_visita_patamar on plano_visita;
create trigger trg_visita_patamar after insert or update of realizada_em, corrige_geracao on plano_visita
for each row execute function public.trg_visita_patamar();

-- manutencao_usinas() e calibrar_fatores() ganharam, nos três lugares onde
-- filtram usina_geracao, o corte:
--   and (x.patamar_desde is null or g.referencia >= date_trunc('month', x.patamar_desde) + interval '1 month')
-- Sem isso o fator seria recalibrado com os meses ruins de antes da correção e
-- esconderia o ganho. Enquanto patamar_desde for nulo (todas as usinas hoje),
-- nada muda no comportamento do cron das 9h.

-- A visita da Tays (açougue) é de correção:
update plano_visita set corrige_geracao = true where id = '61642959-4518-4a62-8e7b-ed9889508439';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. A função
--    (migrações `usina_saude_funcao`, `usina_saude_frase_ajustes`,
--     `usina_saude_correcao_sem_efeito`)
--
-- Como decide:
--   * dia válido = gerou (> 0) E o sol NO LUGAR DA USINA passou de saude_rad_min.
--     Dia nublado sai da conta; zero não entra (armadilha 5: zero é "não medi").
--   * o "normal" de cada dia = mediana, entre todas as usinas com dia válido,
--     de kWh ÷ (kWp × sol do lugar). Precisa de vizinhanca_min_usinas no dia.
--   * desempenho = Σ kWh ÷ Σ (kWp × sol × normal do dia), nos dias válidos.
--     Instalação no meio do mês não pesa (é por dia), chuva não pesa (sai),
--     Guarulhos não é julgada pelo céu de Araçatuba (sol do lugar).
--   * antes = os 90 dias anteriores à janela, ou anteriores à correção.
--   * não usa fator_local de propósito: o fator "calibrado pelo histórico"
--     absorve cadastro errado, e a saúde existe para enxergar isso.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.usinas_saude_calc(p_ate date default null)
returns table (
  usina_id uuid, obra_id uuid, cliente text, apelido text, kwp numeric,
  nivel text, estado text, projeto text, frase text,
  desempenho int, desempenho_antes int, tendencia int,
  dias_validos int, dias_nublados int, dias_sol_sem_geracao int,
  ultimo_dia_gerou date, dias_sem_gerar int, janela_ini date, janela_fim date,
  correcao jsonb
)
language sql stable security definer set search_path to 'public' as $fn$
with cfg as (
  select
    coalesce(p_ate, current_date - 1) as ate,
    coalesce((select valor::int     from config where chave='saude_janela_dias'), 30)     as jan,
    coalesce((select valor::numeric from config where chave='saude_rad_min'), 2.5)        as radmin,
    coalesce((select valor::int     from config where chave='saude_min_dias'), 10)        as mindias,
    coalesce((select valor::numeric from config where chave='saude_atencao_pct'), 85)     as p_aten,
    coalesce((select valor::numeric from config where chave='saude_muito_abaixo_pct'), 70) as p_muito,
    coalesce((select valor::int     from config where chave='saude_critico_dias'), 2)     as critdias,
    coalesce((select valor::int     from config where chave='usina_carencia_dias'), 15)   as carencia,
    coalesce((select valor::int     from config where chave='vizinhanca_min_usinas'), 5)  as minviz,
    coalesce((select valor::int     from config where chave='parada_avisa_dias'), 7)      as avisa_dias
),
u as (
  select u.id, u.apelido, u.potencia_kwp as kwp, u.data_instalacao, u.status_atual, u.causa, u.causa_em,
         u.nota_geracao,
         -- patamar vale por 180 dias: depois disso a usina ja tem historico proprio de novo
         case when u.patamar_desde > c.ate - 180 then u.patamar_desde end as patamar,
         round(coalesce(u.latitude, -21.2089), 1) as la, round(coalesce(u.longitude, -50.4328), 1) as lo,
         cl.nome as cliente,
         (select ou.obra_id from obra_usina ou where ou.usina_id = u.id and ou.saiu_em is null
           order by ou.principal desc nulls last limit 1) as obra_id
  from usinas u cross join cfg c
  left join clientes cl on cl.id = u.cliente_id
  where u.ativa and coalesce(u.potencia_kwp,0) > 0
),
jan as (   -- janela de cada usina: os ultimos N dias, ou so depois da correcao
  select u.*, c.ate,
         greatest(c.ate - c.jan + 1, coalesce(u.patamar + 1, c.ate - c.jan + 1)) as ini,
         coalesce(u.patamar, c.ate - c.jan + 1) - 1 as antes_fim
  from u cross join cfg c
),
d as (     -- cada dia medido, com o sol do lugar da usina
  select j.id, dd.dia, dd.kwh, r.kwh_m2 as rad,
         case when dd.kwh > 0 and r.kwh_m2 >= c.radmin then dd.kwh / (j.kwp * r.kwh_m2) end as pr_d
  from jan j cross join cfg c
  join usina_dia dd on dd.usina_id = j.id and dd.dia between j.antes_fim - 89 and c.ate
  left join radiacao_dia r on r.lat = j.la and r.lon = j.lo and r.dia = dd.dia
),
ref as (   -- o "normal" de cada dia: mediana de todas as usinas naquele dia, ja descontado o sol de cada uma
  select d.dia, percentile_cont(0.5) within group (order by d.pr_d) as pr_ref
  from d where d.pr_d is not null group by d.dia
  having count(*) >= (select minviz from cfg)
),
agg as (
  select j.id,
    count(*) filter (where d.dia between j.ini and j.ate and d.pr_d is not null and rf.pr_ref is not null) as dias_j,
    sum(d.kwh) filter (where d.dia between j.ini and j.ate and d.pr_d is not null and rf.pr_ref is not null)
      / nullif(sum(j.kwp * d.rad * rf.pr_ref) filter (where d.dia between j.ini and j.ate and d.pr_d is not null and rf.pr_ref is not null), 0) as des_j,
    count(*) filter (where d.dia <= j.antes_fim and d.pr_d is not null and rf.pr_ref is not null) as dias_a,
    sum(d.kwh) filter (where d.dia <= j.antes_fim and d.pr_d is not null and rf.pr_ref is not null)
      / nullif(sum(j.kwp * d.rad * rf.pr_ref) filter (where d.dia <= j.antes_fim and d.pr_d is not null and rf.pr_ref is not null), 0) as des_a,
    count(*) filter (where d.dia between j.ini and j.ate and d.kwh > 0 and d.rad < (select radmin from cfg)) as nublados
  from jan j
  left join d on d.id = j.id
  left join ref rf on rf.dia = d.dia
  group by j.id
),
ult as (
  select j.id, (select max(x.dia) from usina_dia x where x.usina_id = j.id and x.kwh > 0) as ult
  from jan j
),
sol as (   -- dias de sol desde a ultima geracao (so conta o que o ceu permitia gerar)
  select j.id, count(r.dia) as dias_sol
  from jan j join ult on ult.id = j.id cross join cfg c
  left join radiacao_dia r on r.lat = j.la and r.lon = j.lo
       and r.dia > coalesce(ult.ult, j.data_instalacao, c.ate - 30) and r.dia <= c.ate and r.kwh_m2 >= c.radmin
  group by j.id
),
vis as (
  select distinct on (pv.usina_id) pv.usina_id, pv.prevista_para, pv.realizada_em
  from plano_visita pv
  where pv.corrige_geracao and coalesce(pv.status,'') not in ('cancelada')
  order by pv.usina_id, (pv.realizada_em is null) desc, coalesce(pv.realizada_em, pv.prevista_para) desc
),
base as (
  select j.*, a.dias_j, a.des_j, a.dias_a, a.des_a, a.nublados, ult.ult, s.dias_sol,
         v.prevista_para as vis_prevista, v.realizada_em as vis_feita,
         c.mindias, c.p_aten, c.p_muito, c.critdias, c.carencia, c.avisa_dias,
         -- sem sinal: datalogger offline, ou wi-fi anotado e a usina nao gerou depois da anotacao (armadilha 19)
         (coalesce(j.status_atual,'') ilike '%offline%'
          or (j.causa = 'wifi' and (ult.ult is null or ult.ult <= j.causa_em::date))) as sem_sinal,
         round(100 * a.des_j)::int as pct_j, round(100 * a.des_a)::int as pct_a
  from jan j cross join cfg c
  join agg a on a.id = j.id join ult on ult.id = j.id join sol s on s.id = j.id
  left join vis v on v.usina_id = j.id
),
cl as (
  select b.*,
    case
      when b.data_instalacao > b.ate - b.carencia                    then 'recem'
      when b.ult is null and b.status_atual is null                  then 'sem_dado'
      when b.sem_sinal                                               then 'sem_sinal'
      when b.dias_sol >= b.critdias                                  then 'parada'
      when b.patamar is not null and coalesce(b.dias_j,0) < b.mindias then 'observacao'
      when coalesce(b.dias_j,0) < b.mindias                          then 'sem_base'
      when b.pct_j < b.p_muito                                       then 'muito_abaixo'
      when b.pct_j < b.p_aten                                        then 'abaixo'
      else 'saudavel'
    end as k,
    -- baixa ha tempo: agora e antes, os dois abaixo do esperado
    (b.pct_j < b.p_aten and b.dias_a >= b.mindias and b.pct_a < b.p_aten) as cronica
  from base b
)
select
  cl.id, cl.obra_id, cl.cliente, cl.apelido, cl.kwp,
  case cl.k when 'parada' then 'critico' when 'muito_abaixo' then 'alerta' when 'abaixo' then 'atencao'
            when 'sem_sinal' then 'sem_sinal' when 'saudavel' then 'ok' else 'info' end,
  case cl.k when 'recem' then 'recém-ligada' when 'sem_dado' then 'sem dado'
            when 'sem_sinal' then 'sem comunicação' when 'parada' then 'sem gerar em dias de sol'
            when 'observacao' then 'em observação após a correção' when 'sem_base' then 'poucos dias medidos'
            when 'muito_abaixo' then 'geração muito abaixo do esperado' when 'abaixo' then 'geração abaixo do esperado'
            else 'saudável' end,
  case when cl.k in ('muito_abaixo','abaixo','observacao') or (cl.k = 'saudavel' and cl.patamar is not null) then
    case when cl.vis_prevista is not null and cl.vis_feita is null then 'correção agendada'
         when cl.patamar is not null and cl.k in ('muito_abaixo','abaixo') then 'correção sem efeito'
         when cl.patamar is not null then 'corrigida'
         when cl.nota_geracao is not null then 'causa conhecida'
         when cl.cronica then 'conferir cadastro' end
  end,
  -- a frase: o que a equipe le no card
  case cl.k
    when 'recem' then 'Ligada em ' || to_char(cl.data_instalacao,'DD/MM') || ' — ainda no período de carência.'
    when 'sem_dado' then 'Nenhuma medição recebida ainda. Confira o cadastro no SolarView.'
    when 'sem_sinal' then
      case when cl.ult is null or cl.ate - cl.ult > cl.avisa_dias then
        'Sem comunicação há ' || coalesce((cl.ate - cl.ult)::text || ' dias (última geração em ' || to_char(cl.ult,'DD/MM/YYYY') || ')', 'muito tempo')
        || case when cl.causa = 'wifi' then ' — Wi-Fi anotado em ' || to_char(cl.causa_em,'DD/MM') || '.' else ' — datalogger offline.' end
        || ' Tempo demais para esperar reconectar: precisa de alguém no local.'
      else
        'Sem comunicação com o inversor desde ' || to_char(cl.ult + 1,'DD/MM')
        || case when cl.causa = 'wifi' then ' — Wi-Fi anotado pela equipe.' else ' — datalogger offline.' end
        || ' Não é geração ruim: quando reconectar, os dias parados costumam voltar.'
      end
    when 'parada' then 'Comunicando, mas sem gerar há ' || (cl.ate - coalesce(cl.ult, cl.data_instalacao))
         || ' dia(s), ' || cl.dias_sol || ' deles com sol. Confira o inversor.'
    when 'observacao' then 'Correção feita em ' || to_char(cl.patamar,'DD/MM') || '. Medindo o novo patamar: '
         || coalesce(cl.dias_j,0) || ' de ' || cl.mindias || ' dias de sol'
         || coalesce(' (antes: ' || cl.pct_a || '%).', '.')
    when 'sem_base' then 'Só ' || coalesce(cl.dias_j,0) || ' dia(s) de sol medidos nos últimos '
         || (cl.ate - cl.ini + 1) || ' — pouco para comparar.'
    else
      'Gerou ' || cl.pct_j || '% do esperado em ' || cl.dias_j || ' dias de sol'
      || case when cl.nublados = 1 then ' (1 dia nublado fora da conta)'
              when cl.nublados > 1 then ' (' || cl.nublados || ' dias nublados fora da conta)' else '' end
      || case when cl.patamar is not null and cl.pct_a is not null
              then '. Antes da correção: ' || cl.pct_a || '%'
              when cl.pct_a is not null and abs(cl.pct_j - cl.pct_a) >= 10
              then '. Nos 90 dias anteriores: ' || cl.pct_a || '%'
              else '' end
      || case when cl.patamar is not null and cl.pct_j < cl.p_aten
              then '. A correção ainda não trouxe a usina para o esperado — vale voltar ao local.'
              when cl.patamar is not null
              then '. Correção resolveu.'
              when cl.vis_prevista is not null and cl.vis_feita is null and cl.pct_j < cl.p_aten
              then '. Correção agendada para ' || to_char(cl.vis_prevista,'DD/MM') || '.'
              when cl.nota_geracao is not null and cl.pct_j < cl.p_aten
              then '. Causa conhecida: ' || cl.nota_geracao || '.'
              when cl.cronica then '. Baixa desde sempre — conferir cadastro (potência, módulos, sombra).'
              else '.' end
  end,
  cl.pct_j, cl.pct_a,
  case when cl.dias_j >= cl.mindias and cl.dias_a >= cl.mindias then cl.pct_j - cl.pct_a end,
  coalesce(cl.dias_j,0)::int, coalesce(cl.nublados,0)::int, coalesce(cl.dias_sol,0)::int,
  cl.ult, (cl.ate - cl.ult)::int, cl.ini, cl.ate,
  case when cl.vis_prevista is not null or cl.patamar is not null then jsonb_build_object(
    'prevista_para', cl.vis_prevista, 'realizada_em', cl.vis_feita, 'patamar_desde', cl.patamar,
    'antes_pct', cl.pct_a, 'depois_pct', case when cl.patamar is not null then cl.pct_j end,
    'dias_depois', case when cl.patamar is not null then cl.dias_j end) end
from cl;
$fn$;

-- o cálculo cru não fica exposto nem para authenticated
revoke execute on function public.usinas_saude_calc(date) from public;
revoke execute on function public.usinas_saude_calc(date) from anon;
revoke execute on function public.usinas_saude_calc(date) from authenticated;

-- o que a tela vai chamar: só equipe (is_autorizado)
create or replace function public.usinas_saude(p_ate date default null)
returns setof jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not is_autorizado() then return; end if;
  return query select to_jsonb(s) from usinas_saude_calc(p_ate) s;
end $fn$;

create or replace function public.usina_saude(p_usina uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v jsonb;
begin
  if not is_autorizado() then return null; end if;
  select to_jsonb(s) into v from usinas_saude_calc(null) s where s.usina_id = p_usina;
  return v;
end $fn$;

revoke execute on function public.usinas_saude(date) from public;
revoke execute on function public.usinas_saude(date) from anon;
grant  execute on function public.usinas_saude(date) to authenticated;
revoke execute on function public.usina_saude(uuid) from public;
revoke execute on function public.usina_saude(uuid) from anon;
grant  execute on function public.usina_saude(uuid) to authenticated;
-- ACL conferida: usinas_saude/usina_saude = {postgres,authenticated,service_role};
-- usinas_saude_calc = {postgres,service_role}.

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Dados de 26/09 (registro — já aplicados)
-- ─────────────────────────────────────────────────────────────────────────────
-- VALDECIR RICOBONI (Atual Noivas): usinas.causa = 'wifi' (caiu segunda 22/09,
--   informado pelo Vitor). regua_contatos 598 (usina_wifi) aprovada pelo Vitor,
--   programada para 28/09 17h — sábado não sai mensagem.
--
-- FERNANDO (4349): usina 4,44 → 2,48 kWp (4 módulos de 620 Wp, informado pelo
--   Vitor); 127 kwh_kwp recalculados; previsão reescalada. Obra: vendedor
--   Vitor Carvalho, origem network (já era), distancia_km = 0 (Araçatuba),
--   potencia_kwp 2,48, qtd_modulos 4, modelo 620Wp. A obra estava travada
--   pela trava_campos_obra ("preencha: vendedor") — não se contornou a trava,
--   preencheu-se o que ela pedia. Era um dos 5 cards incompletos do §10.
--   Resultado: ~49% cravado → 86% (saudável).
--
-- TAYS açougue (20 kWp) e rancho (38,5 kWp): previsão refeita pela potência
--   corrigida em 22/09, fator solto para recalibrar.
--   plano_visita 61642959-… : "Visita técnica e CORREÇÃO do sistema do açougue",
--   prevista 05/10/2026 — DATA PROVISÓRIA, a confirmar pelo Vitor.
--   corrige_geracao = true.
--
-- ACADEMIA sistema antigo: nota_geracao = 'Predio realizando sombreamento'
--   (mesmo padrão do sistema novo, decisão do Vitor) e fator 'ajustado à mão'
--   (0,781) para o cron não recalibrar em cima da sombra.

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Simulação (26/09, janela 27/08–25/09) — o que a tela mostraria
-- ─────────────────────────────────────────────────────────────────────────────
-- 65 usinas ativas com potência: 52 saudáveis · 1 geração muito abaixo (Tays açougue 60%, correção
-- agendada) · 4 abaixo (Luiz P. Barreto 73% conferir cadastro; Academia antigo
-- 73% e novo 79%, causa conhecida; Guaiçara/Maria Aparecida 79% com 11 dias) ·
-- 3 sem comunicação (Valdecir desde 22/09; Av. Brasília desde 25/09; LUCINEI
-- há 105 dias → "precisa de alguém no local") · 5 informativas (CELIA e JACIR
-- recém-ligadas, João Vitor 5 dias medidos, UNI AUTO POSTO ×2 sem dado).
-- Nenhuma "crítica" hoje.
--
-- Tays açougue, simulado dentro de um DO que termina em RAISE (tudo desfeito,
-- conferido depois: visita segue 'prevista', patamar nulo, kWh intacto):
--   hoje            → alerta · muito abaixo · correção agendada ·
--                     "Gerou 60% do esperado em 28 dias de sol (2 dias nublados
--                      fora da conta). Correção agendada para 05/10."
--   feita há 5 dias → info · em observação · "Correção feita em 20/09. Medindo o
--                     novo patamar: 5 de 10 dias de sol (antes: 59%)."
--   feita, sem ganho→ alerta · correção sem efeito · "... Antes da correção: 59%.
--                     A correção ainda não trouxe a usina para o esperado — vale
--                     voltar ao local."
--   feita, +50%     → ok · corrigida · "Gerou 92% ... Antes da correção: 59%.
--                     Correção resolveu."
