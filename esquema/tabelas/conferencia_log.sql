create sequence if not exists public.conferencia_log_id_seq;

create table if not exists public.conferencia_log (
  id bigint default nextval('conferencia_log_id_seq'::regclass) not null,
  achados integer default 0 not null,
  detalhe jsonb,
  criado_em timestamp with time zone default now(),
  constraint conferencia_log_pkey PRIMARY KEY (id)
);

alter sequence public.conferencia_log_id_seq owned by public.conferencia_log.id;

create index if not exists idx_conf_data ON public.conferencia_log USING btree (criado_em DESC);

alter table public.conferencia_log enable row level security;

create policy conf_auth on public.conferencia_log for all to public
  using (is_autorizado())
  with check (is_autorizado());
