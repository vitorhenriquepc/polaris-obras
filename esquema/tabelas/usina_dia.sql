create table if not exists public.usina_dia (
  usina_id uuid not null,
  dia date not null,
  kwh numeric,
  kwh_kwp numeric,
  origem text default 'solarview'::text,
  lido_em timestamp with time zone default now(),
  constraint usina_dia_pkey PRIMARY KEY (usina_id, dia),
  constraint usina_dia_usina_id_fkey FOREIGN KEY (usina_id) REFERENCES usinas(id) ON DELETE CASCADE
);

create index if not exists idx_udia_dia ON public.usina_dia USING btree (dia DESC);

alter table public.usina_dia enable row level security;

create policy usina_dia_auth on public.usina_dia for all to public
  using (is_autorizado())
  with check (is_autorizado());
