-- 14/11: a usina continuava aparecendo com problema depois de voltar (Vitor: "ainda
-- mostra que está offline depois de estar online").
--
-- Medido em 14/11, às 14h30: quatro usinas gerando normalmente, com o SolarView
-- dizendo "operando", liam na aba Usinas um selo de problema, porque a causa que
-- alguém anotou à mão numa queda antiga continuava valendo para sempre:
--   João Vitor Pozzeti (4425)  "sem wi-fi" (anotado em 10/09; operando desde 12/10)
--   JOAO JOSE DE SOUZA (4321)  "sem wi-fi" (10/09; operando desde 05/11)
--   MARASCA (4641)             "sem wi-fi" (15/09; operando desde 04/11)
--   VALDECIR RICOBONI (4452)   "motivo registrado" (28/09; operando desde 09/11)
-- O rotulo_usina() põe a causa na frente do estado, a anotação nunca caducava, e
-- a lista põe quem tem causa no fim, como "já tratado". A armadilha 19 (22/09)
-- tinha resolvido isso só dentro da usina_estado; a usina_dias e o rótulo da tela
-- continuavam lendo a anotação como fato, e o "cliente avisado" valia para
-- qualquer queda futura (um aviso de setembro apareceria como "avisado" numa
-- queda de dezembro).
--
-- A regra agora é uma só, em usina_causa_vigente(usina):
--   - a causa anotada vale para a queda em que foi feita. Deixa de valer quando a
--     usina volta a gerar num dia depois do da anotação ou, no caso de Wi-Fi,
--     quando o SolarView volta a dizer "operando" depois da anotação (é a volta
--     da comunicação, e o "voltou?" de hora em hora do usina-status vê isso) --
--     só se na hora da anotação ele não dizia "operando";
--   - o "cliente avisado" vale enquanto a usina não gerou depois do aviso.
-- Simulado antes de gravar, com as cinco causas que existiam: LUCINEI continua
-- valendo (sem comunicar desde 06/09); JOAO JOSE voltou a comunicar em 24/09,
-- MARASCA em 15/09, João Vitor voltou a gerar em 21/09 e VALDECIR em 29/09 --
-- as datas que o CLAUDE.md registra. Nas outras 69 usinas, estado, saúde, dias
-- e aviso das 8h saíram iguais; só o "há 1 dias" virou "há 1 dia".
-- Nada se apaga (regra 3.6): a anotação de uma queda que acabou continua em
-- usinas.causa até alguém anotar outra, e a ficha a mostra como "anterior". Quando
-- alguém troca ou apaga a causa, a anterior vai para usina_causa_hist.
--
-- Quem passa a seguir a regra: usina_estado (no lugar da causa_caduca_dias, que
-- deixa de ser lida), usina_dias, usinas_saude_calc, get_posvenda_usinas,
-- get_posvenda_lista, pendencias_posvenda (o "avisado há N dias" das usinas
-- paradas), get_usina_causa e salvar_causa.
--
-- E duas chaves para o "voltou?" do usina-status (14/11): usina_volta_hora_ini e
-- usina_volta_hora_fim, e o carimbo usina_status_conferido_em, que a aba Usinas
-- mostra ("status conferido às ...").

-- 1) o histórico das anotações que saem de cena -----------------------------------
create table if not exists public.usina_causa_hist (
  id bigserial primary key,
  usina_id uuid not null references public.usinas(id) on delete cascade,
  causa text not null,
  nota text,
  anotada_em timestamptz,
  anotada_por text,
  avisado_em timestamptz,
  resolvida_em date,
  resolvida_como text,
  trocada_em timestamptz not null default now(),
  trocada_por text
);
create index if not exists usina_causa_hist_usina on public.usina_causa_hist (usina_id, anotada_em desc);
alter table public.usina_causa_hist enable row level security;
revoke all on public.usina_causa_hist from anon, authenticated;
comment on table public.usina_causa_hist is
  'Anotações de causa de usina que saíram de cena (trocadas, apagadas ou de uma queda que acabou), gravadas pelo salvar_causa antes de mexer. Sem policy: só as funções security definer leem. 14/11.';

