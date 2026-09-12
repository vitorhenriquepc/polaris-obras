create sequence if not exists public.usina_marco_id_seq;

create table if not exists public.usina_marco (
  id bigint default nextval('usina_marco_id_seq'::regclass) not null,
  usina_id uuid not null,
  marco integer not null,
  pct_no_momento numeric,
  economizado numeric,
  atingido_em date default CURRENT_DATE not null,
  avisado_em timestamp with time zone,
  constraint usina_marco_pkey PRIMARY KEY (id),
  constraint usina_marco_usina_id_marco_key UNIQUE (usina_id, marco),
  constraint usina_marco_usina_id_fkey FOREIGN KEY (usina_id) REFERENCES usinas(id) ON DELETE CASCADE
);

alter sequence public.usina_marco_id_seq owned by public.usina_marco.id;

alter table public.usina_marco enable row level security;

create policy marco_auth on public.usina_marco for all to public
  using (is_autorizado())
  with check (is_autorizado());
