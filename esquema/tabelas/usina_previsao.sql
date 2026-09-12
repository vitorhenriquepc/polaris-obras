create table if not exists public.usina_previsao (
  usina_id uuid not null,
  mes smallint not null,
  kwh_previsto numeric not null,
  fonte text default 'proposta'::text not null,
  atualizado_em timestamp with time zone default now(),
  atualizado_por text,
  constraint usina_previsao_pkey PRIMARY KEY (usina_id, mes),
  constraint usina_previsao_fonte_check CHECK ((fonte = ANY (ARRAY['proposta'::text, 'estimado'::text]))),
  constraint usina_previsao_kwh_previsto_check CHECK ((kwh_previsto >= (0)::numeric)),
  constraint usina_previsao_mes_check CHECK (((mes >= 1) AND (mes <= 12))),
  constraint usina_previsao_usina_id_fkey FOREIGN KEY (usina_id) REFERENCES usinas(id) ON DELETE CASCADE
);

alter table public.usina_previsao enable row level security;

create policy usina_previsao_auth on public.usina_previsao for all to public
  using (is_autorizado())
  with check (is_autorizado());
