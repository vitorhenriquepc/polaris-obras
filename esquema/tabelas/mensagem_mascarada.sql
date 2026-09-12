create table if not exists public.mensagem_mascarada (
  id bigint not null,
  obra_id uuid,
  mascarada_em timestamp with time zone default now(),
  motivo text,
  tamanho_original integer,
  constraint mensagem_mascarada_pkey PRIMARY KEY (id)
);

alter table public.mensagem_mascarada enable row level security;

create policy mm_admin on public.mensagem_mascarada for all to public
  using (is_admin())
  with check (is_admin());
