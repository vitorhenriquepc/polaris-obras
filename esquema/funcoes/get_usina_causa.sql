CREATE OR REPLACE FUNCTION public.get_usina_causa(p_usina uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v json;
begin
  if not is_autorizado() then return null; end if;
  select json_build_object(
    'causa', u.causa, 'nota', u.causa_nota,
    'em', u.causa_em, 'por', u.causa_por,
    'avisado_em', u.cliente_avisado_em,
    'sugestao', (select json_build_object('causa', p.causa, 'trecho', p.trecho,
                        'quando', p.quando, 'de_quem', p.de_quem)
                 from obra_usina ou join obras o on o.id=ou.obra_id,
                      lateral pista_de_causa(o.id, 45) p
                 where ou.usina_id=u.id and ou.saiu_em is null and p.causa is not null
                 order by p.quando desc limit 1)
  ) into v from usinas u where u.id=p_usina;
  return v;
end $function$