-- 2) a regra única ------------------------------------------------------------------
create or replace function public.usina_causa_vigente(p_usina uuid)
 returns table(causa text, vigente boolean, resolvida_em date, resolvida_como text, avisado_vigente boolean)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with u as (
    select id, causa, causa_em, status_atual, status_desde, cliente_avisado_em,
           (coalesce(causa_em, now()) at time zone 'America/Sao_Paulo')::date as causa_dia
      from usinas where id = p_usina
  ),
  ger as (   -- o primeiro dia em que gerou depois do dia da anotação
    select min(d.dia) as dia from usina_dia d, u
     where d.usina_id = u.id and d.kwh > 0.5 and d.dia > u.causa_dia
  ),
  com as (   -- Wi-Fi: a primeira leitura em que o SolarView voltou a falar com o
             -- inversor depois da anotação. É a data da volta: a geração dos dias
             -- parados chega depois, quando o datalogger descarrega a memória.
             -- Só conta se, na hora da anotação, o SolarView NÃO dizia "operando":
             -- o João Vitor (4425) leu "operando" com zero de 09/09 a 20/09 (o id
             -- antigo da Huawei, armadilha 27); ali quem diz que voltou é a geração
    select case when u.causa = 'wifi'
                 and (select l.status from usina_leitura l
                       where l.usina_id = u.id and l.lida_em <= coalesce(u.causa_em, now())
                       order by l.lida_em desc limit 1) is distinct from 'operando'
           then (select (min(l.lida_em) at time zone 'America/Sao_Paulo')::date
                   from usina_leitura l
                  where l.usina_id = u.id and l.status = 'operando'
                    and l.lida_em > coalesce(u.causa_em, now()))
           end as dia
      from u
  ),
  av as (    -- o aviso ao cliente vale enquanto a usina não gerou depois dele
    select exists (select 1 from usina_dia d
                    where d.usina_id = u.id and d.kwh > 0.5
                      and d.dia > (u.cliente_avisado_em at time zone 'America/Sao_Paulo')::date) as gerou_depois
      from u
  )
  select u.causa,
         (u.causa is not null and ger.dia is null and com.dia is null),
         case when u.causa is not null then coalesce(com.dia, ger.dia) end,
         case when u.causa is null then null
              when com.dia is not null then 'voltou a comunicar'
              when ger.dia is not null then 'voltou a gerar' end,
         (u.cliente_avisado_em is not null and not av.gerou_depois)
    from u, ger, com, av;
$function$;

revoke execute on function public.usina_causa_vigente(uuid) from public;
revoke execute on function public.usina_causa_vigente(uuid) from anon;
grant execute on function public.usina_causa_vigente(uuid) to authenticated, service_role;

comment on function public.usina_causa_vigente(uuid) is
  'A causa anotada à mão vale só para a queda em que foi feita: deixa de valer quando a usina volta a gerar num dia depois do da anotação ou, no Wi-Fi, quando o SolarView volta a dizer operando depois dela. Devolve também se o "cliente avisado" é desta queda. 14/11.';

