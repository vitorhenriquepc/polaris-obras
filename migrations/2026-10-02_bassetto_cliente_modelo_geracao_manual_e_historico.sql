-- 02/10/2026 — Júnior Bassetto vira cliente modelo do resumo mensal, com duas
-- usinas que ainda NÃO têm API (SolarEdge, esperando entrar no SolarView).
--
-- Pedido do Vitor (02/10): o resumo do Gilberto também para o Jose Antonio
-- Bassetto Junior, no dia 5 de outubro, com as três usinas dele — a Fundadores
-- (Auxsol, já no SolarView, id 960239) e as duas SolarEdge da fazenda solar,
-- cujos números por enquanto só existem no aplicativo do fabricante.
--
-- O que faltava no banco para isso não mentir:
--
-- 1. Geração lançada à mão. `usina_geracao.origem = 'manual'` passa a ser um
--    valor legítimo, com `parcial_ate` (o mês só vai até esse dia — o app da
--    SolarEdge parou de atualizar na terça 29/09) e `nota` (de onde veio o
--    número). Quando a API entrar, o upsert do solarview-geracao troca a origem
--    e um gatilho limpa `parcial_ate`/`nota` — o dado da plataforma manda.
--    Lançar à mão NÃO sobrescreve mês que veio da plataforma.
--
-- 2. Histórico de antes do monitoramento. A plataforma nem sempre devolve o
--    passado (armadilha 27): a Fundadores tem 17,88 MWh no app da Auxsol e o
--    SolarView só tem desde maio (13,89 MWh); as SolarEdge têm 549 e 171 MWh
--    de vida útil e nenhum mês aqui. `usinas.historico_kwh` é o que a usina
--    gerou ATÉ `historico_ate` (inclusive), lido em `historico_fonte`. O resumo
--    soma o histórico + os meses de usina_geracao DEPOIS dessa data — o mês que
--    já está dentro do histórico não conta duas vezes.
--
-- 3. resumo_mensal_obra:
--    * número lido no app sai com "≈" e arredondado (total em centenas de kWh,
--      acumulado em milhares) — o app mostra 9,6 MWh, não 9.600 kWh;
--    * mês parcial aparece como "(1 a 29/09)" na linha da usina;
--    * uma linha explica que o "≈" vem do app do inversor;
--    * a comparação com o mês anterior só sai se TODAS as usinas têm os dois
--      meses inteiros. Antes, uma usina sem o mês anterior entrava com zero e a
--      soma comparava 3 usinas contra 1 ("+500% em relação a agosto");
--    * "Desde a instalação" usa a data de instalação quando há histórico, e não
--      afirma mês quando ela não existe.
--
-- 4. usina_meses: mês parcial não é "completo" — senão o desempenho dele
--    (29 dias contra a previsão de 30) sairia rebaixado.
--
-- 5. clientes.chamar_de: o nome que vai no "Olá, ...!" do resumo. Sem ele, o
--    primeiro nome do cadastro — "Jose" para quem todo mundo chama de Júnior.
--
-- 6. config.resumo_sem_acumulado_obras: obras cujo resumo NÃO traz mais o
--    "Desde a instalação" (nem o retorno do investimento). O Júnior recebeu o
--    acumulado só no primeiro (setembro, contato 621, texto já gravado); a
--    partir de outubro, só o mês — decisão do Vitor em 02/10.
--
-- 7. Economia em R$ de cada usina na linha dela e uma linha "*Total:*"; o
--    total do mês (no topo e no Total) é a soma das linhas, para bater na conta
--    do cliente (Vitor, 02/10).
--
-- 8. Layout (Vitor, 02/10): cada usina em duas linhas com uma em branco entre
--    elas, e todo valor de economia em negrito (topo, usinas, Total, acumulado).
--
-- Fora do escopo, de propósito: obra_geracao_total (a ficha) continua sem o
-- histórico de antes do monitoramento. A ficha mostra o que está medido aqui;
-- o resumo do cliente mostra também o que o app do fabricante já tinha.

