create table if not exists public.clientes (
  id uuid default gen_random_uuid() not null,
  nome text not null,
  documento text,
  telefone text,
  cidade text,
  nascimento_dia smallint,
  nascimento_mes smallint,
  observacoes text,
  criado_em timestamp with time zone default now(),
  atualizado_em timestamp with time zone default now(),
  chamar_de text,
  constraint clientes_pkey PRIMARY KEY (id)
);

alter table public.clientes enable row level security;

create policy clientes_auth_ins on public.clientes for insert to public
  with check (is_autorizado());
create policy clientes_auth_sel on public.clientes for select to public
  using (is_autorizado());
create policy clientes_auth_upd on public.clientes for update to public
  using (is_autorizado())
  with check (is_autorizado());
create policy clientes_del on public.clientes for delete to public
  using (is_admin());
