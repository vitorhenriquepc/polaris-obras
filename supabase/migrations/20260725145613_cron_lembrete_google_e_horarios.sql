-- Lembrete às 18h30 de Brasília (21:30 UTC) — fim de tarde, cliente mais disponível
select cron.unschedule(jobid) from cron.job where jobname = 'lembrete-google-diario';
select cron.schedule(
  'lembrete-google-diario',
  '30 21 * * 1-5',   -- seg a sex
  $$
  select net.http_post(
    url := 'https://dakubhcgohiwzyqiegqf.supabase.co/functions/v1/lembrete-google',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('token', (select valor from public.config where chave = 'cron_token'))
  );
  $$
);

-- Análise: em que horário os clientes respondem
create or replace function public.get_horarios_resposta()
returns json language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then return null; end if;
  return json_build_object(
    'por_hora', (select coalesce(json_agg(t order by t.hora), '[]'::json) from (
      select extract(hour from n.criado_em at time zone 'America/Sao_Paulo')::int as hora,
             count(*) as respostas
      from nps n group by 1) t),
    'por_dia_semana', (select coalesce(json_agg(t order by t.dia), '[]'::json) from (
      select extract(dow from n.criado_em at time zone 'America/Sao_Paulo')::int as dia,
             count(*) as respostas
      from nps n group by 1) t),
    'tempo_resposta_horas', (select round(avg(extract(epoch from (n.criado_em - o.nps_enviado_em))/3600)::numeric, 1)
      from nps n join obras o on o.id = n.obra_id where o.nps_enviado_em is not null),
    'google', (select json_build_object(
      'promotores', count(*) filter (where nota >= 9),
      'avaliaram', count(*) filter (where avaliou_google_em is not null),
      'pendentes', count(*) filter (where nota >= 9 and avaliou_google_em is null),
      'lembretes_enviados', coalesce(sum(lembretes_google), 0)
    ) from nps)
  );
end; $$;
grant execute on function public.get_horarios_resposta() to authenticated;
