-- Lista de obras que devem gerar alerta (30+ dias, sem alerta nos últimos 7)
create or replace function public.obras_para_alerta(p_dias int default 30)
returns table (id uuid, cliente text, contrato text, etapa_numero smallint, dias int)
language sql
security definer
set search_path to 'public'
as $$
  select o.id, o.cliente, o.contrato, o.etapa_numero,
         (current_date - o.data_fechamento)::int as dias
  from obras o
  where o.etapa_numero < 8
    and o.data_fechamento is not null
    and current_date - o.data_fechamento >= p_dias
    and (o.ultimo_alerta_prazo is null or o.ultimo_alerta_prazo <= current_date - 7)
  order by dias desc;
$$;
revoke execute on function public.obras_para_alerta(int) from public, anon, authenticated;
