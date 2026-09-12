create table if not exists public.usina_geracao (
  usina_id uuid not null,
  referencia date not null,
  kwh numeric,
  origem text default 'solarview'::text,
  lido_em timestamp with time zone default now(),
  constraint usina_geracao_pkey PRIMARY KEY (usina_id, referencia),
  constraint usina_geracao_usina_id_fkey FOREIGN KEY (usina_id) REFERENCES usinas(id) ON DELETE CASCADE
);

alter table public.usina_geracao enable row level security;

create policy usina_geracao_auth on public.usina_geracao for all to public
  using (is_autorizado())
  with check (is_autorizado());
