-- Autoleitura ligada. Horarios decididos pelo Vitor em 15/09/2026:
--
--    9h  o aviso "no dia"   -- quem le o relogio faz de manha; 17h e tarde
--   18h  a vespera          -- depois da regua das 17h, entao nao disputa
--
-- Em UTC, que e como o cron guarda: 12:00 e 21:00. O `regua-disparo` roda
-- '0 20 * * 1-5' e sai as 17h de Brasilia -- foi dali que confirmei o UTC-3.
--
-- Seg a sex nos dois. Nao e restricao de verdade, e cinto e suspensorio: a
-- fila ja nunca traz ninguem no fim de semana, porque dia_util_ate() antecipa
-- a vespera para a sexta e o aviso "no dia" so existe em dia util.

-- 1. A fila que o service role consegue ler.
--    autoleitura_fila() guarda com is_autorizado(), que le o email do JWT --
--    o service role nao tem email. Mesmo motivo dos get_*_svc que ja existiam.
--    Respeita optout_em: quem pediu para nao receber nao recebe nem isto.
--    (definicao em 2026-09-15_autoleitura_fila_svc, aplicada antes desta)

-- 2. A edge function `autoleitura-aviso`, verify_jwt = FALSE, autorizada pelo
--    cron_token no corpo -- mesmo desenho do regua-disparo. Aceita
--    {"tipo":"vespera"|"dia"} e {"simular":true}, que lista sem enviar.
--    So marca como avisado DEPOIS que a Z-API aceita o envio, e manda o
--    resumo para quem e resp_posvenda, com as falhas separadas.

select cron.schedule('autoleitura-vespera', '0 21 * * 1-5', $c$
  select net.http_post(
    url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/autoleitura-aviso',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('token',(select valor from public.config where chave='cron_token'),
                               'tipo','vespera'),
    timeout_milliseconds := 120000);
$c$);

select cron.schedule('autoleitura-dia', '0 12 * * 1-5', $c$
  select net.http_post(
    url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/autoleitura-aviso',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('token',(select valor from public.config where chave='cron_token'),
                               'tipo','dia'),
    timeout_milliseconds := 120000);
$c$);

update config set valor = '1' where chave = 'autoleitura_ativo';

-- PARA DESLIGAR, sem mexer em cron nem em codigo:
--   update config set valor = '0' where chave = 'autoleitura_ativo';
-- A edge function le essa chave em toda rodada e volta na hora.

-- ---------------------------------------------------------------------------
-- CORRECAO no mesmo dia: aviso adiantado nao cancela o automatico.
--
-- Achado confirmando outra coisa. Clicar em "Enviar no grupo" dez dias antes
-- marcava a vespera como avisada, e o cron das 18h na data certa pulava esse
-- cliente. O aviso adiantado CANCELAVA o aviso na hora certa -- o contrario
-- do que se espera de um "forcar envio".
--
-- Agora autoleitura_marcar() so marca a partir do dia devido. Adiantado,
-- a mensagem sai e o automatico continua programado; a tela mostra
-- "O aviso automatico continua programado para DD/MM".
-- ---------------------------------------------------------------------------
