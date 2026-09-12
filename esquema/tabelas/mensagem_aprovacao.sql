create table if not exists public.mensagem_aprovacao (
  id uuid default gen_random_uuid() not null,
  obra_id uuid,
  usina_id uuid,
  tipo text not null,
  destino text,
  texto text not null,
  motivo text,
  criada_em timestamp with time zone default now(),
  situacao text default 'aguardando'::text not null,
  decidida_em timestamp with time zone,
  decidida_por text,
  enviada_em timestamp with time zone,
  erro text,
  constraint mensagem_aprovacao_pkey PRIMARY KEY (id),
  constraint mensagem_aprovacao_situacao_check CHECK ((situacao = ANY (ARRAY['aguardando'::text, 'aprovada'::text, 'recusada'::text, 'enviada'::text, 'expirada'::text]))),
  constraint mensagem_aprovacao_obra_id_fkey FOREIGN KEY (obra_id) REFERENCES obras(id) ON DELETE CASCADE,
  constraint mensagem_aprovacao_usina_id_fkey FOREIGN KEY (usina_id) REFERENCES usinas(id) ON DELETE SET NULL
);

create index if not exists idx_aprov_situacao ON public.mensagem_aprovacao USING btree (situacao, criada_em DESC);

alter table public.mensagem_aprovacao enable row level security;

create policy mensagem_aprovacao_auth on public.mensagem_aprovacao for all to public
  using (is_autorizado())
  with check (is_autorizado());
