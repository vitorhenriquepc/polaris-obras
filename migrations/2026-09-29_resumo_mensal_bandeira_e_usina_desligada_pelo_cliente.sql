-- 29/09/2026 — Resumo mensal por cliente (modelo: GILBERTO, 4436), bandeira
-- tarifária da ANEEL, chuva no lugar de cada usina, e usina que o CLIENTE
-- desliga de propósito deixando de parecer defeito.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Usina desligada pelo cliente (Rua São Bernardo, GILBERTO)
-- ─────────────────────────────────────────────────────────────────────────────
-- O Vitor informou em 29/09: o Gilberto desliga a da Rua São Bernardo aos
-- domingos, por receio da parte elétrica. Os dados batem e vão além: de 01/06
-- a 28/09, zero em 17 de 17 domingos, 8 de 17 sábados e nos feriados 09/07 e
-- 07/09 — nenhum dia útil. Sem a marca, toda segunda-feira depois de um
-- sábado desligado a saúde dava CRÍTICO ("sem gerar há 2 dias de sol") e a
-- usina_estado dava "silencioso"; e o usina-status avisou a Lívia num domingo
-- (alerta_parada_em 13/09). Simulado dentro de um DO com raise (nada gravado):
-- com a marca, normal / ok; sem ela, silencioso / crítico.
alter table usinas add column if not exists desliga_dias_semana smallint[];
comment on column usinas.desliga_dias_semana is 'Dias da semana (0=domingo … 6=sábado) em que o CLIENTE desliga a usina de propósito. Zero nesses dias não é falha: fica fora de parada/silencioso/crítico, do alerta do usina-status e das perdas do resumo mensal.';

update usinas set desliga_dias_semana = '{0,6}',
  nota_geracao = 'Cliente desliga aos domingos por receio da parte elétrica (Vitor, 29/09). Os dados mostram o mesmo em metade dos sábados e nos feriados (09/07, 07/09).'
 where id = '0cc9b3bf-79ef-4171-9556-6069d5fd6a89' and nota_geracao is null;

-- usina_estado: no CTE `ult` (os últimos 20 dias), o zero num dia marcado sai
-- da lista — não conta como parado nem quebra a sequência:
--      and not (coalesce(d.kwh,0) <= 0.5
--               and extract(dow from d.dia)::smallint = any(coalesce(u.desliga_dias_semana, '{}')))
-- usinas_saude_calc: `u` passa a carregar `coalesce(u.desliga_dias_semana,'{}') as desliga`
-- e o CTE `sol` (dias de sol desde a última geração) ganha:
--      and not (extract(dow from r.dia)::smallint = any(j.desliga))
-- Os dois aplicados por replace na definição e conferidos em comando separado
-- (armadilha 2). Dia com geração num sábado continua contando no desempenho.
-- usina-status (edge function, v4): não avisa usina cujo dia de hoje está na
-- lista. Publicado com verify_jwt false; token errado → 403.

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Chuva no lugar de cada usina e bandeira tarifária
-- ─────────────────────────────────────────────────────────────────────────────
alter table radiacao_dia add column if not exists chuva_mm numeric;
comment on column radiacao_dia.chuva_mm is 'Chuva do dia no ponto (Open-Meteo precipitation_sum). Local de cada usina — o clima_dia só tem Araçatuba.';

create table if not exists bandeira_tarifaria (
  mes date primary key,
  bandeira text not null,
  adicional_r_mwh numeric not null,
  fonte text not null default 'ANEEL dados abertos',
  lido_em timestamptz not null default now()
);
comment on table bandeira_tarifaria is 'Bandeira tarifária acionada por mês (ANEEL, dados abertos). adicional_r_mwh em R$/MWh: 18,85 = R$ 1,885 a cada 100 kWh. Alimentada pela radiacao-diaria.';
alter table bandeira_tarifaria enable row level security;
drop policy if exists bandeira_leitura on bandeira_tarifaria;
create policy bandeira_leitura on bandeira_tarifaria for select to authenticated using (true);
revoke all on bandeira_tarifaria from anon;

