-- 14/11: o "voltou?" do usina-status, de hora em hora (ver o cabeçalho do
-- supabase/functions/usina-status/index.ts e 2026-11-14_usina_causa_por_queda.sql).
--
-- A leitura completa segue às 09h15, 13h15 e 16h15 (cron usina-status). Entre uma
-- e outra, e depois da última, este cron pergunta ao SolarView só se quem estava
-- com status ruim voltou a dizer "operando": às :45 de cada hora, das 08h45 às
-- 18h45 (11h45–21h45 UTC). Não grava queda nova nem manda alerta.
--
-- Criado só depois que o usina-status v5 (que entende o so_voltou) foi publicado
-- e conferido: o v4 ignoraria o so_voltou e faria uma leitura completa a cada
-- hora, com alerta. Desliga junto com a leitura completa (usina_status_ativo).

select cron.schedule('usina-status-volta', '45 11-21 * * *', $cmd$
  select case when (select valor from config where chave='usina_status_ativo')='1' then
    net.http_post(
      url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/usina-status',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('token',(select valor from config where chave='cron_token'), 'so_voltou', true),
      timeout_milliseconds := 180000) end;
$cmd$);
