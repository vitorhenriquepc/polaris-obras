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
    -- a causa desta queda (nula se a anotação é de uma queda que já acabou)
    'causa', case when cv.vigente then u.causa end,
    'nota', case when cv.vigente or u.causa is null then u.causa_nota end,
    'em', case when cv.vigente then u.causa_em end,
    'por', case when cv.vigente then u.causa_por end,
    'avisado_em', case when cv.avisado_vigente then u.cliente_avisado_em end,
    -- a anotação de uma queda que acabou: fica à vista, não vale mais (14/11)
    'anterior', case when u.causa is not null and not cv.vigente then json_build_object(
        'causa', u.causa, 'nota', u.causa_nota, 'em', u.causa_em, 'por', u.causa_por,
        'avisado_em', u.cliente_avisado_em,
        'resolvida_em', cv.resolvida_em, 'como', cv.resolvida_como) end,
    'historico', (select coalesce(json_agg(json_build_object(
        'causa', h.causa, 'nota', h.nota, 'em', h.anotada_em, 'por', h.anotada_por,
        'avisado_em', h.avisado_em, 'resolvida_em', h.resolvida_em, 'como', h.resolvida_como,
        'trocada_em', h.trocada_em) order by h.anotada_em desc nulls last), '[]'::json)
        from (select * from usina_causa_hist x where x.usina_id = u.id
               order by x.anotada_em desc nulls last limit 5) h),
    -- a pista tirada da conversa do grupo só faz sentido com a usina com problema:
    -- sem isso, uma usina gerando normalmente ganharia "parece aguardando a
    -- concessionária" por um link da CPFL que o cliente mandou (MARASCA, 14/11)
    'sugestao', case when e.estado in ('normal', 'recém-ligada') then null else
                (select json_build_object('causa', p.causa, 'trecho', p.trecho,
                        'quando', p.quando, 'de_quem', p.de_quem)
                 from obra_usina ou join obras o on o.id=ou.obra_id,
                      lateral pista_de_causa(o.id, 45) p
                 where ou.usina_id=u.id and ou.saiu_em is null and p.causa is not null
                 order by p.quando desc limit 1) end
  ) into v
  from usinas u cross join lateral usina_causa_vigente(u.id) cv
       cross join lateral usina_estado(u.id) e
  where u.id=p_usina;
  return v;
end $function$
