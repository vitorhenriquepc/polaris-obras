-- 29/09/2026 — Gilberto (4436) vira o CLIENTE MODELO do resumo mensal.
--
-- Pedido do Vitor (29/09):
--   * mandar na mensagem quanto ele perde por desligar a energia, por mês;
--   * só para o Gilberto, todo dia 5;
--   * agosto agora, e setembro no dia 5 de outubro;
--   * nunca no domingo — sempre em dia normal, às 9h da manhã.
--
-- Como ficou
--   * resumo_mensal_obra ganhou a linha "🔌 <usina> desligada": dias (domingos,
--     sábados, feriados), kWh que deixou de gerar pelo sol desses dias e
--     R$ de economia a menos. Feriado cadastrado conta como desligamento só
--     para usina que tem desliga_dias_semana. Agosto: 7 dias (5 domingos e 2
--     sábados), ≈ 509 kWh, ≈ R$ 406.
--   * modelo de régua `resumo_mensal` com `envio_proprio = true`: o disparo das
--     17h (regua_fila) não pega; quem envia é a edge function resumo-mensal,
--     cron `resumo-mensal` às 12:00 UTC = 9h, segunda a sexta. Continua
--     `precisa_aprovacao` — a Lívia aprova no card de sempre (regra 3.5).
--   * resumo_mensal_enfileirar(mes, envio, simular): põe como `aguardando` o
--     resumo das obras de config.resumo_mensal_obras. Envio = dia 5 do mês
--     seguinte, ou o próximo dia útil (proximo_dia_util: pula sábado, domingo
--     e feriado cadastrado) — e nunca hoje, para dar tempo de aprovar. Um por
--     obra por mês; recusado não volta.
--   * a edge function, às 9h: a partir do dia 3 enfileira o mês que fechou e
--     avisa a Lívia; em dia útil envia o que foi aprovado para hoje ou antes.
--     Não aprovado às 9h → avisa a Lívia e sai às 9h do próximo dia útil
--     depois da aprovação (data_limite = envio + 10).
--   * mensagens-usina-auto (v7): o resumo mensal da IA pula as obras do
--     cliente modelo (senão seriam dois resumos) e `resumo_mensal` conta como
--     cortesia no descanso entre mensagens.
--
-- Conferido
--   proximo_dia_util: 05/10/2026 seg → 05/10; 05/12 sáb → 07/12;
--   14/11 → 16/11 (15/11 domingo e feriado); 05/09/2027 dom → 06/09.
--   Pedir envio num domingo é recusado ("04/10 não é dia útil").
--   resumo-mensal: token errado 403; simular às 9h forçada → enfileiraria 1,
--   enviaria 0. mensagens-usina-auto simulado (mensal): 25 geradas, Gilberto
--   em `pulados` com "cliente modelo". Token errado 403.
--   Agosto enfileirado de verdade: regua_contatos 602, aguardando, 30/09,
--   limite 10/10, fora da regua_fila das 17h.
--
-- NÃO testado: o envio real pela Z-API depois de uma aprovação — acontece
-- pela primeira vez às 9h de 30/09, se o 602 estiver aprovado.

-- modelo da régua com envio próprio: o disparo das 17h não manda, quem manda é
-- a edge function resumo-mensal, às 9h, em dia útil
alter table regua_modelos add column if not exists envio_proprio boolean not null default false;
comment on column regua_modelos.envio_proprio is 'true = o regua-disparo das 17h NÃO envia este modelo; ele tem edge function própria com horário próprio (resumo_mensal: resumo-mensal, 9h). Continua passando pela aprovação da régua.';

insert into regua_modelos (codigo, nome, icone, dia, tipo, condicao, texto, ativo, ordem, janela_dias,
                           precisa_aprovacao, gerado_por_ia, repetivel, envio_proprio)
values ('resumo_mensal', 'Resumo do mês (cliente modelo)', '☀️', 0, 'da', 'sempre', '{texto_custom}', true, 96, 10,
        true, false, true, true)
on conflict (codigo) do nothing;

insert into config (chave, valor) values
  ('resumo_mensal_ativo', '1'),
  ('resumo_mensal_obras', '0b038e60-9633-4496-9b37-eb4694e97d8f'),
  ('resumo_mensal_dia', '5'),
  ('resumo_mensal_preparo_dia', '3')
on conflict (chave) do nothing;

-- o primeiro dia útil em p ou depois: pula sábado, domingo e feriado cadastrado
create or replace function public.proximo_dia_util(p date)
returns date language plpgsql stable set search_path to 'public' as $f$
declare d date := p;
begin
  while extract(dow from d) in (0, 6)
        or exists (select 1 from feriados f where f.ativo and f.data = d) loop
    d := d + 1;
  end loop;
  return d;
end $f$;

-- Põe na régua, como `aguardando`, o resumo do mês das obras do cliente modelo
-- (config.resumo_mensal_obras). Sai às 9h do dia `resumo_mensal_dia` do mês
-- seguinte — ou do próximo dia útil — pela edge function resumo-mensal, e só
-- depois de aprovado (regra 3.5). Um por obra por mês: se já existe, não repete
-- (nem se foi recusado). simular = true (o padrão) não grava nada.
create or replace function public.resumo_mensal_enfileirar(
  p_mes date default null, p_envio date default null, p_simular boolean default true)
