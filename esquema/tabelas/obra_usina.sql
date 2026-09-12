create table if not exists public.obra_usina (
  id uuid default gen_random_uuid() not null,
  obra_id uuid not null,
  usina_id uuid not null,
  papel text default 'propria'::text not null,
  medicao text default 'inversor_proprio'::text not null,
  kwp_parte numeric,
  entrou_em date,
  saiu_em date,
  principal boolean default false,
  criado_em timestamp with time zone default now(),
  constraint obra_usina_pkey PRIMARY KEY (id),
  constraint obra_usina_obra_id_usina_id_key UNIQUE (obra_id, usina_id),
  constraint compartilhado_exige_kwp CHECK (((medicao <> 'compartilhado'::text) OR (kwp_parte > (0)::numeric))),
  constraint herdada_sem_rateio CHECK (((papel <> 'herdada'::text) OR (medicao = 'inversor_proprio'::text))),
  constraint medicao_valida CHECK ((medicao = ANY (ARRAY['inversor_proprio'::text, 'compartilhado'::text]))),
  constraint papel_valido CHECK ((papel = ANY (ARRAY['propria'::text, 'expansao'::text, 'herdada'::text]))),
  constraint vigencia_coerente CHECK (((saiu_em IS NULL) OR (entrou_em IS NULL) OR (saiu_em >= entrou_em))),
  constraint obra_usina_obra_id_fkey FOREIGN KEY (obra_id) REFERENCES obras(id) ON DELETE CASCADE,
  constraint obra_usina_usina_id_fkey FOREIGN KEY (usina_id) REFERENCES usinas(id) ON DELETE CASCADE
);

create index if not exists idx_ou_obra ON public.obra_usina USING btree (obra_id);
create index if not exists idx_ou_usina ON public.obra_usina USING btree (usina_id);
CREATE UNIQUE INDEX uq_ou_principal ON public.obra_usina USING btree (obra_id) WHERE principal;

alter table public.obra_usina enable row level security;

create policy obra_usina_auth on public.obra_usina for all to public
  using (is_autorizado())
  with check (is_autorizado());
create policy obra_usina_del on public.obra_usina for delete to public
  using (is_admin());
