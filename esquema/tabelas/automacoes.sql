create table if not exists public.automacoes (
  chave text not null,
  nome text not null,
  descricao text,
  grupo text default 'geral'::text not null,
  ordem integer default 100,
  visivel boolean default true,
  constraint automacoes_pkey PRIMARY KEY (chave)
);

alter table public.automacoes enable row level security;

create policy auto_auth on public.automacoes for all to public
  using (is_autorizado())
  with check (is_autorizado());