-- A radiacao-diaria (v2) passou a pedir precipitation_sum junto e, na mesma
-- rodada, lê os últimos 24 meses do conjunto da ANEEL
-- (resource 0591b8f6-fe54-437b-b72b-1aa2efd46e42) para bandeira_tarifaria.
-- Falha da ANEEL não derruba o sol: volta em `bandeira.erro`. Simulado com
-- 92 dias antes de gravar; rodada real de 7 dias: 200, 24 meses, setembro
-- amarela 18,85.
--
-- Carga da chuva (29/09): só a coluna chuva_mm, só onde estava nula, de 29/06
-- a 28/09, nos 21 pontos — 1.323 linhas. NÃO se regravou o sol desses dias: a
-- fonte de hoje difere até 0,63 kWh/m² da carga inicial em alguns dias, e a
-- saúde mudaria sem ninguém ter pedido. Araçatuba, agosto: 13 mm, 4 dias com
-- 1 mm ou mais (o clima_dia dá 17,5 mm e os mesmos 4 dias).

insert into config(chave, valor) values ('resumo_sol_pct','75') on conflict (chave) do nothing;
-- "dia de sol" no resumo = radiação >= 75% do melhor dia do mês no lugar;
-- "nublado" = abaixo de saude_rad_min (2,5); o resto é "parcialmente nublado".

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Valor do projeto do GILBERTO (dado pelo Vitor, 29/09)
-- ─────────────────────────────────────────────────────────────────────────────
-- Simulado antes: o trg_dre_from_obra cria a receita de R$ 103.000 em
-- 01.1.01, competência e caixa 14/05/2026 (data de instalação), e o
-- trg_sincroniza_valor leva o preco_negociado da ficha a 103.000.
update obras set valor_projeto = 103000
 where id = '0b038e60-9633-4496-9b37-eb4694e97d8f' and valor_projeto is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) resumo_mensal_obra(obra, mes) — o resumo do mês por CLIENTE
-- ─────────────────────────────────────────────────────────────────────────────
-- Uma mensagem por obra, somando as usinas (o resumo de hoje, da
-- mensagens-usina-auto, é por usina e escrito pela IA). Todo número sai do
-- banco e o texto é montado por regra — não tem IA no meio (regra 3.1).
-- Não grava nada; quem for enfileirar na régua continua passando pela Lívia.
--
-- Recusa (ok:false): mês que não fechou, obra sem usina, mês sem geração, e o
-- mês em que TODAS as usinas foram instaladas (o primeiro resumo é o do
-- primeiro mês cheio).
--
-- "Dias sem geração": dias seguidos com zero, a partir da PRIMEIRA geração da
-- usina (zero antes disso é "não medi", armadilha 5), fora os dias marcados em
-- desliga_dias_semana. O texto diz "sem registro de geração" — antes de 06/09
-- não há usina_leitura para saber se foi comunicação ou parada — e só diz
-- "sem comunicação (internet)" quando o SolarView registrou datalogger
-- offline no período. O previsto é kWp × sol do dia × o rendimento típico da
-- própria usina (mediana dos dias bons no mês e no anterior).
-- Os dias em que o cliente desliga ficam em `desligada_pelo_cliente` para a
-- equipe, e NÃO vão no texto.
--
-- Rodado para as 58 obras com usina, agosto: 42 ok e 16 recusas legítimas
-- (8 instaladas em agosto; 3 sem geração em agosto — Lucinei, João Vitor e
-- UNI AUTO POSTO —; 5 com usina instalada só em setembro). Nenhum
-- erro, nenhuma barra invertida nem "null" no texto. Dias sem geração em 5.
-- Antes da regra da primeira geração eram 15, quase todas zeros de usina que
-- ainda não tinha começado a reportar.
-- número no jeito brasileiro: 1.234,5
create or replace function public._rm_num(p numeric, p_casas int default 0)
returns text language sql immutable set search_path to 'public' as $f$
  select translate(to_char(round(p, p_casas),
           'FM999,999,999,990' || case when p_casas > 0 then '.' || repeat('0', p_casas) else '' end), ',.', '.,');
