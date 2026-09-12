create table if not exists public.usina_monitoramento (
  id uuid default gen_random_uuid() not null,
  usina_id uuid not null,
  plataforma text not null,
  id_externo text not null,
  ativo boolean default true,
  ultimo_sync timestamp with time zone,
  criado_em timestamp with time zone default now(),
  constraint usina_monitoramento_pkey PRIMARY KEY (id),
  constraint usina_monitoramento_plataforma_id_externo_key UNIQUE (plataforma, id_externo),
  constraint usina_monitoramento_usina_id_fkey FOREIGN KEY (usina_id) REFERENCES usinas(id) ON DELETE CASCADE
);

create index if not exists idx_mon_usina ON public.usina_monitoramento USING btree (usina_id);

alter table public.usina_monitoramento enable row level security;

create policy usina_monitoramento_auth on public.usina_monitoramento for all to public
  using (is_autorizado())
  with check (is_autorizado());
create policy usina_monitoramento_del on public.usina_monitoramento for delete to public
  using (is_admin());