alter table usina_geracao add column if not exists parcial_ate date;
alter table usina_geracao add column if not exists nota text;
comment on column usina_geracao.parcial_ate is 'Só em origem manual: o mês vai até este dia (o app do fabricante parou de atualizar). Nulo = mês inteiro.';
comment on column usina_geracao.nota is 'Só em origem manual: de onde veio o número (ex.: "app SolarEdge, 9,6 MWh, print do Vitor em 02/10").';

alter table clientes add column if not exists chamar_de text;
comment on column clientes.chamar_de is 'Como a equipe chama o cliente nas mensagens ("Júnior"). Nulo = primeiro nome do cadastro.';

alter table usinas add column if not exists historico_kwh numeric;
alter table usinas add column if not exists historico_ate date;
alter table usinas add column if not exists historico_fonte text;
comment on column usinas.historico_kwh is 'Geração da usina desde a instalação ATÉ historico_ate (inclusive), lida na plataforma do fabricante — o passado que o monitoramento daqui não tem. O resumo mensal soma isto + os meses de usina_geracao depois de historico_ate.';
comment on column usinas.historico_ate is 'Último dia coberto por historico_kwh. Meses de usina_geracao até esta data não somam de novo.';
comment on column usinas.historico_fonte is 'De onde veio o histórico (app, data, quem).';

-- o dado da plataforma manda: chegou origem que não é manual, some a marca de parcial
create or replace function public.trg_usina_geracao_origem()
returns trigger language plpgsql set search_path to 'public' as $f$
begin
  if new.origem is distinct from 'manual' then
    new.parcial_ate := null;
    new.nota := null;
  end if;
  return new;
end $f$;
create or replace trigger trg_usina_geracao_origem before insert or update on usina_geracao
  for each row execute function public.trg_usina_geracao_origem();

