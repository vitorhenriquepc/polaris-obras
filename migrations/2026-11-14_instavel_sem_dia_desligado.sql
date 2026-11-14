-- 14/11: a "conexão instável" não conta a queda que começa no dia em que o cliente
-- desliga a usina de propósito (usinas.desliga_dias_semana).
--
-- A lista "📶 conexão instável" (pendencias_posvenda -> conexao_instavel, no aviso
-- das 8h de segunda desde 05/11, e na aba Hoje do pós-venda desde 14/11) conta as
-- quedas de cada usina em 14 dias pela usina_queda_atual().quedas_14d. A Rua São
-- Bernardo do GILBERTO (4436) aparecia com 4 quedas -- e as quatro começaram num
-- sábado ou domingo (01/11, 07/11, 08/11 e 14/11, sempre na leitura das 9h15): é
-- ele desligando o sistema, que leva o datalogger junto (§4, "desliga_dias_semana").
-- Não é internet instável.
--
-- Simulado antes de gravar, com as leituras de 31/10 a 14/11: só a Rua São Bernardo
-- muda (4 -> 0); as outras 20 usinas com queda em 14 dias ficam iguais, e a lista
-- fica com Zuleica (4618), TANAKA (4745) e a Igreja (4810).
--
-- Só muda o quedas_14d. O "desde", as "horas" e o "sem_comunicar" (que a
-- usina_aviso_cliente usa para a regra das 48 h) ficam como estavam: quem segura o
-- aviso de fim de semana do Gilberto é a usina_estado, que já ignora os dias
-- desligados.

create or replace function public.usina_queda_atual(p_usina uuid)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with l as (
    select lida_em, status from usina_leitura where usina_id = p_usina
  ), ult as (
    select lida_em, status from l order by lida_em desc limit 1
  ), ult_ok as (   -- a última leitura em que o SolarView falava com o inversor
    select max(lida_em) as em from l where status is distinct from 'datalogger offline'
  ), ini as (      -- a primeira leitura da queda em curso
    select min(l.lida_em) as em from l, ult_ok
     where l.status = 'datalogger offline' and (ult_ok.em is null or l.lida_em > ult_ok.em)
  ), q14 as (      -- quedas (começos de sequência offline) nos últimos 14 dias
    select count(*) as n from (
      select lida_em, status = 'datalogger offline' as off,
             lag(status = 'datalogger offline') over (order by lida_em) as off_ant
        from l where lida_em > now() - interval '14 days') z
     where off and coalesce(off_ant, false) = false
       -- a que começa num dia em que o cliente desliga a usina de propósito não
       -- é internet instável (14/11, Rua São Bernardo do GILBERTO)
       and not coalesce(extract(dow from z.lida_em at time zone 'America/Sao_Paulo')::int
                        = any ((select desliga_dias_semana from usinas where id = p_usina)::int[]), false)
  )
  select jsonb_build_object(
    'ultima_leitura', (select lida_em from ult),
    'status', (select status from ult),
    'sem_comunicar', coalesce((select status from ult) = 'datalogger offline', false),
    'desde', case when (select status from ult) = 'datalogger offline' then (select em from ini) end,
    'horas', case when (select status from ult) = 'datalogger offline'
                  then round(extract(epoch from now() - (select em from ini)) / 3600)::int end,
    'quedas_14d', (select n from q14));
$function$;
