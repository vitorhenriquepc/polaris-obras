create table if not exists public.usinas (
  id uuid default gen_random_uuid() not null,
  cliente_id uuid,
  apelido text,
  potencia_kwp numeric,
  data_instalacao date,
  data_estimada boolean default false,
  cidade text,
  instalador_terceiro text,
  ativa boolean default true,
  desativada_em date,
  criado_em timestamp with time zone default now(),
  status_atual text,
  status_desde timestamp with time zone,
  alerta_parada_em timestamp with time zone,
  fator_local numeric,
  fator_origem text,
  fator_em timestamp with time zone,
  nota_geracao text,
  causa text,
  causa_nota text,
  causa_em timestamp with time zone,
  causa_por text,
  cliente_avisado_em timestamp with time zone,
  constraint usinas_pkey PRIMARY KEY (id),
  constraint causa_valida CHECK (((causa IS NULL) OR (causa = ANY (ARRAY['wifi'::text, 'sem_energia'::text, 'desligado_pelo_cliente'::text, 'obra_no_local'::text, 'aguardando_concessionaria'::text, 'defeito_inversor'::text, 'cadastro_errado'::text, 'outro'::text])))),
  constraint usinas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE SET NULL
);

create index if not exists idx_usinas_cliente ON public.usinas USING btree (cliente_id);

alter table public.usinas enable row level security;

create policy usinas_auth on public.usinas for all to public
  using (is_autorizado())
  with check (is_autorizado());
create policy usinas_del on public.usinas for delete to public
  using (is_admin());