-- 3) a aba Usinas -----------------------------------------------------------------
create or replace function public.get_posvenda_usinas()
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v json; v_boa numeric; v_at numeric; v_conf timestamptz;
begin
  if not is_autorizado() then return null; end if;
  select coalesce((select valor::numeric from config where chave='ger_faixa_boa'),0.85) into v_boa;
  select coalesce((select valor::numeric from config where chave='ger_faixa_atencao'),0.70) into v_at;
  -- a última vez que o status do SolarView foi conferido: a leitura completa ou o
  -- "voltou?" de hora em hora (14/11)
  select greatest(
           (select case when valor ~ '^\d{4}-\d{2}-\d{2}' then valor::timestamptz end
              from config where chave = 'usina_status_conferido_em'),
           (select max(lida_em) from usina_leitura)) into v_conf;
  with base as (
    select u.id as usina_id, u.apelido, u.potencia_kwp, u.cidade, u.fator_local,
           u.status_atual, u.status_desde, u.nota_geracao, u.data_instalacao,
           u.causa, u.causa_em, cv.vigente as causa_vigente, cv.resolvida_em, cv.resolvida_como,
           cv.avisado_vigente,
           c.nome as cliente, o.id as obra_id, o.contrato,
           (o.optout_em is not null) as saiu, ou.papel,
           e.estado, e.motivo, e.gravidade, e.dias_sem_gerar,
           -- a causa anotada só vale para a queda em que foi feita (usina_causa_vigente)
           rotulo_usina(e.estado, case when cv.vigente then u.causa end) as rotulo,
           (select x.pct from usina_meses(u.id) x
             where x.kwh>0 and x.completo and x.referencia < date_trunc('month', current_date)
             order by x.referencia desc limit 1) as pct,
           (select to_char(x.referencia,'MM/YYYY') from usina_meses(u.id) x
             where x.kwh>0 and x.completo and x.referencia < date_trunc('month', current_date)
             order by x.referencia desc limit 1) as ref_pct,
           (select round(sum(d.kwh)) from usina_dia d
             where d.usina_id=u.id and d.dia >= current_date - 14) as kwh_14d,
           (select max(d.dia) from usina_dia d
             where d.usina_id=u.id and d.kwh > 0.5) as ultima_geracao
    from usinas u
    join clientes c on c.id=u.cliente_id
    join obra_usina ou on ou.usina_id=u.id and ou.saiu_em is null
    join obras o on o.id=ou.obra_id
    cross join lateral usina_estado(u.id) e
    cross join lateral usina_causa_vigente(u.id) cv
    where u.ativa
  ), marcado as (
    select *, case
        when pct is null then 'sem_base'
        when pct >= v_boa*100 then 'boa'
        when pct >= v_at*100 then 'atencao'
        else 'baixa' end as desempenho
    from base
  )
  select json_build_object(
    'conferido_em', v_conf,
    'resumo', (select json_build_object(
        'total', count(*),
        'normal', count(*) filter (where estado='normal'),
        'sem_comunicacao', count(*) filter (where estado='sem comunicação'),
        'parada', count(*) filter (where estado='parada'),
        'critico', count(*) filter (where estado='crítico'),
        'silencioso', count(*) filter (where estado='silencioso'),
        'nunca_gerou', count(*) filter (where estado='nunca gerou'),
        'sem_dado', count(*) filter (where estado='sem dado'),
        'alerta', count(*) filter (where estado='alerta'),
        'com_causa', count(*) filter (where causa_vigente),
        'boa', count(*) filter (where desempenho='boa'),
        'atencao', count(*) filter (where desempenho='atencao'),
        'baixa', count(*) filter (where desempenho='baixa'),
        'sem_base', count(*) filter (where desempenho='sem_base'),
        'kwp', round(coalesce(sum(potencia_kwp),0)::numeric,2)) from marcado),
    'usinas', (select coalesce(json_agg(json_build_object(
        'usina_id', usina_id, 'apelido', apelido, 'kwp', potencia_kwp, 'cidade', cidade,
        'cliente', cliente, 'contrato', contrato, 'obra_id', obra_id, 'papel', papel,
        'estado', estado, 'rotulo', rotulo, 'motivo', motivo, 'gravidade', gravidade,
        'zerado', dias_sem_gerar,
        'causa', case when causa_vigente then causa end,
        'avisado', coalesce(avisado_vigente, false),
        'causa_anterior', case when causa is not null and not causa_vigente then json_build_object(
            'causa', causa, 'em', causa_em, 'resolvida_em', resolvida_em, 'como', resolvida_como) end,
        'status', status_atual, 'status_desde', status_desde, 'ultima_geracao', ultima_geracao,
        'desempenho', desempenho, 'pct', pct, 'ref_pct', ref_pct, 'fator', fator_local,
        'kwh_14d', kwh_14d, 'nota', nota_geracao, 'saiu', saiu)
      order by (case when causa_vigente then 1 else 0 end), gravidade,
               dias_sem_gerar desc, pct nulls last, cliente),'[]'::json) from marcado)
  ) into v;
  return v;
