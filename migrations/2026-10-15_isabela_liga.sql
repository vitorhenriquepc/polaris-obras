-- APLICADA em 15/10 às 17:17 (atendimento_desde = 2026-10-15T20:17:01Z).
--
-- Liga a escada de atendimento da Isabela (Vitor, 15/10: "pode fazer todos").
--
-- Pré-requisito: "Notificar as enviadas por mim também" ligado na Z-API
-- (instância POS-VENDA), para o que sai pelo número da Isabela — automático
-- ou digitado — entrar em mensagens_recebidas. Conferido às 17:16 de 15/10:
-- as 6 mensagens da régua das 17h entraram como 'automatica' /
-- 'Sistema/Polaris', 5 a 6 s depois de cada envio.
--
-- 1) cron a cada 15 min, todos os dias (o aviso de fim de semana precisa rodar
--    sábado e domingo; a função decide o resto pelo horário e pela config);
-- 2) atendimento_desde = agora — senão a fila antiga dispara de uma vez;
-- 3) atendimento_ativo = 1 e atendimento_fds_ativo = 1 (texto aprovado em 15/10);
-- 4) alerta_espera_ativo = 0 — o "cliente esperando" antigo (60 min, só para a
--    Lívia) passaria na frente do vendedor. O job alerta-espera continua
--    agendado e para de agir pela chave; para voltar, é só a chave em 1.
select cron.schedule('isabela-atendimento', '*/15 * * * *', $cron$
  select net.http_post(
    url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/isabela-atendimento',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('token',(select valor from public.config where chave='cron_token')),
    timeout_milliseconds := 120000);
$cron$);

do $x$ begin
  update config set valor = to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
   where chave = 'atendimento_desde';
  update config set valor = '1' where chave in ('atendimento_ativo', 'atendimento_fds_ativo');
  update config set valor = '0' where chave = 'alerta_espera_ativo';
end $x$;
