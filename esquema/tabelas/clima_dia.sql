create table if not exists public.clima_dia (
  dia date not null,
  chuva_mm numeric,
  sol_horas numeric,
  nuvens_pct numeric,
  lido_em timestamp with time zone default now(),
  constraint clima_dia_pkey PRIMARY KEY (dia)
);

alter table public.clima_dia enable row level security;

create policy clima_dia_auth on public.clima_dia for all to public
  using (is_autorizado())
  with check (is_autorizado());
