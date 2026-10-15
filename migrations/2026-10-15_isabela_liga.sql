-- ⚠️ AINDA NÃO APLICADA (15/10, 09:45). Fica no repositório para a conferência
-- das 17h25 aplicar se a Z-API já estiver gravando as enviadas; quando for
-- aplicada, este aviso sai e entra a hora em que foi.
--
-- Liga a escada de atendimento da Isabela (Vitor, 15/10: "pode fazer todos").
--
-- Pré-requisito: "Notificar as enviadas por mim também" ligado na Z-API
-- (instância POS-VENDA), para o que sai pelo número da Isabela — automático
-- ou digitado — entrar em mensagens_recebidas. Conferido antes de aplicar
-- isto: linhas novas com remetente 'Sistema/Polaris' depois do horário da troca.
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
