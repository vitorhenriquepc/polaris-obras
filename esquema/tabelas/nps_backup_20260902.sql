create table if not exists public.nps_backup_20260902 (
  id bigint,
  obra_id uuid,
  nota smallint,
  comentario text,
  criado_em timestamp with time zone,
  brinde text,
  voucher text,
  brinde_em timestamp with time zone,
  entregue_em timestamp with time zone,
  avaliou_google_em timestamp with time zone,
  avaliou_origem text,
  lembrete_google_em timestamp with time zone,
  lembretes_google smallint,
  origem text
);

alter table public.nps_backup_20260902 enable row level security;

create policy nps_backup_auth on public.nps_backup_20260902 for all to public
  using (is_admin())
  with check (is_admin());
