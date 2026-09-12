CREATE OR REPLACE FUNCTION public.zz_brindes()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_autorizado() then return null; end if;
  return (
    select coalesce(json_agg(t order by t.entregue_em nulls first, t.brinde_em desc), '[]'::json)
    from (
      select o.cliente, o.contrato, o.telefone, o.slug,
             n.brinde, n.voucher, n.nota, n.brinde_em, n.entregue_em,
             n.avaliou_google_em, n.avaliou_origem, n.lembretes_google
      from nps n join obras o on o.id = n.obra_id
      where n.voucher is not null
      order by n.brinde_em desc limit 100
    ) t
  );
end; $function$
