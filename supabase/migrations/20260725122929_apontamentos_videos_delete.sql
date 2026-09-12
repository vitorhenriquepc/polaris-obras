-- ===== 1. APONTAMENTOS TÉCNICOS (condições pré-existentes) =====
create table if not exists public.apontamentos (
  id bigserial primary key,
  obra_id uuid not null references public.obras(id) on delete cascade,
  descricao text not null,
  criado_em timestamptz not null default now()
);
alter table public.apontamentos enable row level security;
drop policy if exists apont_leitura_equipe on public.apontamentos;
create policy apont_leitura_equipe on public.apontamentos for select to authenticated using (public.is_autorizado());

-- ===== 2. MÍDIA: vídeos e vínculo com apontamentos =====
alter table public.fotos
  add column if not exists tipo text not null default 'foto',
  add column if not exists apontamento_id bigint references public.apontamentos(id) on delete cascade;

-- ===== 3. EXCLUSÃO EM CASCATA =====
alter table public.fotos drop constraint if exists fotos_obra_id_fkey;
alter table public.fotos add constraint fotos_obra_id_fkey
  foreign key (obra_id) references public.obras(id) on delete cascade;

alter table public.etapas_historico drop constraint if exists etapas_historico_obra_id_fkey;
alter table public.etapas_historico add constraint etapas_historico_obra_id_fkey
  foreign key (obra_id) references public.obras(id) on delete cascade;

-- Somente admin pode excluir obras
drop policy if exists obras_delete_admin on public.obras;
create policy obras_delete_admin on public.obras for delete to authenticated using (public.is_admin());
