create table if not exists public.obra_relatorios (
  id uuid default gen_random_uuid() not null,
  obra_id uuid not null,
  titulo text not null,
  origem text default 'sistema'::text not null,
  url text,
  data_referencia date,
  criado_em timestamp with time zone default now(),
  criado_por text,
  arquivo_path text,
  tamanho_bytes bigint,
  constraint obra_relatorios_pkey PRIMARY KEY (id),
  constraint origem_valida CHECK ((origem = ANY (ARRAY['sistema'::text, 'auvo'::text, 'externo'::text, 'arquivo'::text]))),
  constraint obra_relatorios_obra_id_fkey FOREIGN KEY (obra_id) REFERENCES obras(id) ON DELETE CASCADE
);

create index if not exists idx_rel_obra ON public.obra_relatorios USING btree (obra_id);

alter table public.obra_relatorios enable row level security;

create policy obra_relatorios_auth on public.obra_relatorios for all to public
  using (is_autorizado())
  with check (is_autorizado());
create policy obra_relatorios_del on public.obra_relatorios for delete to public
  using (is_admin());
