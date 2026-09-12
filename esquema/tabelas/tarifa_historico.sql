create sequence if not exists public.tarifa_historico_id_seq;

create table if not exists public.tarifa_historico (
  id bigint default nextval('tarifa_historico_id_seq'::regclass) not null,
  valor numeric not null,
  vigente_desde date default CURRENT_DATE not null,
  origem text,
  observacao text,
  criado_em timestamp with time zone default now(),
  constraint tarifa_historico_pkey PRIMARY KEY (id)
);

alter sequence public.tarifa_historico_id_seq owned by public.tarifa_historico.id;

alter table public.tarifa_historico enable row level security;

create policy th_auth on public.tarifa_historico for all to public
  using (is_autorizado())
  with check (is_autorizado());
