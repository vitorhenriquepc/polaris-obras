select cron.unschedule(jobid) from cron.job where jobname = 'nps-envio-diario';
select cron.schedule(
  'nps-envio-diario',
  '0 13 * * *',
  $$
  select net.http_post(
    url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/nps-envio',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('token', (select valor from public.config where chave = 'cron_token'))
  );
  $$
);