returns jsonb
language plpgsql security definer set search_path to 'public' as $f$
declare
  v_mes   date := date_trunc('month', coalesce(p_mes, (current_date - interval '1 month')::date))::date;
  v_prox  date;
  v_dia   int  := coalesce((select valor::int from config where chave = 'resumo_mensal_dia'), 5);
  v_envio date;
  v_obras uuid[];
  v_o     uuid;
  r       jsonb;
  v_id    bigint;
  v_nomes text[] := array['janeiro','fevereiro','março','abril','maio','junho','julho','agosto',
                          'setembro','outubro','novembro','dezembro'];
  itens   jsonb := '[]'::jsonb;
begin
  if session_user = 'authenticator' and coalesce(auth.role(), '') <> 'service_role' and not is_autorizado() then
    return jsonb_build_object('ok', false, 'erro', 'Sem permissão.');
  end if;
  v_prox := (v_mes + interval '1 month')::date;
  if p_envio is not null then
    if public.proximo_dia_util(p_envio) <> p_envio then
      return jsonb_build_object('ok', false, 'erro', to_char(p_envio, 'DD/MM') || ' não é dia útil.');
    end if;
    v_envio := p_envio;
  else
    -- nunca hoje: precisa sobrar tempo para alguém aprovar antes das 9h
    v_envio := public.proximo_dia_util(greatest(v_prox + (v_dia - 1), current_date + 1));
  end if;
  if v_envio <= current_date then
    return jsonb_build_object('ok', false, 'erro', 'O envio precisa ser depois de hoje, para dar tempo de aprovar.');
  end if;

  select coalesce(array_agg(x::uuid), '{}') into v_obras
  from unnest(string_to_array(replace(coalesce((select valor from config where chave = 'resumo_mensal_obras'), ''), ' ', ''), ',')) x
  where x <> '';

  foreach v_o in array v_obras loop
    if exists (select 1 from regua_contatos c
               where c.obra_id = v_o and c.modelo = 'resumo_mensal'
                 and c.data_programada >= v_prox and c.data_programada < (v_prox + interval '1 month')::date) then
      itens := itens || jsonb_build_object('obra_id', v_o, 'pulado', 'já existe o resumo de ' || v_nomes[extract(month from v_mes)::int]);
      continue;
    end if;
    r := public.resumo_mensal_obra(v_o, v_mes);
    if not coalesce((r->>'ok')::boolean, false) then
      itens := itens || jsonb_build_object('obra_id', v_o, 'pulado', r->>'erro');
      continue;
    end if;
    if not (r->>'grupo')::boolean or (r->>'optout')::boolean then
      itens := itens || jsonb_build_object('obra_id', v_o, 'cliente', r->>'cliente',
                                           'pulado', case when (r->>'optout')::boolean then 'cliente pediu para sair' else 'sem grupo no WhatsApp' end);
      continue;
    end if;
    v_id := null;
    if not p_simular then
      insert into regua_contatos (obra_id, modelo, data_programada, data_limite, status, status_aprovacao,
                                  texto_custom, bloqueio_motivo)
      values (v_o, 'resumo_mensal', v_envio, v_envio + 10, 'pendente', 'aguardando', r->>'texto',
              'Resumo de ' || v_nomes[extract(month from v_mes)::int] || ' · sai às 9h de '
              || to_char(v_envio, 'DD/MM') || ' se aprovado (se não, às 9h do próximo dia útil depois da aprovação)')
      returning id into v_id;
    end if;
    itens := itens || jsonb_build_object('obra_id', v_o, 'cliente', r->>'cliente', 'contato_id', v_id,
                                         'envio', v_envio, 'texto', r->>'texto');
  end loop;

  return jsonb_build_object('ok', true, 'simular', p_simular, 'mes', v_mes, 'envio', v_envio, 'itens', itens);
end $f$;

revoke execute on function public.resumo_mensal_enfileirar(date, date, boolean) from public;
revoke execute on function public.resumo_mensal_enfileirar(date, date, boolean) from anon;
grant  execute on function public.resumo_mensal_enfileirar(date, date, boolean) to authenticated;
revoke execute on function public.proximo_dia_util(date) from public;
revoke execute on function public.proximo_dia_util(date) from anon;
grant  execute on function public.proximo_dia_util(date) to authenticated;

-- regua_fila: o modelo com envio próprio não sai às 17h
--   where c.status = 'pendente' and o.whatsapp_grupo_id not like 'http%'
--     and not coalesce(m.envio_proprio, false)
-- (aplicado por replace na definição e conferido em comando separado)

-- cron (33º):
-- select cron.schedule('resumo-mensal', '0 12 * * 1-5', $c$
--   select net.http_post(
--     url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/resumo-mensal',
--     headers := jsonb_build_object('Content-Type','application/json'),
--     body := jsonb_build_object('token',(select valor from config where chave='cron_token')),
--     timeout_milliseconds := 60000);
-- $c$);

-- agosto, pedido do Vitor — enfileirado em 29/09, sai às 9h de 30/09 se aprovado:
-- select resumo_mensal_enfileirar('2026-08-01', '2026-09-30', false);   -- → contato 602

-- resumo_mensal_obra, versão final (com a linha do desligamento):
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

-- Ajuste do mesmo dia: o preparo passa do dia 3 para o dia 2. Em outubro o
-- dia 3 é sábado, o cron só roda seg–sex, e o resumo de setembro entraria na
-- régua na segunda 05/10 — e como nunca sai no mesmo dia em que entra, iria
-- para 06/10. O Vitor quer o dia 5. O dia 2 às 9h vem depois do fechamento do
-- SolarView (geracao-mensal, 8h30 do dia 2).
update config set valor = '2' where chave = 'resumo_mensal_preparo_dia';
-- Setembro: entra na sexta 02/10, sai às 9h de 05/10 se aprovado.
-- Agosto (602): aprovado pelo Vitor no chat em 29/09 13:08, sai às 9h de 30/09.