end $function$;

-- 4) a causa na ficha da usina ----------------------------------------------------
create or replace function public.get_usina_causa(p_usina uuid)
 returns json
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select json_build_object(
    -- a causa desta queda (nula se a anotação é de uma queda que já acabou)
    'causa', case when cv.vigente then u.causa end,
    'nota', case when cv.vigente or u.causa is null then u.causa_nota end,
    'em', case when cv.vigente then u.causa_em end,
    'por', case when cv.vigente then u.causa_por end,
    'avisado_em', case when cv.avisado_vigente then u.cliente_avisado_em end,
    -- a anotação de uma queda que acabou: fica à vista, não vale mais (14/11)
    'anterior', case when u.causa is not null and not cv.vigente then json_build_object(
        'causa', u.causa, 'nota', u.causa_nota, 'em', u.causa_em, 'por', u.causa_por,
        'avisado_em', u.cliente_avisado_em,
        'resolvida_em', cv.resolvida_em, 'como', cv.resolvida_como) end,
    'historico', (select coalesce(json_agg(json_build_object(
        'causa', h.causa, 'nota', h.nota, 'em', h.anotada_em, 'por', h.anotada_por,
        'avisado_em', h.avisado_em, 'resolvida_em', h.resolvida_em, 'como', h.resolvida_como,
        'trocada_em', h.trocada_em) order by h.anotada_em desc nulls last), '[]'::json)
        from (select * from usina_causa_hist x where x.usina_id = u.id
               order by x.anotada_em desc nulls last limit 5) h),
    -- a pista tirada da conversa do grupo só faz sentido com a usina com problema:
    -- sem isso, uma usina gerando normalmente ganharia "parece aguardando a
    -- concessionária" por um link da CPFL que o cliente mandou (MARASCA, 14/11)
    'sugestao', case when e.estado in ('normal', 'recém-ligada') then null else
                (select json_build_object('causa', p.causa, 'trecho', p.trecho,
                        'quando', p.quando, 'de_quem', p.de_quem)
                 from obra_usina ou join obras o on o.id=ou.obra_id,
                      lateral pista_de_causa(o.id, 45) p
                 where ou.usina_id=u.id and ou.saiu_em is null and p.causa is not null
                 order by p.quando desc limit 1) end
  ) into v
  from usinas u cross join lateral usina_causa_vigente(u.id) cv
       cross join lateral usina_estado(u.id) e
  where u.id=p_usina;
  return v;
end $function$;

-- 5) gravar a causa sem perder a anterior -----------------------------------------
create or replace function public.salvar_causa(p_usina uuid, p_causa text, p_nota text default null, p_avisado boolean default null)
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_old record;
  v_cv record;
  v_nova text := nullif(btrim(coalesce(p_causa, '')), '');
  v_mesma boolean;
begin
  if not is_autorizado() then return json_build_object('erro','sem permissao'); end if;
  select * into v_old from usinas where id = p_usina for update;
  if not found then return json_build_object('erro','usina não encontrada'); end if;
  select * into v_cv from usina_causa_vigente(p_usina);

  -- a mesma causa, na mesma queda: só ajusta a nota e o "avisado", mantém a data
  v_mesma := v_old.causa is not null and v_old.causa = v_nova and coalesce(v_cv.vigente, false);

  -- a anotação que sai de cena (trocada, apagada, ou de uma queda que já acabou)
  -- vai para o histórico antes de mexer (regra 3.6)
  if v_old.causa is not null and not v_mesma then
    insert into usina_causa_hist (usina_id, causa, nota, anotada_em, anotada_por, avisado_em,
                                  resolvida_em, resolvida_como, trocada_em, trocada_por)
    values (p_usina, v_old.causa, v_old.causa_nota, v_old.causa_em, v_old.causa_por,
            v_old.cliente_avisado_em, v_cv.resolvida_em, v_cv.resolvida_como,
            now(), coalesce(auth.email(), 'equipe'));
  end if;

  update usinas
     set causa = v_nova,
         causa_nota = p_nota,
         causa_em = case when v_nova is null then null
                         when v_mesma then v_old.causa_em
                         else now() end,
         causa_por = case when v_mesma then v_old.causa_por
                          else coalesce(auth.email(),'equipe') end,
         -- o aviso de uma queda que já acabou não vale para esta
         cliente_avisado_em = case
           when p_avisado is true then
             case when coalesce(v_cv.avisado_vigente, false) then coalesce(v_old.cliente_avisado_em, now()) else now() end
           when p_avisado is false then null
           else case when coalesce(v_cv.avisado_vigente, false) then v_old.cliente_avisado_em end
         end
   where id = p_usina;
  return json_build_object('ok', true, 'anterior_guardada', v_old.causa is not null and not v_mesma);
