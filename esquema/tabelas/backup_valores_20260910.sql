create table if not exists public.backup_valores_20260910 (
  obra_id uuid,
  contrato text,
  cliente text,
  valor_projeto numeric(14,2),
  preco_negociado numeric(14,2)
);

alter table public.backup_valores_20260910 enable row level security;

create policy bkv_admin on public.backup_valores_20260910 for all to public
  using (is_admin())
  with check (is_admin());