$f$;

-- as usinas de uma obra num mês, com o ponto de sol de cada uma
create or replace function public._rm_usinas(p_obra uuid, p_fim date)
returns table(id uuid, apelido text, kwp numeric, inst date, la numeric, lo numeric,
              desliga smallint[], principal boolean)
language sql stable security definer set search_path to 'public' as $f$
  select u.id, coalesce(u.apelido, 'Usina'), u.potencia_kwp, u.data_instalacao,
         round(coalesce(u.latitude, -21.2089), 1), round(coalesce(u.longitude, -50.4328), 1),
         coalesce(u.desliga_dias_semana, '{}'), coalesce(ou.principal, false)
  from obra_usina ou join usinas u on u.id = ou.usina_id
  where ou.obra_id = p_obra and ou.saiu_em is null and u.ativa
    and (u.data_instalacao is null or u.data_instalacao <= p_fim);
$f$;

create or replace function public.resumo_mensal_obra(p_obra uuid, p_mes date default null)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
-- O resumo do mês de UMA obra (todas as usinas dela juntas), com o texto pronto
-- para o grupo. Todo número sai do banco (regra 3.1): geração de usina_geracao,
-- sol e chuva de radiacao_dia (no lugar da usina principal), bandeira de
-- bandeira_tarifaria, economia pela config economia_por_kwh. Não grava nada.
declare
  v_mes   date := date_trunc('month', coalesce(p_mes, (current_date - interval '1 month')::date))::date;
  v_fim   date;
  v_ant   date;
  v_o     record;
  v_tar   numeric := coalesce((select valor::numeric from config where chave='economia_por_kwh'), 0.73);
  v_radmin numeric := coalesce((select valor::numeric from config where chave='saude_rad_min'), 2.5);
  v_solpct numeric := coalesce((select valor::numeric from config where chave='resumo_sol_pct'), 75);
  v_nomes text[] := array['janeiro','fevereiro','março','abril','maio','junho','julho','agosto',
                          'setembro','outubro','novembro','dezembro'];
  v_nome_mes text; v_nome_ant text; v_nome_prox text;
  v_usinas jsonb; v_n int;
  v_kwh numeric; v_kwh_ant numeric; v_ant_cheio boolean;
  v_acum numeric; v_desde date;
  v_cl record; v_rad_ant numeric;
  v_inter jsonb; v_desl jsonb;
  v_band record; v_band_prox record;
  v_primeiro text;
  t text; x jsonb;
