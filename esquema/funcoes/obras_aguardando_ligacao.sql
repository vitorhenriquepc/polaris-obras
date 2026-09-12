CREATE OR REPLACE FUNCTION public.obras_aguardando_ligacao()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select coalesce(json_agg(x order by (x->>'dias')::int desc),'[]'::json) into v from (
    select json_build_object(
      'obra_id', o.id, 'contrato', o.contrato, 'cliente', o.cliente,
      'cidade', o.cidade, 'kwp', o.potencia_kwp,
      'concessionaria', coalesce(o.concessionaria,'—'),
      'dias', (current_date - o.atualizado_em::date),
      'tem_usina', exists(select 1 from obra_usina x where x.obra_id=o.id),
      -- ja esta gerando? entao a ligacao saiu e a etapa ficou para tras
      'ja_gerando', exists(
         select 1 from obra_usina ou join usina_dia d on d.usina_id=ou.usina_id
         where ou.obra_id=o.id and d.kwh > 0.5 and d.dia >= current_date - 7),
      'travada', (o.trava is not null)
    ) as x
    from obras o
    where o.status <> 'Cancelado' and o.etapa_numero = 7
  ) t;
  return v;
end $function$
