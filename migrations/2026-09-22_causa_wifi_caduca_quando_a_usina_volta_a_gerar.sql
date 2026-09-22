-- 22/09/2026 — Palpite humano deixa de mandar no diagnóstico da usina.
--
-- ⚠️ O QUE ESTAVA ERRADO
-- A `usina_estado` tinha, no CTE `mudo`:
--
--     (u.status_atual in ('datalogger offline','datalogger sem coletar')
--      or u.causa = 'wifi') as sem_medir
--
-- `usinas.causa` é anotação que UMA PESSOA digita na tela ("acho que é o
-- wifi"). A função tratava isso como fato: `sem_medir = true` curto-circuitava
-- a cascata inteira para 'sem comunicação' — ANTES de chegar em 'parada',
-- 'nunca gerou' ou 'normal'. E palpite não caduca sozinho.
--
-- O caso que prova, medido em 22/09 — BURITAMA 4,96 kWp:
--   · anotação `causa = 'wifi'` posta em 15/09
--   · SolarView diz `status_atual = 'operando'`
--   · últimos 7 dias: 15,5 · 9,54 · 23,98 · 23,78 · 22,96 · 24,82 · 14,61 kWh
--   · e a `usina_estado` devolvia **'sem comunicação'**, gravidade 3, com o
--     motivo se contradizendo: "sem medição há 1 dias (última em 21/09)" —
--     21/09 é ontem, com 15,5 kWh no medidor.
--
-- O wi-fi voltou em algum momento depois de 15/09. A anotação não. A usina
-- contava como problema nos painéis e no total de "sem comunicação".
--
-- ✅ REGRA NOVA: evidência ganha de palpite; ausência de evidência, não.
-- A anotação só vale enquanto a usina NÃO voltar a gerar. Voltou a gerar
-- dentro da janela `causa_caduca_dias` (2), a anotação é ignorada e a cascata
-- segue pelas medições. Usina sem leitura nenhuma continua obedecendo — ali
-- não há evidência para contradizer ninguém, e quem sabe é a pessoa.
--
-- A anotação NÃO é apagada (regra 3.6): ela continua registrando o que a
-- pessoa achou, quando, e quem foi. O que muda é que o estado não obedece
-- mais a ela depois que os kWh voltam.
--
-- Efeito medido nas 4 usinas com anotação:
--   Buritama 4,96      'sem comunicação' → **'normal — gerando normalmente'** (grav. 3 → 4)
--   Araçatuba 6,20     segue 'sem comunicação' (SolarView diz datalogger offline, 31 dias sem gerar)
--   Votuporanga 6,25   segue 'sem comunicação' (datalogger offline, nunca gerou)
--   Araçatuba 8,68     segue 'sem comunicação' (zero leitura desde a instalação)

insert into config (chave, valor)
select 'causa_caduca_dias', '2'
where not exists (select 1 from config where chave='causa_caduca_dias');

CREATE OR REPLACE FUNCTION public.usina_estado(p_usina uuid)
 RETURNS TABLE(estado text, motivo text, dias_sem_gerar integer, dias_sol_perdidos integer, gravidade integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with u as (select * from usinas where id = p_usina),
  ini as (
    -- quando a usina entrou em operacao de verdade
    select coalesce(u.data_instalacao,
                    (select o.data_conclusao from obra_usina ou join obras o on o.id=ou.obra_id
                      where ou.usina_id=p_usina order by ou.principal desc limit 1)) as desde
    from u
  ),
  carencia as (
    select coalesce((select valor::int from config where chave='usina_carencia_dias'),15) as dias
  ),
  nova as (
    select (i.desde is not null and (current_date - i.desde) <= c.dias) as e_nova,
           greatest(0, (current_date - i.desde)) as idade
    from ini i, carencia c
  ),
  hist as (
    select count(*)::int as lidos,
           count(*) filter (where kwh > 0.5)::int as gerou,
           max(dia) filter (where kwh > 0.5) as ultimo_ok
    from usina_dia d cross join u
    where d.usina_id = p_usina and d.dia < current_date
      and (u.data_instalacao is null or d.dia >= u.data_instalacao)
  ),
  caduca as (
    select coalesce((select valor::int from config where chave='causa_caduca_dias'),2) as dias
  ),
  mudo as (
    -- a anotacao de wifi so vale enquanto a usina NAO voltou a gerar.
    -- gerou dentro da janela => a evidencia manda e o palpite e ignorado.
    select (u.status_atual in ('datalogger offline','datalogger sem coletar')
            or (u.causa = 'wifi'
                and (hh.ultimo_ok is null
                     or hh.ultimo_ok < current_date - cd.dias))) as sem_medir,
           coalesce((current_date - hh.ultimo_ok),
             case when u.status_desde is null then null
                  else (current_date - u.status_desde::date) end) as dias_mudo
    from u, hist hh, caduca cd
  ),
  ult as (
    select d.dia, d.kwh, i.mediana_kwh_kwp, row_number() over (order by d.dia desc) as pos
    from usina_dia d left join v_indice_dia i on i.dia = d.dia cross join u
    where d.usina_id = p_usina and d.dia < current_date
      and (u.data_instalacao is null or d.dia >= u.data_instalacao)
    order by d.dia desc limit 20
  ),
  zerados as (
    select coalesce(count(*),0)::int as n from (
      select pos, kwh, sum(case when kwh > 0.5 then 1 else 0 end)
             over (order by pos rows unbounded preceding) as marca from ult
    ) z where z.marca = 0
  ),
  sol_perdido as (
    select coalesce(count(*),0)::int as n from (
      select pos, kwh, mediana_kwh_kwp,
             sum(case when kwh > 0.5 or coalesce(mediana_kwh_kwp,0) <= 1.5 then 1 else 0 end)
               over (order by pos rows unbounded preceding) as marca from ult
    ) z where z.marca = 0 and coalesce(z.mediana_kwh_kwp,0) > 1.5
  )
  select
    case
      when u.status_atual in ('nao injetando','nao injetando com evento',
                              'inversores inativos','medidores inativos') then 'crítico'
      -- usina recem ligada que ainda nao reportou: nao e problema, e comeco
      when nv.e_nova and hh.gerou = 0 then 'recém-ligada'
      when m.sem_medir then 'sem comunicação'
      when hh.lidos = 0 then 'sem dado'
      when hh.gerou = 0 then 'nunca gerou'
      when z.n >= 5 then 'parada'
      when u.status_atual = 'operando' and sp.n >= 2 then 'silencioso'
      when u.status_atual = 'operando' then 'normal'
      when u.status_atual is null then 'sem dado'
      else 'alerta'
    end,
    case
      when u.status_atual in ('nao injetando','nao injetando com evento') then 'o inversor parou de injetar na rede'
      when u.status_atual = 'inversores inativos' then 'inversores inativos'
      when u.status_atual = 'medidores inativos' then 'medidores inativos'
      when nv.e_nova and hh.gerou = 0 then
        'ligada há ' || nv.idade || ' dia' || case when nv.idade=1 then '' else 's' end
        || ' — ainda pode não ter começado a reportar'
      when m.sem_medir and hh.ultimo_ok is not null then
        'sem medição há ' || m.dias_mudo || ' dias (última em ' || to_char(hh.ultimo_ok,'DD/MM')
        || ') — pode estar gerando, mas não conseguimos acompanhar'
      when m.sem_medir then
        'sem comunicar desde a instalação — pode estar gerando, mas não conseguimos acompanhar'
      when hh.lidos = 0 then 'a plataforma não devolve nenhum dado — conferir o cadastro'
      when hh.gerou = 0 then 'nunca gerou desde a instalação — equipamento provavelmente não ligado'
      when z.n >= 5 then 'comunicando e sem gerar há ' || z.n || ' dias (gerava até ' || to_char(hh.ultimo_ok,'DD/MM') || ')'
      when u.status_atual = 'operando' and sp.n >= 2
        then 'a plataforma diz operando, mas não gerou em ' || sp.n || ' dias seguidos de sol'
      when u.status_atual = 'operando' then 'gerando normalmente'
      else coalesce(u.status_atual,'sem status')
    end,
    z.n, sp.n,
    case
      when u.status_atual in ('nao injetando','nao injetando com evento',
                              'inversores inativos','medidores inativos') then 1
      when nv.e_nova and hh.gerou = 0 then 5      -- so acompanhar, nao e problema
      when m.sem_medir and coalesce(m.dias_mudo,999) >= 15 then 2
      when m.sem_medir then 3
      when hh.lidos = 0 then 3
      when hh.gerou = 0 then 2
      when z.n >= 5 then 1
      when u.status_atual = 'operando' and sp.n >= 2 then 2
      else 4
    end
  from u, nova nv, hist hh, mudo m, zerados z, sol_perdido sp;
$function$;

-- ── Conferência (comando SEPARADO, depois — armadilha 2) ────────────────────
-- 'causa_caduca_dias' na definição gravada .......... true
-- 'hh.ultimo_ok < current_date - cd.dias' gravado ... true
-- regra velha (`or u.causa = 'wifi') as sem_medir`) . false (sumiu)
-- config.causa_caduca_dias .......................... 2