end $function$;

-- 6) quem já existia passa a seguir a regra -----------------------------------------
-- Trocas pontuais no texto que o banco tem hoje: cada trecho tem de aparecer uma vez
-- só, senão nada é gravado.
do $troca$
declare
  d text;
  n int;
  procedure_nome text;
begin
  -- usina_estado: a anotação de Wi-Fi segue a regra única; a causa_caduca_dias sai
  d := pg_get_functiondef('public.usina_estado(uuid)'::regprocedure);
  for procedure_nome, n in select x.nome, regexp_count(d, x.pat) from (values
      ('estado.caduca', $p$caduca as \(\s+select coalesce\(\(select valor::int from config where chave='causa_caduca_dias'\),2\) as dias\s+\),\s+$p$),
      ('estado.comentario', $p$-- a anotacao de wifi so vale enquanto a usina NAO voltou a gerar\.\s+-- gerou dentro da janela => a evidencia manda e o palpite e ignorado\.$p$),
      ('estado.wifi', $p$or \(u\.causa = 'wifi'\s+and \(hh\.ultimo_ok is null\s+or hh\.ultimo_ok < current_date - cd\.dias\)\)\) as sem_medir,$p$),
      ('estado.from', $p$from u, hist hh, caduca cd$p$),
      ('estado.plural', $p$'sem medição há ' \|\| m\.dias_mudo \|\| ' dias \(última em '$p$)) x(nome, pat)
  loop
    if n <> 1 then raise exception 'usina_estado: o trecho % aparece % vezes', procedure_nome, n; end if;
  end loop;
  d := regexp_replace(d, $p$caduca as \(\s+select coalesce\(\(select valor::int from config where chave='causa_caduca_dias'\),2\) as dias\s+\),\s+$p$, '');
  d := regexp_replace(d, $p$-- a anotacao de wifi so vale enquanto a usina NAO voltou a gerar\.\s+-- gerou dentro da janela => a evidencia manda e o palpite e ignorado\.$p$,
       $r$-- a anotacao de wifi vale so para a queda em que foi feita (usina_causa_vigente,
    -- 14/11): voltou a comunicar ou a gerar depois dela => a evidencia manda.$r$);
  d := regexp_replace(d, $p$or \(u\.causa = 'wifi'\s+and \(hh\.ultimo_ok is null\s+or hh\.ultimo_ok < current_date - cd\.dias\)\)\) as sem_medir,$p$,
       $r$or coalesce(cv.vigente and cv.causa = 'wifi', false)) as sem_medir,$r$);
  d := regexp_replace(d, $p$from u, hist hh, caduca cd$p$, $r$from u, hist hh, usina_causa_vigente(p_usina) cv$r$);
  d := regexp_replace(d, $p$'sem medição há ' \|\| m\.dias_mudo \|\| ' dias \(última em '$p$,
       $r$'sem medição há ' || m.dias_mudo || case when m.dias_mudo = 1 then ' dia' else ' dias' end || ' (última em '$r$);
  execute d;

  -- usina_dias: a mesma regra (a anotação de Wi-Fi nunca caducava aqui)
  d := pg_get_functiondef('public.usina_dias(uuid,integer)'::regprocedure);
  n := regexp_count(d, $p$or u\.causa='wifi'\) as sem_medir from u\),$p$);
  if n <> 1 then raise exception 'usina_dias: o trecho do wifi aparece % vezes', n; end if;
  d := regexp_replace(d, $p$or u\.causa='wifi'\) as sem_medir from u\),$p$,
       $r$or coalesce(cv.vigente and cv.causa = 'wifi', false)) as sem_medir
           from u, usina_causa_vigente(p_usina) cv),$r$);
  execute d;

  -- usinas_saude_calc: a causa que entra na conta e nas frases é a desta queda
  d := pg_get_functiondef('public.usinas_saude_calc(date)'::regprocedure);
  n := regexp_count(d, $p$u\.status_desde, u\.causa, u\.causa_em,$p$);
  if n <> 1 then raise exception 'usinas_saude_calc: o trecho da causa aparece % vezes', n; end if;
  d := regexp_replace(d, $p$u\.status_desde, u\.causa, u\.causa_em,$p$,
       $r$u.status_desde,
         (select case when cv.vigente then cv.causa end from usina_causa_vigente(u.id) cv) as causa, u.causa_em,$r$);
  execute d;

  -- get_posvenda_lista: o selo da usina na lista de clientes
  d := pg_get_functiondef('public.get_posvenda_lista()'::regprocedure);
  for procedure_nome, n in select x.nome, regexp_count(d, x.pat) from (values
      ('lista.causa', $p$select e\.estado, e\.motivo, e\.gravidade, us\.causa,\s+\(us\.cliente_avisado_em is not null\) as avisado$p$),
      ('lista.from', $p$join usinas us on us\.id=ou\.usina_id, lateral usina_estado\(ou\.usina_id\) e$p$)) x(nome, pat)
  loop
    if n <> 1 then raise exception 'get_posvenda_lista: o trecho % aparece % vezes', procedure_nome, n; end if;
  end loop;
  d := regexp_replace(d, $p$select e\.estado, e\.motivo, e\.gravidade, us\.causa,\s+\(us\.cliente_avisado_em is not null\) as avisado$p$,
       $r$select e.estado, e.motivo, e.gravidade, (case when cv.vigente then cv.causa end) as causa,
               coalesce(cv.avisado_vigente, false) as avisado$r$);
  d := regexp_replace(d, $p$join usinas us on us\.id=ou\.usina_id, lateral usina_estado\(ou\.usina_id\) e$p$,
       $r$join usinas us on us.id=ou.usina_id, lateral usina_estado(ou.usina_id) e,
             lateral usina_causa_vigente(ou.usina_id) cv$r$);
  execute d;

  -- pendencias_posvenda: "avisado há N dias" só quando o aviso é desta queda
  d := pg_get_functiondef('public.pendencias_posvenda()'::regprocedure);
  for procedure_nome, n in select x.nome, regexp_count(d, x.pat) from (values
      ('pend.avisado', $p$\(current_date - u\.cliente_avisado_em::date\)\s+as avisado_ha$p$),
      ('pend.group', $p$group by o\.cliente, o\.contrato, u\.apelido, u\.potencia_kwp,$p$)) x(nome, pat)
  loop
    if n <> 1 then raise exception 'pendencias_posvenda: o trecho % aparece % vezes', procedure_nome, n; end if;
  end loop;
  d := regexp_replace(d, $p$\(current_date - u\.cliente_avisado_em::date\)\s+as avisado_ha$p$,
       $r$(select case when cv.avisado_vigente then current_date - u.cliente_avisado_em::date end
                from usina_causa_vigente(u.id) cv)                             as avisado_ha$r$);
  d := regexp_replace(d, $p$group by o\.cliente, o\.contrato, u\.apelido, u\.potencia_kwp,$p$,
       $r$group by u.id, o.cliente, o.contrato, u.apelido, u.potencia_kwp,$r$);
  execute d;
end $troca$;

-- 7) as chaves do "voltou?" do usina-status ----------------------------------------
insert into public.config (chave, valor) values
  ('usina_volta_hora_ini', '8'),
  ('usina_volta_hora_fim', '19')
on conflict (chave) do nothing;

insert into public.config (chave, valor)
select 'usina_status_conferido_em', to_char(max(lida_em) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  from public.usina_leitura
on conflict (chave) do nothing;
