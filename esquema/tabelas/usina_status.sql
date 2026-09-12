create table if not exists public.usina_status (
  obra_id uuid not null,
  status text,
  status_anterior text,
  ultima_leitura timestamp with time zone,
  mudou_em timestamp with time zone,
  alertado_em timestamp with time zone,
  geracao_instantanea numeric,
  acumulado_kwh numeric,
  constraint usina_status_pkey PRIMARY KEY (obra_id),
  constraint usina_status_obra_id_fkey FOREIGN KEY (obra_id) REFERENCES obras(id) ON DELETE CASCADE
);

alter table public.usina_status enable row level security;
