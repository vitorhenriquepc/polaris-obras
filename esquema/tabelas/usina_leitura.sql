create sequence if not exists public.usina_leitura_id_seq;

create table if not exists public.usina_leitura (
  id bigint default nextval('usina_leitura_id_seq'::regclass) not null,
  usina_id uuid not null,
  lida_em timestamp with time zone default now() not null,
  plataforma text default 'solarview'::text not null,
  status_cod text,
  status text,
  geracao_dia_kwh numeric,
  acumulado_kwh numeric,
  constraint usina_leitura_pkey PRIMARY KEY (id),
  constraint usina_leitura_usina_id_fkey FOREIGN KEY (usina_id) REFERENCES usinas(id) ON DELETE CASCADE
);

alter sequence public.usina_leitura_id_seq owned by public.usina_leitura.id;

create index if not exists idx_leitura_usina_data ON public.usina_leitura USING btree (usina_id, lida_em DESC);

alter table public.usina_leitura enable row level security;

create policy usina_leitura_auth on public.usina_leitura for all to public
  using (is_autorizado())
  with check (is_autorizado());
