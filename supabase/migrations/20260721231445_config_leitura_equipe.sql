drop policy if exists config_leitura_equipe on public.config;
create policy config_leitura_equipe on public.config
  for select to authenticated using (public.is_autorizado());