begin
  v_fim := (v_mes + interval '1 month - 1 day')::date;
  v_ant := (v_mes - interval '1 month')::date;
  v_nome_mes  := v_nomes[extract(month from v_mes)::int];
  v_nome_ant  := v_nomes[extract(month from v_ant)::int];
  v_nome_prox := v_nomes[extract(month from v_mes + interval '1 month')::int];

  select o.id, o.contrato, o.cliente, o.valor_projeto, o.whatsapp_grupo_id, o.optout_em,
         coalesce(o.cliente_externo, false) as externo
    into v_o from obras o where o.id = p_obra;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Obra não encontrada.'); end if;
  if v_fim >= current_date then
    return jsonb_build_object('ok', false, 'erro', 'O mês de ' || v_nome_mes || ' ainda não fechou.');
  end if;
  v_primeiro := initcap(split_part(trim(v_o.cliente), ' ', 1));

  select count(*) into v_n from public._rm_usinas(p_obra, v_fim);
  if v_n = 0 then return jsonb_build_object('ok', false, 'erro', 'Obra sem usina ativa no mês.'); end if;
  if not exists (select 1 from public._rm_usinas(p_obra, v_fim) u where u.inst is null or u.inst < v_mes) then
    return jsonb_build_object('ok', false, 'erro', 'Usina instalada em ' || v_nome_mes || ': o primeiro resumo é o do primeiro mês cheio.');
  end if;

  -- geração do mês, por usina (a mesma tabela que a ficha lê)
  select jsonb_agg(jsonb_build_object('usina_id', u.id, 'apelido', u.apelido, 'kwp', u.kwp,
                                      'kwh', round(coalesce(g.kwh, 0)), 'kwh_mes_anterior', round(ga.kwh))
                   order by coalesce(g.kwh, 0) desc),
         sum(g.kwh), sum(ga.kwh),
         bool_and(u.inst is null or u.inst < v_ant)
    into v_usinas, v_kwh, v_kwh_ant, v_ant_cheio
  from public._rm_usinas(p_obra, v_fim) u
  left join usina_geracao g  on g.usina_id = u.id and g.referencia = v_mes
  left join usina_geracao ga on ga.usina_id = u.id and ga.referencia = v_ant;
  if coalesce(v_kwh, 0) = 0 then
    return jsonb_build_object('ok', false, 'erro', 'Sem geração registrada em ' || v_nome_mes || '.');
  end if;

  select sum(g.kwh), min(g.referencia) filter (where g.kwh > 0)
    into v_acum, v_desde
  from public._rm_usinas(p_obra, v_fim) u join usina_geracao g on g.usina_id = u.id and g.referencia <= v_mes;

  -- o tempo no mês, no lugar da usina principal (ou da maior)
  with p as (select la, lo from public._rm_usinas(p_obra, v_fim) order by principal desc, kwp desc nulls last limit 1),
  d as (select r.dia, r.kwh_m2, r.chuva_mm from radiacao_dia r join p on r.lat = p.la and r.lon = p.lo
        where r.dia between v_mes and v_fim),
  m as (select max(kwh_m2) as mx from d)
  select count(*) as dias,
         count(*) filter (where d.kwh_m2 >= m.mx * v_solpct / 100) as sol,
         count(*) filter (where d.kwh_m2 < v_radmin) as nublado,
         count(*) filter (where d.kwh_m2 >= v_radmin and d.kwh_m2 < m.mx * v_solpct / 100) as parcial,
         count(*) filter (where d.chuva_mm >= 1) as dias_chuva,
         round(sum(d.chuva_mm)) as chuva_mm,
         round(avg(d.kwh_m2), 2) as rad_media,
         (select la from p) as la, (select lo from p) as lo
    into v_cl from d cross join m group by m.mx;
  select round(avg(r.kwh_m2), 2) into v_rad_ant
  from radiacao_dia r where r.lat = v_cl.la and r.lon = v_cl.lo
    and r.dia between v_ant and (v_mes - 1);

  -- dia a dia de cada usina, do mês anterior até o fim deste. `pr` é o que a
  -- usina costuma render por sol (kWh por kWp por kWh/m², mediana dos dias
  -- bons), para estimar o que teria gerado nos dias parados.
  with us as (select * from public._rm_usinas(p_obra, v_fim)),
  dia as (
    select u.id, u.apelido, u.kwp, s.dia::date as dia, dd.kwh, r.kwh_m2 as rad,
           coalesce(dd.kwh, 0) <= 0.5 as zero,
           extract(dow from s.dia)::smallint = any(u.desliga) as desliga
    from us u
    cross join lateral (select min(x0.dia) as prim from usina_dia x0 where x0.usina_id = u.id and x0.kwh > 0.5) pg
    cross join generate_series(greatest(v_mes - 31, coalesce(u.inst, v_mes - 31), coalesce(pg.prim, v_fim + 1)),
                               v_fim, interval '1 day') s(dia)
    left join usina_dia dd on dd.usina_id = u.id and dd.dia = s.dia::date
    left join radiacao_dia r on r.lat = u.la and r.lon = u.lo and r.dia = s.dia::date),
  pr as (
    select id, percentile_cont(0.5) within group (order by kwh / (kwp * rad)) as pr
    from dia where kwh > 0.5 and rad >= v_radmin and kwp > 0 group by id),
  d as (select dia.*, coalesce(pr.pr, 0) as pr from dia left join pr using (id)),
  -- interrupções: dias seguidos sem geração (fora os dias em que o cliente desliga)
  z as (
    select d.*, d.dia - (row_number() over (partition by d.id order by d.dia))::int as grp
    from d where d.zero and not d.desliga),
  run as (
    select id, apelido, grp, min(dia) as ini, max(dia) as fim,
           count(*) filter (where dia between v_mes and v_fim) as dias_mes,
           round(sum(case when dia between v_mes and v_fim then kwp * coalesce(rad, 0) * pr end)) as kwh_prev
    from z group by id, apelido, grp),
  st as (
    select r.id, r.grp, string_agg(distinct l.status, ', ') as status
    from run r join usina_leitura l on l.usina_id = r.id
      and (l.lida_em at time zone 'America/Sao_Paulo')::date between r.ini and r.fim
    group by r.id, r.grp),
  inter as (
    select jsonb_agg(jsonb_build_object(
             'usina_id', r.id, 'apelido', r.apelido, 'de', r.ini, 'ate', r.fim,
             'dias_no_mes', r.dias_mes, 'kwh_previsto', r.kwh_prev,
             'economia_prevista', round(r.kwh_prev * v_tar),
             'motivo', case when st.status ~ 'datalogger' then 'sem comunicação'
                            when st.status ~ 'injetando|inativos' then 'equipamento parado'
                            when st.status is not null then 'sem gerar' end,
             'status_lidos', st.status)
           order by r.ini) as j
    from run r left join st on st.id = r.id and st.grp = r.grp
    where r.dias_mes > 0),
  -- dias em que o cliente desliga (fica na resposta para a equipe; não vai no texto)
  desl as (
    select jsonb_agg(jsonb_build_object('usina_id', q.id, 'apelido', q.apelido, 'dias', q.dias,
                                        'kwh_previsto', q.kwh, 'economia_prevista', round(q.kwh * v_tar))) as j
    from (select id, apelido, count(*) as dias, round(sum(kwp * coalesce(rad, 0) * pr)) as kwh
          from d where zero and desliga and dia between v_mes and v_fim
          group by id, apelido) q)
  select inter.j, desl.j into v_inter, v_desl from inter, desl;

  select * into v_band from bandeira_tarifaria where mes = v_mes;
  select * into v_band_prox from bandeira_tarifaria where mes = (v_mes + interval '1 month')::date;

  -- ───────────── o texto ─────────────
  t := '☀️ *Resumo de ' || v_nome_mes || ' — ' ||
       case when v_n > 1 then 'suas ' || v_n || ' usinas' else 'sua usina' end || '*' || E'\n\n'
    || 'Olá, ' || v_primeiro || '! Aqui vai o resumo do mês:' || E'\n\n'
    || '⚡ *Geração:* ' || public._rm_num(v_kwh, 0) || ' kWh'
    || case when v_ant_cheio and coalesce(v_kwh_ant, 0) > 0 then
         ' (' || case when v_kwh >= v_kwh_ant then '+' else '−' end
         || public._rm_num(abs(round((v_kwh / v_kwh_ant - 1) * 100)), 0) || '% em relação a ' || v_nome_ant || ')'
       else '' end || E'\n'
    || '💰 *Economia estimada:* R$ ' || public._rm_num(v_kwh * v_tar, 0) || E'\n';

  if v_n > 1 then
    t := t || E'\n*Por usina*\n';
    for x in select * from jsonb_array_elements(v_usinas) loop
      t := t || '• ' || (x->>'apelido') || ': ' || public._rm_num((x->>'kwh')::numeric, 0) || ' kWh' || E'\n';
    end loop;
  end if;

  if coalesce(v_cl.dias, 0) >= 25 then
    t := t || E'\n🌤️ *O tempo em ' || v_nome_mes || '*' || E'\n'
      || v_cl.sol || ' dias de sol, ' || v_cl.parcial || ' parcialmente nublado' || case when v_cl.parcial = 1 then '' else 's' end
      || ' e ' || v_cl.nublado || ' nublado' || case when v_cl.nublado = 1 then '' else 's' end || '. '
      || case when v_cl.dias_chuva = 0 then 'Não choveu.'
              when v_cl.dias_chuva = 1 then 'Choveu em 1 dia (' || public._rm_num(v_cl.chuva_mm, 0) || ' mm).'
              else 'Choveu em ' || v_cl.dias_chuva || ' dias (' || public._rm_num(v_cl.chuva_mm, 0) || ' mm no mês).' end
      || case when v_rad_ant > 0 and abs(v_cl.rad_media / v_rad_ant - 1) >= 0.05 then
           ' Teve ' || public._rm_num(abs(round((v_cl.rad_media / v_rad_ant - 1) * 100)), 0) || '% '
           || case when v_cl.rad_media > v_rad_ant then 'mais' else 'menos' end || ' sol que ' || v_nome_ant || '.'
         else '' end || E'\n';
  end if;

  if v_inter is not null then
    t := t || E'\n⚠️ *Dias sem geração*\n';
    for x in select * from jsonb_array_elements(v_inter) loop
      t := t || '• ' || (x->>'apelido') || ': '
        || case when (x->>'de') = (x->>'ate') then 'em ' || to_char((x->>'de')::date, 'DD/MM')
                else 'de ' || to_char((x->>'de')::date, 'DD/MM') || ' a ' || to_char((x->>'ate')::date, 'DD/MM') end
        || case when (x->>'motivo') = 'sem comunicação' then ', sem comunicação com o inversor (internet)'
                when (x->>'motivo') = 'equipamento parado' then ', com o inversor parado'
                else ', sem registro de geração' end
        || case when ((x->>'ate')::date - (x->>'de')::date + 1) <> (x->>'dias_no_mes')::int
                then ' (' || (x->>'dias_no_mes') || ' dia' || case when (x->>'dias_no_mes')::int = 1 then '' else 's' end
                     || ' em ' || v_nome_mes || ')' else '' end
        || case when coalesce((x->>'kwh_previsto')::numeric, 0) > 0 then
             '. Pelo sol desses dias, o previsto seria de cerca de ' || public._rm_num((x->>'kwh_previsto')::numeric, 0)
             || ' kWh (≈ R$ ' || public._rm_num((x->>'economia_prevista')::numeric, 0) || ')'
           else '' end || '.' || E'\n';
    end loop;
  end if;

  t := t || E'\n📈 *Desde a instalação*' || coalesce(' (' || v_nomes[extract(month from v_desde)::int] || '/' || extract(year from v_desde) || ')', '') || E'\n'
    || public._rm_num(v_acum, 0) || ' kWh gerados · R$ ' || public._rm_num(v_acum * v_tar, 0) || ' de economia' || E'\n';
  if coalesce(v_o.valor_projeto, 0) > 0 and not v_o.externo then
    t := t || 'Isso já é ' || public._rm_num(v_acum * v_tar / v_o.valor_projeto * 100, 1)
      || '% do investimento de R$ ' || public._rm_num(v_o.valor_projeto, 0) || '.' || E'\n';
  end if;

  if v_band.mes is not null and v_band.adicional_r_mwh > 0 then
    t := t || E'\n' || case when v_band.bandeira ilike 'amarela%' then '🟡' else '🔴' end
      || ' *Bandeira ' || lower(v_band.bandeira) || ' em ' || v_nome_mes || ':* a conta de luz ficou R$ '
      || public._rm_num(v_band.adicional_r_mwh / 10, 2) || ' mais cara a cada 100 kWh comprados da rede. '
      || 'Quanto mais energia suas usinas produzem, menos você paga desse acréscimo.' || E'\n';
  elsif v_band.mes is not null then
    t := t || E'\n🟢 *Bandeira verde em ' || v_nome_mes || ':* sem acréscimo na conta de luz.' || E'\n';
  end if;
  if v_band_prox.mes is not null and (v_band.mes is null or v_band_prox.bandeira <> v_band.bandeira) then
    t := t || 'Para ' || v_nome_prox || ', a ANEEL definiu bandeira ' || lower(v_band_prox.bandeira)
      || case when v_band_prox.adicional_r_mwh > 0
              then ' (R$ ' || public._rm_num(v_band_prox.adicional_r_mwh / 10, 2) || ' a cada 100 kWh).'
              else ', sem acréscimo.' end || E'\n';
  end if;

  t := t || E'\nQualquer dúvida, estamos por aqui! ☀️\n_Equipe Polaris Energia Solar_';

  return jsonb_build_object(
    'ok', true, 'obra_id', v_o.id, 'contrato', v_o.contrato, 'cliente', v_o.cliente,
    'mes', v_mes, 'grupo', v_o.whatsapp_grupo_id is not null, 'optout', v_o.optout_em is not null,
    'kwh', round(v_kwh), 'kwh_mes_anterior', round(v_kwh_ant),
    'comparacao_valida', v_ant_cheio and coalesce(v_kwh_ant, 0) > 0,
    'economia', round(v_kwh * v_tar, 2), 'tarifa', v_tar,
    'tarifa_provisoria', coalesce((select (tarifa_status()->>'provisorio')::boolean), null),
    'usinas', v_usinas,
    'acumulado', jsonb_build_object('kwh', round(v_acum), 'economia', round(v_acum * v_tar, 2), 'desde', v_desde),
    'retorno', case when coalesce(v_o.valor_projeto, 0) > 0 then jsonb_build_object(
                 'valor_projeto', v_o.valor_projeto,
                 'pct', round(v_acum * v_tar / v_o.valor_projeto * 100, 1)) end,
    'clima', jsonb_build_object('dias', v_cl.dias, 'sol', v_cl.sol, 'parcial', v_cl.parcial, 'nublado', v_cl.nublado,
                                'dias_chuva', v_cl.dias_chuva, 'chuva_mm', v_cl.chuva_mm,
                                'rad_media', v_cl.rad_media, 'rad_media_anterior', v_rad_ant,
                                'ponto', jsonb_build_array(v_cl.la, v_cl.lo)),
    'interrupcoes', coalesce(v_inter, '[]'::jsonb),
    'desligada_pelo_cliente', coalesce(v_desl, '[]'::jsonb),
    'bandeira', case when v_band.mes is not null then jsonb_build_object('nome', v_band.bandeira, 'r_mwh', v_band.adicional_r_mwh) end,
    'bandeira_proxima', case when v_band_prox.mes is not null then jsonb_build_object('nome', v_band_prox.bandeira, 'r_mwh', v_band_prox.adicional_r_mwh) end,
    'texto', t);
end;
$function$;

revoke execute on function public.resumo_mensal_obra(uuid, date) from public;
revoke execute on function public.resumo_mensal_obra(uuid, date) from anon;
grant  execute on function public.resumo_mensal_obra(uuid, date) to authenticated;
revoke execute on function public._rm_usinas(uuid, date) from public;
revoke execute on function public._rm_usinas(uuid, date) from anon;
grant  execute on function public._rm_usinas(uuid, date) to authenticated;
revoke execute on function public._rm_num(numeric, int) from public;
revoke execute on function public._rm_num(numeric, int) from anon;
grant  execute on function public._rm_num(numeric, int) to authenticated;