-- Lança o mês de uma usina lido no app do fabricante. Recusa sobrescrever mês
-- que veio da plataforma. simular = true (o padrão) não grava.
create or replace function public.usina_geracao_manual(
  p_usina uuid, p_mes date, p_kwh numeric, p_parcial_ate date default null,
  p_nota text default null, p_simular boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_u record; v_atual record;
begin
  if not is_autorizado() then return jsonb_build_object('ok', false, 'erro', 'Sem permissão.'); end if;
  select id, apelido, potencia_kwp into v_u from usinas where id = p_usina;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Usina não encontrada.'); end if;
  if p_kwh is null or p_kwh < 0 then return jsonb_build_object('ok', false, 'erro', 'Informe os kWh do mês.'); end if;
  if v_mes > date_trunc('month', current_date)::date then
    return jsonb_build_object('ok', false, 'erro', 'Mês no futuro.');
  end if;
  if p_parcial_ate is not null and date_trunc('month', p_parcial_ate)::date <> v_mes then
    return jsonb_build_object('ok', false, 'erro', '"Até o dia" precisa ser dentro do mês lançado.');
  end if;
  select * into v_atual from usina_geracao where usina_id = p_usina and referencia = v_mes;
  if found and v_atual.origem is distinct from 'manual' then
    return jsonb_build_object('ok', false, 'erro',
      'Esse mês já veio da plataforma (' || coalesce(v_atual.origem, '?') || ', ' || round(v_atual.kwh) || ' kWh). O dado da plataforma manda.');
  end if;
  if p_simular then
    return jsonb_build_object('ok', true, 'simulado', true, 'usina', v_u.apelido, 'mes', v_mes, 'kwh', p_kwh,
      'parcial_ate', p_parcial_ate, 'substitui', case when v_atual.usina_id is not null then v_atual.kwh end,
      'kwh_por_kwp', case when v_u.potencia_kwp > 0 then round(p_kwh / v_u.potencia_kwp, 1) end);
  end if;
  insert into usina_geracao (usina_id, referencia, kwh, origem, lido_em, parcial_ate, nota)
  values (p_usina, v_mes, p_kwh, 'manual', now(), p_parcial_ate,
          coalesce(p_nota, '') || ' — lançado por ' || coalesce(auth.jwt() ->> 'email', session_user))
  on conflict (usina_id, referencia) do update
    set kwh = excluded.kwh, origem = 'manual', lido_em = now(),
        parcial_ate = excluded.parcial_ate, nota = excluded.nota;
  return jsonb_build_object('ok', true, 'simulado', false, 'usina', v_u.apelido, 'mes', v_mes, 'kwh', p_kwh);
end $f$;

-- Grava o histórico de antes do monitoramento. simular = true (o padrão) não grava.
create or replace function public.usina_historico_definir(
  p_usina uuid, p_kwh numeric, p_ate date, p_fonte text, p_simular boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare v_u record; v_dobra numeric;
begin
  if not is_autorizado() then return jsonb_build_object('ok', false, 'erro', 'Sem permissão.'); end if;
  select id, apelido, historico_kwh, historico_ate into v_u from usinas where id = p_usina;
  if not found then return jsonb_build_object('ok', false, 'erro', 'Usina não encontrada.'); end if;
  if p_kwh is null or p_kwh < 0 or p_ate is null then
    return jsonb_build_object('ok', false, 'erro', 'Informe os kWh e até que dia eles vão.');
  end if;
  if p_ate >= current_date then return jsonb_build_object('ok', false, 'erro', 'O histórico precisa terminar antes de hoje.'); end if;
  if coalesce(btrim(p_fonte), '') = '' then
    return jsonb_build_object('ok', false, 'erro', 'Diga de onde veio o número (app, data, quem).');
  end if;
  select sum(kwh) into v_dobra from usina_geracao where usina_id = p_usina and referencia <= p_ate;
  if p_simular then
    return jsonb_build_object('ok', true, 'simulado', true, 'usina', v_u.apelido, 'kwh', p_kwh, 'ate', p_ate,
      'antes', jsonb_build_object('kwh', v_u.historico_kwh, 'ate', v_u.historico_ate),
      'meses_dentro_do_historico_kwh', round(v_dobra));
  end if;
  update usinas set historico_kwh = p_kwh, historico_ate = p_ate,
         historico_fonte = p_fonte || ' — gravado por ' || coalesce(auth.jwt() ->> 'email', session_user) || ' em ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
   where id = p_usina;
  return jsonb_build_object('ok', true, 'simulado', false, 'usina', v_u.apelido, 'kwh', p_kwh, 'ate', p_ate);
end $f$;

revoke execute on function public.usina_geracao_manual(uuid, date, numeric, date, text, boolean) from public;
revoke execute on function public.usina_geracao_manual(uuid, date, numeric, date, text, boolean) from anon;
grant  execute on function public.usina_geracao_manual(uuid, date, numeric, date, text, boolean) to authenticated;
revoke execute on function public.usina_historico_definir(uuid, numeric, date, text, boolean) from public;
revoke execute on function public.usina_historico_definir(uuid, numeric, date, text, boolean) from anon;
grant  execute on function public.usina_historico_definir(uuid, numeric, date, text, boolean) to authenticated;
revoke execute on function public.trg_usina_geracao_origem() from public;
revoke execute on function public.trg_usina_geracao_origem() from anon;

-- mês parcial não é mês completo
create or replace function public.usina_meses(p_usina uuid)
 returns table(referencia date, kwh numeric, dias_ativos integer, dias_mes integer, previsto numeric, previsto_ajustado numeric, completo boolean, pct numeric)
 language sql stable security definer set search_path to 'public'
as $function$
  select g.referencia,
         g.kwh,
         greatest(0, least(
           extract(day from (date_trunc('month',g.referencia) + interval '1 month - 1 day'))::int,
           (date_trunc('month',g.referencia) + interval '1 month - 1 day')::date
             - greatest(u.data_instalacao, date_trunc('month',g.referencia)::date) + 1
         ))::int as dias_ativos,
         extract(day from (date_trunc('month',g.referencia) + interval '1 month - 1 day'))::int as dias_mes,
         p.kwh_previsto,
         round(p.kwh_previsto * coalesce(u.fator_local,1), 0) as previsto_ajustado,
         (u.data_instalacao is not null
           and u.data_instalacao <= date_trunc('month',g.referencia)::date
           and g.parcial_ate is null) as completo,
         case when coalesce(p.kwh_previsto,0) > 0
              then round((g.kwh / (p.kwh_previsto * coalesce(u.fator_local,1)) * 100)::numeric, 0) end as pct
  from usina_geracao g
  join usinas u on u.id = g.usina_id
  left join usina_previsao p on p.usina_id = u.id and p.mes = extract(month from g.referencia)
  where g.usina_id = p_usina
  order by g.referencia;
$function$;

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
  v_manual boolean; v_parcial date; v_hist boolean;
  v_eco_soma numeric;
  -- "Desde a instalação" só no primeiro resumo de quem está nesta lista (Vitor,
  -- 02/10: o Júnior viu o acumulado em setembro; daqui em diante, só o mês)
  v_sem_acum boolean := p_obra::text = any(string_to_array(replace(coalesce(
                          (select valor from config where chave = 'resumo_sem_acumulado_obras'), ''), ' ', ''), ','));
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
  -- como a equipe chama o cliente (clientes.chamar_de); sem isso, o primeiro nome
  -- do cadastro — que para o Jose Antonio Bassetto Junior daria "Jose", e ele é o Júnior
  v_primeiro := coalesce(nullif(btrim((select c.chamar_de from obras ob join clientes c on c.id = ob.cliente_id
                                        where ob.id = p_obra)), ''),
                         initcap(split_part(trim(v_o.cliente), ' ', 1)));

  select count(*) into v_n from public._rm_usinas(p_obra, v_fim);
  if v_n = 0 then return jsonb_build_object('ok', false, 'erro', 'Obra sem usina ativa no mês.'); end if;
  if not exists (select 1 from public._rm_usinas(p_obra, v_fim) u where u.inst is null or u.inst < v_mes) then
    return jsonb_build_object('ok', false, 'erro', 'Usina instalada em ' || v_nome_mes || ': o primeiro resumo é o do primeiro mês cheio.');
  end if;

  -- geração do mês, por usina (a mesma tabela que a ficha lê)
  -- `manual` = lido no aplicativo do fabricante e lançado à mão (usina ainda
  -- sem API, como as SolarEdge do Júnior Bassetto em 02/10); `parcial_ate` =
  -- o mês só tem até esse dia. A comparação com o mês anterior só vale se
  -- TODAS as usinas têm os dois meses inteiros — senão compararia 3 usinas
  -- contra 1 e daria "+500%".
  select jsonb_agg(jsonb_build_object('usina_id', u.id, 'apelido', u.apelido, 'kwp', u.kwp,
                                      'kwh', round(coalesce(g.kwh, 0)), 'kwh_mes_anterior', round(ga.kwh),
                                      'manual', g.origem = 'manual', 'parcial_ate', g.parcial_ate)
                   order by coalesce(g.kwh, 0) desc),
         sum(g.kwh), sum(ga.kwh),
         bool_and(u.inst is null or u.inst < v_ant) and count(ga.kwh) = count(*)
           and bool_and(g.parcial_ate is null and ga.parcial_ate is null),
         coalesce(bool_or(g.origem = 'manual'), false), max(g.parcial_ate)
    into v_usinas, v_kwh, v_kwh_ant, v_ant_cheio, v_manual, v_parcial
  from public._rm_usinas(p_obra, v_fim) u
  left join usina_geracao g  on g.usina_id = u.id and g.referencia = v_mes
  left join usina_geracao ga on ga.usina_id = u.id and ga.referencia = v_ant;
  if coalesce(v_kwh, 0) = 0 then
    return jsonb_build_object('ok', false, 'erro', 'Sem geração registrada em ' || v_nome_mes || '.');
  end if;

  -- desde a instalação: o que está em usina_geracao + o histórico de ANTES do
  -- monitoramento (usinas.historico_kwh, gerado até historico_ate), quando a
  -- plataforma não devolve o passado inteiro. Meses até historico_ate já estão
  -- dentro do histórico e não somam de novo. Com histórico, o "desde" é a data
  -- de instalação; sem ela, o texto não afirma mês.
  select sum(coalesce(case when uu.historico_ate <= v_fim then uu.historico_kwh end, 0)
             + coalesce((select sum(g.kwh) from usina_geracao g
                          where g.usina_id = u.id and g.referencia <= v_mes
                            and (uu.historico_ate is null or uu.historico_ate > v_fim
                                 or g.referencia > uu.historico_ate)), 0)),
         -- instalação depois do fim do histórico = data cadastrada errada (a Fundadores
         -- diz 05/05/2026 no SolarView e gerou em 2025): sem data confiável, sem mês
         case when bool_or(uu.historico_ate <= v_fim and (u.inst is null or u.inst > uu.historico_ate)) then null
              else min(case when uu.historico_ate <= v_fim then u.inst
                            else (select min(g.referencia) from usina_geracao g
                                   where g.usina_id = u.id and g.kwh > 0 and g.referencia <= v_mes) end) end,
         coalesce(bool_or(uu.historico_ate <= v_fim), false)
    into v_acum, v_desde, v_hist
  from public._rm_usinas(p_obra, v_fim) u join usinas uu on uu.id = u.id;

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
           (extract(dow from s.dia)::smallint = any(u.desliga)
            or (cardinality(u.desliga) > 0
                and exists (select 1 from feriados f where f.ativo and f.data = s.dia::date))) as desliga,
           exists (select 1 from feriados f where f.ativo and f.data = s.dia::date) as feriado
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
  -- dias em que o cliente desliga de propósito, e quanto isso custou no mês
  desl as (
    select jsonb_agg(jsonb_build_object('usina_id', q.id, 'apelido', q.apelido, 'dias', q.dias,
                                        'domingos', q.dom, 'sabados', q.sab, 'feriados', q.fer,
                                        'kwh_previsto', q.kwh, 'economia_prevista', round(q.kwh * v_tar))) as j
    from (select id, apelido, count(*) as dias,
                 count(*) filter (where feriado) as fer,
                 count(*) filter (where not feriado and extract(dow from dia) = 0) as dom,
                 count(*) filter (where not feriado and extract(dow from dia) = 6) as sab,
                 round(sum(kwp * coalesce(rad, 0) * pr)) as kwh
          from d where zero and desliga and dia between v_mes and v_fim
          group by id, apelido) q)
  select inter.j, desl.j into v_inter, v_desl from inter, desl;

  select * into v_band from bandeira_tarifaria where mes = v_mes;
  select * into v_band_prox from bandeira_tarifaria where mes = (v_mes + interval '1 month')::date;

  -- economia por usina, como aparece na linha dela (número do app arredondado
  -- a dezenas, medido a reais); o total do mês é a SOMA dessas linhas, para o
  -- cliente poder somar e bater (Vitor, 02/10: "a economia de cada lugar e o total")
  select sum(case when (uj->>'manual')::boolean then round((uj->>'kwh')::numeric * v_tar, -1)
                  else round((uj->>'kwh')::numeric * v_tar) end)
    into v_eco_soma from jsonb_array_elements(v_usinas) as e(uj);

  -- ───────────── o texto ─────────────
  t := '☀️ *Resumo de ' || v_nome_mes || ' — ' ||
       case when v_n > 1 then 'suas ' || v_n || ' usinas' else 'sua usina' end || '*' || E'\n\n'
    || 'Olá, ' || v_primeiro || '! Aqui vai o resumo do mês:' || E'\n\n'
    || '⚡ *Geração:* ' || case when v_manual then '≈ ' || public._rm_num(round(v_kwh, -2), 0)
                                else public._rm_num(v_kwh, 0) end || ' kWh'
    || case when v_ant_cheio and coalesce(v_kwh_ant, 0) > 0 then
         ' (' || case when v_kwh >= v_kwh_ant then '+' else '−' end
         || public._rm_num(abs(round((v_kwh / v_kwh_ant - 1) * 100)), 0) || '% em relação a ' || v_nome_ant || ')'
       else '' end || E'\n'
    -- o valor da economia em negrito, para destacar (Vitor, 02/10)
    || '💰 *Economia estimada:* *' || case when v_n > 1 then case when v_manual then '≈ R$ ' else 'R$ ' end || public._rm_num(v_eco_soma, 0)
                                          when v_manual then '≈ R$ ' || public._rm_num(round(v_kwh * v_tar, -1), 0)
                                          else 'R$ ' || public._rm_num(v_kwh * v_tar, 0) end || '*' || E'\n';

  if v_n > 1 then
    t := t || E'\n*Por usina*\n';
    -- cada usina em duas linhas (nome; kWh · R$ em negrito) e uma linha em
    -- branco entre elas — junto ficava apertado (Vitor, 02/10)
    for x in select * from jsonb_array_elements(v_usinas) loop
      t := t || E'\n• ' || (x->>'apelido')
        || case when x->>'parcial_ate' is not null
                then ' (1 a ' || to_char((x->>'parcial_ate')::date, 'DD/MM') || ')' else '' end || E'\n'
        || case when (x->>'manual')::boolean then '≈ ' else '' end
        || public._rm_num((x->>'kwh')::numeric, 0) || ' kWh · *'
        || case when (x->>'manual')::boolean then '≈ R$ ' || public._rm_num(round((x->>'kwh')::numeric * v_tar, -1), 0)
                else 'R$ ' || public._rm_num(round((x->>'kwh')::numeric * v_tar), 0) end
        || '*' || E'\n';
    end loop;
    t := t || E'\n*Total:* ' || case when v_manual then '≈ ' || public._rm_num(round(v_kwh, -2), 0) || ' kWh · *≈ R$ '
                                  else public._rm_num(v_kwh, 0) || ' kWh · *R$ ' end
      || public._rm_num(v_eco_soma, 0) || '*' || E'\n';
  end if;
  if v_manual then
    t := t || E'\n_≈ números do aplicativo do inversor, enquanto ' ||
         case when v_n > 1 then 'essas usinas entram' else 'a usina entra' end
         || ' no nosso monitoramento automático._' || E'\n';
  end if;

  if coalesce(v_cl.dias, 0) >= 25 then
    t := t || E'\n🌤️ *O tempo em ' || v_nome_mes || '*' || E'\n'
      -- os três grupos somam o mês, e a chuva é "desses dias" — não um quarto grupo
      -- (o Vitor somou 26 + 4 + 1 + 4 = 35 na primeira versão, 29/09)
      || case when v_cl.dias = extract(day from v_fim) then 'Dos ' || v_cl.dias || ' dias de ' || v_nome_mes || ': '
              else 'Nos ' || v_cl.dias || ' dias medidos de ' || v_nome_mes || ': ' end
      || regexp_replace(array_to_string(array_remove(array[
           case when v_cl.sol > 0 then v_cl.sol || ' de sol' end,
           case when v_cl.parcial = 1 then '1 parcialmente nublado'
                when v_cl.parcial > 1 then v_cl.parcial || ' parcialmente nublados' end,
           case when v_cl.nublado = 1 then '1 nublado'
                when v_cl.nublado > 1 then v_cl.nublado || ' nublados' end], null), ', '),
           ', ([^,]*)$', ' e \1') || '. '
      || case when v_cl.dias_chuva = 0 then 'Não choveu.'
              when v_cl.dias_chuva = 1 then 'Choveu em 1 desses dias (' || public._rm_num(v_cl.chuva_mm, 0) || ' mm no mês).'
              else 'Choveu em ' || v_cl.dias_chuva || ' desses dias (' || public._rm_num(v_cl.chuva_mm, 0) || ' mm no mês).' end
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

  -- desligada pelo cliente: quanto deixou de gerar e de economizar no mês
  -- (pedido do Vitor, 29/09 — o cliente precisa ver o que o desligamento custa)
  if v_desl is not null then
    for x in select * from jsonb_array_elements(v_desl) loop
      continue when coalesce((x->>'kwh_previsto')::numeric, 0) <= 0;
      t := t || E'\n🔌 *' || (x->>'apelido') || ' desligada:* em ' || v_nome_mes || ' ela ficou desligada em '
        || (x->>'dias') || ' dia' || case when (x->>'dias')::int = 1 then '' else 's' end || ' ('
        || regexp_replace(array_to_string(array_remove(array[
             case when (x->>'domingos')::int = 1 then '1 domingo'
                  when (x->>'domingos')::int > 1 then (x->>'domingos') || ' domingos' end,
             case when (x->>'sabados')::int = 1 then '1 sábado'
                  when (x->>'sabados')::int > 1 then (x->>'sabados') || ' sábados' end,
             case when (x->>'feriados')::int = 1 then '1 feriado'
                  when (x->>'feriados')::int > 1 then (x->>'feriados') || ' feriados' end], null), ', ')
           -- "5 domingos, 2 sábados" -> "5 domingos e 2 sábados"
           , ', ([^,]*)$', ' e \1')
        || '). Pelo sol desses dias, deixou de gerar cerca de ' || public._rm_num((x->>'kwh_previsto')::numeric, 0)
        || ' kWh — ≈ R$ ' || public._rm_num((x->>'economia_prevista')::numeric, 0) || ' de economia a menos no mês. '
        || 'Se quiser, nossa equipe tira qualquer dúvida sobre deixar o sistema ligado também nesses dias.' || E'\n';
    end loop;
  end if;

  if not v_sem_acum then
  t := t || E'\n📈 *Desde a instalação*' || coalesce(' (' || v_nomes[extract(month from v_desde)::int] || '/' || extract(year from v_desde) || ')', '') || E'\n'
    || case when v_hist or v_manual
            then '≈ ' || public._rm_num(round(v_acum, -3), 0) || ' kWh gerados · *≈ R$ ' || public._rm_num(round(v_acum * v_tar, -3), 0)
            else public._rm_num(v_acum, 0) || ' kWh gerados · *R$ ' || public._rm_num(v_acum * v_tar, 0) end
    || ' de economia*' || E'\n';
  if coalesce(v_o.valor_projeto, 0) > 0 and not v_o.externo then
    t := t || 'Isso já é ' || public._rm_num(v_acum * v_tar / v_o.valor_projeto * 100, 1)
      || '% do investimento de R$ ' || public._rm_num(v_o.valor_projeto, 0) || '.' || E'\n';
  end if;
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
    'acumulado', jsonb_build_object('kwh', round(v_acum), 'economia', round(v_acum * v_tar, 2), 'desde', v_desde,
                                    'inclui_historico', v_hist),
    'manual', v_manual, 'parcial_ate', v_parcial,
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


insert into config (chave, valor) values ('resumo_sem_acumulado_obras', '6de5ef85-ed0c-4cee-b2cc-776726c4a0c8')
on conflict (chave) do nothing;
-- Fundadores: instalação 05/05/2026 confirmada pelo Vitor, e os ~4 MWh do
-- contador do inversor de antes de maio ficam no acumulado (decisão dele, 02/10)
update usinas set nota_geracao = 'Instalação 05/05/2026 (confirmada pelo Vitor em 02/10). O contador do inversor já tinha cerca de 4 MWh antes de maio (app Auxsol 17,88 MWh no total, SolarView 13,89 MWh desde maio); por decisão do Vitor esses 3.990 kWh entram no acumulado.'
 where id = '5512c821-68ab-40b3-82ca-84f2fbea6b7b';
