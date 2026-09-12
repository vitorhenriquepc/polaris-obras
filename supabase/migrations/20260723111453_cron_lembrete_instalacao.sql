select cron.unschedule(jobid) from cron.job where jobname = 'lembrete-instalacao-d1';
select cron.schedule(
  'lembrete-instalacao-d1',
  '0 19 * * *',   -- 16h de Brasília (véspera)
  $$
  select net.http_post(
    url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/lembrete-instalacao',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('token', (select valor from public.config where chave = 'cron_token'))
  );
  $$
);
